"""Chat, Pinned Messages, Recent Rolls, and Hierarchical Preset Die-Roller dock panel (`PySide6`).

Ported from `bin/mapper_legacy.tcl` (`_render_die_roller`, `SendDieRoll`, `_do_roll`,
`DisplayDieRoll`, `DisplayChatMessage`, `_render_chat_message`, `UpdatePeerList`,
`ClearChatHistory`, `PruneChatHistory`).
"""

from __future__ import annotations

from pathlib import Path
from typing import Any, Callable

from gma_mapper.core.dice import (
    ChatHistoryManager,
    DicePresetBank,
    RollStatCollector,
    cleanup_die_roll_spec,
    merge_preset_lists,
    prepare_die_roll,
    render_chat_payload_html,
    render_roll_payload_html,
)
from gma_mapper.core.file_io import load_dice_presets_from_file, save_dice_presets_to_file
from gma_mapper.core.minimarkup import render_html as render_minimarkup_html
from gma_mapper.core.profile import default_preferences, default_styles

try:
    from PySide6.QtCore import QUrl, Qt, Signal
    from PySide6.QtGui import QAction
    from PySide6.QtWidgets import (
        QCheckBox,
        QDialog,
        QFileDialog,
        QFrame,
        QGroupBox,
        QHBoxLayout,
        QLabel,
        QLineEdit,
        QMenu,
        QMessageBox,
        QPushButton,
        QScrollArea,
        QSplitter,
        QTextBrowser,
        QToolButton,
        QVBoxLayout,
        QWidget,
    )

    from gma_mapper.ui.dialogs.dice_dialogs import (
        DiceSyntaxHelpDialog,
        EditColorBoxTitleDialog,
        EditDieRollPresetsDialog,
        QuickSavePresetDialog,
    )

    QT_AVAILABLE = True
except ImportError:  # pragma: no cover
    QT_AVAILABLE = False


def _comp_style(
    styles: dict[str, Any] | None,
    comp: str,
    dark: bool = True,
) -> tuple[str, str, bool, bool]:
    base = (styles or default_styles()).get("dierolls", {}).get("components", {})
    cdict = base.get(comp, base.get("default", {}))
    theme = "dark" if dark else "light"
    colors = cdict.get(theme, {})
    fg = colors.get("fg", "#ffffff" if dark else "#000000")
    bg = colors.get("bg", "")
    bold = bool(cdict.get("bold", False))
    italic = bool(cdict.get("italic", False))
    return fg, bg, bold, italic


def _styled_span(
    text: str,
    comp: str,
    styles: dict[str, Any] | None = None,
    dark: bool = True,
) -> str:
    fg, bg, bold, italic = _comp_style(styles, comp, dark)
    css = [f"color:{fg}"]
    if bg:
        css.append(f"background-color:{bg}")
    if bold:
        css.append("font-weight:bold")
    if italic:
        css.append("font-style:italic")
    style_str = ";".join(css)
    return f'<span style="{style_str}">{text}</span>'


def format_roll_result(
    payload: dict[str, Any],
    styles: dict[str, Any] | None = None,
    dark: bool = True,
) -> str:
    """Format a `ROLL` server payload into styled HTML spans."""
    if (isinstance(payload.get("Result"), dict) or "RollData" in payload) and "Results" not in payload:
        return render_roll_payload_html(payload, prefs={"styles": styles} if styles else None, dark=dark)

    origin = str(payload.get("Origin", payload.get("User", "Unknown")))
    targets = payload.get("Targets", payload.get("Recipients", []))
    title = str(payload.get("Title", ""))
    results = payload.get("Results", [])

    parts: list[str] = [_styled_span(f"[{origin}]", "origin", styles, dark)]
    if targets:
        t_str = ", ".join(str(t) for t in targets)
        parts.append(_styled_span(f" \u2192 {t_str}", "target", styles, dark))
    if title:
        parts.append(" " + _styled_span(render_minimarkup_html(title), "title", styles, dark))

    if isinstance(results, list) and results:
        res_strs: list[str] = []
        for r in results:
            if isinstance(r, dict):
                val = r.get("Value", r.get("Result", ""))
                details = r.get("Details", r.get("Components", []))
                comp_parts: list[str] = []
                for c in details:
                    if isinstance(c, dict):
                        ctype = str(c.get("Type", "default"))
                        cval = str(c.get("Value", c.get("Text", "")))
                        comp_parts.append(_styled_span(cval, ctype, styles, dark))
                    else:
                        comp_parts.append(str(c))
                detail_html = " ".join(comp_parts)
                val_html = _styled_span(f"={val}", "result", styles, dark)
                res_strs.append(f"{detail_html} {val_html}".strip())
            else:
                res_strs.append(_styled_span(str(r), "result", styles, dark))
        parts.append(": " + "; ".join(res_strs))
    elif "Result" in payload or "Value" in payload:
        val = payload.get("Result", payload.get("Value", ""))
        spec = payload.get("RollSpec", payload.get("Spec", ""))
        if spec:
            parts.append(f": {_styled_span(str(spec), 'default', styles, dark)} ")
        parts.append(_styled_span(f"={val}", "result", styles, dark))

    return "".join(parts)


def format_chat_message(
    payload: dict[str, Any],
    styles: dict[str, Any] | None = None,
    dark: bool = True,
) -> str:
    """Format a `TO` (chat message) server payload into styled HTML."""
    origin = str(payload.get("Origin", payload.get("From", payload.get("Sender", "Server"))))
    targets = payload.get("Targets", payload.get("Recipients", []))
    text = str(payload.get("Text", payload.get("Message", "")))
    is_gm = bool(payload.get("ToGM", False))

    parts: list[str] = [_styled_span(f"&lt;{origin}&gt;", "origin", styles, dark)]
    if is_gm:
        parts.append(" " + _styled_span("(to GM)", "GM", styles, dark))
    elif targets:
        t_str = ", ".join(str(t) for t in targets)
        parts.append(" " + _styled_span(f"(to {t_str})", "target", styles, dark))

    rendered_body = render_minimarkup_html(text)
    parts.append(": " + _styled_span(rendered_body, "chat", styles, dark))
    return "".join(parts)


