"""Chat and roll log widget ported from ``GMADieRoller/Chat.py``."""

from __future__ import annotations

from threading import Lock
from typing import Any, Callable

from py_dieroller.images import CHAT_PNG, DICE_LT_PNG, HIDDEN_PNG, LOCK_PNG
from py_dieroller.local_roller import LocalDieRoller
from py_dieroller.models import expand_variables
from py_dieroller.settings import SettingsStore, render_message_segment_html


try:
    from PySide6.QtCore import Qt
    from PySide6.QtGui import QTextCursor
    from PySide6.QtWidgets import (
        QHBoxLayout,
        QLabel,
        QListWidget,
        QPlainTextEdit,
        QPushButton,
        QSplitter,
        QTextBrowser,
        QVBoxLayout,
        QWidget,
    )

    from py_dieroller.images import load_qicon

    QT_AVAILABLE = True
except ImportError:  # pragma: no cover
    QT_AVAILABLE = False


if QT_AVAILABLE:

    class ChatPanel(QWidget):
        """Chat message viewer, recipient list, expression entry, and roll action bar."""

        def __init__(
            self,
            settings: SettingsStore,
            parent: QWidget | None = None,
            on_alert: Callable[[str, str], None] | None = None,
            get_variables: Callable[[], dict[str, str]] | None = None,
            on_history_add: Callable[[str], None] | None = None,
        ) -> None:
            super().__init__(parent)
            self.settings = settings
            self._on_alert = on_alert
            self._get_variables = get_variables
            self._on_history_add = on_history_add
            self.mutex = Lock()
            self.message_buffer: list[dict[str, Any]] = []
            self.roller = LocalDieRoller()
            self.service: Any = None
            self.min_msgid: int = -1
            self._pending_line_fragments: list[dict[str, Any]] = []

            self._init_gui()

        def _init_gui(self) -> None:
            root = QVBoxLayout(self)
            root.setContentsMargins(0, 0, 0, 0)
            self.chat_splitter = QSplitter(Qt.Orientation.Vertical, self)
            root.addWidget(self.chat_splitter, stretch=1)

            # Top pane: Messages + Recipients
            top = QWidget(self.chat_splitter)
            top_v = QVBoxLayout(top)
            top_v.setContentsMargins(4, 4, 4, 4)
            top_v.setSpacing(4)

            headers = QHBoxLayout()
            headers.addWidget(QLabel("Messages", top), stretch=3)
            headers.addWidget(QLabel("Recipients", top), stretch=1)
            top_v.addLayout(headers)

            panes = QHBoxLayout()
            self.messages = QTextBrowser(top)
            self.messages.setReadOnly(True)
            self.messages.setOpenExternalLinks(False)
            self.recipients = QListWidget(top)
            self.recipients.setSelectionMode(QListWidget.SelectionMode.MultiSelection)
            self.recipients.setSortingEnabled(True)
            self.recipients.setMaximumWidth(180)
            self.recipients.itemSelectionChanged.connect(self._on_recipients_selected)

            panes.addWidget(self.messages, stretch=3)
            panes.addWidget(self.recipients, stretch=1)
            top_v.addLayout(panes, stretch=1)

            # Bottom pane: Entry + Action buttons
            bottom = QWidget(self.chat_splitter)
            bot_v = QVBoxLayout(bottom)
            bot_v.setContentsMargins(4, 4, 4, 4)
            bot_v.setSpacing(4)

            entry_hdr = QHBoxLayout()
            entry_hdr.addWidget(QLabel("Message entry", bottom))
            entry_hdr.addStretch(1)
            self.expand_btn = QPushButton("Expand vars", bottom)
            self.expand_btn.clicked.connect(self._on_expand_vars_clicked)
            entry_hdr.addWidget(self.expand_btn)
            bot_v.addLayout(entry_hdr)

            self.chattext = QPlainTextEdit(bottom)
            self.chattext.setMaximumHeight(90)
            bot_v.addWidget(self.chattext, stretch=1)

            btn_row = QHBoxLayout()
            btn_row.addStretch(1)

            self.chatbutton = QPushButton("Send Chat", bottom)
            self.chatbutton.setIcon(load_qicon(CHAT_PNG))
            self.chatbutton.clicked.connect(lambda _c=False: self.do_chat(pm=False))
            self.chatbutton.setEnabled(False)

            self.chatto = QPushButton("Priv Msg", bottom)
            self.chatto.setIcon(load_qicon(LOCK_PNG))
            self.chatto.clicked.connect(lambda _c=False: self.do_chat(pm=True))
            self.chatto.setEnabled(False)

            self.rollbutton = QPushButton("Roll", bottom)
            self.rollbutton.setIcon(load_qicon(DICE_LT_PNG))
            self.rollbutton.clicked.connect(lambda _c=False: self.roll_dice())

            self.rolltobutton = QPushButton("Roll To", bottom)
            self.rolltobutton.clicked.connect(lambda _c=False: self.roll_dice(roll_to=True))
            self.rolltobutton.setEnabled(False)

            self.gmrollbutton = QPushButton("Blind Roll", bottom)
            self.gmrollbutton.setIcon(load_qicon(HIDDEN_PNG))
            self.gmrollbutton.clicked.connect(lambda _c=False: self.roll_dice(blind=True))
            self.gmrollbutton.setEnabled(False)

            for btn in (
                self.chatbutton,
                self.chatto,
                self.rollbutton,
                self.rolltobutton,
                self.gmrollbutton,
            ):
                btn_row.addWidget(btn)
            bot_v.addLayout(btn_row)

            self.chat_splitter.addWidget(top)
            self.chat_splitter.addWidget(bottom)
            self.chat_splitter.setStretchFactor(0, 3)
            self.chat_splitter.setStretchFactor(1, 1)

        def _on_expand_vars_clicked(self) -> None:
            self.chattext.setPlainText(self._expand_variables(self.chattext.toPlainText()))

        def _on_recipients_selected(self) -> None:
            has_sel = len(self.recipients.selectedItems()) > 0
            connected = bool(self.service is not None and self.service.connected())
            self.chatto.setEnabled(connected and has_sel)
            self.rolltobutton.setEnabled(connected and has_sel)

        def _expand_variables(self, text: str) -> str:
            var_defs = self._get_variables() if self._get_variables is not None else {}
            expanded, err = expand_variables(text, var_defs)
            if err and self._on_alert is not None:
                self._on_alert("Expression error", err)
                return text
            return expanded

        def stylesheet_changed(self) -> None:
            """Re-render buffered messages after a style preference change."""
            self.messages.clear()
            self._pending_line_fragments.clear()
            self.add_messages(list(self.message_buffer), buffer=False)
            self.add_message("Styles updated", style="comment")

        def selected_recipients(self) -> list[str]:
            """Return sorted list of currently selected recipient usernames."""
            return [item.text() for item in self.recipients.selectedItems()]

        def do_chat(self, pm: bool = False) -> None:
            """Send chat text in ``self.chattext`` over ``self.service``."""
            if self.service is None or not self.service.connected():
                return
            recips = self.selected_recipients() if pm else None
            msg = self.chattext.toPlainText().strip()
            if not msg:
                return
            self.service.send_chat(msg, recipients=recips)
            self.chattext.clear()

        def stage_dice(self, expr: str) -> None:
            """Populate the message entry box with ``expr`` for manual editing."""
            self.chattext.setPlainText(expr)

        def roll_dice(
            self,
            expr: str | None = None,
            blind: bool = False,
            roll_to: bool = False,
            history: bool = True,
        ) -> None:
            """Evaluate ``expr`` locally (when offline) or send to server (when connected)."""
            raw_expr = self.chattext.toPlainText() if expr is None else expr
            clean_expr = str(raw_expr or "").strip()
            if not clean_expr:
                return
            expanded = self._expand_variables(clean_expr)

            if self.service is not None and self.service.connected():
                if roll_to:
                    self.service.roll_dice(expanded, recipients=self.selected_recipients())
                elif blind:
                    self.service.roll_dice(expanded, blind=True)
                else:
                    self.service.roll_dice(expanded)
                if history and self._on_history_add is not None:
                    self._on_history_add(clean_expr)
            else:
                self._run_offline_roll(expanded)
                if history and self._on_history_add is not None:
                    self._on_history_add(clean_expr)

            if expr is None:
                self.chattext.clear()

        def _run_offline_roll(self, expr: str) -> None:
            self.add_message("Offline die roll: ", style="user", newline=False)
            label, data = self.roller.do_roll(expr)
            if label:
                self.add_message(f"{label}: ", style="rolllabel", newline=False)
            for tag, text in data[0][1]:
                if tag == "roll":
                    self.add_message(f"({text}) ", style="roll", newline=False)
                else:
                    self.add_message(f"{text} ", style=tag, newline=False)
            self.add_message(" ", newline=True)

        def update_userlist(self, users: list[str] | set[str] | None) -> None:
            """Replace the Recipients listbox with ``users``."""
            self.recipients.clear()
            if users:
                self.recipients.addItems(sorted(str(u) for u in users))
            self._on_recipients_selected()

        def set_connected(self, is_connected: bool) -> None:
            """Enable or disable online chat/roll buttons based on connection state."""
            self.chatbutton.setEnabled(is_connected)
            self.gmrollbutton.setEnabled(is_connected)
            if not is_connected:
                self.update_userlist([])
            self._on_recipients_selected()

        def add_message(
            self,
            text: str,
            style: str | None = None,
            newline: bool = True,
            buffer: bool = True,
            msgid: int | None = None,
        ) -> None:
            """Append a single text segment (optionally styled) to the message viewer."""
            if not text:
                return
            msg: dict[str, Any] = {
                "text": text,
                "newline": newline,
                "msgid": msgid,
            }
            if style:
                msg["style"] = style
            self.add_messages([msg], buffer=buffer)

        def add_messages(self, msgs: list[dict[str, Any]], buffer: bool = True) -> None:
            """Append a batch of message segments cleanly with HTML styling."""
            with self.mutex:
                for msg in msgs:
                    self._append_single_message(msg, buffer=buffer)

        def _append_single_message(self, msg: dict[str, Any], buffer: bool = True) -> None:
            msgid = msg.get("msgid")
            if msgid is not None and self.min_msgid > int(msgid):
                return
            if "text" not in msg:
                return
            if buffer:
                self.message_buffer.append(dict(msg))

            frag = render_message_segment_html(msg, self.settings)
            cursor = self.messages.textCursor()
            cursor.movePosition(QTextCursor.MoveOperation.End)
            cursor.insertHtml(frag)
            if msg.get("newline"):
                cursor.insertText("\n")
            self.messages.setTextCursor(cursor)
            self.messages.ensureCursorVisible()
