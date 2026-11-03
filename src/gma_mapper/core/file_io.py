"""GMA Mapper map file (v16-v24) and die-roll preset file (v1-v2) I/O.

Ported from bin/gmafile.tcl.
"""

from __future__ import annotations

import json
import re
import time
from pathlib import Path
from typing import Any, TextIO

from gma_mapper.net.protocol import (
    MESSAGE_PAYLOAD,
    ObjTypeToGMAType,
    _construct,
    _encode_payload_dict,
    to_enum,
)

VERSION: int = 24
MIN_VERSION: int = 16
MAX_VERSION: int = 24

DICE_VERSION: int = 2
MIN_DICE_VERSION: int = 1
MAX_DICE_VERSION: int = 2

_POINT_LIST_TYPE = ("a", {"X": "f", "Y": "f"})

DATA_PAYLOAD: dict[str, dict[str, Any]] = {
    "__META__": {"Timestamp": "i", "DateTime": "s", "Comment": "s", "Location": "s"},
    "__DMETA__": {"Timestamp": "i", "DateTime": "s", "Comment": "s"},
    "ARC": {
        "ArcMode": "i",
        "Start": "f",
        "Extent": "f",
        "ID": "s",
        "X": "f",
        "Y": "f",
        "Points": _POINT_LIST_TYPE,
        "Z": "i",
        "Line": "s",
        "Stipple": "s",
        "Fill": "s",
        "Width": "i",
        "Layer": "s",
        "Level": "i",
        "Group": "s",
        "Dash": "i",
        "Hidden": "?",
        "Locked": "?",
    },
    "CIRC": {
        "ArcMode": "i",
        "Start": "f",
        "Extent": "f",
        "ID": "s",
        "X": "f",
        "Y": "f",
        "Points": _POINT_LIST_TYPE,
        "Z": "i",
        "Line": "s",
        "Stipple": "s",
        "Fill": "s",
        "Width": "i",
        "Layer": "s",
        "Level": "i",
        "Group": "s",
        "Dash": "i",
        "Hidden": "?",
        "Locked": "?",
    },
    "CREATURE": dict(MESSAGE_PAYLOAD["PS"]),
    "IMG": dict(MESSAGE_PAYLOAD["AI"]),
    "LINE": {
        "Arrow": "i",
        "ID": "s",
        "X": "f",
        "Y": "f",
        "Points": _POINT_LIST_TYPE,
        "Z": "i",
        "Line": "s",
        "Stipple": "s",
        "Fill": "s",
        "Width": "i",
        "Layer": "s",
        "Level": "i",
        "Group": "s",
        "Dash": "i",
        "Hidden": "?",
        "Locked": "?",
    },
    "MAP": {"File": "s", "IsLocalFile": "?", "CacheOnly": "?", "Merge": "?"},
    "POLY": {
        "Spline": "i",
        "Join": "i",
        "ID": "s",
        "X": "f",
        "Y": "f",
        "Points": _POINT_LIST_TYPE,
        "Z": "i",
        "Line": "s",
        "Stipple": "s",
        "Fill": "s",
        "Width": "i",
        "Layer": "s",
        "Level": "i",
        "Group": "s",
        "Dash": "i",
        "Hidden": "?",
        "Locked": "?",
    },
    "RECT": {
        "ID": "s",
        "X": "f",
        "Y": "f",
        "Points": _POINT_LIST_TYPE,
        "Z": "i",
        "Line": "s",
        "Stipple": "s",
        "Fill": "s",
        "Width": "i",
        "Layer": "s",
        "Level": "i",
        "Group": "s",
        "Dash": "i",
        "Hidden": "?",
        "Locked": "?",
    },
    "SAOE": {
        "AoEShape": "i",
        "ID": "s",
        "X": "f",
        "Y": "f",
        "Points": _POINT_LIST_TYPE,
        "Z": "i",
        "Line": "s",
        "Fill": "s",
        "Width": "i",
        "Layer": "s",
        "Level": "i",
        "Group": "s",
        "Dash": "i",
        "Hidden": "?",
        "Locked": "?",
    },
    "TEXT": {
        "Text": "s",
        "Font": ("o", {"Family": "s", "Size": "f", "Weight": "i", "Slant": "i"}),
        "Anchor": "i",
        "ID": "s",
        "X": "f",
        "Y": "f",
        "Points": _POINT_LIST_TYPE,
        "Z": "i",
        "Line": "s",
        "Stipple": "s",
        "Fill": "s",
        "Width": "i",
        "Layer": "s",
        "Level": "i",
        "Group": "s",
        "Dash": "i",
        "Hidden": "?",
        "Locked": "?",
    },
    "TILE": {
        "Image": "s",
        "BBHeight": "f",
        "BBWidth": "f",
        "ID": "s",
        "X": "f",
        "Y": "f",
        "Points": _POINT_LIST_TYPE,
        "Z": "i",
        "Line": "s",
        "Fill": "s",
        "Width": "i",
        "Layer": "s",
        "Level": "i",
        "Group": "s",
        "Dash": "i",
        "Hidden": "?",
        "Locked": "?",
    },
    "PRESET": {"Name": "s", "Description": "s", "DieRollSpec": "s"},
}


