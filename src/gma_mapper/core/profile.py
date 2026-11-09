"""GMA Mapper user preferences and server profiles (v1-v15).

Ported from bin/gmaprofile.tcl.
"""

from __future__ import annotations

import copy
import json
from pathlib import Path
from typing import Any

from gma_mapper.core.util import search_in_path
from gma_mapper.net.protocol import _construct, _encode_payload_dict

MINIMUM_FILE_VERSION: int = 1
MAXIMUM_FILE_VERSION: int = 15
CURRENT_FILE_VERSION: int = 15

MARKER_SHAPES: dict[str, str] = {
    "O": "circle",
    "X": "X",
    "V": "downward triangle",
    "^": "upward triangle",
    "<>": "diamond",
    "#": "double cross",
    "+": "single cross",
    "\\\\": "double backslash",
    "//": "double slash",
    "\\": "backslash",
    "/": "slash",
    "=": "double horizontal",
    "-": "single horizontal",
    "||": "double vertical",
    "|": "single vertical",
    "|v": "small triangle to left",
    "v|": "small triangle to right",
    "|o": "small circle to left",
    "o|": "small circle to right",
    "|<>": "small diamond to left",
    "<>|": "small diamond to right",
}

SYMBOLS: dict[str, str] = {
    "pin": "📌",
    "del": "\u232b",
    "triangle": "\u2023",
    "arrow": "\u2199",
    "bullet": "\u23fa",
    "circle-x": "\u2bbf",
    "ref-mk": "\u203b",
    "remove": "\u229d",
    "square-x": "\u22a0",
    "ballot-x": "\u2718",
    "up-arrow": "\u2191",
    "add": "\u2295",
    "__default__": "\u22a0",
}

DEFAULT_COLOR_TABLE: dict[tuple[str, str], str] = {
    ("fg", "light"): "#000000",
    ("normal_fg", "light"): "#000000",
    ("bg", "light"): "#cccccc",
    ("normal_bg", "light"): "#cccccc",
    ("fg", "dark"): "#aaaaaa",
    ("normal_fg", "dark"): "#aaaaaa",
    ("bg", "dark"): "#232323",
    ("normal_bg", "dark"): "#232323",
    ("check_select", "light"): "#000000",
    ("check_select", "dark"): "#ffffff",
    ("check_menu", "light"): "#000000",
    ("check_menu", "dark"): "#ffffff",
    ("bright_fg", "light"): "#000000",
    ("bright_fg", "dark"): "#ffffff",
    ("grid", "light"): "blue",
    ("grid", "dark"): "#aaaaaa",
    ("grid_minor", "light"): "#b00b03",
    ("grid_minor", "dark"): "#b00b03",
    ("grid_major", "light"): "#345f12",
    ("grid_major", "dark"): "#345f12",
    ("hand_color", "light"): "black",
    ("hand_color", "dark"): "#aaaaaa",
    ("tick_color", "light"): "blue",
    ("tick_color", "dark"): "#aaaaaa",
    ("flist_fg", "light"): "black",
    ("flist_fg", "dark"): "white",
    ("flist_bg", "light"): "white",
    ("flist_bg", "dark"): "#232323",
    ("next_fg", "light"): "white",
    ("next_fg", "dark"): "white",
    ("next_bg", "light"): "black",
    ("next_bg", "dark"): "#cc0000",
    ("cur_bg", "light"): "#9cffb4",
    ("cur_bg", "dark"): "#003300",
    ("ready_bg", "light"): "#ff3333",
    ("ready_bg", "dark"): "#ff0000",
    ("hold_bg", "light"): "#ffaaaa",
    ("hold_bg", "dark"): "#610400",
    ("zero_hp", "light"): "#ff0000",
    ("zero_hp", "dark"): "#ff0000",
    ("negative_hp", "light"): "#000000",
    ("negative_hp", "dark"): "#000000",
    ("slot_fg", "light"): "#000000",
    ("slot_fg", "dark"): "#666666",
    ("slot_bg", "light"): "#666666",
    ("slot_bg", "dark"): "#232323",
    ("flat_footed", "light"): "#3333ff",
    ("flat_footed", "dark"): "#3333ff",
    ("preset_name", "dark"): "cyan",
    ("preset_name", "light"): "blue",
}

