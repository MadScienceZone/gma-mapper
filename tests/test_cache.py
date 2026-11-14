"""Unit tests for gma_mapper.core.cache."""

import tempfile
import unittest
from pathlib import Path
from unittest import mock

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

            # Bare filename without leading slash
            b_exists, _, b_name, b_zoom, b_frame = cache.cache_info("goblin_token@1.00.png")
            self.assertFalse(b_exists)
            self.assertEqual(b_name, "goblin_token")
            self.assertEqual(b_zoom, "1.00")
            self.assertEqual(b_frame, "")

            _, _, bm_name, _, _ = cache.cache_info("abcdef123.map")
            self.assertEqual(bm_name, "abcdef123")

            frame_path = cache.cache_filename("fireball", 2.0, frameno=3)
            self.assertTrue(frame_path.name.endswith("3:fireball@2.00.png") or frame_path.name.endswith("3;fireball@2.00.png"))
            frame_path.write_bytes(b"FRAMEDATA")
            frame_path2 = cache.cache_filename("fireball", 2.0, frameno=4)
            frame_path2.write_bytes(b"FRAMEDATA2")
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

            # 1 single image + 1 animated directory + 2 frame files = 4 total items
            deleted, total, _ = cache.cleanup_image_cache(days_old=0)
            self.assertEqual(deleted, 2)
            self.assertEqual(total, 4)
            self.assertFalse(img_path.exists())

    def test_atomic_download_and_send_file_security(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            cache = AssetCache(
                cache_dir=tmpdir,
                scp_server="gm@example.org",
                scp_dest="/var/www/gma/maps",
            )
            dest = Path(tmpdir) / "_t" / "token@1.00.png"
            fake_resp = mock.MagicMock()
            fake_resp.__enter__.return_value.read.return_value = b"ATOMIC_PNG_BYTES"
            with mock.patch("urllib.request.urlopen", return_value=fake_resp):
                ok = cache._download_to_file("https://example.org/t.png", dest)
            self.assertTrue(ok)
            self.assertEqual(dest.read_bytes(), b"ATOMIC_PNG_BYTES")
            # Ensure no temporary .tmp files remain in the directory
            self.assertEqual(list(dest.parent.glob("*.tmp")), [])

            # Reject path traversal or shell metacharacters in file_id
            for bad_id in ("../etc", "ab;rm -rf /", "a", "foo/bar"):
                with self.assertRaises(ValueError):
                    cache.send_file_to_server(bad_id, dest)

            # Verify fallback warning when paramiko is not installed
            with (
                mock.patch.dict("sys.modules", {"paramiko": None}),
                mock.patch("subprocess.run") as mock_run,
                self.assertLogs("gma_mapper.core.cache", level="WARNING") as cm,
            ):
                cache.send_file_to_server("valid_id_123", dest, use_paramiko=True)
                self.assertEqual(mock_run.call_count, 2)
                self.assertTrue(any("paramiko is not installed" in msg for msg in cm.output))


if __name__ == "__main__":
    unittest.main()
