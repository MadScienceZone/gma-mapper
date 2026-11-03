"""Creature Token & Battle Map Right-Click Context Menu (`bin/mapper_legacy.tcl` port).

Provides:
- Pure-Python token mutation helpers (conditions, elevation, size/polymorph, reach, movement mode,
  tags/notes, death/remove, targeting, and `#N-M` multi-creature spawning).
- Qt `QMenu` builder (`build_canvas_context_menu`) supporting single-creature, multi-creature,
  and "(all of the above)" mass operations.
"""

from __future__ import annotations

import random
import re
from typing import Any, Callable

from gma_mapper.core.util import letter_label
from gma_mapper.core.zones import (
    creature_displayed_size,
    creature_size_params,
    full_creature_area_info,
    reach_matrix,
    skin_comment,
    skin_is_default,
    skin_size_only,
)
from gma_mapper.net.protocol import from_enum, new_dict, new_id, to_enum
from gma_mapper.ui.canvas.items import MARKER_COLOR, MARKER_DESCRIPTION, MARKER_SHAPE

SIZE_MENU_CHOICES: list[tuple[list[str], str]] = [
    (["F", "f"], "Fine"),
    (["D", "d"], "Diminutive"),
    (["T", "t"], "Tiny"),
    (["S", "s"], "Small"),
    (["M", "m"], "Medium"),
    (["l"], "Large (long)"),
    (["L"], "Large (tall)"),
    (["L0", "l0"], "Large (no reach)"),
    (["h"], "Huge (long)"),
    (["H"], "Huge (tall)"),
    (["g"], "Gargantuan (long)"),
    (["G"], "Gargantuan (tall)"),
    (["c"], "Colossal (long)"),
    (["C"], "Colossal (tall)"),
]

ELEVATION_MENU_CHOICES: list[tuple[str, str]] = [
    ("0", "(Ground)"),
    ("+30", "+30 ft"),
    ("+20", "+20 ft"),
    ("+10", "+10 ft"),
    ("+5", "+5 ft"),
    ("-5", "-5 ft"),
    ("-10", "-10 ft"),
    ("-20", "-20 ft"),
    ("-30", "-30 ft"),
    ("-40", "-40 ft"),
    ("-60", "-60 ft"),
]

MOVEMENT_MODE_CHOICES: list[tuple[str, str]] = [
    ("", "Land"),
    ("burrow", "Burrow"),
    ("climb", "Climb"),
    ("fly", "Fly"),
    ("swim", "Swim"),
]

REACH_FEET_CHOICES: list[tuple[int, int]] = [
    (0, 0),
    (5, 1),
    (10, 2),
    (15, 3),
    (20, 4),
    (25, 5),
    (30, 6),
    (35, 7),
    (40, 8),
    (45, 9),
]


def compute_elevation_change(current_elev: int, elev_spec: str | int) -> int:
    """Compute new elevation in feet from an absolute (`'0'`, `'15'`) or relative (`'+10'`, `'-5'`) spec.

    Matches `ElevatePerson` in `bin/mapper_legacy.tcl`.
    """
    if isinstance(elev_spec, int):
        return elev_spec
    s = str(elev_spec).strip()
    if s.startswith(("+", "-")):
        return int(current_elev) + int(s)
    return int(s)


def toggle_status_condition(
    mob_data: dict[str, Any], condition: str
) -> dict[str, Any]:
    """Toggle `condition` (`'__clear__'`, `'__hide__'`, or status name) on `mob_data`.

    Returns the dictionary of changed attributes (`{'Hidden': ...}` or `{'StatusList': ...}`)
    suitable for `OA` (`update_obj_attributes`).
    """
    if condition == "__hide__":
        new_hidden = not bool(mob_data.get("Hidden", False))
        mob_data["Hidden"] = new_hidden
        return {"Hidden": new_hidden}

    if condition == "__clear__":
        mob_data["StatusList"] = []
        return {"StatusList": []}

    cur_list = list(mob_data.get("StatusList") or [])
    if condition in cur_list:
        cur_list.remove(condition)
    else:
        cur_list.append(condition)
    mob_data["StatusList"] = cur_list
    return {"StatusList": cur_list}


def default_custom_reach(size_code: str) -> dict[str, Any]:
    """Return default `CustomReach` dict (`{'Enabled': False, 'Natural': ..., 'Extended': ...}`)."""
    tpl = reach_matrix(size_code)
    nat = tpl.natural * 5 if tpl else 0
    ext = tpl.extended * 5 if tpl else 0
    return {"Enabled": False, "Natural": nat, "Extended": ext}


def apply_custom_reach_change(
    mob_data: dict[str, Any], mode: str, value: int
) -> dict[str, Any]:
    """Apply a reach change (`-setnat`, `-setext`, `-incrnat`, `-incrext`, `-setreach`) to `mob_data`.

    Matches `SetCustomReach` in `bin/mapper_legacy.tcl`.
    Returns the dictionary of changed attributes (`{'CustomReach': ...}` or `{'Reach': ...}`).
    """
    if mode == "-setreach":
        reach_val = max(0, min(2, int(value)))
        mob_data["Reach"] = reach_val
        return {"Reach": reach_val}

    disp_size = creature_displayed_size(mob_data)
    custom = dict(mob_data.get("CustomReach") or {})
    if not custom or "Natural" not in custom or "Extended" not in custom:
        custom = default_custom_reach(disp_size)

    if mode == "-setnat":
        custom["Natural"] = max(0, int(value))
        custom["Enabled"] = True
    elif mode == "-setext":
        custom["Extended"] = max(0, int(value))
        custom["Enabled"] = True
    elif mode == "-incrnat":
        # value is in squares (+2 = +10ft, +1 = +5ft, etc.)
        custom["Natural"] = max(0, int(custom.get("Natural", 0)) + int(value) * 5)
        custom["Enabled"] = True
    elif mode == "-incrext":
        custom["Extended"] = max(0, int(custom.get("Extended", 0)) + int(value) * 5)
        custom["Enabled"] = True
    elif mode == "-reset":
        custom["Enabled"] = False

    if int(custom.get("Natural", 0)) > int(custom.get("Extended", 0)):
        custom["Extended"] = int(custom["Natural"])

    mob_data["CustomReach"] = custom
    return {"CustomReach": custom}