_THEME_PAIR = ("o", {"dark": "s", "light": "s"})

FILE_FORMAT: dict[str, Any] = {
    "GMA_Mapper_preferences_version": "i",
    "animate": "?",
    "button_size": "s",
    "chat_timestamp": "?",
    "colorize_die_rolls": "?",
    "a11y": ("o", {"colorize_die_labels": "?"}),
    "curl_path": "s",
    "curl_insecure": "?",
    "current_profile": "s",
    "dark": "?",
    "debug_level": "i",
    "debug_proto": "?",
    "flash_updates": "?",
    "scaling": "f",
    "show_timers": "s",
    "no_dice": "?",
    "no_ondeck_audio": "?",
    "no_sfx": "?",
    "suppress_aka": "?",
    "not_playing": "?",
    "guide_lines": (
        "o",
        {
            "major": ("o", {"interval": "i", "offsets": ("o", {"x": "i", "y": "i"})}),
            "minor": ("o", {"interval": "i", "offsets": ("o", {"x": "i", "y": "i"})}),
        },
    ),
    "image_format": "s",
    "keep_tools": "?",
    "menu_button": "?",
    "markup_enabled": "?",
    "never_animate": "?",
    "preload": "?",
    "profiles": (
        "a",
        {
            "name": "s",
            "host": "s",
            "port": "i",
            "username": "s",
            "password": "s",
            "curl_proxy": "s",
            "blur_all": "?",
            "blur_pct": "i",
            "suppress_chat": "?",
            "chat_limit": "i",
            "chat_log": "s",
            "curl_server": "s",
            "update_url": "s",
            "module_id": "s",
            "server_mkdir": "s",
            "nc_path": "s",
            "scp_path": "s",
            "scp_dest": "s",
            "scp_server": "s",
            "scp_proxy": "s",
            "ssh_path": "s",
        },
    ),
    "fonts": (
        "D",
        {
            "family": "s",
            "size": "i",
            "weight": "i",
            "slant": "i",
            "overstrike": "?",
            "underline": "?",
        },
    ),
    "styles": (
        "o",
        {
            "clocks": (
                "o",
                {
                    "hand_color": _THEME_PAIR,
                    "tick_color": _THEME_PAIR,
                    "flist_fg": _THEME_PAIR,
                    "flist_bg": _THEME_PAIR,
                    "next_fg": _THEME_PAIR,
                    "next_bg": _THEME_PAIR,
                    "cur_bg": _THEME_PAIR,
                    "ready_bg": _THEME_PAIR,
                    "hold_bg": _THEME_PAIR,
                    "zero_hp": _THEME_PAIR,
                    "negative_hp": _THEME_PAIR,
                    "slot_fg": _THEME_PAIR,
                    "slot_bg": _THEME_PAIR,
                    "flat_footed": _THEME_PAIR,
                    "timedisp_font": "s",
                    "turndisp_font": "s",
                    "default_font": "s",
                },
            ),
            "dialogs": (
                "o",
                {
                    "heading_fg": _THEME_PAIR,
                    "normal_fg": _THEME_PAIR,
                    "normal_bg": _THEME_PAIR,
                    "highlight_fg": _THEME_PAIR,
                    "odd_bg": _THEME_PAIR,
                    "even_bg": _THEME_PAIR,
                    "check_select": _THEME_PAIR,
                    "check_menu": _THEME_PAIR,
                    "bright_fg": _THEME_PAIR,
                    "grid": _THEME_PAIR,
                    "grid_minor": _THEME_PAIR,
                    "grid_major": _THEME_PAIR,
                    "preset_name": _THEME_PAIR,
                },
            ),
            "characters": ("D", {"name": "s"}),
            "dierolls": (
                "o",
                {
                    "compact_recents": "?",
                    "components": (
                        "D",
                        {
                            "fg": _THEME_PAIR,
                            "bg": _THEME_PAIR,
                            "font": "s",
                            "format": "s",
                            "overstrike": "?",
                            "underline": "?",
                            "offset": "i",
                        },
                    ),
                },
            ),
            "markers": (
                "D",
                {
                    "modifiers": "l",
                    "color": "s",
                    "shape": "s",
                    "dashpattern": "s",
                    "description": "s",
                    "tracer": "?",
                    "endatdeath": "?",
                    "limit": "i",
                },
            ),
        },
    ),
}