def parse_tcl_list(s: str) -> list[str]:
    """Parse a Tcl list string into its top-level string elements."""
    res: list[str] = []
    n = len(s)
    i = 0
    while i < n:
        while i < n and s[i].isspace():
            i += 1
        if i >= n:
            break
        if s[i] == "{":
            depth = 1
            i += 1
            start = i
            while i < n and depth > 0:
                if s[i] == "\\":
                    i += 2
                    continue
                if s[i] == "{":
                    depth += 1
                elif s[i] == "}":
                    depth -= 1
                i += 1
            if depth != 0:
                raise ValueError(f"Unmatched '{{' in Tcl list: {s!r}")
            res.append(s[start : i - 1])
        elif s[i] == '"':
            i += 1
            buf: list[str] = []
            while i < n and s[i] != '"':
                if s[i] == "\\" and i + 1 < n:
                    i += 1
                    ch = s[i]
                    if ch == "n":
                        buf.append("\n")
                    elif ch == "t":
                        buf.append("\t")
                    elif ch == "r":
                        buf.append("\r")
                    else:
                        buf.append(ch)
                else:
                    buf.append(s[i])
                i += 1
            if i >= n or s[i] != '"':
                raise ValueError(f'Unmatched \'"\' in Tcl list: {s!r}')
            i += 1
            res.append("".join(buf))
        else:
            buf = []
            while i < n and not s[i].isspace():
                if s[i] == "\\" and i + 1 < n:
                    i += 1
                buf.append(s[i])
                i += 1
            res.append("".join(buf))
    return res


def _format_pretty_json(input_dict: dict[str, Any], schema: dict[str, Any]) -> str:
    """Encode a record dictionary as indented JSON for map/dice files."""
    data = _encode_payload_dict(input_dict, schema)
    return json.dumps(data, indent=4)


def _format_timestamp(ts: int) -> str:
    return time.strftime("%d-%b-%Y %H:%M:%S", time.localtime(ts))


