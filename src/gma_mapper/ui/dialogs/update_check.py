"""Package update checker and RSA signature verifier for GMA Mapper."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from gma_mapper.core.util import verify, ustar_gzip_extract

try:
    from PySide6.QtWidgets import QDialog, QVBoxLayout, QLabel, QDialogButtonBox, QWidget
    HAS_PYSIDE6 = True
except ImportError:
    HAS_PYSIDE6 = False


def verify_and_unpack_update(
    tarball_path: str | Path,
    sig_path: str | Path,
    dest_dir: str | Path,
) -> bool:
    """Verify RSA signature on ``tarball_path`` using ``sig_path`` and extract to ``dest_dir``."""
    if not verify(tarball_path, sig_path):
        return False
    ustar_gzip_extract(tarball_path, dest_dir)
    return True


if HAS_PYSIDE6:

    class UpdateCheckDialog(QDialog):
        """Dialog displaying current GMA Mapper version and update verification status."""

        def __init__(self, current_version: str, parent: QWidget | None = None) -> None:
            super().__init__(parent)
            self.setWindowTitle("Check for Updates")
            layout = QVBoxLayout(self)
            self.status_label = QLabel(
                f"GMA Mapper version {current_version} is up to date.",
                self,
            )
            layout.addWidget(self.status_label)
            buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok, self)
            buttons.accepted.connect(self.accept)
            layout.addWidget(buttons)

else:

    class UpdateCheckDialog:  # type: ignore[no-redef]
        def __init__(self, current_version: str, parent: Any = None) -> None:
            self.current_version = current_version

