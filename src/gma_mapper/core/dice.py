"""Die-roller engine, preset codec, roll statistics, and chat/pin history manager.

Ported from `bin/mapper_legacy.tcl` (`GetPresetDetails`, `EncodePresetDetails`,
`PresetLists`, `cleanupDieRollSpec`, `SearchForPreset`, `_do_roll`,
`_apply_die_roll_mods`, `_apply_die_roll_variables`, `AddToDieRollTitle`,
`CollectRollStats`, `ReportRollStats`, `DisplayDieRoll`, `DisplayChatMessage`,
`ClearChatHistory`, `PruneChatHistory`, `ShowDiceSyntax`, `ShowDiceModifierHelp`).
"""

from __future__ import annotations

import base64
import copy
import datetime
import functools
import html
import math
import re
from pathlib import Path
from typing import Any

from .colors import color_to_hex, contrasting_color, darken_color
from .profile import SYMBOLS, default_fonts, default_styles

# Delimiter candidates for table presets (matching EncodePresetDetails in mapper_legacy.tcl)
TABLE_DELIMITER_CANDIDATES = ";|,:/~><=!@_^`\x01\x02\x03\x04\x05\x06\x07"

# Operators that do not require an implicit leading '+' when concatenating modifiers
_MOD_OPERATOR_START_RE = re.compile(r"^([-+*(÷×≤≥]|//|<=|>=)")

# Area tag prefix inside a preset's sequence field: $[area]seq...
_PRESET_AREA_RE = re.compile(r"^\$\[([^\]]*)\](.*)$")

# Valid preset prefix in PresetLists: optional $[area], digits, optional ▶group...
_VALID_PRESET_SEQ_RE = re.compile(r"^(\$\[.*?\]|)([0-9]+)(\u25b6.*)?$")

# Table roll syntax: [Title =] #[#]{tablename}[extra]
_TABLE_ROLL_RE = re.compile(
    r"^\s*(.*=)?\s*#(#?)\{?([a-zA-Z_]\w*)\}?((?:[^a-zA-Z0-9_].*)?)$"
)

# Variable references inside die-roll specifications
_GVAR_BRACE_RE = re.compile(r"\$\$\{([a-zA-Z_]\w*)\}")
_GVAR_BARE_RE = re.compile(r"\$\$([a-zA-Z_]\w*)")
_UVAR_BRACE_RE = re.compile(r"\$\{([a-zA-Z_]\w*)\}")
_UVAR_BARE_RE = re.compile(r"\$([a-zA-Z_]\w*)")
_VALID_VAR_NAME_RE = re.compile(r"^[a-zA-Z_]\w*$")


def build_preset_group_name(
    name: str,
    seq: str = "",
    groups: list[str] | tuple[str, ...] = (),
    prefix: str = "",
    extra: str = "",
) -> str:
    """Construct the encoded preset `Name` string with optional sequence, group path, and flags.

    Matches `_build_preset_group_name` in `bin/mapper_legacy.tcl`.
    """
    clean_groups = [str(g) for g in groups if str(g) != ""]
    seq_str = str(seq or "")
    if clean_groups:
        if not seq_str:
            seq_str = "000"
        seq_str = "\u25b6".join([seq_str, *clean_groups])
    if not seq_str and not prefix and not extra:
        return f"{prefix}{name}"
    return f"{prefix}{seq_str}{extra}|{name}"


def sync_preset_detail_flags(details: dict[str, Any]) -> dict[str, Any]:
    """Synchronize boolean flags (`enabled`, `global`, `markup`) into the `flags` list.

    Matches `SyncPresetDetailFlags` in `bin/mapper_legacy.tcl`.
    """
    flags: list[str] = []
    if details.get("enabled"):
        flags.append("e")
    if details.get("global"):
        flags.append("g")
    if details.get("markup"):
        flags.append("m")
    details["flags"] = flags
    return details


def get_preset_details(preset: dict[str, Any]) -> dict[str, Any]:
    """Decode a raw protocol/file preset dictionary into its structured metadata fields.

    Matches `GetPresetDetails` in `bin/mapper_legacy.tcl`.
    """
    raw_name = str(preset.get("Name", "") or "")
    raw_desc = str(preset.get("Description", "") or "")
    raw_spec = str(preset.get("DieRollSpec", "") or "")
    is_system = bool(preset.get("Global", False))

    details: dict[str, Any] = {
        "area": "",
        "client": "",
        "delim": "",
        "description": raw_desc,
        "dieroll": raw_spec,
        "enabled": False,
        "flags": [],
        "global": False,
        "group": [],
        "markup": False,
        "name": raw_name,
        "seq": "",
        "system": is_system,
        "table": [],
        "type": "preset",
        "var": "",
        "_raw": copy.deepcopy(preset),
    }

    bar_idx = raw_name.find("|")
    if bar_idx < 0:
        return details
    if bar_idx == 0:
        details["name"] = raw_name[1:]
        return details

    prefix = raw_name[:bar_idx]
    display_name = raw_name[bar_idx + 1 :]
    details["name"] = display_name

    if prefix.startswith("\u00a7"):  # '§' -> modifier / variable
        details["type"] = "modifier"
        flds = prefix[1:].split(";")
        if len(flds) >= 2:
            details["var"] = flds[1]
        if len(flds) >= 3:
            details["flags"] = list(flds[2])
        if len(flds) >= 4:
            details["client"] = flds[3]
    elif prefix.startswith("#"):  # '#' -> lookup table
        details["type"] = "table"
        flds = prefix[1:].split(";")
        if len(flds) >= 2:
            details["flags"] = list(flds[1])
        if len(flds) >= 3:
            details["client"] = flds[2]

        drs = raw_spec
        if not drs:
            details["type"] = "invalid"
        else:
            delim = drs[0]
            details["delim"] = delim
            tflds = drs.split(delim)
            # Must be `<delim><dieroll><delim><bound1><delim><text1>...<delim>*<delim><textN><delim>`
            if (
                len(tflds) % 2 == 1
                and tflds[0] == ""
                and tflds[-1] == ""
                and len(tflds) >= 5
                and tflds[-3] == "*"
            ):
                details["dieroll"] = tflds[1]
                pair_items = tflds[2:-1]
                valid_bounds = True
                for idx in range(0, len(pair_items) - 2, 2):
                    bound_str = pair_items[idx].strip()
                    try:
                        int(bound_str)
                    except ValueError:
                        valid_bounds = False
                        break
                if valid_bounds and pair_items[-2] == "*":
                    details["table"] = list(pair_items)
                else:
                    details["type"] = "invalid"
            else:
                details["type"] = "invalid"
    else:
        flds = prefix.split(";")
        m_area = _PRESET_AREA_RE.match(flds[0])
        if m_area:
            details["area"] = m_area.group(1)
            flds[0] = m_area.group(2)

    groups = flds[0].split("\u25b6") if flds else [""]
    details["seq"] = groups[0]
    details["group"] = groups[1:]
    details["enabled"] = "e" in details["flags"]
    details["global"] = "g" in details["flags"]
    details["markup"] = "m" in details["flags"]
    return details


def encode_preset_details(details: dict[str, Any]) -> dict[str, Any]:
    """Encode a structured preset detail dictionary back into a wire/file preset dict.

    Matches `EncodePresetDetails` in `bin/mapper_legacy.tcl`.
    Raises `ValueError` if `type` is unrecognized or table rows are invalid.
    """
    d = copy.deepcopy(details)
    # Sync boolean flags if any boolean key was explicitly set or modified
    if any(k in d for k in ("enabled", "global", "markup")):
        flags_set = set(d.get("flags") or [])
        for flag_char, key in (("e", "enabled"), ("g", "global"), ("m", "markup")):
            if key in d:
                if d[key]:
                    flags_set.add(flag_char)
                else:
                    flags_set.discard(flag_char)
        d["flags"] = [c for c in ("e", "g", "m") if c in flags_set] + [
            c for c in (d.get("flags") or []) if c not in ("e", "g", "m")
        ]

    ptype = d.get("type", "preset")
    name = str(d.get("name", "") or "")
    seq = str(d.get("seq", "") or "")
    groups = list(d.get("group") or [])
    area = str(d.get("area", "") or "")
    seq_with_area = f"$[{area}]{seq}" if area else seq

    if ptype == "preset":
        if "|" in name and not seq_with_area and not groups:
            encoded_name = f"|{name}"
        else:
            encoded_name = build_preset_group_name(name, seq_with_area, groups)
        return {
            "Name": encoded_name,
            "Description": str(d.get("description", "") or ""),
            "DieRollSpec": str(d.get("dieroll", "") or ""),
            "Global": bool(d.get("system", False)),
        }

    if ptype == "modifier":
        flags_str = "".join(d.get("flags") or [])
        var_str = str(d.get("var", "") or "")
        client_str = str(d.get("client", "") or "")
        if client_str:
            extra = f";{var_str};{flags_str};{client_str}"
        elif flags_str:
            extra = f";{var_str};{flags_str}"
        elif var_str:
            extra = f";{var_str}"
        else:
            extra = ""
        encoded_name = build_preset_group_name(name, seq, groups, prefix="\u00a7", extra=extra)
        return {
            "Name": encoded_name,
            "Description": str(d.get("description", "") or ""),
            "DieRollSpec": str(d.get("dieroll", "") or ""),
            "Global": bool(d.get("system", False)),
        }

    if ptype == "table":
        flags_str = "".join(d.get("flags") or [])
        client_str = str(d.get("client", "") or "")
        if client_str:
            extra = f";{flags_str};{client_str}"
        elif flags_str:
            extra = f";{flags_str}"
        else:
            extra = ""

        # Normalize table list: support flat `["1", "low", "*", "high"]` or `[(1, "low"), ("*", "high")]`
        raw_table = d.get("table") or []
        flat_table: list[str] = []
        if raw_table and isinstance(raw_table[0], (tuple, list)):
            for bound, text in raw_table:
                flat_table.extend([str(bound), str(text)])
        else:
            flat_table = [str(item) for item in raw_table]

        if len(flat_table) < 2 or len(flat_table) % 2 != 0:
            raise ValueError("Lookup table must contain at least one (bound, result) pair.")
        if flat_table[-2] != "*":
            raise ValueError("Lookup table must end with a '*' catch-all bound.")

        dieroll_str = str(d.get("dieroll", "") or "")
        combined_text = dieroll_str + "".join(flat_table)
        preferred_delim = str(d.get("delim") or ";")
        candidates = preferred_delim + TABLE_DELIMITER_CANDIDATES
        chosen_delim = ""
        for cand in candidates:
            if len(cand) == 1 and cand not in combined_text:
                chosen_delim = cand
                break
        if not chosen_delim:
            raise ValueError(
                f"Cannot encode table {name!r}: all candidate delimiters appear in the table text."
            )

        encoded_spec = chosen_delim + chosen_delim.join([dieroll_str, *flat_table]) + chosen_delim
        encoded_name = build_preset_group_name(name, seq, groups, prefix="#", extra=extra)
        return {
            "Name": encoded_name,
            "Description": str(d.get("description", "") or ""),
            "DieRollSpec": encoded_spec,
            "Global": bool(d.get("system", False)),
        }

    raise ValueError(f"Unsupported preset type: {ptype!r}")