def save_to_file(
    f: TextIO | str | Path,
    objlist: tuple[dict[str, Any], list[tuple[str, dict[str, Any]]]] | list[Any],
) -> None:
    """Save `(meta, [(record_type, record_data), ...])` to a version 24 `.map` file."""
    if isinstance(f, (str, Path)):
        with open(f, "w", encoding="utf-8", newline="\n") as fp:
            save_to_file(fp, objlist)
        return

    meta = dict(objlist[0] or {})
    objs = objlist[1]
    if "Timestamp" not in meta or not meta["Timestamp"]:
        now = int(time.time())
        meta["Timestamp"] = now
        meta["DateTime"] = _format_timestamp(now)
    elif "DateTime" not in meta or not meta["DateTime"]:
        meta["DateTime"] = _format_timestamp(int(meta["Timestamp"]))

    f.write(f"__MAPPER__:{VERSION}\n")
    f.write(f"\u00ab__META__\u00bb {_format_pretty_json(meta, DATA_PAYLOAD['__META__'])}\n")
    for record_type, record_data in objs:
        if record_type not in DATA_PAYLOAD:
            raise ValueError(f"unable to save record of type '{record_type}' to map file")
        f.write(
            f"\u00ab{record_type}\u00bb {_format_pretty_json(record_data, DATA_PAYLOAD[record_type])}\n"
        )
    f.write("\u00ab__EOF__\u00bb\n")


def save_arrays_to_file(
    f: TextIO | str | Path,
    meta: dict[str, Any],
    elements: dict[str, dict[str, Any]],
    elementtypes: dict[str, str],
    creatures: dict[str, dict[str, Any]],
    imagemap: dict[str, str] | None = None,
    lock_objects: bool = False,
) -> None:
    """Save map element and creature dicts to a `.map` file."""
    objlist: list[tuple[str, dict[str, Any]]] = []
    imap = imagemap or {}

    for obj_id, d in elements.items():
        if obj_id not in elementtypes:
            continue
        try:
            ot = ObjTypeToGMAType(elementtypes[obj_id])
        except ValueError:
            continue
        rec = dict(d)
        if lock_objects:
            rec["Locked"] = True
        objlist.append((ot, rec))

    for mob_id, d in creatures.items():
        rec = dict(d)
        name = rec.get("Name", "")
        if name and name in imap:
            rec["Name"] = f"{imap[name]}={name}"
        objlist.append(("CREATURE", rec))

    save_to_file(f, (meta, objlist))


def load_from_file(
    f: TextIO | str | Path,
) -> tuple[dict[str, Any], list[tuple[str, dict[str, Any]]]]:
    """Load a `.map` file (versions 16..24) and return `(meta, [(record_type, record_data), ...])`."""
    if isinstance(f, (str, Path)):
        with open(f, "r", encoding="utf-8") as fp:
            return load_from_file(fp)

    first_line = f.readline()
    if not first_line:
        raise ValueError("unable to read from map file")
    first_line_stripped = first_line.rstrip("\r\n")
    m = re.match(r"^__MAPPER__:([0-9]+)\s*(.*)$", first_line_stripped)
    if not m:
        raise ValueError("map file does not begin with the required __MAPPER__ header line")

    vid = int(m.group(1))
    oldmeta_str = m.group(2)
    if vid > MAX_VERSION:
        raise ValueError(
            f"map file is version {vid} which is newer than this version of the mapper can read"
        )
    if vid < MIN_VERSION:
        raise ValueError(
            f"map file is version {vid} which is older than this mapper's minimum supported version ({MIN_VERSION})"
        )
    if vid < 20:
        parsed_old = parse_tcl_list(oldmeta_str)
        oldmeta_arg = parsed_old[0] if parsed_old else ""
        return load_legacy_map_file(f, vid, oldmeta_arg)

    meta: dict[str, Any] = {}
    objlist: list[tuple[str, dict[str, Any]]] = []
    record_type = ""
    json_chunks: list[str] = []

    def _flush_record() -> None:
        nonlocal meta, record_type, json_chunks
        if not record_type:
            return
        if record_type not in DATA_PAYLOAD:
            raise ValueError(f"map file contains unrecognized record type {record_type}")
        raw_json = "\n".join(json_chunks)
        parsed = json.loads(raw_json) if raw_json.strip() else {}
        data = _construct(parsed, DATA_PAYLOAD[record_type])
        if record_type == "__META__":
            meta = data
        else:
            objlist.append((record_type, data))
        record_type = ""
        json_chunks = []

    for raw_line in f:
        v = raw_line.rstrip("\r\n")
        if not v and not record_type:
            continue
        if v.startswith("\u00ab"):
            _flush_record()
            if v == "\u00ab__EOF__\u00bb":
                return (meta, objlist)
            rec_match = re.match(r"^\u00ab(.*?)\u00bb (.+)$", v)
            if not rec_match:
                raise ValueError("invalid map file format: unexpected data")
            record_type = rec_match.group(1)
            json_chunks = [rec_match.group(2)]
        else:
            if not record_type:
                raise ValueError("invalid map file format: unexpected data")
            json_chunks.append(v)

    raise ValueError("invalid map file: unexpected end of file")


