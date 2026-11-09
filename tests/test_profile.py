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


if __name__ == "__main__":
    unittest.main()

