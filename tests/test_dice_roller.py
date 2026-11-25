"""Unit tests for the GMA Mapper Die-Roller, Preset Codec, Lookup Tables, Statistics, and Chat History."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

from gma_mapper.core.dice import (
    ChatHistoryManager,
    DicePresetBank,
    RollStatCollector,
    add_to_die_roll_title,
    apply_die_roll_mods,
    apply_die_roll_variables,
    build_color_box_title,
    cleanup_die_roll_spec,
    encode_preset_details,
    format_component_html,
    get_preset_details,
    merge_preset_lists,
    parse_color_blocks,
    prepare_die_roll,
    render_chat_payload_html,
    render_roll_payload_html,
    resolve_table_roll_reply,
    resolve_targeted_modifiers,
    search_for_preset,
)
from gma_mapper.ui.dialogs.dice_dialogs import (
    QT_AVAILABLE,
    validate_and_sort_table_rows,
)
from gma_mapper.ui.main_window import MapperController


class TestPresetCodec(unittest.TestCase):
    """Tests for `get_preset_details` and `encode_preset_details`."""

    def test_standard_and_grouped_preset_roundtrip(self) -> None:
        raw = {
            "Name": "010\u25b6Attacks\u25b6Melee|Longsword",
            "Description": "Primary melee attack",
            "DieRollSpec": "Longsword\u2261gold=1d20+8 1d8+4 |c19",
            "Global": False,
        }
        details = get_preset_details(raw)
        self.assertEqual(details["type"], "preset")
        self.assertEqual(details["seq"], "010")
        self.assertEqual(details["group"], ["Attacks", "Melee"])
        self.assertEqual(details["name"], "Longsword")
        self.assertFalse(details["system"])

        encoded = encode_preset_details(details)
        self.assertEqual(encoded, raw)

    def test_modifier_and_variable_preset_roundtrip(self) -> None:
        raw_mod = {
            "Name": "\u00a7020\u25b6Buffs;pa;eg|Power Attack",
            "Description": "Melee damage trade-off",
            "DieRollSpec": "-2 { PA} | +4 { PA}",
            "Global": True,
        }
        details = get_preset_details(raw_mod)
        self.assertEqual(details["type"], "modifier")
        self.assertEqual(details["seq"], "020")
        self.assertEqual(details["group"], ["Buffs"])
        self.assertEqual(details["var"], "pa")
        self.assertTrue(details["enabled"])
        self.assertTrue(details["global"])
        self.assertTrue(details["system"])
        self.assertEqual(details["name"], "Power Attack")

        encoded = encode_preset_details(details)
        self.assertEqual(encoded, raw_mod)

    def test_lookup_table_roundtrip_and_auto_delimiter(self) -> None:
        raw_tbl = {
            "Name": "#005\u25b6Criticals;m|crit_effect",
            "Description": "Critical Hit Deck",
            "DieRollSpec": ";1d20;10;Normal double damage;19;Bleed 1d6;*;**Severed limb**;",
            "Global": False,
        }
        details = get_preset_details(raw_tbl)
        self.assertEqual(details["type"], "table")
        self.assertEqual(details["name"], "crit_effect")
        self.assertEqual(details["dieroll"], "1d20")
        self.assertTrue(details["markup"])
        self.assertEqual(
            details["table"],
            ["10", "Normal double damage", "19", "Bleed 1d6", "*", "**Severed limb**"],
        )

        # If a table result contains ';', encode_preset_details must pick an alternate delimiter
        details["table"] = ["10", "Low; result", "*", "High; result"]
        encoded = encode_preset_details(details)
        self.assertEqual(encoded["DieRollSpec"][0], "|")
        decoded_again = get_preset_details(encoded)
        self.assertEqual(decoded_again["type"], "table")
        self.assertEqual(decoded_again["table"], ["10", "Low; result", "*", "High; result"])

    def test_encode_seq_padding_area_client_and_merge(self) -> None:
        encoded_roll = encode_preset_details(
            {
                "type": "preset",
                "seq": "5",
                "area": "combat",
                "group": ["Melee"],
                "name": "Bite",
                "description": "Primary bite",
                "dieroll": "1d20+6",
            }
        )
        self.assertEqual(encoded_roll["Name"], "$[combat]005\u25b6Melee|Bite")
        decoded_roll = get_preset_details(encoded_roll)
        self.assertEqual(decoded_roll["seq"], "005")
        self.assertEqual(decoded_roll["area"], "combat")

        encoded_custom_seq = encode_preset_details(
            {
                "type": "modifier",
                "seq": "abc",
                "client": "myclient",
                "name": "Inspire",
                "description": "Bardic song",
                "var": "insp",
                "enabled": True,
                "dieroll": "+2",
            }
        )
        self.assertEqual(encoded_custom_seq["Name"], "\u00a7abc;insp;e;myclient|Inspire")
        self.assertEqual(encoded_custom_seq["Description"], "Bardic song")
        decoded_mod = get_preset_details(encoded_custom_seq)
        self.assertEqual(decoded_mod["client"], "myclient")
        self.assertEqual(decoded_mod["description"], "Bardic song")

        existing = [
            {"Name": "010|Attack", "Description": "Old", "DieRollSpec": "1d20+5"},
            {"Name": "020|Damage", "Description": "Slash", "DieRollSpec": "1d8+3"},
        ]
        incoming = [
            {"Name": "010|Attack", "Description": "Updated", "DieRollSpec": "1d20+7"},
            {"Name": "030|Init", "Description": "Initiative", "DieRollSpec": "1d20+4"},
        ]
        merged = merge_preset_lists(existing, incoming)
        self.assertEqual(
            [p["Name"] for p in merged],
            ["010|Attack", "020|Damage", "030|Init"],
        )
        self.assertEqual(merged[0]["Description"], "Updated")
        self.assertEqual(merged[0]["DieRollSpec"], "1d20+7")
        # Ensure deep copy (mutating merged does not mutate inputs)
        merged[1]["Description"] = "Mutated"
        self.assertEqual(existing[1]["Description"], "Slash")

    def test_cleanup_die_roll_spec_and_search(self) -> None:
        spec = "Attack\u2261white\u2261red\u2016Full Round\u2261yellow=1d20+10"
        self.assertEqual(cleanup_die_roll_spec(spec), "Attack\u2016Full Round=1d20+10")

        presets = [
            {
                "Name": "010|Longsword Attack",
                "Description": "Melee",
                "DieRollSpec": "1d20+8",
            },
            {
                "Name": "020|Longsword Damage",
                "Description": "Damage",
                "DieRollSpec": "1d8+4",
            },
        ]
        full, atk, dmg = search_for_preset(presets, r"longsword", for_Damage=True)
        self.assertEqual(full, "1d20+8")
        self.assertEqual(atk, "1d20+8")
        self.assertEqual(dmg, "1d8+4")


class TestRollPipelineAndTables(unittest.TestCase):
    """Tests for `DicePresetBank`, modifiers, variables, targeted modifiers, and `#table` rolls."""

    def setUp(self) -> None:
        self.bank = DicePresetBank(tkey="Valeros")
        self.bank.set_system_presets(
            [
                {
                    "Name": "\u00a7001;bless;eg|Bless",
                    "Description": "+1 morale on attacks",
                    "DieRollSpec": "+1 { bless}",
                    "Global": True,
                },
                {
                    "Name": "#001;m|weather",
                    "Description": "Weather Table",
                    "DieRollSpec": ";1d6;3;Clear skies;*;**Thunderstorm**;",
                    "Global": True,
                },
            ]
        )
        self.bank.set_user_presets(
            [
                {
                    "Name": "\u00a7010;;e|Flanking",
                    "Description": "+2 flanking",
                    "DieRollSpec": "2 { flanking}",
                    "Global": False,
                },
                {
                    "Name": "\u00a7020;sneak;|Sneak Attack",
                    "Description": "Rogue sneak attack",
                    "DieRollSpec": "+2d6 { sneak}",
                    "Global": False,
                },
                {
                    "Name": "#010;|loot",
                    "Description": "Pocket Loot",
                    "DieRollSpec": ";1d10;5;Copper coins;9;Silver ring;*;Gold amulet;",
                    "Global": False,
                },
            ]
        )

    def test_modifiers_and_variables_expansion(self) -> None:
        # 'Bless' ($$bless) is enabled by default ('e'), 'Flanking' is enabled by default ('e'),
        # 'Sneak Attack' ($sneak) is disabled by default.
        prepared = prepare_die_roll(
            rollspec="Dagger=1d20+5$$bless 1d4+2$sneak",
            extra="+1",
            bank=self.bank,
            for_user="Valeros",
            local_user="Ezren",
        )
        self.assertEqual(
            prepared["rollspec"],
            "(for Valeros) Dagger=1d20+5 +1 { bless}  1d4+2 +1 ad hoc+ 2 { flanking}",
        )

        # Enable $sneak and verify substitution
        self.bank.set_var_enabled("sneak", True)
        prepared2 = prepare_die_roll(
            rollspec="Damage=1d4+2$sneak",
            bank=self.bank,
        )
        self.assertIn("+2d6 { sneak}", prepared2["rollspec"])

    def test_undefined_and_recursive_variable_guards(self) -> None:
        with self.assertRaises(ValueError):
            apply_die_roll_variables("1d20+$nonexistent", bank=self.bank)

        self.bank.vars["loop_a"] = "$loop_b"
        self.bank.vars["loop_b"] = "$loop_a"
        self.bank.on_vars["loop_a"] = True
        self.bank.on_vars["loop_b"] = True
        with self.assertRaises(ValueError):
            apply_die_roll_variables("1d20+$loop_a", bank=self.bank)

    def test_targeted_creature_conditional_modifiers(self) -> None:
        mobs_by_id: dict[str, dict[str, Any]] = {
            "P1": {
                "ID": "P1",
                "Name": "Valeros",
                "Targets": ["M1"],
                "TargetedModifiers": {
                    "M1": {
                        "Sneak": {"Modifiers": ["$sneak"]},
                    }
                },
            }
        }
        mobs_by_name = {"Valeros": "P1"}
        # Even with $sneak unchecked in the UI, targeting M1 activates $sneak automatically
        self.bank.set_var_enabled("sneak", False)
        prepared = prepare_die_roll(
            rollspec="Shortbow=1d6$sneak",
            bank=self.bank,
            for_user="Valeros",
            local_user="Valeros",
            my_names=["Valeros"],
            mobs_by_id=mobs_by_id,
            mobs_by_name=mobs_by_name,
        )
        self.assertIn("+2d6 { sneak}", prepared["rollspec"])
        self.assertIsNone(prepared["warning"])

        # Mismatched multi-target conditions emit a warning and skip conditional modifiers
        mobs_by_id["P1"]["Targets"] = ["M1", "M2"]
        mobs_by_id["P1"]["TargetedModifiers"]["M2"] = {"Cover": {"Modifiers": ["Flanking"]}}
        _, _, _, warning = resolve_targeted_modifiers(
            "Valeros", ["Valeros"], mobs_by_id, mobs_by_name, self.bank.modsym
        )
        self.assertIsNotNone(warning)

    def test_lookup_table_interception_and_reply(self) -> None:
        prepared = prepare_die_roll(
            rollspec="#loot +1",
            bank=self.bank,
            req_id="r42",
        )
        self.assertTrue(prepared["is_table_roll"])
        self.assertEqual(prepared["request_id"], "#loot;Valeros;;r42")
        self.assertIn("1d10 +1", prepared["rollspec"])

        # Simulate incoming ROLL reply from server
        roll_payload = {
            "RequestID": "#loot;Valeros;;r42",
            "Origin": "Valeros",
            "ToAll": True,
            "RollData": {"Result": 7},
        }
        reply = resolve_table_roll_reply(
            roll_payload,
            banks_by_tkey={"Valeros": self.bank},
        )
        self.assertIsNotNone(reply)
        assert reply is not None
        self.assertEqual(reply["text"], "rolled 7 on Pocket Loot: Silver ring")
        self.assertFalse(reply["markup"])

        # Replay rolls must not re-trigger table chat replies
        roll_payload["Replay"] = True
        self.assertIsNone(
            resolve_table_roll_reply(roll_payload, banks_by_tkey={"Valeros": self.bank})
        )


class TestColorBlocksStatsAndHistory(unittest.TestCase):
    """Tests for `parse_color_blocks`, `RollStatCollector`, and `ChatHistoryManager`."""

    def test_parse_color_blocks_auto_darkens_bg(self) -> None:
        blocks = parse_color_blocks("Fireball\u2261#ff0000\u2016DC 18\u2261#ffffff\u2261#000080")
        self.assertEqual(len(blocks), 2)
        self.assertEqual(blocks[0], ("Fireball", "#ff0000", "#660000"))
        self.assertEqual(blocks[1], ("DC 18", "#ffffff", "#000080"))
        rebuilt = build_color_box_title(blocks)
        self.assertIn("\u2016", rebuilt)

    def test_roll_stat_collector(self) -> None:
        collector = RollStatCollector()
        self.assertIsNone(
            collector.collect({"RequestID": "req1", "RollData": {"Result": 4, "MoreResults": True}})
        )
        self.assertIsNone(
            collector.collect({"RequestID": "req1", "RollData": {"Result": 6, "MoreResults": True}})
        )
        stats = collector.collect(
            {"RequestID": "req1", "RollData": {"Result": 6, "MoreResults": False}}
        )
        self.assertIsNotNone(stats)
        assert stats is not None
        self.assertIn("N=3", stats)
        self.assertIn("Md=6", stats)
        self.assertIn("Mo=6", stats)
        self.assertIn("\u03a3=16", stats)

    def test_chat_history_clearing_modes_and_pruning(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            log_file = Path(tmpdir) / "session.log"
            mgr = ChatHistoryManager(transcript_path=log_file)
            for mid in range(1, 6):
                mgr.add_chat_message(
                    {
                        "MessageID": mid,
                        "Origin": "GM",
                        "Text": f"Message {mid}",
                        "Pin": (mid == 2),
                    }
                )
            mgr.pin_message(4)

            self.assertEqual(len(mgr.pinned_entries()), 2)

            # Mode 1: Delete specific message IDs (unpinned message 1 is removed)
            mgr.clear_chat_history(target_messages=[1])
            ids = [e["MessageID"] for e in mgr.visible_entries()]
            self.assertNotIn(1, ids)

            # Mode 3: Negative target (-1 keeps last 1 message plus pinned messages 2 and 4)
            mgr.clear_chat_history(target=-1)
            ids_after_neg = [e["MessageID"] for e in mgr.visible_entries()]
            self.assertEqual(ids_after_neg, [2, 4, 5])

            # Y2 prune outside [3, 5] removes message 2
            mgr.prune_chat_history(min_id=3, max_id=5)
            ids_after_prune = [e["MessageID"] for e in mgr.visible_entries()]
            self.assertEqual(ids_after_prune, [4, 5])

            self.assertTrue(log_file.is_file())
            self.assertIn("Message 1", log_file.read_text(encoding="utf-8"))

    def test_chat_history_deduplication_and_last_message_id(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            log_file = Path(tmpdir) / "dedup.log"
            mgr = ChatHistoryManager(transcript_path=log_file)
            self.assertEqual(mgr.last_message_id(), 0)

            e1 = mgr.add_chat_message({"MessageID": 12, "Origin": "GM", "Text": "First"})
            e2 = mgr.add_roll_message(
                {"MessageID": 25, "Origin": "Ezren", "RollData": {"Title": "Init", "Result": 15}}
            )
            self.assertFalse(e1["_duplicate"])
            self.assertFalse(e2["_duplicate"])
            self.assertEqual(mgr.last_message_id(), 25)

            dup1 = mgr.add_chat_message({"MessageID": 12, "Origin": "GM", "Text": "First"})
            dup2 = mgr.add_roll_message(
                {"MessageID": 25, "Origin": "Ezren", "RollData": {"Title": "Init", "Result": 15}}
            )
            self.assertTrue(dup1["_duplicate"])
            self.assertTrue(dup2["_duplicate"])
            self.assertEqual(len(mgr.entries), 2)

            unnumbered = mgr.add_chat_message({"Origin": "System", "Text": "Notice"})
            self.assertFalse(unnumbered["_duplicate"])
            self.assertEqual(len(mgr.entries), 3)

            lines = log_file.read_text(encoding="utf-8").splitlines()
            self.assertEqual(len(lines), 3)

    def test_chat_and_roll_colors_and_rfc3339_timestamps(self) -> None:
        from gma_mapper.core.dice import get_component_style_dict
        from gma_mapper.core.profile import default_preferences

        prefs = default_preferences()
        light_norm = get_component_style_dict("normal", prefs=prefs)
        self.assertEqual(light_norm["fg"], "#1a1a1a")
        dark_norm = get_component_style_dict("normal", prefs=prefs, dark=True)
        self.assertEqual(dark_norm["fg"], "#e6edf3")

        # Legacy low-contrast saved title colors are normalized automatically
        legacy_prefs = default_preferences()
        legacy_prefs["styles"]["dierolls"]["components"]["title"]["fg"] = {
            "light": "#ffffff",
            "dark": "#aaaaaa",
        }
        legacy_prefs["styles"]["dierolls"]["components"]["title"]["bg"] = {
            "light": "#c7c0ae",
            "dark": "#000044",
        }
        norm_light_title = get_component_style_dict("title", prefs=legacy_prefs, dark=False)
        self.assertEqual(norm_light_title["fg"], "#1e293b")
        self.assertEqual(norm_light_title["bg"], "#dbe4f0")
        norm_dark_title = get_component_style_dict("title", prefs=legacy_prefs, dark=True)
        self.assertEqual(norm_dark_title["fg"], "#f0f6fc")
        self.assertEqual(norm_dark_title["bg"], "#1e3a5f")

        roll_html = render_roll_payload_html(
            {
                "Origin": "Valeros",
                "Sent": "2026-11-24T12:34:56.500Z",
                "RollData": {"Title": "Attack", "Result": 18},
            },
            prefs=prefs,
            dark=False,
        )
        self.assertIn("background-color:#dbe4f0", roll_html)
        self.assertIn("color:#52606d", roll_html)

        chat_light = render_chat_payload_html(
            {
                "MessageID": 5,
                "Origin": "GM",
                "Sent": "2026-11-24T12:34:56Z",
                "Text": "Welcome back",
            },
            prefs=prefs,
            dark=False,
            is_gm=True,
        )
        self.assertIn("color:#0052cc", chat_light)
        self.assertIn("color:#c92a2a", chat_light)
        self.assertIn("color:#52606d", chat_light)

        prefs_no_ts = default_preferences()
        prefs_no_ts["chat_timestamp"] = False
        chat_dark_no_ts = render_chat_payload_html(
            {
                "MessageID": 5,
                "Origin": "GM",
                "Sent": "2026-11-24T12:34:56Z",
                "Text": "Welcome back",
            },
            prefs=prefs_no_ts,
            dark=True,
            is_gm=True,
        )
        self.assertIn("color:#58a6ff", chat_dark_no_ts)
        self.assertIn("color:#ff6b6b", chat_dark_no_ts)
        self.assertNotIn("color:#94a3b8", chat_dark_no_ts)

    def test_html_renderers_and_table_sort(self) -> None:
        roll_html = render_roll_payload_html(
            {
                "Origin": "Kyra",
                "ToAll": True,
                "RollData": {
                    "Title": "Channel Energy\u2261gold",
                    "Result": 14,
                    "FullMax": True,
                    "Details": [
                        {"Type": "dice", "Value": "3d6=6,4,4"},
                        {"Type": "separator", "Value": ""},
                        {"Type": "label", "Value": "{healing\u2261green}"},
                    ],
                },
            }
        )
        self.assertIn("Kyra", roll_html)
        self.assertIn("14", roll_html)
        self.assertIn("Channel Energy", roll_html)

        # Verify wire-protocol ROLL payload structure (where Origin is a bool and Result is a dict)
        wire_roll_html = render_roll_payload_html(
            {
                "Sender": "Valeros",
                "Origin": True,
                "ToAll": True,
                "Title": "ReflexSave",
                "Result": {
                    "Details": [
                        {"Type": "result", "Value": "12"},
                        {"Type": "separator", "Value": "="},
                        {"Type": "diespec", "Value": "1d20"},
                        {"Type": "roll", "Value": "5"},
                        {"Type": "operator", "Value": "+"},
                        {"Type": "constant", "Value": "7"},
                    ],
                    "InvalidRequest": False,
                    "Result": 12,
                    "ResultSuppressed": False,
                },
            }
        )
        self.assertIn("Valeros", wire_roll_html)
        self.assertNotIn("True", wire_roll_html)
        self.assertNotIn("ResultSuppressed", wire_roll_html)
        self.assertIn(">12<", wire_roll_html)
        self.assertIn("ReflexSave", wire_roll_html)
        self.assertIn("1d20", wire_roll_html)
        self.assertIn("{5}", wire_roll_html)

        chat_html = render_chat_payload_html(
            {
                "MessageID": 10,
                "Origin": "GM",
                "Text": "**Initiative** time!",
                "Markup": True,
                "Pin": True,
            },
            is_pinned_view=True,
            is_gm=True,
        )
        self.assertIn("Initiative", chat_html)
        self.assertIn("del:10", chat_html)

        sorted_rows = validate_and_sort_table_rows([("15", "Mid"), ("*", "Max"), ("5", "Min")])
        self.assertEqual(sorted_rows, [("5", "Min"), ("15", "Mid"), ("*", "Max")])


@unittest.skipUnless(QT_AVAILABLE, "PySide6 required for UI panel and dialog tests")
class TestDicePanelAndControllerIntegration(unittest.TestCase):
    """Tests for `ChatDicePanel`, `MapperController`, and `EditDieRollPresetsDialog`."""

    def test_controller_dd_conn_roll_table_and_cc(self) -> None:
        ctrl = MapperController()
        ctrl.prefs["notify_peers"] = True

        # 1. CONN updates peer list and local identity
        ctrl.dispatch_command(
            "CONN",
            {
                "PeerList": [
                    {"User": "Ezren", "AKA": ["Ezren"], "IsMe": True},
                    {"User": "GM", "AKA": [], "IsMe": False},
                    {"User": "Kyra", "AKA": ["Kyra"], "IsMe": False},
                ]
            },
        )
        self.assertEqual(ctrl.chat_panel.local_user, "Ezren")
        self.assertEqual(ctrl.peer_names, ["GM", "Kyra"])

        # Subsequent CONN with new peer emits join notice
        ctrl.dispatch_command(
            "CONN",
            {
                "PeerList": [
                    {"User": "Ezren", "AKA": ["Ezren"], "IsMe": True},
                    {"User": "GM", "AKA": [], "IsMe": False},
                    {"User": "Kyra", "AKA": ["Kyra"], "IsMe": False},
                    {"User": "Merisiel", "AKA": [], "IsMe": False},
                ]
            },
        )
        self.assertIn("Merisiel", ctrl.peer_names)

        # 2. DD= with Delegates, DelegateFor, and a lookup table
        ctrl.dispatch_command(
            "DD=",
            {
                "Delegates": ["Kyra"],
                "DelegateFor": ["Valeros"],
                "Presets": [
                    {
                        "Name": "#001;m|wild_magic",
                        "Description": "Wild Surge",
                        "DieRollSpec": ";1d4;2;Sparks;*;**Boom**;",
                    },
                    {
                        "Name": "010\u25b6Spells|Magic Missile",
                        "Description": "Force bolts",
                        "DieRollSpec": "Magic Missile=3d4+3",
                    },
                ],
            },
        )
        self.assertEqual(ctrl.delegates, ["Kyra"])
        self.assertEqual(ctrl.delegate_for, ["Valeros"])
        self.assertEqual(len(ctrl.chat_panel.bank.tables), 1)
        self.assertEqual(len(ctrl.chat_panel.bank.rolls), 1)

        # 3. Triggering a table roll and receiving ROLL invokes table_reply_cb
        replies: list[dict[str, Any]] = []
        ctrl.table_reply_cb = replies.append
        ctrl.dispatch_command(
            "ROLL",
            {
                "RequestID": "#wild_magic;;m;r1",
                "Origin": "Ezren",
                "ToAll": True,
                "RollData": {"Result": 4},
            },
        )
        self.assertEqual(len(replies), 1)
        self.assertEqual(replies[0]["text"], "rolled 4 on Wild Surge: **Boom**")
        self.assertTrue(replies[0]["markup"])

    def test_dialogs_roundtrip_and_encoding(self) -> None:
        from gma_mapper.ui.dialogs.dice_dialogs import (
            EditColorBoxTitleDialog,
            EditDieRollPresetsDialog,
            EditLookupTableDialog,
            EditPresetGroupDialog,
            ManageDelegatesDialog,
        )

        # 1. EditColorBoxTitleDialog
        cb_dlg = EditColorBoxTitleDialog("Sneak Attack\u2261#ff0000=3d6")
        self.assertIn("Sneak Attack", cb_dlg.encoded_title())
        self.assertTrue(cb_dlg.updated_roll_spec("Sneak Attack=3d6").endswith("=3d6"))

        # 2. EditPresetGroupDialog
        grp_dlg = EditPresetGroupDialog(["Combat", "Melee"], [["Combat", "Ranged"]])
        self.assertEqual(grp_dlg.group_list(), ["Combat", "Melee"])

        # 3. EditLookupTableDialog
        tbl_dlg = EditLookupTableDialog("1d6", ["4", "Miss", "2", "Crit Miss", "*", "Hit"])
        self.assertEqual(tbl_dlg.dieroll(), "1d6")
        self.assertEqual(tbl_dlg.flat_table(), ["2", "Crit Miss", "4", "Miss", "*", "Hit"])

        # 4. EditDieRollPresetsDialog
        bank = DicePresetBank()
        bank.set_user_presets(
            [
                {"Name": "010|Attack", "Description": "Slash", "DieRollSpec": "1d20+5"},
                {"Name": "\u00a7020;pa;e|Power Attack", "Description": "PA", "DieRollSpec": "-2|+4"},
                {"Name": "#030;m|tbl1", "Description": "Table 1", "DieRollSpec": ";1d4;2;Low;*;High;"},
            ]
        )
        ed_dlg = EditDieRollPresetsDialog(bank=bank, system_mode=False)
        encoded_list = ed_dlg.encoded_presets()
        self.assertEqual(len(encoded_list), 3)

        # 5. ManageDelegatesDialog
        del_dlg = ManageDelegatesDialog(["Kyra"], ["Kyra", "Merisiel"])
        self.assertEqual(del_dlg.delegates(), ["Kyra"])

    def test_import_and_export_dice_file_into_panel(self) -> None:
        from gma_mapper.core.file_io import load_dice_presets_from_file, save_dice_presets_to_file
        from gma_mapper.ui.panels.chat_dice import ChatDicePanel

        sample_presets = [
            {
                "Name": "1-StaffDam",
                "Description": "StaffDam",
                "DieRollSpec": "StaffDam = 1d6",
            },
            {
                "Name": "0-WillSave",
                "Description": "WillSave",
                "DieRollSpec": "WillSave= d20 + 3",
            },
        ]
        with tempfile.TemporaryDirectory() as tmpdir:
            dice_file = Path(tmpdir) / "Viktor.dice"
            save_dice_presets_to_file(dice_file, sample_presets)
            _meta, loaded = load_dice_presets_from_file(dice_file)
            self.assertEqual(len(loaded), 2)

            panel = ChatDicePanel()
            panel.bank.set_user_presets(loaded)
            panel._rebuild_presets_ui()
            self.assertEqual(len(panel.bank.rolls), 2)
            self.assertEqual(panel.bank.rolls[0]["name"], "1-StaffDam")

    def test_editor_preserves_metadata_and_cancel_confirmation(self) -> None:
        from PySide6.QtWidgets import QMessageBox
        from gma_mapper.ui.dialogs.dice_dialogs import EditDieRollPresetsDialog

        bank = DicePresetBank()
        bank.set_user_presets(
            [
                {
                    "Name": "$[arena]005\u25b6Melee|Slash",
                    "Description": "Primary slash",
                    "DieRollSpec": "1d20+8",
                },
                {
                    "Name": "\u00a7015;pa;e;cmeta|Power Attack",
                    "Description": "Trade accuracy for damage",
                    "DieRollSpec": "-2|+4",
                },
                {
                    "Name": "#025;m;tmeta|tbl1",
                    "Description": "Table 1",
                    "DieRollSpec": ";1d4;2;Low;*;High;",
                },
            ]
        )
        ed_dlg = EditDieRollPresetsDialog(bank=bank, system_mode=False)
        encoded_before = ed_dlg.encoded_presets()
        self.assertEqual(encoded_before[0]["Name"], "$[arena]005\u25b6Melee|Slash")
        self.assertEqual(encoded_before[1]["Description"], "Trade accuracy for damage")
        self.assertEqual(encoded_before[1]["Name"], "\u00a7015;pa;e;cmeta|Power Attack")
        self.assertEqual(encoded_before[2]["Name"], "#025;m;tmeta|tbl1")

        # Auto-resequence keeps UserRole metadata (`area` / `client`) intact
        ed_dlg._auto_resequence(ed_dlg.rolls_table)
        ed_dlg._auto_resequence(ed_dlg.mods_table)
        ed_dlg._auto_resequence(ed_dlg.tables_table)
        reseq = ed_dlg.encoded_presets()
        self.assertEqual(reseq[0]["Name"], "$[arena]010\u25b6Melee|Slash")
        self.assertEqual(reseq[1]["Name"], "\u00a7010;pa;e;cmeta|Power Attack")
        self.assertEqual(reseq[2]["Name"], "#010;m;tmeta|tbl1")

        # Unmodified reject closes immediately without prompting
        clean_dlg = EditDieRollPresetsDialog(bank=bank, system_mode=False)
        with patch.object(QMessageBox, "question") as q_mock:
            clean_dlg.reject()
            q_mock.assert_not_called()

        # Modified reject prompts confirmation and respects Yes/No
        dirty_dlg = EditDieRollPresetsDialog(bank=bank, system_mode=False)
        dirty_dlg.rolls_table.item(0, 2).setText("Edited Slash")
        with patch.object(QMessageBox, "question", return_value=QMessageBox.StandardButton.No) as q_no:
            dirty_dlg.reject()
            q_no.assert_called_once()
        with patch.object(QMessageBox, "question", return_value=QMessageBox.StandardButton.Yes) as q_yes:
            dirty_dlg.reject()
            q_yes.assert_called_once()

    def test_quick_save_dialog_and_panel_workflows(self) -> None:
        from PySide6.QtWidgets import QDialogButtonBox, QMessageBox
        from gma_mapper.ui.dialogs.dice_dialogs import (
            EditDieRollPresetsDialog,
            QuickSavePresetDialog,
        )
        from gma_mapper.ui.panels.chat_dice import ChatDicePanel

        qs_dlg = QuickSavePresetDialog(initial_spec="Attack\u2261gold=1d20+5")
        qs_buttons = qs_dlg.findChild(QDialogButtonBox)
        self.assertIsNotNone(qs_buttons)
        self.assertEqual(
            qs_buttons.button(QDialogButtonBox.StandardButton.Save).text(),
            "Save to Server",
        )
        self.assertEqual(qs_dlg.name_edit.text(), "Attack")
        qs_dlg.group_edit.setText("Combat \u25b6 Melee")
        qs_dlg.seq_edit.setText("7")
        qs_dlg.desc_edit.setText("Sword swing")
        encoded = qs_dlg.encoded_preset()
        self.assertEqual(encoded["Name"], "007\u25b6Combat\u25b6Melee|Attack")
        self.assertEqual(encoded["Description"], "Sword swing")
        self.assertEqual(encoded["DieRollSpec"], "Attack\u2261gold=1d20+5")

        # Validation rejects empty name or spec
        invalid_dlg = QuickSavePresetDialog(initial_spec="1d20")
        self.assertEqual(invalid_dlg.name_edit.text(), "")
        with patch.object(QMessageBox, "warning") as warn_mock:
            invalid_dlg._on_accept()
            warn_mock.assert_called_once()
            invalid_dlg.name_edit.setText("Test")
            invalid_dlg.spec_edit.setText("")
            invalid_dlg._on_accept()
            self.assertEqual(warn_mock.call_count, 2)

        # Panel quick-save merges locally and emits DD+ and DR signals
        panel = ChatDicePanel(for_user="Valeros", local_user="Valeros")
        self.assertEqual(panel.btn_save_to_server.text(), "Save to Server")
        self.assertEqual(panel.btn_export_presets.text(), "Save to File...")
        self.assertEqual(panel.btn_import_presets.text(), "Import File...")
        self.assertEqual(panel.btn_refresh_presets.text(), "Reload from Server")
        self.assertEqual(panel.save_roll_preset_btn.text(), "Save Preset...")

        appended: list[tuple[list[dict[str, Any]], bool, str]] = []
        saved: list[tuple[list[dict[str, Any]], bool, str]] = []
        refreshed: list[str] = []
        panel.append_presets_requested.connect(lambda p, g, u: appended.append((p, g, u)))
        panel.save_presets_requested.connect(lambda p, g, u: saved.append((p, g, u)))
        panel.refresh_presets_requested.connect(refreshed.append)

        panel.save_single_preset(encoded)
        self.assertEqual(len(panel.bank.user_presets), 1)
        self.assertEqual(len(appended), 1)
        self.assertEqual(appended[0], ([encoded], False, "Valeros"))
        self.assertEqual(refreshed, ["Valeros"])

        panel.push_presets_to_server()
        self.assertEqual(len(saved), 1)
        self.assertEqual(saved[0], (panel.bank.user_presets, False, "Valeros"))

        ed_dlg = EditDieRollPresetsDialog(bank=panel.bank, system_mode=False)
        ed_buttons = ed_dlg.findChild(QDialogButtonBox)
        self.assertIsNotNone(ed_buttons)
        self.assertEqual(
            ed_buttons.button(QDialogButtonBox.StandardButton.Save).text(),
            "Save to Server",
        )

        # Non-GM guard blocks opening system preset editor
        with patch.object(QMessageBox, "warning") as warn_mock:
            panel.open_preset_editor(system_mode=True)
            warn_mock.assert_called_once()

        # File import with merge overwrites matching Name without duplicates
        from gma_mapper.core.file_io import save_dice_presets_to_file

        with tempfile.TemporaryDirectory() as tmpdir:
            dice_file = Path(tmpdir) / "merge.dice"
            save_dice_presets_to_file(
                dice_file,
                [
                    {
                        "Name": "007\u25b6Combat\u25b6Melee|Attack",
                        "Description": "Upgraded sword",
                        "DieRollSpec": "1d20+9",
                    },
                    {
                        "Name": "020|Fort",
                        "Description": "Fortitude save",
                        "DieRollSpec": "1d20+6",
                    },
                ],
            )
            merged = panel.import_presets_from_file(dice_file, merge=True)
            self.assertEqual(len(merged), 2)
            self.assertEqual(merged[0]["Description"], "Upgraded sword")
            self.assertEqual(len(saved), 2)
            self.assertEqual(len(saved[1][0]), 2)
            self.assertEqual(refreshed, ["Valeros", "Valeros"])

    def test_controller_denied_and_delegated_mixed_dd(self) -> None:
        ctrl = MapperController()
        statuses: list[str] = []
        ctrl.status_message_cb = statuses.append

        ctrl.dispatch_command("CONN", {"PeerList": [{"User": "Ezren", "IsMe": True}]})
        ctrl.dispatch_command("DENIED", {"Reason": "Only GM may edit system presets"})
        self.assertTrue(any("Permission denied" in s for s in statuses))

        ctrl.dispatch_command(
            "DD=",
            {
                "For": "Valeros",
                "Presets": [
                    {"Name": "001|SysRoll", "Description": "Sys", "DieRollSpec": "1d20", "Global": True},
                    {"Name": "010|UserRoll", "Description": "Usr", "DieRollSpec": "1d8", "Global": False},
                ],
            },
        )
        del_bank = ctrl.banks_by_tkey["Valeros"]
        self.assertEqual([p["Name"] for p in del_bank.system_presets], ["001|SysRoll"])
        self.assertEqual([p["Name"] for p in del_bank.user_presets], ["010|UserRoll"])

        ctrl.dispatch_command(
            "DD+",
            {
                "For": "Valeros",
                "Presets": [
                    {"Name": "010|UserRoll", "Description": "Usr2", "DieRollSpec": "1d10"},
                ],
            },
        )
        self.assertEqual(len(del_bank.user_presets), 1)
        self.assertEqual(del_bank.user_presets[0]["DieRollSpec"], "1d10")

    def test_protocol_define_dice_presets_wire_and_batch(self) -> None:
        from gma_mapper.net.client import ProtocolSession

        sent: list[str] = []
        session = ProtocolSession(send_line_cb=sent.append)
        session.reset_for_connection("localhost", 2323, "Valeros", "")
        session.is_connected = True
        session.pending_login = False

        preset_with_global = {
            "Name": "010|Attack",
            "Description": "Slash",
            "DieRollSpec": "1d20+5",
            "Global": False,
        }
        session.define_dice_presets([preset_with_global], append_mode=False, for_user="Valeros")
        self.assertEqual(len(sent), 1)
        self.assertTrue(sent[0].startswith("DD "))
        payload = json.loads(sent[0][3:])
        self.assertEqual(payload["For"], "Valeros")
        self.assertNotIn("Global", payload["Presets"][0])

        sent.clear()
        session.define_dice_presets([preset_with_global], append_mode=True, globals_only=True)
        self.assertEqual(len(sent), 1)
        self.assertTrue(sent[0].startswith("DD+ "))
        sys_payload = json.loads(sent[0][4:])
        self.assertTrue(sys_payload["Global"])
        self.assertNotIn("For", sys_payload)
        self.assertNotIn("Global", sys_payload["Presets"][0])

        # Large preset lists automatically split into BATCH packets
        sent.clear()
        big_presets = [
            {
                "Name": f"{i:03d}|Preset_{i}",
                "Description": "X" * 1000,
                "DieRollSpec": "1d20+5",
            }
            for i in range(75)
        ]
        session.define_dice_presets(big_presets, append_mode=False, for_user="Valeros")
        self.assertGreater(len(sent), 1)
        self.assertTrue(all(line.startswith("BATCH ") for line in sent))

    def test_panel_defaults_to_light_theme_dedup_and_rerender(self) -> None:
        from gma_mapper.ui.panels.chat_dice import ChatDicePanel

        panel = ChatDicePanel()
        self.assertFalse(panel.dark)
        self.assertIn("#f8f9fa", panel.chat_log.styleSheet())
        self.assertIn("#1a1a1a", panel.chat_log.styleSheet())
        self.assertIn("#0052cc", panel.chat_log.document().defaultStyleSheet())

        panel.append_chat({"MessageID": 7, "Origin": "GM", "Text": "Hello adventurers"})
        panel.append_chat({"MessageID": 7, "Origin": "GM", "Text": "Hello adventurers"})
        panel.append_roll(
            {"MessageID": 8, "Origin": "Ezren", "RollData": {"Title": "Arcana", "Result": 19}}
        )
        panel.append_roll(
            {"MessageID": 8, "Origin": "Ezren", "RollData": {"Title": "Arcana", "Result": 19}}
        )
        self.assertEqual(len(panel.history_manager.entries), 2)
        plain = panel.chat_log.toPlainText()
        self.assertEqual(plain.count("Hello adventurers"), 1)
        self.assertEqual(plain.count("Arcana"), 1)

        panel.set_theme(True)
        self.assertTrue(panel.dark)
        self.assertIn("#1b1f24", panel.chat_log.styleSheet())
        self.assertIn("#e6edf3", panel.chat_log.styleSheet())
        self.assertIn("#58a6ff", panel.chat_log.document().defaultStyleSheet())
        self.assertEqual(panel.chat_log.toPlainText().count("Hello adventurers"), 1)


if __name__ == "__main__":
    unittest.main()