def cleanup_die_roll_spec(spec: str) -> str:
    """Strip `≡fg≡bg` color definitions from a die-roll specification title while keeping `‖` separators.

    Matches `cleanupDieRollSpec` in `bin/mapper_legacy.tcl`.
    """
    parts = spec.split("=")
    if len(parts) < 2:
        return spec
    title_blocks = parts[0].split("\u2016")
    clean_blocks = [blk.split("\u2261")[0] for blk in title_blocks]
    return "\u2016".join(clean_blocks) + "=" + "=".join(parts[1:])


def search_for_preset(
    presets: list[dict[str, Any]],
    re_pattern: str,
    for_Damage: bool = False,
) -> tuple[str | None, str | None, str | None]:
    """Find the first preset whose decoded name matches `re_pattern` (case-insensitive).

    If `for_Damage` is True, looks for a consecutive subsequent preset whose name contains
    `damage` or `dmg` (case-insensitive) and returns `(full_spec, attack_spec, damage_spec)`.
    Matches `SearchForPreset` in `bin/mapper_legacy.tcl`.
    """
    pat = re.compile(re_pattern, re.IGNORECASE)
    dmg_pat = re.compile(r"damage|dmg", re.IGNORECASE)

    for idx, p in enumerate(presets):
        details = get_preset_details(p)
        if details["type"] != "preset":
            continue
        if pat.search(details["name"]):
            attack_spec = details["dieroll"]
            if not for_Damage:
                return (attack_spec, attack_spec, None)
            damage_spec: str | None = None
            if idx + 1 < len(presets):
                next_details = get_preset_details(presets[idx + 1])
                if next_details["type"] == "preset" and dmg_pat.search(next_details["name"]):
                    damage_spec = next_details["dieroll"]
            return (attack_spec, attack_spec, damage_spec)
    return (None, None, None)


class DicePresetBank:
    """Manages per-user and system die-roll presets, modifier/variable state, and lookup tables.

    Ported from `PresetLists` and `::die_roller` state arrays in `bin/mapper_legacy.tcl`.
    """

    def __init__(self, tkey: str = "") -> None:
        self.tkey: str = tkey
        self.user_presets: list[dict[str, Any]] = []
        self.system_presets: list[dict[str, Any]] = []

        # Interactive toggle states preserved across DD= refreshes
        self.on_vars: dict[str, bool] = {}
        self.on_mods: dict[str, bool] = {}
        self.sys_gvar_on: dict[str, bool] = {}
        self.group_collapsed: dict[str, bool] = {}

        # Partitioned preset lists (populated by rebuild())
        self.rolls: list[dict[str, Any]] = []
        self.global_rolls: list[dict[str, Any]] = []
        self.modifiers: list[dict[str, Any]] = []
        self.global_modifiers: list[dict[str, Any]] = []
        self.tables: list[dict[str, Any]] = []
        self.global_tables: list[dict[str, Any]] = []
        self.custom_rolls: list[dict[str, Any]] = []
        self.global_custom_rolls: list[dict[str, Any]] = []

        # Evaluation lookup maps (populated by rebuild())
        self.apply_order: list[str] = []
        self.mod_specs: dict[str, str] = {}
        self.mod_is_global: dict[str, bool] = {}
        self.mod_var_link: dict[str, tuple[str, bool]] = {}
        self.modsym: dict[str, str] = {}
        self.vars: dict[str, str] = {}
        self.gvars: dict[str, str] = {}
        self.tables_by_name: dict[str, dict[str, Any]] = {}
        self.global_tables_by_name: dict[str, dict[str, Any]] = {}

    def set_user_presets(self, presets: list[dict[str, Any]]) -> None:
        """Replace user presets (non-Global) and rebuild partitioned lists."""
        self.user_presets = [
            {
                "Name": str(p.get("Name", "") or ""),
                "Description": str(p.get("Description", "") or ""),
                "DieRollSpec": str(p.get("DieRollSpec", "") or ""),
                "Global": False,
            }
            for p in presets
            if isinstance(p, dict)
        ]
        self.rebuild()

    def set_system_presets(
        self,
        presets: list[dict[str, Any]],
        shared_gvar_state: dict[str, bool] | None = None,
    ) -> None:
        """Replace system (`Global=True`) presets and rebuild partitioned lists."""
        if shared_gvar_state is not None:
            self.sys_gvar_on = shared_gvar_state
        self.system_presets = [
            {
                "Name": str(p.get("Name", "") or ""),
                "Description": str(p.get("Description", "") or ""),
                "DieRollSpec": str(p.get("DieRollSpec", "") or ""),
                "Global": True,
            }
            for p in presets
            if isinstance(p, dict)
        ]
        self.rebuild()

    def set_combined_presets(self, presets: list[dict[str, Any]]) -> None:
        """Partition a mixed list of user and system (`Global=True`) presets and rebuild."""
        user_list: list[dict[str, Any]] = []
        sys_list: list[dict[str, Any]] = []
        for p in presets:
            if not isinstance(p, dict):
                continue
            entry = {
                "Name": str(p.get("Name", "") or ""),
                "Description": str(p.get("Description", "") or ""),
                "DieRollSpec": str(p.get("DieRollSpec", "") or ""),
                "Global": bool(p.get("Global", False)),
            }
            if entry["Global"]:
                sys_list.append(entry)
            else:
                user_list.append(entry)
        self.user_presets = user_list
        if sys_list:
            self.system_presets = sys_list
        self.rebuild()

    def all_raw_presets(self, include_system: bool = False) -> list[dict[str, Any]]:
        """Return raw preset dictionaries (user presets, plus system presets if requested)."""
        if include_system:
            return copy.deepcopy(self.system_presets) + copy.deepcopy(self.user_presets)
        return copy.deepcopy(self.user_presets)

    def rebuild(self) -> None:
        """Partition all presets into categories and update modifier/variable maps.

        Matches `PresetLists` and `_render_die_roller` in `bin/mapper_legacy.tcl`.
        """
        prev_on_vars = dict(self.on_vars)
        prev_on_mods = dict(self.on_mods)
        prev_sys_gvars = dict(self.sys_gvar_on)

        self.rolls = []
        self.global_rolls = []
        self.modifiers = []
        self.global_modifiers = []
        self.tables = []
        self.global_tables = []
        self.custom_rolls = []
        self.global_custom_rolls = []

        self.apply_order = []
        self.mod_specs = {}
        self.mod_is_global = {}
        self.mod_var_link = {}
        self.modsym = {}
        self.vars = {}
        self.gvars = {}
        self.tables_by_name = {}
        self.global_tables_by_name = {}

        combined = [*self.system_presets, *self.user_presets]
        mod_counter = 0

        for raw in combined:
            is_sys = bool(raw.get("Global", False))
            raw_name = str(raw.get("Name", "") or "")
            raw_desc = str(raw.get("Description", "") or "")
            raw_spec = str(raw.get("DieRollSpec", "") or "")

            details = get_preset_details(raw)
            if details["type"] == "invalid":
                if is_sys:
                    self.global_custom_rolls.append(details)
                else:
                    self.custom_rolls.append(details)
                continue

            # Check if a preset with '|' has a non-numeric sequence (treated as CustomRoll in PresetLists)
            if details["type"] == "preset" and "|" in raw_name and not raw_name.startswith("|"):
                prefix = raw_name[: raw_name.find("|")]
                if not _VALID_PRESET_SEQ_RE.match(prefix):
                    if is_sys:
                        self.global_custom_rolls.append(details)
                    else:
                        self.custom_rolls.append(details)
                    continue

            if details["type"] == "preset":
                if is_sys:
                    self.global_rolls.append(details)
                else:
                    self.rolls.append(details)
                continue

            if details["type"] == "modifier":
                mod_counter += 1
                seq_key = details["seq"] or f"{mod_counter:03d}"
                details["seq"] = seq_key
                mid = f"{'g' if is_sys else 'u'}{seq_key}"
                details["mod_id"] = mid

                var_name = details["var"]
                if var_name and not _VALID_VAR_NAME_RE.match(var_name):
                    if is_sys:
                        self.global_custom_rolls.append(details)
                    else:
                        self.custom_rolls.append(details)
                    continue

                default_enabled = bool(details["enabled"])
                is_global_var = bool(details["global"]) or is_sys
                details["global"] = is_global_var

                if var_name:
                    if is_global_var:
                        self.gvars[var_name] = raw_spec
                        self.modsym[f"$${var_name}"] = var_name
                        if var_name not in prev_sys_gvars:
                            self.sys_gvar_on[var_name] = default_enabled
                        else:
                            self.sys_gvar_on[var_name] = prev_sys_gvars[var_name]
                        self.mod_var_link[mid] = (var_name, True)
                    else:
                        self.vars[var_name] = raw_spec
                        self.modsym[f"${var_name}"] = var_name
                        if var_name not in prev_on_vars:
                            self.on_vars[var_name] = default_enabled
                        else:
                            self.on_vars[var_name] = prev_on_vars[var_name]
                        self.mod_var_link[mid] = (var_name, False)
                else:
                    self.apply_order.append(mid)
                    self.mod_specs[mid] = raw_spec
                    self.mod_is_global[mid] = is_global_var
                    if is_sys:
                        self.modsym[f"/{details['name']}"] = mid
                    else:
                        self.modsym[details["name"]] = mid
                    if mid not in prev_on_mods:
                        self.on_mods[mid] = default_enabled
                    else:
                        self.on_mods[mid] = prev_on_mods[mid]

                if is_sys:
                    self.global_modifiers.append(details)
                else:
                    self.modifiers.append(details)
                continue

            if details["type"] == "table":
                # Validate strictly increasing upper bounds as in PresetLists
                pair_items = details["table"]
                prev_bound: int | None = None
                valid_order = True
                structured_pairs: list[tuple[str, str]] = []
                for idx in range(0, len(pair_items), 2):
                    b_str = pair_items[idx].strip()
                    t_str = pair_items[idx + 1]
                    if idx < len(pair_items) - 2:
                        try:
                            b_val = int(b_str)
                        except ValueError:
                            valid_order = False
                            break
                        if prev_bound is not None and b_val <= prev_bound:
                            valid_order = False
                            break
                        prev_bound = b_val
                        structured_pairs.append((str(b_val), t_str))
                    else:
                        if b_str != "*":
                            valid_order = False
                            break
                        structured_pairs.append(("*", t_str))

                if not valid_order or not _VALID_VAR_NAME_RE.match(details["name"]):
                    if is_sys:
                        self.global_custom_rolls.append(details)
                    else:
                        self.custom_rolls.append(details)
                    continue

                details["pairs"] = structured_pairs
                if is_sys:
                    self.global_tables.append(details)
                    self.global_tables_by_name[details["name"]] = details
                else:
                    self.tables.append(details)
                    self.tables_by_name[details["name"]] = details

    def is_mod_enabled(self, mod_id: str) -> bool:
        """Return True if a modifier or variable preset is currently checked."""
        if mod_id in self.mod_var_link:
            vname, is_gvar = self.mod_var_link[mod_id]
            return bool(self.sys_gvar_on.get(vname, False) if is_gvar else self.on_vars.get(vname, False))
        return bool(self.on_mods.get(mod_id, False))

    def set_mod_enabled(self, mod_id: str, enabled: bool) -> None:
        """Toggle a modifier or variable preset by its `mod_id` (`u001`, `g001`, etc.)."""
        flag = bool(enabled)
        if mod_id in self.mod_var_link:
            vname, is_gvar = self.mod_var_link[mod_id]
            if is_gvar:
                self.sys_gvar_on[vname] = flag
            else:
                self.on_vars[vname] = flag
        else:
            self.on_mods[mod_id] = flag

    def set_var_enabled(self, var_name: str, enabled: bool, is_global: bool = False) -> None:
        """Toggle a `$var` or `$$var` directly by variable name."""
        if is_global:
            self.sys_gvar_on[var_name] = bool(enabled)
        else:
            self.on_vars[var_name] = bool(enabled)