def load_legacy_map_file(
    f: TextIO, vid: int, oldmeta: str
) -> tuple[dict[str, Any], list[tuple[str, dict[str, Any]]]]:
    """Load a pre-version-20 Tcl-formatted `.map` file."""
    meta: dict[str, Any] = {"FileVersion": vid}
    if vid >= 12:
        parts = parse_tcl_list(oldmeta)
        if len(parts) < 2:
            raise ValueError(
                f"Map file is a version {vid} file, but the metadata field is incorrect. Not reading this file."
            )
        ts_parts = parse_tcl_list(parts[1])
        if len(ts_parts) < 2:
            meta["Timestamp"] = int(parts[1]) if parts[1].isdigit() else 0
            meta["DateTime"] = parts[1]
        else:
            meta["Timestamp"] = int(ts_parts[0]) if ts_parts[0].isdigit() else 0
            meta["DateTime"] = ts_parts[1]
        meta["Comment"] = parts[0]
        meta["Location"] = parts[0]
    else:
        raise ValueError("Map file has no metadata. Not loaded since it's probably in an old format.")

    file_lines = [line.rstrip("\r\n") for line in f]
    return load_legacy_map_data(file_lines, meta)


def load_legacy_map_data(
    vlist: list[str], meta: dict[str, Any]
) -> tuple[dict[str, Any], list[tuple[str, dict[str, Any]]]]:
    """Parse legacy map lines into `(meta, upgraded_elements)`."""
    imagedict: dict[str, dict[str, str]] = {}
    file_data: list[tuple[str, Any]] = []

    for v in vlist:
        if not v.strip():
            continue
        if v.startswith("__MAPPER__:"):
            raise ValueError("Metadata line must appear first in map file, not later.")
        tokens = parse_tcl_list(v)
        ll = len(tokens)
        if ll == 4 and tokens[0] == "I":
            _, image_id, image_zoom, image_filename = tokens
            imagedict.setdefault(image_id, {})[image_zoom] = image_filename
        elif ll == 2 and tokens[0] == "F":
            file_data.append(
                (
                    "MAP",
                    _construct(
                        {
                            "File": tokens[1],
                            "IsLocalFile": False,
                            "CacheOnly": True,
                            "Merge": False,
                        },
                        DATA_PAYLOAD["MAP"],
                    ),
                )
            )
        else:
            file_data.append(("RAW", tokens))

    for image_id, size_map in imagedict.items():
        sizes: list[dict[str, Any]] = []
        for image_size, filename in size_map.items():
            if filename.startswith("@"):
                sizes.append(
                    {
                        "File": filename[1:],
                        "ImageData": b"",
                        "IsLocalFile": False,
                        "Zoom": float(image_size),
                    }
                )
            else:
                sizes.append(
                    {
                        "File": filename,
                        "ImageData": b"",
                        "IsLocalFile": True,
                        "Zoom": float(image_size),
                    }
                )
        file_data.append(
            (
                "IMG",
                _construct(
                    {"Name": image_id, "Animation": {}, "Sizes": sizes},
                    DATA_PAYLOAD["IMG"],
                ),
            )
        )

    return (meta, upgrade_elements(file_data))


