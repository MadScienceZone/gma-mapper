"""Unit tests for gma_mapper.core.profile (ported from bin/test_profiles.tcl)."""

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
            self.assertEqual(loaded["GMA_Mapper_preferences_version"], CURRENT_FILE_VERSION)
            self.assertEqual(loaded["current_profile"], "offline")
            self.assertEqual(loaded["scaling"], 1.0)
            self.assertIn("Normal", loaded["fonts"])
            self.assertIn("fullresult", loaded["styles"]["dierolls"]["components"])
            self.assertEqual(
                preferred_color(loaded, "heading_fg", "dark"),
                "cyan",
            )
            self.assertEqual(
                preferred_color(loaded, "fg", "light"),
                "#000000",
            )

    def test_fix_missing_and_symbols(self) -> None:
        sparse: dict = {"GMA_Mapper_preferences_version": 5}
        fix_missing(sparse)
        self.assertEqual(sparse["scaling"], 1.0)
        self.assertEqual(sparse["show_timers"], "mine")
        self.assertIn("ClockTime", sparse["fonts"])
        self.assertEqual(symbol_code_string("pin"), "📌")
        self.assertEqual(symbol_code_string("nonexistent"), "\u22a0")


if __name__ == "__main__":
    unittest.main()