def apply_size_change(mob_data: dict[str, Any], size_code: str) -> dict[str, Any]:
    """Change displayed size (`DispSize`) of `mob_data` matching `ChangeDispSize`."""
    changes: dict[str, Any] = {"DispSize": size_code}
    mob_data["DispSize"] = size_code
    if len(size_code) > 1 and isinstance(mob_data.get("CustomReach"), dict):
        custom = dict(mob_data["CustomReach"])
        custom["Enabled"] = False
        mob_data["CustomReach"] = custom
        changes["CustomReach"] = custom
    return changes


def allowed_to_polymorph(mob_data: dict[str, Any], is_gm: bool = True) -> bool:
    """Return True if `mob_data` has multiple skins and the user is permitted to polymorph it."""
    if mob_data.get("PolyGM") and not is_gm:
        return False
    skin_sizes = mob_data.get("SkinSize") or []
    return isinstance(skin_sizes, list) and len(skin_sizes) > 1


def apply_polymorph(mob_data: dict[str, Any], skin_idx: int) -> dict[str, Any]:
    """Switch `mob_data` to `skin_idx`, updating `Skin`, `Size`, and `DispSize`."""
    skin_sizes = list(mob_data.get("SkinSize") or [])
    mob_data["Skin"] = int(skin_idx)
    if 0 <= skin_idx < len(skin_sizes):
        new_size = str(skin_sizes[skin_idx])
        mob_data["Size"] = new_size
        mob_data["DispSize"] = new_size
    return {
        "Skin": mob_data["Skin"],
        "Size": mob_data.get("Size", "M"),
        "DispSize": mob_data.get("DispSize", mob_data.get("Size", "M")),
    }


def build_spawned_creatures(
    base_gx: float,
    base_gy: float,
    name_spec: str,
    sizes_str: str = "M",
    color: str = "red",
    creature_type: str = "monster",
    reach: int = 1,
    known_pc_ids: dict[str, str] | None = None,
) -> list[dict[str, Any]]:
    """Build one or more `PS` creature dictionaries from `name_spec` (supporting `Goblin #1-4` batch syntax).

    Matches `AddMobFromMenu` in `bin/mapper_legacy.tcl`.
    """
    sizes = [s for s in sizes_str.split() if s] or ["M"]
    for s in sizes:
        if creature_size_params(s) is None:
            raise ValueError(
                f"Size value '{s}' is not valid. Specify number of squares or size code (F, D, T, S, M, L, H, G, C)."
            )
    first_size = sizes[0]
    ctype_enum = to_enum("CreatureType", creature_type)
    results: list[dict[str, Any]] = []

    m = re.match(r"^(.+)#(\d+)-(\d+)$", name_spec.strip())
    if m:
        basename = m.group(1)
        start_num = int(m.group(2))
        end_num = int(m.group(3))
        xx = 0
        cur_y = float(base_gy)
        for i in range(start_num, end_num + 1):
            if xx > 8:
                xx = 0
                cur_y += 1.0
            d = new_dict(
                "PS",
                ID=new_id(),
                Name=f"{basename}#{i}",
                Gx=float(base_gx) + xx,
                Gy=cur_y,
                Color=color,
                Size=first_size,
                DispSize=first_size,
                SkinSize=sizes,
                Skin=0,
                PolyGM=False,
                CreatureType=ctype_enum,
                Reach=int(reach),
            )
            results.append(d)
            xx += 1
    else:
        clean_name = name_spec.strip()
        mob_id = (known_pc_ids or {}).get(clean_name) or new_id()
        d = new_dict(
            "PS",
            ID=mob_id,
            Name=clean_name,
            Gx=float(base_gx),
            Gy=float(base_gy),
            Color=color,
            Size=first_size,
            DispSize=first_size,
            SkinSize=sizes,
            Skin=0,
            PolyGM=False,
            CreatureType=ctype_enum,
            Reach=int(reach),
        )
        results.append(d)
    return results


def build_token_tooltip(mob_data: dict[str, Any]) -> str:
    """Build a detailed hover tooltip for a creature token matching `bin/mapper_legacy.tcl`."""
    name = str(mob_data.get("Name", "Unknown"))
    disp_size = creature_displayed_size(mob_data)
    lines = [f"{name} (Size: {disp_size})"]
    if mob_data.get("Killed"):
        lines.append("Status: KILLED / Dead")
    statuses = list(mob_data.get("StatusList") or [])
    if statuses:
        lines.append(f"Conditions: {', '.join(statuses)}")
    elev = int(mob_data.get("Elev", 0) or 0)
    if elev != 0:
        lines.append(f"Elevation: {elev:+d} ft")
    mmode = from_enum("MoveMode", int(mob_data.get("MoveMode", 0) or 0))
    if mmode:
        lines.append(f"Movement: {mmode.capitalize()}")
    note = str(mob_data.get("Note", "") or "")
    if note:
        lines.append(f"Tag: {note}")
    health = mob_data.get("Health") or {}
    if isinstance(health, dict) and int(health.get("MaxHP", 0) or 0) > 0:
        max_hp = int(health.get("MaxHP", 0))
        lethal = int(health.get("LethalDamage", 0) or 0)
        nl = int(health.get("NonLethalDamage", 0) or 0)
        tmp = int(health.get("TmpHP", 0) or 0)
        cur = max_hp - lethal
        hp_line = f"HP: {cur}/{max_hp}"
        if tmp > 0:
            hp_line += f" (+{tmp} tmp)"
        if nl > 0:
            hp_line += f" [{nl} NL]"
        lines.append(hp_line)
    targets = list(mob_data.get("Targets") or [])
    if targets:
        lines.append(f"Currently targeting: {', '.join(str(t) for t in targets)}")
    return "\n".join(lines)


