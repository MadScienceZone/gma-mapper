"""Spell Area of Effect (`LS-SAOE`, creature `AoE`/`_AoE`, and `AOE_GLOBAL_BOUND`) helpers and target dialog.

Ported from `bin/mapper_legacy.tcl`:
- `aoetool` (`Ctrl+A`), `aoeboundtool` (`Alt+B`), `toggleAoeShape` (`Alt+1`), `toggleAoeSpread` (`Alt+2`)
- `DrawAoeZone`, `_DrawAoeZone`, `DrawAoeSpread`, `DrawAoeGrid`
- `ToggleSpellArea`, `DragMOBAoE`, `CompleteMOBAoE`
- `GetAreaZoneTargets`, `IsMobOccupyingGrid`, `aoe_target_prompt`
"""

from __future__ import annotations

from collections import deque
import math
from typing import Any, Callable

from gma_mapper.core.zones import creature_displayed_size, monster_size_value

BASE_GRID_SCALE: float = 50.0

AOE_SHAPES: tuple[str, ...] = ("radius", "cone", "ray")


def cycle_aoe_shape(current: str) -> str:
    """Cycle `AoEShape` in the legacy `Alt+1` order: `radius -> cone -> ray -> radius`."""
    try:
        idx = AOE_SHAPES.index(current)
        return AOE_SHAPES[(idx + 1) % len(AOE_SHAPES)]
    except ValueError:
        return "radius"


def grid_intersection_distance(gx0: float, gy0: float, gx1: float, gy1: float) -> int:
    """Return rounded Euclidean grid distance matching `GridDistance` in `bin/mapper_legacy.tcl`."""
    return int(round(math.hypot(gx0 - gx1, gy0 - gy1)))


def _segment_intersects_rect(
    x0: float,
    y0: float,
    x1: float,
    y1: float,
    rx0: float,
    ry0: float,
    rx1: float,
    ry1: float,
) -> bool:
    """Return True if line segment `(x0, y0)-(x1, y1)` intersects axis-aligned box `[rx0, rx1] x [ry0, ry1]`."""
    # Liang-Barsky clipping
    dx = x1 - x0
    dy = y1 - y0
    p = (-dx, dx, -dy, dy)
    q = (x0 - rx0, rx1 - x0, y0 - ry0, ry1 - y0)
    u1 = 0.0
    u2 = 1.0
    for pi, qi in zip(p, q):
        if abs(pi) < 1e-9:
            if qi < 0.0:
                return False
        else:
            t = qi / pi
            if pi < 0.0:
                if t > u2:
                    return False
                if t > u1:
                    u1 = t
            else:
                if t < u1:
                    return False
                if t < u2:
                    u2 = t
    return u1 <= u2


def _point_in_pie_slice(
    px: float,
    py: float,
    x0: float,
    y0: float,
    r: float,
    theta0: float,
    half_angle: float = math.pi / 4.0,
) -> bool:
    """Return True if `(px, py)` lies inside the pie slice centered at `(x0, y0)` with radius `r` and center angle `theta0`."""
    dx = px - x0
    dy = y0 - py  # math Y-up orientation matching mapper_legacy.tcl
    dist = math.hypot(dx, dy)
    if dist > r + 1e-6:
        return False
    if dist < 1e-6:
        return True
    ang = math.atan2(dy, dx)
    diff = (ang - theta0 + math.pi) % (2.0 * math.pi) - math.pi
    return abs(diff) <= half_angle + 1e-6


def _segment_overlaps_pie_slice(
    sx0: float,
    sy0: float,
    sx1: float,
    sy1: float,
    x0: float,
    y0: float,
    r: float,
    theta0: float,
    steps: int = 16,
) -> bool:
    """Return True if any part of segment `(sx0, sy0)-(sx1, sy1)` overlaps the 90-degree cone pie slice."""
    for i in range(steps + 1):
        t = i / float(steps)
        px = sx0 + (sx1 - sx0) * t
        py = sy0 + (sy1 - sy0) * t
        if _point_in_pie_slice(px, py, x0, y0, r, theta0):
            return True
    return False


