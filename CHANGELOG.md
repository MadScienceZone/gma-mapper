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

