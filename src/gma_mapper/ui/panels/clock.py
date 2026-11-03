"""Golarion Calendar, Analog/Combat Clock Widget, Initiative Clock Panel, and Timer Requests.

Ported from ``bin/gmaclock.tcl`` and ``bin/mapper_legacy.tcl``.
"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass, field
from typing import Any

from gma_mapper.net.protocol import new_id

try:
    from PySide6.QtCore import Qt, QPointF, QRectF, QTimer, Signal
    from PySide6.QtGui import QAction, QBrush, QColor, QFont, QPainter, QPen
    from PySide6.QtWidgets import (
        QCheckBox,
        QDialog,
        QDialogButtonBox,
        QFormLayout,
        QGroupBox,
        QHBoxLayout,
        QHeaderView,
        QLabel,
        QLineEdit,
        QMenu,
        QProgressBar,
        QPushButton,
        QTreeWidget,
        QTreeWidgetItem,
        QVBoxLayout,
        QWidget,
    )
    HAS_PYSIDE6 = True
except ImportError:
    HAS_PYSIDE6 = False


MONTH_NAMES: list[str] = [
    "Abadius",
    "Calistril",
    "Pharast",
    "Gozran",
    "Desnus",
    "Sarenith",
    "Erastus",
    "Arodus",
    "Rova",
    "Lamashan",
    "Neth",
    "Kuthona",
]

DAY_NAMES: list[str] = [
    "Moonday",
    "Toilday",
    "Wealday",
    "Oathday",
    "Fireday",
    "Starday",
    "Sunday",
]


def ordinal_suffix(n: int) -> str:
    """Return ordinal suffix ('st', 'nd', 'rd', 'th') matching ``gmaclock::_ord``."""
    if n in (1, 21, 31):
        return "st"
    if n in (2, 22):
        return "nd"
    if n in (3, 23):
        return "rd"
    return "th"


def _j(y: int, m: int, d: int) -> int:
    """Convert Golarion (year, month 1..12, day 1..31) to day number (`gmaclock::_j`)."""
    m = (m + 9) % 12
    y = y - m // 10
    return 365 * y + y // 8 + (306 * m + 5) // 10 + (d - 1)


def _ymd(j: int) -> tuple[int, int, int]:
    """Convert Golarion day number back to (year, month 1..12, day 1..31) (`gmaclock::_ymd`)."""
    y = (10000 * j + 14780) // 3651250
    d = j - (365 * y + y // 8)
    if d < 0:
        y = y - 1
        d = j - (365 * y + y // 8)
    m = (100 * d + 52) // 3060
    return (y + (m + 2) // 12, (m + 2) % 12 + 1, d - (306 * m + 5) // 10 + 1)


def _div(n: int, d: int) -> tuple[int, int]:
    """Return ``(n // d, n % d)``."""
    return (n // d, n % d)


def delta_string(s: int) -> str:
    """Format elapsed seconds ``s`` into a human-readable duration string.

    Matches ``gmaclock::delta_string`` from ``bin/gmaclock.tcl``.
    """
    neg = ""
    if s < 0:
        neg = "-"
        s = -s

    t, r = _div(s, 6)
    m, s_rem = _div(s, 60)
    h, m = _div(m, 60)
    d, h = _div(h, 24)
    w, d = _div(d, 7)

    if w > 0:
        if d > 0:
            return f"{neg}{w}w {d}d {h:02d}:{m:02d}:{s_rem:02d}"
        return f"{neg}{w}w {h:02d}:{m:02d}:{s_rem:02d}"
    if d > 0:
        return f"{neg}{d}d {h:02d}:{m:02d}:{s_rem:02d}"
    if h > 0:
        return f"{neg}{h:02d}:{m:02d}:{s_rem:02d}"
    if t > 10:
        return f"{neg}{m:02d}:{s_rem:02d} ({t}r+{r})"
    return f"{neg}{s_rem}s ({t}r+{r})"


def strip_nameplate_prefix(full_name: str) -> str:
    """Remove any leading ``<tag>_`` prefix from a creature name (`gmaclock::nameplate_text`)."""
    return re.sub(r"^\w*_", "", str(full_name or ""))


def nameplate_text(slot: dict[str, Any] | str) -> str:
    """Format an initiative slot nameplate matching ``gmaclock::nameplate_text``."""
    if isinstance(slot, str):
        return strip_nameplate_prefix(slot)
    raw_name = str(slot.get("Name", slot.get("name", "")))
    name = strip_nameplate_prefix(raw_name)
    if slot.get("IsReady") or slot.get("HasReadiedAction") or slot.get("ready"):
        return f"\u23f2 {name}"
    if slot.get("IsHold") or slot.get("IsHolding") or slot.get("hold"):
        return f"\u23f8 {name}"
    if slot.get("FlatFooted") or slot.get("IsFlatFooted"):
        return f"\u26a0 {name}"
    return name


def slot_status_summary(slot: dict[str, Any]) -> str:
    """Format HP and condition state summary for an initiative slot."""
    parts: list[str] = []
    if "CurrentHP" in slot and slot.get("CurrentHP") is not None:
        cur_hp = int(slot.get("CurrentHP", 0))
        if "MaxHP" in slot and slot.get("MaxHP"):
            parts.append(f"{cur_hp}/{int(slot['MaxHP'])} HP")
        elif cur_hp < 0:
            parts.append(f"\u271a Dying ({cur_hp} HP)")
        elif cur_hp == 0:
            parts.append("0 HP (Disabled)")
        else:
            parts.append(f"{cur_hp} HP")
    elif "MaxHP" in slot:
        cur_hp = int(slot.get("MaxHP", 0)) - int(slot.get("LethalDamage", 0))
        parts.append(f"{cur_hp}/{slot.get('MaxHP', 0)} HP")

    if slot.get("IsReady") or slot.get("HasReadiedAction") or slot.get("ready"):
        parts.append("Readied")
    elif slot.get("IsHold") or slot.get("IsHolding") or slot.get("hold"):
        parts.append("Holding")

    if slot.get("FlatFooted") or slot.get("IsFlatFooted"):
        parts.append("Flat-Footed")
    return " | ".join(parts)


@dataclass
class TimerRecord:
    """Tracks a server timer (`PROGRESS` with `IsTimer=True`)."""

    op_id: str
    title: str
    value: int = 0
    max_value: int = 0
    targets: list[str] = field(default_factory=list)
    is_done: bool = False

    @property
    def is_expired(self) -> bool:
        return self.max_value > 0 and self.value <= 0

    @property
    def percentage(self) -> int:
        if self.max_value <= 0:
            return 0
        return max(0, min(100, int(self.value * 100.0 / self.max_value)))


@dataclass
class GolarionCalendar:
    """Pure-Python Golarion / Absalom Reckoning (AR) calendar & combat clock model."""

    absolute: int = 0
    relative: int = 0
    combat_mode: bool = False
    running: bool = False
    turn: int = 0
    frame: int = 0

    # Computed date/time fields
    year: int = 4700
    month: int = 0       # 0..11
    day: int = 1         # 1..31
    dow: int = 5         # 0..6
    hour: int = 0        # 0..23
    minute: int = 0      # 0..59
    second: int = 0      # 0..59
    pm: int = 0          # 0 or 1
    epoch_days: int = 0

    initiative_slots: list[dict[str, Any]] = field(default_factory=list)
    current_slot: int = 0
    active_actor: str = ""
    ondeck_status: int = -1

    def __post_init__(self) -> None:
        self._recalc()

    def set_time(
        self,
        absolute: int | float | None = None,
        relative: int | float | None = None,
        combat_mode: bool | None = None,
        running: bool | None = None,
        turn: int | None = None,
        frame: int | None = None,
    ) -> None:
        """Update clock timestamps and recalculate calendar fields."""
        if absolute is not None:
            self.absolute = int(round(float(absolute)))
        if relative is not None:
            self.relative = int(round(float(relative)))
        if combat_mode is not None:
            self.combat_mode = bool(combat_mode)
        if running is not None:
            self.running = bool(running)
        if turn is not None:
            self.turn = int(turn)
        if frame is not None:
            self.frame = int(frame)
        self._recalc()

    def advance_time(self, delta_seconds: int = 0, delta_turns: int = 0) -> None:
        """Advance both absolute and relative time by seconds and/or 6-second turns."""
        total_seconds = int(delta_seconds) + int(delta_turns) * 6
        self.absolute += total_seconds
        self.relative += total_seconds
        if self.combat_mode and delta_turns:
            self.turn += int(delta_turns)
        self._recalc()

    def advance_slot(self) -> dict[str, Any] | None:
        """Advance ``current_slot`` to the next initiative entry and return it."""
        if not self.initiative_slots:
            return None
        self.current_slot = (self.current_slot + 1) % len(self.initiative_slots)
        if self.current_slot == 0:
            self.advance_time(delta_seconds=0, delta_turns=1)
        slot = self.initiative_slots[self.current_slot]
        self.active_actor = str(slot.get("Name", ""))
        return slot

    def select_actor_slot(self, actor_name_or_id: str) -> int:
        """Find and set ``current_slot`` matching ``actor_name_or_id``."""
        if not actor_name_or_id:
            return self.current_slot
        clean_target = strip_nameplate_prefix(actor_name_or_id)
        for idx, slot in enumerate(self.initiative_slots):
            sname = str(slot.get("Name", ""))
            if sname == actor_name_or_id or strip_nameplate_prefix(sname) == clean_target:
                self.current_slot = idx
                self.active_actor = sname
                return idx
        return self.current_slot

    def compute_ondeck_status(self, my_names: list[str] | set[str]) -> int:
        """Compute on-deck position (`0` = YOUR TURN, `1` = ON DECK, `2` = On deck in 1, `-1` = other).

        Ported from ``update_ondeck_list`` / ``ondeck_calc`` in ``bin/mapper_legacy.tcl`` lines 2957-3005.
        """
        if not self.combat_mode or not self.initiative_slots or not my_names:
            self.ondeck_status = -1
            return -1

        clean_mine = {strip_nameplate_prefix(n) for n in my_names if n} | {n for n in my_names if n}
        names = [str(s.get("Name", "")) for s in self.initiative_slots if s.get("Name")]
        if not names:
            self.ondeck_status = -1
            return -1

        cur_idx = max(0, min(self.current_slot, len(names) - 1))
        if self.active_actor and self.active_actor in names:
            cur_idx = names.index(self.active_actor)

        rotated = names[cur_idx:] + names[:cur_idx]
        best = -1
        for pos, name in enumerate(rotated):
            if name in clean_mine or strip_nameplate_prefix(name) in clean_mine:
                if best < 0 or pos < best:
                    best = pos
                break
        self.ondeck_status = best if best in (0, 1, 2) else -1
        return self.ondeck_status

    def track_health_change(self, obj_id: str, new_attrs: dict[str, Any]) -> bool:
        """Update initiative slot health/flat-footed state from an ``OA`` packet (`gmaclock::track_health_change`)."""
        if not self.initiative_slots or not isinstance(new_attrs, dict):
            return False
        health = new_attrs.get("Health")
        if not isinstance(health, dict):
            return False

        target_name = obj_id[1:] if obj_id.startswith("@") else obj_id
        changed = False
        for slot in self.initiative_slots:
            sname = str(slot.get("Name", ""))
            if sname == target_name or strip_nameplate_prefix(sname) == strip_nameplate_prefix(target_name):
                if "IsFlatFooted" in health:
                    ff = bool(health["IsFlatFooted"])
                    if bool(slot.get("IsFlatFooted", slot.get("FlatFooted", False))) != ff:
                        slot["IsFlatFooted"] = ff
                        slot["FlatFooted"] = ff
                        changed = True
                if "MaxHP" in health or "LethalDamage" in health:
                    max_hp = int(health.get("MaxHP", slot.get("MaxHP", 0)) or 0)
                    lethal = int(health.get("LethalDamage", slot.get("LethalDamage", 0)) or 0)
                    if max_hp > 0:
                        slot["CurrentHP"] = max_hp - lethal
                        slot["MaxHP"] = max_hp
                        slot["LethalDamage"] = lethal
                        changed = True
        return changed

    def _recalc(self) -> None:
        """Recalculate calendar date/time from ``self.absolute`` matching ``gmaclock::_recalc``."""
        epoch = _j(4700, 1, 1)
        s = self.absolute
        self.second = s % 60
        m = s // 60
        self.minute = m % 60
        h = m // 60
        self.hour = h % 24
        self.pm = self.hour >= 12
        self.epoch_days = h // 24
        self.dow = (self.epoch_days + 5) % 7
        y, mo, d = _ymd(self.epoch_days + epoch)
        self.year = y
        self.month = mo - 1
        self.day = d

    @property
    def month_name(self) -> str:
        return MONTH_NAMES[self.month % 12]

    @property
    def day_name(self) -> str:
        return DAY_NAMES[self.dow % 7]

    def to_string(self) -> str:
        """Format full Golarion date/time string matching ``gmaclock::to_string``."""
        suffix = ordinal_suffix(self.day)
        rel_str = delta_string(self.relative)
        return (
            f"{self.hour:02d}:{self.minute:02d}:{self.second:02d} "
            f"{self.day_name}, {self.day}{suffix} of {self.month_name}, "
            f"{self.year} AR [{rel_str}]"
        )


if HAS_PYSIDE6:

    class TimerRequestDialog(QDialog):
        """Dialog to submit a ``TMRQ`` timer request to the GM (`initiate_timer_request` in `bin/mapper_legacy.tcl`)."""

        def __init__(
            self,
            my_names: list[str] | None = None,
            parent: QWidget | None = None,
        ) -> None:
            super().__init__(parent)
            self.setWindowTitle("New Timer Request")
            self.setMinimumWidth(420)
            self.request_id = new_id()
            self.my_names = list(my_names or [])

            layout = QVBoxLayout(self)
            form = QFormLayout()

            self.desc_edit = QLineEdit(self)
            self.desc_edit.setPlaceholderText("e.g. Haste, Bless, Torch")
            form.addRow("Description:", self.desc_edit)

            self.expires_edit = QLineEdit(self)
            self.expires_edit.setPlaceholderText("e.g. +10 rounds, 10 minutes, @12:00")
            form.addRow("Expires:", self.expires_edit)

            target_row = QHBoxLayout()
            self.targets_edit = QLineEdit(self)
            self.targets_edit.setPlaceholderText("Space-separated names (blank = all players)")
            target_row.addWidget(self.targets_edit, 1)
            self.btn_me = QPushButton("ME", self)
            self.btn_me.setEnabled(bool(self.my_names))
            self.btn_me.clicked.connect(lambda: self.targets_edit.setText(" ".join(self.my_names)))
            target_row.addWidget(self.btn_me)
            form.addRow("Targets:", target_row)

            self.chk_running = QCheckBox("Running Now", self)
            self.chk_running.setChecked(True)
            form.addRow("", self.chk_running)

            self.chk_show_all = QCheckBox("Show to Players", self)
            self.chk_show_all.setChecked(True)
            form.addRow("", self.chk_show_all)

            layout.addLayout(form)

            self.status_label = QLabel("", self)
            self.status_label.setStyleSheet("color: #c53030;")
            layout.addWidget(self.status_label)

            buttons = QDialogButtonBox(
                QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel,
                self,
            )
            buttons.button(QDialogButtonBox.StandardButton.Ok).setText("Request")
            buttons.accepted.connect(self._on_accept)
            buttons.rejected.connect(self.reject)
            layout.addWidget(buttons)

        def _on_accept(self) -> None:
            if not self.desc_edit.text().strip() or not self.expires_edit.text().strip():
                self.status_label.setText("Description and expiration time are required.")
                return
            self.accept()

        def request_payload(self) -> dict[str, Any]:
            targets = [t for t in self.targets_edit.text().strip().split() if t]
            return {
                "req_id": self.request_id,
                "description": self.desc_edit.text().strip(),
                "expires": self.expires_edit.text().strip(),
                "is_running": self.chk_running.isChecked(),
                "targets": targets,
                "to_all": self.chk_show_all.isChecked(),
            }

    class ClockWidget(QWidget):
        """Analog 12-hour clock and 60-second / 10-round combat sweep face."""

        def __init__(self, calendar: GolarionCalendar, parent: QWidget | None = None) -> None:
            super().__init__(parent)
            self.calendar = calendar
            self.setMinimumSize(130, 130)

        def paintEvent(self, event: Any) -> None:
            painter = QPainter(self)
            painter.setRenderHint(QPainter.RenderHint.Antialiasing, True)
            w = self.width()
            h = self.height()
            side = min(w, h) - 8
            cx = w / 2.0
            cy = h / 2.0
            radius = side / 2.0

            # Outer dial
            bg_color = QColor("#1e2430") if self.calendar.pm else QColor("#f5f0e1")
            fg_color = QColor("#e8ecf2") if self.calendar.pm else QColor("#222222")
            painter.setPen(QPen(QColor("#666666"), 2.0))
            painter.setBrush(QBrush(bg_color))
            painter.drawEllipse(QPointF(cx, cy), radius, radius)

            if self.calendar.combat_mode:
                # Combat mode concentric pie sweeps (_update_combat in bin/gmaclock.tcl)
                rel = float(max(0, self.calendar.relative))
                sweeps = [
                    (rel, 6.0, 0.90, QColor(224, 64, 64, 90)),        # 6s round sweep (red)
                    (rel / 6.0, 10.0, 0.70, QColor(48, 176, 80, 90)), # 10-round minute sweep (green)
                    (rel / 60.0, 10.0, 0.50, QColor(48, 128, 208, 90)),  # 10-minute turn sweep (blue)
                ]
                painter.setPen(Qt.PenStyle.NoPen)
                for pos, total, length_frac, col in sweeps:
                    frac = (pos % total) / total
                    if frac * 360.0 > 1.0:
                        r_s = radius * length_frac
                        rect = QRectF(cx - r_s, cy - r_s, r_s * 2.0, r_s * 2.0)
                        painter.setBrush(QBrush(col))
                        painter.drawPie(rect, 90 * 16, int(-360.0 * frac * 16))

                # 10 decimal round ticks
                painter.setPen(QPen(fg_color, 1.5))
                for i in range(10):
                    angle = math.radians(i * 36.0 - 90.0)
                    r1 = radius * 0.82
                    r2 = radius * 0.94
                    painter.drawLine(
                        QPointF(cx + r1 * math.cos(angle), cy + r1 * math.sin(angle)),
                        QPointF(cx + r2 * math.cos(angle), cy + r2 * math.sin(angle)),
                    )
            else:
                # Standard 12-hour ticks
                painter.setPen(QPen(fg_color, 1.5))
                for i in range(12):
                    angle = math.radians(i * 30.0 - 90.0)
                    r1 = radius * 0.82
                    r2 = radius * 0.94
                    painter.drawLine(
                        QPointF(cx + r1 * math.cos(angle), cy + r1 * math.sin(angle)),
                        QPointF(cx + r2 * math.cos(angle), cy + r2 * math.sin(angle)),
                    )

            # Hour hand
            hour_val = (self.calendar.hour % 12) + self.calendar.minute / 60.0
            hour_angle = math.radians(hour_val * 30.0 - 90.0)
            painter.setPen(QPen(fg_color, 3.5, Qt.PenStyle.SolidLine, Qt.PenCapStyle.RoundCap))
            painter.drawLine(
                QPointF(cx, cy),
                QPointF(cx + radius * 0.52 * math.cos(hour_angle), cy + radius * 0.52 * math.sin(hour_angle)),
            )

            # Minute hand
            min_val = self.calendar.minute + self.calendar.second / 60.0
            min_angle = math.radians(min_val * 6.0 - 90.0)
            painter.setPen(QPen(fg_color, 2.2, Qt.PenStyle.SolidLine, Qt.PenCapStyle.RoundCap))
            painter.drawLine(
                QPointF(cx, cy),
                QPointF(cx + radius * 0.75 * math.cos(min_angle), cy + radius * 0.75 * math.sin(min_angle)),
            )

            # Second / Combat turn hand
            sec_angle = math.radians(self.calendar.second * 6.0 - 90.0)
            sec_color = QColor("#e04040") if self.calendar.combat_mode else QColor("#3080d0")
            painter.setPen(QPen(sec_color, 1.5, Qt.PenStyle.SolidLine, Qt.PenCapStyle.RoundCap))
            painter.drawLine(
                QPointF(cx, cy),
                QPointF(cx + radius * 0.82 * math.cos(sec_angle), cy + radius * 0.82 * math.sin(sec_angle)),
            )
            painter.end()

    class InitiativeClockPanel(QWidget):
        """Dockable panel displaying the analog/combat clock, on-deck banner, initiative slots, and timers."""

        timeAdvanceRequested = Signal(int, int)             # (delta_seconds, delta_turns)
        nextSlotRequested = Signal()
        combatModeToggled = Signal(bool)
        slotSelected = Signal(str)                          # actor_name
        slotActivated = Signal(str)                         # actor_name (double-click / locate)
        slotAttributeToggled = Signal(str, str, bool)       # (actor_name, attr_key, enabled)
        timerRequestClicked = Signal()

        def __init__(
            self,
            calendar: GolarionCalendar | None = None,
            parent: QWidget | None = None,
        ) -> None:
            super().__init__(parent)
            self.calendar = calendar or GolarionCalendar()
            self.timers: dict[str, TimerRecord] = {}
            self.timer_scope: str = "mine"  # "none" | "mine" | "all"
            self.my_names: list[str] = []

            self._realtime_timer = QTimer(self)
            self._realtime_timer.setInterval(1000)
            self._realtime_timer.timeout.connect(self._on_realtime_tick)

            layout = QVBoxLayout(self)
            layout.setContentsMargins(6, 6, 6, 6)

            # On-Deck turn indicator banner (set_ondeck in bin/mapper_legacy.tcl)
            self.ondeck_banner = QLabel("", self)
            self.ondeck_banner.setAlignment(Qt.AlignmentFlag.AlignCenter)
            bfont = QFont()
            bfont.setBold(True)
            bfont.setPointSize(11)
            self.ondeck_banner.setFont(bfont)
            self.ondeck_banner.setVisible(False)
            layout.addWidget(self.ondeck_banner)

            top_row = QHBoxLayout()
            self.clock_widget = ClockWidget(self.calendar, self)
            top_row.addWidget(self.clock_widget, 0)

            info_col = QVBoxLayout()
            self.date_label = QLabel(self.calendar.to_string(), self)
            self.date_label.setWordWrap(True)
            font = QFont()
            font.setBold(True)
            self.date_label.setFont(font)
            info_col.addWidget(self.date_label)

            self.delta_label = QLabel(f"Elapsed: {delta_string(self.calendar.relative)}", self)
            info_col.addWidget(self.delta_label)

            btn_row = QHBoxLayout()
            self.btn_plus_round = QPushButton("+1 Rd (6s)", self)
            self.btn_plus_round.clicked.connect(lambda: self.timeAdvanceRequested.emit(0, 1))
            self.btn_plus_min = QPushButton("+1 Min", self)
            self.btn_plus_min.clicked.connect(lambda: self.timeAdvanceRequested.emit(60, 0))
            self.btn_plus_hr = QPushButton("+1 Hr", self)
            self.btn_plus_hr.clicked.connect(lambda: self.timeAdvanceRequested.emit(3600, 0))
            btn_row.addWidget(self.btn_plus_round)
            btn_row.addWidget(self.btn_plus_min)
            btn_row.addWidget(self.btn_plus_hr)
            info_col.addLayout(btn_row)

            combat_row = QHBoxLayout()
            self.btn_combat_mode = QPushButton("Combat Mode", self)
            self.btn_combat_mode.setCheckable(True)
            self.btn_combat_mode.setChecked(self.calendar.combat_mode)
            self.btn_combat_mode.clicked.connect(lambda checked: self.combatModeToggled.emit(bool(checked)))
            self.btn_next_slot = QPushButton("Next Turn \u25b6", self)
            self.btn_next_slot.setToolTip("Advance to the next initiative slot")
            self.btn_next_slot.clicked.connect(self.nextSlotRequested.emit)
            self.btn_req_timer = QPushButton("+ Timer...", self)
            self.btn_req_timer.setToolTip("Request a new countdown timer from the GM (TMRQ)")
            self.btn_req_timer.clicked.connect(self.timerRequestClicked.emit)
            combat_row.addWidget(self.btn_combat_mode)
            combat_row.addWidget(self.btn_next_slot)
            combat_row.addWidget(self.btn_req_timer)
            info_col.addLayout(combat_row)

            top_row.addLayout(info_col, 1)
            layout.addLayout(top_row)

            # Initiative slot list
            self.slot_tree = QTreeWidget(self)
            self.slot_tree.setHeaderLabels(["Slot", "Init", "Actor", "HP / Status"])
            self.slot_tree.header().setSectionResizeMode(QHeaderView.ResizeMode.ResizeToContents)
            self.slot_tree.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
            self.slot_tree.itemClicked.connect(self._on_slot_item_clicked)
            self.slot_tree.itemDoubleClicked.connect(self._on_slot_item_double_clicked)
            self.slot_tree.customContextMenuRequested.connect(self._on_slot_context_menu)
            layout.addWidget(self.slot_tree, 1)

            # Active Timers group (populate_timer_widgets in bin/mapper_legacy.tcl)
            self.timers_group = QGroupBox("Active Timers", self)
            self.timers_layout = QVBoxLayout(self.timers_group)
            self.timers_layout.setContentsMargins(4, 4, 4, 4)
            self.timers_group.setVisible(False)
            layout.addWidget(self.timers_group, 0)

        def _on_realtime_tick(self) -> None:
            if self.calendar.running and not self.calendar.combat_mode:
                self.calendar.advance_time(delta_seconds=1, delta_turns=0)
                self.refresh()

        def set_timer_scope(self, scope: str) -> None:
            """Set timer visibility scope (`'none'`, `'mine'`, or `'all'`)."""
            self.timer_scope = scope
            self._rebuild_timers_ui()

        def update_timer(self, payload: dict[str, Any]) -> None:
            """Handle a ``PROGRESS`` message with ``IsTimer=True`` (`DoCommandPROGRESS`)."""
            op_id = str(payload.get("OperationID", ""))
            is_done = bool(payload.get("IsDone", False))
            if op_id == "*":
                if is_done:
                    self.timers.clear()
                    self._rebuild_timers_ui()
                return
            if not op_id:
                return
            if is_done:
                self.timers.pop(op_id, None)
                self._rebuild_timers_ui()
                return

            self.timers[op_id] = TimerRecord(
                op_id=op_id,
                title=str(payload.get("Title", "Timer")),
                value=int(payload.get("Value", payload.get("Current", 0)) or 0),
                max_value=int(payload.get("MaxValue", payload.get("Max", 0)) or 0),
                targets=list(payload.get("Targets", []) or []),
                is_done=False,
            )
            self._rebuild_timers_ui()

        def _is_timer_visible(self, rec: TimerRecord) -> bool:
            if self.timer_scope == "none":
                return False
            if self.timer_scope == "all" or not rec.targets:
                return True
            if self.timer_scope == "mine":
                if not self.my_names:
                    return True
                clean_mine = {strip_nameplate_prefix(n) for n in self.my_names} | set(self.my_names)
                return any(t in clean_mine or strip_nameplate_prefix(t) in clean_mine for t in rec.targets)
            return True

        def _rebuild_timers_ui(self) -> None:
            while self.timers_layout.count():
                child = self.timers_layout.takeAt(0)
                if child.widget():
                    child.widget().deleteLater()

            visible_records = [r for r in self.timers.values() if self._is_timer_visible(r)]
            if not visible_records:
                self.timers_group.setVisible(False)
                return

            self.timers_group.setVisible(True)
            for rec in visible_records:
                bar = QProgressBar(self.timers_group)
                if rec.max_value <= 0:
                    bar.setRange(0, 0)
                    bar.setFormat(f"{rec.title}: ...")
                elif rec.is_expired:
                    bar.setRange(0, 100)
                    bar.setValue(100)
                    bar.setFormat(f"{rec.title}: EXPIRED")
                    bar.setStyleSheet("QProgressBar::chunk { background-color: #c53030; }")
                else:
                    bar.setRange(0, rec.max_value)
                    bar.setValue(rec.value)
                    bar.setFormat(f"{rec.title}: %p% ({delta_string(rec.value // 10 if rec.max_value > 100 else rec.value)})")
                self.timers_layout.addWidget(bar)

        def _update_ondeck_banner(self) -> None:
            place = self.calendar.ondeck_status if self.calendar.combat_mode else -1
            if place == 0:
                self.ondeck_banner.setText("YOUR TURN")
                self.ondeck_banner.setStyleSheet(
                    "background-color: #2f855a; color: #ffffff; padding: 4px; border-radius: 3px;"
                )
                self.ondeck_banner.setVisible(True)
            elif place == 1:
                self.ondeck_banner.setText("ON DECK")
                self.ondeck_banner.setStyleSheet(
                    "background-color: #c53030; color: #ffffff; padding: 4px; border-radius: 3px;"
                )
                self.ondeck_banner.setVisible(True)
            elif place == 2:
                self.ondeck_banner.setText("On deck in 1")
                self.ondeck_banner.setStyleSheet(
                    "background-color: #ecc94b; color: #1a202c; padding: 4px; border-radius: 3px;"
                )
                self.ondeck_banner.setVisible(True)
            else:
                self.ondeck_banner.setVisible(False)

        def refresh(self) -> None:
            """Refresh clock face, date labels, on-deck banner, and initiative slots."""
            if self.calendar.running and not self.calendar.combat_mode:
                if not self._realtime_timer.isActive():
                    self._realtime_timer.start()
            else:
                self._realtime_timer.stop()

            self.btn_combat_mode.blockSignals(True)
            self.btn_combat_mode.setChecked(self.calendar.combat_mode)
            self.btn_combat_mode.blockSignals(False)

            self.date_label.setText(self.calendar.to_string())
            if self.calendar.combat_mode:
                rnd = (self.calendar.relative // 6) + 1
                self.delta_label.setText(
                    f"Round #{rnd} — Elapsed: {delta_string(self.calendar.relative)}"
                )
            else:
                self.delta_label.setText(f"Elapsed: {delta_string(self.calendar.relative)}")
            self._update_ondeck_banner()
            self.clock_widget.update()

            self.slot_tree.clear()
            for idx, slot in enumerate(self.calendar.initiative_slots):
                is_current = idx == self.calendar.current_slot
                if self.calendar.active_actor and str(slot.get("Name", "")) == self.calendar.active_actor:
                    is_current = True
                marker = "\u25b6 " if is_current else ""
                slot_num = slot.get("Slot", idx + 1)
                slot_str = f"{marker}{slot_num}"
                init_str = str(slot.get("Initiative", slot.get("Roll", slot_num)))
                actor_str = nameplate_text(slot)
                hp_info = slot_status_summary(slot)

                item = QTreeWidgetItem([slot_str, init_str, actor_str, hp_info])
                raw_name = str(slot.get("Name", ""))
                item.setData(0, Qt.ItemDataRole.UserRole, raw_name)
                item.setData(1, Qt.ItemDataRole.UserRole, idx)

                # Visual styling matching gmaclock::update_initiative_slots
                bg_col: QColor | None = None
                fg_col: QColor | None = None
                cur_hp = slot.get("CurrentHP")
                if cur_hp is None and "MaxHP" in slot:
                    cur_hp = int(slot.get("MaxHP", 0)) - int(slot.get("LethalDamage", 0))

                if is_current:
                    bg_col = QColor("#2c7a7b")
                    fg_col = QColor("#ffffff")
                elif cur_hp is not None and int(cur_hp) < 0:
                    bg_col = QColor("#742a2a")
                    fg_col = QColor("#fed7d7")
                elif slot.get("IsReady") or slot.get("HasReadiedAction") or slot.get("ready"):
                    bg_col = QColor("#975a16")
                    fg_col = QColor("#fefcbf")
                elif slot.get("IsHold") or slot.get("IsHolding") or slot.get("hold"):
                    bg_col = QColor("#553c9a")
                    fg_col = QColor("#e9d8fd")
                elif cur_hp is not None and int(cur_hp) == 0:
                    bg_col = QColor("#7b341e")
                    fg_col = QColor("#feebc8")

                if is_current:
                    bold_font = QFont()
                    bold_font.setBold(True)
                    for col_i in range(4):
                        item.setFont(col_i, bold_font)

                if bg_col is not None:
                    for col_i in range(4):
                        item.setBackground(col_i, QBrush(bg_col))
                if fg_col is not None:
                    for col_i in range(4):
                        item.setForeground(col_i, QBrush(fg_col))

                self.slot_tree.addTopLevelItem(item)

        def _on_slot_item_clicked(self, item: QTreeWidgetItem, _col: int) -> None:
            actor_name = str(item.data(0, Qt.ItemDataRole.UserRole) or "")
            if actor_name:
                self.slotSelected.emit(actor_name)

        def _on_slot_item_double_clicked(self, item: QTreeWidgetItem, _col: int) -> None:
            actor_name = str(item.data(0, Qt.ItemDataRole.UserRole) or "")
            if actor_name:
                self.slotActivated.emit(actor_name)

        def _on_slot_context_menu(self, pos: Any) -> None:
            item = self.slot_tree.itemAt(pos)
            if item is None:
                return
            actor_name = str(item.data(0, Qt.ItemDataRole.UserRole) or "")
            slot_idx = int(item.data(1, Qt.ItemDataRole.UserRole) or 0)
            if not actor_name or not (0 <= slot_idx < len(self.calendar.initiative_slots)):
                return
            slot = self.calendar.initiative_slots[slot_idx]
            disp_name = strip_nameplate_prefix(actor_name)

            menu = QMenu(self)
            act_locate = QAction(f"Center Map on {disp_name}", menu)
            act_locate.triggered.connect(lambda: self.slotActivated.emit(actor_name))
            menu.addAction(act_locate)

            act_select = QAction(f"Inspect {disp_name} in Combat Dock", menu)
            act_select.triggered.connect(lambda: self.slotSelected.emit(actor_name))
            menu.addAction(act_select)

            act_active = QAction(f"Set {disp_name} as Active Turn", menu)
            act_active.triggered.connect(lambda: self._set_active_slot(slot_idx, actor_name))
            menu.addAction(act_active)

            menu.addSeparator()
            is_ready = bool(slot.get("IsReady") or slot.get("HasReadiedAction"))
            act_ready = QAction("Readied Action (\u23f2)", menu)
            act_ready.setCheckable(True)
            act_ready.setChecked(is_ready)
            act_ready.triggered.connect(
                lambda checked: self._toggle_slot_flag(slot_idx, actor_name, "HasReadiedAction", bool(checked))
            )
            menu.addAction(act_ready)

            is_hold = bool(slot.get("IsHold") or slot.get("IsHolding"))
            act_hold = QAction("Holding Initiative (\u23f8)", menu)
            act_hold.setCheckable(True)
            act_hold.setChecked(is_hold)
            act_hold.triggered.connect(
                lambda checked: self._toggle_slot_flag(slot_idx, actor_name, "IsHolding", bool(checked))
            )
            menu.addAction(act_hold)

            is_ff = bool(slot.get("FlatFooted") or slot.get("IsFlatFooted"))
            act_ff = QAction("Flat-Footed (\u26a0)", menu)
            act_ff.setCheckable(True)
            act_ff.setChecked(is_ff)
            act_ff.triggered.connect(
                lambda checked: self._toggle_slot_flag(slot_idx, actor_name, "IsFlatFooted", bool(checked))
            )
            menu.addAction(act_ff)

            menu.exec(self.slot_tree.viewport().mapToGlobal(pos))

        def _set_active_slot(self, slot_idx: int, actor_name: str) -> None:
            self.calendar.current_slot = slot_idx
            self.calendar.active_actor = actor_name
            self.refresh()
            self.slotActivated.emit(actor_name)

        def _toggle_slot_flag(self, slot_idx: int, actor_name: str, key: str, enabled: bool) -> None:
            if 0 <= slot_idx < len(self.calendar.initiative_slots):
                slot = self.calendar.initiative_slots[slot_idx]
                slot[key] = enabled
                if key == "HasReadiedAction":
                    slot["IsReady"] = enabled
                elif key == "IsHolding":
                    slot["IsHold"] = enabled
                elif key == "IsFlatFooted":
                    slot["FlatFooted"] = enabled
                self.refresh()
                self.slotAttributeToggled.emit(actor_name, key, enabled)

else:

    class ClockWidget:  # type: ignore[no-redef]
        def __init__(self, calendar: GolarionCalendar, parent: Any = None) -> None:
            self.calendar = calendar

    class InitiativeClockPanel:  # type: ignore[no-redef]
        def __init__(self, calendar: GolarionCalendar | None = None, parent: Any = None) -> None:
            self.calendar = calendar or GolarionCalendar()
            self.timers: dict[str, TimerRecord] = {}
            self.timer_scope: str = "mine"
            self.my_names: list[str] = []

        def set_timer_scope(self, scope: str) -> None:
            self.timer_scope = scope

        def update_timer(self, payload: dict[str, Any]) -> None:
            op_id = str(payload.get("OperationID", ""))
            if op_id == "*" and payload.get("IsDone"):
                self.timers.clear()
            elif op_id:
                if payload.get("IsDone"):
                    self.timers.pop(op_id, None)
                else:
                    self.timers[op_id] = TimerRecord(
                        op_id=op_id,
                        title=str(payload.get("Title", "Timer")),
                        value=int(payload.get("Value", 0) or 0),
                        max_value=int(payload.get("MaxValue", 0) or 0),
                        targets=list(payload.get("Targets", []) or []),
                    )

        def refresh(self) -> None:
            pass
