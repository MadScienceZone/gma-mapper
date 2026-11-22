#!/usr/bin/env python3
"""Launcher for the GMA Mapper Python/PySide6 client (`py_mapper`).

Automatically delegates to the repository's `.venv` Python if present,
or adds `src/` to `sys.path` and runs `gma_mapper.__main__.main()`.
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
    script_path = Path(__file__).resolve()
    repo_root = script_path.parent.parent
    venv_py = _repo_venv_python(repo_root)

    if (
        venv_py.is_file()
        and Path(sys.executable).resolve() != venv_py.resolve()
        and os.environ.get("_GMA_PY_MAPPER_REEXEC") != "1"
    ):
        env = dict(os.environ)
        env["_GMA_PY_MAPPER_REEXEC"] = "1"
        return subprocess.call([str(venv_py), str(script_path), *sys.argv[1:]], env=env)

    src_dir = str(repo_root / "src")
    if src_dir not in sys.path:
        sys.path.insert(0, src_dir)

    from gma_mapper.__main__ import main as gma_main

    return gma_main()


if __name__ == "__main__":
    raise SystemExit(main())
