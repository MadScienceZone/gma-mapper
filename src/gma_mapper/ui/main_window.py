"""Main Application Window (`GMAMapperMainWindow`) and protocol message router."""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import sys
from typing import Any, Callable

from gma_mapper import GMAMapperVersion
from gma_mapper.core.cache import AssetCache
from gma_mapper.core.dice import DicePresetBank, merge_preset_lists, resolve_table_roll_reply
from gma_mapper.core.file_io import (
    DATA_PAYLOAD,
    load_from_file,
    save_to_file,
    save_dice_presets_to_file,
)
from gma_mapper.core.profile import (
    default_preferences,
    default_window_layout,
    default_window_layout_path,
    find_server_index,
    load_window_layout,
    preferred_color,
    save as save_preferences,
    save_window_layout as save_window_layout_file,
)
from gma_mapper.net.client import GMANetworkClient
from gma_mapper.ui.audio import AudioManager
from gma_mapper.ui.icons import (
    TOOLBAR_BUTTON_ORDER,
    TOOLBAR_TOOLTIPS,
    IconCatalog,
    mode_slot_specs,
    stipple_icon_name,
)
from gma_mapper.ui.canvas.drawing import (
    GRID_SNAP_CHOICES,
    LINE_WIDTH_CHOICES,
    STIPPLE_CHOICES,
    cycle_in_list,
)
from gma_mapper.ui.canvas.items import creature_image_candidates
from gma_mapper.ui.canvas.scene import (
    CREATURE_GRID_SNAP_CHOICES,
    BattleMapScene,
    grid_coord_label,
)
from gma_mapper.ui.canvas.view import BattleMapView
from gma_mapper.ui.dialogs.aka_dialog import SelectAKADialog
from gma_mapper.ui.dialogs.debug_window import (
    DiagnosticWindow,
    format_diagnostic_entries_text,
)
from gma_mapper.ui.dialogs.distance_dialog import (
    DistanceDialog,
    compute_distances_from_grid,
    compute_distances_from_mob,
)
from gma_mapper.ui.dialogs.help_dialogs import AboutMapperDialog, MarkupSyntaxHelpDialog
from gma_mapper.ui.dialogs.ping_dialog import ServerPingDialog
from gma_mapper.ui.dialogs.preferences import PreferencesDialog
from gma_mapper.ui.dialogs.update_check import UpdateCheckDialog
from gma_mapper.ui.dialogs.dice_dialogs import (
    DiceModifierHelpDialog,
    DiceSyntaxHelpDialog,
    ManageDelegatesDialog,
)
from gma_mapper.ui.panels.chat_dice import ChatDicePanel, DelegatedDieRollerDialog
from gma_mapper.ui.panels.clock import (
    GolarionCalendar,
    InitiativeClockPanel,
    PlayerClockWindow,
)
from gma_mapper.ui.panels.combat import (
    CombatPanel,
    apply_local_hp_adjustment,
    combatant_state_from_token_data,
)

