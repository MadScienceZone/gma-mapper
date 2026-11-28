"""Chat, pinned messages, and roll log widget ported from ``GMADieRoller/Chat.py``."""

from __future__ import annotations

import html
from threading import Lock
from typing import Any, Callable

from gma_mapper.core.dice import (
    ChatHistoryManager,
    DicePresetBank,
    lookup_table_outcome,
    resolve_table_roll_reply,
)
from gma_mapper.core.minimarkup import render_html as render_minimarkup_html
from py_dieroller.images import CHAT_PNG, DICE_LT_PNG, HIDDEN_PNG, LOCK_PNG
from py_dieroller.local_roller import LocalDieRoller
from py_dieroller.models import (
    compose_table_roll_expression,
    expand_variables,
    parse_table_invocation,
)
from py_dieroller.settings import SettingsStore, render_message_segment_html


def _style_css_from_store(store: SettingsStore, style_name: str | None) -> str:
    style_dict = store.effective_style(style_name)
    parts: list[str] = []
    fg = str(style_dict.get("foreground") or "").strip()
    bg = str(style_dict.get("background") or "").strip()
    if fg:
        parts.append(f"color:{fg}")
    if bg:
        parts.append(f"background-color:{bg}")
    fontstyle = style_dict.get("fontstyle") or []
    if "bold" in fontstyle:
        parts.append("font-weight:bold")
    if "italic" in fontstyle:
        parts.append("font-style:italic")
    if "underline" in fontstyle:
        parts.append("text-decoration:underline")
    return ";".join(parts)


def render_chat_entry_html(
    entry: dict[str, Any],
    store: SettingsStore,
    *,
    is_pinned_view: bool = False,
    is_locally_pinned: bool = False,
    is_gm: bool = False,
) -> str:
    """Render a ``TO`` chat entry dict with optional pin badges, markup, and action links."""
    sender = str(
        entry.get("Sender")
        or (entry.get("Origin") if isinstance(entry.get("Origin"), str) else "")
        or "Server"
    )
    text = str(entry.get("Text") or "")
    to_all = bool(entry.get("ToAll", False))
    to_gm = bool(entry.get("ToGM", False))
    recipients = [str(r) for r in (entry.get("Recipients") or entry.get("Targets") or []) if r]
    global_pin = bool(entry.get("Pin", False))
    markup = bool(entry.get("Markup", False))
    msg_id = entry.get("MessageID")

    if to_all:
        sender_html = render_message_segment_html(
            {"text": f"{sender}: ", "style": "user"}, store
        )
        body_style: str | None = None
    else:
        recip_str = ",".join(recipients) if recipients else ("GM" if to_gm else "")
        prefix = f"{sender} to {recip_str}: " if recip_str and (recipients != [sender]) else f"{sender}: "
        sender_html = render_message_segment_html(
            {"text": prefix, "style": "privateuser"}, store
        )
        body_style = "privatemsg"

    if markup:
        markup_body = render_minimarkup_html(text)
        body_css = _style_css_from_store(store, body_style)
        body_html = f'<span style="{body_css}">{markup_body}</span>' if body_css else markup_body
    else:
        body_html = render_message_segment_html({"text": text, "style": body_style}, store)

    actions_html = ""
    if msg_id is not None and not str(msg_id).startswith("-"):
        link_css = "text-decoration:none; color:#64748b;"
        del_css = "text-decoration:none; color:#dc2626;"
        links: list[str] = []
        if is_pinned_view:
            if is_locally_pinned:
                links.append(
                    f'<a href="unpin:{html.escape(str(msg_id))}" title="Unpin locally" '
                    f'style="{link_css}">[\u2606]</a>'
                )
            elif global_pin:
                links.append(
                    f'<a href="hide:{html.escape(str(msg_id))}" title="Dismiss pinned message" '
                    f'style="{link_css}">[\u00d7]</a>'
                )
            if is_gm:
                links.append(
                    f'<a href="del:{html.escape(str(msg_id))}" title="Delete message for all" '
                    f'style="{del_css}">[\U0001f5d1]</a>'
                )
        else:
            if is_locally_pinned:
                links.append(
                    f'<a href="unpin:{html.escape(str(msg_id))}" title="Unpin locally" '
                    f'style="{link_css}">[\u2605]</a>'
                )
            else:
                links.append(
                    f'<a href="pin:{html.escape(str(msg_id))}" title="Pin locally" '
                    f'style="{link_css}">[\u2606]</a>'
                )
            if is_gm:
                links.append(
                    f'<a href="del:{html.escape(str(msg_id))}" title="Delete message for all" '
                    f'style="{del_css}">[\U0001f5d1]</a>'
                )
            else:
                links.append(
                    f'<a href="hide:{html.escape(str(msg_id))}" title="Hide message locally" '
                    f'style="{link_css}">[\u00d7]</a>'
                )
        if links:
            actions_html = f' <span style="font-size:smaller;">{" ".join(links)}</span>'

    pin_badge = "\U0001f4cc " if (global_pin or is_locally_pinned) else ""
    return f"<span>{pin_badge}{sender_html}{body_html}{actions_html}</span>"


