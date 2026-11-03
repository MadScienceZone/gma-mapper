"""Unit tests for gma_mapper.core.minimarkup (port of bin/minimarkup.tcl)."""

from __future__ import annotations

import unittest

from gma_mapper.core.minimarkup import render, render_flat, render_html, strip


class TestMiniMarkup(unittest.TestCase):
    def test_bold_italic_combinations(self) -> None:
        spans = render("Hello **bold** and //italic// and **//both//**!")
        self.assertEqual(
            spans,
            [
                ("normal", "Hello "),
                ("bold", "bold"),
                ("normal", " and "),
                ("italic", "italic"),
                ("normal", " and "),
                ("bold", ""),
                ("bolditalic", "both"),
                ("bold", ""),
                ("normal", "!"),
            ],
        )
        self.assertEqual(strip(spans), "Hello bold and italic and both!")
        self.assertEqual(strip(render_flat("Hello **world**")), "Hello world")

    def test_symbols_and_fractions(self) -> None:
        txt = strip(
            render(
                "+/- --- -- 2x x3 [x] [S] [0][1][2][3][4][5][6][7][8][9] "
                "-5 1/2 1/4 3/4 12_1/2 42_1/4 9_3/4 ^o [c] [R] [<<] [>>] "
                "AE ae ^. [/] [+] [++] ``quote'' `single'"
            )
        )
        self.assertIn("\u00b1", txt)
        self.assertIn("\u2014", txt)
        self.assertIn("\u2013", txt)
        self.assertIn("2\u00d7", txt)
        self.assertIn("\u00d73", txt)
        self.assertIn("\u00b0\u00b9\u00b2\u00b3\u2074\u2075\u2076\u2077\u2078\u2079", txt)
        self.assertIn("\u20125", txt)
        self.assertIn("12\u00bd", txt)
        self.assertIn("42\u00bc", txt)
        self.assertIn("9\u00be", txt)
        self.assertIn("\u201cquote\u201d", txt)

    def test_sections_links_and_lists(self) -> None:
        spans = render("==[Title]== ==(Subtitle)== [[target|Link Text]] [[SimpleLink]]")
        styles = [(s, t) for s, t in spans if t.strip()]
        self.assertEqual(
            styles,
            [
                ("section", "Title"),
                ("subsection", "Subtitle"),
                ("italic", "Link Text"),
                ("italic", "SimpleLink"),
            ],
        )

        list_txt = strip(render("@ First\n@@ Second\n# One\n# Two\n## SubOne"))
        self.assertEqual(list_txt, "\u2022 First \u2022\u2023 Second (1) One (2) Two (2)(1) SubOne")

    def test_escapes_and_html(self) -> None:
        self.assertEqual(strip(render(r"1\.2 \v \e")), "12 | \\")
        self.assertEqual(render_html("Hi **there** & //friends//"), "Hi <b>there</b> &amp; <i>friends</i>")


if __name__ == "__main__":
    unittest.main()
