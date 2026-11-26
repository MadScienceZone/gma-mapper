"""Settings persistence and Preferences dialog ported from ``GMADieRoller/Settings.py``."""

from __future__ import annotations

import base64
import copy
import html
import json
import os
from pathlib import Path
import tempfile
from typing import Any, Callable

from gma_mapper.core.colors import color_to_hex
from py_dieroller.debug import dprint

DEF_PORT: int = 2323

DEF_STYLES: dict[str, dict[str, Any]] = {
    "best": {},
    "bonus": {
        "name": "Crit Bonus",
        "foreground": "#00B25C",
    },
    "comment": {
        "name": "Comment",
        "foreground": "#6F4959",
        "fontstyle": ["italic"],
    },
    "constant": {
        "name": "Die roll constant",
        "foreground": "#00B25C",
    },
    "critlabel": {
        "name": "Critcal hit confirm label",
        "foreground": "#8C003D",
    },
    "critspec": {
        "name": "Critical hit threat range",
        "foreground": "#CC9E58",
        "fontsize": -1,
    },
    "cumulative": {
        "name": "Target value",
        "foreground": "#A66300",
        "fontsize": -1,
    },
    "dc": {
        "name": "DC spec",
        "foreground": "#CC9E58",
        "fontsize": -1,
    },
    "diebonus": {},
    "diespec": {
        "name": "Die roll string",
        "foreground": "#CC9E58",
        "fontsize": -1,
    },
    "discarded": {},
    "error": {
        "name": "Error message from server",
        "foreground": "#8C003D",
        "background": "#FFC773",
        "fontstyle": ["bold"],
    },
    "exceeded": {
        "name": "DC exceeded by",
        "foreground": "#00733C",
        "background": "#FFC773",
        "fontstyle": ["bold"],
        "fontsize": -1,
    },
    "fail": {
        "name": "%dice failure",
        "foreground": "#8C003D",
        "background": "#FFC773",
        "fontstyle": ["bold"],
    },
    "from": {},
    "fullmax": {},
    "fullresult": {},
    "iteration": {
        "name": "Iteration count",
        "foreground": "#A66300",
        "fontsize": -1,
    },
    "label": {
        "name": "Modifier label",
        "foreground": "#CC9E58",
        "fontsize": -1,
    },
    "limit": {},
    "max": {},
    "maximized": {},
    "maxroll": {
        "name": "Die roll (maximized)",
        "foreground": "#00B25C",
    },
    "met": {},
    "min": {},
    "moddelim": {
        "name": "Delimiter |",
        "foreground": "#A66300",
    },
    "notice": {
        "name": "Server notice",
        "foreground": "#8C8C3D",
        "background": "#000000",
        "fontstyle": ["italic"],
    },
    "operator": {
        "name": "Die roll operator",
        "foreground": "#00B25C",
    },
    "privatemsg": {
        "name": "Private message",
        "foreground": "#6F4959",
        "fontstyle": ["italic"],
    },
    "privateuser": {
        "name": "Private message sender",
        "foreground": "#6F4959",
        "fontstyle": ["bold", "italic"],
    },
    "repeat": {},
    "result": {
        "name": "Result",
        "foreground": "#00733C",
        "background": "#FFC773",
        "fontstyle": ["bold"],
    },
    "roll": {
        "name": "Die roll (individual)",
        "foreground": "#00B25C",
    },
    "rolllabel": {
        "name": "Die roll label",
        "foreground": "#318555",
        "fontstyle": ["bold"],
    },
    "separator": {
        "name": "Delimiter =",
        "foreground": "#00B25C",
    },
    "sf": {
        "name": "Auto success/failure",
        "foreground": "#CC9E58",
        "fontsize": -1,
    },
    "short": {
        "name": "DC short by",
        "foreground": "#8C003D",
        "background": "#FFC773",
        "fontstyle": ["bold"],
        "fontsize": -1,
    },
    "success": {
        "name": "%dice success",
        "foreground": "#00733C",
        "background": "#FFC773",
        "fontstyle": ["bold"],
    },
    "system": {},
    "total": {
        "name": "Running total",
        "foreground": "#A66300",
        "fontsize": -1,
    },
    "until": {},
    "user": {
        "name": "Sender name",
        "foreground": "black",
        "fontstyle": ["bold"],
    },
    "worst": {},
}

