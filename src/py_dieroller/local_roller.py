"""Lightweight pure-Python offline die roller for ``py_dieroller``.

Replaces ``MadScienceZone.GMA.Dice.DieRoller`` when disconnected from a GMA server.
Supports optional ``[Label =] Expression [| options]`` syntax including ``NdS``,
``d%``, ``+ - * / //``, ``best N`` / ``worst N``, and ``{label}`` annotations.
"""

from __future__ import annotations

import random
import re
from typing import Any

_DIE_TERM_RE = re.compile(
    r"^\s*(?:(\d*)[dD](\d+|%))(?:\s+(best|worst)\s+(\d+))?\s*$"
)
_REPEAT_OPT_RE = re.compile(r"\brepeat\s+(\d+)\b", flags=re.IGNORECASE)
_TOKEN_RE = re.compile(
    r"(\d*[dD](?:\d+|%)(?:\s+(?:best|worst)\s+\d+)?|\d+|[+\-*/]|//|\(|\)|\{[^{}]+\})"
)


class LocalDieRoller:
    """Evaluate simple GMA die-roll expressions locally without a server connection."""

    def __init__(self, rng: random.Random | None = None) -> None:
        self._rng = rng or random.Random()

    def do_roll(self, expr: str) -> tuple[str | None, list[tuple[int, list[tuple[str, str]]]]]:
        """Evaluate ``expr`` and return ``(label, [(total, [(tag, text), ...])])``.

        Matches the return shape expected by ``ChatPanel.roll_dice`` in offline mode.
        """
        raw = str(expr or "").strip()
        if not raw:
            return (None, [(0, [])])

        label: str | None = None
        if "=" in raw:
            lhs, rhs = raw.split("=", 1)
            label = lhs.strip() or None
            body = rhs.strip()
        else:
            body = raw

        pipe_opts = ""
        if "|" in body:
            body, pipe_opts = body.split("|", 1)
            body = body.strip()
            pipe_opts = pipe_opts.strip()

        repeat_count = 1
        if pipe_opts:
            rep_match = _REPEAT_OPT_RE.search(pipe_opts)
            if rep_match:
                repeat_count = max(1, min(int(rep_match.group(1)), 50))

        tokens = _TOKEN_RE.findall(body)
        if not tokens:
            return (label, [(0, [("error", f"Cannot parse expression: {body}")])])

        results: list[tuple[int, list[tuple[str, str]]]] = []
        for _ in range(repeat_count):
            details: list[tuple[str, str]] = []
            eval_parts: list[str] = []
            for tok in tokens:
                if tok.startswith("{") and tok.endswith("}"):
                    details.append(("label", tok[1:-1].strip()))
                    continue

                if tok in ("+", "-", "*", "/", "//", "(", ")"):
                    details.append(("operator", tok))
                    eval_parts.append(tok)
                    continue

                if tok.isdigit():
                    details.append(("constant", tok))
                    eval_parts.append(tok)
                    continue

                m = _DIE_TERM_RE.match(tok)
                if m:
                    spec_str, rolls_str, term_sum = self._eval_die_match(m)
                    details.append(("diespec", spec_str))
                    details.append(("roll", rolls_str))
                    eval_parts.append(str(term_sum))
                    continue

                details.append(("label", tok))

            total = _safe_eval_arithmetic(" ".join(eval_parts))
            full_details: list[tuple[str, str]] = [
                ("result", str(total)),
                ("separator", "="),
                *details,
            ]
            if pipe_opts:
                full_details.append(("moddelim", "|"))
                full_details.append(("critspec", pipe_opts))
            results.append((total, full_details))

        return (label, results)

    def _eval_die_match(self, match: re.Match[str]) -> tuple[str, str, int]:
        count = int(match.group(1)) if match.group(1) else 1
        sides_raw = match.group(2)
        sides = 100 if sides_raw == "%" else int(sides_raw)
        keep_mode = (match.group(3) or "").lower()
        keep_n = int(match.group(4)) if match.group(4) else 0

        count = max(1, min(count, 1000))
        sides = max(1, min(sides, 100000))
        rolls = [self._rng.randint(1, sides) for _ in range(count)]

        if keep_mode in ("best", "worst") and 0 < keep_n < len(rolls):
            indexed = sorted(
                enumerate(rolls),
                key=lambda pair: pair[1],
                reverse=(keep_mode == "best"),
            )
            kept_indices = {idx for idx, _val in indexed[:keep_n]}
            term_sum = sum(r for idx, r in enumerate(rolls) if idx in kept_indices)
        else:
            term_sum = sum(rolls)

        spec_str = f"{count}d{'%' if sides_raw == '%' else sides}"
        if keep_mode:
            spec_str += f" {keep_mode} {keep_n}"
        return (spec_str, ",".join(str(r) for r in rolls), term_sum)


def _safe_eval_arithmetic(expr: str) -> int:
    """Evaluate a pure arithmetic expression containing only ints and ``+ - * / // ( )``."""
    cleaned = expr.strip()
    if not cleaned:
        return 0
    # Strict allowlist so only arithmetic literals/operators ever reach eval().
    if not re.fullmatch(r"[0-9+\-*/()\s]+", cleaned):
        return 0
    try:
        val: Any = eval(cleaned, {"__builtins__": {}}, {})  # pylint: disable=eval-used
        return int(val)
    except Exception:  # pylint: disable=broad-exception-caught
        return 0
