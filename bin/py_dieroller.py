#!/usr/bin/env python3
"""Launcher for the standalone GMA Die Roller Python/PySide6 client (``py_dieroller``).

Automatically delegates to the repository's ``.venv`` Python if present,
or adds ``src/`` to ``sys.path`` and runs ``py_dieroller.__main__.main()``.
"""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys


def _repo_venv_python(repo_root: Path) -> Path:
    if sys.platform == "win32":
        return repo_root / ".venv" / "Scripts" / "python.exe"
    return repo_root / ".venv" / "bin" / "python"


def main() -> int:
    """Invoke ``py_dieroller.__main__.main()`` via repo ``.venv`` or local ``src/``."""
    script_path = Path(__file__).resolve()
    repo_root = script_path.parent.parent
    venv_py = _repo_venv_python(repo_root)

    if (
        venv_py.is_file()
        and Path(sys.executable).resolve() != venv_py.resolve()
        and os.environ.get("_GMA_PY_DIEROLLER_REEXEC") != "1"
    ):
        env = dict(os.environ)
        env["_GMA_PY_DIEROLLER_REEXEC"] = "1"
        return subprocess.call([str(venv_py), str(script_path), *sys.argv[1:]], env=env)

    bin_dir = script_path.parent
    src_path = (repo_root / "src").resolve()
    src_dir = str(src_path)

    # Remove bin/ entries so bin/py_dieroller.py cannot shadow src/py_dieroller/.
    cleaned: list[str] = []
    for entry in sys.path:
        try:
            resolved = Path(entry or ".").resolve()
        except OSError:
            cleaned.append(entry)
            continue
        if resolved in (bin_dir, src_path):
            continue
        cleaned.append(entry)
    sys.path[:] = [src_dir, *cleaned]

    from py_dieroller.__main__ import main as dieroller_main

    return dieroller_main()


if __name__ == "__main__":
    raise SystemExit(main())