SAMPLE_LINES: tuple[tuple[tuple[str | None, str], ...], ...] = (
    (("comment", "Connected"),),
    (("comment", "Alice has joined"),),
    (
        ("user", "Alice: "),
        ("rolllabel", "attack, sword "),
        ("result", " 29 "),
        ("separator", " = "),
        ("diespec", "1d20 "),
        ("roll", "(20) "),
        ("operator", "+ "),
        ("constant", "7 "),
        ("operator", "+ "),
        ("constant", "2 "),
        ("label", "Inspire Courage "),
        ("moddelim", "| "),
        ("critspec", "c19+1"),
    ),
    (
        ("user", "Alice: "),
        ("rolllabel", "attack, sword "),
        ("critlabel", "Confirm: "),
        ("result", " 29 "),
        ("separator", " = "),
        ("diespec", "1d20 "),
        ("roll", "(20) "),
        ("operator", "+ "),
        ("constant", "7 "),
        ("operator", "+ "),
        ("constant", "2 "),
        ("label", "Inspire Courage "),
        ("bonus", "+1 "),
    ),
    (
        ("user", "Bob: "),
        ("fail", " fail "),
        ("separator", " = "),
        ("diespec", "20% "),
        ("roll", "(87)"),
    ),
    (
        ("user", "Bob: "),
        ("success", " success "),
        ("separator", " = "),
        ("diespec", "20% "),
        ("roll", "(12)"),
    ),
    (("user", "Bob: "), (None, "Hello, everyone")),
    (("privateuser", "Alice: "), ("privatemsg", "Hello, Bob")),
)


def merge_dicts(
    a: dict[str, Any],
    b: dict[str, Any],
    path: list[str] | None = None,
    replace: bool = True,
) -> dict[str, Any]:
    """Recursively merge dict ``b`` into dict ``a`` in place."""
    if path is None:
        path = []
    for key, val in b.items():
        if key in a and isinstance(a[key], dict) and isinstance(val, dict):
            merge_dicts(a[key], val, path + [str(key)], replace=replace)
        elif key in a and a[key] != val and not replace:
            raise ValueError(f"Can't merge {'.'.join(path + [str(key)])}")
        else:
            a[key] = copy.deepcopy(val)
    return a


