"""Network client bridge for ``py_dieroller`` wrapping ``gma_mapper.net.client``.

Ported from ``GMADieRoller/MapService.py`` using PySide6 + ``GMANetworkClient``
instead of worker threads and ``MadScienceZone.GMA.SocketInterface``.
"""

from __future__ import annotations

import getpass
from typing import Any

from gma_mapper import GMAMapperVersion
from gma_mapper.net.client import GMANetworkClient
from py_dieroller import APP_VERSION
from py_dieroller.debug import dprint
from py_dieroller.settings import SettingsStore


def format_chat_event_messages(
    payload: dict[str, Any],
) -> list[dict[str, Any]]:
    """Convert an incoming ``TO`` protocol payload into styled message dictionaries."""
    sender = str(
        payload.get("Sender")
        or (payload.get("Origin") if isinstance(payload.get("Origin"), str) else "")
        or "Server"
    )
    text = str(payload.get("Text") or "")
    to_all = bool(payload.get("ToAll", False))
    recipients = [str(r) for r in (payload.get("Recipients") or payload.get("Targets") or [])]

    if to_all:
        return [
            {"text": f"{sender}: ", "style": "user", "newline": False},
            {"text": text, "newline": True},
        ]

    msgs: list[dict[str, Any]] = []
    if len(recipients) != 1 or sender != recipients[0]:
        recip_str = ",".join(recipients) if recipients else "GM"
        msgs.append(
            {
                "text": f"{sender} to {recip_str}: ",
                "style": "privateuser",
                "newline": False,
            }
        )
    msgs.append({"text": text, "style": "privatemsg", "newline": True})
    return msgs


def format_roll_event_messages(payload: dict[str, Any]) -> list[dict[str, Any]]:
    """Convert an incoming ``ROLL`` protocol payload into styled message dictionaries."""
    result_obj = (
        payload.get("Result")
        if isinstance(payload.get("Result"), dict)
        else (payload.get("RollData") if isinstance(payload.get("RollData"), dict) else {})
    )
    sender = str(
        payload.get("Sender")
        or (payload.get("Origin") if isinstance(payload.get("Origin"), str) else "")
        or result_obj.get("Sender")
        or "[none]"
    )
    msg_id = payload.get("MessageID")
    title = str(payload.get("Title") or result_obj.get("Title") or "")
    recipients = [str(r) for r in (payload.get("Recipients") or payload.get("Targets") or [])]
    details = result_obj.get("Details") or payload.get("Details") or []
    invalid_request = bool(result_obj.get("InvalidRequest", False))
    more_results = bool(result_obj.get("MoreResults", False))

    msgs: list[dict[str, Any]] = [
        {"text": f"{sender}: ", "style": "user", "newline": False, "msgid": msg_id}
    ]
    if invalid_request:
        msgs.append({"text": "INVALID REQUEST: ", "style": "error", "newline": False})
    if recipients:
        msgs.append(
            {"text": f"[roll to {','.join(recipients)}] ", "newline": False}
        )
    if title:
        msgs.append({"text": f"{title} ", "style": "rolllabel", "newline": False})

    for item in details:
        if isinstance(item, dict):
            tag = str(item.get("Type") or item.get("type") or "")
            text = str(item.get("Value", item.get("value", "")))
        elif isinstance(item, (list, tuple)) and len(item) >= 2:
            tag = str(item[0])
            text = str(item[1])
        else:
            tag = ""
            text = str(item)

        if tag in ("result", "fail", "success", "separator"):
            msgs.append({"text": f" {text}  ", "style": tag, "newline": False})
            if tag == "result" and more_results:
                msgs.append({"text": " \u231b", "style": "user", "newline": False})
        elif tag == "roll":
            msgs.append({"text": f"({text}) ", "style": tag, "newline": False})
        elif tag == "notice":
            msgs.append({"text": f"[{text}] ", "style": tag, "newline": False})
        elif tag == "error":
            msgs.append({"text": f"[ERROR: {text}] ", "style": tag, "newline": False})
        else:
            seg: dict[str, Any] = {"text": f"{text} ", "newline": False}
            if tag:
                seg["style"] = tag
            msgs.append(seg)

    msgs.append({"text": " ", "newline": True})
    return msgs