try:
    from PySide6.QtGui import QAction
    from PySide6.QtWidgets import (
        QCheckBox,
        QComboBox,
        QDialog,
        QDialogButtonBox,
        QFormLayout,
        QInputDialog,
        QLabel,
        QLineEdit,
        QMenu,
        QMessageBox,
        QSpinBox,
        QWidget,
    )

    class AddCreatureDialog(QDialog):
        """Dialog for 'Add Player...' / 'Add Monster...' (`AddPlayerMenu` in `bin/mapper_legacy.tcl`)."""

        def __init__(
            self,
            creature_type: str = "monster",
            parent: QWidget | None = None,
        ) -> None:
            super().__init__(parent)
            self.creature_type = creature_type
            self.setWindowTitle(
                "Add Player" if creature_type == "player" else "Add Monster"
            )
            form = QFormLayout(self)

            self.name_edit = QLineEdit(self)
            self.name_edit.setPlaceholderText("e.g. Goblin #1-4 or Valeros")
            form.addRow("Name:", self.name_edit)

            self.size_edit = QLineEdit("M", self)
            self.size_edit.setToolTip(
                "<category>[<natural>][-><extended>][=<space>] (e.g. M, L, H, l)"
            )
            form.addRow("Size Categories:", self.size_edit)

            default_col = "green" if creature_type == "player" else "red"
            self.color_edit = QLineEdit(default_col, self)
            form.addRow("Threat Zone Color:", self.color_edit)

            self.reach_check = QCheckBox("Extended Reach Active", self)
            self.reach_check.setChecked(True)
            form.addRow("", self.reach_check)

            buttons = QDialogButtonBox(
                QDialogButtonBox.StandardButton.Ok
                | QDialogButtonBox.StandardButton.Cancel,
                self,
            )
            buttons.accepted.connect(self.accept)
            buttons.rejected.connect(self.reject)
            form.addRow(buttons)

    class QuickHPDialog(QDialog):
        """Quick dialog for adjusting HP, Lethal/Nonlethal Damage, and Temp HP on a creature token."""

        def __init__(
            self,
            mob_name: str,
            health: dict[str, Any],
            parent: QWidget | None = None,
        ) -> None:
            super().__init__(parent)
            self.setWindowTitle(f"Hit Points — {mob_name}")
            form = QFormLayout(self)

            max_hp = int(health.get("MaxHP", 0) or 0)
            lethal = int(health.get("LethalDamage", 0) or 0)
            nl = int(health.get("NonLethalDamage", 0) or 0)
            tmp = int(health.get("TmpHP", 0) or 0)

            self.max_spin = QSpinBox(self)
            self.max_spin.setRange(0, 99999)
            self.max_spin.setValue(max_hp)
            form.addRow("Max HP:", self.max_spin)

            self.lethal_spin = QSpinBox(self)
            self.lethal_spin.setRange(0, 99999)
            self.lethal_spin.setValue(lethal)
            form.addRow("Lethal Damage:", self.lethal_spin)

            self.nl_spin = QSpinBox(self)
            self.nl_spin.setRange(0, 99999)
            self.nl_spin.setValue(nl)
            form.addRow("Nonlethal Damage:", self.nl_spin)

            self.tmp_spin = QSpinBox(self)
            self.tmp_spin.setRange(0, 99999)
            self.tmp_spin.setValue(tmp)
            form.addRow("Temporary HP:", self.tmp_spin)

            self.delta_spin = QSpinBox(self)
            self.delta_spin.setRange(-9999, 9999)
            self.delta_spin.setValue(0)
            form.addRow("Apply Damage (+) / Heal (-):", self.delta_spin)

            buttons = QDialogButtonBox(
                QDialogButtonBox.StandardButton.Ok
                | QDialogButtonBox.StandardButton.Cancel,
                self,
            )
            buttons.accepted.connect(self.accept)
            buttons.rejected.connect(self.reject)
            form.addRow(buttons)

        def resulting_health(self, orig_health: dict[str, Any]) -> dict[str, Any]:
            h = dict(orig_health or {})
            delta = self.delta_spin.value()
            lethal = max(0, self.lethal_spin.value() + delta)
            h["MaxHP"] = self.max_spin.value()
            h["LethalDamage"] = lethal
            h["NonLethalDamage"] = self.nl_spin.value()
            h["TmpHP"] = self.tmp_spin.value()
            h["IsFlatFooted"] = bool(h.get("IsFlatFooted", False))
            h["IsStaggered"] = (h["MaxHP"] - lethal) == 0
            return h

    def _populate_condition_submenu(
        cond_menu: QMenu,
        mob_ids: list[str],
        scene: Any,
        on_mutate_mob: Callable[[str, dict[str, Any]], None],
    ) -> None:
        first_tok = scene.creatures.get(mob_ids[0]) if mob_ids else None
        first_data = first_tok.data if first_tok else {}
        cur_statuses = set(first_data.get("StatusList") or [])
        is_hidden = bool(first_data.get("Hidden", False))

        act_clear = cond_menu.addAction("(clear all)")
        act_clear.triggered.connect(
            lambda _c=False, ids=list(mob_ids): [
                on_mutate_mob(mid, toggle_status_condition(scene.creatures[mid].data, "__clear__"))
                for mid in ids
                if mid in scene.creatures
            ]
        )

        act_hide = cond_menu.addAction(f"{'* ' if is_hidden else '  '}(hidden)")
        act_hide.triggered.connect(
            lambda _c=False, ids=list(mob_ids): [
                on_mutate_mob(mid, toggle_status_condition(scene.creatures[mid].data, "__hide__"))
                for mid in ids
                if mid in scene.creatures
            ]
        )
        cond_menu.addSeparator()

        all_conditions = sorted(MARKER_COLOR.keys(), key=lambda s: s.lower())
        if len(all_conditions) > 10:
            groups: list[tuple[str, str, list[str]]] = [
                ("A - D", "abcd", []),
                ("E - H", "efgh", []),
                ("I - P", "ijklmnop", []),
                ("Q - Z", "qrstuvwxyz", []),
            ]
            for cond in all_conditions:
                first_ch = cond[0].lower() if cond else "a"
                for _label, chars, bucket in groups:
                    if first_ch in chars:
                        bucket.append(cond)
                        break
            for label, _chars, bucket in groups:
                if not bucket:
                    continue
                sub = cond_menu.addMenu(label)
                for cond in bucket:
                    prefix = "* " if cond in cur_statuses else "  "
                    act = sub.addAction(f"{prefix}{cond}")
                    desc = MARKER_DESCRIPTION.get(cond, "")
                    if desc:
                        act.setToolTip(desc)
                        act.setStatusTip(desc)
                    act.triggered.connect(
                        lambda _c=False, ids=list(mob_ids), cname=cond: [
                            on_mutate_mob(mid, toggle_status_condition(scene.creatures[mid].data, cname))
                            for mid in ids
                            if mid in scene.creatures
                        ]
                    )
        else:
            for cond in all_conditions:
                prefix = "* " if cond in cur_statuses else "  "
                act = cond_menu.addAction(f"{prefix}{cond}")
                act.triggered.connect(
                    lambda _c=False, ids=list(mob_ids), cname=cond: [
                        on_mutate_mob(mid, toggle_status_condition(scene.creatures[mid].data, cname))
                        for mid in ids
                        if mid in scene.creatures
                    ]
                )

    def _populate_elevation_submenu(
        elev_menu: QMenu,
        mob_ids: list[str],
        scene: Any,
        parent_widget: QWidget | None,
        on_mutate_mob: Callable[[str, dict[str, Any]], None],
    ) -> None:
        for spec, label in ELEVATION_MENU_CHOICES:
            act = elev_menu.addAction(label)
            act.triggered.connect(
                lambda _c=False, ids=list(mob_ids), sp=spec: [
                    on_mutate_mob(
                        mid,
                        {
                            "Elev": compute_elevation_change(
                                int(scene.creatures[mid].data.get("Elev", 0) or 0), sp
                            )
                        },
                    )
                    for mid in ids
                    if mid in scene.creatures
                ]
            )
        elev_menu.addSeparator()

        def _prompt_custom_elev() -> None:
            first_tok = scene.creatures.get(mob_ids[0]) if mob_ids else None
            cur_val = int(first_tok.data.get("Elev", 0) or 0) if first_tok else 0
            val, ok = QInputDialog.getInt(
                parent_widget,
                "Set Elevation",
                "Enter new elevation (ft):",
                cur_val,
                -1000,
                1000,
                5,
            )
            if ok:
                for mid in mob_ids:
                    if mid in scene.creatures:
                        on_mutate_mob(mid, {"Elev": val})

        act_set = elev_menu.addAction("(Set...)")
        act_set.triggered.connect(_prompt_custom_elev)

    def _populate_size_submenu(
        size_menu: QMenu,
        mob_ids: list[str],
        scene: Any,
        on_mutate_mob: Callable[[str, dict[str, Any]], None],
    ) -> None:
        first_tok = scene.creatures.get(mob_ids[0]) if mob_ids else None
        first_data = first_tok.data if first_tok else {}
        disp_size = skin_size_only(creature_displayed_size(first_data)) if first_data else "M"
        real_size = skin_size_only(str(first_data.get("Size", "M"))) if first_data else "M"

        for codes, desc in SIZE_MENU_CHOICES:
            primary = codes[0]
            if disp_size in codes:
                flag = "* "
            elif real_size in codes:
                flag = "= "
            else:
                flag = "  "
            act = size_menu.addAction(f"{flag}{desc}")
            act.triggered.connect(
                lambda _c=False, ids=list(mob_ids), sc=primary: [
                    on_mutate_mob(mid, apply_size_change(scene.creatures[mid].data, sc))
                    for mid in ids
                    if mid in scene.creatures
                ]
            )

    def _populate_reach_submenu(
        reach_menu: QMenu,
        mob_ids: list[str],
        scene: Any,
        on_mutate_mob: Callable[[str, dict[str, Any]], None],
    ) -> None:
        first_tok = scene.creatures.get(mob_ids[0]) if mob_ids else None
        first_data = first_tok.data if first_tok else {}
        reach_val = int(first_data.get("Reach", 0) or 0)
        custom = first_data.get("CustomReach") or {}
        if not isinstance(custom, dict) or "Natural" not in custom:
            custom = default_custom_reach(creature_displayed_size(first_data) if first_data else "M")
        cust_enabled = bool(custom.get("Enabled", False))
        cur_nat = int(custom.get("Natural", 0) or 0)
        cur_ext = int(custom.get("Extended", 0) or 0)

        act_ext_toggle = reach_menu.addAction(
            f"{'* ' if reach_val > 0 else '  '}Extended Reach"
        )
        new_reach_toggle = 0 if reach_val > 0 else 1
        act_ext_toggle.triggered.connect(
            lambda _c=False, ids=list(mob_ids), rv=new_reach_toggle: [
                on_mutate_mob(mid, apply_custom_reach_change(scene.creatures[mid].data, "-setreach", rv))
                for mid in ids
                if mid in scene.creatures
            ]
        )

        act_inc_toggle = reach_menu.addAction(
            f"{'* ' if reach_val > 1 else '  '}Include Natural Distance"
        )
        new_inc_toggle = 1 if reach_val > 1 else 2
        act_inc_toggle.triggered.connect(
            lambda _c=False, ids=list(mob_ids), rv=new_inc_toggle: [
                on_mutate_mob(mid, apply_custom_reach_change(scene.creatures[mid].data, "-setreach", rv))
                for mid in ids
                if mid in scene.creatures
            ]
        )

        nat_menu = reach_menu.addMenu("Natural Reach Distance")
        for ft, _sq in REACH_FEET_CHOICES:
            flag = "* " if (cust_enabled and cur_nat == ft) else "  "
            act = nat_menu.addAction(f"{flag}{ft} ft")
            act.triggered.connect(
                lambda _c=False, ids=list(mob_ids), f=ft: [
                    on_mutate_mob(mid, apply_custom_reach_change(scene.creatures[mid].data, "-setnat", f))
                    for mid in ids
                    if mid in scene.creatures
                ]
            )
        nat_menu.addSeparator()
        for label, delta_sq in [("+10 ft", 2), ("+5 ft", 1), ("-5 ft", -1), ("-10 ft", -2)]:
            act = nat_menu.addAction(f"  {label}")
            act.triggered.connect(
                lambda _c=False, ids=list(mob_ids), d=delta_sq: [
                    on_mutate_mob(mid, apply_custom_reach_change(scene.creatures[mid].data, "-incrnat", d))
                    for mid in ids
                    if mid in scene.creatures
                ]
            )

        ext_menu = reach_menu.addMenu("Extended Reach Distance")
        for ft, _sq in REACH_FEET_CHOICES:
            flag = "* " if (cust_enabled and cur_ext == ft) else "  "
            act = ext_menu.addAction(f"{flag}{ft} ft")
            act.triggered.connect(
                lambda _c=False, ids=list(mob_ids), f=ft: [
                    on_mutate_mob(mid, apply_custom_reach_change(scene.creatures[mid].data, "-setext", f))
                    for mid in ids
                    if mid in scene.creatures
                ]
            )
        ext_menu.addSeparator()
        for label, delta_sq in [("+10 ft", 2), ("+5 ft", 1), ("-5 ft", -1), ("-10 ft", -2)]:
            act = ext_menu.addAction(f"  {label}")
            act.triggered.connect(
                lambda _c=False, ids=list(mob_ids), d=delta_sq: [
                    on_mutate_mob(mid, apply_custom_reach_change(scene.creatures[mid].data, "-incrext", d))
                    for mid in ids
                    if mid in scene.creatures
                ]
            )

        if cust_enabled:
            act_reset = reach_menu.addAction("Reset Custom Reach")
            act_reset.triggered.connect(
                lambda _c=False, ids=list(mob_ids): [
                    on_mutate_mob(mid, apply_custom_reach_change(scene.creatures[mid].data, "-reset", 0))
                    for mid in ids
                    if mid in scene.creatures
                ]
            )

    def _populate_polymorph_submenu(
        poly_menu: QMenu,
        mob_id: str,
        scene: Any,
        on_mutate_mob: Callable[[str, dict[str, Any]], None],
    ) -> None:
        tok = scene.creatures.get(mob_id)
        if not tok:
            return
        skin_sizes = list(tok.data.get("SkinSize") or [])
        cur_skin = int(tok.data.get("Skin", 0) or 0)
        for idx, sz_spec in enumerate(skin_sizes):
            flag = "* " if idx == cur_skin else "  "
            comment = skin_comment(str(sz_spec))
            pure_sz = skin_size_only(str(sz_spec))
            desc = comment if comment else f"Skin #{idx} ({pure_sz})"
            if skin_is_default(str(sz_spec)):
                desc += " [default]"
            act = poly_menu.addAction(f"{flag}{desc}")
            act.triggered.connect(
                lambda _c=False, mid=mob_id, sidx=idx: (
                    on_mutate_mob(mid, apply_polymorph(scene.creatures[mid].data, sidx))
                    if mid in scene.creatures
                    else None
                )
            )

    def _populate_movement_mode_submenu(
        move_menu: QMenu,
        mob_ids: list[str],
        scene: Any,
        on_mutate_mob: Callable[[str, dict[str, Any]], None],
    ) -> None:
        first_tok = scene.creatures.get(mob_ids[0]) if mob_ids else None
        cur_mode = (
            from_enum("MoveMode", int(first_tok.data.get("MoveMode", 0) or 0))
            if first_tok
            else ""
        )
        for mode_code, label in MOVEMENT_MODE_CHOICES:
            flag = "* " if mode_code == cur_mode else "  "
            enum_val = to_enum("MoveMode", mode_code)
            act = move_menu.addAction(f"{flag}{label}")
            act.triggered.connect(
                lambda _c=False, ids=list(mob_ids), ev=enum_val: [
                    on_mutate_mob(mid, {"MoveMode": ev})
                    for mid in ids
                    if mid in scene.creatures
                ]
            )

    def _populate_tag_submenu(
        tag_menu: QMenu,
        mob_ids: list[str],
        scene: Any,
        parent_widget: QWidget | None,
        on_mutate_mob: Callable[[str, dict[str, Any]], None],
    ) -> None:
        first_tok = scene.creatures.get(mob_ids[0]) if mob_ids else None
        cur_note = str(first_tok.data.get("Note", "") or "") if first_tok else ""
        tag_history: list[str] = getattr(scene, "tag_history", [])

        act_clear = tag_menu.addAction(f"{'* ' if not cur_note else '  '}(Clear)")
        act_clear.triggered.connect(
            lambda _c=False, ids=list(mob_ids): [
                on_mutate_mob(mid, {"Note": ""})
                for mid in ids
                if mid in scene.creatures
            ]
        )

        def _prompt_new_tag() -> None:
            text, ok = QInputDialog.getText(
                parent_widget, "Tag Creature", "Enter tag / note text:", text=cur_note
            )
            if ok:
                clean = text.strip()
                if clean and hasattr(scene, "tag_history") and clean not in scene.tag_history:
                    scene.tag_history.append(clean)
                for mid in mob_ids:
                    if mid in scene.creatures:
                        on_mutate_mob(mid, {"Note": clean})

        act_new = tag_menu.addAction("  (New...)")
        act_new.triggered.connect(_prompt_new_tag)

        if tag_history:
            tag_menu.addSeparator()
            for tag in tag_history:
                flag = "* " if tag == cur_note else "  "
                act = tag_menu.addAction(f"{flag}{tag}")
                act.triggered.connect(
                    lambda _c=False, ids=list(mob_ids), t=tag: [
                        on_mutate_mob(mid, {"Note": t})
                        for mid in ids
                        if mid in scene.creatures
                    ]
                )

    def _populate_creature_actions(
        menu: QMenu,
        mob_ids: list[str],
        display_name: str,
        scene: Any,
        parent_widget: QWidget | None,
        on_mutate_mob: Callable[[str, dict[str, Any]], None],
        on_remove_mob: Callable[[str], None],
        on_hp_request: Callable[[dict[str, Any]], None] | None = None,
    ) -> None:
        first_tok = scene.creatures.get(mob_ids[0]) if mob_ids else None
        first_data = first_tok.data if first_tok else {}
        is_single = len(mob_ids) == 1

        # 1. Targeting actions
        source_id = getattr(scene, "active_target_source", "") or getattr(
            scene, "active_actor_id", ""
        )
        source_tok = scene.creatures.get(source_id) if source_id else None
        if source_tok is None and scene.creatures:
            # Check if any active turn creature exists
            for cid, tok in scene.creatures.items():
                if getattr(tok, "is_active_turn", False):
                    source_id = cid
                    source_tok = tok
                    break

        if is_single:
            act_set_src = menu.addAction(f"Set {display_name} as Target Source")
            act_set_src.triggered.connect(
                lambda _c=False, mid=mob_ids[0]: setattr(scene, "active_target_source", mid)
            )

        if source_tok is not None:
            cur_targets = list(source_tok.data.get("Targets") or [])
            target_names = [
                str(scene.creatures[mid].data.get("Name", mid))
                for mid in mob_ids
                if mid in scene.creatures
            ]
            all_targeted = bool(target_names) and all(tn in cur_targets for tn in target_names)
            act_target = menu.addAction(
                f"{'Untarget' if all_targeted else 'Target'} {display_name}"
            )

            def _toggle_targets(
                _c: bool = False,
                sid: str = source_id,
                tnames: list[str] = target_names,
                untarget: bool = all_targeted,
            ) -> None:
                stok = scene.creatures.get(sid)
                if not stok:
                    return
                tlist = list(stok.data.get("Targets") or [])
                if untarget:
                    tlist = [t for t in tlist if t not in tnames]
                else:
                    for tn in tnames:
                        if tn not in tlist:
                            tlist.append(tn)
                on_mutate_mob(sid, {"Targets": tlist})

            act_target.triggered.connect(_toggle_targets)

        if len(mob_ids) > 1 and source_tok is not None:
            act_rand = menu.addAction(f"Randomly Target One of {display_name}")

            def _random_target(_c: bool = False, sid: str = source_id, ids: list[str] = list(mob_ids)) -> None:
                chosen_id = random.choice(ids)
                chosen_tok = scene.creatures.get(chosen_id)
                if chosen_tok:
                    cname = str(chosen_tok.data.get("Name", chosen_id))
                    on_mutate_mob(sid, {"Targets": [cname]})

            act_rand.triggered.connect(_random_target)

        if is_single and (first_data.get("Targets") or []):
            act_clr_t = menu.addAction(f"Clear Targets of {display_name}")
            act_clr_t.triggered.connect(
                lambda _c=False, mid=mob_ids[0]: on_mutate_mob(mid, {"Targets": []})
            )

        menu.addSeparator()

        # 2. HP / Damage dialog (single or batch)
        def _open_hp_dialog(_c: bool = False, ids: list[str] = list(mob_ids)) -> None:
            tok0 = scene.creatures.get(ids[0]) if ids else None
            if not tok0:
                return
            orig_h = dict(tok0.data.get("Health") or {})
            dlg = QuickHPDialog(display_name, orig_h, parent_widget)
            if dlg.exec():
                for mid in ids:
                    if mid in scene.creatures:
                        mh = dlg.resulting_health(scene.creatures[mid].data.get("Health") or {})
                        on_mutate_mob(mid, {"Health": mh})
                        if on_hp_request:
                            req = dict(mh)
                            req["ID"] = mid
                            req["Target"] = mid
                            on_hp_request(req)

        act_hp = menu.addAction(f"Adjust HP / Damage for {display_name}...")
        act_hp.triggered.connect(_open_hp_dialog)

        # 3. Toggle Death (Killed)
        is_killed = bool(first_data.get("Killed", False))
        act_kill = menu.addAction(
            f"{'* ' if is_killed else '  '}Toggle Death for {display_name}"
        )
        act_kill.triggered.connect(
            lambda _c=False, ids=list(mob_ids), nk=(not is_killed): [
                on_mutate_mob(mid, {"Killed": nk})
                for mid in ids
                if mid in scene.creatures
            ]
        )

        # 4. Set Reach submenu
        reach_sub = menu.addMenu(f"Set Reach for {display_name}")
        _populate_reach_submenu(reach_sub, mob_ids, scene, on_mutate_mob)

        # 5. Toggle Spell Area (AoE) and Local Aura (_AoE)
        cur_aoe = first_data.get("AoE") or {}
        has_aoe = isinstance(cur_aoe, dict) and float(cur_aoe.get("Radius", 0.0) or 0.0) > 0

        def _toggle_aoe(attr_key: str, has_cur: bool) -> None:
            if is_single and hasattr(parent_widget, "start_mob_aoe_drag"):
                parent_widget.start_mob_aoe_drag(mob_ids[0], attr_key == "_AoE")  # type: ignore[union-attr]
                return
            if has_cur:
                for mid in mob_ids:
                    if mid in scene.creatures:
                        on_mutate_mob(mid, {attr_key: {"Radius": 0.0, "Color": ""}})
                return
            rad_ft, ok = QInputDialog.getDouble(
                parent_widget,
                f"Set {attr_key} Aura Radius",
                "Radius in feet:",
                10.0,
                0.0,
                500.0,
                5.0,
            )
            if not ok or rad_ft <= 0:
                return
            col, ok2 = QInputDialog.getText(
                parent_widget,
                f"Set {attr_key} Aura Color",
                "Color name or #RRGGBB:",
                text=str(first_data.get("Color") or "cyan"),
            )
            if not ok2:
                return
            aoe_dict = {"Radius": rad_ft / 5.0, "Color": col.strip() or "cyan"}
            for mid in mob_ids:
                if mid in scene.creatures:
                    on_mutate_mob(mid, {attr_key: aoe_dict})

        act_aoe = menu.addAction(
            f"{'* ' if has_aoe else '  '}Toggle Spell Area for {display_name}"
        )
        act_aoe.triggered.connect(lambda _c=False, hc=has_aoe: _toggle_aoe("AoE", hc))

        cur_local_aoe = first_data.get("_AoE") or {}
        has_local_aoe = (
            isinstance(cur_local_aoe, dict)
            and float(cur_local_aoe.get("Radius", 0.0) or 0.0) > 0
        )
        act_local_aoe = menu.addAction(
            f"{'* ' if has_local_aoe else '  '}Toggle Local Aura for {display_name}"
        )
        act_local_aoe.triggered.connect(
            lambda _c=False, hc=has_local_aoe: _toggle_aoe("_AoE", hc)
        )

        # 6. Polymorph submenu (single creature with multiple skins)
        if is_single and allowed_to_polymorph(first_data):
            poly_sub = menu.addMenu(f"Polymorph {display_name}")
            _populate_polymorph_submenu(poly_sub, mob_ids[0], scene, on_mutate_mob)

        # 7. Change Size submenu
        size_sub = menu.addMenu(f"Change Size of {display_name}")
        _populate_size_submenu(size_sub, mob_ids, scene, on_mutate_mob)

        # 8. Toggle Condition submenu
        cond_sub = menu.addMenu(f"Toggle Condition for {display_name}")
        _populate_condition_submenu(cond_sub, mob_ids, scene, on_mutate_mob)

        # 9. Tag submenu
        tag_sub = menu.addMenu(f"Tag {display_name}")
        _populate_tag_submenu(tag_sub, mob_ids, scene, parent_widget, on_mutate_mob)

        # 10. Set Elevation submenu
        elev_val = int(first_data.get("Elev", 0) or 0)
        elev_sub = menu.addMenu(f"Set Elevation for {display_name} [{elev_val} ft]")
        _populate_elevation_submenu(
            elev_sub, mob_ids, scene, parent_widget, on_mutate_mob
        )

        # 11. Set Movement Mode submenu
        move_sub = menu.addMenu(f"Set Movement Mode for {display_name}")
        _populate_movement_mode_submenu(move_sub, mob_ids, scene, on_mutate_mob)

        # 12. Remove creature
        act_rm = menu.addAction(f"Remove {display_name}")
        act_rm.triggered.connect(
            lambda _c=False, ids=list(mob_ids): [on_remove_mob(mid) for mid in ids]
        )

    def populate_canvas_context_menu(
        menu: QMenu,
        scene: Any,
        view: Any,
        scene_pt: Any,
        on_mutate_mob: Callable[[str, dict[str, Any]], None],
        on_remove_mob: Callable[[str], None],
        on_spawn_mob: Callable[[dict[str, Any]], None],
        on_hp_request: Callable[[dict[str, Any]], None] | None = None,
        pc_templates: dict[str, dict[str, Any]] | None = None,
    ) -> None:
        """Populate `menu` with the full token & battle-map right-click context menu (`DoContext`)."""
        from gma_mapper.ui.canvas.items import BASE_GRID_SCALE
        from gma_mapper.ui.canvas.scene import grid_coord_label, scene_to_grid_xy

        gx, gy = scene_to_grid_xy(scene_pt.x(), scene_pt.y())
        snap_gx = float(int(gx)) if gx >= 0 else float(int(gx) - 1)
        snap_gy = float(int(gy)) if gy >= 0 else float(int(gy) - 1)
        grid_lbl = grid_coord_label(gx, gy)

        mobs = (
            scene.mobs_at_scene_pos(scene_pt, include_selected=True)
            if hasattr(scene, "mobs_at_scene_pos")
            else []
        )

        if len(mobs) == 1:
            mid = mobs[0]
            tok = scene.creatures[mid]
            mname = str(tok.data.get("Name", mid))
            _populate_creature_actions(
                menu,
                [mid],
                mname,
                scene,
                view,
                on_mutate_mob,
                on_remove_mob,
                on_hp_request,
            )
            menu.addSeparator()
        elif len(mobs) > 1:
            for mid in mobs:
                tok = scene.creatures[mid]
                mname = str(tok.data.get("Name", mid))
                sub = menu.addMenu(f"Creature {mname}")
                _populate_creature_actions(
                    sub,
                    [mid],
                    mname,
                    scene,
                    view,
                    on_mutate_mob,
                    on_remove_mob,
                    on_hp_request,
                )
            all_sub = menu.addMenu("(all of the above)")
            _populate_creature_actions(
                all_sub,
                mobs,
                "(all of the above)",
                scene,
                view,
                on_mutate_mob,
                on_remove_mob,
                on_hp_request,
            )
            menu.addSeparator()

        # Add Player... / Add Monster...
        def _prompt_add_creature(ctype: str) -> None:
            dlg = AddCreatureDialog(creature_type=ctype, parent=view)
            if dlg.exec():
                name_spec = dlg.name_edit.text().strip()
                if not name_spec:
                    return
                sizes_str = dlg.size_edit.text().strip() or "M"
                color = dlg.color_edit.text().strip() or (
                    "green" if ctype == "player" else "red"
                )
                reach = 1 if dlg.reach_check.isChecked() else 0
                known_ids = {
                    str(v.get("Name", k)): k for k, v in (pc_templates or {}).items()
                }
                try:
                    spawned = build_spawned_creatures(
                        snap_gx,
                        snap_gy,
                        name_spec,
                        sizes_str=sizes_str,
                        color=color,
                        creature_type=ctype,
                        reach=reach,
                        known_pc_ids=known_ids,
                    )
                except ValueError as exc:
                    QMessageBox.warning(view, "Invalid Creature Size", str(exc))
                    return
                for cr_dict in spawned:
                    on_spawn_mob(cr_dict)

        act_add_player = menu.addAction("Add Player...")
        act_add_player.triggered.connect(lambda _c=False: _prompt_add_creature("player"))

        if pc_templates:
            pc_sub = menu.addMenu("Quick-Add Known Player")
            for pid, pdata in sorted(
                pc_templates.items(), key=lambda kv: str(kv[1].get("Name", kv[0]))
            ):
                pname = str(pdata.get("Name", pid))
                act_pc = pc_sub.addAction(pname)

                def _spawn_known_pc(
                    _c: bool = False,
                    tpl_id: str = pid,
                    tpl_data: dict[str, Any] = pdata,
                ) -> None:
                    d = dict(tpl_data)
                    d["ID"] = tpl_id
                    d["Gx"] = snap_gx
                    d["Gy"] = snap_gy
                    d.setdefault("Color", "green")
                    d.setdefault("Size", "M")
                    d.setdefault("DispSize", d["Size"])
                    d.setdefault("CreatureType", to_enum("CreatureType", "player"))
                    on_spawn_mob(d)

                act_pc.triggered.connect(_spawn_known_pc)

        act_add_monster = menu.addAction("Add Monster...")
        act_add_monster.triggered.connect(lambda _c=False: _prompt_add_creature("monster"))

        # Distance from <GridLabel> / <Name>
        grid_center = type(scene_pt)(
            (snap_gx + 0.5) * BASE_GRID_SCALE, (snap_gy + 0.5) * BASE_GRID_SCALE
        )
        act_dist_grid = menu.addAction(f"Distance from {grid_lbl}")
        act_dist_grid.triggered.connect(
            lambda _c=False, pt=grid_center: (
                view.start_ruler_from(pt) if hasattr(view, "start_ruler_from") else None
            )
        )

        for mid in mobs:
            tok = scene.creatures.get(mid)
            if not tok:
                continue
            mname = str(tok.data.get("Name", mid))
            msize, _, _, _, _ = tok._area_info()
            mcenter = type(scene_pt)(
                (tok.gx + msize * 0.5) * BASE_GRID_SCALE,
                (tok.gy + msize * 0.5) * BASE_GRID_SCALE,
            )
            act_dist_mob = menu.addAction(f"Distance from {mname}...")
            act_dist_mob.triggered.connect(
                lambda _c=False, pt=mcenter: (
                    view.start_ruler_from(pt) if hasattr(view, "start_ruler_from") else None
                )
            )

        # Selection actions
        selected_set: set[str] = getattr(scene, "selected_mobs", set())
        direct_mobs = (
            scene.mobs_at_scene_pos(scene_pt, include_selected=False)
            if hasattr(scene, "mobs_at_scene_pos")
            else []
        )
        if direct_mobs or selected_set:
            menu.addSeparator()
            for mid in direct_mobs:
                tok = scene.creatures.get(mid)
                if not tok:
                    continue
                mname = str(tok.data.get("Name", mid))
                is_sel = mid in selected_set
                act_sel = menu.addAction(
                    f"{'Deselect' if is_sel else 'Select'} {mname}"
                )
                act_sel.triggered.connect(
                    lambda _c=False, m=mid: (
                        scene.toggle_mob_selection(m)
                        if hasattr(scene, "toggle_mob_selection")
                        else None
                    )
                )
            if selected_set:
                act_desel = menu.addAction("Deselect All")
                act_desel.triggered.connect(
                    lambda _c=False: (
                        scene.clear_mob_selection()
                        if hasattr(scene, "clear_mob_selection")
                        else None
                    )
                )

except ImportError:
    AddCreatureDialog = None  # type: ignore[assignment,misc]
    QuickHPDialog = None  # type: ignore[assignment,misc]
    populate_canvas_context_menu = None  # type: ignore[assignment]