def resolve_targeted_modifiers(
    for_user: str,
    my_names: list[str] | tuple[str, ...],
    mobs_by_id: dict[str, dict[str, Any]],
    mobs_by_name: dict[str, str],
    modsym: dict[str, str],
) -> tuple[set[str], set[str], set[str], str | None]:
    """Evaluate creature `Targets` and `TargetedModifiers` for automatic conditional modifiers.

    Matches the target-conditional modifier check in `_do_roll` (`bin/mapper_legacy.tcl`).
    Returns `(cond_mods, cond_vars, cond_gvars, warning_message)`.
    """
    cond_mods: set[str] = set()
    cond_vars: set[str] = set()
    cond_gvars: set[str] = set()

    attacker_name: str | None = None
    if for_user and for_user in mobs_by_name:
        attacker_name = for_user
    else:
        for candidate in my_names:
            if candidate in mobs_by_name:
                attacker_name = candidate
                break

    if not attacker_name:
        return (cond_mods, cond_vars, cond_gvars, None)

    attacker_id = mobs_by_name.get(attacker_name)
    attacker = mobs_by_id.get(attacker_id or "")
    if not attacker:
        return (cond_mods, cond_vars, cond_gvars, None)

    targets = list(attacker.get("Targets") or [])
    targeted_mods = attacker.get("TargetedModifiers") or {}
    if not targets or not isinstance(targeted_mods, dict):
        return (cond_mods, cond_vars, cond_gvars, None)

    # When multiple targets are selected, verify all targets have identical active condition keys
    if len(targets) > 1:
        first_target_conds = targeted_mods.get(targets[0]) or {}
        first_keys = sorted(first_target_conds.keys()) if isinstance(first_target_conds, dict) else []
        for other_target in targets[1:]:
            other_conds = targeted_mods.get(other_target) or {}
            other_keys = sorted(other_conds.keys()) if isinstance(other_conds, dict) else []
            if other_keys != first_keys:
                return (
                    set(),
                    set(),
                    set(),
                    "Multiple targets with different modifiers selected; skipping conditional modifiers.",
                )

    primary_target = targets[0]
    active_conds = targeted_mods.get(primary_target) or {}
    if not isinstance(active_conds, dict):
        return (cond_mods, cond_vars, cond_gvars, None)

    for _cond_name, cond_data in active_conds.items():
        if not isinstance(cond_data, dict):
            continue
        mod_list = cond_data.get("Modifiers") or []
        for mod_token in mod_list:
            token = str(mod_token or "").strip()
            if not token:
                continue
            if token.startswith("$$"):
                cond_gvars.add(token[2:])
            elif token.startswith("$"):
                cond_vars.add(token[1:])
            elif token.startswith("/"):
                if token in modsym:
                    cond_mods.add(modsym[token])
            else:
                if token in modsym:
                    cond_mods.add(modsym[token])

    return (cond_mods, cond_vars, cond_gvars, None)


def apply_die_roll_mods(
    spec: str,
    extra: str = "",
    bank: DicePresetBank | None = None,
    cond_mods: set[str] | None = None,
) -> str:
    """Apply ad-hoc `extra` and enabled/conditional modifiers to a die-roll specification.

    Matches `_apply_die_roll_mods` in `bin/mapper_legacy.tcl`.
    """
    active_cond_mods = cond_mods or set()
    mods_to_apply: list[tuple[str, bool]] = []

    if extra and extra.strip():
        extra_parts = extra.strip().split("|")
        extra_parts[0] = f"{extra_parts[0]} ad hoc"
        mods_to_apply.append(("|".join(extra_parts), False))

    if bank is not None:
        for mid in bank.apply_order:
            if bank.is_mod_enabled(mid) or mid in active_cond_mods:
                mod_spec = bank.mod_specs.get(mid, "")
                is_glob = bank.mod_is_global.get(mid, False)
                if mod_spec:
                    mods_to_apply.append((mod_spec, is_glob))

    if not mods_to_apply:
        return spec

    spec_parts = spec.split("|")
    base_expr = spec_parts[0]
    spec_opts = spec_parts[1:]

    for mod_spec, is_global_wrap in mods_to_apply:
        mod_parts = mod_spec.split("|")
        m_expr = mod_parts[0].strip()
        m_opts = mod_parts[1:]
        if not m_expr and not m_opts:
            continue

        if is_global_wrap and base_expr.strip():
            if "=" in base_expr:
                eq_idx = base_expr.find("=")
                title_prefix = base_expr[: eq_idx + 1]
                formula_body = base_expr[eq_idx + 1 :].strip()
                base_expr = f"{title_prefix}({formula_body})"
            else:
                base_expr = f"({base_expr.strip()})"

        if m_expr:
            if not _MOD_OPERATOR_START_RE.match(m_expr):
                m_expr = f"+ {m_expr}"
            else:
                m_expr = f" {m_expr}"
            base_expr = f"{base_expr}{m_expr}"

        spec_opts.extend(m_opts)

    return "|".join([base_expr, *spec_opts])


