"""GMA Mapper network client, login state machine, and command sender.

Ported from bin/gmaproto.tcl.
"""

from __future__ import annotations

import getpass
import json
from typing import Any, Callable

from gma_mapper import GMAMapperVersion
from gma_mapper.core.util import my_arch, my_os, my_platform
from gma_mapper.net.protocol import (
    ALL_MESSAGES,
    MAX_MAX_PROTOCOL,
    MAX_PROTOCOL,
    MIN_PROTOCOL,
    PROTOCOL,
    BatchCollector,
    _attribute_encode,
    _parse_data_packet,
    _protocol_encode,
    auth_response,
    encode_with_batching,
    new_id,
)

MAX_SEND_BUFFER: int = 10_000
MAX_LINE_BUFFER_BYTES: int = 4 * 1024 * 1024  # 4 MiB max partial line buffer
MAX_REDIRECTS: int = 5


class ProtocolSession:
    """Pure-Python state machine for GMA server protocol 400-428 negotiation and messaging."""

    def __init__(
        self,
        send_line_cb: Callable[[str], None] | None = None,
        dispatch_cb: Callable[[str, dict[str, Any]], None] | None = None,
        progress_cb: Callable[[str], None] | None = None,
        notice_cb: Callable[[str], None] | None = None,
        upgrade_cb: Callable[[dict[str, Any]], None] | None = None,
        login_success_cb: Callable[[], None] | None = None,
        redirect_cb: Callable[[str, int, str], None] | None = None,
        begin_progress_cb: Callable[[str, str, int | str], None] | None = None,
        end_progress_cb: Callable[[str], None] | None = None,
        debug_cb: Callable[[str], None] | None = None,
    ) -> None:
        self.send_line_cb = send_line_cb
        self.dispatch_cb = dispatch_cb
        self.progress_cb = progress_cb
        self.notice_cb = notice_cb
        self.upgrade_cb = upgrade_cb
        self.login_success_cb = login_success_cb
        self.redirect_cb = redirect_cb
        self.begin_progress_cb = begin_progress_cb
        self.end_progress_cb = end_progress_cb
        self.debug_cb = debug_cb

        self.protocol: int = PROTOCOL
        self.server_version: str = ""
        self.host: str = ""
        self.port: int = 2323
        self.username: str = ""
        self.password: str = ""
        self.client_name: str = f"gma-mapper {GMAMapperVersion}"

        self.pending_login: bool = True
        self.initial_command_received: bool = False
        self.is_connected: bool = False

        self.send_buffer: list[str] = []
        self.progress_stack: list[str] = []
        self.subscribed_messages: list[str] = list(ALL_MESSAGES)
        self.forbidden_urls: set[str] = set()
        self._batch_collector = BatchCollector()
        self._update_ready: dict[str, Any] = {}
        self._redirect_count: int = 0

    def reset_for_connection(
        self,
        host: str,
        port: int,
        username: str = "",
        password: str = "",
        client_name: str = "",
    ) -> None:
        """Reset session state for a new server connection."""
        self.host = host.strip()
        self.port = int(port)
        self.username = username
        self.password = password
        if client_name:
            self.client_name = client_name
        self.pending_login = True
        self.initial_command_received = False
        self.is_connected = True
        self._batch_collector.clear()
        self._update_ready = {}
        self._redirect_count = 0

    def stop_all_progress_meters(self) -> None:
        if self.end_progress_cb:
            for op_id in self.progress_stack:
                self.end_progress_cb(op_id)
        self.progress_stack.clear()

    def is_enabled(self) -> bool:
        return bool(self.host)

    def is_ready(self) -> bool:
        return self.is_connected and not self.pending_login

    def _debug(self, msg: str) -> None:
        if self.debug_cb:
            self.debug_cb(msg)

    def _raw_send(self, message: str) -> None:
        # Sanitize embedded CR/LF to prevent protocol command injection
        clean_msg = message.replace("\r", " ").replace("\n", " ")
        if not self.is_enabled():
            self._debug(f'server not configured; not sending "{clean_msg}"')
            return
        self._debug(f"-> {clean_msg}")
        if len(self.send_buffer) >= MAX_SEND_BUFFER:
            del self.send_buffer[: len(self.send_buffer) - MAX_SEND_BUFFER + 1]
        self.send_buffer.append(clean_msg)
        self.flush_send_buffer()

    def flush_send_buffer(self) -> None:
        if not self.is_connected or not self.send_line_cb or not self.send_buffer:
            return
        pending = self.send_buffer
        self.send_buffer = []
        saved: list[str] = []
        for msg in pending:
            if self.pending_login and msg != "POLO" and not msg.startswith("AUTH "):
                self._debug(f"Holding off on {msg} until login is complete")
                saved.append(msg)
            else:
                self.send_line_cb(msg)
        if saved:
            self.send_buffer = saved + self.send_buffer

    def send_command(self, command: str, dargs: dict[str, Any] | None = None) -> None:
        """Encode `command` with `dargs` (splitting into `BATCH` if needed) and queue for send."""
        packets = encode_with_batching(command, dargs or {})
        for pkt in packets:
            self._raw_send(pkt)

    def receive_line(self, raw_line: str) -> None:
        """Process a single newline-delimited line received from the server."""
        line = raw_line.rstrip("\r\n")
        self._debug(f"<- {line}")

        if self.pending_login and not self.initial_command_received:
            if not line.startswith("PROTOCOL "):
                raise ValueError(
                    "Server failed to identify its protocol. It is either really old or does not conform to the GMA server specification."
                )
            parts = line.split()
            if len(parts) != 2:
                raise ValueError("Server PROTOCOL message is malformed; giving up")
            ver = int(parts[1])
            self.protocol = ver
            if ver < MIN_PROTOCOL:
                raise ValueError(
                    f"Server protocol version {ver} is too old. Minimum supported is {MIN_PROTOCOL}."
                )
            self.initial_command_received = True
            return

        cmd, params = _parse_data_packet(line)
        if cmd == "NIL":
            return
        if cmd == "BATCH":
            reassembled = self._batch_collector.process_batch(params)
            if reassembled is None:
                return
            cmd, params = reassembled

        if self.pending_login:
            self._handle_login_packet(cmd, params)
        else:
            self._dispatch_packet(cmd, params)

    def _handle_login_packet(self, cmd: str, params: Any) -> None:
        if cmd == "//":
            msg = str(params)[2:].strip()
            if msg.lower().startswith("notice:"):
                if self.notice_cb:
                    self.notice_cb(msg[7:].strip())
        elif cmd in ("AC", "DSM", "Y2"):
            if self.dispatch_cb:
                self.dispatch_cb(cmd, params)
        elif cmd == "WORLD":
            if self.dispatch_cb:
                self.dispatch_cb("WORLD", params)
        elif cmd == "MARCO":
            self.polo()
        elif cmd == "REDIRECT":
            self._apply_redirect(params)
        elif cmd == "DENIED":
            self._apply_denied(params)
        elif cmd == "GRANTED":
            self.username = params.get("User", self.username)
            self._debug(f"Access granted for {self.username}")
        elif cmd == "OK":
            if self.progress_cb:
                self.progress_cb("Server greeting complete")
            self.protocol = int(params.get("Protocol", 0))
            if self.protocol == 0:
                raise ValueError(
                    "This does not appear to be a server which speaks any protocol we understand."
                )
            if self.protocol < MIN_PROTOCOL:
                raise ValueError(
                    f"The server speaks a protocol too old for me to understand ({self.protocol})"
                )
            if self.protocol > MAX_MAX_PROTOCOL:
                raise ValueError(
                    f"The server speaks a protocol too new for me to understand at all ({self.protocol})"
                )
            self.server_version = params.get("ServerVersion", "")
            if self.progress_cb:
                self.progress_cb(
                    f"Connected to server version {self.server_version} with protocol {self.protocol}"
                )
            challenge: bytes = params.get("Challenge", b"")
            iterations: int = int(params.get("Iterations", 0))
            if challenge:
                if not self.password:
                    raise PermissionError("Authentication required")
                user = self.username or getpass.getuser()
                self.username = user
                resp = auth_response(challenge, self.password, iterations)
                self.send_command(
                    "AUTH",
                    {
                        "Response": resp,
                        "User": self.username,
                        "Client": self.client_name,
                        "Platform": my_platform(),
                    },
                )
        elif cmd == "UPDATES":
            for pkg in params.get("Packages", []):
                if pkg.get("Name") != "mapper":
                    continue
                for inst in pkg.get("Instances", []):
                    inst_os = inst.get("OS", "")
                    inst_arch = inst.get("Arch", "")
                    if inst_os in ("", my_os()) and inst_arch in ("", my_arch()):
                        if self._update_ready:
                            if (inst_os and not self._update_ready.get("OS")) or (
                                inst_arch and not self._update_ready.get("Arch")
                            ):
                                self._update_ready = inst
                        else:
                            self._update_ready = inst
        elif cmd == "READY":
            self.pending_login = False
            self._redirect_count = 0
            self.watch_operation("Syncing game state")
            if self.progress_cb:
                self.progress_cb("Server login successful.")
            self.flush_send_buffer()
            if self._update_ready and self.upgrade_cb:
                self.upgrade_cb(self._update_ready)
            if self.login_success_cb:
                self.login_success_cb()

    def _apply_redirect(self, params: Any) -> None:
        newhost = str(params.get("Host", "")).strip()
        newport = int(params.get("Port", 2323))
        reason = str(params.get("Reason", ""))
        if not newhost or not (1 <= newport <= 65535):
            raise ValueError(f"Invalid REDIRECT target '{newhost}:{newport}'")
        self._redirect_count += 1
        if self._redirect_count > MAX_REDIRECTS:
            raise RuntimeError(f"Exceeded maximum redirects ({MAX_REDIRECTS})")
        self.host = newhost
        self.port = newport
        self.pending_login = True
        self.initial_command_received = False
        self.send_buffer.clear()
        self.stop_all_progress_meters()
        if self.redirect_cb:
            self.redirect_cb(newhost, newport, reason)

    def _apply_denied(self, params: Any) -> None:
        reason = params.get("Reason", "")
        if self.progress_cb:
            self.progress_cb("Server denied access")
        raise PermissionError(f"Server DENIED access: {reason}")

    def _dispatch_packet(self, cmd: str, params: Any) -> None:
        if cmd in ("//", "ERROR", "UNDEFINED"):
            return
        if cmd == "DENIED":
            self._apply_denied(params)
            return
        if cmd == "REDIRECT":
            self._apply_redirect(params)
            return
        if cmd == "ECHO" and self.progress_stack:
            echo_id = params.get("s", "")
            if echo_id in self.progress_stack:
                self.progress_stack.remove(echo_id)
                if self.end_progress_cb:
                    self.end_progress_cb(echo_id)
        if self.dispatch_cb:
            self.dispatch_cb(cmd, params)

    # ------------------------------------------------------------------
    # High-level client commands matching ::gmaproto::*
    # ------------------------------------------------------------------
    def watch_operation(self, description: str) -> str:
        op_id = new_id()
        self.progress_stack.append(op_id)
        self.send_command("ECHO", {"s": op_id})
        if self.begin_progress_cb:
            self.begin_progress_cb(op_id, description, "*")
        return op_id

    def adjust_view(self, x: float, y: float, grid_label: str = "") -> None:
        self.send_command("AV", {"Grid": grid_label, "XView": x, "YView": y})

    def character_name(self, names: list[str], not_playing: bool = False) -> None:
        self.send_command("AKA", {"Names": names, "NotPlaying": not_playing})

    def chat_message(
        self,
        message: str,
        sender: str = "",
        recipients: list[str] | None = None,
        to_all: bool = True,
        to_gm: bool = False,
        markup: bool = False,
        pinned: bool = False,
    ) -> None:
        self.send_command(
            "TO",
            {
                "Recipients": recipients or [],
                "ToAll": to_all,
                "ToGM": to_gm,
                "Text": message,
                "Markup": markup,
                "Pin": pinned,
            },
        )

    def hit_point_request_d(self, d: dict[str, Any]) -> None:
        self.send_command("HPREQ", d)

    def timer_request(
        self,
        req_id: str,
        description: str,
        expires: str,
        is_running: bool = True,
        targets: list[str] | None = None,
        to_all: bool = True,
    ) -> None:
        self.send_command(
            "TMRQ",
            {
                "RequestID": req_id,
                "Description": description,
                "Expires": expires,
                "Targets": targets or [],
                "IsRunning": is_running,
                "ShowToAll": to_all,
            },
        )

    def clear(self, obj_id: str) -> None:
        self.send_command("CLR", {"ObjID": obj_id})

    def clear_chat(self, silent: bool, target: int) -> None:
        self.send_command("CC", {"DoSilently": silent, "Target": target})

    def clear_chat_list(self, silent: bool, targets: list[int]) -> None:
        if targets:
            self.send_command("CC", {"DoSilently": silent, "TargetMessages": targets})

    def clear_from(self, server_id: str) -> None:
        self.send_command("CLR@", {"File": server_id})

    def combat_mode(self, enabled: bool) -> None:
        self.send_command("CO", {"Enabled": enabled})

    def comment(self, text: str) -> None:
        self._raw_send(f"// {text}")

    def define_dice_presets(
        self,
        plist: list[dict[str, Any]],
        append_mode: bool = False,
        for_user: str = "",
        globals_only: bool = False,
    ) -> None:
        payload: dict[str, Any] = {"Presets": plist}
        if globals_only:
            payload["Global"] = True
        else:
            payload["For"] = for_user
        self.send_command("DD+" if append_mode else "DD", payload)

    def filter_dice_presets(
        self, regex: str, globals_only: bool = False, for_user: str = ""
    ) -> None:
        self.send_command("DD/", {"Filter": regex, "Global": globals_only, "For": for_user})

    def filter_audio(self, regex: str, keep_matching: bool = False) -> None:
        self.send_command("AA/", {"Filter": regex, "KeepMatching": keep_matching})

    def filter_images(self, regex: str, keep_matching: bool = False) -> None:
        self.send_command("AI/", {"Filter": regex, "KeepMatching": keep_matching})

    def load_from(self, server_id: str, cache_only: bool = False, merge: bool = False) -> None:
        self.send_command("L", {"File": server_id, "CacheOnly": cache_only, "Merge": merge})

    def mark(self, x: float, y: float) -> None:
        self.send_command("MARK", {"X": x, "Y": y})

    def query_dice_presets(self, for_user: str = "", globals_only: bool = False) -> None:
        self.send_command("DR", {"For": for_user, "Global": globals_only})

    def define_dice_delegates(self, for_user: str, delegate_list: list[str]) -> None:
        self.send_command("DDD", {"For": for_user, "Delegates": delegate_list})

    def add_audio(self, name: str, fmt: str, file: str, is_local: bool = False) -> None:
        self.send_command(
            "AA", {"Name": name, "Format": fmt, "File": file, "IsLocalFile": is_local}
        )

    def add_image(
        self,
        name: str,
        sizes: list[dict[str, Any]],
        frames: int = 0,
        speed: int = 0,
        loops: int = 0,
    ) -> None:
        self.send_command(
            "AI",
            {
                "Name": name,
                "Sizes": sizes,
                "Animation": {"Frames": frames, "FrameSpeed": speed, "Loops": loops},
            },
        )

    def query_image(self, name: str, size: float) -> None:
        key = f"{name}:{size:.2f}"
        if key in self.forbidden_urls:
            return
        self.send_command("AI?", {"Name": name, "Sizes": [{"Zoom": size}]})

    def query_audio(self, name: str) -> None:
        if name in self.forbidden_urls:
            return
        self.send_command("AA?", {"Name": name})

    def query_peers(self) -> None:
        self.send_command("/CONN")

    def place_someone_d(self, d: dict[str, Any]) -> None:
        self.send_command("PS", d)

    def polo(self) -> None:
        self.send_command("POLO")

    def roll_dice(
        self,
        spec: str,
        recipients: list[str] | None = None,
        to_all: bool = True,
        blind_to_gm: bool = False,
        rid: str = "",
        targets: list[str] | None = None,
        roll_type: str = "",
        for_user: str = "",
    ) -> None:
        self.send_command(
            "D",
            {
                "Recipients": recipients or [],
                "ToAll": to_all,
                "ToGM": blind_to_gm,
                "RollSpec": spec,
                "RequestID": rid,
                "Targets": targets or [],
                "Type": roll_type,
                "For": for_user,
            },
        )

    def sync_chat(self, target: int) -> None:
        self.send_command("SYNC-CHAT", {"Target": target})

    def sync(self) -> None:
        self.send_command("SYNC")

    def toolbar(self, enabled: bool) -> None:
        self.send_command("TB", {"Enabled": enabled})

    def update_clock(
        self, absolute: int | float, relative: int | float, running: bool
    ) -> None:
        self.send_command(
            "CS",
            {
                "Absolute": int(round(absolute)),
                "Relative": int(round(relative)),
                "Running": running,
            },
        )

    def update_obj_attributes(self, obj_id: str, kvdict: dict[str, Any]) -> None:
        new_attrs = {k: _attribute_encode(k, v) for k, v in kvdict.items()}
        payload = json.dumps(
            {"ObjID": obj_id, "NewAttrs": new_attrs},
            separators=(",", ":"),
            allow_nan=False,
        )
        for pkt in encode_with_batching("OA", {"ObjID": obj_id, "NewAttrs": new_attrs}):
            if pkt.startswith("BATCH "):
                self._raw_send(pkt)
            else:
                self._raw_send(f"OA {payload}")
                break

    def add_obj_attributes(self, obj_id: str, attr: str, vs: list[str]) -> None:
        self.send_command("OA+", {"ObjID": obj_id, "AttrName": attr, "Values": vs})

    def remove_obj_attributes(self, obj_id: str, attr: str, vs: list[str]) -> None:
        self.send_command("OA-", {"ObjID": obj_id, "AttrName": attr, "Values": vs})

    def update_status_marker(
        self,
        condition: str,
        shape: str,
        color: str,
        desc: str = "",
        transparent: bool = False,
    ) -> None:
        self.send_command(
            "DSM",
            {
                "Condition": condition,
                "Shape": shape,
                "Color": color,
                "Description": desc,
                "Transparent": transparent,
            },
        )

    def subscribe(self, msg_list: list[str] | None = None) -> None:
        if not msg_list:
            self.subscribed_messages = list(ALL_MESSAGES)
            self.send_command("ACCEPT")
        else:
            self.subscribed_messages = list(msg_list)
            self.send_command("ACCEPT", {"Messages": self.subscribed_messages})

    def allow(self, features: list[str]) -> None:
        self.send_command("ALLOW", {"Features": features})

    def ls(self, obj_type: str, datadict: dict[str, Any]) -> None:
        self.send_command(f"LS-{obj_type}", datadict)

    def update_progress(
        self, op_id: str, title: str, value: int, max_val: int | str, done: bool
    ) -> str:
        if op_id == "*":
            op_id = new_id()
        mv = 0 if max_val == "*" else int(max_val)
        self.send_command(
            "PROGRESS",
            {
                "OperationID": op_id,
                "Title": title,
                "Value": value,
                "MaxValue": mv,
                "IsDone": done,
            },
        )
        return op_id


