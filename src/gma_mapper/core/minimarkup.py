# ########################################################################################
# #  _______  _______  _______                ___          ___    _______                #
# # (  ____ \(       )(  ___  ) Game         /   )        /   )  / ___   )               #
# # | (    \/| () () || (   ) | Master's    / /) |       / /) |  \/   )  |               #
# # | |      | || || || (___) | Assistant  / (_) (_     / (_) (_     /   )               #
# # | | ____ | |(_)| ||  ___  |           (____   _)   (____   _)  _/   /                #
# # | | \_  )| |   | || (   ) | VTT            ) (          ) (   /   _/                 #
# # | (___) || )   ( || )   ( | Mapper         | |   _      | |  (   (__/\               #
# # (_______)|/     \||/     \| Client         (_)  (_)     (_)  \_______/               #
# #                                                                                      #
# ########################################################################################
#
# GMA inline markup parser and formatter.
# Ported from bin/minimarkup.tcl.

from __future__ import annotations

import functools
import html
import re
from typing import Sequence, overload

BULLET_CHARS = ("\u2022", "\u2023", "\u2043", "\u25cb", "\u261e", "\u2605")

_LIST_LINE_RE = re.compile(r"^([@#]+)\s*(.*)$")

_FRACTIONS: dict[str, str] = {
    "1/2": "\u00bd",
    "1/4": "\u00bc",
    "3/4": "\u00be",
}
_FRACTION_RE = re.compile(r"\b(?:(\d+)_)?(1/2|1/4|3/4)\b")


def _replace_fraction(m: re.Match[str]) -> str:
    whole = m.group(1) or ""
    return f"{whole}{_FRACTIONS[m.group(2)]}"


# Ordered replacement rules from bin/minimarkup.tcl
_REPLACEMENTS: list[tuple[str, str | re.Pattern[str], str]] = [
    ("s", "+/-", "\u00b1"),
    ("s", "---", "\u2014"),
    ("s", "--", "\u2013"),
    ("r", re.compile(r"(\d)x"), "\\1\u00d7"),
    ("r", re.compile(r"x(\d)"), "\u00d7\\1"),
    ("s", "[x]", "\u00d7"),
    ("s", "[S]", "\u00a7"),
    ("s", "[0]", "\u00b0"),
    ("s", "[1]", "\u00b9"),
    ("s", "[2]", "\u00b2"),
    ("s", "[3]", "\u00b3"),
    ("s", "[4]", "\u2074"),
    ("s", "[5]", "\u2075"),
    ("s", "[6]", "\u2076"),
    ("s", "[7]", "\u2077"),
    ("s", "[8]", "\u2078"),
    ("s", "[9]", "\u2079"),
    ("r", re.compile(r"-(\d)"), "\u2012\\1"),
    # Consolidated 6 separate fraction regexes into a single pass
    ("f", _FRACTION_RE, ""),
    ("s", "^o", "\u00b0"),
    ("s", "[c]", "\u00a9"),
    ("s", "[R]", "\u00ae"),
    ("s", "[<<]", "\u00ab"),
    ("s", "[>>]", "\u00bb"),
    ("s", "AE", "\u00c6"),
    ("s", "ae", "\u00e6"),
    ("s", "^.", "\u2022"),
    ("s", "[/]", "\u00f7"),
    ("s", "[+]", "\u2020"),
    ("s", "[++]", "\u2021"),
    ("s", r"\v", "|"),
    ("s", "//", "\x01I"),
    ("s", "**", "\x01B"),
    ("s", "``", "\u201c"),
    ("s", "''", "\u201d"),
    ("s", "`", "\u2018"),
    ("s", "'", "\u2019"),
    ("r", re.compile(r"==\[(.*?)\]=="), "\x01T\\1\x01t"),
    ("r", re.compile(r"==\((.*?)\)=="), "\x01S\\1\x01s"),
    ("r", re.compile(r"\[\[[^\]|]*\|([^\]]+)\]\]"), "\x01L\\1\x01l"),
    ("r", re.compile(r"\[\[(.*?)\]\]"), "\x01L\\1\x01l"),
    ("s", r"\.", ""),
    ("s", r"\e", "\\"),
]


