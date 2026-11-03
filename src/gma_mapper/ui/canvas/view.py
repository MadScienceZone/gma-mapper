"""BattleMapView (QGraphicsView) for GMA Mapper battle maps.

Supports discrete and smooth zooming, panning, ruler distance/angle measurement,
MARK pings, token dragging, and GM shape drawing / map element editing tools.
"""

from __future__ import annotations

import copy
import random
from typing import Any, Callable

from gma_mapper.core.util import letter_label_to_grid_xy
from gma_mapper.net.protocol import from_enum, new_dict, new_id, to_enum
from gma_mapper.ui.canvas.aoe import (
    AoETargetDialog,
    compute_aoe_grids,
    compute_creature_aoe_grids,
    cycle_aoe_shape,
    find_creatures_in_aoe_grids,
    grid_intersection_distance,
)
from gma_mapper.ui.canvas.context_menu import populate_canvas_context_menu
from gma_mapper.ui.canvas.drawing import (
    compute_nudge_z,
    cycle_arc_mode,
    cycle_arrow_style,
    cycle_dash_style,
    cycle_join_style,
    cycle_spline_level,
    cycle_text_anchor,
    describe_element,
    snap_point,
    translate_element_coords,
)
from gma_mapper.ui.canvas.items import BASE_GRID_SCALE, CreatureTokenItem
from gma_mapper.ui.canvas.scene import (
    DISCRETE_ZOOM_STEPS,
    BattleMapScene,
    grid_coord_label,
    grid_distance_feet,
    scene_to_grid_xy,
    snap_creature_grid_xy,
)

