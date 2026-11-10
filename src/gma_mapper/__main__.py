"""CLI entry point for ``gma-mapper`` accepting all legacy ``bin/mapper.tcl`` and ``wish`` options."""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Sequence

from gma_mapper import (
    GMAMapperVersion,
    GMAMapperFileFormat,
    GMAMapperDiceFileFormat,
    GMAMapperProtocol,
    GMAMapperPreferencesVersion,
)
from gma_mapper.core.profile import (
    default_preferences,
    default_preferences_path,
    load as load_preferences,
    find_server_index,
    empty_server_profile,
)


@dataclass
class MapperCLIOptions:
    """Parsed command-line options compatible with ``bin/mapper.tcl`` and ``gma`` launcher."""

    host: str | None = None
    port: int | None = None
    user: str | None = None
    password: str | None = None
    profile: str | None = None
    config_path: str | None = None
    dark: bool = False
    preload: bool = False
    no_animate: bool = False
    button_size: str | None = None
    curl_url_base: str | None = None
    scp_dest: str | None = None
    scp_server: str | None = None
    geometry: str | None = None
    display: str | None = None
    chat_Transcript: str | None = None
    extra_args: list[str] = field(default_factory=list)


def normalize_legacy_argv(argv: Sequence[str]) -> list[str]:
    """Normalize single-dash legacy Tcl/Tk & ``wish`` options (`-geometry`, `-display`, `--`) for ``argparse``."""
    single_dash_long = {
        "-geometry": "--geometry",
        "-display": "--display",
        "-host": "--host",
        "-port": "--port",
        "-user": "--user",
        "-password": "--password",
        "-profile": "--profile",
        "-dark": "--dark",
        "-preload": "--preload",
        "-button-size": "--button-size",
        "-curl-url-base": "--curl-url-base",
        "-scp-dest": "--scp-dest",
        "-scp-server": "--scp-server",
    }
    normalized: list[str] = []
    for arg in argv:
        if arg == "--":
            # Legacy wish scripts receive `--` before script arguments; skip it so flags after `--` parse normally
            continue
        normalized.append(single_dash_long.get(arg, arg))
    return normalized


def parse_cli_args(argv: Sequence[str] | None = None) -> MapperCLIOptions:
    """Parse CLI arguments into a :class:`MapperCLIOptions` instance."""
    if argv is None:
        argv = sys.argv[1:]
    norm = normalize_legacy_argv(argv)

    parser = argparse.ArgumentParser(
        prog="gma-mapper",
        description=f"GMA Mapper {GMAMapperVersion} (Protocol {GMAMapperProtocol})",
        add_help=False,
    )
    parser.add_argument("--help", "-?", action="help", help="Show this help message and exit")
    parser.add_argument(
        "--version",
        "-v",
        action="version",
        version=(
            f"gma-mapper {GMAMapperVersion} "
            f"(file={GMAMapperFileFormat}, dice={GMAMapperDiceFileFormat}, "
            f"proto={GMAMapperProtocol}, prefs={GMAMapperPreferencesVersion})"
        ),
    )
    parser.add_argument("-h", "--host", dest="host", help="Server hostname or IP")
    parser.add_argument("-p", "--port", dest="port", type=int, help="Server TCP port")
    parser.add_argument("-u", "--user", dest="user", help="Login username")
    parser.add_argument("-P", "--password", dest="password", help="Login password")
    parser.add_argument("--profile", dest="profile", help="Server profile name")
    parser.add_argument("-f", "--config", dest="config_path", help="Path to preferences.json")
    parser.add_argument("--dark", action="store_true", help="Enable dark UI mode")
    parser.add_argument("--preload", action="store_true", help="Preload map/image assets")
    parser.add_argument("--no-animate", action="store_true", help="Disable animated tiles")
    parser.add_argument(
        "--button-size",
        dest="button_size",
        help='Toolbar button size ("small", "medium", "large", or "text")',
    )
    parser.add_argument("--curl-url-base", dest="curl_url_base", help="Base URL for asset downloads")
    parser.add_argument("--scp-dest", dest="scp_dest", help="SCP destination path for GM uploads")
    parser.add_argument("--scp-server", dest="scp_server", help="SCP server host for GM uploads")
    parser.add_argument("--geometry", dest="geometry", help="Initial window geometry (WxH+X+Y)")
    parser.add_argument("--display", dest="display", help="X11 display name (ignored on Windows/macOS)")
    parser.add_argument("--chat-log", dest="chat_transcript", help="Chat transcript output file")

    ns, extra = parser.parse_known_args(norm)
    return MapperCLIOptions(
        host=ns.host,
        port=ns.port,
        user=ns.user,
        password=ns.password,
        profile=ns.profile,
        config_path=ns.config_path,
        dark=bool(ns.dark),
        preload=bool(ns.preload),
        no_animate=bool(ns.no_animate),
        button_size=ns.button_size,
        curl_url_base=ns.curl_url_base,
        scp_dest=ns.scp_dest,
        scp_server=ns.scp_server,
        geometry=ns.geometry,
        display=ns.display,
        chat_Transcript=ns.chat_transcript,
        extra_args=extra,
    )