STYLE_DESCRIPTIONS: dict[str, str] = {
    "best": 'When making "best of n" die rolls, this displays the number of rolls to attempt.',
    "begingroup": 'The operator (i.e., "(") which signals the start of a grouped sub-expression.',
    "bold": "This is the font and style to use for boldface text in chat messages.",
    "bolditalic": "This is the font and style to use for bold italic text in chat messages.",
    "bonus": "An extra bonus added or subtracted from the roll, such as when confirming a critical hit with a bonus to the confirmation roll only.",
    "constant": "A constant value in the die roll expression, such as a bonus or penalty.",
    "critlabel": "An indicator that this roll is to confirm a critical hit.",
    "critspec": "An indicator that this roll may be subject to confirmation as a critical hit.",
    "cumulative": "The accumulated total of all die rolls (when using the |total option).",
    "dc": "An indicator of the target DC for this roll.",
    "diebonus": "A bonus or penalty applied to every die rolled for a particular diespec value (but not others in a multiple-die-roll request).",
    "diespec": 'A die-roll specification such as "3d12" which indicates a random component of the overall expression.',
    "discarded": 'When making "best of n" or "worst of n" rolls, this indicates a set of die rolls that were discarded to get the required results.',
    "endgroup": 'The operator (i.e., ")") which signals the end of a grouped sub-expression.',
    "error": "An error message from the server indicating what went wrong with your die roll request.",
    "exceeded": 'When making a roll with a DC target, or using "|until", this indicates the amount by which this roll exceeded the target.',
    "fail": "If the roll includes clear success/fail criteria, this indicates why the roll failed.",
    "from": "For chat messages and die rolls, this indicates who requested the roll.",
    "fullmax": "An indicator that the whole die-roll expression was forced to yield its maximum possible value.",
    "fullresult": "The overall result of the die roll, displayed at the start of the line before the other details.",
    "italic": "This is the font and style to use for italic text in chat messages.",
    "iteration": 'When making multiple rolls due to "|until" or "|repeat" options, this shows the roll number in that sequence.',
    "label": 'An arbitrary label placed on a component (e.g., the "fire" in "1d6 fire").',
    "max": 'Indicates a maximum limit placed on the result of the die roll (via the "|max" option).',
    "maximized": 'An indicator that some or all of a diespec is rolled at maximum value. (For example, a ">" character in this style is placed before a diespec if the first of its dice should be taken at maximum value, as in ">3d6".)',
    "maxroll": "This shows the actual results of the individual dice rolled (when they are forced to maximum value).",
    "met": "When a specific DC target is known for the die roll, this indicates that it was exactly met.",
    "min": 'Indicates a minimum limit placed on the result of the die roll (via the "|min" option).',
    "moddelim": "This styles the delimiter used to separate modifiers from each other and the die roll specification.",
    "normal": "This is the style for text that doesn't fit into any other categories and for normal chat message text.",
    "notice": "A notice sent to you from the server about your die-roll results.",
    "operator": 'A math operator (such as "+", "-", etc.) between components of the die-roll request.',
    "repeat": "An indicator that you want the die-roll expression repeated a number of times.",
    "result": "The overal result of the die-roll request.",
    "roll": 'This shows the actual results of the individual dice rolled (when forced to maximum value, the "maxroll" style is used instead).',
    "section": "This is the font and style to use for section titles in chat messages.",
    "separator": "Any punctuation that is used as a separator in the die-roll expression.",
    "sf": 'An indicator that the "|sf" option was used to check for natural min and max rolls as automatic failure or success, along with custom labels, if any, for the success and failure outcomes.',
    "short": 'When making a roll with a DC target, or using "|until", this indicates the amount by which this roll fell short of the target.',
    "stats": 'When reporting statistics about multi-die roll sets such as those generated with "|repeat" options.',
    "subsection": "This is the font and style to use for subsection titles in chat messages.",
    "total": "An indicator that you want to repeat the roll until the total of all rolls meets a target value.",
    "subtotal": "This shows a subtotal at various places in a complex, multi-dice roll expression.",
    "success": "If the roll includes clear success/fail criteria, this indicates why the roll succeeded.",
    "system": "This gives the style to display system messages in the chat window.",
    "timestamp": "This gives the style to display timestamps on messages in the chat window.",
    "title": "A user-supplied title applied to the die-roll expression.",
    "to": "If the die-roll expression or chat message was addressed to specific people, this displays the list of recipients.",
    "until": "An indicator that you want to repeat the roll until a specified target value is reached.",
    "worst": 'When making "worst of n" die rolls, this displays the number of rolls to attempt.',
}