def apply_die_roll_variables(
    spec: str,
    bank: DicePresetBank | None = None,
    cond_vars: set[str] | None = None,
    cond_gvars: set[str] | None = None,
    max_depth: int = 100,
) -> str:
    """Recursively expand `$var`, `${var}`, `$$var`, and `$${var}` placeholders in `spec`.

    Matches `_apply_die_roll_variables` in `bin/mapper_legacy.tcl`.
    Raises `ValueError` on undefined variables or when recursion exceeds `max_depth` (100).
    """
    if "$" not in spec:
        return spec

    active_cond_vars = cond_vars or set()
    active_cond_gvars = cond_gvars or set()
    u_vars = bank.vars if bank else {}
    g_vars = bank.gvars if bank else {}

    def _replace_gvar(match: re.Match[str]) -> str:
        vname = match.group(1)
        if vname not in g_vars:
            raise ValueError(f"Undefined global die-roll variable $${vname}")
        enabled = (bank is not None and bank.sys_gvar_on.get(vname, False)) or (
            vname in active_cond_gvars
        )
        return f" {g_vars[vname]} " if enabled else ""

    def _replace_uvar(match: re.Match[str]) -> str:
        vname = match.group(1)
        if vname not in u_vars:
            raise ValueError(f"Undefined die-roll variable ${vname}")
        enabled = (bank is not None and bank.on_vars.get(vname, False)) or (
            vname in active_cond_vars
        )
        return f" {u_vars[vname]} " if enabled else ""

    current = spec
    for _ in range(max_depth):
        if "$" not in current:
            return current
        prev = current
        current = _GVAR_BRACE_RE.sub(_replace_gvar, current)
        current = _GVAR_BARE_RE.sub(_replace_gvar, current)
        current = _UVAR_BRACE_RE.sub(_replace_uvar, current)
        current = _UVAR_BARE_RE.sub(_replace_uvar, current)
        if current == prev and "$" in current:
            raise ValueError(f"Invalid variable syntax in die-roll specification: {current!r}")

    if "$" in current:
        raise ValueError("Maximum variable recursion depth (100) exceeded in die-roll specification.")
    return current


def add_to_die_roll_title(prefix: str, rollspec: str) -> str:
    """Prepend `prefix` (e.g. `(for Player)`) to the title portion of `rollspec`.

    Matches `AddToDieRollTitle` in `bin/mapper_legacy.tcl`.
    """
    prefix_clean = prefix.strip()
    if not prefix_clean:
        return rollspec
    if "=" in rollspec:
        eq_idx = rollspec.find("=")
        existing_title = rollspec[:eq_idx].strip()
        rest = rollspec[eq_idx + 1 :]
        if existing_title:
            return f"{prefix_clean} {existing_title}={rest}"
        return f"{prefix_clean}={rest}"
    return f"{prefix_clean}={rollspec}"


def prepare_die_roll(
    rollspec: str,
    extra: str = "",
    bank: DicePresetBank | None = None,
    for_user: str = "",
    local_user: str = "",
    my_names: list[str] | tuple[str, ...] | None = None,
    mobs_by_id: dict[str, dict[str, Any]] | None = None,
    mobs_by_name: dict[str, str] | None = None,
    to_gm: bool = False,
    to_all: bool = True,
    recipients: list[str] | None = None,
    req_id: str = "",
) -> dict[str, Any]:
    """Execute the full client-side die-roll preparation pipeline before sending `DR`.

    Handles:
    1. `#tablename` / `##tablename` lookup-table interception and `RequestID` encoding.
    2. Targeted-creature conditional modifiers (`TargetedModifiers`).
    3. Modifier concatenation (`apply_die_roll_mods`).
    4. Recursive variable expansion (`apply_die_roll_variables`).
    5. Delegated roll attribution (`(for <user>)`).

    Returns a dictionary with:
    - `rollspec`: final expanded specification string for `session.roll_Index(...)`
    - `request_id`: protocol `RequestID` (encoded with `#table;tkey;flags;id` for table rolls)
    - `recipients`: recipient list (`None` when `to_all` is True)
    - `to_gm`: boolean
    - `to_all`: boolean
    - `warning`: optional warning string (e.g. mismatched multi-target conditions)
    - `is_table_roll`: boolean
    """
    spec = rollspec.strip()
    effective_req_id = str(req_id or "")
    is_table_roll = False

    # 1. Check for #table or ##table invocation
    m_table = _TABLE_ROLL_RE.match(spec)
    if m_table:
        title_part = (m_table.group(1) or "").strip()
        glob_mark = m_table.group(2) or ""
        table_name = m_table.group(3)
        rest_part = (m_table.group(4) or "").strip()

        if bank is None:
            raise ValueError(f"Lookup table #{glob_mark}{table_name} is not defined.")
        table_map = bank.global_tables_by_name if glob_mark == "#" else bank.tables_by_name
        if table_name not in table_map:
            raise ValueError(f"Lookup table #{glob_mark}{table_name} was not found.")

        tbl_details = table_map[table_name]
        tbl_flags = "".join(tbl_details.get("flags") or [])
        tkey = bank.tkey if bank else ""
        effective_req_id = f"#{glob_mark}{table_name};{tkey};{tbl_flags};{effective_req_id}"
        spec = f"{title_part} {tbl_details['dieroll']} {rest_part}".strip()
        is_table_roll = True

    # 2. Resolve conditional modifiers from targeted creatures on the battle map
    cond_mods: set[str] = set()
    cond_vars: set[str] = set()
    cond_gvars: set[str] = set()
    warning: str | None = None
    if bank is not None and mobs_by_id is not None and mobs_by_name is not None:
        cond_mods, cond_vars, cond_gvars, warning = resolve_targeted_modifiers(
            for_user=for_user,
            my_names=list(my_names or ([local_user] if local_user else [])),
            mobs_by_id=mobs_by_id,
            mobs_by_name=mobs_by_name,
            modsym=bank.modsym,
        )

    # 3. Apply ad-hoc extra and enabled/conditional modifiers
    spec = apply_die_roll_mods(spec, extra=extra, bank=bank, cond_mods=cond_mods)

    # 4. Expand $var and $$var references recursively
    spec = apply_die_roll_variables(
        spec,
        bank=bank,
        cond_vars=cond_vars,
        cond_gvars=cond_gvars,
    )

    # 5. Add delegate attribution if rolling on behalf of another character
    if for_user and local_user and for_user != local_user:
        spec = add_to_die_roll_title(f"(for {for_user})", spec)

    final_recipients: list[str] | None
    if to_gm:
        final_recipients = []
        final_to_all = False
    elif to_all or not recipients:
        final_recipients = None
        final_to_all = True
    else:
        final_recipients = list(recipients)
        final_to_all = False

    return {
        "rollspec": spec,
        "request_id": effective_req_id,
        "recipients": final_recipients,
        "to_gm": bool(to_gm),
        "to_all": final_to_all,
        "warning": warning,
        "is_table_roll": is_table_roll,
    }


def resolve_table_roll_reply(
    payload: dict[str, Any],
    banks_by_tkey: dict[str, DicePresetBank] | None = None,
    default_bank: DicePresetBank | None = None,
    is_gm: bool = False,
) -> dict[str, Any] | None:
    """Inspect an incoming `ROLL` payload for a `#table` `RequestID` and resolve the table row.

    Matches the table-lookup callback in `DisplayDieRoll` (`bin/mapper_legacy.tcl`).
    Returns `None` if `payload` is a `Replay` or not a table roll, or a dictionary with:
    `text`, `markup`, `to_all`, `to_gm`, `recipients`, `table_name`, `result_value`.
    """
    if payload.get("Replay"):
        return None
    req_id = str(payload.get("RequestID", "") or "")
    if not req_id.startswith("#"):
        return None

    parts = req_id.split(";")
    if len(parts) < 3:
        return None

    raw_tbl_token = parts[0]
    tkey = parts[1]
    flags_str = parts[2]

    if raw_tbl_token.startswith("##"):
        is_global_tbl = True
        table_name = raw_tbl_token[2:]
    else:
        is_global_tbl = False
        table_name = raw_tbl_token[1:]

    bank = (banks_by_tkey or {}).get(tkey) or default_bank
    if bank is None:
        return None

    table_map = bank.global_tables_by_name if is_global_tbl else bank.tables_by_name
    tbl = table_map.get(table_name)
    if tbl is None:
        return None

    result_obj = (
        payload.get("Result")
        if isinstance(payload.get("Result"), dict)
        else (payload.get("RollData") if isinstance(payload.get("RollData"), dict) else {})
    )
    if result_obj.get("InvalidRequest"):
        return None
    raw_result = result_obj.get(
        "Result",
        payload.get("Result") if not isinstance(payload.get("Result"), dict) else None,
    )
    try:
        result_int = int(raw_result)
    except (TypeError, ValueError):
        return None

    pairs = tbl.get("pairs") or []
    if not pairs:
        raw_flat = tbl.get("table") or []
        pairs = [(raw_flat[i], raw_flat[i + 1]) for i in range(0, len(raw_flat) - 1, 2)]

    matched_text: str | None = None
    for bound_str, row_text in pairs:
        if bound_str == "*":
            matched_text = row_text
            break
        try:
            if result_int <= int(bound_str):
                matched_text = row_text
                break
        except ValueError:
            continue

    if matched_text is None:
        return None

    display_name = tbl.get("Description") or tbl.get("description") or table_name
    to_all = bool(payload.get("ToAll", False))
    to_gm = bool(payload.get("ToGM", False))
    recipients = list(payload.get("Recipients") or payload.get("Targets") or [])

    sender = str(
        payload.get("Sender")
        or (payload.get("Origin") if isinstance(payload.get("Origin"), str) else "")
    )
    if is_gm and to_gm and not to_all and not recipients and sender:
        recipients = [sender]

    return {
        "text": f"rolled {result_int} on {display_name}: {matched_text}",
        "markup": "m" in flags_str,
        "to_all": to_all,
        "to_gm": to_gm,
        "recipients": recipients,
        "table_name": table_name,
        "result_value": result_int,
    }