class SettingsStore:
    """Persistent configuration storage compatible with ``~/.dieroller/settings.json``."""

    def __init__(
        self,
        filename: str | Path | None = None,
        alert_cb: Callable[[str, str], None] | None = None,
    ) -> None:
        self.filename: Path = Path(
            filename if filename is not None else Path.home() / ".dieroller" / "settings.json"
        )
        self._alert_cb = alert_cb
        self.relfontsize: int = 0
        self.color_boxes: bool = True
        self.color_labels: bool = True
        self.styles: dict[str, dict[str, Any]] = {}
        self.servers: dict[str, dict[str, Any]] = {}
        self._last_server: str | None = None
        self._last_msgid: dict[str, int] = {}

    def _alert(self, caption: str, message: str) -> None:
        if self._alert_cb is not None:
            self._alert_cb(caption, message)

    def snapshot(self) -> dict[str, Any]:
        """Return a deep copy of editable settings for Cancel rollback."""
        return {
            "servers": copy.deepcopy(self.servers),
            "styles": copy.deepcopy(self.styles),
            "relfontsize": self.relfontsize,
            "color_boxes": self.color_boxes,
            "color_labels": self.color_labels,
            "last_server": self._last_server,
            "last_msgid": copy.deepcopy(self._last_msgid),
        }

    def restore(self, snap: dict[str, Any]) -> None:
        """Restore settings from a snapshot created by :meth:`snapshot`."""
        self.servers = copy.deepcopy(snap["servers"])
        self.styles = copy.deepcopy(snap["styles"])
        self.relfontsize = int(snap["relfontsize"])
        self.color_boxes = bool(snap["color_boxes"])
        self.color_labels = bool(snap["color_labels"])
        self._last_server = snap["last_server"]
        self._last_msgid = copy.deepcopy(snap["last_msgid"])

    def allow_colorized_labels(self) -> bool:
        """Return whether die-roll modifier labels may use custom server colors."""
        return self.color_labels

    def allow_colorized_titles(self) -> bool:
        """Return whether die-roll titles may use color boxes."""
        return self.color_boxes

    def effective_style(self, tag: str | None) -> dict[str, Any]:
        """Return the effective style dictionary for ``tag`` merged with ``DEF_STYLES``."""
        if not tag or tag not in DEF_STYLES:
            return {}
        merged = copy.deepcopy(DEF_STYLES[tag])
        if tag in self.styles:
            merged.update(self.styles[tag])
        return merged

    def server_names(self) -> list[str]:
        """Return configured server profile names."""
        return list(self.servers.keys())

    def set_last_server(self, name: str | None) -> None:
        """Set the active/default server name if it exists in configured servers."""
        if name is None or name in self.servers:
            self._last_server = name

    def last_server(self, nameonly: bool = False) -> Any:
        """Return the last active server dict (or its name when ``nameonly=True``)."""
        if self._last_server in self.servers:
            if nameonly:
                return self._last_server
            return self.servers[self._last_server]
        return None

    def server(self, name: str) -> dict[str, Any] | None:
        """Return server configuration dict for ``name`` or None."""
        return self.servers.get(name)

    def update_msgid(self, msgid: int | None, servername: str | None = None) -> None:
        """Update the highest seen message ID for ``servername`` (or active server)."""
        if msgid is None:
            return
        dprint(f"in update_msgid({msgid}, {servername})")
        target = servername or self.last_server(nameonly=True)
        if not target:
            return
        self._last_msgid[str(target)] = int(msgid)

    def last_msgid(self, servername: str | None = None) -> int | None:
        """Return the last seen message ID for ``servername`` (or active server)."""
        target = servername or self.last_server(nameonly=True)
        if not target or str(target) not in self._last_msgid:
            return None
        return self._last_msgid[str(target)]

    @staticmethod
    def password_encode(password: str) -> str:
        """Encode ``password`` as base64 ASCII string (legacy settings.json format)."""
        return base64.b64encode(password.encode("utf-8")).decode("ascii")

    @staticmethod
    def password_decode(b64password: str) -> str:
        """Decode base64-encoded password string from ``settings.json``."""
        if not b64password:
            return ""
        return base64.b64decode(b64password.encode("ascii")).decode("utf-8")

    def to_dict(self) -> dict[str, Any]:
        """Serialize current settings to a JSON-ready dictionary."""
        data: dict[str, Any] = {"servers": {}}
        for sname in self.server_names():
            srv = self.server(sname)
            if srv is None:
                continue
            entry = dict(srv)
            msgid = self.last_msgid(servername=sname)
            if msgid is not None:
                entry["last_msgid"] = msgid
            entry.pop("name", None)
            data["servers"][sname] = entry

        data["fontstyles"] = copy.deepcopy(self.styles)
        if self._last_server:
            data["default_server"] = self._last_server
        data["relative_font_size"] = self.relfontsize
        data["colorize_die_rolls"] = self.color_boxes
        data["colorize_die_labels"] = self.color_labels
        return data

    def save(self, quiet: bool = False) -> bool:
        """Atomically save settings to ``self.filename``."""
        try:
            self.filename.parent.mkdir(parents=True, exist_ok=True)
            payload = json.dumps(self.to_dict(), indent=4) + "\n"
            # Write via a temp file in the destination directory and atomically swap
            # so a crash or disk error never corrupts ~/.dieroller/settings.json.
            fd, tmp_name = tempfile.mkstemp(
                prefix=".settings_",
                suffix=".tmp",
                dir=str(self.filename.parent),
            )
            try:
                with os.fdopen(fd, "w", encoding="utf-8") as fh:
                    fh.write(payload)
                os.replace(tmp_name, self.filename)
            except Exception:
                try:
                    os.unlink(tmp_name)
                except OSError:
                    pass
                raise
        except Exception as exc:  # pylint: disable=broad-exception-caught
            if not quiet:
                self._alert("Could not save settings", str(exc))
            return False
        return True

    def load(self) -> bool:
        """Load settings from ``self.filename`` if present."""
        if not self.filename.is_file():
            return False
        try:
            data = json.loads(self.filename.read_text(encoding="utf-8"))
        except Exception as exc:  # pylint: disable=broad-exception-caught
            self._alert("Could not load settings", str(exc))
            return False

        self.servers = {}
        self._last_msgid = {}
        self._load_servers(data)
        self._load_styles(data)
        self._load_misc(data)
        return True

    def _load_servers(self, data: dict[str, Any]) -> None:
        servers = data.get("servers")
        if servers is None:
            return
        if not isinstance(servers, dict):
            self._alert("Invalid settings", "Corrupt 'servers' entry")
            return
        for name, info in servers.items():
            if not isinstance(info, dict):
                self._alert("Invalid settings", f"Server '{name}' is corrupt")
                break
            self.update_msgid(-1, servername=name)
            entry: dict[str, Any] = {"name": name}
            for field in ("username", "hostname", "password", "port"):
                if field in info:
                    entry[field] = info[field]
            if "last_msgid" in info and info["last_msgid"] is not None:
                self.update_msgid(int(info["last_msgid"]), servername=name)
            self.servers[name] = entry

        default_srv = data.get("default_server")
        if isinstance(default_srv, str) and default_srv in self.servers:
            self._last_server = default_srv

    def _load_styles(self, data: dict[str, Any]) -> None:
        self.styles = {}
        fontstyles = data.get("fontstyles")
        if not isinstance(fontstyles, dict):
            return
        allowed_fields = ("name", "foreground", "background", "fontstyle", "fontsize")
        for load_tag, load_def in fontstyles.items():
            if load_tag not in DEF_STYLES or not isinstance(load_def, dict):
                continue
            sd: dict[str, Any] = {"tag": load_tag}
            for field in allowed_fields:
                if field in load_def and field in DEF_STYLES[load_tag]:
                    sd[field] = load_def[field]
            self.styles[load_tag] = sd

    def _load_misc(self, data: dict[str, Any]) -> None:
        if "relative_font_size" in data:
            try:
                val = int(data["relative_font_size"])
                self.relfontsize = -1 if val < 0 else (1 if val > 0 else 0)
            except (TypeError, ValueError):
                pass
        if "colorize_die_rolls" in data:
            self.color_boxes = bool(data["colorize_die_rolls"])
        if "colorize_die_labels" in data:
            self.color_labels = bool(data["colorize_die_labels"])