def default_color(key: str, theme: str) -> str:
    """Return the default color for `(key, theme)`."""
    return DEFAULT_COLOR_TABLE[(key, theme)]


def preferred_color(prefdata: dict[str, Any], key: str, theme: str) -> str:
    """Return the user's preferred dialog color for `key` and `theme`, or default."""
    if key == "fg":
        key = "normal_fg"
    elif key == "bg":
        key = "normal_bg"
    dialogs = prefdata.get("styles", {}).get("dialogs", {})
    if key in dialogs and theme in dialogs[key] and dialogs[key][theme]:
        return str(dialogs[key][theme])
    return default_color(key, theme)


def symbol_code_string(name: str) -> str:
    """Return the Unicode symbol string for `name`."""
    return SYMBOLS.get(name, SYMBOLS["__default__"])


SymbolCodeString = symbol_code_string


def default_fonts() -> dict[str, dict[str, Any]]:
    """Return the default dictionary of named fonts."""
    def _f(family: str, size: int, weight: int = 0, slant: int = 0) -> dict[str, Any]:
        return {
            "family": family,
            "size": int(size),
            "weight": weight,
            "slant": slant,
            "overstrike": False,
            "underline": False,
        }

    return {
        "Normal": _f("Helvetica", 12, 0, 0),
        "Bold": _f("Helvetica", 12, 1, 0),
        "Italic": _f("Helvetica", 12, 0, 1),
        "BoldItalic": _f("Helvetica", 12, 1, 1),
        "Title": _f("Helvetica", 16, 1, 0),
        "Subtitle": _f("Helvetica", 14, 1, 0),
        "Important": _f("Helvetica", 12, 1, 0),
        "Special": _f("Times", 12, 0, 1),
        "System": _f("Times", 10, 0, 1),
        "Tiny": _f("Helvetica", 8, 0, 0),
        "FullResult": _f("Helvetica", 16, 1, 0),
        "Result": _f("Helvetica", 14, 0, 0),
        "ClockTime": _f("Helvetica", 16, 0, 0),
        "ClockList": _f("Helvetica", 24, 0, 0),
    }


def _comp(
    fg_dark: str = "",
    fg_light: str = "",
    bg_dark: str = "",
    bg_light: str = "",
    font: str = "Normal",
    fmt: str = "",
    overstrike: bool = False,
    underline: bool = False,
    offset: int = 0,
) -> dict[str, Any]:
    return {
        "fg": {"dark": fg_dark, "light": fg_light},
        "bg": {"dark": bg_dark, "light": bg_light},
        "font": font,
        "format": fmt,
        "overstrike": overstrike,
        "underline": underline,
        "offset": offset,
    }


