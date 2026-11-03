"""Combat, Hit Point Management, Condition Toggle, and Timer Progress Panel.

Ported from ``bin/mapper_legacy.tcl``.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from gma_mapper.net.protocol import new_id
from gma_mapper.ui.canvas.items import MARKER_DESCRIPTION
from gma_mapper.ui.panels.clock import strip_nameplate_prefix

try:
    from PySide6.QtCore import Qt, Signal
    from PySide6.QtWidgets import (
        QCheckBox,
        QComboBox,
        QDialog,
        QDialogButtonBox,
        QFormLayout,
        QGroupBox,
        QHBoxLayout,
        QLabel,
        QLineEdit,
        QListWidget,
        QListWidgetItem,
        QProgressBar,
        QPushButton,
        QSpinBox,
        QVBoxLayout,
        QWidget,
    )
    HAS_PYSIDE6 = True
except ImportError:
    HAS_PYSIDE6 = False


@dataclass
class CombatantState:
    """Tracks a creature's hit points, damage, targets, and active status conditions."""

    obj_id: str
    name: str
    max_hp: int = 0
    lethal_damage: int = 0
    non_lethal_damage: int = 0
    temp_hp: int = 0
    temp_damage: int = 0
    ac: int = 10
    touch_ac: int = 10
    flat_footed_ac: int = 10
    cmd: int = 10
    is_flat_footed: bool = False
    is_stable: bool = False
    killed: bool = False
    targets: list[str] = field(default_factory=list)
    conditions: set[str] = field(default_factory=set)

    @property
    def current_hp(self) -> int:
        return self.max_hp - self.lethal_damage

    @property
    def effective_hp(self) -> int:
        return (self.max_hp + self.temp_hp - self.temp_damage) - self.lethal_damage

    @property
    def hp_percentage(self) -> int:
        denom = self.max_hp + self.temp_hp - self.temp_damage
        if denom <= 0:
            return 100 if self.lethal_damage == 0 else 0
        return max(0, min(100, int(round(self.effective_hp * 100.0 / denom))))

    @property
    def is_staggered_or_unconscious(self) -> bool:
        effective = self.current_hp + self.temp_hp - self.non_lethal_damage
        return effective <= 0


def format_hp_summary(c: CombatantState) -> str:
    """Format a compact HP summary string for a combatant."""
    parts = [f"HP: {c.current_hp}/{c.max_hp}"]
    if c.temp_hp > 0:
        parts.append(f"(+{c.temp_hp} tmp)")
    if c.non_lethal_damage > 0:
        parts.append(f"[{c.non_lethal_damage} NL]")
    return " ".join(parts)


def combatant_state_from_token_data(obj_id: str, data: dict[str, Any]) -> CombatantState:
    """Construct a ``CombatantState`` from a creature token/AC dictionary."""
    health = data.get("Health")
    if not isinstance(health, dict):
        health = {}
    name = str(data.get("Name", obj_id) or obj_id)
    conds = set(data.get("StatusList", []) or [])
    h_cond = str(health.get("Condition", "") or "")
    if h_cond and h_cond not in ("normal", "alive"):
        conds.add("flat-footed" if h_cond == "flat" else h_cond)
    is_ff = bool(health.get("IsFlatFooted", False) or "flat-footed" in conds)
    is_stable = bool(health.get("IsStable", False) or "stable" in conds)
    return CombatantState(
        obj_id=obj_id,
        name=name,
        max_hp=int(data.get("MaxHP", health.get("MaxHP", 0)) or 0),
        lethal_damage=int(data.get("LethalDamage", health.get("LethalDamage", 0)) or 0),
        non_lethal_damage=int(data.get("NonLethalDamage", health.get("NonLethalDamage", 0)) or 0),
        temp_hp=int(data.get("TmpHP", health.get("TmpHP", 0)) or 0),
        temp_damage=int(data.get("TmpDamage", health.get("TmpDamage", 0)) or 0),
        ac=int(data.get("AC", health.get("AC", 10)) or 10),
        touch_ac=int(data.get("TouchAC", health.get("TouchAC", 10)) or 10),
        flat_footed_ac=int(data.get("FlatFootedAC", health.get("FlatFootedAC", 10)) or 10),
        cmd=int(data.get("CMD", health.get("CMD", 10)) or 10),
        is_flat_footed=is_ff,
        is_stable=is_stable,
        killed=bool(data.get("Killed", False) or h_cond == "dead"),
        targets=list(data.get("Targets", []) or []),
        conditions=conds,
    )


