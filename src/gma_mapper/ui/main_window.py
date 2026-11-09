"""Main Application Window (`GMAMapperMainWindow`) and protocol message router."""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import sys
from typing import Any, Callable

from gma_mapper import GMAMapperVersion
from gma_mapper.core.cache import AssetCache
from gma_mapper.core.file_io import (
    load_from_file,
    save_to_file,
    load_dice_presets_from_file,
    save_dice_presets_to_file,
)
from gma_mapper.core.profile import (
    default_preferences,
    find_server_index,
    preferred_color,
    save as save_preferences,
)
from gma_mapper.net.client import GMANetworkClient
from gma_mapper.ui.audio import AudioManager
from gma_mapper.ui.canvas.drawing import (
    GRID_SNAP_CHOICES,
    LINE_WIDTH_CHOICES,
    STIPPLE_CHOICES,
)
from gma_mapper.ui.canvas.items import creature_image_candidates
from gma_mapper.ui.canvas.scene import CREATURE_GRID_SNAP_CHOICES, BattleMapScene
from gma_mapper.ui.canvas.view import BattleMapView
from gma_mapper.ui.dialogs.preferences import PreferencesDialog
from gma_mapper.ui.dialogs.update_check import UpdateCheckDialog
from gma_mapper.ui.panels.chat_dice import ChatDicePanel
from gma_mapper.ui.panels.clock import (
    GolarionCalendar,
    InitiativeClockPanel,
     strip_nameplate_prefix,
)
from gma_mapper.ui.panels.combat import (
    CombatantState,
    CombatPanel,
    apply_local_hp_adjustment,
    combatant_state_from_token_data,
)

try:
    from PySide6.QtCore import Qt, QTimer, Signal
    from PySide6.QtGui import QAction, QActionGroup, QColor, QKeySequence, QPixmap
    from PySide6.QtWidgets import (
        QApplication,
        QColorDialog,
        QMainWindow,
        QDockWidget,
        QFileDialog,
        QInputDialog,
        QLineEdit,
        QToolBar,
        QStatusBar,
    )
    from gma_mapper.ui.panels.clock import TimerRequestDialog
    from gma_mapper.ui.panels.combat import HPRequestDialog
    HAS_PYSIDE6 = True
except ImportError:
    HAS_PYSIDE6 = False


