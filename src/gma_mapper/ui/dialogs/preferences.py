"""Preferences and Server Profile Editor Dialog (`~/.gma/mapper/preferences.json`)."""

from __future__ import annotations

import copy
from typing import Any

from gma_mapper.core.profile import empty_server_profile, fix_missing

try:
    from PySide6.QtWidgets import (
        QDialog,
        QVBoxLayout,
        QHBoxLayout,
        QTabWidget,
        QWidget,
        QFormLayout,
        QLineEdit,
        QSpinBox,
        QCheckBox,
        QComboBox,
        QPushButton,
        QDialogButtonBox,
    )
    HAS_PYSIDE6 = True
except ImportError:
    HAS_PYSIDE6 = False


if HAS_PYSIDE6:

    class PreferencesDialog(QDialog):
        """Multi-tab preferences editor for Server Profiles, Display/Styles, and Audio."""

        def __init__(self, prefs: dict[str, Any], parent: QWidget | None = None) -> None:
            super().__init__(parent)
            self.setWindowTitle("GMA Mapper Preferences")
            self.resize(560, 420)
            self.prefs = fix_missing(copy.deepcopy(prefs))

            layout = QVBoxLayout(self)
            self.tabs = QTabWidget(self)
            layout.addWidget(self.tabs, 1)

            self._build_servers_tab()
            self._build_general_tab()

            buttons = QDialogButtonBox(
                QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel,
                self,
            )
            buttons.accepted.connect(self._on_accept)
            buttons.rejected.connect(self.reject)
            layout.addWidget(buttons)

        def _build_servers_tab(self) -> None:
            tab = QWidget(self.tabs)
            form = QFormLayout(tab)

            top_row = QHBoxLayout()
            self.server_combo = QComboBox(tab)
            for srv in self.prefs.get("profiles", []):
                self.server_combo.addItem(str(srv.get("name", "offline")))
            self.server_combo.currentIndexChanged.connect(self._load_selected_server)
            top_row.addWidget(self.server_combo, 1)

            btn_new = QPushButton("New Profile", tab)
            btn_new.clicked.connect(self._on_new_server)
            top_row.addWidget(btn_new)
            form.addRow("Profile:", top_row)

            self.host_edit = QLineEdit(tab)
            self.port_spin = QSpinBox(tab)
            self.port_spin.setRange(1, 65535)
            self.user_edit = QLineEdit(tab)
            self.pass_edit = QLineEdit(tab)
            self.pass_edit.setEchoMode(QLineEdit.EchoMode.Password)
            self.curl_edit = QLineEdit(tab)
            self.scp_server_edit = QLineEdit(tab)
            self.scp_dest_edit = QLineEdit(tab)

            form.addRow("Host:", self.host_edit)
            form.addRow("Port:", self.port_spin)
            form.addRow("Username:", self.user_edit)
            form.addRow("Password:", self.pass_edit)
            form.addRow("HTTP Base URL:", self.curl_edit)
            form.addRow("Upload SSH Host:", self.scp_server_edit)
            form.addRow("Upload Destination:", self.scp_dest_edit)

            self.tabs.addTab(tab, "Server Profiles")
            if self.prefs.get("profiles"):
                self._load_selected_server(0)

        def _build_general_tab(self) -> None:
            tab = QWidget(self.tabs)
            form = QFormLayout(tab)

            self.dark_check = QCheckBox("Enable dark mode UI theme", tab)
            self.dark_check.setChecked(bool(self.prefs.get("dark", False)))
            form.addRow("Theme:", self.dark_check)

            self.animate_check = QCheckBox("Enable animated map tiles", tab)
            self.animate_check.setChecked(bool(self.prefs.get("animate", True)))
            form.addRow("Animations:", self.animate_check)

            self.guide_check = QCheckBox("Show reach/space guide lines", tab)
            self.guide_check.setChecked(bool(self.prefs.get("guide_lines", True)))
            form.addRow("Guide Lines:", self.guide_check)

            self.blur_spin = QSpinBox(tab)
            self.blur_spin.setRange(0, 365)
            self.blur_spin.setValue(int(self.prefs.get("blur_limit", 30)))
            form.addRow("Cache Expiration (days):", self.blur_spin)

            self.tabs.addTab(tab, "Display & Cache")

        def _load_selected_server(self, idx: int) -> None:
            servers = self.prefs.get("profiles", [])
            if 0 <= idx < len(servers):
                srv = servers[idx]
                self.host_edit.setText(str(srv.get("host", "localhost")))
                self.port_spin.setValue(int(srv.get("port", 2325) or 2325))
                self.user_edit.setText(str(srv.get("username", srv.get("user", ""))))
                self.pass_edit.setText(str(srv.get("password", srv.get("pass", ""))))
                self.curl_edit.setText(str(srv.get("curl_server", srv.get("curl_url_base", ""))))
                self.scp_server_edit.setText(str(srv.get("scp_server", "")))
                self.scp_dest_edit.setText(str(srv.get("scp_dest", "")))

        def _save_current_server(self) -> None:
            idx = self.server_combo.currentIndex()
            servers = self.prefs.get("profiles", [])
            if 0 <= idx < len(servers):
                srv = servers[idx]
                srv["host"] = self.host_edit.text().strip()
                srv["port"] = self.port_spin.value()
                srv["username"] = self.user_edit.text().strip()
                srv["password"] = self.pass_edit.text()
                srv["curl_server"] = self.curl_edit.text().strip()
                srv["scp_server"] = self.scp_server_edit.text().strip()
                srv["scp_dest"] = self.scp_dest_edit.text().strip()

        def _on_new_server(self) -> None:
            self._save_current_server()
            name = f"profile-{len(self.prefs.get('profiles', [])) + 1}"
            srv = empty_server_profile(name)
            self.prefs.setdefault("profiles", []).append(srv)
            self.server_combo.addItem(name)
            self.server_combo.setCurrentIndex(self.server_combo.count() - 1)

        def _on_accept(self) -> None:
            self._save_current_server()
            self.prefs["dark"] = self.dark_check.isChecked()
            self.prefs["animate"] = self.animate_check.isChecked()
            self.prefs["guide_lines"] = self.guide_check.isChecked()
            self.prefs["blur_limit"] = self.blur_spin.value()
            self.accept()

else:

    class PreferencesDialog:  # type: ignore[no-redef]
        def __init__(self, prefs: dict[str, Any], parent: Any = None) -> None:
            self.prefs = fix_missing(copy.deepcopy(prefs))

