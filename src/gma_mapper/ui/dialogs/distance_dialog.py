"""Distance from Cell (`DistanceFromGrid`) and Distance from Icon (`DistanceFromMob`) dialog.

Ported from `DistanceToTarget3D`, `NearestCreatureGridToPoint`, `DistanceFromGrid`,
and `DistanceFromMob` in ``bin/mapper.tcl``:
computes 2D/3D Euclidean grid distances (center-to-center and nearest occupied cell)
from a chosen grid cell or creature icon to all visible targets on the battle map.
"""

from __future__ import annotations

from dataclasses import dataclass
import html
import math
import re
from typing import Any, Callable, Sequence

from gma_mapper.core.colors import color_to_hex
from gma_mapper.core.profile import default_preferences, preferred_color
from gma_mapper.core.util import letter_label
from gma_mapper.core.zones import creature_displayed_size, monster_size_value

_DEFAULT_GRID_SCALE = 50.0
_NAMEPLATE_PREFIX_RE = re.compile(r"^\w*_")

try:
    from PySide6.QtCore import Qt, Signal
    from PySide6.QtGui import QFont, QFontDatabase, QIcon, QKeySequence, QShortcut
    from PySide6.QtWidgets import (
        QHBoxLayout,
        QLabel,
        QPushButton,
        QSpinBox,
        QTextEdit,
        QVBoxLayout,
        QWidget,
    )

    QT_AVAILABLE = True
except ImportError:  # pragma: no cover
    QT_AVAILABLE = False


@dataclass(frozen=True)
class DistanceRow:
    """Single computed distance row between a source cell/mob and a target mob."""

    target_id: str
    display_name: str
    center_sq: int
    center_ft: int
    dimension: str
    nearest_sq: int
    nearest_ft: int
    nearest_label: str
    arrow: tuple[float, float, float, float]
    highlight_cells: tuple[tuple[int, int], ...]


def _strip_nameplate_prefix(name: str) -> str:
    return _NAMEPLATE_PREFIX_RE.sub("", str(name or ""))


def _cell_label(gx: float, gy: float) -> str:
    col = max(0, int(math.floor(gx)))
    row = max(0, int(math.floor(gy))) + 1
    return f"{letter_label(col)}{row}"


def round_grid_distance(val: float) -> int:
    """Match Tcl ``expr {round($val)}`` half-away-from-zero rounding on non-negative distances."""
    return int(math.floor(val + 0.5))


def _creature_gx_gy_size_elev(data: dict[str, Any]) -> tuple[float, float, float, float]:
    gx = float(data.get("Gx", data.get("GX", 0.0)) or 0.0)
    gy = float(data.get("Gy", data.get("GY", 0.0)) or 0.0)
    size_sq = float(monster_size_value(creature_displayed_size(data)) or 1.0)
    if size_sq <= 0.0:
        size_sq = 1.0
    try:
        elev_ft = float(data.get("Elev", 0.0) or 0.0)
    except (TypeError, ValueError):
        elev_ft = 0.0
    return (gx, gy, size_sq, elev_ft)


def occupied_grid_cells(gx0: float, gy0: float, size_sq: float) -> list[tuple[float, float]]:
    """Return occupied grid `(x, y)` origins matching Tcl ``for {set x MGx0} {$x < MGx1}`` loops."""
    half = max(0.25, size_sq * 0.5)
    cx = gx0 + half
    cy = gy0 + half
    mgx0 = cx - half
    mgx1 = cx + half - 1e-9
    mgy0 = cy - half
    mgy1 = cy + half - 1e-9

    xs: list[float] = []
    x = mgx0
    while x < mgx1 or not xs:
        xs.append(x)
        x += 1.0

    ys: list[float] = []
    y = mgy0
    while y < mgy1 or not ys:
        ys.append(y)
        y += 1.0

    return [(cx_val, cy_val) for cx_val in xs for cy_val in ys]


def _target_display_name(data: dict[str, Any], mob_id: str, is_gm: bool) -> str | None:
    hidden = bool(data.get("Hidden", False))
    base = _strip_nameplate_prefix(str(data.get("Name") or mob_id))
    if hidden:
        if not is_gm:
            return None
        return f"({base})"
    return base


def _distance_3d(
    x0: float,
    y0: float,
    z0_ft: float,
    x1: float,
    y1: float,
    z1_ft: float,
) -> int:
    dz = (z0_ft / 5.0) - (z1_ft / 5.0)
    return round_grid_distance(math.sqrt((x0 - x1) ** 2 + (y0 - y1) ** 2 + dz * dz))


