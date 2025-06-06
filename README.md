![GitHub](https://img.shields.io/github/license/fizban-of-ragnarok/gma-mapper)
# gma-mapper
Fantasy role-playing battle grid map for use with GMA or standalone.

The current implementation of the mapper is in Tcl/Tk, but is showing
a definite need for refactoring at this point. The rest of GMA has already
been moved to Python and Go, so the next major revision of the mapper
is likely to be rewritten in one or both of those languages.

## Introduction
The GMA toolset (see below) includes facilities to support tracking of
initiative in combat and the location of creatures on the game map. If
using the full GMA toolset, each player may run a gma-mapper client. These
are networked together so each person can move their pieces around and see
the same tactical view of the battle.

It may also be used stand-alone to create maps ahead of the game, or for
the GM to display the battle map using a large monitor or projector, without
the need for any networking at all.

## GMA?
This is part of a larger project called GMA (Game Master's Assistant)
which is a suite of tools to facilitate the play of table-top fantasy
role-playing games. It provides a GM toolset for planning encounters,
tracking character state, and running encounters in a comprehensive way.
This includes a multi-user interactive tactical battle map where players
can move their tokens around the map, initiative is managed automatically,
etc.

While we intend to open source GMA **later in ~~2023 2024~~ 2025**, it's not quite ready for
general use (mostly because it needs to be generalized more to be playable
on multiple game systems and less tied to the author's game group).
The manual describing the full GMA product may be downloaded 
[here](https://www.madscience.zone/gma/gma.pdf) (PDF, 61Mb).

In the mean time, we're moving individual parts of GMA (specifically the map
server and clients) into their own repositories. This is the client repository.

## Documentation
In the repository you will find manpages which document the usage of the
client itself, the file format used for storage of map data, and the network
protocol used when networked.

The [GMA Game Master's Guide](https://www.madscience.zone/gma/gma.pdf) includes
full tutorials describing how to use the mapper (in addition to the rest of GMA).
Players should refer to Appendices G, H, and I, while the GM would want to read Chapters 4, 5, and
possibly 8–10.

### Standalone Note
In the documentation, the invocation of the `mapper` client is shown as
`gma mapper ...` which only makes sense if using the full GMA toolset. The
`gma` script merely sets up some convenient environment variables and allows
you to avoid having to have all the bits of GMA in your `$PATH`. When using
`mapper` on its own, merely execute `bin/mapper.tcl` as a command by having
it in your `$PATH` or using the Tcl/Tk `wish` command (e.g. `wish mapper.tcl`).

### Integrated Usage
If using with the full GMA toolset, the `gma mapper` command will use the environment
variable `GMA_MAPPER` to find the top-level directory of where you cloned this
repository (thus `$GMA_MAPPER/bin/mapper.tcl` is the executable mapper script).
You may need to set `GMA_TCLSH` to point to your `tclsh` interpreter if the `gma`
script can't find it on its own.

# Versioning
Although intended for use with the GMA software suite, the gma-mapper tool has an independent version number
from that project.

## Other Software
Includes Paul Walton's scrollable frame code `sframe.tcl`, available at [http://wiki.tcl.tk/9223]().

Also uses a modified version of [Silk Icons](http://www.famfamfam.com/lab/icons/silk/).

## Game System Neutral
The GMA software and the gma-mapper client in this repository are intended to be game-system-neutral.
They are not written specifically for, nor intended specifically for use with, the oldest fantasy role-playing game,
nor do they rely upon OGL-licensed intellectual property from Wizards of the Coast. Where any game system 
was in mind for these tools, it was the Pathfinder role-playing game system from Paizo, Inc.
