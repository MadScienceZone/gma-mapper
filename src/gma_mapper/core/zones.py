# ########################################################################################
# #  _______  _______  _______                ___          ___    _______                #
# # (  ____ \(       )(  ___  ) Game         /   )        /   )  / ___   )               #
# # | (    \/| () () || (   ) | Master's    / /) |       / /) |  \/   )  |               #
# # | |      | || || || (___) | Assistant  / (_) (_     / (_) (_     /   )               #
# # | | ____ | |(_)| ||  ___  |           (____   _)   (____   _)  _/   /                #
# # | | \_  )| |   | || (   ) | VTT            ) (          ) (   /   _/                 #
# # | (___) || )   ( || )   ( | Mapper         | |   _      | |  (   (__/\               #
# # (_______)|/     \||/     \| Client         (_)  (_)     (_)  \_______/               #
# #                                                                                      #
# ########################################################################################
#
# Creature size, space, reach threat matrices, and token display zoom calculations.
# Ported from bin/gmazones.tcl, bin/mapper.tcl, and man/man3/gma-mapper.3.

from __future__ import annotations

import math
import re
from dataclasses import dataclass
from typing import Any

STANDARD_ZOOM_STEPS: tuple[float, ...] = (
    32.00,
    16.00,
    12.00,
    8.00,
    6.00,
    4.00,
    3.00,
    2.00,
    1.00,
    0.50,
    0.25,
)

_SIZE_PARAMS_RE = re.compile(
    r"^\s*([FDTSMLHGCfdtsmlhgc])(\d+)?(?:->(\d+))?(?:=(\d+))?(?::.*)?\s*$"
)

_FULL_SIZE_CODE_RE = re.compile(
    r"^\s*([fdtsmlhgcFDTSMLHGC])(\d+)?(?:->(\d+))?(?:=(\d+))?(?::(\*)?(.*))?\s*$"
)


@dataclass(frozen=True)
class SizeParams:
    """Parsed creature size parameters in grid-square units."""

    category: str
    natural: int | None = None
    extended: int | None = None
    space: int | None = None

    def to_tcl_list(self) -> list[str | int]:
        """Return 4-element list matching `CreatureSizeParams` in Tcl ('' for omitted fields)."""
        return [
            self.category,
            self.natural if self.natural is not None else "",
            self.extended if self.extended is not None else "",
            self.space if self.space is not None else "",
        ]


@dataclass(frozen=True)
class ParsedSizeCode:
    """Full parsed size code with raw foot distances, default skin flag, and skin comment."""

    category: str
    reach_feet: str
    extended_feet: str
    token_feet: str
    is_default: bool
    comment: str

    def to_tcl_list(self) -> list[Any]:
        return [
            self.category,
            self.reach_feet,
            self.extended_feet,
            self.token_feet,
            self.is_default,
            self.comment,
        ]


@dataclass(frozen=True)
class ReachTemplate:
    """Reach template consisting of natural reach, extended reach, and threat zone matrix."""

    natural: int
    extended: int
    matrix: list[list[int]]

    def to_tcl_list(self) -> list[Any]:
        return [self.natural, self.extended, self.matrix]


@dataclass(frozen=True)
class CreatureAreaInfo:
    """Resolved creature space, natural reach, extended reach, threat matrix, and CustomReach."""

    space: int | float
    natural: int
    extended: int
    matrix: list[list[int]]
    custom_reach: dict[str, Any] | None

    def to_tcl_list(self) -> list[Any]:
        return [
            self.space,
            self.natural,
            self.extended,
            self.matrix,
            self.custom_reach if self.custom_reach is not None else "",
        ]