def apply_cli_overrides(prefs: dict, opts: MapperCLIOptions) -> dict:
    """Apply CLI flag overrides to loaded preferences dictionary without mutating disk until saved."""
    if opts.dark:
        prefs["dark"] = True
    if opts.no_animate:
        prefs["animate"] = False
    if opts.button_size is not None:
        from gma_mapper.ui.icons import normalize_button_size

        raw_bsize = str(opts.button_size).strip().lower()
        if raw_bsize in ("text", "strings", "labels"):
            prefs["toolbar_text"] = True
        else:
            prefs["button_size"] = normalize_button_size(opts.button_size)

    profiles = prefs.setdefault("profiles", [empty_server_profile("offline")])
    target_name = opts.profile
    if not target_name and opts.host:
        for prof in profiles:
            if prof.get("host") == opts.host and (opts.port is None or int(prof.get("port", 0) or 0) == opts.port):
                target_name = str(prof.get("name", ""))
                break
    if not target_name:
        target_name = (
            prefs.get("current_profile")
            or prefs.get("current_server")
            or profiles[0].get("name", "offline")
        )
    idx = find_server_index(prefs, target_name)
    if idx < 0:
        new_srv = empty_server_profile(target_name)
        profiles.append(new_srv)
        idx = len(profiles) - 1
    prefs["current_profile"] = target_name
    prefs["current_server"] = target_name

    srv = profiles[idx]
    if opts.host is not None:
        srv["host"] = opts.host
    if opts.port is not None:
        srv["port"] = opts.port
    if opts.user is not None:
        srv["username"] = opts.user
        srv["user"] = opts.user
    if opts.password is not None:
        srv["password"] = opts.password
        srv["pass"] = opts.password
    if opts.curl_url_base is not None:
        srv["curl_server"] = opts.curl_url_base
        srv["curl_url_base"] = opts.curl_url_base
    if opts.scp_dest is not None:
        srv["scp_dest"] = opts.scp_dest
    if opts.scp_server is not None:
        srv["scp_server"] = opts.scp_server
    return prefs


def main(argv: Sequence[str] | None = None) -> int:
    """Main entry point for ``gma-mapper`` console/GUI script."""
    opts = parse_cli_args(argv)
    prefs_file = Path(opts.config_path) if opts.config_path else default_preferences_path()
    try:
        if prefs_file.is_file():
            prefs = load_preferences(prefs_file)
        else:
            prefs = default_preferences()
    except Exception:
        prefs = default_preferences()

    apply_cli_overrides(prefs, opts)

    try:
        from PySide6.QtWidgets import QApplication
    except ImportError:
        sys.stderr.write("Error: PySide6 is required to launch the GMA Mapper GUI.\n")
        return 1

    from gma_mapper.ui.main_window import GMAMapperMainWindow

    app = QApplication(sys.argv)
    win = GMAMapperMainWindow(prefs=prefs, prefs_path=prefs_file)
    win.show()
    win.showNormal()
    win.raise_()
    win.activateWindow()
    if sys.platform == "win32":
        try:
            import ctypes
            hwnd = int(win.winId())
            ctypes.windll.user32.ShowWindow(hwnd, 9)  # SW_RESTORE
            ctypes.windll.user32.ShowWindow(hwnd, 5)  # SW_SHOW
            ctypes.windll.user32.SetForegroundWindow(hwnd)
            print(f"[gma-mapper] Window shown (hwnd={hwnd})", flush=True)
        except Exception as exc:
            print(f"[gma-mapper] Window show warning: {exc}", flush=True)
    QTimer_connect = getattr(win, "connect_to_configured_server", None)
    if QTimer_connect:
        from PySide6.QtCore import QTimer
        QTimer.singleShot(100, win.connect_to_configured_server)
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())

