"""GUI entry point for standalone ``py_dieroller``."""

from __future__ import annotations

import argparse
import sys
from typing import Sequence

from py_dieroller.debug import debug as set_debug


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    """Parse CLI options for the standalone die roller GUI."""
    parser = argparse.ArgumentParser(prog="py-dieroller")
    parser.add_argument(
        "-c",
        "--config",
        help="Load preferences from FILE",
        metavar="FILE",
    )
    parser.add_argument("-d", "--debug", action="store_true", help="Enable debug output")
    parser.add_argument(
        "-s",
        "--font-size",
        type=int,
        metavar="PTS",
        help="Base UI font size in points",
    )
    parser.add_argument(
        "-x",
        "--high-dpi-scaling",
        action="store_true",
        help="Enable high-DPI scaling (enabled by default in Qt 6)",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    """Launch the standalone PySide6 ``DieRollerWindow`` application."""
    args = parse_args(argv)
    if args.debug:
        set_debug(True)

    try:
        from PySide6.QtWidgets import QApplication
    except ImportError:
        sys.stderr.write("Error: PySide6 is required to launch py-dieroller.\n")
        return 1

    from py_dieroller.app import DieRollerWindow

    app = QApplication(sys.argv)
    win = DieRollerWindow(config_file=args.config, font_size=args.font_size)
    win.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
