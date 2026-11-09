"""Standalone script to verify preferences.json round-trip fidelity against Tcl preferences files.

Reads a known-good preferences.json file via gma_mapper.core.profile.load(), writes it out via
gma_mapper.core.profile.save(), and reads it back in again, checking:
1. Exact JSON object structure, values, and strict Python types (e.g. int vs float) against the original file.
2. Exact in-memory dictionary & type equality between the first load() and second load().
3. Line-by-line normalized JSON text comparison.
"""

from __future__ import annotations

import difflib
import json
import sys
import tempfile
from pathlib import Path
from typing import Any

# Ensure src/ is importable when invoked directly as a script
REPO_ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = REPO_ROOT / "src"
if str(SRC_DIR) not in sys.path:
    sys.path.insert(0, str(SRC_DIR))

from gma_mapper.core.profile import load, save  # noqa: E402


def compare_strict(a: Any, b: Any, path: str = "$") -> list[str]:
    """Recursively compare two structures for value AND exact type equality (`int` vs `float`)."""
    diffs: list[str] = []
    if type(a) is not type(b):
        diffs.append(
            f"{path}: type mismatch: {type(a).__name__} ({a!r}) != {type(b).__name__} ({b!r})"
        )
        return diffs

    if isinstance(a, dict):
        a_keys = list(a.keys())
        b_keys = list(b.keys())
        for k in a_keys:
            if k not in b:
                diffs.append(f"{path}.{k}: present in original ({a[k]!r}), missing in output")
            else:
                diffs.extend(compare_strict(a[k], b[k], f"{path}.{k}"))
        for k in b_keys:
            if k not in a:
                diffs.append(f"{path}.{k}: added in output ({b[k]!r}), not in original")
    elif isinstance(a, list):
        if len(a) != len(b):
            diffs.append(f"{path}: list length mismatch: {len(a)} != {len(b)}")
        for i, (item_a, item_b) in enumerate(zip(a, b)):
            diffs.extend(compare_strict(item_a, item_b, f"{path}[{i}]"))
    else:
        if a != b:
            diffs.append(f"{path}: value mismatch: {a!r} != {b!r}")
    return diffs


def verify_file(src_path: Path) -> bool:
    """Verify load -> save -> load round-trip on `src_path`. Return True if identical."""
    print(f"=== Verifying {src_path} ===")
    orig_raw = json.loads(src_path.read_text(encoding="utf-8"))
    loaded1 = load(src_path)

    with tempfile.TemporaryDirectory() as tmpdir:
        out_path = Path(tmpdir) / "preferences_out.json"
        save(out_path, loaded1)
        written_text = out_path.read_text(encoding="utf-8")
        written_raw = json.loads(written_text)
        loaded2 = load(out_path)

    raw_diffs = compare_strict(orig_raw, written_raw, "$")
    mem_diffs = compare_strict(loaded1, loaded2, "$loaded")

    orig_norm_lines = (json.dumps(orig_raw, indent=4) + "\n").splitlines()
    written_lines = written_text.splitlines()
    text_diff = list(
        difflib.unified_diff(
            orig_norm_lines,
            written_lines,
            fromfile=f"{src_path.name} (original)",
            tofile=f"{src_path.name} (saved by Python)",
            lineterm="",
        )
    )

    if not raw_diffs and not mem_diffs and not text_diff:
        print(f"PASS: {src_path.name} round-tripped with 0 differences (values, types, and JSON text match).\n")
        return True

    if raw_diffs:
        print(f"FAIL: {len(raw_diffs)} strict JSON/type difference(s):")
        for d in raw_diffs:
            print(f"  - {d}")
    if mem_diffs:
        print(f"FAIL: {len(mem_diffs)} in-memory load1 vs load2 difference(s):")
        for d in mem_diffs:
            print(f"  - {d}")
    if text_diff:
        print("Unified JSON diff:")
        print("\n".join(text_diff))
    print()
    return False


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    if args:
        paths = [Path(p) for p in args]
    else:
        default_tcl = REPO_ROOT.parent / "preferences.json.tcl"
        paths = [default_tcl]

    all_ok = True
    for p in paths:
        if not p.is_file():
            print(f"ERROR: file not found: {p}", file=sys.stderr)
            return 2
        if not verify_file(p):
            all_ok = False
    return 0 if all_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