# Cache parsed markup spans as an immutable tuple so repeated renders of static
# descriptions/notes avoid re-running all replacement passes.
@functools.lru_cache(maxsize=256)
def _render_cached(mtext: str) -> tuple[tuple[str, str], ...]:
    lines = mtext.split("\n")
    levels: list[int] = []
    newlines: list[str] = []

    for line in lines:
        m = _LIST_LINE_RE.match(line)
        if m:
            bullets, rest = m.group(1), m.group(2)
            label_parts: list[str] = []
            for i, ch in enumerate(bullets):
                if ch == "@":
                    if i > 5:
                        label_parts.append("*")
                    else:
                        label_parts.append(BULLET_CHARS[i])
                else:
                    while len(levels) <= i:
                        levels.append(0)
                    if i == len(bullets) - 1:
                        levels[i] += 1
                    label_parts.append(f"({levels[i]})")
            line = f"{''.join(label_parts)} {rest}"
        newlines.append(line)

    srctext = "\x02" + " ".join(newlines)
    for kind, pattern, repl in _REPLACEMENTS:
        if kind == "r":
            assert isinstance(pattern, re.Pattern)
            srctext = pattern.sub(repl, srctext)
        elif kind == "f":
            assert isinstance(pattern, re.Pattern)
            srctext = pattern.sub(_replace_fraction, srctext)
        else:
            assert isinstance(pattern, str)
            srctext = srctext.replace(pattern, repl)

    spans: list[tuple[str, str]] = []
    italic = False
    bold = False
    link = False
    section = False
    subsection = False

    for piece in srctext.split("\x01"):
        code = piece[:1]
        text = piece[1:]
        if code == "I":
            italic = not italic
        elif code == "B":
            bold = not bold
        elif code == "L":
            link = True
        elif code == "l":
            link = False
        elif code == "S":
            subsection = True
        elif code == "s":
            subsection = False
        elif code == "T":
            section = True
        elif code == "t":
            section = False

        if section:
            style = "section"
        elif subsection:
            style = "subsection"
        elif link:
            style = "italic"
        elif bold and italic:
            style = "bolditalic"
        elif bold:
            style = "bold"
        elif italic:
            style = "italic"
        else:
            style = "normal"

        spans.append((style, text))

    return tuple(spans)


def render(mtext: str) -> list[tuple[str, str]]:
    """Parse GMA minimarkup text into a list of `(style, text)` spans.

    `style` is one of: `'normal'`, `'bold'`, `'italic'`, `'bolditalic'`, `'section'`, `'subsection'`.
    Matches `::gma::minimarkup::render` in `bin/minimarkup.tcl`.
    """
    return list(_render_cached(mtext))


def render_flat(mtext: str) -> list[str]:
    """Return flat `[style, text, style, text, ...]` list exactly like Tcl `minimarkup::render`."""
    flat: list[str] = []
    for style, text in render(mtext):
        flat.append(style)
        flat.append(text)
    return flat


@overload
def strip(rendered: Sequence[tuple[str, str]]) -> str: ...


@overload
def strip(rendered: Sequence[str]) -> str: ...


def strip(rendered: Sequence[tuple[str, str]] | Sequence[str]) -> str:
    """Strip font style tags from rendered output, returning plain Unicode text.

    Accepts either `list[tuple[str, str]]` (from `render()`) or flat `list[str]` (from `render_flat()`).
    Matches `::gma::minimarkup::strip`.
    """
    if not rendered:
        return ""
    first = rendered[0]
    if isinstance(first, tuple):
        return "".join(item[1] for item in rendered if isinstance(item, tuple))
    # Flat list [style, text, style, text, ...]
    return "".join(str(rendered[i]) for i in range(1, len(rendered), 2))


@functools.lru_cache(maxsize=256)
def render_html(mtext: str) -> str:
    """Render GMA minimarkup text into an HTML snippet suitable for Qt rich text widgets."""
    parts: list[str] = []
    for style, text in render(mtext):
        if not text:
            continue
        esc = html.escape(text)
        if style == "bold":
            parts.append(f"<b>{esc}</b>")
        elif style == "italic":
            parts.append(f"<i>{esc}</i>")
        elif style == "bolditalic":
            parts.append(f"<b><i>{esc}</i></b>")
        elif style == "section":
            parts.append(f"<b><u>{esc}</u></b>")
        elif style == "subsection":
            parts.append(f"<b><i><u>{esc}</u></i></b>")
        else:
            parts.append(esc)
    return "".join(parts)

