"""Dialog to specify which character(s) the user is controlling (`AKA`).

Ported from `selectAKA`, `select_aka_toggle_none`, and `check_aka` in
`bin/mapper_legacy.tcl`.
"""

from __future__ import annotations

from typing import Any

try:
    from PySide6.QtWidgets import (
        QCheckBox,
        QDialog,
        QDialogButtonBox,
        QHBoxLayout,
        QLabel,
        QLineEdit,
        QScrollArea,
        QVBoxLayout,
        QWidget,
    )

    QT_AVAILABLE = True
except ImportError:  # pragma: no cover
    QT_AVAILABLE = False


def parse_custom_aka_names(raw: str) -> list[str]:
    """Parse comma-separated custom character names, preserving order and deduplicating."""
    out: list[str] = []
    seen: set[str] = set()
    for part in str(raw or "").split(","):
        clean = part.strip()
        if clean and clean not in seen:
            seen.add(clean)
            out.append(clean)
    return out


if QT_AVAILABLE:

    class SelectAKADialog(QDialog):
        """Character identity selection dialog (`Who Are You?`) sending `AKA`."""

        def __init__(
            self,
            known_pcs: list[str] | tuple[str, ...] = (),
            current_aka: list[str] | tuple[str, ...] = (),
            local_user: str = "",
            im_not_playing: bool = False,
            show_suppress_option: bool = False,
            parent: QWidget | None = None,
        ) -> None:
            super().__init__(parent)
            self.setWindowTitle("Who Are You?")
            self.resize(400, 320)

            layout = QVBoxLayout(self)

            if show_suppress_option and local_user:
                layout.addWidget(
                    QLabel(
                        f'I don\'t see a character called "{local_user}" on the map.',
                        self,
                    )
                )

            layout.addWidget(
                QLabel(
                    "Please indicate which character(s) you're controlling in this session:",
                    self,
                )
            )

            sorted_pcs = sorted({str(n).strip() for n in known_pcs if str(n).strip()})
            known_set = set(sorted_pcs)
            clean_current = [str(n).strip() for n in current_aka if str(n).strip()]
            current_set = set(clean_current)
            custom_names = [n for n in clean_current if n not in known_set]

            scroll = QScrollArea(self)
            scroll.setWidgetResizable(True)
            scroll.setMaximumHeight(200)
            pc_host = QWidget(scroll)
            pc_layout = QVBoxLayout(pc_host)
            pc_layout.setContentsMargins(6, 6, 6, 6)
            pc_layout.setSpacing(4)

            self.pc_checkboxes: dict[str, QCheckBox] = {}
            if sorted_pcs:
                for name in sorted_pcs:
                    chk = QCheckBox(name, pc_host)
                    chk.setChecked(name in current_set)
                    pc_layout.addWidget(chk)
                    self.pc_checkboxes[name] = chk
            else:
                empty_lbl = QLabel(
                    "No player characters are currently loaded on the map.",
                    pc_host,
                )
                empty_lbl.setStyleSheet("color: gray; font-style: italic;")
                pc_layout.addWidget(empty_lbl)
            pc_layout.addStretch(1)
            scroll.setWidget(pc_host)
            layout.addWidget(scroll, stretch=1)

            custom_row = QHBoxLayout()
            custom_row.addWidget(QLabel("Custom:", self))
            self.custom_edit = QLineEdit(", ".join(custom_names), self)
            self.custom_edit.setPlaceholderText(
                "Optional comma-separated custom character name(s)"
            )
            custom_row.addWidget(self.custom_edit, stretch=1)
            layout.addLayout(custom_row)

            none_label = (
                f"I am not playing any character from the username {local_user}."
                if local_user
                else "I am not playing any character in this session."
            )
            self.not_playing_chk = QCheckBox(none_label, self)
            layout.addWidget(self.not_playing_chk)

            self.suppress_chk: QCheckBox | None = None
            if show_suppress_option:
                self.suppress_chk = QCheckBox("Don't ask me again this session", self)
                layout.addWidget(self.suppress_chk)

            buttons = QDialogButtonBox(
                QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel,
                self,
            )
            buttons.accepted.connect(self.accept)
            buttons.rejected.connect(self.reject)
            layout.addWidget(buttons)

            self.not_playing_chk.toggled.connect(self._on_toggle_not_playing)
            self.not_playing_chk.setChecked(bool(im_not_playing))
            self._on_toggle_not_playing(bool(im_not_playing))

        def _on_toggle_not_playing(self, checked: bool) -> None:
            enabled = not bool(checked)
            for chk in self.pc_checkboxes.values():
                chk.setEnabled(enabled)
            self.custom_edit.setEnabled(enabled)

        def not_playing(self) -> bool:
            return bool(self.not_playing_chk.isChecked())

        def selected_names(self) -> list[str]:
            if self.not_playing():
                return []
            out: list[str] = []
            seen: set[str] = set()
            for name, chk in self.pc_checkboxes.items():
                if chk.isChecked() and name not in seen:
                    seen.add(name)
                    out.append(name)
            for name in parse_custom_aka_names(self.custom_edit.text()):
                if name not in seen:
                    seen.add(name)
                    out.append(name)
            return out

        def suppress_session_prompt(self) -> bool:
            return bool(self.suppress_chk.isChecked()) if self.suppress_chk is not None else False

else:  # pragma: no cover

    class SelectAKADialog:  # type: ignore[no-redef]
        def __init__(self, *_args: Any, **_kwargs: Any) -> None:
            pass