class MapperController:
    """Pure-Python controller routing GMA protocol commands between client, scene, and panels.

    Allows protocol dispatch to be tested headlessly even when ``PySide6`` is not installed.
    """

    def __init__(
        self,
        prefs: dict[str, Any] | None = None,
        cache: AssetCache | None = None,
        audio: AudioManager | None = None,
        query_image_cb: Callable[[str, float], None] | None = None,
        adjust_view_cb: Callable[[str, float, float], None] | None = None,
        async_fetch_image_cb: Callable[[str, float, str, str], None] | None = None,
        async_fetch_map_cb: Callable[[str, bool, bool, str], None] | None = None,
    ) -> None:
        if HAS_PYSIDE6 and QApplication.instance() is None:
            self._headless_app = QApplication([])
        self.prefs = prefs or default_preferences()
        self.cache = cache or AssetCache()
        self.audio = audio or AudioManager()
        self.query_image_cb = query_image_cb
        self.adjust_view_cb = adjust_view_cb
        self.async_fetch_image_cb = async_fetch_image_cb
        self.async_fetch_map_cb = async_fetch_map_cb
        self.calendar = GolarionCalendar()
        self.scene = BattleMapScene()
        self.clock_panel = InitiativeClockPanel(self.calendar)
        self.chat_panel = ChatDicePanel()
        self.combat_panel = CombatPanel()
        self.server_settings: dict[str, Any] = {}
        self.pc_templates: dict[str, dict[str, Any]] = {}
        self.my_names: list[str] = []
        self.polo_cb: Callable[[], None] | None = None
        self.combatant_moved_cb: Callable[[str], None] | None = None
        self.status_message_cb: Callable[[str], None] | None = None
        self.debug_level: int = 0
        self.debug_proto: bool = False
        self.apply_preferences(self.prefs)

    def log_debug(self, level: int, msg: str) -> None:
        """Emit diagnostic message if ``level <= self.debug_level``."""
        if level <= self.debug_level:
            print(f"[gma-mapper:debug:{level}] {msg}", flush=True)

    def apply_preferences(self, prefs: dict[str, Any] | None = None) -> None:
        """Apply appearance, grid guide-line, player, and diagnostic preferences."""
        if prefs is not None:
            self.prefs = prefs
        self.debug_level = max(0, min(6, int(self.prefs.get("debug_level", 0) or 0)))
        self.debug_proto = bool(self.prefs.get("debug_proto", False))
        dark = bool(self.prefs.get("dark", False))
        theme = "dark" if dark else "light"
        self.scene.dark_mode = dark
        self.scene.grid_color = preferred_color(self.prefs, "grid", theme) or self.scene.grid_color
        self.scene.grid_minor_color = preferred_color(self.prefs, "grid_minor", theme) or self.scene.grid_minor_color
        self.scene.grid_major_color = preferred_color(self.prefs, "grid_major", theme) or self.scene.grid_major_color

        guide_lines = self.prefs.get("guide_lines")
        if isinstance(guide_lines, dict):
            major = guide_lines.get("major") or {}
            minor = guide_lines.get("minor") or {}
            major_offsets = major.get("offsets") or {}
            minor_offsets = minor.get("offsets") or {}
            self.scene.major_interval = int(major.get("interval", 0) or 0)
            self.scene.major_offset = (
                int(major_offsets.get("x", 0) or 0),
                int(major_offsets.get("y", 0) or 0),
            )
            self.scene.minor_interval = int(minor.get("interval", 0) or 0)
            self.scene.minor_offset = (
                int(minor_offsets.get("x", 0) or 0),
                int(minor_offsets.get("y", 0) or 0),
            )
        if hasattr(self.scene, "update"):
            self.scene.update()

        self.cache.image_format = str(self.prefs.get("image_format", "png") or "png")
        self.cache.curl_insecure = bool(self.prefs.get("curl_insecure", False))
        self.audio.enabled = not bool(self.prefs.get("no_ondeck_audio", False))
        if hasattr(self.chat_panel, "preset_table"):
            self.chat_panel.preset_table.setEnabled(not bool(self.prefs.get("no_dice", False)))

    def current_url_base(self) -> str:
        url = ""
        if self.server_settings.get("ImageBaseURL"):
            url = str(self.server_settings["ImageBaseURL"])
        else:
            prof_name = self.prefs.get("current_profile") or self.prefs.get("current_server", "offline")
            idx = find_server_index(self.prefs, prof_name)
            profiles = self.prefs.get("profiles", [])
            if 0 <= idx < len(profiles):
                srv = profiles[idx]
                url = str(srv.get("curl_server") or srv.get("curl_url_base") or "")
                if not url and srv.get("host"):
                    url = f"https://{srv['host']}/images"
        if url and not url.startswith(("http://", "https://")):
            url = f"https://{url}"
        url = url.rstrip("/")
        if url:
            self.cache.curl_server = url
        return url

    def _ensure_pixmap_loaded(self, image_name: str, zoom: float = 1.0) -> None:
        if not image_name:
            return
        if hasattr(self.scene, "get_pixmap") and self.scene.get_pixmap(image_name) is not None:
            return
        if HAS_PYSIDE6 and hasattr(self.scene, "register_pixmap"):
            try:
                cfile = self.cache.cache_filename(image_name, zoom)
                if cfile.is_file():
                    pm = QPixmap(str(cfile))
                    if not pm.isNull():
                        self.scene.register_pixmap(image_name, pm)
                        return
            except Exception:
                pass
        if self.query_image_cb:
            self.query_image_cb(image_name, zoom)

    def _ensure_creature_images_loaded(self, creature_data: dict[str, Any], zoom: float = 1.0) -> None:
        candidates = creature_image_candidates(creature_data)
        if not candidates:
            return
        # First check if any candidate is already loaded or cached locally
        for cand in candidates:
            if hasattr(self.scene, "get_pixmap") and self.scene.get_pixmap(cand) is not None:
                return
            if HAS_PYSIDE6 and hasattr(self.scene, "register_pixmap"):
                try:
                    cfile = self.cache.cache_filename(cand, zoom)
                    if cfile.is_file():
                        pm = QPixmap(str(cfile))
                        if not pm.isNull():
                            self.scene.register_pixmap(cand, pm)
                            return
                except Exception:
                    pass
        # Otherwise query the primary prefixed candidate (e.g. '#Name') and fallback
        for cand in candidates[:2]:
            if self.query_image_cb:
                self.query_image_cb(cand, zoom)

    def apply_loaded_map_file(self, local_map: str | Path, merge: bool = False) -> None:
        """Load elements and creatures from a local/cached map file into the scene on the GUI thread."""
        elements, creatures, _meta = load_from_file(local_map)
        if not merge:
            self.scene.clear_all()
            self.combat_panel.clear_combatants()
        for el in elements:
            oid = str(el.get("ID", ""))
            gtype = str(el.get("GMAType", "LS-LINE"))
            if oid:
                self.scene.add_or_update_element(oid, gtype, el)
                if gtype in ("LS-TILE", "TILE"):
                    self._ensure_pixmap_loaded(str(el.get("Image", "")), 1.0)
        for cr in creatures:
            oid = str(cr.get("ID", cr.get("Name", "")))
            if oid:
                self.scene.add_or_update_token(oid, cr)
                self._ensure_creature_images_loaded(cr, 1.0)
                self.combat_panel.update_combatant(combatant_state_from_token_data(oid, cr))

    def unload_map_file(self, local_map: str | Path) -> list[str]:
        """Remove elements and creatures whose IDs appear in `local_map` (`unloadfile` in `bin/mapper_legacy.tcl`)."""
        elements, creatures, _meta = load_from_file(local_map)
        removed_ids: list[str] = []
        for el in elements:
            oid = str(el.get("ID", ""))
            if oid and oid in self.scene.elements:
                self.scene.remove_object(oid)
                removed_ids.append(oid)
        for cr in creatures:
            oid = str(cr.get("ID", cr.get("Name", "")))
            if oid and oid in self.scene.tokens:
                self.scene.remove_object(oid)
                self.combat_panel.remove_combatant(oid)
                removed_ids.append(oid)
        return removed_ids

    def _sync_token_to_combat_panel(self, obj_id: str) -> None:
        if obj_id in self.scene.tokens:
            td = self.scene.tokens[obj_id].data
            self.combat_panel.update_combatant(combatant_state_from_token_data(obj_id, td))

    def _update_ondeck_and_audio(self) -> None:
        prev = self.calendar.ondeck_status
        names = list(self.my_names)
        if not names:
            names = [str(d.get("Name", "")) for d in self.pc_templates.values() if d.get("Name")]
        self.clock_panel.my_names = names
        new_status = self.calendar.compute_ondeck_status(names)
        if new_status in (0, 1, 2) and new_status != prev:
            self.audio.play_ondeck(new_status)

    def dispatch_command(self, cmd: str, payload: dict[str, Any]) -> None:
        """Route a parsed server protocol command (`cmd`, `payload`) to the appropriate subsystem."""
        if cmd == "WORLD":
            cs = payload.get("ClientSettings")
            if isinstance(cs, dict):
                self.server_settings.update(cs)
        elif cmd == "MARCO":
            if self.polo_cb:
                self.polo_cb()
        elif cmd == "AKA":
            names = payload.get("Names") or []
            if isinstance(names, list) and names:
                self.my_names = [str(n) for n in names if n]
                self.clock_panel.my_names = list(self.my_names)
        elif cmd == "CONN":
            peers = payload.get("PeerList") or []
            if isinstance(peers, list):
                for peer in peers:
                    if isinstance(peer, dict) and peer.get("IsMe"):
                        aka = peer.get("AKA") or []
                        user = str(peer.get("User") or "")
                        self.my_names = [str(n) for n in aka if n] if aka else ([user] if user else [])
                        self.clock_panel.my_names = list(self.my_names)
        elif cmd in ("LS-ARC", "LS-CIRC", "LS-LINE", "LS-POLY", "LS-RECT", "LS-SAO", "LS-SAOE", "LS-TEXT", "LS-TILE"):
            obj_id = str(payload.get("ID", ""))
            if obj_id:
                self.scene.add_or_update_element(obj_id, cmd, payload)
                if cmd == "LS-TILE":
                    img_name = str(payload.get("Image", payload.get("File", "")))
                    self._ensure_pixmap_loaded(img_name, 1.0)
        elif cmd == "AC":
            obj_id = str(payload.get("ID", payload.get("Name", "")))
            if obj_id:
                self.pc_templates[obj_id] = dict(payload)
                if any(k in payload for k in ("GX", "GY", "Gx", "Gy")):
                    self.scene.add_or_update_token(obj_id, payload)
                self.combat_panel.update_combatant(combatant_state_from_token_data(obj_id, payload))
        elif cmd == "PS":
            obj_id = str(payload.get("ID", payload.get("Name", "")))
            if obj_id:
                self.scene.add_or_update_token(obj_id, payload)
                self._ensure_creature_images_loaded(payload, 1.0)
                self.combat_panel.update_combatant(combatant_state_from_token_data(obj_id, payload))
        elif cmd == "AI":
            name = str(payload.get("Name", ""))
            sizes = payload.get("Sizes", [])
            url_base = self.current_url_base()
            if name and sizes and url_base and HAS_PYSIDE6:
                for sz in sizes:
                    file_id = str(sz.get("File", ""))
                    zoom = float(sz.get("Zoom", 1.0) or 1.0)
                    if file_id and not sz.get("IsLocalFile"):
                        if self.async_fetch_image_cb:
                            self.async_fetch_image_cb(name, zoom, file_id, url_base)
                        else:
                            try:
                                local_img = self.cache.fetch_image(name, zoom, file_id)
                                if local_img and Path(local_img).is_file():
                                    pm = QPixmap(str(local_img))
                                    if not pm.isNull() and hasattr(self.scene, "register_pixmap"):
                                        self.scene.register_pixmap(name, pm)
                                        break
                            except Exception:
                                pass
        elif cmd == "L":
            file_id = str(payload.get("File", ""))
            merge = bool(payload.get("Merge", False))
            cache_only = bool(payload.get("CacheOnly", False))
            url_base = self.current_url_base()
            if file_id and url_base:
                if self.async_fetch_map_cb:
                    self.async_fetch_map_cb(file_id, merge, cache_only, url_base)
                else:
                    try:
                        local_map = self.cache.fetch_map_file(file_id)
                        if not cache_only and local_map and Path(local_map).is_file():
                            self.apply_loaded_map_file(local_map, merge)
                    except Exception:
                        pass
        elif cmd == "MV":
            obj_id = str(payload.get("ID", payload.get("ObjID", payload.get("Target", ""))))
            gx = float(payload.get("GX", payload.get("Gx", 0.0)))
            gy = float(payload.get("GY", payload.get("Gy", 0.0)))
            self.scene.move_object(obj_id, gx, gy)
            if self.combatant_moved_cb and obj_id:
                self.combatant_moved_cb(obj_id)
        elif cmd == "RM":
            obj_id = str(payload.get("ObjID", payload.get("ID", payload.get("Target", ""))))
            self.scene.remove_object(obj_id)
            self.combat_panel.remove_combatant(obj_id)
        elif cmd == "CLR":
            target = str(payload.get("ObjID", payload.get("ID", payload.get("Target", "*"))))
            if target in ("*", "ALL", ""):
                self.scene.clear_all()
                self.combat_panel.clear_combatants()
            elif target in ("M*", "P*"):
                self.scene.remove_object(target)
                for cid in list(self.combat_panel.combatants.keys()):
                    if cid not in self.scene.tokens:
                        self.combat_panel.remove_combatant(cid)
            else:
                self.scene.remove_object(target)
                self.combat_panel.remove_combatant(target)
        elif cmd == "AV":
            grid = str(payload.get("Grid", ""))
            xv = float(payload.get("XView", 0.0) or 0.0)
            yv = float(payload.get("YView", 0.0) or 0.0)
            if self.adjust_view_cb:
                self.adjust_view_cb(grid, xv, yv)
        elif cmd == "MARK":
            x = float(payload.get("X", 0.0) or 0.0)
            y = float(payload.get("Y", 0.0) or 0.0)
            if hasattr(self.scene, "flash_mark"):
                self.scene.flash_mark(x, y)
        elif cmd == "OA":
            obj_id = str(payload.get("ObjID", payload.get("ID", payload.get("Target", ""))))
            attrs = payload.get("NewAttrs", payload.get("Attributes", payload))
            if isinstance(attrs, dict):
                if hasattr(self.scene, "update_object_attributes"):
                    self.scene.update_object_attributes(obj_id, attrs)
                elif obj_id in self.scene.tokens:
                    self.scene.tokens[obj_id].data.update(attrs)
                if obj_id in self.scene.tokens:
                    td = self.scene.tokens[obj_id].data
                    if any(k in attrs for k in ("Gx", "Gy", "GX", "GY")) and self.combatant_moved_cb:
                        self.combatant_moved_cb(obj_id)
                    if "Skin" in attrs or "Killed" in attrs:
                        self._ensure_creature_images_loaded(td, 1.0)
                    self._sync_token_to_combat_panel(obj_id)
                if self.calendar.track_health_change(obj_id, attrs):
                    self.clock_panel.refresh()
        elif cmd == "OA+":
            obj_id = str(payload.get("ObjID", payload.get("ID", payload.get("Target", ""))))
            attr_name = payload.get("AttrName")
            values = payload.get("Values")
            if attr_name and isinstance(values, list) and hasattr(self.scene, "add_object_attribute_values"):
                self.scene.add_object_attribute_values(obj_id, str(attr_name), values)
            else:
                attrs = (
                    {str(attr_name): values}
                    if attr_name and isinstance(values, list)
                    else payload.get("Attributes", payload)
                )
                if obj_id in self.scene.tokens and isinstance(attrs, dict):
                    tok = self.scene.tokens[obj_id]
                    for k, v in attrs.items():
                        if isinstance(v, list):
                            cur = list(tok.data.get(k, []))
                            for item in v:
                                if item not in cur:
                                    cur.append(item)
                            tok.data[k] = cur
            self._sync_token_to_combat_panel(obj_id)
        elif cmd == "OA-":
            obj_id = str(payload.get("ObjID", payload.get("ID", payload.get("Target", ""))))
            attr_name = payload.get("AttrName")
            values = payload.get("Values")
            if attr_name and isinstance(values, list) and hasattr(self.scene, "remove_object_attribute_values"):
                self.scene.remove_object_attribute_values(obj_id, str(attr_name), values)
            else:
                attrs = (
                    {str(attr_name): values}
                    if attr_name and isinstance(values, list)
                    else payload.get("Attributes", payload)
                )
                if obj_id in self.scene.tokens and isinstance(attrs, dict):
                    tok = self.scene.tokens[obj_id]
                    for k, v in attrs.items():
                        if isinstance(v, list):
                            cur = [x for x in tok.data.get(k, []) if x not in v]
                            tok.data[k] = cur
            self._sync_token_to_combat_panel(obj_id)
        elif cmd == "CS":
            self.calendar.set_time(
                absolute=payload.get("Absolute"),
                relative=payload.get("Relative"),
                combat_mode=payload.get("CombatMode"),
                running=payload.get("Running"),
            )
            self.clock_panel.refresh()
        elif cmd == "CO":
            enabled = bool(payload.get("Enabled", payload.get("CombatMode", False)))
            self.calendar.set_time(combat_mode=enabled)
            if hasattr(self.scene, "set_combat_state"):
                self.scene.set_combat_state(enabled)
            self._update_ondeck_and_audio()
            self.clock_panel.refresh()
        elif cmd == "IL":
            slots = payload.get("InitiativeList", payload.get("Slots", payload.get("List", [])))
            if isinstance(slots, list):
                self.calendar.initiative_slots = slots
                self._update_ondeck_and_audio()
                self.clock_panel.refresh()
                if hasattr(self.scene, "refresh_targets"):
                    self.scene.refresh_targets()
        elif cmd in ("TURN", "I"):
            if "Slot" in payload or "Actor" in payload:
                self.calendar.current_slot = int(payload.get("Slot", payload.get("Actor", 0)) or 0)
            if "Turn" in payload or "Rounds" in payload:
                self.calendar.turn = int(payload.get("Turn", payload.get("Rounds", 0)) or 0)
            actor_id = str(payload.get("ActorID", ""))
            if actor_id:
                self.calendar.select_actor_slot(actor_id)
                if hasattr(self.scene, "set_combat_state"):
                    self.scene.set_combat_state(self.calendar.combat_mode, actor_id)
                resolved_ids = (
                    self.scene.resolve_actor_mob_ids(actor_id)
                    if hasattr(self.scene, "resolve_actor_mob_ids")
                    else ([actor_id] if actor_id in self.scene.tokens else [])
                )
                primary_id = resolved_ids[0] if resolved_ids else actor_id
                self.combat_panel.select_creature(primary_id)
                if self.combatant_moved_cb and primary_id:
                    self.combatant_moved_cb(primary_id)
            self._update_ondeck_and_audio()
            self.clock_panel.refresh()
            if payload.get("OnDeck") is not None:
                self.audio.play_ondeck(int(payload["OnDeck"]))
        elif cmd == "HPACK":
            if self.status_message_cb:
                self.status_message_cb("Hit point request accepted by GM.")
        elif cmd == "TMACK":
            if self.status_message_cb:
                self.status_message_cb("Timer request accepted by GM.")
        elif cmd == "FAILED":
            reason = str(payload.get("Reason", "Operation failed"))
            if self.status_message_cb:
                self.status_message_cb(f"Request failed: {reason}")
        elif cmd == "ROLL":
            self.chat_panel.append_roll(payload, self.prefs.get("styles"))
        elif cmd == "TO":
            self.chat_panel.append_chat(payload)
        elif cmd == "CC":
            keep = int(payload.get("Keep", 0) or 0)
            self.chat_panel.clear_messages(keep)
        elif cmd in ("DD", "DD=", "DD+"):
            presets = payload.get("Presets", payload.get("List", []))
            if isinstance(presets, list):
                if cmd == "DD=":
                    self.chat_panel.set_presets(presets)
                else:
                    self.chat_panel.set_presets(self.chat_panel.presets + presets)
        elif cmd == "PROGRESS":
            if payload.get("IsTimer"):
                self.clock_panel.update_timer(payload)
            else:
                title = str(payload.get("Title", "Working"))
                cur = int(payload.get("Value", payload.get("Current", 0)) or 0)
                mx = int(payload.get("MaxValue", payload.get("Max", payload.get("Maximum", 0))) or 0)
                self.combat_panel.set_progress(title, cur, mx)
        elif cmd == "AA":
            self.audio.register_audio_asset(payload)
        elif cmd == "SOUND":
            self.audio.handle_play_sound(payload)


