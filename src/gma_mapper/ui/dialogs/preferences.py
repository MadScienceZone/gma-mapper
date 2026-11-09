"""Preferences and Server Profile Editor Dialog (`~/.gma/mapper/preferences.json`)."""

from __future__ import annotations

import copy
from typing import Any

from gma_mapper.core.profile import empty_server_profile, find_server_index, fix_missing

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
        QLabel,
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
            self.resize(560, 440)
            self.prefs = fix_missing(copy.deepcopy(prefs))
            self._editing_idx: int = -1

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
                cur_name = str(self.prefs.get("current_profile") or "offline")
                initial_idx = find_server_index(self.prefs, cur_name)
                if initial_idx < 0:
                    initial_idx = 0
                self.server_combo.setCurrentIndex(initial_idx)
                self._load_selected_server(initial_idx)
            self.server_combo.currentIndexChanged.connect(self._on_server_index_changed)

        def _build_general_tab(self) -> None:
            tab = QWidget(self.tabs)
            form = QFormLayout(tab)

            self.dark_check = QCheckBox("Enable dark mode UI theme", tab)
            self.dark_check.setChecked(bool(self.prefs.get("dark", False)))
            form.addRow("Theme:", self.dark_check)

            self.animate_check = QCheckBox("Enable animated map tiles", tab)
            self.animate_check.setChecked(bool(self.prefs.get("animate", False)))
            form.addRow("Animations:", self.animate_check)

            guides = self.prefs.get("guide_lines", {})
            major = guides.get("major", {}) if isinstance(guides, dict) else {}
            major_off = major.get("offsets", {}) if isinstance(major, dict) else {}
            minor = guides.get("minor", {}) if isinstance(guides, dict) else {}
            minor_off = minor.get("offsets", {}) if isinstance(minor, dict) else {}

            major_row = QHBoxLayout()
            self.major_interval_spin = QSpinBox(tab)
            self.major_interval_spin.setRange(0, 1000)
            self.major_interval_spin.setValue(int(major.get("interval", 0) or 0))
            self.major_offset_x_spin = QSpinBox(tab)
            self.major_offset_x_spin.setRange(-1000, 1000)
            self.major_offset_x_spin.setValue(int(major_off.get("x", 0) or 0))
            self.major_offset_y_spin = QSpinBox(tab)
            self.major_offset_y_spin.setRange(-1000, 1000)
            self.major_offset_y_spin.setValue(int(major_off.get("y", 0) or 0))
            major_row.addWidget(QLabel("Interval:", tab))
            major_row.addWidget(self.major_interval_spin)
            major_row.addWidget(QLabel("Offset X:", tab))
            major_row.addWidget(self.major_offset_x_spin)
            major_row.addWidget(QLabel("Y:", tab))
            major_row.addWidget(self.major_offset_y_spin)
            form.addRow("Major Grid Lines:", major_row)

            minor_row = QHBoxLayout()
            self.minor_interval_spin = QSpinBox(tab)
            self.minor_interval_spin.setRange(0, 1000)
            self.minor_interval_spin.setValue(int(minor.get("interval", 0) or 0))
            self.minor_offset_x_spin = QSpinBox(tab)
            self.minor_offset_x_spin.setRange(-1000, 1000)
            self.minor_offset_x_spin.setValue(int(minor_off.get("x", 0) or 0))
            self.minor_offset_y_spin = QSpinBox(tab)
            self.minor_offset_y_spin.setRange(-1000, 1000)
            self.minor_offset_y_spin.setValue(int(minor_off.get("y", 0) or 0))
            minor_row.addWidget(QLabel("Interval:", tab))
            minor_row.addWidget(self.minor_interval_spin)
            minor_row.addWidget(QLabel("Offset X:", tab))
            minor_row.addWidget(self.minor_offset_x_spin)
            minor_row.addWidget(QLabel("Y:", tab))
            minor_row.addWidget(self.minor_offset_y_spin)
            form.addRow("Minor Grid Lines:", minor_row)

            self.tabs.addTab(tab, "Display & Grid")

        def _on_server_index_changed(self, idx: int) -> None:
            if self._editing_idx >= 0:
                self._save_server_at(self._editing_idx)
            self._load_selected_server(idx)

        def _load_selected_server(self, idx: int) -> None:
            servers = self.prefs.get("profiles", [])
            if 0 <= idx < len(servers):
                self._editing_idx = idx
                srv = servers[idx]
                self.prefs["current_profile"] = str(srv.get("name", "offline"))
                self.host_edit.setText(str(srv.get("host", "")))
                self.port_spin.setValue(int(srv.get("port", 2323) or 2323))
                self.user_edit.setText(str(srv.get("username", srv.get("user", ""))))
                self.pass_edit.setText(str(srv.get("password", srv.get("pass", ""))))
                self.curl_edit.setText(str(srv.get("curl_server", srv.get("curl_url_base", ""))))
                self.scp_server_edit.setText(str(srv.get("scp_server", "")))
                self.scp_dest_edit.setText(str(srv.get("scp_dest", "")))

        def _save_server_at(self, idx: int) -> None:
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

        def _save_current_server(self) -> None:
            idx = self.server_combo.currentIndex()
            self._save_server_at(idx)
            servers = self.prefs.get("profiles", [])
            if 0 <= idx < len(servers):
                self.prefs["current_profile"] = str(servers[idx].get("name", "offline"))

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
            self.prefs["guide_lines"] = {
                "major": {
                    "interval": self.major_interval_spin.value(),
                    "offsets": {
                        "x": self.major_offset_x_spin.value(),
                        "y": self.major_offset_y_spin.value(),
                    },
                },
                "minor": {
                    "interval": self.minor_interval_spin.value(),
                    "offsets": {
                        "x": self.minor_offset_x_spin.value(),
                        "y": self.minor_offset_y_spin.value(),
                    },
                },
            }
            self.accept()

else:

    class PreferencesDialog:  # type: ignore[no-redef]
        def __init__(self, prefs: dict[str, Any], parent: Any = None) -> None:
            self.prefs = fix_missing(copy.deepcopy(prefs))