def default_styles() -> dict[str, Any]:
    """Return the default styles dictionary (clocks, markers, characters, dialogs, dierolls)."""
    clocks: dict[str, Any] = {}
    for k in (
        "hand_color",
        "tick_color",
        "flist_fg",
        "flist_bg",
        "next_fg",
        "next_bg",
        "cur_bg",
        "ready_bg",
        "hold_bg",
        "zero_hp",
        "negative_hp",
        "slot_fg",
        "slot_bg",
        "flat_footed",
    ):
        clocks[k] = {
            "dark": default_color(k, "dark"),
            "light": default_color(k, "light"),
        }
    clocks["timedisp_font"] = "ClockTime"
    clocks["turndisp_font"] = "ClockTime"
    clocks["default_font"] = "ClockList"

    dialogs: dict[str, Any] = {
        "heading_fg": {"dark": "cyan", "light": "blue"},
        "normal_fg": {"dark": default_color("fg", "dark"), "light": default_color("fg", "light")},
        "normal_bg": {"dark": default_color("bg", "dark"), "light": default_color("bg", "light")},
        "highlight_fg": {"dark": "yellow", "light": "red"},
        "odd_bg": {"dark": default_color("bg", "dark"), "light": default_color("bg", "light")},
        "even_bg": {"dark": "#000090", "light": "#bbbbff"},
        "grid": {"dark": default_color("grid", "dark"), "light": default_color("grid", "light")},
        "grid_minor": {
            "dark": default_color("grid_minor", "dark"),
            "light": default_color("grid_minor", "light"),
        },
        "grid_major": {
            "dark": default_color("grid_major", "dark"),
            "light": default_color("grid_major", "light"),
        },
        "check_select": {
            "dark": default_color("check_select", "dark"),
            "light": default_color("check_select", "light"),
        },
        "check_menu": {
            "dark": default_color("check_menu", "dark"),
            "light": default_color("check_menu", "light"),
        },
        "bright_fg": {
            "dark": default_color("bright_fg", "dark"),
            "light": default_color("bright_fg", "light"),
        },
        "preset_name": {
            "dark": default_color("preset_name", "dark"),
            "light": default_color("preset_name", "light"),
        },
    }

    components: dict[str, dict[str, Any]] = {
        "begingroup": _comp(),
        "best": _comp("#aaaaaa", "#888888", font="Special", fmt=" best of %s"),
        "bold": _comp(font="Bold"),
        "bolditalic": _comp(font="BoldItalic"),
        "bonus": _comp("#fffb00", "#f05b00", font="Normal"),
        "constant": _comp(),
        "critlabel": _comp("#fffb00", "#f05b00", font="Special", fmt="Confirm: "),
        "critspec": _comp("#fffb00", "#f05b00", font="Special"),
        "cumulative": _comp("#aaaaaa", "#888888", font="Special", fmt=" (now %s)"),
        "dc": _comp("#aaaaaa", "#888888", font="Special", fmt="DC %s: "),
        "diebonus": _comp("red", "red", font="Special", fmt="(%s per die)"),
        "diespec": _comp(),
        "discarded": _comp("#aaaaaa", "#888888", font="Normal", fmt="{%s}", overstrike=True),
        "endgroup": _comp(),
        "error": _comp("red", "red", font="Normal", fmt="ERROR: %s"),
        "exceeded": _comp("#00fa92", "green", font="Special", fmt=" exceeded DC by %s"),
        "fail": _comp("red", "red", font="Important", fmt="(%s) "),
        "from": _comp("cyan", "blue", font="Normal"),
        "fullmax": _comp("red", "red", font="Important", fmt="maximized"),
        "fullresult": _comp("blue", "#ffffff", "white", "blue", font="FullResult"),
        "italic": _comp(font="Italic"),
        "iteration": _comp("#aaaaaa", "#888888", font="Special", fmt=" (roll #%s)"),
        "label": _comp("cyan", "blue", font="Special", fmt=" %s"),
        "max": _comp("#aaaaaa", "#888888", font="Special", fmt="max %s"),
        "maximized": _comp("red", "red", font="Important", fmt=">"),
        "maxroll": _comp("red", "red", font="Important", fmt="{%s}"),
        "met": _comp("#00fa92", "green", font="Special", fmt="successful"),
        "min": _comp("#aaaaaa", "#888888", font="Special", fmt="min %s"),
        "moddelim": _comp("#fffb00", "#f05b00", font="Normal", fmt=" | "),
        "normal": _comp(),
        "notice": _comp("yellow", "red", font="Special", fmt="[%s] "),
        "operator": _comp(),
        "repeat": _comp("#aaaaaa", "#888888", font="Special", fmt="repeat %s"),
        "result": _comp(font="Result"),
        "roll": _comp("#00fa92", "green", font="Normal", fmt="{%s}"),
        "section": _comp(font="Title"),
        "separator": _comp(font="Normal", fmt="="),
        "sf": _comp("#aaaaaa", "#888888", font="Special"),
        "short": _comp("red", "red", font="Special", fmt=" missed DC by %s"),
        "stats": _comp("#aaaaaa", "#888888", font="Tiny"),
        "subsection": _comp(font="Subtitle"),
        "subtotal": _comp("#00fa92", "green", font="Normal", fmt="(%s)"),
        "success": _comp("#00fa92", "green", font="Important", fmt="(%s) "),
        "system": _comp("cyan", "blue", font="System"),
        "timestamp": _comp("#888888", "#888888", font="Tiny"),
        "title": _comp("#aaaaaa", "#ffffff", "#000044", "#c7c0ae", font="Normal"),
        "to": _comp("red", "red", font="Special"),
        "total": _comp("#aaaaaa", "#888888", font="Special", fmt="total %s"),
        "until": _comp("#aaaaaa", "#888888", font="Special", fmt="until %s"),
        "worst": _comp("#aaaaaa", "#888888", font="Special", fmt=" worst of %s"),
    }

    return {
        "clocks": clocks,
        "markers": {},
        "characters": {
            "pushpin": {"name": "pin"},
            "delmsg": {"name": "del"},
            "localpin": {"name": "up-arrow"},
        },
        "dialogs": dialogs,
        "dierolls": {
            "compact_recents": False,
            "components": components,
        },
    }