if HAS_PYSIDE6:

    class GMAMapperMainWindow(QMainWindow):
        """Primary Qt6 Main Window for GMA Mapper (`QMainWindow` + `QDockWidget` panels)."""

        _image_downloaded = Signal(str, str)       # (name, local_file_path)
        _map_downloaded = Signal(str, bool)        # (local_file_path, merge)

        def __init__(
            self,
            prefs: dict[str, Any] | None = None,
            prefs_path: str | Path | None = None,
        ) -> None:
            super().__init__()
            self.prefs = prefs or default_preferences()
            self.prefs_path = Path(prefs_path) if prefs_path else None
            self.cache = AssetCache()
            self.audio = AudioManager()
            self._download_pool = ThreadPoolExecutor(max_workers=4)
            self._auth_prompt_pending = False
            self.net_client = GMANetworkClient(self)
            self.controller = MapperController(
                self.prefs,
                self.cache,
                self.audio,
                query_image_cb=lambda name, zoom: self.net_client.session.query_image(name, zoom),
                adjust_view_cb=lambda grid, xv, yv: self.map_view.adjust_view(grid, xv, yv),
                async_fetch_image_cb=self._submit_image_download,
                async_fetch_map_cb=self._submit_map_download,
            )
            self.controller.polo_cb = lambda: self.net_client.session.polo()
            self.controller.status_message_cb = lambda msg: self.statusBar().showMessage(msg)
            self._apply_debug_protocol()

            self.setWindowTitle(f"GMA Mapper {GMAMapperVersion}")
            self.resize(1280, 840)

            # Central Battle Map View
            self.map_view = BattleMapView(self.controller.scene, self)
            self.map_view.pc_templates_provider = lambda: self.controller.pc_templates
            self.controller.combatant_moved_cb = self.map_view.scroll_to_combatant
            self.setCentralWidget(self.map_view)

            self._create_docks()
            self._create_menus_and_toolbar()
            self._wire_signals()
            self.setStatusBar(QStatusBar(self))
            self.statusBar().showMessage("Ready")

        def _submit_image_download(self, name: str, zoom: float, file_id: str, url_base: str) -> None:
            def _worker() -> None:
                try:
                    self.cache.curl_server = url_base
                    local_img = self.cache.fetch_image(name, zoom, file_id)
                    if local_img and Path(local_img).is_file():
                        self._image_downloaded.emit(name, str(local_img))
                except Exception:
                    pass

            self._download_pool.submit(_worker)

        def _submit_map_download(self, file_id: str, merge: bool, cache_only: bool, url_base: str) -> None:
            def _worker() -> None:
                try:
                    self.cache.curl_server = url_base
                    local_map = self.cache.fetch_map_file(file_id)
                    if not cache_only and local_map and Path(local_map).is_file():
                        self._map_downloaded.emit(str(local_map), merge)
                except Exception:
                    pass

            self._download_pool.submit(_worker)

        def _on_image_downloaded(self, name: str, local_path: str) -> None:
            pm = QPixmap(local_path)
            if not pm.isNull() and hasattr(self.controller.scene, "register_pixmap"):
                self.controller.scene.register_pixmap(name, pm)

        def _on_map_downloaded(self, local_path: str, merge: bool) -> None:
            try:
                self.controller.apply_loaded_map_file(local_path, merge)
            except Exception as exc:
                self.statusBar().showMessage(f"Error loading map: {exc}")

        def _create_docks(self) -> None:
            self.clock_dock = QDockWidget("Initiative & Clock", self)
            self.clock_dock.setWidget(self.controller.clock_panel)
            self.addDockWidget(Qt.DockWidgetArea.RightDockWidgetArea, self.clock_dock)

            self.combat_dock = QDockWidget("Combat & Conditions", self)
            self.combat_dock.setWidget(self.controller.combat_panel)
            self.addDockWidget(Qt.DockWidgetArea.RightDockWidgetArea, self.combat_dock)

            self.chat_dock = QDockWidget("Chat & Dice Roller", self)
            self.chat_dock.setWidget(self.controller.chat_panel)
            self.addDockWidget(Qt.DockWidgetArea.BottomDockWidgetArea, self.chat_dock)

        def _create_menus_and_toolbar(self) -> None:
            menubar = self.menuBar()
            self._tool_actions: dict[str, QAction] = {}

            # 1. File Menu
            file_menu = menubar.addMenu("&File")
            act_open_map = QAction("&Load Map File...", self)
            act_open_map.setShortcut(QKeySequence("Ctrl+O"))
            act_open_map.triggered.connect(lambda _c=False: self._on_open_map(merge=False))
            file_menu.addAction(act_open_map)

            act_merge_map = QAction("&Merge Map File...", self)
            act_merge_map.setShortcut(QKeySequence("Alt+O"))
            act_merge_map.triggered.connect(lambda _c=False: self._on_open_map(merge=True))
            file_menu.addAction(act_merge_map)

            act_save_map = QAction("&Save Map File...", self)
            act_save_map.setShortcut(QKeySequence("Ctrl+S"))
            act_save_map.triggered.connect(self._on_save_map)
            file_menu.addAction(act_save_map)

            act_unload_map = QAction("&Remove Elements from File...", self)
            act_unload_map.setShortcut(QKeySequence("Ctrl+Alt+O"))
            act_unload_map.triggered.connect(self._on_unload_map)
            file_menu.addAction(act_unload_map)

            file_menu.addSeparator()
            act_open_dice = QAction("Load &Dice Presets...", self)
            act_open_dice.triggered.connect(self._on_open_dice)
            file_menu.addAction(act_open_dice)

            act_save_dice = QAction("Save Dice &Presets As...", self)
            act_save_dice.triggered.connect(self._on_save_dice)
            file_menu.addAction(act_save_dice)

            file_menu.addSeparator()
            act_quit = QAction("&Quit", self)
            act_quit.triggered.connect(self.close)
            file_menu.addAction(act_quit)

            # 2. Edit Menu (ported from bin/mapper_legacy.tcl lines 1209-1281)
            edit_menu = menubar.addMenu("&Edit")
            tool_group = QActionGroup(self)
            tool_group.setExclusive(True)

            def _add_tool_action(
                parent_menu: Any,
                label: str,
                mode: str,
                shortcut: str = "",
                status_tip: str = "",
            ) -> QAction:
                act = QAction(label, self)
                act.setCheckable(True)
                if mode == "pointer":
                    act.setChecked(True)
                if shortcut:
                    act.setShortcut(QKeySequence(shortcut))
                if status_tip:
                    act.setStatusTip(status_tip)
                act.triggered.connect(
                    lambda _checked=False, m=mode, tip=status_tip: (
                        self.map_view.set_tool_mode(m),
                        self.statusBar().showMessage(tip or f"Selected {m} tool"),
                    )
                )
                tool_group.addAction(act)
                parent_menu.addAction(act)
                self._tool_actions[mode] = act
                return act

            _add_tool_action(
                edit_menu, "Normal Play Mode", "pointer", "Alt+N", "Selected normal play mode"
            )
            edit_menu.addSeparator()

            for clr_label, clr_targets in [
                ("Clear All Map Elements", ["E*"]),
                ("Clear All Monsters", ["M*"]),
                ("Clear All Players", ["P*"]),
                ("Clear All Creatures", ["P*", "M*"]),
                ("Clear All Objects", ["*"]),
            ]:
                act_clr = QAction(clr_label, self)
                act_clr.triggered.connect(
                    lambda _c=False, tlist=clr_targets: self._clear_targets(tlist)
                )
                edit_menu.addAction(act_clr)

            edit_menu.addSeparator()
            _add_tool_action(
                edit_menu,
                "Draw Lines",
                "line",
                "Alt+L",
                "Selected line tool [Alt+1 arrows, Alt+3 dashes, Double/Right-click to finish]",
            )
            _add_tool_action(
                edit_menu,
                "Draw Rectangles",
                "rect",
                "Alt+R",
                "Selected rectangle tool [Alt+3 dashes]",
            )
            _add_tool_action(
                edit_menu,
                "Draw Polygons",
                "poly",
                "Alt+P",
                "Selected polygon tool [Alt+1 join, Alt+2 spline, Alt+3 dashes, Double/Right-click to finish]",
            )
            _add_tool_action(
                edit_menu,
                "Draw Circles/Ellipses",
                "circ",
                "Alt+E",
                "Selected ellipse tool [Alt+3 dashes]",
            )
            _add_tool_action(
                edit_menu,
                "Draw Arcs",
                "arc",
                "Alt+A",
                "Selected arc tool [Alt+1 mode, Alt+3 dashes]",
            )
            _add_tool_action(
                edit_menu,
                "Add Text...",
                "text",
                "Alt+T",
                "Selected text tool [Right-click to change text, Alt+1 font, Alt+2 anchor]",
            )
            _add_tool_action(
                edit_menu,
                "Remove Objects",
                "kill",
                "Alt+X",
                "Selected remove-object tool [Click element, or P/N to cycle and X to delete]",
            )
            _add_tool_action(
                edit_menu,
                "Move Objects",
                "move",
                "Alt+M",
                "Selected move-object tool [Drag element, Arrows/HJKL to nudge, U/D/F/B for Z-order]",
            )
            _add_tool_action(
                edit_menu,
                "Stamp Objects",
                "tile",
                "Alt+S",
                "Selected stamp tool [Right-click to choose tile image, Left-click to place]",
            )
            _add_tool_action(
                edit_menu,
                "Set Area of Effect Boundary",
                "aoebound",
                "Alt+B",
                "Selected area-of-effect boundary tool [Click vertices, Double/Right-click to finish]",
            )

            edit_menu.addSeparator()
            self.act_force_top = QAction("Force Drawn Elements to Top", self)
            self.act_force_top.setCheckable(True)
            self.act_force_top.setChecked(self.map_view.force_elements_to_top)
            self.act_force_top.triggered.connect(
                lambda checked: setattr(self.map_view, "force_elements_to_top", bool(checked))
            )
            edit_menu.addAction(self.act_force_top)

            edit_menu.addSeparator()
            self.act_fill_shapes = QAction("Fill Shapes", self)
            self.act_fill_shapes.setCheckable(True)
            self.act_fill_shapes.setChecked(self.map_view.fill_enabled)
            self.act_fill_shapes.triggered.connect(
                lambda checked: setattr(self.map_view, "fill_enabled", bool(checked))
            )
            edit_menu.addAction(self.act_fill_shapes)

            act_fill_col = QAction("Choose Fill Color...", self)
            act_fill_col.triggered.connect(self._on_choose_fill_color)
            edit_menu.addAction(act_fill_col)

            act_line_col = QAction("Choose Outline Color...", self)
            act_line_col.triggered.connect(self._on_choose_line_color)
            edit_menu.addAction(act_line_col)

            stipple_menu = edit_menu.addMenu("Select Fill Pattern")
            stipple_group = QActionGroup(self)
            stipple_group.setExclusive(True)
            for st_val, st_label in STIPPLE_CHOICES:
                act_st = QAction(st_label, self)
                act_st.setCheckable(True)
                if st_val == self.map_view.draw_stipple:
                    act_st.setChecked(True)
                act_st.triggered.connect(
                    lambda _c=False, v=st_val: setattr(self.map_view, "draw_stipple", v)
                )
                stipple_group.addAction(act_st)
                stipple_menu.addAction(act_st)

            edit_menu.addSeparator()
            snap_menu = edit_menu.addMenu("Set Grid Snap")
            snap_group = QActionGroup(self)
            snap_group.setExclusive(True)
            for sn_val, sn_label in GRID_SNAP_CHOICES:
                act_sn = QAction(sn_label, self)
                act_sn.setCheckable(True)
                if sn_val == self.map_view.obj_snap:
                    act_sn.setChecked(True)
                act_sn.triggered.connect(
                    lambda _c=False, v=sn_val: setattr(self.map_view, "obj_snap", v)
                )
                snap_group.addAction(act_sn)
                snap_menu.addAction(act_sn)

            width_menu = edit_menu.addMenu("Set Line Thickness")
            width_group = QActionGroup(self)
            width_group.setExclusive(True)
            for w_val, w_label in LINE_WIDTH_CHOICES:
                act_w = QAction(w_label, self)
                act_w.setCheckable(True)
                if w_val == self.map_view.draw_width:
                    act_w.setChecked(True)
                act_w.triggered.connect(
                    lambda _c=False, v=w_val: setattr(self.map_view, "draw_width", v)
                )
                width_group.addAction(act_w)
                width_menu.addAction(act_w)

            edit_menu.addSeparator()
            act_prefs = QAction("P&references...", self)
            act_prefs.triggered.connect(self._on_preferences)
            edit_menu.addAction(act_prefs)

            # 3. View Menu (ported from bin/mapper_legacy.tcl lines 1283-1326)
            view_menu = menubar.addMenu("&View")

            self.act_show_toolbar = QAction("Show &Toolbar", self)
            self.act_show_toolbar.setCheckable(True)
            self.act_show_toolbar.setChecked(True)
            view_menu.addAction(self.act_show_toolbar)

            self.act_show_grid = QAction("Show Map &Grid", self)
            self.act_show_grid.setCheckable(True)
            self.act_show_grid.setChecked(self.controller.scene.show_grid)
            self.act_show_grid.triggered.connect(self._on_toggle_grid)
            view_menu.addAction(self.act_show_grid)

            self.act_show_health = QAction("Show &Health Stats", self)
            self.act_show_health.setCheckable(True)
            self.act_show_health.setChecked(self.controller.scene.show_health_stats)
            self.act_show_health.triggered.connect(self._on_toggle_health_stats)
            view_menu.addAction(self.act_show_health)

            self.act_show_all_targets = QAction("Show All Combat &Targets", self)
            self.act_show_all_targets.setCheckable(True)
            self.act_show_all_targets.setChecked(self.controller.scene.show_all_targets)
            self.act_show_all_targets.triggered.connect(self._on_toggle_all_targets)
            view_menu.addAction(self.act_show_all_targets)

            timers_menu = view_menu.addMenu("Show &Timers")
            timers_group = QActionGroup(self)
            timers_group.setExclusive(True)
            for t_scope, t_label in (("none", "None"), ("mine", "Mine"), ("all", "All")):
                act_tm = QAction(t_label, self)
                act_tm.setCheckable(True)
                if t_scope == self.controller.clock_panel.timer_scope:
                    act_tm.setChecked(True)
                act_tm.triggered.connect(
                    lambda _c=False, sc=t_scope: self.controller.clock_panel.set_timer_scope(sc)
                )
                timers_group.addAction(act_tm)
                timers_menu.addAction(act_tm)

            view_menu.addSeparator()
            act_zin = QAction("Zoom &In", self)
            act_zin.setShortcut(QKeySequence("Ctrl++"))
            act_zin.triggered.connect(self.map_view.zoom_in)
            view_menu.addAction(act_zin)

            act_zout = QAction("Zoom &Out", self)
            act_zout.setShortcut(QKeySequence("Ctrl+-"))
            act_zout.triggered.connect(self.map_view.zoom_out)
            view_menu.addAction(act_zout)

            act_zreset = QAction("&Restore Zoom (100%)", self)
            act_zreset.setShortcut(QKeySequence("Ctrl+0"))
            act_zreset.triggered.connect(self.map_view.reset_zoom)
            view_menu.addAction(act_zreset)

            view_menu.addSeparator()
            act_scroll_vis = QAction("Scroll to &Visible Objects", self)
            act_scroll_vis.setShortcut(QKeySequence("Alt+V"))
            act_scroll_vis.triggered.connect(self.map_view.scroll_to_visible_objects)
            view_menu.addAction(act_scroll_vis)

            act_sync_views = QAction("Scroll &Others' Views to Match Mine", self)
            act_sync_views.triggered.connect(self.map_view.sync_others_views)
            view_menu.addAction(act_sync_views)

            self.act_follow_combatants = QAction("Scroll to &Follow Combatants", self)
            self.act_follow_combatants.setCheckable(True)
            self.act_follow_combatants.setChecked(self.map_view.combatant_scroll_enabled)
            self.act_follow_combatants.triggered.connect(
                lambda checked: setattr(self.map_view, "combatant_scroll_enabled", bool(checked))
            )
            view_menu.addAction(self.act_follow_combatants)

            act_goto = QAction("Go to Map &Location...", self)
            act_goto.setShortcut(QKeySequence("Ctrl+G"))
            act_goto.triggered.connect(self.map_view.go_to_grid_coords_dialog)
            view_menu.addAction(act_goto)

            view_menu.addSeparator()
            act_refresh = QAction("&Refresh Display", self)
            act_refresh.setShortcut(QKeySequence("Ctrl+R"))
            act_refresh.triggered.connect(self.map_view.refresh_display)
            view_menu.addAction(act_refresh)

            # 4. Play Menu (ported from bin/mapper_legacy.tcl lines 1352-1460)
            play_menu = menubar.addMenu("&Play")
            self.act_combat_mode = QAction("&Combat Mode", self)
            self.act_combat_mode.setCheckable(True)
            self.act_combat_mode.setChecked(self.controller.scene.combat_mode)
            self.act_combat_mode.triggered.connect(self._on_toggle_combat_mode)
            play_menu.addAction(self.act_combat_mode)

            _add_tool_action(
                play_menu,
                "&Indicate Area of Effect",
                "saoe",
                "Ctrl+A",
                "Selected area-of-effect tool [Alt+1 shape (radius/cone/ray), Alt+2 spread]",
            )
            _add_tool_action(
                play_menu,
                "&Measure Distance Along Line(s)",
                "ruler",
                "Ctrl+D",
                "Selected ruler tool",
            )

            csnap_menu = play_menu.addMenu("Creature Token &Grid Snap")
            csnap_group = QActionGroup(self)
            csnap_group.setExclusive(True)
            for cs_val, cs_label in CREATURE_GRID_SNAP_CHOICES:
                act_cs = QAction(cs_label, self)
                act_cs.setCheckable(True)
                if cs_val == self.controller.scene.creature_grid_snap:
                    act_cs.setChecked(True)
                act_cs.triggered.connect(
                    lambda _c=False, v=cs_val: setattr(self.controller.scene, "creature_grid_snap", v)
                )
                csnap_group.addAction(act_cs)
                csnap_menu.addAction(act_cs)

            play_menu.addSeparator()
            act_req_timer = QAction("Request a New &Timer...", self)
            act_req_timer.triggered.connect(self._on_open_timer_request_dialog)
            play_menu.addAction(act_req_timer)

            act_req_hp = QAction("Request &Hit Point Adjustment...", self)
            act_req_hp.triggered.connect(lambda: self._on_open_hp_request_dialog("", False))
            play_menu.addAction(act_req_hp)

            act_req_tmp = QAction("Request Te&mporary Hit Points...", self)
            act_req_tmp.triggered.connect(lambda: self._on_open_hp_request_dialog("", True))
            play_menu.addAction(act_req_tmp)

            play_menu.addSeparator()
            act_deselect_all = QAction("&Deselect All Creatures", self)
            act_deselect_all.setShortcut(QKeySequence("Ctrl+Shift+A"))
            act_deselect_all.triggered.connect(self.controller.scene.clear_mob_selection)
            play_menu.addAction(act_deselect_all)

            # 5. Tools Toolbar
            toolbar = QToolBar("Tools", self)
            self.tools_toolbar = toolbar
            self.act_show_toolbar.triggered.connect(toolbar.setVisible)
            self.addToolBar(Qt.ToolBarArea.TopToolBarArea, toolbar)

            _add_tool_action(toolbar, "Mark", "mark", "", "Selected mark/ping tool")
            for mode in ("pointer", "ruler", "saoe", "line", "rect", "poly", "circ", "arc", "text", "tile", "move", "kill"):
                if mode in self._tool_actions:
                    toolbar.addAction(self._tool_actions[mode])

            toolbar.addSeparator()
            toolbar.addAction(act_line_col)
            toolbar.addAction(act_fill_col)
            toolbar.addAction(self.act_fill_shapes)

            act_opt1 = QAction("Opt1 (Alt+1)", self)
            act_opt1.setToolTip("Cycle Arrow / Join / Arc Mode / Font (Alt+1)")
            act_opt1.triggered.connect(self.map_view.trigger_alt_1)
            toolbar.addAction(act_opt1)

            act_opt2 = QAction("Opt2 (Alt+2)", self)
            act_opt2.setToolTip("Cycle Polygon Spline / Text Anchor (Alt+2)")
            act_opt2.triggered.connect(self.map_view.trigger_alt_2)
            toolbar.addAction(act_opt2)

            act_opt3 = QAction("Dash (Alt+3)", self)
            act_opt3.setToolTip("Cycle Line Dash Pattern (Alt+3)")
            act_opt3.triggered.connect(self.map_view.trigger_alt_3)
            toolbar.addAction(act_opt3)

            toolbar.addSeparator()
            toolbar.addAction(act_zin)
            toolbar.addAction(act_zout)
            toolbar.addAction(act_zreset)

            # 5. Help Menu
            help_menu = menubar.addMenu("&Help")
            act_update = QAction("Check for &Updates...", self)
            act_update.triggered.connect(self._on_check_updates)
            help_menu.addAction(act_update)

        def _wire_signals(self) -> None:
            self._image_downloaded.connect(self._on_image_downloaded)
            self._map_downloaded.connect(self._on_map_downloaded)

            self.net_client.command_received.connect(self.controller.dispatch_command)
            self.net_client.progress_message.connect(self._on_progress_message)
            self.net_client.server_notice.connect(lambda msg: self.statusBar().showMessage(f"Notice: {msg}"))
            self.net_client.connection_lost.connect(lambda err: self.statusBar().showMessage(f"Disconnected: {err}"))
            self.net_client.login_successful.connect(self._on_login_successful)

            self.map_view.token_dragged.connect(
                lambda obj_id, gx, gy: self.net_client.session.update_obj_attributes(obj_id, {"Gx": gx, "Gy": gy})
            )
            self.map_view.token_selected.connect(
                lambda obj_id: self.controller.combat_panel.select_creature(obj_id)
            )
            self.map_view.mob_attributes_changed.connect(
                self._on_mob_attributes_changed
            )
            self.map_view.mob_removed.connect(
                self._on_mob_removed
            )
            self.map_view.mob_spawned.connect(
                lambda mob_d: self._on_mob_spawned(mob_d)
            )
            self.map_view.hp_request_sent.connect(
                lambda req_d: self.net_client.session.hit_point_request_d(req_d)
            )
            self.map_view.mark_requested.connect(
                lambda sx, sy: self.net_client.session.mark(sx, sy)
            )
            self.map_view.element_drawn.connect(
                lambda gma_type, data: self.net_client.session.ls(gma_type, data)
            )
            self.map_view.element_attributes_changed.connect(
                lambda obj_id, attrs: self.net_client.session.update_obj_attributes(obj_id, attrs)
            )
            self.map_view.element_removed.connect(
                lambda obj_id: self.net_client.session.clear(obj_id)
            )
            self.map_view.tile_image_requested.connect(
                lambda img_name, z: self.controller._ensure_pixmap_loaded(img_name, z)
            )
            self.map_view.tool_changed.connect(self._on_tool_changed)
            self.map_view.status_message.connect(
                lambda msg: self.statusBar().showMessage(msg)
            )
            self.map_view.ruler_measured.connect(
                lambda msg: self.statusBar().showMessage(msg)
            )
            self.map_view.sync_view_requested.connect(
                lambda xv, yv, lbl: self.net_client.session.adjust_view(xv, yv, lbl)
            )
            self.controller.chat_panel.rollRequested.connect(
                lambda title, spec, targets: self.net_client.session.roll_dice(
                    f"{spec} #{title}" if title else spec,
                    recipients=targets,
                    to_all=(not targets),
                    blind_to_gm=("GM" in targets),
                )
            )
            self.controller.chat_panel.chatSent.connect(
                lambda text, targets: self.net_client.session.chat_message(
                    text,
                    recipients=targets,
                    to_all=(not targets),
                    to_gm=("GM" in targets),
                    markup=True,
                )
            )
            # Initiative & Clock Dock signals
            self.controller.clock_panel.timeAdvanceRequested.connect(self._on_clock_time_advance)
            self.controller.clock_panel.nextSlotRequested.connect(self._on_clock_next_slot)
            self.controller.clock_panel.combatModeToggled.connect(self._on_toggle_combat_mode)
            self.controller.clock_panel.slotSelected.connect(self._on_clock_slot_selected)
            self.controller.clock_panel.slotActivated.connect(self._on_clock_slot_activated)
            self.controller.clock_panel.slotAttributeToggled.connect(self._on_clock_slot_attribute_toggled)
            self.controller.clock_panel.timerRequestClicked.connect(self._on_open_timer_request_dialog)

            # Combat & Conditions Dock signals
            self.controller.combat_panel.hpChangeRequested.connect(self._on_combat_hp_change)
            self.controller.combat_panel.fullHealRequested.connect(self._on_combat_full_heal)
            self.controller.combat_panel.healthAttrsChanged.connect(self._on_combat_health_attrs)
            self.controller.combat_panel.killedToggled.connect(self._on_combat_killed_toggled)
            self.controller.combat_panel.conditionToggled.connect(self._on_combat_condition_toggled)
            self.controller.combat_panel.clearConditionsRequested.connect(self._on_combat_clear_conditions)
            self.controller.combat_panel.locateRequested.connect(self._on_combat_locate)
            self.controller.combat_panel.targetsChanged.connect(self._on_combat_targets_changed)
            self.controller.combat_panel.hpDialogRequested.connect(self._on_open_hp_request_dialog)

        def _on_mob_removed(self, obj_id: str) -> None:
            self.controller.combat_panel.remove_combatant(obj_id)
            self.net_client.session.clear(obj_id)

        def _on_mob_attributes_changed(self, obj_id: str, attrs: dict[str, Any]) -> None:
            self.net_client.session.update_obj_attributes(obj_id, attrs)
            self.controller._sync_token_to_combat_panel(obj_id)
            if ("Skin" in attrs or "Killed" in attrs) and obj_id in self.controller.scene.tokens:
                self.controller._ensure_creature_images_loaded(
                    self.controller.scene.tokens[obj_id].data, 1.0
                )

        def _on_mob_spawned(self, mob_d: dict[str, Any]) -> None:
            self.net_client.session.place_someone_d(mob_d)
            name = str(mob_d.get("Name", ""))
            self.controller._ensure_creature_images_loaded(mob_d, 1.0)
            oid = str(mob_d.get("ID", name))
            if oid:
                self.controller.combat_panel.update_combatant(
                    combatant_state_from_token_data(oid, mob_d)
                )

        def _on_clock_time_advance(self, delta_seconds: int, delta_turns: int) -> None:
            cal = self.controller.calendar
            cal.advance_time(delta_seconds=delta_seconds, delta_turns=delta_turns)
            self.controller.clock_panel.refresh()
            self.net_client.session.update_clock(
                float(cal.absolute), float(cal.relative), cal.running
            )

        def _on_clock_next_slot(self) -> None:
            cal = self.controller.calendar
            slot = cal.advance_slot()
            if slot is None:
                self._on_clock_time_advance(0, 1)
                return
            actor_name = str(slot.get("Name", ""))
            if actor_name:
                self.controller.scene.set_combat_state(cal.combat_mode, actor_name)
                self._on_clock_slot_activated(actor_name)
            self.controller._update_ondeck_and_audio()
            self.controller.clock_panel.refresh()

        def _on_clock_slot_selected(self, actor_name: str) -> None:
            resolved = self.controller.scene.resolve_actor_mob_ids(actor_name)
            target_id = resolved[0] if resolved else actor_name
            self.controller.combat_panel.select_creature(target_id)
            self.controller.scene.active_target_source = target_id
            self.controller.scene.refresh_targets()

        def _on_clock_slot_activated(self, actor_name: str) -> None:
            resolved = self.controller.scene.resolve_actor_mob_ids(actor_name)
            target_id = resolved[0] if resolved else actor_name
            self.controller.combat_panel.select_creature(target_id)
            if target_id in self.controller.scene.tokens:
                tok = self.controller.scene.tokens[target_id]
                sz, _, _, _, _ = tok._area_info()
                cx = (tok.gx + sz * 0.5) * 50.0
                cy = (tok.gy + sz * 0.5) * 50.0
                self.map_view.centerOn(cx, cy)
                self.controller.scene.flash_mark(cx, cy)

        def _on_clock_slot_attribute_toggled(self, actor_name: str, key: str, enabled: bool) -> None:
            resolved = self.controller.scene.resolve_actor_mob_ids(actor_name)
            for mid in resolved:
                if mid in self.controller.scene.tokens:
                    tok = self.controller.scene.tokens[mid]
                    if key == "IsFlatFooted":
                        health = dict(tok.data.get("Health") or {})
                        health["IsFlatFooted"] = enabled
                        tok.update_data({"Health": health})
                        self.net_client.session.update_obj_attributes(mid, {"Health": health})
                        self.controller._sync_token_to_combat_panel(mid)

        def _on_open_timer_request_dialog(self) -> None:
            names = list(self.controller.my_names)
            if not names:
                names = [str(d.get("Name", "")) for d in self.controller.pc_templates.values() if d.get("Name")]
            dlg = TimerRequestDialog(my_names=names, parent=self)
            if dlg.exec():
                req = dlg.request_payload()
                self.net_client.session.timer_request(**req)
                self.statusBar().showMessage(f"Sent timer request '{req['description']}' to GM.")

        def _on_combat_hp_change(
            self, obj_id: str, delta_lethal: int, delta_nonlethal: int, set_temp_hp: int
        ) -> None:
            if obj_id in self.controller.scene.tokens:
                tok = self.controller.scene.tokens[obj_id]
                new_health = apply_local_hp_adjustment(
                    tok.data,
                    delta_lethal=delta_lethal,
                    delta_nonlethal=delta_nonlethal,
                    set_temp_hp=(set_temp_hp if set_temp_hp >= 0 else None),
                )
                tok.update_data({"Health": new_health})
                self.net_client.session.update_obj_attributes(obj_id, {"Health": new_health})
                self.controller._sync_token_to_combat_panel(obj_id)
                if self.controller.calendar.track_health_change(obj_id, {"Health": new_health}):
                    self.controller.clock_panel.refresh()

        def _on_combat_full_heal(self, obj_id: str) -> None:
            if obj_id in self.controller.scene.tokens:
                tok = self.controller.scene.tokens[obj_id]
                new_health = apply_local_hp_adjustment(tok.data, full_heal=True)
                tok.update_data({"Health": new_health})
                self.net_client.session.update_obj_attributes(obj_id, {"Health": new_health})
                self.controller._sync_token_to_combat_panel(obj_id)
                if self.controller.calendar.track_health_change(obj_id, {"Health": new_health}):
                    self.controller.clock_panel.refresh()

        def _on_combat_health_attrs(self, obj_id: str, health_diff: dict[str, Any]) -> None:
            if obj_id in self.controller.scene.tokens:
                tok = self.controller.scene.tokens[obj_id]
                new_health = dict(tok.data.get("Health") or {})
                new_health.update(health_diff)
                tok.update_data({"Health": new_health})
                self.net_client.session.update_obj_attributes(obj_id, {"Health": new_health})
                self.controller._sync_token_to_combat_panel(obj_id)
                if self.controller.calendar.track_health_change(obj_id, {"Health": new_health}):
                    self.controller.clock_panel.refresh()

        def _on_combat_killed_toggled(self, obj_id: str, killed: bool) -> None:
            if obj_id in self.controller.scene.tokens:
                tok = self.controller.scene.tokens[obj_id]
                tok.update_data({"Killed": killed})
                self._on_mob_attributes_changed(obj_id, {"Killed": killed})

        def _on_combat_condition_toggled(self, obj_id: str, cond: str, enabled: bool) -> None:
            if enabled:
                self.controller.scene.add_object_attribute_values(obj_id, "StatusList", [cond])
                self.net_client.session.add_obj_attributes(obj_id, "StatusList", [cond])
            else:
                self.controller.scene.remove_object_attribute_values(obj_id, "StatusList", [cond])
                self.net_client.session.remove_obj_attributes(obj_id, "StatusList", [cond])
            self.controller._sync_token_to_combat_panel(obj_id)

        def _on_combat_clear_conditions(self, obj_id: str) -> None:
            if obj_id in self.controller.scene.tokens:
                self.controller.scene.tokens[obj_id].update_data({"StatusList": []})
            self.net_client.session.update_obj_attributes(obj_id, {"StatusList": []})
            self.controller._sync_token_to_combat_panel(obj_id)

        def _on_combat_locate(self, obj_id: str) -> None:
            self._on_clock_slot_activated(obj_id)

        def _on_combat_targets_changed(self, obj_id: str, targets: list[str]) -> None:
            if obj_id in self.controller.scene.tokens:
                self.controller.scene.tokens[obj_id].update_data({"Targets": list(targets)})
                self.controller.scene.refresh_targets()
            self.net_client.session.update_obj_attributes(obj_id, {"Targets": list(targets)})
            self.controller._sync_token_to_combat_panel(obj_id)

        def _on_open_hp_request_dialog(self, obj_id: str = "", is_temp: bool = False) -> None:
            cid = obj_id or (self.controller.combat_panel.current_creature_id() or "")
            st = self.controller.combat_panel.combatants.get(cid) if cid else None
            target_name = st.name if st else ""
            if not target_name and self.controller.my_names:
                target_name = self.controller.my_names[0]
            dlg = HPRequestDialog(
                target_name=target_name,
                is_temp=is_temp,
                initial_state=st,
                parent=self,
            )
            if dlg.exec():
                req_d = dlg.request_dict()
                self.net_client.session.hit_point_request_d(req_d)
                self.statusBar().showMessage("Sent hit point request (HPREQ) to GM.")

        def _on_progress_message(self, msg: str) -> None:
            print(f"[gma-mapper] {msg}", flush=True)
            self.statusBar().showMessage(msg)
            if "Authentication required" in msg and not self._auth_prompt_pending:
                self._auth_prompt_pending = True
                QTimer.singleShot(0, self._prompt_for_credentials)

        def _prompt_for_credentials(self) -> None:
            self._auth_prompt_pending = False
            self.net_client.hangup()
            prof_name = self.prefs.get("current_profile") or self.prefs.get("current_server", "offline")
            idx = find_server_index(self.prefs, prof_name)
            profiles = self.prefs.get("profiles", [])
            if 0 <= idx < len(profiles):
                srv = profiles[idx]
                cur_user = str(srv.get("username") or srv.get("user") or "")
                user, ok1 = QInputDialog.getText(
                    self,
                    "Server Authentication",
                    f"Username for {srv.get('host')}:{srv.get('port')}:",
                    QLineEdit.EchoMode.Normal,
                    cur_user,
                )
                if ok1 and user:
                    pw, ok2 = QInputDialog.getText(
                        self,
                        "Server Authentication",
                        f"Password for {user}@{srv.get('host')}:",
                        QLineEdit.EchoMode.Password,
                    )
                    if ok2:
                        srv["username"] = user
                        srv["password"] = pw
                        self.connect_to_configured_server()

        def _on_login_successful(self) -> None:
            msg = (
                f"Connected to {self.net_client.session.host}:{self.net_client.session.port} "
                f"(Protocol {self.net_client.session.protocol})"
            )
            print(f"[gma-mapper] {msg}", flush=True)
            self.statusBar().showMessage(msg)
            self.net_client.session.subscribe()
            self.net_client.session.allow(["GMA-MARKUP", "DICE-COLOR-BOXES", "DICE-COLOR-LABELS"])
            self.net_client.session.sync()

        def connect_to_configured_server(self) -> None:
            prof_name = self.prefs.get("current_profile") or self.prefs.get("current_server", "offline")
            idx = find_server_index(self.prefs, prof_name)
            profiles = self.prefs.get("profiles", [])
            if 0 <= idx < len(profiles):
                srv = profiles[idx]
                if srv.get("host") and srv.get("port"):
                    msg = f"Connecting to {srv['host']}:{srv['port']} (profile={prof_name})..."
                    print(f"[gma-mapper] {msg}", flush=True)
                    self.statusBar().showMessage(msg)
                    self.net_client.dial(
                        host=str(srv["host"]),
                        port=int(srv["port"]),
                        user=str(srv.get("username") or srv.get("user") or ""),
                        password=str(srv.get("password") or srv.get("pass") or ""),
                        proxy=str(srv.get("proxy_host", "")),
                        proxy_port=int(srv.get("proxy_port", 0) or 0),
                        proxy_user=str(srv.get("proxy_user", "")),
                        proxy_pass=str(srv.get("proxy_pass", "")),
                    )

        def _on_tool_changed(self, mode: str) -> None:
            if hasattr(self, "_tool_actions") and mode in self._tool_actions:
                self._tool_actions[mode].setChecked(True)

        def _clear_targets(self, targets: list[str]) -> None:
            for t in targets:
                self.controller.scene.remove_object(t)
                self.net_client.session.clear(t)
            self.statusBar().showMessage(f"Cleared {', '.join(targets)}")

        def _on_choose_fill_color(self) -> None:
            col = QColorDialog.getColor(
                QColor(self.map_view.draw_fill_color or "gray"),
                self,
                "Choose Fill Color",
            )
            if col.isValid():
                self.map_view.draw_fill_color = col.name()
                self.map_view.fill_enabled = True
                if hasattr(self, "act_fill_shapes"):
                    self.act_fill_shapes.setChecked(True)
                self.statusBar().showMessage(f"Fill color set to {col.name()}")

        def _on_choose_line_color(self) -> None:
            col = QColorDialog.getColor(
                QColor(self.map_view.draw_line_color or "black"),
                self,
                "Choose Outline Color",
            )
            if col.isValid():
                self.map_view.draw_line_color = col.name()
                self.statusBar().showMessage(f"Outline color set to {col.name()}")

        def _on_toggle_grid(self, checked: bool) -> None:
            self.controller.scene.show_grid = bool(checked)
            self.controller.scene.update()

        def _on_toggle_health_stats(self, checked: bool) -> None:
            self.controller.scene.show_health_stats = bool(checked)
            self.controller.scene.update()

        def _on_toggle_all_targets(self, checked: bool) -> None:
            self.controller.scene.show_all_targets = bool(checked)
            self.controller.scene.refresh_targets()
            self.controller.scene.update()

        def _on_toggle_combat_mode(self, checked: bool) -> None:
            enabled = bool(checked)
            if hasattr(self, "act_combat_mode"):
                self.act_combat_mode.blockSignals(True)
                self.act_combat_mode.setChecked(enabled)
                self.act_combat_mode.blockSignals(False)
            self.controller.calendar.set_time(combat_mode=enabled)
            self.controller.scene.set_combat_state(enabled, self.controller.scene.active_actor_id)
            self.controller._update_ondeck_and_audio()
            self.controller.clock_panel.refresh()
            self.net_client.session.combat_mode(enabled)

        def _on_open_map(self, merge: bool = False) -> None:
            title = "Merge Map File" if merge else "Load Map File"
            path, _ = QFileDialog.getOpenFileName(self, title, "", "GMA Maps (*.map);;All Files (*)")
            if path:
                self.controller.apply_loaded_map_file(path, merge=merge)

        def _on_unload_map(self) -> None:
            path, _ = QFileDialog.getOpenFileName(
                self, "Remove Elements from Map File", "", "GMA Maps (*.map);;All Files (*)"
            )
            if path:
                removed = self.controller.unload_map_file(path)
                for oid in removed:
                    self.net_client.session.clear(oid)
                self.statusBar().showMessage(f"Removed {len(removed)} object(s) from {Path(path).name}")

        def _on_save_map(self) -> None:
            path, _ = QFileDialog.getSaveFileName(self, "Save Map File", "", "GMA Maps (*.map)")
            if path:
                elements = [item.data for item in self.controller.scene.elements.values()]
                creatures = [item.data for item in self.controller.scene.tokens.values()]
                save_to_file(path, elements, creatures)

        def _on_open_dice(self) -> None:
            path, _ = QFileDialog.getOpenFileName(self, "Load Dice Presets", "", "Dice Files (*.dice);;All Files (*)")
            if path:
                presets, _meta = load_dice_presets_from_file(path)
                self.controller.chat_panel.set_presets(presets)

        def _on_save_dice(self) -> None:
            path, _ = QFileDialog.getSaveFileName(self, "Save Dice Presets", "", "Dice Files (*.dice)")
            if path:
                save_dice_presets_to_file(path, self.controller.chat_panel.presets)

        def _configured_server_tuple(self, prefs: dict[str, Any]) -> tuple[str, int, str, str]:
            prof_name = prefs.get("current_profile") or prefs.get("current_server", "offline")
            idx = find_server_index(prefs, prof_name)
            profiles = prefs.get("profiles", [])
            if 0 <= idx < len(profiles):
                srv = profiles[idx]
                return (
                    str(srv.get("host") or "").strip(),
                    int(srv.get("port") or 0),
                    str(srv.get("username") or srv.get("user") or ""),
                    str(srv.get("password") or srv.get("pass") or ""),
                )
            return ("", 0, "", "")

        def _apply_debug_protocol(self) -> None:
            if self.controller.debug_proto:
                self.net_client.session.debug_cb = lambda msg: print(f"[gma-mapper:proto] {msg}", flush=True)
            else:
                self.net_client.session.debug_cb = None

        def _on_preferences(self) -> None:
            old_srv = self._configured_server_tuple(self.prefs)
            dlg = PreferencesDialog(self.prefs, self)
            if dlg.exec():
                self.prefs = dlg.prefs
                self.controller.apply_preferences(self.prefs)
                self._apply_debug_protocol()
                if self.prefs_path:
                    save_preferences(self.prefs_path, self.prefs)
                new_srv = self._configured_server_tuple(self.prefs)
                if new_srv != old_srv:
                    if new_srv[0] and new_srv[1]:
                        self.connect_to_configured_server()
                    else:
                        self.net_client.hangup()

        def _on_check_updates(self) -> None:
            dlg = UpdateCheckDialog(GMAMapperVersion, self)
            dlg.exec()

else:

    class GMAMapperMainWindow:  # type: ignore[no-redef]
        def __init__(
            self,
            prefs: dict[str, Any] | None = None,
            prefs_path: str | Path | None = None,
        ) -> None:
            self.prefs = prefs or default_preferences()
            self.prefs_path = Path(prefs_path) if prefs_path else None
            self.controller = MapperController(self.prefs)
