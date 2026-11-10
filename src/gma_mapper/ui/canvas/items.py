"""QGraphicsItem subclasses and condition/marker definitions for GMA battle map elements.

Ported from bin/mapper.tcl.
"""

from __future__ import annotations

import math
import re
from typing import Any

from gma_mapper.core.colors import color_to_hex, contrasting_color, darken_color
from gma_mapper.core.zones import full_creature_area_info
from gma_mapper.net.protocol import from_enum
from gma_mapper.ui.canvas.aoe import (
    aoe_grid_hatch_lines,
    compute_aoe_grids,
    compute_creature_aoe_grids,
    grid_intersection_distance,
)

BASE_GRID_SCALE: float = 50.0  # 1 grid square (5 ft) = 50 scene units at zoom 1.0

MARKER_COLOR: dict[str, str] = {
    "bleed": "red",
    "ability damage": "yellow",
    "ability drained": "orange",
    "energy drained": "black",
    "poisoned": "green",
    "deafened": "black",
    "stable": "sienna",
    "blinded": "black",
    "dazzled": "cyan",
    "confused": "orange",
    "cowering": "sienna",
    "dazed": "purple",
    "fascinated": "cyan",
    "paralyzed": "black",
    "helpless": "gray",
    "staggered": "blue",
    "stunned": "red",
    "dying": "*",
    "disabled": "red",
    "unconscious": "purple",
    "petrified": "gray",
    "entangled": "green",
    "grappled": "orange",
    "pinned": "red",
    "prone": "blue",
    "exhausted": "red",
    "fatigued": "orange",
    "nauseated": "green",
    "sickened": "sienna",
    "flat-footed": "blue",
    "incorporeal": "gray",
    "invisible": "..black",
    "shaken": "sienna",
    "frightened": "yellow",
    "panicked": "red",
}

MARKER_SHAPE: dict[str, str] = {
    "bleed": "|v",
    "ability damage": "|v",
    "ability drained": "|v",
    "energy drained": "v|",
    "poisoned": "o|",
    "deafened": "|<>",
    "stable": "<>|",
    "blinded": "//",
    "dazzled": "//",
    "confused": "=",
    "cowering": "=",
    "dazed": "=",
    "fascinated": "=",
    "paralyzed": "=",
    "helpless": "=",
    "staggered": "=",
    "stunned": "=",
    "dying": "/",
    "disabled": "|",
    "unconscious": "||",
    "petrified": "X",
    "entangled": "#",
    "grappled": "+",
    "pinned": "+",
    "prone": "-",
    "exhausted": "V",
    "fatigued": "V",
    "nauseated": "^",
    "sickened": "^",
    "flat-footed": "O",
    "incorporeal": "O",
    "invisible": "O",
    "shaken": "<>",
    "frightened": "<>",
    "panicked": "<>",
}

MARKER_TRANSPARENT: dict[str, bool] = {
    "incorporeal": True,
    "invisible": True,
}

MARKER_DESCRIPTION: dict[str, str] = {
    "bleed": "Bleeding: take damage each turn unless stopped by a DC 15 Heal check or any spell that cures hit point damage.",
    "ability damage": "Ability Damage: penalties to ability-related checks.",
    "ability drained": "Ability Drained: Ability score reduced with all applicable effects.",
    "energy drained": "Energy Drained: has negative levels (-1 penalty per level drained).",
    "poisoned": "Poisoned: may have onset delay and additional saving throws.",
    "deafened": "Deafened: cannot hear (-4 initiative, 20% verbal spell failure).",
    "stable": "Stable: no longer dying but unconscious.",
    "blinded": "Blinded: cannot see (-2 AC, no Dex bonus to AC, 50% miss chance).",
    "dazzled": "Dazzled: -1 on attack rolls and sight-based Perception checks.",
    "confused": "Confused: cannot act normally or tell ally from foe.",
    "cowering": "Cowering: frozen in fear and can take no actions (-2 AC, no Dex bonus).",
    "dazed": "Dazed: unable to act normally (no actions, no AC penalty).",
    "fascinated": "Fascinated: entranced by Su or Sp effect.",
    "paralyzed": "Paralyzed: frozen in place, effective Dex and Str of 0.",
    "helpless": "Helpless: paralyzed, held, bound, sleeping, unconscious (Dex 0).",
    "staggered": "Staggered: only single move or standard action.",
    "stunned": "Stunned: drop everything held, take no actions (-2 AC, lose Dex bonus).",
    "dying": "Dying: unconscious, no actions; DC 10 Con check each turn to stabilize.",
    "disabled": "Disabled: conscious, single move or standard action at 1/2 speed.",
    "unconscious": "Unconscious: knocked out and helpless.",
    "petrified": "Petrified: turned to stone, unconscious.",
    "entangled": "Entangled: ensnared, move at 1/2 speed (-2 attack, -4 Dex).",
    "grappled": "Grappled: restrained, cannot move (-4 Dex, -2 attacks).",
    "pinned": "Pinned: tightly bound, cannot move (no Dex bonus, -4 AC).",
    "prone": "Prone: lying on ground (-4 melee attack, +4 AC vs ranged, -4 AC vs melee).",
    "exhausted": "Exhausted: move 1/2 speed, cannot run or charge (-6 Str and Dex).",
    "fatigued": "Fatigued: can't run or charge (-2 Str and Dex).",
    "nauseated": "Nauseated: cannot attack or cast spells; single move action only.",
    "sickened": "Sickened: -2 on attacks, weapon damage, saves, skill and ability checks.",
    "flat-footed": "Flat-Footed: loses Dex bonus to AC, cannot make attacks of opportunity.",
    "incorporeal": "Incorporeal: no physical body.",
    "invisible": "Invisible: +2 attack vs sighted opponent, ignore Dex bonus to AC.",
    "shaken": "Shaken: -2 on attacks, saving throws, skill checks, ability checks.",
    "frightened": "Frightened: flees from source of fear (-2 attacks, saves, checks).",
    "panicked": "Panicked: drop held items and flee at top speed (-2 saves and checks).",
}


