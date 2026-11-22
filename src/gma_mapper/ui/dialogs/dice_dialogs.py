"""Dialogs for Die-Roll Preset Editing, Color-Box Titles, Lookup Tables, Delegation, and Syntax Help.

Ported from `bin/mapper_legacy.tcl` (`EditDieRollPresets`, `EditColorBoxTitle`,
`EditDRPGroup`, `EDRTtbl`, `EditDelegateList`, `ShowDiceSyntax`, `ShowDiceModifierHelp`).
"""

from __future__ import annotations

import copy
from typing import Any

from gma_mapper.core.colors import darken_color
from gma_mapper.core.dice import (
    DICE_MODIFIER_HELP_TEXT,
    DICE_SYNTAX_HELP_SECTIONS,
    DicePresetBank,
    build_color_box_title,
    cleanup_die_roll_spec,
    encode_preset_details,
    get_preset_details,
    parse_color_blocks,
)

try:
    from PySide6.QtCore import Qt
    from PySide6.QtGui import QColor
    from PySide6.QtWidgets import (
        QColorDialog,
        QComboBox,
        QDialog,
        QDialogButtonBox,
        QFormLayout,
        QHBoxLayout,
        QHeaderView,
        QLabel,
        QLineEdit,
        QListWidget,
        QMessageBox,
        QPushButton,
        QTableWidget,
        QTableWidgetItem,
        QTabWidget,
        QTextBrowser,
        QVBoxLayout,
        QWidget,
    )

    QT_AVAILABLE = True
except ImportError:  # pragma: no cover
    QT_AVAILABLE = False


def validate_and_sort_table_rows(
    rows: list[tuple[str, str]],
) -> list[tuple[str, str]]:
    """Validate and sort lookup-table `(bound, result_text)` rows by ascending integer upper bound.

    Ensures a final `("*", catch_all_text)` row exists and integer bounds are strictly increasing.
    Raises `ValueError` on duplicate or invalid integer bounds.
    """
    numeric_rows: list[tuple[int, str]] = []
    wildcard_text = ""
    has_wildcard = False

    for bound_raw, text_raw in rows:
        b_str = str(bound_raw or "").strip()
        t_str = str(text_raw or "")
        if not b_str and not t_str:
            continue
        if b_str == "*":
            wildcard_text = t_str
            has_wildcard = True
            continue
        try:
            b_int = int(b_str)
        except ValueError as exc:
            raise ValueError(f"Table bound {b_str!r} must be an integer or '*'.") from exc
        numeric_rows.append((b_int, t_str))

    numeric_rows.sort(key=lambda item: item[0])
    seen_bounds: set[int] = set()
    for b_int, _ in numeric_rows:
        if b_int in seen_bounds:
            raise ValueError(f"Duplicate table upper bound: {b_int}")
        seen_bounds.add(b_int)

    result: list[tuple[str, str]] = [(str(b), t) for b, t in numeric_rows]
    if not has_wildcard and not result:
        raise ValueError("Lookup table must contain at least one row.")
    result.append(("*", wildcard_text))
    return result


