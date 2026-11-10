"""Preferences and Server Profile Editor Dialog (`~/.gma/mapper/preferences.json`)."""

from __future__ import annotations

import copy
from typing import Any

from gma_mapper.core.colors import contrasting_color, rgb_name
from gma_mapper.core.profile import (
    MARKER_SHAPES,
    STYLE_DESCRIPTIONS,
    default_color,
    default_styles,
    empty_server_profile,
    find_server_index,
    fix_missing,
    symbol_code_string,
)

try:
    from PySide6.QtGui import QColor, QFont
    from PySide6.QtWidgets import (
        QColorDialog,
        QDialog,
        QVBoxLayout,
        QHBoxLayout,
        QGridLayout,
        QTabWidget,
        QWidget,
        QFormLayout,
        QGroupBox,
        QLineEdit,
        QListWidget,
        QSpinBox,
        QDoubleSpinBox,
        QCheckBox,
        QComboBox,
        QPushButton,
        QDialogButtonBox,
        QFontDialog,
        QInputDialog,
        QLabel,
        QMessageBox,
        QTextEdit,
    )
    HAS_PYSIDE6 = True
except ImportError:
    HAS_PYSIDE6 = False

SHOW_TIMERS_OPTIONS: list[tuple[str, str]] = [
    ("none", "Show no timers"),
    ("mine", "Show only my timers"),
    ("all", "Show all timers"),
]

IMAGE_FORMAT_OPTIONS: list[tuple[str, str]] = [
    ("png", "Use PNG-format images"),
    ("gif", "Use GIF-format images"),
]

BUTTON_SIZE_OPTIONS: list[tuple[str, str]] = [
    ("small", "Button size: small"),
    ("medium", "Button size: medium"),
    ("large", "Button size: large"),
]

DIALOG_COLOR_FIELDS: list[tuple[str, str]] = [
    ("heading_fg", "Heading color"),
    ("normal_fg", "Normal text color"),
    ("normal_bg", "Normal text background"),
    ("highlight_fg", "Highlighted text color"),
    ("odd_bg", "Odd-row background"),
    ("even_bg", "Even-row background"),
    ("preset_name", "Die-roll preset name color"),
]

GRID_COLOR_FIELDS: list[tuple[str, str]] = [
    ("grid", "Normal 5' grid color"),
    ("grid_minor", "Minor guide grid color"),
    ("grid_major", "Major guide grid color"),
    ("check_menu", "Check menu color"),
    ("check_select", "Checkbox select color"),
]

CLOCK_COLOR_FIELDS: list[tuple[str, str]] = [
    ("hand_color", "Clock hands"),
    ("tick_color", "Clock tick marks"),
    ("flist_fg", "Initiative list text color"),
    ("flist_bg", "Initiative list background"),
    ("next_fg", "Next round marker color"),
    ("next_bg", "Next round marker background"),
    ("cur_bg", "Current actor background"),
    ("ready_bg", "Readied action background"),
    ("hold_bg", "Held action background"),
    ("zero_hp", "Frame: zero hit points"),
    ("negative_hp", "Frame: negative hit points"),
    ("flat_footed", "Frame: flat-footed"),
    ("slot_fg", "Negative hit point text color"),
    ("slot_bg", "Negative hit point background"),
]

CLOCK_FONT_FIELDS: list[tuple[str, str]] = [
    ("timedisp_font", "Time display font"),
    ("turndisp_font", "Turn display font"),
    ("default_font", "Initiative list font"),
]

SYMBOL_FIELDS: list[tuple[str, str, list[str]]] = [
    (
        "pushpin",
        "Un-Pin Message",
        ["pin", "triangle", "arrow", "bullet", "circle-x", "ref-mk", "remove", "square-x", "ballot-x"],
    ),
    (
        "delmsg",
        "Delete Message",
        ["del", "circle-x", "ref-mk", "remove", "square-x", "ballot-x"],
    ),
    (
        "localpin",
        "Locally Pin Message",
        ["up-arrow", "add", "pin", "ref-mk", "bullet", "triangle"],
    ),
]

PANGRAM_LIST: list[str] = [
    "Waltz, bad nymph, for quick jigs vex",
    "Glib jocks quiz nymph to vex dwarf.",
    "Sphinx of black quartz, judge my vow.",
    "How quickly daft jumping zebras vex!",
    "The five boxing wizards jump quickly.",
    "Jackdaws love my big sphinx of quartz.",
    "Pack my box with five dozen liquor jugs.",
]


def _spaces_to_under(s: str) -> str:
    if not s:
        return ""
    if s.startswith(" "):
        s = "_" + s[1:]
    if len(s) > 0 and s.endswith(" "):
        s = s[:-1] + "_"
    return s


def _under_to_spaces(s: str) -> str:
    s = s.strip()
    if not s:
        return ""
    if s.startswith("_"):
        s = " " + s[1:]
    if len(s) > 0 and s.endswith("_"):
        s = s[:-1] + " "
    return s


def _attempt_format(fmt: str, s: str) -> str:
    if not fmt:
        return s
    try:
        return fmt % s
    except Exception:
        return "**ERROR**"