def creature_status_conditions(
    creature_data: dict[str, Any],
    calc_conditions: list[str] | None = None,
) -> list[str]:
    """Return merged list of status condition names for `creature_data`."""
    conditions = list(calc_conditions or [])
    health = creature_data.get("Health") or {}
    if isinstance(health, dict) and health:
        cond = health.get("Condition", "")
        if cond and cond not in conditions:
            conditions.append(cond)
        if health.get("IsFlatFooted") and "flat-footed" not in conditions:
            conditions.append("flat-footed")
        if health.get("IsStable") and "stable" not in conditions:
            conditions.append("stable")
    for cond in creature_data.get("StatusList") or []:
        if cond and cond not in conditions:
            conditions.append(cond)
    return conditions


def creature_status_transparent(
    creature_data: dict[str, Any],
    custom_transparent: dict[str, bool] | None = None,
) -> bool:
    """Return True if the creature should be rendered semi-transparent."""
    if creature_data.get("Hidden"):
        return True
    trans_map = dict(MARKER_TRANSPARENT)
    if custom_transparent:
        trans_map.update(custom_transparent)
    for cond in creature_status_conditions(creature_data):
        if trans_map.get(cond):
            return True
    return False


def creature_image_candidates(creature_data: dict[str, Any]) -> list[str]:
    """Return ordered list of GMA server image candidate names for `creature_data`.

    Matches `PlaceSomeone` in `bin/mapper_legacy.tcl` lines 7431-7470:
    - Strips trailing ` #<digits>` from numbered monsters (e.g. `'Goblin #1'` -> `'Goblin'`).
    - Prefixes with `'#'`, `'='`, `'-'`, `'+'` for `Skin` `0..3` and `'^<Skin>^'`.
    - Prefixes with `'%'` when `Killed` is True.
    - Also includes the bare name as a fallback.
    """
    raw_name = str(creature_data.get("Name", "") or "").strip()
    if not raw_name:
        return []
    m = re.match(r"^(.*) #\d+$", raw_name)
    mob_img_name = m.group(1) if m else raw_name

    try:
        skin_idx = int(creature_data.get("Skin", 0) or 0)
    except (ValueError, TypeError):
        skin_idx = 0

    killed = bool(creature_data.get("Killed", False))
    i_pfx = "%" if killed else ""
    candidates: list[str] = []

    if killed and skin_idx == 0:
        candidates.append(f"%{mob_img_name}")

    skin_chars = "#=-+"
    if 0 <= skin_idx < 4:
        candidates.append(f"{i_pfx}{skin_chars[skin_idx]}{mob_img_name}")
    candidates.append(f"{i_pfx}^{skin_idx}^{mob_img_name}")

    # Also allow non-killed image fallback when killed if no '%...' image exists
    if killed:
        if 0 <= skin_idx < 4:
            candidates.append(f"{skin_chars[skin_idx]}{mob_img_name}")
        candidates.append(f"^{skin_idx}^{mob_img_name}")

    # Bare name fallback
    if mob_img_name not in candidates:
        candidates.append(mob_img_name)
    if raw_name not in candidates:
        candidates.append(raw_name)
    return candidates


def resolve_condition_markers(
    creature_data: dict[str, Any],
    custom_shapes: dict[str, str] | None = None,
    custom_colors: dict[str, str] | None = None,
) -> list[tuple[str, str, str]]:
    """Return `[(shape, hex_color, dash_pattern), ...]` for a creature's conditions."""
    shapes = dict(MARKER_SHAPE)
    if custom_shapes:
        shapes.update(custom_shapes)
    colors = dict(MARKER_COLOR)
    if custom_colors:
        colors.update(custom_colors)

    mob_color = creature_data.get("Color") or "black"
    result: list[tuple[str, str, str]] = []
    for cond in creature_status_conditions(creature_data):
        if cond in shapes and cond in colors:
            shape = shapes[cond]
            raw_color = colors[cond]
            if raw_color == "*":
                raw_color = mob_color
            dash = ""
            if raw_color.startswith("--"):
                raw_color = raw_color[2:]
                dash = "-"
            elif raw_color.startswith(".."):
                raw_color = raw_color[2:]
                dash = "."
            result.append((shape, color_to_hex(raw_color), dash))
    return result