try:
    from PySide6.QtCore import Qt, QUrl
    from PySide6.QtGui import QTextCursor
    from PySide6.QtWidgets import (
        QGroupBox,
        QHBoxLayout,
        QLabel,
        QListWidget,
        QPlainTextEdit,
        QPushButton,
        QSplitter,
        QTextBrowser,
        QToolButton,
        QVBoxLayout,
        QWidget,
    )

    from py_dieroller.images import load_qicon

    QT_AVAILABLE = True
except ImportError:  # pragma: no cover
    QT_AVAILABLE = False


if QT_AVAILABLE:

    class ChatPanel(QWidget):
        """Chat message viewer, pinned message pane, recipient list, and roll action bar."""

        def __init__(
            self,
            settings: SettingsStore,
            parent: QWidget | None = None,
            on_alert: Callable[[str, str], None] | None = None,
            get_variables: Callable[[], dict[str, str]] | None = None,
            on_history_add: Callable[[str], None] | None = None,
            get_table_bank: Callable[[], DicePresetBank] | None = None,
        ) -> None:
            super().__init__(parent)
            self.settings = settings
            self._on_alert = on_alert
            self._get_variables = get_variables
            self._on_history_add = on_history_add
            self._get_table_bank = get_table_bank
            self.mutex = Lock()
            self.message_buffer: list[dict[str, Any]] = []
            self.stream_items: list[dict[str, Any]] = []
            self.history_manager = ChatHistoryManager()
            self.roller = LocalDieRoller()
            self.service: Any = None
            self.min_msgid: int = -1
            self.allow_pinned_panel: bool = True
            self._req_counter: int = 0

            self._init_gui()

        def _init_gui(self) -> None:
            root = QVBoxLayout(self)
            root.setContentsMargins(0, 0, 0, 0)
            self.chat_splitter = QSplitter(Qt.Orientation.Vertical, self)
            root.addWidget(self.chat_splitter, stretch=1)

            # Top pane: Pinned Messages (auto-shown) + Messages + Recipients
            top = QWidget(self.chat_splitter)
            top_v = QVBoxLayout(top)
            top_v.setContentsMargins(4, 4, 4, 4)
            top_v.setSpacing(4)

            self.pinned_group = QGroupBox("Pinned Messages", top)
            pinned_layout = QVBoxLayout(self.pinned_group)
            pinned_layout.setContentsMargins(4, 4, 4, 4)
            self.pinned_messages = QTextBrowser(self.pinned_group)
            self.pinned_messages.setReadOnly(True)
            self.pinned_messages.setOpenExternalLinks(False)
            self.pinned_messages.setOpenLinks(False)
            self.pinned_messages.setMaximumHeight(110)
            self.pinned_messages.anchorClicked.connect(self._on_anchor_clicked)
            pinned_layout.addWidget(self.pinned_messages)
            self.pinned_group.setVisible(False)
            top_v.addWidget(self.pinned_group)

            headers = QHBoxLayout()
            headers.addWidget(QLabel("Messages", top), stretch=3)
            headers.addWidget(QLabel("Recipients", top), stretch=1)
            top_v.addLayout(headers)

            panes = QHBoxLayout()
            self.messages = QTextBrowser(top)
            self.messages.setReadOnly(True)
            self.messages.setOpenExternalLinks(False)
            self.messages.setOpenLinks(False)
            self.messages.anchorClicked.connect(self._on_anchor_clicked)
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

            self.markup_btn = QToolButton(bottom)
            self.markup_btn.setText("Markup")
            self.markup_btn.setCheckable(True)
            self.markup_btn.setToolTip(
                "Enable GMA inline markup (**bold**, //italic//, __underline__, ~~strike~~, `code`)"
            )
            entry_hdr.addWidget(self.markup_btn)

            self.pin_btn = QToolButton(bottom)
            self.pin_btn.setText("\u2605 Pin")
            self.pin_btn.setCheckable(True)
            self.pin_btn.setToolTip("Pin this chat message for all players")
            entry_hdr.addWidget(self.pin_btn)

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

        def _is_gm(self) -> bool:
            return bool(
                self.service is not None
                and str(getattr(self.service, "username", "") or "") == "GM"
            )

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
            self._rerender_all_messages()
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
            pinned = self.pin_btn.isChecked()
            markup = self.markup_btn.isChecked()
            if pinned:
                self.pin_btn.setChecked(False)
            self.service.send_chat(msg, recipients=recips, pinned=pinned, markup=markup)
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

            tbl_call = parse_table_invocation(expanded)
            if tbl_call is not None:
                self._execute_table_roll(
                    clean_expr=clean_expr,
                    tbl_call=tbl_call,
                    blind=blind,
                    roll_to=roll_to,
                    history=history,
                    clear_entry=(expr is None),
                )
                return

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

        def _execute_table_roll(
            self,
            *,
            clean_expr: str,
            tbl_call: dict[str, Any],
            blind: bool,
            roll_to: bool,
            history: bool,
            clear_entry: bool,
        ) -> None:
            bank = self._get_table_bank() if self._get_table_bank is not None else None
            table_map = (
                (bank.global_tables_by_name if tbl_call["is_global"] else bank.tables_by_name)
                if bank is not None
                else {}
            )
            tbl_details = table_map.get(tbl_call["name"])
            if tbl_details is None:
                prefix = "##" if tbl_call["is_global"] else "#"
                self.add_message(
                    f"Lookup table {prefix}{tbl_call['name']} was not found.",
                    style="error",
                    newline=True,
                )
                return

            expanded_dieroll = self._expand_variables(str(tbl_details.get("dieroll") or "1d20"))
            final_expr = compose_table_roll_expression(
                tbl_call["title"], expanded_dieroll, tbl_call["rest"]
            )

            if self.service is not None and self.service.connected():
                self._req_counter += 1
                flags_str = ("m" if tbl_details.get("markup") else "") + ("b" if blind else "")
                prefix = "##" if tbl_call["is_global"] else "#"
                tkey = bank.tkey if bank is not None else ""
                req_id = f"{prefix}{tbl_call['name']};{tkey};{flags_str};r{self._req_counter}"
                recips = self.selected_recipients() if roll_to else None
                self.service.roll_dice(
                    final_expr,
                    blind=blind,
                    recipients=recips,
                    request_id=req_id,
                )
            else:
                totals = self._run_offline_roll(final_expr)
                pairs_or_flat = tbl_details.get("pairs") or tbl_details.get("table") or []
                display_name = (
                    tbl_details.get("description")
                    or tbl_details.get("Description")
                    or tbl_call["name"]
                )
                use_markup = bool(tbl_details.get("markup", False))
                for total in totals:
                    outcome = lookup_table_outcome(total, pairs_or_flat)
                    if outcome is not None:
                        self.add_messages(
                            [
                                {"text": "Offline table lookup: ", "style": "user", "newline": False},
                                {
                                    "text": f"rolled {total} on {display_name}: ",
                                    "style": "rolllabel",
                                    "newline": False,
                                },
                                {"text": outcome, "markup": use_markup, "newline": True},
                            ]
                        )

            if history and self._on_history_add is not None:
                self._on_history_add(clean_expr)
            if clear_entry:
                self.chattext.clear()

        def handle_roll_payload(self, payload: dict[str, Any]) -> None:
            """Resolve incoming online ``ROLL`` payloads for `#table` / `##table` ``RequestID``s."""
            if self._get_table_bank is None or self.service is None or not self.service.connected():
                return
            bank = self._get_table_bank()
            banks_by_tkey = {bank.tkey: bank} if bank.tkey else None
            reply = resolve_table_roll_reply(
                payload,
                banks_by_tkey=banks_by_tkey,
                default_bank=bank,
                is_gm=self._is_gm(),
            )
            if reply is None:
                return
            recips = (
                list(reply.get("recipients") or [])
                if not reply.get("to_all") and not reply.get("to_gm")
                else None
            )
            self.service.send_chat(
                str(reply.get("text") or ""),
                recipients=recips,
                markup=bool(reply.get("markup", False)),
                to_gm=bool(reply.get("to_gm", False)),
            )

        def _run_offline_roll(self, expr: str) -> list[int]:
            totals: list[int] = []
            label, data = self.roller.do_roll(expr)
            for total, details in data:
                totals.append(int(total))
                self.add_message("Offline die roll: ", style="user", newline=False)
                if label:
                    self.add_message(f"{label}: ", style="rolllabel", newline=False)
                for tag, text in details:
                    if tag == "roll":
                        self.add_message(f"({text}) ", style="roll", newline=False)
                    else:
                        self.add_message(f"{text} ", style=tag, newline=False)
                self.add_message(" ", newline=True)
            return totals

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

        def set_pinned_panel_enabled(self, enabled: bool) -> None:
            """Enable or hide the Pinned Messages box above the chat log."""
            self.allow_pinned_panel = bool(enabled)
            self._refresh_pinned_messages()

        def _append_html_to_browser(self, browser: QTextBrowser, frag: str, newline: bool) -> None:
            cursor = browser.textCursor()
            cursor.movePosition(QTextCursor.MoveOperation.End)
            cursor.insertHtml(frag)
            if newline:
                cursor.insertText("\n")
            browser.setTextCursor(cursor)
            browser.ensureCursorVisible()

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
                copied = dict(msg)
                self.message_buffer.append(copied)
                self.stream_items.append({"kind": "segment", "msg": copied})

            frag = render_message_segment_html(msg, self.settings)
            self._append_html_to_browser(self.messages, frag, bool(msg.get("newline")))

        def append_chat_payload(self, payload: dict[str, Any]) -> None:
            """Record and display an incoming ``TO`` chat payload, updating Pinned Messages."""
            msg_id = payload.get("MessageID")
            if msg_id is not None:
                try:
                    if self.min_msgid > int(msg_id):
                        return
                except (TypeError, ValueError):
                    pass

            with self.mutex:
                entry = self.history_manager.add_chat_message(payload)
                if bool(entry.get("_duplicate", False)):
                    self._rerender_all_messages_unlocked()
                    return
                self.stream_items.append(
                    {"kind": "chat", "msgid": entry.get("MessageID"), "entry": entry}
                )
                is_local_pin = self._is_locally_pinned(entry.get("MessageID"))
                frag = render_chat_entry_html(
                    entry,
                    self.settings,
                    is_pinned_view=False,
                    is_locally_pinned=is_local_pin,
                    is_gm=self._is_gm(),
                )
                self._append_html_to_browser(self.messages, frag, newline=True)
                if bool(entry.get("Pin", False)) or is_local_pin:
                    self._refresh_pinned_messages()

        def _is_locally_pinned(self, msg_id: Any) -> bool:
            if msg_id is None:
                return False
            try:
                return int(msg_id) in self.history_manager.pin_list
            except (TypeError, ValueError):
                return False

        def _refresh_pinned_messages(self) -> None:
            pinned = self.history_manager.pinned_entries()
            self.pinned_messages.clear()
            if not pinned or not self.allow_pinned_panel:
                self.pinned_group.setVisible(False)
                return
            self.pinned_group.setVisible(True)
            is_gm = self._is_gm()
            for entry in pinned:
                frag = render_chat_entry_html(
                    entry,
                    self.settings,
                    is_pinned_view=True,
                    is_locally_pinned=self._is_locally_pinned(entry.get("MessageID")),
                    is_gm=is_gm,
                )
                self._append_html_to_browser(self.pinned_messages, frag, newline=True)

        def _rerender_all_messages(self) -> None:
            with self.mutex:
                self._rerender_all_messages_unlocked()

        def _rerender_all_messages_unlocked(self) -> None:
            self.messages.clear()
            is_gm = self._is_gm()
            visible_chat_ids: set[int] = set()
            for entry in self.history_manager.visible_entries():
                if entry.get("kind", "chat") == "chat" and entry.get("MessageID") is not None:
                    try:
                        visible_chat_ids.add(int(entry["MessageID"]))
                    except (TypeError, ValueError):
                        pass
            active_entries = {id(e) for e in self.history_manager.visible_entries()}

            for item in self.stream_items:
                if item.get("kind") == "segment":
                    msg = item["msg"]
                    frag = render_message_segment_html(msg, self.settings)
                    self._append_html_to_browser(self.messages, frag, bool(msg.get("newline")))
                elif item.get("kind") == "chat":
                    entry = item["entry"]
                    mid = entry.get("MessageID")
                    if id(entry) not in active_entries:
                        if mid is None:
                            continue
                        try:
                            if int(mid) not in visible_chat_ids:
                                continue
                        except (TypeError, ValueError):
                            continue
                    frag = render_chat_entry_html(
                        entry,
                        self.settings,
                        is_pinned_view=False,
                        is_locally_pinned=self._is_locally_pinned(mid),
                        is_gm=is_gm,
                    )
                    self._append_html_to_browser(self.messages, frag, newline=True)
            self._refresh_pinned_messages()

        def clear_chat_messages(self, include_pinned: bool = False) -> None:
            """Clear chat log (preserving pinned chat entries unless ``include_pinned=True``)."""
            with self.mutex:
                self.history_manager.clear_chat_history(target=0, do_all=include_pinned)
                kept_entries = {id(e) for e in self.history_manager.entries}
                self.stream_items = [
                    it
                    for it in self.stream_items
                    if it.get("kind") == "chat" and id(it.get("entry")) in kept_entries
                ]
                if include_pinned:
                    self.message_buffer.clear()
                self._rerender_all_messages_unlocked()

        def clear_pinned_messages(self) -> int:
            """Unpin locally pinned messages and hide server-pinned messages, then re-render."""
            with self.mutex:
                count = self.history_manager.clear_pinned_messages()
                self._rerender_all_messages_unlocked()
                return count

        def handle_clear_chat_payload(self, payload: dict[str, Any]) -> None:
            """Apply incoming ``CC`` server clear/delete command and re-render."""
            targets_raw = payload.get("TargetMessages")
            targets: list[int] | None = None
            if isinstance(targets_raw, list):
                targets = []
                for raw in targets_raw:
                    try:
                        targets.append(int(raw))
                    except (TypeError, ValueError):
                        pass
            target = int(payload.get("Target", 0) or 0)
            do_all = bool(payload.get("DoAll", False)) or bool(targets)
            with self.mutex:
                self.history_manager.clear_chat_history(
                    target=target,
                    target_messages=targets,
                    do_all=do_all,
                )
                if targets is not None:
                    tset = set(targets)
                    self.stream_items = [
                        it for it in self.stream_items if it.get("msgid") not in tset
                    ]
                elif target == 0:
                    kept_entries = {id(e) for e in self.history_manager.entries}
                    self.stream_items = [
                        it
                        for it in self.stream_items
                        if it.get("kind") == "chat" and id(it.get("entry")) in kept_entries
                    ]
                self._rerender_all_messages_unlocked()

        def handle_prune_chat_payload(self, payload: dict[str, Any]) -> None:
            """Apply incoming ``Y2`` history pruning bounds and re-render."""
            min_id = payload.get("MinID")
            max_id = payload.get("MaxID")
            with self.mutex:
                self.history_manager.prune_chat_history(min_id=min_id, max_id=max_id)
                self._rerender_all_messages_unlocked()

        def _on_anchor_clicked(self, url: QUrl) -> None:
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
                self._rerender_all_messages()
            elif action == "unpin":
                self.history_manager.unpin_message(msg_id)
                self._rerender_all_messages()
            elif action == "hide":
                self.history_manager.hide_message(msg_id)
                self._rerender_all_messages()
            elif action == "del":
                if self.service is not None and hasattr(self.service, "delete_chat_message"):
                    self.service.delete_chat_message(msg_id)
