# Game Master's Assistant / Mapper Client

# Release Notes

## Current Version Information
 * This Package Version: 4.35.2-alpha.1          <!-- @@##@@ -->
 * Effective Date: 05-Dec-2025               <!-- @@##@@ -->

## Compatibility
 * GMA Core API Library Version: 6.39 <!-- @@##@@ -->
 * GMA Mapper File Format: 23	     <!-- @@##@@ -->
 * GMA Mapper Protocol: 421        <!-- @@##@@ -->
 * GMA Mapper Preferences File Format: 11 <!-- @@##@@ -->

## DEPRECATION NOTICE
The support for old server protocols (<400) and map file formats (<20) will be dropped in the near future.
If you are still running an ancient version of the server and clients, you need to upgrade to the latest
versions.

# 4.35.2 (unreleased)
## Fixes
 * Changes "disable audio" preferences wording to "mute"
 * Makes spell area of effect zones easier to see when they overlap each other by making them randomly shift position slightly so they'll expose underlying spells (and the visual appearance of the animated areas helps make it apparent they're not part of the static landscape as well).
 * Corrects a bug in the die-roller modifiers which caused stored variables to be forgotten when the server refreshed the state of the preset list (e.g., when editing the presets), so that variables which had been enabled (and still showed as checked on the display) acted as though they weren't.
 * Adds keybindings to more menu items.
 * Fixes error with prompting for which characters you control.

# 4.35.1
## Fixes
 * The audio cues didn't work on Windows. This adds support for the Tcl Windows API Extension (twapi) which allows that to work on that platform now.
 * Now supports protocol 421.
 * Pre-emptively adds an option to the preferences file to disable non-UI sound effects, but we aren't using that yet since that feature is not yet implemented.
 * Fixes ability to restart the mapper on Windows (and possibly other platforms)
 * Start-up scripts added for MagicSplat Tcl on Windows.

# 4.35
## Enhancements
 * Now supports protocol 420.
 * Supports specifying explicitly what character(s) you are playing even if you log in with an arbitrary username that doesn't match any character name on the map. This also means you can indicate that you're playing multiple characters if you're covering for someone.
 * Provides audio and visual cues when your turn in combat is coming up.
 * Now allows you to start with the die roller in "read only" mode as a preferences setting or via `--no-dice` command-line option.
 * New preferences options to opt in/out of new features.
# 4.34.1
## Fixes
 * Corrected bug with modifier enable checkbuttons not tracking the internal state of the modifiers.
 * Replaced scrolled frame code with a faster implementation.
## Updates
 * Added informatin to the gma-mapper-protocol(7) documentation in anticipation of future capabilities.

# 4.34
## Enhancement
 * Adds keybindings for most toolbar/menu commands, allowing more rapid work when doing repetitive tasks in the mapper, when hitting a key may be more convenient than clicking through the menus or using the toolbar.
 * Holding SHIFT while using the up, down, left, right, h, j, k, or l keys while using the move tool now moves the object by 10 pixels at a time instead of the normal 1 pixel (the unshifted behavior).
## Fixes
 * Corrected a typo in the source of the gma-mapper-protocol(7) manpage.

# 4.33.1
## Fixes
 * Corrects cryptographic signature on release files.

# 4.33
## Enhancement
 * Chat messages may now be "pinned" in a priority window.

# 4.32
## Enhancement
 * Users may request that the GM update their current hit point totals by filling out a dialog box in their mapper with their current maximum hit points, lethal, and nonlethal wounds.
 * Users may request that temporary hit points be allocated to their characters by filling out a dialog box with that information.
    * This may be done *en masse* for multiple characters at once.

# 4.31
## Enhancement
 * Supports server protocol 418.
 * Now reports temporary hit points in health bars as a blue zone between permanent hit points (green) and non-lethal damage (yellow). This requires a server running protocol verion 418 and GM client which supplies temporary hit point data.
 * Display of tables in the "edit presets" dialog does a better job of showing ranges of values in the left column.