def empty_server_profile(name: str) -> dict[str, Any]:
    """Return a default server profile dictionary with the given `name`."""
    return {
        "name": name,
        "host": "",
        "port": 2323,
        "username": "",
        "password": "",
        "curl_proxy": "",
        "blur_all": False,
        "blur_pct": 0,
        "suppress_chat": False,
        "chat_limit": 500,
        "chat_log": "",
        "curl_server": "",
        "update_url": "",
        "module_id": "",
        "server_mkdir": "",
        "nc_path": search_in_path("nc"),
        "scp_path": search_in_path("scp"),
        "scp_dest": "",
        "scp_server": "",
        "scp_proxy": "",
        "ssh_path": search_in_path("ssh"),
    }


def default_preferences() -> dict[str, Any]:
    """Return the default preferences dictionary."""
    return {
        "GMA_Mapper_preferences_version": CURRENT_FILE_VERSION,
        "animate": False,
        "button_size": "small",
        "chat_timestamp": True,
        "colorize_die_rolls": True,
        "a11y": {"colorize_die_labels": True},
        "markup_enabled": True,
        "curl_path": search_in_path("curl"),
        "curl_insecure": False,
        "current_profile": "offline",
        "dark": False,
        "debug_level": 0,
        "debug_proto": False,
        "flash_updates": False,
        "guide_lines": {
            "major": {"interval": 0, "offsets": {"x": 0, "y": 0}},
            "minor": {"interval": 0, "offsets": {"x": 0, "y": 0}},
        },
        "image_format": "png",
        "keep_tools": False,
        "menu_button": False,
        "never_animate": False,
        "preload": False,
        "profiles": [empty_server_profile("offline")],
        "fonts": default_fonts(),
        "scaling": 1.0,
        "show_timers": "mine",
        "styles": default_styles(),
        "suppress_aka": False,
        "not_playing": False,
        "no_dice": False,
        "no_ondeck_audio": False,
        "no_sfx": False,
    }


