"""Server Ping Test dialog and timing helpers (`ServerPingTest`).

Ported from `ServerPingTest`, `_ping_server`, `scan_fractional_seconds`, and
`_server_ping_reply` in `bin/mapper_legacy.tcl`.
"""

from __future__ import annotations

from datetime import datetime
import re
import time
from typing import Any, Callable

try:
    from PySide6.QtCore import Qt, QTimer
    from PySide6.QtGui import QCloseEvent
    from PySide6.QtWidgets import (
        QDialog,
        QHBoxLayout,
        QHeaderView,
        QPushButton,
        QTableWidget,
        QTableWidgetItem,
        QVBoxLayout,
        QWidget,
    )

    QT_AVAILABLE = True
except ImportError:  # pragma: no cover
    QT_AVAILABLE = False

_RFC3339_RE = re.compile(
    r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:\d{2})$"
)


def parse_rfc3339_seconds(ts: str) -> float:
    """Parse an RFC 3339 timestamp with optional arbitrary-precision fractional seconds."""
    raw = str(ts or "").strip()
    if not raw or raw == "0001-01-01T00:00:00Z":
        return 0.0
    m = _RFC3339_RE.match(raw)
    if not m:
        return 0.0
    base, frac, tz = m.groups()
    if tz == "Z":
        tz = "+00:00"
    try:
        dt = datetime.fromisoformat(f"{base}{tz}")
    except ValueError:
        return 0.0
    frac_sec = int(frac) / (10 ** len(frac)) if frac else 0.0
    return dt.timestamp() + frac_sec


def compute_ping_metrics(
    payload: dict[str, Any],
    now_us: int,
) -> tuple[int, float, float, float] | None:
    """Compute `(slot_idx, in_transit_ms, in_server_ms, round_trip_ms)` for an `__spt__` ECHO reply."""
    if payload.get("s") != "__spt__":
        return None
    try:
        idx = int(payload.get("i", 0) or 0)
    except (TypeError, ValueError):
        return None
    o_dict = payload.get("o")
    origin_us = 0
    if isinstance(o_dict, dict):
        try:
            origin_us = int(o_dict.get("origin", 0) or 0)
        except (TypeError, ValueError):
            origin_us = 0

    round_trip_ms = max(0.0, (now_us - origin_us) / 1000.0) if origin_us > 0 else 0.0
    server_recd = parse_rfc3339_seconds(str(payload.get("ReceivedTime") or ""))
    server_sent = parse_rfc3339_seconds(str(payload.get("SentTime") or ""))
    in_server_ms = (
        max(0.0, (server_sent - server_recd) * 1000.0)
        if server_recd > 0.0 and server_sent > 0.0
        else 0.0
    )
    in_transit_ms = max(0.0, round_trip_ms - in_server_ms)
    return (idx, in_transit_ms, in_server_ms, round_trip_ms)


if QT_AVAILABLE:

    class ServerPingDialog(QDialog):
        """Periodic `ECHO` latency monitor (`ServerPingTest`) showing 6 rolling samples."""

        def __init__(
            self,
            send_ping_cb: Callable[[int, int], bool],
            interval_ms: int = 10_000,
            auto_start: bool = True,
            parent: QWidget | None = None,
        ) -> None:
            super().__init__(parent)
            self._send_ping_cb = send_ping_cb
            self._slot_idx = 5
            self.setWindowTitle("Server Ping Test")
            self.resize(460, 260)

            layout = QVBoxLayout(self)
            self.table = QTableWidget(6, 4, self)
            self.table.setHorizontalHeaderLabels(
                ["Time", "In Transit", "In Server", "Round-Trip"]
            )
            self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
            self.table.verticalHeader().setVisible(False)
            for col in range(4):
                self.table.horizontalHeader().setSectionResizeMode(
                    col, QHeaderView.ResizeMode.Stretch
                )
            for row in range(6):
                self.table.setItem(row, 0, QTableWidgetItem("--:--:--"))
                for col in range(1, 4):
                    it = QTableWidgetItem("")
                    it.setTextAlignment(
                        Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter
                    )
                    self.table.setItem(row, col, it)
            layout.addWidget(self.table, stretch=1)

            btn_row = QHBoxLayout()
            self.btn_ping_now = QPushButton("Ping Now", self)
            self.btn_dismiss = QPushButton("Dismiss", self)
            btn_row.addWidget(self.btn_ping_now)
            btn_row.addStretch(1)
            btn_row.addWidget(self.btn_dismiss)
            layout.addLayout(btn_row)

            self.btn_ping_now.clicked.connect(self.send_ping)
            self.btn_dismiss.clicked.connect(self.close)

            self._timer = QTimer(self)
            self._timer.setInterval(max(100, int(interval_ms)))
            self._timer.timeout.connect(self.send_ping)
            if auto_start:
                self._timer.start()
                self.send_ping()

        def send_ping(self) -> int:
            self._slot_idx = (self._slot_idx + 1) % 6
            origin_us = time.perf_counter_ns() // 1000
            sent = bool(self._send_ping_cb(self._slot_idx, origin_us))
            self.table.setItem(self._slot_idx, 0, QTableWidgetItem(time.strftime("%H:%M:%S")))
            status_text = "pending..." if sent else "disconnected"
            self.table.setItem(self._slot_idx, 1, QTableWidgetItem(status_text))
            for col in (2, 3):
                it = QTableWidgetItem("")
                it.setTextAlignment(
                    Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter
                )
                self.table.setItem(self._slot_idx, col, it)
            return self._slot_idx

        def handle_echo_reply(
            self,
            payload: dict[str, Any],
            now_us: int | None = None,
        ) -> bool:
            resolved_now = now_us if now_us is not None else (time.perf_counter_ns() // 1000)
            metrics = compute_ping_metrics(payload, resolved_now)
            if metrics is None:
                return False
            idx, in_transit_ms, in_server_ms, round_trip_ms = metrics
            if not (0 <= idx < 6):
                return False
            for col, val in (
                (1, f"{in_transit_ms:.3f}ms"),
                (2, f"{in_server_ms:.3f}ms"),
                (3, f"{round_trip_ms:.3f}ms"),
            ):
                it = QTableWidgetItem(val)
                it.setTextAlignment(
                    Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter
                )
                self.table.setItem(idx, col, it)
            return True

        def reject(self) -> None:
            self._timer.stop()
            super().reject()

        def closeEvent(self, event: QCloseEvent) -> None:
            self._timer.stop()
            super().closeEvent(event)

else:  # pragma: no cover

    class ServerPingDialog:  # type: ignore[no-redef]
        def __init__(self, *_args: Any, **_kwargs: Any) -> None:
            pass