try:
    from PySide6.QtCore import QLineF, QPointF, QRectF, Qt, Signal
    from PySide6.QtGui import (
        QColor,
        QCursor,
        QFont,
        QKeyEvent,
        QMouseEvent,
        QPainter,
        QPen,
        QTransform,
        QWheelEvent,
    )
    from PySide6.QtWidgets import (
        QFontDialog,
        QGraphicsLineItem,
        QGraphicsRectItem,
        QGraphicsSimpleTextItem,
        QGraphicsView,
        QInputDialog,
        QMenu,
        QWidget,
    )

    class BattleMapView(QGraphicsView):
        """Interactive battle map viewport."""

        zoom_changed = Signal(float)
        cursor_grid_changed = Signal(str, float, float)  # (grid_label, gx, gy)
        mark_requested = Signal(float, float)  # (scene_x, scene_y)
        element_drawn = Signal(str, dict)  # (gma_type, data_dict)
        element_attributes_changed = Signal(str, dict)  # (obj_id, new_attrs_dict)
        element_removed = Signal(str)  # obj_id
        tile_image_requested = Signal(str, float)  # (image_name, zoom)
        token_dragged = Signal(str, float, float)  # (mob_id, gx, gy)
        token_selected = Signal(str)  # mob_id
        ruler_measured = Signal(str)  # formatted distance & angle message
        mob_attributes_changed = Signal(str, dict)  # (mob_id, new_attrs_dict)
        mob_removed = Signal(str)  # mob_id
        mob_spawned = Signal(dict)  # PS creature dict
        hp_request_sent = Signal(dict)  # HPREQ dict
        tool_changed = Signal(str)  # active_tool name
        status_message = Signal(str)  # status bar notification
        sync_view_requested = Signal(float, float, str)  # (xview, yview, grid_label)

        def __init__(
            self, scene: BattleMapScene, parent: QWidget | None = None
        ) -> None:
            super().__init__(scene, parent)
            self.map_scene = scene
            self.setMouseTracking(True)
            self.setFocusPolicy(Qt.FocusPolicy.StrongFocus)
            self.setRenderHints(
                QPainter.RenderHint.Antialiasing
                | QPainter.RenderHint.SmoothPixmapTransform
                | QPainter.RenderHint.TextAntialiasing
            )
            self.setViewportUpdateMode(
                QGraphicsView.ViewportUpdateMode.FullViewportUpdate
            )
            self.setTransformationAnchor(
                QGraphicsView.ViewportAnchor.AnchorUnderMouse
            )
            self.setAlignment(Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignTop)
            self.horizontalScrollBar().setValue(0)
            self.verticalScrollBar().setValue(0)

            self._zoom: float = 1.0
            self.active_tool: str = "pointer"  # pointer, ruler, mark, line, rect, poly, circ, arc, text, tile, move, kill, saoe
            self.draw_line_color: str = "black"
            self.draw_fill_color: str = "gray"
            self.fill_enabled: bool = False
            self.draw_stipple: str = ""
            self.draw_width: int = 2
            self.draw_dash: str = ""
            self.draw_arrow: str = "none"
            self.draw_join: str = "bevel"
            self.draw_spline: int = 0
            self.draw_arc_mode: str = "pieslice"
            self.draw_arc_start: float = 0.0
            self.draw_arc_extent: float = 90.0
            self.draw_aoe_shape: str = "radius"
            self.draw_aoe_spread: bool = False
            self.draw_text_string: str = ""
            self.draw_text_anchor: str = "center"
            self.draw_font: dict[str, Any] = {
                "Family": "Helvetica",
                "Size": 12.0,
                "Weight": 0,
                "Slant": 0,
            }
            self.draw_stamp_tile: str = ""
            self.draw_layer: str = "walls"
            self.obj_snap: int = 1
            self.force_elements_to_top: bool = False
            self.combatant_scroll_enabled: bool = False
            self._next_z: int = 10
            self.pc_templates_provider: Callable[[], dict[str, dict[str, Any]]] | None = None

            self._panning: bool = False
            self._right_press_pos: QPointF | None = None
            self._pan_start = QPointF()
            self._last_scene_pos = QPointF(0.0, 0.0)
            self._tool_start: QPointF | None = None
            self._dragging_token: CreatureTokenItem | None = None
            self._ruler_line: QGraphicsLineItem | None = None
            self._ruler_text: QGraphicsSimpleTextItem | None = None
            self._preview_rect: QGraphicsRectItem | None = None

            # Interactive element drawing / editing state
            self._active_draw_id: str = ""
            self._active_draw_press_pt: QPointF | None = None
            self._arc_setting_angles: bool = False
            self._moving_obj_id: str = ""
            self._moving_obj_orig_data: dict[str, Any] | None = None
            self._moving_obj_start_pt: tuple[float, float] = (0.0, 0.0)
            self._last_moved_obj_id: str = ""
            self._kill_cycle_idx: int = -1
            self._mob_aoe_id: str = ""
            self._mob_aoe_local: bool = False

        @property
        def zoom(self) -> float:
            return self._zoom

        def set_zoom(self, new_zoom: float) -> None:
            clamped = max(0.1, min(32.0, float(new_zoom)))
            self._zoom = clamped
            self.setTransform(QTransform.fromScale(clamped, clamped))
            self.zoom_changed.emit(clamped)

        def reset_zoom(self) -> None:
            self.set_zoom(1.0)

        def step_zoom(self, direction: int) -> None:
            """Step to the next (`direction > 0`) or previous (`direction < 0`) discrete zoom level."""
            if direction > 0:
                for z in DISCRETE_ZOOM_STEPS:
                    if z > self._zoom + 1e-4:
                        self.set_zoom(z)
                        return
            elif direction < 0:
                for z in reversed(DISCRETE_ZOOM_STEPS):
                    if z < self._zoom - 1e-4:
                        self.set_zoom(z)
                        return

        def zoom_in(self) -> None:
            self.step_zoom(1)

        def zoom_out(self) -> None:
            self.step_zoom(-1)

        def top_left_grid_label(self) -> str:
            """Return the grid label (e.g. `A1`) of the top-left corner of the viewport."""
            tl_scene = self.mapToScene(0, 0)
            gx, gy = scene_to_grid_xy(tl_scene.x(), tl_scene.y())
            return grid_coord_label(gx, gy)

        def scroll_to_grid_label(self, label: str) -> bool:
            """Scroll the viewport so the grid square named by `label` (`A1`, `C12`, etc.) is at the top-left."""
            try:
                coords = letter_label_to_grid_xy(label.strip())
            except ValueError:
                coords = None
            if coords is None:
                self.status_message.emit(f"Invalid grid coordinate: {label!r}")
                return False
            gx, raw_row = coords
            gy = max(0, raw_row - 1) if raw_row >= 1 else 0
            sx = gx * BASE_GRID_SCALE
            sy = gy * BASE_GRID_SCALE
            sr = self.map_scene.sceneRect()
            self.horizontalScrollBar().setValue(int((sx - sr.left()) * self._zoom))
            self.verticalScrollBar().setValue(int((sy - sr.top()) * self._zoom))
            self.status_message.emit(
                f"Scrolled to {grid_coord_label(gx, gy)} ({gx:g}, {gy:g})"
            )
            return True

        def go_to_grid_coords_dialog(self) -> None:
            """Prompt the user for map grid coordinates (`GoToGridCoords`, `Ctrl+G`) and scroll there."""
            default_lbl = self.top_left_grid_label()
            text, ok = QInputDialog.getText(
                self,
                "Go to Map Location",
                "Map Coordinates (e.g. A1, C12, +A1, -B3):",
                text=default_lbl,
            )
            if ok and text.strip():
                self.scroll_to_grid_label(text.strip())

        def scroll_to_visible_objects(self) -> None:
            """Scroll the viewport to the centroid of all visible map elements and tokens (`FindNearby`, `Alt+V`)."""
            pt = self.map_scene.visible_objects_center()
            if pt is None:
                self.centerOn(0.0, 0.0)
                self.status_message.emit("No visible objects on map; centered on origin")
                return
            self.centerOn(pt[0], pt[1])
            gx, gy = scene_to_grid_xy(pt[0], pt[1])
            self.status_message.emit(
                f"Scrolled to visible objects around {grid_coord_label(gx, gy)}"
            )

        def sync_others_views(self) -> None:
            """Broadcast an `AV` command so other connected clients match our viewport (`SyncView`)."""
            sr = self.map_scene.sceneRect()
            tl_scene = self.mapToScene(0, 0)
            xview = (
                (tl_scene.x() - sr.left()) / sr.width()
                if sr.width() > 0
                else 0.5
            )
            yview = (
                (tl_scene.y() - sr.top()) / sr.height()
                if sr.height() > 0
                else 0.5
            )
            lbl = self.top_left_grid_label()
            self.sync_view_requested.emit(xview, yview, lbl)
            self.status_message.emit(f"Synchronized others' views to {lbl}")

        def adjust_view(self, grid: str, xview: float, yview: float) -> None:
            """Handle incoming `AV` command (`AdjustView`) to scroll our viewport to match the sender."""
            if grid and self.scroll_to_grid_label(grid):
                return
            sr = self.map_scene.sceneRect()
            sx = sr.left() + xview * sr.width()
            sy = sr.top() + yview * sr.height()
            self.centerOn(sx, sy)

        def ensure_scene_xy_visible(
            self, sx: float, sy: float, margin_px: float = 100.0
        ) -> None:
            """Scroll the viewport only if `(sx, sy)` falls outside the current viewport (inset by `margin_px`)."""
            vp = self.viewport().rect()
            tl = self.mapToScene(vp.topLeft())
            br = self.mapToScene(vp.bottomRight())
            vis_rect = QRectF(tl, br).normalized()
            margin_scene = margin_px / max(0.1, self._zoom)
            inner = vis_rect.adjusted(
                margin_scene, margin_scene, -margin_scene, -margin_scene
            )
            if not inner.isValid():
                inner = vis_rect
            if not inner.contains(QPointF(sx, sy)):
                self.centerOn(sx, sy)

        def scroll_to_combatant(self, mob_id: str) -> None:
            """Scroll to keep `mob_id` on screen when `combatant_scroll_enabled` is active (`ScrollToCombatant`)."""
            if not self.combatant_scroll_enabled:
                return
            tok = self.map_scene.creatures.get(mob_id)
            if tok is None or not tok.isVisible():
                return
            sx, sy = tok._center_scene_xy()
            self.ensure_scene_xy_visible(sx, sy)

        def refresh_display(self) -> None:
            """Force redraw of targets, scene, and viewport (`Refresh`, `Ctrl+R`)."""
            self.map_scene.refresh_targets()
            self.map_scene.update()
            self.viewport().update()
            self.status_message.emit("Display refreshed")

        def _next_element_z(self) -> int:
            for item in self.map_scene.elements.values():
                z = int(float(item.data.get("Z", 0) or 0))
                if z < 500_000_000 and z >= self._next_z:
                    self._next_z = z + 1
            self._next_z += 1
            return self._next_z + (999_999_999 if self.force_elements_to_top else 0)

        def _snap_scene_pt(self, scene_pt: QPointF) -> tuple[float, float]:
            if self.active_tool == "saoe":
                return snap_point(scene_pt.x(), scene_pt.y(), max(1, self.obj_snap))
            return snap_point(scene_pt.x(), scene_pt.y(), self.obj_snap)

        def _cancel_active_draw(self) -> None:
            if self._active_draw_id:
                self.map_scene.remove_object(self._active_draw_id)
                self._active_draw_id = ""
            self._active_draw_press_pt = None
            self._arc_setting_angles = False
            if self._preview_rect is not None:
                self.map_scene.removeItem(self._preview_rect)
                self._preview_rect = None
            self._tool_start = None
            self._moving_obj_id = ""
            self._moving_obj_orig_data = None
            self._mob_aoe_id = ""

        def _prompt_aoe_targets(
            self,
            aoe_grids: list[tuple[int, int]],
            source_mob_id: str = "",
        ) -> None:
            """Prompt the user with `AoETargetDialog` if any creatures occupy `aoe_grids` (`aoe_target_prompt`)."""
            if AoETargetDialog is None or not aoe_grids:
                return
            creatures_by_id = {
                cid: tok.data for cid, tok in self.map_scene.creatures.items()
            }
            target_names = find_creatures_in_aoe_grids(aoe_grids, creatures_by_id)
            if not target_names:
                return
            creatures_by_name = {
                str(d.get("Name") or cid): d for cid, d in creatures_by_id.items()
            }
            dlg = AoETargetDialog(target_names, creatures_by_name, self)
            if dlg.exec():
                chosen = dlg.selected_targets()
                if chosen:
                    src_id = (
                        source_mob_id
                        or self.map_scene.active_target_source
                        or self.map_scene.active_actor_id
                    )
                    if src_id and src_id in self.map_scene.creatures:
                        self._mutate_mob(src_id, {"Targets": chosen})
                        self.status_message.emit(
                            f"Targeted {len(chosen)} creature(s) in area of effect"
                        )

        def start_mob_aoe_drag(self, mob_id: str, is_local: bool = False) -> None:
            """Toggle or interactively drag a creature's `AoE` or `_AoE` aura (`ToggleSpellArea`)."""
            tok = self.map_scene.creatures.get(mob_id)
            if tok is None:
                return
            attr_key = "_AoE" if is_local else "AoE"
            cur = tok.data.get(attr_key) or {}
            if isinstance(cur, dict) and float(cur.get("Radius", 0.0) or 0.0) > 0:
                if is_local:
                    self.map_scene.update_object_attributes(
                        mob_id, {attr_key: {"Radius": 0.0, "Color": ""}}
                    )
                else:
                    self._mutate_mob(mob_id, {attr_key: {"Radius": 0.0, "Color": ""}})
                self.status_message.emit(
                    f"Cleared {'local aura' if is_local else 'spell area'} for {tok.data.get('Name', mob_id)}"
                )
                return

            self._clear_ruler_items()
            self._cancel_active_draw()
            self._mob_aoe_id = mob_id
            self._mob_aoe_local = is_local
            self.setCursor(Qt.CursorShape.CrossCursor)
            self.status_message.emit(
                f"Move mouse to set {'local aura' if is_local else 'spell area'} radius for {tok.data.get('Name', mob_id)}; click to finish"
            )

        def _finish_active_draw(self) -> None:
            if not self._active_draw_id or self._active_draw_id not in self.map_scene.elements:
                self._active_draw_id = ""
                self._active_draw_press_pt = None
                self._arc_setting_angles = False
                return
            oid = self._active_draw_id
            self._active_draw_id = ""
            self._active_draw_press_pt = None
            self._arc_setting_angles = False
            item = self.map_scene.elements[oid]
            pts = list(item.data.get("Points") or [])
            if item.gma_type not in ("TEXT", "TILE") and not pts:
                self.map_scene.remove_object(oid)
                return
            if item.gma_type in ("SAOE", "AOE"):
                item.update_data({"_preview": False})
                gx0 = int(round(float(item.data.get("X", 0.0)) / BASE_GRID_SCALE))
                gy0 = int(round(float(item.data.get("Y", 0.0)) / BASE_GRID_SCALE))
                gxx = int(round(float(pts[-1].get("X", 0.0)) / BASE_GRID_SCALE))
                gyy = int(round(float(pts[-1].get("Y", 0.0)) / BASE_GRID_SCALE))
                raw_shape = item.data.get("AoEShape", 1)
                shape_str = (
                    from_enum("AoEShape", int(raw_shape))
                    if isinstance(raw_shape, int)
                    else str(raw_shape or "radius")
                )
                grids = compute_aoe_grids(
                    gx0,
                    gy0,
                    gxx,
                    gyy,
                    shape=shape_str,
                    spread=bool(item.data.get("_spread", False)),
                    barrier_segments=self.map_scene.aoe_barrier_segments(),
                )
                item.data["AoEGrids"] = grids
                self.element_drawn.emit(item.gma_type, dict(item.data))
                self._prompt_aoe_targets(grids)
                return
            self.element_drawn.emit(item.gma_type, dict(item.data))

        def set_tool_mode(self, mode: str) -> None:
            mode_map = {
                "select": "pointer",
                "nil": "pointer",
                "play": "pointer",
                "circle": "circ",
                "stamp": "tile",
                "aoe": "saoe",
            }
            resolved = mode_map.get(mode, mode)
            self._clear_ruler_items()
            self._cancel_active_draw()
            self.map_scene.set_highlighted_element("")
            self.active_tool = resolved
            cursor_map = {
                "pointer": Qt.CursorShape.ArrowCursor,
                "ruler": Qt.CursorShape.CrossCursor,
                "mark": Qt.CursorShape.CrossCursor,
                "line": Qt.CursorShape.CrossCursor,
                "rect": Qt.CursorShape.CrossCursor,
                "poly": Qt.CursorShape.CrossCursor,
                "circ": Qt.CursorShape.CrossCursor,
                "arc": Qt.CursorShape.CrossCursor,
                "saoe": Qt.CursorShape.CrossCursor,
                "aoebound": Qt.CursorShape.CrossCursor,
                "text": Qt.CursorShape.IBeamCursor,
                "tile": Qt.CursorShape.PointingHandCursor,
                "move": Qt.CursorShape.SizeAllCursor,
                "kill": Qt.CursorShape.ForbiddenCursor,
            }
            self.setCursor(cursor_map.get(resolved, Qt.CursorShape.ArrowCursor))
            self.tool_changed.emit(resolved)

        def _clear_ruler_items(self) -> None:
            if self._ruler_line is not None:
                self.map_scene.removeItem(self._ruler_line)
                self._ruler_line = None
            if self._ruler_text is not None:
                self.map_scene.removeItem(self._ruler_text)
                self._ruler_text = None
            self._tool_start = None

        def start_ruler_from(self, scene_pt: QPointF) -> None:
            """Start an interactive distance ruler anchored at `scene_pt`."""
            self._clear_ruler_items()
            self._cancel_active_draw()
            self.active_tool = "ruler"
            self._tool_start = scene_pt
            self._ruler_line = self.map_scene.addLine(
                QLineF(scene_pt, scene_pt),
                QPen(QColor("#ffff00"), 2, Qt.PenStyle.DashLine),
            )
            self._ruler_line.setZValue(2_100_000_000)
            self._ruler_text = self.map_scene.addSimpleText("")
            self._ruler_text.setBrush(QColor("#ffff00"))
            self._ruler_text.setFont(QFont("Helvetica", 10, QFont.Weight.Bold))
            self._ruler_text.setZValue(2_100_000_001)
            self.tool_changed.emit("ruler")

        def _mutate_mob(self, mob_id: str, new_attrs: dict[str, Any]) -> None:
            self.map_scene.update_object_attributes(mob_id, new_attrs)
            self.mob_attributes_changed.emit(mob_id, new_attrs)

        def _remove_mob(self, mob_id: str) -> None:
            self.map_scene.remove_object(mob_id)
            self.mob_removed.emit(mob_id)

        def _spawn_mob(self, mob_dict: dict[str, Any]) -> None:
            self.map_scene.place_someone(mob_dict)
            self.mob_spawned.emit(mob_dict)

        def _remove_element(self, obj_id: str) -> None:
            if self.map_scene.highlighted_element_id == obj_id:
                self.map_scene.set_highlighted_element("")
            self.map_scene.remove_object(obj_id)
            self.element_removed.emit(obj_id)
            self.status_message.emit(f"Removed object {obj_id}")

        def _open_context_menu(self, global_pos: Any, scene_pt: QPointF) -> None:
            if populate_canvas_context_menu is None:
                return
            menu = QMenu(self)
            pc_tpls = self.pc_templates_provider() if self.pc_templates_provider else {}
            populate_canvas_context_menu(
                menu=menu,
                scene=self.map_scene,
                view=self,
                scene_pt=scene_pt,
                on_mutate_mob=self._mutate_mob,
                on_remove_mob=self._remove_mob,
                on_spawn_mob=self._spawn_mob,
                on_hp_request=lambda req: self.hp_request_sent.emit(req),
                pc_templates=pc_tpls,
            )
            menu.exec(global_pos)

        def prompt_text_string(self) -> bool:
            text, ok = QInputDialog.getText(
                self,
                "Text String to Place",
                "Text string to place:",
                text=self.draw_text_string,
            )
            if ok:
                self.draw_text_string = text
                self.status_message.emit(f"Text string set to: {text}")
                return bool(text)
            return False

        def prompt_text_font(self) -> None:
            cur = QFont(
                str(self.draw_font.get("Family", "Helvetica")),
                int(float(self.draw_font.get("Size", 12.0))),
                QFont.Weight.Bold if self.draw_font.get("Weight") else QFont.Weight.Normal,
                bool(self.draw_font.get("Slant")),
            )
            ok, qfont = QFontDialog.getFont(cur, self, "Choose Text Font")
            if ok and isinstance(qfont, QFont):
                self.draw_font = {
                    "Family": qfont.family(),
                    "Size": float(max(6, qfont.pointSize())),
                    "Weight": 1 if qfont.bold() else 0,
                    "Slant": 1 if qfont.italic() else 0,
                }
                self.status_message.emit(
                    f"Font: {self.draw_font['Family']} {self.draw_font['Size']:.0f}pt"
                )

        def prompt_stamp_tile(self) -> bool:
            known = sorted(self.map_scene.pixmaps.keys())
            text, ok = QInputDialog.getItem(
                self,
                "Select Stamp Tile",
                "Tile base name:",
                known if known else [""],
                0,
                True,
            )
            if ok and text.strip():
                self.draw_stamp_tile = text.strip()
                self.tile_image_requested.emit(self.draw_stamp_tile, 1.0)
                self.status_message.emit(f"Stamp tile set to: {self.draw_stamp_tile}")
                return True
            return False

        def trigger_alt_1(self) -> None:
            """Handle `Alt+1` tool sub-option cycling matching `bin/mapper_legacy.tcl`."""
            if self.active_tool == "line":
                self.draw_arrow = cycle_arrow_style(self.draw_arrow)
                if self._active_draw_id in self.map_scene.elements:
                    self.map_scene.elements[self._active_draw_id].update_data(
                        {"Arrow": to_enum("Arrow", self.draw_arrow)}
                    )
                self.status_message.emit(f"Line arrow style: {self.draw_arrow}")
            elif self.active_tool == "poly":
                self.draw_join = cycle_join_style(self.draw_join)
                if self._active_draw_id in self.map_scene.elements:
                    self.map_scene.elements[self._active_draw_id].update_data(
                        {"Join": to_enum("Join", self.draw_join)}
                    )
                self.status_message.emit(f"Polygon join style: {self.draw_join}")
            elif self.active_tool == "arc":
                self.draw_arc_mode = cycle_arc_mode(self.draw_arc_mode)
                if self._active_draw_id in self.map_scene.elements:
                    self.map_scene.elements[self._active_draw_id].update_data(
                        {"ArcMode": to_enum("ArcMode", self.draw_arc_mode)}
                    )
                self.status_message.emit(f"Arc style: {self.draw_arc_mode}")
            elif self.active_tool == "text":
                self.prompt_text_font()
            elif self.active_tool == "saoe":
                self.draw_aoe_shape = cycle_aoe_shape(self.draw_aoe_shape)
                if self._active_draw_id in self.map_scene.elements:
                    self.map_scene.elements[self._active_draw_id].update_data(
                        {"AoEShape": to_enum("AoEShape", self.draw_aoe_shape)}
                    )
                self.status_message.emit(
                    f"Area of effect shape: {self.draw_aoe_shape}"
                )

        def trigger_alt_2(self) -> None:
            """Handle `Alt+2` tool sub-option cycling matching `bin/mapper_legacy.tcl`."""
            if self.active_tool == "poly":
                self.draw_spline = cycle_spline_level(self.draw_spline)
                if self._active_draw_id in self.map_scene.elements:
                    self.map_scene.elements[self._active_draw_id].update_data(
                        {"Spline": self.draw_spline}
                    )
                self.status_message.emit(f"Polygon spline steps: {self.draw_spline}")
            elif self.active_tool == "text":
                self.draw_text_anchor = cycle_text_anchor(self.draw_text_anchor)
                self.status_message.emit(f"Text anchor: {self.draw_text_anchor}")
            elif self.active_tool == "saoe":
                self.draw_aoe_spread = not self.draw_aoe_spread
                if self._active_draw_id in self.map_scene.elements:
                    self.map_scene.elements[self._active_draw_id].update_data(
                        {"_spread": self.draw_aoe_spread}
                    )
                self.status_message.emit(
                    f"Area of effect spread: {'ON' if self.draw_aoe_spread else 'OFF'}"
                )

        def trigger_alt_3(self) -> None:
            """Handle `Alt+3` dash style cycling matching `bin/mapper_legacy.tcl`."""
            if self.active_tool in ("line", "rect", "poly", "circ", "arc"):
                self.draw_dash = cycle_dash_style(self.draw_dash)
                if self._active_draw_id in self.map_scene.elements:
                    self.map_scene.elements[self._active_draw_id].update_data(
                        {"Dash": to_enum("Dash", self.draw_dash)}
                    )
                self.status_message.emit(
                    f"Dash style: {self.draw_dash or 'solid'}"
                )

        def adjust_view(self, grid_label: str = "", xview: float = 0.0, yview: float = 0.0) -> None:
            """Scroll viewport to `grid_label` or `(xview, yview)` from `AV` server command."""
            if grid_label:
                try:
                    gx, gy = letter_label_to_grid_xy(grid_label)
                    self.centerOn(gx * BASE_GRID_SCALE, gy * BASE_GRID_SCALE)
                    return
                except ValueError:
                    pass
            srect = self.map_scene.sceneRect()
            cx = srect.left() + xview * srect.width()
            cy = srect.top() + yview * srect.height()
            self.centerOn(cx, cy)

        def wheelEvent(self, event: QWheelEvent) -> None:
            if event.modifiers() & Qt.KeyboardModifier.ControlModifier:
                angle = event.angleDelta().y()
                factor = 1.15 if angle > 0 else (1.0 / 1.15)
                self.set_zoom(self._zoom * factor)
                event.accept()
            else:
                super().wheelEvent(event)

        def _start_shape_element(self, sx: float, sy: float) -> None:
            oid = new_id()
            z = self._next_element_z()
            fill_val = (
                (self.draw_fill_color or self.draw_line_color)
                if self.fill_enabled
                else ""
            )
            dash_enum = to_enum("Dash", self.draw_dash)
            mode = self.active_tool

            if mode == "line":
                line_stroke = (
                    self.draw_fill_color
                    if (self.fill_enabled and self.draw_fill_color)
                    else self.draw_line_color
                )
                d = new_dict(
                    "LS-LINE",
                    ID=oid,
                    X=sx,
                    Y=sy,
                    Z=z,
                    Points=[{"X": sx, "Y": sy}],
                    Fill=line_stroke,
                    Line=self.draw_line_color,
                    Stipple=self.draw_stipple,
                    Width=self.draw_width,
                    Dash=dash_enum,
                    Layer=self.draw_layer,
                    Arrow=to_enum("Arrow", self.draw_arrow),
                )
                self.map_scene.add_or_update_element("LS-LINE", d)
            elif mode == "poly":
                d = new_dict(
                    "LS-POLY",
                    ID=oid,
                    X=sx,
                    Y=sy,
                    Z=z,
                    Points=[{"X": sx, "Y": sy}],
                    Fill=fill_val,
                    Line=self.draw_line_color,
                    Stipple=self.draw_stipple,
                    Width=self.draw_width,
                    Dash=dash_enum,
                    Layer=self.draw_layer,
                    Join=to_enum("Join", self.draw_join),
                    Spline=self.draw_spline,
                )
                self.map_scene.add_or_update_element("LS-POLY", d)
            elif mode == "rect":
                d = new_dict(
                    "LS-RECT",
                    ID=oid,
                    X=sx,
                    Y=sy,
                    Z=z,
                    Points=[{"X": sx, "Y": sy}],
                    Fill=fill_val,
                    Line=self.draw_line_color,
                    Stipple=self.draw_stipple,
                    Width=self.draw_width,
                    Dash=dash_enum,
                    Layer=self.draw_layer,
                )
                self.map_scene.add_or_update_element("LS-RECT", d)
            elif mode == "circ":
                d = new_dict(
                    "LS-CIRC",
                    ID=oid,
                    X=sx,
                    Y=sy,
                    Z=z,
                    Points=[{"X": sx, "Y": sy}],
                    Fill=fill_val,
                    Line=self.draw_line_color,
                    Stipple=self.draw_stipple,
                    Width=self.draw_width,
                    Dash=dash_enum,
                    Layer=self.draw_layer,
                )
                self.map_scene.add_or_update_element("LS-CIRC", d)
            elif mode == "arc":
                d = new_dict(
                    "LS-ARC",
                    ID=oid,
                    X=sx,
                    Y=sy,
                    Z=z,
                    Points=[{"X": sx, "Y": sy}],
                    Fill=fill_val,
                    Line=self.draw_line_color,
                    Stipple=self.draw_stipple,
                    Width=self.draw_width,
                    Dash=dash_enum,
                    Layer=self.draw_layer,
                    ArcMode=to_enum("ArcMode", self.draw_arc_mode),
                    Start=self.draw_arc_start,
                    Extent=self.draw_arc_extent,
                )
                self.map_scene.add_or_update_element("LS-ARC", d)
            elif mode == "saoe":
                d = new_dict(
                    "LS-SAOE",
                    ID=oid,
                    X=sx,
                    Y=sy,
                    Z=99_999_999,
                    Points=[{"X": sx, "Y": sy}],
                    Fill=self.draw_fill_color or self.draw_line_color or "red",
                    Line=self.draw_line_color,
                    Width=self.draw_width,
                    Dash=dash_enum,
                    Layer=self.draw_layer,
                    AoEShape=to_enum("AoEShape", self.draw_aoe_shape),
                )
                d["_spread"] = self.draw_aoe_spread
                d["_preview"] = True
                self.map_scene.add_or_update_element("LS-SAOE", d)
            elif mode == "aoebound":
                oid = "AOE_GLOBAL_BOUND"
                if oid in self.map_scene.elements:
                    self._remove_element(oid)
                d = new_dict(
                    "LS-LINE",
                    ID=oid,
                    X=sx,
                    Y=sy,
                    Z=99_999_999,
                    Points=[{"X": sx, "Y": sy}],
                    Fill=self.draw_line_color or "black",
                    Line=self.draw_line_color or "black",
                    Width=3,
                    Dash=to_enum("Dash", "-"),
                    Layer=self.draw_layer,
                    Arrow=to_enum("Arrow", "none"),
                )
                self.map_scene.add_or_update_element("LS-LINE", d)

            self._active_draw_id = oid

        def _handle_kill_click(self, global_pos: Any, scene_pt: QPointF) -> None:
            candidates = self.map_scene.elements_at_scene_pos(scene_pt)
            if not candidates:
                self.status_message.emit("No unlocked map element under cursor")
                return
            if len(candidates) == 1:
                self._remove_element(candidates[0])
                return
            menu = QMenu(self)
            for oid in candidates:
                item = self.map_scene.elements[oid]
                label = f"Delete {describe_element(item.gma_type, item.data)}"
                act = menu.addAction(label)
                act.triggered.connect(
                    lambda _c=False, target=oid: self._remove_element(target)
                )
            menu.exec(global_pos)

        def _handle_move_press(self, global_pos: Any, scene_pt: QPointF) -> None:
            candidates = self.map_scene.elements_at_scene_pos(scene_pt)
            if not candidates:
                self.status_message.emit("No unlocked map element under cursor to move")
                return

            def _begin_move(oid: str) -> None:
                if oid not in self.map_scene.elements:
                    return
                self._moving_obj_id = oid
                self._last_moved_obj_id = oid
                self.map_scene.set_highlighted_element(oid)
                self._moving_obj_orig_data = copy.deepcopy(
                    self.map_scene.elements[oid].data
                )
                sx, sy = self._snap_scene_pt(scene_pt)
                self._moving_obj_start_pt = (sx, sy)
                self.status_message.emit(f"Moving object {oid}")

            if len(candidates) == 1:
                _begin_move(candidates[0])
            else:
                menu = QMenu(self)
                for oid in candidates:
                    item = self.map_scene.elements[oid]
                    label = f"Move {describe_element(item.gma_type, item.data)}"
                    act = menu.addAction(label)
                    act.triggered.connect(
                        lambda _c=False, target=oid: _begin_move(target)
                    )
                menu.exec(global_pos)

        def mouseDoubleClickEvent(self, event: QMouseEvent) -> None:
            if (
                event.button() == Qt.MouseButton.LeftButton
                and self._active_draw_id
                and self.active_tool in ("line", "poly", "aoebound")
            ):
                self._finish_active_draw()
                event.accept()
                return
            super().mouseDoubleClickEvent(event)

        def mousePressEvent(self, event: QMouseEvent) -> None:
            scene_pt = self.mapToScene(event.position().toPoint())
            self._last_scene_pos = scene_pt

            # Middle button finishes an active multi-point shape (matching EndObj in Tcl) or pans
            if event.button() == Qt.MouseButton.MiddleButton:
                if self._active_draw_id:
                    self._finish_active_draw()
                    event.accept()
                    return
                self._panning = True
                self._pan_start = event.position()
                self.setCursor(Qt.CursorShape.ClosedHandCursor)
                event.accept()
                return

            if event.button() == Qt.MouseButton.RightButton:
                if self._active_draw_id:
                    self._finish_active_draw()
                    event.accept()
                    return
                if self.active_tool == "text":
                    self.prompt_text_string()
                    event.accept()
                    return
                if self.active_tool == "tile":
                    self.prompt_stamp_tile()
                    event.accept()
                    return
                self._right_press_pos = event.position()
                self._pan_start = event.position()
                event.accept()
                return

            if event.button() == Qt.MouseButton.LeftButton:
                if self._mob_aoe_id:
                    mid = self._mob_aoe_id
                    is_local = self._mob_aoe_local
                    self._mob_aoe_id = ""
                    self.setCursor(Qt.CursorShape.ArrowCursor)
                    tok = self.map_scene.creatures.get(mid)
                    if tok is not None:
                        attr_key = "_AoE" if is_local else "AoE"
                        aoe_d = dict(tok.data.get(attr_key) or {})
                        if not is_local:
                            self.mob_attributes_changed.emit(mid, {attr_key: aoe_d})
                            rad = float(aoe_d.get("Radius", 0.0) or 0.0)
                            if rad > 0:
                                grids = compute_creature_aoe_grids(tok.data, rad)
                                self._prompt_aoe_targets(grids, source_mob_id=mid)
                    self.status_message.emit("Ready")
                    event.accept()
                    return

                if self.active_tool == "mark":
                    self.map_scene.flash_mark(scene_pt.x(), scene_pt.y())
                    self.mark_requested.emit(scene_pt.x(), scene_pt.y())
                    event.accept()
                    return

                if self.active_tool == "ruler":
                    if self._ruler_line is not None:
                        self._clear_ruler_items()
                        self.active_tool = "pointer"
                        self.setCursor(Qt.CursorShape.ArrowCursor)
                        self.tool_changed.emit("pointer")
                        event.accept()
                        return
                    self.start_ruler_from(scene_pt)
                    event.accept()
                    return

                if self.active_tool == "kill":
                    self._handle_kill_click(
                        event.globalPosition().toPoint(), scene_pt
                    )
                    event.accept()
                    return

                if self.active_tool == "move":
                    self._handle_move_press(
                        event.globalPosition().toPoint(), scene_pt
                    )
                    event.accept()
                    return

                if self.active_tool == "text":
                    if not self.draw_text_string and not self.prompt_text_string():
                        event.accept()
                        return
                    sx, sy = self._snap_scene_pt(scene_pt)
                    fill_col = (
                        self.draw_fill_color
                        if (self.fill_enabled and self.draw_fill_color)
                        else self.draw_line_color
                    )
                    data = new_dict(
                        "LS-TEXT",
                        ID=new_id(),
                        X=sx,
                        Y=sy,
                        Points=[],
                        Z=self._next_element_z(),
                        Line=self.draw_line_color,
                        Fill=fill_col or "black",
                        Stipple=self.draw_stipple,
                        Width=1,
                        Layer=self.draw_layer,
                        Text=self.draw_text_string,
                        Font=dict(self.draw_font),
                        Anchor=to_enum("Anchor", self.draw_text_anchor),
                    )
                    self.map_scene.add_or_update_element("TEXT", data)
                    self.element_drawn.emit("TEXT", data)
                    event.accept()
                    return

                if self.active_tool == "tile":
                    if not self.draw_stamp_tile and not self.prompt_stamp_tile():
                        event.accept()
                        return
                    sx, sy = self._snap_scene_pt(scene_pt)
                    pm = self.map_scene.get_pixmap(self.draw_stamp_tile)
                    bbw = float(pm.width()) if (pm and not pm.isNull()) else BASE_GRID_SCALE
                    bbh = float(pm.height()) if (pm and not pm.isNull()) else BASE_GRID_SCALE
                    data = new_dict(
                        "LS-TILE",
                        ID=new_id(),
                        X=sx,
                        Y=sy,
                        Points=[],
                        Z=self._next_element_z(),
                        Layer=self.draw_layer,
                        Image=self.draw_stamp_tile,
                        BBWidth=bbw,
                        BBHeight=bbh,
                    )
                    self.map_scene.add_or_update_element("TILE", data)
                    self.element_drawn.emit("TILE", data)
                    event.accept()
                    return

                if self.active_tool in ("line", "poly", "aoebound"):
                    sx, sy = self._snap_scene_pt(scene_pt)
                    if not self._active_draw_id:
                        self._active_draw_press_pt = event.position()
                        self._start_shape_element(sx, sy)
                    else:
                        item = self.map_scene.elements.get(self._active_draw_id)
                        if item:
                            pts = list(item.data.get("Points") or [])
                            if pts:
                                pts[-1] = {"X": sx, "Y": sy}
                            pts.append({"X": sx, "Y": sy})
                            item.update_data({"Points": pts})
                    event.accept()
                    return

                if self.active_tool in ("rect", "circ", "arc", "saoe"):
                    sx, sy = self._snap_scene_pt(scene_pt)
                    if not self._active_draw_id:
                        self._active_draw_press_pt = event.position()
                        self._start_shape_element(sx, sy)
                    elif self.active_tool == "arc" and not self._arc_setting_angles:
                        item = self.map_scene.elements.get(self._active_draw_id)
                        if item:
                            item.update_data({"Points": [{"X": sx, "Y": sy}]})
                        self._arc_setting_angles = True
                        self.status_message.emit(
                            "Move mouse to set arc Start/Extent angles; click to finish"
                        )
                    else:
                        if not self._arc_setting_angles:
                            item = self.map_scene.elements.get(self._active_draw_id)
                            if item:
                                item.update_data({"Points": [{"X": sx, "Y": sy}]})
                        self._finish_active_draw()
                    event.accept()
                    return

                # Pointer tool: check if clicking a creature token
                item = self.map_scene.itemAt(scene_pt, self.transform())
                if isinstance(item, CreatureTokenItem):
                    self.token_selected.emit(item.mob_id)
                    if event.modifiers() & Qt.KeyboardModifier.ControlModifier:
                        self.map_scene.toggle_mob_selection(item.mob_id)
                        event.accept()
                        return
                    self._dragging_token = item
                    event.accept()
                    return

            super().mousePressEvent(event)

        def mouseMoveEvent(self, event: QMouseEvent) -> None:
            scene_pt = self.mapToScene(event.position().toPoint())
            self._last_scene_pos = scene_pt
            gx, gy = scene_to_grid_xy(scene_pt.x(), scene_pt.y())
            self.cursor_grid_changed.emit(grid_coord_label(gx, gy), gx, gy)

            if self._right_press_pos is not None and not self._panning:
                delta_press = event.position() - self._right_press_pos
                if delta_press.manhattanLength() > 5.0:
                    self._panning = True
                    self.setCursor(Qt.CursorShape.ClosedHandCursor)

            if self._panning:
                delta = event.position() - self._pan_start
                self._pan_start = event.position()
                self.horizontalScrollBar().setValue(
                    self.horizontalScrollBar().value() - int(delta.x())
                )
                self.verticalScrollBar().setValue(
                    self.verticalScrollBar().value() - int(delta.y())
                )
                event.accept()
                return

            if self._mob_aoe_id and self._mob_aoe_id in self.map_scene.creatures:
                tok = self.map_scene.creatures[self._mob_aoe_id]
                sx, sy = snap_point(scene_pt.x(), scene_pt.y(), max(1, self.obj_snap))
                gx_snap = int(round(sx / BASE_GRID_SCALE))
                gy_snap = int(round(sy / BASE_GRID_SCALE))
                r_sq = grid_intersection_distance(tok.gx, tok.gy, gx_snap, gy_snap)
                attr_key = "_AoE" if self._mob_aoe_local else "AoE"
                aoe_col = (
                    self.draw_fill_color
                    if (self.fill_enabled and self.draw_fill_color)
                    else str(tok.data.get("Color") or "cyan")
                )
                tok.update_data({attr_key: {"Radius": float(r_sq), "Color": aoe_col}})
                kind = "Local-display aura" if self._mob_aoe_local else "Spell"
                self.status_message.emit(
                    f"{kind} radius {r_sq} square{'' if r_sq == 1 else 's'} / {r_sq * 5} feet"
                )
                event.accept()
                return

            if (
                self.active_tool == "move"
                and self._moving_obj_id
                and self._moving_obj_orig_data is not None
                and self._moving_obj_id in self.map_scene.elements
            ):
                sx, sy = self._snap_scene_pt(scene_pt)
                dx = sx - self._moving_obj_start_pt[0]
                dy = sy - self._moving_obj_start_pt[1]
                working = copy.deepcopy(self._moving_obj_orig_data)
                diff = translate_element_coords(working, dx, dy)
                self.map_scene.elements[self._moving_obj_id].update_data(diff)
                event.accept()
                return

            if self._active_draw_id and self._active_draw_id in self.map_scene.elements:
                item = self.map_scene.elements[self._active_draw_id]
                if self.active_tool == "arc" and self._arc_setting_angles:
                    start_deg = float(int(event.position().x()) % 360)
                    extent_deg = float(int(event.position().y()) % 360)
                    self.draw_arc_start = start_deg
                    self.draw_arc_extent = extent_deg
                    item.update_data(
                        {
                            "Start": start_deg,
                            "Extent": extent_deg,
                            "ArcMode": to_enum("ArcMode", self.draw_arc_mode),
                        }
                    )
                    self.status_message.emit(
                        f"Arc start={start_deg:.0f}°, extent={extent_deg:.0f}°"
                    )
                else:
                    sx, sy = self._snap_scene_pt(scene_pt)
                    pts = list(item.data.get("Points") or [])
                    if pts:
                        pts[-1] = {"X": sx, "Y": sy}
                    else:
                        pts = [{"X": sx, "Y": sy}]
                    item.update_data({"Points": pts})
                    if self.active_tool == "saoe":
                        gx0 = int(round(float(item.data.get("X", 0.0)) / BASE_GRID_SCALE))
                        gy0 = int(round(float(item.data.get("Y", 0.0)) / BASE_GRID_SCALE))
                        gxx = int(round(sx / BASE_GRID_SCALE))
                        gyy = int(round(sy / BASE_GRID_SCALE))
                        r_sq = grid_intersection_distance(gx0, gy0, gxx, gyy)
                        self.status_message.emit(
                            f"Spell area distance: {r_sq} square{'' if r_sq == 1 else 's'} / {r_sq * 5} feet"
                        )
                event.accept()
                return

            if self._dragging_token is not None:
                snap_gx, snap_gy = snap_creature_grid_xy(
                    scene_pt.x(),
                    scene_pt.y(),
                    self._dragging_token.data,
                    self.map_scene.creature_grid_snap,
                )
                self._dragging_token.setPos(
                    snap_gx * BASE_GRID_SCALE, snap_gy * BASE_GRID_SCALE
                )
                event.accept()
                return

            if self.active_tool == "ruler" and self._tool_start and self._ruler_line:
                self._ruler_line.setLine(QLineF(self._tool_start, scene_pt))
                pf_ft, euc_ft, deg = grid_distance_feet(
                    self._tool_start.x(),
                    self._tool_start.y(),
                    scene_pt.x(),
                    scene_pt.y(),
                )
                msg = f"{pf_ft:.0f} ft (real {euc_ft:.1f} ft) @ {deg:.1f}°"
                if self._ruler_text:
                    self._ruler_text.setText(msg)
                    self._ruler_text.setPos(scene_pt + QPointF(10, -10))
                self.ruler_measured.emit(msg)
                event.accept()
                return

            super().mouseMoveEvent(event)

        def mouseReleaseEvent(self, event: QMouseEvent) -> None:
            scene_pt = self.mapToScene(event.position().toPoint())

            if event.button() == Qt.MouseButton.RightButton:
                was_panning = self._panning
                self._right_press_pos = None
                self._panning = False
                self.setCursor(Qt.CursorShape.ArrowCursor)
                if not was_panning and self.active_tool == "pointer":
                    self._open_context_menu(event.globalPosition().toPoint(), scene_pt)
                event.accept()
                return

            if self._panning:
                self._panning = False
                self.setCursor(Qt.CursorShape.ArrowCursor)
                event.accept()
                return

            if (
                self.active_tool == "move"
                and self._moving_obj_id
                and self._moving_obj_orig_data is not None
            ):
                oid = self._moving_obj_id
                self._moving_obj_id = ""
                self._moving_obj_orig_data = None
                if oid in self.map_scene.elements:
                    d = self.map_scene.elements[oid].data
                    self.element_attributes_changed.emit(
                        oid,
                        {
                            "X": d.get("X", 0.0),
                            "Y": d.get("Y", 0.0),
                            "Points": d.get("Points", []),
                        },
                    )
                event.accept()
                return

            if self._active_draw_id and self._active_draw_press_pt is not None:
                drag_dist = (event.position() - self._active_draw_press_pt).manhattanLength()
                self._active_draw_press_pt = None
                if drag_dist > 6.0 and self.active_tool in ("rect", "circ", "saoe", "line"):
                    if self.active_tool == "line":
                        # Single-segment drag-release line
                        self._finish_active_draw()
                        event.accept()
                        return
                    self._finish_active_draw()
                    event.accept()
                    return
                if drag_dist > 6.0 and self.active_tool == "arc" and not self._arc_setting_angles:
                    self._arc_setting_angles = True
                    self.status_message.emit(
                        "Move mouse to set arc Start/Extent angles; click to finish"
                    )
                    event.accept()
                    return

            if self._dragging_token is not None:
                tok = self._dragging_token
                self._dragging_token = None
                snap_gx, snap_gy = snap_creature_grid_xy(
                    scene_pt.x(),
                    scene_pt.y(),
                    tok.data,
                    self.map_scene.creature_grid_snap,
                )
                tok.update_data({"Gx": snap_gx, "Gy": snap_gy})
                self.map_scene.refresh_targets()
                self.token_dragged.emit(tok.mob_id, snap_gx, snap_gy)
                event.accept()
                return

            if self.active_tool == "ruler" and self._ruler_line is not None:
                self._clear_ruler_items()
                event.accept()
                return

            super().mouseReleaseEvent(event)

        def _nudge_last_moved_object(self, dx: float, dy: float) -> None:
            oid = self._last_moved_obj_id
            if not oid or oid not in self.map_scene.elements:
                self.status_message.emit(
                    "No current object to move; move one with mouse first"
                )
                return
            item = self.map_scene.elements[oid]
            diff = translate_element_coords(item.data, dx, dy)
            item.update_data(diff)
            self.element_attributes_changed.emit(oid, diff)

        def _nudge_last_moved_z(self, adj: str) -> None:
            oid = self._last_moved_obj_id
            if not oid or oid not in self.map_scene.elements:
                self.status_message.emit(
                    "No current object to adjust Z; move one with mouse first"
                )
                return
            elements_data = {
                k: v.data for k, v in self.map_scene.elements.items()
            }
            new_z = compute_nudge_z(elements_data, oid, adj)
            if new_z is None:
                self.status_message.emit(f"Object {oid} already at {adj} limit")
                return
            self.map_scene.elements[oid].update_data({"Z": new_z})
            self.element_attributes_changed.emit(oid, {"Z": new_z})
            self.status_message.emit(f"Object {oid} new Z={new_z}")

        def _cycle_kill_candidate(self, step: int) -> None:
            ids = self.map_scene.unlocked_element_ids_by_z()
            if not ids:
                self.map_scene.set_highlighted_element("")
                self.status_message.emit("No unlocked map elements")
                return
            self._kill_cycle_idx = (self._kill_cycle_idx + step) % len(ids)
            oid = ids[self._kill_cycle_idx]
            self.map_scene.set_highlighted_element(oid)
            item = self.map_scene.elements[oid]
            self.status_message.emit(
                f"Selected for removal: {describe_element(item.gma_type, item.data)} (press X to delete)"
            )

        def keyPressEvent(self, event: QKeyEvent) -> None:
            key = event.key()
            mods = event.modifiers()

            if key in (Qt.Key.Key_Return, Qt.Key.Key_Enter):
                if self._active_draw_id:
                    self._finish_active_draw()
                    event.accept()
                    return

            if key == Qt.Key.Key_Escape:
                if self._active_draw_id:
                    self._finish_active_draw()
                    event.accept()
                    return
                self._clear_ruler_items()
                self._cancel_active_draw()
                self.set_tool_mode("pointer")
                event.accept()
                return

            # Alt+1 / Alt+2 / Alt+3 / Alt+F sub-mode hotkeys
            if mods & Qt.KeyboardModifier.AltModifier:
                if key == Qt.Key.Key_1:
                    self.trigger_alt_1()
                    event.accept()
                    return
                if key == Qt.Key.Key_2:
                    self.trigger_alt_2()
                    event.accept()
                    return
                if key == Qt.Key.Key_3:
                    self.trigger_alt_3()
                    event.accept()
                    return
                if key == Qt.Key.Key_F:
                    self.fill_enabled = not self.fill_enabled
                    self.status_message.emit(
                        f"Fill shapes: {'ON' if self.fill_enabled else 'OFF'}"
                    )
                    event.accept()
                    return

            # Kill tool keyboard navigation (P = prev, N = next, X = kill)
            if self.active_tool == "kill" and not mods:
                if key == Qt.Key.Key_P:
                    self._cycle_kill_candidate(-1)
                    event.accept()
                    return
                if key == Qt.Key.Key_N:
                    self._cycle_kill_candidate(1)
                    event.accept()
                    return
                if key == Qt.Key.Key_X:
                    hid = self.map_scene.highlighted_element_id
                    if hid and hid in self.map_scene.elements:
                        self._remove_element(hid)
                        self._cycle_kill_candidate(-1)
                    event.accept()
                    return

            # Move tool keyboard nudging (arrows, H/J/K/L, U/D/F/B)
            if self.active_tool == "move":
                step = 10.0 if (mods & Qt.KeyboardModifier.ShiftModifier) else 1.0
                if key in (Qt.Key.Key_Left, Qt.Key.Key_H):
                    self._nudge_last_moved_object(-step, 0.0)
                    event.accept()
                    return
                if key in (Qt.Key.Key_Right, Qt.Key.Key_L):
                    self._nudge_last_moved_object(step, 0.0)
                    event.accept()
                    return
                if key in (Qt.Key.Key_Up, Qt.Key.Key_K):
                    self._nudge_last_moved_object(0.0, -step)
                    event.accept()
                    return
                if key in (Qt.Key.Key_Down, Qt.Key.Key_J):
                    self._nudge_last_moved_object(0.0, step)
                    event.accept()
                    return
                if not mods:
                    if key == Qt.Key.Key_U:
                        self._nudge_last_moved_z("up")
                        event.accept()
                        return
                    if key == Qt.Key.Key_D:
                        self._nudge_last_moved_z("down")
                        event.accept()
                        return
                    if key == Qt.Key.Key_F:
                        self._nudge_last_moved_z("front")
                        event.accept()
                        return
                    if key == Qt.Key.Key_B:
                        self._nudge_last_moved_z("back")
                        event.accept()
                        return

            if key == Qt.Key.Key_G and (mods & Qt.KeyboardModifier.ControlModifier):
                self.go_to_grid_coords_dialog()
                event.accept()
                return

            if key == Qt.Key.Key_V and (mods & Qt.KeyboardModifier.AltModifier):
                self.scroll_to_visible_objects()
                event.accept()
                return

            if key == Qt.Key.Key_R and (mods & Qt.KeyboardModifier.ControlModifier):
                self.refresh_display()
                event.accept()
                return

            if (
                key == Qt.Key.Key_A
                and (mods & Qt.KeyboardModifier.ControlModifier)
                and (mods & Qt.KeyboardModifier.ShiftModifier)
            ):
                self.map_scene.clear_mob_selection()
                self.status_message.emit("Deselected all creatures")
                event.accept()
                return

            if (
                key == Qt.Key.Key_A
                and (mods & Qt.KeyboardModifier.ControlModifier)
                and not (mods & Qt.KeyboardModifier.ShiftModifier)
            ):
                self.set_tool_mode("saoe")
                self.status_message.emit(
                    f"Selected area-of-effect tool [Alt+1 shape ({self.draw_aoe_shape}), Alt+2 spread ({'ON' if self.draw_aoe_spread else 'OFF'})]"
                )
                event.accept()
                return

            if key == Qt.Key.Key_B and (mods & Qt.KeyboardModifier.AltModifier):
                self.set_tool_mode("aoebound")
                self.status_message.emit(
                    "Selected area-of-effect boundary tool [Click vertices, Double/Right-click to finish]"
                )
                event.accept()
                return

            if key == Qt.Key.Key_G and not mods:
                self.map_scene.show_grid = not self.map_scene.show_grid
                self.map_scene.update()
                event.accept()
                return

            if key == Qt.Key.Key_D and (mods & Qt.KeyboardModifier.ControlModifier):
                self.set_tool_mode("ruler")
                event.accept()
                return

            if key == Qt.Key.Key_T and (mods & Qt.KeyboardModifier.ControlModifier) and not (
                mods & Qt.KeyboardModifier.ShiftModifier
            ):
                self.force_elements_to_top = not self.force_elements_to_top
                self.status_message.emit(
                    f"Force drawn elements to top: {'ON' if self.force_elements_to_top else 'OFF'}"
                )
                event.accept()
                return

            if key == Qt.Key.Key_T:
                mobs = self.map_scene.mobs_at_scene_pos(
                    self._last_scene_pos, include_selected=True
                )
                if not mobs:
                    super().keyPressEvent(event)
                    return
                if (mods & Qt.KeyboardModifier.ShiftModifier) and not (
                    mods & Qt.KeyboardModifier.ControlModifier
                ):
                    self.map_scene.active_target_source = mobs[0]
                    event.accept()
                    return
                source_id = (
                    self.map_scene.active_target_source
                    or self.map_scene.active_actor_id
                )
                stok = self.map_scene.creatures.get(source_id) if source_id else None
                if stok is None:
                    super().keyPressEvent(event)
                    return
                if (mods & Qt.KeyboardModifier.ControlModifier) and (
                    mods & Qt.KeyboardModifier.ShiftModifier
                ):
                    chosen_id = random.choice(mobs)
                    ctok = self.map_scene.creatures.get(chosen_id)
                    if ctok:
                        self._mutate_mob(
                            source_id,
                            {"Targets": [str(ctok.data.get("Name", chosen_id))]},
                        )
                    event.accept()
                    return
                cur_targets = list(stok.data.get("Targets") or [])
                tnames = [
                    str(self.map_scene.creatures[m].data.get("Name", m))
                    for m in mobs
                    if m in self.map_scene.creatures
                ]
                if tnames and all(t in cur_targets for t in tnames):
                    new_targets = [t for t in cur_targets if t not in tnames]
                else:
                    new_targets = list(cur_targets)
                    for t in tnames:
                        if t not in new_targets:
                            new_targets.append(t)
                self._mutate_mob(source_id, {"Targets": new_targets})
                event.accept()
                return

            super().keyPressEvent(event)

except ImportError:
    BattleMapView = None  # type: ignore[assignment,misc]