if QT_AVAILABLE:

    class DiceSyntaxHelpDialog(QDialog):
        """Non-modal syntax reference window ported from `ShowDiceSyntax` (`bin/mapper_legacy.tcl`)."""

        def __init__(self, parent: QWidget | None = None) -> None:
            super().__init__(parent)
            self.setWindowTitle("Die Roller Syntax Reference")
            self.resize(680, 520)

            layout = QVBoxLayout(self)
            self.tabs = QTabWidget(self)
            for tab_title, html_body in DICE_SYNTAX_HELP_SECTIONS:
                browser = QTextBrowser(self.tabs)
                browser.setOpenExternalLinks(False)
                browser.setHtml(html_body)
                self.tabs.addTab(browser, tab_title)
            layout.addWidget(self.tabs)

            btn_box = QDialogButtonBox(QDialogButtonBox.StandardButton.Close, self)
            btn_box.rejected.connect(self.close)
            btn_box.accepted.connect(self.close)
            layout.addWidget(btn_box)

    class DiceModifierHelpDialog(QDialog):
        """Modifier & variable reference dialog ported from `ShowDiceModifierHelp`."""

        def __init__(self, parent: QWidget | None = None) -> None:
            super().__init__(parent)
            self.setWindowTitle("Die Roll Modifiers & Variables Help")
            self.resize(560, 400)

            layout = QVBoxLayout(self)
            self.browser = QTextBrowser(self)
            self.browser.setHtml(DICE_MODIFIER_HELP_TEXT)
            layout.addWidget(self.browser)

            btn_box = QDialogButtonBox(QDialogButtonBox.StandardButton.Close, self)
            btn_box.rejected.connect(self.close)
            btn_box.accepted.connect(self.close)
            layout.addWidget(btn_box)

    class EditColorBoxTitleDialog(QDialog):
        """Multi-segment color-box title editor ported from `EditColorBoxTitle` (`bin/mapper_legacy.tcl`)."""

        def __init__(
            self,
            initial_spec_or_title: str = "",
            parent: QWidget | None = None,
        ) -> None:
            super().__init__(parent)
            self.setWindowTitle("Edit Color-Box Title")
            self.resize(560, 380)

            self._has_equals = "=" in initial_spec_or_title
            if self._has_equals:
                eq_idx = initial_spec_or_title.find("=")
                raw_title = initial_spec_or_title[:eq_idx]
                self._formula_suffix = initial_spec_or_title[eq_idx + 1 :]
            else:
                raw_title = initial_spec_or_title
                self._formula_suffix = ""

            parsed = parse_color_blocks(raw_title) if raw_title else [("", "", "")]
            self._rows_data: list[tuple[str, str, str]] = parsed or [("", "", "")]

            layout = QVBoxLayout(self)
            info_lbl = QLabel(
                "Define one or more colored label blocks for the roll title (separated by '‖'):",
                self,
            )
            layout.addWidget(info_lbl)

            self.table = QTableWidget(0, 3, self)
            self.table.setHorizontalHeaderLabels(["Label Text", "Text Color (fg)", "Box Color (bg)"])
            self.table.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.Stretch)
            self.table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.ResizeToContents)
            self.table.horizontalHeader().setSectionResizeMode(2, QHeaderView.ResizeMode.ResizeToContents)
            layout.addWidget(self.table, stretch=1)

            btn_row = QHBoxLayout()
            self.btn_add = QPushButton("+ Add Block", self)
            self.btn_remove = QPushButton("- Remove Block", self)
            self.btn_pick_fg = QPushButton("Pick Text Color...", self)
            self.btn_pick_bg = QPushButton("Pick Box Color...", self)
            self.btn_auto_bg = QPushButton("Auto 40% BG", self)
            btn_row.addWidget(self.btn_add)
            btn_row.addWidget(self.btn_remove)
            btn_row.addWidget(self.btn_pick_fg)
            btn_row.addWidget(self.btn_pick_bg)
            btn_row.addWidget(self.btn_auto_bg)
            btn_row.addStretch(1)
            layout.addLayout(btn_row)

            self.preview_browser = QTextBrowser(self)
            self.preview_browser.setMaximumHeight(54)
            layout.addWidget(self.preview_browser)

            buttons = QDialogButtonBox(
                QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel,
                self,
            )
            buttons.accepted.connect(self.accept)
            buttons.rejected.connect(self.reject)
            layout.addWidget(buttons)

            for lbl, fg, bg in self._rows_data:
                self._append_row(lbl, fg, bg)

            self.btn_add.clicked.connect(lambda: self._append_row("", "", ""))
            self.btn_remove.clicked.connect(self._remove_selected_row)
            self.btn_pick_fg.clicked.connect(lambda: self._pick_color_for_col(1))
            self.btn_pick_bg.clicked.connect(lambda: self._pick_color_for_col(2))
            self.btn_auto_bg.clicked.connect(self._apply_auto_bg)
            self.table.itemChanged.connect(lambda _item: self._update_preview())
            self._update_preview()

        def _append_row(self, label: str, fg: str, bg: str) -> None:
            r = self.table.rowCount()
            self.table.insertRow(r)
            self.table.setItem(r, 0, QTableWidgetItem(label))
            self.table.setItem(r, 1, QTableWidgetItem(fg))
            self.table.setItem(r, 2, QTableWidgetItem(bg))
            self._update_preview()

        def _remove_selected_row(self) -> None:
            r = self.table.currentRow()
            if r >= 0 and self.table.rowCount() > 1:
                self.table.removeRow(r)
                self._update_preview()

        def _pick_color_for_col(self, col_idx: int) -> None:
            r = max(0, self.table.currentRow())
            if r >= self.table.rowCount():
                return
            cur_item = self.table.item(r, col_idx)
            initial = QColor(cur_item.text() if cur_item and cur_item.text() else "#ffffff")
            chosen = QColorDialog.getColor(initial, self, "Choose Color")
            if chosen.isValid():
                self.table.setItem(r, col_idx, QTableWidgetItem(chosen.name()))
                if col_idx == 1:
                    bg_item = self.table.item(r, 2)
                    if not bg_item or not bg_item.text().strip():
                        self.table.setItem(
                            r, 2, QTableWidgetItem(darken_color(chosen.name(), 40))
                        )
                self._update_preview()

        def _apply_auto_bg(self) -> None:
            r = max(0, self.table.currentRow())
            if r >= self.table.rowCount():
                return
            fg_item = self.table.item(r, 1)
            if fg_item and fg_item.text().strip():
                try:
                    bg_hex = darken_color(fg_item.text().strip(), 40)
                    self.table.setItem(r, 2, QTableWidgetItem(bg_hex))
                except ValueError:
                    pass
            self._update_preview()

        def segments(self) -> list[tuple[str, str, str]]:
            out: list[tuple[str, str, str]] = []
            for r in range(self.table.rowCount()):
                lbl = self.table.item(r, 0).text() if self.table.item(r, 0) else ""
                fg = self.table.item(r, 1).text().strip() if self.table.item(r, 1) else ""
                bg = self.table.item(r, 2).text().strip() if self.table.item(r, 2) else ""
                if lbl or fg or bg:
                    out.append((lbl, fg, bg))
            return out

        def encoded_title(self) -> str:
            return build_color_box_title(self.segments())

        def updated_roll_spec(self, current_spec: str = "") -> str:
            title_str = self.encoded_title()
            target_spec = current_spec if current_spec else (
                f"{title_str}={self._formula_suffix}" if self._has_equals else ""
            )
            if "=" in target_spec:
                eq_idx = target_spec.find("=")
                rest = target_spec[eq_idx + 1 :]
                return f"{title_str}={rest}" if title_str else rest
            if target_spec:
                return f"{title_str}={target_spec}" if title_str else target_spec
            return f"{title_str}=" if title_str else ""

        def _update_preview(self) -> None:
            blocks = parse_color_blocks(self.encoded_title())
            spans: list[str] = []
            for lbl, fg, bg in blocks:
                if not lbl:
                    continue
                style_parts = ["padding:2px 6px", "border-radius:3px", "font-weight:bold"]
                if fg:
                    style_parts.append(f"color:{fg}")
                if bg:
                    style_parts.append(f"background-color:{bg}")
                spans.append(f'<span style="{";".join(style_parts)}">{lbl}</span>')
            self.preview_browser.setHtml("Preview: " + (" ".join(spans) if spans else "<i>(empty)</i>"))

    class EditPresetGroupDialog(QDialog):
        """Group hierarchy selector and editor ported from `EditDRPGroup` (`bin/mapper_legacy.tcl`)."""

        def __init__(
            self,
            current_groups: list[str] | tuple[str, ...] = (),
            known_group_paths: list[list[str]] | None = None,
            parent: QWidget | None = None,
        ) -> None:
            super().__init__(parent)
            self.setWindowTitle("Edit Preset Group Hierarchy")
            self.resize(440, 320)

            layout = QVBoxLayout(self)
            layout.addWidget(
                QLabel("Enter group hierarchy levels (separated by '▶' or one per line):", self)
            )

            self.combo_existing = QComboBox(self)
            self.combo_existing.addItem("(Choose existing group path...)", [])
            seen: set[str] = set()
            for path_list in known_group_paths or []:
                if not path_list:
                    continue
                joined = " \u25b6 ".join(path_list)
                if joined not in seen:
                    seen.add(joined)
                    self.combo_existing.addItem(joined, list(path_list))
            layout.addWidget(self.combo_existing)

            self.list_levels = QListWidget(self)
            for g in current_groups:
                if g:
                    self.list_levels.addItem(str(g))
            layout.addWidget(self.list_levels, stretch=1)

            row_btns = QHBoxLayout()
            self.edit_level = QLineEdit(self)
            self.edit_level.setPlaceholderText("Subgroup name...")
            self.btn_add = QPushButton("Add Level", self)
            self.btn_remove = QPushButton("Remove Selected", self)
            self.btn_clear = QPushButton("Ungrouped", self)
            row_btns.addWidget(self.edit_level, stretch=1)
            row_btns.addWidget(self.btn_add)
            row_btns.addWidget(self.btn_remove)
            row_btns.addWidget(self.btn_clear)
            layout.addLayout(row_btns)

            buttons = QDialogButtonBox(
                QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel,
                self,
            )
            buttons.accepted.connect(self.accept)
            buttons.rejected.connect(self.reject)
            layout.addWidget(buttons)

            self.combo_existing.currentIndexChanged.connect(self._on_pick_existing)
            self.btn_add.clicked.connect(self._on_add_level)
            self.btn_remove.clicked.connect(self._on_remove_level)
            self.btn_clear.clicked.connect(self.list_levels.clear)

        def _on_pick_existing(self, idx: int) -> None:
            data = self.combo_existing.itemData(idx)
            if isinstance(data, list) and data:
                self.list_levels.clear()
                for g in data:
                    self.list_levels.addItem(str(g))

        def _on_add_level(self) -> None:
            txt = self.edit_level.text().strip()
            if not txt:
                return
            for part in txt.split("\u25b6"):
                clean = part.strip()
                if clean:
                    self.list_levels.addItem(clean)
            self.edit_level.clear()

        def _on_remove_level(self) -> None:
            row = self.list_levels.currentRow()
            if row >= 0:
                self.list_levels.takeItem(row)

        def group_list(self) -> list[str]:
            return [
                self.list_levels.item(i).text().strip()
                for i in range(self.list_levels.count())
                if self.list_levels.item(i).text().strip()
            ]

    class EditLookupTableDialog(QDialog):
        """Table roll expression and upper-bound rows editor ported from `EDRTtbl` (`bin/mapper_legacy.tcl`)."""

        def __init__(
            self,
            dieroll: str = "1d20",
            flat_table: list[str] | None = None,
            parent: QWidget | None = None,
        ) -> None:
            super().__init__(parent)
            self.setWindowTitle("Edit Lookup Table Definition")
            self.resize(560, 420)

            layout = QVBoxLayout(self)
            form = QFormLayout()
            self.roll_edit = QLineEdit(dieroll or "1d20", self)
            form.addRow("Table Die Roll:", self.roll_edit)
            layout.addLayout(form)

            self.table = QTableWidget(0, 2, self)
            self.table.setHorizontalHeaderLabels(["Roll <=", "Result Text"])
            self.table.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.ResizeToContents)
            self.table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
            layout.addWidget(self.table, stretch=1)

            btn_row = QHBoxLayout()
            self.btn_add = QPushButton("+ Add Row", self)
            self.btn_remove = QPushButton("- Remove Row", self)
            self.btn_sort = QPushButton("Sort & Validate", self)
            btn_row.addWidget(self.btn_add)
            btn_row.addWidget(self.btn_remove)
            btn_row.addWidget(self.btn_sort)
            btn_row.addStretch(1)
            layout.addLayout(btn_row)

            buttons = QDialogButtonBox(
                QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel,
                self,
            )
            buttons.accepted.connect(self._on_accept)
            buttons.rejected.connect(self.reject)
            layout.addWidget(buttons)

            raw = list(flat_table or ["1", "Low", "*", "Default"])
            for i in range(0, len(raw) - 1, 2):
                self._append_row(raw[i], raw[i + 1])

            self.btn_add.clicked.connect(lambda: self._append_row("", ""))
            self.btn_remove.clicked.connect(self._remove_selected_row)
            self.btn_sort.clicked.connect(self._sort_rows_ui)

        def _append_row(self, bound: str, text: str) -> None:
            r = self.table.rowCount()
            self.table.insertRow(r)
            self.table.setItem(r, 0, QTableWidgetItem(str(bound)))
            self.table.setItem(r, 1, QTableWidgetItem(str(text)))

        def _remove_selected_row(self) -> None:
            r = self.table.currentRow()
            if r >= 0 and self.table.rowCount() > 1:
                self.table.removeRow(r)

        def _collect_raw_rows(self) -> list[tuple[str, str]]:
            rows: list[tuple[str, str]] = []
            for r in range(self.table.rowCount()):
                b_item = self.table.item(r, 0)
                t_item = self.table.item(r, 1)
                b_str = b_item.text().strip() if b_item else ""
                t_str = t_item.text() if t_item else ""
                if b_str or t_str:
                    rows.append((b_str, t_str))
            return rows

        def _sort_rows_ui(self) -> bool:
            try:
                sorted_rows = validate_and_sort_table_rows(self._collect_raw_rows())
            except ValueError as exc:
                QMessageBox.warning(self, "Invalid Lookup Table", str(exc))
                return False
            self.table.setRowCount(0)
            for b_str, t_str in sorted_rows:
                self._append_row(b_str, t_str)
            return True

        def _on_accept(self) -> None:
            if not self.roll_edit.text().strip():
                QMessageBox.warning(self, "Invalid Lookup Table", "Table die roll expression is required.")
                return
            if self._sort_rows_ui():
                self.accept()

        def dieroll(self) -> str:
            return self.roll_edit.text().strip()

        def flat_table(self) -> list[str]:
            sorted_rows = validate_and_sort_table_rows(self._collect_raw_rows())
            flat: list[str] = []
            for b_str, t_str in sorted_rows:
                flat.extend([b_str, t_str])
            return flat

    class EditDieRollPresetsDialog(QDialog):
        """Multi-tab Die-Roll Preset Editor ported from `EditDieRollPresets` (`bin/mapper_legacy.tcl`).

        Tabs:
        - Rolls (`preset`)
        - Modifiers & Variables (`modifier`)
        - Lookup Tables (`table`)
        - Custom / Raw (`custom`)
        - Global Reference tabs (read-only when editing user presets)
        """

        def __init__(
            self,
            bank: DicePresetBank,
            system_mode: bool = False,
            for_user: str = "",
            parent: QWidget | None = None,
        ) -> None:
            super().__init__(parent)
            self.system_mode = bool(system_mode)
            self.for_user = for_user
            title_target = "System (Global) Presets" if self.system_mode else (
                f"Die Roll Presets for {for_user}" if for_user else "Die Roll Presets"
            )
            self.setWindowTitle(f"Edit {title_target}")
            self.resize(860, 560)

            source_presets = bank.system_presets if self.system_mode else bank.user_presets
            self._details_list: list[dict[str, Any]] = [
                get_preset_details(p) for p in copy.deepcopy(source_presets)
            ]
            self._readonly_globals: list[dict[str, Any]] = (
                []
                if self.system_mode
                else [get_preset_details(p) for p in copy.deepcopy(bank.system_presets)]
            )

            layout = QVBoxLayout(self)
            self.tabs = QTabWidget(self)
            layout.addWidget(self.tabs, stretch=1)

            # 1. Rolls tab
            self.rolls_table = self._create_rolls_tab()
            self.tabs.addTab(self._wrap_tab(self.rolls_table, "preset"), "Rolls")

            # 2. Modifiers & Variables tab
            self.mods_table = self._create_modifiers_tab()
            self.tabs.addTab(self._wrap_tab(self.mods_table, "modifier"), "Modifiers && Variables")

            # 3. Lookup Tables tab
            self.tables_table = self._create_tables_tab()
            self.tabs.addTab(self._wrap_tab(self.tables_table, "table"), "Lookup Tables")

            # 4. Custom / Raw tab
            self.custom_table = self._create_custom_tab()
            self.tabs.addTab(self._wrap_tab(self.custom_table, "custom"), "Custom / Raw")

            # 5. Read-only Global Reference tab when editing user presets
            if not self.system_mode and self._readonly_globals:
                self.global_ref_table = self._create_global_ref_tab()
                self.tabs.addTab(self.global_ref_table, "Global Presets (Read-Only)")

            bottom_bar = QHBoxLayout()
            self.btn_syntax_help = QPushButton("Syntax Help...", self)
            self.btn_mod_help = QPushButton("Modifier Help...", self)
            bottom_bar.addWidget(self.btn_syntax_help)
            bottom_bar.addWidget(self.btn_mod_help)
            bottom_bar.addStretch(1)

            buttons = QDialogButtonBox(
                QDialogButtonBox.StandardButton.Save | QDialogButtonBox.StandardButton.Cancel,
                self,
            )
            save_btn = buttons.button(QDialogButtonBox.StandardButton.Save)
            if save_btn is not None:
                save_btn.setText("Save to Server")
            bottom_bar.addWidget(buttons)
            layout.addLayout(bottom_bar)

            self.btn_syntax_help.clicked.connect(self._show_syntax_help)
            self.btn_mod_help.clicked.connect(self._show_mod_help)
            buttons.accepted.connect(self._on_accept)
            buttons.rejected.connect(self.reject)

            self._populate_tables()
            self._initial_snapshot: list[dict[str, Any]] = self.encoded_presets()

        def reject(self) -> None:
            try:
                dirty = self.encoded_presets() != self._initial_snapshot
            except ValueError:
                dirty = True
            if dirty:
                ans = QMessageBox.question(
                    self,
                    "Confirm Cancel",
                    "Are you sure you wish to abandon any changes you made to the die-roll preset list?",
                    QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                    QMessageBox.StandardButton.No,
                )
                if ans != QMessageBox.StandardButton.Yes:
                    return
            super().reject()

        def _create_rolls_tab(self) -> QTableWidget:
            tbl = QTableWidget(0, 5, self)
            tbl.setHorizontalHeaderLabels(["Seq", "Group", "Name", "Description", "Die Roll Spec"])
            tbl.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.ResizeToContents)
            tbl.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.ResizeToContents)
            tbl.horizontalHeader().setSectionResizeMode(2, QHeaderView.ResizeMode.ResizeToContents)
            tbl.horizontalHeader().setSectionResizeMode(3, QHeaderView.ResizeMode.Stretch)
            tbl.horizontalHeader().setSectionResizeMode(4, QHeaderView.ResizeMode.Stretch)
            return tbl

        def _create_modifiers_tab(self) -> QTableWidget:
            tbl = QTableWidget(0, 8, self)
            tbl.setHorizontalHeaderLabels(
                [
                    "Seq",
                    "Group",
                    "Name",
                    "Description",
                    "Variable ($)",
                    "Default On",
                    "Global",
                    "Modifier / Value Spec",
                ]
            )
            tbl.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.ResizeToContents)
            tbl.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.ResizeToContents)
            tbl.horizontalHeader().setSectionResizeMode(2, QHeaderView.ResizeMode.ResizeToContents)
            tbl.horizontalHeader().setSectionResizeMode(3, QHeaderView.ResizeMode.Stretch)
            tbl.horizontalHeader().setSectionResizeMode(4, QHeaderView.ResizeMode.ResizeToContents)
            tbl.horizontalHeader().setSectionResizeMode(5, QHeaderView.ResizeMode.ResizeToContents)
            tbl.horizontalHeader().setSectionResizeMode(6, QHeaderView.ResizeMode.ResizeToContents)
            tbl.horizontalHeader().setSectionResizeMode(7, QHeaderView.ResizeMode.Stretch)
            return tbl

        def _create_tables_tab(self) -> QTableWidget:
            tbl = QTableWidget(0, 6, self)
            tbl.setHorizontalHeaderLabels(
                ["Seq", "Group", "Table ID (#)", "Title / Description", "Markup", "Table Definition"]
            )
            tbl.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.ResizeToContents)
            tbl.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.ResizeToContents)
            tbl.horizontalHeader().setSectionResizeMode(2, QHeaderView.ResizeMode.ResizeToContents)
            tbl.horizontalHeader().setSectionResizeMode(3, QHeaderView.ResizeMode.Stretch)
            tbl.horizontalHeader().setSectionResizeMode(4, QHeaderView.ResizeMode.ResizeToContents)
            tbl.horizontalHeader().setSectionResizeMode(5, QHeaderView.ResizeMode.Stretch)
            return tbl

        def _create_custom_tab(self) -> QTableWidget:
            tbl = QTableWidget(0, 3, self)
            tbl.setHorizontalHeaderLabels(["Raw Name", "Description", "Raw DieRollSpec"])
            tbl.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.ResizeToContents)
            tbl.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
            tbl.horizontalHeader().setSectionResizeMode(2, QHeaderView.ResizeMode.Stretch)
            return tbl

        def _create_global_ref_tab(self) -> QTableWidget:
            tbl = QTableWidget(0, 4, self)
            tbl.setHorizontalHeaderLabels(["Type", "Name", "Description", "Specification"])
            tbl.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
            for d in self._readonly_globals:
                r = tbl.rowCount()
                tbl.insertRow(r)
                tbl.setItem(r, 0, QTableWidgetItem(str(d.get("type", "preset"))))
                tbl.setItem(r, 1, QTableWidgetItem(str(d.get("name", ""))))
                tbl.setItem(r, 2, QTableWidgetItem(str(d.get("description", ""))))
                tbl.setItem(r, 3, QTableWidgetItem(str(d.get("dieroll", ""))))
            tbl.horizontalHeader().setSectionResizeMode(3, QHeaderView.ResizeMode.Stretch)
            return tbl

        def _wrap_tab(self, table: QTableWidget, tab_kind: str) -> QWidget:
            container = QWidget(self)
            vbox = QVBoxLayout(container)
            vbox.addWidget(table, stretch=1)

            btn_row = QHBoxLayout()
            btn_add = QPushButton("+ Add", container)
            btn_dup = QPushButton("Duplicate", container)
            btn_del = QPushButton("- Delete", container)
            btn_up = QPushButton("\u2191 Move Up", container)
            btn_down = QPushButton("\u2193 Move Down", container)
            btn_reseq = QPushButton("Auto-Number Seq", container)
            btn_group = QPushButton("Edit Group...", container)

            btn_row.addWidget(btn_add)
            btn_row.addWidget(btn_dup)
            btn_row.addWidget(btn_del)
            btn_row.addWidget(btn_up)
            btn_row.addWidget(btn_down)
            if tab_kind != "custom":
                btn_row.addWidget(btn_reseq)
                btn_row.addWidget(btn_group)

            if tab_kind == "preset":
                btn_color = QPushButton("Color-Box Title...", container)
                btn_color.clicked.connect(self._edit_selected_roll_colorbox)
                btn_row.addWidget(btn_color)
            elif tab_kind == "table":
                btn_tbl_rows = QPushButton("Edit Table Rows...", container)
                btn_tbl_rows.clicked.connect(self._edit_selected_lookup_table)
                btn_row.addWidget(btn_tbl_rows)

            btn_row.addStretch(1)
            vbox.addLayout(btn_row)

            btn_add.clicked.connect(lambda: self._add_row_for_kind(table, tab_kind))
            btn_dup.clicked.connect(lambda: self._duplicate_row(table, tab_kind))
            btn_del.clicked.connect(lambda: self._delete_selected_row(table))
            btn_up.clicked.connect(lambda: self._move_row(table, -1))
            btn_down.clicked.connect(lambda: self._move_row(table, 1))
            btn_reseq.clicked.connect(lambda: self._auto_resequence(table))
            btn_group.clicked.connect(lambda: self._edit_selected_group(table))
            return container

        def _populate_tables(self) -> None:
            self.rolls_table.setRowCount(0)
            self.mods_table.setRowCount(0)
            self.tables_table.setRowCount(0)
            self.custom_table.setRowCount(0)

            for d in self._details_list:
                dtype = d.get("type", "preset")
                group_str = " \u25b6 ".join(d.get("group") or [])
                if dtype == "preset":
                    r = self.rolls_table.rowCount()
                    self.rolls_table.insertRow(r)
                    seq_item = QTableWidgetItem(str(d.get("seq", "")))
                    seq_item.setData(Qt.ItemDataRole.UserRole, {"area": str(d.get("area", "") or "")})
                    self.rolls_table.setItem(r, 0, seq_item)
                    self.rolls_table.setItem(r, 1, QTableWidgetItem(group_str))
                    self.rolls_table.setItem(r, 2, QTableWidgetItem(str(d.get("name", ""))))
                    self.rolls_table.setItem(r, 3, QTableWidgetItem(str(d.get("description", ""))))
                    self.rolls_table.setItem(r, 4, QTableWidgetItem(str(d.get("dieroll", ""))))
                elif dtype == "modifier":
                    r = self.mods_table.rowCount()
                    self.mods_table.insertRow(r)
                    seq_item = QTableWidgetItem(str(d.get("seq", "")))
                    seq_item.setData(Qt.ItemDataRole.UserRole, {"client": str(d.get("client", "") or "")})
                    self.mods_table.setItem(r, 0, seq_item)
                    self.mods_table.setItem(r, 1, QTableWidgetItem(group_str))
                    self.mods_table.setItem(r, 2, QTableWidgetItem(str(d.get("name", ""))))
                    self.mods_table.setItem(r, 3, QTableWidgetItem(str(d.get("description", ""))))
                    self.mods_table.setItem(r, 4, QTableWidgetItem(str(d.get("var", ""))))

                    chk_en = QTableWidgetItem()
                    chk_en.setFlags(Qt.ItemFlag.ItemIsUserCheckable | Qt.ItemFlag.ItemIsEnabled | Qt.ItemFlag.ItemIsSelectable)
                    chk_en.setCheckState(Qt.CheckState.Checked if d.get("enabled") else Qt.CheckState.Unchecked)
                    self.mods_table.setItem(r, 5, chk_en)

                    chk_gl = QTableWidgetItem()
                    chk_gl.setFlags(Qt.ItemFlag.ItemIsUserCheckable | Qt.ItemFlag.ItemIsEnabled | Qt.ItemFlag.ItemIsSelectable)
                    chk_gl.setCheckState(Qt.CheckState.Checked if d.get("global") else Qt.CheckState.Unchecked)
                    self.mods_table.setItem(r, 6, chk_gl)

                    self.mods_table.setItem(r, 7, QTableWidgetItem(str(d.get("dieroll", ""))))
                elif dtype == "table":
                    r = self.tables_table.rowCount()
                    self.tables_table.insertRow(r)
                    seq_item = QTableWidgetItem(str(d.get("seq", "")))
                    seq_item.setData(Qt.ItemDataRole.UserRole, {"client": str(d.get("client", "") or "")})
                    self.tables_table.setItem(r, 0, seq_item)
                    self.tables_table.setItem(r, 1, QTableWidgetItem(group_str))
                    self.tables_table.setItem(r, 2, QTableWidgetItem(str(d.get("name", ""))))
                    self.tables_table.setItem(r, 3, QTableWidgetItem(str(d.get("description", ""))))

                    chk_mk = QTableWidgetItem()
                    chk_mk.setFlags(Qt.ItemFlag.ItemIsUserCheckable | Qt.ItemFlag.ItemIsEnabled | Qt.ItemFlag.ItemIsSelectable)
                    chk_mk.setCheckState(Qt.CheckState.Checked if d.get("markup") else Qt.CheckState.Unchecked)
                    self.tables_table.setItem(r, 4, chk_mk)

                    summary_item = QTableWidgetItem(self._format_table_summary(d.get("dieroll", "1d20"), d.get("table") or []))
                    summary_item.setData(Qt.ItemDataRole.UserRole, {
                        "dieroll": d.get("dieroll", "1d20"),
                        "table": list(d.get("table") or ["1", "Low", "*", "High"]),
                        "delim": d.get("delim", ";"),
                    })
                    self.tables_table.setItem(r, 5, summary_item)
                else:
                    raw = d.get("_raw") or {}
                    r = self.custom_table.rowCount()
                    self.custom_table.insertRow(r)
                    self.custom_table.setItem(r, 0, QTableWidgetItem(str(raw.get("Name", d.get("name", "")))))
                    self.custom_table.setItem(r, 1, QTableWidgetItem(str(raw.get("Description", d.get("description", "")))))
                    self.custom_table.setItem(r, 2, QTableWidgetItem(str(raw.get("DieRollSpec", d.get("dieroll", "")))))

        @staticmethod
        def _format_table_summary(dieroll: str, flat_table: list[str]) -> str:
            pair_count = len(flat_table) // 2
            return f"{dieroll} ({pair_count} rows)"

        def _add_row_for_kind(self, table: QTableWidget, tab_kind: str) -> None:
            r = table.rowCount()
            table.insertRow(r)
            seq_str = f"{(r + 1) * 10:03d}"
            if tab_kind == "preset":
                seq_item = QTableWidgetItem(seq_str)
                seq_item.setData(Qt.ItemDataRole.UserRole, {})
                table.setItem(r, 0, seq_item)
                table.setItem(r, 1, QTableWidgetItem(""))
                table.setItem(r, 2, QTableWidgetItem("New Roll"))
                table.setItem(r, 3, QTableWidgetItem(""))
                table.setItem(r, 4, QTableWidgetItem("1d20"))
            elif tab_kind == "modifier":
                seq_item = QTableWidgetItem(seq_str)
                seq_item.setData(Qt.ItemDataRole.UserRole, {})
                table.setItem(r, 0, seq_item)
                table.setItem(r, 1, QTableWidgetItem(""))
                table.setItem(r, 2, QTableWidgetItem("New Modifier"))
                table.setItem(r, 3, QTableWidgetItem(""))
                table.setItem(r, 4, QTableWidgetItem(""))
                chk_en = QTableWidgetItem()
                chk_en.setFlags(Qt.ItemFlag.ItemIsUserCheckable | Qt.ItemFlag.ItemIsEnabled | Qt.ItemFlag.ItemIsSelectable)
                chk_en.setCheckState(Qt.CheckState.Unchecked)
                table.setItem(r, 5, chk_en)
                chk_gl = QTableWidgetItem()
                chk_gl.setFlags(Qt.ItemFlag.ItemIsUserCheckable | Qt.ItemFlag.ItemIsEnabled | Qt.ItemFlag.ItemIsSelectable)
                chk_gl.setCheckState(Qt.CheckState.Unchecked)
                table.setItem(r, 6, chk_gl)
                table.setItem(r, 7, QTableWidgetItem("+2"))
            elif tab_kind == "table":
                seq_item = QTableWidgetItem(seq_str)
                seq_item.setData(Qt.ItemDataRole.UserRole, {})
                table.setItem(r, 0, seq_item)
                table.setItem(r, 1, QTableWidgetItem(""))
                table.setItem(r, 2, QTableWidgetItem("new_table"))
                table.setItem(r, 3, QTableWidgetItem("New Lookup Table"))
                chk_mk = QTableWidgetItem()
                chk_mk.setFlags(Qt.ItemFlag.ItemIsUserCheckable | Qt.ItemFlag.ItemIsEnabled | Qt.ItemFlag.ItemIsSelectable)
                chk_mk.setCheckState(Qt.CheckState.Unchecked)
                table.setItem(r, 4, chk_mk)
                default_tbl = ["10", "Failure", "*", "Success"]
                summary_item = QTableWidgetItem(self._format_table_summary("1d20", default_tbl))
                summary_item.setData(Qt.ItemDataRole.UserRole, {
                    "dieroll": "1d20",
                    "table": default_tbl,
                    "delim": ";",
                })
                table.setItem(r, 5, summary_item)
            else:
                table.setItem(r, 0, QTableWidgetItem("Custom"))
                table.setItem(r, 1, QTableWidgetItem(""))
                table.setItem(r, 2, QTableWidgetItem("1d20"))
            table.setCurrentCell(r, 0)

        def _duplicate_row(self, table: QTableWidget, tab_kind: str) -> None:
            _ = tab_kind
            r = table.currentRow()
            if r < 0:
                return
            dst = r + 1
            table.insertRow(dst)
            for c in range(table.columnCount()):
                src_item = table.item(r, c)
                if src_item is not None:
                    cloned = src_item.clone()
                    table.setItem(dst, c, cloned)
            table.setCurrentCell(dst, 0)

        def _delete_selected_row(self, table: QTableWidget) -> None:
            r = table.currentRow()
            if r >= 0:
                table.removeRow(r)

        def _move_row(self, table: QTableWidget, delta: int) -> None:
            r = table.currentRow()
            target = r + delta
            if r < 0 or target < 0 or target >= table.rowCount():
                return
            for c in range(table.columnCount()):
                a = table.takeItem(r, c)
                b = table.takeItem(target, c)
                table.setItem(r, c, b)
                table.setItem(target, c, a)
            table.setCurrentCell(target, max(0, table.currentColumn()))

        def _auto_resequence(self, table: QTableWidget) -> None:
            for r in range(table.rowCount()):
                seq_text = f"{(r + 1) * 10:03d}"
                existing_item = table.item(r, 0)
                if existing_item is not None:
                    existing_item.setText(seq_text)
                else:
                    table.setItem(r, 0, QTableWidgetItem(seq_text))

        def _known_group_paths(self) -> list[list[str]]:
            paths: list[list[str]] = []
            for tbl in (self.rolls_table, self.mods_table, self.tables_table):
                for r in range(tbl.rowCount()):
                    it = tbl.item(r, 1)
                    if it and it.text().strip():
                        parts = [p.strip() for p in it.text().split("\u25b6") if p.strip()]
                        if parts:
                            paths.append(parts)
            return paths

        def _edit_selected_group(self, table: QTableWidget) -> None:
            r = table.currentRow()
            if r < 0:
                return
            cur_item = table.item(r, 1)
            cur_groups = [
                p.strip() for p in (cur_item.text() if cur_item else "").split("\u25b6") if p.strip()
            ]
            dlg = EditPresetGroupDialog(cur_groups, self._known_group_paths(), self)
            if dlg.exec():
                table.setItem(r, 1, QTableWidgetItem(" \u25b6 ".join(dlg.group_list())))

        def _edit_selected_roll_colorbox(self) -> None:
            r = self.rolls_table.currentRow()
            if r < 0:
                return
            spec_item = self.rolls_table.item(r, 4)
            cur_spec = spec_item.text() if spec_item else ""
            dlg = EditColorBoxTitleDialog(cur_spec, self)
            if dlg.exec():
                self.rolls_table.setItem(r, 4, QTableWidgetItem(dlg.updated_roll_spec(cur_spec)))

        def _edit_selected_lookup_table(self) -> None:
            r = self.tables_table.currentRow()
            if r < 0:
                return
            summary_item = self.tables_table.item(r, 5)
            data = (
                summary_item.data(Qt.ItemDataRole.UserRole)
                if summary_item is not None
                else None
            ) or {"dieroll": "1d20", "table": ["1", "Low", "*", "High"], "delim": ";"}
            dlg = EditLookupTableDialog(
                dieroll=str(data.get("dieroll", "1d20")),
                flat_table=list(data.get("table") or []),
                parent=self,
            )
            if dlg.exec():
                new_data = {
                    "dieroll": dlg.dieroll(),
                    "table": dlg.flat_table(),
                    "delim": data.get("delim", ";"),
                }
                new_item = QTableWidgetItem(
                    self._format_table_summary(new_data["dieroll"], new_data["table"])
                )
                new_item.setData(Qt.ItemDataRole.UserRole, new_data)
                self.tables_table.setItem(r, 5, new_item)

        def _show_syntax_help(self) -> None:
            dlg = DiceSyntaxHelpDialog(self)
            dlg.exec()

        def _show_mod_help(self) -> None:
            dlg = DiceModifierHelpDialog(self)
            dlg.exec()

        @staticmethod
        def _row_meta(table: QTableWidget, row: int) -> dict[str, Any]:
            item = table.item(row, 0)
            data = item.data(Qt.ItemDataRole.UserRole) if item is not None else None
            return data if isinstance(data, dict) else {}

        def encoded_presets(self) -> list[dict[str, Any]]:
            """Encode all tabs back into raw GMA protocol preset dictionaries."""
            out: list[dict[str, Any]] = []

            # 1. Rolls
            for r in range(self.rolls_table.rowCount()):
                seq = (self.rolls_table.item(r, 0).text() if self.rolls_table.item(r, 0) else "").strip()
                grp_raw = (self.rolls_table.item(r, 1).text() if self.rolls_table.item(r, 1) else "").strip()
                groups = [g.strip() for g in grp_raw.split("\u25b6") if g.strip()]
                name = (self.rolls_table.item(r, 2).text() if self.rolls_table.item(r, 2) else "").strip()
                desc = (self.rolls_table.item(r, 3).text() if self.rolls_table.item(r, 3) else "").strip()
                spec = (self.rolls_table.item(r, 4).text() if self.rolls_table.item(r, 4) else "").strip()
                if not name and not spec:
                    continue
                meta = self._row_meta(self.rolls_table, r)
                out.append(
                    encode_preset_details(
                        {
                            "type": "preset",
                            "seq": seq,
                            "area": str(meta.get("area", "") or ""),
                            "group": groups,
                            "name": name,
                            "description": desc,
                            "dieroll": spec,
                            "system": self.system_mode,
                        }
                    )
                )

            # 2. Modifiers & Variables
            for r in range(self.mods_table.rowCount()):
                seq = (self.mods_table.item(r, 0).text() if self.mods_table.item(r, 0) else "").strip()
                grp_raw = (self.mods_table.item(r, 1).text() if self.mods_table.item(r, 1) else "").strip()
                groups = [g.strip() for g in grp_raw.split("\u25b6") if g.strip()]
                name = (self.mods_table.item(r, 2).text() if self.mods_table.item(r, 2) else "").strip()
                desc = (self.mods_table.item(r, 3).text() if self.mods_table.item(r, 3) else "").strip()
                var_name = (self.mods_table.item(r, 4).text() if self.mods_table.item(r, 4) else "").strip()
                en_item = self.mods_table.item(r, 5)
                gl_item = self.mods_table.item(r, 6)
                enabled = bool(en_item and en_item.checkState() == Qt.CheckState.Checked)
                is_glob = bool(gl_item and gl_item.checkState() == Qt.CheckState.Checked)
                spec = (self.mods_table.item(r, 7).text() if self.mods_table.item(r, 7) else "").strip()
                if not name and not spec:
                    continue
                meta = self._row_meta(self.mods_table, r)
                out.append(
                    encode_preset_details(
                        {
                            "type": "modifier",
                            "seq": seq,
                            "client": str(meta.get("client", "") or ""),
                            "group": groups,
                            "name": name,
                            "description": desc,
                            "var": var_name,
                            "enabled": enabled,
                            "global": is_glob,
                            "dieroll": spec,
                            "system": self.system_mode,
                        }
                    )
                )

            # 3. Lookup Tables
            for r in range(self.tables_table.rowCount()):
                seq = (self.tables_table.item(r, 0).text() if self.tables_table.item(r, 0) else "").strip()
                grp_raw = (self.tables_table.item(r, 1).text() if self.tables_table.item(r, 1) else "").strip()
                groups = [g.strip() for g in grp_raw.split("\u25b6") if g.strip()]
                name = (self.tables_table.item(r, 2).text() if self.tables_table.item(r, 2) else "").strip()
                desc = (self.tables_table.item(r, 3).text() if self.tables_table.item(r, 3) else "").strip()
                mk_item = self.tables_table.item(r, 4)
                markup = bool(mk_item and mk_item.checkState() == Qt.CheckState.Checked)
                summary_item = self.tables_table.item(r, 5)
                tbl_data = (
                    summary_item.data(Qt.ItemDataRole.UserRole)
                    if summary_item is not None
                    else None
                ) or {"dieroll": "1d20", "table": ["1", "Low", "*", "High"], "delim": ";"}
                if not name:
                    continue
                meta = self._row_meta(self.tables_table, r)
                out.append(
                    encode_preset_details(
                        {
                            "type": "table",
                            "seq": seq,
                            "client": str(meta.get("client", "") or ""),
                            "group": groups,
                            "name": name,
                            "description": desc,
                            "markup": markup,
                            "dieroll": tbl_data["dieroll"],
                            "table": tbl_data["table"],
                            "delim": tbl_data.get("delim", ";"),
                            "system": self.system_mode,
                        }
                    )
                )

            # 4. Custom / Raw
            for r in range(self.custom_table.rowCount()):
                raw_name = (self.custom_table.item(r, 0).text() if self.custom_table.item(r, 0) else "").strip()
                raw_desc = (self.custom_table.item(r, 1).text() if self.custom_table.item(r, 1) else "").strip()
                raw_spec = (self.custom_table.item(r, 2).text() if self.custom_table.item(r, 2) else "").strip()
                if not raw_name and not raw_spec:
                    continue
                out.append(
                    {
                        "Name": raw_name,
                        "Description": raw_desc,
                        "DieRollSpec": raw_spec,
                        "Global": self.system_mode,
                    }
                )

            return out

        def _on_accept(self) -> None:
            try:
                _ = self.encoded_presets()
            except ValueError as exc:
                QMessageBox.warning(self, "Invalid Preset Definition", str(exc))
                return
            self.accept()

    class ManageDelegatesDialog(QDialog):
        """Dialog to manage players who are allowed to access your die-roll presets (`DDD`).

        Ported from `EditDelegateList` in `bin/mapper_legacy.tcl`.
        """

        def __init__(
            self,
            current_delegates: list[str] | tuple[str, ...] = (),
            known_peers: list[str] | tuple[str, ...] = (),
            parent: QWidget | None = None,
        ) -> None:
            super().__init__(parent)
            self.setWindowTitle("Manage Die Roll Delegates")
            self.resize(420, 320)

            layout = QVBoxLayout(self)
            layout.addWidget(
                QLabel("Players authorized to view and roll your die-roll presets:", self)
            )

            self.list_widget = QListWidget(self)
            for d in current_delegates:
                if d:
                    self.list_widget.addItem(str(d))
            layout.addWidget(self.list_widget, stretch=1)

            add_row = QHBoxLayout()
            self.combo_peer = QComboBox(self)
            self.combo_peer.setEditable(True)
            for p in known_peers:
                if p:
                    self.combo_peer.addItem(str(p))
            self.btn_add = QPushButton("+ Add Delegate", self)
            self.btn_remove = QPushButton("- Remove Selected", self)
            add_row.addWidget(self.combo_peer, stretch=1)
            add_row.addWidget(self.btn_add)
            add_row.addWidget(self.btn_remove)
            layout.addLayout(add_row)

            buttons = QDialogButtonBox(
                QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel,
                self,
            )
            buttons.accepted.connect(self.accept)
            buttons.rejected.connect(self.reject)
            layout.addWidget(buttons)

            self.btn_add.clicked.connect(self._on_add)
            self.btn_remove.clicked.connect(self._on_remove)

        def _on_add(self) -> None:
            name = self.combo_peer.currentText().strip()
            if not name:
                return
            existing = {
                self.list_widget.item(i).text() for i in range(self.list_widget.count())
            }
            if name not in existing:
                self.list_widget.addItem(name)
            self.combo_peer.setEditText("")

        def _on_remove(self) -> None:
            row = self.list_widget.currentRow()
            if row >= 0:
                self.list_widget.takeItem(row)

        def delegates(self) -> list[str]:
            return [
                self.list_widget.item(i).text().strip()
                for i in range(self.list_widget.count())
                if self.list_widget.item(i).text().strip()
            ]

    class QuickSavePresetDialog(QDialog):
        """Lightweight single-preset save dialog ported from `AddDieRollPreset` / `CommitNewPreset`."""

        def __init__(
            self,
            initial_spec: str = "",
            initial_name: str = "",
            initial_description: str = "",
            known_group_paths: list[list[str]] | None = None,
            for_user: str = "",
            parent: QWidget | None = None,
        ) -> None:
            super().__init__(parent)
            self._known_group_paths = known_group_paths or []
            self.for_user = for_user
            self.setWindowTitle(
                f"Save Die-Roll Preset to Server ({for_user})"
                if for_user
                else "Save Die-Roll Preset to Server"
            )
            self.resize(480, 240)

            suggested_name = initial_name.strip()
            if not suggested_name and "=" in initial_spec:
                suggested_name = cleanup_die_roll_spec(initial_spec).split("=", 1)[0].strip()

            layout = QVBoxLayout(self)
            form = QFormLayout()

            self.seq_edit = QLineEdit(self)
            self.seq_edit.setPlaceholderText("Optional (e.g. 010)")
            form.addRow("Sequence:", self.seq_edit)

            grp_row = QHBoxLayout()
            self.group_edit = QLineEdit(self)
            self.group_edit.setPlaceholderText("Optional (e.g. Attacks \u25b6 Melee)")
            self.btn_edit_group = QPushButton("Groups...", self)
            self.btn_edit_group.clicked.connect(self._edit_group)
            grp_row.addWidget(self.group_edit, stretch=1)
            grp_row.addWidget(self.btn_edit_group)
            form.addRow("Group:", grp_row)

            self.name_edit = QLineEdit(suggested_name, self)
            self.name_edit.setPlaceholderText("Required preset name")
            form.addRow("Preset Name:", self.name_edit)

            self.desc_edit = QLineEdit(initial_description, self)
            self.desc_edit.setPlaceholderText("Optional description")
            form.addRow("Description:", self.desc_edit)

            spec_row = QHBoxLayout()
            self.spec_edit = QLineEdit(initial_spec.strip(), self)
            self.spec_edit.setPlaceholderText("Required die roll specification")
            self.btn_colorbox = QPushButton("Color-Box...", self)
            self.btn_colorbox.clicked.connect(self._edit_colorbox)
            spec_row.addWidget(self.spec_edit, stretch=1)
            spec_row.addWidget(self.btn_colorbox)
            form.addRow("Die Roll Spec:", spec_row)

            layout.addLayout(form)

            buttons = QDialogButtonBox(
                QDialogButtonBox.StandardButton.Save | QDialogButtonBox.StandardButton.Cancel,
                self,
            )
            save_btn = buttons.button(QDialogButtonBox.StandardButton.Save)
            if save_btn is not None:
                save_btn.setText("Save to Server")
            buttons.accepted.connect(self._on_accept)
            buttons.rejected.connect(self.reject)
            layout.addWidget(buttons)

        def _edit_group(self) -> None:
            cur_groups = [
                g.strip() for g in self.group_edit.text().split("\u25b6") if g.strip()
            ]
            dlg = EditPresetGroupDialog(cur_groups, self._known_group_paths, self)
            if dlg.exec():
                self.group_edit.setText(" \u25b6 ".join(dlg.group_list()))

        def _edit_colorbox(self) -> None:
            cur_spec = self.spec_edit.text()
            dlg = EditColorBoxTitleDialog(cur_spec, self)
            if dlg.exec():
                self.spec_edit.setText(dlg.updated_roll_spec(cur_spec))

        def _on_accept(self) -> None:
            if not self.name_edit.text().strip():
                QMessageBox.warning(
                    self,
                    "Preset Name Required",
                    "The preset name must be provided. If it matches an existing preset, it will replace the old one.",
                )
                return
            if not self.spec_edit.text().strip():
                QMessageBox.warning(
                    self,
                    "Die Roll Required",
                    "A die-roll specification must be provided.",
                )
                return
            self.accept()

        def encoded_preset(self) -> dict[str, Any]:
            groups = [g.strip() for g in self.group_edit.text().split("\u25b6") if g.strip()]
            return encode_preset_details(
                {
                    "type": "preset",
                    "seq": self.seq_edit.text().strip(),
                    "group": groups,
                    "name": self.name_edit.text().strip(),
                    "description": self.desc_edit.text().strip(),
                    "dieroll": self.spec_edit.text().strip(),
                    "system": False,
                }
            )
