"""Main application window for ``py_dieroller`` ported to PySide6.

Ported from ``GMADieRoller/DieRoller2.py``.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import tempfile
from typing import Any

from gma_mapper.core.dice import DicePresetBank, merge_preset_lists
from gma_mapper.core.file_io import load_dice_presets_from_file
from gma_mapper.ui.dialogs.dice_dialogs import EditLookupTableDialog
from py_dieroller import APP_NAME, APP_VERSION
from py_dieroller.chat import ChatPanel
from py_dieroller.images import DICE_LARGE_PNG, DICE_LT_PNG, load_qicon, load_qpixmap
from py_dieroller.map_service import MapService
from py_dieroller.models import (
    MODIFIER_TYPES,
    PRESET_TAB_BY_TYPE,
    ModifierRow,
    PresetRow,
    TableRow,
    VariableRow,
    normalize_table_dict,
    parse_gma_preset,
    parse_gma_table_preset,
)
from py_dieroller.settings import SettingsDialog, SettingsStore

L_VERTICAL = 0
L_HORIZONTAL = 1

try:
    from PySide6.QtCore import Qt
    from PySide6.QtGui import QAction, QCloseEvent, QKeySequence
    from PySide6.QtWidgets import (
        QApplication,
        QDialog,
        QFileDialog,
        QGridLayout,
        QLabel,
        QLineEdit,
        QMainWindow,
        QMessageBox,
        QPushButton,
        QScrollArea,
        QSplitter,
        QStyle,
        QTabWidget,
        QVBoxLayout,
        QWidget,
    )

    QT_AVAILABLE = True
except ImportError:  # pragma: no cover
    QT_AVAILABLE = False


if QT_AVAILABLE:

    class DieRollerWindow(QMainWindow):
        """Standalone PySide6 GMA Die Roller window."""

        def __init__(
            self,
            config_file: str | Path | None = None,
            font_size: int | None = None,
            parent: QWidget | None = None,
        ) -> None:
            super().__init__(parent)
            self.unsaved_changes: bool = False
            self.modifiers_changed: bool = False
            self.variables_changed: bool = False
            self.loading_presets: bool = False

            self.presets_filename: Path | None = None
            self.modifiers: list[ModifierRow] = []
            self.tables: list[TableRow] = []
            self.variables: list[VariableRow] = []
            self.variable_defs: dict[str, str] = {}
            self.server_bank = DicePresetBank(tkey="local")
            self.presets: dict[str, list[PresetRow]] = {
                "pnCombat": [],
                "pnSave": [],
                "pnSkill": [],
                "pnOther": [],
            }
            self.preset_tabs: dict[str, QWidget] = {}
            self.preset_grids: dict[str, QGridLayout] = {}
            self._tab_row_buttons: dict[str, list[QWidget]] = {
                "pnCombat": [],
                "pnSave": [],
                "pnSkill": [],
                "pnOther": [],
                "pnModifiers": [],
                "pnTables": [],
                "pnConst": [],
                "pnHistory": [],
            }
            self.history: list[str] = []
            self.max_history: int = 20
            self.history_widgets: list[QWidget] = []
            self.chat_layout: int = L_VERTICAL
            self._server_actions: list[QAction] = []

            self.settings = SettingsStore(filename=config_file, alert_cb=self.alert)
            self.settings.load()
            if font_size is not None and font_size > 0:
                app = QApplication.instance()
                if app is not None:
                    fnt = app.font()
                    fnt.setPointSize(int(font_size))
                    app.setFont(fnt)
            elif self.settings.relfontsize != 0:
                fnt = self.font()
                cur_pt = fnt.pointSize() if fnt.pointSize() > 0 else 10
                fnt.setPointSize(max(6, cur_pt + self.settings.relfontsize * 2))
                self.setFont(fnt)

            self.setWindowTitle(APP_NAME)
            self.setWindowIcon(load_qicon(DICE_LARGE_PNG, size=64))
            self.resize(620, 720)
            self.setMinimumSize(510, 500)

            self._init_gui()

            self.service = MapService(self.settings, parent=self, version=APP_VERSION)
            self.chatwindow.service = self.service
            self.service.connection_changed.connect(self._on_connect_state_changed)
            self.service.messages_received.connect(self.chatwindow.add_messages)
            self.service.chat_received.connect(self.chatwindow.append_chat_payload)
            self.service.chat_cleared.connect(self.chatwindow.handle_clear_chat_payload)
            self.service.chat_pruned.connect(self.chatwindow.handle_prune_chat_payload)
            self.service.userlist_updated.connect(self.chatwindow.update_userlist)
            self.service.presets_received.connect(self._on_server_presets_received)
            self.service.roll_payload_received.connect(self.chatwindow.handle_roll_payload)

            self._rebuild_server_menu()
            self.load_presets()
            self.update_preset_modifiers()
            self.chatwindow.add_message("Ready", style="comment")

        # ------------------------------------------------------------------
        # UI Construction
        # ------------------------------------------------------------------
        def _init_gui(self) -> None:
            menubar = self.menuBar()

            # File menu
            file_menu = menubar.addMenu("&File")
            self.act_open = QAction("&Open...", self)
            self.act_open.setShortcut(QKeySequence("Ctrl+O"))
            self.act_open.triggered.connect(lambda: self.load_presets(choosefile=True))
            file_menu.addAction(self.act_open)

            self.act_save = QAction("&Save", self)
            self.act_save.setShortcut(QKeySequence("Ctrl+S"))
            self.act_save.triggered.connect(lambda: self.save_presets(choosefile=False))
            file_menu.addAction(self.act_save)

            self.act_save_as = QAction("Save &As...", self)
            self.act_save_as.triggered.connect(lambda: self.save_presets(choosefile=True))
            file_menu.addAction(self.act_save_as)

            file_menu.addSeparator()
            self.act_import_gma = QAction("&Import GMA presets...", self)
            self.act_import_gma.triggered.connect(self.import_gma)
            file_menu.addAction(self.act_import_gma)

            file_menu.addSeparator()
            self.act_exit = QAction("E&xit", self)
            self.act_exit.setShortcut(QKeySequence("Ctrl+X"))
            self.act_exit.triggered.connect(self.close)
            file_menu.addAction(self.act_exit)

            # Edit menu
            edit_menu = menubar.addMenu("&Edit")
            self.act_preferences = QAction("&Preferences...", self)
            self.act_preferences.triggered.connect(self.open_preferences)
            edit_menu.addAction(self.act_preferences)

            edit_menu.addSeparator()
            self.act_clear_chat = QAction("Clear &Chat Messages", self)
            self.act_clear_chat.triggered.connect(
                lambda _c=False: self.chatwindow.clear_chat_messages(include_pinned=False)
            )
            edit_menu.addAction(self.act_clear_chat)

            self.act_clear_pinned = QAction("Clear &Pinned Chat Messages", self)
            self.act_clear_pinned.triggered.connect(
                lambda _c=False: self.chatwindow.clear_pinned_messages()
            )
            edit_menu.addAction(self.act_clear_pinned)

            # Server menu
            self.server_menu = menubar.addMenu("&Server")
            self.act_server_connect = QAction("&Connect", self)
            self.act_server_connect.triggered.connect(self.on_menu_server_connect)
            self.server_menu.addAction(self.act_server_connect)

            self.act_server_disconnect = QAction("&Disconnect", self)
            self.act_server_disconnect.setEnabled(False)
            self.act_server_disconnect.triggered.connect(self.on_menu_server_disconnect)
            self.server_menu.addAction(self.act_server_disconnect)
            self._server_separator = self.server_menu.addSeparator()

            # View menu
            view_menu = menubar.addMenu("&View")
            self.act_view_chat = QAction("&Chat panel", self)
            self.act_view_chat.setCheckable(True)
            self.act_view_chat.setChecked(True)
            self.act_view_chat.toggled.connect(self.on_menu_view_chat)
            view_menu.addAction(self.act_view_chat)

            self.act_view_pinned = QAction("&Pinned messages", self)
            self.act_view_pinned.setCheckable(True)
            self.act_view_pinned.setChecked(True)
            view_menu.addAction(self.act_view_pinned)

            layout_menu = view_menu.addMenu("&Layout")
            self.act_layout_h = QAction("&Horizontal", self)
            self.act_layout_h.triggered.connect(self.on_layout_h)
            layout_menu.addAction(self.act_layout_h)

            self.act_layout_v = QAction("&Vertical", self)
            self.act_layout_v.triggered.connect(self.on_layout_v)
            layout_menu.addAction(self.act_layout_v)

            # Help menu
            help_menu = menubar.addMenu("&Help")
            self.act_about = QAction("&About", self)
            self.act_about.triggered.connect(self.on_help_about)
            help_menu.addAction(self.act_about)

            # Main vertical/horizontal splitter: ChatPanel + TabWidget
            self.split_win = QSplitter(Qt.Orientation.Vertical, self)
            self.setCentralWidget(self.split_win)

            self.chatwindow = ChatPanel(
                settings=self.settings,
                parent=self.split_win,
                on_alert=self.alert,
                get_variables=self._get_variable_defs,
                on_history_add=self.history_add,
                get_table_bank=self.get_table_bank,
            )
            self.act_view_pinned.toggled.connect(self.chatwindow.set_pinned_panel_enabled)

            self.tab_panel = QWidget(self.split_win)
            tab_vbox = QVBoxLayout(self.tab_panel)
            tab_vbox.setContentsMargins(4, 4, 4, 4)

            self.notebook = QTabWidget(self.tab_panel)
            self.notebook.currentChanged.connect(self._on_notebook_page_changed)
            tab_vbox.addWidget(self.notebook)

            self.modifier_host = self._create_scrollable_tab("Modifiers", "pnModifiers")
            self.preset_tabs["pnCombat"] = self._create_scrollable_tab("Atk/Dmg", "pnCombat")
            self.preset_tabs["pnSave"] = self._create_scrollable_tab("Save", "pnSave")
            self.preset_tabs["pnSkill"] = self._create_scrollable_tab("Skill", "pnSkill")
            self.preset_tabs["pnOther"] = self._create_scrollable_tab("Other", "pnOther")
            self.table_host = self._create_scrollable_tab("Tables", "pnTables")
            self.variable_host = self._create_scrollable_tab("Variables", "pnConst")
            self.history_host = self._create_scrollable_tab("History", "pnHistory")

            self._relayout_modifier_tab()
            for tname in ("pnCombat", "pnSave", "pnSkill", "pnOther"):
                self._relayout_preset_tab(tname)
            self._relayout_table_tab()
            self._relayout_variable_tab()
            self._relayout_history_tab()

            self.split_win.addWidget(self.chatwindow)
            self.split_win.addWidget(self.tab_panel)
            self.split_win.setStretchFactor(0, 3)
            self.split_win.setStretchFactor(1, 2)

        def _create_scrollable_tab(self, title: str, object_name: str) -> QWidget:
            scroll = QScrollArea(self.notebook)
            scroll.setWidgetResizable(True)
            host = QWidget(scroll)
            host.setObjectName(object_name)
            grid = QGridLayout(host)
            grid.setContentsMargins(6, 6, 6, 6)
            grid.setSpacing(4)
            grid.setAlignment(Qt.AlignmentFlag.AlignTop)
            self.preset_grids[object_name] = grid
            scroll.setWidget(host)
            self.notebook.addTab(scroll, title)
            return host

        # ------------------------------------------------------------------
        # Row Layout Helpers
        # ------------------------------------------------------------------
        def _clear_grid_buttons(self, tab_name: str, grid: QGridLayout) -> None:
            for w in self._tab_row_buttons.get(tab_name, []):
                grid.removeWidget(w)
                w.deleteLater()
            self._tab_row_buttons[tab_name] = []

        @staticmethod
        def _clear_grid_layout(grid: QGridLayout) -> None:
            while grid.count():
                grid.takeAt(0)

        def _make_icon_btn(
            self,
            parent: QWidget,
            tab_name: str,
            text: str,
            tooltip: str,
            slot: Any,
            std_icon: QStyle.StandardPixmap | None = None,
            b64_icon: bytes | None = None,
        ) -> QPushButton:
            btn = QPushButton(parent)
            btn.setFixedSize(24, 24)
            btn.setToolTip(tooltip)
            if b64_icon is not None:
                btn.setIcon(load_qicon(b64_icon))
            elif std_icon is not None:
                btn.setIcon(self.style().standardIcon(std_icon))
            else:
                btn.setText(text)
            btn.clicked.connect(slot)
            self._tab_row_buttons[tab_name].append(btn)
            return btn

        def _relayout_variable_tab(self) -> None:
            tab_name = "pnConst"
            host = self.variable_host
            grid = self.preset_grids[tab_name]
            self._clear_grid_buttons(tab_name, grid)
            self._clear_grid_layout(grid)

            lbl_name = QLabel("Name", host)
            lbl_val = QLabel("Value", host)
            self._tab_row_buttons[tab_name].extend([lbl_name, lbl_val])
            grid.addWidget(lbl_name, 0, 1)
            grid.addWidget(lbl_val, 0, 2)
            grid.setColumnStretch(1, 3)
            grid.setColumnStretch(2, 7)

            for idx, vrow in enumerate(self.variables):
                row_num = idx + 1
                del_btn = self._make_icon_btn(
                    host,
                    tab_name,
                    "-",
                    "Delete variable",
                    lambda _c=False, i=idx: self.variable_delete(i),
                )
                ins_btn = self._make_icon_btn(
                    host,
                    tab_name,
                    "+",
                    "Insert variable before this row",
                    lambda _c=False, i=idx: self.variable_insert(i),
                )
                grid.addWidget(del_btn, row_num, 0)
                grid.addWidget(vrow.name, row_num, 1)
                grid.addWidget(vrow.val, row_num, 2)
                grid.addWidget(ins_btn, row_num, 3)

            add_btn = self._make_icon_btn(
                host,
                tab_name,
                "+",
                "Append variable",
                lambda _c=False: self.variable_append(),
            )
            grid.addWidget(add_btn, len(self.variables) + 1, 3)

        def _relayout_modifier_tab(self) -> None:
            tab_name = "pnModifiers"
            host = self.modifier_host
            grid = self.preset_grids[tab_name]
            self._clear_grid_buttons(tab_name, grid)
            self._clear_grid_layout(grid)

            headers = (
                (1, "Act"),
                (2, "Source"),
                (3, "Type"),
                (4, "Label Match"),
                (5, "Modifier"),
            )
            for col, text in headers:
                lbl = QLabel(text, host)
                self._tab_row_buttons[tab_name].append(lbl)
                grid.addWidget(lbl, 0, col)
            grid.setColumnStretch(2, 4)
            grid.setColumnStretch(4, 3)
            grid.setColumnStretch(5, 2)

            for idx, mrow in enumerate(self.modifiers):
                row_num = idx + 1
                del_btn = self._make_icon_btn(
                    host,
                    tab_name,
                    "-",
                    "Delete modifier",
                    lambda _c=False, i=idx: self.modifier_delete(i),
                )
                ins_btn = self._make_icon_btn(
                    host,
                    tab_name,
                    "+",
                    "Insert modifier before this row",
                    lambda _c=False, i=idx: self.modifier_insert(i),
                )
                grid.addWidget(del_btn, row_num, 0)
                grid.addWidget(mrow.active, row_num, 1, Qt.AlignmentFlag.AlignCenter)
                grid.addWidget(mrow.source, row_num, 2)
                grid.addWidget(mrow.mtype, row_num, 3)
                grid.addWidget(mrow.match, row_num, 4)
                grid.addWidget(mrow.mod, row_num, 5)
                grid.addWidget(ins_btn, row_num, 6)

            add_btn = self._make_icon_btn(
                host,
                tab_name,
                "+",
                "Append modifier",
                lambda _c=False: self.modifier_append(),
            )
            grid.addWidget(add_btn, len(self.modifiers) + 1, 6)

        def _relayout_preset_tab(self, tab_name: str) -> None:
            host = self.preset_tabs[tab_name]
            grid = self.preset_grids[tab_name]
            self._clear_grid_buttons(tab_name, grid)
            self._clear_grid_layout(grid)

            is_combat = tab_name == "pnCombat"
            offset = 1 if is_combat else 0
            headers: list[tuple[int, str]] = [
                (1 + offset, "Label"),
                (2 + offset, "Roll String"),
                (3 + offset, "Mod"),
                (4 + offset, "Roll/Stg"),
            ]
            if is_combat:
                headers.insert(0, (1, "Type"))
                headers.append((5, "Crit"))
                roll_col = 6
            else:
                roll_col = 4

            for col, text in headers:
                lbl = QLabel(text, host)
                self._tab_row_buttons[tab_name].append(lbl)
                if text == "Roll/Stg":
                    grid.addWidget(lbl, 0, roll_col, 1, 2)
                else:
                    grid.addWidget(lbl, 0, col)

            grid.setColumnStretch(1 + offset, 3)
            grid.setColumnStretch(2 + offset, 5)
            grid.setColumnStretch(3 + offset, 2)

            rows = self.presets[tab_name]
            for idx, prow in enumerate(rows):
                row_num = idx + 1
                del_btn = self._make_icon_btn(
                    host,
                    tab_name,
                    "-",
                    "Delete preset",
                    lambda _c=False, t=tab_name, i=idx: self.preset_delete(t, i),
                )
                roll_btn = self._make_icon_btn(
                    host,
                    tab_name,
                    "R",
                    "Roll preset",
                    lambda _c=False, t=tab_name, i=idx: self._on_preset_roll(t, i),
                    b64_icon=DICE_LT_PNG,
                )
                stage_btn = self._make_icon_btn(
                    host,
                    tab_name,
                    ">",
                    "Stage expression in message entry",
                    lambda _c=False, t=tab_name, i=idx: self._on_preset_stage(t, i),
                    std_icon=QStyle.StandardPixmap.SP_ArrowForward,
                )
                ins_btn = self._make_icon_btn(
                    host,
                    tab_name,
                    "+",
                    "Insert preset before this row",
                    lambda _c=False, t=tab_name, i=idx: self.preset_insert(t, i),
                )

                grid.addWidget(del_btn, row_num, 0)
                if is_combat and prow.ptype_combo is not None:
                    grid.addWidget(prow.ptype_combo, row_num, 1)
                grid.addWidget(prow.label_edit, row_num, 1 + offset)
                grid.addWidget(prow.expr_edit, row_num, 2 + offset)
                grid.addWidget(prow.mod_edit, row_num, 3 + offset)
                if is_combat and prow.crit_edit is not None:
                    grid.addWidget(prow.crit_edit, row_num, 5)
                grid.addWidget(roll_btn, row_num, roll_col)
                grid.addWidget(stage_btn, row_num, roll_col + 1)
                grid.addWidget(ins_btn, row_num, roll_col + 2)

            add_btn = self._make_icon_btn(
                host,
                tab_name,
                "+",
                "Append preset",
                lambda _c=False, t=tab_name: self.preset_append(t),
            )
            grid.addWidget(add_btn, len(rows) + 1, roll_col + 2)

        def _relayout_table_tab(self) -> None:
            tab_name = "pnTables"
            host = self.table_host
            grid = self.preset_grids[tab_name]
            self._clear_grid_buttons(tab_name, grid)
            self._clear_grid_layout(grid)

            headers = (
                (1, "Name"),
                (2, "Description"),
                (3, "Die Roll"),
                (4, "Mk"),
                (5, "Entries"),
                (6, "Actions"),
            )
            for col, text in headers:
                lbl = QLabel(text, host)
                self._tab_row_buttons[tab_name].append(lbl)
                if text == "Actions":
                    grid.addWidget(lbl, 0, 6, 1, 3)
                else:
                    grid.addWidget(lbl, 0, col)
            grid.setColumnStretch(1, 2)
            grid.setColumnStretch(2, 3)
            grid.setColumnStretch(3, 2)
            grid.setColumnStretch(5, 3)

            for idx, trow in enumerate(self.tables):
                row_num = idx + 1
                del_btn = self._make_icon_btn(
                    host,
                    tab_name,
                    "-",
                    "Delete table",
                    lambda _c=False, i=idx: self.table_delete(i),
                )
                edit_btn = self._make_icon_btn(
                    host,
                    tab_name,
                    "...",
                    "Edit lookup table rows",
                    lambda _c=False, i=idx: self.edit_table_entries(i),
                )
                roll_btn = self._make_icon_btn(
                    host,
                    tab_name,
                    "R",
                    "Roll lookup table",
                    lambda _c=False, i=idx: self._on_table_roll(i),
                    b64_icon=DICE_LT_PNG,
                )
                stage_btn = self._make_icon_btn(
                    host,
                    tab_name,
                    ">",
                    "Stage #table expression in message entry",
                    lambda _c=False, i=idx: self._on_table_stage(i),
                    std_icon=QStyle.StandardPixmap.SP_ArrowForward,
                )
                ins_btn = self._make_icon_btn(
                    host,
                    tab_name,
                    "+",
                    "Insert table before this row",
                    lambda _c=False, i=idx: self.table_insert(i),
                )
                grid.addWidget(del_btn, row_num, 0)
                grid.addWidget(trow.name_edit, row_num, 1)
                grid.addWidget(trow.desc_edit, row_num, 2)
                grid.addWidget(trow.dieroll_edit, row_num, 3)
                grid.addWidget(trow.markup_chk, row_num, 4, Qt.AlignmentFlag.AlignCenter)
                grid.addWidget(trow.summary_edit, row_num, 5)
                grid.addWidget(edit_btn, row_num, 6)
                grid.addWidget(roll_btn, row_num, 7)
                grid.addWidget(stage_btn, row_num, 8)
                grid.addWidget(ins_btn, row_num, 9)

            add_btn = self._make_icon_btn(
                host,
                tab_name,
                "+",
                "Append lookup table",
                lambda _c=False: self.table_append(),
            )
            grid.addWidget(add_btn, len(self.tables) + 1, 9)

        def _relayout_history_tab(self) -> None:
            tab_name = "pnHistory"
            host = self.history_host
            grid = self.preset_grids[tab_name]
            self._clear_grid_buttons(tab_name, grid)
            self._clear_grid_layout(grid)
            for w in self.history_widgets:
                w.deleteLater()
            self.history_widgets = []

            lbl_rs = QLabel("Roll/Stg", host)
            lbl_ex = QLabel("Expression", host)
            self._tab_row_buttons[tab_name].extend([lbl_rs, lbl_ex])
            grid.addWidget(lbl_rs, 0, 0, 1, 2)
            grid.addWidget(lbl_ex, 0, 2)
            grid.setColumnStretch(2, 1)

            for idx, expr in enumerate(self.history):
                row_num = idx + 1
                roll_btn = self._make_icon_btn(
                    host,
                    tab_name,
                    "R",
                    "Re-roll expression",
                    lambda _c=False, e=expr: self.chatwindow.roll_dice(e, history=False),
                    b64_icon=DICE_LT_PNG,
                )
                stage_btn = self._make_icon_btn(
                    host,
                    tab_name,
                    ">",
                    "Stage expression in message entry",
                    lambda _c=False, e=expr: self.chatwindow.stage_dice(e),
                    std_icon=QStyle.StandardPixmap.SP_ArrowForward,
                )
                edit = QLineEdit(expr, host)
                edit.setReadOnly(True)
                self.history_widgets.append(edit)
                grid.addWidget(roll_btn, row_num, 0)
                grid.addWidget(stage_btn, row_num, 1)
                grid.addWidget(edit, row_num, 2)

        # ------------------------------------------------------------------
        # Variable, Modifier, Preset & History API
        # ------------------------------------------------------------------
        def _get_variable_defs(self) -> dict[str, str]:
            if self.variables_changed or not self.variable_defs:
                self.update_variables_dictionary()
                self.clear_variables_changed()
            return self.variable_defs

        def update_variables_dictionary(self) -> None:
            """Rebuild the active variable dictionary from Variables tab rows."""
            self.variable_defs = {}
            for var in self.variables:
                name = var.value("name")
                if name:
                    self.variable_defs[name] = var.value("value")

        def variable_append(self, **data: Any) -> VariableRow:
            """Append a variable row to the Variables tab."""
            return self.variable_insert(len(self.variables), **data)

        def variable_insert(self, idx: int, **data: Any) -> VariableRow:
            """Insert a variable row at ``idx``."""
            row = VariableRow(self.variable_host, self._on_variable_row_changed, **data)
            self.variables.insert(idx, row)
            self._relayout_variable_tab()
            self.set_user_content_changed()
            return row

        def variable_delete(self, idx: int) -> None:
            """Delete variable row at ``idx``."""
            if 0 <= idx < len(self.variables):
                row = self.variables.pop(idx)
                for w in row.widgets():
                    w.deleteLater()
                self._relayout_variable_tab()
                self.set_variables_changed()
                self.set_user_content_changed()

        def variable_delete_all(self) -> None:
            """Remove all variable rows."""
            for row in self.variables:
                for w in row.widgets():
                    w.deleteLater()
            self.variables = []
            self.variable_defs = {}
            self._relayout_variable_tab()

        def _on_variable_row_changed(self) -> None:
            self.set_user_content_changed()
            self.set_variables_changed()

        def modifier_get_all(self) -> list[ModifierRow]:
            """Return all active/inactive modifier rows."""
            return self.modifiers

        def modifier_append(self, **data: Any) -> ModifierRow:
            """Append a modifier row to the Modifiers tab."""
            return self.modifier_insert(len(self.modifiers), **data)

        def modifier_insert(self, idx: int, **data: Any) -> ModifierRow:
            """Insert a modifier row at ``idx``."""
            row = ModifierRow(self.modifier_host, self._on_modifier_row_changed, **data)
            self.modifiers.insert(idx, row)
            self._relayout_modifier_tab()
            self.set_user_content_changed()
            return row

        def modifier_delete(self, idx: int) -> None:
            """Delete modifier row at ``idx``."""
            if 0 <= idx < len(self.modifiers):
                row = self.modifiers.pop(idx)
                for w in row.widgets():
                    w.deleteLater()
                self._relayout_modifier_tab()
                self.set_modifiers_changed()
                self.update_preset_modifiers()
                self.set_user_content_changed()

        def modifier_delete_all(self) -> None:
            """Remove all modifier rows."""
            for row in self.modifiers:
                for w in row.widgets():
                    w.deleteLater()
            self.modifiers = []
            self._relayout_modifier_tab()

        def _on_modifier_row_changed(self) -> None:
            self.set_user_content_changed()
            self.set_modifiers_changed()

        def update_preset_modifiers(self) -> None:
            """Recompute matching modifiers across all presets."""
            if self.loading_presets:
                return
            for tab_rows in self.presets.values():
                for pre in tab_rows:
                    pre.update_modifiers()

        def preset_append(self, tab_name: str, **data: Any) -> PresetRow:
            """Append a preset row to ``tab_name``."""
            return self.preset_insert(tab_name, len(self.presets[tab_name]), **data)

        def preset_insert(self, tab_name: str, idx: int, **data: Any) -> PresetRow:
            """Insert a preset row into ``tab_name`` at ``idx``."""
            row = PresetRow(
                parent=self.preset_tabs[tab_name],
                tab_name=tab_name,
                on_changed=self.set_user_content_changed,
                get_modifiers=self.modifier_get_all,
                **data,
            )
            self.presets[tab_name].insert(idx, row)
            self._relayout_preset_tab(tab_name)
            row.update_modifiers()
            self.set_user_content_changed()
            return row

        def preset_delete(self, tab_name: str, idx: int) -> None:
            """Delete preset row at ``idx`` from ``tab_name``."""
            rows = self.presets[tab_name]
            if 0 <= idx < len(rows):
                row = rows.pop(idx)
                for w in (row.ptype_combo, row.label_edit, row.expr_edit, row.mod_edit, row.crit_edit):
                    if w is not None:
                        w.deleteLater()
                self._relayout_preset_tab(tab_name)
                self.set_user_content_changed()

        def preset_delete_all(self) -> None:
            """Remove all preset rows across all category tabs."""
            for tab_name in list(self.presets.keys()):
                for row in self.presets[tab_name]:
                    for w in (row.ptype_combo, row.label_edit, row.expr_edit, row.mod_edit, row.crit_edit):
                        if w is not None:
                            w.deleteLater()
                self.presets[tab_name] = []
                self._relayout_preset_tab(tab_name)

        def _on_preset_roll(self, tab_name: str, idx: int) -> None:
            expr = self.presets[tab_name][idx].roll_expression()
            if expr:
                self.chatwindow.roll_dice(expr=expr)

        def _on_preset_stage(self, tab_name: str, idx: int) -> None:
            expr = self.presets[tab_name][idx].roll_expression()
            if expr:
                self.chatwindow.stage_dice(expr)

        def table_append(self, **data: Any) -> TableRow:
            """Append a lookup table row to the Tables tab."""
            return self.table_insert(len(self.tables), **data)

        def table_insert(self, idx: int, **data: Any) -> TableRow:
            """Insert a lookup table row into the Tables tab at ``idx``."""
            row = TableRow(self.table_host, self.set_user_content_changed, **data)
            self.tables.insert(idx, row)
            self._relayout_table_tab()
            self.set_user_content_changed()
            return row

        def table_delete(self, idx: int) -> None:
            """Delete lookup table row at ``idx``."""
            if 0 <= idx < len(self.tables):
                row = self.tables.pop(idx)
                for w in row.widgets():
                    w.deleteLater()
                self._relayout_table_tab()
                self.set_user_content_changed()

        def table_delete_all(self) -> None:
            """Remove all lookup table rows."""
            for row in self.tables:
                for w in row.widgets():
                    w.deleteLater()
            self.tables = []
            self._relayout_table_tab()

        def edit_table_entries(self, idx: int) -> EditLookupTableDialog | None:
            """Open the shared ``EditLookupTableDialog`` for table row ``idx``."""
            if not (0 <= idx < len(self.tables)):
                return None
            row = self.tables[idx]
            dlg = EditLookupTableDialog(
                dieroll=row.value("dieroll") or "1d20",
                flat_table=row.flat_table(),
                parent=self,
            )
            if dlg.exec() == QDialog.DialogCode.Accepted:
                flat = dlg.flat_table()
                pairs = [(flat[i], flat[i + 1]) for i in range(0, len(flat) - 1, 2)]
                row.set_dieroll(dlg.dieroll())
                row.set_pairs(pairs)
            return dlg

        def _on_table_roll(self, idx: int) -> None:
            if 0 <= idx < len(self.tables):
                expr = self.tables[idx].roll_expression()
                if expr:
                    self.chatwindow.roll_dice(expr=expr)

        def _on_table_stage(self, idx: int) -> None:
            if 0 <= idx < len(self.tables):
                expr = self.tables[idx].roll_expression()
                if expr:
                    self.chatwindow.stage_dice(expr)

        def get_table_bank(self) -> DicePresetBank:
            """Build a merged ``DicePresetBank`` combining server presets and local Tables rows."""
            tkey = str(getattr(self.service, "username", "") or "local")
            bank = DicePresetBank(tkey=tkey)
            if self.server_bank.system_presets:
                bank.set_system_presets(self.server_bank.system_presets)

            local_user_tables: list[dict[str, Any]] = []
            for idx, trow in enumerate(self.tables, start=1):
                encoded = trow.to_gma_preset(seq=idx)
                if encoded is not None:
                    local_user_tables.append(encoded)
            merged_user = merge_preset_lists(self.server_bank.user_presets, local_user_tables)
            if merged_user:
                bank.set_user_presets(merged_user)
            return bank

        def _on_server_presets_received(self, cmd: str, payload: dict[str, Any]) -> None:
            presets = payload.get("Presets", payload.get("List", []))
            if not isinstance(presets, list):
                return
            is_global = bool(payload.get("Global", False))
            for_user = str(payload.get("For", "") or "")
            append_mode = cmd == "DD+"
            if is_global:
                sys_list = (
                    merge_preset_lists(self.server_bank.system_presets, presets)
                    if append_mode
                    else presets
                )
                self.server_bank.set_system_presets(sys_list)
            elif not for_user or for_user == self.service.username:
                user_list = (
                    merge_preset_lists(self.server_bank.user_presets, presets)
                    if append_mode
                    else presets
                )
                self.server_bank.set_user_presets(user_list)

        def history_add(self, expr: str) -> None:
            """Record ``expr`` at the top of History tab (max 20 unique most recent)."""
            if not expr or (self.history and self.history[0] == expr):
                return
            if len(self.history) >= self.max_history:
                del self.history[self.max_history - 1 :]
            self.history.insert(0, expr)
            self._relayout_history_tab()

        # ------------------------------------------------------------------
        # Dirty State & Menu Callbacks
        # ------------------------------------------------------------------
        def set_variables_changed(self) -> None:
            self.variables_changed = True

        def clear_variables_changed(self) -> None:
            self.variables_changed = False

        def set_modifiers_changed(self) -> None:
            self.modifiers_changed = True

        def clear_modifiers_changed(self) -> None:
            self.modifiers_changed = False

        def set_user_content_changed(self) -> None:
            """Mark preset/modifier/variable content modified unless loading."""
            if self.loading_presets or self.unsaved_changes:
                return
            self.setWindowTitle(f"{APP_NAME}*")
            self.unsaved_changes = True

        def clear_user_content_changed(self) -> None:
            """Clear the unsaved-changes flag and window title marker."""
            if not self.unsaved_changes:
                return
            self.setWindowTitle(APP_NAME)
            self.unsaved_changes = False

        def _on_notebook_page_changed(self, _index: int) -> None:
            if self.modifiers_changed:
                self.update_preset_modifiers()
                self.clear_modifiers_changed()

        def open_preferences(self) -> SettingsDialog:
            """Open the Preferences modal dialog."""
            dlg = SettingsDialog(self.settings, self)
            dlg.servers_changed.connect(lambda _names: self._rebuild_server_menu())
            dlg.styles_changed.connect(self.chatwindow.stylesheet_changed)
            dlg.exec()
            return dlg

        def on_menu_view_chat(self, checked: bool) -> None:
            """Show or hide the Chat panel inside the main splitter."""
            self.chatwindow.setVisible(bool(checked))

        def on_layout_h(self) -> None:
            """Arrange Chat panel and preset tabs side-by-side horizontally."""
            self.chat_layout = L_HORIZONTAL
            self.split_win.setOrientation(Qt.Orientation.Horizontal)

        def on_layout_v(self) -> None:
            """Arrange Chat panel and preset tabs vertically."""
            self.chat_layout = L_VERTICAL
            self.split_win.setOrientation(Qt.Orientation.Vertical)

        def _rebuild_server_menu(self) -> None:
            for act in self._server_actions:
                self.server_menu.removeAction(act)
                act.deleteLater()
            self._server_actions = []

            for name in sorted(self.settings.server_names()):
                act = QAction(name, self)
                act.triggered.connect(lambda _c=False, n=name: self.on_menu_server_connect_to(n))
                self.server_menu.addAction(act)
                self._server_actions.append(act)

            self.act_server_connect.setEnabled(
                self.settings.last_server() is not None and not self.service.connected()
            )

        def on_menu_server_connect(self) -> None:
            srv = self.settings.last_server()
            if srv is None:
                self.act_server_connect.setEnabled(False)
                return
            self.service.connect_server(srv)

        def on_menu_server_connect_to(self, name: str) -> None:
            srv = self.settings.server(name)
            if srv is not None and self.service.connect_server(srv):
                self.settings.set_last_server(name)

        def on_menu_server_disconnect(self) -> None:
            self.service.disconnect_server()

        def _on_connect_state_changed(self, is_connected: bool, _server: dict[str, Any]) -> None:
            self.act_server_disconnect.setEnabled(is_connected)
            self.act_server_connect.setEnabled(
                (not is_connected) and (self.settings.last_server() is not None)
            )
            self.chatwindow.set_connected(is_connected)

        def on_help_about(self) -> QDialog:
            """Show the About GMA Die Roller dialog."""
            dlg = QDialog(self)
            dlg.setWindowTitle(f"About {APP_NAME}")
            vbox = QVBoxLayout(dlg)
            vbox.setContentsMargins(24, 20, 24, 16)
            vbox.setSpacing(10)

            icon_lbl = QLabel(dlg)
            icon_lbl.setPixmap(load_qpixmap(DICE_LARGE_PNG, size=64))
            icon_lbl.setAlignment(Qt.AlignmentFlag.AlignCenter)
            vbox.addWidget(icon_lbl)

            title_lbl = QLabel(APP_NAME, dlg)
            tfnt = title_lbl.font()
            tfnt.setBold(True)
            tfnt.setPointSize(max(12, tfnt.pointSize() + 2))
            title_lbl.setFont(tfnt)
            title_lbl.setAlignment(Qt.AlignmentFlag.AlignCenter)
            vbox.addWidget(title_lbl)

            ver_lbl = QLabel(f"Version {APP_VERSION}", dlg)
            ver_lbl.setAlignment(Qt.AlignmentFlag.AlignCenter)
            vbox.addWidget(ver_lbl)

            copy_lbl = QLabel("(c) 2020 John Mechalas (PySide6 Port)", dlg)
            copy_lbl.setAlignment(Qt.AlignmentFlag.AlignCenter)
            vbox.addWidget(copy_lbl)

            ok_btn = QPushButton("OK", dlg)
            ok_btn.clicked.connect(dlg.accept)
            vbox.addWidget(ok_btn, alignment=Qt.AlignmentFlag.AlignCenter)
            dlg.exec()
            return dlg

        def alert(self, caption: str = "Alert", message: str = "An error occurred") -> None:
            """Display a modal error message box."""
            QMessageBox.critical(self, caption, message)

        # ------------------------------------------------------------------
        # Presets Load / Save / GMA .dice Import
        # ------------------------------------------------------------------
        def find_presets_file(self) -> Path | None:
            """Search default ``presets.json`` locations matching legacy search order."""
            candidates = [
                Path("presets.json"),
                self.settings.filename.parent / "presets.json",
                Path.home() / ".dieroller" / "presets.json",
            ]
            for path in candidates:
                try:
                    if path.is_file():
                        return path
                except OSError:
                    continue
            return None

        def save_presets(self, choosefile: bool = False, filepath: str | Path | None = None) -> bool:
            """Atomically write presets, modifiers, and variables to a JSON presets file."""
            caption = "Can't save presets"
            if filepath is not None:
                target = Path(filepath)
            elif choosefile or self.presets_filename is None:
                chosen, _ = QFileDialog.getSaveFileName(
                    self, "Save presets", "", "Die Roller Presets (*.json)"
                )
                if not chosen:
                    return False
                target = Path(chosen)
                if target.name == "settings.json":
                    self.alert(caption, "Attempted to save dice presets over settings file.")
                    return False
            else:
                target = self.presets_filename

            data: dict[str, Any] = {"presets": [], "mods": [], "variables": [], "tables": []}
            for tab_rows in self.presets.values():
                for prow in tab_rows:
                    data["presets"].append(prow.to_dict())
            for mrow in self.modifiers:
                data["mods"].append(mrow.to_dict())
            for vrow in self.variables:
                data["variables"].append(vrow.to_dict())
            for trow in self.tables:
                data["tables"].append(trow.to_dict())

            try:
                target.parent.mkdir(parents=True, exist_ok=True)
                payload = json.dumps(data, indent=4) + "\n"
                # Atomic temp-file write + os.replace prevents truncated presets files.
                fd, tmp_name = tempfile.mkstemp(
                    prefix=".presets_", suffix=".tmp", dir=str(target.parent)
                )
                try:
                    with os.fdopen(fd, "w", encoding="utf-8") as fh:
                        fh.write(payload)
                    os.replace(tmp_name, target)
                except Exception:
                    try:
                        os.unlink(tmp_name)
                    except OSError:
                        pass
                    raise
            except Exception as exc:  # pylint: disable=broad-exception-caught
                self.alert(caption, str(exc))
                return False

            self.presets_filename = target
            self.clear_user_content_changed()
            return True

        def load_presets(
            self,
            choosefile: bool = False,
            filepath: str | Path | None = None,
        ) -> bool:
            """Load presets, modifiers, and variables from JSON."""
            caption = "Can't load presets"
            if filepath is not None:
                target = Path(filepath)
            elif choosefile:
                chosen, _ = QFileDialog.getOpenFileName(
                    self, "Open presets", "", "Die Roller Presets (*.json)"
                )
                if not chosen:
                    return False
                target = Path(chosen)
            else:
                found = self.find_presets_file()
                if found is None:
                    return False
                target = found

            try:
                data = json.loads(target.read_text(encoding="utf-8"))
            except (OSError, ValueError) as exc:
                self.alert(caption, f"{target}: {exc}")
                return False

            self.presets_filename = target
            if choosefile or filepath is not None:
                self.preset_delete_all()
                self.modifier_delete_all()
                self.variable_delete_all()
                self.table_delete_all()

            self.loading_presets = True
            try:
                for preset in data.get("presets", []):
                    ptype = str(preset.get("ptype") or "")
                    tab = PRESET_TAB_BY_TYPE.get(ptype)
                    if tab is None:
                        continue
                    self.preset_append(tab, **preset)
                for mod in data.get("mods", []):
                    mtype = str(mod.get("mtype") or "")
                    if mtype not in MODIFIER_TYPES:
                        continue
                    self.modifier_append(**mod)
                for var in data.get("variables", []):
                    self.variable_append(**var)
                for tbl in data.get("tables", []):
                    if isinstance(tbl, dict):
                        self.table_append(**normalize_table_dict(tbl))
            finally:
                self.loading_presets = False

            self.clear_user_content_changed()
            self.update_variables_dictionary()
            self.update_preset_modifiers()
            return True

        def import_gma(self, filepath: str | Path | None = None) -> int:
            """Import a GMA Mapper ``.dice`` preset file into category tabs."""
            if filepath is None:
                chosen, _ = QFileDialog.getOpenFileName(
                    self, "Import GMA presets", "", "GMA dice presets (*.dice)"
                )
                if not chosen:
                    return 0
                target = Path(chosen)
            else:
                target = Path(filepath)

            try:
                _meta, raw_presets = load_dice_presets_from_file(target)
            except Exception as exc:  # pylint: disable=broad-exception-caught
                self.alert("Can't import presets", str(exc))
                return 0

            imported = 0
            for raw in raw_presets:
                parsed_tbl = parse_gma_table_preset(raw)
                if parsed_tbl is not None:
                    self.table_append(**parsed_tbl)
                    imported += 1
                    continue
                parsed = parse_gma_preset(raw)
                tab = PRESET_TAB_BY_TYPE.get(parsed["ptype"], "pnOther")
                self.preset_append(tab, **parsed)
                imported += 1
            return imported

        def closeEvent(self, event: QCloseEvent) -> None:
            if self.unsaved_changes:
                ans = QMessageBox.question(
                    self,
                    "Exit without saving",
                    "You have unsaved changes. Are you sure you want to exit?",
                    QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                    QMessageBox.StandardButton.No,
                )
                if ans != QMessageBox.StandardButton.Yes:
                    event.ignore()
                    return
            self.service.disconnect_server()
            self.settings.save(quiet=True)
            super().closeEvent(event)
