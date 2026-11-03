"""Chat and Dice Roller dockable panel and pure-Python roll result formatter.

Ported from die-roll and chat display logic in ``bin/mapper.tcl``.
"""

from __future__ import annotations

import html
from typing import Any

from gma_mapper.core.minimarkup import render_html
from gma_mapper.core.profile import default_styles

try:
    from PySide6.QtCore import Qt, Signal
    from PySide6.QtWidgets import (
        QWidget,
        QVBoxLayout,
        QHBoxLayout,
        QTextBrowser,
        QLineEdit,
        QPushButton,
        QComboBox,
        QTableWidget,
        QTableWidgetItem,
        QHeaderView,
        QSplitter,
        QLabel,
    )
    HAS_PYSIDE6 = True
except ImportError:
    HAS_PYSIDE6 = False


def _apply_component_template(template: Any, value: str) -> str:
    """Apply a component style dict (`{"format": "..."}`) or `[prefix, suffix]` template around `value`."""
    if not template:
        return value
    if isinstance(template, dict):
        fmt = str(template.get("format", "%s"))
        if "%s" in fmt:
            return fmt.replace("%s", value)
        return f"{fmt}{value}"
    if isinstance(template, (list, tuple)):
        if len(template) == 1:
            return f"{template[0]}{value}"
        return f"{template[0]}{value}{template[1]}"
    return value


def format_roll_components(
    components: list[dict[str, Any]],
    comp_styles: dict[str, list[str]] | None = None,
) -> str:
    """Format structured die-roll ``Details`` components into a rich HTML fragment."""
    if comp_styles is None:
        comp_styles = default_styles()["dierolls"]["components"]

    parts: list[str] = []
    for comp in components:
        ctype = str(comp.get("Type", comp.get("type", "constant")))
        val = comp.get("Value", comp.get("value", ""))
        text_val = html.escape(str(val))
        tpl = comp_styles.get(ctype)
        if tpl:
            parts.append(_apply_component_template(tpl, text_val))
        else:
            parts.append(text_val)
    return " ".join(parts)


def format_roll_result(
    payload: dict[str, Any],
    styles: dict[str, Any] | None = None,
) -> str:
    """Format a ``ROLL`` server message payload into HTML for the chat/dice transcript."""
    if styles is None:
        styles = default_styles()
    dieroll_styles = styles.get("dierolls", default_styles()["dierolls"])
    comp_styles = dieroll_styles.get("components", default_styles()["dierolls"]["components"])

    sender = html.escape(str(payload.get("Sender", payload.get("Origin", payload.get("From", "System")))))
    title = render_html(str(payload.get("Title", "")))
    recipients = payload.get("Recipients", payload.get("Targets", payload.get("To", [])))
    to_prefix = ""
    if recipients:
        if isinstance(recipients, list):
            rec_str = ", ".join(html.escape(str(r)) for r in recipients)
        else:
            rec_str = html.escape(str(recipients))
        to_prefix = f" <i>(to {rec_str})</i>"
    elif payload.get("ToGM"):
        to_prefix = " <i>(to GM)</i>"

    result_blocks: list[str] = []
    results = payload.get("Results", [])
    if not results and isinstance(payload.get("Result"), dict):
        results = [payload["Result"]]
    if isinstance(results, list) and results:
        for res in results:
            if isinstance(res, dict):
                total = res.get("Result", res.get("Value", res.get("Total", "")))
                details = res.get("Details", res.get("Components", []))
                total_html = _apply_component_template(
                    comp_styles.get("total", ["=", ""]),
                    html.escape(str(total)),
                )
                if isinstance(details, list) and details:
                    comp_html = format_roll_components(details, comp_styles)
                    result_blocks.append(f"{comp_html} {total_html}")
                else:
                    result_blocks.append(total_html)
            else:
                result_blocks.append(html.escape(str(res)))
    elif "Result" in payload or "Value" in payload:
        val = payload.get("Result", payload.get("Value", ""))
        result_blocks.append(
            _apply_component_template(comp_styles.get("total", ["=", ""]), html.escape(str(val)))
        )

    title_part = f" <b>{title}</b>:" if title else ":"
    body_part = " ; ".join(result_blocks)
    return f"<div class='roll-msg'><b>{sender}</b>{to_prefix}{title_part} {body_part}</div>"


def format_chat_message(payload: dict[str, Any]) -> str:
    """Format a ``TO`` chat message payload into HTML using ``minimarkup.render_html``."""
    sender = html.escape(str(payload.get("Sender", payload.get("Origin", payload.get("From", "System")))))
    raw_text = str(payload.get("Text", payload.get("Message", "")))
    rendered = render_html(raw_text)
    targets = payload.get("Recipients", payload.get("Targets", payload.get("To", [])))
    to_prefix = ""
    if targets:
        if isinstance(targets, list):
            rec_str = ", ".join(html.escape(str(r)) for r in targets)
        else:
            rec_str = html.escape(str(targets))
        to_prefix = f" <i>(to {rec_str})</i>"
    elif payload.get("ToGM"):
        to_prefix = " <i>(to GM)</i>"
    return f"<div class='chat-msg'><b>&lt;{sender}&gt;</b>{to_prefix} {rendered}</div>"


