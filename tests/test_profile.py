"""Unit tests for gma_mapper.core.profile (ported from bin/test_profiles.tcl)."""

import json
import tempfile
import unittest
from pathlib import Path

from gma_mapper.core.profile import (
    CURRENT_FILE_VERSION,
    default_preferences,
    empty_server_profile,
    find_server_index,
    fix_missing,
    list_server_names,
    load,
    preferred_color,
    save,
    symbol_code_string,
)


class TestProfile(unittest.TestCase):
    def test_default_preferences_and_roundtrip(self) -> None:
        prefs = default_preferences()
        self.assertEqual(prefs["current_profile"], "offline")
        self.assertEqual(prefs["button_size"], "small")
        self.assertEqual(prefs["scaling"], 1.0)
        self.assertEqual(list_server_names(prefs), ["offline"])
        self.assertEqual(find_server_index(prefs, "offline"), 0)

        with tempfile.TemporaryDirectory() as tmpdir:
            pref_file = Path(tmpdir) / "testprefs.json"
            save(pref_file, prefs)
            loaded = load(pref_file)
            # Second save->load roundtrip must retain all nested objects for Tcl backwards compatibility
            save(pref_file, loaded)
            raw_json = json.loads(pref_file.read_text(encoding="utf-8"))
            self.assertIn("guide_lines", raw_json)
            self.assertIn("major", raw_json["guide_lines"])
            self.assertIn("offsets", raw_json["guide_lines"]["major"])
            self.assertIn("minor", raw_json["guide_lines"])
            self.assertIn("offsets", raw_json["guide_lines"]["minor"])
            self.assertIn("a11y", raw_json)
            for font_name, font_val in raw_json["fonts"].items():
                self.assertIs(
                    type(font_val["size"]),
                    int,
                    f"font {font_name} size must be int for Tk font create, got {type(font_val['size'])}",
                )
            for comp_name, comp_val in raw_json["styles"]["dierolls"]["components"].items():
                self.assertIn("fg", comp_val, f"missing fg in component {comp_name}")
                self.assertIn("bg", comp_val, f"missing bg in component {comp_name}")

            loaded2 = load(pref_file)
            self.assertEqual(loaded2["GMA_Mapper_preferences_version"], CURRENT_FILE_VERSION)
            self.assertEqual(loaded2["current_profile"], "offline")
            self.assertEqual(loaded2["scaling"], 1.0)
            self.assertEqual(
                loaded2["guide_lines"],
                {
                    "major": {"interval": 0, "offsets": {"x": 0, "y": 0}},
                    "minor": {"interval": 0, "offsets": {"x": 0, "y": 0}},
                },
            )
            self.assertIn("Normal", loaded2["fonts"])
            self.assertIn("fullresult", loaded2["styles"]["dierolls"]["components"])
            self.assertEqual(
                loaded2["styles"]["dierolls"]["components"]["begingroup"]["fg"],
                {"dark": "", "light": ""},
            )
            self.assertEqual(
                loaded2["styles"]["dierolls"]["components"]["begingroup"]["bg"],
                {"dark": "", "light": ""},
            )
            self.assertEqual(
                preferred_color(loaded2, "heading_fg", "dark"),
                "cyan",
            )
            self.assertEqual(
                preferred_color(loaded2, "fg", "light"),
                "#000000",
            )

    def test_fix_missing_and_symbols(self) -> None:
        sparse: dict = {"GMA_Mapper_preferences_version": 5, "guide_lines": True}
        fix_missing(sparse)
        self.assertEqual(sparse["scaling"], 1.0)
        self.assertEqual(sparse["show_timers"], "mine")
        self.assertEqual(
            sparse["guide_lines"],
            {
                "major": {"interval": 0, "offsets": {"x": 0, "y": 0}},
                "minor": {"interval": 0, "offsets": {"x": 0, "y": 0}},
            },
        )
        self.assertIn("ClockTime", sparse["fonts"])
        self.assertEqual(symbol_code_string("pin"), "📌")
        self.assertEqual(symbol_code_string("nonexistent"), "\u22a0")

    def test_preferences_dialog_appearance_tab_and_apply(self) -> None:
        from gma_mapper.ui.dialogs.preferences import HAS_PYSIDE6, PreferencesDialog
        from gma_mapper.ui.main_window import MapperController

        prefs = default_preferences()
        ctrl = MapperController(prefs)
        if not HAS_PYSIDE6:
            return

        dlg = PreferencesDialog(prefs)
        self.assertEqual(
            [dlg.tabs.tabText(i) for i in range(dlg.tabs.count())],
            ["Appearance", "Servers", "Styles", "Tools", "Diagnostics", "Accessibility"],
        )
        # Verify default widget state matches default_preferences()
        self.assertFalse(dlg.animate_check.isChecked())
        self.assertFalse(dlg.flash_updates_check.isChecked())
        self.assertTrue(dlg.chat_timestamp_check.isChecked())
        self.assertTrue(dlg.colorize_die_rolls_check.isChecked())
        self.assertTrue(dlg.markup_enabled_check.isChecked())
        self.assertFalse(dlg.dark_check.isChecked())
        self.assertAlmostEqual(dlg.scaling_spin.value(), 1.0)
        self.assertFalse(dlg.menu_button_check.isChecked())
        self.assertFalse(dlg.never_animate_check.isChecked())
        self.assertFalse(dlg.keep_tools_check.isChecked())
        self.assertEqual(dlg.show_timers_combo.currentData(), "mine")
        self.assertFalse(dlg.preload_check.isChecked())
        self.assertEqual(dlg.image_format_combo.currentData(), "png")
        self.assertEqual(dlg.button_size_combo.currentData(), "small")
        self.assertTrue(dlg.toolbar_icons_check.isChecked())
        self.assertEqual(dlg.major_interval_spin.value(), 0)
        self.assertEqual(dlg.minor_interval_spin.value(), 0)
        self.assertFalse(dlg.no_dice_check.isChecked())
        self.assertFalse(dlg.suppress_aka_check.isChecked())
        self.assertFalse(dlg.not_playing_check.isChecked())
        self.assertFalse(dlg.no_ondeck_audio_check.isChecked())
        self.assertFalse(dlg.no_sfx_check.isEnabled())
        self.assertEqual(dlg.debug_level_spin.value(), 0)
        self.assertFalse(dlg.debug_proto_check.isChecked())
        self.assertFalse(dlg.curl_insecure_check.isChecked())
        self.assertTrue(dlg.colorize_die_labels_check.isChecked())

        # Modify all Appearance, Tools, Diagnostics, and Accessibility controls and accept
        dlg.animate_check.setChecked(True)
        dlg.flash_updates_check.setChecked(True)
        dlg.chat_timestamp_check.setChecked(False)
        dlg.colorize_die_rolls_check.setChecked(False)
        dlg.markup_enabled_check.setChecked(False)
        dlg.dark_check.setChecked(True)
        dlg.scaling_spin.setValue(2.0)
        dlg.menu_button_check.setChecked(True)
        dlg.never_animate_check.setChecked(True)
        dlg.keep_tools_check.setChecked(True)
        dlg.show_timers_combo.setCurrentIndex(dlg.show_timers_combo.findData("all"))
        dlg.preload_check.setChecked(True)
        dlg.image_format_combo.setCurrentIndex(dlg.image_format_combo.findData("gif"))
        dlg.button_size_combo.setCurrentIndex(dlg.button_size_combo.findData("medium"))
        dlg.toolbar_icons_check.setChecked(False)
        dlg.major_interval_spin.setValue(10)
        dlg.major_offset_x_spin.setValue(2)
        dlg.major_offset_y_spin.setValue(3)
        dlg.minor_interval_spin.setValue(5)
        dlg.minor_offset_x_spin.setValue(1)
        dlg.minor_offset_y_spin.setValue(4)
        dlg.no_dice_check.setChecked(True)
        dlg.suppress_aka_check.setChecked(True)
        dlg.not_playing_check.setChecked(True)
        dlg.no_ondeck_audio_check.setChecked(True)
        dlg.debug_level_spin.setValue(3)
        dlg.debug_proto_check.setChecked(True)
        dlg.curl_path_edit.setText("/usr/local/bin/curl")
        dlg.curl_insecure_check.setChecked(True)
        dlg.colorize_die_labels_check.setChecked(False)

        dlg._on_accept()
        updated = dlg.prefs
        self.assertTrue(updated["animate"])
        self.assertTrue(updated["flash_updates"])
        self.assertFalse(updated["chat_timestamp"])
        self.assertFalse(updated["colorize_die_rolls"])
        self.assertFalse(updated["markup_enabled"])
        self.assertTrue(updated["dark"])
        self.assertAlmostEqual(updated["scaling"], 2.0)
        self.assertTrue(updated["menu_button"])
        self.assertTrue(updated["never_animate"])
        self.assertTrue(updated["keep_tools"])
        self.assertEqual(updated["show_timers"], "all")
        self.assertTrue(updated["preload"])
        self.assertEqual(updated["image_format"], "gif")
        self.assertEqual(updated["button_size"], "medium")
        self.assertTrue(updated["toolbar_text"])
        self.assertEqual(
            updated["guide_lines"],
            {
                "major": {"interval": 10, "offsets": {"x": 2, "y": 3}},
                "minor": {"interval": 5, "offsets": {"x": 1, "y": 4}},
            },
        )
        self.assertTrue(updated["no_dice"])
        self.assertTrue(updated["suppress_aka"])
        self.assertTrue(updated["not_playing"])
        self.assertTrue(updated["no_ondeck_audio"])
        self.assertEqual(updated["debug_level"], 3)
        self.assertTrue(updated["debug_proto"])
        self.assertEqual(updated["curl_path"], "/usr/local/bin/curl")
        self.assertTrue(updated["curl_insecure"])
        self.assertFalse(updated["a11y"]["colorize_die_labels"])

        ctrl.apply_preferences(updated)
        self.assertTrue(ctrl.scene.dark_mode)
        self.assertEqual(ctrl.scene.major_interval, 10)
        self.assertEqual(ctrl.scene.major_offset, (2, 3))
        self.assertEqual(ctrl.scene.minor_interval, 5)
        self.assertEqual(ctrl.scene.minor_offset, (1, 4))
        self.assertEqual(ctrl.cache.image_format, "gif")
        self.assertTrue(ctrl.cache.curl_insecure)
        self.assertFalse(ctrl.audio.enabled)
        self.assertEqual(ctrl.debug_level, 3)
        self.assertTrue(ctrl.debug_proto)

    def test_preferences_dialog_styles_tabs(self) -> None:
        from gma_mapper.ui.dialogs.preferences import HAS_PYSIDE6, PreferencesDialog
        from gma_mapper.ui.main_window import MapperController

        prefs = default_preferences()
        _ = MapperController(prefs)
        if not HAS_PYSIDE6:
            return

        dlg = PreferencesDialog(prefs)
        self.assertEqual(dlg.styles_tabs.count(), 7)

        # 1. Fonts sub-tab: add, edit, copy, delete (and block deleting referenced font)
        self.assertTrue(dlg.add_font("CustomFont"))
        self.assertEqual(dlg.selected_font_name(), "CustomFont")
        self.assertTrue(
            dlg.set_selected_font(
                {
                    "family": "Courier",
                    "size": 14,
                    "weight": 1,
                    "slant": 1,
                    "overstrike": True,
                    "underline": True,
                }
            )
        )
        self.assertEqual(dlg.prefs["fonts"]["CustomFont"]["family"], "Courier")
        self.assertIs(type(dlg.prefs["fonts"]["CustomFont"]["size"]), int)
        self.assertEqual(dlg.prefs["fonts"]["CustomFont"]["size"], 14)
        self.assertTrue(dlg.copy_selected_font("CustomFontCopy"))
        self.assertTrue(dlg.delete_selected_font())
        self.assertNotIn("CustomFontCopy", dlg.prefs["fonts"])
        # Selecting "Normal" and trying to delete it must fail because it is referenced
        for i in range(dlg.fonts_list.count()):
            if dlg.fonts_list.item(i).text() == "Normal":
                dlg.fonts_list.setCurrentRow(i)
                break
        self.assertFalse(dlg.delete_selected_font())

        # 2. Dialogs & 5. Colors sub-tabs
        dlg.set_dialog_color("heading_fg", "light", "#112233")
        self.assertEqual(dlg.prefs["styles"]["dialogs"]["heading_fg"]["light"], "#112233")
        dlg.reset_dialog_color("heading_fg")
        self.assertEqual(dlg.prefs["styles"]["dialogs"]["heading_fg"]["light"], "blue")
        dlg.set_dialog_color("grid", "dark", "#445566")
        self.assertEqual(dlg.prefs["styles"]["dialogs"]["grid"]["dark"], "#445566")

        # 3. Die Rolls/Chat sub-tab
        for i in range(dlg.dieroll_styles_list.count()):
            if dlg.dieroll_styles_list.item(i).text() == "best":
                dlg.dieroll_styles_list.setCurrentRow(i)
                break
        self.assertEqual(dlg.selected_dieroll_style_name(), "best")
        self.assertEqual(dlg.dr_format_edit.text(), "_best of %s")
        dlg.dr_format_edit.setText("_top %s_")
        self.assertEqual(dlg.prefs["styles"]["dierolls"]["components"]["best"]["format"], " top %s ")
        dlg.dr_overstrike_check.setChecked(True)
        dlg.dr_underline_check.setChecked(True)
        dlg.dr_offset_spin.setValue(4)
        dlg.dr_font_combo.setCurrentText("CustomFont")
        self.assertTrue(dlg.prefs["styles"]["dierolls"]["components"]["best"]["overstrike"])
        self.assertTrue(dlg.prefs["styles"]["dierolls"]["components"]["best"]["underline"])
        self.assertEqual(dlg.prefs["styles"]["dierolls"]["components"]["best"]["offset"], 4)
        self.assertEqual(dlg.prefs["styles"]["dierolls"]["components"]["best"]["font"], "CustomFont")
        dlg.reset_selected_dieroll_style()
        self.assertEqual(dlg.prefs["styles"]["dierolls"]["components"]["best"]["format"], " best of %s")
        dlg.compact_recents_check.setChecked(True)
        self.assertTrue(dlg.prefs["styles"]["dierolls"]["compact_recents"])

        # 4. Symbols sub-tab
        dlg.symbol_combos["pushpin"].setCurrentText("triangle")
        self.assertEqual(dlg.prefs["styles"]["characters"]["pushpin"]["name"], "triangle")
        self.assertEqual(dlg.symbol_preview_labels["pushpin"].text(), symbol_code_string("triangle"))

        # 6. Clocks sub-tab
        dlg.set_clock_color("hand_color", "light", "#abcdef")
        self.assertEqual(dlg.prefs["styles"]["clocks"]["hand_color"]["light"], "#abcdef")
        dlg.reset_clock_color("hand_color")
        self.assertEqual(dlg.prefs["styles"]["clocks"]["hand_color"]["light"], "black")
        dlg.clock_font_combos["timedisp_font"].setCurrentText("CustomFont")
        self.assertEqual(dlg.prefs["styles"]["clocks"]["timedisp_font"], "CustomFont")

        # 7. Markers sub-tab
        self.assertTrue(dlg.add_marker("smite"))
        self.assertEqual(dlg.selected_marker_name(), "smite")
        dlg.marker_mods_edit.setText("$smite,/holy")
        dlg.marker_desc_edit.setText("Smite Evil target")
        dlg.marker_shape_combo.setCurrentIndex(dlg.marker_shape_combo.findData("<>"))
        dlg.marker_dash_combo.setCurrentIndex(dlg.marker_dash_combo.findData("--"))
        dlg.set_selected_marker_color("#ff0000")
        dlg.marker_tracer_check.setChecked(True)
        dlg.marker_endatdeath_check.setChecked(True)
        dlg.marker_limit_spin.setValue(2)
        self.assertEqual(
            dlg.prefs["styles"]["markers"]["smite"],
            {
                "modifiers": ["$smite", "/holy"],
                "color": "#ff0000",
                "shape": "<>",
                "dashpattern": "--",
                "description": "Smite Evil target",
                "tracer": True,
                "endatdeath": True,
                "limit": 2,
            },
        )
        self.assertTrue(dlg.copy_selected_marker("smite_copy"))
        self.assertIn("smite_copy", dlg.prefs["styles"]["markers"])
        self.assertTrue(dlg.delete_selected_marker())
        self.assertNotIn("smite_copy", dlg.prefs["styles"]["markers"])

        dlg._on_accept()
        with tempfile.TemporaryDirectory() as tmpdir:
            pref_file = Path(tmpdir) / "styles_roundtrip.json"
            save(pref_file, dlg.prefs)
            reloaded = load(pref_file)
            self.assertIn("CustomFont", reloaded["fonts"])
            self.assertEqual(reloaded["styles"]["markers"]["smite"]["shape"], "<>")
            self.assertEqual(reloaded["styles"]["characters"]["pushpin"]["name"], "triangle")
            self.assertTrue(reloaded["styles"]["dierolls"]["compact_recents"])


if __name__ == "__main__":
    unittest.main()

