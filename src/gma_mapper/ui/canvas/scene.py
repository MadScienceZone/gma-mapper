"""BattleMapScene (QGraphicsScene) for GMA Mapper battle maps.

Manages grid lines, coordinate labels, map elements, creature tokens, targeting lines, and pings.
"""

from __future__ import annotations

import math
from typing import Any

from gma_mapper.core.colors import color_to_hex
from gma_mapper.core.util import letter_label, letter_label_to_grid_xy
from gma_mapper.core.zones import creature_displayed_size, monster_size_value
from gma_mapper.ui.canvas.items import (
    BASE_GRID_SCALE,
    CreatureTokenItem,
    MapElementItem,
)

DISCRETE_ZOOM_STEPS: list[float] = [
    0.25,
    0.50,
    1.00,
    2.00,
    3.00,
    4.00,
    6.00,
    8.00,
    12.00,
    16.00,
    32.00,
]

CREATURE_GRID_SNAP_CHOICES: list[tuple[str, str]] = [
    ("nil", "By creature size"),
    ("1", "Full square"),
    ("0.5", "1/2 square"),
    ("0.25", "1/4 square"),
]


def grid_to_scene_xy(gx: float, gy: float) -> tuple[float, float]:
    """Convert grid square coordinates `(gx, gy)` to scene pixel coordinates."""
    return (gx * BASE_GRID_SCALE, gy * BASE_GRID_SCALE)


def scene_to_grid_xy(sx: float, sy: float, snap: bool = False) -> tuple[float, float]:
    """Convert scene pixel coordinates `(sx, sy)` to grid coordinates."""
    gx = sx / BASE_GRID_SCALE
    gy = sy / BASE_GRID_SCALE
    if snap:
        return (math.floor(gx * 2.0) / 2.0, math.floor(gy * 2.0) / 2.0)
    return (gx, gy)


def snap_creature_grid_xy(
    sx: float,
    sy: float,
    mob_data: dict[str, Any] | None = None,
    snap_mode: str = "nil",
) -> tuple[float, float]:
    """Snap scene coordinates `(sx, sy)` to grid coordinates `(gx, gy)` for a creature token.

    Matches `ScreenXYToGridXY` in `bin/mapper_legacy.tcl` lines 8221-8251:
    - If `snap_mode == 'nil'` ('By creature size'), Medium and larger creatures snap to `1.0` full grid squares,
      while Tiny/Diminutive/Fine creatures (`mob_size < 1.0`) snap to `0.5` half-squares.
    - Otherwise snaps to `float(snap_mode)` (`1.0`, `0.5`, or `0.25`).
    """
    gx = sx / BASE_GRID_SCALE
    gy = sy / BASE_GRID_SCALE
    if snap_mode != "nil":
        try:
            step = float(snap_mode)
        except ValueError:
            step = 1.0
    elif mob_data is not None:
        disp_size = creature_displayed_size(mob_data)
        mob_size = monster_size_value(disp_size)
        if mob_size < 1.0:
            step = 0.5 if mob_size <= 0.0 else float(mob_size)
        else:
            step = 1.0
    else:
        step = 1.0

    if step <= 0.0:
        return (gx, gy)
    return (
        float(math.floor(gx / step) * step),
        float(math.floor(gy / step) * step),
    )


def visible_objects_bounds(
    elements_data: list[dict[str, Any]],
    creatures_data: list[dict[str, Any]],
) -> tuple[float, float, float, float] | None:
    """Compute bounding box `(min_x, min_y, max_x, max_y)` in scene coordinates of all visible map objects.

    Matches `FindNearby` / `canvas bbox allOBJ allMOB` in `bin/mapper_legacy.tcl`.
    """
    xs: list[float] = []
    ys: list[float] = []

    for el in elements_data:
        if el.get("Hidden"):
            continue
        x0 = float(el.get("X", 0.0) or 0.0)
        y0 = float(el.get("Y", 0.0) or 0.0)
        xs.append(x0)
        ys.append(y0)
        for pt in el.get("Points") or []:
            xs.append(float(pt.get("X", 0.0) or 0.0))
            ys.append(float(pt.get("Y", 0.0) or 0.0))
        bbw = float(el.get("BBWidth", 0.0) or 0.0)
        bbh = float(el.get("BBHeight", 0.0) or 0.0)
        if bbw > 0 and bbh > 0:
            xs.append(x0 + bbw)
            ys.append(y0 + bbh)

    for cr in creatures_data:
        if cr.get("Hidden"):
            continue
        gx = float(cr.get("Gx", cr.get("GX", 0.0)) or 0.0)
        gy = float(cr.get("Gy", cr.get("GY", 0.0)) or 0.0)
        sz = max(1.0, monster_size_value(creature_displayed_size(cr)))
        xs.append(gx * BASE_GRID_SCALE)
        ys.append(gy * BASE_GRID_SCALE)
        xs.append((gx + sz) * BASE_GRID_SCALE)
        ys.append((gy + sz) * BASE_GRID_SCALE)

    if not xs or not ys:
        return None
    return (min(xs), min(ys), max(xs), max(ys))


