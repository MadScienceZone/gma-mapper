"""Toolbar and application icon loader for GMA Mapper (`lib/MadScienceZone/GMA/Mapper/icons`).

Ported from `bin/mapper_legacy.tcl` (lines 1119, 2277-2286, 2663-2740, 2835-2880, 3152-3189, 4102-4562).
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

try:
    from PySide6.QtCore import QSize, Qt
    from PySide6.QtGui import QColor, QIcon, QPainter, QPixmap
    HAS_PYSIDE6 = True
except ImportError:
    HAS_PYSIDE6 = False

APP_ICON_SIZES: tuple[int, ...] = (512, 256, 128, 48, 32, 16)

TOOLBAR_BUTTON_ORDER: tuple[str, ...] = (
    "line",
    "rect",
    "poly",
    "circ",
    "arc",
    "text",
    "mode",
    "mode2",
    "mode3",
    "nil",
    "kill",
    "move",
    "stamp",
    "|",
    "nfill",
    "cfill",
    "cline",
    "cstip",
    "snap",
    "width",
    "|",
    "clear",
    "clearp",
    "|",
    "combat",
    "showhp",
    "aoe",
    "aoebound",
    "ruler",
    "griden",
    "chat",
    "iniclock",
    "tmrq",
    "|",
    "zi",
    "zo",
    "refresh",
    "load",
    "merge",
    "unload",
    "sync",
    "saf",
    "polo",
    "save",
    "exit",
)

TOOLBAR_TOOLTIPS: dict[str, str] = {
    "line": "Mode Select: Line Drawing",
    "rect": "Mode Select: Rectangle Drawing",
    "poly": "Mode Select: Polygon Drawing",
    "circ": "Mode Select: Circle Drawing",
    "arc": "Mode Select: Arc Drawing",
    "text": "Mode Select: Add Text",
    "mode": "",
    "mode2": "",
    "mode3": "",
    "nil": "Mode Select: Normal Play Mode",
    "kill": "Mode Select: Delete Objects",
    "move": "Mode Select: Move Objects",
    "stamp": "Mode Select: Stamp Images/Textures",
    "nfill": "Toggle Fill/No-Fill Mode",
    "cfill": "Select Fill Color",
    "cline": "Select Outline Color",
    "cstip": "Cycle Fill Pattern",
    "snap": "Cycle Grid Snap (none/full/half/third/quarter)",
    "width": "Cycle Line Width (0-9)",
    "clear": "Remove all map objects",
    "clearp": "Remove all creature tokens",
    "combat": "Toggle combat mode",
    "showhp": "Toggle display of actual health stats",
    "aoe": "Set spell Area of Effect",
    "aoebound": "Set bounded AoE (experimental)",
    "ruler": "Measure grid distances along a path",
    "griden": "Toggle visible gridlines",
    "chat": "Open die roller/chat window",
    "iniclock": "Display Initiative Clock Window",
    "tmrq": "Request a New Timer",
    "zi": "Zoom in",
    "zo": "Zoom out",
    "refresh": "Reset to default zoom level",
    "load": "Load map file (overwrite current map)",
    "merge": "Merge map file (add to current map)",
    "unload": "Unload objects from file",
    "sync": "",
    "saf": "Toggle store-and-forward mode",
    "polo": "Sync game state from server",
    "save": "Save map to file",
    "exit": "Exit mapper application",
}


def default_icons_dir() -> Path:
    """Locate the repository or packaged ``icons`` directory."""
    repo_root = Path(__file__).resolve().parents[3]
    candidates: list[Path] = []
    meipass = getattr(sys, "_MEIPASS", None)
    if meipass:
        mp = Path(meipass)
        candidates.append(mp / "lib" / "MadScienceZone" / "GMA" / "Mapper" / "icons")
        candidates.append(mp / "lib" / "icons")
    candidates.extend(
        (
            repo_root / "lib" / "MadScienceZone" / "GMA" / "Mapper" / "icons",
            repo_root / "lib" / "icons",
            Path.cwd() / "lib" / "MadScienceZone" / "GMA" / "Mapper" / "icons",
            Path.cwd() / "lib" / "icons",
        )
    )
    for candidate in candidates:
        if candidate.is_dir():
            return candidate
    return repo_root / "lib" / "MadScienceZone" / "GMA" / "Mapper" / "icons"


def normalize_button_size(value: Any) -> str:
    """Normalize a button size setting (`small`, `medium`, `large`, or `16`/`30`/`40`).

    Matches `switch -glob -- $ButtonSize` in `bin/mapper_legacy.tcl` lines 2278-2285.
    """
    if value is None:
        return "small"
    if isinstance(value, (int, float)):
        iv = int(value)
        if iv >= 40:
            return "large"
        if iv >= 24:
            return "medium"
        return "small"
    s = str(value).strip().lower()
    if s in ("40", "_40") or s.startswith("l"):
        return "large"
    if s in ("30", "_30") or s.startswith("m"):
        return "medium"
    if s in ("16", "") or s.startswith("s"):
        return "small"
    return "small"


def button_size_suffix(button_size: Any) -> str:
    """Return filename suffix (`''`, `'_30'`, or `'_40'`) for `button_size`."""
    norm = normalize_button_size(button_size)
    if norm == "medium":
        return "_30"
    if norm == "large":
        return "_40"
    return ""


def button_pixel_size(button_size: Any) -> int:
    """Return icon pixel dimension (`16`, `30`, or `40`) for `button_size`."""
    norm = normalize_button_size(button_size)
    if norm == "medium":
        return 30
    if norm == "large":
        return 40
    return 16


def resolve_icon_path(
    icon_name: str,
    button_size: Any = "small",
    dark_mode: bool = False,
    image_format: str = "png",
    icons_dir: str | Path | None = None,
) -> Path | None:
    """Resolve the filesystem path for `icon_name` given size, theme, and format.

    Matches the icon loading loop in `bin/mapper_legacy.tcl` lines 2682-2736:
    prefers dark-mode `d_<name><suffix>` when `dark_mode` is True (outside macOS,
    or in general when dark theme is enabled), and falls back across PNG/GIF formats.
    """
    if not icon_name:
        return None
    base_dir = Path(icons_dir) if icons_dir else default_icons_dir()
    suffix = button_size_suffix(button_size)
    fmt = str(image_format or "png").strip().lower()
    formats = ("png", "gif") if fmt != "gif" else ("gif", "png")
    prefixes = ("d_", "") if dark_mode else ("",)
    suffixes = (suffix, "") if suffix else ("",)

    for sfx in suffixes:
        for pfx in prefixes:
            for ext in formats:
                candidate = base_dir / f"{pfx}{icon_name}{sfx}.{ext}"
                if candidate.is_file():
                    return candidate
    return None


def dash_style_icon_name(dash: str) -> str:
    """Return the legacy icon name for `dash` (`cycleDashStyle` in `bin/mapper_legacy.tcl` lines 4446-4460)."""
    mapping = {
        "": "dash0",
        "-": "dash64",
        ",": "dash44",
        ".": "dash24",
        "-.": "dash6424",
        "-..": "dash642424",
    }
    return mapping.get(str(dash or ""), "dash0")


def stipple_icon_name(stipple: str) -> str:
    """Return the legacy icon name for `stipple` (`cycleStipple` in `bin/mapper_legacy.tcl` lines 3152-3189)."""
    mapping = {
        "": "stipple_100",
        "nil": "stipple_100",
        "gray12": "stipple_88",
        "gray25": "stipple_75",
        "gray50": "stipple_50",
        "gray75": "stipple_25",
    }
    return mapping.get(str(stipple or ""), "stipple_100")


def mode_slot_specs(
    active_tool: str,
    draw_join: str = "bevel",
    draw_aoe_shape: str = "radius",
    draw_arc_mode: str = "pieslice",
    draw_arrow: str = "none",
    draw_spline: int = 0,
    draw_aoe_spread: bool = False,
    draw_text_anchor: str = "center",
    draw_dash: str = "",
) -> tuple[tuple[str, str, str, bool], tuple[str, str, str, bool], tuple[str, str, str, bool]]:
    """Compute `(mode1, mode2, mode3)` toolbar slot specifications for the current tool and sub-options.

    Each returned 4-tuple is `(icon_name, text_label, tooltip, enabled)`, matching `.toolbar.mode`,
    `.toolbar.mode2`, and `.toolbar.mode3` in `bin/mapper_legacy.tcl` lines 4155-4562.
    """
    tool = str(active_tool or "pointer")
    mode1: tuple[str, str, str, bool] = ("blank", "Opt1", "", False)
    mode2: tuple[str, str, str, bool] = ("blank", "Opt2", "", False)
    mode3: tuple[str, str, str, bool] = ("blank", "Dash", "", False)

    if tool in ("poly", "aoebound"):
        join_val = draw_join if draw_join in ("bevel", "miter", "round") else "bevel"
        sp_val = int(draw_spline) % 10
        mode1 = (f"join_{join_val}", f"Join:{join_val}", "Cycle join style", True)
        mode2 = (f"spline_{sp_val}", f"Spline:{sp_val}", "Cycle spline level", True)
    elif tool in ("saoe", "aoe"):
        shape_val = draw_aoe_shape if draw_aoe_shape in ("radius", "cone", "ray") else "radius"
        spread_icon = "spread" if draw_aoe_spread else "no_spread"
        spread_lbl = "Spread:ON" if draw_aoe_spread else "Spread:OFF"
        mode1 = (shape_val, f"Shape:{shape_val}", "Cycle Area Shape", True)
        mode2 = (spread_icon, spread_lbl, "Toggle AoE Spread Mode (experimental)", True)
    elif tool == "text":
        anc = draw_text_anchor or "center"
        mode1 = ("style", "Font...", "Show/hide font chooser", True)
        mode2 = (f"anchor_{anc}", f"Anchor:{anc}", "Set text anchor point direction", True)
    elif tool == "arc":
        arc_m = draw_arc_mode if draw_arc_mode in ("pieslice", "chord", "arc") else "pieslice"
        mode1 = (f"arc_{arc_m}", f"Arc:{arc_m}", "Cycle arc style", True)
    elif tool == "line":
        arr = draw_arrow if draw_arrow in ("none", "first", "last", "both") else "none"
        mode2 = (f"arrow_{arr}", f"Arrow:{arr}", "Cycle arrow style", True)

    if tool in ("line", "rect", "poly", "circ", "arc"):
        dash_icon = dash_style_icon_name(draw_dash)
        dash_lbl = f"Dash:{draw_dash or 'solid'}"
        mode3 = (dash_icon, dash_lbl, "Cycle dash style", True)

    return (mode1, mode2, mode3)


class IconCatalog:
    """Loads and caches `QIcon` instances for GMA Mapper's toolbar and window icons."""

    def __init__(
        self,
        icons_dir: str | Path | None = None,
        button_size: str = "small",
        dark_mode: bool = False,
        image_format: str = "png",
    ) -> None:
        self.icons_dir = Path(icons_dir) if icons_dir else default_icons_dir()
        self.button_size = normalize_button_size(button_size)
        self.dark_mode = bool(dark_mode)
        self.image_format = str(image_format or "png").lower()
        self._icon_cache: dict[tuple[str, str, bool, str], Any] = {}

    def configure(
        self,
        button_size: Any = None,
        dark_mode: bool | None = None,
        image_format: str | None = None,
    ) -> None:
        if button_size is not None:
            self.button_size = normalize_button_size(button_size)
        if dark_mode is not None:
            self.dark_mode = bool(dark_mode)
        if image_format is not None:
            self.image_format = str(image_format or "png").lower()

    def pixel_size(self) -> int:
        return button_pixel_size(self.button_size)

    def path_for(self, icon_name: str) -> Path | None:
        return resolve_icon_path(
            icon_name,
            button_size=self.button_size,
            dark_mode=self.dark_mode,
            image_format=self.image_format,
            icons_dir=self.icons_dir,
        )

    def icon(self, icon_name: str) -> Any:
        """Return a `QIcon` for `icon_name` at the current size/theme (or `None` if headless)."""
        if not HAS_PYSIDE6:
            return None
        key = (icon_name, self.button_size, self.dark_mode, self.image_format)
        if key in self._icon_cache:
            return self._icon_cache[key]
        path = self.path_for(icon_name)
        if path is not None and path.is_file():
            pm = QPixmap(str(path))
            if not pm.isNull():
                ic = QIcon()
                ic.addPixmap(pm, QIcon.Mode.Normal, QIcon.State.Off)
                ic.addPixmap(pm, QIcon.Mode.Normal, QIcon.State.On)
                ic.addPixmap(pm, QIcon.Mode.Disabled, QIcon.State.Off)
                self._icon_cache[key] = ic
                return ic
        empty = QIcon()
        self._icon_cache[key] = empty
        return empty

    def color_swatch_icon(self, icon_name: str, color_str: str) -> Any:
        """Return `icon_name` (`fill_color` or `outline_color`) composited over a `color_str` background."""
        if not HAS_PYSIDE6:
            return None
        px = self.pixel_size()
        base = QPixmap(px, px)
        qcol = QColor(color_str or "black")
        if not qcol.isValid():
            qcol = QColor("black")
        base.fill(qcol)

        fg_path = self.path_for(icon_name)
        if fg_path is not None and fg_path.is_file():
            fg = QPixmap(str(fg_path))
            if not fg.isNull():
                painter = QPainter(base)
                if fg.width() != px or fg.height() != px:
                    fg = fg.scaled(
                        QSize(px, px),
                        Qt.AspectRatioMode.KeepAspectRatio,
                        Qt.TransformationMode.SmoothTransformation,
                    )
                painter.drawPixmap(0, 0, fg)
                painter.end()
        ic = QIcon()
        ic.addPixmap(base, QIcon.Mode.Normal, QIcon.State.Off)
        ic.addPixmap(base, QIcon.Mode.Normal, QIcon.State.On)
        return ic

    def app_window_icon(self) -> Any:
        """Return multi-size application `QIcon` (`gma_icon_512` .. `gma_icon_16`)."""
        if not HAS_PYSIDE6:
            return None
        ic = QIcon()
        formats = ("png", "gif") if self.image_format != "gif" else ("gif", "png")
        for sz in APP_ICON_SIZES:
            for ext in formats:
                p = self.icons_dir / f"gma_icon_{sz}.{ext}"
                if p.is_file():
                    pm = QPixmap(str(p))
                    if not pm.isNull():
                        ic.addPixmap(pm)
                        break
        return ic
