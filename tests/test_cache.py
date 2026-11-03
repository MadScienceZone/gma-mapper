"""Unit tests for gma_mapper.core.cache."""

import tempfile
import unittest
from pathlib import Path

from gma_mapper.core.cache import AssetCache, cache_map_id, normalize_zoom, tile_id


class TestCache(unittest.TestCase):
    def test_zoom_and_map_id(self) -> None:
        self.assertEqual(normalize_zoom(1), "1.00")
        self.assertEqual(normalize_zoom(0.25), "0.25")
        self.assertEqual(tile_id("dungeon", 1.5), "dungeon:1.50")

        mid = cache_map_id("/path/to/FireGeodeTemple.map", "")
        self.assertEqual(len(mid), 22)
        self.assertNotIn("=", mid)
        self.assertNotIn("+", mid)
        self.assertNotIn("/", mid)

        mid_mod = cache_map_id("/path/to/FireGeodeTemple.map", "MOD1")
        self.assertNotEqual(mid, mid_mod)

    def test_cache_paths_and_info(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            cache = AssetCache(cache_dir=tmpdir, image_format="png")
            img_path = cache.cache_filename("goblin_token", 1.0)
            self.assertEqual(img_path.parent.name, "_i")
            self.assertEqual(img_path.name, "goblin_token@1.00.png")

            exists, age, name, zoom, frame = cache.cache_info(img_path)
            self.assertFalse(exists)
            self.assertEqual(name, "goblin_token")
            self.assertEqual(zoom, "1.00")
            self.assertEqual(frame, "")

            img_path.write_bytes(b"PNGDATA")
            exists, age, name, zoom, frame = cache.cache_info(img_path)
            self.assertTrue(exists)
            self.assertEqual(age, 0)

            frame_path = cache.cache_filename("fireball", 2.0, frameno=3)
            self.assertTrue(frame_path.name.endswith("3:fireball@2.00.png") or frame_path.name.endswith("3;fireball@2.00.png"))
            frame_path.write_bytes(b"FRAMEDATA")
            f_exists, _, f_name, f_zoom, f_frame = cache.cache_info(frame_path)
            self.assertTrue(f_exists)
            self.assertEqual(f_name, "fireball")
            self.assertEqual(f_zoom, "2.00")
            self.assertEqual(f_frame, ":3:")

            map_path = cache.cache_map_filename("abcdef123")
            self.assertEqual(map_path.parent.name, "a")
            self.assertEqual(map_path.name, "abcdef123.map")
            map_path.write_text("__MAPPER__:24\n", encoding="utf-8")
            m_exists, _, m_name, _, _ = cache.cache_info(map_path)
            self.assertTrue(m_exists)
            self.assertEqual(m_name, "abcdef123")

            deleted, total, _ = cache.cleanup_image_cache(days_old=0)
            self.assertGreaterEqual(deleted, 2)
            self.assertFalse(img_path.exists())


if __name__ == "__main__":
    unittest.main()