def _barrier_overlaps_box(
    barrier_segments: list[tuple[float, float, float, float]],
    rx0: float,
    ry0: float,
    rx1: float,
    ry1: float,
) -> bool:
    for bx0, by0, bx1, by1 in barrier_segments:
        if _segment_intersects_rect(bx0, by0, bx1, by1, rx0, ry0, rx1, ry1):
            return True
    return False


def compute_aoe_spread_grids(
    gx0: int,
    gy0: int,
    radius_grids: int,
    barrier_segments: list[tuple[float, float, float, float]] | None = None,
    grid_scale: float = BASE_GRID_SCALE,
) -> list[tuple[int, int]]:
    """Compute spread AoE squares around `(gx0, gy0)` constrained by `barrier_segments` (`DrawAoeSpread`)."""
    if radius_grids <= 0:
        return []
    barriers = barrier_segments or []
    r_px = radius_grids * grid_scale
    start_weight = 0.5 * grid_scale
    adj_weight = 1.0 * grid_scale
    diag_weight = 1.5 * grid_scale

    start_cells = [
        (gx0 - 1, gy0 - 1),
        (gx0, gy0 - 1),
        (gx0 - 1, gy0),
        (gx0, gy0),
    ]
    weights: dict[tuple[int, int], float] = {}
    queue: deque[tuple[int, int]] = deque()
    result: list[tuple[int, int]] = []

    for cell in start_cells:
        weights[cell] = start_weight
        queue.append(cell)
        result.append(cell)

    def _neighbors(c: int, r: int) -> list[tuple[int, int]]:
        out: list[tuple[int, int]] = []
        for dc in (-1, 0, 1):
            for dr in (-1, 0, 1):
                if dc != 0 or dr != 0:
                    out.append((c + dc, r + dr))
        return out

    while queue:
        c1, r1 = queue.popleft()
        x1 = c1 * grid_scale
        y1 = r1 * grid_scale
        for cc, rr in _neighbors(c1, r1):
            if (cc, rr) in weights:
                continue
            xc = cc * grid_scale
            yr = rr * grid_scale
            ok = True
            if barriers:
                if cc == c1:
                    zy = min(yr, y1)
                    if _barrier_overlaps_box(
                        barriers, xc + 3, zy + 3, xc + grid_scale - 3, zy + grid_scale * 2 - 3
                    ):
                        ok = False
                elif rr == r1:
                    zx = min(xc, x1)
                    if _barrier_overlaps_box(
                        barriers, zx + 3, yr + 3, zx + grid_scale * 2 - 3, yr + grid_scale - 3
                    ):
                        ok = False
                else:
                    zx = ( x1 - 3 ) if cc < c1 else ( xc - 3 )
                    zy = ( y1 - 3 ) if rr < r1 else ( yr - 3 )
                    if _barrier_overlaps_box(barriers, zx, zy, zx + 6, zy + 6):
                        ok = False
                    elif _barrier_overlaps_box(
                        barriers, xc + 3, yr + 3, xc + grid_scale - 3, yr + grid_scale - 3
                    ):
                        ok = False
            if not ok:
                continue

            my_weight = 0.0
            for nc, nr in _neighbors(cc, rr):
                if (nc, nr) in weights:
                    step = adj_weight if (nc == cc or nr == rr) else diag_weight
                    wt = weights[(nc, nr)] + step
                    if my_weight == 0.0 or wt < my_weight:
                        my_weight = wt

            if 0.0 < my_weight < r_px:
                weights[(cc, rr)] = my_weight
                queue.append((cc, rr))
                result.append((cc, rr))

    return result