try:
    from PySide6.QtCore import QObject, Signal

    QT_AVAILABLE = True
except ImportError:  # pragma: no cover
    QT_AVAILABLE = False


if QT_AVAILABLE:

    class MapService(QObject):
        """Asynchronous PySide6 client adapter for standalone GMA server connections."""

        connection_changed = Signal(bool, dict)
        messages_received = Signal(list)
        userlist_updated = Signal(list)

        def __init__(
            self,
            settings: SettingsStore,
            parent: QObject | None = None,
            version: str = APP_VERSION,
        ) -> None:
            super().__init__(parent)
            self.settings = settings
            self._version = version
            self.server: dict[str, Any] | None = None
            self.username: str = ""
            self.peer: str = ""
            self.userlist: set[str] = set()
            self.targetlist: list[str] | None = None
            self.targeted_mod_list: dict[str, Any] | None = None
            self._initial_setup_done = False

            self.client = GMANetworkClient(self)
            self.client.login_successful.connect(self._on_login_successful)
            self.client.command_received.connect(self.dispatch_command)
            self.client.progress_message.connect(self._on_progress_message)
            self.client.connection_lost.connect(self._on_connection_lost)

        def connected(self) -> bool:
            """Return True when connected and authenticated to a server."""
            return self.client.session.is_ready()

        def connect_server(self, server: dict[str, Any]) -> bool:
            """Initiate connection to ``server`` dictionary from ``SettingsStore``."""
            if self.connected():
                self.disconnect_server()

            self.server = dict(server)
            host = str(server.get("hostname") or "").strip()
            port = int(server.get("port") or 2323)
            if not host:
                self.messages_received.emit(
                    [{"text": "No hostname configured", "style": "comment", "newline": True}]
                )
                return False

            self.userlist = set()
            self.targetlist = None
            self.targeted_mod_list = None
            self._initial_setup_done = False
            self.userlist_updated.emit([])
            self.peer = f"{host}:{port}"

            raw_user = str(server.get("username") or "").strip()
            self.username = raw_user or getpass.getuser()
            b64pw = str(server.get("password") or "")
            password = self.settings.password_decode(b64pw) if b64pw else ""

            self.messages_received.emit(
                [
                    {
                        "text": f"Connecting to {self.peer} as {self.username}",
                        "style": "comment",
                        "newline": True,
                    }
                ]
            )
            client_tag = f"dieroller {self._version}-{GMAMapperVersion}"
            self.client.dial(
                host=host,
                port=port,
                user=self.username,
                password=password,
                client_name=client_tag,
            )
            return True

        def disconnect_server(self) -> None:
            """Disconnect from the active server and save updated settings."""
            self.settings.save(quiet=True)
            was_active = bool(self.client.session.host or self.client.session.is_connected)
            self.client.hangup()
            self.connection_changed.emit(False, self.server or {})
            if was_active:
                self.messages_received.emit(
                    [{"text": "Connection closed", "style": "comment", "newline": True}]
                )

        def _on_login_successful(self) -> None:
            session_user = str(getattr(self.client.session, "username", "") or "")
            if session_user:
                self.username = session_user
            self.client.session.subscribe(["TO", "MARCO", "ROLL", "CONN", "OA", "PS"])

            features: list[str] = []
            if self.settings.allow_colorized_titles():
                features.append("DICE-COLOR-BOXES")
            if self.settings.allow_colorized_labels():
                features.append("DICE-COLOR-LABELS")
            if features:
                self.client.session.allow(features)

            self.connection_changed.emit(True, self.server or {})
            self.messages_received.emit(
                [{"text": "Connected", "style": "comment", "newline": True}]
            )

            sname = str((self.server or {}).get("name") or "") or None
            if self.settings.last_msgid(servername=sname) is not None:
                self.client.session.sync_chat(-50)

        def _on_progress_message(self, msg: str) -> None:
            if "Authentication required" in msg or "denied" in msg.lower():
                self.messages_received.emit(
                    [{"text": msg, "style": "comment", "newline": True}]
                )

        def _on_connection_lost(self, err: str) -> None:
            self.connection_changed.emit(False, self.server or {})
            self.messages_received.emit(
                [
                    {
                        "text": f"Lost connection to server ({err})",
                        "style": "comment",
                        "newline": True,
                    }
                ]
            )

        def roll_dice(
            self,
            expr: str,
            blind: bool = False,
            recipients: list[str] | None = None,
            roll_for: str = "",
        ) -> None:
            """Send a die-roll command ``D`` when connected."""
            if not self.connected() or not expr:
                return
            if blind:
                self.client.session.roll_dice(
                    expr,
                    to_all=False,
                    blind_to_gm=True,
                    targets=self.targetlist or [],
                    for_user=roll_for,
                )
            elif recipients is not None:
                self.client.session.roll_dice(
                    expr,
                    recipients=recipients,
                    to_all=False,
                    targets=self.targetlist or [],
                    for_user=roll_for,
                )
            else:
                self.client.session.roll_dice(
                    expr,
                    to_all=True,
                    targets=self.targetlist or [],
                    for_user=roll_for,
                )

        def send_chat(self, message: str, recipients: list[str] | None = None) -> None:
            """Send a chat message ``TO`` when connected."""
            if not self.connected() or not message:
                return
            if recipients is None:
                self.client.session.chat_message(message, to_all=True)
            else:
                self.client.session.chat_message(
                    message, recipients=recipients, to_all=False
                )

        def _update_last_msgid(self, msgid: Any) -> None:
            if msgid is None:
                return
            try:
                mid_int = int(msgid)
            except (TypeError, ValueError):
                return
            sname = str((self.server or {}).get("name") or "") or None
            cur = self.settings.last_msgid(servername=sname)
            if cur is None or mid_int > cur:
                self.settings.update_msgid(mid_int, servername=sname)

        def dispatch_command(self, cmd: str, payload: dict[str, Any]) -> None:
            """Handle parsed protocol messages from ``GMANetworkClient``."""
            if cmd == "MARCO":
                self.client.session.polo()
                self._initial_setup_done = True
            elif cmd == "CONN":
                self._handle_conn(payload)
            elif cmd == "PS":
                if str(payload.get("Name") or "") == self.username:
                    self.targetlist = list(payload.get("Targets") or [])
                    tmods = payload.get("TargetedModifiers")
                    self.targeted_mod_list = tmods if isinstance(tmods, dict) else {}
            elif cmd == "OA":
                if str(payload.get("ObjID") or "") == f"@{self.username}":
                    attrs = payload.get("NewAttrs") or {}
                    if "Targets" in attrs:
                        self.targetlist = list(attrs["Targets"] or [])
                    if "TargetedModifiers" in attrs and isinstance(attrs["TargetedModifiers"], dict):
                        self.targeted_mod_list = attrs["TargetedModifiers"]
            elif cmd == "TO":
                self._update_last_msgid(payload.get("MessageID"))
                self.messages_received.emit(format_chat_event_messages(payload))
            elif cmd == "ROLL":
                self._update_last_msgid(payload.get("MessageID"))
                dprint(f"ROLL received: {payload}")
                self.messages_received.emit(format_roll_event_messages(payload))

        def _handle_conn(self, payload: dict[str, Any]) -> None:
            peers = payload.get("PeerList") or []
            prev = set(self.userlist)
            current: set[str] = set()
            for peer in peers:
                if isinstance(peer, dict):
                    uname = (
                        self.username
                        if (peer.get("IsMe") and self.username)
                        else str(peer.get("User") or "")
                    )
                else:
                    uname = str(peer or "")
                if uname:
                    current.add(uname)
            self.userlist = current
            self.userlist_updated.emit(sorted(current))

            if not prev:
                self.messages_received.emit(
                    [
                        {
                            "text": f"There are {len(peers)} users connected",
                            "style": "comment",
                            "newline": True,
                        }
                    ]
                )
                return

            msgs: list[dict[str, Any]] = []
            for user in sorted(current - prev):
                msgs.append({"text": f"{user} has joined", "style": "comment", "newline": True})
            for user in sorted(prev - current):
                msgs.append({"text": f"{user} has left", "style": "comment", "newline": True})
            if msgs:
                self.messages_received.emit(msgs)
