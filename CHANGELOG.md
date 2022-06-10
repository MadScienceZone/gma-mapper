Game Master's Assistant / Mapper Client
Release Notes
Version UNNAMED * Sunday, 26th September, 2021

Represents:
 * Supported GMA Mapper Version: 4.x.x      <!-- @@##@@ -->
 * Supported GMA Mapper File Format: 20	      <!-- @@##@@ -->
 * Supported GMA Mapper Protocol: 400         <!-- @@##@@ -->

# CURRENT
This version represents a complete rewrite of the mapper client.
A rewrite has been needed for some time to clean up the code and
overall code structure. I decided this time to do the rewrite by
porting the client to Go instead of keeping it in Tcl/Tk or porting
it to Python. This was based on our experience to date with the mapper
and other tools, and the fact that the mapper, more than any other tool,
should be as simple to install and use as possible, in addition to being
fast and robust. By compiling ready-to-run clients in Go, we can deliver
a binary execuatble (say, `mapper.exe` on Windows) which just works without
needing to install and tweak numerous external dependencies.

## Enhancements
* This version moves the mapper to protocol 400, which drops the old-style
protocol using Tcl lists for serialization in favor of JSON.
* This version also updates the file formats for `.map` files to format 20,
which drops the older multi-line key-value TCL-based file format for a more
structured one based on JSON.

# 3.42.2
## Enhancements
Improved styling of die-roll results by allowing user control over coloring and number of titles attached to the start of a die roll.

A die roll specification may have an optional title, followed by an equals sign (=), before the start of the die-roll spec proper. This is returned as-is by the server and clients may display it along with the detailed results. Previously, clients treated this as plain text without further consideration.

Starting with version 3.42.2, the gma-mapper client allows for some additional formatting controls to be embedded in the title string.

First, multiple titles may be given, separated from one another by '`‖`' characters (codepoint U+2016). Each of these titles are displayed in its own colored box. The color may be set by the user as part of their client's style configuration settings (`fg_title` sets the foreground color.) For example, "`goblin‖claw attack`".

Second, within each of the (possibly multiple) titles, the title text may be followed by the character '`≡`' (codepoint U+2261) and a color specification (e.g., "`goblin≡blue`" or "`goblin≡#8888ff`"). This sets an arbitrary foreground color. By default, the background will be the same color as the foreground, but darkened to 40% of the foreground's color intensity. However, adding a second color specification will set an arbitrary background color (e.g., "`goblin≡red≡yellow`").

# 3.42.1
## Enhancements
Improved styling of die-roll results.

# 3.42.0
## Enhancements
Added subtotals to die-roll results.

# 3.41.0
## Enhancements
When reporting die rolls which are critical confirmation attempts, the die icon
is reversed in color so that roll is easily distinguished from regular attack
and other rolls.

## Changes
Changed icon directory path from `lib/SoftwareAlchemy...` to `lib/MadScienceZone/...`
to reflect our change in domain name.

# 3.40.10
Moved out of the main GMA repository into its own.

# Legacy
The GMA software has a long, convoluted history since its humble beginnings in
the early 1990s as a C++ program running on an old Sun 2/120 server displaying
initiative events on an ASCII terminal. It was eventually re-written in Perl
and Tcl as its features evolved, picking up a Tcl/Tk GUI along the way.

More recently, it was re-implemented again with significant improvements across
the board, this time in Python (although notably the mapper client is still in
Tcl/Tk while the author swears that someday he'll recode it in Python, but is
still maintaining and evolving the Tcl/Tk version anyway for the sake of
expediency).  