def compute_aoe_grids(
    gx0: int,
    gy0: int,
    gxx: int,
    gyy: int,
    shape: str = "radius",
    spread: bool = False,
    barrier_segments: list[tuple[float, float, float, float]] | None = None,
    grid_scale: float = BASE_GRID_SCALE,
) -> list[tuple[int, int]]:
    """Return list of `(gx, gy)` grid squares covered by an AoE from `(gx0, gy0)` to `(gxx, gyy)`.

    Matches `_DrawAoeZone` in `bin/mapper_legacy.tcl` lines 5526-5774.
    """
    radius_grids = grid_intersection_distance(gx0, gy0, gxx, gyy)
    if radius_grids <= 0:
        return []

    r = radius_grids * grid_scale
    x0 = gx0 * grid_scale
    y0 = gy0 * grid_scale
    xx = gxx * grid_scale
    yy = gyy * grid_scale
    deltax = xx - x0
    deltay = y0 - yy  # math Y-up

    seen: set[tuple[int, int]] = set()
    ordered: list[tuple[int, int]] = []

    def _add(gx: int, gy: int) -> None:
        pt = (int(gx), int(gy))
        if pt not in seen:
            seen.add(pt)
            ordered.append(pt)

    if shape == "radius":
        if spread:
            for pt in compute_aoe_spread_grids(gx0, gy0, radius_grids, barrier_segments, grid_scale):
                _add(pt[0], pt[1])
            return ordered

        for i in range(0, radius_grids):
            for j in range(1, radius_grids + 1):
                if i < j and math.hypot(i, j) <= radius_grids + 1e-6:
                    # Octant I
                    _add(gx0 + i, gy0 - j)
                    _add(gx0 + j - 1, gy0 - i - 1)
                    # Octant IV
                    _add(gx0 + i, gy0 + j - 1)
                    _add(gx0 + j - 1, gy0 + i)
                    # Octant II
                    _add(gx0 - i - 1, gy0 - j)
                    _add(gx0 - j, gy0 - i - 1)
                    # Octant III
                    _add(gx0 - i - 1, gy0 + j - 1)
                    _add(gx0 - j, gy0 + i)
        return ordered

    if shape == "ray":
        if deltax == 0 and deltay == 0:
            return []
        min_gx = min(gx0, gxx)
        max_gx = max(gx0, gxx)
        min_gy = min(gy0, gyy)
        max_gy = max(gy0, gyy)
        if deltax == 0:
            col = gx0 if deltay < 0 else gx0 - 1
            for gy in range(min_gy, max_gy):
                _add(col, gy)
            return ordered
        if deltay == 0:
            row = gy0 if deltax > 0 else gy0 - 1
            for gx in range(min_gx, max_gx):
                _add(gx, row)
            return ordered
        for gx in range(min_gx, max_gx):
            for gy in range(min_gy, max_gy):
                rx0 = gx * grid_scale + 1.0
                ry0 = gy * grid_scale + 1.0
                rx1 = (gx + 1) * grid_scale - 1.0
                ry1 = (gy + 1) * grid_scale - 1.0
                if _segment_intersects_rect(x0, y0, xx, yy, rx0, ry0, rx1, ry1):
                    _add(gx, gy)
        return ordered

    if shape == "cone":
        theta0 = math.atan2(deltay, deltax)
        fuzz = 3.0
        # Top edge check
        for dg_x in range(-radius_grids, radius_grids):
            for dg_y in range(-radius_grids, 0):
                x = dg_x * grid_scale
                y = dg_y * grid_scale
                if (x < 0 and x >= y) or (x >= 0 and x < -y):
                    if _segment_overlaps_pie_slice(
                        x0 + x + fuzz, y0 + y, x0 + x + grid_scale - fuzz, y0 + y, x0, y0, r, theta0
                    ):
                        _add(gx0 + dg_x, gy0 + dg_y)
        # Left edge check
        for dg_x in range(-radius_grids, 0):
            for dg_y in range(-radius_grids, radius_grids):
                x = dg_x * grid_scale
                y = dg_y * grid_scale
                if (y < 0 and y >= x) or (y >= 0 and y < -x):
                    if _segment_overlaps_pie_slice(
                        x0 + x, y0 + y + fuzz, x0 + x, y0 + y + grid_scale - fuzz, x0, y0, r, theta0
                    ):
                        _add(gx0 + dg_x, gy0 + dg_y)
        # Bottom edge check
        for dg_x in range(-radius_grids, radius_grids):
            for dg_y in range(0, radius_grids):
                x = dg_x * grid_scale
                y = dg_y * grid_scale
                if (x < 0 and -x - grid_scale <= y) or (x >= 0 and x <= y):
                    if _segment_overlaps_pie_slice(
                        x0 + x + fuzz,
                        y0 + y + grid_scale,
                        x0 + x + grid_scale - fuzz,
                        y0 + y + grid_scale,
                        x0,
                        y0,
                        r,
                        theta0,
                    ):
                        _add(gx0 + dg_x, gy0 + dg_y)
        # Right edge check
        for dg_x in range(0, radius_grids):
            for dg_y in range(-radius_grids, radius_grids):
                x = dg_x * grid_scale
                y = dg_y * grid_scale
                if (y < 0 and x >= -y - grid_scale) or (y >= 0 and x >= y):
                    if _segment_overlaps_pie_slice(
                        x0 + x + grid_scale,
                        y0 + y + fuzz,
                        x0 + x + grid_scale,
                        y0 + y + grid_scale - fuzz,
                        x0,
                        y0,
                        r,
                        theta0,
                    ):
                        _add(gx0 + dg_x, gy0 + dg_y)
        return ordered

    return ordered