def _resolve_color(name: str) -> str:
    clean = str(name or "").strip()
    if not clean:
        return ""
    if clean.startswith("#"):
        return clean
    return color_to_hex(clean) or clean


def _span_css(style_dict: dict[str, Any], override_fg: str = "", override_bg: str = "") -> str:
    parts: list[str] = []
    fg = _resolve_color(override_fg or str(style_dict.get("foreground") or ""))
    bg = _resolve_color(override_bg or str(style_dict.get("background") or ""))
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
    fsize = style_dict.get("fontsize")
    if isinstance(fsize, int) and fsize != 0:
        parts.append("font-size:smaller" if fsize < 0 else "font-size:larger")
    return ";".join(parts)


def render_message_segment_html(msg: dict[str, Any], store: SettingsStore) -> str:
    """Render one styled message dictionary (handling ``≡fg≡bg`` and ``‖`` boxes) to HTML."""
    raw_text = str(msg.get("text") or "")
    style_name = msg.get("style")
    if style_name == "cumulative":
        raw_text = f"(currently {raw_text.strip()}) "
    elif style_name == "total":
        raw_text = f"until total {raw_text.strip()} "
    elif style_name == "iteration":
        raw_text = f"roll #{raw_text.strip()}"

    style_dict = store.effective_style(style_name)
    base_css = _span_css(style_dict)

    if "\u2261" in raw_text:
        spans: list[str] = []
        for block in raw_text.split("\u2016"):
            parts = block.split("\u2261")
            if len(parts) not in (2, 3):
                escaped = html.escape(block)
                spans.append(f'<span style="{base_css}">{escaped}</span>')
                continue
            seg_text = parts[0]
            fg = parts[1].strip()
            bg = parts[2].strip() if len(parts) == 3 else "#000000"
            box_css = _span_css(style_dict, override_fg=fg, override_bg=bg)
            spans.append(f'<span style="{box_css}"> {html.escape(seg_text)} </span>')
        return "".join(spans)

    escaped = html.escape(raw_text)
    if base_css:
        return f'<span style="{base_css}">{escaped}</span>'
    return escaped


