"""Unit tests for Phase 5: Clock/Calendar, Chat/Dice Formatter, Combat State, Audio, Controller, and CLI."""

from __future__ import annotations

import unittest
from pathlib import Path

from gma_mapper.__main__ import parse_cli_args, apply_cli_overrides
from gma_mapper.core.profile import default_preferences
from gma_mapper.ui.audio import AudioManager
from gma_mapper.ui.main_window import MapperController
from gma_mapper.ui.panels.chat_dice import format_roll_result, format_chat_message
from gma_mapper.ui.panels.clock import (
    GolarionCalendar,
    delta_string,
    nameplate_text,
    slot_status_summary,
    strip_nameplate_prefix,
)
from gma_mapper.ui.panels.combat import (
    CombatantState,
    apply_local_hp_adjustment,
    combatant_state_from_token_data,
    format_hp_summary,
)


class TestPanelsAndCLI(unittest.TestCase):
    def test_golarion_calendar_and_delta_string(self) -> None:
        cal = GolarionCalendar(absolute=0, relative=0)
        self.assertEqual(cal.year, 4700)
        self.assertEqual(cal.month_name, "Abadius")
        self.assertEqual(cal.day, 1)
        self.assertEqual(cal.day_name, "Starday")
        self.assertIn("00:00:00 Starday, 1st of Abadius, 4700 AR", cal.to_string())

        cal.advance_time(delta_seconds=0, delta_turns=3)
        self.assertEqual(cal.second, 18)
        self.assertEqual(delta_string(18), "18s (3r+0)")
        self.assertEqual(delta_string(90), "01:30 (15r+0)")
        self.assertEqual(delta_string(86400 + 3661), "1d 01:01:01")

    def test_nameplate_text(self) -> None:
        self.assertEqual(nameplate_text({"Name": "Valeros", "IsReady": True}), "\u23f2 Valeros")
        self.assertEqual(nameplate_text({"Name": "Ezren", "IsHold": True}), "\u23f8 Ezren")
        self.assertEqual(nameplate_text({"Name": "Merisiel", "FlatFooted": True}), "\u26a0 Merisiel")
        self.assertEqual(nameplate_text({"Name": "Kyra"}), "Kyra")

    def test_roll_and_chat_formatting(self) -> None:
        roll_payload = {
            "Origin": "Valeros",
            "Title": "**Longsword** Attack",
            "Results": [
                {
                    "Value": 24,
                    "Details": [
                        {"Type": "die", "Value": "[19]"},
                        {"Type": "constant", "Value": "+5"},
                    ],
                }
            ],
        }
        html_out = format_roll_result(roll_payload)
        self.assertIn("Valeros", html_out)
        self.assertIn("<b>Longsword</b> Attack", html_out)
        self.assertIn("24", html_out)

        chat_payload = {
            "Origin": "GM",
            "Targets": ["Valeros"],
            "Text": "Watch out for the //trap//!",
        }
        chat_html = format_chat_message(chat_payload)
        self.assertIn("&lt;GM&gt;", chat_html)
        self.assertIn("(to Valeros)", chat_html)
        self.assertIn("<i>trap</i>", chat_html)

    def test_combatant_state_and_audio(self) -> None:
        st = CombatantState(obj_id="c1", name="Goblin", max_hp=12, lethal_damage=5, temp_hp=3)
        self.assertEqual(st.current_hp, 7)
        self.assertEqual(format_hp_summary(st), "HP: 7/12 (+3 tmp)")

        audio = AudioManager(enabled=True, mute_level=0)
        # Verify cue files exist in lib/sounds/
        self.assertTrue(audio.cue_path(0).is_file())
        self.assertTrue(audio.play_ondeck(1))
        self.assertEqual(audio.last_played_cue, 1)

        # Muted when mute_level > cue level
        audio.mute_level = 2
        self.assertFalse(audio.play_ondeck(1))
        self.assertTrue(audio.play_ondeck(2))

    def test_controller_dispatch(self) -> None:
        ctrl = MapperController()
        ctrl.dispatch_command("AC", {"ID": "tok1", "Name": "Seoni", "GX": 2, "GY": 3, "MaxHP": 30, "LethalDamage": 4})
        self.assertIn("tok1", ctrl.scene.tokens)
        self.assertIn("tok1", ctrl.combat_panel.combatants)
        self.assertEqual(ctrl.combat_panel.combatants["tok1"].current_hp, 26)

        ctrl.dispatch_command("MV", {"ID": "tok1", "GX": 5, "GY": 6})
        self.assertEqual(ctrl.scene.tokens["tok1"].gx, 5.0)
        self.assertEqual(ctrl.scene.tokens["tok1"].gy, 6.0)

        ctrl.dispatch_command("CS", {"Absolute": 3600, "Relative": 60, "CombatMode": True})
        self.assertEqual(ctrl.calendar.hour, 1)
        self.assertTrue(ctrl.calendar.combat_mode)

    def test_cli_arg_parsing_with_wish_flags(self) -> None:
        opts = parse_cli_args([
            "-geometry", "1024x768+10+10",
            "--",
            "-h", "game.example.org",
            "-p", "2325",
            "-u", "merisiel",
            "--profile", "campaign1",
            "--dark",
        ])
        self.assertEqual(opts.geometry, "1024x768+10+10")
        self.assertEqual(opts.host, "game.example.org")
        self.assertEqual(opts.port, 2325)
        self.assertEqual(opts.user, "merisiel")
        self.assertEqual(opts.profile, "campaign1")
        self.assertTrue(opts.dark)

        prefs = default_preferences()
        apply_cli_overrides(prefs, opts)
        self.assertTrue(prefs["dark"])
        self.assertEqual(prefs["current_server"], "campaign1")

        # Verify --button-size supports small/medium/large/text
        opts_med = parse_cli_args(["--button-size", "medium"])
        prefs_med = default_preferences()
        apply_cli_overrides(prefs_med, opts_med)
        self.assertEqual(prefs_med["button_size"], "medium")
        self.assertFalse(prefs_med["toolbar_text"])

        opts_txt = parse_cli_args(["--button-size", "text"])
        prefs_txt = default_preferences()
        apply_cli_overrides(prefs_txt, opts_txt)
        self.assertTrue(prefs_txt["toolbar_text"])

    def test_toolbar_icons_and_display_mode_toggle(self) -> None:
        from gma_mapper.ui.icons import (
            HAS_PYSIDE6,
            TOOLBAR_BUTTON_ORDER,
            IconCatalog,
            button_pixel_size,
            button_size_suffix,
            dash_style_icon_name,
            mode_slot_specs,
            normalize_button_size,
            resolve_icon_path,
            stipple_icon_name,
        )
        from gma_mapper.ui.main_window import GMAMapperMainWindow

        self.assertEqual(normalize_button_size("small"), "small")
        self.assertEqual(normalize_button_size("medium"), "medium")
        self.assertEqual(normalize_button_size("large"), "large")
        self.assertEqual(normalize_button_size(30), "medium")
        self.assertEqual(normalize_button_size(40), "large")
        self.assertEqual(button_size_suffix("small"), "")
        self.assertEqual(button_size_suffix("medium"), "_30")
        self.assertEqual(button_size_suffix("large"), "_40")
        self.assertEqual(button_pixel_size("small"), 16)
        self.assertEqual(button_pixel_size("medium"), 30)
        self.assertEqual(button_pixel_size("large"), 40)

        # Light vs dark mode and size path resolution
        p_light = resolve_icon_path("line", button_size="small", dark_mode=False)
        p_dark = resolve_icon_path("line", button_size="small", dark_mode=True)
        p_large = resolve_icon_path("line", button_size="large", dark_mode=True)
        self.assertIsNotNone(p_light)
        self.assertIsNotNone(p_dark)
        self.assertIsNotNone(p_large)
        self.assertEqual(p_light.name, "line.gif")
        self.assertEqual(p_dark.name, "d_line.gif")
        self.assertEqual(p_large.name, "d_line_40.gif")

        self.assertEqual(dash_style_icon_name(""), "dash0")
        self.assertEqual(dash_style_icon_name("-."), "dash6424")
        self.assertEqual(stipple_icon_name(""), "stipple_100")
        self.assertEqual(stipple_icon_name("gray12"), "stipple_88")
        self.assertEqual(stipple_icon_name("gray75"), "stipple_25")

        m1, m2, m3 = mode_slot_specs("poly", draw_join="miter", draw_spline=3, draw_dash="-")
        self.assertEqual(m1[0], "join_miter")
        self.assertTrue(m1[3])
        self.assertEqual(m2[0], "spline_3")
        self.assertTrue(m2[3])
        self.assertEqual(m3[0], "dash64")
        self.assertTrue(m3[3])

        if not HAS_PYSIDE6:
            return
        from PySide6.QtCore import Qt

        cat = IconCatalog(button_size="medium", dark_mode=True)
        self.assertFalse(cat.icon("line").isNull())
        self.assertFalse(cat.color_swatch_icon("fill_color", "#ff0000").isNull())
        self.assertFalse(cat.app_window_icon().isNull())

        win = GMAMapperMainWindow(prefs=default_preferences())
        expected_keys = [k for k in TOOLBAR_BUTTON_ORDER if k != "|"]
        self.assertEqual(list(win.toolbar_actions.keys()), expected_keys)
        self.assertIn("#d9d9d9", win.tools_toolbar.styleSheet())
        self.assertFalse(win.icon_catalog.dark_mode)
        # Default mode is Icons (16x16 small)
        self.assertEqual(
            win.tools_toolbar.toolButtonStyle(),
            Qt.ToolButtonStyle.ToolButtonIconOnly,
        )
        self.assertEqual(win.tools_toolbar.iconSize().width(), 16)
        self.assertTrue(win.act_toolbar_icons.isChecked())

        # Toggle to Text labels mode
        win.set_toolbar_display_mode(use_icons=False)
        self.assertTrue(win.prefs["toolbar_text"])
        self.assertFalse(win.act_toolbar_icons.isChecked())
        self.assertEqual(
            win.tools_toolbar.toolButtonStyle(),
            Qt.ToolButtonStyle.ToolButtonTextOnly,
        )
        self.assertEqual(win.toolbar_actions["line"].iconText(), "Line")
        self.assertEqual(win.toolbar_actions["nil"].iconText(), "Play")

        # Toggle back to Icons mode with large button_size
        win.prefs["button_size"] = "large"
        win.set_toolbar_display_mode(use_icons=True)
        self.assertFalse(win.prefs["toolbar_text"])
        self.assertTrue(win.act_toolbar_icons.isChecked())
        self.assertEqual(
            win.tools_toolbar.toolButtonStyle(),
            Qt.ToolButtonStyle.ToolButtonIconOnly,
        )
        self.assertEqual(win.tools_toolbar.iconSize().width(), 40)

        # Verify dynamic mode slots update when switching tools and cycling options
        win.map_view.set_tool_mode("poly")
        self.assertTrue(win.act_mode1.isEnabled())
        self.assertTrue(win.act_mode2.isEnabled())
        self.assertTrue(win.act_mode3.isEnabled())
        self.assertEqual(win.act_mode1.iconText(), "Join:bevel")
        win._on_toolbar_mode1()
        self.assertEqual(win.act_mode1.iconText(), "Join:miter")
        win._on_toolbar_mode2()
        self.assertEqual(win.act_mode2.iconText(), "Spline:1")
        win._on_toolbar_mode3()
        self.assertEqual(win.act_mode3.iconText(), "Dash:-")

        # Verify stipple, snap, width cycling and SaF mode
        win._on_cycle_stipple()
        self.assertEqual(win.map_view.draw_stipple, "gray12")
        win._on_cycle_snap()
        self.assertEqual(win.map_view.obj_snap, 2)
        win._on_cycle_width()
        self.assertEqual(win.map_view.draw_width, 3)

        win._on_toggle_saf_mode(True)
        self.assertFalse(win.toolbar_actions["line"].isEnabled())
        self.assertTrue(win.act_saf_sync.isEnabled())
        win._on_toggle_saf_mode(False)
        self.assertTrue(win.toolbar_actions["line"].isEnabled())
        self.assertFalse(win.act_saf_sync.isEnabled())

    def test_initiative_and_combat_dock_interactivity(self) -> None:
        self.assertEqual(strip_nameplate_prefix("grp1_Goblin #1"), "Goblin #1")
        self.assertEqual(
            nameplate_text({"Name": "pc_Valeros", "HasReadiedAction": True}),
            "\u23f2 Valeros",
        )
        self.assertEqual(
            slot_status_summary({"Name": "Ezren", "CurrentHP": -3, "IsFlatFooted": True}),
            "\u271a Dying (-3 HP) | Flat-Footed",
        )

        # On-deck calculation & slot advancement
        cal = GolarionCalendar(combat_mode=True)
        cal.initiative_slots = [
            {"Slot": 22, "Name": "Goblin #1", "CurrentHP": 6},
            {"Slot": 18, "Name": "Valeros", "CurrentHP": 32},
            {"Slot": 12, "Name": "Seoni", "CurrentHP": 24},
        ]
        cal.select_actor_slot("Goblin #1")
        self.assertEqual(cal.current_slot, 0)
        self.assertEqual(cal.compute_ondeck_status(["Valeros"]), 1)  # ON DECK
        self.assertEqual(cal.compute_ondeck_status(["Seoni"]), 2)    # On deck in 1

        next_s = cal.advance_slot()
        self.assertEqual(next_s["Name"], "Valeros")
        self.assertEqual(cal.compute_ondeck_status(["Valeros"]), 0)  # YOUR TURN

        # Track health change on @Valeros
        self.assertTrue(cal.track_health_change("@Valeros", {"Health": {"IsFlatFooted": True, "MaxHP": 40, "LethalDamage": 10}}))
        self.assertTrue(cal.initiative_slots[1]["IsFlatFooted"])
        self.assertEqual(cal.initiative_slots[1]["CurrentHP"], 30)

        # Local HP adjustment with temporary HP absorption and full heal
        tok_data = {"ID": "t1", "Name": "Valeros", "Health": {"MaxHP": 40, "LethalDamage": 5, "NonLethalDamage": 2, "TmpHP": 8}}
        h1 = apply_local_hp_adjustment(tok_data, delta_lethal=10)
        # 8 absorbed by TmpHP, 2 added to LethalDamage (5 + 2 = 7)
        self.assertEqual(h1["TmpHP"], 0)
        self.assertEqual(h1["LethalDamage"], 7)

        h2 = apply_local_hp_adjustment({"Health": h1}, full_heal=True)
        self.assertEqual(h2["LethalDamage"], 0)
        self.assertEqual(h2["NonLethalDamage"], 0)

        # Controller dispatch for IL, I, OA+, OA-, PROGRESS (IsTimer=True), RM
        ctrl = MapperController()
        ctrl.dispatch_command("AKA", {"Names": ["Seoni"]})
        ctrl.dispatch_command("PS", {"ID": "m1", "Name": "Goblin #1", "Gx": 2.0, "Gy": 2.0, "CreatureType": 1, "Health": {"MaxHP": 10}})
        ctrl.dispatch_command("PS", {"ID": "p1", "Name": "Seoni", "Gx": 4.0, "Gy": 4.0, "CreatureType": 2, "Health": {"MaxHP": 30}})
        ctrl.dispatch_command("CO", {"Enabled": True})
        ctrl.dispatch_command("IL", {"InitiativeList": [
            {"Slot": 20, "Name": "Goblin #1", "CurrentHP": 10, "IsHolding": False, "HasReadiedAction": False, "IsFlatFooted": False},
            {"Slot": 15, "Name": "Seoni", "CurrentHP": 30, "IsHolding": False, "HasReadiedAction": False, "IsFlatFooted": False},
        ]})
        ctrl.dispatch_command("I", {"ActorID": "Goblin #1", "Rounds": 2})
        self.assertEqual(ctrl.calendar.ondeck_status, 1)

        ctrl.dispatch_command("OA+", {"ObjID": "p1", "AttrName": "StatusList", "Values": ["haste"]})
        self.assertIn("haste", ctrl.combat_panel.combatants["p1"].conditions)
        ctrl.dispatch_command("OA-", {"ObjID": "p1", "AttrName": "StatusList", "Values": ["haste"]})
        self.assertNotIn("haste", ctrl.combat_panel.combatants["p1"].conditions)

        ctrl.dispatch_command("PROGRESS", {
            "OperationID": "tm1",
            "Title": "Haste",
            "Value": 40,
            "MaxValue": 60,
            "IsDone": False,
            "IsTimer": True,
            "Targets": ["Seoni"],
        })
        self.assertIn("tm1", ctrl.clock_panel.timers)
        ctrl.dispatch_command("PROGRESS", {"OperationID": "tm1", "IsDone": True, "IsTimer": True})
        self.assertNotIn("tm1", ctrl.clock_panel.timers)

        ctrl.dispatch_command("RM", {"ObjID": "m1"})
        self.assertNotIn("m1", ctrl.combat_panel.combatants)


if __name__ == "__main__":
    unittest.main()