def compute_creature_aoe_grids(
    creature_data: dict[str, Any],
    radius_grids: float,
) -> list[tuple[int, int]]:
    """Return all `(gx, gy)` squares covered by a creature's perimeter-emanation `AoE` or `_AoE`.

    Matches `RenderSomeone` in `bin/mapper_legacy.tcl` lines 7278-7342.
    """
    r_int = int(round(radius_grids))
    if r_int <= 0:
        return []
    gx0 = int(math.floor(float(creature_data.get("Gx", creature_data.get("GX", 0.0)) or 0.0)))
    gy0 = int(math.floor(float(creature_data.get("Gy", creature_data.get("GY", 0.0)) or 0.0)))
    sz = max(1, int(math.ceil(monster_size_value(creature_displayed_size(creature_data)))))

    seen: set[tuple[int, int]] = set()
    ordered: list[tuple[int, int]] = []

    def _collect_from(ix: int, iy: int) -> None:
        for cell in compute_aoe_grids(ix, iy, ix + r_int, iy, shape="radius"):
            if cell not in seen:
                seen.add(cell)
                ordered.append(cell)

    for ax in range(0, sz + 1):
        _collect_from(gx0 + ax, gy0)
        if sz >= 1:
            _collect_from(gx0 + ax, gy0 + sz)
    for ay in range(1, sz):
        _collect_from(gx0, gy0 + ay)
        _collect_from(gx0 + sz, gy0 + ay)
    return ordered


def is_mob_occupying_grid(gx: int, gy: int, creature_data: dict[str, Any]) -> bool:
    """Return True if `creature_data` occupies grid square `(gx, gy)` (`IsMobOccupyingGrid`)."""
    mx = float(creature_data.get("Gx", creature_data.get("GX", 0.0)) or 0.0)
    my = float(creature_data.get("Gy", creature_data.get("GY", 0.0)) or 0.0)
    sz = max(1, int(math.ceil(monster_size_value(creature_displayed_size(creature_data)))))
    base_x = int(math.floor(mx))
    base_y = int(math.floor(my))
    for i in range(sz):
        for j in range(sz):
            if base_x + i == gx and base_y + j == gy:
                return True
    return False


def find_creatures_in_aoe_grids(
    aoe_grids: list[tuple[int, int]],
    creatures: dict[str, dict[str, Any]],
) -> list[str]:
    """Return sorted list of creature `Name`s occupying any square in `aoe_grids` (`GetAreaZoneTargets`)."""
    grid_set = {(int(gx), int(gy)) for gx, gy in aoe_grids}
    if not grid_set:
        return []
    names: list[str] = []
    for cid, cdata in creatures.items():
        if cdata.get("Hidden"):
            continue
        mx = int(math.floor(float(cdata.get("Gx", cdata.get("GX", 0.0)) or 0.0)))
        my = int(math.floor(float(cdata.get("Gy", cdata.get("GY", 0.0)) or 0.0)))
        sz = max(1, int(math.ceil(monster_size_value(creature_displayed_size(cdata)))))
        hit = False
        for i in range(sz):
            for j in range(sz):
                if (mx + i, my + j) in grid_set:
                    hit = True
                    break
            if hit:
                break
        if hit:
            name = str(cdata.get("Name") or cid)
            if name not in names:
                names.append(name)
    names.sort()
    return names