def apply_local_hp_adjustment(
    data: dict[str, Any],
    delta_lethal: int = 0,
    delta_nonlethal: int = 0,
    set_temp_hp: int | None = None,
    set_max_hp: int | None = None,
    full_heal: bool = False,
) -> dict[str, Any]:
    """Compute updated ``Health`` dictionary after applying damage/healing to ``data``."""
    old_health = data.get("Health")
    health: dict[str, Any] = dict(old_health) if isinstance(old_health, dict) else {}

    max_hp = int(data.get("MaxHP", health.get("MaxHP", 0)) or 0)
    lethal = int(data.get("LethalDamage", health.get("LethalDamage", 0)) or 0)
    nonlethal = int(data.get("NonLethalDamage", health.get("NonLethalDamage", 0)) or 0)
    tmp_hp = int(data.get("TmpHP", health.get("TmpHP", 0)) or 0)

    if set_max_hp is not None:
        max_hp = max(0, int(set_max_hp))
    if set_temp_hp is not None:
        tmp_hp = max(0, int(set_temp_hp))

    if full_heal:
        lethal = 0
        nonlethal = 0
    else:
        if delta_lethal > 0 and tmp_hp > 0:
            # Absorb lethal damage into temporary HP first
            absorbed = min(tmp_hp, delta_lethal)
            tmp_hp -= absorbed
            delta_lethal -= absorbed
        lethal = max(0, lethal + int(delta_lethal))
        nonlethal = max(0, nonlethal + int(delta_nonlethal))

    health["MaxHP"] = max_hp
    health["LethalDamage"] = lethal
    health["NonLethalDamage"] = nonlethal
    health["TmpHP"] = tmp_hp

    eff_hp = (max_hp + tmp_hp) - lethal
    if max_hp > 0:
        if eff_hp < 0:
            health["Condition"] = "dying"
        elif eff_hp == 0:
            health["Condition"] = "disabled"
        else:
            if health.get("Condition") in ("dying", "disabled"):
                health["Condition"] = ""
    return health


