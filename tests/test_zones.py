"""Unit tests for gma_mapper.core.zones (port of bin/gmazones.tcl & mapper.tcl)."""

from __future__ import annotations

import unittest

from gma_mapper.core.zones import (
    ComputedReachMatrix,
    CreatureDisplayedSize,
    CreatureSizeParams,
    FullCreatureAreaInfo,
    MatchesStandardTemplate,
    MonsterSizeValue,
    ParseSizeCode,
    ReachMatrix,
    SkinComment,
    SkinIsDefault,
    SkinSizeOnly,
    creature_display_zoom,
)


class TestZones(unittest.TestCase):
    def test_creature_size_params(self) -> None:
        self.assertEqual(CreatureSizeParams("M"), ["M", "", "", ""])
        self.assertEqual(CreatureSizeParams("L10->20=10:ogre"), ["L", 2, 4, 2])
        self.assertEqual(CreatureSizeParams("invalid"), [])

    def test_parse_size_code_and_skin_helpers(self) -> None:
        self.assertEqual(
            ParseSizeCode("L10->20=10:*longspear"),
            ["L", "10", "20", "10", True, "longspear"],
        )
        self.assertEqual(SkinComment("M:*sword"), "sword")
        self.assertTrue(SkinIsDefault("M:*sword"))
        self.assertFalse(SkinIsDefault("M:bow"))
        self.assertEqual(SkinSizeOnly("L10->20:*spear"), "L10->20")

    def test_monster_size_value_and_reach_matrix(self) -> None:
        self.assertEqual(MonsterSizeValue("F"), 0.1)
        self.assertEqual(MonsterSizeValue("T"), 0.5)
        self.assertEqual(MonsterSizeValue("M"), 1)
        self.assertEqual(MonsterSizeValue("L"), 2)
        self.assertEqual(MonsterSizeValue("H"), 3)
        self.assertEqual(MonsterSizeValue("G"), 4)
        self.assertEqual(MonsterSizeValue("C"), 6)
        self.assertEqual(MonsterSizeValue("M=15"), 3)

        m_tpl = ReachMatrix("M")
        self.assertEqual(m_tpl[0], 1)
        self.assertEqual(m_tpl[1], 2)
        self.assertEqual(len(m_tpl[2]), 5)

        self.assertEqual(MatchesStandardTemplate("M", 1, 2), m_tpl)
        self.assertEqual(MatchesStandardTemplate("M", 1, 3), [])

    def test_computed_reach_matrix_custom(self) -> None:
        # M with natural=1, reach=3 -> dimension = 1 + 2*3 = 7x7
        nat, ext, mat = ComputedReachMatrix("M", 1, 3)
        self.assertEqual((nat, ext), (1, 3))
        self.assertEqual(len(mat), 7)
        self.assertEqual(len(mat[0]), 7)
        # Center square (3,3) is within natural reach (value 2)
        self.assertEqual(mat[3][3], 2)
        # Corner square (0,0) has distance int(sqrt(15^2 + 15^2)/5) = int(21.21/5) = 4 > 3 -> 0
        self.assertEqual(mat[0][0], 0)
        # Cardinal edge (3,0) has distance 3 <= 3 -> 1
        self.assertEqual(mat[0][3], 1)

    def test_full_creature_area_info_and_zoom(self) -> None:
        mob = {
            "Size": "M:*normal",
            "DispSize": "L:enlarged",
            "CustomReach": {},
        }
        self.assertEqual(CreatureDisplayedSize(mob), "L")
        space, nat, ext, mat, custom = FullCreatureAreaInfo(mob)
        self.assertEqual((space, nat, ext, custom), (2, 2, 4, ""))
        self.assertEqual(len(mat), 10)

        mob_custom = {
            "Size": "M",
            "DispSize": "",
            "CustomReach": {"Enabled": True, "Natural": 10, "Extended": 20},
        }
        space2, nat2, ext2, mat2, custom2 = FullCreatureAreaInfo(mob_custom)
        self.assertEqual((space2, nat2, ext2), (1, 2, 4))
        self.assertEqual(len(mat2), 9)
        self.assertEqual(custom2["Natural"], 10)

        self.assertEqual(creature_display_zoom("M", "M", 1.0), 1.0)
        self.assertEqual(creature_display_zoom("M", "L", 1.0), 2.0)
        self.assertEqual(creature_display_zoom("L", "M", 2.0), 1.0)


if __name__ == "__main__":
    unittest.main()

