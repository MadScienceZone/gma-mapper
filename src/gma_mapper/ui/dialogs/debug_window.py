"""Modeless Diagnostic / Debug Message Window (`DiagnosticWindow`).

Ported from `DEBUG`, `DEBUGp`, `INFO`, and `SaveDebugText` in ``bin/mapper.tcl``:
spawns an independent top-level window for errors, enabled debug levels,
informational notices, and optional protocol traces with light/dark parity.
"""

from __future__ import annotations

import html
from typing import Any, Callable, Sequence

try:
    from PySide6.QtCore import Qt
    from PySide6.QtGui import QFont, QFontDatabase, QIcon, QTextCursor
    from PySide6.QtWidgets import (
        QCheckBox,
        QHBoxLayout,
        QLabel,
        QPushButton,
        QTextEdit,
        QVBoxLayout,
        QWidget,
    )

    QT_AVAILABLE = True
except ImportError:  # pragma: no cover
    QT_AVAILABLE = False


def diagnostic_base_colors(dark_mode: bool = False) -> dict[str, str]:
    """Return base background, foreground, and selection colors for ``DiagnosticWindow``."""
    if dark_mode:
        return {
            "bg": "#232323",
            "fg": "#ffffff",
            "sel_bg": "#ffffff",
            "sel_fg": "#232323",
        }
    return {
        "bg": "#cccccc",
        "fg": "#000000",
        "sel_bg": "#0000ff",
        "sel_fg": "#cccccc",
    }


def diagnostic_tag_colors(tag: str, dark_mode: bool = False) -> tuple[str, str]:
    """Return `(fg_hex, bg_hex)` matching legacy `.debugwindow.text` tag styling."""
    norm = str(tag or "").strip().upper()
    if norm == "ERROR":
        return ("#ff0000", "#ffff00")
    if norm == "DEBUG 1":
        return ("#ffff00", "#232323") if dark_mode else ("#ff0000", "#cccccc")
    if norm == "DEBUG 2":
        return ("#000000", "#ffff00")
    if norm.startswith("DEBUG "):
        return ("#ffffff", "#232323") if dark_mode else ("#0000ff", "#cccccc")
    if norm == "INFO":
        return ("#ffffff", "#0000ff")
    if norm == "PROTOCOL":
        return ("#ffffff", "#666666")
    base = diagnostic_base_colors(dark_mode)
    return (base["fg"], base["bg"])


def should_display_diagnostic(tag: str, show_protocol: bool) -> bool:
    """Return whether an entry with ``tag`` should be shown given ``show_protocol``."""
    if str(tag or "").strip().upper() == "PROTOCOL":
        return bool(show_protocol)
    return True


def format_diagnostic_line_html(
    tag: str,
    line: str,
    dark_mode: bool = False,
) -> str:
    """Format a single diagnostic message line as an HTML block."""
    fg, bg = diagnostic_tag_colors(tag, dark_mode=dark_mode)
    norm = str(tag or "").strip().upper()
    text = str(line)
    if norm == "INFO" and not text.startswith("[info] "):
        text = f"[info] {text}"
    escaped = html.escape(text)
    return (
        f'<div style="white-space:pre-wrap; margin:0; padding:0 2px; '
        f'color:{fg}; background-color:{bg};">{escaped}</div>'
    )


def format_diagnostic_entries_text(entries: Sequence[tuple[str, str]]) -> str:
    """Format `(tag, line)` pairs matching legacy ``SaveDebugText``."""
    return "\n".join(f"{tag:<8}|{line}" for tag, line in entries)