# 4.30.2
## Fixes
 * Corrected an error that sometimes occurs when editing die-roll presets loaded from the server.
 * Updates to the text of the server protocol document to note encoding formats for die roll preset object types.

# 4.30.1
## Fixes
 * Die roll coloring now also includes DC-based success/failure determination (red if DC is missed, green if DC is met or exceeded, but still red if natural 1 or green if nat 20 if that also applies to the same die roll since that takes precedence)

# 4.30
## Enhancement
 * Now shows visually when a die roll is known to be a success or failure. Previously, this was already indicated in the detailed results that followed the die roll result number, but it was easy to miss if just quickly glancing at the total number. For example, if looking at the result of an attack roll you might notice that the attack roll exceeded an opponent's AC, but might not have noticed that the roll itself was a natural 1, even though if you looked just a little more to the right there was a prominent "MISS" tag displayed. Now the die icon color changes to indicate this.
   * This follows the "success" and "fail" detail tag types, which indicates:
      * Rolls with the `|c` option (e.g. attack rolls) which fail on natural 1 and succeed on natural 20 rolls.
      * Rolls with the `|sf` option (e.g. saving throws) which fail on natural 1 and succeed on natural 20 rolls.
      * Percentile rolls (e.g. "`42%`") based on whether the value rolled indicated success or failure.
 * Added dict preset data format to protocol specification.

## Fixes
 * Fixes display of custom die-roll preset data.
 * Small updates to documentation.

# 4.29.1
## Fixes
 * Corrected packaging error in release zip/tar files.

# 4.29
## Enhancements
 * Implements server protocol 417, which is documented here in manpage gma-mapper-procotol(7).
 * Adds GMA markup formatting codes to chat messages. (Requires server 5.27.0 or later.)
 * Adds random lookup tables to the die-roll preset system. This allows you to define a lookup table based on a random die roll where a random outcome is to be determined. Once defined, you can activate the table by clicking its button in the die roller or typing `#` followed by the table name as part of a larger die-roll expression to roll the dice and automatically look up, and report out, the resulting action according to the table.
 * Implements system-wide die-roll presets, modifiers, and lookup tables. The GM may now define these globally for all users to access (read-only) instead of being required to define their own separate copies of the same modifiers when there are common modifiers that everyone needs to use in the campaign.