if HAS_PYSIDE6:

    class ChatDicePanel(QWidget):
        """Dockable panel combining Chat Transcript, Quick Roll / Message Bar, and Preset Table."""

        rollRequested = Signal(str, str, list)      # (title, formula, targets)
        chatSent = Signal(str, list)                # (message_text, targets)
        clearChatRequested = Signal(int)            # keep_count

        def __init__(self, parent: QWidget | None = None) -> None:
            super().__init__(parent)
            self.presets: list[dict[str, Any]] = []

            layout = QVBoxLayout(self)
            layout.setContentsMargins(6, 6, 6, 6)

            splitter = QSplitter(Qt.Orientation.Vertical, self)

            # Upper pane: Chat & Roll Transcript
            transcript_container = QWidget(splitter)
            t_layout = QVBoxLayout(transcript_container)
            t_layout.setContentsMargins(0, 0, 0, 0)

            self.transcript = QTextBrowser(transcript_container)
            self.transcript.setOpenExternalLinks(False)
            t_layout.addWidget(self.transcript, 1)

            # Entry bar
            entry_row = QHBoxLayout()
            self.recipient_combo = QComboBox(transcript_container)
            self.recipient_combo.addItem("All", [])
            self.recipient_combo.addItem("GM Only", ["GM"])
            self.recipient_combo.addItem("Self", ["SELF"])
            entry_row.addWidget(self.recipient_combo)

            self.input_edit = QLineEdit(transcript_container)
            self.input_edit.setPlaceholderText("Enter chat message or /roll 1d20+5 ...")
            self.input_edit.returnPressed.connect(self._on_send_input)
            entry_row.addWidget(self.input_edit, 1)

            self.send_btn = QPushButton("Send", transcript_container)
            self.send_btn.clicked.connect(self._on_send_input)
            entry_row.addWidget(self.send_btn)

            t_layout.addLayout(entry_row)
            splitter.addWidget(transcript_container)

            # Lower pane: Die-Roll Presets Table
            preset_container = QWidget(splitter)
            p_layout = QVBoxLayout(preset_container)
            p_layout.setContentsMargins(0, 0, 0, 0)

            p_header = QHBoxLayout()
            p_header.addWidget(QLabel("Die-Roll Presets (Double-click to roll):", preset_container))
            p_layout.addLayout(p_header)

            self.preset_table = QTableWidget(0, 3, preset_container)
            self.preset_table.setHorizontalHeaderLabels(["Name", "Description", "Formula"])
            self.preset_table.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeMode.Stretch)
            self.preset_table.cellDoubleClicked.connect(self._on_preset_double_clicked)
            p_layout.addWidget(self.preset_table, 1)

            splitter.addWidget(preset_container)
            layout.addWidget(splitter, 1)

        def current_targets(self) -> list[str]:
            data = self.recipient_combo.currentData()
            return list(data) if isinstance(data, list) else []

        def _on_send_input(self) -> None:
            text = self.input_edit.text().strip()
            if not text:
                return
            self.input_edit.clear()
            targets = self.current_targets()
            if text.startswith("/roll ") or text.startswith("/r "):
                spec = text.split(" ", 1)[1].strip()
                self.rollRequested.emit("Custom Roll", spec, targets)
            else:
                self.chatSent.emit(text, targets)

        def _on_preset_double_clicked(self, row: int, _col: int) -> None:
            if 0 <= row < len(self.presets):
                preset = self.presets[row]
                name = str(preset.get("Name", ""))
                spec = str(preset.get("DieRollSpec", ""))
                if spec:
                    self.rollRequested.emit(name, spec, self.current_targets())

        def set_presets(self, presets: list[dict[str, Any]]) -> None:
            """Populate the die-roll presets table from ``DD`` / ``DD=`` or local ``.dice`` file."""
            self.presets = list(presets)
            self.preset_table.setRowCount(len(self.presets))
            for idx, p in enumerate(self.presets):
                self.preset_table.setItem(idx, 0, QTableWidgetItem(str(p.get("Name", ""))))
                self.preset_table.setItem(idx, 1, QTableWidgetItem(str(p.get("Description", ""))))
                self.preset_table.setItem(idx, 2, QTableWidgetItem(str(p.get("DieRollSpec", ""))))

        def append_roll(self, payload: dict[str, Any], styles: dict[str, Any] | None = None) -> None:
            self.transcript.append(format_roll_result(payload, styles))

        def append_chat(self, payload: dict[str, Any]) -> None:
            self.transcript.append(format_chat_message(payload))

        def clear_messages(self, keep_last: int = 0) -> None:
            if keep_last <= 0:
                self.transcript.clear()

else:

    class ChatDicePanel:  # type: ignore[no-redef]
        def __init__(self, parent: Any = None) -> None:
            self.presets: list[dict[str, Any]] = []
            self.messages: list[str] = []

        def set_presets(self, presets: list[dict[str, Any]]) -> None:
            self.presets = list(presets)

        def append_roll(self, payload: dict[str, Any], styles: dict[str, Any] | None = None) -> None:
            self.messages.append(format_roll_result(payload, styles))

        def append_chat(self, payload: dict[str, Any]) -> None:
            self.messages.append(format_chat_message(payload))

        def clear_messages(self, keep_last: int = 0) -> None:
            if keep_last <= 0:
                self.messages.clear()
            else:
                self.messages = self.messages[-keep_last:]
