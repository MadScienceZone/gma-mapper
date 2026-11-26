"""Debug logging helpers ported from ``GMADieRoller/Debug.py``."""

from __future__ import annotations

import sys
from typing import Any

_DEBUG_ENABLED: bool = False


def debug(state: bool) -> None:
    """Enable or disable debug trace output to stderr."""
    global _DEBUG_ENABLED  # pylint: disable=global-statement
    _DEBUG_ENABLED = bool(state)


def is_debug() -> bool:
    """Return True when debug tracing is enabled."""
    return _DEBUG_ENABLED


def dprint(*args: Any, **kwargs: Any) -> None:
    """Print diagnostic output to stderr when debug mode is enabled."""
    if not _DEBUG_ENABLED:
        return
    if "file" not in kwargs:
        kwargs["file"] = sys.stderr
    print(*args, **kwargs)
