"""Standalone headless CLI die roller ported from ``gma/extras/dieroller/roll.py``."""

from __future__ import annotations

import argparse
import base64
import getpass
import json
from pathlib import Path
import socket
import sys
import uuid
from typing import Any, Sequence

from gma_mapper.net.client import ProtocolSession

DEFAULT_SETTINGS_FILE = Path.home() / ".dieroller" / "settings.json"
DEFAULT_MAPPER_CONF_FILE = Path.home() / ".gma" / "mapper" / "mapper.conf"


def load_dieroller_settings(settings_file: str | Path) -> dict[str, Any]:
    """Load ``~/.dieroller/settings.json`` and normalize ``servers`` dict."""
    data = json.loads(Path(settings_file).read_text(encoding="utf-8"))
    if "servers" in data:
        if not isinstance(data["servers"], dict):
            raise TypeError(f"Corrupt 'servers' entry in {settings_file}")
    else:
        data["servers"] = {}
    return data


def load_mapper_conf(conf_file: str | Path) -> dict[str, str]:
    """Load key=value legacy ``mapper.conf`` settings."""
    data: dict[str, str] = {}
    for line in Path(conf_file).read_text(encoding="utf-8").splitlines():
        if "=" in line:
            key, val = line.split("=", 1)
            data[key.strip()] = val.strip()
    return data


def format_cli_roll_output(payload: dict[str, Any]) -> str:
    """Format a server ``ROLL`` payload into a single console line."""
    result_obj = (
        payload.get("Result")
        if isinstance(payload.get("Result"), dict)
        else (payload.get("RollData") if isinstance(payload.get("RollData"), dict) else {})
    )
    sender = str(
        payload.get("Sender")
        or (payload.get("Origin") if isinstance(payload.get("Origin"), str) else "")
        or "Player"
    )
    title = str(payload.get("Title") or result_obj.get("Title") or "")
    details = result_obj.get("Details") or payload.get("Details") or []

    parts = [f"{sender}: "]
    if title:
        parts.append(f"{title} ")
    for item in details:
        if isinstance(item, dict):
            tag = str(item.get("Type") or "")
            text = str(item.get("Value") or "")
        elif isinstance(item, (list, tuple)) and len(item) >= 2:
            tag = str(item[0])
            text = str(item[1])
        else:
            tag = ""
            text = str(item)
        if tag == "roll":
            parts.append(f"({text}) ")
        else:
            parts.append(f"{text} ")
    return "".join(parts).strip()


def parse_roll_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    """Parse CLI arguments for headless ``py-roll``."""
    parser = argparse.ArgumentParser(prog="py-roll")
    parser.add_argument("-b", "--blind", action="store_true", help="Make a blind roll")

    group = parser.add_mutually_exclusive_group()
    group.add_argument(
        "-c",
        "--config",
        metavar="FILE",
        help="Load settings from FILE (cannot combine with --gma-config)",
    )
    group.add_argument(
        "-g",
        "--gma-config",
        action="store_true",
        help="Load server settings from ~/.gma/mapper/mapper.conf",
    )

    parser.add_argument(
        "-l",
        "--list-servers",
        action="store_true",
        help="List configured servers and exit",
    )
    parser.add_argument("-s", "--server-name", metavar="NAME", help="Configured server name")
    parser.add_argument("-H", "--hostname", help="Override server hostname")
    parser.add_argument("-p", "--port", type=int, help="Override server port")
    parser.add_argument("-u", "--user", help="Override login username")
    parser.add_argument("-d", "--debug", action="store_true", help="Enable debug output")
    parser.add_argument("dieroll", nargs="*", metavar="EXPR", help="Die-roll expression")
    return parser.parse_args(argv)