if HAS_PYSIDE6:

    class HPRequestDialog(QDialog):
        """Dialog to submit an ``HPREQ`` hit point or temporary HP request (`initiate_hp_request`)."""

        def __init__(
            self,
            target_name: str = "",
            is_temp: bool = False,
            initial_state: CombatantState | None = None,
            parent: QWidget | None = None,
        ) -> None:
            super().__init__(parent)
            self.is_temp = is_temp
            self.request_id = new_id()
            self.setWindowTitle("New Temporary HP Request" if is_temp else "New HP Change Request")
            self.setMinimumWidth(400)

            layout = QVBoxLayout(self)
            form = QFormLayout()

            self.desc_edit = QLineEdit(self)
            self.desc_edit.setPlaceholderText("Reason / spell / attack description")
            form.addRow("Description:", self.desc_edit)

            self.targets_edit = QLineEdit(strip_nameplate_prefix(target_name), self)
            form.addRow("Targets (Character Name):", self.targets_edit)

            if is_temp:
                self.expires_edit = QLineEdit("+10 rounds", self)
                self.expires_edit.setPlaceholderText("e.g. +10 rounds, 1 hour, @12:00")
                form.addRow("Expires:", self.expires_edit)

                self.tmp_hp_spin = QSpinBox(self)
                self.tmp_hp_spin.setRange(0, 9999)
                self.tmp_hp_spin.setValue(initial_state.temp_hp if initial_state else 10)
                form.addRow("Temporary HP:", self.tmp_hp_spin)

                self.tmp_dmg_spin = QSpinBox(self)
                self.tmp_dmg_spin.setRange(0, 9999)
                self.tmp_dmg_spin.setValue(0)
                form.addRow("Damage Against Tmp HP:", self.tmp_dmg_spin)
            else:
                self.max_hp_spin = QSpinBox(self)
                self.max_hp_spin.setRange(0, 9999)
                self.max_hp_spin.setValue(initial_state.max_hp if initial_state else 20)
                form.addRow("Max HP:", self.max_hp_spin)

                self.lethal_spin = QSpinBox(self)
                self.lethal_spin.setRange(0, 9999)
                self.lethal_spin.setValue(initial_state.lethal_damage if initial_state else 0)
                form.addRow("Lethal Damage:", self.lethal_spin)

                self.nonlethal_spin = QSpinBox(self)
                self.nonlethal_spin.setRange(0, 9999)
                self.nonlethal_spin.setValue(initial_state.non_lethal_damage if initial_state else 0)
                form.addRow("Nonlethal Damage:", self.nonlethal_spin)

            layout.addLayout(form)

            self.status_label = QLabel("", self)
            self.status_label.setStyleSheet("color: #c53030;")
            layout.addWidget(self.status_label)

            buttons = QDialogButtonBox(
                QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel,
                self,
            )
            buttons.button(QDialogButtonBox.StandardButton.Ok).setText("Request")
            buttons.accepted.connect(self._on_accept)
            buttons.rejected.connect(self.reject)
            layout.addWidget(buttons)

        def _on_accept(self) -> None:
            if not self.targets_edit.text().strip():
                self.status_label.setText("At least one target character name is required.")
                return
            if self.is_temp and not self.expires_edit.text().strip():
                self.status_label.setText("Expiration time is required for temporary HP.")
                return
            self.accept()

        def request_dict(self) -> dict[str, Any]:
            targets = [t for t in self.targets_edit.text().strip().split() if t]
            if self.is_temp:
                return {
                    "Targets": targets,
                    "Description": self.desc_edit.text().strip(),
                    "RequestID": self.request_id,
                    "TmpHP": {
                        "TmpHP": self.tmp_hp_spin.value(),
                        "TmpDamage": self.tmp_dmg_spin.value(),
                        "Expires": self.expires_edit.text().strip(),
                    },
                }
            return {
                "Targets": targets,
                "Description": self.desc_edit.text().strip(),
                "RequestID": self.request_id,
                "Health": {
                    "MaxHP": self.max_hp_spin.value(),
                    "LethalDamage": self.lethal_spin.value(),
                    "NonLethalDamage": self.nonlethal_spin.value(),
                },
            }

    class CombatPanel(QWidget):
        """Dockable panel for managing creature HP (`OA`/`HPREQ`), conditions (`OA+`/`OA-`), targets, and timers."""

        hpChangeRequested = Signal(str, int, int, int)      # (obj_id, delta_lethal, delta_nonlethal, set_temp_hp_or_neg1)
        fullHealRequested = Signal(str)                     # obj_id
        healthAttrsChanged = Signal(str, dict)              # (obj_id, health_subdict)
        killedToggled = Signal(str, bool)                   # (obj_id, killed)
        conditionToggled = Signal(str, str, bool)           # (obj_id, condition_name, enabled)
        clearConditionsRequested = Signal(str)              # obj_id
        locateRequested = Signal(str)                       # obj_id
        targetsChanged = Signal(str, list)                  # (obj_id, target_names)
        hpDialogRequested = Signal(str, bool)               # (obj_id, is_temp)

        def __init__(self, parent: QWidget | None = None) -> None:
            super().__init__(parent)
            self.combatants: dict[str, CombatantState] = {}

            layout = QVBoxLayout(self)
            layout.setContentsMargins(6, 6, 6, 6)

            # Creature selector + Locate button
            sel_row = QHBoxLayout()
            sel_row.addWidget(QLabel("Creature:", self))
            self.creature_combo = QComboBox(self)
            self.creature_combo.currentIndexChanged.connect(self._on_creature_selected)
            sel_row.addWidget(self.creature_combo, 1)

            self.btn_locate = QPushButton("Locate", self)
            self.btn_locate.setToolTip("Center map view on selected creature")
            self.btn_locate.clicked.connect(self._on_locate_clicked)
            sel_row.addWidget(self.btn_locate)
            layout.addLayout(sel_row)

            # HP Group
            hp_group = QGroupBox("Hit Points & Damage", self)
            hp_layout = QVBoxLayout(hp_group)

            hp_top_row = QHBoxLayout()
            self.hp_label = QLabel("HP: --/--", hp_group)
            hp_top_row.addWidget(self.hp_label, 1)

            self.btn_req_hp = QPushButton("HPREQ...", hp_group)
            self.btn_req_hp.setToolTip("Send formal HP adjustment request to GM (HPREQ)")
            self.btn_req_hp.clicked.connect(lambda: self._emit_hp_dialog(False))
            self.btn_req_tmp = QPushButton("+Tmp HP...", hp_group)
            self.btn_req_tmp.setToolTip("Send formal Temporary HP request to GM (HPREQ)")
            self.btn_req_tmp.clicked.connect(lambda: self._emit_hp_dialog(True))
            hp_top_row.addWidget(self.btn_req_hp)
            hp_top_row.addWidget(self.btn_req_tmp)
            hp_layout.addLayout(hp_top_row)

            self.hp_bar = QProgressBar(hp_group)
            self.hp_bar.setRange(0, 100)
            self.hp_bar.setValue(100)
            self.hp_bar.setFixedHeight(14)
            hp_layout.addWidget(self.hp_bar)

            adj_row = QHBoxLayout()
            self.amount_spin = QSpinBox(hp_group)
            self.amount_spin.setRange(1, 9999)
            self.amount_spin.setValue(5)
            adj_row.addWidget(self.amount_spin)

            self.btn_dmg = QPushButton("Damage", hp_group)
            self.btn_dmg.clicked.connect(lambda: self._emit_hp_adjust(1, 0))
            self.btn_heal = QPushButton("Heal", hp_group)
            self.btn_heal.clicked.connect(lambda: self._emit_hp_adjust(-1, 0))
            self.btn_nl = QPushButton("Nonlethal", hp_group)
            self.btn_nl.clicked.connect(lambda: self._emit_hp_adjust(0, 1))
            self.btn_full_heal = QPushButton("Full", hp_group)
            self.btn_full_heal.setToolTip("Heal all lethal and nonlethal damage")
            self.btn_full_heal.clicked.connect(self._on_full_heal_clicked)
            adj_row.addWidget(self.btn_dmg)
            adj_row.addWidget(self.btn_heal)
            adj_row.addWidget(self.btn_nl)
            adj_row.addWidget(self.btn_full_heal)
            hp_layout.addLayout(adj_row)

            # Health state toggles (Flat-Footed, Stable, Killed)
            flags_row = QHBoxLayout()
            self.chk_flat_footed = QCheckBox("Flat-Footed", hp_group)
            self.chk_flat_footed.toggled.connect(self._on_health_flag_toggled)
            self.chk_stable = QCheckBox("Stable", hp_group)
            self.chk_stable.toggled.connect(self._on_health_flag_toggled)
            self.chk_killed = QCheckBox("Killed", hp_group)
            self.chk_killed.toggled.connect(self._on_killed_toggled)
            flags_row.addWidget(self.chk_flat_footed)
            flags_row.addWidget(self.chk_stable)
            flags_row.addWidget(self.chk_killed)
            hp_layout.addLayout(flags_row)

            # Active Targets row
            targ_row = QHBoxLayout()
            self.targets_label = QLabel("Targets: (none)", hp_group)
            self.targets_label.setWordWrap(True)
            targ_row.addWidget(self.targets_label, 1)
            self.btn_clear_targets = QPushButton("Clear Targets", hp_group)
            self.btn_clear_targets.clicked.connect(self._on_clear_targets)
            targ_row.addWidget(self.btn_clear_targets)
            hp_layout.addLayout(targ_row)

            layout.addWidget(hp_group)

            # Conditions Group
            cond_group = QGroupBox("Status Conditions", self)
            cond_layout = QVBoxLayout(cond_group)

            filter_row = QHBoxLayout()
            self.cond_filter_edit = QLineEdit(cond_group)
            self.cond_filter_edit.setPlaceholderText("Filter conditions...")
            self.cond_filter_edit.textChanged.connect(self._on_filter_conditions)
            filter_row.addWidget(self.cond_filter_edit, 1)

            self.btn_clear_conds = QPushButton("Clear All", cond_group)
            self.btn_clear_conds.setToolTip("Remove all status conditions from selected creature")
            self.btn_clear_conds.clicked.connect(self._on_clear_all_conditions)
            filter_row.addWidget(self.btn_clear_conds)
            cond_layout.addLayout(filter_row)

            self.condition_list = QListWidget(cond_group)
            for cond_name in sorted(MARKER_DESCRIPTION.keys()):
                item = QListWidgetItem(cond_name)
                item.setFlags(item.flags() | Qt.ItemFlag.ItemIsUserCheckable)
                item.setCheckState(Qt.CheckState.Unchecked)
                item.setToolTip(MARKER_DESCRIPTION.get(cond_name, cond_name))
                self.condition_list.addItem(item)
            self.condition_list.itemChanged.connect(self._on_condition_item_changed)
            cond_layout.addWidget(self.condition_list, 1)
            layout.addWidget(cond_group, 1)

            # Progress / Operation Bar
            self.progress_bar = QProgressBar(self)
            self.progress_bar.setVisible(False)
            layout.addWidget(self.progress_bar)

        def current_creature_id(self) -> str | None:
            data = self.creature_combo.currentData()
            return str(data) if data else None

        def select_creature(self, obj_id_or_name: str) -> bool:
            """Select a combatant in ``creature_combo`` by ``obj_id`` or ``Name``."""
            if not obj_id_or_name:
                return False
            idx = self.creature_combo.findData(obj_id_or_name)
            if idx >= 0:
                self.creature_combo.setCurrentIndex(idx)
                return True
            clean_target = strip_nameplate_prefix(obj_id_or_name)
            for cid, st in self.combatants.items():
                if st.name == obj_id_or_name or strip_nameplate_prefix(st.name) == clean_target:
                    idx2 = self.creature_combo.findData(cid)
                    if idx2 >= 0:
                        self.creature_combo.setCurrentIndex(idx2)
                        return True
            return False

        def update_combatant(self, state: CombatantState) -> None:
            self.combatants[state.obj_id] = state
            disp_name = strip_nameplate_prefix(state.name) or state.name
            idx = self.creature_combo.findData(state.obj_id)
            if idx < 0:
                self.creature_combo.addItem(disp_name, state.obj_id)
            else:
                self.creature_combo.setItemText(idx, disp_name)
            if self.current_creature_id() == state.obj_id:
                self._refresh_selected()

        def remove_combatant(self, obj_id: str) -> None:
            self.combatants.pop(obj_id, None)
            idx = self.creature_combo.findData(obj_id)
            if idx >= 0:
                self.creature_combo.removeItem(idx)
            self._refresh_selected()

        def clear_combatants(self) -> None:
            self.combatants.clear()
            self.creature_combo.clear()
            self._refresh_selected()

        def _on_creature_selected(self, _idx: int) -> None:
            self._refresh_selected()

        def _refresh_selected(self) -> None:
            cid = self.current_creature_id()
            if not cid or cid not in self.combatants:
                self.hp_label.setText("HP: --/--")
                self.hp_bar.setValue(0)
                self.targets_label.setText("Targets: (none)")
                return
            st = self.combatants[cid]
            self.hp_label.setText(format_hp_summary(st))

            pct = st.hp_percentage
            self.hp_bar.setValue(pct)
            if pct <= 25:
                self.hp_bar.setStyleSheet("QProgressBar::chunk { background-color: #c53030; }")
            elif pct <= 50:
                self.hp_bar.setStyleSheet("QProgressBar::chunk { background-color: #d69e2e; }")
            else:
                self.hp_bar.setStyleSheet("QProgressBar::chunk { background-color: #2f855a; }")

            self.chk_flat_footed.blockSignals(True)
            self.chk_stable.blockSignals(True)
            self.chk_killed.blockSignals(True)
            self.chk_flat_footed.setChecked(st.is_flat_footed)
            self.chk_stable.setChecked(st.is_stable)
            self.chk_killed.setChecked(st.killed)
            self.chk_flat_footed.blockSignals(False)
            self.chk_stable.blockSignals(False)
            self.chk_killed.blockSignals(False)

            if st.targets:
                clean_targs = [strip_nameplate_prefix(t) for t in st.targets]
                self.targets_label.setText(f"Targets: {', '.join(clean_targs)}")
            else:
                self.targets_label.setText("Targets: (none)")

            self.condition_list.blockSignals(True)
            for i in range(self.condition_list.count()):
                item = self.condition_list.item(i)
                item.setCheckState(
                    Qt.CheckState.Checked if item.text() in st.conditions else Qt.CheckState.Unchecked
                )
            self.condition_list.blockSignals(False)

        def _on_filter_conditions(self, text: str) -> None:
            needle = text.strip().lower()
            for i in range(self.condition_list.count()):
                item = self.condition_list.item(i)
                item.setHidden(bool(needle) and needle not in item.text().lower())

        def _emit_hp_adjust(self, lethal_sign: int, nl_sign: int) -> None:
            cid = self.current_creature_id()
            if not cid:
                return
            amt = self.amount_spin.value()
            self.hpChangeRequested.emit(cid, lethal_sign * amt, nl_sign * amt, -1)

        def _on_full_heal_clicked(self) -> None:
            cid = self.current_creature_id()
            if cid:
                self.fullHealRequested.emit(cid)

        def _emit_hp_dialog(self, is_temp: bool) -> None:
            cid = self.current_creature_id()
            if cid:
                self.hpDialogRequested.emit(cid, is_temp)

        def _on_locate_clicked(self) -> None:
            cid = self.current_creature_id()
            if cid:
                self.locateRequested.emit(cid)

        def _on_health_flag_toggled(self, _checked: bool) -> None:
            cid = self.current_creature_id()
            if not cid or cid not in self.combatants:
                return
            st = self.combatants[cid]
            st.is_flat_footed = self.chk_flat_footed.isChecked()
            st.is_stable = self.chk_stable.isChecked()
            self.healthAttrsChanged.emit(
                cid,
                {
                    "IsFlatFooted": st.is_flat_footed,
                    "IsStable": st.is_stable,
                },
            )

        def _on_killed_toggled(self, checked: bool) -> None:
            cid = self.current_creature_id()
            if not cid or cid not in self.combatants:
                return
            self.combatants[cid].killed = bool(checked)
            self.killedToggled.emit(cid, bool(checked))

        def _on_clear_targets(self) -> None:
            cid = self.current_creature_id()
            if not cid or cid not in self.combatants:
                return
            self.combatants[cid].targets = []
            self.targets_label.setText("Targets: (none)")
            self.targetsChanged.emit(cid, [])

        def _on_clear_all_conditions(self) -> None:
            cid = self.current_creature_id()
            if not cid or cid not in self.combatants:
                return
            self.combatants[cid].conditions.clear()
            self._refresh_selected()
            self.clearConditionsRequested.emit(cid)

        def _on_condition_item_changed(self, item: QListWidgetItem) -> None:
            cid = self.current_creature_id()
            if not cid:
                return
            enabled = item.checkState() == Qt.CheckState.Checked
            self.condition_list.blockSignals(True)
            if cid in self.combatants:
                if enabled:
                    self.combatants[cid].conditions.add(item.text())
                else:
                    self.combatants[cid].conditions.discard(item.text())
            self.condition_list.blockSignals(False)
            self.conditionToggled.emit(cid, item.text(), enabled)

        def set_progress(self, title: str, current: int, maximum: int) -> None:
            if maximum <= 0 or current >= maximum:
                self.progress_bar.setVisible(False)
            else:
                self.progress_bar.setVisible(True)
                self.progress_bar.setFormat(f"{title}: %p%")
                self.progress_bar.setRange(0, maximum)
                self.progress_bar.setValue(current)

else:

    class CombatPanel:  # type: ignore[no-redef]
        def __init__(self, parent: Any = None) -> None:
            self.combatants: dict[str, CombatantState] = {}

        def select_creature(self, obj_id_or_name: str) -> bool:
            return obj_id_or_name in self.combatants

        def update_combatant(self, state: CombatantState) -> None:
            self.combatants[state.obj_id] = state

        def remove_combatant(self, obj_id: str) -> None:
            self.combatants.pop(obj_id, None)

        def clear_combatants(self) -> None:
            self.combatants.clear()

        def set_progress(self, title: str, current: int, maximum: int) -> None:
            pass