if HAS_PYSIDE6:

    class PreferencesDialog(QDialog):
        """Multi-tab preferences editor ported from `bin/gmaprofile.tcl` (`::gmaprofile::editor`)."""

        def __init__(self, prefs: dict[str, Any], parent: QWidget | None = None) -> None:
            super().__init__(parent)
            self.setWindowTitle("Mapper Preferences")
            self.resize(620, 640)
            self.prefs = fix_missing(copy.deepcopy(prefs))
            self._editing_idx: int = -1

            layout = QVBoxLayout(self)
            self.tabs = QTabWidget(self)
            layout.addWidget(self.tabs, 1)

            self.dialog_color_btns: dict[tuple[str, str], QPushButton] = {}
            self.dialog_reset_btns: dict[str, QPushButton] = {}
            self.grid_color_btns: dict[tuple[str, str], QPushButton] = {}
            self.grid_reset_btns: dict[str, QPushButton] = {}
            self.clock_color_btns: dict[tuple[str, str], QPushButton] = {}
            self.clock_reset_btns: dict[str, QPushButton] = {}
            self.clock_font_combos: dict[str, QComboBox] = {}
            self.symbol_combos: dict[str, QComboBox] = {}
            self.symbol_preview_labels: dict[str, QLabel] = {}
            self._updating_dieroll_ui: bool = False
            self._updating_marker_ui: bool = False

            self._build_appearance_tab()
            self._build_servers_tab()
            self._build_styles_tab()
            self._build_tools_tab()
            self._build_diagnostics_tab()
            self._build_accessibility_tab()

            buttons = QDialogButtonBox(
                QDialogButtonBox.StandardButton.Save | QDialogButtonBox.StandardButton.Cancel,
                self,
            )
            buttons.accepted.connect(self._on_accept)
            buttons.rejected.connect(self.reject)
            layout.addWidget(buttons)

        def _build_appearance_tab(self) -> None:
            """Build the Appearance tab (`$w.n.a` in `bin/gmaprofile.tcl` lines 1307-1358)."""
            tab = QWidget(self.tabs)
            tab_layout = QVBoxLayout(tab)

            # 1. MAPPER APPEARANCE SETTINGS
            app_group = QGroupBox("MAPPER APPEARANCE SETTINGS", tab)
            app_layout = QVBoxLayout(app_group)

            self.animate_check = QCheckBox("Animate updates", app_group)
            self.animate_check.setChecked(bool(self.prefs.get("animate", False)))
            app_layout.addWidget(self.animate_check)

            self.flash_updates_check = QCheckBox("Flash objects when they are updated", app_group)
            self.flash_updates_check.setChecked(bool(self.prefs.get("flash_updates", False)))
            app_layout.addWidget(self.flash_updates_check)

            self.chat_timestamp_check = QCheckBox("Show timestamp in chat messages", app_group)
            self.chat_timestamp_check.setChecked(bool(self.prefs.get("chat_timestamp", True)))
            app_layout.addWidget(self.chat_timestamp_check)

            self.colorize_die_rolls_check = QCheckBox("Enable colors in die-roll titles", app_group)
            self.colorize_die_rolls_check.setChecked(bool(self.prefs.get("colorize_die_rolls", True)))
            app_layout.addWidget(self.colorize_die_rolls_check)

            self.markup_enabled_check = QCheckBox("Enable markup by default in chat messages", app_group)
            self.markup_enabled_check.setChecked(bool(self.prefs.get("markup_enabled", True)))
            app_layout.addWidget(self.markup_enabled_check)

            self.dark_check = QCheckBox("Dark theme", app_group)
            self.dark_check.setChecked(bool(self.prefs.get("dark", False)))
            app_layout.addWidget(self.dark_check)

            scaling_row = QHBoxLayout()
            scaling_row.addWidget(QLabel("Visual scaling factor:", app_group))
            self.scaling_spin = QDoubleSpinBox(app_group)
            self.scaling_spin.setRange(1.0, 100.0)
            self.scaling_spin.setSingleStep(1.0)
            self.scaling_spin.setDecimals(1)
            self.scaling_spin.setValue(float(self.prefs.get("scaling", 1.0) or 1.0))
            scaling_row.addWidget(self.scaling_spin)
            scaling_row.addStretch(1)
            app_layout.addLayout(scaling_row)

            self.menu_button_check = QCheckBox("Use menu button instead of menu bar", app_group)
            self.menu_button_check.setChecked(bool(self.prefs.get("menu_button", False)))
            app_layout.addWidget(self.menu_button_check)

            self.never_animate_check = QCheckBox("Never play animated images", app_group)
            self.never_animate_check.setChecked(bool(self.prefs.get("never_animate", False)))
            app_layout.addWidget(self.never_animate_check)

            self.keep_tools_check = QCheckBox("Keep toolbar visible", app_group)
            self.keep_tools_check.setChecked(bool(self.prefs.get("keep_tools", False)))
            app_layout.addWidget(self.keep_tools_check)

            self.show_timers_combo = QComboBox(app_group)
            cur_timers = str(self.prefs.get("show_timers", "mine") or "mine")
            if cur_timers not in ("none", "mine", "all"):
                cur_timers = "mine"
            for idx, (val, label) in enumerate(SHOW_TIMERS_OPTIONS):
                self.show_timers_combo.addItem(label, val)
                if val == cur_timers:
                    self.show_timers_combo.setCurrentIndex(idx)
            app_layout.addWidget(self.show_timers_combo)

            self.preload_check = QCheckBox("Pre-load all cached images", app_group)
            self.preload_check.setChecked(bool(self.prefs.get("preload", False)))
            app_layout.addWidget(self.preload_check)

            self.image_format_combo = QComboBox(app_group)
            cur_fmt = str(self.prefs.get("image_format", "png") or "png").lower()
            if cur_fmt not in ("png", "gif"):
                cur_fmt = "png"
            for idx, (val, label) in enumerate(IMAGE_FORMAT_OPTIONS):
                self.image_format_combo.addItem(label, val)
                if val == cur_fmt:
                    self.image_format_combo.setCurrentIndex(idx)
            app_layout.addWidget(self.image_format_combo)

            self.button_size_combo = QComboBox(app_group)
            cur_bsize = str(self.prefs.get("button_size", "small") or "small").lower()
            if cur_bsize not in ("small", "medium", "large"):
                cur_bsize = "small"
            for idx, (val, label) in enumerate(BUTTON_SIZE_OPTIONS):
                self.button_size_combo.addItem(label, val)
                if val == cur_bsize:
                    self.button_size_combo.setCurrentIndex(idx)
            app_layout.addWidget(self.button_size_combo)

            self.toolbar_icons_check = QCheckBox("Display toolbar buttons as icons", app_group)
            self.toolbar_icons_check.setChecked(not bool(self.prefs.get("toolbar_text", False)))
            app_layout.addWidget(self.toolbar_icons_check)

            tab_layout.addWidget(app_group)

            # 2. EXTRA GRID LINES
            grid_group = QGroupBox("EXTRA GRID LINES", tab)
            grid_layout = QVBoxLayout(grid_group)

            guides = self.prefs.get("guide_lines", {})
            major = guides.get("major", {}) if isinstance(guides, dict) else {}
            major_off = major.get("offsets", {}) if isinstance(major, dict) else {}
            minor = guides.get("minor", {}) if isinstance(guides, dict) else {}
            minor_off = minor.get("offsets", {}) if isinstance(minor, dict) else {}

            major_row = QHBoxLayout()
            self.major_interval_spin = QSpinBox(grid_group)
            self.major_interval_spin.setRange(0, 100)
            self.major_interval_spin.setValue(int(major.get("interval", 0) or 0))
            self.major_offset_x_spin = QSpinBox(grid_group)
            self.major_offset_x_spin.setRange(-100, 100)
            self.major_offset_x_spin.setValue(int(major_off.get("x", 0) or 0))
            self.major_offset_y_spin = QSpinBox(grid_group)
            self.major_offset_y_spin.setRange(-100, 100)
            self.major_offset_y_spin.setValue(int(major_off.get("y", 0) or 0))
            major_row.addWidget(QLabel("Major grid lines every", grid_group))
            major_row.addWidget(self.major_interval_spin)
            major_row.addWidget(QLabel("offset by", grid_group))
            major_row.addWidget(self.major_offset_x_spin)
            major_row.addWidget(QLabel("right,", grid_group))
            major_row.addWidget(self.major_offset_y_spin)
            major_row.addWidget(QLabel("down.", grid_group))
            major_row.addStretch(1)
            grid_layout.addLayout(major_row)

            minor_row = QHBoxLayout()
            self.minor_interval_spin = QSpinBox(grid_group)
            self.minor_interval_spin.setRange(0, 100)
            self.minor_interval_spin.setValue(int(minor.get("interval", 0) or 0))
            self.minor_offset_x_spin = QSpinBox(grid_group)
            self.minor_offset_x_spin.setRange(-100, 100)
            self.minor_offset_x_spin.setValue(int(minor_off.get("x", 0) or 0))
            self.minor_offset_y_spin = QSpinBox(grid_group)
            self.minor_offset_y_spin.setRange(-100, 100)
            self.minor_offset_y_spin.setValue(int(minor_off.get("y", 0) or 0))
            minor_row.addWidget(QLabel("Minor grid lines every", grid_group))
            minor_row.addWidget(self.minor_interval_spin)
            minor_row.addWidget(QLabel("offset by", grid_group))
            minor_row.addWidget(self.minor_offset_x_spin)
            minor_row.addWidget(QLabel("right,", grid_group))
            minor_row.addWidget(self.minor_offset_y_spin)
            minor_row.addWidget(QLabel("down.", grid_group))
            minor_row.addStretch(1)
            grid_layout.addLayout(minor_row)

            tab_layout.addWidget(grid_group)

            # 3. PLAYER OPTIONS
            player_group = QGroupBox("PLAYER OPTIONS", tab)
            player_layout = QVBoxLayout(player_group)

            self.no_dice_check = QCheckBox("Disable die rolling (die roller will be read-only)", player_group)
            self.no_dice_check.setChecked(bool(self.prefs.get("no_dice", False)))
            player_layout.addWidget(self.no_dice_check)

            self.suppress_aka_check = QCheckBox("Never ask me what characters I'm playing", player_group)
            self.suppress_aka_check.setChecked(bool(self.prefs.get("suppress_aka", False)))
            player_layout.addWidget(self.suppress_aka_check)

            self.not_playing_check = QCheckBox("I'm not playing any character from this username", player_group)
            self.not_playing_check.setChecked(bool(self.prefs.get("not_playing", False)))
            player_layout.addWidget(self.not_playing_check)

            self.no_ondeck_audio_check = QCheckBox("Mute audio cues for ondeck and my turns", player_group)
            self.no_ondeck_audio_check.setChecked(bool(self.prefs.get("no_ondeck_audio", False)))
            player_layout.addWidget(self.no_ondeck_audio_check)

            self.no_sfx_check = QCheckBox("Mute audio sound effects for game play", player_group)
            self.no_sfx_check.setChecked(bool(self.prefs.get("no_sfx", False)))
            self.no_sfx_check.setEnabled(False)
            player_layout.addWidget(self.no_sfx_check)

            tab_layout.addWidget(player_group)
            tab_layout.addStretch(1)

            self.tabs.addTab(tab, "Appearance")

        def _build_servers_tab(self) -> None:
            tab = QWidget(self.tabs)
            form = QFormLayout(tab)

            top_row = QHBoxLayout()
            self.server_combo = QComboBox(tab)
            for srv in self.prefs.get("profiles", []):
                self.server_combo.addItem(str(srv.get("name", "offline")))
            top_row.addWidget(self.server_combo, 1)

            btn_new = QPushButton("New Profile", tab)
            btn_new.clicked.connect(self._on_new_server)
            top_row.addWidget(btn_new)
            form.addRow("Profile:", top_row)

            self.host_edit = QLineEdit(tab)
            self.port_spin = QSpinBox(tab)
            self.port_spin.setRange(1, 65535)
            self.user_edit = QLineEdit(tab)
            self.pass_edit = QLineEdit(tab)
            self.pass_edit.setEchoMode(QLineEdit.EchoMode.Password)
            self.curl_edit = QLineEdit(tab)
            self.scp_server_edit = QLineEdit(tab)
            self.scp_dest_edit = QLineEdit(tab)

            form.addRow("Host:", self.host_edit)
            form.addRow("Port:", self.port_spin)
            form.addRow("Username:", self.user_edit)
            form.addRow("Password:", self.pass_edit)
            form.addRow("HTTP Base URL:", self.curl_edit)
            form.addRow("Upload SSH Host:", self.scp_server_edit)
            form.addRow("Upload Destination:", self.scp_dest_edit)

            self.tabs.addTab(tab, "Servers")
            if self.prefs.get("profiles"):
                cur_name = str(self.prefs.get("current_profile") or "offline")
                initial_idx = find_server_index(self.prefs, cur_name)
                if initial_idx < 0:
                    initial_idx = 0
                self.server_combo.setCurrentIndex(initial_idx)
                self._load_selected_server(initial_idx)
            self.server_combo.currentIndexChanged.connect(self._on_server_index_changed)

        @staticmethod
        def _style_color_button(btn: QPushButton, color: str) -> None:
            if not color:
                btn.setText("")
                btn.setStyleSheet("")
                return
            btn.setText(rgb_name(color))
            try:
                fg = contrasting_color(color)
            except Exception:
                fg = "black"
            btn.setStyleSheet(f"background-color: {color}; color: {fg};")

        @staticmethod
        def _dict_to_qfont(font_d: dict[str, Any]) -> QFont:
            qfont = QFont(str(font_d.get("family", "Helvetica")), int(font_d.get("size", 12) or 12))
            qfont.setBold(bool(int(font_d.get("weight", 0) or 0)))
            qfont.setItalic(bool(int(font_d.get("slant", 0) or 0)))
            qfont.setStrikeOut(bool(font_d.get("overstrike", False)))
            qfont.setUnderline(bool(font_d.get("underline", False)))
            return qfont

        @staticmethod
        def _describe_font_dict(font_d: dict[str, Any] | None) -> str:
            if not font_d:
                return ""
            desc = f"{font_d.get('family', 'Helvetica')} {int(font_d.get('size', 12) or 12)}"
            if int(font_d.get("weight", 0) or 0) > 0:
                desc += ", bold"
            if int(font_d.get("slant", 0) or 0) > 0:
                desc += ", italic"
            if font_d.get("overstrike"):
                desc += ", overstrike"
            if font_d.get("underline"):
                desc += ", underline"
            return f"{desc}: "

        def _build_styles_tab(self) -> None:
            """Build the Styles tab (`$w.n.s`) and its 7 sub-tabs (`bin/gmaprofile.tcl` lines 991-1290)."""
            tab = QWidget(self.tabs)
            layout = QVBoxLayout(tab)
            self.styles_tabs = QTabWidget(tab)
            layout.addWidget(self.styles_tabs, 1)

            self._build_styles_fonts_tab()
            self._build_styles_dialogs_tab()
            self._build_styles_dierolls_tab()
            self._build_styles_symbols_tab()
            self._build_styles_colors_tab()
            self._build_styles_clocks_tab()
            self._build_styles_markers_tab()

            self.tabs.addTab(tab, "Styles")

        # ------------------------------------------------------------------
        # Styles Sub-Tab 1: Fonts ($st.f)
        # ------------------------------------------------------------------
        def _build_styles_fonts_tab(self) -> None:
            tab = QWidget(self.styles_tabs)
            vbox = QVBoxLayout(tab)

            top_row = QHBoxLayout()
            self.fonts_list = QListWidget(tab)
            for fname in self.prefs.get("fonts", {}):
                self.fonts_list.addItem(str(fname))
            self.fonts_list.currentTextChanged.connect(self._on_font_selected)
            top_row.addWidget(self.fonts_list, 1)

            btn_col = QVBoxLayout()
            self.font_add_btn = QPushButton("Add New...", tab)
            self.font_add_btn.clicked.connect(self._on_add_font_clicked)
            self.font_copy_btn = QPushButton("Copy", tab)
            self.font_copy_btn.setEnabled(False)
            self.font_copy_btn.clicked.connect(self._on_copy_font_clicked)
            self.font_del_btn = QPushButton("Delete", tab)
            self.font_del_btn.setEnabled(False)
            self.font_del_btn.clicked.connect(self._on_delete_font_clicked)
            btn_col.addWidget(self.font_add_btn)
            btn_col.addWidget(self.font_copy_btn)
            btn_col.addStretch(1)
            btn_col.addWidget(self.font_del_btn)
            top_row.addLayout(btn_col)
            vbox.addLayout(top_row, 1)

            self.font_choose_btn = QPushButton("Show Font Chooser", tab)
            self.font_choose_btn.clicked.connect(self._on_choose_font_clicked)
            vbox.addWidget(self.font_choose_btn)

            self.font_desc_label = QLabel("", tab)
            self.font_sample_label = QLabel("", tab)
            self.font_sample_label.setWordWrap(True)
            vbox.addWidget(self.font_desc_label)
            vbox.addWidget(self.font_sample_label)

            self.styles_tabs.addTab(tab, "Fonts")

        def selected_font_name(self) -> str:
            item = self.fonts_list.currentItem()
            return item.text() if item is not None else ""

        def _on_font_selected(self, name: str) -> None:
            fonts = self.prefs.get("fonts", {})
            if not name or name not in fonts:
                self.font_copy_btn.setEnabled(False)
                self.font_copy_btn.setText("Copy")
                self.font_del_btn.setEnabled(False)
                self.font_del_btn.setText("Delete")
                self.font_desc_label.setText("")
                self.font_sample_label.setText("")
                return
            self.font_copy_btn.setEnabled(True)
            self.font_copy_btn.setText(f"Copy {name}")
            self.font_del_btn.setEnabled(True)
            self.font_del_btn.setText(f"Delete {name}")
            font_d = fonts[name]
            self.font_desc_label.setText(self._describe_font_dict(font_d))
            self.font_sample_label.setFont(self._dict_to_qfont(font_d))
            self.font_sample_label.setText(f"{PANGRAM_LIST[0]}; 0,123,456,789 +-*/ [](){{}}?!")

        def _refresh_font_combos(self) -> None:
            font_names = list(self.prefs.get("fonts", {}).keys())
            if hasattr(self, "dr_font_combo"):
                cur = self.dr_font_combo.currentText()
                self.dr_font_combo.blockSignals(True)
                self.dr_font_combo.clear()
                self.dr_font_combo.addItems(font_names)
                if cur in font_names:
                    self.dr_font_combo.setCurrentText(cur)
                self.dr_font_combo.blockSignals(False)
            for fld, combo in self.clock_font_combos.items():
                cur = str(self.prefs.get("styles", {}).get("clocks", {}).get(fld, "") or combo.currentText())
                combo.blockSignals(True)
                combo.clear()
                combo.addItems(font_names)
                if cur in font_names:
                    combo.setCurrentText(cur)
                combo.blockSignals(False)

        def add_font(self, name: str, font_dict: dict[str, Any] | None = None) -> bool:
            name = name.strip()
            if not name or name in self.prefs.get("fonts", {}):
                return False
            self.prefs.setdefault("fonts", {})[name] = (
                copy.deepcopy(font_dict)
                if font_dict is not None
                else {
                    "family": "Helvetica",
                    "size": 12,
                    "weight": 0,
                    "slant": 0,
                    "overstrike": False,
                    "underline": False,
                }
            )
            self.fonts_list.addItem(name)
            self.fonts_list.setCurrentRow(self.fonts_list.count() - 1)
            self._refresh_font_combos()
            return True

        def copy_selected_font(self, new_name: str) -> bool:
            src = self.selected_font_name()
            if not src or src not in self.prefs.get("fonts", {}):
                return False
            return self.add_font(new_name, self.prefs["fonts"][src])

        def font_references(self, name: str) -> list[str]:
            refs: list[str] = []
            comps = self.prefs.get("styles", {}).get("dierolls", {}).get("components", {})
            for sname, sdata in comps.items():
                if sdata.get("font") == name:
                    refs.append(sname)
            clocks = self.prefs.get("styles", {}).get("clocks", {})
            for ff in ("timedisp_font", "turndisp_font", "default_font"):
                if clocks.get(ff) == name:
                    refs.append("clock")
                    break
            return refs

        def delete_selected_font(self) -> bool:
            src = self.selected_font_name()
            if not src or src not in self.prefs.get("fonts", {}):
                return False
            if self.font_references(src):
                return False
            row = self.fonts_list.currentRow()
            if row >= 0:
                self.fonts_list.takeItem(row)
            del self.prefs["fonts"][src]
            self.fonts_list.clearSelection()
            self._on_font_selected("")
            self._refresh_font_combos()
            return True

        def set_selected_font(self, font_dict: dict[str, Any]) -> bool:
            src = self.selected_font_name()
            if not src or src not in self.prefs.get("fonts", {}):
                return False
            normalized = {
                "family": str(font_dict.get("family", "Helvetica")),
                "size": int(font_dict.get("size", 12) or 12),
                "weight": 1 if int(font_dict.get("weight", 0) or 0) > 0 else 0,
                "slant": 1 if int(font_dict.get("slant", 0) or 0) > 0 else 0,
                "overstrike": bool(font_dict.get("overstrike", False)),
                "underline": bool(font_dict.get("underline", False)),
            }
            self.prefs["fonts"][src] = normalized
            self._on_font_selected(src)
            return True

        def _on_add_font_clicked(self) -> None:
            name, ok = QInputDialog.getText(self, "Name of new font", "Name of new font:")
            if ok and name.strip():
                if not self.add_font(name.strip()):
                    QMessageBox.critical(
                        self,
                        "Duplicate name",
                        f'You tried to add a font called "{name.strip()}" but that name already exists in the font set.',
                    )

        def _on_copy_font_clicked(self) -> None:
            src = self.selected_font_name()
            if not src:
                return
            name, ok = QInputDialog.getText(
                self, f"Name of new font (copy of {src})", f"Name of new font (copy of {src}):"
            )
            if ok and name.strip():
                if not self.copy_selected_font(name.strip()):
                    QMessageBox.critical(
                        self,
                        "Duplicate name",
                        f'You tried to add a font called "{name.strip()}" but that name already exists in the font set.',
                    )

        def _on_delete_font_clicked(self) -> None:
            src = self.selected_font_name()
            if not src:
                return
            refs = self.font_references(src)
            if refs:
                QMessageBox.critical(
                    self,
                    "Font in use!",
                    f'You cannot delete font "{src}" because it is referenced by: {", ".join(refs)}',
                )
                return
            ans = QMessageBox.warning(
                self,
                "Confirm Deletion",
                f'Are you SURE you want to delete the font "{src}"? This operation cannot be undone.',
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.No,
            )
            if ans == QMessageBox.StandardButton.Yes:
                self.delete_selected_font()

        def _on_choose_font_clicked(self) -> None:
            src = self.selected_font_name()
            if not src:
                QMessageBox.critical(
                    self,
                    "No Font Selected",
                    "You selected a new font, but did not select which font that was supposed to modify.",
                )
                return
            cur_qfont = self._dict_to_qfont(self.prefs["fonts"][src])
            ok, qfont = QFontDialog.getFont(cur_qfont, self, "Choose Font")
            if ok:
                self.set_selected_font(
                    {
                        "family": qfont.family(),
                        "size": int(qfont.pointSize() if qfont.pointSize() > 0 else 12),
                        "weight": 1 if qfont.bold() else 0,
                        "slant": 1 if qfont.italic() else 0,
                        "overstrike": qfont.strikeOut(),
                        "underline": qfont.underline(),
                    }
                )

        # ------------------------------------------------------------------
        # Styles Sub-Tab 2: Dialogs ($st.d)
        # ------------------------------------------------------------------
        def _build_styles_dialogs_tab(self) -> None:
            tab = QWidget(self.styles_tabs)
            vbox = QVBoxLayout(tab)
            grid = QGridLayout()
            grid.addWidget(QLabel("Light Mode", tab), 0, 1)
            grid.addWidget(QLabel("Dark Mode", tab), 0, 2)

            dialogs = self.prefs.setdefault("styles", {}).setdefault("dialogs", {})
            for row, (fld, label) in enumerate(DIALOG_COLOR_FIELDS, start=1):
                grid.addWidget(QLabel(f"{label}:", tab), row, 0)
                for col, theme in enumerate(("light", "dark"), start=1):
                    color = str(dialogs.get(fld, {}).get(theme, "") or "")
                    btn = QPushButton(tab)
                    self._style_color_button(btn, color)
                    btn.clicked.connect(
                        lambda _c=False, f=fld, t=theme, lbl=label: self._prompt_dialog_color(f, t, lbl)
                    )
                    self.dialog_color_btns[(fld, theme)] = btn
                    grid.addWidget(btn, row, col)
                reset_btn = QPushButton("Reset to Default", tab)
                reset_btn.clicked.connect(lambda _c=False, f=fld: self.reset_dialog_color(f))
                self.dialog_reset_btns[fld] = reset_btn
                grid.addWidget(reset_btn, row, 3)

            vbox.addLayout(grid)

            self.dialog_light_preview = QTextEdit(tab)
            self.dialog_light_preview.setReadOnly(True)
            self.dialog_light_preview.setMaximumHeight(90)
            self.dialog_dark_preview = QTextEdit(tab)
            self.dialog_dark_preview.setReadOnly(True)
            self.dialog_dark_preview.setMaximumHeight(90)
            vbox.addWidget(QLabel("Light Mode Example:", tab))
            vbox.addWidget(self.dialog_light_preview)
            vbox.addWidget(QLabel("Dark Mode Example:", tab))
            vbox.addWidget(self.dialog_dark_preview)
            vbox.addStretch(1)

            self._refresh_dialog_examples()
            self.styles_tabs.addTab(tab, "Dialogs")

        def _refresh_dialog_examples(self) -> None:
            dialogs = self.prefs.get("styles", {}).get("dialogs", {})
            for widget, theme in ((self.dialog_light_preview, "light"), (self.dialog_dark_preview, "dark")):
                nfg = dialogs.get("normal_fg", {}).get(theme, "#000000")
                nbg = dialogs.get("normal_bg", {}).get(theme, "#cccccc")
                hfg = dialogs.get("heading_fg", {}).get(theme, "blue")
                ifg = dialogs.get("highlight_fg", {}).get(theme, "red")
                obg = dialogs.get("odd_bg", {}).get(theme, nbg)
                ebg = dialogs.get("even_bg", {}).get(theme, "#bbbbff")
                widget.setStyleSheet(f"background-color: {nbg}; color: {nfg};")
                html = (
                    f"<div style='color:{hfg};'>Example Heading</div>"
                    f"<div style='background-color:{obg}; color:{nfg};'>Odd-numbered row: normal, "
                    f"<span style='color:{ifg};'>highlighted</span></div>"
                    f"<div style='background-color:{ebg}; color:{nfg};'>Even-numbered row: normal, "
                    f"<span style='color:{ifg};'>highlighted</span></div>"
                )
                widget.setHtml(html)

        def set_dialog_color(self, fld: str, theme: str, color: str) -> None:
            dialogs = self.prefs.setdefault("styles", {}).setdefault("dialogs", {})
            dialogs.setdefault(fld, {})[theme] = color
            btn = self.dialog_color_btns.get((fld, theme))
            if btn is not None:
                self._style_color_button(btn, color)
            self._refresh_dialog_examples()
            self._refresh_dieroller_examples()

        def reset_dialog_color(self, fld: str) -> None:
            defs = default_styles()["dialogs"].get(fld, {})
            for theme in ("light", "dark"):
                if theme in defs:
                    self.set_dialog_color(fld, theme, str(defs[theme]))

        def _prompt_dialog_color(self, fld: str, theme: str, label: str) -> None:
            cur = str(self.prefs.get("styles", {}).get("dialogs", {}).get(fld, {}).get(theme, "") or "black")
            col = QColorDialog.getColor(QColor(cur), self, f"Choose color for {label} ({theme} mode)")
            if col.isValid():
                self.set_dialog_color(fld, theme, col.name())

        # ------------------------------------------------------------------
        # Styles Sub-Tab 3: Die Rolls/Chat ($st.r)
        # ------------------------------------------------------------------
        def _build_styles_dierolls_tab(self) -> None:
            tab = QWidget(self.styles_tabs)
            vbox = QVBoxLayout(tab)

            top_split = QHBoxLayout()
            self.dieroll_styles_list = QListWidget(tab)
            comps = self.prefs.get("styles", {}).get("dierolls", {}).get("components", {})
            for sname in sorted(comps.keys()):
                self.dieroll_styles_list.addItem(sname)
            self.dieroll_styles_list.currentTextChanged.connect(self._on_dieroll_style_selected)
            top_split.addWidget(self.dieroll_styles_list, 1)

            right_col = QVBoxLayout()
            self.dr_desc_text = QTextEdit(tab)
            self.dr_desc_text.setReadOnly(True)
            self.dr_desc_text.setMaximumHeight(60)
            right_col.addWidget(self.dr_desc_text)

            color_grid = QGridLayout()
            color_grid.addWidget(QLabel("Light Mode", tab), 0, 1)
            color_grid.addWidget(QLabel("Dark Mode", tab), 0, 2)

            self.dr_fg_check = QCheckBox("Text color:", tab)
            self.dr_fg_check.toggled.connect(self._on_dr_fg_toggled)
            self.dr_fg_light_btn = QPushButton(tab)
            self.dr_fg_light_btn.clicked.connect(lambda: self._prompt_dieroll_color("fg", "light"))
            self.dr_fg_dark_btn = QPushButton(tab)
            self.dr_fg_dark_btn.clicked.connect(lambda: self._prompt_dieroll_color("fg", "dark"))
            self.dr_light_sample_label = QLabel("Sample (light mode)", tab)
            color_grid.addWidget(self.dr_fg_check, 1, 0)
            color_grid.addWidget(self.dr_fg_light_btn, 1, 1)
            color_grid.addWidget(self.dr_fg_dark_btn, 1, 2)
            color_grid.addWidget(self.dr_light_sample_label, 1, 3)

            self.dr_bg_check = QCheckBox("Background color:", tab)
            self.dr_bg_check.toggled.connect(self._on_dr_bg_toggled)
            self.dr_bg_light_btn = QPushButton(tab)
            self.dr_bg_light_btn.clicked.connect(lambda: self._prompt_dieroll_color("bg", "light"))
            self.dr_bg_dark_btn = QPushButton(tab)
            self.dr_bg_dark_btn.clicked.connect(lambda: self._prompt_dieroll_color("bg", "dark"))
            self.dr_dark_sample_label = QLabel("Sample (dark mode)", tab)
            color_grid.addWidget(self.dr_bg_check, 2, 0)
            color_grid.addWidget(self.dr_bg_light_btn, 2, 1)
            color_grid.addWidget(self.dr_bg_dark_btn, 2, 2)
            color_grid.addWidget(self.dr_dark_sample_label, 2, 3)
            right_col.addLayout(color_grid)

            form = QFormLayout()
            self.dr_font_combo = QComboBox(tab)
            self.dr_font_combo.addItems(list(self.prefs.get("fonts", {}).keys()))
            self.dr_font_combo.currentTextChanged.connect(self._on_dr_font_changed)
            form.addRow("Font:", self.dr_font_combo)

            fmt_row = QHBoxLayout()
            self.dr_format_edit = QLineEdit(tab)
            self.dr_format_edit.textChanged.connect(self._on_dr_format_changed)
            fmt_row.addWidget(self.dr_format_edit)
            fmt_row.addWidget(QLabel("(_=leading/trailing space; blank for default format)", tab))
            form.addRow("Display Format:", fmt_row)
            right_col.addLayout(form)

            self.dr_overstrike_check = QCheckBox("Overstrike", tab)
            self.dr_overstrike_check.toggled.connect(self._on_dr_overstrike_toggled)
            right_col.addWidget(self.dr_overstrike_check)

            self.dr_underline_check = QCheckBox("Underline", tab)
            self.dr_underline_check.toggled.connect(self._on_dr_underline_toggled)
            right_col.addWidget(self.dr_underline_check)

            off_row = QHBoxLayout()
            off_row.addWidget(QLabel("Raise (Lower) text by:", tab))
            self.dr_offset_spin = QSpinBox(tab)
            self.dr_offset_spin.setRange(-100, 100)
            self.dr_offset_spin.valueChanged.connect(self._on_dr_offset_changed)
            off_row.addWidget(self.dr_offset_spin)
            off_row.addStretch(1)
            right_col.addLayout(off_row)

            self.dr_reset_btn = QPushButton("Reset to Default Values", tab)
            self.dr_reset_btn.clicked.connect(self.reset_selected_dieroll_style)
            right_col.addWidget(self.dr_reset_btn)
            right_col.addStretch(1)

            top_split.addLayout(right_col, 2)
            vbox.addLayout(top_split, 1)

            self.compact_recents_check = QCheckBox("Use less compact layout for die roll presets", tab)
            self.compact_recents_check.setChecked(
                bool(self.prefs.get("styles", {}).get("dierolls", {}).get("compact_recents", False))
            )
            self.compact_recents_check.toggled.connect(
                lambda checked: self.prefs.setdefault("styles", {}).setdefault("dierolls", {}).__setitem__(
                    "compact_recents", bool(checked)
                )
            )
            vbox.addWidget(self.compact_recents_check)

            self._on_dieroll_style_selected("")
            self.styles_tabs.addTab(tab, "Die Rolls/Chat")

        def selected_dieroll_style_name(self) -> str:
            item = self.dieroll_styles_list.currentItem()
            return item.text() if item is not None else ""

        def _on_dieroll_style_selected(self, sname: str) -> None:
            self._updating_dieroll_ui = True
            try:
                comps = self.prefs.get("styles", {}).get("dierolls", {}).get("components", {})
                if not sname or sname not in comps:
                    self.dr_desc_text.setPlainText("")
                    self.dr_fg_check.setChecked(False)
                    self.dr_fg_light_btn.setEnabled(False)
                    self.dr_fg_dark_btn.setEnabled(False)
                    self._style_color_button(self.dr_fg_light_btn, "")
                    self._style_color_button(self.dr_fg_dark_btn, "")
                    self.dr_bg_check.setChecked(False)
                    self.dr_bg_light_btn.setEnabled(False)
                    self.dr_bg_dark_btn.setEnabled(False)
                    self._style_color_button(self.dr_bg_light_btn, "")
                    self._style_color_button(self.dr_bg_dark_btn, "")
                    self.dr_format_edit.setText("")
                    self.dr_overstrike_check.setChecked(False)
                    self.dr_underline_check.setChecked(False)
                    self.dr_offset_spin.setValue(0)
                    return

                self.dr_desc_text.setPlainText(STYLE_DESCRIPTIONS.get(sname, ""))
                comp = comps[sname]
                fg_l = str(comp.get("fg", {}).get("light", "") or "")
                fg_d = str(comp.get("fg", {}).get("dark", "") or "")
                bg_l = str(comp.get("bg", {}).get("light", "") or "")
                bg_d = str(comp.get("bg", {}).get("dark", "") or "")

                fg_en = bool(fg_l or fg_d)
                self.dr_fg_check.setChecked(fg_en)
                self.dr_fg_light_btn.setEnabled(fg_en)
                self.dr_fg_dark_btn.setEnabled(fg_en)
                self._style_color_button(self.dr_fg_light_btn, fg_l if fg_en else "")
                self._style_color_button(self.dr_fg_dark_btn, fg_d if fg_en else "")

                bg_en = bool(bg_l or bg_d)
                self.dr_bg_check.setChecked(bg_en)
                self.dr_bg_light_btn.setEnabled(bg_en)
                self.dr_bg_dark_btn.setEnabled(bg_en)
                self._style_color_button(self.dr_bg_light_btn, bg_l if bg_en else "")
                self._style_color_button(self.dr_bg_dark_btn, bg_d if bg_en else "")

                font_name = str(comp.get("font", "Normal") or "Normal")
                if self.dr_font_combo.findText(font_name) >= 0:
                    self.dr_font_combo.setCurrentText(font_name)
                self.dr_format_edit.setText(_spaces_to_under(str(comp.get("format", "") or "")))
                self.dr_overstrike_check.setChecked(bool(comp.get("overstrike", False)))
                self.dr_underline_check.setChecked(bool(comp.get("underline", False)))
                self.dr_offset_spin.setValue(int(comp.get("offset", 0) or 0))
            finally:
                self._updating_dieroll_ui = False
            self._refresh_dieroller_examples()

        def _refresh_dieroller_examples(self) -> None:
            if not hasattr(self, "dieroll_styles_list"):
                return
            sname = self.selected_dieroll_style_name()
            comps = self.prefs.get("styles", {}).get("dierolls", {}).get("components", {})
            if not sname or sname not in comps:
                return
            comp = comps[sname]
            fmt = str(comp.get("format", "") or "")
            sample_val = _attempt_format(fmt, "value")
            fg_l = str(comp.get("fg", {}).get("light", "") or "#000000")
            fg_d = str(comp.get("fg", {}).get("dark", "") or "#aaaaaa")
            bg_l = str(comp.get("bg", {}).get("light", "") or "#cccccc")
            bg_d = str(comp.get("bg", {}).get("dark", "") or "#232323")
            self.dr_light_sample_label.setText(f"Sample (light mode): {sample_val}")
            self.dr_light_sample_label.setStyleSheet(f"color: {fg_l}; background-color: {bg_l};")
            self.dr_dark_sample_label.setText(f"Sample (dark mode): {sample_val}")
            self.dr_dark_sample_label.setStyleSheet(f"color: {fg_d}; background-color: {bg_d};")

        def _on_dr_fg_toggled(self, enabled: bool) -> None:
            if self._updating_dieroll_ui:
                return
            sname = self.selected_dieroll_style_name()
            if not sname:
                return
            comp = self.prefs["styles"]["dierolls"]["components"][sname]
            defs = default_styles()["dierolls"]["components"].get(sname, {}).get("fg", {})
            if enabled:
                lt = str(defs.get("light") or default_color("fg", "light"))
                dk = str(defs.get("dark") or default_color("fg", "dark"))
                comp["fg"] = {"light": lt, "dark": dk}
            else:
                comp["fg"] = {"light": "", "dark": ""}
            self._on_dieroll_style_selected(sname)

        def _on_dr_bg_toggled(self, enabled: bool) -> None:
            if self._updating_dieroll_ui:
                return
            sname = self.selected_dieroll_style_name()
            if not sname:
                return
            comp = self.prefs["styles"]["dierolls"]["components"][sname]
            defs = default_styles()["dierolls"]["components"].get(sname, {}).get("bg", {})
            if enabled:
                lt = str(defs.get("light") or default_color("bg", "light"))
                dk = str(defs.get("dark") or default_color("bg", "dark"))
                comp["bg"] = {"light": lt, "dark": dk}
            else:
                comp["bg"] = {"light": "", "dark": ""}
            self._on_dieroll_style_selected(sname)

        def set_dieroll_style_color(self, key: str, theme: str, color: str) -> None:
            sname = self.selected_dieroll_style_name()
            if not sname:
                return
            comp = self.prefs["styles"]["dierolls"]["components"][sname]
            comp.setdefault(key, {})[theme] = color
            self._on_dieroll_style_selected(sname)

        def _prompt_dieroll_color(self, key: str, theme: str) -> None:
            sname = self.selected_dieroll_style_name()
            if not sname:
                return
            cur = str(
                self.prefs["styles"]["dierolls"]["components"][sname].get(key, {}).get(theme, "") or "black"
            )
            col = QColorDialog.getColor(QColor(cur), self, f"Choose color for {sname} ({theme} mode)")
            if col.isValid():
                self.set_dieroll_style_color(key, theme, col.name())

        def _on_dr_font_changed(self, font_name: str) -> None:
            if self._updating_dieroll_ui or not font_name:
                return
            sname = self.selected_dieroll_style_name()
            if sname:
                self.prefs["styles"]["dierolls"]["components"][sname]["font"] = font_name
                self._refresh_dieroller_examples()

        def _on_dr_format_changed(self, text: str) -> None:
            if self._updating_dieroll_ui:
                return
            sname = self.selected_dieroll_style_name()
            if sname:
                self.prefs["styles"]["dierolls"]["components"][sname]["format"] = _under_to_spaces(text)
                self._refresh_dieroller_examples()

        def _on_dr_overstrike_toggled(self, checked: bool) -> None:
            if self._updating_dieroll_ui:
                return
            sname = self.selected_dieroll_style_name()
            if sname:
                self.prefs["styles"]["dierolls"]["components"][sname]["overstrike"] = bool(checked)
                self._refresh_dieroller_examples()

        def _on_dr_underline_toggled(self, checked: bool) -> None:
            if self._updating_dieroll_ui:
                return
            sname = self.selected_dieroll_style_name()
            if sname:
                self.prefs["styles"]["dierolls"]["components"][sname]["underline"] = bool(checked)
                self._refresh_dieroller_examples()

        def _on_dr_offset_changed(self, val: int) -> None:
            if self._updating_dieroll_ui:
                return
            sname = self.selected_dieroll_style_name()
            if sname:
                self.prefs["styles"]["dierolls"]["components"][sname]["offset"] = int(val)
                self._refresh_dieroller_examples()

        def reset_selected_dieroll_style(self) -> None:
            sname = self.selected_dieroll_style_name()
            if not sname:
                return
            defs = default_styles()["dierolls"]["components"].get(sname)
            if defs is not None:
                self.prefs["styles"]["dierolls"]["components"][sname] = copy.deepcopy(defs)
                self._on_dieroll_style_selected(sname)

        # ------------------------------------------------------------------
        # Styles Sub-Tab 4: Symbols ($st.ch)
        # ------------------------------------------------------------------
        def _build_styles_symbols_tab(self) -> None:
            tab = QWidget(self.styles_tabs)
            grid = QGridLayout(tab)
            chars = self.prefs.setdefault("styles", {}).setdefault("characters", {})

            for row, (key, title, choices) in enumerate(SYMBOL_FIELDS):
                grid.addWidget(QLabel(title, tab), row, 0)
                combo = QComboBox(tab)
                combo.addItems(choices)
                cur = str(chars.get(key, {}).get("name", choices[0]) or choices[0])
                if cur in choices:
                    combo.setCurrentText(cur)
                preview = QLabel(symbol_code_string(combo.currentText()), tab)
                combo.currentTextChanged.connect(
                    lambda val, k=key, lbl=preview: self._on_symbol_changed(k, val, lbl)
                )
                self.symbol_combos[key] = combo
                self.symbol_preview_labels[key] = preview
                grid.addWidget(combo, row, 1)
                grid.addWidget(preview, row, 2)

            grid.setRowStretch(len(SYMBOL_FIELDS), 1)
            self.styles_tabs.addTab(tab, "Symbols")

        def _on_symbol_changed(self, key: str, val: str, preview: QLabel) -> None:
            self.prefs.setdefault("styles", {}).setdefault("characters", {}).setdefault(key, {})["name"] = val
            preview.setText(symbol_code_string(val))

        # ------------------------------------------------------------------
        # Styles Sub-Tab 5: Colors ($st.c)
        # ------------------------------------------------------------------
        def _build_styles_colors_tab(self) -> None:
            tab = QWidget(self.styles_tabs)
            vbox = QVBoxLayout(tab)
            grid = QGridLayout()
            grid.addWidget(QLabel("Light Mode", tab), 0, 1)
            grid.addWidget(QLabel("Dark Mode", tab), 0, 2)

            dialogs = self.prefs.setdefault("styles", {}).setdefault("dialogs", {})
            for row, (fld, label) in enumerate(GRID_COLOR_FIELDS, start=1):
                grid.addWidget(QLabel(f"{label}:", tab), row, 0)
                for col, theme in enumerate(("light", "dark"), start=1):
                    color = str(dialogs.get(fld, {}).get(theme, "") or "")
                    btn = QPushButton(tab)
                    self._style_color_button(btn, color)
                    btn.clicked.connect(
                        lambda _c=False, f=fld, t=theme, lbl=label: self._prompt_dialog_color(f, t, lbl)
                    )
                    self.grid_color_btns[(fld, theme)] = btn
                    self.dialog_color_btns[(fld, theme)] = btn
                    grid.addWidget(btn, row, col)
                reset_btn = QPushButton("Reset to Default", tab)
                reset_btn.clicked.connect(lambda _c=False, f=fld: self.reset_dialog_color(f))
                self.grid_reset_btns[fld] = reset_btn
                self.dialog_reset_btns[fld] = reset_btn
                grid.addWidget(reset_btn, row, 3)

            vbox.addLayout(grid)
            vbox.addStretch(1)
            self.styles_tabs.addTab(tab, "Colors")

        # ------------------------------------------------------------------
        # Styles Sub-Tab 6: Clocks ($st.cl)
        # ------------------------------------------------------------------
        def _build_styles_clocks_tab(self) -> None:
            tab = QWidget(self.styles_tabs)
            vbox = QVBoxLayout(tab)
            grid = QGridLayout()
            grid.addWidget(QLabel("Light Mode", tab), 0, 1)
            grid.addWidget(QLabel("Dark Mode", tab), 0, 2)

            clocks = self.prefs.setdefault("styles", {}).setdefault("clocks", {})
            for row, (fld, label) in enumerate(CLOCK_COLOR_FIELDS, start=1):
                grid.addWidget(QLabel(f"{label}:", tab), row, 0)
                for col, theme in enumerate(("light", "dark"), start=1):
                    color = str(clocks.get(fld, {}).get(theme, "") or "")
                    btn = QPushButton(tab)
                    self._style_color_button(btn, color)
                    btn.clicked.connect(
                        lambda _c=False, f=fld, t=theme, lbl=label: self._prompt_clock_color(f, t, lbl)
                    )
                    self.clock_color_btns[(fld, theme)] = btn
                    grid.addWidget(btn, row, col)
                reset_btn = QPushButton("Reset to Default", tab)
                reset_btn.clicked.connect(lambda _c=False, f=fld: self.reset_clock_color(f))
                self.clock_reset_btns[fld] = reset_btn
                grid.addWidget(reset_btn, row, 3)

            vbox.addLayout(grid)

            font_form = QFormLayout()
            font_names = list(self.prefs.get("fonts", {}).keys())
            for fld, label in CLOCK_FONT_FIELDS:
                combo = QComboBox(tab)
                combo.addItems(font_names)
                cur = str(clocks.get(fld, "") or "")
                if cur in font_names:
                    combo.setCurrentText(cur)
                combo.currentTextChanged.connect(
                    lambda val, f=fld: self.prefs.setdefault("styles", {})
                    .setdefault("clocks", {})
                    .__setitem__(f, val)
                )
                self.clock_font_combos[fld] = combo
                font_form.addRow(f"{label}:", combo)

            vbox.addLayout(font_form)
            vbox.addStretch(1)
            self.styles_tabs.addTab(tab, "Clocks")

        def set_clock_color(self, fld: str, theme: str, color: str) -> None:
            clocks = self.prefs.setdefault("styles", {}).setdefault("clocks", {})
            clocks.setdefault(fld, {})[theme] = color
            btn = self.clock_color_btns.get((fld, theme))
            if btn is not None:
                self._style_color_button(btn, color)

        def reset_clock_color(self, fld: str) -> None:
            defs = default_styles()["clocks"].get(fld, {})
            for theme in ("light", "dark"):
                if theme in defs:
                    self.set_clock_color(fld, theme, str(defs[theme]))

        def _prompt_clock_color(self, fld: str, theme: str, label: str) -> None:
            cur = str(self.prefs.get("styles", {}).get("clocks", {}).get(fld, {}).get(theme, "") or "black")
            col = QColorDialog.getColor(QColor(cur), self, f"Choose color for {label} ({theme} mode)")
            if col.isValid():
                self.set_clock_color(fld, theme, col.name())

        # ------------------------------------------------------------------
        # Styles Sub-Tab 7: Markers ($st.m)
        # ------------------------------------------------------------------
        def _build_styles_markers_tab(self) -> None:
            tab = QWidget(self.styles_tabs)
            vbox = QVBoxLayout(tab)
            vbox.addWidget(
                QLabel(
                    "Define custom markers you can place on creatures to denote things like studied or smite evil targets, etc.",
                    tab,
                )
            )

            top_row = QHBoxLayout()
            self.markers_list = QListWidget(tab)
            for mname in self.prefs.get("styles", {}).get("markers", {}):
                self.markers_list.addItem(str(mname))
            self.markers_list.currentTextChanged.connect(self._on_marker_selected)
            top_row.addWidget(self.markers_list, 1)

            btn_col = QVBoxLayout()
            self.marker_add_btn = QPushButton("Add New...", tab)
            self.marker_add_btn.clicked.connect(self._on_add_marker_clicked)
            self.marker_copy_btn = QPushButton("Copy", tab)
            self.marker_copy_btn.setEnabled(False)
            self.marker_copy_btn.clicked.connect(self._on_copy_marker_clicked)
            self.marker_del_btn = QPushButton("Delete", tab)
            self.marker_del_btn.setEnabled(False)
            self.marker_del_btn.clicked.connect(self._on_delete_marker_clicked)
            btn_col.addWidget(self.marker_add_btn)
            btn_col.addWidget(self.marker_copy_btn)
            btn_col.addStretch(1)
            btn_col.addWidget(self.marker_del_btn)
            top_row.addLayout(btn_col)
            vbox.addLayout(top_row, 1)

            form = QFormLayout()
            self.marker_mods_edit = QLineEdit(tab)
            self.marker_mods_edit.textChanged.connect(self._on_marker_mods_changed)
            form.addRow("Modifiers:", self.marker_mods_edit)

            self.marker_desc_edit = QLineEdit(tab)
            self.marker_desc_edit.textChanged.connect(self._on_marker_desc_changed)
            form.addRow("Description:", self.marker_desc_edit)

            self.marker_shape_combo = QComboBox(tab)
            for sym, label in MARKER_SHAPES.items():
                self.marker_shape_combo.addItem(f"{label} ({sym})", sym)
            self.marker_shape_combo.currentIndexChanged.connect(self._on_marker_shape_changed)
            form.addRow("Marker shape:", self.marker_shape_combo)

            dash_color_row = QHBoxLayout()
            self.marker_dash_combo = QComboBox(tab)
            for dpat in ("", "--", ".."):
                self.marker_dash_combo.addItem(dpat or "(solid)", dpat)
            self.marker_dash_combo.currentIndexChanged.connect(self._on_marker_dash_changed)
            self.marker_color_btn = QPushButton(tab)
            self.marker_color_btn.clicked.connect(self._prompt_marker_color)
            dash_color_row.addWidget(self.marker_dash_combo)
            dash_color_row.addWidget(self.marker_color_btn, 1)
            form.addRow("Dash pattern and color:", dash_color_row)
            vbox.addLayout(form)

            self.marker_tracer_check = QCheckBox("Draw tracer line", tab)
            self.marker_tracer_check.toggled.connect(self._on_marker_tracer_toggled)
            vbox.addWidget(self.marker_tracer_check)

            self.marker_endatdeath_check = QCheckBox("Condition ends at target's death", tab)
            self.marker_endatdeath_check.toggled.connect(self._on_marker_endatdeath_toggled)
            vbox.addWidget(self.marker_endatdeath_check)

            limit_row = QHBoxLayout()
            limit_row.addWidget(QLabel("Maximum number at once:", tab))
            self.marker_limit_spin = QSpinBox(tab)
            self.marker_limit_spin.setRange(0, 25)
            self.marker_limit_spin.valueChanged.connect(self._on_marker_limit_changed)
            limit_row.addWidget(self.marker_limit_spin)
            limit_row.addStretch(1)
            vbox.addLayout(limit_row)

            self._on_marker_selected("")
            self.styles_tabs.addTab(tab, "Markers")

        def selected_marker_name(self) -> str:
            item = self.markers_list.currentItem()
            return item.text() if item is not None else ""

        def _on_marker_selected(self, name: str) -> None:
            self._updating_marker_ui = True
            try:
                markers = self.prefs.get("styles", {}).get("markers", {})
                enabled = bool(name and name in markers)
                self.marker_copy_btn.setEnabled(enabled)
                self.marker_copy_btn.setText(f"Copy {name}" if enabled else "Copy")
                self.marker_del_btn.setEnabled(enabled)
                self.marker_del_btn.setText(f"Delete {name}" if enabled else "Delete")
                for w in (
                    self.marker_mods_edit,
                    self.marker_desc_edit,
                    self.marker_shape_combo,
                    self.marker_dash_combo,
                    self.marker_color_btn,
                    self.marker_tracer_check,
                    self.marker_endatdeath_check,
                    self.marker_limit_spin,
                ):
                    w.setEnabled(enabled)

                if not enabled:
                    self.marker_mods_edit.setText("")
                    self.marker_desc_edit.setText("")
                    self.marker_shape_combo.setCurrentIndex(max(0, self.marker_shape_combo.findData("O")))
                    self.marker_dash_combo.setCurrentIndex(max(0, self.marker_dash_combo.findData("")))
                    self._style_color_button(self.marker_color_btn, "black")
                    self.marker_tracer_check.setChecked(False)
                    self.marker_endatdeath_check.setChecked(False)
                    self.marker_limit_spin.setValue(0)
                    return

                mdata = markers[name]
                mods = mdata.get("modifiers", [])
                self.marker_mods_edit.setText(",".join(str(x) for x in mods) if isinstance(mods, list) else str(mods))
                self.marker_desc_edit.setText(str(mdata.get("description", "") or ""))
                shape = str(mdata.get("shape", "O") or "O")
                s_idx = self.marker_shape_combo.findData(shape)
                self.marker_shape_combo.setCurrentIndex(s_idx if s_idx >= 0 else 0)
                dash = str(mdata.get("dashpattern", "") or "")
                d_idx = self.marker_dash_combo.findData(dash)
                self.marker_dash_combo.setCurrentIndex(d_idx if d_idx >= 0 else 0)
                self._style_color_button(self.marker_color_btn, str(mdata.get("color", "black") or "black"))
                self.marker_tracer_check.setChecked(bool(mdata.get("tracer", False)))
                self.marker_endatdeath_check.setChecked(bool(mdata.get("endatdeath", False)))
                self.marker_limit_spin.setValue(int(mdata.get("limit", 0) or 0))
            finally:
                self._updating_marker_ui = False

        def add_marker(self, name: str, marker_dict: dict[str, Any] | None = None) -> bool:
            name = name.strip()
            markers = self.prefs.setdefault("styles", {}).setdefault("markers", {})
            if not name or name in markers:
                return False
            markers[name] = (
                copy.deepcopy(marker_dict)
                if marker_dict is not None
                else {
                    "modifiers": [],
                    "color": "black",
                    "shape": "O",
                    "dashpattern": "",
                    "description": "",
                    "tracer": False,
                    "endatdeath": False,
                    "limit": 0,
                }
            )
            self.markers_list.addItem(name)
            self.markers_list.setCurrentRow(self.markers_list.count() - 1)
            return True

        def copy_selected_marker(self, new_name: str) -> bool:
            src = self.selected_marker_name()
            markers = self.prefs.get("styles", {}).get("markers", {})
            if not src or src not in markers:
                return False
            return self.add_marker(new_name, markers[src])

        def delete_selected_marker(self) -> bool:
            src = self.selected_marker_name()
            markers = self.prefs.get("styles", {}).get("markers", {})
            if not src or src not in markers:
                return False
            row = self.markers_list.currentRow()
            if row >= 0:
                self.markers_list.takeItem(row)
            del markers[src]
            self.markers_list.clearSelection()
            self._on_marker_selected("")
            return True

        def set_selected_marker_color(self, color: str) -> None:
            src = self.selected_marker_name()
            markers = self.prefs.get("styles", {}).get("markers", {})
            if src and src in markers:
                markers[src]["color"] = color
                self._style_color_button(self.marker_color_btn, color)

        def _on_add_marker_clicked(self) -> None:
            name, ok = QInputDialog.getText(self, "Name of new marker", "Name of new marker:")
            if ok and name.strip():
                if not self.add_marker(name.strip()):
                    QMessageBox.critical(
                        self,
                        "Duplicate name",
                        f'You tried to add a marker called "{name.strip()}" but that name already exists in the marker set.',
                    )

        def _on_copy_marker_clicked(self) -> None:
            src = self.selected_marker_name()
            if not src:
                return
            name, ok = QInputDialog.getText(
                self, f"Name of new marker (copy of {src})", f"Name of new marker (copy of {src}):"
            )
            if ok and name.strip():
                if not self.copy_selected_marker(name.strip()):
                    QMessageBox.critical(
                        self,
                        "Duplicate name",
                        f'You tried to add a marker called "{name.strip()}" but that name already exists in the marker set.',
                    )

        def _on_delete_marker_clicked(self) -> None:
            self.delete_selected_marker()

        def _on_marker_mods_changed(self, text: str) -> None:
            if self._updating_marker_ui:
                return
            src = self.selected_marker_name()
            if src:
                self.prefs["styles"]["markers"][src]["modifiers"] = [x for x in text.split(",") if x] if text else []

        def _on_marker_desc_changed(self, text: str) -> None:
            if self._updating_marker_ui:
                return
            src = self.selected_marker_name()
            if src:
                self.prefs["styles"]["markers"][src]["description"] = text

        def _on_marker_shape_changed(self, _idx: int) -> None:
            if self._updating_marker_ui:
                return
            src = self.selected_marker_name()
            if src:
                self.prefs["styles"]["markers"][src]["shape"] = str(self.marker_shape_combo.currentData() or "O")

        def _on_marker_dash_changed(self, _idx: int) -> None:
            if self._updating_marker_ui:
                return
            src = self.selected_marker_name()
            if src:
                self.prefs["styles"]["markers"][src]["dashpattern"] = str(self.marker_dash_combo.currentData() or "")

        def _prompt_marker_color(self) -> None:
            src = self.selected_marker_name()
            if not src:
                return
            cur = str(self.prefs["styles"]["markers"][src].get("color", "black") or "black")
            col = QColorDialog.getColor(QColor(cur), self, "Choose color for custom marker")
            if col.isValid():
                self.set_selected_marker_color(col.name())

        def _on_marker_tracer_toggled(self, checked: bool) -> None:
            if self._updating_marker_ui:
                return
            src = self.selected_marker_name()
            if src:
                self.prefs["styles"]["markers"][src]["tracer"] = bool(checked)

        def _on_marker_endatdeath_toggled(self, checked: bool) -> None:
            if self._updating_marker_ui:
                return
            src = self.selected_marker_name()
            if src:
                self.prefs["styles"]["markers"][src]["endatdeath"] = bool(checked)

        def _on_marker_limit_changed(self, val: int) -> None:
            if self._updating_marker_ui:
                return
            src = self.selected_marker_name()
            if src:
                self.prefs["styles"]["markers"][src]["limit"] = int(val)

        def _build_tools_tab(self) -> None:
            """Build the Tools tab (`$w.n.t` in `bin/gmaprofile.tcl` lines 1359-1362)."""
            tab = QWidget(self.tabs)
            tab_layout = QVBoxLayout(tab)

            tools_group = QGroupBox("PATHS TO SUPPORT PROGRAMS", tab)
            tools_layout = QVBoxLayout(tools_group)

            curl_row = QHBoxLayout()
            curl_row.addWidget(QLabel("Curl program path:", tools_group))
            self.curl_path_edit = QLineEdit(tools_group)
            self.curl_path_edit.setText(str(self.prefs.get("curl_path", "") or ""))
            curl_row.addWidget(self.curl_path_edit, 1)
            tools_layout.addLayout(curl_row)

            self.curl_insecure_check = QCheckBox("Run Curl in insecure mode", tools_group)
            self.curl_insecure_check.setChecked(bool(self.prefs.get("curl_insecure", False)))
            tools_layout.addWidget(self.curl_insecure_check)

            tab_layout.addWidget(tools_group)
            tab_layout.addStretch(1)
            self.tabs.addTab(tab, "Tools")

        def _build_diagnostics_tab(self) -> None:
            """Build the Diagnostics tab (`$w.n.d` in `bin/gmaprofile.tcl` lines 1364-1367)."""
            tab = QWidget(self.tabs)
            tab_layout = QVBoxLayout(tab)

            diag_group = QGroupBox("DIAGNOSTIC/DEBUGGING OPTIONS", tab)
            diag_layout = QVBoxLayout(diag_group)

            level_row = QHBoxLayout()
            level_row.addWidget(QLabel("Debugging level:", diag_group))
            self.debug_level_spin = QSpinBox(diag_group)
            self.debug_level_spin.setRange(0, 6)
            self.debug_level_spin.setValue(int(self.prefs.get("debug_level", 0) or 0))
            level_row.addWidget(self.debug_level_spin)
            level_row.addStretch(1)
            diag_layout.addLayout(level_row)

            self.debug_proto_check = QCheckBox(
                "Debug client/server protocol messages", diag_group
            )
            self.debug_proto_check.setChecked(bool(self.prefs.get("debug_proto", False)))
            diag_layout.addWidget(self.debug_proto_check)

            tab_layout.addWidget(diag_group)
            tab_layout.addStretch(1)
            self.tabs.addTab(tab, "Diagnostics")

        def _build_accessibility_tab(self) -> None:
            """Build the Accessibility tab (`$w.n.a11y` in `bin/gmaprofile.tcl` line 1305)."""
            tab = QWidget(self.tabs)
            tab_layout = QVBoxLayout(tab)

            self.colorize_die_labels_check = QCheckBox(
                "Enable colors in die-roll modifier labels", tab
            )
            self.colorize_die_labels_check.setChecked(
                bool(self.prefs.get("a11y", {}).get("colorize_die_labels", True))
            )
            tab_layout.addWidget(self.colorize_die_labels_check)
            tab_layout.addStretch(1)
            self.tabs.addTab(tab, "Accessibility")

        def _on_server_index_changed(self, idx: int) -> None:
            if self._editing_idx >= 0:
                self._save_server_at(self._editing_idx)
            self._load_selected_server(idx)

        def _load_selected_server(self, idx: int) -> None:
            servers = self.prefs.get("profiles", [])
            if 0 <= idx < len(servers):
                self._editing_idx = idx
                srv = servers[idx]
                self.prefs["current_profile"] = str(srv.get("name", "offline"))
                self.host_edit.setText(str(srv.get("host", "")))
                self.port_spin.setValue(int(srv.get("port", 2323) or 2323))
                self.user_edit.setText(str(srv.get("username", srv.get("user", ""))))
                self.pass_edit.setText(str(srv.get("password", srv.get("pass", ""))))
                self.curl_edit.setText(str(srv.get("curl_server", srv.get("curl_url_base", ""))))
                self.scp_server_edit.setText(str(srv.get("scp_server", "")))
                self.scp_dest_edit.setText(str(srv.get("scp_dest", "")))

        def _save_server_at(self, idx: int) -> None:
            servers = self.prefs.get("profiles", [])
            if 0 <= idx < len(servers):
                srv = servers[idx]
                srv["host"] = self.host_edit.text().strip()
                srv["port"] = self.port_spin.value()
                srv["username"] = self.user_edit.text().strip()
                srv["password"] = self.pass_edit.text()
                srv["curl_server"] = self.curl_edit.text().strip()
                srv["scp_server"] = self.scp_server_edit.text().strip()
                srv["scp_dest"] = self.scp_dest_edit.text().strip()

        def _save_current_server(self) -> None:
            idx = self.server_combo.currentIndex()
            self._save_server_at(idx)
            servers = self.prefs.get("profiles", [])
            if 0 <= idx < len(servers):
                self.prefs["current_profile"] = str(servers[idx].get("name", "offline"))

        def _on_new_server(self) -> None:
            self._save_current_server()
            name = f"profile-{len(self.prefs.get('profiles', [])) + 1}"
            srv = empty_server_profile(name)
            self.prefs.setdefault("profiles", []).append(srv)
            self.server_combo.addItem(name)
            self.server_combo.setCurrentIndex(self.server_combo.count() - 1)

        def _on_accept(self) -> None:
            self._save_current_server()
            self.prefs["animate"] = self.animate_check.isChecked()
            self.prefs["flash_updates"] = self.flash_updates_check.isChecked()
            self.prefs["chat_timestamp"] = self.chat_timestamp_check.isChecked()
            self.prefs["colorize_die_rolls"] = self.colorize_die_rolls_check.isChecked()
            self.prefs["markup_enabled"] = self.markup_enabled_check.isChecked()
            self.prefs["dark"] = self.dark_check.isChecked()
            self.prefs["scaling"] = round(float(self.scaling_spin.value()), 1)
            self.prefs["menu_button"] = self.menu_button_check.isChecked()
            self.prefs["never_animate"] = self.never_animate_check.isChecked()
            self.prefs["keep_tools"] = self.keep_tools_check.isChecked()
            self.prefs["show_timers"] = str(self.show_timers_combo.currentData() or "mine")
            self.prefs["preload"] = self.preload_check.isChecked()
            self.prefs["image_format"] = str(self.image_format_combo.currentData() or "png")
            self.prefs["button_size"] = str(self.button_size_combo.currentData() or "small")
            self.prefs["toolbar_text"] = not self.toolbar_icons_check.isChecked()
            self.prefs["guide_lines"] = {
                "major": {
                    "interval": self.major_interval_spin.value(),
                    "offsets": {
                        "x": self.major_offset_x_spin.value(),
                        "y": self.major_offset_y_spin.value(),
                    },
                },
                "minor": {
                    "interval": self.minor_interval_spin.value(),
                    "offsets": {
                        "x": self.minor_offset_x_spin.value(),
                        "y": self.minor_offset_y_spin.value(),
                    },
                },
            }
            self.prefs["no_dice"] = self.no_dice_check.isChecked()
            self.prefs["suppress_aka"] = self.suppress_aka_check.isChecked()
            self.prefs["not_playing"] = self.not_playing_check.isChecked()
            self.prefs["no_ondeck_audio"] = self.no_ondeck_audio_check.isChecked()
            self.prefs["no_sfx"] = self.no_sfx_check.isChecked()
            self.prefs["debug_level"] = int(self.debug_level_spin.value())
            self.prefs["debug_proto"] = self.debug_proto_check.isChecked()
            self.prefs["curl_path"] = self.curl_path_edit.text().strip()
            self.prefs["curl_insecure"] = self.curl_insecure_check.isChecked()
            self.prefs.setdefault("a11y", {})["colorize_die_labels"] = (
                self.colorize_die_labels_check.isChecked()
            )
            self.accept()

else:

    class PreferencesDialog:  # type: ignore[no-redef]
        def __init__(self, prefs: dict[str, Any], parent: Any = None) -> None:
            self.prefs = fix_missing(copy.deepcopy(prefs))