def render_messages_html(msgs: list[dict[str, Any]], store: SettingsStore) -> str:
    """Render a sequence of message segments into HTML respecting ``newline`` flags."""
    out: list[str] = []
    for msg in msgs:
        if "text" not in msg:
            continue
        out.append(render_message_segment_html(msg, store))
        if msg.get("newline"):
            out.append("<br/>")
    return "".join(out)


def render_sample_preview_html(store: SettingsStore) -> str:
    """Render ``SAMPLE_LINES`` to HTML for the Styles preview pane."""
    blocks: list[str] = []
    for line_segments in SAMPLE_LINES:
        msgs: list[dict[str, Any]] = []
        for idx, (tag, text) in enumerate(line_segments):
            msg: dict[str, Any] = {
                "text": text,
                "newline": idx == len(line_segments) - 1,
            }
            if tag:
                msg["style"] = tag
            msgs.append(msg)
        blocks.append(render_messages_html(msgs, store))
    return "".join(blocks)


try:
    from PySide6.QtCore import Qt, Signal
    from PySide6.QtGui import QColor
    from PySide6.QtWidgets import (
        QCheckBox,
        QColorDialog,
        QComboBox,
        QDialog,
        QDialogButtonBox,
        QFormLayout,
        QGridLayout,
        QHBoxLayout,
        QLabel,
        QLineEdit,
        QListWidget,
        QMessageBox,
        QPushButton,
        QScrollArea,
        QSpinBox,
        QSplitter,
        QTabWidget,
        QTextBrowser,
        QVBoxLayout,
        QWidget,
    )

    QT_AVAILABLE = True
except ImportError:  # pragma: no cover
    QT_AVAILABLE = False