if QT_AVAILABLE:

    class ChatDicePanel(QWidget):
        """Interactive Chat, Pinned Messages, Recent Rolls, and Preset Die-Roller panel."""

        # Legacy 4-arg signals preserved for backward compatibility
        send_chat_requested = Signal(str, list, bool, bool)  # text, recipients, to_all, to_gm
        send_roll_requested = Signal(str, list, bool, bool)  # roll_spec, recipients, to_all, to_gm
        rollRequested = Signal(str, str, list)  # title, spec, targets (legacy alias)
        chatSent = Signal(str, list)  # text, targets (legacy alias)

        # Extended signals carrying Markup/Pin and RequestID/Preset management
        send_chat_ex_requested = Signal(str, list, bool, bool, bool, bool)  # text, recipients, to_all, to_gm, markup, pin
        send_roll_ex_requested = Signal(str, list, bool, bool, str)  # roll_spec, recipients, to_all, to_gm, request_id
        save_presets_requested = Signal(list, bool, str)  # presets, is_global, for_user
        append_presets_requested = Signal(list, bool, str)  # presets, is_global, for_user (`DD+`)
        refresh_presets_requested = Signal(str)  # for_user
        refresh_peers_requested = Signal()
        delete_message_requested = Signal(int)  # msg_id (GM server-wide delete)

        def __init__(
            self,
            parent: QWidget | None = None,
            tkey: str = "",
            for_user: str = "",
            local_user: str = "",
            prefs: dict[str, Any] | None = None,
            shared_gvar_state: dict[str, bool] | None = None,
            roll_only: bool = False,
        ) -> None:
            super().__init__(parent)
            self.tkey: str = tkey
            self.for_user: str = for_user
            self.local_user: str = local_user
            self.is_gm: bool = (local_user == "GM")
            self.roll_only: bool = bool(roll_only)
            self.prefs: dict[str, Any] = prefs or default_preferences()
            self.dark: bool = bool(self.prefs.get("dark", True))

            self.bank = DicePresetBank(tkey=tkey)
            if shared_gvar_state is not None:
                self.bank.sys_gvar_on = shared_gvar_state

            self.history_manager = ChatHistoryManager()
            self.stat_collector = RollStatCollector()
            self.recent_rolls: list[str] = []
            self._req_seq: int = 0
            self._peer_names: list[str] = []
            self._selected_recipients: set[str] = set()
            self._recip_mode: str = "all"  # "all" | "gm" | "custom"

            # Optional callback returning `(my_names, mobs_by_id, mobs_by_name)` from MapperController
            self.target_context_provider: Callable[
                [], tuple[list[str], dict[str, dict[str, Any]], dict[str, str]]
            ] | None = None

            self._build_ui()

        @property
        def presets(self) -> list[dict[str, Any]]:
            """Return combined raw presets (backward-compatible property)."""
            return self.bank.all_raw_presets(include_system=bool(self.bank.system_presets))

        @presets.setter
        def presets(self, value: list[dict[str, Any]]) -> None:
            self.set_presets(value)

        def _build_ui(self) -> None:
            root_layout = QVBoxLayout(self)
            root_layout.setContentsMargins(4, 4, 4, 4)
            root_layout.setSpacing(4)

            self.main_splitter = QSplitter(Qt.Orientation.Vertical, self)
            root_layout.addWidget(self.main_splitter, stretch=1)

            # --- Pane 1: Pinned Messages (auto-shown when pinned messages exist) ---
            self.pinned_group = QGroupBox("Pinned Messages", self.main_splitter)
            pinned_layout = QVBoxLayout(self.pinned_group)
            pinned_layout.setContentsMargins(4, 4, 4, 4)
            self.pinned_log = QTextBrowser(self.pinned_group)
            self.pinned_log.setOpenExternalLinks(False)
            self.pinned_log.anchorClicked.connect(self._on_chat_anchor_clicked)
            self.pinned_log.setMaximumHeight(120)
            pinned_layout.addWidget(self.pinned_log)
            self.pinned_group.setVisible(False)
            if not self.roll_only:
                self.main_splitter.addWidget(self.pinned_group)

            # --- Pane 2: Chat Log + Chat & Roll Entry Controls ---
            self.chat_container = QWidget(self.main_splitter)
            chat_vbox = QVBoxLayout(self.chat_container)
            chat_vbox.setContentsMargins(0, 0, 0, 0)
            chat_vbox.setSpacing(4)

            self.chat_log = QTextBrowser(self.chat_container)
            self.chat_log.setOpenExternalLinks(False)
            self.chat_log.anchorClicked.connect(self._on_chat_anchor_clicked)
            if self.roll_only:
                self.chat_log.setVisible(False)
            else:
                chat_vbox.addWidget(self.chat_log, stretch=1)

            # Recipient & Chat Input Bar
            self.chat_bar_widget = QWidget(self.chat_container)
            chat_row = QHBoxLayout(self.chat_bar_widget)
            chat_row.setContentsMargins(0, 0, 0, 0)
            chat_row.setSpacing(4)

            self.to_menu_btn = QToolButton(self.chat_bar_widget)
            self.to_menu_btn.setText("To: (all)")
            self.to_menu_btn.setPopupMode(QToolButton.ToolButtonPopupMode.InstantPopup)
            self.to_menu = QMenu(self.to_menu_btn)
            self.to_menu_btn.setMenu(self.to_menu)
            self._rebuild_recipient_menu()

            # Maintain `target_combo` alias for backward compatibility with older tests
            self.target_combo = self._create_compat_target_combo()

            self.chat_entry = QLineEdit(self.chat_bar_widget)
            self.chat_entry.setPlaceholderText("Chat message (or /r 1d20+5)...")
            self.chat_entry.returnPressed.connect(self._on_send_chat)

            self.markup_btn = QToolButton(self.chat_bar_widget)
            self.markup_btn.setText("M")
            self.markup_btn.setCheckable(True)
            self.markup_btn.setToolTip("Enable rich text markup (**bold**, //italic//, __underline__, `code`)")

            self.pin_btn = QToolButton(self.chat_bar_widget)
            self.pin_btn.setText("\u2605")
            self.pin_btn.setCheckable(True)
            self.pin_btn.setToolTip("Pin this chat message for all players")

            self.send_btn = QPushButton("Send", self.chat_bar_widget)
            self.send_btn.clicked.connect(self._on_send_chat)

            chat_row.addWidget(self.to_menu_btn)
            chat_row.addWidget(self.chat_entry, stretch=1)
            chat_row.addWidget(self.markup_btn)
            chat_row.addWidget(self.pin_btn)
            chat_row.addWidget(self.send_btn)
            if self.roll_only:
                self.chat_bar_widget.setVisible(False)
            else:
                chat_vbox.addWidget(self.chat_bar_widget)

            # Ad-hoc Die Roll Input Bar
            roll_row = QHBoxLayout()
            roll_row.setContentsMargins(0, 0, 0, 0)
            roll_row.setSpacing(4)

            self.colorbox_btn = QToolButton(self.chat_container)
            self.colorbox_btn.setText("\U0001f3a8")
            self.colorbox_btn.setToolTip("Edit multi-segment Color-Box Title for this roll...")
            self.colorbox_btn.clicked.connect(self._on_edit_roll_entry_colorbox)

            self.roll_entry = QLineEdit(self.chat_container)
            self.roll_entry.setPlaceholderText("Die roll (e.g. Attack=1d20+7 1d8+4 |c, or #table)")
            self.roll_entry.returnPressed.connect(self._on_send_roll)

            self.gm_only_chk = QCheckBox("GM", self.chat_container)
            self.gm_only_chk.setToolTip("Send blind roll only to the Game Master")

            self.roll_btn = QPushButton("Roll", self.chat_container)
            self.roll_btn.clicked.connect(self._on_send_roll)

            self.save_roll_preset_btn = QToolButton(self.chat_container)
            self.save_roll_preset_btn.setText("Save Preset...")
            self.save_roll_preset_btn.setToolTip("Save this die roll as a preset on the GMA server")
            self.save_roll_preset_btn.clicked.connect(
                lambda: self.open_quick_save_preset(self.roll_entry.text())
            )

            self.syntax_help_btn = QToolButton(self.chat_container)
            self.syntax_help_btn.setText("?")
            self.syntax_help_btn.setToolTip("Show Die Roller Syntax Reference")
            self.syntax_help_btn.clicked.connect(self._on_show_syntax_help)

            roll_row.addWidget(self.colorbox_btn)
            roll_row.addWidget(QLabel("Roll:"))
            roll_row.addWidget(self.roll_entry, stretch=1)
            roll_row.addWidget(self.gm_only_chk)
            roll_row.addWidget(self.roll_btn)
            roll_row.addWidget(self.save_roll_preset_btn)
            roll_row.addWidget(self.syntax_help_btn)
            chat_vbox.addLayout(roll_row)

            self.main_splitter.addWidget(self.chat_container)

            # --- Pane 3: Recent Rolls (up to 10 entries) ---
            self.recent_group = QGroupBox("Recent Rolls", self.main_splitter)
            recent_outer = QVBoxLayout(self.recent_group)
            recent_outer.setContentsMargins(4, 4, 4, 4)
            recent_outer.setSpacing(2)

            self.recent_scroll = QScrollArea(self.recent_group)
            self.recent_scroll.setWidgetResizable(True)
            self.recent_scroll.setFrameShape(QFrame.Shape.NoFrame)
            self.recent_list_host = QWidget(self.recent_scroll)
            self.recent_list_layout = QVBoxLayout(self.recent_list_host)
            self.recent_list_layout.setContentsMargins(0, 0, 0, 0)
            self.recent_list_layout.setSpacing(2)
            self.recent_list_layout.addStretch(1)
            self.recent_scroll.setWidget(self.recent_list_host)
            recent_outer.addWidget(self.recent_scroll)
            self.recent_group.setMaximumHeight(150)
            self.main_splitter.addWidget(self.recent_group)

            # --- Pane 4: Preset Rolls (hierarchical groups, tables, modifiers, presets) ---
            self.presets_group = QGroupBox(
                f"Preset Rolls ({self.for_user})" if self.for_user else "Preset Rolls",
                self.main_splitter,
            )
            presets_outer = QVBoxLayout(self.presets_group)
            presets_outer.setContentsMargins(4, 4, 4, 4)
            presets_outer.setSpacing(4)

            self.presets_scroll = QScrollArea(self.presets_group)
            self.presets_scroll.setWidgetResizable(True)
            self.presets_scroll.setFrameShape(QFrame.Shape.NoFrame)
            self.presets_host = QWidget(self.presets_scroll)
            self.presets_layout = QVBoxLayout(self.presets_host)
            self.presets_layout.setContentsMargins(0, 0, 0, 0)
            self.presets_layout.setSpacing(2)
            self.presets_layout.addStretch(1)
            self.presets_scroll.setWidget(self.presets_host)
            presets_outer.addWidget(self.presets_scroll, stretch=1)

            # Bottom Preset Management Toolbar
            toolbar_row = QHBoxLayout()
            toolbar_row.setContentsMargins(0, 0, 0, 0)
            toolbar_row.setSpacing(4)

            self.btn_edit_presets = QPushButton("Edit...", self.presets_group)
            self.btn_edit_presets.setToolTip(
                "Edit die-roll presets, modifiers, variables, and lookup tables (saves to server)"
            )
            self.btn_edit_presets.clicked.connect(lambda: self.open_preset_editor(system_mode=False))

            self.btn_edit_sys_presets = QPushButton("System...", self.presets_group)
            self.btn_edit_sys_presets.setToolTip("Edit global system presets (saves to server, GM only)")
            self.btn_edit_sys_presets.clicked.connect(lambda: self.open_preset_editor(system_mode=True))
            self.btn_edit_sys_presets.setVisible(self.is_gm)

            self.btn_save_to_server = QPushButton("Save to Server", self.presets_group)
            self.btn_save_to_server.setToolTip("Save current die-roll presets to the GMA server")
            self.btn_save_to_server.clicked.connect(self.push_presets_to_server)

            self.btn_import_presets = QPushButton("Import File...", self.presets_group)
            self.btn_import_presets.setToolTip("Import presets from a local .dice file and save to server")
            self.btn_import_presets.clicked.connect(self.prompt_import_presets_from_file)

            self.btn_export_presets = QPushButton("Save to File...", self.presets_group)
            self.btn_export_presets.setToolTip("Save/export presets to a local .dice file on disk")
            self.btn_export_presets.clicked.connect(self._on_export_presets_clicked)

            self.btn_refresh_presets = QPushButton("Reload from Server", self.presets_group)
            self.btn_refresh_presets.setToolTip("Reload presets from the GMA server")
            self.btn_refresh_presets.clicked.connect(
                lambda: self.refresh_presets_requested.emit(self.for_user)
            )

            toolbar_row.addWidget(self.btn_edit_presets)
            toolbar_row.addWidget(self.btn_edit_sys_presets)
            toolbar_row.addWidget(self.btn_save_to_server)
            toolbar_row.addWidget(self.btn_import_presets)
            toolbar_row.addWidget(self.btn_export_presets)
            toolbar_row.addWidget(self.btn_refresh_presets)
            toolbar_row.addStretch(1)
            presets_outer.addLayout(toolbar_row)

            self.main_splitter.addWidget(self.presets_group)
            self.main_splitter.setStretchFactor(1, 3)
            self.main_splitter.setStretchFactor(3, 2)

            self.set_theme(self.dark)
            self._rebuild_recent_rolls_ui()
            self._rebuild_presets_ui()

        def _create_compat_target_combo(self) -> Any:
            """Provide a lightweight compatibility proxy for `self.target_combo`."""
            panel = self

            class _CompatCombo:
                def currentText(self) -> str:
                    if panel.recipient_mode() == "gm":
                        return "GM Only"
                    return "All"

                def setCurrentText(self, text: str) -> None:
                    if text == "GM Only":
                        panel.set_recipient_mode("gm")
                    else:
                        panel.set_recipient_mode("all")

            return _CompatCombo()

        # ------------------------------------------------------------------
        # Theme & Preferences
        # ------------------------------------------------------------------
        def set_theme(self, dark: bool) -> None:
            self.dark = bool(dark)
            bg = "#000000" if self.dark else "#ffffff"
            fg = "#ffffff" if self.dark else "#000000"
            style = f"QTextBrowser {{ background-color: {bg}; color: {fg}; }}"
            self.chat_log.setStyleSheet(style)
            self.pinned_log.setStyleSheet(style)

        def set_preferences(self, prefs: dict[str, Any]) -> None:
            self.prefs = prefs
            self.set_theme(bool(prefs.get("dark", True)))
            self._rerender_history_views()

        def set_identity(self, local_user: str, is_gm: bool | None = None) -> None:
            self.local_user = local_user
            self.is_gm = bool(is_gm) if is_gm is not None else (local_user == "GM")
            self.btn_edit_sys_presets.setVisible(self.is_gm)

        # ------------------------------------------------------------------
        # Recipient Selection Menu (`To:` (all) / GM / Peers)
        # ------------------------------------------------------------------
        def update_peer_list(self, peers: list[str]) -> None:
            """Update the dynamic list of connected peers in the `To:` recipient menu."""
            clean = sorted({str(p).strip() for p in peers if str(p).strip()})
            self._peer_names = clean
            self._selected_recipients &= set(clean)
            if self._recip_mode == "custom" and not self._selected_recipients:
                self._recip_mode = "all"
            self._rebuild_recipient_menu()
            self._update_recipient_button_label()

        def _rebuild_recipient_menu(self) -> None:
            self.to_menu.clear()
            act_all = QAction("To: (all)", self.to_menu)
            act_all.setCheckable(True)
            act_all.setChecked(self._recip_mode == "all")
            act_all.triggered.connect(lambda: self.set_recipient_mode("all"))
            self.to_menu.addAction(act_all)

            act_gm = QAction("To: GM Only", self.to_menu)
            act_gm.setCheckable(True)
            act_gm.setChecked(self._recip_mode == "gm")
            act_gm.triggered.connect(lambda: self.set_recipient_mode("gm"))
            self.to_menu.addAction(act_gm)

            if self._peer_names:
                self.to_menu.addSeparator()
                for peer in self._peer_names:
                    act_peer = QAction(peer, self.to_menu)
                    act_peer.setCheckable(True)
                    act_peer.setChecked(
                        self._recip_mode == "custom" and peer in self._selected_recipients
                    )
                    act_peer.triggered.connect(
                        lambda checked, p=peer: self._toggle_peer_recipient(p, checked)
                    )
                    self.to_menu.addAction(act_peer)

            self.to_menu.addSeparator()
            act_refresh = QAction("Refresh Peer List", self.to_menu)
            act_refresh.triggered.connect(self.refresh_peers_requested.emit)
            self.to_menu.addAction(act_refresh)

        def recipient_mode(self) -> str:
            """Return the active chat recipient mode (`'all'`, `'gm'`, or `'custom'`)."""
            return self._recip_mode

        def set_recipient_mode(self, mode: str) -> None:
            """Set chat recipient mode (`'all'`, `'gm'`, or `'custom'`) and refresh UI."""
            self._recip_mode = mode
            if mode != "custom":
                self._selected_recipients.clear()
            self._rebuild_recipient_menu()
            self._update_recipient_button_label()

        _set_recipient_mode = set_recipient_mode

        def _toggle_peer_recipient(self, peer: str, checked: bool) -> None:
            if checked:
                self._selected_recipients.add(peer)
                self._recip_mode = "custom"
            else:
                self._selected_recipients.discard(peer)
                if not self._selected_recipients:
                    self._recip_mode = "all"
            self._rebuild_recipient_menu()
            self._update_recipient_button_label()

        def _update_recipient_button_label(self) -> None:
            if self._recip_mode == "gm":
                self.to_menu_btn.setText("To: GM")
            elif self._recip_mode == "custom" and self._selected_recipients:
                names = sorted(self._selected_recipients)
                label = ", ".join(names) if len(names) <= 2 else f"{names[0]} +{len(names) - 1}"
                self.to_menu_btn.setText(f"To: {label}")
            else:
                self.to_menu_btn.setText("To: (all)")

        def current_recipient_routing(self, force_gm: bool = False) -> tuple[list[str], bool, bool]:
            """Return `(recipients, to_all, to_gm)` for the current recipient selection."""
            if force_gm or self._recip_mode == "gm":
                return ([], False, True)
            if self._recip_mode == "custom" and self._selected_recipients:
                return (sorted(self._selected_recipients), False, False)
            return ([], True, False)

        # ------------------------------------------------------------------
        # Presets & Hierarchical Tree Rendering
        # ------------------------------------------------------------------
        def set_presets(
            self,
            presets: list[dict[str, Any]],
            is_global: bool | None = None,
        ) -> None:
            """Update presets from server `DD=` or file load and rebuild the hierarchical UI."""
            if is_global is True:
                self.bank.set_system_presets(presets)
            elif is_global is False:
                self.bank.set_user_presets(presets)
            else:
                self.bank.set_combined_presets(presets)
            self._rebuild_presets_ui()

        def set_user_presets(self, presets: list[dict[str, Any]]) -> None:
            self.bank.set_user_presets(presets)
            self._rebuild_presets_ui()

        def set_system_presets(self, presets: list[dict[str, Any]]) -> None:
            self.bank.set_system_presets(presets)
            self._rebuild_presets_ui()

        def _clear_layout(self, layout: QVBoxLayout) -> None:
            while layout.count():
                item = layout.takeAt(0)
                w = item.widget()
                if w is not None:
                    w.deleteLater()

        def _rebuild_recent_rolls_ui(self) -> None:
            self._clear_layout(self.recent_list_layout)
            if not self.recent_rolls:
                empty_lbl = QLabel("No recent rolls yet.", self.recent_list_host)
                empty_lbl.setStyleSheet("color: gray; font-style: italic;")
                self.recent_list_layout.addWidget(empty_lbl)
                self.recent_list_layout.addStretch(1)
                return

            for spec in self.recent_rolls[:10]:
                row_w = QWidget(self.recent_list_host)
                row_l = QHBoxLayout(row_w)
                row_l.setContentsMargins(0, 0, 0, 0)
                row_l.setSpacing(4)

                roll_btn = QToolButton(row_w)
                roll_btn.setText("\U0001f3b2")
                roll_btn.setToolTip(f"Re-roll: {spec}")

                extra_edit = QLineEdit(row_w)
                extra_edit.setPlaceholderText("+mod")
                extra_edit.setFixedWidth(64)
                extra_edit.setToolTip("Optional ad-hoc modifier for this roll")

                clean_text = cleanup_die_roll_spec(spec)
                spec_lbl = QLabel(clean_text, row_w)
                spec_lbl.setWordWrap(False)
                spec_lbl.setToolTip(spec)

                roll_btn.clicked.connect(
                    lambda _chk=False, s=spec, e=extra_edit: self.trigger_roll(s, extra=e.text())
                )
                extra_edit.returnPressed.connect(
                    lambda s=spec, e=extra_edit: self.trigger_roll(s, extra=e.text())
                )

                save_btn = QToolButton(row_w)
                save_btn.setText("Save...")
                save_btn.setToolTip(f"Save as preset on server: {spec}")
                save_btn.clicked.connect(
                    lambda _chk=False, s=spec: self.open_quick_save_preset(s)
                )

                row_l.addWidget(roll_btn)
                row_l.addWidget(QLabel("+", row_w))
                row_l.addWidget(extra_edit)
                row_l.addWidget(spec_lbl, stretch=1)
                row_l.addWidget(save_btn)
                self.recent_list_layout.addWidget(row_w)

            self.recent_list_layout.addStretch(1)

        def _is_group_path_hidden(self, group_path: list[str]) -> bool:
            """Return True if any ancestor prefix in `group_path` is collapsed."""
            for depth in range(1, len(group_path) + 1):
                prefix_key = "\u25b6".join(group_path[:depth])
                if self.bank.group_collapsed.get(prefix_key, False):
                    return True
            return False

        def _toggle_group_collapsed(self, group_key: str) -> None:
            cur = bool(self.bank.group_collapsed.get(group_key, False))
            self.bank.group_collapsed[group_key] = not cur
            self._rebuild_presets_ui()

        def _rebuild_presets_ui(self) -> None:
            """Render collapsible groups, lookup tables, modifier checkboxes, and preset rolls."""
            self._clear_layout(self.presets_layout)

            sections: list[tuple[str, list[tuple[str, dict[str, Any]]]]] = [
                (
                    "tables",
                    [("global_table", tbl) for tbl in self.bank.global_tables]
                    + [("table", tbl) for tbl in self.bank.tables],
                ),
                (
                    "modifiers",
                    [("global_modifier", mod) for mod in self.bank.global_modifiers]
                    + [("modifier", mod) for mod in self.bank.modifiers],
                ),
                (
                    "rolls",
                    [("global_preset", r) for r in self.bank.global_rolls]
                    + [("preset", r) for r in self.bank.rolls],
                ),
            ]

            if not any(items for _sec, items in sections):
                empty_lbl = QLabel("No presets loaded.", self.presets_host)
                empty_lbl.setStyleSheet("color: gray; font-style: italic;")
                self.presets_layout.addWidget(empty_lbl)
                self.presets_layout.addStretch(1)
                return

            for _sec_name, sec_items in sections:
                prev_group_path: list[str] = []
                for item_kind, details in sec_items:
                    group_path: list[str] = list(details.get("group") or [])
                    # Find first level where group_path differs from prev_group_path
                    common_depth = 0
                    for a, b in zip(prev_group_path, group_path):
                        if a == b:
                            common_depth += 1
                        else:
                            break
                    for depth in range(common_depth + 1, len(group_path) + 1):
                        ancestor_slice = group_path[:depth]
                        if depth > 1 and self._is_group_path_hidden(group_path[: depth - 1]):
                            break
                        g_key = "\u25b6".join(ancestor_slice)
                        self._add_group_header_widget(ancestor_slice, g_key)
                    prev_group_path = group_path

                    if group_path and self._is_group_path_hidden(group_path):
                        continue

                    indent_px = len(group_path) * 14
                    if item_kind in ("table", "global_table"):
                        self._add_table_row_widget(
                            details, is_global=(item_kind == "global_table"), indent_px=indent_px
                        )
                    elif item_kind in ("modifier", "global_modifier"):
                        self._add_modifier_row_widget(
                            details, is_global=(item_kind == "global_modifier"), indent_px=indent_px
                        )
                    else:
                        self._add_preset_row_widget(
                            details, is_global=(item_kind == "global_preset"), indent_px=indent_px
                        )

            self.presets_layout.addStretch(1)

        def _add_group_header_widget(self, group_slice: list[str], group_key: str) -> None:
            collapsed = bool(self.bank.group_collapsed.get(group_key, False))
            arrow = "\u25b8" if collapsed else "\u25be"
            indent_px = (len(group_slice) - 1) * 14
            btn = QPushButton(f"{arrow} {' \u25b6 '.join(group_slice)}", self.presets_host)
            btn.setFlat(True)
            btn.setStyleSheet(
                f"text-align: left; font-weight: bold; padding-left: {indent_px + 4}px;"
            )
            btn.clicked.connect(lambda _chk=False, k=group_key: self._toggle_group_collapsed(k))
            self.presets_layout.addWidget(btn)

        def _add_table_row_widget(
            self,
            details: dict[str, Any],
            is_global: bool,
            indent_px: int = 0,
        ) -> None:
            row_w = QWidget(self.presets_host)
            row_l = QHBoxLayout(row_w)
            row_l.setContentsMargins(indent_px, 0, 0, 0)
            row_l.setSpacing(4)

            prefix = "##" if is_global else "#"
            tbl_name = details["name"]
            desc = details.get("description") or tbl_name
            roll_expr = details.get("dieroll") or "1d20"

            roll_btn = QToolButton(row_w)
            roll_btn.setText("\U0001f3b2")
            roll_btn.setToolTip(f"Roll on table {prefix}{tbl_name} ({roll_expr})")

            extra_edit = QLineEdit(row_w)
            extra_edit.setPlaceholderText("+mod")
            extra_edit.setFixedWidth(60)

            lbl = QLabel(f"[{prefix}{tbl_name}] {desc} ({roll_expr})", row_w)
            lbl.setToolTip(details.get("dieroll", ""))

            roll_spec = f"{desc} = {prefix}{tbl_name}"
            roll_btn.clicked.connect(
                lambda _chk=False, s=roll_spec, e=extra_edit: self.trigger_roll(s, extra=e.text())
            )
            extra_edit.returnPressed.connect(
                lambda s=roll_spec, e=extra_edit: self.trigger_roll(s, extra=e.text())
            )

            row_l.addWidget(roll_btn)
            row_l.addWidget(QLabel("+", row_w))
            row_l.addWidget(extra_edit)
            row_l.addWidget(lbl, stretch=1)
            self.presets_layout.addWidget(row_w)

        def _add_modifier_row_widget(
            self,
            details: dict[str, Any],
            is_global: bool,
            indent_px: int = 0,
        ) -> None:
            row_w = QWidget(self.presets_host)
            row_l = QHBoxLayout(row_w)
            row_l.setContentsMargins(indent_px, 0, 0, 0)
            row_l.setSpacing(4)

            mod_id = details.get("mod_id", "")
            var_name = details.get("var", "")
            name = details.get("name", "")
            spec = details.get("dieroll", "")
            desc = details.get("description", "")

            if var_name:
                var_sigil = f"$${var_name}" if details.get("global") else f"${var_name}"
                label_text = f"{name} (as {var_sigil}): {spec}"
            else:
                glob_tag = " [Global]" if is_global else ""
                label_text = f"{name}{glob_tag}: {spec}"

            chk = QCheckBox(label_text, row_w)
            chk.setChecked(self.bank.is_mod_enabled(mod_id))
            if desc:
                chk.setToolTip(desc)
            chk.toggled.connect(
                lambda checked, mid=mod_id: self.bank.set_mod_enabled(mid, checked)
            )
            row_l.addWidget(chk, stretch=1)
            self.presets_layout.addWidget(row_w)

        def _add_preset_row_widget(
            self,
            details: dict[str, Any],
            is_global: bool,
            indent_px: int = 0,
        ) -> None:
            row_w = QWidget(self.presets_host)
            row_l = QHBoxLayout(row_w)
            row_l.setContentsMargins(indent_px, 0, 0, 0)
            row_l.setSpacing(4)

            name = details.get("name", "")
            desc = details.get("description", "")
            spec = details.get("dieroll", "")

            roll_btn = QToolButton(row_w)
            roll_btn.setText("\U0001f3b2")
            roll_btn.setToolTip(desc or f"Roll {name}: {spec}")

            extra_edit = QLineEdit(row_w)
            extra_edit.setPlaceholderText("+mod")
            extra_edit.setFixedWidth(60)
            extra_edit.setToolTip("Optional ad-hoc modifier for this roll")

            clean_spec = cleanup_die_roll_spec(spec)
            prefix_tag = "[Sys] " if is_global else ""
            lbl = QLabel(f"{prefix_tag}<b>{name}</b>: {clean_spec}", row_w)
            lbl.setToolTip(f"{desc}\n{spec}".strip())

            roll_btn.clicked.connect(
                lambda _chk=False, s=spec, e=extra_edit: self.trigger_roll(s, extra=e.text())
            )
            extra_edit.returnPressed.connect(
                lambda s=spec, e=extra_edit: self.trigger_roll(s, extra=e.text())
            )

            row_l.addWidget(roll_btn)
            row_l.addWidget(QLabel("+", row_w))
            row_l.addWidget(extra_edit)
            row_l.addWidget(lbl, stretch=1)
            self.presets_layout.addWidget(row_w)

        # ------------------------------------------------------------------
        # Roll & Chat Dispatch
        # ------------------------------------------------------------------
        def trigger_roll(self, raw_spec: str, extra: str = "") -> None:
            """Execute the client-side die-roll pipeline and emit `send_roll_requested`."""
            spec = raw_spec.strip()
            if not spec:
                return

            # Record raw spec in recent rolls (newest first, max 10, deduplicated)
            if spec in self.recent_rolls:
                self.recent_rolls.remove(spec)
            self.recent_rolls.insert(0, spec)
            if len(self.recent_rolls) > 10:
                self.recent_rolls = self.recent_rolls[:10]
            self._rebuild_recent_rolls_ui()

            my_names: list[str] = [self.local_user] if self.local_user else []
            mobs_by_id: dict[str, dict[str, Any]] | None = None
            mobs_by_name: dict[str, str] | None = None
            if self.target_context_provider is not None:
                my_names, mobs_by_id, mobs_by_name = self.target_context_provider()

            self._req_seq += 1
            req_id = f"r{self._req_seq}"
            recipients, to_all, to_gm = self.current_recipient_routing(
                force_gm=self.gm_only_chk.isChecked()
            )

            try:
                prepared = prepare_die_roll(
                    rollspec=spec,
                    extra=extra,
                    bank=self.bank,
                    for_user=self.for_user,
                    local_user=self.local_user,
                    my_names=my_names,
                    mobs_by_id=mobs_by_id,
                    mobs_by_name=mobs_by_name,
                    to_gm=to_gm,
                    to_all=to_all,
                    recipients=recipients,
                    req_id=req_id,
                )
            except ValueError as exc:
                self.append_notice(f"Roll Error: {exc}")
                return

            if prepared.get("warning"):
                self.append_notice(str(prepared["warning"]))

            final_spec = str(prepared["rollspec"])
            final_req_id = str(prepared["request_id"])
            final_recips = list(prepared["recipients"] or [])
            final_to_all = bool(prepared["to_all"])
            final_to_gm = bool(prepared["to_gm"])

            self.send_roll_ex_requested.emit(
                final_spec, final_recips, final_to_all, final_to_gm, final_req_id
            )
            self.send_roll_requested.emit(
                final_spec, final_recips, final_to_all, final_to_gm
            )
            legacy_targets = ["GM"] if final_to_gm else final_recips
            self.rollRequested.emit("", final_spec, legacy_targets)

        def _on_send_chat(self) -> None:
            text = self.chat_entry.text().strip()
            if not text:
                return
            self.chat_entry.clear()

            if text.startswith("/r ") or text.startswith("/roll "):
                spec = text.split(" ", 1)[1].strip()
                self.trigger_roll(spec)
                return

            recipients, to_all, to_gm = self.current_recipient_routing()
            markup = self.markup_btn.isChecked()
            pin = self.pin_btn.isChecked()
            if pin:
                self.pin_btn.setChecked(False)

            self.send_chat_ex_requested.emit(text, recipients, to_all, to_gm, markup, pin)
            self.send_chat_requested.emit(text, recipients, to_all, to_gm)
            legacy_targets = ["GM"] if to_gm else recipients
            self.chatSent.emit(text, legacy_targets)

        def _on_send_roll(self) -> None:
            spec = self.roll_entry.text().strip()
            if not spec:
                return
            self.roll_entry.clear()
            self.trigger_roll(spec)

        # ------------------------------------------------------------------
        # Rich Display, Pinned Messages, History Clearing & Pruning
        # ------------------------------------------------------------------
        def append_chat(self, payload: dict[str, Any]) -> None:
            """Record and display an incoming `TO` chat payload."""
            entry = self.history_manager.add_chat_message(payload)
            msg_id = entry.get("MessageID")
            is_local_pin = False
            if msg_id is not None:
                try:
                    is_local_pin = int(msg_id) in self.history_manager.pin_list
                except (TypeError, ValueError):
                    pass

            html_line = render_chat_payload_html(
                entry,
                prefs=self.prefs,
                dark=self.dark,
                is_pinned_view=False,
                is_locally_pinned=is_local_pin,
                is_gm=self.is_gm,
            )
            self.chat_log.append(html_line)
            if bool(entry.get("Pin", False)) or is_local_pin:
                self._refresh_pinned_view()

        def append_roll(self, payload: dict[str, Any], _styles: Any = None) -> None:
            """Record, collect stats for, and display an incoming `ROLL` payload."""
            stats_line = self.stat_collector.collect(payload)
            entry = self.history_manager.add_roll_message(payload, stats_line=stats_line)
            html_line = render_roll_payload_html(
                entry,
                prefs=self.prefs,
                dark=self.dark,
                stats_line=stats_line,
            )
            self.chat_log.append(html_line)

        def clear_messages(self, keep: int = 0) -> None:
            """Legacy alias for `clear_chat_history`."""
            target = -abs(int(keep)) if keep else 0
            self.clear_chat_history(target=target)

        def append_notice(self, text: str) -> None:
            """Display a local status/warning notice in the chat log."""
            self.history_manager.add_notice(text)
            color = "#ffcc00" if self.dark else "#995500"
            self.chat_log.append(
                f'<div><span style="color:{color};font-style:italic;">* {text}</span></div>'
            )

        def clear_chat_history(
            self,
            target: int = 0,
            target_messages: list[int] | None = None,
            do_all: bool = False,
        ) -> None:
            """Apply `CC` clearing rules and re-render chat and pinned panes."""
            self.history_manager.clear_chat_history(
                target=target,
                target_messages=target_messages,
                do_all=do_all,
            )
            self._rerender_history_views()

        def clear_pinned_messages(self) -> int:
            """Unpin locally pinned messages and hide server-pinned messages, then refresh."""
            count = self.history_manager.clear_pinned_messages()
            self._rerender_history_views()
            return count

        def prune_chat_history(self, min_id: int | None, max_id: int | None) -> None:
            """Apply `Y2` message pruning and re-render chat and pinned panes."""
            self.history_manager.prune_chat_history(min_id=min_id, max_id=max_id)
            self._rerender_history_views()

        def _rerender_history_views(self) -> None:
            self.chat_log.clear()
            for entry in self.history_manager.visible_entries():
                kind = entry.get("kind", "chat")
                if kind == "roll":
                    self.chat_log.append(
                        render_roll_payload_html(
                            entry,
                            prefs=self.prefs,
                            dark=self.dark,
                            stats_line=entry.get("stats_line"),
                        )
                    )
                elif kind == "notice":
                    color = "#ffcc00" if self.dark else "#995500"
                    self.chat_log.append(
                        f'<div><span style="color:{color};font-style:italic;">* {entry.get("Text", "")}</span></div>'
                    )
                else:
                    mid = entry.get("MessageID")
                    is_local_pin = False
                    if mid is not None:
                        try:
                            is_local_pin = int(mid) in self.history_manager.pin_list
                        except (TypeError, ValueError):
                            pass
                    self.chat_log.append(
                        render_chat_payload_html(
                            entry,
                            prefs=self.prefs,
                            dark=self.dark,
                            is_pinned_view=False,
                            is_locally_pinned=is_local_pin,
                            is_gm=self.is_gm,
                        )
                    )
            self._refresh_pinned_view()

        def _refresh_pinned_view(self) -> None:
            pinned = self.history_manager.pinned_entries()
            self.pinned_log.clear()
            if not pinned or self.roll_only:
                self.pinned_group.setVisible(False)
                return
            self.pinned_group.setVisible(True)
            for entry in pinned:
                mid = entry.get("MessageID")
                is_local_pin = int(mid) in self.history_manager.pin_list if mid is not None else False
                self.pinned_log.append(
                    render_chat_payload_html(
                        entry,
                        prefs=self.prefs,
                        dark=self.dark,
                        is_pinned_view=True,
                        is_locally_pinned=is_local_pin,
                        is_gm=self.is_gm,
                    )
                )

        def _on_chat_anchor_clicked(self, url: QUrl) -> None:
            raw = url.toString()
            if ":" not in raw:
                return
            action, raw_id = raw.split(":", 1)
            try:
                msg_id = int(raw_id)
            except ValueError:
                return
            if action == "pin":
                self.history_manager.pin_message(msg_id)
                self._rerender_history_views()
            elif action == "unpin":
                self.history_manager.unpin_message(msg_id)
                self._rerender_history_views()
            elif action == "hide":
                self.history_manager.hide_message(msg_id)
                self._rerender_history_views()
            elif action == "del":
                self.delete_message_requested.emit(msg_id)

        # ------------------------------------------------------------------
        # Dialog Launchers & Import / Export
        # ------------------------------------------------------------------
        def _on_edit_roll_entry_colorbox(self) -> None:
            cur_spec = self.roll_entry.text()
            dlg = EditColorBoxTitleDialog(cur_spec, self)
            if dlg.exec():
                self.roll_entry.setText(dlg.updated_roll_spec(cur_spec))

        def _on_show_syntax_help(self) -> None:
            dlg = DiceSyntaxHelpDialog(self)
            dlg.show()

        def open_preset_editor(self, system_mode: bool = False) -> None:
            if system_mode and not self.is_gm:
                self.append_notice("You are not authorized to edit system presets.")
                QMessageBox.warning(
                    self,
                    "Authorization Required",
                    "You are not authorized to edit system presets.",
                )
                return
            dlg = EditDieRollPresetsDialog(
                bank=self.bank,
                system_mode=system_mode,
                for_user=self.for_user,
                parent=self,
            )
            if dlg.exec():
                new_presets = dlg.encoded_presets()
                if system_mode:
                    self.bank.set_system_presets(new_presets)
                else:
                    self.bank.set_user_presets(new_presets)
                self._rebuild_presets_ui()
                self.save_presets_requested.emit(new_presets, system_mode, self.for_user)

        def _known_group_paths(self) -> list[list[str]]:
            paths: list[list[str]] = []
            for entry in [*self.bank.rolls, *self.bank.modifiers, *self.bank.tables]:
                grp = entry.get("group") or []
                if grp:
                    paths.append(list(grp))
            return paths

        def push_presets_to_server(self) -> None:
            """Explicitly push the current user presets to the GMA server (`DD`)."""
            self.save_presets_requested.emit(self.bank.user_presets, False, self.for_user)

        def save_single_preset(self, preset: dict[str, Any]) -> None:
            """Merge a single encoded preset into the local bank and emit `DD+` + `DR` signals."""
            merged = merge_preset_lists(self.bank.user_presets, [preset])
            self.bank.set_user_presets(merged)
            self._rebuild_presets_ui()
            self.append_presets_requested.emit([preset], False, self.for_user)
            self.refresh_presets_requested.emit(self.for_user)

        def open_quick_save_preset(self, initial_spec: str = "") -> bool:
            """Open the lightweight quick-save preset dialog and push via `DD+` on Save."""
            dlg = QuickSavePresetDialog(
                initial_spec=initial_spec,
                known_group_paths=self._known_group_paths(),
                for_user=self.for_user or self.local_user,
                parent=self,
            )
            if dlg.exec():
                self.save_single_preset(dlg.encoded_preset())
                return True
            return False

        def _apply_imported_presets(
            self, loaded: list[dict[str, Any]], merge: bool = True
        ) -> list[dict[str, Any]]:
            merged = (
                merge_preset_lists(self.bank.user_presets, loaded)
                if merge
                else [dict(p) for p in loaded]
            )
            self.bank.set_user_presets(merged)
            self._rebuild_presets_ui()
            self.save_presets_requested.emit(self.bank.user_presets, False, self.for_user)
            self.refresh_presets_requested.emit(self.for_user)
            return merged

        def import_presets_from_file(
            self, path: str | Path, merge: bool = True
        ) -> list[dict[str, Any]]:
            """Load presets from `path`, merge or replace locally, and emit `DD` + `DR` signals."""
            _meta, loaded = load_dice_presets_from_file(path)
            if not loaded:
                return []
            return self._apply_imported_presets(loaded, merge=merge)

        def prompt_import_presets_from_file(self) -> None:
            """Prompt for a local `.dice` file and import presets."""
            path, _ = QFileDialog.getOpenFileName(
                self, "Import Dice Presets", "", "Dice Files (*.dice);;All Files (*)"
            )
            if not path:
                return
            try:
                _meta, loaded = load_dice_presets_from_file(path)
            except (OSError, ValueError) as exc:
                QMessageBox.critical(
                    self,
                    "Error Loading Preset File",
                    f"Error loading file: {exc}",
                )
                return
            if not loaded:
                return
            merge = True
            if self.bank.user_presets:
                count = len(self.bank.user_presets)
                noun = "preset" if count == 1 else "presets"
                ans = QMessageBox.question(
                    self,
                    "Merge with existing presets?",
                    f"You already have {count} {noun} defined. Do you want the new ones to be MERGED with those?\n\n"
                    "Yes: overwrite matching names and add new presets.\n"
                    "No: delete all current presets and replace them with the file contents.",
                    QMessageBox.StandardButton.Yes
                    | QMessageBox.StandardButton.No
                    | QMessageBox.StandardButton.Cancel,
                    QMessageBox.StandardButton.Yes,
                )
                if ans == QMessageBox.StandardButton.Cancel:
                    return
                merge = ans == QMessageBox.StandardButton.Yes
            self._apply_imported_presets(loaded, merge=merge)

        _on_import_presets_clicked = prompt_import_presets_from_file

        def _on_export_presets_clicked(self) -> None:
            if not self.bank.user_presets:
                QMessageBox.information(
                    self,
                    "No Presets to Save",
                    "You have no presets to save.",
                )
                return
            path, _ = QFileDialog.getSaveFileName(
                self, "Export Dice Presets", "", "Dice Files (*.dice)"
            )
            if not path:
                return
            try:
                save_dice_presets_to_file(Path(path), self.bank.user_presets)
            except OSError as exc:
                QMessageBox.critical(
                    self,
                    "Error Saving Preset File",
                    f"Unable to save {path}: {exc}",
                )

    class DelegatedDieRollerDialog(QDialog):
        """Secondary die-roller window for rolling on behalf of another player (`DelegateFor`)."""

        def __init__(
            self,
            for_user: str,
            local_user: str = "",
            prefs: dict[str, Any] | None = None,
            shared_gvar_state: dict[str, bool] | None = None,
            parent: QWidget | None = None,
        ) -> None:
            super().__init__(parent)
            self.for_user = for_user
            self.setWindowTitle(f"Die Roller for {for_user}")
            self.resize(480, 560)

            layout = QVBoxLayout(self)
            layout.setContentsMargins(4, 4, 4, 4)
            self.panel = ChatDicePanel(
                parent=self,
                tkey=for_user,
                for_user=for_user,
                local_user=local_user,
                prefs=prefs,
                shared_gvar_state=shared_gvar_state,
                roll_only=True,
            )
            layout.addWidget(self.panel, stretch=1)