if QT_AVAILABLE:

    class DiagnosticWindow(QWidget):
        """Modeless top-level window displaying errors and diagnostic messages."""

        def __init__(
            self,
            entries_provider: Callable[[], Sequence[tuple[str, str]]] | None = None,
            save_cb: Callable[[], None] | None = None,
            clear_cb: Callable[[], Any] | None = None,
            dark_mode: bool = False,
            show_protocol: bool = False,
            max_lines: int = 5000,
            window_icon: QIcon | None = None,
        ) -> None:
            super().__init__(None, Qt.WindowType.Window)
            self._entries_provider = entries_provider
            self._save_cb = save_cb
            self._clear_cb = clear_cb
            self.dark_mode: bool = bool(dark_mode)
            self.show_protocol: bool = bool(show_protocol)
            self.max_lines: int = max(1, int(max_lines))
            self._displayed_lines: int = 0

            self.setWindowTitle("Diagnostic Messages")
            if window_icon is not None and not window_icon.isNull():
                self.setWindowIcon(window_icon)
            self.resize(760, 440)

            layout = QVBoxLayout(self)
            layout.setContentsMargins(6, 6, 6, 6)
            layout.setSpacing(6)

            self.text_view = QTextEdit(self)
            self.text_view.setReadOnly(True)
            self.text_view.setUndoRedoEnabled(False)
            self.text_view.setLineWrapMode(QTextEdit.LineWrapMode.WidgetWidth)
            mono_font = QFontDatabase.systemFont(QFontDatabase.SystemFont.FixedFont)
            if not mono_font.family():
                mono_font = QFont("Courier New", 10)
            self.text_view.setFont(mono_font)
            layout.addWidget(self.text_view, stretch=1)

            btn_row = QHBoxLayout()
            btn_row.setContentsMargins(0, 0, 0, 0)
            btn_row.setSpacing(8)

            self.chk_show_protocol = QCheckBox("Show protocol traces", self)
            self.chk_show_protocol.setChecked(self.show_protocol)
            self.chk_show_protocol.toggled.connect(self._on_show_protocol_toggled)
            btn_row.addWidget(self.chk_show_protocol)

            self.count_label = QLabel("0 lines", self)
            btn_row.addWidget(self.count_label)
            btn_row.addStretch(1)

            self.btn_save = QPushButton("Save As...", self)
            self.btn_save.clicked.connect(self._on_save_clicked)
            btn_row.addWidget(self.btn_save)

            self.btn_clear = QPushButton("Clear", self)
            self.btn_clear.clicked.connect(self._on_clear_clicked)
            btn_row.addWidget(self.btn_clear)

            self.btn_close = QPushButton("Close", self)
            self.btn_close.clicked.connect(self.close)
            btn_row.addWidget(self.btn_close)

            layout.addLayout(btn_row)

            self._apply_text_view_style()
            if self._entries_provider is not None:
                self.set_entries(self._entries_provider())

        def _update_count_label(self) -> None:
            noun = "line" if self._displayed_lines == 1 else "lines"
            self.count_label.setText(f"{self._displayed_lines} {noun}")

        def _apply_text_view_style(self) -> None:
            base = diagnostic_base_colors(self.dark_mode)
            self.text_view.setStyleSheet(
                f"QTextEdit {{ background-color: {base['bg']}; color: {base['fg']}; "
                f"selection-background-color: {base['sel_bg']}; "
                f"selection-color: {base['sel_fg']}; }}"
            )

        def _on_show_protocol_toggled(self, checked: bool) -> None:
            self.show_protocol = bool(checked)
            if self._entries_provider is not None:
                self.set_entries(self._entries_provider())

        def _on_save_clicked(self) -> None:
            if self._save_cb is not None:
                self._save_cb()

        def _on_clear_clicked(self) -> None:
            if self._clear_cb is not None:
                self._clear_cb()
            else:
                self.clear_entries()

        def apply_theme(self, dark_mode: bool) -> None:
            """Update light/dark theme colors and re-render current entries."""
            self.dark_mode = bool(dark_mode)
            self._apply_text_view_style()
            if self._entries_provider is not None:
                self.set_entries(self._entries_provider())

        def set_show_protocol(self, show: bool) -> None:
            """Toggle protocol trace visibility and re-render."""
            show_b = bool(show)
            self.show_protocol = show_b
            self.chk_show_protocol.blockSignals(True)
            self.chk_show_protocol.setChecked(show_b)
            self.chk_show_protocol.blockSignals(False)
            if self._entries_provider is not None:
                self.set_entries(self._entries_provider())

        def set_entries(self, entries: Sequence[tuple[str, str]]) -> None:
            """Replace window contents from a sequence of ``(tag, line)`` tuples."""
            filtered = [
                (tag, line)
                for tag, line in entries
                if should_display_diagnostic(tag, self.show_protocol)
            ]
            if len(filtered) > self.max_lines:
                filtered = filtered[-self.max_lines :]
            base = diagnostic_base_colors(self.dark_mode)
            if filtered:
                blocks = "".join(
                    format_diagnostic_line_html(tag, line, dark_mode=self.dark_mode)
                    for tag, line in filtered
                )
                self.text_view.setHtml(
                    f'<body style="margin:0; background-color:{base["bg"]}; '
                    f'color:{base["fg"]};">{blocks}</body>'
                )
            else:
                self.text_view.clear()
            self._displayed_lines = len(filtered)
            self._update_count_label()
            sb = self.text_view.verticalScrollBar()
            sb.setValue(sb.maximum())

        def append_entry(self, tag: str, line: str) -> bool:
            """Append a single `(tag, line)` entry, auto-scrolling when near the bottom."""
            if not should_display_diagnostic(tag, self.show_protocol):
                return False
            sb = self.text_view.verticalScrollBar()
            at_bottom = sb.maximum() == 0 or sb.value() >= sb.maximum() - max(
                20, sb.pageStep() // 10
            )
            block_html = format_diagnostic_line_html(
                tag, line, dark_mode=self.dark_mode
            )
            self.text_view.append(block_html)
            self._displayed_lines += 1
            if self._displayed_lines > self.max_lines:
                cursor = self.text_view.textCursor()
                cursor.movePosition(QTextCursor.MoveOperation.Start)
                cursor.movePosition(
                    QTextCursor.MoveOperation.Down,
                    QTextCursor.MoveMode.KeepAnchor,
                    self._displayed_lines - self.max_lines,
                )
                cursor.removeSelectedText()
                self._displayed_lines = self.max_lines
            self._update_count_label()
            if at_bottom:
                sb.setValue(sb.maximum())
            return True

        def clear_entries(self) -> None:
            """Clear all displayed lines in the diagnostic window."""
            self.text_view.clear()
            self._displayed_lines = 0
            self._update_count_label()

else:

    class DiagnosticWindow:  # type: ignore[no-redef]
        """Headless stub when PySide6 is unavailable."""

        def __init__(self, *_args: Any, **_kwargs: Any) -> None:
            pass