try:
    from PySide6.QtCore import QObject, QTimer, Signal
    from PySide6.QtNetwork import QAbstractSocket, QNetworkProxy, QTcpSocket

    class GMANetworkClient(QObject):
        """Qt asynchronous TCP client wrapping `ProtocolSession`."""

        command_received = Signal(str, dict)
        login_successful = Signal()
        progress_message = Signal(str)
        server_notice = Signal(str)
        upgrade_available = Signal(dict)
        connection_lost = Signal(str)

        def __init__(self, parent: QObject | None = None) -> None:
            super().__init__(parent)
            self._socket: QTcpSocket | None = None
            self._read_buffer: bytearray = bytearray()
            self._redial_tries: int = 0
            self._suppress_redial: bool = False
            self._redial_timer = QTimer(self)
            self._redial_timer.setSingleShot(True)
            self._redial_timer.timeout.connect(self._on_redial_timeout)

            self.proxy_host: str = ""
            self.proxy_port: int = 0
            self.proxy_user: str = ""
            self.proxy_pass: str = ""

            self.session = ProtocolSession(
                send_line_cb=self._write_line,
                dispatch_cb=lambda cmd, params: self.command_received.emit(cmd, params),
                progress_cb=lambda msg: self.progress_message.emit(msg),
                notice_cb=lambda msg: self.server_notice.emit(msg),
                upgrade_cb=lambda inst: self.upgrade_available.emit(inst),
                login_success_cb=lambda: self.login_successful.emit(),
                redirect_cb=self._on_redirect,
            )

        def dial(
            self,
            host: str,
            port: int,
            user: str = "",
            password: str = "",
            proxy: str = "",
            proxy_port: int = 0,
            proxy_user: str = "",
            proxy_pass: str = "",
            client_name: str = "",
        ) -> None:
            self.proxy_host = proxy
            self.proxy_port = proxy_port
            self.proxy_user = proxy_user
            self.proxy_pass = proxy_pass
            self._suppress_redial = False
            self.session.reset_for_connection(host, port, user, password, client_name)
            self.redial()

        def hangup(self) -> None:
            self._redial_timer.stop()
            self._suppress_redial = True
            self.session.host = ""
            self.session.is_connected = False
            self.session.stop_all_progress_meters()
            if self._socket is not None:
                self._socket.disconnectFromHost()
                self._socket.deleteLater()
                self._socket = None

        def redial(self) -> None:
            self._read_buffer.clear()
            if self._socket is not None:
                self._socket.abort()
                self._socket.deleteLater()
                self._socket = None

            if not self.session.host:
                return

            sock = QTcpSocket(self)
            if self.proxy_host and self.proxy_port > 0:
                net_proxy = QNetworkProxy(
                    QNetworkProxy.ProxyType.Socks5Proxy,
                    self.proxy_host,
                    self.proxy_port,
                    self.proxy_user,
                    self.proxy_pass,
                )
                sock.setProxy(net_proxy)

            sock.connected.connect(self._on_connected)
            sock.readyRead.connect(self._on_ready_read)
            sock.disconnected.connect(self._on_disconnected)
            sock.errorOccurred.connect(self._on_error)
            self._socket = sock
            sock.connectToHost(self.session.host, self.session.port)

        def _write_line(self, line: str) -> None:
            if self._socket and self._socket.state() == QAbstractSocket.SocketState.ConnectedState:
                self._socket.write((line + "\n").encode("utf-8"))
                self._socket.flush()

        def _on_connected(self) -> None:
            self._redial_tries = 0
            self.session.is_connected = True
            self.session.pending_login = True
            self.session.initial_command_received = False

        def _on_ready_read(self) -> None:
            if not self._socket:
                return
            chunk = bytes(self._socket.readAll())
            if not chunk:
                return
            self._read_buffer.extend(chunk)
            if b"\n" not in self._read_buffer:
                if len(self._read_buffer) > MAX_LINE_BUFFER_BYTES:
                    self._read_buffer.clear()
                    self.progress_message.emit(
                        "Disconnected: incoming protocol line exceeded maximum buffer size."
                    )
                    self.hangup()
                return

            parts = self._read_buffer.split(b"\n")
            remainder = parts.pop()
            if len(remainder) > MAX_LINE_BUFFER_BYTES:
                self._read_buffer.clear()
                self.progress_message.emit(
                    "Disconnected: incoming protocol line exceeded maximum buffer size."
                )
                self.hangup()
                return
            self._read_buffer = bytearray(remainder)

            for line_bytes in parts:
                line_str = bytes(line_bytes).decode("utf-8", errors="replace")
                try:
                    self.session.receive_line(line_str)
                except PermissionError as exc:
                    self._suppress_redial = True
                    self.progress_message.emit(str(exc))
                    self.hangup()
                    return
                except Exception as exc:
                    self.progress_message.emit(str(exc))

        def _on_disconnected(self) -> None:
            self.session.is_connected = False
            self.session.pending_login = True
            self.session.stop_all_progress_meters()
            if self.session.host and not self._suppress_redial:
                self._schedule_redial()

        def _on_error(self, _err: QAbstractSocket.SocketError) -> None:
            if self._socket:
                self.connection_lost.emit(self._socket.errorString())
            if (
                self.session.host
                and not self._suppress_redial
                and not self._redial_timer.isActive()
            ):
                self._schedule_redial()

        def _schedule_redial(self) -> None:
            self._redial_tries += 1
            delay_ms = min(self._redial_tries * 1000, 10000)
            self._redial_timer.start(delay_ms)

        def _on_redial_timeout(self) -> None:
            self.redial()

        def _on_redirect(self, newhost: str, newport: int, _reason: str) -> None:
            self.redial()

except ImportError:
    GMANetworkClient = None  # type: ignore[assignment,misc]

