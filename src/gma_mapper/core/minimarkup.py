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

import html
import re
from typing import Sequence

BULLET_CHARS = ("\u2022", "\u2023", "\u2043", "\u25cb", "\u261e", "\u2605")

_LIST_LINE_RE = re.compile(r"^([@#]+)\s*(.*)$")

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
    ("r", re.compile(r"\b1/2\b"), "\u00bd"),
    ("r", re.compile(r"\b1/4\b"), "\u00bc"),
    ("r", re.compile(r"\b3/4\b"), "\u00be"),
    ("r", re.compile(r"\b(\d+)_1/2\b"), "\\1\u00bd"),
    ("r", re.compile(r"\b(\d+)_1/4\b"), "\\1\u00bc"),
    ("r", re.compile(r"\b(\d+)_3/4\b"), "\\1\u00be"),
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


def render(mtext: str) -> list[tuple[str, str]]:
    """Parse GMA minimarkup text into a list of `(style, text)` spans.

    `style` is one of: `'normal'`, `'bold'`, `'italic'`, `'bolditalic'`, `'section'`, `'subsection'`.
    Matches `::gma::minimarkup::render` in `bin/minimarkup.tcl`.
    """
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

    return spans


def render_flat(mtext: str) -> list[str]:
    """Return flat `[style, text, style, text, ...]` list exactly like Tcl `minimarkup::render`."""
    flat: list[str] = []
    for style, text in render(mtext):
        flat.append(style)
        flat.append(text)
    return flat


def strip(rendered: Sequence[tuple[str, str] | str]) -> str:
    """Strip font style tags from rendered output, returning plain Unicode text.

    Accepts either `list[tuple[str, str]]` (from `render()`) or flat `list[str]` (from `render_flat()`).
    Matches `::gma::minimarkup::strip`.
    """
    if not rendered:
        return ""
    first = rendered[0]
    if isinstance(first, tuple):
        return "".join(text for _style, text in rendered)  # type: ignore[misc]
    # Flat list [style, text, style, text, ...]
    return "".join(str(rendered[i]) for i in range(1, len(rendered), 2))


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

