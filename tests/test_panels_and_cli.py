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

        # Legacy -S / --select / -select and -L / --list-profiles flags
        self.assertEqual(parse_cli_args(["--select", "Liberte"]).profile, "Liberte")
        self.assertEqual(parse_cli_args(["-S", "Liberte"]).profile, "Liberte")
        self.assertEqual(parse_cli_args(["-select", "Liberte"]).profile, "Liberte")
        self.assertTrue(parse_cli_args(["--list-profiles"]).list_profiles)
        self.assertTrue(parse_cli_args(["-L"]).list_profiles)

        import contextlib
        import io
        import tempfile
        from gma_mapper.__main__ import main as cli_main
        from gma_mapper.core.profile import save as save_preferences

        with tempfile.TemporaryDirectory() as tmpdir:
            cfg_path = Path(tmpdir) / "prefs.json"
            cfg_prefs = default_preferences()
            cfg_prefs["profiles"] = [
                {"name": "offline", "host": "", "port": 2323},
                {"name": "Liberte", "host": "liberte.example.org", "port": 2325},
            ]
            save_preferences(cfg_path, cfg_prefs)
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = cli_main(["--list-profiles", "-f", str(cfg_path)])
            self.assertEqual(rc, 0)
            self.assertEqual(buf.getvalue().splitlines(), ["offline", "Liberte"])

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

    def test_map_save_load_merge_unload_and_server_l(self) -> None:
        import tempfile

        src_ctrl = MapperController()
        src_ctrl.scene.add_or_update_element(
            "rect1",
            "LS-RECT",
            {
                "ID": "rect1",
                "Points": [{"X": 100.0, "Y": 100.0}, {"X": 200.0, "Y": 200.0}],
                "Color": "#ff0000",
                "Fill": "#00ff00",
                "_spread": True,
            },
        )
        src_ctrl.scene.add_or_update_element(
            "circ1",
            "LS-CIRC",
            {
                "ID": "circ1",
                "Points": [{"X": 300.0, "Y": 300.0}, {"X": 350.0, "Y": 350.0}],
                "Color": "#0000ff",
            },
        )
        src_ctrl.scene.add_or_update_token(
            "tok1",
            {
                "ID": "tok1",
                "Name": "Goblin Scout",
                "Gx": 3.0,
                "Gy": 4.0,
                "CreatureType": 2,
                "Health": {"MaxHP": 12},
            },
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            map_path = Path(tmpdir) / "roundtrip.map"
            count = src_ctrl.save_map_file(map_path)
            self.assertEqual(count, 3)
            raw_text = map_path.read_text(encoding="utf-8")
            self.assertNotIn("_spread", raw_text)

            # Load into a fresh controller (merge=False clears existing objects)
            dst_ctrl = MapperController()
            dst_ctrl.scene.add_or_update_element(
                "old_line",
                "LS-LINE",
                {"ID": "old_line", "Points": [{"X": 0.0, "Y": 0.0}, {"X": 50.0, "Y": 50.0}]},
            )
            dst_ctrl.apply_loaded_map_file(map_path, merge=False)
            self.assertNotIn("old_line", dst_ctrl.scene.elements)
            self.assertIn("rect1", dst_ctrl.scene.elements)
            self.assertIn("circ1", dst_ctrl.scene.elements)
            self.assertEqual(dst_ctrl.scene.elements["rect1"].gma_type, "RECT")
            self.assertEqual(dst_ctrl.scene.elements["circ1"].gma_type, "CIRC")
            self.assertIn("tok1", dst_ctrl.scene.tokens)
            self.assertEqual(dst_ctrl.scene.tokens["tok1"].data.get("Name"), "Goblin Scout")
            self.assertIn("tok1", dst_ctrl.combat_panel.combatants)

            # Merge=True preserves existing objects
            dst_ctrl.scene.add_or_update_element(
                "keep_line",
                "LS-LINE",
                {"ID": "keep_line", "Points": [{"X": 10.0, "Y": 10.0}, {"X": 60.0, "Y": 60.0}]},
            )
            dst_ctrl.apply_loaded_map_file(map_path, merge=True)
            self.assertIn("keep_line", dst_ctrl.scene.elements)
            self.assertIn("rect1", dst_ctrl.scene.elements)

            # Unload removes only objects from map_path
            removed = dst_ctrl.unload_map_file(map_path)
            self.assertEqual(set(removed), {"rect1", "circ1", "tok1"})
            self.assertIn("keep_line", dst_ctrl.scene.elements)
            self.assertNotIn("rect1", dst_ctrl.scene.elements)
            self.assertNotIn("tok1", dst_ctrl.scene.tokens)
            self.assertNotIn("tok1", dst_ctrl.combat_panel.combatants)

            # Server L command dispatch (synchronous fallback when async_fetch_map_cb is None)
            srv_ctrl = MapperController()
            srv_ctrl.server_settings["ImageBaseURL"] = "http://example.invalid/maps"
            srv_ctrl.cache.fetch_map_file = lambda _fid: map_path  # type: ignore[method-assign]
            srv_ctrl.dispatch_command(
                "L", {"File": "testmap", "Merge": False, "CacheOnly": False}
            )
            self.assertIn("rect1", srv_ctrl.scene.elements)
            self.assertEqual(srv_ctrl.scene.elements["rect1"].gma_type, "RECT")
            self.assertIn("tok1", srv_ctrl.scene.tokens)

    def test_battle_map_view_adjust_view_top_left(self) -> None:
        import os

        os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
        try:
            from PySide6.QtWidgets import QApplication
            from gma_mapper.ui.canvas.scene import BattleMapScene
            from gma_mapper.ui.canvas.view import BattleMapView
        except ImportError:
            self.skipTest("PySide6 not available")

        _app = QApplication.instance() or QApplication([])
        scene = BattleMapScene()
        view = BattleMapView(scene)
        view.resize(800, 600)

        view.adjust_view("C12", 0.0, 0.0)
        self.assertEqual(view.top_left_grid_label(), "C12")

        # Fraction fallback (empty grid label) aligns top-left to (xview, yview) of sceneRect
        sr = scene.sceneRect()
        target_sx = 4 * 50.0  # Column E (gx=4)
        target_sy = 6 * 50.0  # Row 7 (gy=6)
        xv = (target_sx - sr.left()) / sr.width()
        yv = (target_sy - sr.top()) / sr.height()
        view.adjust_view("", xv, yv)
        self.assertEqual(view.top_left_grid_label(), "E7")

    def test_player_clock_window_helpers_and_role_behavior(self) -> None:
        from gma_mapper.ui.panels.clock import (
            GolarionCalendar,
            compute_visible_initiative_slots,
            format_gmaclock_date,
            format_gmaclock_delta,
            resolve_slot_visual_state,
        )

        cal = GolarionCalendar(absolute=3661, relative=12, combat_mode=True)
        self.assertEqual(format_gmaclock_date(cal), "01-ABA-4700 01:01:01.0")
        self.assertEqual(format_gmaclock_delta(12), "+00:12.0  2.0r")
        self.assertEqual(format_gmaclock_delta(3660), "+01:01:00.0 610.0r")

        slots = [
            {"Slot": 1, "Name": "mob_Goblin #1", "CurrentHP": 8, "IsFlatFooted": False},
            {"Slot": 2, "Name": "Valeros", "CurrentHP": 32, "IsHolding": True, "HasReadiedAction": False},
            {"Slot": 3, "Name": "Seoni", "CurrentHP": 0, "IsHolding": True, "HasReadiedAction": True},
            {"Slot": 4, "Name": "Kyra", "CurrentHP": -3, "IsFlatFooted": False},
            {"Slot": 5, "Name": "Merisiel", "CurrentHP": 20, "IsFlatFooted": True},
        ]

        # When limit < len(slots) and active slot is at the end of the round, window wraps and inserts NEXT ROUND
        visible = compute_visible_initiative_slots(slots, current_slot=4, limit=4, active_actor="Merisiel")
        seps = [e for e in visible if e.get("is_separator")]
        self.assertEqual(len(seps), 1)
        self.assertEqual(seps[0]["label"], "NEXT ROUND")
        names = [e["slot"]["Name"] for e in visible if not e.get("is_separator")]
        self.assertEqual(names, ["Seoni", "Kyra", "Merisiel", "mob_Goblin #1"])

        # Visual state checks (public nameplate only, no raw HP numbers, legacy icons + 4px borders)
        vis_active = resolve_slot_visual_state(slots[0], is_current=True)
        self.assertEqual(vis_active.display_name, "Goblin #1")
        self.assertEqual(vis_active.icon_name, "bullet_go")
        self.assertEqual(vis_active.border_width, 0)

        vis_hold = resolve_slot_visual_state(slots[1], is_current=False)
        self.assertEqual(vis_hold.icon_name, "hourglass")

        vis_ready_zero = resolve_slot_visual_state(slots[2], is_current=False)
        self.assertEqual(vis_ready_zero.icon_name, "hourglass_go")
        self.assertEqual(vis_ready_zero.border_width, 4)

        vis_dying = resolve_slot_visual_state(slots[3], is_current=False)
        self.assertEqual(vis_dying.icon_name, "cross")
        self.assertEqual(vis_dying.border_width, 4)

        vis_ff = resolve_slot_visual_state(slots[4], is_current=False)
        self.assertEqual(vis_ff.icon_name, "blank")
        self.assertEqual(vis_ff.border_width, 4)

        import os

        os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
        try:
            from PySide6.QtWidgets import QApplication, QLabel, QPushButton
            from gma_mapper.ui.main_window import GMAMapperMainWindow
            from gma_mapper.ui.panels.clock import PlayerClockWindow
        except ImportError:
            self.skipTest("PySide6 not available")

        _app = QApplication.instance() or QApplication([])
        win = GMAMapperMainWindow()
        try:
            # Non-GM by default: GM clock_dock is hidden, toolbar Clock action opens PlayerClockWindow
            self.assertFalse(win.controller.chat_panel.is_gm)
            self.assertTrue(win.clock_dock.isHidden())
            self.assertIsNone(win.controller.player_clock_window)

            win._on_toggle_clock_dock()
            pwin = win.controller.player_clock_window
            self.assertIsInstance(pwin, PlayerClockWindow)
            assert pwin is not None
            self.assertEqual(pwin.windowTitle(), "Game Clock")
            # Player clock window is read-only: no GM control buttons
            self.assertEqual(pwin.findChildren(QPushButton), [])

            # Live sync on CS, CO, IL, I, OA, PROGRESS (IsTimer=True)
            win.controller.dispatch_command("CS", {"Absolute": 3661, "Relative": 12, "Running": False})
            self.assertEqual(pwin.timedisp_label.text(), "01-ABA-4700 01:01:01.0")
            self.assertEqual(pwin.turndisp_label.text(), "")

            win.controller.dispatch_command("CO", {"Enabled": True})
            win.controller.dispatch_command("IL", {"InitiativeList": slots})
            win.controller.dispatch_command("I", {"ActorID": "Valeros", "Slot": 1, "Rounds": 2})
            self.assertEqual(pwin.turndisp_label.text(), "+00:12.0  2.0r")

            slot_texts = [lbl.text() for lbl in pwin.slots_container.findChildren(QLabel) if lbl.text()]
            self.assertIn("Goblin #1", slot_texts)
            self.assertIn("Valeros", slot_texts)
            # Raw HP numbers must not be exposed in player clock slot labels
            self.assertFalse(any("HP" in t or "32" in t for t in slot_texts))

            win.controller.dispatch_command(
                "PROGRESS",
                {"OperationID": "tm1", "Title": "Haste", "Value": 5, "MaxValue": 10, "IsTimer": True, "IsDone": False},
            )
            self.assertFalse(pwin.timers_group.isHidden())
            self.assertEqual(pwin.timers_layout.count(), 1)

            # Switching identity to GM via _on_login_successful (ProtocolSession.username) shows the GM clock_dock
            win.net_client.session.username = "GM"
            win._on_login_successful()
            self.assertTrue(win.controller.chat_panel.is_gm)
            self.assertFalse(win.clock_dock.isHidden())
            # Toolbar Clock icon toggles GM clock_dock visibility when GM
            win.act_open_clock_dock.trigger()
            self.assertTrue(win.clock_dock.isHidden())
            win.act_open_clock_dock.trigger()
            self.assertFalse(win.clock_dock.isHidden())
            # Toolbar Chat icon toggles chat_dock visibility
            chat_was_hidden = win.chat_dock.isHidden()
            win.act_open_chat_dock.trigger()
            self.assertEqual(win.chat_dock.isHidden(), not chat_was_hidden)
            win.act_open_chat_dock.trigger()
            self.assertEqual(win.chat_dock.isHidden(), chat_was_hidden)
            # Switching back to non-GM via GRANTED hides the GM clock_dock, and toolbar Clock icon toggles PlayerClockWindow
            win.controller.dispatch_command("GRANTED", {"User": "Valeros"})
            self.assertFalse(win.controller.chat_panel.is_gm)
            self.assertTrue(win.clock_dock.isHidden())
            self.assertFalse(pwin.isHidden())
            win.act_open_clock_dock.trigger()
            self.assertTrue(pwin.isHidden())
            win.act_open_clock_dock.trigger()
            self.assertFalse(pwin.isHidden())
        finally:
            if win.controller.player_clock_window is not None:
                win.controller.player_clock_window.close()
            win.close()

    def test_select_aka_dialog_and_protocol_flow(self) -> None:
        import json
        import os

        from gma_mapper.net.client import ProtocolSession
        from gma_mapper.ui.dialogs.aka_dialog import SelectAKADialog, parse_custom_aka_names

        # 1. Pure-Python custom name parser
        self.assertEqual(
            parse_custom_aka_names("Sir Robin, Valeros, , Sir Robin, Ezren "),
            ["Sir Robin", "Valeros", "Ezren"],
        )

        # 2. ProtocolSession.aka() wire output
        sent: list[str] = []
        session = ProtocolSession(send_line_cb=sent.append)
        session.reset_for_connection("localhost", 2323, "alice", "")
        session.is_connected = True
        session.pending_login = False
        session.aka(["Valeros", "Sir Robin"], not_playing=False)
        self.assertEqual(len(sent), 1)
        self.assertTrue(sent[0].startswith("AKA "))
        self.assertEqual(json.loads(sent[0][4:]), {"Names": ["Valeros", "Sir Robin"]})
        sent.clear()
        session.aka([], not_playing=True)
        self.assertEqual(json.loads(sent[0][4:]), {"NotPlaying": True})

        # 3. MapperController AKA / CONN isolation, known_pc_names, NotPlaying, and should_prompt_aka
        ctrl = MapperController()
        ctrl.dispatch_command("CONN", {"PeerList": [{"User": "alice", "IsMe": True}]})
        self.assertTrue(ctrl.should_prompt_aka())

        ctrl.dispatch_command(
            "AC",
            {"ID": "P1", "Name": "Valeros", "CreatureType": 1, "GX": 1, "GY": 1},
        )
        ctrl.dispatch_command(
            "PS",
            {"ID": "M1", "Name": "Goblin", "CreatureType": 2, "GX": 3, "GY": 3},
        )
        ctrl.dispatch_command(
            "PS",
            {"ID": "P2", "Name": "Seoni", "CreatureType": 1, "GX": 2, "GY": 2},
        )
        self.assertEqual(ctrl.known_pc_names(), ["Seoni", "Valeros"])

        # Peer AKA must NOT overwrite local user's my_names
        ctrl.dispatch_command(
            "AKA",
            {"User": "bob", "Names": ["Seoni"], "NotPlaying": False},
        )
        self.assertEqual(ctrl.peer_aka["bob"], ["Seoni"])
        self.assertFalse(ctrl.peer_not_playing["bob"])
        self.assertEqual(ctrl.my_names, ["alice"])
        self.assertTrue(ctrl.should_prompt_aka())

        # Local AKA updates my_names & suppresses prompt
        ctrl.dispatch_command(
            "AKA",
            {"User": "alice", "Names": ["Valeros"], "NotPlaying": False},
        )
        self.assertEqual(ctrl.local_aka, ["Valeros"])
        self.assertEqual(ctrl.my_names, ["Valeros"])
        self.assertFalse(ctrl.should_prompt_aka())

        # NotPlaying clears my_names without falling back to all PCs or username
        ctrl.dispatch_command(
            "AKA",
            {"User": "alice", "Names": [], "NotPlaying": True},
        )
        self.assertTrue(ctrl.im_not_playing)
        self.assertEqual(ctrl.my_names, [])
        self.assertEqual(ctrl._target_context_snapshot()[0], [])
        ctrl._update_ondeck_and_audio()
        self.assertEqual(ctrl.clock_panel.my_names, [])
        self.assertFalse(ctrl.should_prompt_aka())

        # CONN populates local and peer AKA / NotPlaying accurately
        ctrl.dispatch_command(
            "CONN",
            {
                "PeerList": [
                    {"User": "alice", "AKA": ["Valeros"], "NotPlaying": False, "IsMe": True},
                    {"User": "bob", "AKA": ["Seoni"], "NotPlaying": False, "IsMe": False},
                    {"User": "obs", "AKA": ["Ghost"], "NotPlaying": True, "IsMe": False},
                ]
            },
        )
        self.assertEqual(ctrl.local_aka, ["Valeros"])
        self.assertFalse(ctrl.im_not_playing)
        self.assertEqual(ctrl.peer_aka["bob"], ["Seoni"])
        self.assertTrue(ctrl.peer_not_playing["obs"])
        self.assertNotIn("Ghost", ctrl.peer_names)

        # should_prompt_aka returns False for GM or matching PC name
        gm_ctrl = MapperController()
        gm_ctrl.dispatch_command("GRANTED", {"User": "GM"})
        self.assertFalse(gm_ctrl.should_prompt_aka())

        pc_ctrl = MapperController()
        pc_ctrl.dispatch_command("GRANTED", {"User": "Valeros"})
        pc_ctrl.dispatch_command("AC", {"ID": "P1", "Name": "Valeros", "CreatureType": 1})
        self.assertFalse(pc_ctrl.should_prompt_aka())

        # 4. Qt Dialog & GMAMapperMainWindow Play menu wiring
        os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
        try:
            from PySide6.QtWidgets import QApplication
            from gma_mapper.ui.main_window import GMAMapperMainWindow
        except ImportError:
            self.skipTest("PySide6 not available")

        _app = QApplication.instance() or QApplication([])
        dlg = SelectAKADialog(
            known_pcs=["Valeros", "Seoni"],
            current_aka=["Valeros", "Sir Robin"],
            local_user="alice",
            im_not_playing=False,
            show_suppress_option=True,
        )
        self.assertEqual(dlg.windowTitle(), "Who Are You?")
        self.assertTrue(dlg.pc_checkboxes["Valeros"].isChecked())
        self.assertFalse(dlg.pc_checkboxes["Seoni"].isChecked())
        self.assertEqual(dlg.custom_edit.text(), "Sir Robin")
        self.assertIsNotNone(dlg.suppress_chk)
        self.assertEqual(dlg.selected_names(), ["Valeros", "Sir Robin"])

        # Toggling NotPlaying disables PC checkboxes and custom input and clears selected_names
        dlg.not_playing_chk.setChecked(True)
        self.assertFalse(dlg.pc_checkboxes["Valeros"].isEnabled())
        self.assertFalse(dlg.custom_edit.isEnabled())
        self.assertTrue(dlg.not_playing())
        self.assertEqual(dlg.selected_names(), [])
        dlg.close()

        win = GMAMapperMainWindow()
        try:
            self.assertEqual(
                win.act_select_aka.text(),
                "Specify What &Character You're Playing...",
            )
            # Disconnected commit updates locally with notice
            win._commit_aka_selection(["Seoni"], not_playing=False)
            self.assertEqual(win.controller.local_aka, ["Seoni"])
            self.assertIn("updated locally", win.statusBar().currentMessage())

            # Connected commit transmits AKA over ProtocolSession
            win_sent: list[str] = []
            win.net_client.session.send_line_cb = win_sent.append
            win.net_client.session.reset_for_connection("localhost", 2323, "alice", "")
            win.net_client.session.is_connected = True
            win.net_client.session.pending_login = False
            win._commit_aka_selection(["Valeros", "Seoni"], not_playing=False)
            self.assertEqual(len(win_sent), 1)
            self.assertEqual(
                json.loads(win_sent[0][4:]),
                {"Names": ["Valeros", "Seoni"]},
            )
        finally:
            win.close()

    def test_tools_menu_cache_chat_ping_and_diagnostics(self) -> None:
        import json
        import os
        import tempfile
        import time

        from gma_mapper.core.dice import ChatHistoryManager
        from gma_mapper.ui.dialogs.ping_dialog import (
            compute_ping_metrics,
            parse_rfc3339_seconds,
        )

        # 1. Pure-Python RFC 3339 parser & ping metric calculations
        self.assertEqual(parse_rfc3339_seconds(""), 0.0)
        self.assertEqual(parse_rfc3339_seconds("0001-01-01T00:00:00Z"), 0.0)
        self.assertEqual(parse_rfc3339_seconds("not-a-timestamp"), 0.0)
        t_recd = parse_rfc3339_seconds("2026-11-22T20:00:00.100000000Z")
        t_sent = parse_rfc3339_seconds("2026-11-22T20:00:00.105000000Z")
        self.assertAlmostEqual((t_sent - t_recd) * 1000.0, 5.0, places=3)
        t_tz = parse_rfc3339_seconds("2026-11-22T12:00:00.250000-08:00")
        self.assertGreater(t_tz, 0.0)

        self.assertIsNone(compute_ping_metrics({"s": "other"}, 100_000))
        metrics = compute_ping_metrics(
            {
                "s": "__spt__",
                "i": 2,
                "o": {"origin": "1000000"},
                "ReceivedTime": "2026-11-22T20:00:00.100000Z",
                "SentTime": "2026-11-22T20:00:00.102500Z",
            },
            now_us=1_015_000,
        )
        assert metrics is not None
        slot_idx, in_transit_ms, in_server_ms, round_trip_ms = metrics
        self.assertEqual(slot_idx, 2)
        self.assertAlmostEqual(round_trip_ms, 15.0, places=3)
        self.assertAlmostEqual(in_server_ms, 2.5, places=3)
        self.assertAlmostEqual(in_transit_ms, 12.5, places=3)

        # 2. ChatHistoryManager.clear_pinned_messages
        hist = ChatHistoryManager()
        hist.add_chat_message({"MessageID": 1, "Sender": "Alice", "Text": "Local pin"})
        hist.add_chat_message({"MessageID": 2, "Sender": "GM", "Text": "Server pin", "Pin": True})
        hist.pin_message(1)
        self.assertEqual(len(hist.pinned_entries()), 2)
        self.assertEqual(hist.clear_pinned_messages(), 2)
        self.assertEqual(hist.pinned_entries(), [])
        self.assertNotIn(1, hist.pin_list)
        self.assertIn(2, hist.hide_list)

        # 3. Qt ServerPingDialog & GMAMapperMainWindow Tools menu integration
        os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
        try:
            from PySide6.QtWidgets import QApplication
            from gma_mapper.ui.dialogs.ping_dialog import ServerPingDialog
            from gma_mapper.ui.main_window import GMAMapperMainWindow
        except ImportError:
            self.skipTest("PySide6 not available")

        _app = QApplication.instance() or QApplication([])
        sent_pings: list[tuple[int, int]] = []
        ping_dlg = ServerPingDialog(
            send_ping_cb=lambda idx, ts: sent_pings.append((idx, ts)) or True,
            auto_start=False,
        )
        try:
            slot = ping_dlg.send_ping()
            self.assertEqual(slot, 0)
            self.assertEqual(len(sent_pings), 1)
            self.assertEqual(ping_dlg.table.item(0, 1).text(), "pending...")
            origin_us = sent_pings[0][1]
            ok = ping_dlg.handle_echo_reply(
                {
                    "s": "__spt__",
                    "i": 0,
                    "o": {"origin": str(origin_us)},
                    "ReceivedTime": "2026-11-22T20:00:00.000Z",
                    "SentTime": "2026-11-22T20:00:00.001Z",
                },
                now_us=origin_us + 8000,
            )
            self.assertTrue(ok)
            self.assertEqual(ping_dlg.table.item(0, 1).text(), "7.000ms")
            self.assertEqual(ping_dlg.table.item(0, 2).text(), "1.000ms")
            self.assertEqual(ping_dlg.table.item(0, 3).text(), "8.000ms")

            disc_dlg = ServerPingDialog(send_ping_cb=lambda _i, _t: False, auto_start=False)
            disc_dlg.send_ping()
            self.assertEqual(disc_dlg.table.item(0, 1).text(), "disconnected")
            disc_dlg.close()
        finally:
            ping_dlg.close()

        win = GMAMapperMainWindow()
        try:
            # Verify Tools menu & actions
            menu_titles = [act.text() for act in win.menuBar().actions()]
            self.assertIn("&Tools", menu_titles)
            self.assertEqual(win.reset_chat_menu.actions().__len__(), 4)
            self.assertEqual(win.act_check_updates.text(), "Check for &Updates...")
            self.assertEqual(win.act_clear_chat_history.text(), "Clear Chat &History")
            self.assertEqual(win.act_clear_pinned_chats.text(), "Clear &Pinned Chat Messages")
            self.assertEqual(win.act_clear_image_cache.text(), "Clear Image &Cache")
            self.assertEqual(win.act_clear_image_cache_60.text(), "Clear Image Cache (over &60 days)")
            self.assertEqual(win.act_update_image_cache.text(), "&Update Cached Images from Server")
            self.assertEqual(win.act_retry_failed_images.text(), "&Retry Failed Image Retrievals")
            self.assertEqual(win.act_server_ping_test.text(), "Test &Server Response Time...")
            self.assertEqual(win.act_save_diagnostics.text(), "Save &Diagnostic Messages As...")

            # Wire session capture
            win_sent: list[str] = []
            win.net_client.session.send_line_cb = win_sent.append
            win.net_client.session.reset_for_connection("localhost", 2323, "alice", "")
            win.net_client.session.is_connected = True
            win.net_client.session.pending_login = False

            # Chat clear & Reset Chat History (50 / all)
            win.controller.chat_panel.append_chat(
                {"MessageID": 10, "Sender": "alice", "Text": "Hello", "Pin": True}
            )
            win._on_reset_chat_history(-1)
            self.assertEqual(win_sent, [])
            self.assertEqual(len(win.controller.chat_panel.history_manager.pinned_entries()), 1)

            self.assertEqual(win._on_clear_pinned_chats(), 1)
            self.assertEqual(win.controller.chat_panel.history_manager.pinned_entries(), [])

            win._on_reset_chat_history(50)
            self.assertTrue(any(l == 'SYNC-CHAT {"Target":-50}' for l in win_sent))
            self.assertTrue(any(l.startswith("ECHO ") for l in win_sent))
            win_sent.clear()
            win._on_reset_chat_history(0)
            self.assertTrue(any(l == "SYNC-CHAT {}" for l in win_sent))
            win_sent.clear()

            # Image cache cleanup (0 & -update) + retry failed retrievals
            with tempfile.TemporaryDirectory() as tmpdir:
                win.cache.cache_dir = Path(tmpdir)
                cache_file = win.cache.cache_filename("orc", 1.0)
                cache_file.parent.mkdir(parents=True, exist_ok=True)
                cache_file.write_bytes(b"PNG")
                os.utime(cache_file, (time.time() - 60, time.time() - 60))

                deleted, total, requeried = win._on_cleanup_image_cache("-update")
                self.assertEqual((deleted, total, requeried), (1, 1, 1))
                self.assertFalse(cache_file.exists())
                self.assertTrue(any(l.startswith("AI? ") and '"orc"' in l for l in win_sent))
                win_sent.clear()

                cache_file2 = win.cache.cache_filename("goblin", 1.0)
                cache_file2.write_bytes(b"PNG")
                self.assertEqual(win._on_cleanup_image_cache(0), (1, 1, 0))
                self.assertFalse(cache_file2.exists())

            win.cache.forbidden_urls.add("https://example.com/bad.png")
            win.net_client.session.forbidden_urls.add("bad:1.00")
            self.assertEqual(win._on_retry_failed_images(), 2)
            self.assertEqual(win.cache.forbidden_urls, set())
            self.assertEqual(win.net_client.session.forbidden_urls, set())

            # Server Ping Test dialog + ECHO dispatch
            win_sent.clear()
            live_ping_dlg = win._on_server_ping_test()
            self.assertIs(win._ping_dialog, live_ping_dlg)
            echo_lines = [l for l in win_sent if l.startswith("ECHO ")]
            self.assertEqual(len(echo_lines), 1)
            echo_req = json.loads(echo_lines[0][5:])
            self.assertEqual(echo_req["s"], "__spt__")
            origin_val = int(echo_req["o"]["origin"])
            win.controller.dispatch_command(
                "ECHO",
                {
                    "s": "__spt__",
                    "i": 0,
                    "o": {"origin": str(origin_val)},
                    "ReceivedTime": "2026-11-22T20:00:00.000Z",
                    "SentTime": "2026-11-22T20:00:00.002Z",
                },
            )
            self.assertTrue(live_ping_dlg.table.item(0, 3).text().endswith("ms"))
            live_ping_dlg.close()
            self.assertIsNone(win._ping_dialog)

            # Diagnostic buffering & save to file
            win.controller.debug_level = 1
            win.controller.log_debug(0, "boom error")
            win.controller.log_debug(2, "filtered out")
            with tempfile.TemporaryDirectory() as tmpdir:
                diag_path = Path(tmpdir) / "diag.txt"
                count = win.save_diagnostics_to_file(diag_path)
                self.assertGreater(count, 0)
                text = diag_path.read_text(encoding="utf-8")
                self.assertIn("ERROR   |boom error", text)
                self.assertIn("PROTOCOL|-> AI?", text)
                self.assertNotIn("filtered out", text)
        finally:
            if win._ping_dialog is not None:
                win._ping_dialog.close()
            win.close()

    def test_view_menu_dock_toggles(self) -> None:
        import os

        os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
        try:
            from PySide6.QtGui import QKeySequence
            from PySide6.QtWidgets import QApplication
            from gma_mapper.ui.main_window import GMAMapperMainWindow
        except ImportError:
            self.skipTest("PySide6 not available")

        _app = QApplication.instance() or QApplication([])
        win = GMAMapperMainWindow()
        try:
            # Find &View menu and check dock toggleViewAction objects
            view_menus = [
                act.menu()
                for act in win.menuBar().actions()
                if act.text() == "&View" and act.menu() is not None
            ]
            self.assertEqual(len(view_menus), 1)
            view_actions = view_menus[0].actions()

            self.assertIs(win.act_view_chat_dock, win.chat_dock.toggleViewAction())
            self.assertIs(win.act_view_combat_dock, win.combat_dock.toggleViewAction())
            self.assertIs(win.act_view_clock_dock, win.clock_dock.toggleViewAction())
            self.assertIn(win.act_view_chat_dock, view_actions)
            self.assertIn(win.act_view_combat_dock, view_actions)
            self.assertIn(win.act_view_clock_dock, view_actions)

            # Shortcuts do not collide
            self.assertEqual(win.act_view_chat_dock.shortcut(), QKeySequence("Alt+D"))
            self.assertEqual(win.act_view_clock_dock.shortcut(), QKeySequence("Alt+Shift+C"))
            self.assertEqual(win.act_show_player_clock.shortcut(), QKeySequence("Alt+C"))

            # Toggling Chat and Combat dock actions hides and restores docks
            win.show()
            _app.processEvents()
            chat_visible = not win.chat_dock.isHidden()
            win.act_view_chat_dock.trigger()
            self.assertEqual(win.chat_dock.isHidden(), chat_visible)
            win.act_view_chat_dock.trigger()
            self.assertEqual(win.chat_dock.isHidden(), not chat_visible)

            combat_visible = not win.combat_dock.isHidden()
            win.act_view_combat_dock.trigger()
            self.assertEqual(win.combat_dock.isHidden(), combat_visible)
            win.act_view_combat_dock.trigger()
            self.assertEqual(win.combat_dock.isHidden(), not combat_visible)

            # Non-GM: clock dock toggle is hidden & disabled
            self.assertFalse(win.act_view_clock_dock.isVisible())
            self.assertFalse(win.act_view_clock_dock.isEnabled())

            # GM login enables & shows clock dock toggle and allows toggling clock_dock
            win.controller.dispatch_command("GRANTED", {"User": "GM"})
            self.assertTrue(win.act_view_clock_dock.isVisible())
            self.assertTrue(win.act_view_clock_dock.isEnabled())
            self.assertFalse(win.clock_dock.isHidden())
            win.act_view_clock_dock.trigger()
            self.assertTrue(win.clock_dock.isHidden())
            win.act_view_clock_dock.trigger()
            self.assertFalse(win.clock_dock.isHidden())
        finally:
            win.close()

    def test_profile_switcher_and_help_reference_dialogs(self) -> None:
        import os
        from unittest.mock import MagicMock

        from gma_mapper.core.minimarkup import MARKUP_SYNTAX_HELP_HTML
        from gma_mapper.net.client import ProtocolSession
        from gma_mapper.ui.dialogs.help_dialogs import format_about_mapper_info

        # 1. format_about_mapper_info across all 4 connection states
        msg_off, detail_off = format_about_mapper_info(None)
        self.assertIn("GMA VTT Mapper Client", msg_off)
        self.assertEqual(detail_off, "This mapper is running offline.")

        sess = ProtocolSession()
        sess.host = "gma.example.org"
        sess.port = 2325
        sess.username = "Valeros"
        _, detail_disc = format_about_mapper_info(sess)
        self.assertIn("has not yet connected", detail_disc)

        sess.is_connected = True
        sess.pending_login = True
        _, detail_neg = format_about_mapper_info(sess)
        self.assertIn("negotiating its connection", detail_neg)

        sess.pending_login = False
        sess.server_version = "5.31.0"
        sess.protocol = 428
        _, detail_ready = format_about_mapper_info(sess)
        self.assertIn("Connected to gma.example.org:2325 as Valeros", detail_ready)
        self.assertIn("5.31.0", detail_ready)

        # 2. Markup syntax reference content
        for token in ("**", "//", "==[", "[[", "12_1/2"):
            self.assertIn(token, MARKUP_SYNTAX_HELP_HTML)

        os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
        try:
            from PySide6.QtGui import QKeySequence
            from PySide6.QtWidgets import QApplication
            from gma_mapper.ui.dialogs.help_dialogs import (
                AboutMapperDialog,
                MarkupSyntaxHelpDialog,
            )
            from gma_mapper.ui.main_window import GMAMapperMainWindow
        except ImportError:
            self.skipTest("PySide6 not available")

        _app = QApplication.instance() or QApplication([])

        about_dlg = AboutMapperDialog(sess)
        self.assertEqual(about_dlg.windowTitle(), "About GMA Mapper")
        self.assertIn("Valeros", about_dlg.connection_label.text())
        about_dlg.close()

        markup_dlg = MarkupSyntaxHelpDialog()
        self.assertEqual(markup_dlg.windowTitle(), "Markup Syntax Information")
        self.assertIn("GMA Markup Syntax", markup_dlg.browser.toPlainText())
        markup_dlg.close()

        prefs = default_preferences()
        prefs["profiles"] = [
            {"name": "offline", "host": "", "port": 2323},
            {"name": "Home", "host": "home.example.org", "port": 2323, "username": "Alice", "password": "pw1"},
            {"name": "GameNight", "host": "game.example.org", "port": 2325, "username": "Bob", "password": "pw2"},
        ]
        prefs["current_profile"] = "Home"
        prefs["current_server"] = "Home"

        win = GMAMapperMainWindow(prefs=prefs)
        open_about = None
        open_markup = None
        try:
            # 3. Help menu shortcuts & actions
            self.assertEqual(win.act_about_mapper.shortcut(), QKeySequence("F1"))
            self.assertEqual(win.act_dice_syntax.shortcut(), QKeySequence("?"))
            self.assertEqual(win.act_markup_syntax.shortcut(), QKeySequence("Alt+?"))
            open_about = win._on_show_about_mapper()
            open_markup = win._on_show_markup_syntax_help()
            self.assertEqual(open_about.windowTitle(), "About GMA Mapper")
            self.assertEqual(open_markup.windowTitle(), "Markup Syntax Information")

            # 4. Quick Server Profile Switcher submenu & switching/reconnect/disconnect
            prof_texts = [a.text() for a in win.server_profile_menu.actions() if not a.isSeparator()]
            self.assertTrue(any("Home (home.example.org:2323)" in t for t in prof_texts))
            self.assertTrue(any("GameNight (game.example.org:2325)" in t for t in prof_texts))
            self.assertIn("&Reconnect to Current Server", prof_texts)
            self.assertIn("&Disconnect (Go Offline)", prof_texts)

            win.net_client.dial = MagicMock()
            win.net_client.hangup = MagicMock()

            self.assertTrue(win.switch_server_profile("GameNight"))
            self.assertEqual(win.prefs["current_profile"], "GameNight")
            self.assertEqual(win.prefs["current_server"], "GameNight")
            win.net_client.hangup.assert_called_once()
            win.net_client.dial.assert_called_once()
            self.assertEqual(win.net_client.dial.call_args.kwargs["host"], "game.example.org")
            self.assertEqual(win.net_client.dial.call_args.kwargs["port"], 2325)

            gn_actions = [
                a for a in win.server_profile_menu.actions()
                if "GameNight" in a.text()
            ]
            self.assertEqual(len(gn_actions), 1)
            self.assertTrue(gn_actions[0].isChecked())

            win.net_client.dial.reset_mock()
            win.net_client.hangup.reset_mock()
            self.assertTrue(win.reconnect_current_server())
            win.net_client.hangup.assert_called_once()
            win.net_client.dial.assert_called_once()

            win.net_client.dial.reset_mock()
            win.net_client.hangup.reset_mock()
            win.disconnect_server()
            win.net_client.hangup.assert_called_once()
            win.net_client.dial.assert_not_called()

            win.net_client.dial.reset_mock()
            win.net_client.hangup.reset_mock()
            self.assertTrue(win.switch_server_profile("offline"))
            win.net_client.hangup.assert_called_once()
            win.net_client.dial.assert_not_called()
            self.assertFalse(win.reconnect_current_server())
        finally:
            if open_about is not None:
                open_about.close()
            if open_markup is not None:
                open_markup.close()
            win.close()

    def test_floating_docks_detach_owner_and_close_with_main_window(self) -> None:
        import os
        import sys

        os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
        try:
            from PySide6.QtWidgets import QApplication
            from gma_mapper.ui.main_window import GMAMapperMainWindow, IndependentDockWidget
        except ImportError:
            self.skipTest("PySide6 not available")

        app = QApplication.instance() or QApplication([])
        win = GMAMapperMainWindow()
        pclock = None
        try:
            self.assertIsInstance(win.chat_dock, IndependentDockWidget)
            self.assertIsInstance(win.combat_dock, IndependentDockWidget)
            self.assertIsInstance(win.clock_dock, IndependentDockWidget)

            win.show()
            app.processEvents()

            win.chat_dock.setFloating(True)
            app.processEvents()
            self.assertTrue(win.chat_dock.isFloating())
            wh = win.chat_dock.windowHandle()
            if wh is not None:
                self.assertIsNone(wh.transientParent())
            if sys.platform == "win32" and app.platformName() != "offscreen":
                import ctypes

                get_window = ctypes.windll.user32.GetWindow
                get_window.argtypes = [ctypes.c_void_p, ctypes.c_uint]
                get_window.restype = ctypes.c_void_p
                self.assertEqual(get_window(int(win.chat_dock.winId()), 4) or 0, 0)

            win.chat_dock.setFloating(False)
            app.processEvents()
            self.assertFalse(win.chat_dock.isFloating())

            win.chat_dock.setFloating(True)
            pclock = win.show_player_clock_window()
            app.processEvents()
            self.assertTrue(win.chat_dock.isVisible())
            self.assertTrue(pclock.isVisible())

            win.close()
            app.processEvents()
            self.assertFalse(win.chat_dock.isVisible())
            self.assertFalse(pclock.isVisible())
        finally:
            if pclock is not None:
                pclock.close()
            win.close()

    def test_auto_sync_chat_on_login_and_opening_chat_dock(self) -> None:
        import os

        os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
        try:
            from PySide6.QtWidgets import QApplication
            from gma_mapper.core.profile import default_preferences, empty_server_profile
            from gma_mapper.ui.main_window import GMAMapperMainWindow
        except ImportError:
            self.skipTest("PySide6 not available")

        app = QApplication.instance() or QApplication([])
        prefs = default_preferences()
        home = empty_server_profile("Home")
        home.update({"host": "home.example.org", "port": 2323, "chat_limit": 250, "suppress_chat": False})
        unlimited = empty_server_profile("Unlimited")
        unlimited.update({"host": "all.example.org", "port": 2323, "chat_limit": 0, "suppress_chat": False})
        quiet = empty_server_profile("Quiet")
        quiet.update({"host": "quiet.example.org", "port": 2323, "chat_limit": 500, "suppress_chat": True})
        prefs["profiles"] = [empty_server_profile("offline"), home, unlimited, quiet]
        prefs["current_profile"] = "Home"

        win = GMAMapperMainWindow(prefs=prefs)
        try:
            sync_calls: list[int] = []
            win.net_client.session.is_ready = lambda: True  # type: ignore[method-assign]
            win.net_client.session.subscribe = lambda: None  # type: ignore[method-assign]
            win.net_client.session.allow = lambda *_args, **_kw: None  # type: ignore[method-assign]
            win.net_client.session.sync = lambda: None  # type: ignore[method-assign]
            win.net_client.session.watch_operation = lambda *_args, **_kw: None  # type: ignore[method-assign]
            win.net_client.session.sync_chat = lambda target: sync_calls.append(target)  # type: ignore[method-assign]

            # 1. Login triggers SYNC-CHAT with -chat_limit when no messages are loaded
            win._on_login_successful()
            self.assertEqual(sync_calls, [-250])

            # 2. Catch up from last_message_id when unsynced session opens chat_dock
            sync_calls.clear()
            win.controller.chat_panel.append_chat(
                {"MessageID": 42, "Origin": "GM", "Text": "Session recap"}
            )
            win.show()
            win.chat_dock.hide()
            app.processEvents()
            win._chat_history_synced_for_session = False
            win.chat_dock.show()
            app.processEvents()
            self.assertEqual(sync_calls, [42])

            # 3. Reopening an empty chat dock while connected requests full profile limit again
            sync_calls.clear()
            win.controller.chat_panel.clear_chat_history(target=0, do_all=True)
            win.chat_dock.hide()
            app.processEvents()
            win.chat_dock.show()
            app.processEvents()
            self.assertEqual(sync_calls, [-250])

            # 4. chat_limit == 0 requests full history (SYNC-CHAT 0)
            sync_calls.clear()
            win.net_client.dial = lambda **_kw: None  # type: ignore[method-assign]
            win.net_client.hangup = lambda: None  # type: ignore[method-assign]
            win.switch_server_profile("Unlimited")
            self.assertEqual(len(win.controller.chat_panel.history_manager.entries), 0)
            self.assertTrue(win.sync_chat_history_from_server())
            self.assertEqual(sync_calls, [0])

            # 5. suppress_chat == True skips SYNC-CHAT
            sync_calls.clear()
            win.switch_server_profile("Quiet")
            self.assertFalse(win.sync_chat_history_from_server())
            self.assertEqual(sync_calls, [])
        finally:
            win.close()

    def test_window_layout_save_restore_reset_and_close_persistence(self) -> None:
        import os
        import tempfile
        from pathlib import Path

        os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
        try:
            from PySide6.QtCore import Qt
            from PySide6.QtWidgets import QApplication
            from gma_mapper.core.profile import (
                default_preferences,
                default_window_layout_path,
                load_window_layout,
            )
            from gma_mapper.ui.main_window import GMAMapperMainWindow
        except ImportError:
            self.skipTest("PySide6 not available")

        app = QApplication.instance() or QApplication([])
        with tempfile.TemporaryDirectory() as tmpdir:
            prefs_path = Path(tmpdir) / "preferences.json"
            layout_path = default_window_layout_path(prefs_path)
            prefs = default_preferences()
            self.assertNotIn("window_layout", prefs)
            win = GMAMapperMainWindow(prefs=prefs, prefs_path=prefs_path)
            win2 = None
            try:
                win.show()
                app.processEvents()

                win.resize(1440, 900)
                win.addDockWidget(Qt.DockWidgetArea.LeftDockWidgetArea, win.combat_dock)
                win.combat_dock.hide()
                win.chat_dock.setFloating(True)
                target_w = max(680, win.chat_dock.minimumSizeHint().width() + 40)
                target_h = max(440, win.chat_dock.minimumSizeHint().height() + 40)
                win.chat_dock.setGeometry(120, 140, target_w, target_h)
                app.processEvents()

                win.close()
                app.processEvents()

                # Legacy preferences.json must remain untouched; layout lives in window_layout.json
                self.assertFalse(prefs_path.exists())
                self.assertTrue(layout_path.is_file())

                wl = load_window_layout(layout_path)
                self.assertTrue(wl["saved"])
                self.assertEqual(wl["docks"]["combat"]["area"], "left")
                self.assertFalse(wl["docks"]["combat"]["visible"])
                self.assertTrue(wl["docks"]["chat"]["floating"])
                self.assertEqual(
                    wl["docks"]["chat"]["geometry"],
                    {"x": 120, "y": 140, "width": target_w, "height": target_h},
                )

                win2 = GMAMapperMainWindow(prefs=default_preferences(), prefs_path=prefs_path)
                self.assertEqual(
                    win2.dockWidgetArea(win2.combat_dock),
                    Qt.DockWidgetArea.LeftDockWidgetArea,
                )
                self.assertTrue(win2.combat_dock.isHidden())
                self.assertTrue(win2.chat_dock.isFloating())
                self.assertEqual(win2.chat_dock.geometry().width(), target_w)
                self.assertEqual(win2.chat_dock.geometry().height(), target_h)

                win2.act_reset_window_layout.trigger()
                app.processEvents()
                self.assertEqual(
                    win2.dockWidgetArea(win2.combat_dock),
                    Qt.DockWidgetArea.RightDockWidgetArea,
                )
                self.assertFalse(win2.combat_dock.isHidden())
                self.assertFalse(win2.chat_dock.isFloating())
                self.assertEqual(
                    win2.dockWidgetArea(win2.chat_dock),
                    Qt.DockWidgetArea.BottomDockWidgetArea,
                )
                self.assertFalse(win2.window_layout["saved"])
                self.assertFalse(load_window_layout(layout_path)["saved"])
            finally:
                if win2 is not None:
                    win2.close()
                win.close()

    def test_diagnostic_window_auto_spawn_colors_save_clear_and_cli(self) -> None:
        import os
        import tempfile

        from gma_mapper.__main__ import apply_cli_overrides, parse_cli_args
        from gma_mapper.core.profile import default_preferences
        from gma_mapper.ui.dialogs.debug_window import (
            diagnostic_tag_colors,
            format_diagnostic_entries_text,
            format_diagnostic_line_html,
            should_display_diagnostic,
        )

        # 1. Pure-Python colors, escaping, filtering, and text formatting
        self.assertEqual(diagnostic_tag_colors("ERROR", dark_mode=False), ("#ff0000", "#ffff00"))
        self.assertEqual(diagnostic_tag_colors("DEBUG 1", dark_mode=True), ("#ffff00", "#232323"))
        self.assertEqual(diagnostic_tag_colors("DEBUG 1", dark_mode=False), ("#ff0000", "#cccccc"))
        self.assertEqual(diagnostic_tag_colors("DEBUG 2", dark_mode=False), ("#000000", "#ffff00"))
        self.assertEqual(diagnostic_tag_colors("DEBUG 3", dark_mode=True), ("#ffffff", "#232323"))
        self.assertEqual(diagnostic_tag_colors("DEBUG 3", dark_mode=False), ("#0000ff", "#cccccc"))
        self.assertEqual(diagnostic_tag_colors("INFO", dark_mode=False), ("#ffffff", "#0000ff"))
        self.assertEqual(diagnostic_tag_colors("PROTOCOL", dark_mode=False), ("#ffffff", "#666666"))
        self.assertFalse(should_display_diagnostic("PROTOCOL", show_protocol=False))
        self.assertTrue(should_display_diagnostic("PROTOCOL", show_protocol=True))
        self.assertTrue(should_display_diagnostic("ERROR", show_protocol=False))

        html_line = format_diagnostic_line_html("INFO", "Connected <ok>", dark_mode=False)
        self.assertIn("[info] Connected &lt;ok&gt;", html_line)
        self.assertIn("#0000ff", html_line)
        self.assertEqual(
            format_diagnostic_entries_text([("ERROR", "bad"), ("PROTOCOL", "-> OK")]),
            "ERROR   |bad\nPROTOCOL|-> OK",
        )

        # 2. CLI -D / --debug / --debug-proto options
        opts = parse_cli_args(["-D", "-D", "--debug-proto"])
        self.assertEqual(opts.debug_level, 2)
        self.assertTrue(opts.debug_proto)
        prefs_cli = apply_cli_overrides(default_preferences(), opts)
        self.assertEqual(prefs_cli["debug_level"], 2)
        self.assertTrue(prefs_cli["debug_proto"])

        # 3. Headless Qt DiagnosticWindow lifecycle & auto-spawn
        os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
        try:
            from PySide6.QtWidgets import QApplication
            from gma_mapper.ui.main_window import GMAMapperMainWindow
        except ImportError:
            self.skipTest("PySide6 not available")

        _app = QApplication.instance() or QApplication([])
        win = GMAMapperMainWindow()
        try:
            self.assertIsNone(win._debug_window)
            self.assertEqual(win.act_show_diagnostics.text(), "Show &Diagnostic Messages...")

            # Passive PROTOCOL does not auto-spawn when debug_proto=False
            win.controller.log_protocol("<- PING")
            self.assertIsNone(win._debug_window)

            # Error auto-spawns the modeless DiagnosticWindow
            win.controller.log_error("boom error")
            self.assertIsNotNone(win._debug_window)
            dbg = win._debug_window
            assert dbg is not None
            self.assertTrue(dbg.isVisible())
            self.assertIn("boom error", dbg.text_view.toPlainText())
            self.assertNotIn("<- PING", dbg.text_view.toPlainText())

            # Show protocol traces checkbox reveals previously buffered PROTOCOL entries
            dbg.chk_show_protocol.setChecked(True)
            self.assertIn("<- PING", dbg.text_view.toPlainText())
            dbg.chk_show_protocol.setChecked(False)

            # Light/dark theme application
            dbg.apply_theme(True)
            self.assertIn("#232323", dbg.text_view.styleSheet())
            dbg.apply_theme(False)
            self.assertIn("#cccccc", dbg.text_view.styleSheet())

            # Clear button empties both controller log and window view
            dbg.btn_clear.click()
            self.assertEqual(win.controller.diagnostic_log, [])
            self.assertEqual(dbg.text_view.toPlainText(), "")

            # Save As callback & save_diagnostics_to_file parity
            win.controller.debug_proto = True
            win.controller.log_protocol("-> SYNC")
            self.assertIn("-> SYNC", dbg.text_view.toPlainText())
            with tempfile.TemporaryDirectory() as tmpdir:
                out_path = Path(tmpdir) / "diag_window.txt"
                self.assertEqual(win.save_diagnostics_to_file(out_path), 1)
                self.assertEqual(out_path.read_text(encoding="utf-8").strip(), "PROTOCOL|-> SYNC")

            # Closing debug window and reopening via Tools -> Show Diagnostic Messages
            dbg.close()
            self.assertFalse(dbg.isVisible())
            win.act_show_diagnostics.trigger()
            self.assertTrue(dbg.isVisible())
        finally:
            win.close()


if __name__ == "__main__":
    unittest.main()