def grid_coord_label(gx: float, gy: float) -> str:
    """Return alphanumeric grid label (e.g. `'A1'`, `'B12'`) for grid coordinates `(gx, gy)`."""
    col = max(0, int(math.floor(gx)))
    row = max(0, int(math.floor(gy))) + 1
    return f"{letter_label(col)}{row}"


def grid_distance_feet(x0: float, y0: float, x1: float, y1: float) -> tuple[float, float, float]:
    """Compute Pathfinder/3.5e 5-10-5 diagonal grid distance in feet, Euclidean feet, and angle degrees.

    Inputs are in scene coordinates (`BASE_GRID_SCALE = 50.0` per 5-ft square).
    """
    dx_sq = abs(x1 - x0) / BASE_GRID_SCALE
    dy_sq = abs(y1 - y0) / BASE_GRID_SCALE
    diag = min(dx_sq, dy_sq)
    straight = max(dx_sq, dy_sq) - diag
    pf_squares = straight + math.floor(diag * 1.5)
    pf_feet = pf_squares * 5.0
    euclid_feet = math.hypot(dx_sq, dy_sq) * 5.0
    angle_deg = (math.degrees(math.atan2(y1 - y0, x1 - x0)) + 360.0) % 360.0
    return (pf_feet, euclid_feet, angle_deg)