def parse_color_blocks(
    text: str,
    default_fg: str = "",
    default_bg: str = "",
) -> list[tuple[str, str, str]]:
    """Parse `‖`-delimited segments with optional `≡fg≡bg` color tags.

    Matches the color-block parser in `DisplayDieRoll` and `EditColorBoxTitle` (`bin/mapper_legacy.tcl`).
    When `fg` is specified without `bg`, `bg` is automatically darkened to 40% brightness.
    Returns a list of `(label, fg_hex_or_empty, bg_hex_or_empty)` tuples.
    """
    if not text:
        return []

    segments = text.split("\u2016")
    result: list[tuple[str, str, str]] = []
    for seg in segments:
        fields = seg.split("\u2261")
        label = fields[0]
        fg = default_fg
        bg = default_bg
        if len(fields) >= 2 and fields[1].strip():
            raw_fg = fields[1].strip()
            try:
                fg = color_to_hex(raw_fg)
            except ValueError:
                fg = raw_fg
            if len(fields) >= 3 and fields[2].strip():
                raw_bg = fields[2].strip()
                try:
                    bg = color_to_hex(raw_bg)
                except ValueError:
                    bg = raw_bg
            else:
                try:
                    bg = darken_color(fg, 40)
                except ValueError:
                    bg = default_bg
        elif len(fields) >= 3 and fields[2].strip():
            raw_bg = fields[2].strip()
            try:
                bg = color_to_hex(raw_bg)
                fg = contrasting_color(bg)
            except ValueError:
                bg = raw_bg
        result.append((label, fg, bg))
    return result


def build_color_box_title(segments: list[tuple[str, str, str]]) -> str:
    """Encode a list of `(label, fg, bg)` tuples into a `‖` and `≡` delimited title string."""
    parts: list[str] = []
    for label, fg, bg in segments:
        clean_label = str(label or "").replace("\u2016", "").replace("\u2261", "")
        clean_fg = str(fg or "").strip()
        clean_bg = str(bg or "").strip()
        if clean_fg and clean_bg:
            parts.append(f"{clean_label}\u2261{clean_fg}\u2261{clean_bg}")
        elif clean_fg:
            parts.append(f"{clean_label}\u2261{clean_fg}")
        elif clean_bg:
            parts.append(f"{clean_label}\u2261\u2261{clean_bg}")
        else:
            parts.append(clean_label)
    return "\u2016".join(parts)


class RollStatCollector:
    """Collects multi-roll results by `RequestID` and computes summary statistics when `N >= 3`.

    Matches `CollectRollStats` and `ReportRollStats` in `bin/mapper_legacy.tcl`.
    """

    def __init__(self) -> None:
        self._samples: dict[str, list[float]] = {}

    def collect(self, payload: dict[str, Any]) -> str | None:
        """Record a roll result and return the formatted stats line if the batch is complete (`N >= 3`)."""
        req_id = str(payload.get("RequestID", "") or "")
        result_obj = (
            payload.get("Result")
            if isinstance(payload.get("Result"), dict)
            else (payload.get("RollData") if isinstance(payload.get("RollData"), dict) else {})
        )
        raw_result = result_obj.get(
            "Result",
            payload.get("Result") if not isinstance(payload.get("Result"), dict) else None,
        )
        more_results = bool(
            payload.get("MoreResults", result_obj.get("MoreResults", False))
        )

        if not req_id:
            return None

        try:
            val = float(raw_result)
        except (TypeError, ValueError):
            if not more_results:
                self._samples.pop(req_id, None)
            return None

        bucket = self._samples.setdefault(req_id, [])
        bucket.append(val)

        if more_results:
            return None

        values = self._samples.pop(req_id, [])
        if len(values) < 3:
            return None
        return self.format_stats(values)

    @staticmethod
    def format_stats(values: list[float]) -> str:
        """Compute `N`, `μ` (mean), `σ` (sample std dev), `Md` (median), `Mo` (mode), and `Σ` (sum)."""
        n = len(values)
        if n == 0:
            return ""
        total = sum(values)
        mean = total / n
        if n > 1:
            variance = sum((x - mean) ** 2 for x in values) / (n - 1)
            stddev = math.sqrt(variance)
        else:
            stddev = 0.0

        sorted_vals = sorted(values)
        mid = n // 2
        if n % 2 == 1:
            median = sorted_vals[mid]
        else:
            median = (sorted_vals[mid - 1] + sorted_vals[mid]) / 2.0

        counts: dict[float, int] = {}
        for v in sorted_vals:
            counts[v] = counts.get(v, 0) + 1
        max_freq = max(counts.values())
        if max_freq <= 1:
            mode_str = "none"
        else:
            modes = [
                f"{int(k) if k == int(k) else k:g}"
                for k, c in counts.items()
                if c == max_freq
            ]
            mode_str = ",".join(modes)

        return (
            f"N={n} "
            f"\u03bc={mean:g} "
            f"\u03c3={stddev:g} "
            f"Md={median:g} "
            f"Mo={mode_str} "
            f"\u03a3={total:g}"
        )


@functools.lru_cache(maxsize=32) if "functools" in globals() else (lambda f: f)
def _load_default_icon_data_uri(icon_name: str) -> str:
    """Return a `data:image/png;base64,...` URI for an icon in `assets/icons`."""
    icons_dir = Path(__file__).resolve().parents[1] / "assets" / "icons"
    path = icons_dir / f"{icon_name}.png"
    if not path.is_file():
        return ""
    b64 = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:image/png;base64,{b64}"


_COMPONENT_KEY_ALIASES: dict[str, str] = {
    "origin": "from",
    "target": "to",
    "GM": "to",
    "chat": "normal",
    "default": "normal",
}


def get_component_style_dict(
    component_key: str,
    prefs: dict[str, Any] | None = None,
    dark: bool | None = None,
) -> dict[str, Any]:
    """Return the resolved style dictionary for one of the 39 die-roll/chat components."""
    if dark is None:
        dark = bool((prefs or {}).get("dark", True))
    theme_key = "dark" if dark else "light"

    styles_root = (prefs or {}).get("styles") or default_styles()
    dieroll_styles = styles_root.get("dierolls") or default_styles()["dierolls"]
    components = dieroll_styles.get("components") or default_styles()["dierolls"]["components"]

    canonical_key = _COMPONENT_KEY_ALIASES.get(component_key, component_key)
    comp = (
        components.get(component_key)
        or components.get(canonical_key)
        or default_styles()["dierolls"]["components"].get(
            canonical_key,
            components.get("normal", {}),
        )
    )

    # Support both `comp["fg"][theme_key]` (canonical profile.py layout) and `comp[theme_key]["fg"]`
    fg_entry = comp.get("fg")
    bg_entry = comp.get("bg")
    if isinstance(fg_entry, dict):
        fg_val = str(fg_entry.get(theme_key) or "")
    elif isinstance(comp.get(theme_key), dict):
        fg_val = str(comp[theme_key].get("fg") or "")
    else:
        fg_val = str(fg_entry or "")

    if isinstance(bg_entry, dict):
        bg_val = str(bg_entry.get(theme_key) or "")
    elif isinstance(comp.get(theme_key), dict):
        bg_val = str(comp[theme_key].get("bg") or "")
    else:
        bg_val = str(bg_entry or "")

    fonts_root = (prefs or {}).get("fonts") or default_fonts()
    font_key = str(comp.get("font") or "Normal")
    font_spec = (
        fonts_root.get(font_key)
        or default_fonts().get(font_key)
        or default_fonts().get("Normal", {"family": "Helvetica", "size": 12})
    )

    is_bold = bool(comp.get("bold", False)) or bool(int(font_spec.get("weight", 0) or 0))
    is_italic = bool(comp.get("italic", False)) or bool(int(font_spec.get("slant", 0) or 0))
    is_underline = bool(comp.get("underline", False)) or bool(font_spec.get("underline", False))
    is_overstrike = bool(comp.get("overstrike", False)) or bool(font_spec.get("overstrike", False))

    return {
        "fg": fg_val,
        "bg": bg_val,
        "family": str(font_spec.get("family") or "Helvetica"),
        "size": float(font_spec.get("size") or 12.0),
        "bold": is_bold,
        "italic": is_italic,
        "underline": is_underline,
        "overstrike": is_overstrike,
        "format": str(comp.get("format") or ""),
        "offset": int(comp.get("offset") or 0),
    }


