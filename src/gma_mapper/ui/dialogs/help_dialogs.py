"""Help dialogs for GMA Mapper (`About GMA Mapper` and `Text Markup Syntax`).

Ported from `aboutMapper` (`bin/mapper_legacy.tcl`) and
`gma::minimarkup::ShowMarkupSyntax` (`bin/minimarkup.tcl`).
"""

from __future__ import annotations

from typing import Any

from gma_mapper import (
    GMAMapperDiceFileFormat,
    GMAMapperFileFormat,
    GMAMapperProtocol,
    GMAMapperVersion,
)
from gma_mapper.core.minimarkup import MARKUP_SYNTAX_HELP_HTML

try:
    from PySide6.QtWidgets import (
        QDialog,
        QDialogButtonBox,
        QLabel,
        QTextBrowser,
        QVBoxLayout,
        QWidget,
    )

    QT_AVAILABLE = True
except ImportError:  # pragma: no cover
    QT_AVAILABLE = False


def format_about_mapper_info(session: Any | None = None) -> tuple[str, str]:
    """Return `(main_message, connection_detail)` matching legacy `aboutMapper`."""
    main_message = (
        f"GMA VTT Mapper Client, Version {GMAMapperVersion}.\n\n"
        "Copyright \u00a9 Steve Willoughby, Aloha, Oregon, USA. All Rights Reserved. "
        "Distributed under the terms and conditions of the 3-Clause BSD License.\n\n"
        f"This client supports file format {GMAMapperFileFormat}, "
        f"dice preset format {GMAMapperDiceFileFormat}, "
        f"and server protocol {GMAMapperProtocol}."
    )

    if session is not None and session.is_enabled():
        if session.is_connected:
            if session.is_ready():
                connection_detail = (
                    f"Connected to {session.host}:{session.port} as {session.username}. "
                    f"The server is version {session.server_version} and speaks protocol {session.protocol}."
                )
            else:
                connection_detail = (
                    f"This mapper is negotiating its connection to {session.host}."
                )
        else:
            connection_detail = (
                f"This mapper wants to connect to {session.host}:{session.port}, "
                "but it has not yet connected."
            )
    else:
        connection_detail = "This mapper is running offline."

    return (main_message, connection_detail)


if QT_AVAILABLE:

    class AboutMapperDialog(QDialog):
        """Application version, copyright, and live connection summary dialog (`F1`)."""

        def __init__(
            self,
            session: Any | None = None,
            parent: QWidget | None = None,
        ) -> None:
            super().__init__(parent)
            self.setWindowTitle("About GMA Mapper")
            self.resize(460, 220)

            main_message, connection_detail = format_about_mapper_info(session)
            layout = QVBoxLayout(self)

            self.main_label = QLabel(main_message, self)
            self.main_label.setWordWrap(True)
            layout.addWidget(self.main_label)

            self.connection_label = QLabel(connection_detail, self)
            self.connection_label.setWordWrap(True)
            self.connection_label.setStyleSheet("color: #666666; padding-top: 6px;")
            layout.addWidget(self.connection_label)

            buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok, self)
            buttons.accepted.connect(self.accept)
            layout.addWidget(buttons)

    class MarkupSyntaxHelpDialog(QDialog):
        """Non-modal GMA text markup syntax reference dialog (`Alt+?`)."""

        def __init__(self, parent: QWidget | None = None) -> None:
            super().__init__(parent)
            self.setWindowTitle("Markup Syntax Information")
            self.resize(600, 480)

            layout = QVBoxLayout(self)
            self.browser = QTextBrowser(self)
            self.browser.setOpenExternalLinks(False)
            self.browser.setHtml(MARKUP_SYNTAX_HELP_HTML)
            layout.addWidget(self.browser, stretch=1)

            buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Close, self)
            buttons.rejected.connect(self.close)
            buttons.accepted.connect(self.close)
            layout.addWidget(buttons)

else:  # pragma: no cover

    class AboutMapperDialog:  # type: ignore[no-redef]
        def __init__(self, *_args: Any, **_kwargs: Any) -> None:
            pass

    class MarkupSyntaxHelpDialog:  # type: ignore[no-redef]
        def __init__(self, *_args: Any, **_kwargs: Any) -> None:
            pass