try:
    from PySide6.QtCore import QLineF, QPointF, QRectF, Qt, QTimer, Signal
    from PySide6.QtGui import QBrush, QColor, QFont, QPainter, QPen, QPixmap
    from PySide6.QtWidgets import QGraphicsEllipseItem, QGraphicsLineItem, QGraphicsScene

    class BattleMapScene(QGraphicsScene):
        """Hardware-accelerated 2D battle map scene."""

        token_moved = Signal(str, float, float)  # (mob_id, gx, gy)
        element_selected = Signal(str)

        def __init__(self, parent: Any = None) -> None:
            super().__init__(parent)
            self.setSceneRect(0, 0, 40000, 40000)

            self.elements: dict[str, MapElementItem] = {}
            self.element_types: dict[str, str] = {}
            self.creatures: dict[str, CreatureTokenItem] = {}
            self.creature_by_name: dict[str, str] = {}
            self.pixmaps: dict[str, QPixmap] = {}

            self.show_grid: bool = True
            self.show_health_stats: bool = True
            self.show_all_targets: bool = True
            self.creature_grid_snap: str = "nil"
            self.dark_mode: bool = False
            self.combat_mode: bool = False
            self.active_actor_id: str = ""
            self.active_target_source: str = ""
            self.selected_mobs: set[str] = set()
            self.tag_history: list[str] = []
            self.grid_color: str = "blue"
            self.grid_minor_color: str = "#b00b03"
            self.grid_major_color: str = "#345f12"
            self.minor_interval: int = 0
            self.major_interval: int = 0
            self.minor_offset: tuple[int, int] = (0, 0)
            self.major_offset: tuple[int, int] = (0, 0)

            self._target_lines: list[Any] = []
            self.highlighted_element_id: str = ""

        def visible_objects_center(self) -> tuple[float, float] | None:
            """Return `(cx, cy)` scene center of all visible map elements and creatures."""
            bounds = visible_objects_bounds(
                [item.data for item in self.elements.values()],
                [tok.data for tok in self.creatures.values()],
            )
            if bounds is None:
                return None
            x0, y0, x1, y1 = bounds
            return ((x0 + x1) * 0.5, (y0 + y1) * 0.5)

        def aoe_barrier_segments(self) -> list[tuple[float, float, float, float]]:
            """Return line segments `(x0, y0, x1, y1)` of `AOE_GLOBAL_BOUND` if present."""
            item = self.elements.get("AOE_GLOBAL_BOUND")
            if item is None or item.data.get("Hidden"):
                return []
            pts = item._all_points()
            segs: list[tuple[float, float, float, float]] = []
            for i in range(len(pts) - 1):
                segs.append((pts[i].x(), pts[i].y(), pts[i + 1].x(), pts[i + 1].y()))
            return segs

        def set_highlighted_element(self, obj_id: str) -> None:
            if self.highlighted_element_id and self.highlighted_element_id in self.elements:
                self.elements[self.highlighted_element_id].is_highlighted = False
                self.elements[self.highlighted_element_id].update()
            self.highlighted_element_id = obj_id
            if obj_id and obj_id in self.elements:
                self.elements[obj_id].is_highlighted = True
                self.elements[obj_id].update()

        def unlocked_element_ids_by_z(self) -> list[str]:
            """Return unlocked element IDs sorted by `(Z, ID)` matching `cmp_obj_attr_z`."""
            pairs = [
                (int(float(item.data.get("Z", 0) or 0)), oid)
                for oid, item in self.elements.items()
                if not item.data.get("Locked") and not item.data.get("Hidden")
            ]
            pairs.sort()
            return [oid for _z, oid in pairs]

        def elements_at_scene_pos(
            self, scene_pt: QPointF, tolerance: float = 6.0
        ) -> list[str]:
            """Return unlocked element IDs overlapping `scene_pt` within `tolerance`, top-most Z first."""
            probe = QRectF(
                scene_pt.x() - tolerance,
                scene_pt.y() - tolerance,
                tolerance * 2.0,
                tolerance * 2.0,
            )
            found: list[tuple[float, str]] = []
            for item in self.items(probe):
                if isinstance(item, MapElementItem) and item.obj_id in self.elements:
                    if item.data.get("Locked") or item.data.get("Hidden"):
                        continue
                    found.append((float(item.data.get("Z", 0) or 0), item.obj_id))
            found.sort(reverse=True)
            seen: list[str] = []
            for _z, oid in found:
                if oid not in seen:
                    seen.append(oid)
            return seen

        def mobs_at_scene_pos(
            self, scene_pt: QPointF, include_selected: bool = True
        ) -> list[str]:
            """Return ordered list of creature IDs whose token footprint contains `scene_pt`."""
            sx = float(scene_pt.x())
            sy = float(scene_pt.y())
            found: list[str] = []
            for cid, tok in self.creatures.items():
                if not tok.isVisible():
                    continue
                mob_size, _, _, _, _ = tok._area_info()
                s = mob_size * BASE_GRID_SCALE
                x0 = tok.gx * BASE_GRID_SCALE
                y0 = tok.gy * BASE_GRID_SCALE
                if x0 <= sx <= x0 + s and y0 <= sy <= y0 + s:
                    found.append(cid)
            if include_selected:
                for sid in sorted(self.selected_mobs):
                    if sid in self.creatures and sid not in found:
                        found.append(sid)
            return found

        def toggle_mob_selection(self, mob_id: str) -> None:
            if mob_id in self.selected_mobs:
                self.selected_mobs.discard(mob_id)
                if mob_id in self.creatures:
                    self.creatures[mob_id].is_selected = False
                    self.creatures[mob_id].update()
            elif mob_id in self.creatures:
                self.selected_mobs.add(mob_id)
                self.creatures[mob_id].is_selected = True
                self.creatures[mob_id].update()

        def clear_mob_selection(self) -> None:
            for mid in list(self.selected_mobs):
                if mid in self.creatures:
                    self.creatures[mid].is_selected = False
                    self.creatures[mid].update()
            self.selected_mobs.clear()

        def register_pixmap(self, name: str, pixmap: QPixmap) -> None:
            self.pixmaps[name] = pixmap
            self.update()

        def get_pixmap(self, name: str) -> QPixmap | None:
            if name in self.pixmaps:
                return self.pixmaps[name]
            if "=" in name:
                prefix = name.split("=", 1)[0]
                if prefix in self.pixmaps:
                    return self.pixmaps[prefix]
            return None

        def drawBackground(self, painter: QPainter, rect: QRectF) -> None:
            bg_hex = "#232323" if self.dark_mode else "#cccccc"
            painter.fillRect(rect, QColor(bg_hex))

            if not self.show_grid:
                return

            left = int(math.floor(rect.left() / BASE_GRID_SCALE))
            right = int(math.ceil(rect.right() / BASE_GRID_SCALE))
            top = int(math.floor(rect.top() / BASE_GRID_SCALE))
            bottom = int(math.ceil(rect.bottom() / BASE_GRID_SCALE))

            base_pen = QPen(QColor(color_to_hex(self.grid_color)), 1, Qt.PenStyle.DotLine)
            minor_pen = QPen(QColor(color_to_hex(self.grid_minor_color)), 1.5)
            major_pen = QPen(QColor(color_to_hex(self.grid_major_color)), 2.5)

            for gx in range(left, right + 1):
                x = gx * BASE_GRID_SCALE
                if self.major_interval > 0 and (gx - self.major_offset[0]) % self.major_interval == 0:
                    painter.setPen(major_pen)
                elif self.minor_interval > 0 and (gx - self.minor_offset[0]) % self.minor_interval == 0:
                    painter.setPen(minor_pen)
                else:
                    painter.setPen(base_pen)
                painter.drawLine(QLineF(x, rect.top(), x, rect.bottom()))

            for gy in range(top, bottom + 1):
                y = gy * BASE_GRID_SCALE
                if self.major_interval > 0 and (gy - self.major_offset[1]) % self.major_interval == 0:
                    painter.setPen(major_pen)
                elif self.minor_interval > 0 and (gy - self.minor_offset[1]) % self.minor_interval == 0:
                    painter.setPen(minor_pen)
                else:
                    painter.setPen(base_pen)
                painter.drawLine(QLineF(rect.left(), y, rect.right(), y))

            # Draw column letters along top of visible rect and row numbers along left
            label_col = QColor("#aaaaaa" if self.dark_mode else "#3333ff")
            painter.setPen(label_col)
            painter.setFont(QFont("Helvetica", 8))
            for gx in range(max(0, left), right + 1):
                col_rect = QRectF(
                    gx * BASE_GRID_SCALE,
                    rect.top() + 2,
                    BASE_GRID_SCALE,
                    18.0,
                )
                painter.drawText(
                    col_rect,
                    int(Qt.AlignmentFlag.AlignHCenter | Qt.AlignmentFlag.AlignTop),
                    letter_label(gx),
                )
            for gy in range(max(0, top), bottom + 1):
                row_rect = QRectF(
                    rect.left() + 4,
                    gy * BASE_GRID_SCALE,
                    36.0,
                    BASE_GRID_SCALE,
                )
                painter.drawText(
                    row_rect,
                    int(Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter),
                    str(gy + 1),
                )

        def add_or_update_element(
            self,
            obj_id_or_type: str,
            data_or_type: Any,
            maybe_data: dict[str, Any] | None = None,
        ) -> MapElementItem:
            if maybe_data is not None:
                obj_id = str(obj_id_or_type)
                gma_type = str(data_or_type)
                data = dict(maybe_data)
                data.setdefault("ID", obj_id)
            else:
                gma_type = str(obj_id_or_type)
                data = dict(data_or_type)
                obj_id = str(data.get("ID", ""))
            clean_type = gma_type.replace("LS-", "")
            if obj_id in self.elements:
                item = self.elements[obj_id]
                item.gma_type = clean_type
                item.update_data(data)
            else:
                item = MapElementItem(clean_type, data, pixmap_provider=self.get_pixmap)
                self.addItem(item)
                self.elements[obj_id] = item
            self.element_types[obj_id] = clean_type.lower()
            return item

        def place_someone(self, data: dict[str, Any]) -> CreatureTokenItem:
            mob_id = str(data.get("ID", ""))
            name = str(data.get("Name", ""))
            if name and name in self.creature_by_name and self.creature_by_name[name] != mob_id:
                old_id = self.creature_by_name[name]
                self.remove_object(old_id)

            if mob_id in self.creatures:
                token = self.creatures[mob_id]
                token.update_data(data)
            else:
                token = CreatureTokenItem(data, pixmap_provider=self.get_pixmap)
                token.combat_mode = self.combat_mode
                token.is_active_turn = mob_id == self.active_actor_id
                token.is_selected = mob_id in self.selected_mobs
                self.addItem(token)
                self.creatures[mob_id] = token
            if name:
                self.creature_by_name[name] = mob_id
            self.refresh_targets()
            return token

        def update_object_attributes(self, obj_id: str, new_attrs: dict[str, Any]) -> None:
            if obj_id in self.creatures:
                self.creatures[obj_id].update_data(new_attrs)
                self.refresh_targets()
            elif obj_id in self.elements:
                self.elements[obj_id].update_data(new_attrs)

        def add_object_attribute_values(
            self, obj_id: str, attr_name: str, values: list[str]
        ) -> None:
            target_d = None
            item: Any = None
            if obj_id in self.creatures:
                item = self.creatures[obj_id]
                target_d = item.data
            elif obj_id in self.elements:
                item = self.elements[obj_id]
                target_d = item.data
            if target_d is not None and item is not None:
                cur_list = list(target_d.get(attr_name) or [])
                for v in values:
                    if v not in cur_list:
                        cur_list.append(v)
                item.update_data({attr_name: cur_list})
                self.refresh_targets()

        def remove_object_attribute_values(
            self, obj_id: str, attr_name: str, values: list[str]
        ) -> None:
            target_d = None
            item: Any = None
            if obj_id in self.creatures:
                item = self.creatures[obj_id]
                target_d = item.data
            elif obj_id in self.elements:
                item = self.elements[obj_id]
                target_d = item.data
            if target_d is not None and item is not None:
                cur_list = [x for x in (target_d.get(attr_name) or []) if x not in values]
                item.update_data({attr_name: cur_list})
                self.refresh_targets()

        def remove_object(self, obj_id: str) -> None:
            if obj_id == "*":
                for item in list(self.elements.values()):
                    self.removeItem(item)
                for tok in list(self.creatures.values()):
                    self.removeItem(tok)
                self.elements.clear()
                self.element_types.clear()
                self.creatures.clear()
                self.creature_by_name.clear()
                self.refresh_targets()
                return
            if obj_id == "E*":
                for item in list(self.elements.values()):
                    self.removeItem(item)
                self.elements.clear()
                self.element_types.clear()
                return
            if obj_id == "M*":
                for cid, tok in list(self.creatures.items()):
                    if tok.data.get("CreatureType") == 1:
                        self.removeItem(tok)
                        del self.creatures[cid]
                self.refresh_targets()
                return
            if obj_id == "P*":
                for cid, tok in list(self.creatures.items()):
                    if tok.data.get("CreatureType") == 2:
                        self.removeItem(tok)
                        del self.creatures[cid]
                self.refresh_targets()
                return

            if obj_id in self.elements:
                self.removeItem(self.elements.pop(obj_id))
                self.element_types.pop(obj_id, None)
            if obj_id in self.creatures:
                tok = self.creatures.pop(obj_id)
                self.selected_mobs.discard(obj_id)
                name = str(tok.data.get("Name", ""))
                if self.creature_by_name.get(name) == obj_id:
                    self.creature_by_name.pop(name, None)
                self.removeItem(tok)
                self.refresh_targets()

        def resolve_actor_mob_ids(self, actor_id: str) -> list[str]:
            """Resolve an `ActorID` (mob ID, creature Name, `*Monsters*`, or `/regex`) into matching `mob_id`s.

            Ported from `DoCommandI` in `bin/mapper_legacy.tcl` lines 11654-11675.
            """
            if not actor_id:
                return []
            if actor_id == "*Monsters*":
                return [
                    cid
                    for cid, tok in self.creatures.items()
                    if tok.data.get("CreatureType") == 1 and not tok.data.get("Killed")
                ]
            if actor_id in self.creatures:
                return [actor_id]
            if actor_id in self.creature_by_name:
                mid = self.creature_by_name[actor_id]
                if mid in self.creatures:
                    return [mid]
            if actor_id.startswith("/") and len(actor_id) > 1:
                import re

                try:
                    pat = re.compile(actor_id[1:])
                except re.error:
                    return []
                matched: list[str] = []
                for name, mid in self.creature_by_name.items():
                    if mid in self.creatures and not self.creatures[mid].data.get("Killed"):
                        if pat.search(name):
                            matched.append(mid)
                return matched
            # Fallback: strip leading tag_ prefix and match
            for cid, tok in self.creatures.items():
                tname = str(tok.data.get("Name", ""))
                if tname == actor_id or tname.endswith(f"_{actor_id}"):
                    return [cid]
            return []

        def set_combat_state(self, enabled: bool, active_actor_id: str = "") -> None:
            self.combat_mode = enabled
            if active_actor_id or not enabled:
                self.active_actor_id = active_actor_id if enabled else ""
            active_mobs = set(self.resolve_actor_mob_ids(self.active_actor_id)) if self.combat_mode else set()
            for cid, tok in self.creatures.items():
                tok.combat_mode = self.combat_mode
                tok.is_active_turn = (
                    cid in active_mobs
                    or cid == self.active_actor_id
                    or tok.data.get("Name") == self.active_actor_id
                )
                tok.update()
            self.refresh_targets()

        def refresh_targets(self) -> None:
            for item in self._target_lines:
                self.removeItem(item)
            self._target_lines.clear()

            # 1. Draw green dotted SRCTARG box around active_target_source (or active_actor_id)
            src_id = self.active_target_source or self.active_actor_id
            if src_id and src_id in self.creatures:
                stok = self.creatures[src_id]
                if not stok.data.get("Hidden"):
                    ssz, _, _, _, _ = stok._area_info()
                    srect = self.addRect(
                        stok.gx * BASE_GRID_SCALE,
                        stok.gy * BASE_GRID_SCALE,
                        ssz * BASE_GRID_SCALE,
                        ssz * BASE_GRID_SCALE,
                        QPen(QColor("#00cc00"), 3.5, Qt.PenStyle.DotLine),
                    )
                    srect.setZValue(2_000_000_008)
                    self._target_lines.append(srect)

            # 2. Draw target bullseye rings & dashed target lines
            for cid, tok in self.creatures.items():
                if tok.data.get("Hidden"):
                    continue
                if not self.show_all_targets and cid != src_id and not tok.is_active_turn:
                    continue
                targets = tok.data.get("Targets") or []
                if not targets:
                    continue
                src_size, _, _, _, _ = tok._area_info()
                sx = (tok.gx + src_size / 2.0) * BASE_GRID_SCALE
                sy = (tok.gy + src_size / 2.0) * BASE_GRID_SCALE
                is_primary = (cid == src_id) or tok.is_active_turn
                line_color = QColor("#ff3333" if is_primary else "#3388ff")
                for tname in targets:
                    tid = self.creature_by_name.get(tname, tname)
                    ttok = self.creatures.get(tid)
                    if not ttok or ttok.data.get("Hidden"):
                        continue
                    tsize, _, _, _, _ = ttok._area_info()
                    tx = (ttok.gx + tsize / 2.0) * BASE_GRID_SCALE
                    ty = (ttok.gy + tsize / 2.0) * BASE_GRID_SCALE
                    ring = self.addEllipse(
                        ttok.gx * BASE_GRID_SCALE + 2,
                        ttok.gy * BASE_GRID_SCALE + 2,
                        tsize * BASE_GRID_SCALE - 4,
                        tsize * BASE_GRID_SCALE - 4,
                        QPen(line_color, 2.5, Qt.PenStyle.DashLine),
                    )
                    ring.setZValue(2_000_000_009)
                    self._target_lines.append(ring)
                    line = self.addLine(
                        sx,
                        sy,
                        tx,
                        ty,
                        QPen(line_color, 2.5, Qt.PenStyle.DashLine),
                    )
                    line.setZValue(2_000_000_010)
                    self._target_lines.append(line)

        def flash_mark(self, x: float, y: float) -> None:
            """Draw a temporary animated target ring at scene coordinates `(x, y)` for `MARK`."""
            ring = QGraphicsEllipseItem(x - 25, y - 25, 50, 50)
            ring.setPen(QPen(QColor("#ffff00"), 3))
            ring.setZValue(2_100_000_000)
            self.addItem(ring)
            QTimer.singleShot(1500, lambda: self.removeItem(ring) if ring.scene() else None)

        @property
        def tokens(self) -> dict[str, CreatureTokenItem]:
            return self.creatures

        def add_or_update_token(self, obj_id: str, data: dict[str, Any]) -> CreatureTokenItem:
            d = dict(data)
            d.setdefault("ID", obj_id)
            return self.place_someone(d)

        def move_object(self, obj_id: str, gx: float, gy: float) -> None:
            self.update_object_attributes(obj_id, {"GX": gx, "GY": gy, "Gx": gx, "Gy": gy})

        def clear_all(self) -> None:
            self.remove_object("*")