try:
    from PySide6.QtCore import QByteArray, QEvent, QSize, Qt, QTimer, Signal
    from PySide6.QtGui import QAction, QActionGroup, QCloseEvent, QColor, QKeySequence, QPixmap
    from PySide6.QtWidgets import (
        QApplication,
        QColorDialog,
        QMainWindow,
        QDockWidget,
        QFileDialog,
        QInputDialog,
        QLineEdit,
        QMenu,
        QMessageBox,
        QToolBar,
        QToolButton,
        QStatusBar,
        QWidget,
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
        self.player_clock_window: PlayerClockWindow | None = None
        self.shared_gvar_state: dict[str, bool] = {}
        self.chat_panel = ChatDicePanel(
            prefs=self.prefs,
            shared_gvar_state=self.shared_gvar_state,
        )
        self.chat_panel.target_context_provider = self.target_context_snapshot
        self.banks_by_tkey: dict[str, DicePresetBank] = {"": self.chat_panel.bank}
        self.delegated_panels: dict[str, ChatDicePanel] = {}
        self.delegates: list[str] = []
        self.delegate_for: list[str] = []
        self.peer_names: list[str] = []
        self.combat_panel = CombatPanel()
        self.server_settings: dict[str, Any] = {}
        self.pc_templates: dict[str, dict[str, Any]] = {}
        self.my_names: list[str] = []
        self.local_aka: list[str] = []
        self.im_not_playing: bool = False
        self.suppress_aka: bool = bool(self.prefs.get("suppress_aka", False))
        self.peer_aka: dict[str, list[str]] = {}
        self.peer_not_playing: dict[str, bool] = {}
        self.polo_cb: Callable[[], None] | None = None
        self.combatant_moved_cb: Callable[[str], None] | None = None
        self.combat_mode_changed_cb: Callable[[bool], None] | None = None
        self.identity_changed_cb: Callable[[str, bool], None] | None = None
        self.status_message_cb: Callable[[str], None] | None = None
        self.table_reply_cb: Callable[[dict[str, Any]], None] | None = None
        self.delegates_updated_cb: Callable[[], None] | None = None
        self.echo_received_cb: Callable[[dict[str, Any]], None] | None = None
        self.debug_level: int = 0
        self.debug_proto: bool = False
        self.diagnostic_log: list[tuple[str, str]] = []
        self.max_diagnostic_lines: int = 5000
        self.diagnostic_recorded_cb: Callable[[str, str, bool], None] | None = None
        self.diagnostic_cleared_cb: Callable[[], None] | None = None
        self.apply_preferences(self.prefs)

    def known_pc_names(self) -> list[str]:
        """Return sorted unique player-character names from `AC` templates and map tokens."""
        names: set[str] = set()
        for data in self.pc_templates.values():
            name = str(data.get("Name") or "").strip()
            if name:
                names.add(name)
        for oid, tok in self.scene.tokens.items():
            data = tok.data or {}
            ctype = int(data.get("CreatureType", 0) or 0)
            if ctype == 1 or str(oid).startswith("P"):
                name = str(data.get("Name") or "").strip()
                if name:
                    names.add(name)
        return sorted(names)

    def apply_local_aka(self, names: list[str], not_playing: bool = False) -> None:
        """Update local `AKA` / `NotPlaying` state and propagate to clock views."""
        if not_playing:
            self.im_not_playing = True
            self.local_aka = []
            self.my_names = []
        else:
            self.im_not_playing = False
            clean: list[str] = []
            seen: set[str] = set()
            for raw in names:
                s = str(raw or "").strip()
                if s and s not in seen:
                    seen.add(s)
                    clean.append(s)
            self.local_aka = clean
            self.my_names = (
                list(clean)
                if clean
                else ([self.chat_panel.local_user] if self.chat_panel.local_user else [])
            )
        self.clock_panel.my_names = list(self.my_names)
        if self.player_clock_window is not None:
            self.player_clock_window.my_names = list(self.my_names)
        self.refresh_clocks()

    def should_prompt_aka(self) -> bool:
        """Return True when legacy `check_aka` rules call for prompting the user."""
        local_user = self.chat_panel.local_user
        if self.local_aka or self.suppress_aka or self.im_not_playing:
            return False
        if not local_user or local_user == "GM":
            return False
        if local_user in self.known_pc_names():
            return False
        for tok in self.scene.tokens.values():
            if str((tok.data or {}).get("Name") or "").strip() == local_user:
                return False
        return True

    def target_context_snapshot(
        self,
    ) -> tuple[list[str], dict[str, dict[str, Any]], dict[str, str]]:
        """Return `(my_names, mobs_by_id, mobs_by_name)` from active battle-map tokens."""
        mobs_by_id: dict[str, dict[str, Any]] = {}
        mobs_by_name: dict[str, str] = {}
        for oid, tok in self.scene.tokens.items():
            data = dict(tok.data)
            mobs_by_id[oid] = data
            name = str(data.get("Name") or oid)
            if name:
                mobs_by_name[name] = oid
        if self.im_not_playing:
            names: list[str] = []
        else:
            names = list(self.my_names)
            if not names and self.chat_panel.local_user:
                names = [self.chat_panel.local_user]
        return (names, mobs_by_id, mobs_by_name)

    _target_context_snapshot = target_context_snapshot

    def refresh_clocks(self) -> None:
        """Refresh both the GM clock dock and the standalone player Game Clock window if open."""
        self.clock_panel.refresh()
        if self.player_clock_window is not None:
            self.player_clock_window.my_names = list(self.clock_panel.my_names)
            self.player_clock_window.refresh()

    def set_timer_scope(self, scope: str) -> None:
        """Apply timer visibility scope (`'none'`, `'mine'`, `'all'`) to both clock views."""
        self.clock_panel.set_timer_scope(scope)
        if self.player_clock_window is not None:
            self.player_clock_window.my_names = list(self.clock_panel.my_names)
            self.player_clock_window.set_timer_scope(scope)

    def sync_player_clock_timers(self) -> None:
        """Synchronize active timer records from `clock_panel` into `player_clock_window`."""
        if self.player_clock_window is not None:
            self.player_clock_window.my_names = list(self.clock_panel.my_names)
            self.player_clock_window.sync_timers(self.clock_panel.timers)

    def record_diagnostic(
        self, tag: str, msg: str, auto_spawn: bool = False
    ) -> None:
        """Append non-empty lines of `msg` with `tag` to the bounded diagnostic buffer."""
        appended: list[str] = []
        for line in str(msg).splitlines():
            if line:
                self.diagnostic_log.append((tag, line))
                appended.append(line)
        excess = len(self.diagnostic_log) - self.max_diagnostic_lines
        if excess > 0:
            del self.diagnostic_log[:excess]
        if appended and self.diagnostic_recorded_cb is not None:
            for line in appended:
                self.diagnostic_recorded_cb(tag, line, auto_spawn)

    def clear_diagnostics(self) -> int:
        """Clear all buffered diagnostic entries and notify listeners."""
        count = len(self.diagnostic_log)
        self.diagnostic_log.clear()
        if self.diagnostic_cleared_cb is not None:
            self.diagnostic_cleared_cb()
        return count

    def log_info(self, msg: str) -> None:
        """Record an informational message in the diagnostic log."""
        self.record_diagnostic("INFO", msg, auto_spawn=True)

    def log_protocol(self, msg: str) -> None:
        """Record a protocol trace line and echo to stdout when `debug_proto` is enabled."""
        self.record_diagnostic("PROTOCOL", msg, auto_spawn=self.debug_proto)
        if self.debug_proto:
            print(f"[gma-mapper:proto] {msg}", flush=True)

    def log_debug(self, level: int, msg: str) -> None:
        """Emit diagnostic message if ``level <= self.debug_level``."""
        if level == 0 or level <= self.debug_level:
            tag = "ERROR" if level == 0 else f"DEBUG {level}"
            self.record_diagnostic(tag, msg, auto_spawn=True)
        if level <= self.debug_level:
            print(f"[gma-mapper:debug:{level}] {msg}", flush=True)

    def log_error(self, msg: str) -> None:
        """Record a level-0 error diagnostic message (matching legacy ``DEBUG 0``)."""
        self.log_debug(0, msg)

    def format_diagnostic_text(self) -> str:
        """Format buffered diagnostic messages matching legacy `SaveDebugText`."""
        return format_diagnostic_entries_text(self.diagnostic_log)

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
        if self.player_clock_window is not None:
            self.player_clock_window.apply_styles(self.prefs, dark)

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
        if bool(self.prefs.get("suppress_aka", False)):
            self.suppress_aka = True
        if hasattr(self.chat_panel, "set_preferences"):
            self.chat_panel.set_preferences(self.prefs)
        if hasattr(self.chat_panel, "presets_group"):
            self.chat_panel.presets_group.setEnabled(not bool(self.prefs.get("no_dice", False)))

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

    def ensure_pixmap_loaded(self, image_name: str, zoom: float = 1.0) -> None:
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
            except Exception:  # pylint: disable=broad-exception-caught
                pass
        if self.query_image_cb:
            self.query_image_cb(image_name, zoom)

    _ensure_pixmap_loaded = ensure_pixmap_loaded

    def ensure_creature_images_loaded(self, creature_data: dict[str, Any], zoom: float = 1.0) -> None:
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
                except Exception:  # pylint: disable=broad-exception-caught
                    pass
        # Otherwise query the primary prefixed candidate (e.g. '#Name') and fallback
        for cand in candidates[:2]:
            if self.query_image_cb:
                self.query_image_cb(cand, zoom)

    _ensure_creature_images_loaded = ensure_creature_images_loaded

    @staticmethod
    def _read_map_records(
        local_map: str | Path,
    ) -> tuple[list[tuple[str, dict[str, Any]]], list[dict[str, Any]], dict[str, Any]]:
        """Read a `.map` file via `load_from_file` and partition records into `(elements, creatures, meta)`.

        `elements` is a list of `(record_type, record_data)` tuples (e.g. `("RECT", {...})`),
        preserving each shape's record type since `.map` payloads do not embed a `GMAType` key.
        Recursive `MAP` reference records are skipped.
        """
        meta, objlist = load_from_file(local_map)
        elements: list[tuple[str, dict[str, Any]]] = []
        creatures: list[dict[str, Any]] = []
        for record_type, record_data in objlist:
            if record_type == "CREATURE":
                creatures.append(record_data)
            elif record_type == "MAP":
                # Nested MAP file references are intentionally skipped here.
                continue
            else:
                elements.append((record_type, record_data))
        return elements, creatures, meta

    def apply_loaded_map_file(self, local_map: str | Path, merge: bool = False) -> None:
        """Load elements and creatures from a local/cached map file into the scene on the GUI thread."""
        elements, creatures, _meta = self._read_map_records(local_map)
        if not merge:
            self.scene.clear_all()
            self.combat_panel.clear_combatants()
        for record_type, el in elements:
            oid = str(el.get("ID", ""))
            gtype = record_type or str(el.get("GMAType", "LS-LINE"))
            if oid:
                self.scene.add_or_update_element(oid, gtype, el)
                if gtype in ("LS-TILE", "TILE"):
                    self.ensure_pixmap_loaded(str(el.get("Image", "")), 1.0)
        for cr in creatures:
            oid = str(cr.get("ID", cr.get("Name", "")))
            if oid:
                self.scene.add_or_update_token(oid, cr)
                self.ensure_creature_images_loaded(cr, 1.0)
                self.combat_panel.update_combatant(combatant_state_from_token_data(oid, cr))

    def unload_map_file(self, local_map: str | Path) -> list[str]:
        """Remove elements and creatures whose IDs appear in `local_map` (`unloadfile` in `bin/mapper_legacy.tcl`)."""
        elements, creatures, _meta = self._read_map_records(local_map)
        removed_ids: list[str] = []
        for _record_type, el in elements:
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

    def save_map_file(self, path: str | Path, meta: dict[str, Any] | None = None) -> int:
        """Serialize current scene elements and creature tokens to a `.map` file and return record count."""
        objlist: list[tuple[str, dict[str, Any]]] = []
        non_element_types = {"__META__", "__DMETA__", "PRESET", "CREATURE", "MAP"}
        for item in self.scene.elements.values():
            raw_type = getattr(item, "gma_type", "") or str(item.data.get("GMAType", ""))
            clean_type = raw_type.replace("LS-", "")
            # Skip any unrecognized or non-element record type so a single odd item cannot abort saving.
            if not clean_type or clean_type in non_element_types or clean_type not in DATA_PAYLOAD:
                continue
            objlist.append((clean_type, dict(item.data)))
        for token in self.scene.tokens.values():
            objlist.append(("CREATURE", dict(token.data)))
        save_to_file(path, (dict(meta or {}), objlist))
        return len(objlist)

    def sync_token_to_combat_panel(self, obj_id: str) -> None:
        if obj_id in self.scene.tokens:
            td = self.scene.tokens[obj_id].data
            self.combat_panel.update_combatant(combatant_state_from_token_data(obj_id, td))

    _sync_token_to_combat_panel = sync_token_to_combat_panel

    def update_ondeck_and_audio(self) -> None:
        prev = self.calendar.ondeck_status
        if self.im_not_playing:
            names: list[str] = []
        else:
            names = list(self.my_names)
            if not names:
                names = [str(d.get("Name", "")) for d in self.pc_templates.values() if d.get("Name")]
        self.clock_panel.my_names = names
        new_status = self.calendar.compute_ondeck_status(names)
        if new_status in (0, 1, 2) and new_status != prev:
            self.audio.play_ondeck(new_status)

    _update_ondeck_and_audio = update_ondeck_and_audio

    def _handle_conn_command(self, payload: dict[str, Any]) -> None:
        peers = payload.get("PeerList") or []
        if not isinstance(peers, list):
            return
        self.peer_aka.clear()
        self.peer_not_playing.clear()
        new_peer_names: list[str] = []
        for peer in peers:
            if not isinstance(peer, dict):
                continue
            user = str(peer.get("User") or "")
            aka = peer.get("AKA") or []
            aka_list = (
                [str(n).strip() for n in aka if str(n).strip()]
                if isinstance(aka, list)
                else []
            )
            not_playing = bool(peer.get("NotPlaying", False))
            if peer.get("IsMe"):
                if user:
                    self.chat_panel.set_identity(user)
                    if self.identity_changed_cb:
                        self.identity_changed_cb(user, self.chat_panel.is_gm)
                self.apply_local_aka(aka_list, not_playing=not_playing)
                continue
            if user:
                new_peer_names.append(user)
                self.peer_aka[user] = aka_list
                self.peer_not_playing[user] = not_playing
            if not not_playing:
                new_peer_names.extend(aka_list)
        clean_peers = sorted({p for p in new_peer_names if p})
        if bool(self.prefs.get("notify_peers", False)) and self.peer_names:
            joined = sorted(set(clean_peers) - set(self.peer_names))
            left = sorted(set(self.peer_names) - set(clean_peers))
            for p in joined:
                self.chat_panel.append_notice(f"{p} connected.")
            for p in left:
                self.chat_panel.append_notice(f"{p} disconnected.")
        self.peer_names = clean_peers
        self.chat_panel.update_peer_list(clean_peers)

    def _handle_ai_command(self, payload: dict[str, Any]) -> None:
        name = str(payload.get("Name", ""))
        sizes = payload.get("Sizes", [])
        url_base = self.current_url_base()
        if not (name and sizes and url_base and HAS_PYSIDE6):
            return
        for sz in sizes:
            file_id = str(sz.get("File", ""))
            zoom = float(sz.get("Zoom", 1.0) or 1.0)
            if not file_id or sz.get("IsLocalFile"):
                continue
            if self.async_fetch_image_cb:
                self.async_fetch_image_cb(name, zoom, file_id, url_base)
                continue
            try:
                local_img = self.cache.fetch_image(name, zoom, file_id)
                if local_img and Path(local_img).is_file():
                    pm = QPixmap(str(local_img))
                    if not pm.isNull() and hasattr(self.scene, "register_pixmap"):
                        self.scene.register_pixmap(name, pm)
                        break
            except Exception:  # pylint: disable=broad-exception-caught
                pass

    def _handle_oa_list_delta(self, payload: dict[str, Any], add_mode: bool) -> None:
        obj_id = str(payload.get("ObjID", payload.get("ID", payload.get("Target", ""))))
        attr_name = payload.get("AttrName")
        values = payload.get("Values")
        scene_method = "add_object_attribute_values" if add_mode else "remove_object_attribute_values"
        if attr_name and isinstance(values, list) and hasattr(self.scene, scene_method):
            getattr(self.scene, scene_method)(obj_id, str(attr_name), values)
            self.sync_token_to_combat_panel(obj_id)
            return
        attrs = (
            {str(attr_name): values}
            if attr_name and isinstance(values, list)
            else payload.get("Attributes", payload)
        )
        if obj_id not in self.scene.tokens or not isinstance(attrs, dict):
            self.sync_token_to_combat_panel(obj_id)
            return
        tok = self.scene.tokens[obj_id]
        for k, v in attrs.items():
            if not isinstance(v, list):
                continue
            if add_mode:
                cur = list(tok.data.get(k, []))
                cur.extend(item for item in v if item not in cur)
                tok.data[k] = cur
            else:
                tok.data[k] = [x for x in tok.data.get(k, []) if x not in v]
        self.sync_token_to_combat_panel(obj_id)

    def dispatch_command(self, cmd: str, payload: dict[str, Any]) -> None:
        """Route a parsed server protocol command (`cmd`, `payload`) to the appropriate subsystem."""
        if cmd == "WORLD":
            cs = payload.get("ClientSettings")
            if isinstance(cs, dict):
                self.server_settings.update(cs)
        elif cmd == "MARCO":
            if self.polo_cb:
                self.polo_cb()
        elif cmd == "GRANTED":
            user = str(payload.get("User") or "")
            if user:
                self.chat_panel.set_identity(user)
                if self.identity_changed_cb:
                    self.identity_changed_cb(user, self.chat_panel.is_gm)
        elif cmd == "AKA":
            user = str(payload.get("User") or "")
            raw_names = payload.get("Names") or []
            clean_names = (
                [str(n).strip() for n in raw_names if str(n).strip()]
                if isinstance(raw_names, list)
                else []
            )
            not_playing = bool(payload.get("NotPlaying", False))
            if not user or user == self.chat_panel.local_user:
                self.apply_local_aka(clean_names, not_playing=not_playing)
            else:
                self.peer_aka[user] = clean_names
                self.peer_not_playing[user] = not_playing
        elif cmd == "CONN":
            self._handle_conn_command(payload)
        elif cmd in ("LS-ARC", "LS-CIRC", "LS-LINE", "LS-POLY", "LS-RECT", "LS-SAO", "LS-SAOE", "LS-TEXT", "LS-TILE"):
            obj_id = str(payload.get("ID", ""))
            if obj_id:
                self.scene.add_or_update_element(obj_id, cmd, payload)
                if cmd == "LS-TILE":
                    img_name = str(payload.get("Image", payload.get("File", "")))
                    self.ensure_pixmap_loaded(img_name, 1.0)
        elif cmd == "AC":
            obj_id = str(payload.get("ID", payload.get("Name", "")))
            if obj_id:
                pc_d = dict(payload)
                if not int(pc_d.get("CreatureType", 0) or 0):
                    pc_d["CreatureType"] = 2
                if not pc_d.get("Color"):
                    pc_d["Color"] = "green"
                if not pc_d.get("Size"):
                    pc_d["Size"] = "M"
                self.pc_templates[obj_id] = pc_d
                if any(k in payload for k in ("GX", "GY", "Gx", "Gy")):
                    self.scene.add_or_update_token(obj_id, pc_d)
                self.combat_panel.update_combatant(combatant_state_from_token_data(obj_id, pc_d))
        elif cmd == "PS":
            obj_id = str(payload.get("ID", payload.get("Name", "")))
            if obj_id:
                self.scene.add_or_update_token(obj_id, payload)
                self.ensure_creature_images_loaded(payload, 1.0)
                self.combat_panel.update_combatant(combatant_state_from_token_data(obj_id, payload))
        elif cmd == "AI":
            self._handle_ai_command(payload)
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
                    except Exception:  # pylint: disable=broad-exception-caught
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
                        self.ensure_creature_images_loaded(td, 1.0)
                    self.sync_token_to_combat_panel(obj_id)
                if self.calendar.track_health_change(obj_id, attrs):
                    self.refresh_clocks()
        elif cmd == "OA+":
            self._handle_oa_list_delta(payload, add_mode=True)
        elif cmd == "OA-":
            self._handle_oa_list_delta(payload, add_mode=False)
        elif cmd == "CS":
            self.calendar.set_time(
                absolute=payload.get("Absolute"),
                relative=payload.get("Relative"),
                combat_mode=payload.get("CombatMode"),
                running=payload.get("Running"),
            )
            if payload.get("CombatMode") is not None:
                enabled = bool(payload.get("CombatMode"))
                if hasattr(self.scene, "set_combat_state"):
                    self.scene.set_combat_state(enabled, getattr(self.scene, "active_actor_id", ""))
                if self.combat_mode_changed_cb:
                    self.combat_mode_changed_cb(enabled)
            self.refresh_clocks()
        elif cmd == "CO":
            enabled = bool(payload.get("Enabled", payload.get("CombatMode", False)))
            self.calendar.set_time(combat_mode=enabled)
            if hasattr(self.scene, "set_combat_state"):
                self.scene.set_combat_state(enabled, getattr(self.scene, "active_actor_id", ""))
            if self.combat_mode_changed_cb:
                self.combat_mode_changed_cb(enabled)
            self.update_ondeck_and_audio()
            self.refresh_clocks()
        elif cmd == "IL":
            slots = payload.get("InitiativeList", payload.get("Slots", payload.get("List", [])))
            if isinstance(slots, list):
                self.calendar.initiative_slots = slots
                self.update_ondeck_and_audio()
                self.refresh_clocks()
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
            self.update_ondeck_and_audio()
            self.refresh_clocks()
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
        elif cmd == "DENIED":
            reason = str(payload.get("Reason", "Permission denied"))
            if self.status_message_cb:
                self.status_message_cb(f"Permission denied: {reason}")
            self.chat_panel.append_notice(f"Permission denied: {reason}")
        elif cmd == "ROLL":
            self.chat_panel.append_roll(payload)
            reply = resolve_table_roll_reply(
                payload,
                banks_by_tkey=self.banks_by_tkey,
                default_bank=self.chat_panel.bank,
                is_gm=self.chat_panel.is_gm,
            )
            if reply is not None and self.table_reply_cb is not None:
                self.table_reply_cb(reply)
        elif cmd == "TO":
            self.chat_panel.append_chat(payload)
        elif cmd == "CC":
            target_msgs = payload.get("TargetMessages")
            if "Target" in payload:
                target_val = int(payload.get("Target", 0) or 0)
            elif "Keep" in payload:
                keep_val = int(payload.get("Keep", 0) or 0)
                target_val = -abs(keep_val) if keep_val else 0
            else:
                target_val = 0
            self.chat_panel.clear_chat_history(
                target=target_val,
                target_messages=list(target_msgs) if isinstance(target_msgs, list) else None,
                do_all=False,
            )
        elif cmd == "Y2":
            min_id = payload.get("MinimumMessageID")
            max_id = payload.get("MaximumMessageID")
            self.chat_panel.prune_chat_history(min_id=min_id, max_id=max_id)
        elif cmd in ("DD", "DD=", "DD+"):
            if "Delegates" in payload and isinstance(payload["Delegates"], list):
                self.delegates = [str(x) for x in payload["Delegates"] if x]
            if "DelegateFor" in payload and isinstance(payload["DelegateFor"], list):
                self.delegate_for = [str(x) for x in payload["DelegateFor"] if x]
                if self.delegates_updated_cb:
                    self.delegates_updated_cb()

            presets = payload.get("Presets", payload.get("List", []))
            if isinstance(presets, list):
                is_global = bool(payload.get("Global", False))
                for_user = str(payload.get("For", "") or "")
                append_mode = (cmd == "DD+")

                if is_global:
                    sys_list = (
                        merge_preset_lists(self.chat_panel.bank.system_presets, presets)
                        if append_mode
                        else presets
                    )
                    self.chat_panel.set_system_presets(sys_list)
                    for del_panel in self.delegated_panels.values():
                        del_panel.set_system_presets(sys_list)
                elif for_user and for_user != self.chat_panel.local_user:
                    bank = self.banks_by_tkey.setdefault(
                        for_user, DicePresetBank(tkey=for_user)
                    )
                    bank.sys_gvar_on = self.shared_gvar_state
                    if append_mode:
                        bank.set_user_presets(merge_preset_lists(bank.user_presets, presets))
                        if for_user in self.delegated_panels:
                            self.delegated_panels[for_user].set_user_presets(bank.user_presets)
                    elif any(isinstance(p, dict) and p.get("Global") for p in presets):
                        sys_only = [p for p in presets if isinstance(p, dict) and p.get("Global")]
                        user_only = [p for p in presets if isinstance(p, dict) and not p.get("Global")]
                        bank.set_system_presets(sys_only)
                        bank.set_user_presets(user_only)
                        if for_user in self.delegated_panels:
                            self.delegated_panels[for_user].set_system_presets(bank.system_presets)
                            self.delegated_panels[for_user].set_user_presets(bank.user_presets)
                    else:
                        bank.set_user_presets(presets)
                        if for_user in self.delegated_panels:
                            self.delegated_panels[for_user].set_user_presets(bank.user_presets)
                else:
                    if append_mode:
                        self.chat_panel.set_user_presets(
                            merge_preset_lists(self.chat_panel.bank.user_presets, presets)
                        )
                    elif any(isinstance(p, dict) and p.get("Global") for p in presets):
                        self.chat_panel.set_presets(presets)
                    else:
                        self.chat_panel.set_user_presets(presets)
        elif cmd == "PROGRESS":
            if payload.get("IsTimer"):
                self.clock_panel.update_timer(payload)
                self.sync_player_clock_timers()
            else:
                title = str(payload.get("Title", "Working"))
                cur = int(payload.get("Value", payload.get("Current", 0)) or 0)
                mx = int(payload.get("MaxValue", payload.get("Max", payload.get("Maximum", 0))) or 0)
                self.combat_panel.set_progress(title, cur, mx)
        elif cmd == "AA":
            self.audio.register_audio_asset(payload)
        elif cmd == "SOUND":
            self.audio.handle_play_sound(payload)
        elif cmd == "ECHO":
            if self.echo_received_cb:
                self.echo_received_cb(payload)


if HAS_PYSIDE6:

    TOOLBAR_LIGHT_STYLESHEET = (
        "QToolBar { background-color: #d9d9d9; border-bottom: 1px solid #a0a0a0; spacing: 2px; padding: 2px; }"
        "QToolBar::separator { background-color: #a0a0a0; width: 1px; margin: 2px 3px; }"
        "QToolButton { background-color: #e6e6e6; color: #000000; border: 1px solid #b8b8b8; border-radius: 2px; padding: 2px; }"
        "QToolButton:hover { background-color: #f4f4f4; border-color: #888888; }"
        "QToolButton:checked, QToolButton:pressed { background-color: #b8cfe5; border: 1px solid #5b82ad; }"
        "QToolButton:disabled { background-color: #d9d9d9; color: #777777; border-color: #c4c4c4; }"
    )

    def detach_window_owner(widget: QWidget) -> None:
        """Clear Qt transient parent and Win32 owner so a floating window can layer behind the main window.

        Win32 always keeps an owned HWND above its owner in Z-order, and Qt's Windows QPA
        plugin only updates GWLP_HWNDPARENT when transientParent() is non-null.
        """
        if not widget.isWindow() or not widget.isVisible():
            return
        wh = widget.windowHandle()
        if wh is not None:
            wh.setTransientParent(None)
        if sys.platform == "win32":
            try:
                import ctypes

                user32 = ctypes.windll.user32
                set_win_long = getattr(user32, "SetWindowLongPtrW", user32.SetWindowLongW)
                set_win_long.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
                set_win_long.restype = ctypes.c_void_p
                set_win_long(int(widget.winId()), -8, 0)  # GWLP_HWNDPARENT = -8
            except Exception:  # pylint: disable=broad-exception-caught
                pass

    class IndependentDockWidget(QDockWidget):
        """Dock widget whose floating window is unowned so it can move behind the main window."""

        def __init__(self, title: str, parent: QWidget | None = None) -> None:
            super().__init__(title, parent)
            self.topLevelChanged.connect(self._on_top_level_changed)

        def _detach_if_floating(self) -> None:
            if self.isFloating():
                detach_window_owner(self)

        def _on_top_level_changed(self, floating: bool) -> None:
            if floating:
                self._detach_if_floating()
                QTimer.singleShot(0, self._detach_if_floating)

        def event(self, event: QEvent) -> bool:
            res = super().event(event)
            if self.isFloating() and event.type() in (
                QEvent.Type.Show,
                QEvent.Type.WinIdChange,
                QEvent.Type.WindowActivate,
            ):
                self._detach_if_floating()
                QTimer.singleShot(0, self._detach_if_floating)
            return res

    class GMAMapperMainWindow(QMainWindow):
        """Primary Qt6 Main Window for GMA Mapper (`QMainWindow` + `QDockWidget` panels)."""

        _image_downloaded = Signal(str, str)       # (name, local_file_path)
        _map_downloaded = Signal(str, bool)        # (local_file_path, merge)
        _diagnostic_event = Signal(str, str, bool) # (tag, message, auto_spawn)

        def __init__(
            self,
            prefs: dict[str, Any] | None = None,
            prefs_path: str | Path | None = None,
        ) -> None:
            super().__init__()
            self.prefs = prefs or default_preferences()
            self.prefs_path = Path(prefs_path) if prefs_path else None
            self.window_layout_path: Path | None = (
                default_window_layout_path(self.prefs_path) if self.prefs_path else None
            )
            self.window_layout: dict[str, Any] = (
                load_window_layout(self.window_layout_path)
                if self.window_layout_path
                else default_window_layout()
            )
            self.cache = AssetCache()
            self.audio = AudioManager()
            self._saf_mode = False
            self.icon_catalog = IconCatalog(
                button_size=self.prefs.get("button_size", "small"),
                dark_mode=False,
                image_format=str(self.prefs.get("image_format", "png") or "png"),
            )
            self._download_pool = ThreadPoolExecutor(max_workers=4)
            self._auth_prompt_pending = False
            self._chat_history_synced_for_session = False
            self._dice_presets_synced_for_session = False
            self.act_reconnect_server: Any = None
            self.act_disconnect_server: Any = None
            self.net_client = GMANetworkClient(self)
            self.controller = MapperController(
                self.prefs,
                self.cache,
                self.audio,
                query_image_cb=self.net_client.session.query_image,
                async_fetch_image_cb=self._submit_image_download,
                async_fetch_map_cb=self._submit_map_download,
            )
            self.controller.polo_cb = self.net_client.session.polo
            self.controller.status_message_cb = lambda msg: self.statusBar().showMessage(msg)
            self.controller.table_reply_cb = self._on_table_roll_reply
            self.controller.delegates_updated_cb = self._rebuild_delegate_for_menu
            self.controller.echo_received_cb = self._on_echo_received
            self._ping_dialog: ServerPingDialog | None = None
            self._debug_window: DiagnosticWindow | None = None
            self._distance_dialog: DistanceDialog | None = None
            self._delegated_dialogs: dict[str, DelegatedDieRollerDialog] = {}
            self.controller.diagnostic_recorded_cb = self._on_diagnostic_recorded
            self.controller.diagnostic_cleared_cb = self._on_diagnostics_cleared
            self._apply_debug_protocol()

            self.setWindowTitle(f"GMA Mapper {GMAMapperVersion}")
            app_icon = self.icon_catalog.app_window_icon()
            if app_icon is not None and not app_icon.isNull():
                self.setWindowIcon(app_icon)
            self.resize(1280, 840)

            # Central Battle Map View
            self.map_view = BattleMapView(self.controller.scene, self)
            self.map_view.pc_templates_provider = lambda: self.controller.pc_templates
            self.controller.adjust_view_cb = self.map_view.adjust_view
            self.controller.combatant_moved_cb = self.map_view.scroll_to_combatant
            self.controller.combat_mode_changed_cb = self._sync_combat_mode_action
            self.controller.identity_changed_cb = self._on_identity_changed
            self.setCentralWidget(self.map_view)

            self._create_docks()
            self._create_menus_and_toolbar()
            self._sync_role_ui()
            self._wire_signals()
            self.setStatusBar(QStatusBar(self))
            self.statusBar().showMessage("Ready")
            self.restore_window_layout()

        def _submit_image_download(self, name: str, zoom: float, file_id: str, url_base: str) -> None:
            def _worker() -> None:
                try:
                    self.cache.curl_server = url_base
                    local_img = self.cache.fetch_image(name, zoom, file_id)
                    if local_img and Path(local_img).is_file():
                        self._image_downloaded.emit(name, str(local_img))
                except Exception as exc:  # pylint: disable=broad-exception-caught
                    self._diagnostic_event.emit(
                        "ERROR", f"Image download failed ({name}): {exc}", True
                    )

            self._download_pool.submit(_worker)

        def _submit_map_download(self, file_id: str, merge: bool, cache_only: bool, url_base: str) -> None:
            def _worker() -> None:
                try:
                    self.cache.curl_server = url_base
                    local_map = self.cache.fetch_map_file(file_id)
                    if not cache_only and local_map and Path(local_map).is_file():
                        self._map_downloaded.emit(str(local_map), merge)
                except Exception as exc:  # pylint: disable=broad-exception-caught
                    self._diagnostic_event.emit(
                        "ERROR", f"Map download failed ({file_id}): {exc}", True
                    )

            self._download_pool.submit(_worker)

        def _on_image_downloaded(self, name: str, local_path: str) -> None:
            pm = QPixmap(local_path)
            if not pm.isNull() and hasattr(self.controller.scene, "register_pixmap"):
                self.controller.scene.register_pixmap(name, pm)

        def _on_map_downloaded(self, local_path: str, merge: bool) -> None:
            try:
                self.controller.apply_loaded_map_file(local_path, merge)
            except Exception as exc:  # pylint: disable=broad-exception-caught
                msg = f"Error loading map: {exc}"
                self.statusBar().showMessage(msg)
                self.controller.log_error(msg)

        def _create_docks(self) -> None:
            self.clock_dock = IndependentDockWidget("Initiative & Clock", self)
            self.clock_dock.setObjectName("clock_dock")
            self.clock_dock.setWidget(self.controller.clock_panel)
            self.addDockWidget(Qt.DockWidgetArea.RightDockWidgetArea, self.clock_dock)

            self.combat_dock = IndependentDockWidget("Combat & Conditions", self)
            self.combat_dock.setObjectName("combat_dock")
            self.combat_dock.setWidget(self.controller.combat_panel)
            self.addDockWidget(Qt.DockWidgetArea.RightDockWidgetArea, self.combat_dock)

            self.chat_dock = IndependentDockWidget("Chat & Dice Roller", self)
            self.chat_dock.setObjectName("chat_dock")
            self.chat_dock.setWidget(self.controller.chat_panel)
            self.addDockWidget(Qt.DockWidgetArea.BottomDockWidgetArea, self.chat_dock)
            self.chat_dock.visibilityChanged.connect(self._on_chat_dock_visibility_changed)

            self._sync_role_ui()

        def _create_menus_and_toolbar(self) -> None:
            menubar = self.menuBar()
            self._tool_actions: dict[str, QAction] = {}
            self.toolbar_actions: dict[str, QAction] = {}
            self._stipple_actions: dict[str, QAction] = {}
            self._snap_actions: dict[int, QAction] = {}
            self._width_actions: dict[int, QAction] = {}

            # 1. File Menu
            file_menu = menubar.addMenu("&File")
            act_open_map = QAction("&Load Map File...", self)
            act_open_map.setIconText("Load")
            act_open_map.setShortcut(QKeySequence("Ctrl+O"))
            act_open_map.triggered.connect(lambda _c=False: self._on_open_map(merge=False))
            file_menu.addAction(act_open_map)

            act_merge_map = QAction("&Merge Map File...", self)
            act_merge_map.setIconText("Merge")
            act_merge_map.setShortcut(QKeySequence("Alt+O"))
            act_merge_map.triggered.connect(lambda _c=False: self._on_open_map(merge=True))
            file_menu.addAction(act_merge_map)

            act_save_map = QAction("&Save Map File...", self)
            act_save_map.setIconText("Save")
            act_save_map.setShortcut(QKeySequence("Ctrl+S"))
            act_save_map.triggered.connect(self._on_save_map)
            file_menu.addAction(act_save_map)

            act_unload_map = QAction("&Remove Elements from File...", self)
            act_unload_map.setIconText("Unload")
            act_unload_map.setShortcut(QKeySequence("Ctrl+Alt+O"))
            act_unload_map.triggered.connect(self._on_unload_map)
            file_menu.addAction(act_unload_map)

            file_menu.addSeparator()
            act_open_dice = QAction("Load &Dice Presets from File...", self)
            act_open_dice.setStatusTip("Import die-roll presets from a local .dice file and save to server")
            act_open_dice.triggered.connect(self._on_open_dice)
            file_menu.addAction(act_open_dice)

            act_save_dice = QAction("Save Dice &Presets to File...", self)
            act_save_dice.setStatusTip("Export die-roll presets to a local .dice file on disk")
            act_save_dice.triggered.connect(self._on_save_dice)
            file_menu.addAction(act_save_dice)

            file_menu.addSeparator()
            act_quit = QAction("&Quit", self)
            act_quit.setIconText("Quit")
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
                short_text: str = "",
            ) -> QAction:
                act = QAction(label, self)
                if short_text:
                    act.setIconText(short_text)
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
                if parent_menu is not None:
                    parent_menu.addAction(act)
                self._tool_actions[mode] = act
                return act

            _add_tool_action(
                edit_menu, "Normal Play Mode", "pointer", "Alt+N", "Selected normal play mode", "Play"
            )
            edit_menu.addSeparator()

            clear_actions_by_label: dict[str, QAction] = {}
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
                clear_actions_by_label[clr_label] = act_clr

            self.act_clear_elements = clear_actions_by_label["Clear All Map Elements"]
            self.act_clear_elements.setIconText("Clear Map")
            self.act_clear_creatures = clear_actions_by_label["Clear All Creatures"]
            self.act_clear_creatures.setIconText("Clear Creatures")

            edit_menu.addSeparator()
            _add_tool_action(
                edit_menu,
                "Draw Lines",
                "line",
                "Alt+L",
                "Selected line tool [Alt+1 arrows, Alt+3 dashes, Double/Right-click to finish]",
                "Line",
            )
            _add_tool_action(
                edit_menu,
                "Draw Rectangles",
                "rect",
                "Alt+R",
                "Selected rectangle tool [Alt+3 dashes]",
                "Rect",
            )
            _add_tool_action(
                edit_menu,
                "Draw Polygons",
                "poly",
                "Alt+P",
                "Selected polygon tool [Alt+1 join, Alt+2 spline, Alt+3 dashes, Double/Right-click to finish]",
                "Poly",
            )
            _add_tool_action(
                edit_menu,
                "Draw Circles/Ellipses",
                "circ",
                "Alt+E",
                "Selected ellipse tool [Alt+3 dashes]",
                "Circ",
            )
            _add_tool_action(
                edit_menu,
                "Draw Arcs",
                "arc",
                "Alt+A",
                "Selected arc tool [Alt+1 mode, Alt+3 dashes]",
                "Arc",
            )
            _add_tool_action(
                edit_menu,
                "Add Text...",
                "text",
                "Alt+T",
                "Selected text tool [Right-click to change text, Alt+1 font, Alt+2 anchor]",
                "Text",
            )
            _add_tool_action(
                edit_menu,
                "Remove Objects",
                "kill",
                "Alt+X",
                "Selected remove-object tool [Click element, or P/N to cycle and X to delete]",
                "Delete",
            )
            _add_tool_action(
                edit_menu,
                "Move Objects",
                "move",
                "Alt+M",
                "Selected move-object tool [Drag element, Arrows/HJKL to nudge, U/D/F/B for Z-order]",
                "Move",
            )
            _add_tool_action(
                edit_menu,
                "Stamp Objects",
                "tile",
                "Alt+S",
                "Selected stamp tool [Right-click to choose tile image, Left-click to place]",
                "Stamp",
            )
            _add_tool_action(
                edit_menu,
                "Set Area of Effect Boundary",
                "aoebound",
                "Alt+B",
                "Selected area-of-effect boundary tool [Click vertices, Double/Right-click to finish]",
                "AoE Bound",
            )
            _add_tool_action(None, "Mark", "mark", "", "Selected mark/ping tool", "Mark")

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
            self.act_fill_shapes.setIconText("Fill")
            self.act_fill_shapes.setCheckable(True)
            self.act_fill_shapes.setChecked(self.map_view.fill_enabled)
            self.act_fill_shapes.triggered.connect(self._on_toggle_fill_shapes)
            edit_menu.addAction(self.act_fill_shapes)

            self.act_fill_col = QAction("Choose Fill Color...", self)
            self.act_fill_col.setIconText("Fill Color")
            self.act_fill_col.triggered.connect(self._on_choose_fill_color)
            edit_menu.addAction(self.act_fill_col)

            self.act_line_col = QAction("Choose Outline Color...", self)
            self.act_line_col.setIconText("Line Color")
            self.act_line_col.triggered.connect(self._on_choose_line_color)
            edit_menu.addAction(self.act_line_col)

            stipple_menu = edit_menu.addMenu("Select Fill Pattern")
            stipple_group = QActionGroup(self)
            stipple_group.setExclusive(True)
            for st_val, st_label in STIPPLE_CHOICES:
                act_st = QAction(st_label, self)
                act_st.setCheckable(True)
                if st_val == self.map_view.draw_stipple:
                    act_st.setChecked(True)
                act_st.triggered.connect(
                    lambda _c=False, v=st_val: self._set_stipple(v)
                )
                stipple_group.addAction(act_st)
                stipple_menu.addAction(act_st)
                self._stipple_actions[st_val] = act_st

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
                    lambda _c=False, v=sn_val: self._set_obj_snap(v)
                )
                snap_group.addAction(act_sn)
                snap_menu.addAction(act_sn)
                self._snap_actions[sn_val] = act_sn

            width_menu = edit_menu.addMenu("Set Line Thickness")
            width_group = QActionGroup(self)
            width_group.setExclusive(True)
            for w_val, w_label in LINE_WIDTH_CHOICES:
                act_w = QAction(w_label, self)
                act_w.setCheckable(True)
                if w_val == self.map_view.draw_width:
                    act_w.setChecked(True)
                act_w.triggered.connect(
                    lambda _c=False, v=w_val: self._set_draw_width(v)
                )
                width_group.addAction(act_w)
                width_menu.addAction(act_w)
                self._width_actions[w_val] = act_w

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

            self.act_toolbar_icons = QAction("Show Toolbar &Icons", self)
            self.act_toolbar_icons.setCheckable(True)
            self.act_toolbar_icons.setChecked(not bool(self.prefs.get("toolbar_text", False)))
            self.act_toolbar_icons.triggered.connect(self._on_toggle_toolbar_icons)
            view_menu.addAction(self.act_toolbar_icons)

            view_menu.addSeparator()
            self.act_view_chat_dock = self.chat_dock.toggleViewAction()
            self.act_view_chat_dock.setShortcut(QKeySequence("Alt+D"))
            view_menu.addAction(self.act_view_chat_dock)

            self.act_view_combat_dock = self.combat_dock.toggleViewAction()
            view_menu.addAction(self.act_view_combat_dock)

            # Play -> Show Initiative Clock already owns Alt+C (standalone player clock window),
            # so bind the GM-only Initiative & Clock dock toggle to Alt+Shift+C to avoid an
            # ambiguous Qt shortcut collision.
            self.act_view_clock_dock = self.clock_dock.toggleViewAction()
            self.act_view_clock_dock.setShortcut(QKeySequence("Alt+Shift+C"))
            view_menu.addAction(self.act_view_clock_dock)

            self.act_save_window_layout = QAction("&Save Window Layout", self)
            self.act_save_window_layout.triggered.connect(self._on_save_window_layout)
            view_menu.addAction(self.act_save_window_layout)

            self.act_reset_window_layout = QAction("Reset &Window Layout", self)
            self.act_reset_window_layout.triggered.connect(self._on_reset_window_layout)
            view_menu.addAction(self.act_reset_window_layout)
            view_menu.addSeparator()

            self.act_show_grid = QAction("Show Map &Grid", self)
            self.act_show_grid.setIconText("Grid")
            self.act_show_grid.setCheckable(True)
            self.act_show_grid.setChecked(self.controller.scene.show_grid)
            self.act_show_grid.triggered.connect(self._on_toggle_grid)
            view_menu.addAction(self.act_show_grid)

            self.act_show_health = QAction("Show &Health Stats", self)
            self.act_show_health.setIconText("HP")
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
                    lambda _c=False, sc=t_scope: self.controller.set_timer_scope(sc)
                )
                timers_group.addAction(act_tm)
                timers_menu.addAction(act_tm)

            view_menu.addSeparator()
            act_zin = QAction("Zoom &In", self)
            act_zin.setIconText("Zoom In")
            act_zin.setShortcut(QKeySequence("Ctrl++"))
            act_zin.triggered.connect(self.map_view.zoom_in)
            view_menu.addAction(act_zin)

            act_zout = QAction("Zoom &Out", self)
            act_zout.setIconText("Zoom Out")
            act_zout.setShortcut(QKeySequence("Ctrl+-"))
            act_zout.triggered.connect(self.map_view.zoom_out)
            view_menu.addAction(act_zout)

            act_zreset = QAction("&Restore Zoom (100%)", self)
            act_zreset.setIconText("100%")
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
            self.act_combat_mode.setIconText("Combat")
            self.act_combat_mode.setCheckable(True)
            self.act_combat_mode.setChecked(self.controller.scene.combat_mode)
            self.act_combat_mode.triggered.connect(self._on_toggle_combat_mode)
            play_menu.addAction(self.act_combat_mode)

            self.act_show_player_clock = QAction("Show &Initiative Clock", self)
            self.act_show_player_clock.setShortcut(QKeySequence("Alt+C"))
            self.act_show_player_clock.triggered.connect(self.show_player_clock_window)
            play_menu.addAction(self.act_show_player_clock)

            _add_tool_action(
                play_menu,
                "&Indicate Area of Effect",
                "saoe",
                "Ctrl+A",
                "Selected area-of-effect tool [Alt+1 shape (radius/cone/ray), Alt+2 spread]",
                "AoE",
            )
            _add_tool_action(
                play_menu,
                "&Measure Distance Along Line(s)",
                "ruler",
                "Ctrl+D",
                "Selected ruler tool",
                "Ruler",
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
            act_req_timer.setIconText("Timer")
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

            play_menu.addSeparator()
            self.act_select_aka = QAction("Specify What &Character You're Playing...", self)
            self.act_select_aka.triggered.connect(lambda: self._on_select_aka(auto_prompt=False))
            play_menu.addAction(self.act_select_aka)

            play_menu.addSeparator()
            self.act_edit_presets = QAction("Edit &Die Roll Presets...", self)
            self.act_edit_presets.triggered.connect(
                lambda: self.controller.chat_panel.open_preset_editor(system_mode=False)
            )
            play_menu.addAction(self.act_edit_presets)

            self.act_edit_sys_presets = QAction("Edit &System Presets...", self)
            self.act_edit_sys_presets.triggered.connect(
                lambda: self.controller.chat_panel.open_preset_editor(system_mode=True)
            )
            play_menu.addAction(self.act_edit_sys_presets)

            self.act_save_presets_server = QAction("Save Die Roll Presets to &Server", self)
            self.act_save_presets_server.triggered.connect(
                self.controller.chat_panel.push_presets_to_server
            )
            play_menu.addAction(self.act_save_presets_server)

            act_manage_delegates = QAction("Manage Die Roll D&elegates...", self)
            act_manage_delegates.triggered.connect(self._on_manage_delegates)
            play_menu.addAction(act_manage_delegates)

            self.act_refresh_presets = QAction("Refresh Die-Roll and Delegate Data from Server", self)
            self.act_refresh_presets.triggered.connect(
                lambda: self._on_refresh_presets_from_server("")
            )
            play_menu.addAction(self.act_refresh_presets)

            self.delegate_for_menu = play_menu.addMenu("Access Die Rolls &For")
            self._rebuild_delegate_for_menu()

            play_menu.addSeparator()
            self.server_profile_menu = play_menu.addMenu("Server &Profile")
            self._rebuild_server_profile_menu()

            # 5. Tools Menu (ported from bin/mapper_legacy.tcl lines 1339-1360)
            tools_menu = menubar.addMenu("&Tools")
            self.act_check_updates = QAction("Check for &Updates...", self)
            self.act_check_updates.triggered.connect(self._on_check_updates)
            tools_menu.addAction(self.act_check_updates)

            tools_menu.addSeparator()
            self.act_clear_chat_history = QAction("Clear Chat &History", self)
            self.act_clear_chat_history.triggered.connect(
                lambda: self._on_reset_chat_history(-1)
            )
            tools_menu.addAction(self.act_clear_chat_history)

            self.act_clear_pinned_chats = QAction("Clear &Pinned Chat Messages", self)
            self.act_clear_pinned_chats.triggered.connect(self._on_clear_pinned_chats)
            tools_menu.addAction(self.act_clear_pinned_chats)

            self.reset_chat_menu = tools_menu.addMenu("Reset Chat History")
            for qty, label in (
                (50, "...and load 50 messages"),
                (100, "...and load 100 messages"),
                (500, "...and load 500 messages"),
                (0, "...and load all"),
            ):
                act_rc = QAction(label, self.reset_chat_menu)
                act_rc.triggered.connect(
                    lambda _c=False, q=qty: self._on_reset_chat_history(q)
                )
                self.reset_chat_menu.addAction(act_rc)

            tools_menu.addSeparator()
            self.act_clear_image_cache = QAction("Clear Image &Cache", self)
            self.act_clear_image_cache.triggered.connect(
                lambda: self._on_cleanup_image_cache(0)
            )
            tools_menu.addAction(self.act_clear_image_cache)

            self.act_clear_image_cache_60 = QAction(
                "Clear Image Cache (over &60 days)", self
            )
            self.act_clear_image_cache_60.triggered.connect(
                lambda: self._on_cleanup_image_cache(60)
            )
            tools_menu.addAction(self.act_clear_image_cache_60)

            self.act_update_image_cache = QAction(
                "&Update Cached Images from Server", self
            )
            self.act_update_image_cache.triggered.connect(
                lambda: self._on_cleanup_image_cache("-update")
            )
            tools_menu.addAction(self.act_update_image_cache)

            self.act_retry_failed_images = QAction(
                "&Retry Failed Image Retrievals", self
            )
            self.act_retry_failed_images.triggered.connect(self._on_retry_failed_images)
            tools_menu.addAction(self.act_retry_failed_images)

            tools_menu.addSeparator()
            self.act_server_ping_test = QAction(
                "Test &Server Response Time...", self
            )
            self.act_server_ping_test.triggered.connect(self._on_server_ping_test)
            tools_menu.addAction(self.act_server_ping_test)

            tools_menu.addSeparator()
            self.act_show_diagnostics = QAction(
                "Show &Diagnostic Messages...", self
            )
            self.act_show_diagnostics.triggered.connect(
                lambda _c=False: self.show_diagnostic_window(raise_window=True)
            )
            tools_menu.addAction(self.act_show_diagnostics)

            self.act_save_diagnostics = QAction(
                "Save &Diagnostic Messages As...", self
            )
            self.act_save_diagnostics.triggered.connect(
                self._on_save_diagnostic_messages
            )
            tools_menu.addAction(self.act_save_diagnostics)

            # 6. Help Menu
            help_menu = menubar.addMenu("&Help")
            self.act_about_mapper = QAction("&About GMA Mapper...", self)
            self.act_about_mapper.setShortcut(QKeySequence("F1"))
            self.act_about_mapper.triggered.connect(self._on_show_about_mapper)
            help_menu.addAction(self.act_about_mapper)

            help_menu.addSeparator()
            self.act_dice_syntax = QAction("&Die Roller Syntax...", self)
            self.act_dice_syntax.setShortcut(QKeySequence("?"))
            self.act_dice_syntax.triggered.connect(self._on_show_dice_syntax_help)
            help_menu.addAction(self.act_dice_syntax)

            self.act_dice_mod_help = QAction("Die Roll &Modifiers and Conditions...", self)
            self.act_dice_mod_help.triggered.connect(self._on_show_dice_modifier_help)
            help_menu.addAction(self.act_dice_mod_help)

            self.act_markup_syntax = QAction("Text &Markup Syntax...", self)
            self.act_markup_syntax.setShortcut(QKeySequence("Alt+?"))
            self.act_markup_syntax.triggered.connect(self._on_show_markup_syntax_help)
            help_menu.addAction(self.act_markup_syntax)

            # 7. Tools Toolbar (ported from bin/mapper_legacy.tcl lines 2835-2880)
            toolbar = QToolBar("Tools", self)
            toolbar.setObjectName("tools_toolbar")
            self.tools_toolbar = toolbar
            self.act_show_toolbar.triggered.connect(toolbar.setVisible)
            self.addToolBar(Qt.ToolBarArea.TopToolBarArea, toolbar)

            # Optional compact menu button (when preferences `menu_button` is True)
            self.menu_tool_button = QToolButton(toolbar)
            self.menu_tool_button.setText("Menu")
            self.menu_tool_button.setToolTip("Main Application Menu")
            self.menu_tool_button.setPopupMode(QToolButton.ToolButtonPopupMode.InstantPopup)
            compact_menu = QMenu(self.menu_tool_button)
            for sub_m in (file_menu, edit_menu, view_menu, play_menu, tools_menu, help_menu):
                compact_menu.addMenu(sub_m)
            self.menu_tool_button.setMenu(compact_menu)
            self.act_menu_button_widget = toolbar.addWidget(self.menu_tool_button)

            self.act_mode1 = QAction("Opt1", self)
            self.act_mode1.triggered.connect(self._on_toolbar_mode1)
            self.act_mode2 = QAction("Opt2", self)
            self.act_mode2.triggered.connect(self._on_toolbar_mode2)
            self.act_mode3 = QAction("Dash", self)
            self.act_mode3.triggered.connect(self._on_toolbar_mode3)

            self.act_cycle_stipple = QAction("Pattern", self)
            self.act_cycle_stipple.triggered.connect(self._on_cycle_stipple)

            self.act_cycle_snap = QAction("Snap", self)
            self.act_cycle_snap.triggered.connect(self._on_cycle_snap)

            self.act_cycle_width = QAction("Width", self)
            self.act_cycle_width.triggered.connect(self._on_cycle_width)

            self.act_open_chat_dock = QAction("Chat/Dice", self)
            self.act_open_chat_dock.triggered.connect(self._on_toggle_chat_dock)

            self.act_open_clock_dock = QAction("Clock", self)
            self.act_open_clock_dock.triggered.connect(self._on_toggle_clock_dock)

            self.act_saf_sync = QAction("Push", self)
            self.act_saf_sync.setEnabled(False)
            self.act_saf_sync.triggered.connect(self._on_saf_push_sync)

            self.act_saf_mode = QAction("SaF", self)
            self.act_saf_mode.setCheckable(True)
            self.act_saf_mode.triggered.connect(self._on_toggle_saf_mode)

            self.act_sync_server = QAction("Sync", self)
            self.act_sync_server.triggered.connect(self._on_sync_from_server)

            self.toolbar_actions = {
                "line": self._tool_actions["line"],
                "rect": self._tool_actions["rect"],
                "poly": self._tool_actions["poly"],
                "circ": self._tool_actions["circ"],
                "arc": self._tool_actions["arc"],
                "text": self._tool_actions["text"],
                "mode": self.act_mode1,
                "mode2": self.act_mode2,
                "mode3": self.act_mode3,
                "nil": self._tool_actions["pointer"],
                "kill": self._tool_actions["kill"],
                "move": self._tool_actions["move"],
                "stamp": self._tool_actions["tile"],
                "nfill": self.act_fill_shapes,
                "cfill": self.act_fill_col,
                "cline": self.act_line_col,
                "cstip": self.act_cycle_stipple,
                "snap": self.act_cycle_snap,
                "width": self.act_cycle_width,
                "clear": self.act_clear_elements,
                "clearp": self.act_clear_creatures,
                "combat": self.act_combat_mode,
                "showhp": self.act_show_health,
                "aoe": self._tool_actions["saoe"],
                "aoebound": self._tool_actions["aoebound"],
                "ruler": self._tool_actions["ruler"],
                "griden": self.act_show_grid,
                "chat": self.act_open_chat_dock,
                "iniclock": self.act_open_clock_dock,
                "tmrq": act_req_timer,
                "zi": act_zin,
                "zo": act_zout,
                "refresh": act_zreset,
                "load": act_open_map,
                "merge": act_merge_map,
                "unload": act_unload_map,
                "sync": self.act_saf_sync,
                "saf": self.act_saf_mode,
                "polo": self.act_sync_server,
                "save": act_save_map,
                "exit": act_quit,
            }

            for btn_key, tip in TOOLBAR_TOOLTIPS.items():
                if btn_key in self.toolbar_actions and tip:
                    self.toolbar_actions[btn_key].setToolTip(tip)

            for entry in TOOLBAR_BUTTON_ORDER:
                if entry == "|":
                    toolbar.addSeparator()
                elif entry in self.toolbar_actions:
                    toolbar.addAction(self.toolbar_actions[entry])

            self._refresh_toolbar_appearance()

        def _wire_signals(self) -> None:
            self._image_downloaded.connect(self._on_image_downloaded)
            self._map_downloaded.connect(self._on_map_downloaded)
            self._diagnostic_event.connect(self._on_async_diagnostic_event)

            self.net_client.command_received.connect(self.controller.dispatch_command)
            self.net_client.progress_message.connect(self._on_progress_message)
            self.net_client.server_notice.connect(lambda msg: self.statusBar().showMessage(f"Notice: {msg}"))
            self.net_client.connection_lost.connect(self._on_connection_lost)
            self.net_client.login_successful.connect(self._on_login_successful)

            self.map_view.token_dragged.connect(
                lambda obj_id, gx, gy: self.net_client.session.update_obj_attributes(obj_id, {"Gx": gx, "Gy": gy})
            )
            self.map_view.token_selected.connect(
                self.controller.combat_panel.select_creature
            )
            self.map_view.mob_attributes_changed.connect(
                self._on_mob_attributes_changed
            )
            self.map_view.mob_removed.connect(
                self._on_mob_removed
            )
            self.map_view.mob_spawned.connect(
                self._on_mob_spawned
            )
            self.map_view.hp_request_sent.connect(
                self.net_client.session.hit_point_request_d
            )
            self.map_view.mark_requested.connect(
                self.net_client.session.mark
            )
            self.map_view.element_drawn.connect(
                self.net_client.session.ls
            )
            self.map_view.element_attributes_changed.connect(
                self.net_client.session.update_obj_attributes
            )
            self.map_view.element_removed.connect(
                self.net_client.session.clear
            )
            self.map_view.tile_image_requested.connect(
                self.controller.ensure_pixmap_loaded
            )
            self.map_view.tool_changed.connect(self._on_tool_changed)
            self.map_view.tool_options_changed.connect(self._update_toolbar_dynamic_states)
            self.map_view.status_message.connect(
                lambda msg: self.statusBar().showMessage(msg)
            )
            self.map_view.ruler_measured.connect(
                lambda msg: self.statusBar().showMessage(msg)
            )
            self.map_view.sync_view_requested.connect(
                self.net_client.session.adjust_view
            )
            self.map_view.distance_from_grid_requested.connect(
                self.show_distance_from_grid
            )
            self.map_view.distance_from_mob_requested.connect(
                self.show_distance_from_mob
            )
            self._wire_chat_panel_signals(self.controller.chat_panel)
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
            self.controller.sync_token_to_combat_panel(obj_id)
            if ("Skin" in attrs or "Killed" in attrs) and obj_id in self.controller.scene.tokens:
                self.controller.ensure_creature_images_loaded(
                    self.controller.scene.tokens[obj_id].data, 1.0
                )

        def _on_mob_spawned(self, mob_d: dict[str, Any]) -> None:
            self.net_client.session.place_someone_d(mob_d)
            name = str(mob_d.get("Name", ""))
            self.controller.ensure_creature_images_loaded(mob_d, 1.0)
            oid = str(mob_d.get("ID", name))
            if oid:
                self.controller.combat_panel.update_combatant(
                    combatant_state_from_token_data(oid, mob_d)
                )

        def _on_clock_time_advance(self, delta_seconds: int, delta_turns: int) -> None:
            cal = self.controller.calendar
            cal.advance_time(delta_seconds=delta_seconds, delta_turns=delta_turns)
            self.controller.refresh_clocks()
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
            self.controller.update_ondeck_and_audio()
            self.controller.refresh_clocks()

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
                sz, _, _, _, _ = tok.area_info()
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
                        self.controller.sync_token_to_combat_panel(mid)

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
                self.controller.sync_token_to_combat_panel(obj_id)
                if self.controller.calendar.track_health_change(obj_id, {"Health": new_health}):
                    self.controller.refresh_clocks()

        def _on_combat_full_heal(self, obj_id: str) -> None:
            if obj_id in self.controller.scene.tokens:
                tok = self.controller.scene.tokens[obj_id]
                new_health = apply_local_hp_adjustment(tok.data, full_heal=True)
                tok.update_data({"Health": new_health})
                self.net_client.session.update_obj_attributes(obj_id, {"Health": new_health})
                self.controller.sync_token_to_combat_panel(obj_id)
                if self.controller.calendar.track_health_change(obj_id, {"Health": new_health}):
                    self.controller.refresh_clocks()

        def _on_combat_health_attrs(self, obj_id: str, health_diff: dict[str, Any]) -> None:
            if obj_id in self.controller.scene.tokens:
                tok = self.controller.scene.tokens[obj_id]
                new_health = dict(tok.data.get("Health") or {})
                new_health.update(health_diff)
                tok.update_data({"Health": new_health})
                self.net_client.session.update_obj_attributes(obj_id, {"Health": new_health})
                self.controller.sync_token_to_combat_panel(obj_id)
                if self.controller.calendar.track_health_change(obj_id, {"Health": new_health}):
                    self.controller.refresh_clocks()

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
            self.controller.sync_token_to_combat_panel(obj_id)

        def _on_combat_clear_conditions(self, obj_id: str) -> None:
            if obj_id in self.controller.scene.tokens:
                self.controller.scene.tokens[obj_id].update_data({"StatusList": []})
            self.net_client.session.update_obj_attributes(obj_id, {"StatusList": []})
            self.controller.sync_token_to_combat_panel(obj_id)

        def _on_combat_locate(self, obj_id: str) -> None:
            self._on_clock_slot_activated(obj_id)

        def _on_combat_targets_changed(self, obj_id: str, targets: list[str]) -> None:
            if obj_id in self.controller.scene.tokens:
                self.controller.scene.tokens[obj_id].update_data({"Targets": list(targets)})
                self.controller.scene.refresh_targets()
            self.net_client.session.update_obj_attributes(obj_id, {"Targets": list(targets)})
            self.controller.sync_token_to_combat_panel(obj_id)

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
            lower_msg = msg.lower()
            if (
                msg.startswith("Disconnected:")
                or "error" in lower_msg
                or "failed" in lower_msg
                or "authentication required" in lower_msg
            ):
                self.controller.log_error(msg)
            else:
                self.controller.record_diagnostic("INFO", msg, auto_spawn=False)
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

        def _on_connection_lost(self, err: str) -> None:
            self._chat_history_synced_for_session = False
            self._dice_presets_synced_for_session = False
            self.statusBar().showMessage(f"Disconnected: {err}")
            if err:
                self.controller.log_error(f"Connection lost: {err}")

        def _active_server_profile(self) -> dict[str, Any]:
            prof_name = str(
                self.prefs.get("current_profile")
                or self.prefs.get("current_server")
                or "offline"
            )
            idx = find_server_index(self.prefs, prof_name)
            profiles = self.prefs.get("profiles", [])
            if 0 <= idx < len(profiles) and isinstance(profiles[idx], dict):
                return profiles[idx]
            return {}

        def sync_chat_history_from_server(self) -> bool:
            """Request chat/roll history from the server (`InitializeChatHistory` parity)."""
            if not self.net_client.session.is_ready():
                return False
            prof = self._active_server_profile()
            if bool(prof.get("suppress_chat", False)):
                return False
            raw_limit = prof.get("chat_limit", 500)
            try:
                chat_limit = int(500 if raw_limit is None else raw_limit)
            except (TypeError, ValueError):
                chat_limit = 500
            if chat_limit < 0:
                return False

            last_id = self.controller.chat_panel.history_manager.last_message_id()
            if last_id <= 0:
                if chat_limit > 0:
                    self.net_client.session.sync_chat(-chat_limit)
                    self.net_client.session.watch_operation(
                        f"Loading up to {chat_limit} chat messages"
                    )
                else:
                    self.net_client.session.sync_chat(0)
                    self.net_client.session.watch_operation(
                        "Loading full chat message history"
                    )
            else:
                self.net_client.session.sync_chat(last_id)
                self.net_client.session.watch_operation("Loading new chat messages")
            self._chat_history_synced_for_session = True
            return True

        def sync_dice_presets_from_server(self, for_user: str = "") -> bool:
            """Request saved die-roll presets from the server (`DR`) on connect or chat open."""
            if not self.net_client.session.is_ready():
                return False
            target_user = (
                for_user
                or self.controller.chat_panel.local_user
                or str(getattr(self.net_client.session, "username", "") or "")
            )
            self.net_client.session.query_dice_presets(for_user=target_user)
            if not for_user:
                self._dice_presets_synced_for_session = True
            return True

        def _on_chat_dock_visibility_changed(self, visible: bool) -> None:
            if not visible or not hasattr(self, "net_client"):
                return
            if not self.net_client.session.is_ready():
                return
            if (
                not self._chat_history_synced_for_session
                or self.controller.chat_panel.history_manager.last_message_id() <= 0
            ):
                self.sync_chat_history_from_server()
            if not self._dice_presets_synced_for_session:
                self.sync_dice_presets_from_server()

        def _on_login_successful(self) -> None:
            self._chat_history_synced_for_session = False
            self._dice_presets_synced_for_session = False
            user = str(getattr(self.net_client.session, "username", "") or "")
            if user:
                self.controller.chat_panel.set_identity(user)
                self._on_identity_changed(user, self.controller.chat_panel.is_gm)
            msg = (
                f"Connected to {self.net_client.session.host}:{self.net_client.session.port} "
                f"(Protocol {self.net_client.session.protocol})"
            )
            print(f"[gma-mapper] {msg}", flush=True)
            self.statusBar().showMessage(msg)
            self.net_client.session.subscribe()
            self.net_client.session.allow(["GMA-MARKUP", "DICE-COLOR-BOXES", "DICE-COLOR-LABELS"])
            self.net_client.session.sync()
            self.sync_chat_history_from_server()
            self.sync_dice_presets_from_server()

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
            self._update_toolbar_dynamic_states()

        def _on_toggle_toolbar_icons(self, checked: bool) -> None:
            self.prefs["toolbar_text"] = not bool(checked)
            self._refresh_toolbar_appearance()
            if self.prefs_path:
                save_preferences(self.prefs_path, self.prefs)
            self.statusBar().showMessage(
                "Toolbar display mode: Icons" if checked else "Toolbar display mode: Text labels"
            )

        def set_toolbar_display_mode(self, use_icons: bool) -> None:
            """Switch the command bar between icon buttons (`use_icons=True`) and text strings (`use_icons=False`)."""
            self.prefs["toolbar_text"] = not bool(use_icons)
            self._refresh_toolbar_appearance()

        def _refresh_toolbar_appearance(self) -> None:
            """Refresh toolbar icon size, theme, button display style (icons vs. text), and menu button visibility."""
            self.tools_toolbar.setStyleSheet(TOOLBAR_LIGHT_STYLESHEET)
            self.icon_catalog.configure(
                button_size=self.prefs.get("button_size", "small"),
                dark_mode=False,
                image_format=str(self.prefs.get("image_format", "png") or "png"),
            )
            px = self.icon_catalog.pixel_size()
            self.tools_toolbar.setIconSize(QSize(px, px))

            use_text = bool(self.prefs.get("toolbar_text", False))
            self.tools_toolbar.setToolButtonStyle(
                Qt.ToolButtonStyle.ToolButtonTextOnly
                if use_text
                else Qt.ToolButtonStyle.ToolButtonIconOnly
            )
            if hasattr(self, "act_toolbar_icons"):
                self.act_toolbar_icons.blockSignals(True)
                self.act_toolbar_icons.setChecked(not use_text)
                self.act_toolbar_icons.blockSignals(False)

            use_menu_btn = bool(self.prefs.get("menu_button", False))
            self.menuBar().setVisible(not use_menu_btn)
            if hasattr(self, "act_menu_button_widget"):
                self.act_menu_button_widget.setVisible(use_menu_btn)
            if hasattr(self, "menu_tool_button"):
                self.menu_tool_button.setIcon(self.icon_catalog.icon("menu"))
                self.menu_tool_button.setToolButtonStyle(
                    Qt.ToolButtonStyle.ToolButtonTextOnly
                    if use_text
                    else Qt.ToolButtonStyle.ToolButtonIconOnly
                )

            static_icon_map = {
                "nil": "play",
                "kill": "cut",
                "move": "shape_square_go",
                "clear": "clear",
                "clearp": "clear_players",
                "combat": "combat",
                "showhp": "heart",
                "ruler": "ruler",
                "griden": "snap_1",
                "chat": "die20",
                "iniclock": "clock",
                "tmrq": "tmrq",
                "zi": "zoom_in",
                "zo": "zoom_out",
                "refresh": "zoom",
                "saf": "saf",
                "polo": "arrow_refresh",
                "save": "save",
                "exit": "exit",
            }
            for btn_key, icon_name in static_icon_map.items():
                if btn_key in self.toolbar_actions:
                    self.toolbar_actions[btn_key].setIcon(self.icon_catalog.icon(icon_name))

            self._update_toolbar_dynamic_states()

        def _update_toolbar_dynamic_states(self) -> None:
            """Sync dynamic toolbar icons, labels, and tooltips (`mode`/`mode2`/`mode3`, fill, colors, stipple, snap, width, SaF)."""
            if not hasattr(self, "toolbar_actions") or not self.toolbar_actions:
                return

            # 1. Fill, Color Swatches, Stipple, Grid Snap, and Line Width
            fill_icon = "fill" if self.map_view.fill_enabled else "no_fill"
            self.act_fill_shapes.blockSignals(True)
            self.act_fill_shapes.setChecked(self.map_view.fill_enabled)
            self.act_fill_shapes.blockSignals(False)
            self.act_fill_shapes.setIcon(self.icon_catalog.icon(fill_icon))

            self.act_fill_col.setIcon(
                self.icon_catalog.color_swatch_icon("fill_color", self.map_view.draw_fill_color)
            )
            self.act_line_col.setIcon(
                self.icon_catalog.color_swatch_icon("outline_color", self.map_view.draw_line_color)
            )

            st_icon = stipple_icon_name(self.map_view.draw_stipple)
            self.act_cycle_stipple.setIcon(self.icon_catalog.icon(st_icon))
            self.act_cycle_stipple.setIconText(f"Pat:{self.map_view.draw_stipple or '100%'}")

            snap_idx = int(self.map_view.obj_snap) % 5
            self.act_cycle_snap.setIcon(self.icon_catalog.icon(f"snap_{snap_idx}"))
            self.act_cycle_snap.setIconText(f"Snap:{snap_idx}")

            width_idx = int(self.map_view.draw_width) % 10
            self.act_cycle_width.setIcon(self.icon_catalog.icon(f"width_{width_idx}"))
            self.act_cycle_width.setIconText(f"W:{width_idx}")

            # 2. Store-and-Forward (SaF) mode vs normal drawing mode
            draw_btn_icons = {
                "line": "line",
                "rect": "rect",
                "poly": "poly",
                "circ": "circ",
                "arc": "arc",
                "text": "textfield_add",
                "stamp": "stamp",
                "aoe": "wand",
                "aoebound": "wandbound",
            }
            if self._saf_mode:
                blank_ic = self.icon_catalog.icon("blank")
                for bkey in draw_btn_icons:
                    if bkey in self.toolbar_actions:
                        self.toolbar_actions[bkey].setIcon(blank_ic)
                        self.toolbar_actions[bkey].setEnabled(False)
                for m_act, m_lbl in ((self.act_mode1, "Opt1"), (self.act_mode2, "Opt2"), (self.act_mode3, "Dash")):
                    m_act.setIcon(blank_ic)
                    m_act.setIconText(m_lbl)
                    m_act.setToolTip("")
                    m_act.setEnabled(False)
                self.toolbar_actions["load"].setIcon(self.icon_catalog.icon("saf_open"))
                self.toolbar_actions["merge"].setIcon(self.icon_catalog.icon("saf_merge"))
                self.toolbar_actions["unload"].setIcon(self.icon_catalog.icon("saf_unload"))
                self.act_saf_sync.setIcon(self.icon_catalog.icon("saf_group_go"))
                self.act_saf_sync.setToolTip("Push this map to all other clients (USE THIS WITH CARE)")
                self.act_saf_sync.setEnabled(True)
            else:
                for bkey, ic_name in draw_btn_icons.items():
                    if bkey in self.toolbar_actions:
                        self.toolbar_actions[bkey].setIcon(self.icon_catalog.icon(ic_name))
                        self.toolbar_actions[bkey].setEnabled(True)
                m1, m2, m3 = mode_slot_specs(
                    active_tool=self.map_view.active_tool,
                    draw_join=self.map_view.draw_join,
                    draw_aoe_shape=self.map_view.draw_aoe_shape,
                    draw_arc_mode=self.map_view.draw_arc_mode,
                    draw_arrow=self.map_view.draw_arrow,
                    draw_spline=self.map_view.draw_spline,
                    draw_aoe_spread=self.map_view.draw_aoe_spread,
                    draw_text_anchor=self.map_view.draw_text_anchor,
                    draw_dash=self.map_view.draw_dash,
                )
                for act_slot, (ic_name, short_lbl, tip, enabled) in (
                    (self.act_mode1, m1),
                    (self.act_mode2, m2),
                    (self.act_mode3, m3),
                ):
                    act_slot.setIcon(self.icon_catalog.icon(ic_name))
                    act_slot.setIconText(short_lbl)
                    act_slot.setToolTip(tip)
                    act_slot.setEnabled(enabled)
                self.toolbar_actions["load"].setIcon(self.icon_catalog.icon("open"))
                self.toolbar_actions["merge"].setIcon(self.icon_catalog.icon("merge"))
                self.toolbar_actions["unload"].setIcon(self.icon_catalog.icon("unload"))
                self.act_saf_sync.setIcon(self.icon_catalog.icon("blank"))
                self.act_saf_sync.setToolTip("")
                self.act_saf_sync.setEnabled(False)

        def _on_toolbar_mode1(self) -> None:
            self.map_view.trigger_alt_1()

        def _on_toolbar_mode2(self) -> None:
            if self.map_view.active_tool == "line":
                self.map_view.trigger_alt_1()
            else:
                self.map_view.trigger_alt_2()

        def _on_toolbar_mode3(self) -> None:
            self.map_view.trigger_alt_3()

        def _on_toggle_fill_shapes(self, checked: bool) -> None:
            self.map_view.fill_enabled = bool(checked)
            self._update_toolbar_dynamic_states()
            self.statusBar().showMessage(f"Fill shapes: {'ON' if checked else 'OFF'}")

        def _set_stipple(self, stipple: str) -> None:
            self.map_view.draw_stipple = stipple
            if stipple in self._stipple_actions:
                self._stipple_actions[stipple].setChecked(True)
            self._update_toolbar_dynamic_states()
            self.statusBar().showMessage(f"Fill pattern: {stipple or 'solid (100%)'}")

        def _on_cycle_stipple(self) -> None:
            choices = [st_val for st_val, _ in STIPPLE_CHOICES]
            next_st = cycle_in_list(self.map_view.draw_stipple, choices)
            self._set_stipple(next_st)

        def _set_obj_snap(self, snap: int) -> None:
            self.map_view.obj_snap = int(snap) % 5
            if self.map_view.obj_snap in self._snap_actions:
                self._snap_actions[self.map_view.obj_snap].setChecked(True)
            self._update_toolbar_dynamic_states()
            self.statusBar().showMessage(f"Grid snap set to {self.map_view.obj_snap}")

        def _on_cycle_snap(self) -> None:
            self._set_obj_snap((int(self.map_view.obj_snap) + 1) % 5)

        def _set_draw_width(self, width: int) -> None:
            self.map_view.draw_width = int(width) % 10
            if self.map_view.draw_width in self._width_actions:
                self._width_actions[self.map_view.draw_width].setChecked(True)
            self._update_toolbar_dynamic_states()
            self.statusBar().showMessage(f"Line width set to {self.map_view.draw_width}")

        def _on_cycle_width(self) -> None:
            self._set_draw_width((int(self.map_view.draw_width) + 1) % 10)

        def _on_toggle_chat_dock(self, _checked: bool = False) -> None:
            if self.chat_dock.isHidden():
                self.chat_dock.show()
                self.chat_dock.raise_()
            else:
                self.chat_dock.hide()

        def _sync_role_ui(self) -> None:
            is_gm = bool(self.controller.chat_panel.is_gm)
            if hasattr(self, "clock_dock"):
                if is_gm:
                    layout = self.window_layout
                    if isinstance(layout, dict) and bool(layout.get("saved", False)):
                        clock_vis = bool(
                            layout.get("docks", {}).get("clock", {}).get("visible", True)
                        )
                    else:
                        clock_vis = True
                    self.clock_dock.setVisible(clock_vis)
                else:
                    self.clock_dock.setVisible(False)
            if hasattr(self, "act_view_clock_dock"):
                self.act_view_clock_dock.setVisible(is_gm)
                self.act_view_clock_dock.setEnabled(is_gm)
            if hasattr(self, "act_edit_sys_presets"):
                self.act_edit_sys_presets.setEnabled(is_gm)
            if hasattr(self, "act_edit_presets"):
                user = self.controller.chat_panel.local_user
                self.act_edit_presets.setText(
                    f"Edit &Die Roll Presets for {user}..." if user else "Edit &Die Roll Presets..."
                )

        def _on_identity_changed(self, _user: str, _is_gm: bool) -> None:
            self._sync_role_ui()

        def show_player_clock_window(self) -> PlayerClockWindow:
            """Open or raise the standalone read-only 'Game Clock' window (`display_initiative_clock`)."""
            win = self.controller.player_clock_window
            if win is None:
                win = PlayerClockWindow(
                    self.controller.calendar,
                    prefs=self.prefs,
                    icon_catalog=self.icon_catalog,
                    parent=self,
                )
                self.controller.player_clock_window = win
            win.my_names = list(self.controller.clock_panel.my_names)
            win.timer_scope = self.controller.clock_panel.timer_scope
            win.sync_timers(self.controller.clock_panel.timers)
            win.apply_styles(self.prefs, bool(self.prefs.get("dark", False)))
            win.refresh()
            win.show()
            detach_window_owner(win)
            win.raise_()
            win.activateWindow()
            return win

        def _on_toggle_clock_dock(self, _checked: bool = False) -> None:
            if not self.controller.chat_panel.is_gm:
                win = self.controller.player_clock_window
                if win is None or win.isHidden():
                    self.show_player_clock_window()
                else:
                    win.hide()
                return
            if self.clock_dock.isHidden():
                self.clock_dock.show()
                self.clock_dock.raise_()
            else:
                self.clock_dock.hide()

        def _on_toggle_saf_mode(self, checked: bool) -> None:
            self._saf_mode = bool(checked)
            if self._saf_mode:
                self.map_view.set_tool_mode("pointer")
            self._update_toolbar_dynamic_states()
            self.statusBar().showMessage(
                f"Store-and-forward mode {'enabled' if self._saf_mode else 'disabled'}"
            )

        def _on_saf_push_sync(self) -> None:
            self.net_client.session.sync()
            self.statusBar().showMessage("Synchronized map state with server")

        def _on_sync_from_server(self) -> None:
            self.net_client.session.sync()
            self.statusBar().showMessage("Requested game state sync from server")

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
                self._update_toolbar_dynamic_states()
                self.statusBar().showMessage(f"Fill color set to {col.name()}")

        def _on_choose_line_color(self) -> None:
            col = QColorDialog.getColor(
                QColor(self.map_view.draw_line_color or "black"),
                self,
                "Choose Outline Color",
            )
            if col.isValid():
                self.map_view.draw_line_color = col.name()
                self._update_toolbar_dynamic_states()
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

        def _sync_combat_mode_action(self, enabled: bool) -> None:
            if hasattr(self, "act_combat_mode"):
                self.act_combat_mode.blockSignals(True)
                self.act_combat_mode.setChecked(bool(enabled))
                self.act_combat_mode.blockSignals(False)

        def _on_toggle_combat_mode(self, checked: bool) -> None:
            enabled = bool(checked)
            self._sync_combat_mode_action(enabled)
            self.controller.calendar.set_time(combat_mode=enabled)
            self.controller.scene.set_combat_state(enabled, self.controller.scene.active_actor_id)
            self.controller.update_ondeck_and_audio()
            self.controller.refresh_clocks()
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
                try:
                    count = self.controller.save_map_file(path)
                    self.statusBar().showMessage(
                        f"Saved {count} map object(s) to {Path(path).name}"
                    )
                except (OSError, ValueError) as exc:
                    msg = f"Error saving map: {exc}"
                    self.statusBar().showMessage(msg)
                    self.controller.log_error(msg)

        def _on_open_dice(self) -> None:
            self.controller.chat_panel.prompt_import_presets_from_file()

        def _on_save_dice(self) -> None:
            path, _ = QFileDialog.getSaveFileName(self, "Save Dice Presets", "", "Dice Files (*.dice)")
            if path:
                save_dice_presets_to_file(path, self.controller.chat_panel.bank.user_presets)

        def _on_save_presets_to_server(
            self,
            plist: list[dict[str, Any]],
            is_glob: bool,
            for_user: str,
            append_mode: bool = False,
            panel: ChatDicePanel | None = None,
        ) -> None:
            target_panel = panel or self.controller.chat_panel
            target_user = "" if is_glob else (for_user or self.controller.chat_panel.local_user)
            if not self.net_client.session.is_ready():
                warn = "Not connected to server — die presets updated locally only and NOT saved to server."
                self.statusBar().showMessage(warn)
                target_panel.append_notice(warn)
                return
            self.net_client.session.define_dice_presets(
                plist,
                append_mode=append_mode,
                for_user=target_user,
                globals_only=is_glob,
            )
            verb = "Added" if append_mode else "Saved"
            scope = "system" if is_glob else (target_user or "user")
            self.statusBar().showMessage(f"{verb} {len(plist)} {scope} die preset(s) to server.")

        def _on_refresh_presets_from_server(self, for_user: str = "") -> None:
            target_user = for_user or self.controller.chat_panel.local_user
            if not self.net_client.session.is_ready():
                self.statusBar().showMessage("Not connected to server — cannot refresh die presets.")
                return
            self.net_client.session.query_dice_presets(for_user=target_user)

        def _wire_chat_panel_signals(self, panel: ChatDicePanel) -> None:
            panel.send_roll_ex_requested.connect(
                lambda spec, recips, to_all, to_gm, req_id, p=panel: self.net_client.session.roll_dice(
                    spec,
                    recipients=recips,
                    to_all=to_all,
                    blind_to_gm=to_gm,
                    rid=req_id,
                    for_user=p.for_user,
                )
            )
            panel.send_chat_ex_requested.connect(
                lambda text, recips, to_all, to_gm, markup, pin: self.net_client.session.chat_message(
                    text,
                    recipients=recips,
                    to_all=to_all,
                    to_gm=to_gm,
                    markup=markup,
                    pinned=pin,
                )
            )
            panel.save_presets_requested.connect(
                lambda plist, is_glob, for_user, p=panel: self._on_save_presets_to_server(
                    plist, is_glob, for_user, append_mode=False, panel=p
                )
            )
            panel.append_presets_requested.connect(
                lambda plist, is_glob, for_user, p=panel: self._on_save_presets_to_server(
                    plist, is_glob, for_user, append_mode=True, panel=p
                )
            )
            panel.refresh_presets_requested.connect(self._on_refresh_presets_from_server)
            panel.refresh_peers_requested.connect(self.net_client.session.query_peers)
            panel.delete_message_requested.connect(
                lambda msg_id: self.net_client.session.clear_chat_list(False, [msg_id])
            )

        def _on_table_roll_reply(self, reply: dict[str, Any]) -> None:
            self.net_client.session.chat_message(
                str(reply.get("text", "")),
                recipients=list(reply.get("recipients") or []),
                to_all=bool(reply.get("to_all", True)),
                to_gm=bool(reply.get("to_gm", False)),
                markup=bool(reply.get("markup", False)),
            )

        def _on_manage_delegates(self) -> None:
            dlg = ManageDelegatesDialog(
                current_delegates=self.controller.delegates,
                known_peers=self.controller.peer_names,
                parent=self,
            )
            if dlg.exec():
                self.controller.delegates = dlg.delegates()
                self.net_client.session.define_dice_delegates(
                    self.controller.chat_panel.local_user,
                    self.controller.delegates,
                )

        def _rebuild_delegate_for_menu(self) -> None:
            if not hasattr(self, "delegate_for_menu"):
                return
            self.delegate_for_menu.clear()
            if not self.controller.delegate_for:
                act_empty = QAction("(No delegated players)", self.delegate_for_menu)
                act_empty.setEnabled(False)
                self.delegate_for_menu.addAction(act_empty)
                return
            for user in self.controller.delegate_for:
                act = QAction(f"Die Rolls for {user}...", self.delegate_for_menu)
                act.triggered.connect(
                    lambda _c=False, u=user: self._open_delegated_die_roller(u)
                )
                self.delegate_for_menu.addAction(act)

        def _open_delegated_die_roller(self, for_user: str) -> None:
            if for_user in self._delegated_dialogs:
                dlg = self._delegated_dialogs[for_user]
                dlg.show()
                detach_window_owner(dlg)
                dlg.raise_()
                return
            dlg = DelegatedDieRollerDialog(
                for_user=for_user,
                local_user=self.controller.chat_panel.local_user,
                prefs=self.prefs,
                shared_gvar_state=self.controller.shared_gvar_state,
                parent=self,
            )
            dlg.panel.target_context_provider = self.controller.target_context_snapshot
            dlg.panel.set_system_presets(self.controller.chat_panel.bank.system_presets)
            if for_user in self.controller.banks_by_tkey:
                dlg.panel.set_user_presets(self.controller.banks_by_tkey[for_user].user_presets)
            self.controller.banks_by_tkey[for_user] = dlg.panel.bank
            self.controller.delegated_panels[for_user] = dlg.panel
            self._wire_chat_panel_signals(dlg.panel)
            self._delegated_dialogs[for_user] = dlg
            self.net_client.session.query_dice_presets(for_user=for_user)
            dlg.show()
            detach_window_owner(dlg)

        def _on_show_about_mapper(self) -> AboutMapperDialog:
            dlg = AboutMapperDialog(self.net_client.session, self)
            dlg.show()
            return dlg

        def _on_show_dice_syntax_help(self) -> None:
            dlg = DiceSyntaxHelpDialog(self)
            dlg.show()

        def _on_show_dice_modifier_help(self) -> None:
            dlg = DiceModifierHelpDialog(self)
            dlg.show()

        def _on_show_markup_syntax_help(self) -> MarkupSyntaxHelpDialog:
            dlg = MarkupSyntaxHelpDialog(self)
            dlg.show()
            return dlg

        def _rebuild_server_profile_menu(self) -> None:
            if not hasattr(self, "server_profile_menu"):
                return
            self.server_profile_menu.clear()
            prof_group = QActionGroup(self.server_profile_menu)
            prof_group.setExclusive(True)

            cur_name = str(
                self.prefs.get("current_profile")
                or self.prefs.get("current_server")
                or "offline"
            )
            saw_offline = False
            for prof in self.prefs.get("profiles", []):
                if not isinstance(prof, dict):
                    continue
                name = str(prof.get("name") or "").strip()
                if not name:
                    continue
                if name == "offline":
                    saw_offline = True
                safe_name = name.replace("&", "&&")
                host = str(prof.get("host") or "").strip()
                port = int(prof.get("port") or 0)
                label = f"{safe_name} ({host}:{port})" if host and port else f"{safe_name} (offline)"
                act = QAction(label, self.server_profile_menu)
                act.setCheckable(True)
                act.setChecked(name == cur_name)
                act.triggered.connect(
                    lambda _c=False, p=name: self.switch_server_profile(p)
                )
                prof_group.addAction(act)
                self.server_profile_menu.addAction(act)

            if not saw_offline:
                act_off = QAction("Offline", self.server_profile_menu)
                act_off.setCheckable(True)
                act_off.setChecked(cur_name == "offline")
                act_off.triggered.connect(
                    lambda _c=False: self.switch_server_profile("offline")
                )
                prof_group.addAction(act_off)
                self.server_profile_menu.addAction(act_off)

            self.server_profile_menu.addSeparator()
            self.act_reconnect_server = QAction(
                "&Reconnect to Current Server", self.server_profile_menu
            )
            self.act_reconnect_server.triggered.connect(self.reconnect_current_server)
            self.server_profile_menu.addAction(self.act_reconnect_server)

            self.act_disconnect_server = QAction(
                "&Disconnect (Go Offline)", self.server_profile_menu
            )
            self.act_disconnect_server.triggered.connect(self.disconnect_server)
            self.server_profile_menu.addAction(self.act_disconnect_server)

        def switch_server_profile(self, profile_name: str) -> bool:
            """Switch active server profile in preferences, persist, and reconnect/hang up."""
            old_profile = str(
                self.prefs.get("current_profile")
                or self.prefs.get("current_server")
                or "offline"
            )
            self._chat_history_synced_for_session = False
            self._dice_presets_synced_for_session = False
            if profile_name != old_profile:
                if hasattr(self.controller.chat_panel, "clear_chat_history"):
                    self.controller.chat_panel.clear_chat_history(target=0, do_all=True)
                if hasattr(self.controller.chat_panel, "set_presets"):
                    self.controller.chat_panel.set_presets([])
                if hasattr(self.controller.chat_panel, "set_system_presets"):
                    self.controller.chat_panel.set_system_presets([])
            self.prefs["current_profile"] = profile_name
            self.prefs["current_server"] = profile_name
            self.controller.apply_preferences(self.prefs)
            if self.prefs_path:
                save_preferences(self.prefs_path, self.prefs)
            self._rebuild_server_profile_menu()
            self.net_client.hangup()
            host, port, _u, _p = self._configured_server_tuple(self.prefs)
            if host and port:
                self.connect_to_configured_server()
            else:
                self.statusBar().showMessage("Switched to offline profile.")
            return True

        def reconnect_current_server(self) -> bool:
            """Drop any active socket and dial the currently configured server profile."""
            host, port, _u, _p = self._configured_server_tuple(self.prefs)
            if not (host and port):
                self.statusBar().showMessage(
                    "Current profile is offline — no server configured."
                )
                return False
            self._chat_history_synced_for_session = False
            self._dice_presets_synced_for_session = False
            self.net_client.hangup()
            self.connect_to_configured_server()
            return True

        def disconnect_server(self) -> None:
            """Disconnect from the GMA server and enter offline state."""
            self._chat_history_synced_for_session = False
            self._dice_presets_synced_for_session = False
            self.net_client.hangup()
            self.controller.log_info("Disconnected from server.")
            self.statusBar().showMessage("Disconnected (offline).")

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
            self.net_client.session.debug_cb = self.controller.log_protocol

        def _on_preferences(self) -> None:
            old_srv = self._configured_server_tuple(self.prefs)
            dlg = PreferencesDialog(self.prefs, self)
            if dlg.exec():
                self.prefs = dlg.prefs
                self.controller.apply_preferences(self.prefs)
                self._refresh_toolbar_appearance()
                self._apply_debug_protocol()
                if self._debug_window is not None:
                    self._debug_window.apply_theme(bool(self.prefs.get("dark", False)))
                    self._debug_window.set_show_protocol(self.controller.debug_proto)
                if self._distance_dialog is not None:
                    self._distance_dialog.apply_theme(
                        self.prefs, bool(self.prefs.get("dark", False))
                    )
                self._rebuild_server_profile_menu()
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

        def _commit_aka_selection(self, names: list[str], not_playing: bool) -> None:
            self.controller.apply_local_aka(names, not_playing=not_playing)
            if self.net_client.session.is_ready():
                self.net_client.session.aka(names, not_playing=not_playing)
                if not_playing:
                    msg = "Declared not playing any character."
                elif names:
                    msg = f"Playing as: {', '.join(names)}"
                else:
                    msg = "Cleared character selection (using login username)."
                self.statusBar().showMessage(msg)
            else:
                warn = "Not connected to server — character selection updated locally only."
                self.statusBar().showMessage(warn)
                self.controller.chat_panel.append_notice(warn)

        def _on_select_aka(self, auto_prompt: bool = False) -> bool:
            dlg = SelectAKADialog(
                known_pcs=self.controller.known_pc_names(),
                current_aka=self.controller.local_aka,
                local_user=self.controller.chat_panel.local_user,
                im_not_playing=self.controller.im_not_playing,
                show_suppress_option=auto_prompt,
                parent=self,
            )
            if dlg.exec():
                if auto_prompt and dlg.suppress_session_prompt():
                    self.controller.suppress_aka = True
                self._commit_aka_selection(dlg.selected_names(), dlg.not_playing())
                return True
            return False

        def _on_reset_chat_history(self, load_qty: int) -> None:
            self.controller.chat_panel.clear_chat_history(target=0, do_all=False)
            if load_qty < 0:
                msg = "Cleared local chat history."
                self.controller.log_info(msg)
                self.statusBar().showMessage(msg)
                return
            if not self.net_client.session.is_ready():
                msg = "Cleared local chat history (not connected to server to reload messages)."
                self.controller.log_info(msg)
                self.statusBar().showMessage(msg)
                return
            target = -load_qty if load_qty > 0 else 0
            desc = (
                f"Loading up to {load_qty} chat messages"
                if load_qty > 0
                else "Loading full chat message history"
            )
            self.net_client.session.sync_chat(target)
            self.net_client.session.watch_operation(desc)
            self.controller.log_info(desc)
            self.statusBar().showMessage(desc)

        def _on_clear_pinned_chats(self) -> int:
            count = self.controller.chat_panel.clear_pinned_messages()
            msg = f"Cleared {count} pinned chat message(s)."
            self.controller.log_info(msg)
            self.statusBar().showMessage(msg)
            return count

        def _on_cleanup_image_cache(self, days_old: int | str) -> tuple[int, int, int]:
            deleted, total, queries = self.cache.cleanup_image_cache(days_old)
            requeried = 0
            if days_old == "-update" and self.net_client.session.is_ready():
                for img_name, img_zoom in queries:
                    self.net_client.session.query_image(img_name, img_zoom)
                requeried = len(queries)
            msg = f"Removed {deleted} of {total} cached image file(s)"
            if requeried:
                msg += f" and requested {requeried} refresh(es)"
            msg += "."
            self.controller.log_info(msg)
            self.statusBar().showMessage(msg)
            return (deleted, total, requeried)

        def _on_retry_failed_images(self) -> int:
            cleared = len(
                self.cache.forbidden_urls | self.net_client.session.forbidden_urls
            )
            self.cache.forbidden_urls.clear()
            self.net_client.session.forbidden_urls.clear()
            msg = f"Cleared {cleared} failed image/asset retrieval block(s)."
            self.controller.log_info(msg)
            self.statusBar().showMessage(msg)
            return cleared

        def _send_server_ping(self, slot_idx: int, origin_us: int) -> bool:
            if not self.net_client.session.is_ready():
                return False
            self.net_client.session.echo(
                s="__spt__", i=slot_idx, o={"origin": str(origin_us)}
            )
            return True

        def _on_echo_received(self, payload: dict[str, Any]) -> None:
            if self._ping_dialog is not None and payload.get("s") == "__spt__":
                self._ping_dialog.handle_echo_reply(payload)

        def _on_server_ping_test(self) -> ServerPingDialog:
            if self._ping_dialog is not None:
                self._ping_dialog.show()
                self._ping_dialog.raise_()
                return self._ping_dialog
            dlg = ServerPingDialog(send_ping_cb=self._send_server_ping, parent=self)
            self._ping_dialog = dlg
            dlg.finished.connect(lambda _res: setattr(self, "_ping_dialog", None))
            dlg.show()
            return dlg

        def _close_distance_dialog(self) -> None:
            if self._distance_dialog is not None:
                prev = self._distance_dialog
                self._distance_dialog = None
                prev.close()

        def _on_distance_dialog_closed(self, dlg: DistanceDialog) -> None:
            if self._distance_dialog is dlg:
                self._distance_dialog = None

        def _open_distance_dialog(
            self,
            title: str,
            rows_provider: Any,
            allow_elevation: bool,
            initial_z_ft: float = 0.0,
        ) -> DistanceDialog:
            self._close_distance_dialog()
            scene = self.controller.scene
            dlg = DistanceDialog(
                title=title,
                rows_provider=rows_provider,
                apply_tracers_cb=(
                    scene.set_distance_tracers
                    if hasattr(scene, "set_distance_tracers")
                    else None
                ),
                clear_tracers_cb=(
                    scene.clear_distance_tracers
                    if hasattr(scene, "clear_distance_tracers")
                    else None
                ),
                allow_elevation=allow_elevation,
                initial_z_ft=initial_z_ft,
                prefs=self.prefs,
                dark_mode=bool(self.prefs.get("dark", False)),
                window_icon=self.icon_catalog.app_window_icon(),
            )
            dlg.closed.connect(lambda d=dlg: self._on_distance_dialog_closed(d))
            self._distance_dialog = dlg
            dlg.show()
            detach_window_owner(dlg)
            dlg.raise_()
            return dlg

        def show_distance_from_grid(
            self, gx: int, gy: int, z_ft: float = 0.0
        ) -> DistanceDialog:
            """Display the Distance from Cell dialog and yellow tracers (`DistanceFromGrid`)."""
            label = grid_coord_label(gx, gy)
            scene = self.controller.scene

            def _rows(elev_ft: float) -> list[Any]:
                creatures = {cid: tok.data for cid, tok in scene.creatures.items()}
                return compute_distances_from_grid(
                    gx,
                    gy,
                    elev_ft,
                    creatures,
                    is_gm=bool(self.controller.chat_panel.is_gm),
                )

            return self._open_distance_dialog(
                title=f"Distance from grid point {label}",
                rows_provider=_rows,
                allow_elevation=True,
                initial_z_ft=z_ft,
            )

        def show_distance_from_mob(self, mob_id: str) -> DistanceDialog | None:
            """Display the Distance from Icon dialog and yellow tracers (`DistanceFromMob`)."""
            scene = self.controller.scene
            tok = scene.creatures.get(mob_id)
            if tok is None:
                return None
            is_gm = bool(self.controller.chat_panel.is_gm)
            if tok.data.get("Hidden") and not is_gm:
                return None

            raw_name = str(tok.data.get("Name") or mob_id)

            def _rows(_elev_ft: float) -> list[Any]:
                creatures = {cid: t.data for cid, t in scene.creatures.items()}
                return (
                    compute_distances_from_mob(
                        mob_id,
                        creatures,
                        is_gm=bool(self.controller.chat_panel.is_gm),
                    )
                    or []
                )

            return self._open_distance_dialog(
                title=f"Distance from {raw_name}",
                rows_provider=_rows,
                allow_elevation=False,
            )

        def ensure_diagnostic_window(self) -> DiagnosticWindow:
            """Create (if needed) the modeless ``DiagnosticWindow`` and return it."""
            if self._debug_window is None:
                dlg = DiagnosticWindow(
                    entries_provider=lambda: self.controller.diagnostic_log,
                    save_cb=self._on_save_diagnostic_messages,
                    clear_cb=self.clear_diagnostic_messages,
                    dark_mode=bool(self.prefs.get("dark", False)),
                    show_protocol=self.controller.debug_proto,
                    max_lines=self.controller.max_diagnostic_lines,
                    window_icon=self.icon_catalog.app_window_icon(),
                )
                self._debug_window = dlg
            return self._debug_window

        def show_diagnostic_window(self, raise_window: bool = True) -> DiagnosticWindow:
            """Show (and optionally raise) the modeless ``DiagnosticWindow``."""
            dlg = self.ensure_diagnostic_window()
            if not dlg.isVisible():
                dlg.show()
                detach_window_owner(dlg)
            if raise_window:
                dlg.raise_()
            return dlg

        def clear_diagnostic_messages(self) -> int:
            """Clear all buffered and displayed diagnostic messages."""
            return self.controller.clear_diagnostics()

        def _on_diagnostic_recorded(self, tag: str, line: str, auto_spawn: bool) -> None:
            if self._debug_window is None:
                if auto_spawn:
                    # ensure_diagnostic_window() hydrates from diagnostic_log (which already has `line`).
                    self.show_diagnostic_window(raise_window=False)
                return
            if auto_spawn and tag == "PROTOCOL" and not self._debug_window.show_protocol:
                # set_show_protocol() re-renders from diagnostic_log (which already has `line`).
                self._debug_window.set_show_protocol(True)
                appended = True
            else:
                appended = self._debug_window.append_entry(tag, line)
            if auto_spawn and appended and not self._debug_window.isVisible():
                self.show_diagnostic_window(raise_window=False)

        def _on_diagnostics_cleared(self) -> None:
            if self._debug_window is not None:
                self._debug_window.clear_entries()

        def _on_async_diagnostic_event(self, tag: str, msg: str, auto_spawn: bool) -> None:
            self.controller.record_diagnostic(tag, msg, auto_spawn=auto_spawn)

        def save_diagnostics_to_file(self, path: str | Path) -> int:
            """Write buffered diagnostic log entries to `path` and return line count."""
            content = self.controller.format_diagnostic_text()
            Path(path).write_text(
                (content + "\n") if content else "",
                encoding="utf-8",
            )
            return len(self.controller.diagnostic_log)

        def _on_save_diagnostic_messages(self) -> None:
            if not self.controller.diagnostic_log:
                QMessageBox.information(
                    self,
                    "No Diagnostics to Save",
                    "There are no diagnostic messages to save yet.",
                )
                return
            path, _ = QFileDialog.getSaveFileName(
                self,
                "Save Diagnostic Messages As...",
                "",
                "Text Files (*.txt);;All Files (*)",
            )
            if not path:
                return
            try:
                count = self.save_diagnostics_to_file(path)
                self.statusBar().showMessage(
                    f"Saved {count} diagnostic line(s) to {Path(path).name}."
                )
            except OSError as exc:
                QMessageBox.critical(
                    self,
                    "Unable to Open File",
                    f'Unable to write to "{path}": {exc}',
                )

        def _dock_area_to_name(self, area: Qt.DockWidgetArea, fallback: str) -> str:
            area_map = {
                Qt.DockWidgetArea.LeftDockWidgetArea: "left",
                Qt.DockWidgetArea.RightDockWidgetArea: "right",
                Qt.DockWidgetArea.TopDockWidgetArea: "top",
                Qt.DockWidgetArea.BottomDockWidgetArea: "bottom",
            }
            return area_map.get(area, fallback)

        def _name_to_dock_area(self, name: str, fallback: str = "right") -> Qt.DockWidgetArea:
            name_map = {
                "left": Qt.DockWidgetArea.LeftDockWidgetArea,
                "right": Qt.DockWidgetArea.RightDockWidgetArea,
                "top": Qt.DockWidgetArea.TopDockWidgetArea,
                "bottom": Qt.DockWidgetArea.BottomDockWidgetArea,
            }
            return name_map.get(str(name).strip().lower(), name_map[fallback])

        def _layout_dock_specs(self) -> tuple[tuple[str, IndependentDockWidget, str], ...]:
            return (
                ("clock", self.clock_dock, "right"),
                ("combat", self.combat_dock, "right"),
                ("chat", self.chat_dock, "bottom"),
            )

        def _apply_dock_layout(
            self,
            key: str,
            dock: IndependentDockWidget,
            cfg: dict[str, Any],
            default_area: str,
        ) -> None:
            target_area = self._name_to_dock_area(
                str(cfg.get("area") or default_area), default_area
            )
            if self.dockWidgetArea(dock) != target_area:
                self.addDockWidget(target_area, dock)
            is_floating = bool(cfg.get("floating", False))
            dock.setFloating(is_floating)

            geom = cfg.get("geometry")
            if isinstance(geom, dict):
                gx = int(geom.get("x", 0) or 0)
                gy = int(geom.get("y", 0) or 0)
                gw = int(geom.get("width", 0) or 0)
                gh = int(geom.get("height", 0) or 0)
                if gw > 0 and gh > 0:
                    if is_floating:
                        dock.setGeometry(gx, gy, gw, gh)
                    else:
                        horizontal = target_area in (
                            Qt.DockWidgetArea.LeftDockWidgetArea,
                            Qt.DockWidgetArea.RightDockWidgetArea,
                        )
                        orient = (
                            Qt.Orientation.Horizontal
                            if horizontal
                            else Qt.Orientation.Vertical
                        )
                        self.resizeDocks([dock], [gw if horizontal else gh], orient)

            if key == "clock" and not bool(self.controller.chat_panel.is_gm):
                dock.setVisible(False)
            else:
                dock.setVisible(bool(cfg.get("visible", True)))

        def save_window_layout(self, persist: bool = True) -> dict[str, Any]:
            """Capture main window and dock states/geometries into `window_layout.json`."""
            prev = self.window_layout
            if not isinstance(prev, dict):
                prev = default_window_layout()
            prev_docks = prev.get("docks") if isinstance(prev.get("docks"), dict) else {}

            rect = (
                self.normalGeometry()
                if self.isMaximized() and self.normalGeometry().isValid()
                else self.geometry()
            )
            docks_out: dict[str, dict[str, Any]] = {}
            is_gm = bool(self.controller.chat_panel.is_gm)
            for key, dock, default_area in self._layout_dock_specs():
                prev_dock = prev_docks.get(key) if isinstance(prev_docks.get(key), dict) else {}
                prev_area = str(prev_dock.get("area") or default_area)
                area_name = self._dock_area_to_name(self.dockWidgetArea(dock), prev_area)
                vis = (
                    bool(prev_dock.get("visible", True))
                    if (key == "clock" and not is_gm)
                    else (not dock.isHidden())
                )
                g = dock.geometry()
                docks_out[key] = {
                    "floating": bool(dock.isFloating()),
                    "area": area_name,
                    "visible": vis,
                    "geometry": {
                        "x": int(g.x()),
                        "y": int(g.y()),
                        "width": int(g.width()),
                        "height": int(g.height()),
                    },
                }

            layout: dict[str, Any] = {
                "saved": True,
                "main_geometry": bytes(self.saveGeometry().toBase64()).decode("ascii"),
                "main_state": bytes(self.saveState().toBase64()).decode("ascii"),
                "main_window": {
                    "x": int(rect.x()),
                    "y": int(rect.y()),
                    "width": int(rect.width()),
                    "height": int(rect.height()),
                    "maximized": bool(self.isMaximized()),
                },
                "docks": docks_out,
            }
            self.window_layout = layout
            if persist and self.window_layout_path:
                save_window_layout_file(self.window_layout_path, layout)
            return layout

        def restore_window_layout(self, layout: dict[str, Any] | None = None) -> bool:
            """Restore previously saved main window and dock layout from `window_layout.json`."""
            cfg = layout if isinstance(layout, dict) else self.window_layout
            if not isinstance(cfg, dict) or not bool(cfg.get("saved", False)):
                return False

            main_geom = str(cfg.get("main_geometry") or "")
            if main_geom:
                self.restoreGeometry(QByteArray.fromBase64(main_geom.encode("ascii")))

            mw = cfg.get("main_window")
            if isinstance(mw, dict):
                mw_w = int(mw.get("width", 0) or 0)
                mw_h = int(mw.get("height", 0) or 0)
                mw_x = int(mw.get("x", 0) or 0)
                mw_y = int(mw.get("y", 0) or 0)
                mw_max = bool(mw.get("maximized", False))
                if mw_max:
                    self.setWindowState(self.windowState() | Qt.WindowState.WindowMaximized)
                elif mw_w > 0 and mw_h > 0:
                    self.resize(mw_w, mw_h)
                    if mw_x != 0 or mw_y != 0:
                        self.move(mw_x, mw_y)

            main_state = str(cfg.get("main_state") or "")
            if main_state:
                self.restoreState(QByteArray.fromBase64(main_state.encode("ascii")))

            docks_cfg = cfg.get("docks")
            docks_dict = docks_cfg if isinstance(docks_cfg, dict) else {}
            for key, dock, default_area in self._layout_dock_specs():
                d_cfg = docks_dict.get(key)
                self._apply_dock_layout(
                    key,
                    dock,
                    d_cfg if isinstance(d_cfg, dict) else {},
                    default_area,
                )
            return True

        def reset_window_layout(self, persist: bool = True) -> None:
            """Reset main window and all dock panels back to their default docked positions."""
            self.window_layout = default_window_layout()
            for key, dock, default_area in self._layout_dock_specs():
                dock.setFloating(False)
                self.addDockWidget(self._name_to_dock_area(default_area, default_area), dock)
                if key == "clock":
                    dock.setVisible(bool(self.controller.chat_panel.is_gm))
                else:
                    dock.setVisible(True)
            self.resize(1280, 840)
            if persist and self.window_layout_path:
                save_window_layout_file(self.window_layout_path, self.window_layout)
            self.statusBar().showMessage("Window layout reset to default.")

        def _on_save_window_layout(self) -> None:
            self.save_window_layout(persist=True)
            self.statusBar().showMessage("Window layout saved.")

        def _on_reset_window_layout(self) -> None:
            self.reset_window_layout(persist=True)

        def closeEvent(self, event: QCloseEvent) -> None:
            """Persist layout then close floating docks and unowned modeless child windows."""
            self.save_window_layout(persist=True)
            for dock in (self.clock_dock, self.combat_dock, self.chat_dock):
                dock.close()
            if self.controller.player_clock_window is not None:
                self.controller.player_clock_window.close()
            if self._ping_dialog is not None:
                self._ping_dialog.close()
            if self._distance_dialog is not None:
                self._close_distance_dialog()
            elif hasattr(self.controller.scene, "clear_distance_tracers"):
                self.controller.scene.clear_distance_tracers()
            if self._debug_window is not None:
                self._debug_window.close()
            for dlg in list(self._delegated_dialogs.values()):
                dlg.close()
            super().closeEvent(event)

else:

    class GMAMapperMainWindow:  # type: ignore[no-redef]
        def __init__(
            self,
            prefs: dict[str, Any] | None = None,
            prefs_path: str | Path | None = None,
        ) -> None:
            self.prefs = prefs or default_preferences()
            self.prefs_path = Path(prefs_path) if prefs_path else None
            self.window_layout_path: Path | None = (
                default_window_layout_path(self.prefs_path) if self.prefs_path else None
            )
            self.window_layout: dict[str, Any] = (
                load_window_layout(self.window_layout_path)
                if self.window_layout_path
                else default_window_layout()
            )
            self.controller = MapperController(self.prefs)