def _resolve_server_config(args: argparse.Namespace) -> tuple[dict[str, Any], str]:
    settings_path = Path(args.config) if args.config else DEFAULT_SETTINGS_FILE
    if args.gma_config:
        server: dict[str, Any] = dict(load_mapper_conf(DEFAULT_MAPPER_CONF_FILE))
        if "host" in server and "hostname" not in server:
            server["hostname"] = server["host"]
        return (server, str(server.get("password") or "") or getpass.getpass())

    settings = load_dieroller_settings(settings_path)
    servers: dict[str, Any] = settings["servers"]
    if args.list_servers:
        return ({"__list__": sorted(servers.keys())}, "")

    server_name = args.server_name or settings.get("default_server")
    if server_name is None:
        if len(servers) == 1:
            server_name = next(iter(servers))
        else:
            raise ValueError(
                "Multiple servers and no default_server defined. Rerun with -s option"
            )
    if server_name not in servers:
        raise ValueError(f'Unknown server "{server_name}"')
    server = dict(servers[server_name])
    b64pw = str(server.get("password") or "")
    password = (
        base64.b64decode(b64pw.encode("ascii")).decode("utf-8")
        if b64pw
        else getpass.getpass()
    )
    return (server, password)


def _execute_socket_roll(
    host: str,
    port: int,
    username: str,
    password: str,
    expr: str,
    blind: bool,
) -> int:
    roll_id = str(uuid.uuid1())
    done = False
    exit_code = 0

    with socket.create_connection((host, port), timeout=15.0) as sock:
        def _send_line(line: str) -> None:
            sock.sendall((line + "\n").encode("utf-8"))

        def _dispatch(cmd: str, payload: dict[str, Any]) -> None:
            nonlocal done, exit_code
            if cmd == "MARCO":
                session.polo()
            elif cmd == "ROLL":
                if payload.get("RequestID") == roll_id:
                    print(format_cli_roll_output(payload))
                    result_obj = payload.get("Result") if isinstance(payload.get("Result"), dict) else {}
                    if not bool(result_obj.get("MoreResults", False)):
                        done = True
            elif cmd == "TO" and payload.get("Sender") == username:
                print(f"// {payload.get('Text', '')}")
                exit_code = 1
                done = True

        def _on_login() -> None:
            session.subscribe(["TO", "ROLL", "MARCO"])
            session.roll_dice(
                expr,
                to_all=not blind,
                blind_to_gm=blind,
                rid=roll_id,
            )

        session = ProtocolSession(
            send_line_cb=_send_line,
            dispatch_cb=_dispatch,
            login_success_cb=_on_login,
        )
        session.reset_for_connection(host, port, username, password, client_name="dieroller")
        session.is_connected = True
        session.pending_login = True

        buf = bytearray()
        while not done:
            chunk = sock.recv(4096)
            if not chunk:
                break
            buf.extend(chunk)
            while b"\n" in buf:
                line_bytes, rest = buf.split(b"\n", 1)
                buf = bytearray(rest)
                session.receive_line(bytes(line_bytes).decode("utf-8", errors="replace"))
    return exit_code


def main(argv: Sequence[str] | None = None) -> int:
    """Run headless ``py-roll`` CLI die roller."""
    args = parse_roll_args(argv)
    try:
        server, password = _resolve_server_config(args)
    except (OSError, ValueError, TypeError) as exc:
        print(str(exc), file=sys.stderr)
        return 1

    if "__list__" in server:
        names = server["__list__"]
        if not names:
            print("No servers defined.", file=sys.stderr)
            return 1
        for name in names:
            print(name)
        return 0

    if not args.dieroll:
        print("Die roll expression required", file=sys.stderr)
        return 1

    if args.hostname:
        server["hostname"] = args.hostname
    if args.port:
        server["port"] = args.port
    if args.user:
        server["username"] = args.user

    for req_key in ("hostname", "port", "username"):
        if not server.get(req_key):
            print(f"{req_key} not defined for server", file=sys.stderr)
            return 1

    if args.debug:
        print(server, file=sys.stderr)

    return _execute_socket_roll(
        host=str(server["hostname"]),
        port=int(server["port"]),
        username=str(server["username"]),
        password=password,
        expr=" ".join(args.dieroll),
        blind=bool(args.blind),
    )


if __name__ == "__main__":
    raise SystemExit(main())
