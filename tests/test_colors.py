"""Unit tests for gma_mapper.core.colors (port of bin/gmacolors.tcl)."""

from __future__ import annotations

import unittest

from gma_mapper.core.colors import (
    X11_COLOR_LIST,
    color_to_hex,
    contrasting_color,
    darken_color,
    parse_color_rgb,
    rgb_name,
)


class TestColors(unittest.TestCase):
    def test_rgb_name_exact_matches(self) -> None:
        self.assertEqual(rgb_name("#ffffff"), "white")
        self.assertEqual(rgb_name("#000000"), "black")
        self.assertEqual(rgb_name("#ff0000"), "red")
        self.assertEqual(rgb_name("#00ff00"), "green")
        self.assertEqual(rgb_name("#0000ff"), "blue")
        self.assertEqual(rgb_name("#2f4f4f"), "dark slate gray")  # first match wins over grey
        self.assertEqual(rgb_name("#00ffff"), "cyan")  # first match wins over aqua
        self.assertEqual(rgb_name("#ff00ff"), "magenta")  # first match wins over fuchsia
        self.assertEqual(rgb_name("#663399"), "rebecca purple")

    def test_rgb_name_unknown_returns_input(self) -> None:
        self.assertEqual(rgb_name("#123456"), "#123456")
        self.assertEqual(rgb_name("custom"), "custom")

    def test_parse_color_rgb_and_hex(self) -> None:
        self.assertEqual(parse_color_rgb("snow"), (255, 250, 250))
        self.assertEqual(parse_color_rgb("Dark Slate Grey"), (47, 79, 79))
        self.assertEqual(parse_color_rgb("RebeccaPurple"), (102, 51, 153))
        self.assertEqual(parse_color_rgb("#f0a"), (255, 0, 170))
        self.assertEqual(parse_color_rgb("#112233"), (0x11, 0x22, 0x33))
        self.assertEqual(color_to_hex("gold"), "#ffd700")

    def test_contrasting_and_darken(self) -> None:
        self.assertEqual(contrasting_color("#ffffff"), "black")
        self.assertEqual(contrasting_color("#ffff00"), "black")
        self.assertEqual(contrasting_color("#000000"), "white")
        self.assertEqual(contrasting_color("#000080"), "white")
        self.assertEqual(darken_color("#ff8040", 50), "#7f4020")
        self.assertGreater(len(X11_COLOR_LIST), 650)


if __name__ == "__main__":
    unittest.main()