# Standard Pathfinder/D&D reach matrices from bin/gmazones.tcl
_STANDARD_MATRICES: dict[str, tuple[int, int, list[list[int]]]] = {
    "F": (0, 0, []),
    "f": (0, 0, []),
    "D": (0, 0, []),
    "d": (0, 0, []),
    "T": (0, 0, []),
    "t": (0, 0, []),
    "1": (
        1,
        2,
        [
            [1, 1, 1, 1, 1],
            [1, 2, 2, 2, 1],
            [1, 2, 2, 2, 1],
            [1, 2, 2, 2, 1],
            [1, 1, 1, 1, 1],
        ],
    ),
    "l": (
        1,
        2,
        [
            [1, 1, 1, 1, 1, 1],
            [1, 2, 2, 2, 2, 1],
            [1, 2, 2, 2, 2, 1],
            [1, 2, 2, 2, 2, 1],
            [1, 2, 2, 2, 2, 1],
            [1, 1, 1, 1, 1, 1],
        ],
    ),
    "L": (
        2,
        4,
        [
            [0, 0, 0, 1, 1, 1, 1, 0, 0, 0],
            [0, 1, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 1, 2, 2, 2, 2, 2, 2, 1, 0],
            [1, 1, 2, 2, 2, 2, 2, 2, 1, 1],
            [1, 1, 2, 2, 2, 2, 2, 2, 1, 1],
            [1, 1, 2, 2, 2, 2, 2, 2, 1, 1],
            [1, 1, 2, 2, 2, 2, 2, 2, 1, 1],
            [0, 1, 2, 2, 2, 2, 2, 2, 1, 0],
            [0, 1, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 0, 0, 1, 1, 1, 1, 0, 0, 0],
        ],
    ),
    "h": (
        2,
        4,
        [
            [0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0],
            [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 1, 2, 2, 2, 2, 2, 2, 2, 1, 0],
            [1, 1, 2, 2, 2, 2, 2, 2, 2, 1, 1],
            [1, 1, 2, 2, 2, 2, 2, 2, 2, 1, 1],
            [1, 1, 2, 2, 2, 2, 2, 2, 2, 1, 1],
            [1, 1, 2, 2, 2, 2, 2, 2, 2, 1, 1],
            [1, 1, 2, 2, 2, 2, 2, 2, 2, 1, 1],
            [0, 1, 2, 2, 2, 2, 2, 2, 2, 1, 0],
            [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0],
        ],
    ),
    "H": (
        3,
        6,
        [
            [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0],
            [0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0],
            [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
            [0, 1, 1, 1, 1, 2, 2, 2, 2, 2, 1, 1, 1, 1, 0],
            [0, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 0],
            [1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1],
            [1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1],
            [1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1],
            [1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1],
            [1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1],
            [0, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 0],
            [0, 1, 1, 1, 1, 2, 2, 2, 2, 2, 1, 1, 1, 1, 0],
            [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
            [0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0],
            [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0],
        ],
    ),
    "G": (
        4,
        8,
        [
            [0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0],
            [0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0],
            [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
            [0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 0, 0],
            [0, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 0],
            [0, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 0],
            [1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1],
            [1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1],
            [1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1],
            [1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1],
            [1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1],
            [1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1],
            [0, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 0],
            [0, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 0],
            [0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 0, 0],
            [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
            [0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0],
            [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0],
        ],
    ),
    "g": (
        3,
        6,
        [
            [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0],
            [0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0],
            [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
            [0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 1, 1, 1, 1, 1, 0],
            [0, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 0],
            [1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1],
            [1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1],
            [1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1],
            [1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1],
            [1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1],
            [1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1],
            [0, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 0],
            [0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 1, 1, 1, 1, 1, 0],
            [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
            [0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0],
            [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0],
        ],
    ),
    "C": (
        6,
        12,
        [
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0],
            [0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0],
            [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
            [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
            [0, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 0],
            [1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1],
            [1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1],
            [1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1],
            [1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1],
            [1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1],
            [1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1],
            [1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1],
            [1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1],
            [0, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 0],
            [0, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
            [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
            [0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0],
            [0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        ],
    ),
    "c": (
        4,
        8,
        [
            [0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0],
            [0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0],
            [0, 0, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 0, 0],
            [0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 0],
            [0, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 0],
            [1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1],
            [1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1],
            [1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1],
            [1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1],
            [1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1],
            [1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1],
            [1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1],
            [1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1],
            [0, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 0],
            [0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 0],
            [0, 0, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 0, 0],
            [0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0],
            [0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0],
        ],
    ),
}
# Aliases for 1/S/s/M/m, 2/L, 3/H
for _alias in ("S", "s", "M", "m"):
    _STANDARD_MATRICES[_alias] = _STANDARD_MATRICES["1"]
_STANDARD_MATRICES["2"] = _STANDARD_MATRICES["L"]
_STANDARD_MATRICES["3"] = _STANDARD_MATRICES["H"]


def creature_size_params(size_code: str) -> SizeParams | None:
    """Parse a creature size code `[FDTSMLHGC][nat][->ext][=space][:comment]` into grid units."""
    m = _SIZE_PARAMS_RE.match(str(size_code))
    if not m:
        return None
    category, nat_s, ext_s, sz_s = m.group(1), m.group(2), m.group(3), m.group(4)
    return SizeParams(
        category=category,
        natural=int(nat_s) // 5 if nat_s is not None else None,
        extended=int(ext_s) // 5 if ext_s is not None else None,
        space=int(sz_s) // 5 if sz_s is not None else None,
    )


def CreatureSizeParams(size_code: str) -> list[str | int]:
    """Tcl-compatible `CreatureSizeParams` returning `[category, nat, ext, space]` or `[]`."""
    params = creature_size_params(size_code)
    return params.to_tcl_list() if params is not None else []


def parse_size_code(size_code: str) -> ParsedSizeCode:
    """Parse full size code `[fdtsmlhgc][reach][->extended][=token][:*?comment]` or raise ValueError."""
    m = _FULL_SIZE_CODE_RE.match(str(size_code))
    if not m:
        raise ValueError(f'invalid size code "{size_code}"')
    category, reach, extended, token, def_star, comment = m.groups()
    return ParsedSizeCode(
        category=category,
        reach_feet=reach or "",
        extended_feet=extended or "",
        token_feet=token or "",
        is_default=(def_star == "*"),
        comment=comment or "",
    )


def ParseSizeCode(size_code: str) -> list[Any]:
    """Tcl-compatible `ParseSizeCode`."""
    return parse_size_code(size_code).to_tcl_list()


def skin_comment(size_code: str) -> str:
    """Return skin comment from `size_code`, or `''` if invalid (`SkinComment` in `mapper.tcl`)."""
    try:
        return parse_size_code(size_code).comment
    except ValueError:
        return ""


SkinComment = skin_comment


def skin_is_default(size_code: str) -> bool:
    """Return True if `size_code` has the `:*` default marker (`SkinIsDefault` in `mapper.tcl`)."""
    try:
        return parse_size_code(size_code).is_default
    except ValueError:
        return False


SkinIsDefault = skin_is_default


def skin_size_only(size_code: str) -> str:
    """Strip `:comment` suffix from `size_code` (`SkinSizeOnly` in `mapper.tcl`)."""
    return re.sub(r":.*$", "", str(size_code))


SkinSizeOnly = skin_size_only


def monster_size_value(size: str | int) -> int | float:
    """Return creature occupied space in grid squares (`MonsterSizeValue` in `bin/gmazones.tcl`)."""
    s = str(size)
    params = creature_size_params(s)
    if params is not None:
        if params.space is not None:
            return params.space
        s = params.category
    if s in ("F", "f"):
        return 0.1
    if s in ("D", "d"):
        return 0.2
    if s in ("T", "t"):
        return 0.5
    if s in ("S", "s", "M", "m", "1"):
        return 1
    if s in ("L", "l", "2"):
        return 2
    if s in ("H", "h", "3"):
        return 3
    if s in ("G", "g", "4"):
        return 4
    if s in ("C", "c", "6"):
        return 6
    return 0


MonsterSizeValue = monster_size_value


def reach_matrix(size: str | int) -> ReachTemplate | None:
    """Return the standard `ReachTemplate` for the first character of `size` (`ReachMatrix`)."""
    s = str(size)
    if not s:
        return None
    entry = _STANDARD_MATRICES.get(s[0])
    if entry is None:
        return None
    nat, ext, mat = entry
    return ReachTemplate(natural=nat, extended=ext, matrix=[ list(row) for row in mat ])


def ReachMatrix(size: str | int) -> list[Any]:
    """Tcl-compatible `ReachMatrix` returning `[natural, extended, matrix]` or `[]`."""
    tpl = reach_matrix(size)
    return tpl.to_tcl_list() if tpl is not None else []


def matches_standard_template(
    size: str, natural: int, extended: int
) -> ReachTemplate | None:
    """Return standard `ReachTemplate` if `(size, natural, extended)` matches a standard template."""
    params = creature_size_params(size)
    if params is None:
        return None
    tpl = reach_matrix(size)
    if (
        tpl is not None
        and params.space is None
        and tpl.natural == natural
        and tpl.extended == extended
    ):
        return tpl
    return None


def MatchesStandardTemplate(size: str, natural: int, extended: int) -> list[Any]:
    """Tcl-compatible `MatchesStandardTemplate`."""
    tpl = matches_standard_template(size, natural, extended)
    return tpl.to_tcl_list() if tpl is not None else []


def computed_reach_matrix(size: str, natural: int, reach: int) -> ReachTemplate:
    """Compute or look up the threat and reach zone matrix for `(size, natural, reach)`.

    Matches `ComputedReachMatrix` in `bin/gmazones.tcl`.
    """
    std = matches_standard_template(size, natural, reach)
    if std is not None:
        return std

    size_g = monster_size_value(size)
    matrix_dimension = size_g + max(2 * reach, 2 * natural)
    distance_to_perimeter = max(natural, reach)
    matrix: list[list[int]] = []

    y = 0
    while y < matrix_dimension:
        row: list[int] = []
        x = 0
        while x < matrix_dimension:
            if x < distance_to_perimeter:
                reference_x: int | float = distance_to_perimeter
            elif x >= distance_to_perimeter + size_g:
                reference_x = distance_to_perimeter + size_g - 1
            else:
                reference_x = x

            if y < distance_to_perimeter:
                reference_y: int | float = distance_to_perimeter
            elif y >= distance_to_perimeter + size_g:
                reference_y = distance_to_perimeter + size_g - 1
            else:
                reference_y = y

            distance = int(
                math.sqrt(
                    (5.0 * x - 5.0 * reference_x) ** 2 + (5.0 * y - 5.0 * reference_y) ** 2
                )
                / 5.0
            )
            if distance > reach:
                row.append(0)
            elif distance > natural:
                row.append(1)
            else:
                row.append(2)
            x += 1
        matrix.append(row)
        y += 1

    return ReachTemplate(natural=natural, extended=reach, matrix=matrix)


def ComputedReachMatrix(size: str, natural: int, reach: int) -> list[Any]:
    """Tcl-compatible `ComputedReachMatrix` returning `[natural, reach, matrix]`."""
    return computed_reach_matrix(size, natural, reach).to_tcl_list()


def creature_displayed_size(
    mob: dict[str, Any] | str,
    mob_registry: dict[str, dict[str, Any]] | None = None,
) -> str:
    """Return the effective displayed size code for a creature (`DispSize` if non-empty else `Size`)."""
    mob_dict = mob if isinstance(mob, dict) else (mob_registry or {})[mob]
    disp_size = mob_dict.get("DispSize", "")
    if disp_size:
        return skin_size_only(str(disp_size))
    return skin_size_only(str(mob_dict.get("Size", "")))


CreatureDisplayedSize = creature_displayed_size


def full_creature_area_info(
    mob: dict[str, Any] | str,
    mob_registry: dict[str, dict[str, Any]] | None = None,
) -> CreatureAreaInfo | None:
    """Compute full creature area/reach info from `Size`, `DispSize`, and `CustomReach`.

    Matches `FullCreatureAreaInfo` in `bin/gmazones.tcl`.
    """
    mob_dict = mob if isinstance(mob, dict) else (mob_registry or {})[mob]
    disp_size = creature_displayed_size(mob_dict)
    szparams = creature_size_params(disp_size)
    if szparams is None:
        return None

    custom_reach = mob_dict.get("CustomReach")
    szcode = szparams.category
    sznat = szparams.natural
    szext = szparams.extended
    szsz: int | float | None = szparams.space

    std_tpl = reach_matrix(szcode)
    if std_tpl is None:
        return None
    std_nat, std_ext = std_tpl.natural, std_tpl.extended

    if szsz is None:
        szsz = monster_size_value(szcode)

    has_active_custom = (
        isinstance(custom_reach, dict)
        and len(custom_reach) > 0
        and custom_reach.get("Enabled", True) is not False
    )

    if not has_active_custom:
        if szext is None:
            if sznat is None:
                szext = std_ext
                sznat = std_nat
            else:
                szext = sznat * 2
        elif sznat is None:
            sznat = std_nat
    else:
        assert isinstance(custom_reach, dict)
        sznat = int(custom_reach["Natural"]) // 5
        szext = int(custom_reach["Extended"]) // 5

    comp = computed_reach_matrix(szcode, sznat, szext)
    return CreatureAreaInfo(
        space=szsz,
        natural=sznat,
        extended=szext,
        matrix=comp.matrix,
        custom_reach=custom_reach if isinstance(custom_reach, dict) and custom_reach else None,
    )


def FullCreatureAreaInfo(
    mob: dict[str, Any] | str,
    mob_registry: dict[str, dict[str, Any]] | None = None,
) -> list[Any]:
    """Tcl-compatible `FullCreatureAreaInfo` returning `[space, natural, extended, matrix, custom]` or `[]`."""
    info = full_creature_area_info(mob, mob_registry)
    return info.to_tcl_list() if info is not None else []


def _creature_zoom_relative_to_medium(size: str) -> float:
    params = creature_size_params(size)
    if params is not None:
        if params.space is not None:
            return float(params.space)
        cat = params.category
        if cat in ("f", "F"):
            return 0.1
        if cat in ("d", "D"):
            return 0.2
        if cat in ("t", "T"):
            return 0.5
        if cat in ("s", "S", "m", "M"):
            return 1.0
        if cat in ("l", "L"):
            return 2.0
        if cat in ("h", "H"):
            return 3.0
        if cat in ("g", "G"):
            return 4.0
        if cat in ("c", "C"):
            return 6.0
    return 0.0


def creature_display_zoom(size: str, dispsize: str, zoom: float) -> float:
    """Compute the discrete token image zoom factor for `size` displayed as `dispsize` at map `zoom`.

    Matches `creature_display_zoom` in `bin/mapper.tcl` and `man/man3/gma-mapper.3`.
    """
    base_rel = _creature_zoom_relative_to_medium(size)
    disp_rel = _creature_zoom_relative_to_medium(dispsize)
    if base_rel <= 0 or disp_rel <= 0:
        return 0.0
    newzoom = (zoom / base_rel) * disp_rel
    for defined in STANDARD_ZOOM_STEPS:
        if newzoom >= defined:
            return defined
    return 0.0