def compute_distances_from_grid(
    gx: int,
    gy: int,
    z_ft: float,
    creatures: dict[str, dict[str, Any]],
    is_gm: bool = False,
    grid_scale: float = _DEFAULT_GRID_SCALE,
) -> list[DistanceRow]:
    """Compute sorted 2D/3D distances from grid cell `(gx, gy, z_ft)` to visible creatures."""
    src_cx = float(gx) + 0.5
    src_cy = float(gy) + 0.5
    src_elev = float(z_ft)

    rows: list[DistanceRow] = []
    for tid, data in creatures.items():
        disp = _target_display_name(data, tid, is_gm)
        if disp is None:
            continue

        tgx, tgy, tsize, telev = _creature_gx_gy_size_elev(data)
        t_cx = tgx + tsize * 0.5
        t_cy = tgy + tsize * 0.5
        center_sq = _distance_3d(src_cx, src_cy, src_elev, t_cx, t_cy, telev)
        dimension = "2D" if telev == src_elev else "3D"

        best_d = -1
        near_x = int(math.floor(tgx))
        near_y = int(math.floor(tgy))
        for cell_x, cell_y in occupied_grid_cells(tgx, tgy, tsize):
            d = _distance_3d(src_cx, src_cy, src_elev, cell_x + 0.5, cell_y + 0.5, telev)
            if best_d < 0 or d < best_d:
                best_d = d
                near_x = int(math.floor(cell_x))
                near_y = int(math.floor(cell_y))

        near_sq = max(0, best_d)
        rows.append(
            DistanceRow(
                target_id=tid,
                display_name=disp,
                center_sq=center_sq,
                center_ft=center_sq * 5,
                dimension=dimension,
                nearest_sq=near_sq,
                nearest_ft=near_sq * 5,
                nearest_label=_cell_label(near_x, near_y),
                arrow=(
                    src_cx * grid_scale,
                    src_cy * grid_scale,
                    t_cx * grid_scale,
                    t_cy * grid_scale,
                ),
                highlight_cells=((near_x, near_y),),
            )
        )

    rows.sort(key=lambda r: (r.center_sq, r.nearest_sq, r.display_name.lower()))
    return rows


def compute_distances_from_mob(
    mob_id: str,
    creatures: dict[str, dict[str, Any]],
    is_gm: bool = False,
    grid_scale: float = _DEFAULT_GRID_SCALE,
) -> list[DistanceRow] | None:
    """Compute sorted 2D/3D distances from `mob_id` to all other visible creatures."""
    src_data = creatures.get(mob_id)
    if src_data is None:
        return None
    if bool(src_data.get("Hidden", False)) and not is_gm:
        return None

    sgx, sgy, ssize, selev = _creature_gx_gy_size_elev(src_data)
    src_cx = sgx + ssize * 0.5
    src_cy = sgy + ssize * 0.5
    # Legacy DistanceFromMob uses int(MobX/iscale) + 0.5 for center-to-center DistanceToTarget3D,
    # matching the grid square center containing MobCenterPoint.
    src_grid_cx = float(int(math.floor(src_cx))) + 0.5
    src_grid_cy = float(int(math.floor(src_cy))) + 0.5
    src_cells = occupied_grid_cells(sgx, sgy, ssize)

    rows: list[DistanceRow] = []
    for tid, tdata in creatures.items():
        if tid == mob_id:
            continue
        disp = _target_display_name(tdata, tid, is_gm)
        if disp is None:
            continue

        tgx, tgy, tsize, telev = _creature_gx_gy_size_elev(tdata)
        t_cx = tgx + tsize * 0.5
        t_cy = tgy + tsize * 0.5
        center_sq = _distance_3d(src_grid_cx, src_grid_cy, selev, t_cx, t_cy, telev)
        dimension = "2D" if telev == selev else "3D"

        best_d = -1
        near_sx = int(math.floor(sgx))
        near_sy = int(math.floor(sgy))
        near_tx = int(math.floor(tgx))
        near_ty = int(math.floor(tgy))
        for sx, sy in src_cells:
            for tx, ty in occupied_grid_cells(tgx, tgy, tsize):
                d = _distance_3d(sx, sy, selev, tx, ty, telev)
                if best_d < 0 or d < best_d:
                    best_d = d
                    near_sx = int(math.floor(sx))
                    near_sy = int(math.floor(sy))
                    near_tx = int(math.floor(tx))
                    near_ty = int(math.floor(ty))

        near_sq = max(0, best_d)
        rows.append(
            DistanceRow(
                target_id=tid,
                display_name=disp,
                center_sq=center_sq,
                center_ft=center_sq * 5,
                dimension=dimension,
                nearest_sq=near_sq,
                nearest_ft=near_sq * 5,
                nearest_label=_cell_label(near_tx, near_ty),
                arrow=(
                    src_cx * grid_scale,
                    src_cy * grid_scale,
                    t_cx * grid_scale,
                    t_cy * grid_scale,
                ),
                highlight_cells=((near_sx, near_sy), (near_tx, near_ty)),
            )
        )

    rows.sort(key=lambda r: (r.center_sq, r.nearest_sq, r.display_name.lower()))
    return rows