def fix_missing(prefs: dict[str, Any]) -> dict[str, Any]:
    """Populate missing style, font, scaling, guide_lines, or server profile fields in `prefs` in-place.

    Ensures all sub-objects expected by Tcl's `::gmaprofile::load`, `::gmaprofile::editor`, and
    `ApplyPreferences` (`::gmautil::dassign`) are present with their nested keys so `_encode_payload_dict`
    always emits the required JSON objects (even when empty `{}`).
    """
    d_prefs = default_preferences()
    for top_key, top_val in d_prefs.items():
        if top_key not in prefs:
            prefs[top_key] = copy.deepcopy(top_val)

    d_styles = default_styles()
    if not isinstance(prefs.get("styles"), dict):
        prefs["styles"] = {}
    styles = prefs["styles"]

    # dierolls
    if not isinstance(styles.get("dierolls"), dict):
        styles["dierolls"] = {}
    dierolls = styles["dierolls"]
    if not isinstance(dierolls.get("components"), dict):
        dierolls["components"] = {}
    comps = dierolls["components"]
    for stylename, styledata in d_styles["dierolls"]["components"].items():
        if stylename not in comps or not isinstance(comps[stylename], dict) or not comps[stylename]:
            comps[stylename] = copy.deepcopy(styledata)
        else:
            c_entry = comps[stylename]
            for color_field in ("fg", "bg"):
                if not isinstance(c_entry.get(color_field), dict) or not c_entry[color_field]:
                    c_entry[color_field] = {"dark": "", "light": ""}
                else:
                    c_entry[color_field].setdefault("dark", "")
                    c_entry[color_field].setdefault("light", "")
            for field_name in ("overstrike", "underline", "font", "format"):
                c_entry.setdefault(field_name, styledata[field_name])
    if "compact_recents" not in dierolls:
        dierolls["compact_recents"] = False

    # dialogs
    if not isinstance(styles.get("dialogs"), dict):
        styles["dialogs"] = {}
    dialogs = styles["dialogs"]
    for stylename, styledata in d_styles["dialogs"].items():
        if stylename not in dialogs or not isinstance(dialogs[stylename], dict) or not dialogs[stylename]:
            dialogs[stylename] = copy.deepcopy(styledata)
        else:
            dialogs[stylename].setdefault("dark", styledata["dark"])
            dialogs[stylename].setdefault("light", styledata["light"])

    # clocks
    if not isinstance(styles.get("clocks"), dict):
        styles["clocks"] = {}
    clocks = styles["clocks"]
    for stylename, styledata in d_styles["clocks"].items():
        if stylename not in clocks or not clocks[stylename]:
            clocks[stylename] = copy.deepcopy(styledata)
        elif isinstance(styledata, dict):
            if not isinstance(clocks[stylename], dict):
                clocks[stylename] = copy.deepcopy(styledata)
            else:
                clocks[stylename].setdefault("dark", styledata["dark"])
                clocks[stylename].setdefault("light", styledata["light"])

    # characters
    if not isinstance(styles.get("characters"), dict):
        styles["characters"] = {}
    chars = styles["characters"]
    for symbol, desc in d_styles["characters"].items():
        if symbol not in chars or not isinstance(chars[symbol], dict) or not chars[symbol]:
            chars[symbol] = copy.deepcopy(desc)

    # markers
    if not isinstance(styles.get("markers"), dict):
        styles["markers"] = {}

    # fonts
    d_fonts = default_fonts()
    if not isinstance(prefs.get("fonts"), dict):
        prefs["fonts"] = {}
    fonts = prefs["fonts"]
    for font_name, font_dict in d_fonts.items():
        if font_name not in fonts or not isinstance(fonts[font_name], dict) or not fonts[font_name]:
            fonts[font_name] = copy.deepcopy(font_dict)
    for f_entry in fonts.values():
        if isinstance(f_entry, dict) and "size" in f_entry:
            try:
                f_entry["size"] = int(round(float(f_entry["size"])))
            except (ValueError, TypeError):
                f_entry["size"] = 12

    # a11y
    if not isinstance(prefs.get("a11y"), dict):
        prefs["a11y"] = {}
    a11y = prefs["a11y"]
    if "colorize_die_labels" not in a11y:
        a11y["colorize_die_labels"] = False

    # guide_lines (required by Tcl's ApplyPreferences and ::gmaprofile::editor via ::gmautil::dassign)
    if not isinstance(prefs.get("guide_lines"), dict):
        prefs["guide_lines"] = copy.deepcopy(d_prefs["guide_lines"])
    guides = prefs["guide_lines"]
    for tier in ("major", "minor"):
        if not isinstance(guides.get(tier), dict):
            guides[tier] = {"interval": 0, "offsets": {"x": 0, "y": 0}}
        else:
            guides[tier]["interval"] = int(guides[tier].get("interval", 0) or 0)
            if not isinstance(guides[tier].get("offsets"), dict):
                guides[tier]["offsets"] = {"x": 0, "y": 0}
            else:
                guides[tier]["offsets"]["x"] = int(guides[tier]["offsets"].get("x", 0) or 0)
                guides[tier]["offsets"]["y"] = int(guides[tier]["offsets"].get("y", 0) or 0)

    # profiles
    if not isinstance(prefs.get("profiles"), list) or not prefs["profiles"]:
        prefs["profiles"] = [empty_server_profile("offline")]
    else:
        for i, prof in enumerate(prefs["profiles"]):
            if not isinstance(prof, dict):
                prefs["profiles"][i] = empty_server_profile("offline")
            else:
                defaults = empty_server_profile(str(prof.get("name", "offline") or "offline"))
                for k, v in defaults.items():
                    prof.setdefault(k, v)

    if not prefs.get("current_profile"):
        prefs["current_profile"] = str(prefs["profiles"][0].get("name", "offline"))
    if not prefs.get("button_size"):
        prefs["button_size"] = "small"
    if not prefs.get("image_format"):
        prefs["image_format"] = "png"
    if not prefs.get("scaling"):
        prefs["scaling"] = 1.0
    if not prefs.get("show_timers"):
        prefs["show_timers"] = "mine"

    return prefs