def format_component_html(
    text: str,
    component_key: str,
    prefs: dict[str, Any] | None = None,
    dark: bool | None = None,
    override_fg: str = "",
    override_bg: str = "",
    apply_format_pattern: bool = True,
) -> str:
    """Render `text` as an HTML `<span>` styled according to the 39-component `dierolls` schema."""
    st = get_component_style_dict(component_key, prefs=prefs, dark=dark)
    fmt = st["format"] if apply_format_pattern else ""
    if fmt:
        formatted_text = fmt.replace("%s", text) if "%s" in fmt else fmt
    else:
        formatted_text = text
    escaped = html.escape(formatted_text)

    css: list[str] = []
    fg = override_fg or st["fg"]
    bg = override_bg or st["bg"]
    if fg:
        css.append(f"color:{fg}")
    if bg:
        css.append(f"background-color:{bg};padding:0 2px;border-radius:2px")
    if st["family"]:
        css.append(f"font-family:'{st['family']}'")
    if st["size"]:
        css.append(f"font-size:{st['size']:g}pt")
    if st["bold"]:
        css.append("font-weight:bold")
    if st["italic"]:
        css.append("font-style:italic")

    decorations: list[str] = []
    if st["underline"]:
        decorations.append("underline")
    if st["overstrike"]:
        decorations.append("line-through")
    if decorations:
        css.append(f"text-decoration:{' '.join(decorations)}")

    if st["offset"] > 0:
        css.append("vertical-align:super;font-size:80%")
    elif st["offset"] < 0:
        css.append("vertical-align:sub;font-size:80%")

    style_attr = ";".join(css)
    return f'<span style="{style_attr}">{escaped}</span>'


def render_markup_text_html(
    text: str,
    base_component: str = "chat",
    prefs: dict[str, Any] | None = None,
    dark: bool | None = None,
) -> str:
    """Render GMA inline markup (`**bold**`, `//italic//`, `__underline__`, `~~strike~~`, `` `code` ``)."""
    # Tokenize inline markup blocks while escaping plain text
    pattern = re.compile(
        r"(\*\*(.+?)\*\*|//(.+?)//|__(.+?)__|~~(.+?)~~|`([^`]+)`)",
        re.DOTALL,
    )
    out: list[str] = []
    pos = 0
    for m in pattern.finditer(text):
        if m.start() > pos:
            out.append(format_component_html(text[pos : m.start()], base_component, prefs=prefs, dark=dark))
        if m.group(2) is not None:
            out.append(format_component_html(m.group(2), "bold", prefs=prefs, dark=dark))
        elif m.group(3) is not None:
            out.append(format_component_html(m.group(3), "italic", prefs=prefs, dark=dark))
        elif m.group(4) is not None:
            out.append(format_component_html(m.group(4), "underline", prefs=prefs, dark=dark))
        elif m.group(5) is not None:
            st = get_component_style_dict(base_component, prefs=prefs, dark=dark)
            out.append(f'<span style="text-decoration:line-through;color:{st["fg"]}">{html.escape(m.group(5))}</span>')
        elif m.group(6) is not None:
            out.append(format_component_html(m.group(6), "code", prefs=prefs, dark=dark))
        pos = m.end()
    if pos < len(text):
        out.append(format_component_html(text[pos:], base_component, prefs=prefs, dark=dark))
    return "".join(out) if out else format_component_html(text, base_component, prefs=prefs, dark=dark)


def _icon_img_tag(icon_name: str, icon_data_uris: dict[str, str] | None = None) -> str:
    uri = (icon_data_uris or {}).get(icon_name) or _load_default_icon_data_uri(icon_name)
    if not uri:
        return ""
    return f'<img src="{uri}" width="16" height="16" style="vertical-align:middle;margin-right:2px;" />'


def render_roll_components_html(
    components: list[Any],
    prefs: dict[str, Any] | None = None,
    dark: bool | None = None,
) -> str:
    """Render a server `Details` component list (`[{"Type": ..., "Value": ...}, ...]`) into HTML.

    Matches the component loop in `DisplayDieRoll` (`bin/mapper_legacy.tcl`).
    Supports `‖` and `≡fg≡bg` color blocks on any component value.
    """
    parts: list[str] = []
    for item in components:
        if isinstance(item, dict):
            ctype = str(item.get("Type") or item.get("type") or "default")
            cval = item.get("Value", item.get("value", ""))
        elif isinstance(item, (list, tuple)) and len(item) >= 2:
            ctype = str(item[0])
            cval = item[1]
        else:
            ctype = "default"
            cval = str(item)

        if ctype in SYMBOLS:
            cval_str = SYMBOLS[ctype]
        else:
            cval_str = str(cval)

        if "\u2016" in cval_str or "\u2261" in cval_str:
            blocks = parse_color_blocks(cval_str)
            blk_spans: list[str] = []
            for blk_text, blk_fg, blk_bg in blocks:
                blk_spans.append(
                    format_component_html(
                        blk_text,
                        ctype,
                        prefs=prefs,
                        dark=dark,
                        override_fg=blk_fg,
                        override_bg=blk_bg,
                        apply_format_pattern=(not blk_fg and not blk_bg),
                    )
                )
            parts.append("".join(blk_spans))
        else:
            parts.append(format_component_html(cval_str, ctype, prefs=prefs, dark=dark))

    return "".join(parts)


def render_roll_payload_html(
    payload: dict[str, Any],
    prefs: dict[str, Any] | None = None,
    dark: bool | None = None,
    stats_line: str | None = None,
    icon_data_uris: dict[str, str] | None = None,
    group_pos: str = "",
) -> str:
    """Render a complete `ROLL` protocol payload into rich HTML matching `DisplayDieRoll`.

    Supports both GMA wire payloads (`Sender`, `Result: {Result, Details, InvalidRequest, ResultSuppressed}`)
    and synthetic test payloads (`RollData`).
    """
    result_obj = (
        payload.get("Result")
        if isinstance(payload.get("Result"), dict)
        else (payload.get("RollData") if isinstance(payload.get("RollData"), dict) else {})
    )
    sender = str(
        payload.get("Sender")
        or (payload.get("Origin") if isinstance(payload.get("Origin"), str) else "")
        or result_obj.get("Sender")
        or (result_obj.get("Origin") if isinstance(result_obj.get("Origin"), str) else "")
        or "Player"
    )
    recipients = list(payload.get("Recipients") or payload.get("Targets") or [])
    to_gm = bool(payload.get("ToGM", result_obj.get("ToGM", False)))
    to_all = bool(payload.get("ToAll", result_obj.get("ToAll", not to_gm and not recipients)))

    title = str(payload.get("Title") or result_obj.get("Title") or "")
    result_val = result_obj.get(
        "Result",
        payload.get("Result") if not isinstance(payload.get("Result"), dict) else "",
    )
    details = result_obj.get("Details") or payload.get("Details") or []
    is_invalid = bool(result_obj.get("InvalidRequest", False))
    is_blind = bool(result_obj.get("ResultSuppressed", False))

    # Determine outcome icon by scanning Details component types (matching DisplayDieRoll lines 12380-12391)
    die_icon = "die16"
    if isinstance(details, list):
        for dd in details:
            if not isinstance(dd, dict):
                continue
            dtype = str(dd.get("Type") or "")
            if dtype == "critlabel":
                die_icon = "die16c"
                break
            if dtype == "success":
                die_icon = "die16success"
                break
            if dtype == "fail":
                die_icon = "die16fail"
                break
            if dtype == "short":
                die_icon = "die16fail"
            elif dtype in ("exceeded", "met"):
                die_icon = "die16success"

    if die_icon == "die16":
        if bool(result_obj.get("FullMax") or result_obj.get("Max")):
            die_icon = "die16c"
        elif bool(result_obj.get("Success")):
            die_icon = "die16success"
        elif bool(result_obj.get("Fail") or result_obj.get("Miss")):
            die_icon = "die16fail"

    if is_blind or is_invalid or (to_gm and not to_all):
        die_icon = "dieb16"

    bracket_html = ""
    if group_pos in ("dbracket_t", "dbracket_m", "dbracket_b", "dbracket__"):
        bracket_html = _icon_img_tag(group_pos, icon_data_uris)

    icon_html = _icon_img_tag(die_icon, icon_data_uris)

    # Timestamp if present
    ts_html = ""
    sent_time = payload.get("Sent") or payload.get("Time")
    if isinstance(sent_time, (int, float)) and sent_time > 0:
        dt = datetime.datetime.fromtimestamp(sent_time)
        ts_html = format_component_html(dt.strftime("%H:%M:%S "), "timestamp", prefs=prefs, dark=dark)

    # Leading [fullresult] badge (matching DisplayDieRoll line 12415)
    fullresult_html = ""
    if not is_blind and not is_invalid and result_val is not None and str(result_val) != "":
        fullresult_html = format_component_html(str(result_val), "fullresult", prefs=prefs, dark=dark) + " "

    # Sender and recipient attribution
    sender_html = format_component_html(sender, "origin", prefs=prefs, dark=dark)
    recip_html = ""
    if to_gm and not to_all:
        recip_html = " \u2192 " + format_component_html("GM", "GM", prefs=prefs, dark=dark)
    elif not to_all and recipients:
        recip_html = " \u2192 " + format_component_html(
            ", ".join(str(t) for t in recipients), "target", prefs=prefs, dark=dark
        )

    # Title with color-box support (matching DisplayDieRoll lines 12419-12450)
    title_html = ""
    if title:
        title_style = get_component_style_dict("title", prefs=prefs, dark=dark)
        default_title_fg = title_style["fg"] or ("#ffffff" if dark else "#000000")
        try:
            default_title_bg = darken_color(default_title_fg, 40)
        except ValueError:
            default_title_bg = ""
        blocks = parse_color_blocks(title, default_fg=default_title_fg, default_bg=default_title_bg)
        rendered_blocks: list[str] = []
        for blk_label, blk_fg, blk_bg in blocks:
            rendered_blocks.append(
                format_component_html(
                    blk_label,
                    "title",
                    prefs=prefs,
                    dark=dark,
                    override_fg=blk_fg,
                    override_bg=blk_bg,
                )
            )
        title_html = " " + " ".join(rendered_blocks) + " "

    # Detailed breakdown (server Details already includes Type='result', Type='separator' ('='), etc.)
    if isinstance(details, list) and details:
        details_html = (" " if not title_html else "") + render_roll_components_html(
            details, prefs=prefs, dark=dark
        )
    elif isinstance(details, str) and details:
        details_html = " : " + format_component_html(details, "default", prefs=prefs, dark=dark)
    else:
        spec_str = str(result_obj.get("RollSpec") or payload.get("RollSpec") or "")
        details_html = (
            " : " + format_component_html(spec_str, "default", prefs=prefs, dark=dark)
            if spec_str
            else ""
        )

    line_html = (
        f"<div>{ts_html}{icon_html}{bracket_html}{fullresult_html}"
        f"{sender_html}{recip_html}{title_html}{details_html}</div>"
    )
    if stats_line:
        stats_html = format_component_html(stats_line, "stats", prefs=prefs, dark=dark)
        line_html += f'<div style="margin-left:20px;">{stats_html}</div>'
    return line_html


