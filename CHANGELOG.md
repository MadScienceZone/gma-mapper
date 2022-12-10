# Game Master's Assistant / Mapper Client
# Release Notes
## Current Version Information
 * Supported GMA Mapper Version: 4.0.3      <!-- @@##@@ -->
 * Supported GMA Mapper File Format: 20	     <!-- @@##@@ -->
 * Supported GMA Mapper Protocol: 400        <!-- @@##@@ -->
 * Effective Date: 09-Dec-2022               <!-- @@##@@ -->

# 4.0.0
## Changes
* Legion. The way objects are stored and referenced inside the mapper is fundamentally different now.
* Save file format updated to version 20. This is a *completely* different format, which should be easier to parse and hand-edit than previously had been the case.
   * Rather than an unordered collection of individual object attributes, each creature or map element is represented together as a record, which is JSON-formatted.
   * The mapper still recognizes the previous file format (version 17) and will read version 17 files but will write new files in version 20 format.
* Die-roll preset file format updated to version 2. This is a *completely* different format, similar to the new map file format.
   * Rather than the file containing lines of TCL lists with data, the file now is a sequence of records which a JSON-encoded.
   * The mapper still recognizes the previous file format (version 1) and will read version 1 files but will write new files in version 2 format.
* All client/server interaction code has been re-written. It now supports server protocol 400, which is a total departure from the previous protocol formats.
   * Instead of each server command being a TCL list of parameters, the parameters are now sent as JSON-encoded objects.
   * A legacy compatibility mode is included, which allows the mapper to connect to an older server running protocol version 333. The mapper will translate incoming and outgoing data from its internal JSON-based format to the legacy protocol 333 when talking to an old server.

## Added
* You can now right-click on a creature token or a grid square to calculate the distance from that point to all creature tokens.
  * If measuring from a grid, it measures from the center of the grid to the center of each creature and to the nearest grid center occupied by each creature.
  * If measuring from a creature, it measures from the center of the creature to the center of each other creature as well as finding the shortest distance between *any* grid occupied by the referenced creature to *any* grid occupied by each target.

# 3.44.0
## Enhancements
* Enlarged arrowheads for line objects so they're more visible.

# 3.43.0
## Enhancements
* Added C80 size code for colossal things with space 80 feet and reach 80 feet.

# 3.42.7
## Fixes
* Changes creature token labels to have a background color behind them (which matches
the creature's threat zone color) so token label text won't get lost in the map image or
canvas color. Fixes [Issue #34](https://github.com/MadScienceZone/gma-mapper/issues/34).

# 3.42.6
## Fixes
* Corrected Unicode encoding (makes UTF-8 always assumed; this corrects a problem seen on Windows platforms where the default encoding was incompatible, which messed up die-roll formatting).
* Now clears the status display on startup when not authenticating to a server.

# 3.42.5
## Fixes
Cleaned up display of die-roll presets and status displays.

# 3.42.4
## Enhancements
Improved display of creature status. Removed the confusing aspect that hovering
the mouse anywhere in the threat zone put the creature's stats at the top of the
window (since in combat many creatures are in overlapping threat zones). Now,
the status is implemented as a "tooltip" when hovering over the creature token
itself, and contains greater detail about the conditions in effect for the creature.

Changed the "toggle reach" menu to "cycle reach". It now cycles between three different
reach modes: normal, reach, and extended. The latter is an extended threat zone
that includes the reach area but also the adjacent spaces.

Now supports mapper protocol version 333.

# 3.42.3
## Enhancements
Improved styling of die-roll results is now an opt-in feature for clients.
Added code to the client to tell the server that it supports that feature.
Adjusted display style of die roll result number so the background doesn't carry over into the space between that and the name of the person sending the die roll.


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

