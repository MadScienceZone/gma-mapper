"""Unit tests for the standalone PySide6 die roller (``py_dieroller``)."""

from __future__ import annotations

import json
import os
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

from gma_mapper.core.dice import lookup_table_outcome
from py_dieroller.chat import render_chat_entry_html
from py_dieroller.local_roller import LocalDieRoller
from py_dieroller.map_service import format_chat_event_messages, format_roll_event_messages
from py_dieroller.models import (
    build_preset_roll_expression,
    compose_table_roll_expression,
    expand_variables,
    format_applied_modifiers,
    match_modifier_to_preset,
    normalize_table_dict,
    parse_gma_preset,
    parse_gma_table_preset,
    parse_table_invocation,
)
from py_dieroller.roll import format_cli_roll_output, load_dieroller_settings, parse_roll_args
from py_dieroller.settings import SettingsStore, render_messages_html, render_sample_preview_html

try:
    from PySide6.QtCore import Qt
    from PySide6.QtWidgets import QApplication

    QT_AVAILABLE = True
except ImportError:  # pragma: no cover
    QT_AVAILABLE = False


class TestPyDieRollerCore(unittest.TestCase):
    """Pure-Python tests for offline rolling, variable expansion, modifiers, settings, and CLI."""

    def test_local_die_roller_and_best_worst(self) -> None:
        roller = LocalDieRoller(rng=random.Random(42))
        label, res = roller.do_roll("Longsword = 1d20 + 7 {magic} | c19")
        self.assertEqual(label, "Longsword")
        total, details = res[0]
        self.assertGreaterEqual(total, 8)
        self.assertLessEqual(total, 27)
        tags = [t for t, _v in details]
        self.assertIn("diespec", tags)
        self.assertIn("roll", tags)
        self.assertIn("critspec", tags)

        _lbl, pct = roller.do_roll("2d6 best 1 + 1d%")
        pct_total, pct_details = pct[0]
        self.assertGreaterEqual(pct_total, 2)
        self.assertLessEqual(pct_total, 106)
        self.assertTrue(any(t == "diespec" and "d%" in v for t, v in pct_details))

    def test_expand_variables_nested_and_cycle_guard(self) -> None:
        defs = {"str": "4", "atk": "1d20+${str}", "loop_a": "${loop_b}", "loop_b": "${loop_a}"}
        out, err = expand_variables("Sword=${atk}+1", defs)
        self.assertIsNone(err)
        self.assertEqual(out, "Sword=1d20+4+1")

        out_missing, err_missing = expand_variables("1d20+${unknown}", defs)
        self.assertIsNone(err_missing)
        self.assertEqual(out_missing, "1d20+")

        _out_cyc, err_cyc = expand_variables("${loop_a}", defs)
        self.assertIsNotNone(err_cyc)
        assert err_cyc is not None
        self.assertIn("Circular", err_cyc)

    def test_modifier_matching_and_preset_expressions(self) -> None:
        pat = re.compile("sword", re.IGNORECASE)
        self.assertTrue(match_modifier_to_preset("atk/dmg", pat, "attack", "Longsword"))
        self.assertTrue(match_modifier_to_preset("atk/dmg", pat, "damage", "Shortsword"))
        self.assertFalse(match_modifier_to_preset("atk/dmg", pat, "save", "Sword Save"))
        self.assertFalse(match_modifier_to_preset("attack", pat, "damage", "Longsword"))

        mod_str = format_applied_modifiers([("2", "Flank"), ("-1", "Shaken")])
        self.assertEqual(mod_str, " +2 Flank -1 Shaken")

        expr = build_preset_roll_expression(
            ptype="attack",
            label="Longsword",
            expr="1d20+8",
            mod="+2 Flank",
            crit="19",
        )
        self.assertEqual(expr, "attack, Longsword = 1d20+8 +2 Flank | c19")

        gma_atk = parse_gma_preset(
            {"Name": "010|Rapier", "Description": "Rapier", "DieRollSpec": "1d20+6 | c18"}
        )
        self.assertEqual(gma_atk, {"ptype": "attack", "label": "Rapier", "expr": "1d20+6", "crit": "18"})
        gma_save = parse_gma_preset(
            {"Name": "020|Ref", "Description": "Reflex Save", "DieRollSpec": "1d20+4"}
        )
        self.assertEqual(gma_save["ptype"], "save")

        tbl_parsed = parse_gma_table_preset(
            {
                "Name": "#001;m|weather",
                "Description": "Weather Table",
                "DieRollSpec": ";1d6;3;Clear;*;**Storm**;",
            }
        )
        self.assertIsNotNone(tbl_parsed)
        assert tbl_parsed is not None
        self.assertEqual(tbl_parsed["name"], "weather")
        self.assertEqual(tbl_parsed["description"], "Weather Table")
        self.assertEqual(tbl_parsed["dieroll"], "1d6")
        self.assertTrue(tbl_parsed["markup"])
        self.assertEqual(tbl_parsed["pairs"], [("3", "Clear"), ("*", "**Storm**")])
        self.assertIsNone(parse_gma_table_preset(gma_save))

        inv = parse_table_invocation("Random Weather = ##weather +1 | repeat 2")
        self.assertEqual(
            inv,
            {
                "title": "Random Weather =",
                "is_global": True,
                "name": "weather",
                "rest": "+1 | repeat 2",
            },
        )
        self.assertEqual(
            compose_table_roll_expression("Loot =", "1d20 | c20", "+2"),
            "Loot = 1d20 +2 | c20",
        )
        self.assertEqual(lookup_table_outcome(2, tbl_parsed["pairs"]), "Clear")
        self.assertEqual(lookup_table_outcome(6, tbl_parsed["pairs"]), "**Storm**")
        norm = normalize_table_dict({"name": "crit", "table": ["1", "Slip", "*", "Hit"]})
        self.assertEqual(norm["pairs"], [("1", "Slip"), ("*", "Hit")])

    def test_settings_store_roundtrip_and_chat_formatting(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            cfg = Path(tmpdir) / "settings.json"
            store = SettingsStore(filename=cfg)
            store.servers["Game"] = {
                "name": "Game",
                "hostname": "gma.example.org",
                "port": 2325,
                "username": "Ezren",
                "password": store.password_encode("secret-pw"),
            }
            store.set_last_server("Game")
            store.update_msgid(99, servername="Game")
            store.styles["user"] = {"tag": "user", "foreground": "#112233"}
            store.color_boxes = False
            self.assertTrue(store.save())

            reloaded = SettingsStore(filename=cfg)
            self.assertTrue(reloaded.load())
            self.assertEqual(reloaded.last_server(nameonly=True), "Game")
            self.assertEqual(reloaded.last_msgid(), 99)
            self.assertFalse(reloaded.allow_colorized_titles())
            srv = reloaded.server("Game")
            assert srv is not None
            self.assertEqual(reloaded.password_decode(srv["password"]), "secret-pw")

            html_preview = render_sample_preview_html(reloaded)
            self.assertIn("Alice:", html_preview)

            box_html = render_messages_html(
                [{"text": "Fire\u2261red\u2261yellow", "style": "rolllabel", "newline": True}],
                reloaded,
            )
            self.assertIn("background-color:", box_html)

            chat_segs = format_chat_event_messages(
                {"Sender": "GM", "Text": "Roll initiative", "ToAll": True}
            )
            self.assertEqual(chat_segs[0]["style"], "user")
            roll_segs = format_roll_event_messages(
                {
                    "Sender": "Valeros",
                    "Title": "Longsword",
                    "MessageID": 101,
                    "Result": {
                        "Details": [{"Type": "result", "Value": "18"}, {"Type": "roll", "Value": "13"}],
                        "MoreResults": True,
                    },
                }
            )
            self.assertTrue(any("\u231b" in s["text"] for s in roll_segs))

            pinned_html = render_chat_entry_html(
                {
                    "MessageID": 77,
                    "Sender": "GM",
                    "ToAll": True,
                    "Text": "**Important** rule",
                    "Pin": True,
                    "Markup": True,
                },
                reloaded,
                is_pinned_view=True,
                is_locally_pinned=False,
                is_gm=True,
            )
            self.assertIn("<b>Important</b>", pinned_html)
            self.assertIn('href="hide:77"', pinned_html)
            self.assertIn('href="del:77"', pinned_html)

    def test_roll_cli_parsing_and_settings_loading(self) -> None:
        args = parse_roll_args(["-b", "-H", "host.example", "-p", "2325", "-u", "Valeros", "1d20+5"])
        self.assertTrue(args.blind)
        self.assertEqual(args.hostname, "host.example")
        self.assertEqual(args.port, 2325)
        self.assertEqual(args.user, "Valeros")
        self.assertEqual(args.dieroll, ["1d20+5"])

        out = format_cli_roll_output(
            {
                "Sender": "Kyra",
                "Title": "Heal",
                "Result": {
                    "Details": [
                        {"Type": "result", "Value": "14"},
                        {"Type": "separator", "Value": "="},
                        {"Type": "diespec", "Value": "2d8"},
                        {"Type": "roll", "Value": "6,8"},
                    ]
                },
            }
        )
        self.assertEqual(out, "Kyra: Heal 14 = 2d8 (6,8)")

        with tempfile.TemporaryDirectory() as tmpdir:
            sfile = Path(tmpdir) / "settings.json"
            sfile.write_text(json.dumps({"default_server": "s1"}), encoding="utf-8")
            loaded = load_dieroller_settings(sfile)
            self.assertEqual(loaded["servers"], {})

    def test_bin_launcher_does_not_shadow_package(self) -> None:
        repo_root = Path(__file__).resolve().parent.parent
        proc = subprocess.run(
            [sys.executable, str(repo_root / "bin" / "py_dieroller.py"), "--help"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        self.assertIn("py-dieroller", proc.stdout)


@unittest.skipUnless(QT_AVAILABLE, "PySide6 required for py_dieroller UI tests")
class TestPyDieRollerUI(unittest.TestCase):
    """Headless Qt UI tests for ``DieRollerWindow``, ``SettingsDialog``, and ``MapService``."""

    def test_window_tabs_presets_modifiers_history_and_file_roundtrip(self) -> None:
        os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
        _app = QApplication.instance() or QApplication([])

        from py_dieroller.app import DieRollerWindow, L_HORIZONTAL, L_VERTICAL
        from py_dieroller.images import (
            CHAT_PNG,
            DICE_LARGE_PNG,
            DICE_LT_2_PNG,
            DICE_LT_PNG,
            DICE_PNG,
            HIDDEN_PNG,
            LOCK_PNG,
            load_qpixmap,
        )

        for png_data in (
            DICE_PNG,
            DICE_LT_PNG,
            DICE_LT_2_PNG,
            LOCK_PNG,
            HIDDEN_PNG,
            CHAT_PNG,
            DICE_LARGE_PNG,
        ):
            self.assertFalse(load_qpixmap(png_data).isNull())

        with tempfile.TemporaryDirectory() as tmpdir, mock.patch.object(
            Path, "home", return_value=Path(tmpdir)
        ):
            cfg = Path(tmpdir) / "settings.json"
            presets_path = Path(tmpdir) / "presets.json"
            win = DieRollerWindow(config_file=cfg)
            win2 = None
            try:
                self.assertEqual(win.notebook.count(), 8)
                self.assertEqual(
                    [win.notebook.tabText(i) for i in range(win.notebook.count())],
                    [
                        "Modifiers",
                        "Atk/Dmg",
                        "Save",
                        "Skill",
                        "Other",
                        "Tables",
                        "Variables",
                        "History",
                    ],
                )

                # Add variable, active atk/dmg modifier, and combat preset
                win.variable_append(name="str", val="4")
                win.modifier_append(
                    active=True,
                    source="Bless",
                    mtype="atk/dmg",
                    match="sword",
                    mod="+1",
                )
                pre = win.preset_append(
                    "pnCombat",
                    ptype="attack",
                    label="Longsword",
                    expr="1d20+${str}",
                    crit="19",
                )
                self.assertEqual(pre.value("mod"), "+1 Bless")
                self.assertEqual(
                    pre.roll_expression(),
                    "attack, Longsword = 1d20+${str} +1 Bless | c19",
                )

                # Offline preset roll expands ${str} and logs to History + Chat
                win._on_preset_roll("pnCombat", 0)
                self.assertEqual(len(win.history), 1)
                self.assertIn("Offline die roll:", win.chatwindow.messages.toPlainText())

                # Test layout & chat toggle
                win.on_layout_h()
                self.assertEqual(win.chat_layout, L_HORIZONTAL)
                self.assertEqual(win.split_win.orientation(), Qt.Orientation.Horizontal)
                win.on_layout_v()
                self.assertEqual(win.chat_layout, L_VERTICAL)
                win.act_view_chat.setChecked(False)
                self.assertTrue(win.chatwindow.isHidden())
                win.act_view_chat.setChecked(True)
                self.assertFalse(win.chatwindow.isHidden())

                # Save & reload presets JSON round-trip
                self.assertTrue(win.save_presets(filepath=presets_path))
                self.assertFalse(win.unsaved_changes)
                win2 = DieRollerWindow(config_file=cfg)
                self.assertTrue(win2.load_presets(filepath=presets_path))
                self.assertEqual(len(win2.presets["pnCombat"]), 1)
                self.assertEqual(len(win2.modifiers), 1)
                self.assertEqual(len(win2.variables), 1)
                self.assertEqual(win2.presets["pnCombat"][0].value("mod"), "+1 Bless")

                # Import a GMA .dice (v2) file
                dice_file = Path(tmpdir) / "sample.dice"
                dice_file.write_text(
                    "\n".join(
                        [
                            "__DICE__:2",
                            '\u00ab__META__\u00bb {"Comment": "test", "Timestamp": 0}',
                            (
                                '\u00abPRESET\u00bb {"Name": "Ref Save", '
                                '"Description": "Ref Save", "DieRollSpec": "1d20+6"}'
                            ),
                            "\u00ab__EOF__\u00bb",
                            "",
                        ]
                    ),
                    encoding="utf-8",
                )
                imported = win2.import_gma(filepath=dice_file)
                self.assertEqual(imported, 1)
                self.assertEqual(len(win2.presets["pnSave"]), 1)
                win2.clear_user_content_changed()
            finally:
                if win2 is not None:
                    win2.close()
                win.clear_user_content_changed()
                win.close()

    def test_settings_dialog_and_map_service_dispatch(self) -> None:
        os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
        _app = QApplication.instance() or QApplication([])

        from py_dieroller.app import DieRollerWindow
        from py_dieroller.settings import SettingsDialog

        with tempfile.TemporaryDirectory() as tmpdir, mock.patch.object(
            Path, "home", return_value=Path(tmpdir)
        ):
            cfg = Path(tmpdir) / "settings.json"
            win = DieRollerWindow(config_file=cfg)
            try:
                dlg = SettingsDialog(win.settings, win)
                self.assertTrue(
                    dlg.apply_server_entry("Local", "127.0.0.1", 2323, "Ezren", "pw")
                )
                self.assertTrue(dlg.set_style_color("user", "foreground", "#114488"))
                dlg.accept()
                self.assertIn("Local", win.settings.server_names())
                self.assertTrue(cfg.is_file())

                # Cancel reverts unsaved dialog changes
                dlg2 = SettingsDialog(win.settings, win)
                dlg2.apply_server_entry("Temp", "10.0.0.1", 2323)
                dlg2.reject()
                self.assertNotIn("Temp", win.settings.server_names())

                # MapService protocol dispatch updates peers, last_msgid, and chat log
                win.service.username = "Ezren"
                win.service.server = {"name": "Local"}
                win.service.dispatch_command(
                    "CONN",
                    {
                        "PeerList": [
                            {"User": "Ezren", "IsMe": True},
                            {"User": "GM", "IsMe": False},
                        ]
                    },
                )
                self.assertIn("GM", win.service.userlist)
                win.service.dispatch_command(
                    "TO",
                    {
                        "MessageID": 55,
                        "Sender": "GM",
                        "ToAll": True,
                        "Text": "Welcome!",
                    },
                )
                self.assertEqual(win.settings.last_msgid(servername="Local"), 55)
                self.assertIn("Welcome!", win.chatwindow.messages.toPlainText())
            finally:
                win.clear_user_content_changed()
                win.close()

    def test_pinned_chat_messages_pin_unpin_hide_clear_send_and_cc(self) -> None:
        os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
        _app = QApplication.instance() or QApplication([])

        from PySide6.QtCore import QUrl
        from py_dieroller.app import DieRollerWindow

        with tempfile.TemporaryDirectory() as tmpdir, mock.patch.object(
            Path, "home", return_value=Path(tmpdir)
        ):
            cfg = Path(tmpdir) / "settings.json"
            win = DieRollerWindow(config_file=cfg)
            try:
                chat = win.chatwindow
                self.assertTrue(chat.pinned_group.isHidden())

                sent_cmds: list[tuple[str, dict]] = []
                win.service.username = "Ezren"
                win.service.server = {"name": "Local"}
                win.service.client.session.is_connected = True
                win.service.client.session.pending_login = False
                win.service.client.session.send_command = (  # type: ignore[method-assign]
                    lambda cmd, payload=None: sent_cmds.append((cmd, payload or {}))
                )

                # 1. Server-pinned chat auto-shows Pinned Messages and deduplicates on replay
                win.service.dispatch_command(
                    "TO",
                    {
                        "MessageID": 10,
                        "Sender": "GM",
                        "ToAll": True,
                        "Text": "Stay on the bridge",
                        "Pin": True,
                    },
                )
                self.assertFalse(chat.pinned_group.isHidden())
                self.assertIn("Stay on the bridge", chat.pinned_messages.toPlainText())
                win.service.dispatch_command(
                    "TO",
                    {
                        "MessageID": 10,
                        "Sender": "GM",
                        "ToAll": True,
                        "Text": "Stay on the bridge",
                        "Pin": True,
                    },
                )
                self.assertEqual(chat.pinned_messages.toPlainText().count("Stay on the bridge"), 1)

                # 2. Local pin/unpin & View menu toggle
                win.service.dispatch_command(
                    "TO",
                    {"MessageID": 11, "Sender": "Ezren", "ToAll": True, "Text": "Torch active"},
                )
                chat._on_anchor_clicked(QUrl("pin:11"))
                self.assertIn("Torch active", chat.pinned_messages.toPlainText())
                self.assertIn("Stay on the bridge", chat.messages.toPlainText())

                win.act_view_pinned.setChecked(False)
                self.assertTrue(chat.pinned_group.isHidden())
                win.act_view_pinned.setChecked(True)
                self.assertFalse(chat.pinned_group.isHidden())

                # 3. Sending pinned + markup chat resets Pin toggle and transmits Pin=True, Markup=True
                chat.chattext.setPlainText("**Watch** out")
                chat.markup_btn.setChecked(True)
                chat.pin_btn.setChecked(True)
                chat.do_chat(pm=False)
                self.assertFalse(chat.pin_btn.isChecked())
                self.assertEqual(sent_cmds[-1][0], "TO")
                self.assertTrue(sent_cmds[-1][1]["Pin"])
                self.assertTrue(sent_cmds[-1][1]["Markup"])

                # 4. Clear Chat preserves pinned messages; Clear Pinned removes them
                win.act_clear_chat.trigger()
                self.assertIn("Stay on the bridge", chat.pinned_messages.toPlainText())
                self.assertIn("Torch active", chat.pinned_messages.toPlainText())

                # Unpin local 11, then test CC TargetMessages removal and Clear Pinned
                chat._on_anchor_clicked(QUrl("unpin:11"))
                self.assertNotIn("Torch active", chat.pinned_messages.toPlainText())

                win.service.dispatch_command("CC", {"DoSilently": True, "TargetMessages": [10]})
                self.assertTrue(chat.pinned_group.isHidden())

                # 5. GM delete anchor sends CC TargetMessages for that message ID
                win.service.username = "GM"
                win.service.dispatch_command(
                    "TO",
                    {"MessageID": 12, "Sender": "GM", "ToAll": True, "Text": "Temp pin", "Pin": True},
                )
                sent_cmds.clear()
                chat._on_anchor_clicked(QUrl("del:12"))
                self.assertEqual(sent_cmds, [("CC", {"DoSilently": True, "TargetMessages": [12]})])

                win.act_clear_pinned.trigger()
                self.assertTrue(chat.pinned_group.isHidden())
            finally:
                win.clear_user_content_changed()
                win.close()

    def test_lookup_tables_crud_import_persistence_offline_and_online(self) -> None:
        os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
        _app = QApplication.instance() or QApplication([])

        from py_dieroller.app import DieRollerWindow

        with tempfile.TemporaryDirectory() as tmpdir, mock.patch.object(
            Path, "home", return_value=Path(tmpdir)
        ):
            cfg = Path(tmpdir) / "settings.json"
            presets_path = Path(tmpdir) / "presets.json"
            win = DieRollerWindow(config_file=cfg)
            win2 = None
            try:
                # 1. Local table CRUD + deterministic offline lookup roll with inline markup
                trow = win.table_append(
                    name="loot",
                    description="Pocket Loot",
                    dieroll="1d1+4",
                    markup=True,
                    pairs=[("3", "Copper"), ("6", "**Silver**"), ("*", "Gold")],
                )
                self.assertEqual(trow.roll_expression(), "Pocket Loot = #loot")
                win._on_table_roll(0)
                log_html = win.chatwindow.messages.toHtml()
                log_text = win.chatwindow.messages.toPlainText()
                self.assertIn("Offline table lookup:", log_text)
                self.assertIn("rolled 5 on Pocket Loot: Silver", log_text)
                self.assertIn("font-weight:700", log_html)
                self.assertNotIn("**Silver**", log_text)

                # Insert & delete table rows
                extra_row = win.table_insert(0, name="tmp", dieroll="1d4")
                self.assertEqual(win.tables[0], extra_row)
                win.table_delete(0)
                self.assertEqual(len(win.tables), 1)

                # 2. Persist tables in presets.json and reload in a fresh window
                self.assertTrue(win.save_presets(filepath=presets_path))
                win2 = DieRollerWindow(config_file=cfg)
                self.assertTrue(win2.load_presets(filepath=presets_path))
                self.assertEqual(len(win2.tables), 1)
                self.assertEqual(win2.tables[0].value("name"), "loot")
                self.assertEqual(win2.tables[0].pairs, [("3", "Copper"), ("6", "**Silver**"), ("*", "Gold")])

                # 3. Import .dice (v2) file containing a #table preset
                dice_file = Path(tmpdir) / "tables.dice"
                dice_file.write_text(
                    "\n".join(
                        [
                            "__DICE__:2",
                            '\u00ab__META__\u00bb {"Comment": "tables", "Timestamp": 0}',
                            (
                                '\u00abPRESET\u00bb {"Name": "#002;m|crit", '
                                '"Description": "Crit Effects", '
                                '"DieRollSpec": ";1d20;10;Staggered;*;**Stunned**;"}'
                            ),
                            "\u00ab__EOF__\u00bb",
                            "",
                        ]
                    ),
                    encoding="utf-8",
                )
                imported = win2.import_gma(filepath=dice_file)
                self.assertEqual(imported, 1)
                self.assertEqual(len(win2.tables), 2)
                self.assertEqual(win2.tables[1].value("name"), "crit")
                self.assertTrue(win2.tables[1].is_markup())

                # 4. Online server ##global table sync (DD=), D request with RequestID, and ROLL->TO
                sent_cmds: list[tuple[str, dict]] = []
                win2.service.username = "Ezren"
                win2.service.server = {"name": "Local"}
                win2.service.client.session.is_connected = True
                win2.service.client.session.pending_login = False
                win2.service.client.session.send_command = (  # type: ignore[method-assign]
                    lambda cmd, payload=None: sent_cmds.append((cmd, payload or {}))
                )
                win2.service.dispatch_command(
                    "DD=",
                    {
                        "Global": True,
                        "Presets": [
                            {
                                "Name": "#001;m|weather",
                                "Description": "Weather Table",
                                "DieRollSpec": ";1d6;3;Clear skies;*;**Thunderstorm**;",
                                "Global": True,
                            }
                        ],
                    },
                )
                win2.chatwindow.roll_dice("##weather +1")
                self.assertEqual(sent_cmds[-1][0], "D")
                d_payload = sent_cmds[-1][1]
                self.assertEqual(d_payload["RollSpec"], "1d6 +1")
                self.assertEqual(d_payload["RequestID"], "##weather;Ezren;m;r1")

                sent_cmds.clear()
                win2.service.dispatch_command(
                    "ROLL",
                    {
                        "RequestID": "##weather;Ezren;m;r1",
                        "Sender": "Ezren",
                        "Origin": True,
                        "ToAll": True,
                        "Result": {"Result": 5, "Details": [{"Type": "result", "Value": "5"}]},
                    },
                )
                self.assertEqual(len(sent_cmds), 1)
                self.assertEqual(sent_cmds[0][0], "TO")
                self.assertEqual(
                    sent_cmds[0][1]["Text"],
                    "rolled 5 on Weather Table: **Thunderstorm**",
                )
                self.assertTrue(sent_cmds[0][1]["Markup"])
                self.assertTrue(sent_cmds[0][1]["ToAll"])
            finally:
                if win2 is not None:
                    win2.clear_user_content_changed()
                    win2.close()
                win.clear_user_content_changed()
                win.close()


if __name__ == "__main__":
    unittest.main()
