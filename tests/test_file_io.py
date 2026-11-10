"""Unit tests for gma_mapper.core.file_io against real-world and synthetic files."""

import io
import unittest
from pathlib import Path

from gma_mapper.core.file_io import (
    load_dice_presets_from_file,
    load_from_file,
    parse_tcl_list,
    save_dice_presets_to_file,
    save_to_file,
)


WORKSPACE_ROOT = Path(__file__).resolve().parents[2]


def _can_read_external(p: Path) -> bool:
    try:
        return p.exists() and bool(p.read_bytes()[:1])
    except PermissionError:
        return False


class TestFileIO(unittest.TestCase):
    def test_parse_tcl_list(self) -> None:
        self.assertEqual(
            parse_tcl_list("SenseMotive {Sense Motive} d20+4"),
            ["SenseMotive", "Sense Motive", "d20+4"],
        )
        self.assertEqual(
            parse_tcl_list("{{} {1632100538 {Sun Sep 19 18:15:38 PDT 2021}}}"),
            ["{} {1632100538 {Sun Sep 19 18:15:38 PDT 2021}}"],
        )

    def test_load_real_legacy_and_modern_map_files(self) -> None:
        # Modern v23 map file
        temple_path = WORKSPACE_ROOT / "FireGeodeTemple.map"
        if _can_read_external(temple_path):
            meta, objs = load_from_file(temple_path)
            self.assertEqual(meta["Timestamp"], 1702857654)
            self.assertGreater(len(objs), 20)
            self.assertEqual(objs[0][0], "RECT")
            self.assertEqual(objs[0][1]["ID"], "ee32ab10545347e9ad2b7761437e5555")

        # Legacy v17 map file with creatures
        session_one_path = WORKSPACE_ROOT / "end of session one.map"
        if _can_read_external(session_one_path):
            meta, objs = load_from_file(session_one_path)
            self.assertEqual(meta["FileVersion"], 17)
            creatures = [d for t, d in objs if t == "CREATURE"]
            self.assertGreater(len(creatures), 5)
            names = {c["Name"] for c in creatures}
            self.assertIn("Gaspose", names)
            self.assertIn("Raven", names)

        # Legacy v17 map file with geometry
        sheriff_path = WORKSPACE_ROOT / "Sheriffsoffice.map"
        if _can_read_external(sheriff_path):
            meta, objs = load_from_file(sheriff_path)
            self.assertEqual(meta["FileVersion"], 17)
            types = {t for t, _ in objs}
            self.assertIn("RECT", types)
            self.assertIn("LINE", types)

    def test_roundtrip_map_v24(self) -> None:
        buf = io.StringIO()
        meta_in = {"Timestamp": 1700000000, "Comment": "Unit test map", "Location": "Dungeon"}
        objs_in = [
            (
                "RECT",
                {
                    "ID": "r1",
                    "X": 50.0,
                    "Y": 100.0,
                    "Points": [{"X": 150.0, "Y": 200.0}],
                    "Z": 3,
                    "Line": "black",
                    "Fill": "red",
                    "Width": 2,
                    "Layer": "walls",
                },
            ),
            (
                "CREATURE",
                {
                    "ID": "c1",
                    "Name": "Goblin",
                    "Gx": 4.0,
                    "Gy": 6.0,
                    "Size": "S",
                    "DispSize": "S",
                    "Color": "red",
                    "CreatureType": 1,
                },
            ),
        ]
        save_to_file(buf, (meta_in, objs_in))
        buf.seek(0)
        first_line = buf.getvalue().splitlines()[0]
        self.assertEqual(first_line, "__MAPPER__:24")

        meta_out, objs_out = load_from_file(buf)
        self.assertEqual(meta_out["Timestamp"], 1700000000)
        self.assertEqual(meta_out["Comment"], "Unit test map")
        self.assertEqual(len(objs_out), 2)
        self.assertEqual(objs_out[0][0], "RECT")
        self.assertEqual(objs_out[0][1]["ID"], "r1")
        self.assertEqual(objs_out[1][0], "CREATURE")
        self.assertEqual(objs_out[1][1]["Name"], "Goblin")

    def test_load_and_roundtrip_dice_presets(self) -> None:
        viktor_path = WORKSPACE_ROOT / "Viktor.dice"
        if _can_read_external(viktor_path):
            meta, presets = load_dice_presets_from_file(viktor_path)
            self.assertEqual(meta["FileVersion"], 2)
            self.assertEqual(len(presets), 10)
            self.assertEqual(presets[0]["Name"], "1-StaffDam")

        magnius_path = WORKSPACE_ROOT / "magnius.dice"
        if _can_read_external(magnius_path):
            meta, presets = load_dice_presets_from_file(magnius_path)
            self.assertEqual(meta["FileVersion"], 1)
            self.assertEqual(len(presets), 4)
            self.assertEqual(presets[1]["Description"], "Sense Motive")

        buf = io.StringIO()
        save_dice_presets_to_file(
            buf,
            (
                {"Timestamp": 1700000000, "Comment": "Test presets"},
                [{"Name": "Attack", "Description": "Longsword", "DieRollSpec": "1d20+5"}],
            ),
        )
        buf.seek(0)
        meta2, presets2 = load_dice_presets_from_file(buf)
        self.assertEqual(meta2["FileVersion"], 2)
        self.assertEqual(len(presets2), 1)
        self.assertEqual(presets2[0]["Name"], "Attack")


if __name__ == "__main__":
    unittest.main()