try:
    from PySide6.QtCore import QPointF, QRectF, Qt
    from PySide6.QtGui import (
        QBrush,
        QColor,
        QFont,
        QPainter,
        QPainterPath,
        QPen,
        QPixmap,
        QPolygonF,
    )
    from PySide6.QtWidgets import (
        QGraphicsItem,
        QGraphicsObject,
        QStyleOptionGraphicsItem,
        QWidget,
    )

    def make_qpen(
        color_str: str,
        width: float = 1.0,
        dash_enum_or_str: int | str = 0,
    ) -> QPen:
        """Create a QPen from a GMA color name/hex, line width, and Dash enum or string."""
        if not color_str:
            return QPen(Qt.PenStyle.NoPen)
        qcolor = QColor(color_to_hex(color_str))
        pen = QPen(qcolor, max(1.0, float(width)))
        dash_str = (
            from_enum("Dash", dash_enum_or_str)
            if isinstance(dash_enum_or_str, int)
            else str(dash_enum_or_str)
        )
        if dash_str in ("-", "--"):
            pen.setStyle(Qt.PenStyle.DashLine)
        elif dash_str in (".", "..", ","):
            pen.setStyle(Qt.PenStyle.DotLine)
        elif dash_str == "-.":
            pen.setStyle(Qt.PenStyle.DashDotLine)
        elif dash_str == "-..":
            pen.setStyle(Qt.PenStyle.DashDotDotLine)
        else:
            pen.setStyle(Qt.PenStyle.SolidLine)
        return pen

    def make_qbrush(fill_str: str, stipple: str = "") -> QBrush:
        """Create a QBrush from a GMA fill color and optional stipple pattern."""
        if not fill_str or fill_str == "nil":
            return QBrush(Qt.BrushStyle.NoBrush)
        qcolor = QColor(color_to_hex(fill_str))
        alpha_map = {
            "gray12": 36,
            "gray25": 68,
            "gray50": 128,
            "gray75": 192,
        }
        if stipple in alpha_map:
            qcolor.setAlpha(alpha_map[stipple])
        return QBrush(qcolor)

    def _draw_arrowhead(
        painter: QPainter, tip: QPointF, prev: QPointF, color: QColor, size: float = 14.0
    ) -> None:
        dx = tip.x() - prev.x()
        dy = tip.y() - prev.y()
        length = math.hypot(dx, dy)
        if length < 1e-3:
            return
        ux = dx / length
        uy = dy / length
        px = -uy
        py = ux
        wing = size * 0.48
        base_x = tip.x() - ux * size
        base_y = tip.y() - uy * size
        p1 = QPointF(base_x + px * wing, base_y + py * wing)
        p2 = QPointF(base_x - px * wing, base_y - py * wing)
        painter.save()
        painter.setPen(QPen(color, 1))
        painter.setBrush(QBrush(color))
        painter.drawPolygon(QPolygonF([tip, p1, p2]))
        painter.restore()

    class MapElementItem(QGraphicsItem):
        """Graphics item representing a vector/raster map element (`RECT`, `LINE`, `POLY`, `CIRC`, `ARC`, `SAOE`, `TEXT`, `TILE`)."""

        def __init__(
            self,
            gma_type: str,
            data: dict[str, Any],
            pixmap_provider: Any = None,
        ) -> None:
            super().__init__()
            self.gma_type = gma_type.replace("LS-", "")
            self.data = dict(data)
            self.obj_id: str = str(self.data.get("ID", ""))
            self.pixmap_provider = pixmap_provider
            self.is_highlighted: bool = False
            self._sync_properties()

        def update_data(self, new_data: dict[str, Any]) -> None:
            self.prepareGeometryChange()
            self.data.update(new_data)
            self._sync_properties()
            self.update()

        def _sync_properties(self) -> None:
            z = float(self.data.get("Z", 0))
            self.setZValue(z)
            self.setVisible(not bool(self.data.get("Hidden", False)))

        def _all_points(self) -> list[QPointF]:
            pts = [QPointF(float(self.data.get("X", 0.0)), float(self.data.get("Y", 0.0)))]
            for p in self.data.get("Points") or []:
                pts.append(QPointF(float(p.get("X", 0.0)), float(p.get("Y", 0.0))))
            return pts

        def boundingRect(self) -> QRectF:
            pts = self._all_points()
            if self.gma_type == "TILE":
                x0 = pts[0].x()
                y0 = pts[0].y()
                w = float(self.data.get("BBWidth", 0.0) or 0.0)
                h = float(self.data.get("BBHeight", 0.0) or 0.0)
                if (w <= 0 or h <= 0) and self.pixmap_provider:
                    img_name = str(self.data.get("Image", ""))
                    pm = self.pixmap_provider(img_name) if img_name else None
                    if pm and not pm.isNull():
                        w = float(pm.width())
                        h = float(pm.height())
                w = w or BASE_GRID_SCALE
                h = h or BASE_GRID_SCALE
                return QRectF(x0, y0, w, h).adjusted(-4, -4, 4, 4)
            if self.gma_type == "TEXT":
                x0 = pts[0].x()
                y0 = pts[0].y()
                return QRectF(x0 - 300, y0 - 150, 600, 300)
            if self.gma_type in ("SAOE", "AOE") and len(pts) >= 2:
                x0, y0 = pts[0].x(), pts[0].y()
                xx, yy = pts[-1].x(), pts[-1].y()
                gx0, gy0 = int(x0 / BASE_GRID_SCALE), int(y0 / BASE_GRID_SCALE)
                gxx, gyy = int(xx / BASE_GRID_SCALE), int(yy / BASE_GRID_SCALE)
                r = (grid_intersection_distance(gx0, gy0, gxx, gyy) + 2) * BASE_GRID_SCALE
                return QRectF(x0 - r, y0 - r, 2 * r, 2 * r)
            if len(pts) == 1:
                return QRectF(pts[0].x() - 10, pts[0].y() - 10, 20, 20)
            xs = [p.x() for p in pts]
            ys = [p.y() for p in pts]
            pad = float(self.data.get("Width", 1)) + 16.0
            return QRectF(
                min(xs) - pad,
                min(ys) - pad,
                (max(xs) - min(xs)) + 2 * pad,
                (max(ys) - min(ys)) + 2 * pad,
            )

        def paint(
            self,
            painter: QPainter,
            option: QStyleOptionGraphicsItem,
            widget: QWidget | None = None,
        ) -> None:
            pts = self._all_points()
            line_col = str(self.data.get("Line", ""))
            fill_col = str(self.data.get("Fill", ""))
            stipple = str(self.data.get("Stipple", ""))
            width = float(self.data.get("Width", 1))
            dash = self.data.get("Dash", 0)

            pen = make_qpen(line_col, width, dash)
            brush = make_qbrush(fill_col, stipple)
            painter.setPen(pen)
            painter.setBrush(brush)

            if self.gma_type == "RECT" and len(pts) >= 2:
                rect = QRectF(pts[0], pts[1]).normalized()
                painter.drawRect(rect)
            elif self.gma_type == "CIRC" and len(pts) >= 2:
                rect = QRectF(pts[0], pts[1]).normalized()
                painter.drawEllipse(rect)
            elif self.gma_type == "ARC" and len(pts) >= 2:
                rect = QRectF(pts[0], pts[1]).normalized()
                start_deg = int(float(self.data.get("Start", 0.0)) * 16)
                extent_deg = int(float(self.data.get("Extent", 90.0)) * 16)
                raw_mode = self.data.get("ArcMode", 0)
                arc_mode = (
                    from_enum("ArcMode", int(raw_mode))
                    if isinstance(raw_mode, int)
                    else str(raw_mode)
                )
                if arc_mode == "arc":
                    painter.setBrush(Qt.BrushStyle.NoBrush)
                    painter.drawArc(rect, start_deg, extent_deg)
                elif arc_mode == "chord":
                    painter.drawChord(rect, start_deg, extent_deg)
                else:
                    painter.drawPie(rect, start_deg, extent_deg)
            elif self.gma_type == "LINE" and len(pts) >= 2:
                # Note: in Tcl mapper (line 4739), LS-LINE uses Fill or Line for stroke color
                stroke_col = fill_col or line_col or "black"
                line_pen = make_qpen(stroke_col, width, dash)
                painter.setPen(line_pen)
                painter.setBrush(Qt.BrushStyle.NoBrush)
                poly = QPolygonF(pts)
                painter.drawPolyline(poly)
                raw_arrow = self.data.get("Arrow", 0)
                arrow_mode = (
                    from_enum("Arrow", int(raw_arrow))
                    if isinstance(raw_arrow, int)
                    else str(raw_arrow)
                )
                arrow_qcol = QColor(color_to_hex(stroke_col))
                arrow_sz = max(12.0, width * 3.5)
                if arrow_mode in ("first", "both"):
                    _draw_arrowhead(painter, pts[0], pts[1], arrow_qcol, arrow_sz)
                if arrow_mode in ("last", "both"):
                    _draw_arrowhead(painter, pts[-1], pts[-2], arrow_qcol, arrow_sz)
            elif self.gma_type in ("SAOE", "AOE") and len(pts) >= 2:
                x0, y0 = pts[0].x(), pts[0].y()
                xx, yy = pts[-1].x(), pts[-1].y()
                gx0 = int(round(x0 / BASE_GRID_SCALE))
                gy0 = int(round(y0 / BASE_GRID_SCALE))
                gxx = int(round(xx / BASE_GRID_SCALE))
                gyy = int(round(yy / BASE_GRID_SCALE))
                raw_shape = self.data.get("AoEShape", 1)
                shape_str = (
                    from_enum("AoEShape", int(raw_shape))
                    if isinstance(raw_shape, int)
                    else str(raw_shape or "radius")
                )
                aoe_col_hex = color_to_hex(fill_col or line_col or "red")
                aoe_qcol = QColor(aoe_col_hex)
                line_qcol = QColor(color_to_hex(line_col or fill_col or "black"))

                # 1. Origin '+' crosshair at (x0, y0)
                painter.setPen(QPen(aoe_qcol, 3.5))
                painter.setBrush(Qt.BrushStyle.NoBrush)
                painter.drawLine(QPointF(x0 - 10, y0), QPointF(x0 + 10, y0))
                painter.drawLine(QPointF(x0, y0 - 10), QPointF(x0, y0 + 10))

                # 2. Target '⊕' reticle at (xx, yy)
                painter.drawEllipse(QRectF(xx - 10, yy - 10, 20, 20))
                painter.drawLine(QPointF(xx - 5, yy - 5), QPointF(xx + 5, yy + 5))
                painter.drawLine(QPointF(xx - 5, yy + 5), QPointF(xx + 5, yy - 5))

                # 3. Preview guide while dragging
                radius_grids = grid_intersection_distance(gx0, gy0, gxx, gyy)
                r_px = radius_grids * BASE_GRID_SCALE
                if self.data.get("_preview") and radius_grids > 0:
                    painter.setPen(QPen(aoe_qcol, 2.5, Qt.PenStyle.DashLine))
                    painter.drawLine(QPointF(x0, y0), QPointF(xx, yy))
                    _draw_arrowhead(painter, QPointF(xx, yy), QPointF(x0, y0), aoe_qcol, 15.0)
                    painter.setPen(QPen(line_qcol, 2.5, Qt.PenStyle.DashLine))
                    if shape_str == "radius":
                        painter.drawEllipse(QPointF(x0, y0), r_px, r_px)
                    elif shape_str == "cone":
                        theta0 = math.atan2(y0 - yy, xx - x0)
                        start_deg = math.degrees(theta0 - math.pi / 4.0)
                        painter.drawPie(
                            QRectF(x0 - r_px, y0 - r_px, 2 * r_px, 2 * r_px),
                            int(start_deg * 16),
                            90 * 16,
                        )

                # 4. Diagonal cross-hatch across all affected grid squares
                barriers: list[tuple[float, float, float, float]] = []
                sc = self.scene()
                spread = bool(self.data.get("_spread", False))
                if sc is not None and hasattr(sc, "aoe_barrier_segments"):
                    barriers = sc.aoe_barrier_segments()
                grids = compute_aoe_grids(
                    gx0, gy0, gxx, gyy, shape=shape_str, spread=spread, barrier_segments=barriers
                )
                self.data["AoEGrids"] = grids
                hatch_pen = QPen(aoe_qcol, 3.0)
                painter.setPen(hatch_pen)
                for gx, gy in grids:
                    for lx1, ly1, lx2, ly2 in aoe_grid_hatch_lines(gx, gy, local_aura=False):
                        painter.drawLine(QPointF(lx1, ly1), QPointF(lx2, ly2))

            elif self.gma_type == "POLY" and len(pts) >= 2:
                raw_join = self.data.get("Join", 0)
                join_str = (
                    from_enum("Join", int(raw_join))
                    if isinstance(raw_join, int)
                    else str(raw_join)
                )
                if join_str == "miter":
                    pen.setJoinStyle(Qt.PenJoinStyle.MiterJoin)
                elif join_str == "round":
                    pen.setJoinStyle(Qt.PenJoinStyle.RoundJoin)
                else:
                    pen.setJoinStyle(Qt.PenJoinStyle.BevelJoin)
                painter.setPen(pen)
                spline = int(self.data.get("Spline", 0) or 0)
                if spline > 0 and len(pts) >= 3:
                    path = QPainterPath()
                    n = len(pts)
                    mid0 = QPointF(
                        (pts[-1].x() + pts[0].x()) * 0.5,
                        (pts[-1].y() + pts[0].y()) * 0.5,
                    )
                    path.moveTo(mid0)
                    for i in range(n):
                        nxt = pts[(i + 1) % n]
                        mid = QPointF(
                            (pts[i].x() + nxt.x()) * 0.5,
                            (pts[i].y() + nxt.y()) * 0.5,
                        )
                        path.quadTo(pts[i], mid)
                    path.closeSubpath()
                    painter.drawPath(path)
                else:
                    poly = QPolygonF(pts)
                    painter.drawPolygon(poly)
            elif self.gma_type == "TEXT":
                font_d = self.data.get("Font") or {}
                family = str(font_d.get("Family") or "Helvetica")
                size = max(6, int(float(font_d.get("Size") or 12)))
                weight = QFont.Weight.Bold if font_d.get("Weight") else QFont.Weight.Normal
                italic = bool(font_d.get("Slant"))
                qfont = QFont(family, size, weight, italic)
                painter.setFont(qfont)
                text_col = fill_col or line_col or "white"
                painter.setPen(QColor(color_to_hex(text_col)))
                text_str = str(self.data.get("Text", ""))
                raw_anchor = self.data.get("Anchor", 0)
                anchor = (
                    from_enum("Anchor", int(raw_anchor))
                    if isinstance(raw_anchor, int)
                    else str(raw_anchor)
                )
                fm = painter.fontMetrics()
                tw = float(fm.horizontalAdvance(text_str))
                th = float(fm.height())
                x0 = pts[0].x()
                y0 = pts[0].y()
                if "w" in anchor:
                    rx = x0
                elif "e" in anchor:
                    rx = x0 - tw
                else:
                    rx = x0 - tw * 0.5
                if "n" in anchor:
                    ry = y0
                elif "s" in anchor:
                    ry = y0 - th
                else:
                    ry = y0 - th * 0.5
                painter.drawText(
                    QRectF(rx, ry, tw + 8, th + 4),
                    Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter,
                    text_str,
                )
            elif self.gma_type == "TILE":
                img_name = str(self.data.get("Image", ""))
                pixmap: QPixmap | None = None
                if self.pixmap_provider and img_name:
                    pixmap = self.pixmap_provider(img_name)
                w = float(self.data.get("BBWidth", 0.0) or 0.0)
                h = float(self.data.get("BBHeight", 0.0) or 0.0)
                if pixmap and not pixmap.isNull():
                    if w <= 0 or h <= 0:
                        w = float(pixmap.width())
                        h = float(pixmap.height())
                    target_rect = QRectF(pts[0].x(), pts[0].y(), w, h)
                    painter.drawPixmap(target_rect.toRect(), pixmap)
                else:
                    w = w or BASE_GRID_SCALE
                    h = h or BASE_GRID_SCALE
                    target_rect = QRectF(pts[0].x(), pts[0].y(), w, h)
                    painter.setPen(QPen(QColor("#ff3333"), 2, Qt.PenStyle.DashLine))
                    painter.setBrush(QBrush(QColor(80, 20, 20, 80)))
                    painter.drawRect(target_rect)
                    painter.drawText(target_rect, Qt.AlignmentFlag.AlignCenter, img_name)

            if self.is_highlighted:
                painter.setPen(QPen(QColor("#ffff00"), 3, Qt.PenStyle.DashLine))
                painter.setBrush(Qt.BrushStyle.NoBrush)
                painter.drawRect(self.boundingRect().adjusted(2, 2, -2, -2))

    class CreatureTokenItem(QGraphicsObject):
        """Graphics item representing a creature/player token (`PS`/`CREATURE`) with reach, health gauge, and condition markers."""

        def __init__(
            self,
            data: dict[str, Any],
            pixmap_provider: Any = None,
        ) -> None:
            super().__init__()
            self.data: dict[str, Any] = dict(data)
            self.mob_id: str = str(self.data.get("ID", ""))
            self.pixmap_provider = pixmap_provider
            self.is_active_turn: bool = False
            self.is_selected: bool = False
            self.combat_mode: bool = False
            self._sync_position()

        def update_data(self, new_data: dict[str, Any]) -> None:
            self.prepareGeometryChange()
            self.data.update(new_data)
            self._sync_position()
            self.update()

        @property
        def gx(self) -> float:
            return float(self.data.get("Gx", self.data.get("GX", 0.0)))

        @property
        def gy(self) -> float:
            return float(self.data.get("Gy", self.data.get("GY", 0.0)))

        def _sync_position(self) -> None:
            from gma_mapper.ui.canvas.context_menu import build_token_tooltip

            gx = self.gx
            gy = self.gy
            self.setPos(gx * BASE_GRID_SCALE, gy * BASE_GRID_SCALE)
            self.setZValue(2_000_000_000)
            self.setVisible(not bool(self.data.get("Hidden", False)))
            if creature_status_transparent(self.data) or self.data.get("Dim"):
                self.setOpacity(0.55)
            else:
                self.setOpacity(1.0)
            self.setToolTip(build_token_tooltip(self.data))

        def _area_info(self) -> tuple[float, int, int, list[list[int]], dict[str, Any]]:
            info = full_creature_area_info(self.data)
            if not info:
                return (1.0, 0, 1, [[2]], {})
            return (
                float(info.space),
                int(info.natural),
                int(info.extended),
                info.matrix,
                info.custom_reach or {},
            )

        def boundingRect(self) -> QRectF:
            mob_size, mob_area, mob_reach, _, _ = self._area_info()
            s = mob_size * BASE_GRID_SCALE
            aoe_r = 0.0
            for k in ("AoE", "_AoE"):
                aoe = self.data.get(k)
                if isinstance(aoe, dict):
                    aoe_r = max(aoe_r, float(aoe.get("Radius", 0.0) or 0.0))
            margin = max(float(mob_area), float(mob_reach), aoe_r, 1.0) * BASE_GRID_SCALE + 28.0
            return QRectF(-margin, -margin, s + 2 * margin, s + 2 * margin)

        def shape(self) -> QPainterPath:
            """Restrict hit-testing and hover tooltips strictly to the creature's token footprint `[0, s) x [0, s)`."""
            mob_size, _, _, _, _ = self._area_info()
            s = max(0.5, mob_size) * BASE_GRID_SCALE
            path = QPainterPath()
            path.addRect(QRectF(0.0, 0.0, s, s))
            return path

        def paint(
            self,
            painter: QPainter,
            option: QStyleOptionGraphicsItem,
            widget: QWidget | None = None,
        ) -> None:
            mob_size, mob_area, mob_reach, mob_matrix, _ = self._area_info()
            s = mob_size * BASE_GRID_SCALE
            mob_color_hex = color_to_hex(str(self.data.get("Color") or "red"))
            mob_qcolor = QColor(mob_color_hex)

            # 1. Threat / Reach zones in combat mode
            if self.combat_mode and self.is_active_turn and mob_matrix:
                start_offset = -max(mob_area, mob_reach) * BASE_GRID_SCALE
                for r_idx, row in enumerate(mob_matrix):
                    for c_idx, cell in enumerate(row):
                        if cell == 0:
                            continue
                        rx = start_offset + c_idx * BASE_GRID_SCALE
                        ry = start_offset + r_idx * BASE_GRID_SCALE
                        cell_rect = QRectF(rx, ry, BASE_GRID_SCALE, BASE_GRID_SCALE)
                        if cell == 2:
                            c2 = QColor(mob_qcolor)
                            c2.setAlpha(55)
                            painter.fillRect(cell_rect, c2)
                        elif cell == 1 and mob_reach > 0:
                            c1 = QColor(mob_qcolor)
                            c1.setAlpha(30)
                            painter.fillRect(cell_rect, c1)
                            painter.setPen(QPen(mob_qcolor, 1, Qt.PenStyle.DotLine))
                            painter.drawRect(cell_rect)

            # 2. AoE and _AoE perimeter-emanation grid cross-hatches (matches RenderSomeone lines 7278-7342)
            orig_x = self.gx * BASE_GRID_SCALE
            orig_y = self.gy * BASE_GRID_SCALE
            for attr_key, is_local in (("AoE", False), ("_AoE", True)):
                aoe = self.data.get(attr_key) or {}
                if isinstance(aoe, dict) and float(aoe.get("Radius", 0.0) or 0.0) > 0:
                    rad_sq = float(aoe["Radius"])
                    aoe_col = QColor(color_to_hex(str(aoe.get("Color") or mob_color_hex)))
                    pen_style = Qt.PenStyle.DotLine if is_local else Qt.PenStyle.SolidLine
                    painter.setPen(QPen(aoe_col, 3.0, pen_style))
                    painter.setBrush(Qt.BrushStyle.NoBrush)
                    for gx, gy in compute_creature_aoe_grids(self.data, rad_sq):
                        for lx1, ly1, lx2, ly2 in aoe_grid_hatch_lines(gx, gy, local_aura=is_local):
                            painter.drawLine(
                                QPointF(lx1 - orig_x, ly1 - orig_y),
                                QPointF(lx2 - orig_x, ly2 - orig_y),
                            )

            # 2b. Selection highlight ring
            if self.is_selected:
                sel_rect = QRectF(-4, -4, s + 8, s + 8)
                painter.setPen(QPen(QColor("#00ffff"), 2.5, Qt.PenStyle.DashLine))
                painter.setBrush(Qt.BrushStyle.NoBrush)
                painter.drawRect(sel_rect)

            # 3. Token image or circular base (matches PlaceSomeone in bin/mapper_legacy.tcl)
            token_rect = QRectF(0, 0, s, s)
            name = str(self.data.get("Name", ""))
            is_killed = bool(self.data.get("Killed", False))
            fill_qcolor = QColor("#000000" if is_killed else "#ffffff")
            text_qcolor = QColor("#ffffff" if is_killed else "#000000")

            pixmap: QPixmap | None = None
            if self.pixmap_provider:
                for cand in creature_image_candidates(self.data):
                    pixmap = self.pixmap_provider(cand)
                    if pixmap is not None and not pixmap.isNull():
                        break

            if pixmap and not pixmap.isNull():
                if not creature_status_transparent(self.data):
                    painter.setPen(QPen(mob_qcolor, 2))
                    painter.setBrush(QBrush(fill_qcolor))
                    painter.drawEllipse(token_rect)
                painter.drawPixmap(token_rect.toRect(), pixmap)
                painter.setPen(QPen(mob_qcolor, 2.5))
                painter.setBrush(Qt.BrushStyle.NoBrush)
                painter.drawEllipse(token_rect)
            else:
                painter.setPen(QPen(mob_qcolor, 2.5))
                painter.setBrush(QBrush(fill_qcolor))
                painter.drawEllipse(token_rect)
                painter.setPen(text_qcolor)
                font = QFont("Helvetica", max(8, int(s * 0.18)), QFont.Weight.Bold)
                painter.setFont(font)
                painter.drawText(token_rect, Qt.AlignmentFlag.AlignCenter, name[:10])

            # 4. Killed X indicator
            if is_killed:
                painter.setPen(QPen(mob_qcolor, 5))
                painter.drawLine(QPointF(0, 0), QPointF(s, s))
                painter.drawLine(QPointF(s, 0), QPointF(0, s))

            # 5. Status condition markers
            self._paint_status_markers(painter, s)

            # 6. Health bar (left edge)
            self._paint_health_bar(painter, s)

            # 7. Elevation / Movement Mode / Note Tag / Nameplate badge
            elev = int(self.data.get("Elev", 0) or 0)
            mmode = from_enum("MoveMode", int(self.data.get("MoveMode", 0) or 0))
            note = str(self.data.get("Note", "") or "")
            mode_icons = {
                "fly": "▲",
                "climb": "🧗",
                "swim": "≈",
                "burrow": "▼",
            }
            mode_tag = mode_icons.get(mmode, "")
            parts = [p for p in (mode_tag, name) if p]
            label = " ".join(parts)
            if elev != 0:
                label = f"{label} ({elev:+d}')"
            if label:
                badge_rect = QRectF(-10, s + 2, s + 20, 16)
                badge_bg = QColor(darken_color(mob_color_hex, 40))
                badge_bg.setAlpha(210)
                painter.fillRect(badge_rect, badge_bg)
                painter.setPen(QColor("#ffffff"))
                font = QFont("Helvetica", 8, QFont.Weight.Bold)
                painter.setFont(font)
                painter.drawText(badge_rect, Qt.AlignmentFlag.AlignCenter, label)
            if note:
                note_rect = QRectF(-10, -18, s + 20, 15)
                painter.fillRect(note_rect, QColor(25, 25, 90, 185))
                painter.setPen(QColor("#ffff88"))
                font = QFont("Helvetica", 7, QFont.Weight.Bold)
                painter.setFont(font)
                painter.drawText(note_rect, Qt.AlignmentFlag.AlignCenter, note)

        def _paint_health_bar(self, painter: QPainter, s: float) -> None:
            sc = self.scene()
            if sc is not None and not getattr(sc, "show_health_stats", True):
                return
            health = self.data.get("Health") or {}
            if not isinstance(health, dict):
                return
            max_hp = int(health.get("MaxHP", 0) or 0)
            if max_hp <= 0:
                return
            lethal = int(health.get("LethalDamage", 0) or 0)
            nonlethal = int(health.get("NonLethalDamage", 0) or 0)
            cur_hp = max(0, max_hp - lethal - nonlethal)
            ratio = max(0.0, min(1.0, cur_hp / float(max_hp)))

            bar_rect = QRectF(-8, 0, 6, s)
            painter.fillRect(bar_rect, QColor("#222222"))
            fill_h = s * ratio
            bar_color = "#00cc00" if ratio > 0.5 else ("#ffcc00" if ratio > 0.2 else "#ff0000")
            painter.fillRect(QRectF(-8, s - fill_h, 6, fill_h), QColor(bar_color))
            painter.setPen(QPen(QColor("#ffffff"), 1))
            painter.drawRect(bar_rect)

        def _paint_status_markers(self, painter: QPainter, s: float) -> None:
            markers = resolve_condition_markers(self.data)
            if not markers:
                return
            vlo = 0.0
            vro = 0.0
            oo = 0.0
            for shape, hex_col, dash in markers:
                pen = make_qpen(hex_col, 4.0, dash)
                outline_col = QColor(contrasting_color(hex_col))
                painter.setPen(pen)
                painter.setBrush(Qt.BrushStyle.NoBrush)
                if shape == "O":
                    painter.drawEllipse(QRectF(oo, oo, s - 2 * oo, s - 2 * oo))
                    oo += 4.0
                elif shape == "<>":
                    poly = QPolygonF(
                        [
                            QPointF(s * 0.5, oo),
                            QPointF(s - oo, s * 0.5),
                            QPointF(s * 0.5, s - oo),
                            QPointF(oo, s * 0.5),
                        ]
                    )
                    painter.drawPolygon(poly)
                    oo += 4.0
                elif shape == "V":
                    poly = QPolygonF(
                        [QPointF(oo, oo), QPointF(s - oo, oo), QPointF(s * 0.5, s - oo)]
                    )
                    painter.drawPolygon(poly)
                    oo += 4.0
                elif shape == "^":
                    poly = QPolygonF(
                        [QPointF(s * 0.5, oo), QPointF(oo, s - oo), QPointF(s - oo, s - oo)]
                    )
                    painter.drawPolygon(poly)
                    oo += 4.0
                elif shape in ("/", "//"):
                    painter.drawLine(QPointF(s, 0), QPointF(0, s))
                elif shape in ("\\", "\\\\"):
                    painter.drawLine(QPointF(0, 0), QPointF(s, s))
                elif shape == "X":
                    painter.drawLine(QPointF(s, 0), QPointF(0, s))
                    painter.drawLine(QPointF(0, 0), QPointF(s, s))
                elif shape in ("-", "="):
                    painter.drawLine(QPointF(0, s * 0.5), QPointF(s, s * 0.5))
                elif shape in ("|", "||"):
                    painter.drawLine(QPointF(s * 0.5, 0), QPointF(s * 0.5, s))
                elif shape in ("+", "#"):
                    painter.drawLine(QPointF(0, s * 0.5), QPointF(s, s * 0.5))
                    painter.drawLine(QPointF(s * 0.5, 0), QPointF(s * 0.5, s))
                elif shape == "|v":
                    painter.setPen(QPen(outline_col, 1))
                    painter.setBrush(QBrush(QColor(hex_col)))
                    painter.drawPolygon(
                        QPolygonF(
                            [
                                QPointF(vlo, s * 0.5),
                                QPointF(vlo + 10, s * 0.5),
                                QPointF(vlo + 5, s * 0.5 + 15),
                            ]
                        )
                    )
                    vlo += 10.0
                elif shape == "v|":
                    painter.setPen(QPen(outline_col, 1))
                    painter.setBrush(QBrush(QColor(hex_col)))
                    painter.drawPolygon(
                        QPolygonF(
                            [
                                QPointF(s - vro, s * 0.5),
                                QPointF(s - vro - 10, s * 0.5),
                                QPointF(s - vro - 5, s * 0.5 + 15),
                            ]
                        )
                    )
                    vro += 10.0
                elif shape == "|o":
                    painter.setPen(QPen(outline_col, 1))
                    painter.setBrush(QBrush(QColor(hex_col)))
                    painter.drawEllipse(QRectF(vlo, s * 0.5, 14, 14))
                    vlo += 15.0
                elif shape == "o|":
                    painter.setPen(QPen(outline_col, 1))
                    painter.setBrush(QBrush(QColor(hex_col)))
                    painter.drawEllipse(QRectF(s - vro - 14, s * 0.5, 14, 14))
                    vro += 15.0

except ImportError:
    MapElementItem = None  # type: ignore[assignment,misc]
    CreatureTokenItem = None  # type: ignore[assignment,misc]