def render_chat_payload_html(
    payload: dict[str, Any],
    prefs: dict[str, Any] | None = None,
    dark: bool | None = None,
    is_pinned_view: bool = False,
    is_locally_pinned: bool = False,
    is_gm: bool = False,
) -> str:
    """Render a `TO` chat payload into rich HTML with action links (`pin:`, `unpin:`, `hide:`, `del:`).

    Matches `_render_chat_message` in `bin/mapper_legacy.tcl`.
    """
    msg_id = payload.get("MessageID")
    sender = str(
        payload.get("Sender")
        or (payload.get("Origin") if isinstance(payload.get("Origin"), str) else "")
        or "Server"
    )
    text = str(payload.get("Text") or "")
    to_gm = bool(payload.get("ToGM", False))
    to_all = bool(payload.get("ToAll", not to_gm and not payload.get("Recipients")))
    recipients = list(payload.get("Recipients") or payload.get("Targets") or [])
    markup = bool(payload.get("Markup", False))
    global_pin = bool(payload.get("Pin", False))

    ts_html = ""
    sent_time = payload.get("Sent") or payload.get("Time")
    if isinstance(sent_time, (int, float)) and sent_time > 0:
        dt = datetime.datetime.fromtimestamp(sent_time)
        ts_html = format_component_html(dt.strftime("%H:%M:%S "), "timestamp", prefs=prefs, dark=dark)

    origin_html = format_component_html(sender, "origin", prefs=prefs, dark=dark)
    recip_html = ""
    if to_gm and not to_all:
        recip_html = " \u2192 " + format_component_html("GM", "GM", prefs=prefs, dark=dark)
    elif not to_all and recipients:
        recip_html = " \u2192 " + format_component_html(
            ", ".join(str(r) for r in recipients), "target", prefs=prefs, dark=dark
        )

    body_html = (
        render_markup_text_html(text, "chat", prefs=prefs, dark=dark)
        if markup
        else format_component_html(text, "chat", prefs=prefs, dark=dark)
    )

    actions_html = ""
    if msg_id is not None:
        links: list[str] = []
        if is_pinned_view:
            if is_locally_pinned:
                links.append(f'<a href="unpin:{msg_id}" title="Unpin locally" style="text-decoration:none;">[\u2606]</a>')
            elif global_pin:
                links.append(f'<a href="hide:{msg_id}" title="Dismiss pinned message" style="text-decoration:none;">[\u00d7]</a>')
        else:
            if is_locally_pinned:
                links.append(f'<a href="unpin:{msg_id}" title="Unpin locally" style="text-decoration:none;">[\u2605]</a>')
            else:
                links.append(f'<a href="pin:{msg_id}" title="Pin locally" style="text-decoration:none;">[\u2606]</a>')
        if is_gm:
            links.append(f'<a href="del:{msg_id}" title="Delete message for all" style="text-decoration:none;">[\U0001f5d1]</a>')
        else:
            links.append(f'<a href="hide:{msg_id}" title="Hide message locally" style="text-decoration:none;">[\u00d7]</a>')
        if links:
            actions_html = " <span style=\"font-size:85%;opacity:0.75;\">" + " ".join(links) + "</span>"

    pin_badge = "\U0001f4cc " if (global_pin or is_locally_pinned) and is_pinned_view else ""
    return f"<div>{pin_badge}{ts_html}{origin_html}{recip_html}: {body_html}{actions_html}</div>"