def _require_arr(arr: dict[str, str], obj_id: str, *attrs: str) -> None:
    for a in attrs:
        if f"{a}:{obj_id}" not in arr:
            raise ValueError(f"object {obj_id} missing required attribute {a}")


def _default_arr(arr: dict[str, str], obj_id: str, value: str, *attrs: str) -> None:
    for a in attrs:
        key = f"{a}:{obj_id}"
        if key not in arr:
            arr[key] = value


def upgrade_elements(filedata: list[tuple[str, Any]]) -> list[tuple[str, dict[str, Any]]]:
    """Convert legacy `RAW` attribute tuples into structured v20+ element records."""
    old_objs: dict[str, str] = {}
    old_mobs: dict[str, str] = {}
    new_filedata: list[tuple[str, dict[str, Any]]] = []

    for element_type, element_data in filedata:
        if element_type == "RAW":
            tokens = parse_tcl_list(element_data) if isinstance(element_data, str) else list(element_data)
            if not tokens:
                continue
            if tokens[0] in ("P", "M"):
                if len(tokens) >= 3:
                    old_mobs[tokens[1]] = tokens[2]
            else:
                if len(tokens) >= 2:
                    old_objs[tokens[0]] = tokens[1]
        else:
            new_filedata.append((element_type, element_data))

    mob_ids = [k[5:] for k in old_mobs if k.startswith("NAME:")]
    for mob_id in mob_ids:
        _require_arr(old_mobs, mob_id, "NAME")
        _default_arr(
            old_mobs,
            mob_id,
            "0",
            "GX",
            "GY",
            "SKIN",
            "ELEV",
            "REACH",
            "KILLED",
            "DIM",
        )
        _default_arr(
            old_mobs,
            mob_id,
            "",
            "HEALTH",
            "MOVEMODE",
            "COLOR",
            "NOTE",
            "SKIN",
            "SKINSIZE",
            "SIZE",
            "STATUSLIST",
            "AOE",
            "TYPE",
        )

        health_raw = old_mobs[f"HEALTH:{mob_id}"]
        if not health_raw:
            health: dict[str, Any] = {}
        else:
            hp_parts = parse_tcl_list(health_raw)
            while len(hp_parts) < 8:
                hp_parts.append("0")
            health = {
                "MaxHP": hp_parts[0],
                "LethalDamage": hp_parts[1],
                "NonLethalDamage": hp_parts[2],
                "Con": hp_parts[3],
                "IsFlatFooted": hp_parts[4],
                "IsStable": hp_parts[5],
                "Condition": hp_parts[6],
                "HPBlur": hp_parts[7],
            }

        aoe_raw = old_mobs[f"AOE:{mob_id}"]
        if not aoe_raw:
            aoe: dict[str, Any] = {}
        else:
            aoe_parts = parse_tcl_list(aoe_raw)
            aoe = {
                "Radius": aoe_parts[0] if len(aoe_parts) > 0 else 0.0,
                "Color": aoe_parts[1] if len(aoe_parts) > 1 else "",
            }

        skin_size_list = parse_tcl_list(old_mobs[f"SKINSIZE:{mob_id}"])
        status_list = parse_tcl_list(old_mobs[f"STATUSLIST:{mob_id}"])

        creature_dict = _construct(
            {
                "ID": mob_id,
                "Name": old_mobs[f"NAME:{mob_id}"],
                "Health": health,
                "Gx": old_mobs[f"GX:{mob_id}"],
                "Gy": old_mobs[f"GY:{mob_id}"],
                "Skin": old_mobs[f"SKIN:{mob_id}"],
                "SkinSize": skin_size_list,
                "Elev": old_mobs[f"ELEV:{mob_id}"],
                "Color": old_mobs[f"COLOR:{mob_id}"],
                "Note": old_mobs[f"NOTE:{mob_id}"],
                "Size": old_mobs[f"SIZE:{mob_id}"],
                "DispSize": old_mobs[f"SIZE:{mob_id}"],
                "StatusList": status_list,
                "AoE": aoe,
                "MoveMode": to_enum("MoveMode", old_mobs[f"MOVEMODE:{mob_id}"]),
                "Reach": old_mobs[f"REACH:{mob_id}"],
                "Killed": old_mobs[f"KILLED:{mob_id}"],
                "Dim": old_mobs[f"DIM:{mob_id}"],
                "CreatureType": to_enum("CreatureType", old_mobs[f"TYPE:{mob_id}"]),
            },
            DATA_PAYLOAD["CREATURE"],
        )
        new_filedata.append(("CREATURE", creature_dict))

    obj_ids = [k[5:] for k in old_objs if k.startswith("TYPE:")]
    for obj_id in obj_ids:
        _require_arr(old_objs, obj_id, "X", "Y", "Z")
        _default_arr(old_objs, obj_id, "0", "WIDTH", "HIDDEN", "LOCKED")
        _default_arr(
            old_objs,
            obj_id,
            "",
            "POINTS",
            "LINE",
            "FILL",
            "LAYER",
            "LEVEL",
            "GROUP",
            "DASH",
        )
        obj_type = old_objs[f"TYPE:{obj_id}"]

        if obj_type == "arc":
            _default_arr(old_objs, obj_id, "0", "START", "EXTENT")
            _default_arr(old_objs, obj_id, "", "ARCMODE")
        elif obj_type == "circ":
            pass
        elif obj_type == "line":
            _default_arr(old_objs, obj_id, "", "ARROW")
        elif obj_type == "poly":
            _default_arr(old_objs, obj_id, "0", "SPLINE")
            _default_arr(old_objs, obj_id, "", "JOIN")
        elif obj_type == "rect":
            pass
        elif obj_type == "saoe":
            _require_arr(old_objs, obj_id, "AOESHAPE")
        elif obj_type == "text":
            _require_arr(old_objs, obj_id, "TEXT", "FONT")
            _default_arr(old_objs, obj_id, "", "ANCHOR")
        elif obj_type == "tile":
            _default_arr(old_objs, obj_id, "0", "BBHEIGHT", "BBWIDTH")
            _default_arr(old_objs, obj_id, "", "IMAGE")
        else:
            raise ValueError(f"map element of unsupported type {obj_type}")

        pts_flat = parse_tcl_list(old_objs[f"POINTS:{obj_id}"])
        points = [
            {"X": pts_flat[i], "Y": pts_flat[i + 1]}
            for i in range(0, len(pts_flat) - 1, 2)
        ]

        element: dict[str, Any] = {
            "ID": obj_id,
            "X": old_objs[f"X:{obj_id}"],
            "Y": old_objs[f"Y:{obj_id}"],
            "Points": points,
            "Z": old_objs[f"Z:{obj_id}"],
            "Line": old_objs[f"LINE:{obj_id}"],
            "Fill": old_objs[f"FILL:{obj_id}"],
            "Width": old_objs[f"WIDTH:{obj_id}"],
            "Layer": old_objs[f"LAYER:{obj_id}"],
            "Level": old_objs[f"LEVEL:{obj_id}"],
            "Group": old_objs[f"GROUP:{obj_id}"],
            "Dash": to_enum("Dash", old_objs[f"DASH:{obj_id}"]),
            "Hidden": old_objs[f"HIDDEN:{obj_id}"],
            "Locked": old_objs[f"LOCKED:{obj_id}"],
        }

        if obj_type == "arc":
            element["ArcMode"] = to_enum("ArcMode", old_objs[f"ARCMODE:{obj_id}"])
            element["Start"] = old_objs[f"START:{obj_id}"]
            element["Extent"] = old_objs[f"EXTENT:{obj_id}"]
            new_filedata.append(("ARC", _construct(element, DATA_PAYLOAD["ARC"])))
        elif obj_type == "circ":
            new_filedata.append(("CIRC", _construct(element, DATA_PAYLOAD["CIRC"])))
        elif obj_type == "line":
            element["Arrow"] = to_enum("Arrow", old_objs[f"ARROW:{obj_id}"])
            new_filedata.append(("LINE", _construct(element, DATA_PAYLOAD["LINE"])))
        elif obj_type == "poly":
            element["Spline"] = old_objs[f"SPLINE:{obj_id}"]
            element["Join"] = to_enum("Join", old_objs[f"JOIN:{obj_id}"])
            new_filedata.append(("POLY", _construct(element, DATA_PAYLOAD["POLY"])))
        elif obj_type == "rect":
            new_filedata.append(("RECT", _construct(element, DATA_PAYLOAD["RECT"])))
        elif obj_type == "saoe":
            element["AoEShape"] = to_enum("AoEShape", old_objs[f"AOESHAPE:{obj_id}"])
            new_filedata.append(("SAOE", _construct(element, DATA_PAYLOAD["SAOE"])))
        elif obj_type == "text":
            font_tokens = parse_tcl_list(old_objs[f"FONT:{obj_id}"])
            if font_tokens:
                first_sub = parse_tcl_list(font_tokens[0])
                if len(first_sub) >= 2:
                    family, size = first_sub[0], first_sub[1]
                    rest_opts = font_tokens[1:]
                else:
                    family = font_tokens[0]
                    size = font_tokens[1] if len(font_tokens) > 1 else "12"
                    rest_opts = font_tokens[2:]
            else:
                family, size, rest_opts = "Helvetica", "12", []
            weight = 1 if "bold" in rest_opts else 0
            slant = 1 if "italic" in rest_opts else 0
            element["Text"] = old_objs[f"TEXT:{obj_id}"]
            element["Font"] = {
                "Family": family,
                "Size": size,
                "Weight": weight,
                "Slant": slant,
            }
            element["Anchor"] = to_enum("Anchor", old_objs.get(f"ANCHOR:{obj_id}", ""))
            new_filedata.append(("TEXT", _construct(element, DATA_PAYLOAD["TEXT"])))
        elif obj_type == "tile":
            element["Image"] = old_objs[f"IMAGE:{obj_id}"]
            element["BBHeight"] = old_objs[f"BBHEIGHT:{obj_id}"]
            element["BBWidth"] = old_objs[f"BBWIDTH:{obj_id}"]
            new_filedata.append(("TILE", _construct(element, DATA_PAYLOAD["TILE"])))

    return new_filedata