def format_distance_table_text(rows: Sequence[DistanceRow]) -> str:
    """Format distance rows as fixed-width plain text matching legacy `.dfg.list`."""
    namelen = max([len("TARGET"), *(len(r.display_name) for r in rows)])
    hdr_name = "TARGET------------------------"[:namelen].ljust(namelen)
    lines = [f"{hdr_name}  CENTER-TO-CENTER  NEAREST-GRID-----"]
    for row in rows:
        lines.append(
            f"{row.display_name:<{namelen}}  "
            f"{row.center_sq:3d}sq {row.center_ft:3d}ft ({row.dimension})  "
            f"{row.nearest_sq:3d}sq {row.nearest_ft:3d}ft {row.nearest_label}"
        )
    return "\n".join(lines)


def _dialog_color_hex(prefs: dict[str, Any], key: str, theme: str) -> str:
    return color_to_hex(preferred_color(prefs, key, theme))


def format_distance_table_html(
    rows: Sequence[DistanceRow],
    prefs: dict[str, Any] | None = None,
    dark_mode: bool = False,
) -> str:
    """Format distance rows as monospace HTML matching legacy ``DistanceFromGrid``/``DistanceFromMob`` tags."""
    prefdata = prefs if isinstance(prefs, dict) else default_preferences()
    theme = "dark" if dark_mode else "light"
    bg_col = _dialog_color_hex(prefdata, "normal_bg", theme)
    fg_col = _dialog_color_hex(prefdata, "normal_fg", theme)
    head_col = _dialog_color_hex(prefdata, "heading_fg", theme)
    key_col = _dialog_color_hex(prefdata, "highlight_fg", theme)

    namelen = max([len("TARGET"), *(len(r.display_name) for r in rows)])
    hdr_name = "TARGET------------------------"[:namelen].ljust(namelen)
    header = html.escape(f"{hdr_name}  CENTER-TO-CENTER  NEAREST-GRID-----")
    parts = [
        f'<div style="color:{head_col}; font-weight:bold;">{header}</div>'
    ]
    for row in rows:
        left = html.escape(
            f"{row.display_name:<{namelen}}  "
            f"{row.center_sq:3d}sq {row.center_ft:3d}ft ({row.dimension})  "
            f"{row.nearest_sq:3d}sq "
        )
        key_part = html.escape(f"{row.nearest_ft:3d}ft")
        right = html.escape(f" {row.nearest_label}")
        parts.append(
            f'<div><span style="color:{fg_col};">{left}</span>'
            f'<span style="color:{key_col}; font-weight:bold;">{key_part}</span>'
            f'<span style="color:{fg_col};">{right}</span></div>'
        )
    if not rows:
        parts.append(
            f'<div style="color:{fg_col};">(No visible target creatures on the map)</div>'
        )
    body = "".join(parts)
    return (
        f'<body style="margin:4px; background-color:{bg_col}; color:{fg_col};">'
        f'<pre style="margin:0; font-family:monospace;">{body}</pre></body>'
    )