except ImportError:

    class _HeadlessItem:
        def __init__(self, obj_id: str, data: dict[str, Any], gma_type: str = "") -> None:
            self.obj_id = obj_id
            self.gma_type = gma_type
            self.data = dict(data)

        @property
        def gx(self) -> float:
            return float(self.data.get("GX", self.data.get("Gx", 0.0)))

        @property
        def gy(self) -> float:
            return float(self.data.get("GY", self.data.get("Gy", 0.0)))

        def update_data(self, attrs: dict[str, Any]) -> None:
            self.data.update(attrs)

    class BattleMapScene:  # type: ignore[no-redef]
        """Headless fallback scene when PySide6 is not installed."""

        def __init__(self, parent: Any = None) -> None:
            self.elements: dict[str, _HeadlessItem] = {}
            self.element_types: dict[str, str] = {}
            self.creatures: dict[str, _HeadlessItem] = {}
            self.creature_by_name: dict[str, str] = {}
            self.combat_mode: bool = False
            self.active_actor_id: str = ""

        @property
        def tokens(self) -> dict[str, _HeadlessItem]:
            return self.creatures

        def add_or_update_element(self, obj_id_or_type: str, data_or_type: Any, maybe_data: dict[str, Any] | None = None) -> _HeadlessItem:
            if maybe_data is not None:
                obj_id = obj_id_or_type
                gma_type = str(data_or_type)
                data = dict(maybe_data)
            else:
                gma_type = obj_id_or_type
                data = dict(data_or_type)
                obj_id = str(data.get("ID", ""))
            clean_type = gma_type.replace("LS-", "")
            item = _HeadlessItem(obj_id, data, clean_type)
            self.elements[obj_id] = item
            self.element_types[obj_id] = clean_type.lower()
            return item

        def place_someone(self, data: dict[str, Any]) -> _HeadlessItem:
            mob_id = str(data.get("ID", data.get("Name", "")))
            item = _HeadlessItem(mob_id, data, "token")
            self.creatures[mob_id] = item
            if data.get("Name"):
                self.creature_by_name[str(data["Name"])] = mob_id
            return item

        def add_or_update_token(self, obj_id: str, data: dict[str, Any]) -> _HeadlessItem:
            d = dict(data)
            d.setdefault("ID", obj_id)
            return self.place_someone(d)

        def move_object(self, obj_id: str, gx: float, gy: float) -> None:
            if obj_id in self.creatures:
                self.creatures[obj_id].update_data({"GX": gx, "GY": gy, "Gx": gx, "Gy": gy})
            elif obj_id in self.elements:
                self.elements[obj_id].update_data({"GX": gx, "GY": gy, "Gx": gx, "Gy": gy})

        def update_object_attributes(self, obj_id: str, new_attrs: dict[str, Any]) -> None:
            if obj_id in self.creatures:
                self.creatures[obj_id].update_data(new_attrs)
            elif obj_id in self.elements:
                self.elements[obj_id].update_data(new_attrs)

        def add_object_attribute_values(
            self, obj_id: str, attr_name: str, values: list[str]
        ) -> None:
            item = self.creatures.get(obj_id) or self.elements.get(obj_id)
            if item is not None:
                cur_list = list(item.data.get(attr_name) or [])
                for v in values:
                    if v not in cur_list:
                        cur_list.append(v)
                item.update_data({attr_name: cur_list})

        def remove_object_attribute_values(
            self, obj_id: str, attr_name: str, values: list[str]
        ) -> None:
            item = self.creatures.get(obj_id) or self.elements.get(obj_id)
            if item is not None:
                cur_list = [x for x in (item.data.get(attr_name) or []) if x not in values]
                item.update_data({attr_name: cur_list})

        def remove_object(self, obj_id: str) -> None:
            if obj_id == "*":
                self.elements.clear()
                self.element_types.clear()
                self.creatures.clear()
                self.creature_by_name.clear()
                return
            self.elements.pop(obj_id, None)
            self.creatures.pop(obj_id, None)

        def clear_all(self) -> None:
            self.remove_object("*")