def save(filename: str | Path, data: dict[str, Any]) -> None:
    """Save `data` to `filename` in preferences v15 JSON format."""
    out_data = fix_missing(copy.deepcopy(data))
    out_data["GMA_Mapper_preferences_version"] = CURRENT_FILE_VERSION
    encoded = _encode_payload_dict(out_data, FILE_FORMAT)
    path = Path(filename)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(encoded, indent=4) + "\n", encoding="utf-8")


def load(filename: str | Path) -> dict[str, Any]:
    """Load preferences from `filename` (supporting v1-v15) and normalize missing fields."""
    path = Path(filename)
    raw = json.loads(path.read_text(encoding="utf-8"))
    data = _construct(raw, FILE_FORMAT)
    v = data.get("GMA_Mapper_preferences_version", 0)
    if v < MINIMUM_FILE_VERSION:
        raise ValueError(
            f"{filename} is version {v}, below minimum supported version {MINIMUM_FILE_VERSION}"
        )
    if v > MAXIMUM_FILE_VERSION:
        raise ValueError(
            f"{filename} is version {v}, above maximum supported version {MAXIMUM_FILE_VERSION}"
        )
    fix_missing(data)
    return data


def find_server_index(prefs: dict[str, Any], servername: str) -> int:
    """Return index of `servername` in `prefs['profiles']`, or -1 if not found."""
    for i, prof in enumerate(prefs.get("profiles", [])):
        if prof.get("name") == servername:
            return i
    return -1


def list_server_names(prefs: dict[str, Any]) -> list[str]:
    """Return list of server profile names in `prefs`."""
    return [str(p.get("name", "")) for p in prefs.get("profiles", [])]


def default_preferences_path() -> Path:
    """Return the standard `~/.gma/mapper/preferences.json` path."""
    return Path.home() / ".gma" / "mapper" / "preferences.json"

