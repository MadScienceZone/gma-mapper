"""Pure-Python preset/modifier/variable logic and PySide6 row widgets for ``py_dieroller``.

Ported from ``GMADieRoller/Variable.py``, ``GMADieRoller/Modifier.py``, and
``GMADieRoller/Preset.py``.
"""

from __future__ import annotations

import re
from typing import Any, Callable

PRESET_TYPES: tuple[str, ...] = ("attack", "damage", "save", "skill", "other")
MODIFIER_TYPES: tuple[str, ...] = (*PRESET_TYPES, "atk/dmg")

PRESET_TAB_BY_TYPE: dict[str, str] = {
    "attack": "pnCombat",
    "damage": "pnCombat",
    "save": "pnSave",
    "skill": "pnSkill",
    "other": "pnOther",
}

_VAR_RE = re.compile(r"\$\{([^{}]+)\}")
_GMA_CRIT_RE = re.compile(r"\|\s*c([0-9]*)$", flags=re.IGNORECASE)
_GMA_PTYPE_RE = re.compile(r"(attack|damage|save|skill)", flags=re.IGNORECASE)

COLOR_INVALID_REGEX = "#eba0b8"
COLOR_HAS_MOD = "#fde5c1"


def expand_variables(
    text: str,
    variable_defs: dict[str, str],
    limit: int = 50,
) -> tuple[str, str | None]:
    """Expand ``${name}`` variable references in ``text``.

    Returns ``(expanded_text, error_message)``. When a circular expansion or
    recursion limit is hit, returns the partially expanded text and an error string.
    """
    if len(text) < 3:
        return (text, None)

    def _expand_one(rem: int, seen: set[str], g0: str, g1: str) -> tuple[str | None, str | None]:
        if rem <= 0:
            return (None, "Recursion limit exceeded")
        if g0 in seen:
            return (None, f"Circular expansion of {g0} in expression")
        seen.add(g0)
        if g1 not in variable_defs:
            return ("", None)
        cur = str(variable_defs[g1])
        inner_rem = rem
        while inner_rem > 0:
            m = _VAR_RE.search(cur)
            if m is None:
                return (cur, None)
            sub, err = _expand_one(inner_rem - 1, set(seen), str(m.group(0)), str(m.group(1)))
            if err is not None or sub is None:
                return (None, err or "Recursion limit exceeded")
            cur = _VAR_RE.sub(lambda _match, rep=sub: rep, cur, count=1)
            inner_rem -= 1
        return (None, "Recursion limit exceeded")

    cur_text = text
    rem = limit
    while rem > 0:
        m = _VAR_RE.search(cur_text)
        if m is None:
            return (cur_text, None)
        sub, err = _expand_one(rem, set(), str(m.group(0)), str(m.group(1)))
        if err is not None or sub is None:
            return (cur_text, err)
        cur_text = _VAR_RE.sub(lambda _match, rep=sub: rep, cur_text, count=1)
        rem -= 1
    return (cur_text, "Recursion limit exceeded")


def match_modifier_to_preset(
    mtype: str,
    pattern: re.Pattern[str] | None,
    ptype: str,
    label: str,
) -> bool:
    """Return True if a modifier with ``(mtype, pattern)`` applies to ``(ptype, label)``."""
    if mtype == "atk/dmg":
        if ptype not in ("attack", "damage"):
            return False
    elif mtype != ptype:
        return False

    if pattern is None:
        return True
    return bool(pattern.search(label))


def format_applied_modifiers(mods: list[tuple[str, str]]) -> str:
    """Format a list of ``(mod_expr, source_label)`` tuples into a roll modifier suffix."""
    parts: list[str] = []
    for raw_mod, raw_src in mods:
        smod = raw_mod.strip()
        if not smod:
            continue
        chunk = smod if smod[0] in ("-", "+") else f"+{smod}"
        src = raw_src.strip()
        if src:
            chunk += f" {src}"
        parts.append(chunk)
    return (" " + " ".join(parts)) if parts else ""


def build_preset_roll_expression(
    ptype: str,
    label: str,
    expr: str,
    mod: str = "",
    crit: str = "",
) -> str:
    """Build the full GMA roll expression string for a preset row."""
    clean_expr = expr.strip()
    if not clean_expr:
        return ""

    prefix = ptype.strip() if (ptype.strip() and ptype.strip() != "other") else ""
    clean_label = label.strip()
    if clean_label:
        prefix = f"{prefix}, {clean_label}" if prefix else clean_label

    text = f"{prefix} = {clean_expr}" if prefix else clean_expr
    clean_mod = mod.strip()
    if clean_mod:
        text += f" {clean_mod}"
    clean_crit = crit.strip()
    if clean_crit:
        text += f" | c{clean_crit}"
    return text