if QT_AVAILABLE:

    class SettingsDialog(QDialog):
        """PySide6 Preferences dialog with General, Servers, and Styles tabs."""

        servers_changed = Signal(list)
        styles_changed = Signal()

        def __init__(self, store: SettingsStore, parent: QWidget | None = None) -> None:
            super().__init__(parent)
            self.store = store
            self.servers_dirty = False
            self.styles_dirty = False
            self._snapshot = store.snapshot()
            self._style_buttons: dict[tuple[str, str], QPushButton] = {}
            self._updating_server_form = False

            self.setWindowTitle("Preferences")
            self.resize(640, 440)
            self.setMinimumSize(580, 380)

            root = QVBoxLayout(self)
            self.tabs = QTabWidget(self)
            root.addWidget(self.tabs, stretch=1)

            self._build_general_tab()
            self._build_servers_tab()
            self._build_styles_tab()

            buttons = QDialogButtonBox(
                QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel,
                self,
            )
            buttons.accepted.connect(self.accept)
            buttons.rejected.connect(self.reject)
            root.addWidget(buttons)

        def _build_general_tab(self) -> None:
            tab = QWidget(self.tabs)
            vbox = QVBoxLayout(tab)
            vbox.setContentsMargins(20, 20, 20, 20)
            vbox.setSpacing(14)

            font_row = QHBoxLayout()
            font_row.addWidget(QLabel("Font size:", tab))
            self.font_size_combo = QComboBox(tab)
            self.font_size_combo.addItems(["smaller", "normal", "larger"])
            self.font_size_combo.setCurrentIndex(max(0, min(2, self.store.relfontsize + 1)))
            self.font_size_combo.currentIndexChanged.connect(
                lambda idx: setattr(self.store, "relfontsize", idx - 1)
            )
            font_row.addWidget(self.font_size_combo)
            font_row.addStretch(1)
            vbox.addLayout(font_row)

            self.color_boxes_check = QCheckBox("Allow colored die-roll titles", tab)
            self.color_boxes_check.setChecked(self.store.color_boxes)
            self.color_boxes_check.toggled.connect(
                lambda chk: setattr(self.store, "color_boxes", bool(chk))
            )
            vbox.addWidget(self.color_boxes_check)

            self.color_labels_check = QCheckBox("Allow colored die-roll modifier labels", tab)
            self.color_labels_check.setChecked(self.store.color_labels)
            self.color_labels_check.toggled.connect(
                lambda chk: setattr(self.store, "color_labels", bool(chk))
            )
            vbox.addWidget(self.color_labels_check)

            vbox.addStretch(1)
            self.tabs.addTab(tab, "General")

        def _build_servers_tab(self) -> None:
            tab = QWidget(self.tabs)
            hbox = QHBoxLayout(tab)
            splitter = QSplitter(Qt.Orientation.Horizontal, tab)
            hbox.addWidget(splitter)

            # Left server list + New/Delete buttons
            left = QWidget(splitter)
            left_v = QVBoxLayout(left)
            self.server_list = QListWidget(left)
            self.server_list.setSortingEnabled(True)
            self.server_list.currentRowChanged.connect(self._on_server_selected)
            left_v.addWidget(self.server_list, stretch=1)

            btn_row = QHBoxLayout()
            self.btn_new_server = QPushButton("New", left)
            self.btn_new_server.clicked.connect(self._on_new_server)
            self.btn_del_server = QPushButton("Delete", left)
            self.btn_del_server.setEnabled(False)
            self.btn_del_server.clicked.connect(self._on_delete_server)
            btn_row.addStretch(1)
            btn_row.addWidget(self.btn_new_server)
            btn_row.addWidget(self.btn_del_server)
            left_v.addLayout(btn_row)

            # Right server form + Apply
            right = QWidget(splitter)
            right_v = QVBoxLayout(right)
            form = QFormLayout()
            self.site_edit = QLineEdit(right)
            self.host_edit = QLineEdit(right)
            self.port_spin = QSpinBox(right)
            self.port_spin.setRange(1, 65535)
            self.port_spin.setValue(DEF_PORT)
            self.login_edit = QLineEdit(right)
            self.password_edit = QLineEdit(right)
            self.password_edit.setEchoMode(QLineEdit.EchoMode.Password)

            form.addRow("Name:", self.site_edit)
            form.addRow("Host:", self.host_edit)
            form.addRow("Port:", self.port_spin)
            form.addRow("Login:", self.login_edit)
            form.addRow("Password:", self.password_edit)
            right_v.addLayout(form)

            self.apply_server_btn = QPushButton("Apply", right)
            self.apply_server_btn.clicked.connect(self._on_apply_server)
            right_v.addWidget(self.apply_server_btn, alignment=Qt.AlignmentFlag.AlignCenter)
            right_v.addStretch(1)

            splitter.addWidget(left)
            splitter.addWidget(right)
            splitter.setStretchFactor(1, 2)
            self._set_server_form_enabled(False)
            self._reload_server_list()
            self.tabs.addTab(tab, "Servers")

        def _build_styles_tab(self) -> None:
            tab = QWidget(self.tabs)
            hbox = QHBoxLayout(tab)

            scroll = QScrollArea(tab)
            scroll.setWidgetResizable(True)
            host = QWidget(scroll)
            grid = QGridLayout(host)
            grid.addWidget(QLabel("Style", host), 0, 0)
            grid.addWidget(QLabel("Text", host), 0, 1)
            grid.addWidget(QLabel("Back", host), 0, 2)

            tags = sorted(
                (t for t, d in DEF_STYLES.items() if "name" in d),
                key=lambda t: str(DEF_STYLES[t]["name"]),
            )
            for row_idx, tag in enumerate(tags, start=1):
                eff = self.store.effective_style(tag)
                grid.addWidget(QLabel(str(DEF_STYLES[tag]["name"]), host), row_idx, 0)
                for col_idx, prop in ((1, "foreground"), (2, "background")):
                    if prop not in DEF_STYLES[tag]:
                        continue
                    btn = QPushButton("", host)
                    btn.setFixedSize(22, 20)
                    color_str = str(eff.get(prop) or "")
                    self._paint_swatch_button(btn, color_str)
                    btn.clicked.connect(
                        lambda _c=False, t=tag, p=prop: self._prompt_style_color(t, p)
                    )
                    self._style_buttons[(tag, prop)] = btn
                    grid.addWidget(btn, row_idx, col_idx)

            scroll.setWidget(host)
            hbox.addWidget(scroll, stretch=1)

            right = QWidget(tab)
            right_v = QVBoxLayout(right)
            right_v.addWidget(QLabel("Preview", right))
            self.preview_browser = QTextBrowser(right)
            self.preview_browser.setReadOnly(True)
            right_v.addWidget(self.preview_browser, stretch=1)
            hbox.addWidget(right, stretch=1)

            self._refresh_style_preview()
            self.tabs.addTab(tab, "Styles")

        @staticmethod
        def _paint_swatch_button(btn: QPushButton, color_str: str) -> None:
            btn.setStyleSheet(
                f"background-color: {color_str}; border: 1px solid #222222;"
                if color_str
                else "border: 1px solid #222222;"
            )

        def _refresh_style_preview(self) -> None:
            self.preview_browser.setHtml(render_sample_preview_html(self.store))

        def set_style_color(self, tag: str, which: str, color_hex: str) -> bool:
            """Update ``tag``'s ``foreground`` or ``background`` color and refresh preview."""
            if tag not in DEF_STYLES or which not in DEF_STYLES[tag]:
                return False
            self.store.styles.setdefault(tag, {"tag": tag})[which] = color_hex
            btn = self._style_buttons.get((tag, which))
            if btn is not None:
                self._paint_swatch_button(btn, color_hex)
            self._refresh_style_preview()
            self.styles_dirty = True
            return True

        def _prompt_style_color(self, tag: str, which: str) -> None:
            eff = self.store.effective_style(tag)
            initial = QColor(str(eff.get(which) or "#000000"))
            chosen = QColorDialog.getColor(
                initial,
                self,
                f"Choose {which} color for {DEF_STYLES[tag].get('name', tag)}",
            )
            if chosen.isValid():
                self.set_style_color(tag, which, chosen.name())

        def _set_server_form_enabled(self, enabled: bool) -> None:
            for w in (
                self.site_edit,
                self.host_edit,
                self.port_spin,
                self.login_edit,
                self.password_edit,
                self.apply_server_btn,
            ):
                w.setEnabled(enabled)
            if not enabled:
                self.site_edit.clear()
                self.host_edit.clear()
                self.port_spin.setValue(DEF_PORT)
                self.login_edit.clear()
                self.password_edit.clear()

        def _reload_server_list(self) -> None:
            self.server_list.clear()
            for name in sorted(self.store.server_names()):
                self.server_list.addItem(name)

        def _on_server_selected(self, row: int) -> None:
            if row < 0:
                self._set_server_form_enabled(False)
                self.btn_del_server.setEnabled(False)
                return
            item = self.server_list.item(row)
            if item is None:
                return
            srv = self.store.server(item.text())
            if srv is None:
                return
            self._set_server_form_enabled(True)
            self.btn_del_server.setEnabled(True)
            self.site_edit.setText(str(srv.get("name", item.text())))
            self.host_edit.setText(str(srv.get("hostname", "")))
            self.port_spin.setValue(int(srv.get("port") or DEF_PORT))
            self.login_edit.setText(str(srv.get("username", "")))
            self.password_edit.setText(
                self.store.password_decode(str(srv.get("password", "")))
            )

        def _on_new_server(self) -> None:
            self.server_list.clearSelection()
            self.server_list.setCurrentRow(-1)
            self._set_server_form_enabled(True)
            self.btn_del_server.setEnabled(False)
            self.site_edit.setFocus()

        def _on_delete_server(self) -> None:
            row = self.server_list.currentRow()
            if row < 0:
                return
            item = self.server_list.item(row)
            if item is None:
                return
            name = item.text()
            self.store.servers.pop(name, None)
            if self.store.last_server(nameonly=True) == name:
                self.store.set_last_server(None)
            self.server_list.takeItem(row)
            self._set_server_form_enabled(False)
            self.btn_del_server.setEnabled(False)
            self.servers_dirty = True

        def _on_apply_server(self) -> None:
            site = self.site_edit.text().strip()
            if not site:
                QMessageBox.warning(self, "Can't update server", "Name required")
                return
            host = self.host_edit.text().strip()
            if not host:
                QMessageBox.warning(self, "Can't update server", "Hostname required")
                return
            port = int(self.port_spin.value())
            username = self.login_edit.text().strip()
            password = self.password_edit.text().strip()
            self.apply_server_entry(site, host, port, username, password)

        def apply_server_entry(
            self,
            site: str,
            host: str,
            port: int,
            username: str = "",
            password: str = "",
        ) -> bool:
            """Create or update a server profile in the store and list widget."""
            row = self.server_list.currentRow()
            oldname = (
                self.server_list.item(row).text()
                if row >= 0 and self.server_list.item(row) is not None
                else None
            )
            if oldname is None and site in self.store.servers:
                QMessageBox.warning(self, "Can't update server", "Name already exists")
                return False

            entry: dict[str, Any] = {
                "name": site,
                "hostname": host,
                "port": int(port),
                "username": username,
            }
            if password:
                entry["password"] = self.store.password_encode(password)
            if oldname and oldname != site:
                self.store.servers.pop(oldname, None)
                if self.store.last_server(nameonly=True) == oldname:
                    self.store.set_last_server(site)
                    prev_msgid = self.store.last_msgid(servername=oldname)
                    if prev_msgid is not None:
                        self.store.update_msgid(prev_msgid, servername=site)
            self.store.servers[site] = entry
            if self.store.last_server(nameonly=True) is None:
                self.store.set_last_server(site)

            self._reload_server_list()
            matches = self.server_list.findItems(site, Qt.MatchFlag.MatchExactly)
            if matches:
                self.server_list.setCurrentItem(matches[0])
            self.servers_dirty = True
            return True

        def accept(self) -> None:
            old_rel = self._snapshot["relfontsize"]
            if self.store.save():
                if self.servers_dirty:
                    self.servers_changed.emit(self.store.server_names())
                    self.servers_dirty = False
                if self.styles_dirty:
                    self.styles_changed.emit()
                    self.styles_dirty = False
                if old_rel != self.store.relfontsize:
                    QMessageBox.information(
                        self,
                        "Restart required",
                        "You must restart the application for font size changes to take effect",
                    )
            super().accept()

        def reject(self) -> None:
            self.store.restore(self._snapshot)
            super().reject()