def save_dice_presets_to_file(
    f: TextIO | str | Path,
    objlist: tuple[dict[str, Any], list[dict[str, Any]]] | list[Any],
) -> None:
    """Save `(meta, [preset_dict, ...])` to a version 2 `.dice` file."""
    if isinstance(f, (str, Path)):
        with open(f, "w", encoding="utf-8", newline="\n") as fp:
            save_dice_presets_to_file(fp, objlist)
        return

    meta = dict(objlist[0] or {})
    presets = objlist[1]
    if "Timestamp" not in meta or not meta["Timestamp"]:
        now = int(time.time())
        meta["Timestamp"] = now
        meta["DateTime"] = _format_timestamp(now)
    elif "DateTime" not in meta or not meta["DateTime"]:
        meta["DateTime"] = _format_timestamp(int(meta["Timestamp"]))

    f.write(f"__DICE__:{DICE_VERSION}\n")
    f.write(f"\u00ab__META__\u00bb {_format_pretty_json(meta, DATA_PAYLOAD['__DMETA__'])}\n")
    for r in presets:
        f.write(f"\u00abPRESET\u00bb {_format_pretty_json(r, DATA_PAYLOAD['PRESET'])}\n")
    f.write("\u00ab__EOF__\u00bb\n")


def load_dice_presets_from_file(
    f: TextIO | str | Path,
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    """Load a `.dice` file (versions 1..2) and return `(meta, [preset_dict, ...])`."""
    if isinstance(f, (str, Path)):
        with open(f, "r", encoding="utf-8") as fp:
            return load_dice_presets_from_file(fp)

    first_line = f.readline()
    if not first_line:
        raise ValueError("unable to read from die roll preset file")
    first_line_stripped = first_line.rstrip("\r\n")
    m = re.match(r"^__DICE__:([0-9]+)\s*(.*)$", first_line_stripped)
    if not m:
        raise ValueError("file does not begin with the required __DICE__ header line")

    vid = int(m.group(1))
    oldmeta_str = m.group(2)
    if vid > MAX_DICE_VERSION:
        raise ValueError(
            f"die roll preset file is version {vid} which is newer than this version of the mapper can read"
        )
    if vid < MIN_DICE_VERSION:
        raise ValueError(
            f"die roll preset file is version {vid} which is older than this mapper's minimum supported version ({MIN_DICE_VERSION})"
        )
    if vid < 2:
        parsed_old = parse_tcl_list(oldmeta_str)
        oldmeta_arg = parsed_old[0] if parsed_old else ""
        return load_legacy_preset_file(f, vid, oldmeta_arg)

    meta: dict[str, Any] = {}
    presets: list[dict[str, Any]] = []
    record_type = ""
    json_chunks: list[str] = []

    def _flush_record() -> None:
        nonlocal meta, record_type, json_chunks
        if not record_type:
            return
        raw_json = "\n".join(json_chunks)
        parsed = json.loads(raw_json) if raw_json.strip() else {}
        if record_type == "__META__":
            meta = _construct(parsed, DATA_PAYLOAD["__DMETA__"])
        elif record_type == "PRESET":
            presets.append(_construct(parsed, DATA_PAYLOAD["PRESET"]))
        else:
            raise ValueError(
                f"die roll preset file contains unrecognized record type {record_type}"
            )
        record_type = ""
        json_chunks = []

    for raw_line in f:
        v = raw_line.rstrip("\r\n")
        if not v and not record_type:
            continue
        if v.startswith("\u00ab"):
            _flush_record()
            if v == "\u00ab__EOF__\u00bb":
                meta["FileVersion"] = vid
                return (meta, presets)
            rec_match = re.match(r"^\u00ab(.*?)\u00bb (.+)$", v)
            if not rec_match:
                raise ValueError("invalid map file format: unexpected data")
            record_type = rec_match.group(1)
            json_chunks = [rec_match.group(2)]
        else:
            if not record_type:
                raise ValueError("invalid map file format: unexpected data")
            json_chunks.append(v)

    raise ValueError("invalid die roll preset file: unexpected end of file")


def load_legacy_preset_file(
    f: TextIO, vid: int, oldmeta: str
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    """Load a version 1 Tcl-formatted `.dice` preset file."""
    meta: dict[str, Any] = {
        "FileVersion": vid,
        "Comment": "",
        "DateTime": "",
        "Timestamp": 0,
    }
    plist: list[dict[str, Any]] = []

    meta_parts = parse_tcl_list(oldmeta)
    if meta_parts:
        ts = int(meta_parts[0]) if meta_parts[0].isdigit() else 0
        meta["Timestamp"] = ts
        if len(meta_parts) > 1:
            meta["DateTime"] = meta_parts[1]
        else:
            meta["DateTime"] = _format_timestamp(ts)

    for raw_line in f:
        v = raw_line.rstrip("\r\n")
        if not v.strip():
            continue
        tokens = parse_tcl_list(v)
        if len(tokens) == 3:
            plist.append(
                {
                    "Name": tokens[0],
                    "Description": tokens[1],
                    "DieRollSpec": tokens[2],
                }
            )
        else:
            raise ValueError(f"Invalid line in legacy die-roll preset file: {v}")

    return (meta, plist)

