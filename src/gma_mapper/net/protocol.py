"""GMA Mapper JSON protocol (v400-428) codec, framing, batching, and auth.

Ported from bin/gmaproto.tcl.
"""

from __future__ import annotations

import base64
import hashlib
import json
import math
import struct
import uuid
from typing import Any

PROTOCOL: int = 428
MIN_PROTOCOL: int = 400
MAX_PROTOCOL: int = 428
MAX_MAX_PROTOCOL: int = 499
MAXIMUM_MESSAGE_LENGTH: int = 61440
FRAG_SIZE: int = 32768
MAX_AUTH_ITERATIONS: int = 1_000_000
MAX_BATCH_PARTS: int = 2048
MAX_CONCURRENT_BATCHES: int = 64

MESSAGE_MAP: dict[str, str] = {
    "add_audio": "AA",
    "add_image": "AI",
    "add_obj_attributes": "OA+",
    "adjust_view": "AV",
    "character_name": "AKA",
    "chat_message": "TO",
    "clear": "CLR",
    "clear_chat": "CC",
    "clear_from": "CLR@",
    "combat_mode": "CO",
    "comment": "//",
    "echo": "ECHO",
    "filter_audio": "AA/",
    "filter_images": "AI/",
    "load_from": "L",
    "load_arc": "LS-ARC",
    "load_circle": "LS-CIRC",
    "load_line": "LS-LINE",
    "load_polygon": "LS-POLY",
    "load_rectangle": "LS-RECT",
    "load_spell_area_of_effect": "LS-SAOE",
    "load_text": "LS-TEXT",
    "load_tile": "LS-TILE",
    "marco": "MARCO",
    "mark": "MARK",
    "place_someone": "PS",
    "query_image": "AI?",
    "query_audio": "AA?",
    "remove_obj_attributes": "OA-",
    "roll_result": "ROLL",
    "server_state": "Y2",
    "toolbar": "TB",
    "update_clock": "CS",
    "update_core_data": "CORE=",
    "update_core_index": "COREIDX=",
    "update_dice_presets": "DD=",
    "update_initiative_list": "IL",
    "update_obj_attributes": "OA",
    "update_peer_list": "CONN",
    "update_progress": "PROGRESS",
    "update_status_marker": "DSM",
    "update_turn": "I",
}

ALL_MESSAGES: list[str] = list(MESSAGE_MAP.values())

ENUM_ENCODINGS: dict[str, list[str]] = {
    "Dash": ["", "-", ",", ".", "-.", "-.."],
    "ArcMode": ["pieslice", "arc", "chord"],
    "Arrow": ["none", "first", "last", "both"],
    "Join": ["bevel", "miter", "round"],
    "AoEShape": ["cone", "radius", "ray"],
    "Weight": ["normal", "bold"],
    "Slant": ["roman", "italic"],
    "Anchor": ["center", "n", "s", "e", "w", "ne", "nw", "sw", "se"],
    "MoveMode": ["land", "burrow", "climb", "fly", "swim"],
    "CreatureType": ["unknown", "monster", "player"],
}

_HEALTH_PAYLOAD: dict[str, Any] = {
    "MaxHP": "i",
    "TmpHP": "i",
    "TmpDamage": "i",
    "LethalDamage": "i",
    "NonLethalDamage": "i",
    "Con": "i",
    "IsFlatFooted": "?",
    "IsStable": "?",
    "Condition": "s",
    "HPBlur": "i",
    "AC": "i",
    "FlatFootedAC": "i",
    "TouchAC": "i",
    "CMD": "i",
}

_CREATURE_PAYLOAD: dict[str, Any] = {
    "ID": "s",
    "Name": "s",
    "Health": ("o", _HEALTH_PAYLOAD),
    "Gx": "f",
    "Gy": "f",
    "Skin": "i",
    "SkinSize": "l",
    "PolyGM": "?",
    "Elev": "i",
    "Color": "s",
    "Note": "s",
    "Size": "s",
    "DispSize": "s",
    "StatusList": "l",
    "AoE": ("o", {"Radius": "f", "Color": "s"}),
    "MoveMode": "i",
    "Reach": "i",
    "Killed": "?",
    "Dim": "?",
    "CreatureType": "i",
    "Hidden": "?",
    "CustomReach": ("o", {"Enabled": "?", "Natural": "i", "Extended": "i"}),
    "Targets": "l",
    "TargetedModifiers": "TM",
}

_POINT_LIST_TYPE = ("a", {"X": "f", "Y": "f"})