class ChatHistoryManager:
    """Manages chat/roll message history, pinned messages, `CC` clearing, `Y2` pruning, and transcripts.

    Matches `DisplayChatMessage`, `ClearChatHistory`, `PruneChatHistory`, `TranscribeChat`,
    and `TranscribeDieRoll` in `bin/mapper_legacy.tcl`.
    """

    def __init__(self, transcript_path: str | Path | None = None) -> None:
        self.entries: list[dict[str, Any]] = []
        self.pin_list: set[int] = set()
        self.hide_list: set[int] = set()
        self.last_displayed_date: str = ""
        self.transcript_path: Path | None = Path(transcript_path) if transcript_path else None

    def add_chat_message(self, payload: dict[str, Any]) -> dict[str, Any]:
        """Record an incoming `TO` chat message and optionally write to the transcript file."""
        entry = copy.deepcopy(payload)
        entry.setdefault("kind", "chat")
        self.entries.append(entry)
        self.transcribe_chat(entry)
        return entry

    def add_roll_message(self, payload: dict[str, Any], stats_line: str | None = None) -> dict[str, Any]:
        """Record an incoming `ROLL` message and optionally write to the transcript file."""
        entry = copy.deepcopy(payload)
        entry["kind"] = "roll"
        if stats_line:
            entry["stats_line"] = stats_line
        self.entries.append(entry)
        self.transcribe_die_roll(entry, stats_line=stats_line)
        return entry

    def add_notice(self, text: str) -> dict[str, Any]:
        """Record a local notice message (e.g. peer join/leave or conditional modifier warning)."""
        entry = {
            "kind": "notice",
            "Text": text,
            "Sent": datetime.datetime.now().timestamp(),
        }
        self.entries.append(entry)
        return entry

    def pin_message(self, msg_id: int) -> None:
        """Pin a message locally by `MessageID`."""
        self.pin_list.add(int(msg_id))
        self.hide_list.discard(int(msg_id))

    def unpin_message(self, msg_id: int) -> None:
        """Remove a local pin for `msg_id`."""
        self.pin_list.discard(int(msg_id))

    def hide_message(self, msg_id: int) -> None:
        """Hide a message or dismiss a globally pinned message locally."""
        self.hide_list.add(int(msg_id))
        self.pin_list.discard(int(msg_id))

    def visible_entries(self) -> list[dict[str, Any]]:
        """Return all non-hidden history entries in chronological order."""
        out: list[dict[str, Any]] = []
        for entry in self.entries:
            mid = entry.get("MessageID")
            if mid is not None:
                try:
                    if int(mid) in self.hide_list:
                        continue
                except (TypeError, ValueError):
                    pass
            out.append(entry)
        return out

    def pinned_entries(self) -> list[dict[str, Any]]:
        """Return all currently pinned (`Pin=True` or locally pinned) non-hidden chat messages."""
        out: list[dict[str, Any]] = []
        for entry in self.entries:
            if entry.get("kind") != "chat":
                continue
            mid = entry.get("MessageID")
            if mid is None:
                continue
            try:
                mid_int = int(mid)
            except (TypeError, ValueError):
                continue
            if mid_int in self.hide_list:
                continue
            if bool(entry.get("Pin", False)) or mid_int in self.pin_list:
                out.append(entry)
        return out

    def clear_chat_history(
        self,
        target: int = 0,
        target_messages: list[int] | None = None,
        do_all: bool = False,
    ) -> None:
        """Clear chat/roll history according to all 4 GMA `CC` protocol modes.

        Matches `ClearChatHistory` in `bin/mapper_legacy.tcl`:
        1. `target_messages` non-empty: delete specific `MessageID`s.
        2. `target == 0`: clear all messages (keeping pinned messages unless `do_all` is True).
        3. `target < 0`: keep only the most recent `abs(target)` chat messages.
        4. `target > 0`: remove messages with `MessageID < target`.
        """
        if target_messages:
            target_set = {int(m) for m in target_messages}
            self.entries = [
                e
                for e in self.entries
                if e.get("MessageID") is None
                or int(e["MessageID"]) not in target_set
                or (not do_all and (bool(e.get("Pin")) or int(e["MessageID"]) in self.pin_list))
            ]
            if do_all:
                self.pin_list -= target_set
            return

        if target == 0:
            if do_all:
                self.entries = []
                self.pin_list.clear()
                self.hide_list.clear()
            else:
                self.entries = [
                    e
                    for e in self.entries
                    if e.get("MessageID") is not None
                    and (bool(e.get("Pin")) or int(e["MessageID"]) in self.pin_list)
                ]
            return

        if target < 0:
            keep_count = abs(int(target))
            chat_with_ids = [
                e for e in self.entries if e.get("MessageID") is not None
            ]
            keep_ids = {
                int(e["MessageID"]) for e in chat_with_ids[-keep_count:]
            }
            self.entries = [
                e
                for e in self.entries
                if e.get("MessageID") is None
                or int(e["MessageID"]) in keep_ids
                or (not do_all and (bool(e.get("Pin")) or int(e["MessageID"]) in self.pin_list))
            ]
            return

        if target > 0:
            cutoff = int(target)
            self.entries = [
                e
                for e in self.entries
                if e.get("MessageID") is None
                or int(e["MessageID"]) >= cutoff
                or (not do_all and (bool(e.get("Pin")) or int(e["MessageID"]) in self.pin_list))
            ]

    def prune_chat_history(self, min_id: int | None, max_id: int | None) -> None:
        """Remove messages outside `[min_id, max_id]` on `Y2` server sync.

        Matches `PruneChatHistory` in `bin/mapper_legacy.tcl`.
        """
        if min_id is None and max_id is None:
            return
        kept: list[dict[str, Any]] = []
        for e in self.entries:
            mid = e.get("MessageID")
            if mid is None:
                kept.append(e)
                continue
            try:
                mid_int = int(mid)
            except (TypeError, ValueError):
                kept.append(e)
                continue
            if min_id is not None and mid_int < int(min_id):
                self.pin_list.discard(mid_int)
                continue
            if max_id is not None and mid_int > int(max_id):
                self.pin_list.discard(mid_int)
                continue
            kept.append(e)
        self.entries = kept

    def transcribe_chat(self, payload: dict[str, Any]) -> None:
        """Append a chat message line to `transcript_path` if configured."""
        if not self.transcript_path:
            return
        sender = str(
            payload.get("Sender")
            or (payload.get("Origin") if isinstance(payload.get("Origin"), str) else "")
            or "Server"
        )
        text = str(payload.get("Text") or "")
        line = f"[CHAT] <{sender}> {text}\n"
        try:
            with self.transcript_path.open("a", encoding="utf-8") as fh:
                fh.write(line)
        except OSError:
            pass

    def transcribe_die_roll(self, payload: dict[str, Any], stats_line: str | None = None) -> None:
        """Append a die-roll result line to `transcript_path` if configured."""
        if not self.transcript_path:
            return
        result_obj = (
            payload.get("Result")
            if isinstance(payload.get("Result"), dict)
            else (payload.get("RollData") if isinstance(payload.get("RollData"), dict) else {})
        )
        sender = str(
            payload.get("Sender")
            or (payload.get("Origin") if isinstance(payload.get("Origin"), str) else "")
            or "Player"
        )
        title = str(payload.get("Title") or result_obj.get("Title") or "")
        result_val = result_obj.get(
            "Result",
            payload.get("Result") if not isinstance(payload.get("Result"), dict) else "",
        )
        line = f"[ROLL] {sender}: {title} = {result_val}\n"
        if stats_line:
            line += f"[STATS] {stats_line}\n"
        try:
            with self.transcript_path.open("a", encoding="utf-8") as fh:
                fh.write(line)
        except OSError:
            pass


# Reference documentation for ShowDiceSyntax and ShowDiceModifierHelp dialogs
DICE_SYNTAX_HELP_SECTIONS: list[tuple[str, str]] = [
    (
        "Overview & Title",
        """<h3>Die Roll Expression Syntax</h3>
<p>A die-roll specification has the general form:</p>
<pre>[Title =] Expression [| Option | Option ...]</pre>
<ul>
  <li><b>Title =</b> Optional label shown before the roll result. Supports multi-segment color boxes separated by <code>‖</code> with <code>≡fg≡bg</code> colors.</li>
  <li><b>#tablename / ##tablename</b> Rolls on a user (<code>#</code>) or system (<code>##</code>) lookup table.</li>
  <li><b>$var / $$var</b> Expands a user (<code>$var</code>) or global (<code>$$var</code>) modifier variable when checked.</li>
</ul>""",
    ),
    (
        "Dice & Operators",
        """<h3>Dice &amp; Arithmetic Operators</h3>
<table border="1" cellspacing="0" cellpadding="4">
  <tr><th>Syntax</th><th>Meaning</th></tr>
  <tr><td><code>[N]dS</code></td><td>Roll <i>N</i> dice with <i>S</i> sides (e.g., <code>1d20</code>, <code>3d6</code>, <code>d%</code>).</td></tr>
  <tr><td><code>+ - * / //</code></td><td>Addition, subtraction, multiplication, division, and integer division.</td></tr>
  <tr><td><code>best N</code> / <code>worst N</code></td><td>Keep the highest or lowest <i>N</i> dice from the roll.</td></tr>
  <tr><td><code>min V</code> / <code>max V</code></td><td>Clamp total expression result to at least or at most <i>V</i>.</td></tr>
  <tr><td><code>minroll V</code> / <code>maxroll V</code></td><td>Clamp each individual die to at least or at most <i>V</i>.</td></tr>
  <tr><td><code>reroll L</code> / <code>reroll &lt;= L</code></td><td>Reroll dice at or below <i>L</i> once.</td></tr>
  <tr><td><code>explode [N]</code></td><td>Explode dice rolling their maximum value.</td></tr>
  <tr><td><code>bonus D</code> / <code>malus D</code></td><td>Add bonus/penalty dice (e.g. 5e Advantage/Disadvantage or Boon/Bane).</td></tr>
</table>""",
    ),
    (
        "Roll Options (|)",
        """<h3>Pipe-Delimited Roll Options (<code>|</code>)</h3>
<table border="1" cellspacing="0" cellpadding="4">
  <tr><th>Option</th><th>Description</th></tr>
  <tr><td><code>|c</code> or <code>|cN</code></td><td>Critical threat on natural 20 (or <code>N..20</code>) with automatic confirmation roll.</td></tr>
  <tr><td><code>|dc=N</code></td><td>Compare total against difficulty class / target number <i>N</i>.</td></tr>
  <tr><td><code>|sf</code></td><td>Pathfinder 2e / Starfinder 4-tier degrees of success (critical success/success/failure/critical failure).</td></tr>
  <tr><td><code>|repeat=N</code> or <code>|xN</code></td><td>Repeat the entire roll <i>N</i> times (triggers statistical summary when <i>N &ge; 3</i>).</td></tr>
  <tr><td><code>|total</code></td><td>Sum repeated rolls into a grand total.</td></tr>
  <tr><td><code>| {label}</code></td><td>Attach a descriptive label to the preceding expression or modifier.</td></tr>
</table>""",
    ),
]

DICE_MODIFIER_HELP_TEXT: str = """<h3>Die Roll Modifiers &amp; Variables</h3>
<p>Modifiers allow you to toggle situational bonuses, penalties, and variables on or off with a single click in the <b>Preset Rolls</b> panel.</p>
<ul>
  <li><b>Standard Modifiers (no variable name):</b> When checked, the modifier's expression is appended to every roll in sequence order (e.g., <code>+2 { flanking}</code>). If the modifier is marked <b>Global</b>, the base roll expression is wrapped in parentheses before applying the modifier.</li>
  <li><b>User Variables (<code>$var</code>):</b> When given a variable name (e.g., <code>pa</code>), the modifier's value is substituted wherever <code>$pa</code> or <code>${pa}</code> appears in a preset roll, <i>only</i> when the checkbox is enabled (evaluates to empty when unchecked).</li>
  <li><b>Global Variables (<code>$$var</code>):</b> Shared across all character tabs in the session. Referenced in presets via <code>$$var</code> or <code>$${var}</code>.</li>
  <li><b>Targeted Creature Modifiers:</b> When attacking a targeted creature on the map that has active conditional modifiers (such as Cover or Flanking), matching modifiers or variables are automatically activated for that roll.</li>
</ul>"""