def aoe_grid_hatch_lines(
    gx: int,
    gy: int,
    local_aura: bool = False,
    grid_scale: float = BASE_GRID_SCALE,
) -> list[tuple[float, float, float, float]]:
    """Return diagonal cross-hatch line segments `(x1, y1, x2, y2)` inside square `(gx, gy)`.

    Matches `DrawAoeGrid` in `bin/mapper_legacy.tcl` lines 5930-5955.
    """
    x1 = gx * grid_scale
    y1 = gy * grid_scale
    x2 = x1 + grid_scale
    y2 = y1 + grid_scale
    o = 5.0 if local_aura else 0.0
    step = grid_scale / 4.0
    lines: list[tuple[float, float, float, float]] = []
    for k in range(4):
        xk = x1 + k * step
        yk = y2 - k * step
        lines.append((xk + o, y1 + o, x2 + o, yk + o))
        if k > 0:
            lines.append((x1 + o, yk + o, xk + o, y2 + o))
    return lines


try:
    from PySide6.QtWidgets import (
        QCheckBox,
        QDialog,
        QDialogButtonBox,
        QFrame,
        QLabel,
        QVBoxLayout,
        QWidget,
    )

    class AoETargetDialog(QDialog):
        """Modal dialog prompting the user to select which creatures inside an AoE are targeted.

        Matches `aoe_target_prompt` in `bin/mapper_legacy.tcl` lines 18621-18706.
        """

        def __init__(
            self,
            target_names: list[str],
            creatures_by_name: dict[str, dict[str, Any]],
            parent: QWidget | None = None,
        ) -> None:
            super().__init__(parent)
            self.setWindowTitle("Area of Effect Targets")
            self._creatures_by_name = creatures_by_name
            self._checks: dict[str, QCheckBox] = {}

            layout = QVBoxLayout(self)
            lbl = QLabel(
                "If your area effect will do targeted damage, please select the creatures affected:",
                self,
            )
            lbl.setWordWrap(True)
            layout.addWidget(lbl)

            self.chk_all = QCheckBox("All creatures in area", self)
            self.chk_living = QCheckBox("All living creatures in area", self)
            self.chk_party = QCheckBox("Party members in area", self)
            self.chk_all.toggled.connect(self._on_toggle_all)
            self.chk_living.toggled.connect(self._on_toggle_living)
            self.chk_party.toggled.connect(self._on_toggle_party)
            layout.addWidget(self.chk_all)
            layout.addWidget(self.chk_living)
            layout.addWidget(self.chk_party)

            sep = QFrame(self)
            sep.setFrameShape(QFrame.Shape.HLine)
            layout.addWidget(sep)

            for name in sorted(target_names):
                cb = QCheckBox(name, self)
                self._checks[name] = cb
                layout.addWidget(cb)

            buttons = QDialogButtonBox(
                QDialogButtonBox.StandardButton.Ok
                | QDialogButtonBox.StandardButton.Cancel,
                self,
            )
            buttons.accepted.connect(self.accept)
            buttons.rejected.connect(self.reject)
            layout.addWidget(buttons)

        def _on_toggle_all(self, checked: bool) -> None:
            for cb in self._checks.values():
                cb.setChecked(checked)

        def _on_toggle_living(self, checked: bool) -> None:
            for name, cb in self._checks.items():
                cdata = self._creatures_by_name.get(name, {})
                if not cdata.get("Killed", False):
                    cb.setChecked(checked)

        def _on_toggle_party(self, checked: bool) -> None:
            for name, cb in self._checks.items():
                cdata = self._creatures_by_name.get(name, {})
                if int(cdata.get("CreatureType", 0) or 0) == 2:
                    cb.setChecked(checked)

        def selected_targets(self) -> list[str]:
            return [name for name, cb in self._checks.items() if cb.isChecked()]

except ImportError:
    AoETargetDialog = None  # type: ignore[assignment,misc]