MESSAGE_PAYLOAD: dict[str, dict[str, Any]] = {
    "AC": dict(_CREATURE_PAYLOAD),
    "ACCEPT": {"Messages": "l"},
    "AA": {"Name": "s", "Format": "s", "File": "s", "IsLocalFile": "?"},
    "AA?": {"Name": "s"},
    "AA/": {"Filter": "s", "KeepMatching": "?"},
    "AI": {
        "Name": "s",
        "Sizes": ("a", {"File": "s", "ImageData": "b", "IsLocalFile": "?", "Zoom": "f"}),
        "Animation": ("o", {"Frames": "i", "FrameSpeed": "i", "Loops": "i"}),
    },
    "AI?": {"Name": "s", "Sizes": ("a", {"Zoom": "f"})},
    "AI/": {"Filter": "s", "KeepMatching": "?"},
    "AKA": {"Names": "l", "User": "s", "NotPlaying": "?"},
    "ALLOW": {"Features": "l"},
    "AUTH": {"Client": "s", "Response": "b", "User": "s", "Platform": "s"},
    "AV": {"Grid": "s", "XView": "f", "YView": "f"},
    "BATCH": {"ID": "s", "Command": "s", "Part": "i", "Of": "i", "Data": "s", "Error": "s"},
    "CC": {
        "RequestedBy": "s",
        "DoSilently": "?",
        "Target": "i",
        "TargetMessages": "L",
        "MessageID": "i",
    },
    "CLR": {"ObjID": "s"},
    "CLR@": {"File": "s", "IsLocalFile": "?"},
    "CO": {"Enabled": "?"},
    "CORE": {"Type": "s", "Code": "s", "Name": "s", "RequestID": "s"},
    "CORE=": {
        "NoSuchEntry": "?",
        "IsHidden": "?",
        "IsLocal": "?",
        "Code": "s",
        "Name": "s",
        "Type": "s",
        "RequestID": "s",
        "Data": "d",
    },
    "CORE/": {"Filter": "s", "Type": "s", "IsHidden": "?", "InvertSelection": "?"},
    "COREIDX": {
        "Type": "s",
        "CodeRegex": "s",
        "NameRegex": "s",
        "Since": "s",
        "RequestID": "s",
    },
    "COREIDX=": {
        "RequestID": "s",
        "Type": "s",
        "IsDone": "?",
        "N": "i",
        "Of": "i",
        "Name": "s",
        "Code": "s",
    },
    "CONN": {
        "PeerList": (
            "a",
            {
                "Addr": "s",
                "User": "s",
                "Client": "s",
                "LastPolo": "f",
                "IsAuthenticated": "?",
                "IsMe": "?",
                "AKA": "l",
                "NotPlaying": "?",
            },
        )
    },
    "CS": {"Absolute": "i", "Relative": "i", "Running": "?"},
    "D": {
        "Recipients": "l",
        "ToAll": "?",
        "ToGM": "?",
        "RollSpec": "s",
        "RequestID": "s",
        "Targets": "l",
        "Type": "s",
        "For": "s",
    },
    "DD": {
        "Global": "?",
        "For": "s",
        "Presets": ("a", {"Name": "s", "Description": "s", "DieRollSpec": "s"}),
    },
    "DD+": {
        "Global": "?",
        "For": "s",
        "Presets": ("a", {"Name": "s", "Description": "s", "DieRollSpec": "s"}),
    },
    "DD/": {"Global": "?", "For": "s", "Filter": "s"},
    "DD=": {
        "Global": "?",
        "For": "s",
        "Presets": ("a", {"Global": "?", "Name": "s", "Description": "s", "DieRollSpec": "s"}),
        "DelegateFor": "l",
        "Delegates": "l",
    },
    "DDD": {"For": "s", "Delegates": "l"},
    "DENIED": {"Reason": "s"},
    "DR": {"For": "s", "Global": "?"},
    "DSM": {
        "Condition": "s",
        "Shape": "s",
        "Color": "s",
        "Description": "s",
        "Transparent": "?",
    },
    "ECHO": {"s": "s", "i": "i", "b": "?", "o": "d", "ReceivedTime": "s", "SentTime": "s"},
    "FAILED": {
        "IsError": "?",
        "IsDiscretionary": "?",
        "Command": "s",
        "Reason": "s",
        "RequestID": "s",
        "RequestedBy": "s",
        "RequestingClient": "s",
    },
    "GRANTED": {"User": "s"},
    "HPACK": {"RequestID": "s", "RequestingClient": "s", "RequestedBy": "s"},
    "HPREQ": {
        "Targets": "l",
        "Description": "s",
        "RequestID": "s",
        "RequestingClient": "s",
        "RequestedBy": "s",
        "Health": (
            "o",
            {
                "MaxHP": "i",
                "LethalDamage": "i",
                "NonLethalDamage": "i",
                "AC": "i",
                "FlatFootedAC": "i",
                "TouchAC": "i",
                "CMD": "i",
            },
        ),
        "TmpHP": ("o", {"TmpHP": "i", "TmpDamage": "i", "Expires": "s"}),
    },
    "I": {
        "ActorID": "s",
        "Hours": "i",
        "Minutes": "i",
        "Seconds": "i",
        "Rounds": "i",
        "Count": "i",
    },
    "IL": {
        "InitiativeList": (
            "a",
            {
                "Slot": "i",
                "CurrentHP": "i",
                "Name": "s",
                "IsHolding": "?",
                "HasReadiedAction": "?",
                "IsFlatFooted": "?",
            },
        )
    },
    "L": {"File": "s", "IsLocalFile": "?", "CacheOnly": "?", "Merge": "?"},
    "LS-ARC": {
        "ArcMode": "i",
        "Start": "f",
        "Extent": "f",
        "ID": "s",
        "X": "f",
        "Y": "f",
        "Points": _POINT_LIST_TYPE,
        "Z": "i",
        "Line": "s",
        "Fill": "s",
        "Stipple": "s",
        "Width": "i",
        "Layer": "s",
        "Level": "i",
        "Group": "s",
        "Dash": "i",
        "Hidden": "?",
        "Locked": "?",
    },
    "LS-CIRC": {
        "ArcMode": "i",
        "Start": "f",
        "Extent": "f",
        "ID": "s",
        "X": "f",
        "Y": "f",
        "Points": _POINT_LIST_TYPE,
        "Z": "i",
        "Line": "s",
        "Fill": "s",
        "Stipple": "s",
        "Width": "i",
        "Layer": "s",
        "Level": "i",
        "Group": "s",
        "Dash": "i",
        "Hidden": "?",
        "Locked": "?",
    },
    "LS-LINE": {
        "Arrow": "i",
        "ID": "s",
        "X": "f",
        "Y": "f",
        "Points": _POINT_LIST_TYPE,
        "Z": "i",
        "Line": "s",
        "Fill": "s",
        "Stipple": "s",
        "Width": "i",
        "Layer": "s",
        "Level": "i",
        "Group": "s",
        "Dash": "i",
        "Hidden": "?",
        "Locked": "?",
    },
    "LS-POLY": {
        "Spline": "i",
        "Join": "i",
        "ID": "s",
        "X": "f",
        "Y": "f",
        "Points": _POINT_LIST_TYPE,
        "Z": "i",
        "Line": "s",
        "Fill": "s",
        "Stipple": "s",
        "Width": "i",
        "Layer": "s",
        "Level": "i",
        "Group": "s",
        "Dash": "i",
        "Hidden": "?",
        "Locked": "?",
    },
    "LS-RECT": {
        "ID": "s",
        "X": "f",
        "Y": "f",
        "Points": _POINT_LIST_TYPE,
        "Z": "i",
        "Line": "s",
        "Fill": "s",
        "Stipple": "s",
        "Width": "i",
        "Layer": "s",
        "Level": "i",
        "Group": "s",
        "Dash": "i",
        "Hidden": "?",
        "Locked": "?",
    },
    "LS-SAOE": {
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
    "LS-TEXT": {
        "Text": "s",
        "Font": ("o", {"Family": "s", "Size": "f", "Weight": "i", "Slant": "i"}),
        "Anchor": "i",
        "ID": "s",
        "X": "f",
        "Y": "f",
        "Points": _POINT_LIST_TYPE,
        "Z": "i",
        "Line": "s",
        "Fill": "s",
        "Stipple": "s",
        "Width": "i",
        "Layer": "s",
        "Level": "i",
        "Group": "s",
        "Dash": "i",
        "Hidden": "?",
        "Locked": "?",
    },
    "LS-TILE": {
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
    "MARCO": {},
    "MARK": {"X": "f", "Y": "f"},
    "OA": {"ObjID": "s", "NewAttrs": "d"},
    "OA+": {"ObjID": "s", "AttrName": "s", "Values": "l"},
    "OA-": {"ObjID": "s", "AttrName": "s", "Values": "l"},
    "OK": {
        "Protocol": "i",
        "Challenge": "b",
        "ServerStarted": "s",
        "ServerActive": "s",
        "ServerTime": "s",
        "ServerVersion": "s",
        "Iterations": "i",
    },
    "PRIV": {"Command": "s", "Reason": "s"},
    "POLO": {},
    "PROGRESS": {
        "OperationID": "s",
        "Title": "s",
        "Value": "i",
        "MaxValue": "i",
        "IsDone": "?",
        "Targets": "l",
        "IsTimer": "?",
    },
    "PS": dict(_CREATURE_PAYLOAD),
    "READY": {},
    "REDIRECT": {"Host": "s", "Port": "i", "Reason": "s"},
    "ROLL": {
        "Replay": "?",
        "Sender": "s",
        "Recipients": "l",
        "MessageID": "i",
        "ToAll": "?",
        "ToGM": "?",
        "Title": "s",
        "Result": (
            "o",
            {
                "InvalidRequest": "?",
                "ResultSuppressed": "?",
                "Result": "i",
                "Details": ("a", {"Type": "s", "Value": "s"}),
            },
        ),
        "RequestID": "s",
        "MoreResults": "?",
        "Sent": "s",
        "Origin": "?",
        "Targets": "l",
        "Type": "s",
        "For": "s",
    },
    "SOUND": {"Name": "s", "Loop": "?", "Stop": "?", "Addrs": "l"},
    "SYNC": {},
    "SYNC-CHAT": {"Target": "i"},
    "TB": {"Enabled": "?"},
    "TMACK": {"RequestID": "s", "RequestingClient": "s", "RequestedBy": "s"},
    "TMRQ": {
        "Description": "s",
        "Expires": "s",
        "Targets": "l",
        "ShowToAll": "?",
        "IsRunning": "?",
        "RequestedBy": "s",
        "RequestingClient": "s",
        "RequestID": "s",
    },
    "TO": {
        "Replay": "?",
        "Sender": "s",
        "Recipients": "l",
        "MessageID": "i",
        "ToAll": "?",
        "ToGM": "?",
        "Text": "s",
        "Sent": "s",
        "Markup": "?",
        "Origin": "?",
        "Pin": "?",
    },
    "UPDATES": {
        "Packages": (
            "a",
            {
                "Name": "s",
                "Instances": ("a", {"OS": "s", "Arch": "s", "Version": "s", "Token": "s"}),
            },
        )
    },
    "WORLD": {
        "Calendar": "s",
        "ClientSettings": (
            "o",
            {
                "MkdirPath": "s",
                "ImageBaseURL": "s",
                "ModuleCode": "s",
                "SCPDestination": "s",
                "ServerHostname": "s",
            },
        ),
    },
    "/CONN": {},
    "Y2": {"MinimumMessageID": "i", "MaximumMessageID": "i"},
    "Animation": {"Frames": "i", "FrameSpeed": "i", "Loops": "i"},
    "Health": dict(_HEALTH_PAYLOAD),
    "Font": {"Family": "s", "Size": "f", "Weight": "i", "Slant": "i"},
    "CustomReach": {"Enabled": "?", "Natural": "i", "Extended": "i"},
}

_TM_DETAIL_PAYLOAD: dict[str, Any] = {
    "Tracer": "?",
    "Modifiers": "l",
    "Shape": "s",
    "Color": "s",
    "Description": "s",
    "Limit": "i",
    "EndAtDeath": "?",
}


def new_id() -> str:
    """Return a lowercase hex UUID without hyphens."""
    return uuid.uuid4().hex


def to_enum(key: str, value: str | None) -> int:
    """Convert an enum string value to its integer code."""
    if key not in ENUM_ENCODINGS:
        raise ValueError(f"no such enum type {key}")
    if not value:
        return 0
    try:
        return ENUM_ENCODINGS[key].index(value)
    except ValueError:
        return 0


def from_enum(key: str, value: int) -> str:
    """Convert an integer enum code to its string value."""
    if key not in ENUM_ENCODINGS:
        raise ValueError(f"no such enum type {key}")
    values = ENUM_ENCODINGS[key]
    if value < 0 or value >= len(values):
        raise ValueError(f"enum value {value} out of range for {key}")
    return values[value]


def ObjTypeToGMAType(ot: str, protocol: bool = False) -> str:
    """Convert internal canvas object type (e.g. 'rect') to GMA type ('RECT' or 'LS-RECT')."""
    prefix = "LS-" if protocol else ""
    mapping = {
        "arc": "ARC",
        "circ": "CIRC",
        "line": "LINE",
        "poly": "POLY",
        "rect": "RECT",
        "aoe": "SAOE",
        "saoe": "SAOE",
        "text": "TEXT",
        "tile": "TILE",
    }
    if ot in mapping:
        return f"{prefix}{mapping[ot]}"
    raise ValueError(f"No such defined GMA type for {ot}")


obj_type_to_gma_type = ObjTypeToGMAType


def GMATypeToObjType(gt: str) -> str:
    """Convert GMA type ('RECT' or 'LS-RECT') to internal object type ('rect')."""
    mapping = {
        "LS-ARC": "arc",
        "ARC": "arc",
        "LS-CIRC": "circ",
        "CIRC": "circ",
        "LS-LINE": "line",
        "LINE": "line",
        "LS-POLY": "poly",
        "POLY": "poly",
        "LS-RECT": "rect",
        "RECT": "rect",
        "LS-SAOE": "aoe",
        "SAOE": "aoe",
        "LS-SAO": "aoe",
        "SAO": "aoe",
        "LS-TEXT": "text",
        "TEXT": "text",
        "LS-TILE": "tile",
        "TILE": "tile",
    }
    if gt in mapping:
        return mapping[gt]
    raise ValueError(f"No such defined object type for {gt}")


gma_type_to_obj_type = GMATypeToObjType


def GMATypeToProtocolCommand(gt: str) -> str:
    """Convert GMA map element type or command to protocol command name."""
    mapping = {
        "LS-ARC": "LS-ARC",
        "ARC": "LS-ARC",
        "LS-CIRC": "LS-CIRC",
        "CIRC": "LS-CIRC",
        "LS-LINE": "LS-LINE",
        "LINE": "LS-LINE",
        "LS-POLY": "LS-POLY",
        "POLY": "LS-POLY",
        "LS-RECT": "LS-RECT",
        "RECT": "LS-RECT",
        "LS-SAOE": "LS-SAOE",
        "SAOE": "LS-SAOE",
        "LS-SAO": "LS-SAOE",
        "SAO": "LS-SAOE",
        "LS-TEXT": "LS-TEXT",
        "TEXT": "LS-TEXT",
        "LS-TILE": "LS-TILE",
        "TILE": "LS-TILE",
        "CREATURE": "PS",
        "PS": "PS",
    }
    return mapping.get(gt, gt)


gma_type_to_protocol_command = GMATypeToProtocolCommand


def payload_format(cmd: str) -> dict[str, Any]:
    """Return the schema definition dictionary for command `cmd`."""
    if cmd in MESSAGE_PAYLOAD:
        return MESSAGE_PAYLOAD[cmd]
    raise ValueError(f"undefined protocol message {cmd}")


def _is_null(v: Any) -> bool:
    return v is None or v == "null"


def _parse_bool(v: Any, field: str) -> bool:
    if isinstance(v, bool):
        return v
    if isinstance(v, int):
        return bool(v)
    if isinstance(v, str):
        vl = v.strip().lower()
        if vl in ("true", "1", "yes", "on"):
            return True
        if vl in ("false", "0", "no", "off", "null", ""):
            return False
    raise ValueError(f"value for {field} is not a boolean: {v}")


def json_decode_special(special_type: str, d: Any) -> dict[str, Any]:
    """Decode special schema fields like TargetedModifiers ('TM')."""
    if special_type == "TM":
        if not d or d == "null" or not isinstance(d, dict):
            return {}
        out: dict[str, Any] = {}
        for creature, conds in d.items():
            if not conds or not isinstance(conds, dict):
                continue
            c_out: dict[str, Any] = {}
            for cond, details in conds.items():
                if not isinstance(details, dict):
                    details = {}
                c_out[cond] = {
                    "Modifiers": list(details.get("Modifiers") or []),
                    "Shape": str(details.get("Shape") or "O"),
                    "Color": str(details.get("Color") or "black"),
                    "Tracer": bool(details.get("Tracer", False)),
                    "Limit": int(details.get("Limit", 0) or 0),
                    "EndAtDeath": bool(details.get("EndAtDeath", False)),
                    "Description": str(details.get("Description") or ""),
                }
            out[creature] = c_out
        return out
    raise ValueError(f"unknown special data type for json_decode_special: {special_type}")


def json_encode_special(special_type: str, d: Any) -> dict[str, Any]:
    """Encode special schema fields like TargetedModifiers ('TM') to JSON-serializable dicts."""
    if special_type == "TM":
        if not d or not isinstance(d, dict):
            return {}
        out: dict[str, Any] = {}
        for creature, conds in d.items():
            if not isinstance(conds, dict):
                continue
            c_out: dict[str, Any] = {}
            for cond, details in conds.items():
                c_out[cond] = _encode_payload_dict(details, _TM_DETAIL_PAYLOAD)
            out[creature] = c_out
        return out
    raise ValueError(f"unknown special data type for json_encode_special: {special_type}")


def _construct(input_dict: dict[str, Any] | None, types: dict[str, Any]) -> dict[str, Any]:
    """Construct a normalized dictionary with defaults for missing/null fields."""
    result: dict[str, Any] = dict(input_dict) if input_dict else {}
    for field, t in types.items():
        t_code = t[0] if isinstance(t, (tuple, list)) else t
        t_sub = t[1] if isinstance(t, (tuple, list)) and len(t) > 1 else None
        has_field = field in result
        val = result.get(field)

        if t_code == "s":
            if has_field and not _is_null(val):
                result[field] = str(val)
            else:
                result[field] = ""
        elif t_code == "l":
            if has_field and not _is_null(val):
                if isinstance(val, (list, tuple)):
                    result[field] = [str(x) for x in val]
                elif isinstance(val, str):
                    result[field] = [] if val == "" else [val]
                else:
                    raise ValueError(f"value for {field} is not a valid list: {val}")
            else:
                result[field] = []
        elif t_code == "L":
            if has_field and not _is_null(val):
                if isinstance(val, (list, tuple)):
                    result[field] = [int(x) for x in val]
                elif val == "":
                    result[field] = []
                else:
                    raise ValueError(f"value for {field} is not a valid list: {val}")
            else:
                result[field] = []
        elif t_code == "i":
            if has_field and not _is_null(val) and val != "":
                if isinstance(val, bool):
                    raise ValueError(f"value for {field} is not an integer: {val}")
                try:
                    if isinstance(val, str):
                        result[field] = int(val.strip())
                    elif isinstance(val, int):
                        result[field] = val
                    elif isinstance(val, float) and val.is_integer():
                        result[field] = int(val)
                    else:
                        raise ValueError(f"value for {field} is not an integer: {val}")
                except ValueError as exc:
                    raise ValueError(f"value for {field} is not an integer: {val}") from exc
            else:
                result[field] = 0
        elif t_code == "f":
            if has_field and not _is_null(val) and val != "":
                if isinstance(val, bool):
                    raise ValueError(f"value for {field} is not a float: {val}")
                try:
                    fv = float(val)
                except (ValueError, TypeError) as exc:
                    raise ValueError(f"value for {field} is not a float: {val}") from exc
                if not math.isfinite(fv):
                    raise ValueError(f"value for {field} must be finite: {val}")
                result[field] = fv
            else:
                result[field] = 0.0
        elif t_code == "?":
            if has_field and not _is_null(val):
                result[field] = _parse_bool(val, field)
            else:
                result[field] = False
        elif t_code == "b":
            if has_field and not _is_null(val) and val != "" and val != b"":
                if isinstance(val, bytes):
                    result[field] = val
                elif isinstance(val, str):
                    try:
                        result[field] = base64.b64decode(val)
                    except Exception as exc:
                        raise ValueError(f"unable to decode base64 value for {field}: {exc}") from exc
                else:
                    raise ValueError(f"unable to decode base64 value for {field}: {val}")
            else:
                result[field] = b""
        elif t_code == "a":
            if has_field and not _is_null(val) and val != "":
                if not isinstance(val, (list, tuple)):
                    raise ValueError(f"value for {field} is not a list: {val}")
                result[field] = [_construct(v, t_sub) for v in val]
            else:
                result[field] = []
        elif t_code == "o":
            if has_field and not _is_null(val) and val != "":
                if not isinstance(val, dict):
                    raise ValueError(f"value for {field} is not a dict: {val}")
                result[field] = _construct(val, t_sub)
            else:
                result[field] = {}
        elif t_code == "D":
            if has_field and not _is_null(val) and val != {} and val != "":
                if not isinstance(val, dict):
                    raise ValueError(f"value for {field} is not a dict: {val}")
                result[field] = {
                    str(k): _construct(v, t_sub) for k, v in val.items()
                }
            else:
                result[field] = {}
        elif t_code == "d":
            if has_field and not _is_null(val) and isinstance(val, dict):
                result[field] = {
                    str(k): ("" if _is_null(v) else v) for k, v in val.items()
                }
            else:
                result[field] = {}
        elif t_code == "TM":
            if has_field:
                result[field] = json_decode_special("TM", val)
            else:
                result[field] = json_decode_special("TM", {})
        else:
            raise ValueError(f'bug: unrecognized type code "{t}"')
    return result


def _encode_payload_dict(input_dict: dict[str, Any] | None, type_dict: dict[str, Any]) -> dict[str, Any]:
    """Convert `input_dict` into a JSON-ready Python dict, omitting zero/default fields."""
    if not input_dict:
        return {}
    out: dict[str, Any] = {}
    for f, t in type_dict.items():
        if f not in input_dict:
            continue
        v = input_dict[f]
        if v is None:
            continue
        t_code = t[0] if isinstance(t, (tuple, list)) else t
        t_sub = t[1] if isinstance(t, (tuple, list)) and len(t) > 1 else None

        if t_code == "s":
            if v != "":
                out[f] = str(v)
        elif t_code == "l":
            if v and len(v) > 0:
                out[f] = [str(s) for s in v]
        elif t_code == "L":
            if v and len(v) > 0:
                out[f] = [int(s) for s in v]
        elif t_code == "i":
            if v != "" and not isinstance(v, bool):
                try:
                    iv = int(v)
                    if iv != 0:
                        out[f] = iv
                except (ValueError, TypeError):
                    pass
        elif t_code == "f":
            if v != "" and not isinstance(v, bool):
                try:
                    fv = float(v)
                    if math.isfinite(fv) and fv != 0.0:
                        # Preserve int-like formatting only if float, json.dumps handles float
                        out[f] = int(fv) if isinstance(v, int) else fv
                except (ValueError, TypeError):
                    pass
        elif t_code == "?":
            if isinstance(v, bool):
                if v:
                    out[f] = True
            elif isinstance(v, (int, str)) and _parse_bool(v, f):
                out[f] = True
        elif t_code == "b":
            if v:
                raw_bytes = v.encode("utf-8") if isinstance(v, str) else bytes(v)
                if len(raw_bytes) > 0:
                    out[f] = base64.b64encode(raw_bytes).decode("ascii")
        elif t_code == "o":
            if v and isinstance(v, dict) and len(v) > 0:
                out[f] = _encode_payload_dict(v, t_sub)
        elif t_code == "a":
            if v and len(v) > 0:
                out[f] = [_encode_payload_dict(obj, t_sub) for obj in v]
        elif t_code == "d":
            if v and isinstance(v, dict) and len(v) > 0:
                out[f] = {str(dk): str(dv) for dk, dv in v.items()}
        elif t_code == "D":
            if v and isinstance(v, dict) and len(v) > 0:
                out[f] = {str(dk): _encode_payload_dict(dv, t_sub) for dk, dv in v.items()}
        elif t_code == "TM":
            out[f] = json_encode_special("TM", v)
        else:
            raise ValueError(f'bug: unrecognized type code "{t}"')
    return out


def _encode_payload(input_dict: dict[str, Any] | None, type_dict: dict[str, Any]) -> str:
    """Encode `input_dict` as compact JSON according to `type_dict`."""
    data = _encode_payload_dict(input_dict, type_dict)
    return json.dumps(data, separators=(",", ":"), allow_nan=False)


def _protocol_encode(oldcommand: str, kvdict: dict[str, Any] | None = None) -> str:
    """Encode a command and parameter dictionary into a wire line (without trailing newline)."""
    command = GMATypeToProtocolCommand(oldcommand)
    pfmt = payload_format(command)
    if not pfmt:
        return command
    return f"{command} {_encode_payload(kvdict or {}, pfmt)}"


def _protocol_encode_struct(oldcommand: str, kvdict: dict[str, Any] | None = None) -> str:
    """Encode only the JSON struct portion of a command."""
    command = GMATypeToProtocolCommand(oldcommand)
    pfmt = payload_format(command)
    if not pfmt:
        return ""
    return _encode_payload(kvdict or {}, pfmt)


def _parse_data_packet(raw_line: str) -> tuple[str, Any]:
    """Parse a raw protocol line received from the server.

    Returns:
      - `("NIL", "")` for blank lines
      - `("//", raw_line)` for comments
      - `("PROTOCOL", version_str)` for protocol header
      - `("ERROR", [err_str, raw_line])` for malformed JSON
      - `("UNDEFINED", raw_line)` for unknown command
      - `(command, constructed_dict)` for valid commands
    """
    line = raw_line.strip()
    if not line:
        return ("NIL", "")
    if line.startswith("//"):
        return ("//", line)
    delim = line.find(" ")
    if delim > 0:
        command = line[:delim]
        payload = line[delim + 1 :].strip()
        if command == "PROTOCOL":
            return ("PROTOCOL", payload)
        if payload:
            try:
                json_payload = json.loads(payload)
                if not isinstance(json_payload, dict):
                    return ("ERROR", ["JSON payload is not an object", line])
            except Exception as err:
                return ("ERROR", [str(err), line])
        else:
            json_payload = {}
    else:
        command = line
        json_payload = {}

    try:
        pfmt = payload_format(command)
    except ValueError:
        return ("UNDEFINED", line)

    try:
        return (command, _construct(json_payload, pfmt))
    except Exception as err:
        return ("ERROR", [str(err), line])


def new_dict(command: str, **kwargs: Any) -> dict[str, Any]:
    """Create a new default-populated dictionary for `command`."""
    return _construct(kwargs, payload_format(command))


def new_dict_from_json(command: str, jsondata: str) -> dict[str, Any]:
    """Parse `jsondata` and construct a normalized dictionary for `command`."""
    parsed = json.loads(jsondata) if jsondata.strip() else {}
    return _construct(parsed, payload_format(command))


def json_from_dict(command: str, d: dict[str, Any]) -> str:
    """Encode `d` into compact JSON using `command`'s payload format."""
    return _encode_payload(d, payload_format(command))


def normalize_dict(cmd: str, d: dict[str, Any]) -> dict[str, Any]:
    """Round-trip `d` through `cmd`'s JSON encoder and constructor to normalize fields."""
    try:
        payload_format(cmd)
    except ValueError:
        cmd = GMATypeToProtocolCommand(cmd)
        try:
            payload_format(cmd)
        except ValueError as exc:
            raise ValueError(f"can't normalize type {cmd} dictionary {d}") from exc
    return new_dict_from_json(cmd, json_from_dict(cmd, d))


def _attribute_encode(k: str, v: Any) -> Any:
    """Convert an internal object attribute `(k, v)` to a JSON-serializable Python value for `OA`."""
    if k in (
        "AoEShape",
        "Anchor",
        "ArcMode",
        "Arrow",
        "Dash",
        "Join",
        "MoveMode",
        "CreatureType",
        "BBHeight",
        "BBWidth",
        "Elev",
        "Extent",
        "Gx",
        "Gy",
        "Reach",
        "Skin",
        "Spline",
        "Start",
        "Width",
        "X",
        "Y",
        "Z",
    ):
        return v
    if k in ("Dim", "Hidden", "Killed", "Locked"):
        return _parse_bool(v, k)
    if k == "AoE":
        if not v or not isinstance(v, dict):
            return None
        if "Radius" in v and "Color" in v:
            return {"Radius": v["Radius"], "Color": str(v["Color"])}
        return None
    if k == "SkinSize":
        return list(v) if v else []
    if k in ("StatusList", "Targets"):
        return [str(s) for s in (v or [])]
    if k in ("Font", "CustomReach", "Health"):
        return _encode_payload_dict(v, payload_format(k))
    if k == "TargetedModifiers":
        return json_encode_special("TM", v)
    if k == "Points":
        return [{"X": p["X"], "Y": p["Y"]} for p in (v or [])]
    return str(v)


def encode_with_batching(
    command: str,
    dargs: dict[str, Any] | None = None,
    max_len: int = MAXIMUM_MESSAGE_LENGTH,
    frag_size: int = FRAG_SIZE,
) -> list[str]:
    """Encode a command and split into `BATCH` packets if it exceeds `max_len`."""
    packet = _protocol_encode(command, dargs)
    if len(packet) <= max_len:
        return [packet]

    delim = packet.find(" ")
    if delim < 0:
        raise ValueError(f"malformed outgoing {command} data packet (can't find delimiter)")
    blob_bytes = packet[delim + 1 :].encode("utf-8")
    total_batches = (len(blob_bytes) + frag_size - 1) // frag_size
    batch_id = new_id()
    packets: list[str] = []
    for part in range(total_batches):
        chunk_bytes = blob_bytes[part * frag_size : (part + 1) * frag_size]
        b64_chunk = base64.b64encode(chunk_bytes).decode("ascii")
        b: dict[str, Any] = {
            "ID": batch_id,
            "Part": part,
            "Of": total_batches,
            "Data": b64_chunk,
        }
        if part == 0:
            b["Command"] = GMATypeToProtocolCommand(command)
        packets.append(_protocol_encode("BATCH", b))
    return packets


class BatchCollector:
    """Reassembles incoming `BATCH` protocol fragments into complete messages."""

    def __init__(self) -> None:
        self._storage: dict[str, dict[int, tuple[str, bytes]]] = {}

    def clear(self) -> None:
        self._storage.clear()

    def process_batch(self, batch_params: dict[str, Any]) -> tuple[str, Any] | None:
        """Process a `BATCH` dictionary; return `(cmd, params)` when all fragments arrive."""
        batch_group = str(batch_params.get("ID", ""))
        part = batch_params.get("Part", -1)
        total = batch_params.get("Of", 0)
        batch_error = batch_params.get("Error", "")
        data = batch_params.get("Data", "")
        batched_cmd = str(batch_params.get("Command", ""))

        if not batch_group:
            return None
        if batch_error:
            self._storage.pop(batch_group, None)
            return None
        if (
            not isinstance(part, int)
            or not isinstance(total, int)
            or part < 0
            or total <= 0
            or part >= total
            or total > MAX_BATCH_PARTS
        ):
            self._storage.pop(batch_group, None)
            return None

        try:
            decoded_chunk = base64.b64decode(data) if isinstance(data, str) else bytes(data)
        except Exception:
            self._storage.pop(batch_group, None)
            return None

        if batch_group not in self._storage and len(self._storage) >= MAX_CONCURRENT_BATCHES:
            oldest_key = next(iter(self._storage))
            self._storage.pop(oldest_key, None)

        group_dict = self._storage.setdefault(batch_group, {})
        group_dict[part] = (batched_cmd, decoded_chunk)

        if len(group_dict) >= total:
            if not all(i in group_dict for i in range(total)):
                return None
            cmd = group_dict[0][0]
            full_bytes = b"".join(group_dict[i][1] for i in range(total))
            self._storage.pop(batch_group, None)
            if not cmd:
                return None
            full_json = full_bytes.decode("utf-8", errors="replace")
            res = _parse_data_packet(f"{cmd} {full_json}")
            if res[0] == "NIL":
                return None
            return res
        return None


def auth_response(challenge: bytes, password: str, passes: int = 0) -> bytes:
    """Compute the GMA iterative SHA-256 challenge-response digest."""
    if passes <= 0:
        if len(challenge) < 2:
            raise ValueError("Challenge too short to extract pass count")
        passes = struct.unpack(">H", challenge[:2])[0] & 0xFFFF
    if passes > MAX_AUTH_ITERATIONS:
        raise ValueError(
            f"Auth iteration count {passes} exceeds maximum allowed ({MAX_AUTH_ITERATIONS})"
        )

    pw_bytes = password.encode("utf-8")
    h = hashlib.sha256()
    h.update(challenge)
    h.update(pw_bytes)
    digest = h.digest()

    for _ in range(passes):
        h = hashlib.sha256()
        h.update(pw_bytes)
        h.update(digest)
        digest = h.digest()

    return digest