## Fixes
 * Introduced some new streamlined code that will eventually form the basis for refactoring out some older cruft (at the moment it's redundantly implementing some new features with newer, better code but will eventually supersede the older stuff).

# 4.28
## Enhancements
 * Players may now request new timers to be added to the set of events that are being tracked on the game calendar by the GM.
 * Die rolls which result in multiple results are now visually grouped together in the die-roll output display.
 * Implements server protocol 416.

# 4.27.2
## Fixes
 * Bug fixes to colorization of die-roll modifier labels.

# 4.27.1
## Fixes
 * Bug fixes to colorization of die-roll modifier labels.

# 4.27 
## Enhancements
 * Die rolls are now sent with `RequestID` fields to identify which results that come back from the server relate to which rolls.
 * When a die roll is made which has 3 or more results (such as with the `|repeat` option), the mapper will print a line after the results which include the basic statistics from that result set (population size, population mean, standard deviation, median, mode, and sum).
 * Adds a new die roller style `stats` for printing the stats of a die roll set.
 * Die roll labels may now include custom colors using the same syntax as the up-front die-roll title string does. This allows a foreground or foreground and background color to be specified by name or RGB hex value. We recommend using these sparingly as an ad-hoc addition to the style definitions to make certain special modifiers stand out in large multi-roll sets, saving time hunting for them by making them visually stand out from the others.

# 4.26
## Enhancements
 * Implements protocol 415, which provides a slightly more secure challenge/response exchange (backward compatible with previous versions).
## Fixes
 * Moves manual page entries to have names starting with `gma` as part of the overall GMA-project-wide effort to clean up the footprint of GMA tools that might clash with names of other packages installed on a system.

# 4.25
## Adds
 * Supports die-roll option `|total` and displays the results accordingly.
## Fixes
 * Repositions some dialog boxes to be on top of the main window instead of random locations possibly on other displays.

# 4.24.5
## Fixes
 * Corrects problem with add player/monster dialog so that it now allows you to add a token that has multiple skins, possibly at different sizes.
 * Improves image retrieval from server. Now it will stop asking entirely about images that the server indicated were available but we got a 404 error trying to fetch them. Menu option available to clear that status so another attempt can be made for any such images.
 * Protection added around updating progress meters.
 * Moved some diagnostic messages from level 0 to level 1, so they only show in the diagnostic window if debugging information was requested.
 * Fixes [Issue #212](https://github.com/MadScienceZone/gma-mapper/issues/212) and [Issue #220](https://github.com/MadScienceZone/gma-mapper/issues/220).

# 4.24.4
## Fixes
 * Corrects requests for delegate die-roll presets.
 * Corrects standard threatened space templates.
 
# 4.24.3
## Fixes
 * Corrects color name parsing error in die-roll preset editor.

# 4.24.2
## Fixes
 * Corrects image request back-off time intervals to avoid spamming the server faster than you can download images.

# 4.24.1
## Fixes
 * Corrects a bug in resolving the location of files in the mapper's cache on Windows filesystems.

# 4.24
## Enhancements
 * Better highlighting for selection in the diagnostic window for when selecting text to copy and paste.
 * Added menu item `Tools > Save diagnostic messages as...` to save entire contents of the diagnostic window to a text file.
 * Now supports mapper protocol 414.
 * Previously, the display of timers defaulted to only show timers specifically targetted at the PC named the same as the login name on the mapper client. This can be changed via the `View > Show timers > ...` menu. Now, the default setting (no timers, my timers, or all timers) appears in the preferences editor, so once set there that becomes the permanent default for that client.
 * Added support for the new ability for the server to reject client connections after the authentication stage, so the client will gracefully inform the user of why their session has been terminated by the server.
## Fixes
 * Corrects the way the initiative tracker window is resized when timers are added or removed.
 * The analog clock display is slightly smaller. It didn't need to be that big and we needed more room.

# 4.23.2
## Fixes
 * Now honors server requests to dismiss all displayed timers.
 * Fixes cosmetic issues where timers overcrowded the initiative list.

# 4.23.1
## Fixes
 * Corrects cosmetic issue with menus.
 * Removes deprecated "connect to" menu.

# 4.23
## Enhancements
 * Adds display of event timers on the initiative clock window. The user can select whether to display only timers which involve their character (which requires their login name to match their character name), all timers, or none.
 * Supports protocol 413.
   * Includes acceptance of protocol commands for retrieving core data from the server, although those remain unused at this time.

# 4.22.3
## Fixes
 * Corrects error when updating menus.

# 4.22.2
## Fixes
 * Corrects error in GUI scaling when there is no `scaling` value in the preferences file.
 * Corrects combat clock animation (was disabled in recent versions).

# 4.22.1
## Fixes
 * Mitigates the scrolled frame scrollbar issue (it didn't recalculate scrollbar placement when the internal managed contents change).
 * Mitigates the issue of dialogs and widgets having bad aspect ratios and sizes on high-res displays by providing a "Visual scaling factor" preferences setting. 
   * Defaults to 1.0, but increase to 2.0 or 3.0 for high res displays (e.g., 4K).

# 4.22
## Enhancements
 * Implements server protocol 412
 * Adds the capability for users to designate other users as delegates to manage their die rolls for them. This allows the delegate to edit the other user's die-roll presets and to roll dice and send chat messages on behalf of the other user. It does not allow them to fully impersonate the other user and they won't receive private messages directed to that user. It just allows for users to help one another roll dice.
 * Adds die-roll preset grouping to better organize long lists of presets.
 * Adds the capability to change the grid snap factor for creature tokens, allowing them to locate in areas where the map doesn't align to the 5-foot grid points.
 * The preferences option to show timestamps in chat messages is now on by default.
 * The preferences option to limit chat message history now defaults to 500 messages (was unlimited).
 * "Cycle" menus (e.g., cycle through grid snap sizes) now use cascading menus to allow direct setting of the desired value.
 * Includes some (currently unused) code to allow for creature tokens to snap to fractional grid points.
 * Adds `--list-profiles` (`-L`) option to list all the profile names defined in the current profile file. These may then be used with the `--select` option to start the mapper to connect to that profile without making it the new default for all invocations.
 * Adds `flash_updates` to preferences list (bumping the file format version to 6) to allow users to decide if they want map elements to flash briefly when their attributes are updated.
 * Moves unparsable die-roll preset names to their own tab on the preset editor dialog.


## Fixes
 * Improvements to several internal routines including how menus are updated for dark mode.
 * Improved indicators on menus for current mode of play.
 * Added better messaging to display in case the mapper is unable to re-launch itself.
 * Corrected some bugs with the stipple fill patterns.
 * Improved error message wording when attempting an unauthorized operation.
 * Reinstated "default-on" flag for die-roll modifiers (more debugging required here to ensure that doens't make the flag keep turning itself on during play).

# 4.21
## Enancements
 * Protocol 411
   * Adds timestamps to chat messages and die-roll results, along with preferences settings to allow users to choose whether, and how, to display them.
## Fixes
 * Fixes [Issue #185](https://github.com/MadScienceZone/gma-mapper/issues/185). When the mapper is set to follow the current combatant, the map should keep scrolling as needed to keep that combatant in view even as that token is moved.
 * Fixes [Issue #179](https://github.com/MadScienceZone/gma-mapper/issues/179). When a creature token is hidden, it is still revealed in the distance-measuring tool.

# 4.20.1
## Fixes
 * Improved and debugged client-side handling of background socket reading and redirect commands from the server.

# 4.20
## Fixes
 * Bug that misinterpreted `null` in dict-value JSON payloads (e.g., `OA` commands).
## Enhancements
 * Protocol 410
   * Adds `REDIRECT` command to protocol, allowing the server administrator to temporarily direct clients to an alternate server.
   * Adds server-side configuration extension to `WORLD` command to allow server admin/GM to set a limited number of client preferences, overriding local user preferences.
      * `MkdirPath`, `SCPDestination`, `ServerHostname` GM settings for uploading content to the server.
      * `ImageBaseURL` setting which tells clients where to find images and maps on the server.
      * `ModuleCode` setting which specifies the adventure module in play.

# 4.19.2
## Fixes
 * File I/O module was missing increment to file format version and support for `Stipple` and `PolyGM` attributes.

# 4.19.1
## Fixes
 * Bug that prevented loading map files which don't have expected fields (i.e., if the old file was created before a protocol change).
 * Fixes color of menu checkmarks in dark mode.

# 4.19
## Enhancements
 * Adds fill patterns for drawn objects. Stipple patterns are included for 12%, 25%, 50%, and 75% area shading, and this set can be added to later.
 * Now supports protocol 409.
 * Menus are more dynamic now, indicating more clearly what the current state of the mapper controls are.

# 4.18.2
## Fixes
 * The condition markers weren't always easy to see against the creature token background. Added contrasting white or black border around the markers to resolve this.

# 4.18.1
## Fixes
 * Improves language in `Play -> Connect to...` menu.
 * Documents `// notice:` in protocol spec.
 * Fixes typos in manpages.

# 4.18
## Enhancements
 * Adds progress bars for long-running operations, especially those done at start-up, so you know when the mapper is ready to use.
 * Adds a server response time testing tool.

# 4.17.3
## Fixes
 * Adds warning message to the `Play` -> `Connect to ...` menu which advises users that this method of switching servers is not guaranteed to work correctly, and suggests methods which are reliable.
 * Fixes bug where the distance tracer arrows didn't get removed from the map if the distance calculator window was closed other than by clicking the `OK` button.
## Enhancements
 * Adds server notice alert boxes.
 * Adds option under `Edit` -> `Preferences` -> `Tools` to run `curl` in insecure mode. Select this if your `curl` is failing due to being unable to verify SSL certificates and you're willing to take the security risk of reading files from an unverified server. This should only be used as a stop-gap solution and only if you fully understand the risks involved.

# 4.17.2
## Fixes
 * Corrects bug in error message reporting for duplicate AC commands from server.
 * Mitigates bug with die-roll modifiers getting turned on; now there is no setting for "on by default" in the stored presets; presets will turn off any time the presets are reloaded from the server.
 * Fixed error with die-roll preset grouping option that incorrectly put the parens around the title string as well as the die roll expression.
## Enhancements
 * Changes die-roll color button icons.

# 4.17.1
## Fixes
 * Removed debugging statement
 * Fixed bug in auto-update code (failed to correctly print error messages if update failed)

# 4.17
## Enhancements
 * Supports server protocol version 408.
 * Now supports enhanced size codes for creatures (including skin comment tags).
 * Adds `File`->`Restart Mapper` menu option to restart the mapper client.
 * More intelligently handles creation of polymorph context menu (only enables when a creature can actually polymorph, uses better descriptions instead of numbers)

## Deprecations
 * Removed old `-c` / `--character` command-line option.

# 4.16.4
## Fixes
 * Cleaned up the way conditions are automatically calculated based on lethal and nonlethal damage.

# 4.16.3
## Fixes
 * Corrects software logic bug.

# 4.16.2
* Does not exist (error in release process)

# 4.16.1
## Fixes
 * Corrects bug in the `ChangeRealSize` procedure.

# 4.16
## Adds
 * Ability to specify internal-only prefix "*name*`_`" to creature nameplates.

# 4.15.2
## Fixes
 * Corrects a bug where loading an animated image via loading a `.map` file (as opposed to an *ad-hoc* load by placing a token or being commanded to place the token by the server) caused the frame list to be reset to null.

# 4.15.1
## Fixes
 * Corrects a bug where creature nameplate colors don't change when the creature's color changes.

# 4.15
## Adds
 * View -> Scroll to Follow Combatants menu option. When this is checked during combat, the map will automatically scroll as needed when each combatant's turn starts so that creature is visible on the map.
 * Adds option to force hand-drawn objects to the top of the display stacking order.
 * About dialog now displays the server's port number.

## Fixes
 * Corrects color of menu checkbox items.

# 4.14.1
## Fixes
 * Corrects an issue where combat threat zone drawing fails if a creature's coordinates were sent as a float value (e.g., 123.0) instead of an integer (e.g., 123).

# 4.14
## Adds
 * Support for animated images.
 * Now supports mapper file format 22.
 * Now supports preferences file format 3.
 * Now supports server protocol version 407.
 * Changed the back-end socket reading code used to get messages from the server. This should mitigate the issue we've seen where getting too much data from the server caused the mapper to fail to process it all, resulting in missing chat messages and map contents.
 * Added ability damage condition marker to the built-in status marker set.


## Fixes
 * Corrects UI cosmetic annoyances on the Mac platform, especially when in dark mode.
 * Fixes a bug which caused an exception when advancing the initiative clock under certain circumstances. ([Issue #127](https://github.com/MadScienceZone/gma-mapper/issues/127))
 * Corrects condition tooltip text that conflicted with the core Pathfinder rules.
 * Corrects issue where not all conditions (i.e., those dynamically computed by the mapper) were displayed in the tooltip. ([Issue #12](https://github.com/MadScienceZone/gma-mapper/issues/12)).
 * Adds braces around conditional expressions, in the hopes that this gives a tiny optimization improvement to the program, since the Tcl bytecode compiler will parse that more efficiently.
 * Wrapped float font size value in `int()` because Tk was unhappy with non-integer font sizes there.
 * Fixed a bug in the code that draws spell areas of effect.


# 4.13.1
## Fixes
This patch attempts to fix an occasional problem whereby the mapper client triggers a set of 
"too many nested evaluations (infinite loop?)" exceptions. On the theory that the real issue here is a burst
of too many operations being given at one time to the tk event loop, it's just exceeding its capacity and triggering
that error (as opposed to errant recursion in the mapper code). To address this, we added a number of `update` commands
throughout the functions involved in those operations to let Tk catch its breath enough along the way. So far this
does appear to have stopped those exeptions from occurring.

# 4.13
## Adds
 * Controls to remove and update cached data.
 * Menu option to move the mapper view to any arbitrary map location by label (e.g., "AA42").

# 4.12
## Adds
 * Now provides a preferences setting to select whether to display the main menu as an application menu bar or on a menu button. (Previously it was only on a menu button).

# 4.11.1
## Adds
 * Warning dialog if the mapper is using a legacy `mapper.conf` file which is now deprecated.

## Fixes
 * Corrects error in detecting and loading the legacy `mapper.conf` file on startup if no `preferences.json` file is present.

# 4.11
 * Adds a command-line option `--recursionlimit` *n* which sets the runtime recursion limit to the given value. It will then be an error if we nest function calls more than *n* calls deep. The default is 1000. This is to help debug the issue that occasionally pops up where we exceed the default limit.
 * Adds "Check for Updates" menu option which queries github for the latest version of gma-mapper as well as looking at what the GM set on the server configuration. This allows users to upgrade manually independent of their GM offering downloads or recommending a particular version.
 * Adds server connection info to the "About Mapper" dialog.

# 4.10.1
## Fixes
 * Corrects several bugs found in the new code that renders creature tokens at various sizes and with various arbitrary threat zones.

# 4.10
## Enhancements
* Now implements server protocol 406
* Removes `Area` attribute from creatures (affects AC and PS commands and saved files).
* Adds `CustomReach` attribute to creatures (affects AC and PS commands and saved files).
* Adds `DispSize` attribute to creatures (affects AC and PS commands and saved files).
* File format updated to 21 to reflect the new attributes.
* Creature `Size` attribute syntax expanded to generalize specifying creature size, space, and reach in a single attribute.
* Changed context menu from "cycle reach" to an expanded submenu allowing full customization of reach zones.
* Added highlighting to reach menu to show the creature's current reach zones.
* Removed redundant items from the context menu, that weren't related to the context of operations involving a particular square of the map, to keep the menu as short as possible
.
* `Scroll to Visible Objects` already exists in the View menu.
* `Scroll Others' Views to Match Mine` also already exists in the View menu.
* `Refresh Display` already exists in the View menu too.
* `About Mapper...` already exists in the Help menu.
* Scales creature token image when changing size on the map. Works better if `rendersizes` makes additional sizes for the token.
## Fixes
* Corrected internal encoding of complex attribute types.
* Corrected a bug where, after removing creatures which were in the selection list, the selection list continued to point to the now-nonexistent creature.
* Fixed layout of the dialog to add creatures to the map.
## Comments
The move (across the board with GMA components) to deprecate the `Area` attribute from creatures has been a long time coming, but with the addition of fully customizable reach zones, it's no
w fully redundant and needs to be removed now.
Originally, creatures (the `Monster` object class in the GMA Core code) have a `size`, `space`, and `reach` attribute corresponding to the monster stats as published in the various bestiary
volumes (d20, Pathfinder, etc.). The mapper (and client/server protocol) had corresponding `Size` and `Area` attributes with `Size` indicating creature size (aka `space`) and threat zone (ak
a `reach`), which is normally doubled for extended reach when using a reach weapon.

The `Size` and `Area` fields were integers indicating distances in 5' grid-square units but this was later expanded to allow standard size categories such as `M` and `L` to make adding creat
ures manually on the map easier. However, since that single code indicates both space and reach for standard creatures, even the dialog box to add creatures to the map was wired to automatic
ally populate `Area` with the value you typed for `Size`, exposing the essential redundancy of having both fields, other than the occasional special case.

As time went on we added some bespoke size categories for those special cases, like `L0` for swarms (large creature with 10' space but 0' reach), which meant more and more the `Monster.size`
field and `Size` protocol field could drive the other stats but at the expense of adding a bunch of special cases to the size list.

This also bled into some places in the code where `Size` and `Area` could be used interchangeably when they shouldn't be.

Now we have fully customizable creature size and threat zones. To support entry of creatures with arbitrary sizes, the `Monster.size` attribute (and correspondingly the `Size` protocol field) has been expanded to allow specification of all those values in a way that is backward compatible with the bespoke codes like `L0`, `M20`, etc., so they are no longer special cases. At this point, the space and reach of creatures is fully specified in the size field, so there's no justification to keep the `Area` field anymore. In the `Monster` class in GMA Core, it is now deprecated to set `Monster.space` and `Monster.reach`. Just set `Monster.size` and the `space` and `reach` object attributes will be auto-filled accordingly.

# 4.9.3
## Fixes
 * Corrected bug that forced `RenderSomeone` function to recurse too deeply, causing a runtime exception.

# 4.9.2
## Fixes
 * Corrected a bug in the error message produced when the server tries to set a nonexistent attribute in an object.

# 4.9.1
## Fixes
 * Expanded the entry widgets for the URL fields in the server preferences setting tab. They were too short for the URLs we expect to go there, and there was room on the form to let them be bigger.

# 4.9
## Enhancements
 * Adds an option in the user preferences to turn on/off colorized die-roll titles
 * Adds `--preferences` command-line option to switch between preference files.

# 4.8.1
## Fixes
 * The mapper didn't lock map objects when saving.
 * The debug window was missing the application icon.

# 4.8
## Enhancements
 * Now supports protocol 405.
## Fixes
 * Corrects enabling/disabling of die-roll modifier option checkbuttons.
 * Fixes bug which lost custom images from creature tokens when saving maps to disk.
 * Corrects a bug with tracking hidden creatures.

# 4.7
## Enhancements
 * Now supports protocol 404
 * Supports semi-transparent creature token images for hidden creatures and for certain status conditions.
## Fixes
 * Mitigated tooltip library bug for tip strings that begin with a hyphen.

# 4.6.1 
## Enhancements
 * Created INFO level of debugging output
 * Changed appearance of upgrade process to be less jittery
 * Added scrolling frames to die-roll preset editor

# 4.6
## Enhancements
 * Updated initiative display with icons to show status (current actor, held or readied action, dying) to make the status more obvious despite customizing colors or difficulty differentiating colors on-screen.
 * Adjusted the default color styles for the initiative display.
 * Documented the way modifiers and variables are stored as die-roll preset data in the protocol specificaion **mapper-protocol**(7).
## Fixes
 * Corrected error which caused the GM's mapper to fail to read the metadata of cached map files, forcing them to be re-uploaded to the server when they didn't need to be.
 * Worked around issue with the tklib tooltip implementation which caused a bug if a die-roll preset description started with a hyphen.
## Other Changes
 * Added deprecation notice in **style.conf**(5).

# 4.5.3
## Fixes
 * UI bug when editing/deleting presets

# 4.5.2
## Fixes
 * UI bug when editing presets with custom sort ordering
 * Extended naming syntax for monster die-roll modifier settings (for use with gm console)

# 4.5.1
## Fixes
 * There was a bug in the handling of the editing of presets and titles.

# 4.5
## Enhancements
 * Added new die-roll result detail types "begingroup" and "endgroup"
 * Updated the in-app documentation for die roll expressions.
 * Fixed a bug that caused tooltips to be unreadable in dark mode.
 * Added an editor window to create or edit die-roll title tags with full colored box support.

# 4.4.1
## Enhancements 
 * Augmented preferences editor to include more color settings, including initiative clock fonts and colors.

# 4.4
## Enhancements
 * Created in-app preferences editor.
    * Server profile selected in editor is the default for subsequent uses of the mapper.
    * If the preference editor was used, the mapper will use that at startup and **NOT** the old default behavior of reading from the `mapper.conf` file.
    * If a config file is named with the `--config` option, that will be read in after the new preference data are loaded, possibly overriding those values with the named config file's contents.
    * A runtime menu option allows *ad-hoc* selection of a mapper server profile to connect to (may not set all other preferences).
    * A command line option `--select` *profilename* selects that server profile saved from the preferences editor to be used for this invocation of the mapper without affecting the default profile used by other invocations.
 * Supports protocol 403 (although it isn't directly affected by the difference between 402 and 403.
 * Moves nameplate for dead creatures to the bottom of the display to avoid overcrowding the map.
 * Moves nameplates out the the way of nearby creatures better.
    
## Changes
 * Moved mapper client/server protocol spec out of `mapper`(6) and into its own manpage, `mapper-protocol`(7).

# 4.3.4
## Fixes
 * If for some reason (like an older version of Tk) the user's system can't handle PNG files, the Mapper automatically switches to GIF image format for map files and icons.

# 4.3.3
## Fixes
 * When initiative slots disappear during combat, the game clock would throw an exception.

# 4.3.2
## Enhancements
 * Added support for mapper to use PNG format graphic images as an alternative to GIF.
 * Updated documentation.
 * GUI output for `check_install.tcl` so it works better on Windows.

# 4.3.1
## Fixed
 * If the server's protocol version is higher than expected, a debugging message is printed to the user letting them know. There was a bug in the code that threw an error trying to print that message.
 * Added `check_install.tcl` to the standalone distribution archive files.

# 4.3
## Added
 * A new script, `bin/check_install.tcl`, is provided to check to see that you have the Tcl/Tk libraries on which the mapper tool depends. If you don't, it will give you some instructions as to where to find the missing library.
 * Now implements protocol 402, which enhances the responses to die roll requests to include the cases where blind rolls are made to or by the GM, and reports of invalid roll requests.
 * Now uses GMA application icon where supported by the window manager.

## Fixed
 * Added documentation to die-roll help screen about the `>` prefix to a die roll.

# 4.2.5
## Fixed
 * Activestate Tcl apparently supplies JSON library version 1.3.3, but the mapper was asking for at least 1.3.4 (since that's the current version in our dev environment). This caused Windows clients to refuse to run so this release backs off the minimum json library version to 1.3.3 which makes the mapper run successfully in Activestate Tcl on Windows (tested on Win10).

# 4.2.4
## Fixed
 * Corrected a but that prevented self-upgrades if the protocol version is already ahead of the one expected.

# 4.2.3
## Fixed
 * There was either a race condition or failure to clean up a failed chat history cache load, causing subsequently-received messages to throw an exception when received. The code around those operations has been replaced with a more defensive implementation which should recover from an error in initial load and also avoid trying to write new entries to the cache while a load operation is underway.
 * Changed the chat history cache load so it happens after successful server login, so we know the correct user's cache file is loaded (really only an issue for GMs who sign on to the server with a non-GM username initially).
 * Installed code to tell the user that moving or nudging spell area-of-effect zones is not implemented, rather than letting them try which leads to an error as the mapper fails to do that correctly.

# 4.2.2
## Added
 * Now displays connection information in main window title bar.

# 4.2.1
## Fixed
 * Corrected issue with function definition order that caused an error on startup if the server asked for scrolling to a grid label.

# 4.2
## Added
 * Improved scrolling when zooming the map in and out, so that it does a better job of keeping the map scrolled to where it was before the zoom operation.
 * Improved scrolling between clients so they go to the same area of the map even if they are at different zoom levels from each other.

# 4.1
## Added
* New feature which displays a game clock window. This tracks the in-game date and time, and shows the state of the initiative order list during combat.

# 4.0.5
## Fixes
* Numerous bug fixes to get the new protocol working.
* Corrected problem in detecting if a new version is staged for upgrading.
* Corrected problem where the mapper would not correctly find image tiles stored on the server.
* Now immediately updates loaded images instead of waiting for a manual refresh.

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

