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

from py_dieroller.local_roller import LocalDieRoller
from py_dieroller.map_service import format_chat_event_messages, format_roll_event_messages
from py_dieroller.models import (
    build_preset_roll_expression,
    expand_variables,
    format_applied_modifiers,
    match_modifier_to_preset,
    parse_gma_preset,
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
                self.assertEqual(win.notebook.count(), 7)
                self.assertEqual(
                    [win.notebook.tabText(i) for i in range(win.notebook.count())],
                    ["Modifiers", "Atk/Dmg", "Save", "Skill", "Other", "Variables", "History"],
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


if __name__ == "__main__":
    unittest.main()