if QT_AVAILABLE:

    class DistanceDialog(QWidget):
        """Modeless unowned distance summary window with canvas tracer lifecycle."""

        closed = Signal()

        def __init__(
            self,
            title: str,
            rows_provider: Callable[[float], Sequence[DistanceRow]],
            apply_tracers_cb: Callable[[Sequence[DistanceRow]], Any] | None = None,
            clear_tracers_cb: Callable[[], Any] | None = None,
            allow_elevation: bool = False,
            initial_z_ft: float = 0.0,
            prefs: dict[str, Any] | None = None,
            dark_mode: bool = False,
            window_icon: QIcon | None = None,
        ) -> None:
            super().__init__(None, Qt.WindowType.Window)
            self._rows_provider = rows_provider
            self._apply_tracers_cb = apply_tracers_cb
            self._clear_tracers_cb = clear_tracers_cb
            self.prefs: dict[str, Any] = prefs if isinstance(prefs, dict) else default_preferences()
            self.dark_mode: bool = bool(dark_mode)
            self.allow_elevation: bool = bool(allow_elevation)
            self.rows: list[DistanceRow] = []

            self.setWindowTitle(title)
            if window_icon is not None and not window_icon.isNull():
                self.setWindowIcon(window_icon)
            self.resize(620, 320)

            layout = QVBoxLayout(self)
            layout.setContentsMargins(6, 6, 6, 6)
            layout.setSpacing(6)

            self.elev_bar = QWidget(self)
            elev_row = QHBoxLayout(self.elev_bar)
            elev_row.setContentsMargins(0, 0, 0, 0)
            elev_row.setSpacing(6)
            elev_row.addWidget(QLabel("Source elevation (ft):", self.elev_bar))
            self.elev_spin = QSpinBox(self.elev_bar)
            self.elev_spin.setRange(-500, 5000)
            self.elev_spin.setSingleStep(5)
            self.elev_spin.setValue(int(round(initial_z_ft)))
            self.elev_spin.valueChanged.connect(lambda _v: self.refresh())
            elev_row.addWidget(self.elev_spin)
            elev_row.addStretch(1)
            self.elev_bar.setVisible(self.allow_elevation)
            layout.addWidget(self.elev_bar)

            self.text_view = QTextEdit(self)
            self.text_view.setReadOnly(True)
            self.text_view.setUndoRedoEnabled(False)
            self.text_view.setLineWrapMode(QTextEdit.LineWrapMode.NoWrap)
            mono_font = QFontDatabase.systemFont(QFontDatabase.SystemFont.FixedFont)
            if not mono_font.family():
                mono_font = QFont("Courier New", 10)
            self.text_view.setFont(mono_font)
            layout.addWidget(self.text_view, stretch=1)

            btn_row = QHBoxLayout()
            btn_row.setContentsMargins(0, 0, 0, 0)
            btn_row.addStretch(1)
            self.btn_ok = QPushButton("OK", self)
            self.btn_ok.setDefault(True)
            self.btn_ok.clicked.connect(self.close)
            btn_row.addWidget(self.btn_ok)
            btn_row.addStretch(1)
            layout.addLayout(btn_row)

            self._esc_shortcut = QShortcut(QKeySequence("Escape"), self)
            self._esc_shortcut.activated.connect(self.close)

            self._apply_text_style()
            self.refresh()

        def _apply_text_style(self) -> None:
            theme = "dark" if self.dark_mode else "light"
            bg_col = _dialog_color_hex(self.prefs, "normal_bg", theme)
            fg_col = _dialog_color_hex(self.prefs, "normal_fg", theme)
            self.text_view.setStyleSheet(
                f"QTextEdit {{ background-color: {bg_col}; color: {fg_col}; }}"
            )

        def refresh(self) -> list[DistanceRow]:
            """Recompute distances for current elevation and update table + canvas tracers."""
            z_ft = float(self.elev_spin.value()) if self.allow_elevation else 0.0
            self.rows = list(self._rows_provider(z_ft))
            self.text_view.setHtml(
                format_distance_table_html(self.rows, prefs=self.prefs, dark_mode=self.dark_mode)
            )
            if self._apply_tracers_cb is not None:
                self._apply_tracers_cb(self.rows)
            return self.rows

        def apply_theme(self, prefs: dict[str, Any] | None, dark_mode: bool) -> None:
            """Update light/dark dialog theme and re-render current distance rows."""
            if isinstance(prefs, dict):
                self.prefs = prefs
            self.dark_mode = bool(dark_mode)
            self._apply_text_style()
            self.text_view.setHtml(
                format_distance_table_html(self.rows, prefs=self.prefs, dark_mode=self.dark_mode)
            )

        def closeEvent(self, event: Any) -> None:
            if self._clear_tracers_cb is not None:
                self._clear_tracers_cb()
            self.closed.emit()
            super().closeEvent(event)

else:

    class DistanceDialog:  # type: ignore[no-redef]
        """Headless stub when PySide6 is unavailable."""

        def __init__(self, *_args: Any, **_kwargs: Any) -> None:
            pass