def parse_gma_preset(raw_preset: dict[str, Any]) -> dict[str, str]:
    """Convert a GMA ``.dice`` preset dictionary into a ``py_dieroller`` preset dict."""
    name = str(raw_preset.get("Name") or "").strip()
    label = str(raw_preset.get("Description") or "").strip() or name
    expr = str(raw_preset.get("DieRollSpec") or "").strip()

    crit_match = _GMA_CRIT_RE.search(expr)
    if crit_match:
        crit = crit_match.group(1)
        expr = _GMA_CRIT_RE.sub("", expr).strip()
        return {
            "ptype": "attack",
            "label": label,
            "expr": expr,
            "crit": crit,
        }

    ptype = "other"
    type_match = _GMA_PTYPE_RE.search(label)
    if type_match:
        ptype = type_match.group(1).lower()

    return {
        "ptype": ptype,
        "label": label,
        "expr": expr,
        "crit": "",
    }


try:
    from PySide6.QtWidgets import QCheckBox, QComboBox, QLineEdit, QWidget

    QT_AVAILABLE = True
except ImportError:  # pragma: no cover
    QT_AVAILABLE = False


if QT_AVAILABLE:

    class VariableRow:
        """One editable variable row (``name``, ``val``) in the Variables tab."""

        def __init__(
            self,
            parent: QWidget,
            on_changed: Callable[[], None],
            name: str = "",
            val: str = "",
        ) -> None:
            self._on_changed = on_changed
            self.name = QLineEdit(str(name), parent)
            self.name.setPlaceholderText("var_name")
            self.name.textChanged.connect(lambda _t: self._on_changed())

            self.val = QLineEdit(str(val), parent)
            self.val.setPlaceholderText("value or expression")
            self.val.textChanged.connect(lambda _t: self._on_changed())

        def value(self, which: str) -> str:
            """Return trimmed field value for ``name`` or ``value``."""
            if which == "name":
                return self.name.text().strip()
            if which == "value":
                return self.val.text().strip()
            raise ValueError(f"Unknown variable field {which}")

        def to_dict(self) -> dict[str, str]:
            """Serialize this row to a presets JSON variable dict."""
            return {"name": self.value("name"), "val": self.value("value")}

        def widgets(self) -> tuple[QWidget, ...]:
            """Return column widgets in left-to-right grid order."""
            return (self.name, self.val)

    class ModifierRow:
        """One editable modifier row (active, source, mtype, match regex, mod) in Modifiers tab."""

        def __init__(
            self,
            parent: QWidget,
            on_changed: Callable[[], None],
            active: bool = False,
            source: str = "",
            mtype: str = "",
            match: str = "",
            mod: str = "",
        ) -> None:
            self._on_changed = on_changed
            self.pat: re.Pattern[str] | None = None

            self.active = QCheckBox(parent)
            self.active.setChecked(bool(active))
            self.active.stateChanged.connect(lambda _s: self._on_changed())

            self.source = QLineEdit(str(source), parent)
            self.source.setPlaceholderText("Source (e.g. Bless)")
            self.source.textChanged.connect(lambda _t: self._on_changed())

            self.mtype = QComboBox(parent)
            self.mtype.addItems(sorted(MODIFIER_TYPES))
            if mtype:
                idx = self.mtype.findText(str(mtype))
                if idx >= 0:
                    self.mtype.setCurrentIndex(idx)
            self.mtype.currentTextChanged.connect(lambda _t: self._on_changed())

            self.match = QLineEdit(str(match), parent)
            self.match.setPlaceholderText("Regex (optional)")
            self.match.textChanged.connect(self._on_match_text_changed)

            self.mod = QLineEdit(str(mod), parent)
            self.mod.setPlaceholderText("+1")
            self.mod.textChanged.connect(lambda _t: self._on_changed())

            self._compile_regex()

        def _on_match_text_changed(self, _text: str) -> None:
            self._compile_regex()
            self._on_changed()

        def _compile_regex(self) -> None:
            raw = self.match.text().strip()
            if not raw:
                self.pat = None
                self.match.setStyleSheet("")
                self.match.setToolTip("")
                return
            try:
                self.pat = re.compile(raw, re.IGNORECASE)
                self.match.setStyleSheet("")
                self.match.setToolTip("")
            except re.error:
                self.pat = None
                self.match.setStyleSheet(f"background-color: {COLOR_INVALID_REGEX};")
                self.match.setToolTip("Invalid regular expression")

        def is_active(self) -> bool:
            """Return True when this modifier checkbox is checked."""
            return self.active.isChecked()

        def value(self, which: str) -> str:
            """Return trimmed field value for ``source``, ``mtype``, ``match``, or ``mod``."""
            if which == "source":
                return self.source.text().strip()
            if which == "mtype":
                return self.mtype.currentText().strip()
            if which == "match":
                return self.match.text().strip()
            if which == "mod":
                return self.mod.text().strip()
            raise ValueError(f"Unknown modifier field {which}")

        def match_preset(self, preset: PresetRow) -> bool:
            """Return True if this modifier applies to ``preset``."""
            return match_modifier_to_preset(
                self.value("mtype"),
                self.pat,
                preset.value("ptype"),
                preset.value("label"),
            )

        def to_dict(self) -> dict[str, Any]:
            """Serialize this row to a presets JSON modifier dict."""
            return {
                "active": self.is_active(),
                "source": self.value("source"),
                "mtype": self.value("mtype"),
                "match": self.value("match"),
                "mod": self.value("mod"),
            }

        def widgets(self) -> tuple[QWidget, ...]:
            """Return column widgets in left-to-right grid order."""
            return (self.active, self.source, self.mtype, self.match, self.mod)

    class PresetRow:
        """One editable preset row in Atk/Dmg, Save, Skill, or Other tab."""

        def __init__(
            self,
            parent: QWidget,
            tab_name: str,
            on_changed: Callable[[], None],
            get_modifiers: Callable[[], list[ModifierRow]],
            ptype: str = "",
            label: str = "",
            expr: str = "",
            crit: str = "",
        ) -> None:
            self.tab_name = tab_name
            self._on_changed = on_changed
            self._get_modifiers = get_modifiers
            self.ptype_combo: QComboBox | None = None
            self.crit_edit: QLineEdit | None = None
            self._fixed_ptype: str = "other"

            self.label_edit = QLineEdit(str(label), parent)
            self.label_edit.setPlaceholderText("Label")
            self.label_edit.textChanged.connect(self._on_label_changed)

            self.expr_edit = QLineEdit(str(expr), parent)
            self.expr_edit.setPlaceholderText("1d20+5")
            self.expr_edit.textChanged.connect(lambda _t: self._on_changed())

            self.mod_edit = QLineEdit("", parent)
            self.mod_edit.setReadOnly(True)
            self.mod_edit.setPlaceholderText("auto mods")

            if tab_name == "pnCombat":
                self.ptype_combo = QComboBox(parent)
                self.ptype_combo.addItems(["attack", "damage"])
                idx = self.ptype_combo.findText(str(ptype))
                self.ptype_combo.setCurrentIndex(idx if idx >= 0 else 0)
                self.ptype_combo.currentTextChanged.connect(self._on_ptype_changed)

                self.crit_edit = QLineEdit(str(crit), parent)
                self.crit_edit.setMaximumWidth(54)
                self.crit_edit.setPlaceholderText("19")
                self.crit_edit.textChanged.connect(lambda _t: self._on_changed())
                self.crit_edit.setEnabled(self.ptype_combo.currentText().strip() == "attack")
            elif tab_name == "pnSave":
                self._fixed_ptype = "save"
            elif tab_name == "pnSkill":
                self._fixed_ptype = "skill"
            else:
                self._fixed_ptype = "other"

        def _on_ptype_changed(self, _text: str) -> None:
            if self.crit_edit is not None:
                self.crit_edit.setEnabled(self.value("ptype") == "attack")
            self.update_modifiers()
            self._on_changed()

        def _on_label_changed(self, _text: str) -> None:
            self.update_modifiers()
            self._on_changed()

        def value(self, which: str) -> str:
            """Return trimmed field value for ``ptype``, ``label``, ``expr``, ``crit``, or ``mod``."""
            if which == "ptype":
                if self.ptype_combo is not None:
                    return self.ptype_combo.currentText().strip()
                return self._fixed_ptype
            if which == "label":
                return self.label_edit.text().strip()
            if which == "expr":
                return self.expr_edit.text().strip()
            if which == "crit":
                if self.crit_edit is None or not self.crit_edit.isEnabled():
                    return ""
                return self.crit_edit.text().strip()
            if which == "mod":
                return self.mod_edit.text().strip()
            raise ValueError(f"Unknown preset field {which}")

        def roll_expression(self) -> str:
            """Build the complete roll expression string including active modifiers and crit."""
            return build_preset_roll_expression(
                ptype=self.value("ptype"),
                label=self.value("label"),
                expr=self.value("expr"),
                mod=self.value("mod"),
                crit=self.value("crit"),
            )

        def update_modifiers(self) -> None:
            """Recompute matching active modifiers and update the read-only Mod preview box."""
            matching: list[tuple[str, str]] = []
            for mod in self._get_modifiers():
                if mod.is_active() and mod.match_preset(self):
                    matching.append((mod.value("mod"), mod.value("source")))
            formatted = format_applied_modifiers(matching)
            if not formatted:
                self.mod_edit.clear()
                self.mod_edit.setToolTip("")
                self.mod_edit.setStyleSheet("")
                return
            self.mod_edit.setText(formatted)
            self.mod_edit.setToolTip(formatted.strip())
            self.mod_edit.setStyleSheet(
                f"background-color: {COLOR_HAS_MOD}; color: #1a1a1a;"
            )

        def to_dict(self) -> dict[str, str]:
            """Serialize this row to a presets JSON entry dict."""
            return {
                "ptype": self.value("ptype"),
                "label": self.value("label"),
                "expr": self.value("expr"),
                "crit": self.crit_edit.text().strip() if self.crit_edit is not None else "",
            }
