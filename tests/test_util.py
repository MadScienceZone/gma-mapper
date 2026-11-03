"""Unit tests for gma_mapper.core.util (port of gmautil.tcl, ustar.tcl, letterlabel.tcl)."""

from __future__ import annotations

import pathlib
import unittest

from gma_mapper.core.util import (
    dassign,
    dassigndef,
    is_git,
    letter_label,
    letter_label_to_grid_xy,
    my_arch,
    my_os,
    my_platform,
    ustar_gzip_contents,
    verify,
    version_compare,
)


class TestUtil(unittest.TestCase):
    def test_version_compare_tcl_cases(self) -> None:
        # Exact test vectors from bin/version_test.tcl
        self.assertEqual(version_compare("1.2", "1.2.3"), -1)
        self.assertEqual(version_compare("1.2.3-alpha", "1.2.3"), -1)
        self.assertEqual(version_compare("1.2.3", "1.2.3-alpha"), 1)
        self.assertEqual(version_compare("1.2-alpha", "1.2-beta"), -1)
        self.assertEqual(version_compare("1.2-beta", "1.2-alpha"), 1)
        self.assertEqual(version_compare("1.2+foo-alpha.3", "1.2+bar-alpha.4"), -1)
        self.assertEqual(version_compare("4.42", "4.42"), 0)
        self.assertEqual(version_compare("4.42", "5.0.0-alpha.1"), -1)

    def test_letter_label_and_grid_xy(self) -> None:
        self.assertEqual(letter_label(0), "A")
        self.assertEqual(letter_label(25), "Z")
        self.assertEqual(letter_label(26), "AA")
        self.assertEqual(letter_label(27), "AB")
        self.assertEqual(letter_label(51), "AZ")
        self.assertEqual(letter_label(52), "BA")
        self.assertEqual(letter_label(701), "ZZ")
        self.assertEqual(letter_label(702), "AAA")

        for col in (0, 1, 25, 26, 27, 51, 52, 100, 701, 702):
            lbl = f"{letter_label(col)}42"
            self.assertEqual(letter_label_to_grid_xy(lbl), (col, 42))

        with self.assertRaises(ValueError):
            letter_label_to_grid_xy("12A")

    def test_verify_and_ustar_on_signed_release(self) -> None:
        repo_root = pathlib.Path(__file__).resolve().parents[1]
        tar_path = repo_root / "signed-releases" / "mapper-4.38.1.tar.gz"
        sig_path = repo_root / "signed-releases" / "mapper-4.38.1.tar.gz.sig"
        if tar_path.exists() and sig_path.exists():
            data = tar_path.read_bytes()
            sig = sig_path.read_bytes()
            self.assertTrue(verify(data, sig))
            self.assertFalse(verify(data + b"tamper", sig))

            entries = ustar_gzip_contents(tar_path)
            self.assertGreater(len(entries), 10)
            names = [e.name for e in entries]
            self.assertTrue(any("__checksums__" in n for n in names))

    def test_git_and_platform_helpers(self) -> None:
        repo_root = pathlib.Path(__file__).resolve().parents[1]
        self.assertTrue(is_git(repo_root))
        self.assertIn(my_os(), ("windows", "linux", "darwin", "freebsd"))
        self.assertTrue(len(my_arch()) > 0)
        self.assertEqual(len(my_platform()), 3)

    def test_dassign_and_dassigndef(self) -> None:
        d = {"a": 1, "nested": {"b": 2}}
        self.assertEqual(dassign(d, "a", "nested b"), [1, 2])
        self.assertEqual(
            dassigndef(d, ("a", 10), ("nested c", 99), ("missing", "default")),
            [1, 99, "default"],
        )


if __name__ == "__main__":
    unittest.main()

