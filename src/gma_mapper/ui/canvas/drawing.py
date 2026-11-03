"""Pure-Python helpers for GMA Mapper drawing tools, grid snapping, style cycling, and object manipulation.

Ported from `bin/mapper_legacy.tcl` (lines 1209-1281, 4264-4650, 5148-5394, 8201-8315, 10113-10393).
"""

from __future__ import annotations

import math
from typing import Any

from gma_mapper.ui.canvas.items import BASE_GRID_SCALE

ARROW_STYLES: list[str] = ["none", "first", "last", "both"]
DASH_STYLES: list[str] = ["", "-", ",", ".", "-.", "-.."]
JOIN_STYLES: list[str] = ["bevel", "miter", "round"]
ARC_MODES: list[str] = ["pieslice", "chord", "arc"]
TEXT_ANCHORS: list[str] = ["center", "w", "nw", "n", "ne", "e", "se", "s", "sw"]

STIPPLE_CHOICES: list[tuple[str, str]] = [
    ("", "None"),
    ("gray12", "12%"),
    ("gray25", "25%"),
    ("gray50", "50%"),
    ("gray75", "75%"),
]

GRID_SNAP_CHOICES: list[tuple[int, str]] = [
    (0, "None"),
    (1, "Full grid squares"),
    (2, "1/2 square"),
    (3, "1/3 square"),
    (4, "1/4 square"),
]

LINE_WIDTH_CHOICES: list[tuple[int, str]] = [
    (0, "0 (Thinnest)"),
    (1, "1"),
    (2, "2"),
    (3, "3"),
    (4, "4"),
    (5, "5"),
    (6, "6"),
    (7, "7"),
    (8, "8"),
    (9, "9 (Thickest)"),
]


def snap_coord(
    val: float, obj_snap: int, grid_scale: float = BASE_GRID_SCALE
) -> float:
    """Snap a scene coordinate `val` according to `obj_snap` (`0` = None, `1..4` = subdivisions per square).

    Matches `SnapCoord` in `bin/mapper_legacy.tcl` lines 8210-8217.
    """
    if obj_snap <= 0:
        return float(val)
    step = float(grid_scale) / float(obj_snap)
    return float(math.floor((val + step / 2.0) / step) * step)


def snap_point(
    x: float, y: float, obj_snap: int, grid_scale: float = BASE_GRID_SCALE
) -> tuple[float, float]:
    """Snap `(x, y)` scene coordinates according to `obj_snap`."""
    return (
        snap_coord(x, obj_snap, grid_scale),
        snap_coord(y, obj_snap, grid_scale),
    )


def cycle_in_list(current: str, choices: list[str]) -> str:
    """Return the next item in `choices` after `current` (wrapping around)."""
    if not choices:
        return current
    try:
        idx = choices.index(current)
        return choices[(idx + 1) % len(choices)]
    except ValueError:
        return choices[0]


def cycle_arrow_style(current: str) -> str:
    return cycle_in_list(current, ARROW_STYLES)


def cycle_dash_style(current: str) -> str:
    return cycle_in_list(current, DASH_STYLES)


def cycle_join_style(current: str) -> str:
    return cycle_in_list(current, JOIN_STYLES)


def cycle_arc_mode(current: str) -> str:
    return cycle_in_list(current, ARC_MODES)


def cycle_text_anchor(current: str) -> str:
    return cycle_in_list(current, TEXT_ANCHORS)


def cycle_spline_level(current: int) -> int:
    """Cycle spline level `0..9` matching `toggleSpline` in `bin/mapper_legacy.tcl`."""
    return (int(current) + 1) % 10


def translate_element_coords(
    elem_data: dict[str, Any], dx: float, dy: float
) -> dict[str, Any]:
    """Shift `elem_data`'s `X`, `Y`, and all `Points` by `(dx, dy)` in place and return the changed attributes dict.

    Matches `MoveObjEndDrag` and `NudgeObject` in `bin/mapper_legacy.tcl`.
    """
    new_x = float(elem_data.get("X", 0.0)) + float(dx)
    new_y = float(elem_data.get("Y", 0.0)) + float(dy)
    new_pts: list[dict[str, float]] = []
    for pt in elem_data.get("Points") or []:
        new_pts.append(
            {
                "X": float(pt.get("X", 0.0)) + float(dx),
                "Y": float(pt.get("Y", 0.0)) + float(dy),
            }
        )
    elem_data["X"] = new_x
    elem_data["Y"] = new_y
    elem_data["Points"] = new_pts
    return {"X": new_x, "Y": new_y, "Points": new_pts}


def compute_nudge_z(
    elements_data: dict[str, dict[str, Any]], target_id: str, adj: str
) -> int | None:
    """Compute new `Z` coordinate for `target_id` given adjustment `'up'`, `'down'`, `'front'`, or `'back'`.

    Matches `NudgeObjectZ` in `bin/mapper_legacy.tcl` lines 10272-10350.
    Returns `None` if `target_id` is not found or is already at the requested limit.
    """
    if target_id not in elements_data:
        return None

    max_z: int | None = None
    min_z: int | None = None
    for oid, d in elements_data.items():
        z = int(d.get("Z", 0) or 0)
        if max_z is None or min_z is None:
            min_z = z
            max_z = z
        else:
            if max_z == z:
                max_z = z + 1
            elif max_z < z:
                max_z = z
            if min_z == z:
                min_z = z - 1
            elif min_z > z:
                min_z = z

    if min_z is None:
        min_z = 0
    if max_z is None:
        max_z = 0

    cur_z = int(elements_data[target_id].get("Z", 0) or 0)
    if adj == "up":
        if cur_z >= max_z:
            return None
        new_z = cur_z + 1
    elif adj == "down":
        if cur_z <= min_z:
            return None
        new_z = cur_z - 1
    elif adj == "front":
        if cur_z >= max_z:
            return None
        new_z = max_z + 1
    elif adj == "back":
        if cur_z <= min_z:
            return None
        new_z = min_z - 1
    else:
        return None

    elements_data[target_id]["Z"] = new_z
    return new_z


def describe_element(gma_type: str, data: dict[str, Any]) -> str:
    """Format a human-readable description of a map element for Move/Delete disambiguation menus.

    Matches `KillObjUnderMouse` / `MoveObjUnderMouse` in `bin/mapper_legacy.tcl`.
    """
    clean_type = gma_type.replace("LS-", "").lower()
    line = str(data.get("Line") or "no line")
    fill = str(data.get("Fill") or "no fill")
    width = data.get("Width", "no width")
    x = int(float(data.get("X", 0.0)))
    y = int(float(data.get("Y", 0.0)))
    z = int(float(data.get("Z", 0)))
    layer = str(data.get("Layer") or "")
    desc = ""
    if data.get("Text"):
        desc = f' "{data["Text"]}"'
    elif data.get("Image"):
        desc = f' "{data["Image"]}"'
    return f"{clean_type} ({line}/{fill}){desc} @({x},{y},{z}); w={width}; [{layer}]"

