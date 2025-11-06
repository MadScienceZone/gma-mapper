#!/usr/bin/env wish
########################################################################################
#  _______  _______  _______                ___       ______   ______       __         #
# (  ____ \(       )(  ___  ) Game         /   )     / ___  \ / ___  \     /  \        #
# | (    \/| () () || (   ) | Master's    / /) |     \/   \  \\/   \  \    \/) )       #
# | |      | || || || (___) | Assistant  / (_) (_       ___) /   ___) /      | |       #
# | | ____ | |(_)| ||  ___  |           (____   _)     (___ (   (___ (       | |       #
# | | \_  )| |   | || (   ) |                ) (           ) \      ) \      | |       #
# | (___) || )   ( || )   ( | Mapper         | |   _ /\___/  //\___/  / _  __) (_      #
# (_______)|/     \||/     \| Client         (_)  (_)\______/ \______/ (_) \____/      #
#                                                                                      #
########################################################################################
# TODO move needs to move entire animated stack (seems to do the right thing when mapper is restarted)
# TODO note that in server INIT file, Skin= must be set; the mapper does not use the * field in monsters,
#      it just does as instructed based on Skin index
#
# GMA Mapper Client with background I/O processing.
#
# Auto-configure values
set GMAMapperVersion {4.33.1}     ;# @@##@@
set GMAMapperFileFormat {23}        ;# @@##@@
set GMAMapperProtocol {419}         ;# @@##@@
set CoreVersionNumber {6.34.1}            ;# @@##@@
encoding system utf-8
#---------------------------[CONFIG]-------------------------------------------
#
# The following are some system-dependent values you may need to tweak.
# The values here are defaults which can be overridden by command-line options
# and/or configuration file settings.
#
# CURL:
#  The mapper runs CURL to retrieve files from the web server into our
#  local cache.
#	CURLproxy	URL of proxy server to use if any, e.g., https://www.example.org:1080
#				The -x command line option sets this value at runtime.
#	CURLpath	Pathname to the CURL program on this system. (--curl-path overrides)
#	CURLserver	The URL of stored images (the top-level directory) (--curl-url-base overrides)
#
set CURLproxy {}
set CURLpath /usr/bin/curl
set CURLinsecure false
set CURLserver https://www.rag.com/gma/map
set ImageFormat png
set ServerSideConfiguration {}
#
# SCP/SSH:
#  The mapper runs SSH and SCP to send files TO the web server for authorized
#  users. Normally this is just the GM. Appropriate SSH credentials need to be
#  available for this to work.
#	SCPproxy	hostname of a SOCKS5 proxy to use for SSH/SCP, if any, e.g., example.org:8080
#				The -X command-line option sets this at runtime.
#	SCPpath		The local pathname to the SCP command. (--scp-path)
#	SSHpath		The local pathname to the SSH command. (--ssh-path)
#	SCPdest		The server's pathname to the top-level directory for file storage. (--scp-dest)
#	SCPserver	The server's hostname (--scp-server)
#	NCpath		The local pathname to the NetCat command (used when going through a proxy) (--nc-path)
#	SERVER_MKDIRpath
#				The server's pathname to the mkdir command. (--mkdir-path)
#
# Server Image Name Encoding:
#	ModuleID	String (default blank) added to hash in server-side names for files.
#
set ClockDisplay {}
set ChatHistoryLimit 512
set SCPproxy {}
set SCPpath /usr/bin/scp
set SSHpath /usr/bin/ssh
set SCPdest {}
set SCPserver {} 
set UpdateURL {}
set NCpath /usr/bin/nc
set SERVER_MKDIRpath /bin/mkdir
set ModuleID {}
set UpgradeNotice false
#
# Cache files newer than this many days are used without any further
# checks. Otherwise, we check with the server to see if there's a newer
# version available.
#
set cache_too_old_days 2
#
# If you have a SOCKS proxy server you need to talk through to reach the
# map service, specify it here as:
#	ITproxy		hostname/IP address of SOCKS proxy server
#	ITproxyport	TCP port for SOCKS server
#	ITproxyuser	username to log in to SOCKS proxy if any
#	ITproxypass	password "   "  "  "    "     "   "   "
#
# note that this is experimental and not tested much in actual usage (we
# just use SSH tunnels instead).
#
set ITproxy {}
set ITproxyuser {}
set ITproxypass {}
set ITproxyport 0
#
#
#---------------------------[END CONFIG]--------------------------------------
#
# begin_progress id|* title maxvalue|* ?-send? -> id
# 
set IThost {}
set ITport 2323
set ITbuffer {}
set ITpassword {}
set MasterClient 0
set ButtonSize small
set OptAddCharacters {}
set OptPreload 0
set time_abs 0
set time_rel 0
set ClockProgress 0
set progress_stack {}
set is_GM false
set LastDisplayedChatDate {}
set CombatantSelected {}
set CreatureGridSnap nil
proc begin_progress { id title max args } {
    if {[catch {
        DEBUG 1 "begin_progress [list $id $title $max $args]"
        global ClockProgress progress_stack progress_data ClockDisplay
        if {$id eq "*"} {
            set id [new_id]
        }
        if {$args eq {-send}} {
			::gmaproto::update_progress $id $title 0 $max false
        }
        grid .toolbar2.progbar -row 0 -column 2 -sticky e
        set ClockProgress 0
        if {$max eq "*" || $max == 0} {
            .toolbar2.progbar configure -mode indeterminate
            .toolbar2.progbar start
	    set max *
        } else {
            .toolbar2.progbar stop
            .toolbar2.progbar configure -mode determinate -maximum $max
        }
        if {[llength $progress_stack] == 0} {
            set progress_data(_:title) $ClockDisplay
        }
        lappend progress_stack $id
        set progress_data($id:title) $title
        set progress_data($id:value) 0
        set progress_data($id:max) $max
        set ClockDisplay $title
        update
    } err]} {
        DEBUG 0 "begin_progress $id: $err"
    }
    return $id
}

proc TopLeftGridLabel {} {
	lassign [ScreenXYToGridXY 0 0 -exact] x y
	return "[LetterLabel $x]$y"
}

proc LetterLabelToGridXY {label} {
	if {[regexp {^([A-Z]+)([0-9]+)$} [string toupper $label] _ xlabel ylabel]} {
		set x -1
		foreach letter [split $xlabel {}] {
			incr x
			set x [expr $x*26 + [scan $letter %c] - 65]
		}
		return [list $x $ylabel]
	} 
	error "$label is not a valid map locator value"
}

# scroll screen so (gx,gy) is at the top-left of the screen
proc ScrollToGridXY {gx gy} {
	global canvas
	set x [GridToCanvas $gx]
	set y [GridToCanvas $gy]
	set region [$canvas cget -scrollregion]
	if {[llength $region] == 0} {
		error "no -scrollregion set on canvas"
	}
	lassign $region x1 y1 x2 y2
	$canvas xview moveto [expr double($x)/$x2]
	$canvas yview moveto [expr double($y)/$y2]
}

# scroll to ensure (x,y) are centered on the screen unless they're 
# already visible within a margin of a couple of grids from the edges.
proc ScrollToCenterScreenXY {x y} {
	global canvas

	if {[IsScreenXYVisible $x $y 100 150]} {
		return
	}

	set region [$canvas cget -scrollregion]
	if {[llength $region] == 0} {
		error "no -scrollregion set on canvas"
	}
	lassign $region x1 y1 x2 y2
	lassign [$canvas xview] vx1 vx2
	lassign [$canvas yview] vy1 vy2
	SmoothScroll 20 50 \
		$vx1 [expr min(1.0,max(0.0,(double($x)-(($vx2*$x2-$vx1*$x2)/2.0))/$x2))] \
	        $vy1 [expr min(1.0,max(0.0,(double($y)-(($vy2*$y2-$vy1*$y2)/2.0))/$y2))]
}

set smooth_scroll_bg_id {}
proc SmoothScroll {steps delay x0 x1 y0 y1} {
	global smooth_scroll_bg_id
	if {$smooth_scroll_bg_id ne {}} {
		after cancel $smooth_scroll_bg_id
	}
	set smooth_scroll_bg_id [after $delay "do_smooth_scroll_update $steps $delay 1 $x0 $x1 $y0 $y1"]
}

proc do_smooth_scroll_update {steps delay step x0 x1 y0 y1} {
	global smooth_scroll_bg_id
	global canvas

	if {$step >= $steps} {
		$canvas xview moveto $x1
		$canvas yview moveto $y1
		set smooth_scroll_bg_id {}
	} else {
		$canvas xview moveto [expr (($x1-$x0)*(double($step)/$steps))+$x0]
		$canvas yview moveto [expr (($y1-$y0)*(double($step)/$steps))+$y0]
		set smooth_scroll_bg_id [after $delay "do_smooth_scroll_update $steps $delay [expr $step+1] $x0 $x1 $y0 $y1"]
	}
}
	

# determine if the (x,y) coordinates are within the visible scroll region.
proc IsScreenXYVisible {x y {ltmargin 0} {rbmargin 0}} {
	global canvas

	set region [$canvas cget -scrollregion]
	if {[llength $region] == 0} {
		error "no -scrollregion set on canvas"
	}
	lassign $region x1 y1 x2 y2
	lassign [$canvas xview] vx1 vx2
	lassign [$canvas yview] vy1 vy2

	if {($x - $ltmargin) < ($vx1*$x2) || ($x + $rbmargin) > ($vx2*$x2) || ($y - $ltmargin) < ($vy1*$y2) || ($y + $rbmargin) > ($vy2*$y2)} {
		return false
	}
	return true
}

proc GoToGridCoords {} {
	global GoToGrid__label
	if {[::getstring::tk_getString .goToGridPrompt GoToGrid__label {Map Coordinates:} -geometry [parent_geometry_ctr]]} {
		ScrollToGridLabel $GoToGrid__label
	}
}
proc ScrollToGridLabel {label} {
	if {[catch {
		lassign [LetterLabelToGridXY $label] gx gy
		ScrollToGridXY $gx $gy
	} err]} {
		DEBUG 0 "Unable to scroll to $label: $err"
	}
}

#
# update_progress id value newmax|* ?-send?
#
proc update_progress { id value newmax args } {
    if {[catch {
        DEBUG 1 "update_progress [list $id $value $newmax $args]"
        global ClockProgress progress_stack progress_data ClockDisplay
        if {$args eq {-send}} {
			::gmaproto::update_progress $id {} $value $newmax false
        }
        if {[info exists progress_data($id:title)]} {
            if {$newmax eq "*" || $newmax == 0} {
		if {$progress_data($id:max) ne "*"} {
			# switching to indeterminate mode
			.toolbar2.progbar configure -mode indeterminate -maximum 100.0
			.toolbar2.progbar start
			set progress_data($id:max) *
		}
		# if we already were in that mode, do nothing.
	    } else {
		    if {[info exists progress_data($id:max)] && $progress_data($id:max) eq "*"} {
			    # switching to determinate mode
			    .toolbar2.progbar stop
			    .toolbar2.progbar configure -mode determinate
		    }
	    	    set progress_data($id:max) $newmax
                    .toolbar2.progbar configure -maximum $newmax
            }
            
            if {[info exists progress_data($id:max)] && $progress_data($id:max) eq "*"} {
                set progress_data($id:value) [expr $progress_data($id:value) + $value]
            } else {
                set progress_data($id:value) $value
                if {$id eq [lindex $progress_stack end]} {
                    set ClockProgress $value
                }
            }
            update
        }
    } err]} {
        DEBUG 0 "update_progress $id: $err"
    }
}

#
# end_progress id ?-send?
#    
proc end_progress {id args} {
    if {[catch {
        global ClockProgress progress_stack progress_data ClockDisplay
        if {$args eq {-send}} {
			::gmaproto::update_progress $id {} {} {} true
        }
        if {[info exists progress_data($id:max)] && $progress_data($id:max) eq "*"} {
            .toolbar2.progbar stop
        }
        unset progress_data($id:title)
        unset progress_data($id:value)
        unset progress_data($id:max)
        set idx [lsearch $progress_stack $id]
        if {$idx >= 0} {
            set progress_stack [lreplace $progress_stack $idx $idx]
        }
        if {[llength $progress_stack] == 0} {
            # that was the last one, take down the bar
            grid forget .toolbar2.progbar
            set ClockDisplay $progress_data(_:title)
            set progress_data(_:title) {}
        } elseif {$idx >= [llength $progress_stack]} {
            # this was the displayed element and there are more
            # so move the bar back to the previous one
            set ClockDisplay $progress_data([lindex $progress_stack end]:title)
            set ClockProgress $progress_data([lindex $progress_stack end]:value)
        }
        update
    } err]} {
        DEBUG 0 "end_progress $id: $err"
    }
}

proc report_progress_noconsole {msg} {
    global ClockDisplay
    set ClockDisplay $msg
    catch { update }
}
proc report_progress {msg} {
    puts "mapper: $msg"
    report_progress_noconsole $msg
}

proc setDarkMode {enabled} {
	global dark_mode colortheme _preferences
	if {$enabled} {
		set dark_mode 1
		set colortheme dark
		dict set _preferences dark true
		catch {
			set ::tooltip::labelOpts [list -highlightthickness 0 -relief solid -bd 1 -background blue -foreground white]
			if {[winfo exists $::tooltip::G(TOPLEVEL)]} {
				$::tooltip::G(TOPLEVEL) configure -background blue
				$::tooltip::G(TOPLEVEL).label configure -background blue -foreground white
			}
		}
	} else {
		set dark_mode 0
		set colortheme light
		dict set _preferences dark false
		catch {
			set ::tooltip::labelOpts [list -highlightthickness 0 -relief solid -bd 1 -background lightyellow -foreground black]
			if {[winfo exists $::tooltip::G(TOPLEVEL)]} {
				$::tooltip::G(TOPLEVEL) configure -background lightyellow
				$::tooltip::G(TOPLEVEL).label configure -background lightyellow -foreground black
			}
		}
	}
}

report_progress "Starting up..."
set dark_mode 0
set colortheme light
set _preferences {}
set SuppressChat 0
set PeerList {}
# Files we reference in various places
set path_DEBUG_file   [file normalize [file join ~ .gma mapper debug.log]]
set path_log_dir      [file normalize [file join ~ .gma mapper logs]]
set path_log(stdout)  [file normalize [file join $path_log_dir "mapper.[pid].log"]]
set path_log(stderr)  [file normalize [file join $path_log_dir "mapper-errors.[pid].log"]]
set path_log(wstdout) [file normalize [file join $path_log_dir "mapper.[pid].stdout"]]
set path_log(wstderr) [file normalize [file join $path_log_dir "mapper.[pid].stderr"]]
set path_cache        [file normalize [file join ~ .gma mapper cache]]
set path_tmp          [file normalize [file join ~ .gma mapper tmp]]
set preferences_path  [file normalize [file join ~ .gma mapper preferences.json]]
set default_config    [file normalize [file join ~ .gma mapper mapper.conf]]
#set default_style_cfg [file normalize [file join ~ .gma mapper style.conf]]
set path_install_base [file normalize [file join ~ .gma mapper]]

if {[catch {set local_user $::tcl_platform(user)}]} {set local_user __unknown__}
set ChatTranscript 	{}

proc say {msg} {
	puts "-> $msg"
	if {[catch {
		tk_messageBox -type ok -icon warning -title "Warning" -message $msg -parent .
	}]} {
		tk_messageBox -type ok -icon warning -title "Warning" -message $msg
	}
}

#
# We now accept image=name wherever a creature name could be input.
# to facilitate this, the following functions will take an input creature
# name, and:
#	SplitCreatureImageName:  return a list of two elements: bare name and
#				 image name (or just bare name if there was no
#                                separate image given).
#	AcceptCreatureImageName: return the bare name, storing the image name 
#				 in MOB_IMAGE if one was specified.
# 
#
proc SplitCreatureImageName {name} {
	set parts [split $name =]
	switch [llength $parts] {
		0		{ return {}}
		1		{ return [list $name] }
		2		{ return [list [lindex $parts 1] [lindex $parts 0]] }
		default { return [list [join [lrange $parts 1 end] =] [lindex $parts 0]] }
	}
}

# Stirge #1

proc GMAFontToTkFont {gfont} {
	set font [list [dict get $gfont Family] [expr int([dict get $gfont Size])]]
	if {[dict get $gfont Weight] == 1} {
		lappend font "bold"
	}
	if {[dict get $gfont Slant] == 1} {
		lappend font "italic"
	}
	return $font
}

proc TkFontToGMAFont {tkfont} {
	# may be packaged in an outer list for historical reasons;
	# if so, unwrap it
	if {[llength $tkfont] == 1} {
		set tkfont [lindex $tkfont 0]
	}
	if {[llength $tkfont] >= 2} {
		set d [dict create Family [lindex $tkfont 0] Size [lindex $tkfont 1] Slant 0 Weight 0]
		if {[lsearch -exact $tkfont italic] >= 0} {dict set d Slant 1}
		if {[lsearch -exact $tkfont bold] >= 0} {dict set d Weight 1}
		return $d
	}
	DEBUG 1 "unable to read tk font value $tkfont; assuming it's the family name only"
	return [dict create Family $tkfont Size 10 Slant 0 Weight 0]
}

proc ScaleFont {fontspec factor} {
	array set _base_font_info [font actual $fontspec]
	if {[info exists _base_font_info(-size)]} {
		set _base_font_info(-size) [expr int($_base_font_info(-size) * $factor)]
		return [array get _base_font_info]
	}
	DEBUG 1 "Unable to scale font '$fontspec'"
	return [font actual $fontspec]
}

proc AcceptCreatureImageName {name} {
	set parts [SplitCreatureImageName $name]
	DEBUG 3 "AcceptCreatureName $name -> $parts"
	if {[llength $parts] > 1} {
		global MOB_IMAGE
		set MOB_IMAGE([lindex $parts 0]) [lindex $parts 1]
		DEBUG 3 "Stored [lindex $parts 1] as image for [lindex $parts 0]"
		return [lindex $parts 0]
	}
	DEBUG 3 "Did not store image for $name"
	return $name
}


set PI 3.14159265358979323

# 
# Okay, here's the deal.
#
# This is a TRULY AWFUL (okay, maybe that's a bit harsh.  I've seen [and written]
# my share of awful spaghetti-code scripts in my time, and this is fairly tame by
# comparison... maybe it's just a SOMEWHAT BUT NOT COMPLETELY EVIL) Tcl/Tk program
# to run the game grid for our D&D/Pathfinder games.  It's been hacked and kludged
# over way too many years and is due for a rewrite.
#
# In the mean time, I decided it was better to enhance it for multi-user capability
# rather than rewriting it RIGHT NOW, but eventually I have a whole pile of new and
# exciting things that I want to do with this, and pulling it into the rest of the
# Python code base that makes the rest of GMA work wouldn't be a bad thing, really.
#
# For now, however, here it is.
# 
package require Tcl 8.6
package require uuid 1.0.1
package require base64
package require md5 2.0.7
package require sha256
package require struct::queue
package require getstring
package require tooltip
package require inifile

set animatePlacement 0
set blur_pct 0
set blur_all 0
set DEBUG_level 0
set GridEnable 1


# Objects are stored in these arrays:
#   OBJdata -- graphics drawn on-screen
#   OBJtype -- type of each object
#   MOBdata -- creatures
#   MOBid   -- map of creature name to ID
# These associate the object ID with a dict of information about the object.
#
# Previously, we did this:
#
# Objects are stored in these arrays:
#   OBJ     -- graphics drawn on-screen
#   MOB     -- player or monster
# 
# In the past, we stored objects in files and memory using
# small integer ID numbers.  We consider ID numbers in files
# to be unique only within those files, so we translate them
# upon file load into a set of integers we use internally.
# This means that merging a file multiple times will result
# in multiple copies of the same object.  This is now a problem
# when we have multiple map clients talking to each other.  The
# IDs need to be universally unique.  I considered a few cheezy
# approaches to getting unique IDs among a small group of clients
# but in the end it's just easier to use standard UUIDs and leave
# it at that.
# When we read an old file with small integer IDs, we convert them
# to UUIDs.  We use UUIDs everywhere from that point on.  If we load
# an object from a file with a UUID we already have, we will just 
# update that object, not duplicate it.
# We used to use object ID as a display order indication.  We're
# moving to using a Z coordinate for that, which allows for objects
# to be moved up and down, too.  There's code here to add a new Z
# coordinate based on file order if a file doesn't already have
# Z coordinates.

set DEBUG_file {}
proc DEBUGp {msg} {
	puts "::protocol:: $msg"
	DEBUG protocol $msg -custom [list white [::tk::Darken white 40]]
}

# INFO message ?-progress n ?-of m?? ?-done? ?-display?
set info_progress_id {}

proc INFO {msg args} {
	global info_progress_id
	set pvalue {}
	set maxvalue *

	if {[lsearch -exact $args -done] >= 0} {
		if {$info_progress_id ne {}} {
			end_progress $info_progress_id
			set info_progress_id {}
		}
	} else {
		if {[set pidx [lsearch -exact $args -progress]] >= 0} {
			if {$pidx+1 < [llength $args]} {
				set pvalue [lindex $args $pidx+1]
			} else {
				DEBUG 0 "INFO option -progress requires a value"
			}
		}
		if {[set pidx [lsearch -exact $args -of]] >= 0} {
			if {$pidx+1 < [llength $args]} {
				set maxvalue [lindex $args $pidx+1]
			} else {
				DEBUG 0 "INFO option -of requires a value"
			}
		}
	}
	if {[lsearch -exact $args -display] >= 0} {
		display_message $msg
	}

	if {$pvalue ne {}} {
		if {$info_progress_id eq {}} {
			set info_progress_id [begin_progress * "operation progress" $maxvalue]
		} else {
			update_progress $info_progress_id $pvalue $maxvalue
		}
	}
	DEBUG info "\[info\] $msg" -custom {white blue}
}

proc DEBUG {level msg args} {
	global DEBUG_level DEBUG_file path_DEBUG_file dark_mode colortheme

	if {[set i [lsearch -exact $args -custom]] >= 0} {
		if {$i+1 < [llength $args]} {
			lassign [lindex $args $i+1] fg bg
			set DEBUGfgcolor($level) $fg 
			set DEBUGbgcolor($level) $bg
		} else {
			error "DEBUG: wrong number of args to -custom: should be -custom {fg bg}"
		}
	}

	if {$level <= $DEBUG_level || [string is alpha $level]} {
		if {![winfo exists .debugwindow]} {
			if {$dark_mode} {
				set DEBUGfgcolor(0) red
				set DEBUGbgcolor(0) yellow
				set DEBUGfgcolor(1) yellow
				set DEBUGbgcolor(1) #232323
				set DEBUGfgcolor(2) black
				set DEBUGbgcolor(2) yellow
				set DEBUGfgcolor(3) white
				set DEBUGbgcolor(3) #232323
				set DEBUGbgsel white
				set DEBUGfgsel #232323
				set dialogbg #232323
			} else {
				set DEBUGfgcolor(0) red
				set DEBUGbgcolor(0) yellow
				set DEBUGfgcolor(1) red
				set DEBUGbgcolor(1) #cccccc
				set DEBUGfgcolor(2) black
				set DEBUGbgcolor(2) yellow
				set DEBUGfgcolor(3) blue
				set DEBUGbgcolor(3) #cccccc
				set DEBUGbgsel blue
				set DEBUGfgsel #cccccc
				set dialogbg #cccccc
			}
			toplevel .debugwindow -background $dialogbg
			wm title .debugwindow "Diagnostic Messages"
			grid [text .debugwindow.text -exportselection true -yscrollcommand {.debugwindow.sb set}] \
				[scrollbar .debugwindow.sb -orient vertical -command {.debugwindow.text yview}] -sticky news
			foreach l {0 1 2 3} {
				.debugwindow.text tag configure level$l -foreground $DEBUGfgcolor($l) -background $DEBUGbgcolor($l)
			}
			.debugwindow.text configure -selectforeground $DEBUGfgsel -selectbackground $DEBUGbgsel
		}

		foreach k [array names DEBUGfgcolor] {
			if {[string is alpha $k]} {
				.debugwindow.text tag configure level$k -foreground $DEBUGfgcolor($k) -background $DEBUGbgcolor($k)
			}
		}

		grid columnconfigure .debugwindow 0 -weight 1
		grid rowconfigure .debugwindow 0 -weight 1
		set visible [lindex [.debugwindow.text yview] 1]
		.debugwindow.text insert end "$msg\n" level$level
		if {$visible >= .95} {
			.debugwindow.text see end
		}
		if {$DEBUG_file eq {}} {
			set DEBUG_file [open $path_DEBUG_file a]
			puts $DEBUG_file "[clock format [clock seconds]] Started Client -------------------------------"
		}
		puts $DEBUG_file $msg
		flush $DEBUG_file
	}
}

file mkdir $path_log_dir
foreach channel {stdout stderr} {
	set my_$channel [open $path_log($channel) a]
	puts [set my_$channel] "[clock format [clock seconds]] started new mapper client with PID [pid]"
}
	
if {$tcl_platform(os) eq "Windows NT"} {
	set stdout [open $path_log(wstdout) a]
	set stderr [open $path_log(wstderr) a]
} else {
	set stdout stdout
	set stderr stderr
}

#
# Scale text labels so they don't cover up too much of the smaller tokens
#
font create Tf16 -family Helvetica -size 16 -weight bold
font create Tf14 -family Helvetica -size 14 -weight bold
font create Tf12 -family Helvetica -size 12 -weight bold
font create Tf10 -family Helvetica -size 10 -weight bold
font create Hf14 -family Helvetica -size 14 
font create Hf12 -family Helvetica -size 12 
font create Hf10 -family Helvetica -size 10 
font create Tf8  -family Helvetica -size  8 -weight bold
font create If10 -family Times     -size 10 -slant italic
font create If12 -family Times     -size 12 -slant italic
font create Nf10 -family Times     -size 10 
font create Nf12 -family Times     -size 12 

proc FontBySize {creature_size} {
	global zoom
	DEBUG 1 "FontBySize $creature_size @ $zoom"

	if {$zoom > 1.0} {
		return Tf14
	}
	switch $creature_size {
		f - F - D - d - T - t 	{return Tf8}
		m - M - s - S - 1		{return Tf10}
		default					{return Tf12}
	}
}


set ChatHistory {}
set ChatHistoryFile {}
set ChatHistoryFileHandle {}
set ChatHistoryFileDirection {}
set ChatHistoryLastMessageID 0

proc ResetChatHistory {loadqty} {
	global ChatHistoryFile ChatHistoryFileHandle ChatHistoryLastMessageID ChatHistoryLimit ChatHistoryFileDirection
	global ChatHistory LastDisplayedChatDate

	catch {
		close $ChatHistoryFileHandle
	}
	set ChatHistoryFileHandle {}
	set ChatHistoryFileDirection {}
	INFO "Removing chat cache file $ChatHistoryFile"
	file delete -- $ChatHistoryFile
	set ChatHistoryLastMessageID 0
	INFO "Resetting chat history"
	set ch $ChatHistoryLimit
	set ChatHistoryLimit $loadqty
	set ChatHistory {}
	set LastDisplayedChatDate {}
	BlankChatHistoryDisplay
	InitializeChatHistory
	set ChatHistoryLimit $ch
}

# We only use ChatHistoryLastMessageID while loading the saved data. From that point on
# we get the messages in real time and don't ask the server to catch us up again, (or
# if we do, we can look at our in-memory history for that instead of taking time to update
# this for every message).

set ICH_tries 10
proc InitializeChatHistory {} {
	global ChatHistoryFile ChatHistory ChatHistoryFileHandle ChatHistoryLastMessageID
	global path_cache IThost ITport ChatHistoryLimit local_user
	global ChatHistoryFileDirection ICH_tries
	global LastDisplayedChatDate
	set LastDisplayedChatDate {}

	if {$IThost ne {}} {
		if {$ChatHistoryFileDirection ne {}} {
			if {$ICH_tries <= 0} {
				DEBUG 0 "Refusing to load the chat history from cache because someone beat me to the file! (mode $ChatHistoryFileDirection) This shouldn't happen."
				return
			}
			DEBUG 0 "Can't load the chat history because it's currently busy (mode $ChatHistoryFileDirection). Waiting... $ICH_tries more attempts"
			incr ICH_tries -1
			after 1000 InitializeChatHistory
			return
		}
		set ICH_tries 10
		set prog_id [begin_progress * "Loading cached chat messages" *]
		DEBUG 1 "prog_id $prog_id"
		set ChatHistoryFile [file join $path_cache "${IThost}-${ITport}-${local_user}-chat.history"]
		DEBUG 1 "Loading chat history from $ChatHistoryFile"
		if {! [file exists $ChatHistoryFile]} {
			DEBUG 1 "-Creating new file; did not find an existing one"
		} else {
			if {[catch {set ChatHistoryFileHandle [open $ChatHistoryFile]} err]} {
				DEBUG 0 "Unable to read chat history file $ChatHistoryFile ($err). We will try asking the server for a new history download."
				set ChatHistoryFileHandle {}
				set ChatHistoryFileDirection {}
			} else {
				set ChatHistoryFileDirection r
				if {[catch {
					while {[gets $ChatHistoryFileHandle msg] >= 0} {
						DEBUG 2 "read $msg from cache"
						update 
						if {[lindex $msg 0] eq {CHAT}} {
							# new-style entry:	{CHAT ROLL|TO|CC|-system json-dict}
							DEBUG 3 "parsing new style message"
							lassign [UnmarshalChatHistoryEntry $msg] ctype d
							DEBUG 2 "new-style -> $ctype, $d"
						} else {
							# old-style entry:	{ROLL|TO|CC|-system a b c ...}
							DEBUG 3 "parsing old style message"
							if {[set o [ValidateChatHistoryEntry $msg]] eq {}} {
								DEBUG 1 "$ChatHistoryFile: Rejecting invalid old-style entry $msg"
								continue
							}
							lassign $o ctype d
							DEBUG 2 "old-style -> $ctype, $d"
						}

						if {$ctype eq {-system}} {
							set mid -1
						} else {
							set mid [dict get $d MessageID]
						}

						if {$ctype eq {CC}} {
							set ChatHistory {}
						} else {
							set ChatHistoryLastMessageID [expr max($ChatHistoryLastMessageID, $mid)]
						}
						lappend ChatHistory [list $ctype $d $mid]
					}
				} err]} {
					# error reading cache file; don't leave it open
					DEBUG 0 "Error loading chat history from cache: $err"
				}
				close $ChatHistoryFileHandle
				set ChatHistoryFileDirection {}
				set ChatHistoryFileHandle {}

				if {$ChatHistoryLimit > 0 && [llength $ChatHistory] > $ChatHistoryLimit} {
					DEBUG 1 "Chat history contains [llength $ChatHistory] items; trimming it back to $ChatHistoryLimit."
					if {[catch {set ChatHistoryFileHandle [open $ChatHistoryFile w]} err]} {
						DEBUG 0 "Unable to overwrite the chat history in $ChatHistoryFile ($err). No history will be kept now."
						set ChatHistoryFileHandle {}
					} else {
						set ChatHistoryFileDirection w
						set ChatHistory [lrange $ChatHistory end-$ChatHistoryLimit end]
						foreach msg $ChatHistory {
							update
							puts $ChatHistoryFileHandle [MarshalChatHistoryEntry $msg]
						}
						flush $ChatHistoryFileHandle
					}
				}
			}
		}
		end_progress $prog_id

		set ChatHistoryFileDirection a
		if {$ChatHistoryFileHandle eq {}} {
			if {[catch {set ChatHistoryFileHandle [open $ChatHistoryFile a]} err]} {
				DEBUG 0 "Unable to append to or create chat history file $ChatHistoryFile ($err). No history will be kept."
				set ChatHistoryFileHandle {}
				set ChatHistoryFileDirection {}
			}
		}
		DEBUG 1 "Chat history now has [llength $ChatHistory] items."
		if {$ChatHistoryLastMessageID <= 0} {
			if {$ChatHistoryLimit > 0} {
				DEBUG 1 "We don't have any loaded history; asking server for up to $ChatHistoryLimit messages."
				::gmaproto::sync_chat -$ChatHistoryLimit
				::gmaproto::watch_operation "Loading up to $ChatHistoryLimit chat messages"
			} elseif {$ChatHistoryLimit == 0} {
				DEBUG 1 "We don't have any loaded history; asking server all messages."
				::gmaproto::sync_chat 0
				::gmaproto::watch_operation "Loading full chat message history"
			}
		} else {
			DEBUG 1 "Asking server for any new messages since $ChatHistoryLastMessageID."
			::gmaproto::sync_chat $ChatHistoryLastMessageID
			::gmaproto::watch_operation "Loading new chat messages"
		}
	}
}

set _last_known_message_id 0

#
# {CC|TO|ROLL|-system d|msg id} -> CHAT type jsonified-d
#
proc MarshalChatHistoryEntry {m} {
	if {[lindex $m 0] eq {-system}} {
		return [list CHAT -system [::json::write string [lindex $m 1]]]
	}
	return [list CHAT [lindex $m 0] [::gmaproto::_encode_payload [lindex $m 1] $::gmaproto::_message_payload([lindex $m 0])]]
}

#
# {CHAT type json} -> {CC|TO|ROLL|-system d|msg id}
#
proc UnmarshalChatHistoryEntry {m} {
	if {[lindex $m 1] eq {-system}} {
		return [list {-system} [::json::json2dict [lindex $m 2]] -1]
	}
	DEBUG 2 "unmarshal $m"
	set d [::gmaproto::_construct [::json::json2dict [lindex $m 2]] $::gmaproto::_message_payload([lindex $m 1])]
	DEBUG 3 "-> [lindex $m 1] $d" 
	return [list [lindex $m 1] $d [dict get $d MessageID]]
}

# ChatHistoryAppend {CC|ROLL|TO d mid}
# ChatHistoryAppend {-system msg -1}
proc ChatHistoryAppend {event} {
	global ChatHistory ChatHistoryFileHandle _last_known_message_id ChatHistoryFileDirection

	if {[set m [ValidateChatHistoryEntry $event]] ne {}} {
		set mid [lindex $m 2]
		if {$mid eq {} || $mid < 0} {
			set mid ${_last_known_message_id}
		}
		if {$mid >= ${_last_known_message_id}} {
			lappend ChatHistory $m
			if {$ChatHistoryFileHandle ne {}} {
				if {$ChatHistoryFileDirection eq {a}} {
					puts $ChatHistoryFileHandle [MarshalChatHistoryEntry $m]
					flush $ChatHistoryFileHandle
				} else {
					DEBUG 0 "(chat message not written to cache because cache file is busy (mode $ChatHistoryFileDirection))"
				}
			}
		} else {
		    DEBUG 1 "Rejected chat message $m; message ID $mid < ${_last_known_message_id}"
		}
	} else {
		DEBUG 1 "Rejected invalid chat message '$event'"
	}
}

#
# Generate a new unique ID for an object.
#
proc new_id {} {
	return [string tolower [string map {- {}} [::uuid::uuid generate]]]
}

# sanitize username to a key that can be used in a comma-separated array name
set user_key_map {}
for {set c 0} {$c < 256} {incr c} {
	set cs [format %c $c]
	if {![string is alnum -strict $cs]} {
		lappend user_key_map $cs [format %%%02x $c]
	}
}
DEBUG 2 "Initialized user_key map to $user_key_map"

#
# sanitize a user name to use it as a lookup key more safely
#
proc user_key {name} {
	global user_key_map
	return [string map $user_key_map $name]
}
proc root_user_key {} {
	global local_user
	return [user_key $local_user]
}

#
# convert a string like a user key or user name to an alphanumeric (and _ and -) value
# suitable for use as a widget pathname component
#
proc to_window_id {s} {
	return w[string map {+ _ / - = {}} [::base64::encode [::md5::md5 $s]]]
}
proc root_user_window_id {base} {
	return "$base[to_window_id [root_user_key]]"
}

if {$tcl_platform(os) eq "Darwin"} {
	set BUTTON_RIGHT <2>
	set BUTTON_MIDDLE <3>
} else {
	set BUTTON_RIGHT <3>
	set BUTTON_MIDDLE <2>
}

set ICON_DIR [file normalize [file join {*}[lreplace [file split [file normalize $argv0]] end-1 end lib MadScienceZone GMA Mapper icons]]]
set BIN_DIR [file normalize [file join {*}[lreplace [file split [file normalize $argv0]] end end]]]
foreach module {scrolledframe ustar gmaclock gmacolors gmautil gmaprofile gmaproto gmafile gmazones progressbar minimarkup} {
	source [file normalize [file join {*}[lreplace [file split [file normalize $argv0]] end end $module.tcl]]]
}

set canw 1000
set canh 1400
set cansw 40000
set cansh 40000
set initialColor black
set initialwidth 5
set ThreatLineWidth 3
set ThreatLineHatchWidth 3
set AoeHatchWidth 5
set ReachLineColor green
set SelectLineWidth 8
set iscale 50
set rscale 50.0
set zoom 1.0
set GuideLines 0
set MajorGuideLines 0
set GuideLineOffset {0 0}
set MajorGuideLineOffset {0 0}
set CombatantScrollEnabled false
set ForceElementsToTop true
set TimerScope mine
set check_menu_color     [::gmaprofile::preferred_color $_preferences check_menu   $colortheme]
#set iscale 100
#set rscale 100.0

frame .toolbar2
set MAIN_MENU {}
proc update_main_menu {} {
	global check_menu_color MAIN_MENU is_GM
	foreach menu {view edit play edit.stipple edit.gridsnap edit.setwidth play.gridsnap view.timers} {
		for {set i 0} {$i <= [$MAIN_MENU.$menu index last]} {incr i} {
			if {[set mtype [$MAIN_MENU.$menu type $i]] eq {radiobutton} || $mtype eq {checkbutton}} {
				$MAIN_MENU.$menu entryconfigure $i -selectcolor $check_menu_color
			}
		}
	}
	if {$is_GM} {
		set privcmdstate normal
	} else {
		set privcmdstate disabled
	}
	$MAIN_MENU.play entryconfigure "Edit System Die Roll Presets" -state $privcmdstate
}

proc create_main_menu {use_button} {
	global MAIN_MENU CombatantScrollEnabled check_menu_color
	global ForceElementsToTop NoFill d_OBJ_MODE StipplePattern local_user is_GM

	if {$is_GM} {
		set privcmdstate normal
	} else {
		set privcmdstate disabled
	}

	if {$MAIN_MENU ne {}} {
		return
	}
	if {$use_button} {
		set MAIN_MENU .toolbar2.menu.main_menu
		set toolbar2_menu [menubutton .toolbar2.menu -relief raised -menu $MAIN_MENU]
		menu $MAIN_MENU
		::tooltip::tooltip .toolbar2.menu "Main Application Menu"
		grid $toolbar2_menu -row 0 -column 0 -sticky w
	} else {
		set MAIN_MENU .menu
		menu $MAIN_MENU
		. configure -menu $MAIN_MENU
	}
	set mm $MAIN_MENU
	$mm add cascade -menu $mm.file -label File
	$mm add cascade -menu $mm.edit -label Edit
	$mm add cascade -menu $mm.view -label View
	$mm add cascade -menu $mm.play -label Play
	$mm add cascade -menu $mm.tools -label Tools
	$mm add cascade -menu $mm.help -label Help
	menu $mm.file
	$mm.file add command -command {loadfile {}} -label "Load Map File..."
	$mm.file add command -command {loadfile {} -merge} -label "Merge Map File..."
	$mm.file add command -command savefile -label "Save Map File..."
	$mm.file add separator
	$mm.file add command -command restartMapper -label "Restart Mapper"
	$mm.file add command -command exitchk -label Exit
	menu $mm.edit
	$mm.edit add radiobutton -command playtool -label "Normal Play Mode" -selectcolor $check_menu_color -variable d_OBJ_MODE -value nil
	$mm.edit add separator
	$mm.edit add command -command {cleargrid; ::gmaproto::clear E*} -label "Clear All Map Elements"
	$mm.edit add command -command {clearplayers monster; ::gmaproto::clear M*} -label "Clear All Monsters"
	$mm.edit add command -command {clearplayers player; ::gmaproto::clear P*} -label "Clear All Players"
	$mm.edit add command -command {clearplayers *; ::gmaproto::clear P*; ::gmaproto::clear M*} -label "Clear All Creatures"
	$mm.edit add command -command {cleargrid; clearplayers *; ::gmaproto::clear *} -label "Clear All Objects"
	$mm.edit add separator
	$mm.edit add radiobutton -command linetool -label "Draw Lines" -selectcolor $check_menu_color -variable d_OBJ_MODE -value line
	$mm.edit add radiobutton -command recttool -label "Draw Rectangles" -selectcolor $check_menu_color -variable d_OBJ_MODE -value rect
	$mm.edit add radiobutton -command polytool -label "Draw Polygons" -selectcolor $check_menu_color -variable d_OBJ_MODE -value poly
	$mm.edit add radiobutton -command circtool -label "Draw Circles/Ellipses" -selectcolor $check_menu_color -variable d_OBJ_MODE -value circ
	$mm.edit add radiobutton -command arctool  -label "Draw Arcs" -selectcolor $check_menu_color -variable d_OBJ_MODE -value arc
	$mm.edit add radiobutton -command texttool -label "Add Text..." -selectcolor $check_menu_color -variable d_OBJ_MODE -value text
	$mm.edit add radiobutton -command killtool -label "Remove Objects" -selectcolor $check_menu_color -variable d_OBJ_MODE -value kill
	$mm.edit add radiobutton -command movetool -label "Move Objects" -selectcolor $check_menu_color -variable d_OBJ_MODE -value move
	$mm.edit add radiobutton -command stamptool -label "Stamp Objects" -selectcolor $check_menu_color -variable d_OBJ_MODE -value tile
	$mm.edit add separator
	$mm.edit add checkbutton -onvalue true -offvalue false -selectcolor $check_menu_color -variable ForceElementsToTop -label "Force Drawn Elements to Top"
	$mm.edit add separator
	$mm.edit add checkbutton -command _showNoFill -label "Fill Shapes" -onvalue 0 -offvalue 1 -variable NoFill -selectcolor $check_menu_color
	$mm.edit add command -command {colorpick fill} -label "Choose Fill Color..."
	$mm.edit add command -command {colorpick line} -label "Choose Outline Color..."
	# cycleStipple {} gray12 gray25 gray50 gray75
	menu $mm.edit.stipple
	$mm.edit add cascade -menu $mm.edit.stipple -state normal -label "Select fill pattern"
	foreach {value label} {
		{nil} {None}
		gray12 12%
		gray25 25%
		gray50 50%
		gray75 75%
	} {
		$mm.edit.stipple add radiobutton -command [list cycleStipple $value] -label $label -selectcolor $check_menu_color -variable StipplePattern -value $value
	}
	#$mm.edit add command -command {cycleStipple -cycle} -label "Cycle Fill Pattern to 12% \[now none\]"
	$mm.edit add separator
	# gridsnap 0 1 2 3 4
	menu $mm.edit.gridsnap
	$mm.edit add cascade -menu $mm.edit.gridsnap -state normal -label "Set grid snap"
	foreach {value label} {
		0 {None}
		1 {Full grid squares}
		2 {1/2 square}
		3 {1/3 square}
		4 {1/4 square}
	} {
		$mm.edit.gridsnap add radiobutton -command [list gridsnap $value] -label $label -selectcolor $check_menu_color -variable OBJ_SNAP -value $value
	}

	# setwidth 0-9
	menu $mm.edit.setwidth
	$mm.edit add cascade -menu $mm.edit.setwidth -state normal -label "Set line thickness"
	foreach {value label} {
		0 {0 (Thinnest)}
		1 1
		2 2
		3 3
		4 4
		5 5
		6 6
		7 7
		8 8
		9 {9 (Thickest)}
	} {
		$mm.edit.setwidth add radiobutton -command [list setwidth $value] -label $label -selectcolor $check_menu_color -variable OBJ_WIDTH -value $value
	}

	$mm.edit add separator
	$mm.edit add command -command {unloadfile {}} -label "Remove Elements from File..."
	$mm.edit add separator
	$mm.edit add command -command {editPreferences} -label "Preferences..."
	menu $mm.view
	$mm.view add checkbutton -command {toolBarState -1} -label "Show Toolbar" -onvalue 1 -offvalue 0 -selectcolor $check_menu_color -variable ShowToolBar
	$mm.view add checkbutton -command {setGridEnable} -label "Show Map Grid" -onvalue 1 -offvalue 0 -selectcolor $check_menu_color -variable ShowMapGrid
	$mm.view add checkbutton -command {RefreshMOBs} -label "Show Health Stats" -onvalue 1 -offvalue 0 -selectcolor $check_menu_color -variable ShowHealthStats
	menu $mm.view.timers
	$mm.view add cascade -menu $mm.view.timers -label "Show Timers"
	$mm.view.timers add radiobutton -label "none" -selectcolor $check_menu_color -variable TimerScope -value none -command populate_timer_widgets
	$mm.view.timers add radiobutton -label "mine" -selectcolor $check_menu_color -variable TimerScope -value mine -command populate_timer_widgets
	$mm.view.timers add radiobutton -label "all" -selectcolor $check_menu_color -variable TimerScope -value all -command populate_timer_widgets
	$mm.view add separator
	$mm.view add command -command {zoomInBy 2} -label "Zoom In"
	$mm.view add command -command {zoomInBy 0.5} -label "Zoom Out"
	$mm.view add command -command {resetZoom} -label "Restore Zoom"
	$mm.view add separator
	$mm.view add command -command {FindNearby} -label "Scroll to Visible Objects"
	$mm.view add command -command {SyncView} -label "Scroll Others' Views to Match Mine"
	$mm.view add checkbutton -onvalue true -offvalue false -selectcolor $check_menu_color -variable CombatantScrollEnabled -label "Scroll to Follow Combatants"
	$mm.view add command -command {GoToGridCoords} -label "Go to Map Location..."
	$mm.view add separator
	$mm.view add command -command {refreshScreen} -label "Refresh Display"
	$mm.view add separator
	$mm.view add command -command {animation_stop -all} -label "Stop Animations"
	menu $mm.play
	menu $mm.play.servers
	menu $mm.play.delegatemenu
	$mm.play add checkbutton -onvalue 1 -offvalue 0 -selectcolor $check_menu_color -variable MOB_COMBATMODE -label "Combat Mode" -command setcombatfrommenu
	$mm.play add command -command {aoetool} -label "Indicate Area of Effect"
	$mm.play add command -command {rulertool} -label "Measure Distance Along Line(s)"
	$mm.play add command -command {DisplayChatMessage {} {}} -label "Show Chat/Die-roll Window"
	$mm.play add separator
	$mm.play add cascade -menu $mm.play.delegatemenu -state disabled -label "Access Die Rolls For..."
	$mm.play add command -command {EditDelegateList} -label "Manage Die-Roll Preset Delegates..."
	$mm.play add command -command {RefreshDelegates .delegates} -label "Refresh Die-Roll and Delegate Data from Server"
	$mm.play add command -command EditRootDieRollPresets -label "Edit Die Roll Presets for $local_user"
	$mm.play add command -command EditSystemDieRollPresets -label "Edit System Die Roll Presets" -state $privcmdstate
	$mm.play add separator
	$mm.play add command -command {display_initiative_clock} -label "Show Initiative Clock"
	$mm.play add separator
	$mm.play add command -command {initiate_timer_request} -label "Request a New Timer..."
	$mm.play add command -command {initiate_hp_request -tmp} -label "Request Temporary Hit Points..."
	$mm.play add command -command {initiate_hp_request} -label "Request Permanent Hit Point Adjustment..."
	$mm.play add separator
	# gridsnap nil .25 .5 1
	menu $mm.play.gridsnap
	$mm.play add cascade -menu $mm.play.gridsnap -label "Creature token grid snap"
	foreach {value label} {
		nil {By creature size}
		1   {full square}
		.5  {1/2 square}
		.25 {1/4 square}
	} {
		$mm.play.gridsnap add radiobutton -label $label -selectcolor $check_menu_color -variable CreatureGridSnap -value $value
	}
	$mm.play add command -command {ClearSelection} -label "Deselect All"
	menu $mm.tools
	$mm.tools add command -command {checkForUpdates} -label "Check for Updates..."
	$mm.tools add separator
	$mm.tools add command -command {ResetChatHistory -1} -label "Clear Chat History"
	$mm.tools add command -command {ClearPinnedChats} -label {Clear Pinned Chat Messages}
	$mm.tools add cascade -menu $mm.tools.rch -label "Reset Chat History"
	$mm.tools add separator
	$mm.tools add command -command {CleanupImageCache 0} -label "Clear Image Cache"
	$mm.tools add command -command {CleanupImageCache 60} -label "Clear Image Cache (over 60 days)"
	$mm.tools add command -command {CleanupImageCache -update} -label "Update Cached Images from Server"
	$mm.tools add command -command {array unset forbidden_url} -label "Retry failed image retrievals"
	$mm.tools add separator
	$mm.tools add command -command ServerPingTest -label "Test server response time..."
	$mm.tools add separator
	$mm.tools add command -command SaveDebugText -label "Save diagnostic messages as..."

	menu $mm.tools.rch
	$mm.tools.rch add command -command {ResetChatHistory 50} -label "...and load 50 messages"
	$mm.tools.rch add command -command {ResetChatHistory 100} -label "...and load 100 messages"
	$mm.tools.rch add command -command {ResetChatHistory 500} -label "...and load 500 messages"
	$mm.tools.rch add command -command {ResetChatHistory 0} -label "...and load all"

	menu $mm.help
	$mm.help add command -command {aboutMapper} -label "About Mapper..."
	$mm.help add command -command {ShowDiceSyntax} -label "Die roller syntax ..."
	$mm.help add command -command {gma::minimarkup::ShowMarkupSyntax} -label "Text markup syntax ..."
}

proc ClearPinnedChats {} {
	global dice_preset_data

	set tkey [root_user_key] 
	set w $dice_preset_data(cw,$tkey)
	if {[catch {
		$w.p.pinnedchat.1.text configure -state normal 
		$w.p.pinnedchat.1.text delete 1.0 end
		$w.p.pinnedchat.1.text configure -state disabled 
	} err]} {
		DEBUG 0 $err
	}
}

proc SaveDebugText {} {
	if {[winfo exists .debugwindow.text]} {
		if {[set filename [tk_getSaveFile -defaultextension .txt \
				-parent .  -title "Save diagnostic messages as..." \
				-filetypes {
					{{Text Files} {.txt}}
					{{All Files}       *}
				}]] eq {}} {
			return
		}

		if {[catch {set f [open $filename w]} err]} {
			tk_messageBox -type ok -icon error -title "Unable to open file" \
				-message "Unable to write to \"$filename\": $err" -parent .
			return
		}
#		puts $f [.debugwindow.text get 1.0 end]
		set level "???"
		foreach {k v i} [.debugwindow.text dump -text -tag 1.0 end] {
			switch -exact $k {
				text     { 
					foreach line [split $v "\n"] {
						if {$line ne {}} {
							puts $f [format "%-8s|%s" $level $line]
						}
					}
				}
				tagon    { 
					switch -exact $v {
						level0          { set level "ERROR" }
						level1          { set level "DEBUG 1" }
						level2          { set level "DEBUG 2" }
						level3          { set level "DEBUG 3" }
						levelprotocol   { set level "PROTOCOL" }
						levelinfo       { set level "INFO" }
						default         { set level $v }
					}
				}
				tagoff   {}
				default  { puts -nonewline $f "<<??? $v>>" }
			}
		}
		close $f
	} else {
		tk_messageBox -type ok -icon error -title "No diagnostics to save" \
			-message "There is no diagnostics window to save to a file." -parent .
	}
}


#
# Manage Delegates
# The users in this list will have access to modify and use your die-roll presets.
#  _________
# |name1    |   [Add Delegate...]
# |name2    |   [Remove <name>]
# |_________|
#
# [Refresh] [Cancel]               [Save]
#
proc EditDelegateList {} {
	set w .delegates

	if {[winfo exists $w]} {
		destroy $w
	}
	toplevel $w
	wm title $w "Manage Delegate List"
	pack [frame $w.buttons] -side bottom -fill x -expand 1
	pack [label $w.info2 -text "" -anchor w] -side bottom -fill x
	pack [label $w.info1 -text "" -anchor w] -side bottom -fill x
	pack [label $w.heading -text "Your delegates:" -anchor w] -fill both -expand 1
	pack [listbox $w.lb -yscrollcommand "$w.s set" -selectmode browse -selectforeground white -selectbackground blue -exportselection false] -side left -fill y -expand 1
	pack [scrollbar $w.s -orient vertical -command "$w.lb yview"] -side left -fill y -expand 1
	pack [button $w.add -text "Add Delegate..." -command "AddDelegate $w"] -side top
	pack [button $w.del -text "Remove" -state disabled -foreground red -command "DelDelegate $w"] -side bottom
	pack [button $w.buttons.refresh -text "Refresh" -command "RefreshDelegates $w"] -side left
	pack [button $w.buttons.cancel -text "Cancel" -command "destroy $w"] -side left
	pack [button $w.buttons.save -text "Save" -command "SaveDelegates $w"] -side right
	bind $w.lb <<ListboxSelect>> "SelectDelegateByIdx $w \[%W curselection\]"
	::tooltip::tooltip $w.buttons.refresh "Update the delegate list from the server."
	::tooltip::tooltip $w.buttons.cancel "Abandon any changes you made here."
	::tooltip::tooltip $w.buttons.save "Save this delegate list to the server."
	::tooltip::tooltip $w.del "Remove the selected delegate from the list."
	::tooltip::tooltip $w.add "Add a new delegate to the list."
	_update_delegate_list $w
}
proc SelectDelegateByIdx {w idx} {
	if {$idx eq {}} {
		$w.del configure -state disabled -text "Delete"
		$w.lb selection clear 0 end
	} else {
		set name [$w.lb get [lindex $idx 0]]
		$w.del configure -state normal -text "Delete $name"
	}
}

proc AddDelegate {w} {
	global AddDelegateName
	if {[::getstring::tk_getString .delegates_entry AddDelegateName {User name of delegate:} -title {Add Delegate} -geometry [parent_geometry_ctr]]} {
		foreach existing [$w.lb get 0 end] {
			if {$AddDelegateName eq $existing} {
				return
			}
		}
		$w.lb insert end $AddDelegateName
	}
}

proc DelDelegate {w} {
	if {[set idx [$w.lb curselection]] ne {}} {
		$w.lb delete [lindex $idx 0]
		$w.lb selection clear 0 end
	}
	SelectDelegateByIdx $w {}
}

proc RefreshDelegates {w} {
	global local_user
	::gmaproto::query_dice_presets $local_user
}

proc SaveDelegates {w} {
	global local_user
	::gmaproto::define_dice_delegates $local_user [$w.lb get 0 end]
	destroy $w
}

proc _update_delegate_list {w} {
	global dice_preset_data
	global MAIN_MENU
	set updated false
	set tkey [root_user_key]

	if {[info exists dice_preset_data(delegate_for,$tkey)]} {
		$MAIN_MENU.play.delegatemenu delete 0 end
		if {[llength $dice_preset_data(delegate_for,$tkey)] > 0} {
			if {[winfo exists $w.info1]} {
				$w.info1 configure -text {}
				$w.info2 configure -text "You are a delegate for: [join $dice_preset_data(delegate_for,$tkey) {, }]"
			}
			if {$MAIN_MENU ne {}} {
				foreach player $dice_preset_data(delegate_for,$tkey) {
					$MAIN_MENU.play.delegatemenu add command -label $player -command [list DisplayChatMessage {} $player]
				}
				$MAIN_MENU.play entryconfigure "Access Die Rolls For*" -state normal
			}
		} else {
			if {[winfo exists $w.info2]} {
				$w.info2 configure -text "You are not a delegate for any users."
			}
			if {$MAIN_MENU ne {}} {
				$MAIN_MENU.play entryconfigure "Access Die Rolls For*" -state disabled
			}
		}
	} else {
		if {[winfo exists $w.info1]} {
			$w.info1 configure -text "Loading delegate data from server..."
		}
		update
		RefreshDelegates $w
	}
	if {[winfo exists $w.lb] && [info exists dice_preset_data(delegates,$tkey)]} {
		set existing [$w.lb get 0 end]
		foreach delegate $dice_preset_data(delegates,[root_user_key]) {
			if {[lsearch -exact $existing $delegate] < 0} {
				set updated true
				$w.lb insert end $delegate
				lappend delegates $delegate
			}
		}
		if {$updated} {
			$w.info1 configure -text "List updated from server (click Refresh to update again)"
		}
	}
}

#
# The existence of the preferences dictionary is a relative latecomer
# to the application. The various configurable parameters are already
# implemented as global variables (for the most part). Until some
# future refactoring changes all the code to read from the preferences
# dict, we'll just use this function to set the variables based on what
# was loaded into the preferences dictionary at this point.
#
proc ApplyDebugProtocol {enabled} {
	if {$enabled} {
		::gmaproto::set_debug ::DEBUGp
	} else {
		::gmaproto::set_debug {}
	}
}
proc applyServerSideConfiguration {} {
	global ServerSideConfiguration
	global SERVER_MKDIRpath SCPserver SCPdest ModuleID CURLserver

	if {$ServerSideConfiguration ne {}} {
		if {[dict exists $ServerSideConfiguration MkdirPath] && [set v [dict get $ServerSideConfiguration MkdirPath]] ne {}} {
			if {$v ne $SERVER_MKDIRpath} {
				INFO "Server requests server-side mkdir path to be changed from \"$SERVER_MKDIRpath\" to \"$v\""
				set SERVER_MKDIRpath $v
			}
		}
		if {[dict exists $ServerSideConfiguration ImageBaseURL] && [set v [dict get $ServerSideConfiguration ImageBaseURL]] ne {}} {
			if {$v ne $CURLserver} {
				INFO "Server requests server-side image base URL to be changed from \"$CURLserver\" to \"$v\""
				set CURLserver $v
			}
		}
		if {[dict exists $ServerSideConfiguration ModuleCode] && [set v [dict get $ServerSideConfiguration ModuleCode]] ne {}} {
			if {$v ne $ModuleID} {
				INFO "Server requests module ID to be changed from \"$ModuleID\" to \"$v\""
				set ModuleID $v
			}
		}
		if {[dict exists $ServerSideConfiguration SCPDestination] && [set v [dict get $ServerSideConfiguration SCPDestination]] ne {}} {
			if {$v ne $SCPdest} {
				INFO "Server requests server-side image destination path to be changed from \"$SCPdest\" to \"$v\""
				set SCPdest $v
			}
		}
		if {[dict exists $ServerSideConfiguration ServerHostname] && [set v [dict get $ServerSideConfiguration ServerHostname]] ne {}} {
			if {$v ne $SCPserver} {
				INFO "Server requests content server host to be changed from \"$SCPserver\" to \"$v\""
				set SCPserver $v
			}
		}
	}
}
proc ApplyPreferences {data args} {
	global colortheme TimerScope
	global animatePlacement blur_all blur_pct DEBUG_level debug_protocol
	global dark_mode IThost ImageFormat ITpassword ITport
	global GuideLineOffset GuideLines MajorGuideLines MajorGuideLineOffset
	global ModuleID MasterClient SuppressChat ChatTranscript local_user
	global OptPreload ButtonSize ChatHistoryLimit CURLpath CURLserver
	global CURLproxy SCPproxy SERVER_MKDIRpath NCpath SCPpath SCPdest SCPserver
	global SSHpath UpdateURL CurrentProfileName _preferences CURLinsecure

	set _preferences $data
	set majox 0
	set mamoy 0
	set minox 0
	set minoy 0
	set username {}
	set current_profile {}
	set servers {}
	set cprof {}

	if {[dict exists $data scaling]} {
		tk scaling -displayof . [dict get $data scaling]
	}

	gmautil::dassign $data \
		animate      animatePlacement \
		button_size  ButtonSize \
		curl_path    CURLpath \
		curl_insecure CURLinsecure \
		dark         dark_mode \
		debug_level  DEBUG_level \
		debug_proto  debug_protocol \
		{guide_lines major interval} MajorGuideLines \
		{guide_lines major offsets x} majox \
		{guide_lines major offsets y} majoy \
		{guide_lines minor interval} GuideLines \
		{guide_lines minor offsets x} minox \
		{guide_lines minor offsets y} minoy \
		image_format ImageFormat \
		keep_tools   MasterClient \
		preload      OptPreload \
		profiles     servers \
		current_profile cprof

	if {[lsearch -exact $args -override] < 0} {
		set CurrentProfileName $cprof
	}

	if {$CurrentProfileName ne {}} {
		if {[set idx [::gmaprofile::find_server_index $data $CurrentProfileName]] >= 0} {
			gmautil::dassign [lindex $servers $idx] \
				host            IThost \
				port            ITport \
				username	username  \
				password        ITpassword \
				curl_proxy 	CURLproxy \
				blur_all 	blur_all \
				blur_pct	blur_pct  \
				suppress_chat   SuppressChat \
				chat_limit 	ChatHistoryLimit \
				chat_log 	ChatTranscript \
				curl_server 	CURLserver \
				update_url 	UpdateURL \
				module_id       ModuleID \
				server_mkdir 	SERVER_MKDIRpath \
				nc_path 	NCpath \
				scp_path 	SCPpath \
				scp_dest 	SCPdest \
				scp_server 	SCPserver \
				scp_proxy 	SCPproxy \
				ssh_path        SSHpath
		} else {
			set CurrentProfileName {}
		}
	}
		
	setDarkMode $dark_mode
	set blur_pct [expr max(0, min(100, $blur_pct))]
	ApplyDebugProtocol $debug_protocol
	if {$ImageFormat ne {gif} && $ImageFormat ne {png}} {
		set ImageFormat gif
	}
	set GuideLineOffset [list $minox $minoy]
	set MajorGuideLineOffset [list $majox $majoy]
	if {$username ne {}} {
		set local_user $username
	}
	applyServerSideConfiguration
	create_main_menu [dict get $data menu_button]
	set TimerScope [dict get $data show_timers]
}

set PreferencesData {}
set CurrentProfileName {}
proc editPreferences {} {
	global PreferencesData preferences_path
	set PreferencesData [::gmaprofile::editor .preferences $PreferencesData]
	::gmaprofile::save $preferences_path $PreferencesData
	ApplyPreferences $PreferencesData
	if {[tk_messageBox -type yesno -default no -icon warning -title "Restart Mapper?" -parent . \
		-message "Some preferences will only take effect when the mapper is restarted. Do you wish to go ahead and restart the mapper now? (If you do, it will be started with the same command-line arguments as were used to start this instance.)"\
	]} {
		restartMapper
	}
}

proc restartMapper {} {
	global argv0
	global argv
	global env
	set searchlist {}
	set err {unknown error}
	set tries {}
	if {[info exists env(GMA_WISH)]} {
		lappend searchlist $env(GMA_WISH)
	}
	lappend searchlist wish8.7 wish8.6 wish -

	foreach i $searchlist {
		if {$i eq {-}} {
			DEBUG 1 "Trying to run $argv0 $argv"
			puts "Trying to run $argv0 $argv"
			if {![catch {exec $argv0 {*}$argv &} err]} {
				exit 0
			}
			lappend tries " -  $argv0 $argv"
		} else {
			if {[set cmd [::gmautil::searchInPath $i]] eq {}} {
				DEBUG 1 "Skipping $i; not found in \$PATH"
				puts "Skipping $i; not found in \$PATH"
				lappend tries "(skipped $i since it was not in your PATH)"
				continue
			}
			DEBUG 1 "Trying to run $cmd $argv0 $argv"
			puts "Trying to run $cmd $argv0 $argv"
			if {![catch {exec $cmd $argv0 {*}$argv &} err]} {
				exit 0
			}
			lappend tries " -  $cmd $argv0 $argv"
		}
	}
	
	tk_messageBox -parent . -type ok -icon error -title "Unable to restart" -message "Sorry, we were unable to relaunch the mapper. If you want to restart it, you need to manually exit and restart the mapper." -detail "$err\n\nWe tried:\n[join $tries \n]"
	return
}


#
# Load preferences from disk if possible
#
# First, look for --preferences <path> in the command args
for {set i 0} {$i < $argc} {incr i} {
	if {[lindex $argv $i] eq {--preferences} && $i+1 < $argc} {
		set preferences_path [lindex $argv $i+1]
		INFO "Using alternative preferences file $preferences_path"
		break
	}
}

set allowLegacy false
if {[file exists $preferences_path]} {
	if {[catch {
		set PreferencesData [::gmaprofile::load $preferences_path]
		::gmaprofile::fix_missing PreferencesData
		ApplyPreferences $PreferencesData
	} err]} {
		tk_messageBox -type ok -icon error -title "Unable to load preferences" -message "The preferences settings could not be loaded from \"$preferences_path\"." -detail $err -parent .
		set PreferencesData [::gmaprofile::default_preferences]
		set CurrentProfileName {}
		ApplyPreferences $PreferencesData
	}
} else {
	# give PreferencesData a reasonable default but don't load it up.
	# This enables us to use the preferences editor on that variable later.
	set PreferencesData [::gmaprofile::default_preferences]
	set CurrentProfileName {}
	set _preferences $PreferencesData
	set allowLegacy true
}

create_main_menu [dict get $PreferencesData menu_button]

#
# Runtime Argument Processing
# These may override what we just read from the preferences file
#
report_progress "parsing configuration and command-line arguments"
proc usage {} {
	global argv0
	global GMAMapperVersion
	global stderr
	global ChatHistoryLimit

	puts $stderr "This is mapper, version $GMAMapperVersion"
	puts $stderr "Usage: $argv0 \[-display name\] \[-geometry value\] \[other wish options...\] -- \[--help]"
	puts $stderr {        [-A] [-a] [-B] [-b pct] [-C file] [-D] [-d] [-f fmt]}
	puts $stderr {        [-G n[+x[:y]]] [-g n[+x[:y]]] [-h hostname] [-k] [-l] [-M moduleID]}
	puts $stderr {        [-n] [-P pass] [-p port] [-S profile] [-t transcriptfile] [-u name]}
	puts $stderr {        [-x proxyurl] [-X proxyhost] [--button-size size] [--chat-history n]}
	puts $stderr {        [--curl-path path] [--curl-url-base url] [--dark] [--debug-protocol]}
	puts $stderr {        [--mkdir-path path] [--nc-path path] [--no-animate] [--no-blur-all]}
	puts $stderr {        [--preferences path] [--scp-dest dir]}
	puts $stderr {        [--scp-path path] [--scp-server hostname] [--ssh-path path] [--update-url url]}
	puts $stderr {        [--recursionlimit n]}
	puts $stderr {Each option and its argument must appear in separate CLI parameters (words).}
	puts $stderr {   -A, --animate:     Enable animation of drawing onto the map}
	puts $stderr {   -a, --no-animate:  Suppress animation of drawing onto the map}
	puts $stderr {   -B, --blur-all:    Apply --blur-hp to all creatures, not just monsters}
	puts $stderr {       --no-blur-all: Cancel the effect of --blur-all [default]}
	puts $stderr {   -b, --blur-hp:     Change imprecision factor for health bar displays (0 for full precision) [0]}
	puts $stderr {       --button-size: Set button size to "small" (default), "medium", or "large"}
	puts $stderr {   -C, --config:      Read options from specified file (subsequent options further modify)}
	puts $stderr {   -d, --dark:        Adjust colors for dark mode}
	puts $stderr {   -D, --debug:       Increase debug output level}
	puts $stderr {       --debug-protocol: Show a transcript of network I/O data in debug window}
	puts $stderr {   -f, --image-format: Image format for map graphics (png or gif)}
	puts $stderr {   -G, --major:       Set major grid guidlines every n (offset by x and/or y)}
	puts $stderr {   -g, --guide:       Set minor grid guidlines every n (offset by x and/or y)}
	puts $stderr {       --help:        Print this information and exit}
	puts $stderr {   -h, --host:        Hostname for initiative tracker [none]}
	puts $stderr {   -k, --keep-tools:  Don't allow remote disabling of the toolbar}
	puts $stderr {   -L, --list-profiles: Print available profiles you can use with --select}
	puts $stderr {   -l, --preload:     Load all cached images at startup}
	puts $stderr {   -M, --module:      Set module ID (SaF GM role only)}
	puts $stderr {   -n, --no-chat:		Do not display incoming chat messages}
	puts $stderr {   -P, --password:    Password to log in to the map service}
	puts $stderr {   -p, --port:        Port for initiative tracker [2323]}
	puts $stderr {       --recursionlimit: set runtime recursion limit}
	puts $stderr {   -S, --select:      Select server profile (but don't make it the default)}
	puts $stderr {   -t, --transcript:  Specify file to record a transcript of chat messages and die rolls.}
	puts $stderr {   -u, --username:    Set the name you go by on your game server}
	puts $stderr {   -x, --proxy-url:   Proxy url for retrieving image data (usually like -x http://proxy.example.com:8080)}
	puts $stderr {   -X, --proxy-host:  SOCKS 5 proxy host and port for SSH/SCP (usually like -X proxy.example.com:8080)}
	global CURLpath CURLserver SCPpath SSHpath SCPdest SCPserver NCpath SERVER_MKDIRpath
	puts $stderr "   --chat-history:   number of chat messages to retain between sessions \[$ChatHistoryLimit\]"
	puts $stderr "   --curl-path:      pathname of curl command to invoke \[$CURLpath\]"
	puts $stderr "   --curl-url-base:  base URL for stored data \[$CURLserver\]"
	puts $stderr "   --mkdir-path:     pathname of server-side mkdir command \[$SERVER_MKDIRpath\]"
	puts $stderr "   --nc-path:        pathname of nc command to invoke \[$NCpath\]"
	puts $stderr "   --preferences:    pathname of alternative preferences.json file (may NOT be in a config file)"
	puts $stderr "   --scp-dest:       server-side top-level storage directory \[$SCPdest\]"
	puts $stderr "   --scp-path:       pathname of scp command to invoke \[$SCPpath\]"
	puts $stderr "   --scp-server:     storage server hostname \[$SCPserver\]"
	puts $stderr "   --ssh-path:       pathname of ssh command to invoke \[$SSHpath\]"
	puts $stderr "   --update-url:     base URL to automatically download software updates from."
	exit 1
}

set optlist $argv
set optc $argc

proc getarg {opt} {
	global optlist optc stderr
	upvar argi i

	if {[incr i] < $optc} {
		return [lindex $optlist $i]
	}
	puts $stderr "Option $opt requires a parameter!"
	usage
}

#
# Load from mapper.conf ONLY if we didn't already find a new-style preferences file first
#
if {$allowLegacy && [file exists $default_config]} {
	set optc [expr $optc + 2]
	set optlist [linsert $optlist 0 --config $default_config]
}

for {set argi 0} {$argi < $optc} {incr argi} {
	set option [lindex $optlist $argi]
	switch -exact -- $option {
		-a - --no-animate {
				set animatePlacement 0
		}
		-A - --animate  {
				set animatePlacement 1
		}
		-B - --blur-all { set blur_all 1 }
		--no-blur-all   { set blur_all 0 }
		-b - --blur-hp  { set blur_pct [expr max(0, min(100, [getarg -b]))] }
		-C - --config {
			set config_filename [getarg -C]
			tk_messageBox -type ok -icon info -title "Legacy config file"\
				-parent . -message "The usage of legacy configuration files such as $config_filename is deprecated. Please transition your settings using \"Edit > Preferences...\" from the main menu.\n\nSupport for legacy configuration files will be removed in the future."

			set config_file [open $config_filename]
			while {[gets $config_file config_line] >= 0} {
				if {[string range $config_line 0 0] eq {#}} {
					continue
				}
				set c_args [split $config_line =]
				if {[llength $c_args] == 1} {
					# singleton argument
					incr optc
					set optlist [linsert $optlist [expr $argi + 1] "--$c_args"]
				} elseif {[llength $c_args] == 0} {
					# empty? Weird. ignore it.
				} else {
					# arg=value pair
					incr optc 2
					set optlist [linsert $optlist [expr $argi + 1] "--[lindex $c_args 0]" [join [lrange $c_args 1 end] =]]
				}
			}
			close $config_file
		}
		-c - --character { 
#				set charToAdd [split [getarg -c] :]
#				if {[llength $charToAdd] == 1} {
#					lappend charToAdd blue
#				} elseif {[llength $charToAdd] > 2} {
#					puts $stderr "Option -c syntax error: should be '-c name\[:color\]'"
#					usage
#				}
#                lappend OptAddCharacters $charToAdd
			DEBUG 0 "-c / --character command-line option is DEPRECATED and no longer supported."
			}
		-D - --debug  { incr DEBUG_level }
		--debug-protocol { ApplyDebugProtocol true }
		-d - --dark {setDarkMode 1}
		--help { usage }
		-h - --host { 
			set IThost [getarg -h] 
		}
		-f - --image-format { 
			set ImageFormat [getarg -f] 
			if {$ImageFormat ne {gif} && $ImageFormat ne {png}} {
				DEBUG 0 "Invalid --image-format (-f) value \"$ImageFormat\"; must be \"gif\" or \"png\""
				DEBUG 0 "Defaulting to gif instead."
				set ImageFormat gif
			}
		}
		-P - --password { set ITpassword [getarg -P] }
		-p - --port  { set ITport [getarg -p] }
		-g - --guide { 
			if {[llength [set GuideLines [split [getarg -g] +]]] > 1} {
				set GuideLineOffset [split [lindex $GuideLines 1] :]
				set GuideLines [lindex $GuideLines 0]
			}
			if {[llength $GuideLineOffset] == 1} {
				lappend GuideLineOffset $GuideLineOffset
			}
		}
		-G - --major { 
			if {[llength [set MajorGuideLines [split [getarg -G] +]]] > 1} {
				set MajorGuideLineOffset [split [lindex $MajorGuideLines 1] :]
				set MajorGuideLines [lindex $MajorGuideLines 0]
			}
			if {[llength $MajorGuideLineOffset] == 1} {
				lappend MajorGuideLineOffset $MajorGuideLineOffset
			}
		}
		-M - --module     { set ModuleID [getarg -M] }
		-m - --master -
		-k - --keep-tools { set MasterClient 1 }
		-n - --no-chat    { set SuppressChat 1 }
		-S - --select     { 
			set CurrentProfileName [getarg -S]
			ApplyPreferences $PreferencesData -override
		}
		-L - --list-profiles { 
			puts "The following server profiles are defined in your preferences data."
			puts "You may use one of these as the argument to the --select option (-S):"
			foreach server [dict get $PreferencesData profiles] {
				puts [format "  profile: %-20s user: %-10s host: %s:%s" \
					[dict get $server name] \
					[dict get $server username] \
					[dict get $server host] \
					[dict get $server port] \
				]
			}
			exit 0
		}
		-s - --style      { puts "The --style option is deprecated." }
		-t - --transcript { set ChatTranscript [getarg -t] }
		-u - --username   { set local_user [getarg -u] }
		-x - --proxy-url  { set CURLproxy [getarg -x] }
		-X - --proxy-host { set SCPproxy [getarg -X] }
		-l - --preload    { set OptPreload 1 }
		--button-size     { set ButtonSize [getarg --button-size] }
		--chat-history    { set ChatHistoryLimit [getarg --chat-history] }
		--curl-path   	  { set CURLpath [getarg --curl-path] }
		--curl-url-base   { set CURLserver [getarg --curl-url-base] }
		--mkdir-path 	  { set SERVER_MKDIRpath [getarg --mkdir-path] }
		--nc-path 		  { set NCpath [getarg --nc-path] }
		--scp-path 		  { set SCPpath [getarg --scp-path] }
		--scp-dest 		  { set SCPdest [getarg --scp-dest] }
		--scp-server 	  { set SCPserver [getarg --scp-server] }
		--ssh-path   	  { set SSHpath [getarg --ssh-path] }
		--generate-style-config { puts "The --generate-style-config option is deprecated." }
		--generate-config       { puts "The --generate-config option is deprecated." }
		--update-url      { set UpdateURL [getarg --update-url] }
		--upgrade-notice  { set UpgradeNotice true }
		--preferences     { getarg --preferences }
		--recursionlimit  { 
			set oldlimit [interp recursionlimit {}]
			set newlimit [interp recursionlimit {} [getarg --recursionlimit]]
			INFO "recurion limit changed from $oldlimit to $newlimit"
		}
		default {
			if {[string range $option 0 0] eq "-"} {
				usage
			} else {
				puts stderr "Invalid option: $option"
				usage
			}
		}
	}
}

set icon_size {}	; # or _30 or _40
switch -glob -- $ButtonSize {
	s* { set icon_size {} }
	m* { set icon_size {_30} }
	l* { set icon_size {_40} }
	default {
		puts stderr "Invalid value for --button-size: must be small, medium, or large."
		exit 1
	}
}

# 
# global color settings
#

set theme_fg  [::gmaprofile::preferred_color $_preferences normal_fg $colortheme]
set theme_bg  [::gmaprofile::preferred_color $_preferences normal_bg $colortheme]
set theme_bfg [::gmaprofile::preferred_color $_preferences bright_fg $colortheme]

tk_setPalette background $theme_bg
option add "*foreground" $theme_fg
set global_bg_color      $theme_bg
set check_select_color   [::gmaprofile::preferred_color $_preferences check_select $colortheme]
set check_menu_color     [::gmaprofile::preferred_color $_preferences check_menu   $colortheme]
ttk::style configure TFrame            -background $global_bg_color -foreground $theme_bfg
ttk::style configure TPanedwindow      -background $global_bg_color -foreground $theme_bfg
ttk::style configure TLabelframe       -background $global_bg_color -foreground $theme_bfg
ttk::style configure TLabelframe.Label -background $global_bg_color -foreground $theme_fg
ttk::style configure TLabel            -background $global_bg_color -foreground $theme_bfg
ttk::style configure Full.Horizontal.TProgressbar -troughcolor green
ttk::style configure Medium.Horizontal.TProgressbar -troughcolor yellow
ttk::style configure Low.Horizontal.TProgressbar -troughcolor red
ttk::style configure Expired.Horizontal.TProgressbar -troughcolor black
ttk::style configure Expired.TLabel -background black -foreground red

#
# tile ID
# 

proc normalize_zoom {z} {
	return [format %.2f $z]
}

proc tile_id {name zoom} {
	return "$name:[normalize_zoom $zoom]"
}

#
# cache file name from name and zoom
#
proc cache_filename {name zoom {frameno -1}} {
	global tcl_platform path_cache ImageFormat

	if {$tcl_platform(os) eq "Windows NT"} {
		file mkdir $path_cache
		file mkdir [file nativename [file join $path_cache _[string range $name 4 4]]]
		if {$frameno >= 0} {
			file mkdir [file nativename [file join $path_cache _[string range $name 4 4] "$name@[normalize_zoom $zoom]"]]
		}
	}
	if {$frameno >= 0} {
		return [file nativename \
			[file join $path_cache \
				_[string range $name 4 4] \
				"$name@[normalize_zoom $zoom]"\
				":$frameno:$name@[normalize_zoom $zoom].$ImageFormat"\
			]\
		]
	} else {
		return [file nativename [file join $path_cache _[string range $name 4 4] "$name@[normalize_zoom $zoom].$ImageFormat"]]
	}
}
proc cache_file_dir {name {zoom 1} {frameno -1}} {
	global path_cache
	if {$frameno >= 0} {
		return [file nativename \
			[file join $path_cache \
				_[string range $name 4 4] \
				"$name@[normalize_zoom $zoom]"\
			]\
		]
	}
	return [file nativename [file join $path_cache _[string range $name 4 4]]]
}
proc cache_map_filename {id} {
	global tcl_platform path_cache

	if {$tcl_platform(os) eq "Windows NT"} {
		file mkdir $path_cache
		file mkdir [file nativename [file join $path_cache [string range $id 0 0]]]
	}
	return [file nativename [file join $path_cache [string range $id 0 0] "$id.map"]]
}
proc cache_map_file_dir {id} {
	global path_cache
	return [file nativename [file join $path_cache [string range $id 0 0]]]
}

#
# get cache file info
#   pathname -> {exists? age(days) name zoom frame}
#   if the name is in an invalid format, name and zoom are empty strings
#
proc cache_info {cache_filename} {
	global ImageFormat tcl_platform

	DEBUG 1 "cache_info($cache_filename) starts"
	if {$tcl_platform(os) eq "Windows NT"} {
		set rpath [file normalize $cache_filename]
	} else {
		set rpath $cache_filename
	}
	if {[regexp [format "%s%s" {/(:[0-9]+:)?([^/]+)@([0-9.]+)\.} $ImageFormat] $rpath _ image_frame image_name image_zoom]} {
		if {[file exists $cache_filename]} {
			return [list 1 [expr ([clock seconds] - [file mtime $cache_filename]) / (24*60*60)] $image_name $image_zoom $image_frame]
		}
		return [list 0 0 $image_name $image_zoom $image_frame]
	}
	if {[regexp {/([^/]+)@([0-9.]+)$} $rpath _ image_name image_zoom] && [file isdirectory $cache_filename]} {
		DEBUG 1 "file $cache_filename is a directory; name=$image_name zoom=$image_zoom"
		return [list 1 0 $image_name $image_zoom -dir]
	}
	if {[regexp {/([^/]+)\.map} $rpath x map_name]} {
		if {[file exists $cache_filename]} {
			return [list 1 [expr ([clock seconds] - [file mtime $cache_filename]) / (24*60*60)] $map_name {} {}]
		}
		return [list 0 0 $map_name {} {}]
	}
		
	return [list 0 0 {} {} {}]
}

#
# load an image from cache file
#
proc create_image_from_file {tile_id filename} {
	global TILE_SET
	global ImageFormat

	if {[catch {set image_file [open $filename r]} err]} {
		DEBUG 1 "Can't open image file $filename ($tile_id): $err"
		return
	}
	fconfigure $image_file -encoding binary -translation binary
	if {[catch {set image_data [read $image_file]} err]} {
		DEBUG 0 "Can't read data from image file $filename ($tile_id): $err"
		close $image_file
		return
	}
	close $image_file
	if {[info exists TILE_SET($tile_id)]} {
		DEBUG 1 "Replacing existing image $TILE_SET($tile_id) for $tile_id"
		image delete $TILE_SET($tile_id)
		unset TILE_SET($tile_id)
	}
	if {[catch {set TILE_SET($tile_id) [image create photo -format $ImageFormat -data $image_data]} err]} {
		DEBUG 0 "Can't use data read from image file $filename ($tile_id): $err"
		return
	}
}

proc create_animated_frame_from_file {tile_id frameno filename} {
	global TILE_ANIMATION
	global ImageFormat

	if {[catch {set image_file [open $filename r]} err]} {
		DEBUG 1 "Can't open image file $filename ($tile_id, frame $frameno): $err"
		return
	}
	fconfigure $image_file -encoding binary -translation binary
	if {[catch {set image_data [read $image_file]} err]} {
		DEBUG 0 "Can't read data from image file $filename ($tile_id, frame $frameno): $err"
		close $image_file
		return
	}
	close $image_file
	animation_add_frame $tile_id $frameno [image create photo -format $ImageFormat -data $image_data]
}

proc CleanupImageCache {daysOld} {
	global path_cache ImageFormat cache_too_old_days
	set deleted 0
	set total 0

	if {$daysOld eq {-update}} {
		INFO "Freshening cached images..."
	} else {
		INFO "Removing cached images older than $daysOld days..."
	}

	foreach cache_dir [glob -nocomplain -directory $path_cache _*] {
		INFO "Scanning $cache_dir..."
		update
		foreach cache_filename [glob -nocomplain -directory $cache_dir *.$ImageFormat] {
			incr total
			set cache_stats [cache_info $cache_filename]
			if {[lindex $cache_stats 4] eq "-dir"} {
				# animated image (directory of frame files)
				set delall false
				foreach cache_frame [glob -nocomplain -directory $cache_filename *.$ImageFormat] {
					incr total
					lassign [cache_info $cache_frame] frame_exists frame_age frame_name frame_zoom frame_frame
					if {$daysOld eq {-update}} {
						INFO "Cached image frame $frame_name at $frame_zoom frame $frame_frame age $frame_age"
						update
						if {$frame_age <= $cache_too_old_days} {
							file delete $cache_frame
							INFO "--Removing cache file $cache_frame to force refresh"
							incr deleted
							update
						}
					} elseif {$frame_age >= $daysOld} {
						set delall true
						break
					}
				}
				if {$delall} {
					INFO "--Removing all frames of $cache_filename"
					update
					file delete -force -- $cache_filename
					incr deleted
				}
			} else {
				lassign $cache_stats image_exists image_age image_name image_zoom
				if {$daysOld eq {-update}} {
					INFO "Cached image $image_name at $image_zoom age $image_age"
					update
					if {$image_age <= $cache_too_old_days} {
						file delete $cache_filename
						INFO "--Removing cache file $cache_filename to force refresh"
						incr deleted
						update
					}
					::gmaproto::query_image $image_name $image_zoom
				} elseif {$image_age >= $daysOld} {
					INFO "--Removing cache file $cache_filename"
					file delete $cache_filename
					incr deleted
				}
			}
		}
	}
	INFO [format "Removed %d of %d cache file%s" $deleted $total [expr $total==1? {{}} : {{s}}]]
	update
}

#
# preload all the cached images into the map
#
proc load_cached_images {} {
	global cache_too_old_days path_cache ImageFormat

DEBUG 1 "Loading cached images"
	puts "preloading cached images..."
	set i 0
	foreach cache_dir [glob -nocomplain -directory $path_cache _*] {
		DEBUG 2 "-scanning $cache_dir"
		foreach cache_filename [glob -nocomplain -directory $cache_dir *.$ImageFormat] {
			set cache_stats [cache_info $cache_filename]
			if {[incr i] % 20 == 0} {
				puts -nonewline .
				if {$i % 100 == 0} {
					puts -nonewline $i
				}
				flush stdout
			}
			if {![lindex $cache_stats 0]} {
				DEBUG 1 "Cache file $cache_filename disappeared!"
				continue
			}
			if {[lindex $cache_stats 4] eq "-dir"} {
				DEBUG 2 "$cache_filename is an animated image directory"
				set frame_path_parts [file split $cache_filename]
				set frame0_path [file join $cache_filename ":0:[lindex $frame_path_parts end].$ImageFormat"]
				set frame0_stats [cache_info $frame0_path]
				if {[lindex $frame0_stats 2] eq {} || [lindex $frame0_stats 3] eq {}} {
					DEBUG 1 "Cache frame 0 of $cache_filename not recognized (ignoring, but it shouldn't be there.)"
					continue
				}
				if {[lindex $frame0_stats 1] >= $cache_too_old_days} {
					DEBUG 2 "Not pre-loading cache file $cache_filename for [lindex $frame0_stats 2] at zoom [lindex $frame0_stats 3] because it is [lindex $frame0_stats 1] days old."
					continue
				}
				DEBUG 2 "Pre-loading cacheed animated image files $cache_filename/... for [lindex $cache_stats 2] at zoom [lindex $cache_stats 3]."
				if {[catch {
					set animation_meta [animation_read_metadata $cache_filename \
									[lindex $cache_stats 2] \
									[lindex $cache_stats 3]]
					_load_local_animated_file $cache_filename [lindex $cache_stats 2] [lindex $cache_stats 3]\
						[dict get $animation_meta Animation Frames]\
						[dict get $animation_meta Animation FrameSpeed]\
						[dict get $animation_meta Animation Loops]
				} err]} {
					DEBUG 1 "Cached animated file $cache_filename could not be loaded: $err"
				}
				continue
			}
			if {[lindex $cache_stats 2] eq {} || [lindex $cache_stats 3] eq {}} {
				DEBUG 1 "Cache file $cache_filename not recognized (ignoring, but it shouldn't be there.)"
				continue
			}
			if {[lindex $cache_stats 1] >= $cache_too_old_days} {
				DEBUG 2 "Not pre-loading cache file $cache_filename for [lindex $cache_stats 2] at zoom [lindex $cache_stats 3] because it is [lindex $cache_stats 1] days old."
				continue
			}
			DEBUG 2 "Pre-loading cache file $cache_filename for [lindex $cache_stats 2] at zoom [lindex $cache_stats 3]."
			create_image_from_file [tile_id [lindex $cache_stats 2] [lindex $cache_stats 3]] $cache_filename
		}
	}
	puts $i
}
report_progress "managing cache"
if {[file exists $path_cache]} {
	DEBUG 1 "Looking for old-style cache files to move"
	set filelist [glob -nocomplain -types f -directory $path_cache -tails *.gif]
	set f [glob -nocomplain -types f -directory $path_cache -tails *.png]
	if {[llength $f] > 0} {
		lappend filelist {*}$f
	}
	foreach old_cache $filelist {
		set new_location [cache_file_dir $old_cache]
		set old_location [file join $path_cache $old_cache]
		INFO "Moving old image file $old_location -> $new_location"
		puts "Moving old image cache file $old_location -> $new_location"

		if {! [file isdirectory $new_location]} {
			if {[file exists $new_location]} {
				say "The file $new_location should be a directory. Having it there will confuse the mapper's cache."
				break
			} else {
				file mkdir $new_location
			}
		}
		file rename $old_location $new_location
	}

	foreach old_cache [glob -nocomplain -types f -directory $path_cache -tails *.map] {
		set new_location [cache_map_file_dir $old_cache]
		set old_location [file join $path_cache $old_cache]
		INFO "Moving old map file $old_location -> $new_location"
		puts "Moving old map cache file $old_location -> $new_location"

		if {! [file isdirectory $new_location]} {
			if {[file exists $new_location]} {
				say "The file $new_location should be a directory. Having it there will confuse the mapper's cache."
				break
			} else {
				file mkdir $new_location
			}
		}
		file rename $old_location $new_location
	}


	DEBUG 1 "Expiring old cache files"
	puts "Cleaning up cache..."
	foreach cache_filename [glob -nocomplain -types f -directory $path_cache *] {
		DEBUG 2 "-$cache_filename"
		if {[clock seconds] - [file mtime $cache_filename] > 15552000} {
			DEBUG 2 "-$cache_filename is older than 6 months, removing it"
			if {[catch {file delete $cache_filename} err]} {
				DEBUG 0 "Unable to delete old cache file $cache_filename: $err"
			}
		}
	}
}

if {[file exists $path_log_dir]} {
	DEBUG 1 "Expiring old log files"
	puts "Cleaning up logs..."
	foreach log_pattern {mapper.*.log mapper-errors.*.log mapper.*.stdout mapper.*.stderr} {
		foreach log_filename [glob -nocomplain -types f -directory $path_log_dir $log_pattern] {
			if {[clock seconds] - [file mtime $log_filename] > 15552000} {
				DEBUG 2 "-$log_filename is older than 6 months, removing it"
				if {[catch {file delete $log_filename} err]} {
					DEBUG 0 "Unable to delete old log file $log_filename: $err"
				}
			}
		}
	}
}
report_progress "Setting up UI"
#
#
#

if {[catch {
	foreach app_icon_size {512 256 128 48 32 16} {
		set icon_gma_$app_icon_size [image create photo -format png -file "${ICON_DIR}/gma_icon_${app_icon_size}.png"]
	}
} err]} {
	DEBUG 0 "Your version of Tcl/Tk does not appear to support PNG-format graphics files."
	DEBUG 0 "(error was $err)"
	DEBUG 0 "Reverting to GIF-format data files now."
	set ImageFormat gif
	foreach app_icon_size {512 256 128 48 32 16} {
		set icon_gma_$app_icon_size [image create photo -format gif -file "${ICON_DIR}/gma_icon_${app_icon_size}.gif"]
	}
}
wm iconphoto . -default $icon_gma_512 $icon_gma_256 $icon_gma_128 $icon_gma_48 $icon_gma_32 $icon_gma_16
catch {
	wm iconphoto .debugwindow -default $icon_gma_512 $icon_gma_256 $icon_gma_128 $icon_gma_48 $icon_gma_32 $icon_gma_16
}


set _icon_format gif
foreach icon_name {
	line rect poly circ arc *blank play colorwheel
	arc_pieslice arc_chord arc_arc
	join_round join_miter join_bevel
	spline_0 spline_1 spline_2 spline_3 spline_4 spline_5
	spline_6 spline_7 spline_8 spline_9
	fill_color outline_color fill no_fill
	snap_0 snap_1 snap_2 snap_3 snap_4
	width_0 width_1 width_2 width_3 width_4
	width_5 width_6 width_7 width_8 width_9
	cut save open merge exit clear clear_players combat group_go
	style textfield_add anchor_center anchor_n anchor_w anchor_e anchor_s
	anchor_ne anchor_nw anchor_se anchor_sw
	stamp zoom_in zoom_out zoom unload wand wandbound radius cone ray spread no_spread ruler
	shape_square_go dash0 dash24 dash44 dash64 dash6424 dash642424 
	arrow_both arrow_first arrow_none arrow_last arrow_refresh heart
	saf saf_open saf_merge saf_unload saf_group_go die16 die16c information info20 die20 die20c
	dbracket_t dbracket_m dbracket_b dbracket__
	delete add clock dieb16 -- *hourglass *hourglass_go *arrow_right *cross *bullet_go menu
	stipple_100 stipple_75 stipple_50 stipple_25 stipple_12 stipple_88 lock unlock bullet_arrow_down bullet_arrow_right
	bullet_arrow_down16 bullet_arrow_right16 tmrq pencil die16g die16success die16fail star smstar
} {
	if {$icon_name eq {--}} {
		if {$ImageFormat eq {png}} {
			set _icon_format png
		}
		continue
	}

	if {[string range $icon_name 0 0] eq "*"} {
		set all_sizes true
		set icon_name [string range $icon_name 1 end]
	} else {
		set all_sizes false
	}

	if {$tcl_platform(os) ne "Darwin" && $dark_mode && [file exists "${ICON_DIR}/d_${icon_name}${icon_size}.$_icon_format"]} {
		set icon_filename "${ICON_DIR}/d_${icon_name}${icon_size}.$_icon_format"
	} else {
		set icon_filename "${ICON_DIR}/${icon_name}${icon_size}.$_icon_format"
	}
	set icon_$icon_name [image create photo -format $_icon_format -file $icon_filename]

	if {$all_sizes} {
		foreach {sz fsz} {16 {} 30 _30 40 _40} {
			if {$dark_mode && [file exists "${ICON_DIR}/d_${icon_name}${fsz}.$_icon_format"]} {
				set icon_filename "${ICON_DIR}/d_${icon_name}${fsz}.$_icon_format"
			} else {
				set icon_filename "${ICON_DIR}/${icon_name}${fsz}.$_icon_format"
			}
			set icon_${icon_name}_$sz [image create photo -format $_icon_format -file $icon_filename]
		}
	}
}

catch {
	.toolbar2.menu configure -image $icon_menu
}

set canvas [canvas .c -height $canh -width $canw -scrollregion [list 0 0 $cansw $cansh] -xscrollcommand {.xs set} -yscrollcommand {.ys set}]

grid [frame .toolbar] -sticky ew
grid .toolbar2 -sticky ew
grid .c [scrollbar .ys -orient vertical -command {battleGridScroller .c yview}] -sticky news
grid [scrollbar .xs -orient horizontal -command {battleGridScroller .c xview}]  -sticky  ew
label .c.distanceLabel -textvariable DistanceLabelText
bind $canvas <Shift-1> "PingMarker $canvas %x %y"

set LastFileComment {}

proc display_message {msg} {
	global ClockDisplay

	catch {set ClockDisplay $msg}
	catch {puts $msg}
	catch {update}
}

proc LetterLabel {x} {
	set l [string index ABCDEFGHIJKLMNOPQRSTUVWXYZ [expr $x % 26]]
	set x [expr $x/26]
	while {$x > 0} {
		incr x -1
		set l "[string index ABCDEFGHIJKLMNOPQRSTUVWXYZ [expr $x % 26]]$l"
		set x [expr $x/26]
	}
	return $l
}

proc battleGridScroller {w view args} {
	$w $view {*}$args
	battleGridLabels
}

proc battleGridLabels {} {
	global cansw cansh iscale dark_mode
	global _preferences colortheme
	set gridcolor [::gmaprofile::preferred_color $_preferences grid $colortheme]
	lassign [.xs get] xstartfrac xendfrac
	lassign [.ys get] ystartfrac yendfrac

	.c delete {x#label}
	set startpx [expr int($xstartfrac * $cansw)]
	set endpx [expr int($xendfrac * $cansw)]
	set startgrid [CanvasToGrid $startpx]
	set endgrid [CanvasToGrid $endpx]
	set ypx [expr int($ystartfrac * $cansh)]
	for {set xbox $startgrid} {$xbox <= $endgrid} {incr xbox} {
		.c create text [expr [GridToCanvas $xbox]+($iscale/2.0)] $ypx -tags "x#label" -anchor n -justify center -text [LetterLabel $xbox] -fill $gridcolor
	}

	.c delete {y#label}
	set startpx [expr int($ystartfrac * $cansh)]
	set endpx [expr int($yendfrac * $cansh)]
	set startgrid [CanvasToGrid $startpx]
	set endgrid [CanvasToGrid $endpx]
	set xpx [expr int($xstartfrac * $cansw)]
	for {set ybox $startgrid} {$ybox <= $endgrid} {incr ybox} {
		.c create text $xpx [expr [GridToCanvas $ybox]+($iscale/2.0)] -tags "y#label" -anchor w -justify left -text $ybox -fill $gridcolor
	}
}


set ShowToolBar 1
proc toolBarState {state} {
    global toolbar_current_state MAIN_MENU ShowToolBar
    	if {$state == -1} {
		set state $ShowToolBar
	}
	if {$state} {
		grid configure .toolbar -row 0 -column 0 -sticky ew
#		if {$MAIN_MENU ne {}} {
#			${MAIN_MENU}.view entryconfigure *Toolbar -label "Hide Toolbar" -command {toolBarState 0}
#		}
	} else {
		grid forget .toolbar 
#		if {$MAIN_MENU ne {}} {
#			${MAIN_MENU}.view entryconfigure *Toolbar -label "Show Toolbar" -command {toolBarState 1}
#		}
	}
}


grid \
     [button .toolbar.line -image $icon_line -command linetool] \
	 [button .toolbar.rect -image $icon_rect -command recttool] \
	 [button .toolbar.poly -image $icon_poly -command polytool] \
	 [button .toolbar.circ -image $icon_circ -command circtool] \
	 [button .toolbar.arc  -image $icon_arc  -command arctool] \
	 [button .toolbar.text -image $icon_textfield_add -command texttool] \
	 [button .toolbar.mode -image $icon_blank -command {}] \
	 [button .toolbar.mode2 -image $icon_blank -command {}] \
	 [button .toolbar.mode3 -image $icon_blank -command {}] \
     [button .toolbar.nil  -image $icon_play -command playtool] \
	 [button .toolbar.kill -image $icon_cut  -command killtool] \
	 [button .toolbar.move -image $icon_shape_square_go -command movetool] \
	 [button .toolbar.stamp -image $icon_stamp        -command stamptool] \
	 [label  .toolbar.sp1  -text "   "] \
	 [button .toolbar.nfill -image $icon_no_fill -command toggleNoFill]\
	 [button .toolbar.cfill -image $icon_fill_color -bg $initialColor -command {colorpick fill}] \
	 [button .toolbar.cline -image $icon_outline_color -bg $initialColor -command {colorpick line}] \
	 [button .toolbar.cstip -image $icon_stipple_100 -command {cycleStipple -cycle}] \
	 [button .toolbar.snap -image $icon_snap_0 -command {gridsnap -cycle}] \
	 [button .toolbar.width -image [set icon_width_$initialwidth] -command {setwidth -cycle}] \
	 [label  .toolbar.sp2  -text "   "] \
	 [button .toolbar.clear -image $icon_clear -command {cleargrid; ::gmaproto::clear E*}] \
	 [button .toolbar.clearp -image $icon_clear_players -command {clearplayers *; ::gmaproto::clear P*; ::gmaproto::clear M*}] \
	 [label  .toolbar.sp3  -text "   "] \
	 [button .toolbar.combat -image $icon_combat -command togglecombat] \
	 [button .toolbar.showhp -image $icon_heart -command toggleShowHealthStats] \
	 [button .toolbar.aoe -image $icon_wand -command aoetool] \
	 [button .toolbar.aoebound -image $icon_wandbound -command aoeboundtool] \
	 [button .toolbar.ruler -image $icon_ruler -command rulertool] \
	 [button .toolbar.griden -image $icon_snap_1 -command toggleGridEnable] \
	 [button .toolbar.chat -image $icon_die20 -command {DisplayChatMessage {} {}}] \
	 [button .toolbar.iniclock -image $icon_clock -command {display_initiative_clock}] \
	 [button .toolbar.tmrq -image $icon_tmrq -command {initiate_timer_request}] \
	 [label  .toolbar.sp4  -text "   "] \
	 [button .toolbar.zi   -image $icon_zoom_in -command {zoomInBy 2}] \
	 [button .toolbar.zo   -image $icon_zoom_out -command {zoomInBy 0.5}] \
	 [button .toolbar.refresh -image $icon_zoom -command resetZoom] \
	 [button .toolbar.load -image $icon_open -command {loadfile {}}] \
	 [button .toolbar.merge -image $icon_merge -command {loadfile {} -merge}] \
	 [button .toolbar.unload -image $icon_unload -command {unloadfile {}}] \
	 [button .toolbar.sync -image $icon_blank -command {} -state disabled] \
	 [button .toolbar.saf  -image $icon_saf -command toggleSafMode] \
	 [button .toolbar.polo -image $icon_arrow_refresh -command SyncFromServer] \
	 [button .toolbar.save -image $icon_save -command savefile] \
	 [button .toolbar.exit -image $icon_exit -command exitchk] 

grid [label   .toolbar2.clock -anchor w -font {Helvetica 18} -textvariable ClockDisplay]         -row 0 -column 1 -sticky we 
grid [ttk::progressbar .toolbar2.progbar -orient horizontal -length 200 -variable ClockProgress] -row 0 -column 2 -sticky e
grid columnconfigure .toolbar2 1 -weight 2
grid forget .toolbar2.progbar

proc configureChatCapability {} {
	global icon_blank IThost

	if {$IThost eq {}} {
		.toolbar.chat configure -image $icon_blank -state disabled
		::tooltip::tooltip .toolbar.chat "Chat/die roll tool is not available unless connected to a server."
		.toolbar.iniclock configure -image $icon_blank -state disabled
		::tooltip::tooltip .toolbar.iniclock "Game clock tool is not available unless connected to a server."
	}
}

proc configureSafCapability {} {
	global SCPdest SCPserver icon_blank

	if {$SCPdest eq {} || $SCPserver eq {}} {
		.toolbar.saf configure -image $icon_blank -state disabled
		
	}
}

set SafMode 0
proc toggleSafMode {} {
	global SafMode icon_blank icon_saf_group_go
	playtool
	if {[set SafMode [expr !$SafMode]]} {
		# SaF mode: you can't draw things in this mode
		foreach btn {line rect poly circ arc text mode mode2 mode3 stamp aoe aoebound} {
			.toolbar.$btn configure -image $icon_blank -state disabled
		}
		foreach {function icon} {
			load open merge merge unload unload sync group_go
		} {
			global icon_saf_$icon
			.toolbar.$function configure -image [set icon_saf_$icon]
		}
		.toolbar.saf configure -relief sunken
		.toolbar.sync configure -image $icon_saf_group_go -state normal -command SyncAllClientsToMe
		::tooltip::tooltip .toolbar.sync {Push this map to all other clients (USE THIS WITH CARE)}
	} else {
		foreach {function icon} {
			load open merge merge unload unload sync group_go
		} {
			global icon_$icon
			.toolbar.$function configure -image [set icon_$icon]
		}
		.toolbar.saf configure -relief raised
		foreach {btn img} {line line rect rect poly poly circ circ arc arc text textfield_add 
						   mode blank mode2 blank mode3 blank stamp stamp aoe wand aoebound wandbound} {
			global icon_$img
			.toolbar.$btn configure -image [set icon_$img] -state normal
		}
		.toolbar.sync configure -image $icon_blank -state disabled -command {}
		::tooltip::tooltip clear .toolbar.sync
	}
}
grid columnconfigure . 0 -weight 1
grid rowconfigure    . 2 -weight 1
#grid rowconfigure    . 1 -weight 1

foreach {btn tip} {
	line	{Mode Select: Line Drawing}
	rect	{Mode Select: Rectangle Drawing}
	poly	{Mode Select: Polygon Drawing}
	circ	{Mode Select: Circle Drawing}
	arc		{Mode Select: Arc Drawing}
	text    {Mode Select: Add Text}
	mode	{}
	mode2	{}
	nil		{Mode Select: Normal Play Mode}
	iniclock {Display Initiative Clock Window}
	tmrq    {Request a New Timer}
	kill	{Mode Select: Delete Objects}
	move	{Mode Select: Move Objects}
	stamp	{Mode Select: Stamp Images/Textures}
	nfill	{Toggle Fill/No-Fill Mode}
	cstip	{Cycle Fill Pattern}
	cfill	{Select Fill Color}
	cline	{Select Outline Color}
	snap	{Cycle Grid Snap (none/full/half/third/quarter)}
	width	{Cycle Line Width (0-9)}
	clear	{Remove all map objects}
	clearp	{Remove all creature tokens}
	combat	{Toggle combat mode}
	showhp	{Toggle display of actual health stats}
	aoe		{Set spell Area of Effect}
	aoebound {Set bounded AoE (experimental)}
	ruler	{Measure grid distances along a path}
	griden  {Toggle visible gridlines}
	chat    {Open die roller/chat window}
	zi		{Zoom in}
	zo		{Zoom out}
	refresh {Reset to default zoom level}
	load	{Load map file (overwrite current map)}
	merge	{Merge map file (add to current map)}
	unload	{Unload objects from file}
	sync	{}
	polo	{Sync game state from server}
	saf   	{Toggle store-and-forward mode}
	save	{Save map to file}
	exit	{Exit mapper application}
} {
	if {$tip eq {}} {
		::tooltip::tooltip clear .toolbar.$btn
	} else {
		::tooltip::tooltip .toolbar.$btn $tip
	}
}

proc exitchk {} {
	global OBJ_MODIFIED OBJ_FILE

	if {$OBJ_MODIFIED 
	&& [tk_messageBox -parent . -type yesno -default no -icon warning -title "Abandon changes to $OBJ_FILE?"\
		-message "You have unsaved changes to this map.  Do you want to abandon them and exit anyway?"]\
		ne "yes"} {
		return
	}
	exit
}

set NoFill 0
proc _showNoFill {} {
	global NoFill

	if {$NoFill} {
		.toolbar.nfill configure -relief sunken
		.toolbar.cfill configure -state disabled
	} else {
		.toolbar.nfill configure -relief raised
		.toolbar.cfill configure -state normal
	}
}

proc toggleNoFill {} {
	global NoFill

	if {$NoFill} {
		set NoFill 0
	} else {
		set NoFill 1
	}
	_showNoFill
}

set StipplePattern {nil}
proc cycleStipple {{newStipple -cycle}} {
	global StipplePattern MAIN_MENU
	global icon_stipple_100 icon_stipple_75 icon_stipple_50 icon_stipple_25 icon_stipple_12 icon_stipple_88

	if {$newStipple eq {-cycle}} {
		switch -exact -- $StipplePattern {
			"nil"		{ set n 12; set i 88 }
			"gray12"	{ set n 25; set i 75 }
			"gray25"	{ set n 50; set i 50 }
			"gray50"	{ set n 75; set i 25 }
			"gray75"	{ set n 100; set i 100 }
			default		{ set n 100; set i 100 }
		}
	} else {
		switch -exact -- $newStipple {
			"gray12"	{ set n 12; set i 88 }
			"gray25"	{ set n 25; set i 75 }
			"gray50"	{ set n 50; set i 50 }
			"gray75"	{ set n 75; set i 25 }
			"nil"		{ set n 100; set i 100 }
			default		{ set n 100; set i 100 }
		}
	}

	if {$n == 100} {
		.toolbar.cstip configure -image $icon_stipple_100
		set StipplePattern {nil}
	} else {
		if {[catch {
			.toolbar.cstip configure -image [set icon_stipple_$i]
			set StipplePattern "gray$n"
		} err]} {
			DEBUG 1 "Unable to set stipple pattern $StipplePattern on toolbar button: $err"
			.toolbar.cstip configure -image $icon_stipple_100
			set StipplePattern {nil}
		}
	}
}


set ShowHealthStats 0

proc toggleShowHealthStats {} {
	global ShowHealthStats

	set ShowHealthStats [expr !$ShowHealthStats]
	RefreshMOBs
}


proc setcombatfrommenu {} {
	global MOB_COMBATMODE
	setCombatMode $MOB_COMBATMODE
	::gmaproto::combat_mode $MOB_COMBATMODE
}

proc togglecombat {} {
	global MOB_COMBATMODE
	setCombatMode [expr !$MOB_COMBATMODE]
	::gmaproto::combat_mode $MOB_COMBATMODE
}

proc SyncFromServer {} {
	cleargrid
	clearplayers *
	::gmaproto::sync
	::gmaproto::watch_operation "Syncing game state"
}

proc ReconnectToServer {} {
	::gmaproto::redial
}

set DHS_Saved_ClockDisplay {}

proc blur_hp {maxhp lethal} {
	global blur_pct

	if {$blur_pct <= 0 || $maxhp <= $lethal} {
		return [expr $maxhp - $lethal]
	} else {
		if {[catch {
			set mf [expr $maxhp * ($blur_pct / 100.0)]
			set res [expr max(1, int(int(($maxhp - $lethal) / $mf) * $mf))]
		} err]} {
			DEBUG 1 "Error calculating blurred HP total: $err; falling back on true value"
			return [expr $maxhp - $lethal]
		}
		return $res
	}
}

proc CreateHealthStatsToolTip {mob_id {extra_condition {}}} {
	global MOBdata
	if {$mob_id eq {} || ![info exists MOBdata($mob_id)]} {
		return {}
	}

	# get the list of applied conditions
	set conditions {}
	set has_health_info false
	set dead [dict get $MOBdata($mob_id) Killed]

	if {[dict exists $MOBdata($mob_id) Health] && [dict get $MOBdata($mob_id) Health] ne {}} {
		set has_health_info true
		::gmautil::dassigndef [dict get $MOBdata($mob_id) Health] \
			MaxHP 		maxhp \
			LethalDamage 	lethal \
			NonLethalDamage	nonlethal \
			Con 		con \
			IsFlatFooted 	flatp \
			IsStable 	stablep \
			HPBlur		server_blur_pct \
			Condition	condition \
			TmpHP		{tmp_hp 0} \
			TmpDamage	{tmp_damage 0}
		if {$condition ne {}} {
			switch -exact -- $condition {
				dead { set dead true }
				flat { lappend conditions flat-footed }
				default { lappend conditions $condition }
			}
		}

		# Really, we shouldn't be calculating this here because we're just
		# reporting it. the data SHOULD already be correct before we get it.
		# So I'm removing the calculations that used to be here and trusting
		# that we are being sent reliable data (this also helps us see if there's
		# an upstream bug so the mapper isn't somehow compensating for it by recalculating
		# the hitpoints locally for display).
		#
		#if {$nonlethal > ($maxhp + $tmp_hp - $tmp_damage)} {
			#set lethal [expr $lethal + ($nonlethal - $maxhp)]
			#set nonlethal $maxhp
		#}
		#set true_hp_remaining [expr $maxhp + $tmp_hp - $tmp_damage - $lethal]
	}

	if {[llength [set statuslist [dict get $MOBdata($mob_id) StatusList]]] > 0} {
		lappend conditions {*}$statuslist
	}

	if {$extra_condition ne {} && [lsearch -exact $conditions $extra_condition] < 0} {
		lappend conditions $extra_condition
	}

	if {$has_health_info} {
		if {$flatp && [lsearch -exact $conditions flat-footed] < 0} {lappend conditions flat-footed}
		if {$stablep && [lsearch -exact $conditions stable] < 0} {lappend conditions stable}
		set tiptext "[::gmaclock::nameplate_text [dict get $MOBdata($mob_id) Name]]:"

		global blur_all blur_pct
		set client_blur {}
		set server_blur {}
		set hp_temporary {}
		if {$blur_all || [dict get $MOBdata($mob_id) CreatureType] != 2} {
			set hp_remaining [blur_hp [expr $maxhp+$tmp_hp-$tmp_damage] $lethal]
			if {$blur_pct > 0} {
				set client_blur [format "(\u00B1%d%%)" $blur_pct]
			}
		} else {
			set hp_remaining [expr ($maxhp+$tmp_hp-$tmp_damage) - $lethal]
		}
		if {$server_blur_pct > 0} {
			# server blur overrides local one
			set client_blur {}
			set hp_remaining [expr ($maxhp+$tmp_hp-$tmp_damage) - $lethal]
			set server_blur [format "\u00B1%d%%" $server_blur_pct]
		}
		if {!$dead} {
			if {[dict get $MOBdata($mob_id) CreatureType] == 2} {
				# player
				if {($maxhp+$tmp_hp-$tmp_damage) == 0} {
					# we don't know the total hp (yet?) so just say how much damage they have
					if {$lethal == 0} {
						append tiptext " no lethal wounds"
					} else {
						append tiptext [format " %d%s%s lethal wounds" $lethal $client_blur $server_blur]
					}
				} else {
					if {$tmp_hp > 0} {
						set hp_temporary [format " (+%d temporary hp)" $tmp_hp]
					}
					append tiptext [format " %d/%d%s%s%s HP" $hp_remaining $maxhp $hp_temporary $client_blur $server_blur]
				}
				if {$nonlethal != 0} {
					append tiptext [format " (%d non-lethal)" $nonlethal]
				}
			} else {
				# not a player; so we're not quite as direct about health status
				if {($maxhp+$tmp_hp-$tmp_damage) == 0} {
					# we don't know the creatures's hit point total
					append tiptext [format " %d%s%s lethal damage" $lethal $client_blur $server_blur]
					if {$nonlethal != 0} {
						append tiptext [format " (%d non-lethal)" $nonlethal]
					}
				} else {
					# otherwise we know more about what the damage means in context
					if {$lethal > ($maxhp+$tmp_hp-$tmp_damage)} {
						if {[lsearch -exact $conditions dying] < 0} {
							lappend conditions dying
						} 
					} else {
						# n%+x+x
						append tiptext [format " %d%%%s%s HP" [expr (100 * $hp_remaining)/($maxhp+$tmp_hp-$tmp_damage)] $client_blur $server_blur]
						if {$nonlethal != 0 && ($maxhp+$tmp_hp-$tmp_damage) != $lethal} {
							append tiptext [format " (%d%% of remaining hp non-lethal)" [expr (100*$nonlethal)/$hp_remaining]]
						}
					}
				}
			}
		} else {
			append tiptext " dead."
		}
	} else {
		set tiptext "[::gmaclock::nameplate_text [dict get $MOBdata($mob_id) Name]]: \[no health info\]"
	}

	if {[set elevation [dict get $MOBdata($mob_id) Elev]] != 0} {
		append tiptext [format "; elevation %d ft" $elevation]
	}
	switch -exact -- [set movemode [::gmaproto::from_enum MoveMode [dict get $MOBdata($mob_id) MoveMode]]] {
		land - {} {
		}
		fly - climb - burrow {
			append tiptext [format " (%sing)" $movemode]
		}
		swim {
			append tiptext " (swimming)"
		}
		default {
			append tiptext [format " (%s)" $movemode]
		}
	}

	# add conditions
	global MarkerDescription

	foreach status $conditions {
		if {[info exists MarkerDescription($status)]} {
			append tiptext "\n[reflowText 80 $MarkerDescription($status)]"
		} else {
			append tiptext "\n$status."
		}
	}

	return $tiptext
}


proc reflowText {maxlen text} {
	set output {}
	set current {}
	foreach word [split $text] {
		if {[string length $current] + [llength $current] + [string length $word] >= $maxlen} {
			lappend output [join $current]
			set current [list "    " $word]
		} else {
			lappend current $word
		}
	}
	if {[llength $current] > 0} {
		lappend output [join $current]
	}
	return [join $output "\n"]
}

proc setCombatMode {mode} {
	global MOB_COMBATMODE MOB_BLINK ClockDisplay
	
	set MOB_COMBATMODE $mode
	if {[::gmaclock::exists .initiative.clock]} {
		::gmaclock::combat_mode .initiative.clock $mode
	}
	.toolbar.combat configure -relief [expr $MOB_COMBATMODE ? {{sunken}} : {{raised}}]
	if {$MOB_COMBATMODE} {
#		bind . <Key-comma> "MobTurn prev"
#		bind . <Key-period> "MobTurn next"
	} else {
#		bind . <Key-comma> {}
#		bind . <Key-period> {}
		set MOB_BLINK {}
		set ClockDisplay {}
	}
#	global MobTurnID
#	set MobTurnID 0
	RefreshMOBs
}

#
# drawing objects
#   OBJdata(<id>)		<dict>
#   OBJtype(<id>)		<type>
#
#---OLD---
#  OBJ(TYPE:<id>)   line|rect|arc|circ|poly
#  OBJ(X:<id>)      origin x
#  OBJ(Y:<id>)      origin y
#  OBJ(POINTS:<id>) 
#		line: {x2 y2 x3 y3 x4 y4 ...}
#  OBJ(FILL:<id>)  color
#  OBJ(LINE:<id>)  color
#  OBJ(WIDTH:<id>) line width
## OBJ(LAYER:<id>)  layerID
#
#set OBJ_NEXT_ID 0
set OBJ_NEXT_Z 0
set OBJ_MODE nil
set d_OBJ_MODE nil
set OBJ_SNAP 0
set OBJ_COLOR(fill) $initialColor
set OBJ_COLOR(line) $initialColor
set OBJ_WIDTH $initialwidth
set OBJ_MODIFIED 0
set TX_QUEUE_STATUS {}
set OBJ_FILE "untitled"

#
# merge an element into the current grid, renumbering
# it so as not to collide with existing object ID
# numbers.
#
# return the new ID number
#

#
# To support Store-and-Forward mode, saf_loadfile
# ensures that the server has the most up-to-date version
# of <file> and that we can download a copy of it to
# our cache.
#
# interacts with the user and returns true if successful
proc map_modtime {filename desc} {
	if {[catch {set f [open $filename]} err]} {
		tk_messageBox -type ok -icon error -title "Error opening file"\
			-message "Unable to open $desc: $err" -parent .
		return -1
	}
	if {[catch {set file_metadata [lindex [::gmafile::load_from_file $f] 0]} err ]} {
		tk_messageBox -type ok -icon error -title "Error reading file"\
			-message "Unable to read from $desc file $filename: $err" -parent .
		return -1
	}
	close $f
	if {![dict exists $file_metadata Timestamp]} {
		return 0
	}

	return [dict get $file_metadata Timestamp]
}

proc saf_loadfile {file oldcd args} {
	global ClockDisplay

	set server_id [cache_map_id $file]
	if {$args ne {-nocheck}} {
		if {[catch {set cache_filename [fetch_map_file $server_id]} err]} {
			DEBUG 1 "saf_loadfile: fetch_map_file $server_id failed: $err"
			if {$err eq {NOSUCH}} {
				# not on server yet
				set ClockDisplay "$file not yet on server. Sending..."
				update
				if {[catch {send_file_to_server $server_id $file} err]} {
					tk_messageBox -type ok -icon error -title "Error sending file"\
						-message "Unable to send $file to server: $err" -parent .
					set ClockDisplay $oldcd
					return 0
				}
				if {[catch {set cache_filename [fetch_map_file $server_id]} err]} {
					tk_messageBox -type ok -icon error -title "Error sending file"\
						-message "Uploaded $file but still can't get it from the server: $err" -parent .
					set ClockDisplay $oldcd
					return 0
				}
			} else {
				tk_messageBox -type ok -icon error -title "Error opening file"\
					-message "Unable to check server-side copy of $file: $err" -parent .
				return 0
			}
		}
		# At this point we have a cached copy of the file
		if {[set cache_mtime [map_modtime $cache_filename "cached server-side copy of $file"]] < 0} {
			set ClockDisplay $oldcd
			return 0
		}

		if {$cache_mtime <= 0} {
			tk_messageBox -type ok -icon warning -title "Can't see file metadata"\
				-message "Can't get server-side file's timestamp from metadata; sending new copy over to be safe." -parent .
		}
	} else {
		set cache_mtime 0	; # force send if we're unconditionally sending anyway
	}
	set source_mtime [map_modtime $file "source copy of $file"]
	if {$cache_mtime < $source_mtime} {
		set ClockDisplay "Sending new copy to server..."
		DEBUG 1 "Cached file $cache_mtime, source $source_mtime"
		update
		if {[catch {send_file_to_server $server_id $file} err]} {
			tk_messageBox -type ok -icon error -title "Error sending file"\
				-message "Unable to send $file to server: $err" -parent .
			set ClockDisplay $oldcd
			return 0
		}
		if {[catch {set cache_filename [fetch_map_file $server_id]} err]} {
			tk_messageBox -type ok -icon error -title "Error sending file"\
				-message "Uploaded $file but still can't get it from the server: $err" -parent .
			set ClockDisplay $oldcd
			return 0
		}
	}
	return 1
}

# loadfile file ?-merge? ?-nosend? ?-force?
# Load the contents of the named file into memory and display.
#   if file is empty, prompt user to select one.
#   -force: ignore unsaved changes
#   -merge:	don't erase the current contents first
#   -nosend: don't send the loaded elements to peers as well.

proc loadfile {file args} {
	global LastFileComment OBJ_MODIFIED OBJ_FILE
#	global okToLoadMonsters okToLoadPlayers
	global ClockDisplay
	global SafMode
	global TILE_ID
	global MOBdata MOBid OBJdata OBJtype
	global canvas
	global ImageFormat

	set mergep false
	set sendp true
	set forcep false
	set sendflag {-send}
	if {[lsearch -exact $args -force] >= 0} { set forcep true }
	if {[lsearch -exact $args -merge] >= 0} { set mergep true }
	if {[lsearch -exact $args -nosend] >= 0} { set sendp false; set sendflag {} }

	set LastFileComment {}
	if {$OBJ_MODIFIED && !$mergep && !$forcep && [tk_messageBox \
		-type yesno -default no -icon warning \
		-title "Abandon changes to $OBJ_FILE?"\
		-message "You have unsaved changes to this map. Do you want to abandon them and load a new map anyway?"\
		-parent .\
	] ne "yes"} {
		return
	}

	if {$file eq {}} {
		if {[set file [tk_getOpenFile -defaultextension .map -filetypes {
			{{GMA Mapper Files} {.map}}
			{{All Files} *}
		} -parent . -title "Load current map from..."]] eq {}} {
			return
		}
	}

	set oldcd $ClockDisplay
	
	#
	# Store-and-Forward Mode:
	#  (1) Ensure we have a cached version from the server
	#  (2) If we don't, or it's older than the local one, upload the local file to the server and try again
	#  (3) Send CLR unless merging then M@ to peers
	#  (4) Proceed to load the local file
	#
	if {$SafMode} {
		if {![saf_loadfile $file $oldcd]} {
			return
		}
		# Now the server has an updated version of our file and we confirmed we can
		# download it.
		# Tell the others
		if {$sendp} {
			::gmaproto::load_from [cache_map_id $file] false $mergep
			set sendp false
		}
		set ClockDisplay $oldcd
	}

	while {[catch {
        set f [open $file r]
    } err]} {
		if {[tk_messageBox -type retrycancel -icon error -default cancel -title "Error opening file"\
			-message "Unable to open $file: $err" -parent .] eq "cancel"} {
				return
		}
	}

	if {!$mergep} {
		cleargrid
	}

	if {[catch {
		set file_data [::gmafile::load_from_file $f]
		close $f
	} err]} {
		say "Error loading map data from file: $err"
		catch {close $f}
		return
	}

	lassign $file_data meta_data record_data		;# record data is {{type dict} ...}
	set ClockDisplay "Loading [dict get $meta_data Location]..."
	update

	set progress_id [begin_progress * "Loading map data" [llength $record_data] $sendflag]
	set progress_i 0
	if {[catch {
		foreach record $record_data {
			update_progress $progress_id [incr progress_i] [llength $record_data] $sendflag
			update
			lassign $record element_type d
			switch -exact -- $element_type {
				IMG {
					DEBUG 2 "Defining image $d"
					set aframes 0
					set aspeed 0
					set aloops 0
					set image_id [dict get $d Name]
					foreach instance [dict get $d Sizes] {
						DEBUG 2 "... $instance"
						if {![dict get $instance IsLocalFile]} {
							DEBUG 3 "Image is supposed to be on the server. Retrieving..."
							::gmautil::dassign $instance Zoom image_zoom File image_filename
							if {[dict get $d Animation] ne {} && [dict get $d Animation Frames] > 0} {
								DEBUG 3 "Image is animated"
								::gmautil::dassign $d {Animation Frames} aframes \
										      {Animation FrameSpeed} aspeed \
										      {Animation Loops} aloops
								fetch_animated_image $image_id $image_zoom $image_filename $aframes $aspeed $aloops
								#animation_init [tile_id $image_id $image_zoom] $aframes $aspeed $aloops
							} else {
								fetch_image $image_id $image_zoom $image_filename
								set TILE_ID([tile_id $image_id $image_zoom]) $image_filename
							}
						} else {
							if {[dict get $d Animation] ne {} && [dict get $d Animation Frames] > 0} {
								DEBUG 3 "Image is animated"
								::gmautil::dassign $d {Animation Frames} aframes \
										      {Animation FrameSpeed} aspeed \
										      {Animation Loops} aloops
								if {[catch {
									_load_local_animated_file $image_filename $image_id \
										$image_zoom $aframes $aspeed $aloops
								} err]} {
									DEBUG 1 "Can't open $image_filename: $err"
									continue
								}
							} else {
								if {[catch {set image_file [open $image_filename r]} err]} {
									DEBUG 1 "Can't open image file $image_filename for $image_id at zoom $image_zoom: $err"
									continue
								}
								fconfigure $image_file -encoding binary -translation binary
								if {[catch {set image_data [read $image_file]} err]} {
									DEBUG 0 "Can't read data from image file $image_filename: $err"
									close $image_file
									continue
								}
								close $image_file

								if {[info exists TILE_SET([tile_id $image_id $image_zoom])]} {
									DEBUG 1 "Replacing existing image $TILE_SET([tile_id $image_id $image_zoom]) for ${image_id} x$image_zoom"
									image delete $TILE_SET([tile_id $image_id $image_zoom])
									unset TILE_SET([tile_id $image_id $image_zoom])
								}
								if {[catch {set TILE_SET([tile_id $image_id $image_zoom]) [image create photo -format $ImageFormat -data $image_data]} err]} {
									DEBUG 0 "Can't use data read from image file $image_filename: $err"
									continue
								}
								DEBUG 3 "Created image $TILE_SET([tile_id $image_id $image_zoom]) for $image_id, zoom $image_zoom len=[string length $image_data]"
								#
								# Looks like the image is valid.  Send it to everyone else too...
								# This is deprecated but we'll do it anyway for now.
								#
								if {$sendp} {
									DEBUG 0 "Sending raw image data like this is deprecated. You should upload image files to the server instead and just refernce them in map files."
									::gmaproto::add_image $image_id [list [dict create ImageData $image_data Zoom $image_zoom]]
								}
							}
						}
					}
					if {$sendp} {
						::gmaproto::add_image $image_id [dict get $d Sizes] $aframes $aspeed $aloops
					}
				}
				MAP {
					set map_id [dict get $d File]
					DEBUG 2 "Defining map file $map_id"
					if {[catch {
						set cache_filename [fetch_map_file $map_id]
						DEBUG 1 "Pre-load: map ID $map_id cached as $cache_filename"
					} err]} {
						if {$err eq {NOSUCH}} {
							DEBUG 0 "We were asked to pre-load map file with ID $map_id but the server doesn't have it"
						} else {
							say "Error retrieving map ID $map_id from server: $err"
						}
					}
					if {$sendp} {
						::gmaproto::load_from $map_id true false
					}
				}
				CREATURE - PS {
					dict set d Name [AcceptCreatureImageName [dict get $d Name]]
					PlaceSomeone $canvas $d
					if {$sendp} {
						::gmaproto::place_someone_d [InsertCreatureImageName $d]
					}
				}
				default {
					if {[catch {set etype [::gmaproto::GMATypeToObjType $element_type]} err]} {
						DEBUG 0 "Can't load element of unknown type $element_type ($err)."
						continue
					}
					if {[catch {
						set OBJdata([dict get $d ID]) [::gmaproto::normalize_dict $element_type $d]
					} err]} {
						DEBUG 0 "input type $element_type: $err"
						set OBJdata([dict get $d ID]) $d
					}

					set OBJtype([dict get $d ID]) $etype
					if {$sendp} {
						::gmaproto::ls $element_type $d
					}
				}
			}
		}
		end_progress $progress_id $sendflag
	} err]} {
		say "Failed to import data: $err"
		return
	}

	RefreshGrid false
	RefreshMOBs
	modifiedflag $file false
	set ClockDisplay $oldcd
	update
}
# TODO use explicit -force (was implied before by !-nosend)
# TODO make sure commands that send updates to peers don't when we're the receiver

# unloadfile file ?-nosend? ?-force?
proc unloadfile {file args} {
	global OBJdata OBJ_FILE OBJ_MODIFIED SafMode ClockDisplay

	set sendp true
	set forcep false
	if {[lsearch -exact $args -force] >= 0}  {set forcep true}
	if {[lsearch -exact $args -nosend] >= 0} {set sendp false}

	if {$file eq {}} {
		if {[set file [tk_getOpenFile -defaultextension .map -filetypes {
			{{GMA Mapper Files} {.map}}
			{{All Files}        *}
		} -parent . -title "Delete elements from..."]] eq {}} return
	}

    #
    # If we're being told remotely to do this, don't prompt the user
    # 
    if {!$forcep} {
        if {[tk_messageBox -type yesno -default no -icon warning -title "Remove Elements?" -parent .\
            -message "Do you really want to DELETE all elements from file $file?"] ne "yes"} {
            return
        }
    }

	set oldcd $ClockDisplay

	#
	# Store-and-Forward Mode:
	#  (1) Ensure we have a cached version from the server
	#  (2) If we don't, or it's older than the local one, upload the local file to the server and try again
	#  (3) Send CLR@ to peers
	#  (4) Proceed to unload the local file
	#
	if {$SafMode} {
		if {![saf_loadfile $file $oldcd]} {
			return
		}
		# Now the server has an updated version of our file and we confirmed we can
		# download it.
		# Tell the others
		if {$sendp} {
			::gmaproto::clear_from [cache_map_id $file]
		}
		set ClockDisplay $oldcd
		set sendp false
	}


	while {[catch {set f [open $file r]} err]} {
		if {[tk_messageBox -type retrycancel -icon error -default cancel -title "Error opening file"\
			-message "Unable to open $file: $err" -parent .] eq "cancel"} {
				return
		}
	}

	if {[catch {
		set file_data [::gmafile::load_from_file $f]
		close $f
	} err]} {
		say "Error unloading map data from file: $err"
		catch {close $f}
		return
	}
	lassign $file_data meta_data record_data
	foreach record $record_data {
		lassign $record rec_type d
		if {[dict exists $d ID]} {
			if {$sendp} {
				KillObjById [dict get $d ID]
			} else {
				KillObjById [dict get $d ID] -nosend
			}
		}
	}
	RefreshGrid false
}

proc parent_geometry_ctr {{w .}} {
	if {![regexp {^(\d+)x(\d+)([+-]\d+)([+-]\d+)$} [winfo geometry $w] _ g_w g_h g_x g_y]} {
		set g_x 0
		set g_y 0
		set g_w 0
		set g_h 0
	}
	return [format %+d%+d [expr $g_x + ($g_w/2)] [expr $g_y + ($g_h/2)]]
}

proc savefile {} {
	global OBJdata OBJtype MOBdata MOBid OBJ_FILE LastFileComment LastFileLocation MOB_IMAGE

	if {[set file [tk_getSaveFile -defaultextension .map -initialfile $OBJ_FILE -filetypes {
		{{GMA Mapper Files} {.map}}
		{{All Files}        *}
	} -parent . -title "Save current map as..."]] eq {}} return

	while {[catch {set f [open $file w]} err]} {
		if {[tk_messageBox -type retrycancel -icon error -default cancel -title "Error opening file"\
			-message "Unable to open $file: $err" -parent .] eq "cancel"} {
			return
		}
	}

	set lock_objects [tk_messageBox -parent . -type yesno -icon question -title {Lock objects?} -message {Do you wish to lock all map objects in this file?} -detail {When locked, map objects cannot be further modified by clients. This helps avoid accidentally disturbing the map background while people are interacting with the map during a game.} -default yes]

	::getstring::tk_getString .meta_comment LastFileComment {Map Name/Comment:} -geometry [parent_geometry_ctr]
	::getstring::tk_getString .meta_location LastFileLocation {Map Location:} -geometry [parent_geometry_ctr]

	if {[catch {
		::gmafile::save_arrays_to_file $f [dict create\
			Comment $LastFileComment\
			Location $LastFileLocation\
		] OBJdata OBJtype MOBdata MOB_IMAGE $lock_objects
		close $f
	} err]} {
		say "Error writing map file to disk: $err"
		catch {close $f}
		return
	}

	modifiedflag $file false
}

proc modifiedflag {file state} {
	global OBJ_FILE OBJ_MODIFIED

	if {$file ne "-"} {
		set OBJ_FILE $file
	}
	set OBJ_MODIFIED $state
	refresh_title
}

proc refresh_title {} {
	global OBJ_FILE OBJ_MODIFIED TX_QUEUE_STATUS ModuleID
	global IThost ITport local_user CurrentProfileName

	if {$ModuleID ne {}} {
		set tag "\[$ModuleID\] "
	} else {
		set tag {}
	}

	if {$IThost ne {}} {
		set host "\[$local_user@$IThost:$ITport\]"
	} else {
		set host "\[offline\]"
	}

	if {$CurrentProfileName ne {}} {
		set host "${CurrentProfileName}(${host})"
	}

	if {$OBJ_MODIFIED} {
		wm title . "${tag}Mapper: $OBJ_FILE (*) $TX_QUEUE_STATUS $host"
	} else {
		wm title . "${tag}Mapper: $OBJ_FILE $TX_QUEUE_STATUS $host"
	}
}


proc colorpick {type} {
	global OBJ_COLOR

	if {[set new [tk_chooseColor -initialcolor $OBJ_COLOR($type) -parent .  -title "Object $type color"]] ne {}} {
		set OBJ_COLOR($type) $new
		.toolbar.c$type configure -bg $new
	}
}

proc RemoveObject id {
	global OBJdata OBJtype canvas animatePlacement TILE_ANIMATION

	if {[animation_obj_exists $id]} {
		animation_destroy_instance $canvas * $id
	} 
	$canvas delete obj$id
	if {$animatePlacement} update
	catch { unset OBJdata($id) }
	catch { unset OBJtype($id) }
}

proc cleargrid {} {
	global OBJdata OBJtype canvas

	set olist [array names OBJdata]
	foreach id $olist {
		RemoveObject $id
	}
	modifiedflag "untitled" 0
}

proc zoomInBy factor {
	global zoom
	global iscale
	global rscale
	global canvas

#	set oldx   [lindex [$canvas xview] 0]
#	set oldy   [lindex [$canvas yview] 0]
	set oldposition [TopLeftGridLabel]
	set zoom   [expr $zoom * $factor]
	set rscale [expr $rscale * $factor]
	set iscale [expr int($rscale)]
	refreshScreen
#	$canvas xview moveto [expr $oldx * $factor]
#	$canvas yview moveto [expr $oldy * $factor]
	ScrollToGridLabel $oldposition
}

proc resetZoom {} {
	global zoom
	global rscale
	global canvas
	if {$zoom != 1} {
#		set oldx   [lindex [$canvas xview] 0]
#		set oldy   [lindex [$canvas yview] 0]
		set oldposition [TopLeftGridLabel]
		set factor [expr 50.0 / $rscale]
		set zoom 1.0
		set rscale 50.0
		zoomInBy 1
#		$canvas xview moveto [expr $oldx * $factor]
#		$canvas yview moveto [expr $oldy * $factor]
		ScrollToGridLabel $oldposition
	}
}

set ShowMapGrid 1
proc setGridEnable {} {
	global GridEnable ShowMapGrid
	set GridEnable $ShowMapGrid
	refreshScreen
}
proc toggleGridEnable {} {
	global GridEnable
	set GridEnable [expr ! $GridEnable]
	refreshScreen
}

proc refreshScreen {} {
	global zoom canvas animatePlacement

	DrawScreen $zoom $animatePlacement
	RefreshGrid $animatePlacement
	RefreshMOBs
	DEBUG 3 "Bounding box of all on-screen objects: [$canvas bbox allOBJ allMOB]"
	DEBUG 3 "                all room features:     [$canvas bbox allOBJ]"
	DEBUG 3 "                all monsters/players:  [$canvas bbox allMOB]"
}

proc gridsnap {{newsnap -cycle}} {
	global OBJ_SNAP MAIN_MENU

	if {$newsnap eq {-cycle}} {
		set OBJ_SNAP [expr ($OBJ_SNAP + 1) % 5]
	} else {
		set OBJ_SNAP [expr $newsnap % 5]
	}
	global icon_snap_$OBJ_SNAP
	.toolbar.snap configure -image [set icon_snap_$OBJ_SNAP]
}

proc setwidth {{newwidth -cycle}} {
	global OBJ_WIDTH MAIN_MENU

	if {$newwidth eq {-cycle}} {
		set OBJ_WIDTH [expr ($OBJ_WIDTH+1)%10]
	} else {
		set OBJ_WIDTH [expr $newwidth % 10]
	}
	global icon_width_$OBJ_WIDTH
	.toolbar.width configure -image [set icon_width_$OBJ_WIDTH]
}

proc playtool {} {
	canceltool
	.toolbar.nil configure -relief sunken
}

proc canceltool {} {
	global OBJ_MODE canvas OBJ_BLINK icon_blank d_OBJ_MODE
	global BUTTON_RIGHT BUTTON_MIDDLE
	switch $OBJ_MODE {
		nil  {.toolbar.nil  configure -relief raised}
		line {.toolbar.line configure -relief raised}
		rect {.toolbar.rect configure -relief raised}
		poly {.toolbar.poly configure -relief raised}
		circ {.toolbar.circ configure -relief raised}
		arc  {.toolbar.arc  configure -relief raised}
		kill {.toolbar.kill configure -relief raised}
		aoe  {.toolbar.aoe  configure -relief raised}
		move {.toolbar.move configure -relief raised}
		ruler {.toolbar.ruler configure -relief raised}
		text {
			global CURRENT_TEXT_WIDGET
			.toolbar.text configure -relief raised
			catch {tk fontchooser hide}
			set CURRENT_TEXT_WIDGET {}
		}
		tile {.toolbar.stamp configure -relief raised}
		aoebound {.toolbar.aoebound configure -relief raised}
	}

	.toolbar.mode configure -image $icon_blank -command {}
	.toolbar.mode2 configure -image $icon_blank -command {}
	.toolbar.mode3 configure -image $icon_blank -command {}
	::tooltip::tooltip clear .toolbar.mode*

    $canvas configure -cursor iron_cross ;#left_ptr
	set_OBJ_MODE nil
	bind $canvas <Control-ButtonPress-4> {zoomInBy 2}
	bind $canvas <Control-ButtonPress-5> {zoomInBy 0.5}
    bind $canvas <Control-MouseWheel> {zoomInBy [expr {%D>0 ? 2 : 0.5}]}
	bind $canvas <1> "MOB_StartDrag $canvas %x %y"
	bind $canvas <Control-Button-1> "MOB_SelectEvent $canvas %x %y"
	bind $canvas <B1-Motion> "MOB_Drag $canvas %x %y"
	bind $canvas <B1-ButtonRelease> "MOB_EndDrag $canvas"
	bind $canvas <Motion> {}
	bind $canvas $BUTTON_MIDDLE {}
	bind $canvas $BUTTON_RIGHT "DoContext %x %y"
	bind . <Key-Escape> {}
	bind . <Key-p> {}
	bind . <Key-n> {}
	bind . <Key-x> {}
	bind . <Key-Left> {}
	bind . <Key-Right> {}
	bind . <Key-Up> {}
	bind . <Key-Down> {}
	bind . <Key-h> {}
	bind . <Key-k> {}
	bind . <Key-l> {}
	bind . <Key-j> {}
	bind . <Key-u> {}
	bind . <Key-d> {}
	bind . <Key-f> {}
	bind . <Key-b> {}
	set OBJ_BLINK {}
}

#
# This makes a special polygon which defines a global boundary
# zone to contain spells.  Only one of these is defined at a time
# on the board with the special ID AOE_GLOBAL_BOUND
#
proc set_OBJ_MODE {m} {
	global OBJ_MODE
	global d_OBJ_MODE
	set OBJ_MODE [set d_OBJ_MODE $m]
}
proc aoeboundtool {} {
	global canvas OBJ_MODE JOINSTYLE SPLINE
	global icon_join_bevel icon_spline_0
	canceltool
	bind $canvas <1> "StartObj $canvas %x %y"
	bind $canvas <Motion> "ObjDrag $canvas %x %y"
	bind $canvas <B1-Motion> "ObjDrag $canvas %x %y"
	bind $canvas <B1-ButtonRelease> {}
	.toolbar.aoebound configure -relief sunken
	$canvas configure -cursor rtl_logo
	set_OBJ_MODE aoebound
	.toolbar.mode configure -image $icon_join_bevel -command toggleJoinStyle
	.toolbar.mode2 configure -image $icon_spline_0 -command toggleSpline
	::tooltip::tooltip .toolbar.mode {Cycle join style}
	::tooltip::tooltip .toolbar.mode2 {Cycle spline level}
	set JOINSTYLE bevel
	set SPLINE 0
}

proc aoetool {} {
	global canvas OBJ_MODE AOE_SHAPE AOE_SPREAD
	global icon_radius icon_cone icon_ray icon_spread icon_no_spread
	canceltool
	bind $canvas <1> "StartObj $canvas %x %y"
	bind $canvas <Motion> "ObjAoeDrag $canvas %x %y"
	bind $canvas <B1-Motion> "ObjAoeDrag $canvas %x %y"
	bind $canvas <B1-ButtonRelease> {}
	.toolbar.aoe configure -relief sunken
	$canvas configure -cursor star
	.toolbar.mode configure -image $icon_radius -command toggleAoeShape
	.toolbar.mode2 configure -image $icon_no_spread -command toggleAoeSpread
	::tooltip::tooltip .toolbar.mode {Cycle Area Shape}
	::tooltip::tooltip .toolbar.mode2 {Toggle AoE Spread Mode (experimental)}
	set_OBJ_MODE aoe
	set AOE_SHAPE radius
	set AOE_SPREAD 0
}

proc rulertool {} {
	global canvas OBJ_MODE
	canceltool
	bind $canvas <1> "StartObj $canvas %x %y"
	bind $canvas <Motion> "ObjDrag $canvas %x %y"
	bind $canvas <B1-Motion> "ObjDrag $canvas %x %y"
	bind $canvas <B1-ButtonRelease> {}
	.toolbar.ruler configure -relief sunken
	$canvas configure -cursor crosshair
	set_OBJ_MODE ruler
}

proc linetool {} {
	global canvas OBJ_MODE ARROWSTYLE DASHSTYLE icon_arrow_none icon_dash0
	canceltool
	bind $canvas <1> "StartObj $canvas %x %y"
	bind $canvas <Motion> "ObjDrag $canvas %x %y"
	bind $canvas <B1-Motion> "ObjDrag $canvas %x %y"
	bind $canvas <B1-ButtonRelease> {}
	.toolbar.line configure -relief sunken
	$canvas configure -cursor crosshair
	.toolbar.mode2 configure -image $icon_arrow_none -command cycleArrowStyle
	.toolbar.mode3 configure -image $icon_dash0 -command cycleDashStyle
	::tooltip::tooltip .toolbar.mode2 {Cycle arrow style}
	::tooltip::tooltip .toolbar.mode3 {Cycle dash style}
	set ARROWSTYLE none
	set DASHSTYLE {}
	set_OBJ_MODE line
}

proc polytool {} {
	global canvas OBJ_MODE JOINSTYLE SPLINE
	global icon_join_bevel icon_spline_0 icon_dash0 DASHSTYLE
	canceltool
	bind $canvas <1> "StartObj $canvas %x %y"
	bind $canvas <Motion> "ObjDrag $canvas %x %y"
	bind $canvas <B1-Motion> "ObjDrag $canvas %x %y"
	bind $canvas <B1-ButtonRelease> {}
	.toolbar.poly configure -relief sunken
	$canvas configure -cursor rtl_logo
	set_OBJ_MODE poly
	.toolbar.mode configure -image $icon_join_bevel -command toggleJoinStyle
	.toolbar.mode2 configure -image $icon_spline_0 -command toggleSpline
	.toolbar.mode3 configure -image $icon_dash0 -command cycleDashStyle
	::tooltip::tooltip .toolbar.mode {Cycle join style}
	::tooltip::tooltip .toolbar.mode2 {Cycle spline level}
	::tooltip::tooltip .toolbar.mode3 {Cycle dash style}
	set JOINSTYLE bevel
	set SPLINE 0
	set DASHSTYLE {}
}

#
# text tool:
#	left click: place current text at x,y
#	right click: enter text string to use
#

set CurrentTextString {}
proc texttool {} {
	global OBJ_MODE canvas ClockDisplay
	global BUTTON_MIDDLE BUTTON_RIGHT CurrentTextString CurrentAnchor
	global icon_anchor_center icon_style
	global CURRENT_FONT CURRENT_TEXT_WIDGET
	canceltool
	set CURRENT_TEXT_WIDGET {}
	bind $canvas $BUTTON_MIDDLE {}
	bind $canvas $BUTTON_RIGHT {SelectText %x %y}
	bind $canvas <B1-ButtonRelease> {}
	bind $canvas <1> "StartObj $canvas %x %y"
	bind $canvas <B1-Motion> {}
	bind $canvas <Motion> {}
	.toolbar.mode configure -image $icon_style -command toggleFontChooser
	::tooltip::tooltip .toolbar.mode {Show/hide font chooser}
	.toolbar.mode2 configure -image $icon_anchor_center -command cycleAnchor
	::tooltip::tooltip .toolbar.mode2 {Set text anchor point direction}
	set CurrentAnchor center
	$canvas configure -cursor xterm
	.toolbar.text configure -relief sunken
	set_OBJ_MODE text
	DEBUG 3 "Selected text mode"
	set ClockDisplay $CurrentTextString
	catch {tk fontchooser configure -parent . -font [lindex $CURRENT_FONT 0] -command [list SelectFont $canvas]}
	bind . <<TkFontchooserFontChanged>> [list SelectFont $canvas]
}

proc SelectText {x y} {
	global ClockDisplay CurrentTextString 
	global _newtextstring
	set _newtextstring {}
	if {[::getstring::tk_getString .textstring _newtextstring {Text string to place:} -geometry [parent_geometry_ctr]]} {
		set CurrentTextString $_newtextstring
		set ClockDisplay $CurrentTextString
	}
}

proc cycleAnchor {} {
	global CurrentAnchor icon_anchor_center icon_anchor_n icon_anchor_s icon_anchor_e
	global icon_anchor_w icon_anchor_ne icon_anchor_se icon_anchor_nw icon_anchor_sw
	set legal_anchors [list center w nw n ne e se s sw]
	if {[set i [lsearch -exact $legal_anchors $CurrentAnchor]] < 0} {
		set i 0
	} else {
		set i [expr ($i + 1) % [llength $legal_anchors]]
	}
	set CurrentAnchor [lindex $legal_anchors $i]
	.toolbar.mode2 configure -image [set icon_anchor_$CurrentAnchor]
}



#
# stamp tool:
#	left click: place current tile at x,y
#	right click: select tile
#
set CurrentStampTile {}
proc stamptool {} {
	global OBJ_MODE canvas ClockDisplay
	global BUTTON_MIDDLE BUTTON_RIGHT CurrentStampTile
	canceltool
	bind $canvas $BUTTON_MIDDLE {}
	bind $canvas $BUTTON_RIGHT {SelectTile %x %y}
	bind $canvas <B1-ButtonRelease> {}
	bind $canvas <1> "StartObj $canvas %x %y"
	bind $canvas <B1-Motion> {}
	bind $canvas <Motion> {}
	$canvas configure -cursor star
	.toolbar.stamp configure -relief sunken
	set_OBJ_MODE tile
	DEBUG 3 "Selected stamp mode"
	set ClockDisplay $CurrentStampTile
}

#
# SelectTile x y
# 	With the cursor at (x,y), select the current tile
#	pattern from the list of existing patterns or from
#	a disk file
#
#	This sets CURRENT_TILE to this image as well as makes
#	sure that image is loaded into the mapper.
#
proc SelectTile {x y} {
	global ClockDisplay CurrentStampTile zoom
	global TILE_SET _newtilename
	set _newtilename {}
	if {[::getstring::tk_getString .tilename _newtilename {Tile base name:} -geometry [parent_geometry_ctr]]} {
		set CurrentStampTile [list [FindImage $_newtilename $zoom] $_newtilename $zoom]
		set ClockDisplay $CurrentStampTile
	}
}


proc PlaceTile {canvas x y} {
	DEBUG 0 "PlaceTile not implemented"
}

proc toggleSpline {} {
	global SPLINE

	set SPLINE [expr ($SPLINE+1) % 10]
	if {$SPLINE == 0} {
		global icon_spline_0
		.toolbar.mode2 configure -image $icon_spline_0
	} else {
		global icon_spline_$SPLINE
		.toolbar.mode2 configure -image [set icon_spline_$SPLINE]
	}
}

set ARROWSTYLE none
proc cycleArrowStyle {} {
	global ARROWSTYLE
	switch $ARROWSTYLE {
		none	{ set ARROWSTYLE first}
		first	{ set ARROWSTYLE last}
		last	{ set ARROWSTYLE both}
		both 	-
		default	{ set ARROWSTYLE none}
	}
	set newimage icon_arrow_$ARROWSTYLE
	global $newimage
	.toolbar.mode2 configure -image [set $newimage]
}

set DASHSTYLE {}
proc cycleDashStyle {} {
	global DASHSTYLE
	switch $DASHSTYLE {
		{}	    { set DASHSTYLE -   ; set dashID 64 }
		-	    { set DASHSTYLE ,   ; set dashID 44 }
		,	    { set DASHSTYLE .   ; set dashID 24 }
		.	    { set DASHSTYLE -.  ; set dashID 6424 }
		-.	    { set DASHSTYLE -.. ; set dashID 642424 }
		default { set DASHSTYLE {}  ; set dashID 0}
	}

	set newimage icon_dash$dashID
	global $newimage
	.toolbar.mode3 configure -image [set $newimage]
}

set JOINSTYLE bevel
proc toggleJoinStyle {} {
	global JOINSTYLE icon_join_miter icon_join_round icon_join_bevel

	switch $JOINSTYLE {
		bevel {set JOINSTYLE miter}
		miter {set JOINSTYLE round}
		round {set JOINSTYLE bevel}
	}
	.toolbar.mode configure -image [set icon_join_$JOINSTYLE]
}

set AOE_SHAPE radius
proc toggleAoeShape {} {
	global AOE_SHAPE icon_radius icon_cone icon_ray

	switch $AOE_SHAPE {
		radius {set AOE_SHAPE cone}
		cone   {set AOE_SHAPE ray}
		ray    {set AOE_SHAPE radius}
	}
	.toolbar.mode configure -image [set icon_$AOE_SHAPE]
}

set AOE_SPREAD 0
proc toggleAoeSpread {} {
	global AOE_SPREAD icon_spread icon_no_spread

	switch $AOE_SPREAD {
		0	{set AOE_SPREAD 1; .toolbar.mode2 configure -image $icon_spread}
		default	{set AOE_SPREAD 0; .toolbar.mode2 configure -image $icon_no_spread}
	}
}

proc recttool {} {
	global canvas OBJ_MODE 
	global icon_dash0 DASHSTYLE
	canceltool
	bind $canvas <1> "StartObj $canvas %x %y"
	bind $canvas <Motion> "ObjDrag $canvas %x %y"
	bind $canvas <B1-Motion> "ObjDrag $canvas %x %y"
	bind $canvas <B1-ButtonRelease> {}
	.toolbar.rect configure -relief sunken
	.toolbar.mode3 configure -image $icon_dash0 -command cycleDashStyle
	::tooltip::tooltip .toolbar.mode3 {Cycle dash style}
	$canvas configure -cursor dotbox
	set DASHSTYLE {}
	set_OBJ_MODE rect
}

proc circtool {} {
	global canvas OBJ_MODE
	global icon_dash0 DASHSTYLE
	canceltool
	bind $canvas <1> "StartObj $canvas %x %y"
	bind $canvas <Motion> "ObjDrag $canvas %x %y"
	bind $canvas <B1-Motion> "ObjDrag $canvas %x %y"
	bind $canvas <B1-ButtonRelease> {}
	.toolbar.circ configure -relief sunken
	.toolbar.mode3 configure -image $icon_dash0 -command cycleDashStyle
	::tooltip::tooltip .toolbar.mode3 {Cycle dash style}
	$canvas configure -cursor circle
	set_OBJ_MODE circ
	set DASHSTYLE {}
}

proc arctool {} {
	global canvas OBJ_MODE ARCMODE icon_arc_pieslice
	global icon_dash0 DASHSTYLE
	canceltool
	bind $canvas <1> "StartObj $canvas %x %y"
	bind $canvas <Motion> "ObjDrag $canvas %x %y"
	bind $canvas <B1-Motion> "ObjDrag $canvas %x %y"
	bind $canvas <B1-ButtonRelease> {}
	.toolbar.arc configure -relief sunken
	$canvas configure -cursor diamond_cross
	.toolbar.mode3 configure -image $icon_dash0 -command cycleDashStyle
	::tooltip::tooltip .toolbar.mode3 {Cycle dash style}
	set_OBJ_MODE arc
	.toolbar.mode configure -image $icon_arc_pieslice -command toggleArcMode
	::tooltip::tooltip .toolbar.mode {Cycle arc style}
	set ARCMODE pieslice
	set DASHSTYLE {}
}

proc toggleArcMode {} {
	global OBJ_CURRENT ARCMODE icon_arc_arc icon_arc_pieslice icon_arc_chord

	if {$ARCMODE eq "pieslice"} {
		set ARCMODE "chord"
	} elseif {$ARCMODE eq "chord"} {
		set ARCMODE "arc"
	} else {
		set ARCMODE "pieslice"
	}
	.toolbar.mode configure -image [set icon_arc_$ARCMODE]
}

proc killtool {} {
	global OBJ_MODE canvas
	global BUTTON_MIDDLE BUTTON_RIGHT
	canceltool
	bind $canvas $BUTTON_MIDDLE {}
	bind $canvas $BUTTON_RIGHT {}
	bind $canvas <B1-ButtonRelease> {}
	bind $canvas <1> "KillObjUnderMouse $canvas %x %y"
	bind $canvas <B1-Motion> {}
	bind $canvas <Motion> {}
	bind . <Key-p> "KillObj prev"
	bind . <Key-n> "KillObj next"
	bind . <Key-x> "KillObj kill"
	$canvas configure -cursor pirate
	.toolbar.kill configure -relief sunken
	set_OBJ_MODE kill
	DEBUG 3 "Selected kill mode"
}

proc movetool {} {
	global OBJ_MODE canvas
	global BUTTON_MIDDLE BUTTON_RIGHT
	canceltool
	bind $canvas $BUTTON_MIDDLE {}
	bind $canvas $BUTTON_RIGHT {}
	bind $canvas <B1-ButtonRelease> "MoveObjEndDrag $canvas"
	bind $canvas <1> "MoveObjUnderMouse $canvas %x %y"
	bind $canvas <B1-Motion> "MoveObjDrag $canvas %x %y"
	bind . <Key-u> "NudgeObjectZ $canvas up"
	bind . <Key-d> "NudgeObjectZ $canvas down"
	bind . <Key-f> "NudgeObjectZ $canvas front"
	bind . <Key-b> "NudgeObjectZ $canvas back"
	bind . <Shift-Key-h> "NudgeObject $canvas -10 0"
	bind . <Shift-Key-l> "NudgeObject $canvas 10 0"
	bind . <Shift-Key-k> "NudgeObject $canvas 0 -10"
	bind . <Shift-Key-j> "NudgeObject $canvas 0 10"
	bind . <Key-h> "NudgeObject $canvas -1 0"
	bind . <Key-l> "NudgeObject $canvas 1 0"
	bind . <Key-k> "NudgeObject $canvas 0 -1"
	bind . <Key-j> "NudgeObject $canvas 0 1"
	bind . <Shift-Key-Left> "NudgeObject $canvas -10 0"
	bind . <Shift-Key-Right> "NudgeObject $canvas 10 0"
	bind . <Shift-Key-Up> "NudgeObject $canvas 0 -10"
	bind . <Shift-Key-Down> "NudgeObject $canvas 0 10"
	bind . <Key-Left> "NudgeObject $canvas -1 0"
	bind . <Key-Right> "NudgeObject $canvas 1 0"
	bind . <Key-Up> "NudgeObject $canvas 0 -1"
	bind . <Key-Down> "NudgeObject $canvas 0 1"
	bind $canvas <Motion> {}
	$canvas configure -cursor fleur
	.toolbar.move configure -relief sunken
	set_OBJ_MODE move
	DEBUG 3 "Selected move mode"
}

set OBJ_CURRENT 0
set CURRENT_TEXT_WIDGET {}
set CURRENT_FONT {{Helvetica 10}}
set ARCMODE pieslice

proc cmp_obj_attr_z {a b} {
	global OBJdata
	set z [expr [dict get $OBJdata($a) Z] - [dict get $OBJdata($b) Z]]
	if {$z} {
		return $z
	}
	return [string compare $a $b]
}

#
# Compare elements of OBJ based on the values of these attributes
# passed but giving precedence to image tiles
#
# (reverted back to be the same as cmp_obj_attr_z for now)
proc cmp_obj_attr_z_img {a b} {
	global OBJdata
	set z [expr [dict get $OBJdata($a) Z] - [dict get $OBJdata($b) Z]]
	if {$z} {
		return $z
	}
	return [string compare $a $b]
}

#
# Compare MOB IDs and sort them first as {dead, monster, player}, then in ID order 
# sort keys are ID:<name>. The monster ID is at $OBJ(ID:<name>).
#
proc major_mob_sort {id} {
	global MOBdata

	if {[dict get $MOBdata($id) Killed]} {return 0}
	if {[dict get $MOBdata($id) CreatureType] != 2} {return 1}
	return 2
}

proc cmp_mob_living {a b} {
	global MOBdata
#	set id_a $MOB($a)
#	set id_b $MOB($b)
	set ord_a [major_mob_sort $a]
	set ord_b [major_mob_sort $b]

	DEBUG 4 "cmp_mob_living $a $b: ord_a=$ord_a ord_b=$ord_b"
	if {$ord_a == $ord_b} {
		DEBUG 4 "-> [string compare $a $b] (minor sort)"
		return [string compare $a $b]
	}
	DEBUG 4 "-> [expr $ord_a - $ord_b] (major sort)"
	return [expr $ord_a - $ord_b]
}


proc RefreshGrid {show} {
	global canvas OBJdata OBJtype ARCMODE SPLINE zoom animatePlacement
	global AoeZoneLast
	set AoeZoneLast {}
	#
	# draw in Z coordinate order within 2 groups: image tiles, everything else,
	# with the grid sitting on top
	#
	set display_list [lsort -integer -command cmp_obj_attr_z_img [array names OBJdata]]
	foreach id $display_list {
	  if {[catch {
		if {[info exists OBJtype($id)]} {
			if {[animation_obj_exists $id]} {
				animation_destroy_instance $canvas * $id
			} 
			$canvas delete obj$id
			if $animatePlacement update
			#DEBUG 3 "rendering object $id $OBJ(TYPE:$id)"
			#
			# Get universal element attributes
			#
			::gmautil::dassign $OBJdata($id) X X Y Y Z Z Points _Points Line Line Fill Fill Width Width Layer Layer Level Level Group Group Dash _Dash Hidden Hidden Locked Locked
			if {[dict exists $OBJdata($id) Stipple]} {
				set Stipple [dict get $OBJdata($id) Stipple]
			} else {
				set Stipple {}
			}
			if {[set _Stipple $Stipple] eq {nil}} {
				set _Stipple {}
			}
			set Dash [::gmaproto::from_enum Dash ${_Dash}]
			
			#
			# apply zoom factor
			#
			catch {unset Points}
			if {$zoom != 1} {
				set X [expr $X * $zoom]
				set Y [expr $Y * $zoom]
				foreach x ${_Points} {
					lappend Points [expr [dict get $x X] * $zoom]
					lappend Points [expr [dict get $x Y] * $zoom]
				}
			} else {
				foreach x ${_Points} {
					lappend Points [dict get $x X]
					lappend Points [dict get $x Y]
				}
			}

			switch $OBJtype($id) {
				arc {
					$canvas create arc "$X $Y $Points"\
						-fill $Fill -outline $Line -stipple $_Stipple \
						-style [::gmaproto::from_enum ArcMode [dict get $OBJdata($id) ArcMode]] \
						-start [dict get $OBJdata($id) Start] -extent [dict get $OBJdata($id) Extent] \
						-dash $Dash -width $Width -tags [list obj$id allOBJ]
				}
				circ {
					$canvas create oval "$X $Y $Points"\
						-fill $Fill -outline $Line -stipple $_Stipple -width $Width -dash $Dash -tags [list obj$id allOBJ]
				}
				line {
					$canvas create line "$X $Y $Points"\
						-fill $Fill -width $Width -stipple $_Stipple -tags [list obj$id allOBJ] \
						-dash $Dash -arrow [::gmaproto::from_enum Arrow [dict get $OBJdata($id) Arrow]] \
						-arrowshape [list 15 18  8]
				}
				poly {
					set Spline [dict get $OBJdata($id) Spline]
					$canvas create polygon "$X $Y $Points"\
						-fill $Fill -outline $Line -stipple $_Stipple -width $Width -tags [list obj$id allOBJ]\
						-joinstyle [::gmaproto::from_enum Join [dict get $OBJdata($id) Join]] \
						-smooth [expr $Spline != 0] -splinesteps $Spline -dash $Dash
				}
				rect {
					$canvas create rectangle "$X $Y $Points"\
						-fill $Fill -outline $Line -stipple $_Stipple -width $Width -dash $Dash -tags [list obj$id allOBJ]
				}
				aoe - saoe {
					$canvas create line [expr $X-10] $Y [expr $X+10] $Y $X $Y $X [expr $Y-10] $X [expr $Y+10]\
						-fill $Fill -width 3 -tags [list obj$id allOBJ]
					lassign $Points tx ty
					$canvas create oval [expr $tx-10] [expr $ty-10] [expr $tx+10] [expr $ty+10] -width 3 -outline $Fill -tags [list obj$id]
					$canvas create line [expr $tx-5] [expr $ty-5] [expr $tx+5] [expr $ty+5] -width 3 -fill $Fill -tags [list obj$id]
					$canvas create line [expr $tx-5] [expr $ty+5] [expr $tx+5] [expr $ty-5] -width 3 -fill $Fill -tags [list obj$id]
					DrawAoeZone $canvas $id "$X $Y $Points"
				}
				text {
					::gmautil::dassign $OBJdata($id) Text Text Font Font Anchor _Anchor
					#::gmautil::dassign $Font Family FontFamily Size FontSize WeightFontWei
					set Anchor [::gmaproto::from_enum Anchor ${_Anchor}]

					$canvas create text $X $Y -fill $Fill -stipple $_Stipple -anchor $Anchor -font [ScaleFont [GMAFontToTkFont $Font] $zoom] \
						-justify left -text $Text -tags [list obj$id allOBJ]
				}
				tile {
					global TILE_SET TILE_ANIMATION
					# TYPE tile
					# X,Y  upper left corner
					# IMAGE image ID
					set tile_id [FindImage [dict get $OBJdata($id) Image] $zoom]
					if {[info exists TILE_SET($tile_id)]} {
						$canvas create image $X $Y -anchor nw -image $TILE_SET($tile_id) -tags [list obj$id tiles allOBJ]
					} elseif {[info exists TILE_ANIMATION($tile_id,frames)]} {
						animation_create $canvas $X $Y $tile_id $id -start
					} else {
						DEBUG 1 "Warning: no image $tile_id for [dict get $OBJdata($id) Image] @ $zoom available. Looking for it..."
						global TILE_ATTR
						::gmautil::dassign $OBJdata($id) BBHeight BBHeight BBWidth BBWidth Image bbti
						if {$BBHeight > 0 && $BBWidth > 0} {
							set bbxx [expr $X + $BBwidth]
							set bbyy [expr $Y + $BBHeight]
							$canvas create polygon "$X $Y $bbxx $Y $bbxx $bbyy $X $bbyy $X $Y $bbxx $bbyy $X $bbyy $bbxx $Y" \
								-fill {} -outline red -width 5 -tags [list obj$id allOBJ bbox$id]
							$canvas create text [expr $X + ($BBWidth/2)] [expr $Y + ($BBHeight/2)] -fill red -anchor center -text $bbti -tags [list obj$id allOBJ bbox$id]
						}
					}
				}
				default {
					say "ERROR: weird object $id; type=$OBJtype($id)"
				}
			}
			if $show {
				update
			}
		}
	  } err]} {
		say "ERROR: Unable to render object $id: $err"
	  }
	}
	$canvas raise grid
	update
}

#
# update the visual display of an on-screen object to match
# the values in the OBJdata array.
#
proc UpdateObjectDisplay {id} {
	global canvas OBJdata OBJtype zoom animatePlacement

	if {![info exists OBJdata($id)]} {
		DEBUG 0 "UpdateObjectDisplay: $id does not exist in OBJdata."
		return
	}

	if {![info exists OBJtype($id)]} {
		DEBUG 0 "UpdateObjectDisplay: $id does not seem to have a type."
		return
	}

	::gmautil::dassign $OBJdata($id) X X Y Y Z Z Points _Points Line Line Fill Fill Width Width Layer Layer Level Level Group Group Dash _Dash Hidden Hidden Locked Locked
	set Dash [::gmaproto::from_enum Dash ${_Dash}]
	
	#
	# apply zoom factor
	#
	catch {unset Points}
	if {$zoom != 1} {
		set X [expr $X * $zoom]
		set Y [expr $Y * $zoom]
		foreach x ${_Points} {
			lappend Points [expr [dict get $x X] * $zoom]
			lappend Points [expr [dict get $x Y] * $zoom]
		}
	} else {
		foreach x ${_Points} {
			lappend Points [dict get $x X]
			lappend Points [dict get $x Y]
		}
	}

	if {[catch {
		switch $OBJtype($id) {
			arc {
				$canvas coords obj$id "$X $Y $Points"
				$canvas itemconfigure obj$id -fill $Fill -outline $Line \
					-style [::gmaproto::from_enum ArcMode [dict get $OBJdata($id) ArcMode]] \
					-start [dict get $OBJdata($id) Start] -extent [dict get $OBJdata($id) Extent] \
					-dash $Dash -width $Width
			}
			circ {
				$canvas coords obj$id "$X $Y $Points"
				$canvas itemconfigure obj$id -fill $Fill -outline $Line -width $Width -dash $Dash
			}
			line {
				$canvas coords obj$id "$X $Y $Points"
				$canvas itemconfigure obj$id -fill $Fill -width $Width \
					-dash $Dash -arrow [::gmaproto::from_enum Arrow [dict get $OBJdata($id) Arrow]]
			}
			poly {
				$canvas coords obj$id "$X $Y $Points"
				$canvas itemconfigure obj$id -fill $Fill -outline $Line -width $Width \
					-joinstyle [::gmaproto::from_enum Join [dict get $OBJdata($id) Join]] \
					-smooth [expr $Spline != 0] -splinesteps $Spline -dash $Dash
			}
			rect {
				$canvas coords obj$id "$X $Y $Points"
				$canvas itemconfigure obj$id -fill $Fill -outline $Line -width $Width -dash $Dash
			}
			aoe - saoe {
				$canvas delete obj$id
				$canvas create line [expr $X-10] $Y [expr $X+10] $Y $X $Y $X [expr $Y-10] $X [expr $Y+10]\
					-fill $Fill -width 3 -tags [list obj$id allOBJ]
				lassign $Points tx ty
				$canvas create oval [expr $tx-10] [expr $ty-10] [expr $tx+10] [expr $ty+10] -width 3 -outline $Fill -tags [list obj$id]
				$canvas create line [expr $tx-5] [expr $ty-5] [expr $tx+5] [expr $ty+5] -width 3 -fill $Fill -tags [list obj$id]
				$canvas create line [expr $tx-5] [expr $ty+5] [expr $tx+5] [expr $ty-5] -width 3 -fill $Fill -tags [list obj$id]
				DrawAoeZone $canvas $id "$X $Y $Points"
			}
			text {
				$canvas coords obj$id "$X $Y"
				::gmautil::dassign $OBJdata($id) Text Text Font Font Anchor _Anchor
				#::gmautil::dassign $Font Family FontFamily Size FontSize WeightFontWei
				set Anchor [::gmaproto::from_enum Anchor ${_Anchor}]

				$canvas itemconfigure obj$id -fill $Fill -anchor $Anchor -font [ScaleFont [GMAFontToTkFont $Font] $zoom] \
					-justify left -text $Text
			}
			tile {
				global TILE_SET TILE_ANIMATION
				# TYPE tile
				# X,Y  upper left corner
				# IMAGE image ID
				set tile_id [FindImage [dict get $OBJdata($id) Image] $zoom]
				if {[info exists TILE_SET($tile_id)]} {
					$canvas coords obj$id $X $Y
					$canvas itemconfigure obj$id -image $TILE_SET($tile_id)
					$canvas delete bbox$id
				} elseif {[info exists TILE_ANIMATION($tile_id,frames)]} {
					for {set frameno 0} {$frameno < $TILE_ANIMATION($tile_id,frames)} {incr frameno} {
						set cid $TILE_ANIMATION($tile_id,id,$id,$frameno)
						$canvas coords $cid $X $Y
						$canvas itemconfigure $cid -image $TILE_ANIMATION($tile_id,img,$frameno)
					}
					$canvas delete bbox$id
				}
			}
			default {
				say "ERROR: weird object $id; type=$OBJtype($id)"
			}
		}
    } err]} {
        say "ERROR: Unable to render object $id: $err"
    }
	$canvas raise grid
	update
}

proc create_dialog {w} {
	global global_bg_color

	catch {destroy $w}
	toplevel $w -class dialog -background $global_bg_color
}

proc ShowDiceSyntax {} {
	set w .dicesyntax
	create_dialog $w
	wm title $w "Chat/Dice Roller Information"
	grid [text $w.text -yscrollcommand "$w.sb set"] \
	     [scrollbar $w.sb -orient vertical -command "$w.text yview"]\
		 	-sticky news
	grid columnconfigure $w 0 -weight 1
	grid rowconfigure $w 0 -weight 1
	$w.text tag configure h1 -justify center -font Tf14
	$w.text tag configure p -font Nf12 -wrap word
	$w.text tag configure i -font If12 -wrap word
	$w.text tag configure b -font Tf12 -wrap word

	foreach line {
		{h1 {Chat Window}}
		{p {}}
		{p  {Select the recipient(s) to whom you wish to send a message, or select "To all" to send a global message to everyone. If you select one person, the message will be private to them. If you then select another person, they will be }
		 i  {added to}
		 p  {the conversation, so the message goes to all of them. Selecting "all" will clear the recipient selection. The message is sent when you press Return in the entry field. If the "M" checkbox is selected, you can use simple GMA markup formatting codes in your chat messages (note that these are not supported in die rolls because they'd get confused with the die-roll expression operators).}}
		{p {}}
		{h1 {Die Roller Syntax}}
		{p {}}
		{p {To roll dice, select the recipient(s) who can see the roll using the chat controls, type the die description in the 'Roll' field and press Return. To re-roll a recent die roll, just click the die button next to that roll in the 'Recent' list. Similarly to roll a saved 'Preset'.}}
		{p {}}
		{p {General syntax: [} i name b = p {] [} i qty p { [} b / i div p {]]} b { d } i sides p { [}
		 b {best|worst of } i n p {]  [...] [} b { | } i modifiers p {]}}
		{p {}}
		{p {(The [square brackets] indicate optional values; they are not literally part of the expression syntax.)}}
		{p {}}
		{p {This will roll } i qty p { dice, each of which has the specified number of } 
		 i sides p { (i.e., each generates a number between 1 and } i sides 
		 p {, inclusive.) The result is divided by } i div 
		 p { (but in no case will the result be less than 1). Finally, any } i bonus 
		 p { (positive or negative) is added to the result. If } i factor 
		 p { is specified, the final result is multiplied by that amount.}}
		{p {}}
		{p {As a special case, } i sides p " may be the character \"" b % 
		 p "\", which means to roll percentile (d100) dice."}
		{p {}}
		{p {Where the [...] is shown above, you may place more die roll patterns or integer values, separated by } b + p , b { -} p , b { *} p {, or } b // 
		 p { to, respectively, add, subtract, multiply, or divide the following value from the total so far.}
		 p { You can also use the character × for multiplication and ÷ for division.}}
		{p {}}
		{p {The math operators for addition, subtraction, multiplication, division, and unary - for negation (and technically the unary + which really doesn't do anything) are interpreted using the standard precedence and order of operation for those operators. You may use parentheses to group sub-expressions to force a particular order of operations.}}
		{p {}}
		{p {At the very end, you may place global modifiers separated from each other and from the die roll string with a vertical bar. These affect the outcome of the entire die roll in some way, by repeating the roll, confirming critical rolls, and so forth. The available global modifiers include:}}
		{p {}}
		{b {| c} p \[ i T p \]\[ b + i B p "\]\tThe roll (which must include a single die only) might be critical if it rolled a natural maximum die value (or at least "
		 i T p { if specified). In this case, the entire roll will be repeated with the optional bonus (or penalty, if a - is used instead of a +) of }
		 i B p { added to the confirmation roll.}}
		{b {| min } i N p "\tThe result will be " i N p { or the result of the actual dice, whichever is greater.}}
		{b {| max } i N p "\tThe result will be " i N p { or the result of the actual dice, whichever is less.}}
		{b {| maximized} p "\tAll dice will produce their maximum possible values rather than being random. (May also be given as "
		 b {!} p .)}
		{b {| repeat } i N p "\tRoll the expression " i N p { times, reporting that many separate results.}}
		{b {| until } i N p "\tRoll the expression repeatedly (reporting each result) until the result is at least " i N p .}
		{b {| total } i N p "\tRoll the expression repeatedly (reporting each result) until the cumulative total of the rolls is at least " i N p .}
		{b {| dc } i N p "\tThis is a check against a difficulty class (DC) of " i N 
		 p {. This does not affect the roll, but will report back whether the roll satisfied the DC and by what margin.}}
		{b {| sf } p \[ i success p \[ b / i fail p "\]\]\tThis roll (which must involve but a single die) indicates automatic success or failure on a natural 20 or 1 respectively (or whatever the maximum value of the die is, if not a d20). The optional " i success p " or " i fail p " labels are used in the report (or suitable defaults are used if these are not given)."}
		{p {}}
		{p {Examples:}}
		{b d20         p "\tRoll a 20-sided die."}
		{b 3d6         p "\tRoll three 6-sided dice and add them together."}
		{b 15d6+15     p "\tRoll 16 6-sided dice and add them together, addiing 15 to the result."}
		{b 1d10+5*10   p "\tRoll a 10-sided die, add 5, then multiply the result by 10."}
		{b 1/2d6       p "\tRoll a 6-sided die, then divide the result by 2 (i.e., roll 1/2 of a d6)."}
		{b 2d10+3d6+12 p "\tRoll 2d10, 3d6, add them plus 12 and report the result."}
		{b d20+15|c     p "\tRoll 1d20, add 15 and report the result. Additionally, if the d20 rolled a natural 20, roll 1d20+15 again and report that result."}
		{b d20+15|c19+2 p "\tRoll 1d20, add 15 and report the result. Additionally, if the d20 rolled a natural 19 or 20, roll 1d20+15+2 and report that result."}
		{b d%          p "\tRoll a percentile die, generating a number from 1-100."}
		{b 40%         p "\tThis is an additional way to roll percentile dice, by specifying the probability of a successful outcome. In this example, the roll should be successful 40% of the time. The report will include the die roll and whether it was successful or not."}
		{b 40% i label p "\tAs above, but indicate the event outcome as a 40% chance of being \"" i label p "\" and 60% chance of \"did not " i label p "\". Note that if " i label p " is \"hit\" then \"miss\" will be displayed rather than \"did not hit\" and vice versa."}
		{b 40% i a b / i b p "\tAs above, but indicate the event outcome as a 40% chance of being \"" i a p "\" and 60% chance of \"" i b p "\"."}
		{b {d20 + 12 | max 20}    p "\tRolls a d20, adds 12, and reports the result or 20, whichever is smaller."}
		{b {1d20 + 2d12 + 2 | max 20} p "\tRolls a d20, 2 12-sided dice, adds them together, adds 2 to the sum, then reports the result or 20, whichever is smaller."}
		{p {}}
		{p {You can't use the } b c p {... modifier to ask for confirmation rolls if there was more than one die involved in your roll.}}
		{p {}}
		{h1 {Fancy Things}}
		{p {}}
		{p "You can put \"" i name b = p "\" in front of the entire expression to label it for what it represents. For example, \"" b {attack=d20+5 | c} p "\" rolls d20+5 (with confirmation check) but reports it along with the name \"attack\" to make it clear what the roll was for."}
		{p {}}
		{p "If you put a \"" b > p "\" in front of a multi-die roll, such as \"" b >3d6 p "\", the first die will be maximized while the remaining ones will be random. So in this example, the actual roll will be equivalent to \"" b 2d6+6 p "\". This is usually used for hit points of creatures with class levels."}
		{p {}}
		{p {The } b {best of} p { pattern will cause the die following it to be rolled } i n 
		 p " times and the best of them taken. (Similarly, you can use \"" b worst 
		 p "\" in place of \"" b best p "\".)"}
		{p {}}
		{b {d20 best of 2 + 12} p "\tRolls 2 d20, takes the better of the 2, then adds 12."}
		{p {}}
		{p "If you put some random text at the end of any die roll expression, it will be repeated in the output. You can use this to label things like energy damage in a die roll like \""
		 b {Damage = 1d12 + 1d6 fire + 2d6 sneak}
		 p "\"."}
		{p {}}
		{p {If part of a die roll needs to be constrained within a given minimum or maximum value (as opposed to applying a global minimum or maximum on the } i entire p { result via the } b |min p { and } b |max p { options, you can use the } b <= p { and } b >= p { operators. In an expression, } i x b <= i y p { means to take the value of } i x p { but that it must be less than or equal to } i y p {, and likewise for } i x b >= i y p {. You may also use the characters ≤ and ≥ for these operators.}}
		{p {}}
		{p "You can color the die-roll title (everything before the = sign) or any individual modifier label by adding the special character \u2261 (U+2261) followed by a hex RGB color code like #334455 or a color name at the end of the label. Add two of these to specify both a foreground and background color. Separate titles or labels into multiple, separately colored parts by dividing them with \u2016 (U+2016) characters."}
		{p {}}
		{h1 {Lookup Tables}}
		{p {}}
		{p {If a random outcome lookup table is defined in your die-roll preset list, you can roll on that table and have the mapper's die roller look up what that random result means and let the other players know. To do so, just specify } b # i name p { to roll on the table defined under the specified }
			i name p { or } b ## i name p { if the table is defined system-wide by your GM. This must appear at the start of the die-roll expression but may be followed by other modifiers you wish to be added to whatever dice are defined for the lookup table, plus other options such as repeats.}}
		{p {}}
		{p {The formal syntax definition for invoking a lookup table roll is:}}
		{p {}}
		{p [ i title b = p {] } b # p [ b # p ] i tablename p { [} i expr p ... p {] [} b | i options p ...]}
		{p {}}
		{p {So if, for example, a lookup table called "confusion" is defined to roll percentile dice (d100) and specifies a random action a confused creature will do based on ranges of numbers that come up on the dice when they're rolled, if you type } b #confusion p { as your die roll, the mapper will send }
			b d100 p " to the server, get the result back (say, 42), which you will see just like any other die roll result, but will then also look that result up on the confusion table, to see that a value between 26\u201350 means the creature just babbles incoherently. It will then send a chat message out to everyone who was a recipient of the original die roll, with this additional information."}
		{p {}}
		{p {If you wanted to bias this effect to make the creature more confused by adding 25 to the die roll, just specify the roll as }
			b #confusion+25 p {. This will add everything aftter the table name to the die roll, so the die roll sent to the server will be }
			b d100+25 p {. Likewise, you could say things like } b {#confusion best of 2} p { or }
			b {#confusion|repeat 10} p .}
		{p {}}
		{p {If necessary to avoid confusion with surrounding text, you can enclose the name of the table in braces just as you can with variable names, so you could invoke the above table lookup as } b {#{confusion}} p { (or as } b {##{confusion}} p { if it were defined at the system level by the GM).}}
		{p {}}
		{h1 {Presets}}
		{p {}}
		{p {Saving preset rolls to the server allows them to be available any time your client connects to it. Each preset is given a unique name. If another preset is added with the same name, it will replace the previous one.}}
		{p {}}
		{p {Clicking on the [Edit Presets...] button will allow you to add, remove, modify, and reorder the list of presets you have on file. You can also define modifiers and variables. These are fragments of die-roll expressions (such as "+2 inspiration") which you can turn on or off as you need them. When turned on, they are added to all of your die rolls (in the order they appear). You may also give them a variable name, in which case they will not be added to every die roll but will instead be substituted in place of the notation } b $ i name p { or } b $\{ i name b \} p {, where } i name p { is the name of the variable. For variables defined at the global (system-wide) level, set by your GM for all players, use two dollar signs, as in } b $$ i name p { or } b $$\{ i name b \} p . }
		{p {}}
		{p {The export file for presets is a structured, record-based text file documented in gma-dice(5).}}
		{p {See gma-dice-syntax(7) for more (run } b {gma man dice-syntax} p {).}}
		{p {}}
		{p {Why } b {$} p { for variable names and } b {#} p { for table names? Just because there's a long standing tradition of using the former as a variable prefix in scripting languages such as Unix and Linux shell scripts and scripting languages such as perl, awk, and tcl. In the latter case, because the octothorpe or pound sign visually resembles the horizontal and vertical rules that separate the rows and columns of a table which struck my imagination at the time and I just ran with that idea.}}
	} {
		foreach {f t} $line {
			$w.text insert end $t $f
		}
		$w.text insert end "\n"
	}
	$w.text configure -state disabled
}

# Begin drawing a new object of some type on the screen
# OBJ_MODE will be nil, line, rect, poly, circ, arc, kill, aoe, move, text, tile, aoebound, ruler
proc StartObj {w x y} {
	global OBJtype OBJdata OBJ_CURRENT canvas OBJ_SNAP OBJ_MODE OBJ_COLOR OBJ_WIDTH OBJ_MODIFIED ARCMODE
	global NoFill StipplePattern JOINSTYLE SPLINE DASHSTYLE ARROWSTYLE
	global BUTTON_MIDDLE BUTTON_RIGHT
	global OBJ_NEXT_Z zoom
	global animatePlacement
	global ForceElementsToTop

	if {[set _StipplePattern $StipplePattern] eq {nil}} {
		set _StipplePattern {}
	}

	modifiedflag - 1
	#
	# special case for aoebound tool; there is only one of these
	#
	if {$OBJ_MODE == "aoebound"} {
		set OBJ_CURRENT AOE_GLOBAL_BOUND
		$w delete obj$OBJ_CURRENT
		RemoveObject $OBJ_CURRENT
	} elseif {$OBJ_MODE == "ruler"} {
		set OBJ_CURRENT RULER_GLOBAL
		$w delete obj$OBJ_CURRENT
	} else {
		set OBJ_CURRENT [new_id]
	}

	#
	# set up new element object in storage
	#
	if {$NoFill} {
		set fill_color {}
	} else {
		set fill_color $OBJ_COLOR(fill)
	}
	set dash [::gmaproto::to_enum Dash $DASHSTYLE]
	set layer walls
	set x [$canvas canvasx $x]
	set y [$canvas canvasy $y]
	set z [incr OBJ_NEXT_Z]
	if {$ForceElementsToTop} {
		incr z 999999999
	}
	

	switch $OBJ_MODE {
		nil - kill - move { 
			DEBUG 0 "Called StartObj($w,$x,$y) for $OBJ_MODE tool. Why?" 
			return
		}
		aoe - saoe {
			global DistanceLabelText AOE_SHAPE AOE_START
			set a_x [SnapCoordAlways $x]
			set a_y [SnapCoordAlways $y]

			set OBJtype($OBJ_CURRENT) aoe
			set OBJdata($OBJ_CURRENT) [::gmaproto::new_dict LS-SAOE ID $OBJ_CURRENT \
				X [expr $a_x / $zoom] Y [expr $a_y / $zoom] Z 99999999 \
				Fill $fill_color Line $OBJ_COLOR(line) Width $OBJ_WIDTH Dash $dash Layer $layer \
				AoEShape [::gmaproto::to_enum AoEShape $AOE_SHAPE] \
			]

			$canvas create line [expr $a_x-10] $a_y [expr $a_x+10] $a_y -fill $fill_color -width 4 -tags [list obj$OBJ_CURRENT allOBJ]
			$canvas create line $a_x [expr $a_y-10] $a_x [expr $a_y+10] -fill $fill_color -width 4 -tags [list obj$OBJ_CURRENT allOBJ]
			$canvas create line $a_x $a_y $a_x $a_y -dash - -fill $fill_color -width 3 -tags [list obj$OBJ_CURRENT obj_locator$OBJ_CURRENT allOBJ] -arrow last -arrowshape [list 15 18  8]
			bind $canvas <1> "LastAoePoint $canvas %x %y"
			set DistanceLabelText {}
			switch $AOE_SHAPE {
				radius {
					$canvas create oval $a_x $a_y $a_x $a_y \
						-outline $OBJ_COLOR(line) -width 3 -dash - \
						-tags [list obj$OBJ_CURRENT obj_locator_radius$OBJ_CURRENT allOBJ]
				}
				cone   {
					$canvas create arc $a_x $a_y $a_x $a_y -dash - \
						-outline $OBJ_COLOR(line) -width 3 -start 0 -extent 90 \
						-tags [list obj$OBJ_CURRENT obj_locator_cone3_$OBJ_CURRENT allOBJ]
				}
			}
			$canvas create window $a_x [expr $a_y - 20] -window $canvas.distanceLabel -tags [list obj_distance$OBJ_CURRENT allOBJ]
			set AOE_START [list [CanvasToGrid $a_x] [CanvasToGrid $a_y]]
		}
		aoebound {
			# TODO X,Y are [expr [SnapCoord $x(y)] / $zoom]
			# TODO Z is 99999999
			$canvas create line [SnapCoord $x] [SnapCoord $y] [SnapCoord $x] [SnapCoord $y] -width 3 -fill $OBJ_COLOR(line) -tags [list obj$OBJ_CURRENT allOBJ] -dash -
			bind $canvas <1> "NextPoint $canvas %x %y"
		}
		arc { 
			set OBJtype($OBJ_CURRENT) arc
			set OBJdata($OBJ_CURRENT) [::gmaproto::new_dict LS-ARC ID $OBJ_CURRENT \
				X [expr [SnapCoord $x] / $zoom] Y [expr [SnapCoord $y] / $zoom] Z $z \
				Stipple $_StipplePattern Fill $fill_color Line $OBJ_COLOR(line) Width $OBJ_WIDTH \
				Dash $dash Layer $layer]
			$canvas create arc  [SnapCoord $x] [SnapCoord $y] [SnapCoord $x] [SnapCoord $y] -fill [dict get $OBJdata($OBJ_CURRENT) Fill] -stipple $_StipplePattern -outline $OBJ_COLOR(line) -width $OBJ_WIDTH -tags [list obj$OBJ_CURRENT allOBJ] -style $ARCMODE -start 0 -extent 359 -dash $DASHSTYLE
			bind $canvas <1> "LastArcPoint $canvas %x %y"
			dict set OBJdata($OBJ_CURRENT) ArcMode [::gmaproto::to_enum ArcMode $ARCMODE]
		}
		circ { 
			set OBJtype($OBJ_CURRENT) circ
			set OBJdata($OBJ_CURRENT) [::gmaproto::new_dict LS-CIRC ID $OBJ_CURRENT \
				X [expr [SnapCoord $x] / $zoom] Y [expr [SnapCoord $y] / $zoom] Z $z \
				Fill $fill_color Stipple $_StipplePattern Line $OBJ_COLOR(line) \
				Width $OBJ_WIDTH Dash $dash Layer $layer]
			$canvas create oval [SnapCoord $x] [SnapCoord $y] [SnapCoord $x] [SnapCoord $y] -fill $fill_color -stipple $_StipplePattern -outline $OBJ_COLOR(line) -width $OBJ_WIDTH -tags [list obj$OBJ_CURRENT allOBJ] -dash $DASHSTYLE
			bind $canvas <1> "LastPoint $canvas %x %y"
		}
		line { 
			set arrow [::gmaproto::to_enum Arrow $ARROWSTYLE]
			set OBJtype($OBJ_CURRENT) line
			set OBJdata($OBJ_CURRENT) [::gmaproto::new_dict LS-LINE ID $OBJ_CURRENT \
				X [expr [SnapCoord $x] / $zoom] Y [expr [SnapCoord $y] / $zoom] Z $z \
				Fill $fill_color Line $OBJ_COLOR(line) Width $OBJ_WIDTH \
				Dash $dash Layer $layer Arrow $arrow]
			$canvas create line [SnapCoord $x] [SnapCoord $y] [SnapCoord $x] [SnapCoord $y] -stipple $_StipplePattern -fill $fill_color -width $OBJ_WIDTH -tags [list obj$OBJ_CURRENT allOBJ] -dash $DASHSTYLE -arrow $ARROWSTYLE -arrowshape [list 15 18 8]
			bind $canvas <1> "NextPoint $canvas %x %y"
		}
		poly {
			set OBJtype($OBJ_CURRENT) poly
			set OBJdata($OBJ_CURRENT) [::gmaproto::new_dict LS-POLY ID $OBJ_CURRENT \
				X [expr [SnapCoord $x] / $zoom] Y [expr [SnapCoord $y] / $zoom] Z $z \
				Stipple $_StipplePattern Fill $fill_color Line $OBJ_COLOR(line) Width $OBJ_WIDTH Dash $dash Layer $layer\
				Join [::gmaproto::to_enum Join $JOINSTYLE] \
				Spline $SPLINE \
			]
			$canvas create polygon [SnapCoord $x] [SnapCoord $y] [SnapCoord $x] [SnapCoord $y] -stipple $_StipplePattern -fill $fill_color -width $OBJ_WIDTH -outline $OBJ_COLOR(line) -tags [list obj$OBJ_CURRENT allOBJ] -joinstyle $JOINSTYLE -smooth [expr $SPLINE != 0] -splinesteps $SPLINE -dash $DASHSTYLE
			bind $canvas <1> "NextPoint $canvas %x %y"
		}
		rect {
			set OBJtype($OBJ_CURRENT) rect
			set OBJdata($OBJ_CURRENT) [::gmaproto::new_dict LS-RECT ID $OBJ_CURRENT \
				X [expr [SnapCoord $x] / $zoom] Y [expr [SnapCoord $y] / $zoom] Z $z \
				Stipple $_StipplePattern Fill $fill_color Line $OBJ_COLOR(line) Width $OBJ_WIDTH \
				Dash $dash Layer $layer]
			$canvas create rectangle [SnapCoord $x] [SnapCoord $y] [SnapCoord $x] [SnapCoord $y] -stipple $_StipplePattern -fill $fill_color -outline $OBJ_COLOR(line) -width $OBJ_WIDTH -tags [list obj$OBJ_CURRENT allOBJ] -dash $DASHSTYLE
			bind $canvas <1> "LastPoint $canvas %x %y"
		}
		ruler {
			set OBJtype($OBJ_CURRENT) line
			set OBJdata($OBJ_CURRENT) [::gmaproto::new_dict LS-LINE ID $OBJ_CURRENT \
				X [expr [SnapCoord $x] / $zoom] Y [expr [SnapCoord $y] / $zoom] Z $z \
				Fill $fill_color Width 3]
			$canvas create line [SnapCoord $x] [SnapCoord $y] [SnapCoord $x] [SnapCoord $y] \
				-fill $fill_color -width 3 -tags [list obj$OBJ_CURRENT allOBJ] -dash -
			bind $canvas <1> "NextPoint $canvas %x %y"
			$canvas create window $x [expr $y - 20] -window $canvas.distanceLabel -tags [list obj_distance$OBJ_CURRENT allOBJ]
		}
		text {
			global CurrentTextString CurrentAnchor
			global CURRENT_TEXT_WIDGET CURRENT_FONT zoom

			if {$CurrentTextString eq {}} {
				SelectText $x $y
			}
			if {$CurrentTextString ne {}} {
				$canvas create text [SnapCoord $x] [SnapCoord $y] -anchor $CurrentAnchor \
					-font [ScaleFont [lindex $CURRENT_FONT 0] $zoom] \
					-justify left \
					-text $CurrentTextString \
					-fill $fill_color \
					-stipple $_StipplePattern \
					-tags "tiles obj$OBJ_CURRENT"

				set OBJtype($OBJ_CURRENT) text
				set OBJdata($OBJ_CURRENT) [::gmaproto::new_dict LS-TEXT ID $OBJ_CURRENT \
					X [expr [SnapCoord $x] / $zoom] Y [expr [SnapCoord $y] / $zoom] Z $z \
					Fill $fill_color Layer $layer Text $CurrentTextString \
					Stipple $_StipplePattern \
					Font [TkFontToGMAFont $CURRENT_FONT] \
					Anchor [::gmaproto::to_enum Anchor $CurrentAnchor]\
				]
				set CURRENT_TEXT_WIDGET $OBJ_CURRENT
			} else {
				DEBUG 1 "Removing text object $OBJ_CURRENT"
				catch {unset OBJdata($OBJ_CURRENT)}
				catch {unset OBJtype($OBJ_CURRENT)}
			}
			EndObj $canvas
		}
		tile {
			set OBJtype($OBJ_CURRENT) tile
			set OBJdata($OBJ_CURRENT) [::gmaproto::new_dict LS-TILE ID $OBJ_CURRENT \
				X [expr [SnapCoord $x] / $zoom] Y [expr [SnapCoord $y] / $zoom] Z $z \
				Layer $layer \
			]

			global CurrentStampTile TILE_SET TILE_ANIMATION
			if {[llength $CurrentStampTile] == 0} {
				SelectTile $x $y
			}
			if {[llength $CurrentStampTile] > 0} {
				set iid [lindex $CurrentStampTile 0]
				if {[info exists TILE_SET($iid)]} {
					$canvas create image [SnapCoord $x] [SnapCoord $y] -anchor nw -image $TILE_SET($iid) -tags "tiles obj$OBJ_CURRENT"
				} elseif {[info exists TILE_ANIMATION($iid,frames)]} {
					animation_create $canvas [SnapCoord $x] [SnapCoord $y] $iid $OBJ_CURRENT -start

				} else {
					say "Unable to load image $CurrentStampTile. Be sure to define and upload it."
					create_dialog .stbx
					wm title .stbx "Image Not Found"

					global STBX_X STBX_Y TILE_ATTR
					set bbti [lindex $CurrentStampTile 0]
					set STBX_X 50
					set STBX_Y 50
					pack [frame .stbx.1] \
						 [frame .stbx.2] \
						 [frame .stbx.3] \
						 [frame .stbx.4] \
						 [frame .stbx.5] \
						-side top
					pack [label .stbx.1.lab -text "Unable to load image $CurrentStampTile. Be sure to define and upload it."]
					pack [label .stbx.2.lab -text "Until we find the image, please specify its size for the placeholder."]
					pack [label .stbx.3.lab -text "Width (pixels):"] \
					     [entry .stbx.3.ent -textvariable STBX_X -width 5 -validate key -validatecommand {regexp {^\\d+$} {%P}} ] \
						 -side left -anchor w
					pack [label .stbx.4.lab -text "Height (pixels):"] \
					     [entry .stbx.4.ent -textvariable STBX_Y -width 5 -validate key -validatecommand {regexp {^\\d+$} {%P}} ] \
						 -side left -anchor w
					pack [button .stbx.5.cancel -command "destroy .stbx" -text Cancel] \
					     [button .stbx.5.ok -command "SetTilePlaceHolder {$OBJ_CURRENT} \$STBX_X \$STBX_Y {$bbti}; destroy .stbx" -text Ok]\
						 -side right
					SetTilePlaceHolder $OBJ_CURRENT $STBX_X $STBX_Y $bbti
				}
				dict set OBJdata($OBJ_CURRENT) Image [lindex $CurrentStampTile 1]
			} else {
				DEBUG 1 "Removing image object$OBJ_CURRENT"
				catch {unset OBJdata($OBJ_CURRENT)}
				catch {unset OBJtype($OBJ_CURRENT)}
			}
			EndObj $canvas
		}
		default {
			DEBUG 0 "Called StartObj($w,$x,$y) with illegal mode $OBJ_MODE"
		}
	}

	bind $canvas $BUTTON_MIDDLE "EndObj $canvas"
	bind . <Key-Escape> "EndObj $canvas"

	$canvas raise grid
	if {$animatePlacement} update
}

proc ZoomVector { args } {
	global zoom
	set r {}
	foreach j $args {
		foreach i $j {
			if {$i ne {}} {
				lappend r [expr $i * $zoom]
			}
		}
	}
	return $r
}

proc ObjAoeDrag {w x y} {
	global OBJdata OBJ_CURRENT OBJ_SNAP canvas zoom DistanceLabelText AOE_START

	set xx  [SnapCoordAlways [$canvas canvasx $x]]
	set yy  [SnapCoordAlways [$canvas canvasy $y]]
	set gx  [CanvasToGrid $xx]
	set gy  [CanvasToGrid $yy]

	if {$OBJ_CURRENT != 0} {
		global iscale PI

		set radius_grids [GridDistance [lindex $AOE_START 0] [lindex $AOE_START 1] $gx $gy]
		set radius_feet  [expr $radius_grids * 5]
		set r [expr $radius_grids * $iscale]
		set x0	[expr [dict get $OBJdata($OBJ_CURRENT) X] * $zoom]
		set y0	[expr [dict get $OBJdata($OBJ_CURRENT) Y] * $zoom]

		$w coords obj_locator$OBJ_CURRENT "$x0 $y0 $xx $yy"
		set DistanceLabelText [format "%d feet" $radius_feet]
		
		switch [::gmaproto::from_enum AoEShape [dict get $OBJdata($OBJ_CURRENT) AoEShape]] {
			radius {
				$w coords obj_locator_radius$OBJ_CURRENT "[expr $x0-$r] [expr $y0-$r] [expr $x0+$r] [expr $y0+$r]"
			}
			cone {
				if {$r > 0} {
					set theta0  [expr atan2($y0 - $yy, $xx - $x0)]
					#set theta1	[expr $theta0 + ($PI / 4)]
					set theta2	[expr $theta0 - ($PI / 4)]
					#set x1	[expr $x0 + ($r * cos($theta1))]
					#set y1	[expr $y0 - ($r * sin($theta1))]
					#set x2	[expr $x0 + ($r * cos($theta2))]
					#set y2	[expr $y0 - ($r * sin($theta2))]
					#$w coords obj_locator_cone1_$OBJ_CURRENT "$x0 $y0 $x1 $y1"
					#$w coords obj_locator_cone2_$OBJ_CURRENT "$x0 $y0 $x2 $y2"
					$w coords obj_locator_cone3_$OBJ_CURRENT "[expr $x0-$r] [expr $y0-$r] [expr $x0+$r] [expr $y0+$r]"
					$w itemconfigure obj_locator_cone3_$OBJ_CURRENT -start [expr ($theta2 / $PI) * 180.0]
				}
			}
		}
		DrawAoeZone $w $OBJ_CURRENT "$x0 $y0 $xx $yy"
		update
	}
}

# DrawAoeZone canvas AOEobjID {x1 y1 x2 y2}
# coordinates are assumed to already be scaled and snapped to the grid
proc DrawAoeZone {w id coords} {
	global OBJdata iscale PI
	
	if {[llength $coords] != 4} {
		say "ERROR: DrawAoeZone coordinates value {$coords} invalid"
		return
	}
	lassign $coords x0 y0 xx yy
	set gx0 [CanvasToGrid $x0]
	set gy0 [CanvasToGrid $y0]
	set gxx [CanvasToGrid $xx]
	set gyy [CanvasToGrid $yy]
	set radius_grids [GridDistance $gx0 $gy0 $gxx $gyy]
	set r [expr $radius_grids * $iscale]

	_DrawAoeZone $w $id $gx0 $gy0 $gxx $gyy $r [dict get $OBJdata($id) Fill] \
		[::gmaproto::from_enum AoEShape [dict get $OBJdata($id) AoEShape]] \
		[list AoEZoneCrossHatch$id obj$id allOBJ]
}

set AoeZoneLast {}
proc _DrawAoeZone {w id gx0 gy0 gxx gyy r color shape tags} {
	global PI iscale AOE_SPREAD AoeZoneLast

	# prevent re-drawing the same area repeatedly while the mouse is moved 
	# through the area
	if {$AoeZoneLast == "$gx0:$gy0:$r"} {
		return
	}
	set AoeZoneLast "$gx0:$gy0:$r"
	set x0 [expr $gx0 * $iscale]
	set y0 [expr $gy0 * $iscale]
	set xx [expr $gxx * $iscale]
	set yy [expr $gyy * $iscale]
	set deltax [expr $xx - $x0];	# dx, dy have the usual "math" orientation
	set deltay [expr $y0 - $yy];	# with y increasing UP

	$w delete AoEZoneCrossHatch$id
	$w delete REF$id
	switch $shape {
		radius {
			if {$AOE_SPREAD} {
				DrawAoeSpread $w $x0 $y0 $r {} $tags $color
				return
			}
				
			set bbx1 [expr $x0 - $r]
			set bby1 [expr $y0 - $r]
			set bbx2 [expr $x0 + $r]
			set bby2 [expr $y0 + $r]

			#
			# iterate over the squares in a 1/8 circle wedge
			# up from the center and to the right 45 degrees
			# then reflect 7 more times
			#
			for {set i 0} {$x0+$iscale*$i < $bbx2} {incr i} {
				for {set j 1} {$y0-$iscale*$j >= $bby1} {incr j} {
					if {$i < $j} {
						set is [expr $iscale * $i]
						set js [expr $iscale * $j]
						set is1 [expr $iscale + $is]
						set js1 [expr $js - $iscale]
						if {sqrt($is**2 + $js**2) <= $r} {
							# I
							DrawAoeGrid $w [expr $x0 + $is] [expr $y0 - $js] \
							               [expr $x0 + $is1] [expr $y0 - $js1] \
										   $color $id $tags
							DrawAoeGrid $w [expr $x0 + $js - $iscale] [expr $y0 - $is - $iscale] \
										   [expr $x0 + $js] [expr $y0 - $is] \
										   $color $id $tags

							# IV
							DrawAoeGrid $w [expr $x0 + $is] [expr $y0 + $js1] \
							               [expr $x0 + $is1] [expr $y0 + $js] \
										   $color $id $tags
							DrawAoeGrid $w [expr $x0 + $js - $iscale] [expr $y0 + $is] \
										   [expr $x0 + $js] [expr $y0 + $is + $iscale] \
										   $color $id $tags

							# II
							DrawAoeGrid $w [expr $x0 - $is1] [expr $y0 - $js] \
										   [expr $x0 - $is] [expr $y0 - $js1] \
										   $color $id $tags
							DrawAoeGrid $w [expr $x0 - $js] [expr $y0 - $is - $iscale] \
										   [expr $x0 - $js + $iscale] [expr $y0 - $is] \
										   $color $id $tags

							# III
							DrawAoeGrid $w [expr $x0 - $is1] [expr $y0 + $js1] \
										[expr $x0 - $is] [expr $y0 + $js] \
										   $color $id $tags
							DrawAoeGrid $w [expr $x0 - $js] [expr $y0 + $is] \
										   [expr $x0 - $js + $iscale] [expr $y0 + $is1] \
										   $color $id $tags
						}
					}
				}
			}
		}
		ray {
			if {$r > 0} {
				$w create line $x0 $y0 $xx $yy -tags [list REF$id] -width 1 -fill red
				if {$deltax > 0 && $deltay > 0} {
					# quadrant I
					for {set x $x0} {$x < $xx} {set x [expr $x+$iscale]} {
						for {set y [expr $y0 - $iscale]} {$y >= $yy} {set y [expr $y-$iscale]} {
							set bx [expr $x + $iscale]
							set by [expr $y + $iscale]
							foreach wid [$w find overlapping [expr $x+1] [expr $y+1] [expr $bx-1] [expr $by-1]] {
								if {[lsearch -exact [$w gettags $wid] REF$id] >= 0} {
									DrawAoeGrid $w $x $y $bx $by $color $id $tags
									break
								}
							}
						}
					}
				}
				if {$deltax < 0 && $deltay > 0} {
					# quadrant II
					$w create line $x0 $y0 $xx $yy -tags [list REF$id] -width 1 -fill red
					for {set x $xx} {$x < $x0} {set x [expr $x+$iscale]} {
						for {set y [expr $y0 - $iscale]} {$y >= $yy} {set y [expr $y-$iscale]} {
							set bx [expr $x + $iscale]
							set by [expr $y + $iscale]
							foreach wid [$w find overlapping [expr $x+1] [expr $y+1] [expr $bx-1] [expr $by-1]] {
								if {[lsearch -exact [$w gettags $wid] REF$id] >= 0} {
									DrawAoeGrid $w $x $y $bx $by $color $id $tags
									break
								}
							}
						}
					}
				}
				if {$deltax < 0 && $deltay < 0} {
					# quadrant III
					$w create line $x0 $y0 $xx $yy -tags [list REF$id] -width 1 -fill red
					for {set x $xx} {$x < $x0} {set x [expr $x+$iscale]} {
						#for {set y [expr $y0 - $iscale]} {$y >= $yy} {set y [expr $y-$iscale]} {}
						for {set y [expr $yy-$iscale]} {$y >= $y0} {set y [expr $y-$iscale]} {
							set bx [expr $x + $iscale]
							set by [expr $y + $iscale]
							foreach wid [$w find overlapping [expr $x+1] [expr $y+1] [expr $bx-1] [expr $by-1]] {
								if {[lsearch -exact [$w gettags $wid] REF$id] >= 0} {
									DrawAoeGrid $w $x $y $bx $by $color $id $tags
									break
								}
							}
						}
					}
				}
				if {$deltax > 0 && $deltay < 0} {
					# quadrant IV
					$w create line $x0 $y0 $xx $yy -tags [list REF$id] -width 1 -fill red
					for {set x $x0} {$x < $xx} {set x [expr $x+$iscale]} {
						for {set y [expr $yy-$iscale]} {$y >= $y0} {set y [expr $y-$iscale]} {
							set bx [expr $x + $iscale]
							set by [expr $y + $iscale]
							foreach wid [$w find overlapping [expr $x+1] [expr $y+1] [expr $bx-1] [expr $by-1]] {
								if {[lsearch -exact [$w gettags $wid] REF$id] >= 0} {
									DrawAoeGrid $w $x $y $bx $by $color $id $tags
									break
								}
							}
						}
					}
				}
			}
		}
		cone {
			# draw a reference pie slice and see what's inside it
			set theta0 [expr atan2($y0 - $yy, $xx - $x0)]
			set theta2 [expr $theta0 - ($PI / 4)]
			set theta2_deg [expr ($theta2/$PI)*180.0]
			if {$theta2_deg < -180} {
				set theta2_deg [expr $theta2_deg + 360]
			}
			set offset [expr $iscale / 2.0]
			$w create arc [expr $x0-$r] [expr $y0-$r] [expr $x0+$r] [expr $y0+$r] -width 1 -fill red -outline red -start $theta2_deg -extent 90 -tags [list REF$id]
			#
			# Note that for corner grid squares, we'll test two of these.
			#
			#
			# if the cone's right edge is in [0,π/2], check that the top edge of the grid square overlaps the cone
			#
			set fuzz 3
			#if {$theta2_deg >= 0 && $theta2_deg <= 90} {
				for {set x [expr -$r]} {$x < $r} {set x [expr $x+$iscale]} {
					for {set y [expr -$r]} {$y < 0} {set y [expr $y+$iscale]} {
						if {($x < 0 && $x >= $y) || ($x >=0 && $x < -$y)} {
							foreach wid [$w find overlapping [expr $x0+$x+$fuzz] [expr $y0+$y] [expr $x0+$x+$iscale-$fuzz] [expr $y0+$y]] {
								if {[lsearch -exact [$w gettags $wid] REF$id] >= 0} {
									DrawAoeGrid $w [expr $x0+$x] [expr $y0+$y] [expr $x0+$x+$iscale] [expr $y0+$y+$iscale] $color $id $tags
									break
								}
							}
						}
					}
				}
			#}
			#
			# if the cone's right edge is in [π/2,π], check that the left edge of the grid square overlaps the cone
			#
			#if {$theta2_deg >= 90 && $theta2_deg <= 180} {
				for {set x [expr -$r]} {$x < 0} {set x [expr $x+$iscale]} {
					for {set y [expr -$r]} {$y < $r} {set y [expr $y+$iscale]} {
						if {($y < 0 && $y >= $x) || ($y >= 0 && $y < -$x)} {
							foreach wid [$w find overlapping [expr $x0+$x] [expr $y0+$y+$fuzz] [expr $x0+$x] [expr $y0+$y+$iscale-$fuzz]] {
								if {[lsearch -exact [$w gettags $wid] REF$id] >= 0} {
									DrawAoeGrid $w [expr $x0+$x] [expr $y0+$y] [expr $x0+$x+$iscale] [expr $y0+$y+$iscale] $color $id $tags
									break
								}
							}
						}
					}
				}
			#}
			#
			# if the cone's right edge is in [-π,-π/2], check that the bottom edge of the grid square overlaps the cone
			#
			#if {$theta2_deg >= -180 && $theta2_deg <= -90} {
				for {set x [expr -$r]} {$x < $r} {set x [expr $x+$iscale]} {
					for {set y 0} {$y < $r} {set y [expr $y+$iscale]} {
						if {($x < 0 && -$x-$iscale <= $y) || ($x >= 0 && $x <= $y)} {
							foreach wid [$w find overlapping [expr $x0+$x+$fuzz] [expr $y0+$y+$iscale] [expr $x0+$x+$iscale-$fuzz] [expr $y0+$y+$iscale]] {

								if {[lsearch -exact [$w gettags $wid] REF$id] >= 0} {
									DrawAoeGrid $w [expr $x0+$x] [expr $y0+$y] [expr $x0+$x+$iscale] [expr $y0+$y+$iscale] $color $id $tags
									break
								}
							}
						}
					}
				}
			#}
			#
			# if the cone's right edge is in [-π/2,0], check that the right edge of the grid square overlaps the cone
			#
			#if {$theta2_deg >= -90 && $theta2_deg <= 0} {
				for {set x 0} {$x < $r} {set x [expr $x+$iscale]} {
					for {set y [expr -$r]} {$y < $r} {set y [expr $y+$iscale]} {
						if {($y < 0 && $x >= -$y-$iscale) || ($y >= 0 && $x >= $y)} {
							foreach wid [$w find overlapping [expr $x0+$x+$iscale] [expr $y0+$y+$fuzz] [expr $x0+$x+$iscale] [expr $y0+$y+$iscale-$fuzz]] {

								if {[lsearch -exact [$w gettags $wid] REF$id] >= 0} {
									DrawAoeGrid $w [expr $x0+$x] [expr $y0+$y] [expr $x0+$x+$iscale] [expr $y0+$y+$iscale] $color $id $tags
									break
								}
							}
						}
					}
				}
			#}
		}
	}
	$w delete REF$id
}

#
# From a starting point (x0,y0), fill in all squares radiating out in all
# directions but constrained by a list of shapes (must be inside all shapes)
# to implement the idea of a "spread" area of effect.
# The distances are in canvas units (grid*iscale).
#
proc DrawAoeSpread {w x0 y0 r bounds tags color} {
	global iscale 
	set x1 [expr $x0-$iscale]
	set y1 [expr $y0-$iscale]
	set x2 [expr $x0+$iscale]
	set y2 [expr $y0+$iscale]
	set start_weight [expr 0.5 * $iscale]
	set adj_weight   [expr 1.0 * $iscale]
	set diag_weight  [expr 1.5 * $iscale]
	set weights($x1,$y1) $start_weight;		# set initial path weights for squares
	set weights($x0,$y1) $start_weight;		# directly around the starting point  
	set weights($x1,$y0) $start_weight;		#
	set weights($x0,$y0) $start_weight;		#
	::struct::queue to_do
	to_do put $x0,$y0
	to_do put $x0,$y1
	to_do put $x1,$y0
	to_do put $x1,$y1
	DrawAoeGrid $w $x1 $y1 $x0 $y0 $color {} $tags
	DrawAoeGrid $w $x0 $y1 $x2 $y0 $color {} $tags
	DrawAoeGrid $w $x1 $y0 $x0 $y2 $color {} $tags
	DrawAoeGrid $w $x0 $y0 $x2 $y2 $color {} $tags

	#puts "on $w, draw from ($x0,$y0) for $r within $bounds"
	while {[to_do size] > 0} {
		set point [to_do get]
		# add weights to this point's neighbors if they aren't already done
		# as long as we haven't gone past our total distance
		lassign [split $point ,] c1 r1
		#puts "Looking at neighbors of ($point) (column $c1, row $r1)"
		foreach neighbor [NeighborsOf $c1 $r1] {
			if {![info exists weights($neighbor)]} {
				# we haven't already computed a value for this square, so proceed now...
				lassign [split $neighbor ,] cc rr
				set my_weight 0
				set ok 1
				#
				# make sure we didn't cross a barrier to get here from the reference point (c1,r1)
				# for now, use the global AOE boundary object. In the future, we can distinguish
				# map features which are obstacles by using layers
				#
				if {$cc == $c1} {
					#
					# we're moving straight up or down. See if the zone inside both squares overlaps
					# the boundary
					#
					if {$rr < $r1} {set zy $rr} else {set zy $r1}
					foreach wid [$w find overlapping [expr $cc+3] [expr $zy+3] [expr $cc+$iscale-3] [expr $zy+($iscale*2)-3]] {
						if {[lsearch -exact [$w gettags $wid] objAOE_GLOBAL_BOUND] >= 0} {
							set ok 0 
							break
						}
					}
				} elseif {$rr == $r1} {
					#
					# we're moving straight left or right. See if the zone inside both squares overlaps
					# the boundary
					#
					if {$cc < $c1} {set zx $cc} else {set zx $c1}
					foreach wid [$w find overlapping [expr $zx+3] [expr $rr+3] [expr $zx+($iscale*2)-3] [expr $rr+$iscale-3]] {
						if {[lsearch -exact [$w gettags $wid] objAOE_GLOBAL_BOUND] >= 0} {
							set ok 0
							break
						}
					}
				} else {
					#
					# we're moving diagonally. See if the zone around the common corner overlaps
					# the boundary, which will cover the case of not going diagonally around
					# corners as well as through solid walls
					#
					if {$cc<$c1} {
						if {$rr<$r1} { 
							set zx [expr $c1-3]; set zy [expr $r1-3];	# going up and left
						} else {
							set zx [expr $c1-3]; set zy [expr $rr-3];	# going down and left
						}
					} else {
						if {$rr<$r1} {
							set zx [expr $cc-3]; set zy [expr $r1-3];	# going up and right
						} else {
							set zx [expr $cc-3]; set zy [expr $rr-3];	# going down and right
						}
					}
					foreach wid [$w find overlapping $zx $zy [expr $zx+6] [expr $zy+6]] {
						if {[lsearch -exact [$w gettags $wid] objAOE_GLOBAL_BOUND] >= 0} {
							set ok 0
							break
						}
					}
					foreach wid [$w find overlapping [expr $cc+3] [expr $rr+3] [expr $cc+$iscale-3] [expr $rr+$iscale-3]] {
						if {[lsearch -exact [$w gettags $wid] objAOE_GLOBAL_BOUND] >= 0} {
							set ok 0
							break
						}
					}
				}
				if {! $ok} {
					continue
				}
				#
				# If we made it this far, then (cc,rr) is a point we will
				# spread to (if it turns out to be in range).
				#
				foreach npoint [NeighborsOf $cc $rr] {
					if {[info exists weights($npoint)]} {
						# this is a neighbor we've calculated a value for, so it affects us too
						# are we coming at this square diagonally or adjacent?
						lassign [split $npoint ,] nc nr
						if {$nc == $cc || $nr == $rr} {
							# we're going straight up or down
							set wt [expr $adj_weight + $weights($npoint)]
						} else {
							# we're going diagonally
							set wt [expr $diag_weight + $weights($npoint)]
						}
						if {$my_weight == 0 || $my_weight > $wt} {
							set my_weight $wt
						}
					}
				}
				if {$my_weight > 0 && $my_weight < $r} {
					# include this grid in the area of effect

					to_do put $neighbor
					set weights($neighbor) $my_weight
					DrawAoeGrid $w $cc $rr [expr $cc+$iscale] [expr $rr+$iscale] $color {} $tags
				}
			}
		}
	}
	to_do destroy
}

proc NeighborsOf {c1 r1} {
	global iscale
	set    neigbors {}

	for {set col -1} {$col < 2} {incr col} {
		for {set row -1} {$row < 2} {incr row} {
			if {!($col == 0 && $row == 0)} {
				lappend neighbors [expr $c1+($col*$iscale)],[expr $r1+($row*$iscale)]
			}
		}
	}
	return $neighbors
}

proc DrawAoeGrid {w x1 y1 x2 y2 color id tags} {
	global AoeHatchWidth
	#DEBUG 0 "DrawAoEGrid $w $x1 $y1 $x2 $y2 $color $id"

	for {set x $x1; set y $y2} {$x < $x2} {set x [expr $x + ($x2-$x1)/4.0]; set y [expr $y - ($y2-$y1)/4.0]} {
		$w create line $x $y1 $x2 $y -fill $color -width $AoeHatchWidth -tags $tags
		if {$x > $x1} {
			$w create line $x1 $y $x $y2 -fill $color -width $AoeHatchWidth -tags $tags
		}
	}
}

proc PointsDictToList {p} {
	set pts {}
	foreach xy $p {
		lappend pts [dict get $xy X]
		lappend pts [dict get $xy Y]
	}
	return $pts
}

proc AllPointsFromObj {o} {
	set pts {}
	lappend pts [dict get $o X] [dict get $o Y]
	lappend pts {*}[PointsDictToList [dict get $o Points]]
	return $pts
}

proc ObjDrag {w x y} {
	global OBJdata OBJ_CURRENT OBJ_SNAP canvas zoom OBJ_MODE
	if {$OBJ_CURRENT != 0} {
		set new_coords "[lmap v [AllPointsFromObj $OBJdata($OBJ_CURRENT)] {expr $v*$zoom}] [SnapCoord [$canvas canvasx $x]] [SnapCoord [$canvas canvasy $y]]"
		if {[catch {
			$w coords obj$OBJ_CURRENT $new_coords
		} err]} {
			DEBUG 0 "Warning: Updating $OBJ_CURRENT coordinates to $new_coords failed: $err"
		}
		if {$OBJ_MODE == "ruler"} {
			global DistanceLabelText
			set d [DistanceAlongRoute $new_coords]
			set DistanceLabelText [format "%d grid%s, %d ft" $d [expr $d==1 ? {{}} : {{s}}] [expr $d*5] [expr ($d*5)==1 ? {{}} : {{s}}]]
		}
		update
	}
}

proc NextPoint {w x y} {
	global OBJdata OBJ_CURRENT OBJ_SNAP canvas zoom
	set x [$canvas canvasx $x]
	set y [$canvas canvasy $y]
	dict lappend OBJdata($OBJ_CURRENT) Points [dict create X [expr [SnapCoord $x] / $zoom] Y [expr [SnapCoord $y] / $zoom]]
	$w coords obj$OBJ_CURRENT "[ZoomVector {*}[AllPointsFromObj $OBJdata($OBJ_CURRENT)]] [SnapCoord $x] [SnapCoord $y]"
	update
}

proc LastPoint {w x y} {
	global OBJdata OBJ_CURRENT OBJ_SNAP canvas zoom
	set x [$canvas canvasx $x]
	set y [$canvas canvasy $y]
	dict lappend OBJdata($OBJ_CURRENT) Points [dict create X [expr [SnapCoord $x] / $zoom] Y [expr [SnapCoord $y] / $zoom]]
	EndObj $w 
}

proc LastAoePoint {w x y} {
	global OBJdata OBJ_CURRENT OBJ_SNAP canvas zoom
	set x [$canvas canvasx $x]
	set y [$canvas canvasy $y]
	set xx [SnapCoordAlways $x]
	set yy [SnapCoordAlways $y]
	dict lappend OBJdata($OBJ_CURRENT) Points [dict create X [expr $xx / $zoom] Y [expr $yy / $zoom]]
	$w delete obj_distance$OBJ_CURRENT
	$w delete obj_locator$OBJ_CURRENT
	$w delete obj_locator_radius$OBJ_CURRENT
	$w delete obj_locator_cone3_$OBJ_CURRENT
	$canvas create oval [expr $xx-10] [expr $yy-10] [expr $xx+10] [expr $yy+10] -width 3 -outline [dict get $OBJdata($OBJ_CURRENT) Fill] -tags [list obj$OBJ_CURRENT]
	$canvas create line [expr $xx-5] [expr $yy-5] [expr $xx+5] [expr $yy+5] -width 3 -fill [dict get $OBJdata($OBJ_CURRENT) Fill] -tags [list obj$OBJ_CURRENT]
	$canvas create line [expr $xx-5] [expr $yy+5] [expr $xx+5] [expr $yy-5] -width 3 -fill [dict get $OBJdata($OBJ_CURRENT) Fill] -tags [list obj$OBJ_CURRENT]
	EndObj $w 
}
	
proc LastArcPoint {w x y} {
	global OBJdata OBJ_CURRENT OBJ_SNAP canvas zoom
	set x [$canvas canvasx $x]
	set y [$canvas canvasy $y]
	dict lappend OBJdata($OBJ_CURRENT) Points [dict create X [expr [SnapCoord $x] / $zoom] Y [expr [SnapCoord $y] / $zoom]]
	bind $w <1>         "SetArcStartAngle $w %x %y"
	bind $w <B1-Motion> "DragArcStartAngle $w %x %y"
	bind $w <Motion>    "DragArcStartAngle $w %x %y"
}

proc DragArcStartAngle {w x y} {
	global OBJdata OBJ_CURRENT OBJ_SNAP ARCMODE canvas
	dict set OBJdata($OBJ_CURRENT) Start [expr $x % 360]
	dict set OBJdata($OBJ_CURRENT) Extent [expr $y % 360]
	dict set OBJdata($OBJ_CURRENT) ArcMode [::gmaproto::to_enum ArcMode $ARCMODE]

	$w itemconfigure obj$OBJ_CURRENT \
		-start [dict get $OBJdata($OBJ_CURRENT) Start] \
		-extent [dict get $OBJdata($OBJ_CURRENT) Extent] -style $ARCMODE
}

proc SetArcStartAngle {w x y} {
	DragArcStartAngle $w $x $y
	EndObj $w
	arctool
}

proc EndObj w {
	global OBJdata OBJ_CURRENT OBJ_MODE
	global BUTTON_MIDDLE BUTTON_RIGHT

	if {[info exists OBJtype($OBJ_CURRENT)]} {
		set t $OBJtype($OBJ_CURRENT)
	} else {
		set t $OBJ_MODE
	}

	if {$t != "tile" && $t != "text" && [llength [dict get $OBJdata($OBJ_CURRENT) Points]] == 0} {
		$w delete obj$OBJ_CURRENT
		RemoveObject $OBJ_CURRENT
		$w delete obj_distance$OBJ_CURRENT
	} elseif {$t == "ruler"} {
		# Rulers are only temporary. I suppose we could plant a flag at the endpoint or something
		# but right now we don't need to.
		$w delete obj$OBJ_CURRENT
		RemoveObject $OBJ_CURRENT
		$w delete obj_distance$OBJ_CURRENT
	} elseif {$t != "aoe"} {
		$w coords obj$OBJ_CURRENT [ZoomVector {*}[AllPointsFromObj $OBJdata($OBJ_CURRENT)]]
	}
	bind $w <1> "StartObj $w %x %y"
	bind $w $BUTTON_MIDDLE {}
	bind . <Key-Escape> {}
	update
	send_element $OBJ_CURRENT
	set OBJ_CURRENT 0
}

proc send_element {id} {
	global OBJtype OBJdata

	if {[info exists OBJtype($id)]} {
		::gmaproto::ls [::gmaproto::ObjTypeToGMAType $OBJtype($id)] $OBJdata($id)
	}
}

proc SquareGrid {w xx yy show} {
	global iscale GuideLines MajorGuideLines GuideLineOffset MajorGuideLineOffset GridEnable dark_mode
	global _preferences colortheme
	$w delete grid
	if {! $GridEnable} {
		return
	}
	set gridcolor  [::gmaprofile::preferred_color $_preferences grid $colortheme]
	set majorcolor [::gmaprofile::preferred_color $_preferences grid_major $colortheme]
	set minorcolor [::gmaprofile::preferred_color $_preferences grid_minor $colortheme]

	for {set x 0} {($x * $iscale) < $xx} {incr x} {
		if {$MajorGuideLines > 0 && (($x - [lindex $MajorGuideLineOffset 0]) % $MajorGuideLines) == 0} {
			set SGfc $majorcolor
			set SGw 3
		} elseif {$GuideLines > 0 && (($x - [lindex $GuideLineOffset 0]) % $GuideLines) == 0} {
			set SGfc $minorcolor
			set SGw  2
		} else {
			set SGfc $gridcolor
			set SGw  1
		}
		$w create line [expr $x*$iscale] 0 [expr $x*$iscale] $yy -fill $SGfc -tags "grid" -width $SGw
		if {$show} update
	}
	for {set y 0} {($y * $iscale) < $yy} {incr y} {
		if {$MajorGuideLines > 0 && (($y - [lindex $MajorGuideLineOffset 1]) % $MajorGuideLines) == 0} {
			set SGfc $majorcolor
			set SGw 3
		} elseif {$GuideLines > 0 && (($y - [lindex $GuideLineOffset 1]) % $GuideLines) == 0} {
			set SGfc $minorcolor
			set SGw  2
		} else {
			set SGfc $gridcolor
			set SGw  1
		}
		$w create line 0 [expr $y*$iscale] $xx [expr $y*$iscale] -fill $SGfc -tags "grid" -width $SGw
		if {$show} update
	}
		
#	for {set x 0} {($x * $iscale) < $xx} {incr x} {
#		if {($x % 10) == 0} {
#			puts -nonewline [format "%5d\r" [expr $xx - ($x * $iscale)]]
#			flush stdout
#		}
#		for {set y 0} {($y * $iscale) < $yy} {incr y} {
#			$w create rectangle [expr $x*$iscale] [expr $y*$iscale] [expr ($x+1)*$iscale] [expr ($y+1)*$iscale] -outline blue -tags "grid g$x,$y"
#			if $show update
#		}
#	}
#	puts [format "%5d" 0]
#	flush stdout
}

#
# Grids are organized from origin at upper-left corner (0,0)
# they're drawn scaled (for now) by 50 
# grid rectangles are tagged as "g<x>,<y>" where <x> and <y> are grid id numbers
# and all as "grid"
#

#
# Objects which can be moved around on the grid:
#   MOB(ID:<name>)  <id>
#   MOB(NAME:<id>)  <name>
#   MOB(GX:<id>)    <grid-x>
#   MOB(GY:<id>)    <grid-y>
#   MOB(COLOR:<id>) <color>
# DEPRECATED  MOB(AREA:<id>)  <grids surrounding object for threat area> or size code
#		FDTSMLHGC  lower-case is long, upper-case is tall
#   MOB(SIZE:<id>)  <grid diameter> or size code
#   MOB(TYPE:<id>)  {player|monster}
#	MOB(REACH:<id>)	bool indicating if reach zone is enabled for the mob
#

#
# create mob and draw it on the map
# mobs are tagged M#<id>
#
# PlaceSomeone widget gridX gridY color name area {player|monster} id reach
# TODO: if name contains "#[n]-[m]" then generate multiples in that range
#
set MOB_COMBATMODE 0
set NextMOBID 0
proc PopSomeoneToFront {w id} {
	RenderSomeone $w $id
}

#proc PlaceSomeone {w x y c n a s t id reach} {}
proc PlaceSomeone {w d} {
	global MOBdata MOBid NextMOBID OBJ_NEXT_Z canvas


	set n [dict get $d Name]
	set id [dict get $d ID]
	if {[info exists MOBid($n)] && $id ne $MOBid($n)} {
		DEBUG 1 "Placing [::gmaclock::nameplate_text $n] (ID $id) but already have one with ID $MOBid($n)"
		DEBUG 1 "--Removing old one"
		::gmaproto::clear $MOBid($n)	;# TODO ???
		RemovePerson $MOBid($n)
	}

	if {![info exists MOBdata($id)]} {
		DEBUG 1 "--Adding new person [::gmaclock::nameplate_text $n] with ID $id"
		set MOBid($n) $id
		set MOBdata($id) $d
	} else {
		DEBUG 1 "--PlaceSomeone [::gmaclock::nameplate_text $n] using existing id $id (updating in-place)"
		set MOBdata($id) [dict merge $MOBdata($id) $d]
	}

	if {[set fullinfo [FullCreatureAreaInfo $id]] eq {}} {
		DEBUG 0 "Can't get area info for creature $id"
	} else {
		lassign $fullinfo mob_size mob_area mob_reach mob_matrix custom_reach
		if {$custom_reach ne {}} {
			dict set MOBdata($id) CustomReach $custom_reach
		}
	}

	MoveSomeone $w $id [dict get $d Gx] [dict get $d Gy]
}

proc MoveSomeone {w id x y} {
	global MOBdata
	global CombatantScrollEnabled
	global CombatantSelected
	global is_GM
	global MOB_COMBATMODE


	if {[info exists MOBdata($id)]} {
		dict set MOBdata($id) Gx $x
		dict set MOBdata($id) Gy $y
		if {$CombatantScrollEnabled && $CombatantSelected eq $id && [info exists MOBdata($CombatantSelected)] && (![dict get $MOBdata($CombatantSelected) Hidden] || $is_GM)} {
			if {!$MOB_COMBATMODE} {
				set CombatantSelected {}
			} else {
				ScrollToCenterScreenXY [GridToCanvas [dict get $MOBdata($CombatantSelected) Gx]] \
						       [GridToCanvas [dict get $MOBdata($CombatantSelected) Gy]]
			}
		}
		RenderSomeone $w $id
	}
}

proc MOBCenterPoint {id} {
	global MOBdata iscale
	set x [dict get $MOBdata($id) Gx]
	set y [dict get $MOBdata($id) Gy]
	if {[set fullinfo [FullCreatureAreaInfo $id]] eq {}} {
		DEBUG 0 "Can't get area info on $id to figure out the center point"
		set r 1
	} else {
		set r [expr [lindex $fullinfo 0] / 2.0]
	}
	return [list [expr ($x+$r)*$iscale] [expr ($y+$r)*$iscale] [expr $r*$iscale]]
}

proc FindImage {image_pfx zoom} {
	global TILE_SET TILE_RETRY TILE_ANIMATION

	set tile_id [tile_id $image_pfx $zoom]
	if {! [info exists TILE_SET($tile_id)] && ! [info exists TILE_ANIMATION($tile_id,frames)]} {
		DEBUG 1 "Asked for image $image_pfx at zoom $zoom, but that image isn't already loaded."
		set cache_filename [cache_filename $image_pfx $zoom]
		if {[lindex [set cache_stats [cache_info $cache_filename]] 0]} {
			DEBUG 1 "--Cache file $cache_filename exists, using that..."
			if {[lindex $cache_stats 4] eq "-dir"} {
				DEBUG 1 "--and it's animated"
				if {[catch {
					set animation_meta [animation_read_metadata $cache_filename $image_pfx $zoom]
					_load_local_animated_file $cache_filename $image_pfx $zoom \
						[dict get $animation_meta Animation Frames]\
						[dict get $animation_meta Animation FrameSpeed]\
						[dict get $animation_meta Animation Loops]
				} err]} {
					DEBUG 0 "Error loading image $cache_filename: $err"
				}
			} else {
				create_image_from_file $tile_id $cache_filename
			}
		} else {
			DEBUG 1 "--No cached copy exists, either. Asking for help..."
			# We used to throttle by dropping requests so we only send every 10th and then every 50th to the server
			# but as it turns out we can still get too many sent at once so now we'll make the fallback time-based.
			# We will ask immediately, then no sooner than 30 seconds, then no sooner than 60 seconds
			#
			# After we added code to stop even asking if we get a 404 (or other 400+ failure) from the server,
			# we don't need to be quite so conservative about backoff times. Now we'll wait 5 seconds after the first
			# one and 10 after that.
			if {![info exists TILE_RETRY($tile_id)]} {
				# first reference: ask now and wait for 5 seconds
				set TILE_RETRY($tile_id) [clock add [clock seconds] 5 seconds]
				::gmaproto::query_image $image_pfx $zoom
				DEBUG 1 "---first query (sending immediately; try again in 5 seconds)"
			} elseif {$TILE_RETRY($tile_id) < [clock seconds]} {
				# subsequent times: ask every 10 seconds
				::gmaproto::query_image $image_pfx $zoom
				set TILE_RETRY($tile_id) [clock add [clock seconds] 10 seconds]
				DEBUG 1 "---trying again (10 seconds until next try)"
			} else {
				DEBUG 1 "---Too early to try again"
			}
		}
	}

	return $tile_id
}

# Resizing creature tokens locally can be done with an expanded usage of the
# mechanism used to zoom in/out on the map.
# Assuming we could have tokens at zoom levels 0.25, 0.50, 1, 2, 4, 8, 16, and 32,
# compute the actual zoom level based on the map zoom level, creature original size
# (used for creating their token originally) and the displayed size.
proc _creature_zoom_relative_to_medium size {
	if {[set p [CreatureSizeParams $size]] ne {}} {
		if {[lindex $p 3] ne {}} {
			return [lindex $p 3]
		}
		switch -exact -- [lindex $p 0] {
			f - F { return 0.1 }
			d - D { return 0.2 }
			t - T { return 0.5 }
			s - S - m - M { return 1.0 }
			l - L { return 2.0 }
			h - H { return 3.0 }
			g - G { return 4.0 }
			c - C { return 6.0 }
		}
	}
	return 0
}
proc creature_display_zoom {size dispsize zoom} {
	set newzoom [expr ($zoom / [_creature_zoom_relative_to_medium $size]) * [_creature_zoom_relative_to_medium $dispsize]]
	foreach defined {32.00 16.00 12.00 8.00 6.00 4.00 3.00 2.00 1.00 0.50 0.25} {
		if {$newzoom >= $defined} {
			return $defined
		}
	}
	return 0
}

# ParseSizeCode sizecode -> category reach extended tokensize default? comment OR throws error
proc ParseSizeCode {sizecode} {
	if {[regexp -nocase {^\s*([fdtsmlhgc])(\d+)?(?:->(\d+))?(?:=(\d+))?(?::(\*)?(.*))?\s*$} $sizecode _ category reach extended token def comment]} {
		return [list $category $reach $extended $token [expr "{$def} eq {*}"] $comment]
	}
	error "invalid size code \"$sizecode\""
}

proc SkinComment {sizecode} {
	if {[catch {
		set comment [lindex [ParseSizeCode $sizecode] 5]
	} err]} {
		DEBUG 0 "ERROR in SkinComment: $err; sizecode=$sizecode"
		return ""
	}
	return $comment
}

proc SkinIsDefault {sizecode} {
	if {[catch {
		set def [lindex [ParseSizeCode $sizecode] 4]
	}]} {
		return false
	}
	return $def
}

proc SkinSizeOnly {sizecode} {
	return [regsub {:.*$} $sizecode {}]
}

proc CreatureDisplayedSize {id} {
	global MOBdata
	if {[dict exists $MOBdata($id) DispSize] && [set dsize [dict get $MOBdata($id) DispSize]] ne {}} {
		return [SkinSizeOnly $dsize]
	}
	return [SkinSizeOnly [dict get $MOBdata($id) Size]]
}

#
# RenderSomeone draws a creature token at its current location based on its object attributes.
#
# The object is in the array MOB(<attrib>:<id>)
# AOE = {aoe_type aoe_radius aoe_color}		aoe_radius is scaled
#   Draws area of effect around creature
#
# x,y = GX,GY attrs
# mob_area, mob_reach, mob_matrix derived from AREA attr
# mob_size derived from SIZE attr
#
# area of threat (if MOB_COMBATMODE)
#   if not their turn, draw a circle (all coords scaled by iscale)
#   .........................................................
#   :                      ^                                :<-if REACH
#   :  ................___.|..............................  :
#   :  :                ^  |                             :  :
#   :  :                |  |mob_reach                    :  :
#   :  :          mob_area |                             :  :
#   :  :                |  |                             :  :
#   :  |<--mob_area---(x,y)--mob_size-->|<---mob_area--->|  :
#   |<-------mob_reach- |mob_size       |<-----mob_reach--->|
#   :  :                V_______________|                :  :
#   :  :                |            ^                   :  :
#   :  :                |mob_area    |                   :  :
#   :  :..............__V__..........|...................:  :
#   :                                |mob_reach             :
#   :................................V......................:
#
#
#  otherwise, it's a bit more complicated.
#
#  Xstart
#   |
#   ...........................................___.................................. --yy
#   :                                           ^                                  :
#   :                                           |mob_                            *--------fill from mob_matrix
#   :                                           |reach                             :      2s with COLOR
#   :           ..........................___...|......................            :      1s if REACH, with ReachLineColor
#   :           :                          ^    |                     :            :
#   :           :                  mob_area|    |                     :            :
#   :           :                   x      |    |                     :            :
#   :           :                   |      |    |                     :            :
#   :           :                y--......_V_.._V_.___.               :            :
#   :           :                   :               ^ :               :            :
#   :           |<----mob_area----->|       mob_size| :               :            :
#   :           :                   :               | :               :            :
#   :           :                   |<---mob_size---->|<----mob_area->|            :
#   |<--------------mob_reach------>|               | |<-----------mob_reach------>|
#   :           :                   :.............._V_:               :            :
#   :           :                                   ^                 :            :
#   :           :                                   |                 :            :
#   :           :                                   |                 :            :
#   :           :                                   |                 :            :
#   :           :                                   |                 :            :
#   :           :...................................|.................:            *---draw circle if REACH
#   :                                               |                              :
#   :                                               |mob_reach                     :
#   :                                               |                              :
#   :.............................................._V_.............................:
#
#

# Health bar sizes
set HealthBarWidth 10
set HealthBarConditionFrameWidth 4
set HealthBarFrameWidth 2

#   x      s
# y +------------+
#   |            |
#   |          po|isoned
#  s|vv        ov|
#   |bleed       |energy drain
#   | ability dr |
#   +------------+ y1
#                x1
# CreatureStatusMarker $w $id [expr $x*$iscale] [expr $y*$iscale] [expr $mob_size*$iscale]
#

#  v  R bleed (auto updates hp)
#  // K blinded CN dazzled \\ GN deafened
#  =  Y confused ? cowering V dazed LtV fascinated ? paralyzed CN helpless(maybe because of other conditions) ? staggered ? stunned
#| X/ * (dead) * dying GY disabled BN unconscious(maybe from other conditions) ? petrified ? stable
#  v  OR ability_drained K energy_drained 
#|-#+ Y entangled +OR grappled +R pinned -BL prone
#  V^ ? exhausted OR fatigued ^? nauseated ^? sickened
#|    BL (flat-footed)
#| O  Y shaken ? frightened ? panicked
#| <> ? incorporeal
#| <> ? invisible
#| o  GN poisoned
#
# 

# marker colors
# These can be 
# 	Any platform-recognized color name (e.g. X11 rgb.txt file)
#   #rgb #rrggbb #rrrgggbbb #rrrrggggbbbb
#   * (to use creature's area-fill color)
#   --color	(to use dashed line in the given color)

array set MarkerColor {
	bleed	    		red
	{ability damage} 	yellow
	{ability drained} 	orange
	{energy drained}  	black
	poisoned    		green
 	deafened    		black
	stable      		sienna

	blinded     		black
 	dazzled     		cyan
 
	confused    		orange
	cowering    		sienna
	dazed       		purple
	fascinated  		cyan
	paralyzed   		black
	helpless    		gray
	staggered   		blue
	stunned     		red

	dying       		*
	disabled    		red
	unconscious 		purple
	petrified   		gray


	entangled   		green
	grappled    		orange
	pinned      		red
	prone       		blue

	exhausted   		red
	fatigued    		orange
	nauseated   		green
	sickened    		sienna

	flat-footed 		blue
	incorporeal 		gray
	invisible   		..black

	shaken      		sienna
	frightened  		yellow
	panicked    		red
}

# marker shapes are
#	|v  v| 	small downward triangle badge on the left or right
#   |o  o|  small circle badge on the left or right
#   |<><>|  small diamond badge on the left or right
#   // \\   double slash or backslash through entire token
#   /   \   single   "    "    "         "      "      "
# 	=   -   double or single horizontal line through center of entire token
#   ||  |	double or single vertical    "      "      "    "    "      "
#   #   +   double or single vertical and horizontal lines through entire token
#   V   ^   downward or upward triangle around entire token
#   <>  O   diamond or circle around entire token

array set MarkerShape {
	bleed	    		|v
	{ability damage} 	|v
	{ability drained} 	|v
	{energy drained}  	v|
	poisoned    		o|
	deafened			|<>
	stable      		<>|

	blinded     		//
 	dazzled     		//
 
	confused    		=
	cowering    		=
	dazed       		=
	fascinated 			=
	paralyzed  			=
	helpless   			=
	staggered  			=
	stunned    			=

	dying       		/
	disabled    		|
	unconscious 		||
	petrified   		X


	entangled   		#
	grappled    		+
	pinned      		+
	prone       		-

	exhausted   		V
	fatigued    		V
	nauseated   		^
	sickened    		^

	flat-footed 		O
	incorporeal 		O
	invisible   		O

	shaken      		<>
	frightened  		<>
	panicked    		<>
}

array set MarkerTransparent {
	incorporeal true
	invisible   true
}

array set MarkerDescription {
	bleed	    		{Bleeding: take damage each turn unless stopped by a DC 15 Heal check or any spell that cures hit point damage (even if bleed is ability damage).}
	blinded     		{Blinded: cannot see, -2 AC, no Dexterity bonus to AC, -4 on most Strength- and Dexterity-based skill checks and opposed Perception skill checks. All checks and activities that rely on vision automatically fail. Opponents have total concealment (50% miss chance). Must make DC 10 Acrobatics check to move faster than 1/2 speed (fail: fall prone).}
	confused    		{Confused: cannot act normally or tell ally from foe, treating all as enemies. Action is random: 01-25%=normal, 26-50%=babble incoherently, 51-75%=deal 1d8+Str modifier damage to self, 76-100%=attack nearest creature. Beneficial touch spells require attack roll. Attacks last creature who attacked it. Will not make attacks of opportunity unless against creature already fighting.}
	cowering    		{Cowering: frozen in fear and can take no actions. -2 AC, no Dexterity bonus.}
	dazed       		{Dazed: unable to act normally (no actions, no AC penalty).}
 	dazzled     		{Dazzled: unable to see well because of overstimulation of the eyes. -1 on attack rolls and sight-based Perception checks.}
	dead			{Dead: soul leaves body, cannot be healed.}
	deafened		{Deafened: cannot hear. -4 initiative, automatically fails Perception checks based on sound, -4 on opposed Perception checks, 20% of spell failure when casting spells with verbal components.}
	disabled    		{Disabled: conscious, make take a single move or standard action but not both nor full-round actions; swift, immediate, and free actions are ok. Move at 1/2 speed. Std actions that are strenuous deal 1 point of damage at completion.}
	dying       		{Dying: unconscious, no actions. Each turn make DC 10 Constitution check to stabilize, at penalty equal to current (negative) hit points. Natural 20=auto success. If check failed, take 1 hp damage.}
	{energy drained}  	{Energy Drained: has negative levels. Take cumulative -1 penalty per level drained on all ability checks, attack rolls, combat maneuver checks, combat maneuver defense, saving throws, and skill checks. Current and total hit points reduce by 5 per negative level. Treated as level reduction for level-dependent variables. No loss of prepared spells or slots. Daily saving throw to remove each negative level unless permanent.  If negative levels >= hit dice, dies.}
	entangled   		{Entangled: ensnared, move at 1/2 speed, cannot run or charge, -2 attack, -4 Dexterity. Spellcasting requires concentration DC 15+spell level or lose spell.}
	exhausted   		{Exhausted: move 1/2 speed, cannot run or charge, -6 Strength and Dexterity. Change to fatigued after 1 hour of complete rest.}
	fascinated 		{Fascinated: entranced by Su or Sp effect. Stand or sit quietly, taking no other actions. -4 on skill checks made as reactions. Potential threats grant new saving throw against fascinating effect. Obvious threat automatically breaks fascination. Ally may make shake creature free of the effect as standard action.}
	fatigued    		{Fatigued: can't run or charge, -2 penalty to Strength and Dexterity. Advance to exhausted if doing anything that would normally cause fatigue; Remove after 8 hours of complete rest.}
	flat-footed 		{Flat-Footed: not yet acted during combat, unable to react normally to the situation. Loses Dexterity bonus to AC, cannot make attacks of opportunity.}
	frightened  		{Frightened: flees from source of fear if possible, else fight. -2 attacks, saving throws, skill checks, and ability checks. Can use special abilities and spells to flee (MUST do so if they are only way to escape).}
	grappled    		{Grappled: restrained, cannot move, -4 Dexterity, -2 attacks and combat maneuver checks except those made to grapple or escape grapple. No action requiring two hands. Spellcasting or (Sp) requires concentration DC 10 + grappler's CMB + spell level) or lose spell. Cannot make attack of opportunity. Cannot use Stealth against grappler but if becomes invisible, gain +2 on CMD to avoid being grappled.}
	helpless   		{Helpless: paralyzed, held, bound, sleeping, unconscious, etc. Effective Dexterity of 0. Melee attackers get +4 bonus (no bonus for ranged). Can be sneak attacked. Subject to coup de grâce (full-round action with automatic critical hit, Fort save DC 10 + damage dealt or die; if immune to critical hits, then critical damage not taken nor Fort save required).}
	incorporeal 		{Incorporeal: no physical body. Immune to nonmagic attacks, 50% damage from magic weapons, spells, Sp effects, Su effects. Full damage from other incorporeal creatures and effects as well as force effects.}
	invisible   		{Invisible: +2 attack vs. sighted opponent, ignore opponent Dexterity bonus to AC. Immune to favored enemy/sneak attack damage. Can be noticed by those within 30 ft (DC 20 Perception) but cannot be targeted w/o +20 DC to pinpoint location, even so still 50% miss chance; see p. 563.}
	nauseated   		{Nauseated: Cannot attack, cast spells, concentrate on spells, or do anything else requiring attention. Can only take a single move action.}
	panicked    		{Panicked: drop anything held and flee at top speed along random path. -2 on saving throws, skill checks, ability checks. If cornered, cowers. Can use special abilities and spells to flee (MUST if that's the only way to escape).}
	paralyzed  		{Paralyzed: frozen in place, unable to move or act. Effective Dexterity and Strength of 0. Helpless but can take purely mental actions. Winged flying creatures fall. Swimmers may drown. Others may move through space of paralyzed creatures, but counts as 2 spaces.}
	petrified   		{Petrified: turned to stone, unconscious. Broken pieces must be reattached when turning to flesh to avoid permanent damage.}
	pinned      		{Pinned: tightly bound. Cannot move. No Dexterity bonus, plus -4 AC. May attempt to free with CMB or Escape Artist check, take verbal and mental actions, but not cast spells with somatic or material components. Spell casting requires concentration DC 10 + grappler's CMB + spell level or lose spell. More severe than (and does not stack with) grapple condition.}
	prone       		{Prone: lying on ground. -4 on melee attacks, cannot use ranged weapon except crossbows. +4 AC vs. ranged attacks but -4 AC vs. melee attacks. Standing up is a move-equivalent action that provokes attacks of opportunity.}
	shaken      		{Shaken: -2 on attacks, saving throws, skill checks, ability checks.}
	sickened    		{Sickened: -2 on attacks, weapon damage, saving throws, skill checks, ability checks.}
	stable      		{Stable: no longer dying but unconscious. If made stable by other's action, may make DC 10 Constitution check hourly to become conscious and disabled even with negative hit points, with check penalty equal to negative hit points. If became stable without help, can make hourly Con check to become stable as above but failure causes 1 hit point damage.}
	staggered  		{Staggered: only single move or standard action. No full-round actions but ok to make free, swift, and immediate actions.}
	stunned    		{Stunned: drop everything held, take no actions, -2 AC, lose Dexterity bonus to AC.}
	unconscious 		{Unconscious: knocked out and helpless.}

	{ability damage}	{Ability Damage: penalties to ability-related checks but does not affect the ability score itself.}
	{ability drained} 	{Ability Drained: Ability score reduced with all applicable effects that implies. May be healed via spells such as restoration.}
	poisoned    		{Poisoned: may have onset delay and additional saving throws and additional damage over time as the poison runs its course.}
}


proc CreatureStatusTransparent {id conditions} {
	global MarkerTransparent MOBdata
	set transparent false

	if {[dict get $MOBdata($id) Hidden]} {
		return true
	}
	foreach condition [CreatureStatusConditions $id $conditions] {
		if {[info exists MarkerTransparent($condition)] && $MarkerTransparent($condition)} {
			set transparent true
		}
	}
	return $transparent
}

proc CreatureStatusConditions {id calc_condition} {
	global MOBdata
	
	# HEALTH conditions
	#  normal/{} flat staggered unconscious stable disabled dying
	# dying: half-slash through the token
	set conditions $calc_condition
	if {[info exists MOBdata($id)]} {
		if {[dict get $MOBdata($id) Health] ne {}} {
			if {[set condition [dict get $MOBdata($id) Health Condition]] ne {}} {
				lappend conditions $condition
			}
			if {[dict get $MOBdata($id) Health IsFlatFooted] && [lsearch -exact $conditions flat-footed] < 0} {
				lappend conditions flat-footed
			}
			if {[dict get $MOBdata($id) Health IsStable] && [lsearch -exact $conditions stable] < 0} {
				lappend conditions stable
			}
		}
		foreach condition [dict get $MOBdata($id) StatusList] {
			if {[lsearch -exact $conditions $condition] < 0} {
				lappend conditions $condition
			}
		}
	}
	return $conditions
}

proc CreatureStatusMarker {w id x y s calc_condition} {
	global MOBdata MarkerColor MarkerShape
	
	# HEALTH conditions
	#  normal/{} flat staggered unconscious stable disabled dying
	# dying: half-slash through the token
	set conditions [CreatureStatusConditions $id $calc_condition]
	if {[llength $conditions] == 0} {
		return
	}

	set x1 [expr $x + $s]
	set y1 [expr $y + $s]
	set tags "mob MF#$id M#$id MN#$id allMOB"

	set Vo   0; # V triangle around token full size
	set To   0; # ^ triangle around token full size
	set vlo  0; # left v triangle badge   small
	set vro  0; # right v triangle badge  small
	set slo  0; # slashes /               full size
	set bso  0; # backslashes  \          full size
	set dbr  0; # double bar = # ||       full size
	set sslo 0; # slashes //              full size
	set bbso 0; # backslashes \\          full size
	set sbr  0; # single bar - | +        full size
	set diao 0; # diamond <>              full size
	set oo   0; # circle around full token

	foreach condition $conditions {
		if {[info exists MarkerShape($condition)] && [info exists MarkerColor($condition)]} {
			if {[set color $MarkerColor($condition)] eq {*}} {
				set color [dict get $MOBdata($id) Color]
			}
			if {[string range $color 0 1] eq {--}} {
				set color [string range $color 2 end]
				set dashpattern {-}
			} elseif {[string range $color 0 1] eq {..}} {
				set color [string range $color 2 end]
				set dashpattern {.}
			} else {
				set dashpattern {}
			}
			
			# calculate border color
			lassign [winfo rgb . $color] fillR fillG fillB
			if {$fillR * 0.299 + $fillG * 0.587 + $fillB * 0.114 > 32767} {
				set outlineColor black
			} else {
				set outlineColor white
			}
			switch -exact $MarkerShape($condition) {
				|v		{
							$w create polygon [expr $x+$vlo] [expr $y+($s*.5)] \
									  [expr $x+$vlo+10] [expr $y+($s*.5)] \
									  [expr $x+$vlo+5] [expr $y+($s*.5)+15] \
									  [expr $x+$vlo] [expr $y+($s*.5)] \
								-fill $color -width 1 -outline $outlineColor -tags $tags -dash $dashpattern
							incr vlo 10
						}
				v|		{
							$w create polygon [expr $x1-$vro] [expr $y+($s*.5)] \
											  [expr $x1-$vro-10] [expr $y+($s*.5)] \
											  [expr $x1-$vro-5] [expr $y+($s*.5)+15] \
											  [expr $x1-$vro] [expr $y+($s*.5)] \
								-fill $color -width 1 -outline $outlineColor -tags $tags -dash $dashpattern
							incr vro 10
						}
				|o		{
							$w create oval [expr $x+$vlo] [expr $y+($s*.5)] \
									  	   [expr $x+$vlo+15] [expr $y+($s*.5)+15] \
								-fill $color -width 1 -outline $outlineColor -tags $tags -dash $dashpattern
							incr vlo 15
						}
				o|		{
							$w create oval [expr $x1-$vro] [expr $y+($s*.5)] \
									  	   [expr $x1-$vro-15] [expr $y+($s*.5)+15] \
								-fill $color -width 1 -outline $outlineColor -tags $tags -dash $dashpattern
							incr vro 15
						}
				|<>		{
							$w create polygon [expr $x+$vlo+5] [expr $y+($s*.5)] \
									  	      [expr $x+$vlo+10] [expr $y+($s*.5)+7] \
									  	      [expr $x+$vlo+5] [expr $y+($s*.5)+15] \
									  	      [expr $x+$vlo] [expr $y+($s*.5)+7] \
									  	      [expr $x+$vlo+5] [expr $y+($s*.5)] \
								-fill $color -width 1 -outline $outlineColor -tags $tags -dash $dashpattern
							incr vlo 10
						}
				<>|		{
							$w create polygon [expr $x1-$vro-5] [expr $y+($s*.5)] \
									  	      [expr $x1-$vro-10] [expr $y+($s*.5)+7] \
									  	      [expr $x1-$vro-5] [expr $y+($s*.5)+15] \
									  	      [expr $x1-$vro] [expr $y+($s*.5)+7] \
									  	      [expr $x1-$vro-5] [expr $y+($s*.5)] \
								-fill $color -width 1 -outline $outlineColor -tags $tags -dash $dashpattern
							incr vro 10
						}
				{\\\\}	{
							$w create line [expr $x+$bbso+10] $y \
										   [expr $x1+$bbso] $y1 \
								-fill $color -width 5 -tags $tags -dash $dashpattern
							$w create line [expr $x+$bbso] $y \
										   [expr $x1+$bbso-10] $y1 \
								-fill $color -width 5 -tags $tags -dash $dashpattern
							incr bbso 4
						}
				//		{
							$w create line [expr $x1-$sslo-10] $y \
										   [expr $x-$sslo] $y1 \
								-fill $color -width 5 -tags $tags -dash $dashpattern
							$w create line [expr $x1-$sslo] $y \
										   [expr $x-$sslo+10] $y1 \
								-fill $color -width 5 -tags $tags -dash $dashpattern
							incr sslo 4
						}
				{\\}   	{
							$w create line [expr $x+$bso] $y \
										   [expr $x1+$bso] $y1 \
								-fill $color -width 7 -tags $tags -dash $dashpattern
							 incr bso 5
				        }
				/   	{
							$w create line [expr $x1+$slo] $y \
										   [expr $x+$slo] $y1 \
								-fill $color -width 7 -tags $tags -dash $dashpattern
							 incr slo 5
						}
				=		{
							$w create line $x [expr $y+($s*.4)+$dbr] \
										   $x1 [expr $y+($s*.4)+$dbr] \
								-fill $color -width 5 -tags $tags -dash $dashpattern
							$w create line $x [expr $y+($s*.6)+$dbr] \
										   $x1 [expr $y+($s*.6)+$dbr] \
								-fill $color -width 5 -tags $tags -dash $dashpattern
							incr dbr 4
						}
				-		{
							$w create line $x [expr $y+($s*.5)+$sbr] \
										   $x1 [expr $y+($s*.5)+$sbr] \
								-fill $color -width 5 -tags $tags -dash $dashpattern
							incr sbr 4
						}
				||		{
							$w create line [expr $x+($s*.4)+$dbr] $y \
										   [expr $x+($s*.4)+$dbr] $y1 \
								-fill $color -width 5 -tags $tags -dash $dashpattern
							$w create line [expr $x+($s*.6)+$dbr] $y \
										   [expr $x+($s*.6)+$dbr] $y1 \
								-fill $color -width 5 -tags $tags -dash $dashpattern
							incr dbr 4
						}
				|		{
							$w create line [expr $x+($s*.5)+$sbr] $y \
										   [expr $x+($s*.5)+$sbr] $y1 \
								-fill $color -width 5 -tags $tags -dash $dashpattern
							incr sbr 4
						}
				{#}		{
							$w create line [expr $x+($s*.4)+$dbr] $y \
										   [expr $x+($s*.4)+$dbr] $y1 \
								-fill $color -width 5 -tags $tags -dash $dashpattern
							$w create line [expr $x+($s*.6)+$dbr] $y \
										   [expr $x+($s*.6)+$dbr] $y1 \
								-fill $color -width 5 -tags $tags -dash $dashpattern
							$w create line $x [expr $y+($s*.4)+$dbr] \
										   $x1 [expr $y+($s*.4)+$dbr] \
								-fill $color -width 5 -tags $tags -dash $dashpattern
							$w create line $x [expr $y+($s*.6)+$dbr] \
										   $x1 [expr $y+($s*.6)+$dbr] \
								-fill $color -width 5 -tags $tags -dash $dashpattern
							incr dbr 4
						}
				+		{
							$w create line [expr $x+($s*.5)+$sbr] $y \
										   [expr $x+($s*.5)+$sbr] $y1 \
								-fill $color -width 5 -tags $tags -dash $dashpattern
							$w create line $x [expr $y+($s*.5)+$sbr] \
										   $x1 [expr $y+($s*.5)+$sbr] \
								-fill $color -width 5 -tags $tags -dash $dashpattern
							incr sbr 4
						}
				V		{
							$w create line [expr $x+$Vo] [expr $y+$Vo] \
										   [expr $x1-$Vo] [expr $y+$Vo] \
										   [expr $x+($s*.5)] [expr $y1-$Vo] \
										   [expr $x+$Vo] [expr $y+$Vo] \
								-fill $color -width 5 -tags $tags -dash $dashpattern
							incr Vo 4
						}
				^		{
							$w create line [expr $x+($s*.5)] [expr $y+$To] \
										   [expr $x+$To] [expr $y1-$To] \
										   [expr $x1-$To] [expr $y1-$To] \
										   [expr $x+($s*.5)] [expr $y+$To] \
								-fill $color -width 5 -tags $tags -dash $dashpattern
							incr To 4
						}
				<>		{
							$w create line [expr $x+($s*.5)] [expr $y+$diao] \
										   [expr $x1-$diao] [expr $y+($s*.5)] \
										   [expr $x+($s*.5)] [expr $y1-$diao] \
										   [expr $x+$diao] [expr $y+($s*.5)] \
										   [expr $x+($s*.5)] [expr $y+$diao] \
								-fill $color -width 5 -tags $tags -dash $dashpattern
							incr diao 4
						}
				O		{
							$w create oval [expr $x+$oo] [expr $y+$oo] \
										   [expr $x1-$oo] [expr $y1-$oo] \
								-fill {} -outline $color -width 5 -tags $tags -dash $dashpattern
							incr oo 4
						}
				X		{
							$w create line [expr $x1+$slo] $y \
										   [expr $x+$slo] $y1 \
								-fill $color -width 7 -tags $tags -dash $dashpattern
							$w create line [expr $x+$bso] $y \
										   [expr $x1+$bso] $y1 \
								-fill $color -width 7 -tags $tags -dash $dashpattern
							 incr bso 5
							 incr slo 5
						}
				default	{
						}
							
			}
		}
	}
}

proc RenderSomeone {w id {norecurse false}} {
	DEBUG 3 "RenderSomeone $w $id"
	global MOBdata ThreatLineWidth iscale SelectLineWidth ThreatLineHatchWidth ReachLineColor
	global HealthBarWidth HealthBarFrameWidth HealthBarConditionFrameWidth
	global ShowHealthStats is_GM
	set lower_neighbors {}

	#
	# find out where everyone is
	# TODO: This would be more efficient to do less frequently than every time we call RenderSomeone
	#
	array unset WhereIsMOB
	foreach mob_id [array names MOBdata] {
		DEBUG 1 "Looking for location of $mob_id"
		if {![dict get $MOBdata($mob_id) Killed] && ![dict get $MOBdata($mob_id) Hidden]} {
			set xx [expr int([dict get $MOBdata($mob_id) Gx])]
			set yy [expr int([dict get $MOBdata($mob_id) Gy])]
			set sz [MonsterSizeValue [CreatureDisplayedSize $mob_id]]
			DEBUG 1 "- Found at ($xx,$yy), size=$sz:"
			for {set xi 0} {$xi < $sz} {incr xi} {
				for {set yi 0} {$yi < $sz} {incr yi} {
					lappend WhereIsMOB([expr $xx+$xi],[expr $yy+$yi]) $mob_id
					DEBUG 1 "-- ($xx+$xi, $yy+$yi) = $WhereIsMOB([expr $xx+$xi],[expr $yy+$yi])"
				}
			}
		}
	}

	set x [dict get $MOBdata($id) Gx]
	set y [dict get $MOBdata($id) Gy]
	if {[set fullinfo [FullCreatureAreaInfo $id]] eq {}} {
		DEBUG 0 "can't get full area info on $id to render them on the map!"
		lassign {1 1 2 {} {}} mob_size mob_area mob_reach mob_matrix custom_reach
	} else {
		lassign $fullinfo mob_size mob_area mob_reach mob_matrix custom_reach
	}

	# If somehow we have a misaligned creature that's at least "small",
	# snap to even grid boundary
# XXX no longer needed or wanted now that we have CreatureGridSnap
#	if {$mob_size >= 1 && ($x != int($x) || $y != int($y))} {
#		set x [expr int($x)]
#		set y [expr int($y)]
#		dict set MOBdata($id) Gx $x
#		dict set MOBdata($id) Gy $y
#	}

	if {[animation_obj_exists $id]} {
		animation_destroy_instance $w * $id
	} 
	$w delete "M#$id"

	if {[dict get $MOBdata($id) Hidden] && !$is_GM} {
		return
	}

	# spell area of effect
	if {[set AoE [dict get $MOBdata($id) AoE]] ne {}} {
		set aoe_type radius
		::gmautil::dassign $AoE Radius aoe_radius Color aoe_color
		set aoe_radius [expr $aoe_radius * $iscale]; #convert to canvas units for rendering
		switch $aoe_type {
			radius {
				set GX0 [dict get $MOBdata($id) Gx]
				set GY0 [dict get $MOBdata($id) Gy]
				set GXX [expr $GX0 * $iscale]
				set GYY [expr $GY0 * $iscale]
				#
				# In order to get the spell to be "centered on you" but adapted reasonably to
				# creatures of whatever size, we will take the optional rule of having the spell
				# emanate from the perimeter of the creature. In practical terms, we will draw
				# a zone around each grid intersection around the occupied area of the creature.
				# this makes some overlapping draw calls, but gets the job done.
				#
				# Our (GX,GY) reference point is already at the upper left of the occupied space.
				set sz [MonsterSizeValue [CreatureDisplayedSize $id]]
				for {set AoEx 0} {$AoEx <= $sz} {incr AoEx} {
					_DrawAoeZone $w $id [expr $GX0+$AoEx] $GY0 [expr $GXX+$AoEx] $GYY $aoe_radius $aoe_color radius [list M#$id MA#$id allMOB MAzone]			
					if {$sz >= 1} {
						_DrawAoeZone $w $id [expr $GX0+$AoEx] [expr $GY0+$sz] [expr $GXX+$AoEx] [expr $GYY+$sz] $aoe_radius $aoe_color radius [list M#$id MA#$id allMOB MAzone]			
					}
				}
				for {set AoEy 1} {$AoEy < $sz} {incr AoEy} {
					_DrawAoeZone $w $id $GX0 [expr $GY0+$AoEy] $GXX [expr $GYY+$AoEy] $aoe_radius $aoe_color radius [list M#$id MA#$id allMOB MAzone]			
					_DrawAoeZone $w $id [expr $GX0+$sz] [expr $GY0+$AoEy] [expr $GXX+$sz] [expr $GYY+$AoEy] $aoe_radius $aoe_color radius [list M#$id MA#$id allMOB MAzone]			
				}
			}
		}
	}

	# area of threat 
	global MOB_COMBATMODE
	if {[dict get $MOBdata($id) CreatureType] == 2} {
		set ctype player
	} else {
		set ctype monster
	}
	if {$MOB_COMBATMODE && ![dict get $MOBdata($id) Killed]} {
		if {[dict get $MOBdata($id) Dim]} {
			$w create arc [expr ($x-$mob_area)*$iscale] [expr ($y-$mob_area)*$iscale] \
				[expr ($x+$mob_size+$mob_area)*$iscale] [expr ($y+$mob_area+$mob_size)*$iscale] \
				-outline [dict get $MOBdata($id) Color] \
				-width $ThreatLineWidth \
				-tags "M#$id MC#$id MT=$ctype allMOB MCzone" \
				-dash . -start 0 -extent 359.9 -style arc
			if {[dict get $MOBdata($id) Reach] > 0} {
				$w create arc [expr ($x-$mob_reach)*$iscale] [expr ($y-$mob_reach)*$iscale] \
					[expr ($x+$mob_size+$mob_reach)*$iscale] [expr ($y+$mob_reach+$mob_size)*$iscale] \
					-outline [dict get $MOBdata($id) Color] \
					-width $ThreatLineWidth \
					-tags "M#$id MR#$id MT=$ctype allMOB MCzone" \
					-dash . -start 0 -extent 359.9 -style arc
			}
		} else {
			set Xstart [expr ($x-$mob_reach)]
			#set yy [expr int($y-$mob_reach)]
			set yy [expr $y-$mob_reach]
			switch [dict get $MOBdata($id) Reach] {
				1 {
					# reach weapons
					set hashbit 1
				}
				2 {
					# extended melee zone
					set hashbit 3
				}
				default {
					# normal melee zone
					set hashbit 2
				}
			}
			set color [dict get $MOBdata($id) Color]
			foreach row $mob_matrix {
#				set xx [expr int($Xstart)]
				set xx $Xstart
				foreach col $row {
					if {$col & $hashbit} {
						foreach {xa ya xb yb} {
							0.5 0 0 0.5
							1   0 0 1  
							1 0.5 0.5 1
							0.25 0 0 0.25 
							0.75 0 0 0.75
							1 0.25 0.25 1
							1 0.75 0.75 1
						} {
							$w create line [expr ($xx + $xa) * $iscale] \
										   [expr ($yy + $ya) * $iscale] \
										   [expr ($xx + $xb) * $iscale] \
										   [expr ($yy + $yb) * $iscale] \
										   -fill $color \
										   -width $ThreatLineHatchWidth \
										   -tags "M#$id MF#$id MH#$id MT=$ctype allMOB"
						}
					}
					set xx [expr $xx + 1]
				}
				set yy [expr $yy + 1]
			}

			$w create arc [expr ($x-$mob_area)*$iscale] [expr ($y-$mob_area)*$iscale] \
				[expr ($x+$mob_size+$mob_area)*$iscale] [expr ($y+$mob_area+$mob_size)*$iscale] \
				-outline red -width $ThreatLineWidth \
				-tags "MF#$id M#$id MC#$id MT=$ctype allMOB MCzone" \
				-dash . -start 0 -extent 359.9 -style arc
			if {[dict get $MOBdata($id) Reach] > 0} {
				$w create arc [expr ($x-$mob_reach)*$iscale] [expr ($y-$mob_reach)*$iscale] \
					[expr ($x+$mob_size+$mob_reach)*$iscale] [expr ($y+$mob_reach+$mob_size)*$iscale] \
					-outline $ReachLineColor -width $ThreatLineWidth \
					-tags "M#$id MF#$id MR#$id MT=$ctype allMOB MCzone" \
					-dash . -start 0 -extent 359.9 -style arc
			}
		}
	}
		
	# nametag
	global MOB_IMAGE
	set mob_name [set mob_img_name [dict get $MOBdata($id) Name]]
	if {[info exists MOB_IMAGE($mob_name)]} {
		set mob_img_name $MOB_IMAGE($mob_name)
	} elseif {[regexp {^(.*) #\d+$} $mob_name mob_full_name mob_creature_name mob_sequence]} {
		set mob_img_name $mob_creature_name
	}

        # TODO this may be a little premature, but that's ok as long as the computed
	# health conditions don't require shifting to transparency. We'll assume for
        # now that only explicitly set ones will do that.
        set is_transparent [CreatureStatusTransparent $id {}]

	#
	# prefix to use based on skin selected and possibly if alive
	#
	set image_candidates {}
	set skin_idx [dict get $MOBdata($id) Skin]

	if {[dict get $MOBdata($id) Killed]} {
		set fillcolor black
		set textcolor white
		set i_pfx "%"
		if {$skin_idx == 0} {
			lappend image_candidates "%$mob_img_name"
		}
	} else {
		set fillcolor white
		set textcolor black
		set i_pfx ""
	}

	if {$skin_idx < 4} {
		lappend image_candidates "$i_pfx[string range #=-+ $skin_idx $skin_idx]$mob_img_name"
	}
	lappend image_candidates "$i_pfx^$skin_idx^$mob_img_name"

	if {$is_transparent} {
		set image_candidates [lmap v $image_candidates {string cat ! $v}]
		lappend image_candidates "!$mob_img_name"
	}

	global zoom 
	global TILE_SET TILE_ANIMATION
	#set tile_id [FindImage $image_pfx $zoom]
	
    #
    # Run through each possible name to see if we have that name 
    # cached already, before broadcasting a request for one.
    #
    set found_image false
    if {[dict exists $MOBdata($id) DispSize] \
     && [set disp_size [SkinSizeOnly [dict get $MOBdata($id) DispSize]]] ne {} \
     && [set real_size [dict get $MOBdata($id) Size]] ne $disp_size} {
	    set disp_zoom [creature_display_zoom $real_size $disp_size $zoom]
    } else {
	    set disp_zoom $zoom
    }

    DEBUG 3 "Looking up image at zoom $disp_zoom for each of: $image_candidates"
	foreach image_pfx $image_candidates {
		#
		# if we already know we have this image, just use it
		#
		if {[info exists TILE_SET([tile_id $image_pfx $disp_zoom])]
		||  [info exists TILE_ANIMATION([tile_id $image_pfx $disp_zoom],frames)]} {
            DEBUG 3 "- Found $image_pfx, using that"
            set found_image true
			break
		} else {
            DEBUG 3 "- No $image_pfx already loaded"
        }
    }

    if {! $found_image} {
        DEBUG 3 "No candidate tiles were found. Querying server and checking cache..."
        foreach ip $image_candidates {
            DEBUG 3 "- Trying $ip"
            FindImage $ip $disp_zoom
            if {[info exists TILE_SET([tile_id $ip $disp_zoom])]
	    ||  [info exists TILE_ANIMATION([tile_id $ip $disp_zoom],frames)]} {
                DEBUG 3 "-- Found $ip, using that."
                set image_pfx $ip
                break
            }
        }
     }


	#
	# if we found a copy of the image, it will now appear in TILE_SET.
	#
        set mob_token_tile_id [tile_id $image_pfx $disp_zoom]
	if {[info exists TILE_SET($mob_token_tile_id)]
	|| [info exists TILE_ANIMATION($mob_token_tile_id,frames)]} {
		DEBUG 3 "$image_pfx:$disp_zoom"
		if {!$is_transparent} {
			$w create oval [expr $x*$iscale] [expr $y*$iscale] [expr ($x+$mob_size)*$iscale] [expr ($y+$mob_size)*$iscale] -fill $fillcolor -tags "mob MF#$id M#$id MN#$id allMOB MB#$id"
		}

		if {[info exists TILE_SET($mob_token_tile_id)]} {
			$w create image [expr $x*$iscale] [expr $y*$iscale] -anchor nw -image $TILE_SET([tile_id $image_pfx $disp_zoom]) -tags "mob M#$id MN#$id allMOB"
		} else {
			animation_create $w [expr $x*$iscale] [expr $y*$iscale] $mob_token_tile_id $id -start
		}

		# set mob_name to just what the players should see, not the full name known to the system.
		set mob_name [::gmaclock::nameplate_text $mob_name]
		set nametag_w "$w.nt_$id"
		if {[winfo exists $nametag_w]} {
			$nametag_w configure -font [FontBySize [CreatureDisplayedSize $id]] -text $mob_name \
				-background [::tk::Darken [dict get $MOBdata($id) Color] 40]
		} else {
			label $nametag_w -background [::tk::Darken [dict get $MOBdata($id) Color] 40] \
				-foreground white -font [FontBySize [CreatureDisplayedSize $id]] -text $mob_name 
		}
		# is anyone above me?
		set nametag_anchor sw
		set look_y [expr $y - 1]
		for {set look_x $x} {$look_x < [expr $x+$mob_size]} {set look_x [expr $look_x + 1]} {
			if {[info exists WhereIsMOB($look_x,$look_y)]} {
				set nametag_anchor nw
				break
			}
		}
		# notify people below me too
		set look_y [expr $y+$mob_size]
		for {set look_x $x} {$look_x < [expr $x+$mob_size]} {set look_x [expr $look_x + 1]} {
			if {[info exists WhereIsMOB($look_x,$look_y)]} {
				lappend lower_neighbors {*}$WhereIsMOB($look_x,$look_y)
			}
		}

		if {[dict get $MOBdata($id) Killed]} {
			$w create text [expr $x*$iscale] [expr $y*$iscale] -text $mob_name -anchor nw -font [FontBySize [CreatureDisplayedSize $id]] -fill $textcolor -tags "M#$id MF#$id MT#$id allMOB"
		} else {
			$w create window [expr $x*$iscale] [expr $y*$iscale] -anchor $nametag_anchor -window $nametag_w -tags "M#$id MF#$id MT#$id allMOB"
		}
	} else {
		set mob_name [::gmaclock::nameplate_text $mob_name]
		DEBUG 3 "No $image_pfx:$disp_zoom found in TILE_SET"
		$w create oval [expr $x*$iscale] [expr $y*$iscale] [expr ($x+$mob_size)*$iscale] [expr ($y+$mob_size)*$iscale] -fill $fillcolor -tags "mob MF#$id M#$id MN#$id MB#id allMOB"
		$w create text [expr ($x+(.5*$mob_size))*$iscale] [expr ($y+(.5*$mob_size))*$iscale] -fill $textcolor \
			-font [FontBySize [CreatureDisplayedSize $id]] -text $mob_name -tags "M#$id MF#$id MN#$id MT#$id allMOB"
	}
	if {[dict get $MOBdata($id) Killed]} {
		$w create line [expr $x*$iscale] [expr $y*$iscale] [expr ($x+$mob_size)*$iscale] [expr ($y+$mob_size)*$iscale] \
			-fill [dict get $MOBdata($id) Color] -width 7 -tags "mob MF#$id M#$id MN#$id allMOB"
		$w create line [expr $x*$iscale] [expr ($y+$mob_size)*$iscale] [expr ($x+$mob_size)*$iscale] [expr $y*$iscale] \
			-fill [dict get $MOBdata($id) Color] -width 7 -tags "mob MF#$id M#$id MN#$id allMOB"
	}
		
	#
	# Bind mouseover events for the token
	#
	#$w bind M#$id <Enter> "DisplayHealthStats $id"
	#$w bind M#$id <Leave> "DisplayHealthStats {}"
	#
	# get general status for healthbar and condition markers
	#	show_healthbar		true if it should be displayed not
	#	health				array of healthbar info or {} if unknown
	#	maxhp lethal nonlethal grace flatp stablep condition server_blur_hp (set from health)
	#   its_dead_jim		true if creature fully dead
	#	condition			name of health-computed condition: {}, dead, dying, disabled, unconscious, staggered, flat
	#	MOB(_CONDITION:id)	condition
	#	x,y					grid coords
	#   mob_size			grids across/down
	#   iscale				multiplier to turn grids to pixels
	#	Xhw					healthbar width (token width)
	#	Xh0					healthbar left edge
	#   Xhl   				healthbar right edge
	#   Yh0					healthbar bottom edge
	#	Yh1					healthbar top edge
	#	Thl                 healthbar tags: M#id MHB#id allMOB
	#   TxX					healthbar 1/2 point across
	#   TxY					healthbar 1/2 point down
	#	bw					healthbar frame width
	#	bc					healthbar frame color
	#
	set its_dead_jim [dict get $MOBdata($id) Killed]
	set show_healthbar false 
	set health {}
	set maxhp 0
	set lethal 0
	set nonlethal 0
	set grace 0
	set flatp false
	set stablep false
	set server_blur_hp 0
	set condition {}

	if {[set hd [dict get $MOBdata($id) Health]] ne {}} {
		::gmautil::dassigndef $hd \
			Condition condition \
			MaxHP maxhp \
			TmpHP {tmp_hp 0} \
			TmpDamage {tmp_damage 0} \
			LethalDamage lethal \
			NonLethalDamage nonlethal \
			Con grace \
			IsFlatFooted flatp \
			IsStable stablep \
			HPBlur server_blur_hp
		set show_healthbar true
		global blur_all blur_pct

		# I removed the calculations here to adjust the hit points based on the game rules
		# for things like nonlethal damage because we're supposed to just be reporting the stats
		# and they SHOULD be correct already before we get them. This way we aren't potentially
		# hiding a bug upstream.
		# 
		# We will just show the MaxHP, TmpHP, TmpDamage, LethalDamage, and NonLethalDamage as given to us.
		#  ___________________________________________
		# |_______G______|____B_____|___Y___|___R_____|
		# |<-M+T-Td-N-L->|<- T-Td ->|<- N ->|<-- L  ->|
		# |<-------------M+T------------------------->|
		# |<----hp_remaining--------------->|

		set effective_hp [expr $maxhp + $tmp_hp - $tmp_damage]
		
		set true_hp_remaining [expr $effective_hp - $lethal]
		if {($blur_all || [dict get $MOBdata($id) CreatureType] != 2) && $server_blur_hp == 0} {
			set hp_remaining [blur_hp $effective_hp $lethal]
		} else {
			set hp_remaining $true_hp_remaining
		}


		if {$its_dead_jim} {
			set condition {}
		} elseif {$condition eq {}} {
			# calculate condition automatically, otherwise it's forced
			if {$effective_hp <= 0 || ($true_hp_remaining <= -$grace)} { 
				set condition dead 
				# We're making the change locally here instead of broadcasting it out
				# because all the other map clients will be acting on the same logic
				# themselves and we don't need a storm of "this creature died" messages.
				dict set MOBdata($id) Killed true
				set its_dead_jim true
				# Oh, no! We're already past the point where this would have been
				# useful to know. Start over and re-render them as a corpse this time.
				RenderSomeone $w $id
				return
			} elseif {$true_hp_remaining < 0} {
				set condition dying
			} elseif {$nonlethal > $true_hp_remaining} {
				set condition unconscious
			} elseif {$true_hp_remaining == 0} {
				set condition disabled
			} elseif {$nonlethal == $true_hp_remaining} {
				set condition staggered
			} elseif {$flatp} {
				set condition flat-footed
			}
		}
##		set MOB(_CONDITION:$id) $condition
		# x,y 		grid coords
		# mob_size	grids across/down
		# iscale	multiplier to turn grids to pixels
		# is anyone below me?
		set pull_up_bar false
		set look_y [expr $y + $mob_size]
		for {set look_x $x} {$look_x < [expr $x+$mob_size]} {set look_x [expr $look_x + 1]} {
			if {[info exists WhereIsMOB($look_x,$look_y)]} {
				set pull_up_bar true
				break
			}
		}
		set Xhw [expr $mob_size * $iscale]
		set Xh0 [expr $x * $iscale]
		set Xhl [expr ($x + $mob_size) * $iscale]
		set Yh0 [expr ($y + $mob_size) * $iscale]
		if {$pull_up_bar} {
			set Yh1 [expr ($y + $mob_size) * $iscale - $HealthBarWidth]
			set TxY [expr $Yh0 - 0.5*$HealthBarWidth]
		} else {
			set Yh1 [expr ($y + $mob_size) * $iscale + $HealthBarWidth]
			set TxY [expr $Yh0 + 0.5*$HealthBarWidth]
		}
		set Thl [list "M#$id" "MHB#$id" "allMOB"]
		set TxX [expr $Xh0 + 0.5*$Xhw]
		set full_stats [expr $ShowHealthStats && [dict get $MOBdata($id) CreatureType] == 2]

		set bw $HealthBarFrameWidth
		set bc black
	}

	tooltip::tooltip $w -items MN#$id [CreateHealthStatsToolTip $id $condition]
	CreatureStatusMarker $w $id [expr $x*$iscale] [expr $y*$iscale] [expr $mob_size*$iscale] $condition
	if {$MOB_COMBATMODE} {
		if {$show_healthbar} {
			if {$its_dead_jim} {
				$w create rectangle $Xh0 $Yh0 $Xhl $Yh1 -width $bw -outline $bc -fill black -tags $Thl
				if {$full_stats} {
					$w create text $TxX $TxY -anchor center -fill white -text DEAD -tags $Thl
				}
			} elseif {$condition eq {dying}} {
				# not at all feeling well:
				#
				#   |<----------------Xhw------------------->|
				#   |________________________________________|
				#   |#######################|                |
				#  Xh0   bleed-out amount   |               Xhl
				#                          Xhb
				#
				# -grace < maxhp - lethal < 0

				if {$grace == 0} {
					DEBUG 1 "$id is dying but has con grace zone of $grace"
					set Xhb $Xh0
				} else {
					set Xhb [expr max($Xh0, $Xhl - ($Xhw * (double($lethal - $effective_hp)/$grace)))]
				}
				set bw $HealthBarConditionFrameWidth
				if {$stablep} {
					set bc sienna
				} else {
					set bc red
				}
				$w create rectangle $Xh0 $Yh0 $Xhb $Yh1 -width $bw -outline $bc -fill red -tags $Thl
				$w create rectangle $Xhb $Yh0 $Xhl $Yh1 -width $bw -outline $bc -fill black -tags $Thl
				if {$full_stats} {
					$w create text $TxX $TxY -anchor center -fill white -text [format "%d/%d" [expr $effective_hp-$lethal] $effective_hp] -tags $Thl
				}
			} else {
				# not quite dead yet:
				#
				# old:
				#   |<----------------Xhw------------------->|
				#   |________________________________________|
				#   |////////////|::::::::::|################|
				#  Xh0   health  |   non-l  |     lethal    Xhl
				#               Xhh        Xhn
				#
				# new:
				#   |<----------------Xhw----------------------------->|
				#   |__________________________________________________|
				#   |////////////|\\\\\\\\\|::::::::::|################|
				#  Xh0   health  |   tmp   |   non-l  |     lethal    Xhl
				#               Xhh       Xht        Xhn
				#
				# XXX if maxhp=0
				# XXX set width and outline based on condition

				if {$effective_hp <= 0} {
					DEBUG 0 "$id has effective max HP of $effective_hp; how did we even get this far without noticing that? BUG!"
					return
				}

				switch -exact $condition {
					flat - flat-footed	{ set bw $HealthBarConditionFrameWidth; set bc blue }
					staggered		{ set bw $HealthBarConditionFrameWidth; set bc yellow }
					unconscious		{ set bw $HealthBarConditionFrameWidth; set bc purple }
					stable			{ set bw $HealthBarConditionFrameWidth; set bc sienna }
					disabled		{ set bw $HealthBarConditionFrameWidth; set bc red }
				}

				# using maxhp-hp_remaining instead of lethal to account for blurring
				# we don't blur nonlethal for now but it's showing relative to the blurred lethal damage
				set Xhn [expr (max($Xh0, $Xhl - ($Xhw * (double($effective_hp-$hp_remaining)/$effective_hp))))]
				set Xht [expr (max($Xh0, $Xhn - ($Xhw * (double($nonlethal)/$effective_hp))))]
				set Xhh [expr (max($Xh0, $Xht - ($Xhw * (double($tmp_hp-$tmp_damage)/$effective_hp))))]
				#set Xhn [expr max($Xh0, $Xhl - ($Xhw * (double($maxhp-$hp_remaining)/$maxhp)))]
				#set Xhh [expr max($Xh0, $Xhn - ($Xhw * (double($nonlethal)/$maxhp)))]
				#DEBUG 3 "-- X: $Xhw $Xh0 $Xhl $Xhn $Xhh; Y: $Yh0 $Yh1; $Thl"
				$w create rectangle $Xh0 $Yh0 $Xhh $Yh1 -width $bw -outline $bc -fill green -tags $Thl
				if {$tmp_hp - $tmp_damage > 0} {
					$w create rectangle $Xhh $Yh0 $Xht $Yh1 -width $bw -outline $bc -fill blue -tags $Thl
				}
				if {$nonlethal > 0} {
					$w create rectangle $Xht $Yh0 $Xhn $Yh1 -width $bw -outline $bc -fill yellow -tags $Thl
				}
				if {$lethal > 0} {
					$w create rectangle $Xhn $Yh0 $Xhl $Yh1 -width $bw -outline $bc -fill red -tags $Thl
				}
				if {$full_stats} {
					if {$server_blur_hp ne {}} {
						set pfx {~}
					} else {
						set pfx {}
					}
					if {$nonlethal > 0} {
						$w create text $TxX $TxY -anchor center -fill white -text [format "%s%d(%d)" $pfx $hp_remaining $nonlethal] -tags $Thl
					} else {
						$w create text $TxX $TxY -anchor center -fill white -text [format "%s%d/%d" $pfx $hp_remaining $maxhp] -tags $Thl
					}
				}
			}
		}
	}

	#
	# Elevation tag
	# 

	if {[set elev [dict get $MOBdata($id) Elev]] != 0} {
		set fillcolor black
		set textcolor white
		switch [::gmaproto::from_enum MoveMode [dict get $MOBdata($id) MoveMode]] {
			fly { 
				set textcolor black
				set fillcolor deepskyblue
			}
			climb { 
				set fillcolor forestgreen 
			}
			swim { 
				set fillcolor teal
			}
			burrow {
				set fillcolor sienna
			}
		}
		if {![winfo exists $w.z$id]} {
			catch {label $w.z$id -text {} -foreground $textcolor -background $fillcolor}
		}
		$w create window [expr ($x+($mob_size))*$iscale] [expr ($y)*$iscale] -tags "M#$id MELEV#$id allMOB" -anchor ne -window $w.z$id 
		$w.z$id configure -foreground $textcolor -background $fillcolor -text $elev -font [FontBySize [CreatureDisplayedSize $id]]
	}

	#
	# Status tag
	#
	if {[set noteText [dict get $MOBdata($id) Note]] ne {}} {
		if {![winfo exists $w.ms$id]} {
			catch {label $w.ms$id -text {} -foreground white -background blue}
		}
		$w create window [expr ($x+($mob_size))*$iscale] [expr ($y+$mob_size)*$iscale] \
			-tags "M#$id MT#$id allMOB" -anchor se -window $w.ms$id 
		$w.ms$id configure -text $noteText -font [FontBySize [CreatureDisplayedSize $id]]
	}

	#
	# selection
	#
	global MOB_SELECTED
	if {[info exists MOB_SELECTED($id)] && $MOB_SELECTED($id)} {
		$w create rectangle [expr $x*$iscale] [expr $y*$iscale] \
			[expr ($x+$mob_size)*$iscale] [expr ($y+$mob_size)*$iscale] \
			-outline blue -width $SelectLineWidth -tags "M#$id allMOB"
	}
	#
	# Threat zones
	# Find all of the instances of one being threatening another, and draw
	# arrows between them, indicating player-vs-monster sides as not threatening
	# each other.  We'll draw arrows tangent to the nametag ovals between
	# threatener and threatenee.
	#
	if {$MOB_COMBATMODE} {
		global PI
		$w delete "MArrows"
		DEBUG 4 "Deleting arrows, redrawing them"

		foreach threatening_mob_id [array names MOBdata] {
			DEBUG 1 "Checking who $threatening_mob_id is threatening"
			if {[dict get $MOBdata($threatening_mob_id) Killed]} continue
			if {[dict get $MOBdata($threatening_mob_id) Hidden] && !$is_GM} continue
			if {[set fullinfo [FullCreatureAreaInfo $threatening_mob_id]] eq {}} {
				DEBUG 0 "can't get full area info for threatening creature $threatening_mob_id"
				continue
			}
			lassign $fullinfo sz ar re mat _
#			lassign [ReachMatrix [CreatureDisplayedSize $threatening_mob_id]] ar re mat
			lassign [MOBCenterPoint $threatening_mob_id] xc yc rc
#			set sz [MonsterSizeValue [CreatureDisplayedSize $threatening_mob_id]]
			DEBUG 1 "-- area $ar reach $re ($xc,$yc) r=$rc"
			set Xstart [expr ([dict get $MOBdata($threatening_mob_id) Gx] - $re)]
			set yy [expr int([dict get $MOBdata($threatening_mob_id) Gy] - $re)]
			array unset target
			if {[dict get $MOBdata($threatening_mob_id) Reach] > 0} {
				set matbit 1
			} else {
				set matbit 2
			}
			foreach row $mat {
				set xx [expr int($Xstart)]
				foreach col $row {
					DEBUG 1 "--- @($xx,$yy) m=$col"
					if {$col & $matbit} {
						if {[info exists WhereIsMOB($xx,$yy)]} {
							DEBUG 1 "---- something is here: $WhereIsMOB($xx,$yy)"
							foreach target_id $WhereIsMOB($xx,$yy) {
								if {$target_id ne $threatening_mob_id
								&& [dict get $MOBdata($target_id) CreatureType] != [dict get $MOBdata($threatening_mob_id) CreatureType]
								&& (![info exists target($target_id)] 
									|| $target($target_id) < $col)} {
										DEBUG 1 "----- target($target_id) <- $col"
										set target($target_id) $col
								}
							}
						}
					}
					incr xx
				}
				incr yy
			}
		

			# target(id) is now 1 if threatened by reach or 2 if by normal
			foreach target_id [array names target] {
				DEBUG 1 "$threatening_mob_id target $target_id"
				# yes, we have a threat.  Figure out the distance and angle
				# between their center points.
				#
				#set R [expr hypot($Txc-$xc, $Tyc-$yc)]
				lassign [MOBCenterPoint $target_id] Txc Tyc Trc
				set dx [expr $Txc-$xc]
				set dy [expr $Tyc-$yc]
				set theta [expr atan2(-$dy,-$dx)]
				DEBUG 1 "dx=$dx dy=$dy theta=$theta ($Txc,$Tyc) r=$Trc"
				if {$dx != 0 || $dy != 0} {
					# and they're not on top of each other, which would only serve
					# to annoy the atan2() function anyway.
					#
					# from that, we get the (x,y) coordinates of the endpoint 
					# of the arrow where it intersects the nametag circle
					# origin: on the threatener's circle
					#
					set AOx [expr $xc + ($rc * cos($theta + $PI))]
					set AOy [expr $yc - ($rc * sin($theta))]
					#
					# and the arrow on the destination end is just 180 degrees around
					# its circle from where the other arrow was.
					#
					set ADx [expr $Txc + ($Trc * cos($theta))]
					set ADy [expr $Tyc - ($Trc * sin($theta + $PI))]
					#
					# Draw it
					#

					if {$target($target_id) > 0} {
						$w create line $AOx $AOy $ADx $ADy -arrow last -fill red -width 5 -tags "MArrows M#$threatening_mob_id M#$target_id" -arrowshape [list 15 18  8]
					}
				}
			}
		}
	}
	if {!$norecurse && [llength $lower_neighbors] > 0} {
		foreach neighbor [lsort -unique $lower_neighbors] {
			RenderSomeone $w $neighbor true
		}
	}
}

# returns the MOB id associated with a map element or empty string
proc CanvasElementIdToMobId {w tag} {
	return [string range [lsearch -glob -inline [$w gettags $tag] M#*] 2 end]
}

# returns x1 y1 x2 y2 xc yc rx ry x1 y1 x2 y2  given a MOB id
#         \_________/ \_____________________/
#   threat zone box      name ellipse
#
proc CanvasMobCoordinates {w mob_id} {
	set zone_coords [$w coords "MC#$mob_id"];	# [x1 y1 x2 y2] around threat zone
	# R = (x2-x1)/2 + x1
	lassign [$w coords "MN#$mob_id"] x1 y1 x2 y2
	set Rx [expr ($x2 - $x1) / 2.0]
	set Ry [expr ($y2 - $y1) / 2.0]
	return [concat $zone_coords [list [expr $Rx + $x1] [expr $Ry + $y1] $Rx $Ry $x1 $y1 $x2 $y2]]
}

#
# Selection of on-screen objects
#
proc AddToSelection {id} {
	global MOB_SELECTED canvas
	DEBUG 3 "Selecting $id"
	if {[info exists MOBdata($id)]} {
		set MOB_SELECTED($id) true
		RenderSomeone $canvas $id
	} else {
		DEBUG 3 "No mob key $id found"
	}
	SetSelectionContextMenu
}

proc SetSelectionContextMenu {} {
	if {[llength [GetSelectionList]] == 0} {
		.contextMenu entryconfigure Deselect* -state disabled
	} else {
		.contextMenu entryconfigure Deselect* -state normal
	}
}

proc ToggleSelection {id} {
	global MOB_SELECTED canvas MOBdata
	DEBUG 3 "Selecting $id"
	if {[info exists MOBdata($id)]} {
		if {[info exists MOB_SELECTED($id)]} {
			set MOB_SELECTED($id) [expr !$MOB_SELECTED($id)]
		} else {
			set MOB_SELECTED($id) true
		}
		RenderSomeone $canvas $id
	} else {
		DEBUG 3 "No mob key $id found"
	}
	SetSelectionContextMenu
}

proc RemoveFromSelection {id} {
	global MOB_SELECTED canvas
	if {[info exists MOB_SELECTED($id)]} {
		set MOB_SELECTED($id) false
		RenderSomeone $canvas $id
	}
	SetSelectionContextMenu
}

proc ClearSelection {} {
	global MOB_SELECTED canvas
	foreach id [array names MOB_SELECTED] {
		catch {
			set MOB_SELECTED($id) false
			RenderSomeone $canvas $id
		}
	}
	SetSelectionContextMenu
	array unset MOB_SELECTED
}

proc GetSelectionList {} {
	global MOB_SELECTED MOBdata
	set result {}
	foreach id [array names MOB_SELECTED] {
		if {![info exists MOBdata($id)] && $MOB_SELECTED($id)} {
			DEBUG 1 "Removed nonexistent id $id from selection list"
			set MOB_SELECTED($id) false
		}
		if {$MOB_SELECTED($id)} {
			lappend result $id
		}
	}
	return $result
}


#
# The click-and-drag logic works in screen x,y coordinates.
# we need to convert that to an object.
#

proc RefreshMOBs {} {
	global MOBdata canvas

	DEBUG 3 "RefreshMOBs start ([array names MOBdata])"
	foreach id [lsort -command cmp_mob_living [array names MOBdata]] {
		DEBUG 3 "Rendering $id"
		RenderSomeone $canvas $id
	}
	DEBUG 3 "RefreshMOBs end"
}

proc ScreenXYToMOBID {w x y} {
	global MOBdata
	lassign [ScreenXYToGridXY $x $y -exact] gx gy

	DEBUG 3 "Looking for object at $x,$y (grid $gx,$gy)..."
	set mob_list {}
	foreach id [array names MOBdata] {
		set msz [expr max(1, [MonsterSizeValue [CreatureDisplayedSize $id]])]
		set mx0 [expr int([dict get $MOBdata($id) Gx])]
		set mx1 [expr $mx0 + $msz]
		set my0 [expr int([dict get $MOBdata($id) Gy])]
		set my1 [expr $my0 + $msz]
		if {$mx0 <= $gx && $gx < $mx1 && $my0 <= $gy && $gy < $my1} {
			DEBUG 3 "...found $id"
			lappend mob_list $id
		}
		DEBUG 3 "... $id is at ($gx,$gy)"
	}
	DEBUG 3 "found $mob_list"
	return $mob_list
}


proc SnapCoordAlways {x} {
	global OBJ_SNAP
	set old_snap $OBJ_SNAP
	set OBJ_SNAP 1
	set r [SnapCoord $x]
	set OBJ_SNAP $old_snap
	return $r
}

proc SnapCoord {x} {
	global OBJ_SNAP rscale
	if {$OBJ_SNAP} {
		return [expr int(($x+(($rscale/$OBJ_SNAP)/2.0))/($rscale/$OBJ_SNAP))*($rscale/$OBJ_SNAP)]
	} else {
		return $x
	}
}

# ScreenXYToGridXY x y ?-exact?
#	unless -exact given, use MOB_MOVING's size to allow fractional measures
proc ScreenXYToGridXY {x y args} {
	# adjust for scrolled view region (x and y are screen coordinates,
	# not virtual canvas coordinates)
	#set xview [lindex [.xs get] 0]
	#set yview [lindex [.ys get] 0]
	#return [list [expr int(($x + ($xview*$cansw))/50)] \
		#[expr int(($y + ($yview*$cansh))/50)]]
	global canvas iscale MOB_MOVING MOBdata
	global CreatureGridSnap

	if {$args ne {-exact} && $MOB_MOVING ne {}} {
		DEBUG 3 "ScreenXYToGridXY $x $y $args for MOB $MOB_MOVING"
		if {$CreatureGridSnap ne {nil}} {
			set mob_size $CreatureGridSnap
		} else {
			set mob_size [MonsterSizeValue [CreatureDisplayedSize $MOB_MOVING]]
		}
		DEBUG 3 "--size $mob_size"
		if {$mob_size < 1} {
			if {$mob_size == 0} {
				set mob_size .5 
			}
			DEBUG 3 "-- calc as [list [expr int([$canvas canvasx $x]/($iscale*$mob_size))*$mob_size] [expr int([$canvas canvasy $y]/($iscale*$mob_size))*$mob_size]]"
			return [list [expr int([$canvas canvasx $x]/($iscale*$mob_size))*$mob_size] [expr int([$canvas canvasy $y]/($iscale*$mob_size))*$mob_size]]
		}
	}

	return [list [expr int(([$canvas canvasx $x])/$iscale)] \
		[expr int(([$canvas canvasy $y])/$iscale)]]
	global CreatureGridSnap
}

proc CanvasToGrid {x} {
	global iscale
	return [expr int($x/$iscale)]
}

proc GridToCanvas {x} {
	global iscale
	return [expr $x*$iscale]
}

set OBJ_MOVING {}
set OBJ_MOVING_SELECTED {}
proc MoveObjById {w id} {
	global OBJdata OBJ_MOVING OBJ_MOVING_SELECTED ClockDisplay OBJtype
	if {[info exists OBJdata($id)]} {
		if {$OBJtype($id) eq {aoe} || $OBJtype($id) eq {saoe}} {
			say "Moving spell area of effect is not yet implemented."
			set OBJ_MOVING {}
			set OBJ_MOVING_SELECTED {}
		} else {
			set OBJ_MOVING [list $id [$w coords obj$id]]
			set OBJ_MOVING_SELECTED {}
			set ClockDisplay $OBJ_MOVING
		}
	}
}

proc MoveObjDrag {w x y} {
	global OBJdata OBJ_MOVING
	if {$OBJ_MOVING ne {}} {
		lassign $OBJ_MOVING id old_coords
		set cx [SnapCoord [$w canvasx $x]]
		set cy [SnapCoord [$w canvasy $y]]
		set dx [expr $cx - [dict get $OBJdata($id) X]]
		set dy [expr $cy - [dict get $OBJdata($id) Y]]
		set new_coords {}
		foreach {xx yy} $old_coords {
			lappend new_coords [expr $xx + $dx] [expr $yy + $dy]
		}
		if {[animation_obj_exists $id]} {
			animation_move_instance $w * $id $new_coords
		} 
		$w coords obj$id $new_coords
		DEBUG 3 "MoveObjDrag $w $x $y for object $id: dx=$dx, dy=$dy; $old_coords -> $new_coords"
	}
}

proc MoveObjEndDrag {w} {
	global OBJdata OBJ_MOVING ClockDisplay MO_disp
	set ClockDisplay $MO_disp
	if {$OBJ_MOVING ne {}} {
		lassign $OBJ_MOVING id
		set obj_coords [$w coords obj$id]
		dict set OBJdata($id) X [lindex $obj_coords 0]
		dict set OBJdata($id) Y [lindex $obj_coords 1]
		dict set OBJdata($id) Points {}
		foreach {x y} [lrange $obj_coords 2 end] {
			dict lappend OBJdata($id) Points [dict create X $x Y $y]
		}
		SendObjChanges $id {X Y Points}
		set OBJ_MOVING {}
	}
}


menu .movemobmenu -tearoff 0
set MOB_DISAMBIG {}
set MOB_MOVING {}
proc MOB_StartDrag {w x y} {
	global MOB_MOVING MOB_DISAMBIG MOBdata DistanceLabelText MOB_StartGxGy MOB_TrackXY
	set MOB_MOVING [ScreenXYToMOBID $w $x $y]
	if {[llength $MOB_MOVING] > 1} {
		if {$MOB_DISAMBIG ne {}} {
			set MOB_MOVING $MOB_DISAMBIG
			set MOB_DISAMBIG {}
		} else {
			.movemobmenu delete 0 end
			foreach mob_id $MOB_MOVING {
				.movemobmenu add command -command "set MOB_DISAMBIG $mob_id" -label "Move [::gmaclock::nameplate_text [dict get $MOBdata($mob_id) Name]]"
			}
			set MOB_MOVING {}
			set MOB_DISAMBIG {}
			set wx [expr [winfo rootx $w] + $x]
			set wy [expr [winfo rooty $w] + $y]
			DEBUG 3 "popup ($x,$y) -> ($wx,$wy)"
			tk_popup .movemobmenu $wx $wy
			return
		}
	}
	if {[llength $MOB_MOVING] == 1} {
		set DisatanceLabelText {}
		set cx [$w canvasx $x]
		set cy [$w canvasy $y]
		$w delete DL#marks
		$w create line $cx $cy $cx $cy -fill red -width 5 -tags [list DL#marks DL#line]
		$w create line $cx $cy $cx $cy -fill green -width 5 -tags [list DL#marks DL#track]
		$w create window $cx $cy -window $w.distanceLabel -tags [list DL#marks DL#label]
		set MOB_StartGxGy [list [dict get $MOBdata($MOB_MOVING) Gx] [dict get $MOBdata($MOB_MOVING) Gy]]
		set MOB_TrackXY [list $cx $cy $cx $cy]
		bind $w <B1-Motion> "MOB_Drag $w %x %y"
	} else {
		# no mobs being dragged? scroll the canvas instead
		$w scan mark $x $y
		bind $w <B1-Motion> "$w scan dragto %x %y 1; battleGridLabels"
	}
}

proc MOB_SelectEvent {w x y} {
	global MOB_DISAMBIG MOBdata MOB_SELECTED
	set target_MOB [ScreenXYToMOBID $w $x $y]
	if {[llength $target_MOB] > 1} {
		if {$MOB_DISAMBIG ne {}} {
			set target_MOB $MOB_DISAMBIG
			set MOB_DISAMBIG {}
			ToggleSelection $target_MOB
			return
		}
		.movemobmenu delete 0 end
		foreach mob_id $target_MOB {
			if {[info exists MOB_SELECTED($mob_id)] && $MOB_SELECTED($mob_id)} {
				set label "Deselect [::gmaclock::nameplate_text [dict get $MOBdata($mob_id) Name]]"
			} else {
				set label "Select [::gmaclock::nameplate_text [dict get $MOBdata($mob_id) Name]]"
			}
			.movemobmenu add command -command "ToggleSelection $mob_id" -label $label
		}
		set wx [expr [winfo rootx $w] + $x]
		set wy [expr [winfo rooty $w] + $y]
		DEBUG 3 "popup ($x,$y) -> ($wx,$wy)"
		tk_popup .movemobmenu $wx $wy
	} elseif {[llength $target_MOB] == 1} {
		ToggleSelection $target_MOB
		set MOB_DISAMBIG {}
	}
}

#proc Generic_StartDrag {w x y} {
	#global MOB_X MOB_Y
#
	#set MOB_X [$w canvasx $x]
	#set MOB_Y [$w canvasy $y]
	#DEBUG "StartDrag: ($x,$y) -> ($MOB_X,$MOB_Y)"
#}
#
#proc Generic_Drag {w x y} {
	#global MOB_X MOB_Y 
#
	#set x [$w canvasx $x]
	#set y [$w canvasy $y]
	#$w move current [expr $x-$MOB_X] [expr $y-$MOB_Y]
	#set MOB_X $x
	#set MOB_Y $y
	#DEBUG "Drag: ($x,$y) -> ($MOB_X,$MOB_Y)"
#}

#
# as you drag someone, figure the delta (x,y) in grid squares from
# its starting position and draw a line with the movement rate
#

#
# given a mob and (x,y) coordinates, return
# the (delta x,delta y) for that MOB from its current location to
# (x,y).  The units are grid squares.
#
proc MOBPositionDelta {grid_xy mob_id} {
	global MOBdata

	if {[dict get $MOBdata($mob_id) Gx] != [lindex $grid_xy 0]
	||  [dict get $MOBdata($mob_id) Gy] != [lindex $grid_xy 1]} {
		return [list [expr [lindex $grid_xy 0] - [dict get $MOBdata($mob_id) Gx]] [expr [lindex $grid_xy 1] - [dict get $MOBdata($mob_id) Gy]]]
	} else {
		return {0 0}
	}
}

#
# given two square coordinates, return the distance
# between them, as an integer number of squares
# using d20 standard rules
#
proc GridDistance {x1 y1 x2 y2} {
	return [expr round(sqrt(pow($x1-$x2,2) + pow($y1-$y2,2)))]
}
proc GridDeltaDistance {deltaxy} {
	return [expr round(sqrt(pow([lindex $deltaxy 0],2) + pow([lindex $deltaxy 1],2)))]
}

#
# Given a grid (Gx,Gy), return the screen coordinates of the grid's center point.
#
proc GridXYToCenterPoint {Gx Gy} {
	global iscale;			# pixels per grid square
	return [list [expr $Gx*$iscale + ($iscale/2.0)] [expr $Gy*$iscale + ($iscale/2.0)]]
}

#
# Given a grid location with (Gx,Gy) at Gz_ft elevation and a MOB id, calculate
# the 3D distance from the center of the first grid to the center of the creature's
# body and the distance to the center of the nearest grid square which contains the
# creature. The output is in grid units.
#

proc DistanceToTarget3D {Gx Gy Gz_ft MobID} {
	global iscale;			# pixels per grid square
	global MOBdata;			# collection of all possible targets

	set Cx [expr $Gx + 0.5]
	set Cy [expr $Gy + 0.5]

	lassign [MOBCenterPoint $MobID] Mx My Mr
	set MGx [expr $Mx/$iscale]
	set MGy [expr $My/$iscale]
	#set MGr [expr $Mr/$iscale]

	if {[set Mz_ft [dict get $MOBdata($MobID) Elev]] != $Gz_ft} {
		return [expr round(sqrt(pow($Cx-$MGx,2) + pow($Cy-$MGy,2) + pow(($Gz_ft/5.0)-($Mz_ft/5.0),2)))]
	}
	return [GridDistance $Cx $Cy $MGx $MGy]
}


proc DebugMarker {title cmd dcmd} {
	create_dialog .dm
	wm title .dm $title
	grid [text .dm.text -yscrollcommand {.dm.sb set}] [scrollbar .dm.sb -orient vertical -command {.dm.text yview}] -sticky news
	grid [button .dm.ok -text OK -command "$dcmd; destroy .dm"]
	grid columnconfigure .dm 0 -weight 1
	grid rowconfigure .dm 0 -weight 1
	eval $cmd
	update
	tkwait window .dm
}

proc NearestCreatureGridToPoint {Gx Gy Gz_ft MobID} {
	global iscale MOBdata
	set distance -1
	set nearX 0
	set nearY 0
	lassign [MOBCenterPoint $MobID] Mx My Mr
	set MGx0 [expr ($Mx-$Mr)/$iscale]
	set MGx1 [expr ($Mx+$Mr)/$iscale]
	set MGy0 [expr ($My-$Mr)/$iscale]
	set MGy1 [expr ($My+$Mr)/$iscale]
	set Cx [expr $Gx + 0.5]
	set Cy [expr $Gy + 0.5]
	set Mz_ft [dict get $MOBdata($MobID) Elev]

	for {set x $MGx0} {$x < $MGx1} {set x [expr $x + 1.0]} {
		for {set y $MGy0} {$y < $MGy1} {set y [expr $y + 1.0]} {
			set d [expr round(sqrt(pow($Cx-($x+.5),2) + pow($Cy-($y+.5),2) + pow(($Gz_ft/5.0)-($Mz_ft/5.0),2)))]
#			DebugMarker "Measured Distance" "
#				global canvas
#				.dm.text insert end \"distance ($Cx,$Cy,$Gz_ft)-($x+.5,$y+.5,$Mz_ft) $d\nnear ([expr int($x)],[expr int($y)]) [LetterLabel [expr int($x)]]$y\n\"
#				\$canvas create line [expr $Cx*$iscale] [expr $Cy*$iscale] [expr ($x+.5)*$iscale] [expr ($y+.5)*$iscale] -fill green -width 5 -tags DMDM
#			" "
#				global canvas
#				\$canvas delete DMDM
#			"
#
			if {$distance < 0 || $d < $distance} {
				set distance [expr int($d)]
				set nearX [expr int($x)]
				set nearY [expr int($y)]
			}
		}
	}
	if {$distance < 0} {
		return [list 0 0 0 {ERROR}]
	}
	return [list $distance $nearX $nearY "[LetterLabel $nearX]$nearY"]
}

proc PixelsToFeet {px} {
	global iscale
	return [expr $px / ($iscale / 5.0)]
}

proc FeetToPixels {ft} {
	global iscale
	return [expr $ft * ($iscale / 5.0)]
}

#
# time ->server @server ->client round-trip
# 0
# 1
# 2
# 3
# 4
# 5
# [Dismiss]
#
proc ServerPingTest {} {
	global _preferences colortheme SPTidx

	create_dialog .spt
	set SPTidx 5
	wm title .spt "Server Ping Test"
	grid [label .spt.h0 -text "Time"      -foreground [dict get $_preferences styles dialogs heading_fg $colortheme]] \
	     [label .spt.h1 -text "In Transit" -foreground [dict get $_preferences styles dialogs heading_fg $colortheme]] \
	     [label .spt.h2 -text "In Server" -foreground [dict get $_preferences styles dialogs heading_fg $colortheme]] \
	     [label .spt.h3 -text "Round-Trip" -foreground [dict get $_preferences styles dialogs heading_fg $colortheme]]
     	grid [label .spt.t0 -text "--:--:--"]
     	grid [label .spt.t1 -text "--:--:--"]
     	grid [label .spt.t2 -text "--:--:--"]
     	grid [label .spt.t3 -text "--:--:--"]
     	grid [label .spt.t4 -text "--:--:--"]
     	grid [label .spt.t5 -text "--:--:--"]
     	grid [button .spt.dismiss -text Dismiss -command "destroy .spt"] - - -
	after 0 _ping_server
}

proc _ping_server {} {
	global SPTidx _preferences colortheme
	if {[winfo exists .spt]} {
		set SPTidx [expr ($SPTidx + 1) % 6]
		foreach w {s i r} {
			if {[winfo exists .spt.$w$SPTidx]} {
				grid forget .spt.$w$SPTidx
				destroy .spt.$w$SPTidx
			}
		}
		.spt.t$SPTidx configure -text [clock format [clock seconds] -format %H:%M:%S]
		grid [label .spt.s$SPTidx -text "pending..."] - - -row [expr $SPTidx + 1] -column 1
		.spt.t$SPTidx configure -foreground [dict get $_preferences styles dialogs highlight_fg $colortheme]
		.spt.s$SPTidx configure -foreground [dict get $_preferences styles dialogs highlight_fg $colortheme]
		::gmaproto::_protocol_send ECHO s __spt__ i $SPTidx o [dict create origin [clock microseconds]]
		after 10000 _ping_server
	}
}

proc scan_fractional_seconds {t} {
	if {$t eq {0001-01-01T00:00:00Z}} {
		# This is the zero value for times
		return 0
	}
	if {[regexp {^(.*T\d+:\d+:\d+)\.(\d+)([+-].*)$} $t _ pre frac post]} {
		if {[set intsec [clock scan "$pre$post" -format "%Y-%m-%dT%H:%M:%S%z"]]} {
			return "$intsec.$frac"
		}
	}
	DEBUG 0 "Unable to parse date string \"$t\""
	return 0
}

proc _server_ping_reply {d} {
	global _preferences colortheme

	if {[winfo exists .spt]} {
		set recd_f [expr [clock microseconds] / 1000000.0]
		set sent_f [expr [dict get $d o origin] / 1000000.0]
		set idx [dict get $d i]
		set server_recd [scan_fractional_seconds [dict get $d ReceivedTime]]
		set server_sent [scan_fractional_seconds [dict get $d SentTime]]
		set round_trip [expr $recd_f - $sent_f]
		set in_server [expr $server_sent - $server_recd]
		set in_transit [expr $round_trip - $in_server]

		.spt.t$idx configure -foreground [dict get $_preferences styles dialogs normal_fg $colortheme]
		grid forget .spt.s$idx
		.spt.s$idx configure -foreground [dict get $_preferences styles dialogs normal_fg $colortheme]\
			-text [format "%.3fms" [expr $in_transit * 1000.0]]
		grid configure x .spt.s$idx \
			[label .spt.i$idx -foreground [dict get $_preferences styles dialogs normal_fg $colortheme] -text [format "%.3fms" [expr $in_server * 1000.0]]] \
			[label .spt.r$idx -foreground [dict get $_preferences styles dialogs normal_fg $colortheme] -text [format "%.3fms" [expr $round_trip * 1000.0]]] \
		-row [expr $idx+1] -sticky e
	}
}

proc DistanceFromGrid {x y z_ft} {
	global MOBdata canvas
	global iscale is_GM
	global _preferences colortheme
	lassign [ScreenXYToGridXY $x $y -exact] Gx Gy

	create_dialog .dfg
	wm title .dfg "Distance from grid point [LetterLabel $Gx]$Gy"
	grid [text .dfg.list -background [dict get $_preferences styles dialogs normal_bg $colortheme] -yscrollcommand {.dfg.sb set}] \
	     [scrollbar .dfg.sb -orient vertical -command {.dfg.list yview}] -sticky news
	grid [button .dfg.ok -text OK -command "$canvas delete distanceTracer; destroy .dfg"]
	bind .dfg <Destroy> "$canvas delete distanceTracer"
	grid columnconfigure .dfg 0 -weight 1
	grid rowconfigure .dfg 0 -weight 1
	.dfg.list tag configure key    -foreground [dict get $_preferences styles dialogs highlight_fg $colortheme]
	.dfg.list tag configure normal -foreground [dict get $_preferences styles dialogs normal_fg $colortheme]
	.dfg.list tag configure title  -foreground [dict get $_preferences styles dialogs heading_fg $colortheme]
	set namelen [string length "TARGET"]

	foreach target [array names MOBdata] {
		# exclude hidden MOBs
		if {[dict get $MOBdata($target) Hidden]} {
			if {$is_GM} {
				set name($target) [format "(%s)" [::gmaclock::nameplate_text [dict get $MOBdata($target) Name]]]
			} else {
				continue
			}
		} else {
			set name($target) [::gmaclock::nameplate_text [dict get $MOBdata($target) Name]]
		}

		set centerdist($target) [DistanceToTarget3D $Gx $Gy $z_ft $target]
		set dimension($target) [expr [dict get $MOBdata($target) Elev] == $z_ft ? {{2D}} : {{3D}}]
		lassign [set nearest($target) [NearestCreatureGridToPoint $Gx $Gy $z_ft $target]] neardist nearX nearY nearLbl
		$canvas create line {*}[GridXYToCenterPoint $Gx $Gy] {*}[lrange [MOBCenterPoint $target] 0 1] \
			-fill yellow -width 5 -tags distanceTracer -arrow last -arrowshape [list 15 18 8]
		$canvas create rect [expr $nearX*$iscale] [expr $nearY*$iscale] [expr ($nearX+1)*$iscale] [expr ($nearY+1)*$iscale] \
			-outline yellow -width 5 -tags distanceTracer
		set namelen [expr max($namelen, [string length $name($target)])]
	}

	.dfg.list insert end [format "%-${namelen}.${namelen}s  CENTER-TO-CENTER  NEAREST-GRID-----\n" TARGET------------------------] title

	foreach target [lsort -real -command "SortByValue centerdist" [array names centerdist]] {
		.dfg.list insert end [format "%-${namelen}s  %3dsq %3dft (%s)  %3dsq "\
			$name($target) $centerdist($target) [expr $centerdist($target)*5] $dimension($target)\
			[lindex $nearest($target) 0]] normal
		.dfg.list insert end [format "%3dft" [expr [lindex $nearest($target) 0]*5]] key
		.dfg.list insert end " [lindex $nearest($target) 3]\n" normal
	}
}

proc SortByValue {arrname i j} {
	upvar $arrname a
	return [expr $a($i) - $a($j)]
}


proc DistanceFromMob {MobID} {
	global MOBdata canvas
	global iscale is_GM
	global _preferences colortheme
	lassign [MOBCenterPoint $MobID] MobX MobY MobR
	set Cx [expr int($MobX/$iscale)]
	set Cy [expr int($MobY/$iscale)]
	set z_ft [dict get $MOBdata($MobID) Elev]
	set MGx0 [expr ($MobX-$MobR)/$iscale]
	set MGx1 [expr ($MobX+$MobR)/$iscale]
	set MGy0 [expr ($MobY-$MobR)/$iscale]
	set MGy1 [expr ($MobY+$MobR)/$iscale]

	if {[dict get $MOBdata($MobID) Hidden] && !$is_GM} {
		return
	}

	create_dialog .dfg
	wm title .dfg "Distance from [dict get $MOBdata($MobID) Name]"
	grid [text .dfg.list -background [dict get $_preferences styles dialogs normal_bg $colortheme] -yscrollcommand {.dfg.sb set}] \
	     [scrollbar .dfg.sb -orient vertical -command {.dfg.list yview}] -sticky news
	grid [button .dfg.ok -text OK -command "$canvas delete distanceTracer; destroy .dfg"]
	bind .dfg <Destroy> "$canvas delete distanceTracer"
	grid columnconfigure .dfg 0 -weight 1
	grid rowconfigure .dfg 0 -weight 1
	.dfg.list tag configure key -foreground    [dict get $_preferences styles dialogs highlight_fg $colortheme]
	.dfg.list tag configure normal -foreground [dict get $_preferences styles dialogs normal_fg $colortheme]
	.dfg.list tag configure title -foreground  [dict get $_preferences styles dialogs heading_fg $colortheme]
	set namelen [string length "TARGET"]

	foreach target [array names MOBdata] {
		if {$target eq $MobID} continue
		if {[dict get $MOBdata($target) Hidden]} {
			if {$is_GM} {
				set name($target) [format "(%s)" [::gmaclock::nameplate_text [dict get $MOBdata($target) Name]]]
			} else {
				continue
			}
		} else {
			set name($target) [::gmaclock::nameplate_text [dict get $MOBdata($target) Name]]
		}
		
		# get center-to-center distance
		set centerdist($target) [DistanceToTarget3D $Cx $Cy $z_ft $target]
		set dimension($target) [expr [dict get $MOBdata($target) Elev] == $z_ft ? {{2D}} : {{3D}}]
		set namelen [expr max($namelen, [string length $name($target)])]
		$canvas create line $MobX $MobY {*}[lrange [MOBCenterPoint $target] 0 1] \
			-fill yellow -width 5 -tags distanceTracer -arrow last -arrowshape [list 15 18 8]

		# Now iterate over all the grids occupied by this creature to see what the closest distance
		# is between ANY grid of this creature and ANY grid of the target.
		set distance -1
		lassign [MOBCenterPoint $target] Tx Ty Tr
		set TGx0 [expr ($Tx-$Tr)/$iscale]
		set TGx1 [expr ($Tx+$Tr)/$iscale]
		set TGy0 [expr ($Ty-$Tr)/$iscale]
		set TGy1 [expr ($Ty+$Tr)/$iscale]
		set Tz_ft [dict get $MOBdata($target) Elev]
		for {set x $MGx0} {$x < $MGx1} {set x [expr $x + 1.0]} {
			for {set y $MGy0} {$y < $MGy1} {set y [expr $y + 1.0]} {
				for {set tx $TGx0} {$tx < $TGx1} {set tx [expr $tx + 1.0]} {
					for {set ty $TGy0} {$ty < $TGy1} {set ty [expr $ty + 1.0]} {
						set d [expr round(sqrt(pow($x-$tx,2) + pow($y-$ty,2) + pow(($z_ft/5.0)-($Tz_ft/5.0),2)))]

						if {$distance < 0 || $d < $distance} {
							set distance [expr int($d)]
							set nearX [expr int($x)]
							set nearY [expr int($y)]
							set nearTX [expr int($tx)]
							set nearTY [expr int($ty)]
						}
					}
				}
			}
		}
		if {$distance < 0} {
			DEBUG 0 "Unable to calculate the distance between $MobID and $target"
		} else {
			set nearest($target) [list $distance $nearTX $nearTY "[LetterLabel $nearTX]$nearTY"]
			$canvas create rect [expr $nearX*$iscale] [expr $nearY*$iscale] \
				            [expr ($nearX+1)*$iscale] [expr ($nearY+1)*$iscale] \
					    -outline yellow -width 5 -tags distanceTracer

			$canvas create rect [expr $nearTX*$iscale] [expr $nearTY*$iscale] \
				            [expr ($nearTX+1)*$iscale] [expr ($nearTY+1)*$iscale] \
					    -outline yellow -width 5 -tags distanceTracer
		}
	}

	.dfg.list insert end [format "%-${namelen}.${namelen}s  CENTER-TO-CENTER  NEAREST-GRID-----\n" TARGET------------------------] title

	foreach target [lsort -real -command "SortByValue centerdist" [array names centerdist]] {
		.dfg.list insert end [format "%-${namelen}s  %3dsq %3dft (%s)  %3dsq " \
			$name($target) $centerdist($target) [expr $centerdist($target)*5] $dimension($target)\
			[lindex $nearest($target) 0]] normal
		.dfg.list insert end [format "%3dft" [expr [lindex $nearest($target) 0]*5]] key
		.dfg.list insert end " [lindex $nearest($target) 3]\n" normal
	}
}

proc DistanceAlongRoute {coordlist} {
	set distance 0
	set gridxy [ScreenXYToGridXY [lindex $coordlist 0] [lindex $coordlist 1]]
	set x [lindex $gridxy 0]
	set y [lindex $gridxy 1]
	foreach {x2 y2} [lrange $coordlist 2 end] {
		set gridxy [ScreenXYToGridXY $x2 $y2]
		incr distance [GridDistance $x $y [lindex $gridxy 0] [lindex $gridxy 1]]
		set x [lindex $gridxy 0]
		set y [lindex $gridxy 1]
	}
	return $distance
}

proc MOB_Drag {w x y} {
	global MOBdata MOB_MOVING DistanceLabelText MOB_StartGxGy MOB_TrackXY

	if {$MOB_MOVING ne {}} {
		set cx [$w canvasx $x]
		set cy [$w canvasy $y]
		set gridxy [ScreenXYToGridXY $x $y]
		set orig [$w coords DL#line]
		$w coords DL#line [lindex $orig 0] [lindex $orig 1] $cx $cy
		$w coords DL#track $MOB_TrackXY
		DEBUG 3 "DL#track $MOB_TrackXY : [$w coords DL#track ]"
		#
		# TODO: the track needs to be optimized, maybe a snap to
		#       grid centers or something, so that there are fewer
		#       points and the line is "cleaner".
		#
		set delta_xy [MOBPositionDelta $gridxy $MOB_MOVING]
		set total_move [GridDistance [lindex $MOB_StartGxGy 0] [lindex $MOB_StartGxGy 1] [lindex $gridxy 0] [lindex $gridxy 1]]
		set DistanceLabelText [format {[%02d] %03d ft / path %03d ft} $total_move [expr $total_move * 5] [expr [DistanceAlongRoute $MOB_TrackXY] * 5]]
		if {[dict get $MOBdata($MOB_MOVING) Gx] != [lindex $gridxy 0]
		||  [dict get $MOBdata($MOB_MOVING) Gy] != [lindex $gridxy 1]} {
			MoveSomeone $w $MOB_MOVING [lindex $gridxy 0] [lindex $gridxy 1]
			set MOB_TrackXY [concat $MOB_TrackXY $cx $cy]
			set select_list [GetSelectionList]
			#
			# If the thing they're dragging isn't in the selection list, don't drag the
			# selected items too
			#
			if {[llength $select_list] > 0 && [lsearch -exact $select_list $MOB_MOVING] >= 0} {
				foreach other_mob $select_list {
					if {$other_mob != $MOB_MOVING} {
						MoveSomeone $w $other_mob [expr [dict get $MOBdata($other_mob) Gx] + [lindex $delta_xy 0]] [expr [dict get $MOBdata($other_mob) Gy] + [lindex $delta_xy 1]]
					}
				}
			}
		}
	}
}

proc MOB_EndDrag {w} {
	global MOB_MOVING

	DEBUG 3 "EndDrag $MOB_MOVING"
	if {$MOB_MOVING ne {}} {
		$w delete DL#marks
		foreach mob_id [GetSelectionList] {
			SendMobChanges $mob_id {Gx Gy}
		}
		SendMobChanges $MOB_MOVING {Gx Gy}
		#if {[lsearch -exact [GetSelectionList] $MOB_MOVING] >= 0} {
			#ClearSelection
		#}
		set MOB_MOVING {}
	}
}

#$canvas create line 0 0 400 400 -fill red
#$canvas bind item <Any-Enter> "MOB_Enter $canvas"
#$canvas bind item <Any-Leave> "MOB_Leave $canvas"
#bind $canvas <1> "MOB_StartDrag $canvas %x %y"
bind $canvas $BUTTON_RIGHT "DoContext %x %y"
#bind $canvas <B1-Motion> "MOB_Drag $canvas %x %y"
#bind $canvas <B1-ButtonRelease> "MOB_EndDrag $canvas"
playtool

proc FindNearby {} {
	global MOB_X MOB_Y canvas
	canvas_see $canvas allOBJ
}

# Menu: movement mode ( {} = normal/walk/run, fly, swim, climb, burrow )

#
# Is the current value of the mob's attribute equal to <value>?
#
proc MobState {mob_id attr value} {
	global MOBdata

	if {[llength $mob_id] != 1} { 
		return false ; # not just one target, so no.
	}
	if {[info exists MOBdata($mob_id)]} {
		if {![dict exists $MOBdata($mob_id) $attr]} {
			DEBUG 0 "MobState($mob_id,$attr,$value) no such attribute"
			return false
		}
		if {[dict get $MOBdata($mob_id) $attr] == $value} {
			return true
		}
	}
	return false
}

#
# Is the current value of the mob's attribute one of the values in the list <value>?
#
proc MobStateList {mob_id attr value} {
	global MOBdata

	if {[llength $mob_id] != 1} { 
		return false ; # not just one target, so no.
	}
	if {[info exists MOBdata($mob_id)]} {
		if {![dict exists $MOBdata($mob_id) $attr]} {
			DEBUG 0 "MobStateList($mob_id,$attr,$value) no such attribute"
			return false
		}
		if {[lsearch -exact $value [dict get $MOBdata($mob_id) $attr]] >= 0} {
			return true
		}
	}
	return false
}

#
# Does the value of the mob's attribute (which is a list) contain <value> as an element?
#
proc MobStateFlag {mob_id attr value} {
	global MOBdata

	if {[llength $mob_id] != 1} { 
		return false ; # not just one target, so no.
	}
	if {$attr eq {__hide__}} {
		return [dict get $MOBdata($mob_id) Hidden]
	}
	if {[info exists MOBdata($mob_id)]} {
		if {![dict exists $MOBdata($mob_id) $attr]} {
			DEBUG 0 "MobStateFlag($mob_id,$attr,$value) no such attribute"
			return false
		}
		if {[lsearch -exact [dict get $MOBdata($mob_id) $attr] $value] >= 0} {
			return true
		}
	}
	return false
}
	

proc CreateMovementModeSubMenu {args} {
	if {[lindex $args 0] == {-mass}} {
		set mob_id __mass__
		set mob_list [lindex $args 1]
		set cmd MovementModeAll
		set sub mmode.m_
	} else {
		set sub [expr [string equal [lindex $args 0] {-deep}] ? {{mmode.m_}} : {{mmode_m_}}]
		set mob_list [set mob_id [lindex $args 1]]
		set cmd MovementModePerson
	}

	set mid .contextMenu.$sub$mob_id
	catch {$mid delete 0 end; destroy $mid}
	menu $mid -tearoff 0
	foreach {value label} {{} Land burrow Burrow climb Climb fly Fly swim Swim} {
		if {[MobState $mob_list MoveMode [::gmaproto::to_enum MoveMode $value]]} {
			$mid add command -command [list $cmd $mob_list $value] -label $label -foreground #ff0000
		} else {
			$mid add command -command [list $cmd $mob_list $value] -label $label
		}
	}
	return $mid
}

proc MovementModePerson {mob_id movemode} {
	global MOBdata canvas
	dict set MOBdata($mob_id) MoveMode [::gmaproto::to_enum MoveMode $movemode]
	RenderSomeone $canvas $mob_id
	SendMobChanges $mob_id {MoveMode}
}

proc MovementModeAll {mob_list movemode} {
	foreach mob $mob_list {
		MovementModePerson $mob $movemode
	}
}

# Menu: Elevation

proc CreateElevationSubMenu {args} {
	if {[lindex $args 0] == {-mass}} {
		set mob_id __mass__
		set mob_list [lindex $args 1]
		set cmd ElevateAll
		set ncmd AddElevationMenuAll
		set sub elev.m_
	} else {
		set sub [expr [string equal [lindex $args 0] {-deep}] ? {{elev.m_}} : {{elev_m_}}]
		set mob_list [set mob_id [lindex $args 1]]
		set cmd ElevatePerson
		set ncmd AddElevationMenu
	}

	set mid .contextMenu.$sub$mob_id
	catch {$mid delete 0 end; destroy $mid}
	menu $mid
	foreach {value label} {0 (Ground) +30 +30 +20 +20 +10 +10 +5 +5 -5 -5 -10 -10 -20 -20 -30 -30 -40 -40 -60 -60} {
		if {$value == 0 && [MobState $mob_list Elev $value]} {
			$mid add command -command [list $cmd $mob_list $value] -label $label -foreground #ff0000
		} else {
			$mid add command -command [list $cmd $mob_list $value] -label $label
		}
	}
	$mid add command -command [list $ncmd $mob_list] -label (Set)
	return $mid
}

proc ElevatePerson {mob_id elev} {
	global MOBdata canvas
	if {[regexp {^[+\-]} $elev] } {
		catch {dict set MOBdata($mob_id) Elev [expr [dict get $MOBdata($mob_id) Elev] + $elev]}
	} else {
		dict set MOBdata($mob_id) Elev $elev
	}
	RenderSomeone $canvas $mob_id
	SendMobChanges $mob_id {Elev}
}

proc ElevateAll {mob_list elev} {
	foreach mob $mob_list {
		ElevatePerson $mob $elev
	}
}

#proc AddToObjectAttribute {id key vlist} {}
#proc RemoveFromObjectAttribute {id key vlist} {}

#
# Toggle item in attribute list. Returns 1 if added,
# -1 if removed, or 0 if nothing changed.
#
proc ToggleObjectAttribute {id key value} {
	if {[set idlist [ResolveObjectId_OA $id]] eq {}} {
		return 0
	}
	lassign $idlist a id datatype
	global $a

	if {![dict exists [set ${a}($id)] $key]} {
		DEBUG 0 "Attempt to access field $key in object $id but type $datatype has no such field."
		return 0
	}

	if {$value eq {__clear__}} {
		set defv [dict get [::gmaproto::new_dict $datatype] $key]
		DEBUG 4 "Clearing $id.$key completely (in $a) to \"$defv\""
		dict set ${a}($id) $key $defv
		return -1
	}
	DEBUG 4 "Toggling value $value in object $id.$key (in $a)"
	set old [dict get [set ${a}($id)] $key]
	if {[set index [lsearch -exact $old $value]] >= 0} {
		dict set ${a}($id) $key [set new [lreplace $old $index $index]]
		DEBUG 4 "Removed attribute; now $new"
		return -1
	} else {
		dict lappend ${a}($id) $key $value
		DEBUG 4 "Added attribute; now [dict get [set ${a}($id)] $key]"
		return 1
	}
}
	

proc CondPerson {mob_id condition} {
	global canvas

	if {$condition eq {__hide__}} {
		global MOBdata
		dict set MOBdata($mob_id) Hidden [expr ! [dict get $MOBdata($mob_id) Hidden]]
		RenderSomeone $canvas $mob_id
		SendMobChanges $mob_id {Hidden}
	} else {
		if {[ToggleObjectAttribute $mob_id StatusList $condition] != 0} {
			RenderSomeone $canvas $mob_id
			SendMobChanges $mob_id {StatusList}
		}
	}
}

proc CondAll {mob_list condition} {
	foreach mob $mob_list {
		CondPerson $mob $condition
	}
}

proc CreateConditionSubMenu {args} {
	global MarkerShape MarkerColor is_GM

	if {[lindex $args 0] == {-mass}} {
		set mob_id __mass__
		set mob_list [lindex $args 1]
		set cmd CondAll
		set sub cond.m_
	} else {
		set sub [expr [string equal [lindex $args 0] {-deep}] ? {{cond.m_}} : {{cond_m_}}]
		set mob_list [set mob_id [lindex $args 1]]
		set cmd CondPerson
	}

	set mid .contextMenu.$sub$mob_id
	catch {$mid delete 0 end; destroy $mid}
	menu $mid
	set choices [lsort [array names MarkerShape]]
	if {[llength $choices] > 20} {
		set groupsize [expr int([llength $choices] / 10)]
		set submenu {}
		for {set i 0} {$i < [llength $choices]} {incr i} {
			if {$i % $groupsize == 0} {
				if {[set last [expr $i + $groupsize - 1]] >= [llength $choices]} {
					set last end
				}
				catch {$mid.$i delete 0 end; destroy $mid.$i}
				menu $mid.$i
				$mid add cascade -menu $mid.$i -label "[lindex $choices $i] - [lindex $choices $last]"
				set submenu $mid.$i
			}
			set condition [lindex $choices $i]
			if {[info exists MarkerColor($condition)] && $MarkerColor($condition) ne {} && $MarkerShape($condition) ne {}} {
				if {[MobStateFlag $mob_list StatusList $condition]} {
					$submenu add command -command [list $cmd $mob_list $condition] -label $condition -foreground #ff0000
				} else {
					$submenu add command -command [list $cmd $mob_list $condition] -label $condition
				}
			}
		}
	} else {
		foreach condition [lsort [array names MarkerShape]] {
			if {[info exists MarkerColor($condition)] && $MarkerColor($condition) ne {} && $MarkerShape($condition) ne {}} {
				if {[MobStateFlag $mob_list StatusList $condition]} {
					$mid add command -command [list $cmd $mob_list $condition] -label $condition -foreground #ff0000
				} else {
					$mid add command -command [list $cmd $mob_list $condition] -label $condition
				}
			}
		}
	}
	$mid add separator
	$mid add command -command [list $cmd $mob_list __clear__] -label "(clear all)"
	if {$is_GM} {
		if {[MobStateFlag $mob_list __hide__ {}]} {
			$mid add command -command [list $cmd $mob_list __hide__] -label "(hidden)" -foreground #ff0000
		} else {
			$mid add command -command [list $cmd $mob_list __hide__] -label "(hidden)"
		}
	}
	return $mid
}

set TagHistory {}
proc CreateTagSubMenu {args} {
	if {[lindex $args 0] == {-mass}} {
		set mob_id __mass__
		set mob_list [lindex $args 1]
		set cmd TagAll
		set ncmd AddTagMenuAll
		set sub tag.m_
	} else {
		set sub [expr [string equal [lindex $args 0] {-deep}] ? {{tag.m_}} : {{tag_m_}}]
		set mob_list [set mob_id [lindex $args 1]]
		set cmd TagPerson
		set ncmd AddTagMenu
	}
	global TagHistory

	set mid .contextMenu.$sub$mob_id
	catch {$mid delete 0 end; destroy $mid}
	menu $mid
	$mid add command -command [list $cmd $mob_list {}] -label (Clear)
	$mid add command -command [list $ncmd $mob_list] -label (New)
	foreach tag $TagHistory {
		if {[MobState $mob_list Note $tag]} {
			$mid add command -command [list $cmd $mob_list $tag] -label $tag -foreground #ff0000
		} else {
			$mid add command -command [list $cmd $mob_list $tag] -label $tag
		}
	}
	#dumpMenu $mid
	return $mid
}

proc TagPerson {mob_id tag} {
	global MOBdata TagHistory canvas
	dict set MOBdata($mob_id) Note $tag
	if {$tag != {}} {
		if {[set i [lsearch -exact $TagHistory $tag]] < 0} {
			if {[llength $TagHistory] <= 9} {
				set TagHistory [linsert $TagHistory 0 $tag]
			} else {
				set TagHistory [lreplace [linsert $TagHistory 0 $tag] 10 end]
			}
		} elseif {$i > 0} {
			set TagHistory [linsert [lreplace $TagHistory $i $i] 0 $tag]
		}
	}
	RenderSomeone $canvas $mob_id
	SendMobChanges $mob_id {Note}
}

proc TagAll {mob_list tag} {
	foreach mob $mob_list {
		TagPerson $mob $tag
	}
}

proc AllowedToPolymorph {mobID} {
	global MOBdata
	global is_GM

	if {![info exists MOBdata($mobID)]} {
		return false
	}

	if {[dict exists $MOBdata($mobID) PolyGM] && [dict get $MOBdata($mobID) PolyGM] && !$is_GM} {
		return false
	}
	
	if {[dict exists $MOBdata($mobID) SkinSize] && [llength [dict get $MOBdata($mobID) SkinSize]] > 1} {
		return true
	}

	return false
}

# CreatePolySubMenu ?-deep <mobID>? ?-shallow <mobID>? ?-mass <mobIDlist>?
#   adds a new set of menu items for each skin available to a monster
#   -mass (used for "all of the above" selection)
#   	.contextMenu.poly.m___mass__		-> PolymorphMass <mobIDlist> <skin#>
#   -deep (used when adding a sub-menu for each of a set of mobs)
#   	.contextMenu.poly.m_<mobID>		-> PolymorphPerson <mobID> <skin#>
#   default (used for a single creature)
#   	.contextMenu.poly_m_<mobID>		-> PolymorphPerson <mobID> <skin#>
#
#   all targets which can't polymorph (or the player can't polymorph) are removed
#   from the list for -mass; otherwise it's the caller's responsibility to decide
#   not to call CreatePolySubMenu if a creature can't be polymorphed
proc CreatePolySubMenu {args} {
	global MOBdata
	if {[lindex $args 0] == {-mass}} {
		set mob_id __mass__
		set mob_list [lindex $args 1]
		set cmd PolymorphMass
		set sub poly.m_
	} else {
		set sub [expr [string equal [lindex $args 0] {-deep}] ? {{poly.m_}} : {{poly_m_}}]
		set mob_list [set mob_id [lindex $args 1]]
		set cmd PolymorphPerson
	}
	set mid .contextMenu.$sub$mob_id
	catch {$mid delete 0 end; destroy $mid}
	menu $mid
	set mob_list [lmap mi $mob_list {
		if {![AllowedToPolymorph $mi]} {
			continue
		}
		list $mi
	}]
	if {[llength $mob_list] == 0} {
		return $mid
	}

	if {[llength $mob_list] == 1} {
		set mob_id [lindex $mob_list 0]
		set i 0
		foreach sz [dict get $MOBdata($mob_id) SkinSize] {
			if {[set name [SkinComment $sz]] eq {}} {
				set name [format "Skin #%d" $i]
			}
			if {[SkinIsDefault $sz]} {
				set name "\[$name\]"
			}
			if {[MobState $mob_list Skin $i]} {
				$mid add command -command [list $cmd $mob_list $i] -label $name -foreground #ff0000
			} else {
				$mid add command -command [list $cmd $mob_list $i] -label $name
			}
			incr i
		}
		return $mid
	}

	#
	# Find the maximum number of skins for the monster(s) we're dealing with here
	#
	set max_skin 0
	foreach mi $mob_list {
		if {[info exists MOBdata($mi)] && [dict exists $MOBdata($mi) SkinSize]} {
			set max_skin [expr max($max_skin, [llength [dict get $MOBdata($mi) SkinSize]])]
		} 
	}

	for {set i 0} {$i < $max_skin} {incr i} {
		$mid add command -command [list $cmd $mob_list $i] -label [format "Skin #%d" $i]
	}
	return $mid
}

proc CreateSizeSubMenu {args} {
	global MOBdata
	if {[lindex $args 0] == {-mass}} {
		set mob_id __mass__
		set mob_list [lindex $args 1]
		set cmd ChangeDispSizeAll
		set sub size.m_
	} else {
		set sub [expr [string equal [lindex $args 0] {-deep}] ? {{size.m_}} : {{size_m_}}]
		set mob_list [set mob_id [lindex $args 1]]
		set cmd ChangeDispSize
	}
	set mid .contextMenu.$sub$mob_id
	catch {$mid delete 0 end; destroy $mid}
	menu $mid
	foreach {size_code size_name} {
		{F f} Fine
		{D d} Diminutive
		{T t} Tiny
		{S s} Small
		{M m} Medium
		l {Large (long)}
		L {Large (tall)}
		{L0 l0} {Large (no reach)}
		h {Huge (long)}
		H {Huge (tall)}
		g {Gargantuan (long)}
		G {Gargantuan (tall)}
		c {Colossal (long)}
		C {Colossal (tall)}
	} {
		if {$mob_id ne {__mass__}} {
			set real_size [SkinSizeOnly [dict get $MOBdata($mob_id) Size]]
			set disp_size [CreatureDisplayedSize $mob_id]

			if {[lsearch -exact $size_code $disp_size] >= 0} {
				$mid add command -command [list $cmd $mob_list [lindex $size_code 0]] -label $size_name -foreground #ff0000
			} elseif {[lsearch -exact $size_code $real_size] >= 0} {
				$mid add command -command [list $cmd $mob_list [lindex $size_code 0]] -label $size_name -foreground #0000bb
			} else {
				$mid add command -command [list $cmd $mob_list [lindex $size_code 0]] -label $size_name
			}
		}
	}
	return $mid
}


# CreateReachSubMenu -shallow mob   -> menu .contextMenu.reach_m_(mob) of choices to apply to mob	(only mob involved)
# CreateReachSubMenu -deep mob      -> menu .contextMenu.reach.m_(mob) of choices to apply to mob	(one of many mobs involved)
# 	call SetCustomReach [mob...] -setnat|-setext|-incrnat|-incrext|-toggle squares|reach|all
# CreateReachSubMenu -mass [mob...] -> menu .contextMenu.reach.m___mass__ of choices to apply to all mobs
# 	call SetCustomReachAll [mob...] -setnat|-setext|-incrnat|-incrext|-toggle squares|reach|all
proc DefaultCustomReach {size} {
	set template [ReachMatrix $size]
	if {$template eq {}} {
		set template [list 0 0 {}]
	}
	return [dict create \
		Enabled false \
		Natural [lindex $template 0] \
		Extended [lindex $template 1] \
	]
}

proc SetCustomReach {mob_id mode value} {
	global MOBdata canvas
	set d $MOBdata($mob_id)
	set reach [dict get $d Reach]
	set custom [dict get $d CustomReach]
	set size [CreatureDisplayedSize $mob_id]
	if {$custom eq {}} {
		set custom [DefaultCustomReach $size]
	}
	set whatchanged {}

	# Apply requested changes
	switch -exact -- $mode {
		-setnat { 
			dict set custom Natural $value 
			dict set custom Enabled true
			set whatchanged CustomReach
		}
		-setext { 
			dict set custom Extended $value 
			dict set custom Enabled true
			set whatchanged CustomReach
		}
		-incrnat { 
			dict set custom Natural [expr [dict get $custom Natural] + $value] 
			dict set custom Enabled true
			set whatchanged CustomReach
		}
		-incrext { 
			dict set custom Extended [expr [dict get $custom Extended] + $value] 
			dict set custom Enabled true
			set whatchanged CustomReach
		}
		-toggle {
			global SCRR SCRN
			if {$SCRR($mob_id)} {
				if {$SCRN($mob_id)} {
					set reach 2
				} else {
					set reach 1
				}
			} else {
				set reach 0
			}
			set whatchanged Reach
		}
	}

	switch $whatchanged {
		Reach {
			dict set MOBdata($mob_id) Reach $reach
			SendMobChanges $mob_id {Reach}
		}
		CustomReach {
			if {[dict get $custom Natural] > [dict get $custom Extended]} {
				dict set custom Extended [dict get $custom Natural]
			}
			dict set MOBdata($mob_id) CustomReach $custom
			SendMobChanges $mob_id {CustomReach}
		}
	}

	RenderSomeone $canvas $mob_id
}

proc SetCustomReachAll {mob_list mode value} {
	foreach mob $mob_list {
		SetCustomReach $mob $mode $value
	}
}

proc CreateReachSubMenu {args} {
	global MOBdata

	if {[lindex $args 0] == {-mass}} {
		set mob_id __mass__
		set mob_list [lindex $args 1]
		set cmd SetCustomReachAll
		set sub reach.m_
	} else {
		set sub [expr [string equal [lindex $args 0] {-deep}] ? {{reach.m_}} : {{reach_m_}}]
		set mob_list [set mob_id [lindex $args 1]]
		set cmd SetCustomReach
	}
	set mid .contextMenu.$sub$mob_id
	catch {$mid.nat delete 0 end; destroy $mid.nat}
	catch {$mid.ext delete 0 end; destroy $mid.ext}
	catch {$mid delete 0 end; destroy $mid}
	menu $mid
	menu $mid.nat
	menu $mid.ext
	foreach {feet code} {
		0 0
		5 1
		10 2
		15 3
		20 4
		25 5
		30 6
		35 7
		40 8
		45 9
	} {
		set this_nat false
		set this_ext false
		if {$mob_id ne {__mass__}} {
			if {[catch {
				lassign [FullCreatureAreaInfo $mob_id] _ n e _ _
				set this_nat [expr $n == $code]
				set this_ext [expr $e == $code]
			} err]} {
				DEBUG 0 "Error trying to look up reach zones for $mob_id: $err"
			}
		}

		foreach menutype {nat ext} {
			if {[set this_$menutype]} {
				$mid.$menutype add command -command [list $cmd $mob_list -set$menutype $feet] -label "$feet ft" -foreground #ff0000
			} else {
				$mid.$menutype add command -command [list $cmd $mob_list -set$menutype $feet] -label "$feet ft"
			}
		}
	}
	foreach submenu {nat ext} {
		$mid.$submenu add separator
		$mid.$submenu add command -command [list $cmd $mob_list -incr$submenu  2] -label "+10 ft"
		$mid.$submenu add command -command [list $cmd $mob_list -incr$submenu  1] -label "+5 ft"
		$mid.$submenu add command -command [list $cmd $mob_list -incr$submenu -1] -label "-5 ft"
		$mid.$submenu add command -command [list $cmd $mob_list -incr$submenu -2] -label "-10 ft"
	}
	global SCRR SCRN check_menu_color
	$mid add checkbutton -onvalue 1 -offvalue 0 -variable SCRR($mob_id) -command [list $cmd $mob_list -toggle reach] -label "Extended Reach" -selectcolor $check_menu_color
	$mid add checkbutton -onvalue 1 -offvalue 0 -variable SCRN($mob_id) -command [list $cmd $mob_list -toggle all] -label "Include Natural Distance" -selectcolor $check_menu_color

	if {$mob_id eq {__mass__}} {
		set SCRR(__mass__) 2
		set SCRN(__mass__) 2
	} else {
		set reach [dict get $MOBdata($mob_id) Reach]
		set SCRR($mob_id) [expr $reach == 0 ? 0 : 1]
		set SCRN($mob_id) [expr $reach == 2 ? 1 : 0]
	}

	$mid add cascade -menu $mid.nat -label "Natural Reach Distance"
	$mid add cascade -menu $mid.ext -label "Extended Reach Distance"
	return $mid
}

proc DoContext {x y} {
	global MOB_X MOB_Y canvas MOBdata
	set MOB_X $x
	set MOB_Y $y
	lassign [ScreenXYToGridXY $x $y -exact] Gx Gy

	set mob_list [lsort -unique -command MobNameComparison [concat [ScreenXYToMOBID $canvas $x $y] [GetSelectionList]]]
	DEBUG 3 "DoContext mob_list $mob_list from [ScreenXYToMOBID $canvas $x $y] + [GetSelectionList]"

	.contextMenu delete 13
	.contextMenu insert 13 command -command "DistanceFromGrid $x $y 0" -label "Distance from [LetterLabel $Gx]$Gy"

	if {[llength $mob_list] == 0} {
		.contextMenu delete 0
		.contextMenu insert 0 command -command "" -label "Remove" -state disabled
		.contextMenu delete 3
		.contextMenu insert 3 command -command "" -label "Toggle Death" -state disabled
		.contextMenu delete 4
		.contextMenu insert 4 command -command "" -label "Set Reach" -state disabled
		.contextMenu delete 5
		.contextMenu insert 5 command -command "" -label "Toggle Spell Area" -state disabled
		.contextMenu delete 6
		.contextMenu insert 6 command -command "" -label "Polymorph" -state disabled
		.contextMenu delete 7
		.contextMenu insert 7 command -command "" -label "Change Size" -state disabled
		.contextMenu delete 8
		.contextMenu insert 8 command -command "" -label "Toggle Condition" -state disabled
		.contextMenu delete 9
		.contextMenu insert 9 command -command "" -label "Tag" -state disabled
		.contextMenu delete 10
		.contextMenu insert 10 command -command "" -label "Set Elevation" -state disabled
		.contextMenu delete 11
		.contextMenu insert 11 command -command "" -label "Set Movement Mode" -state disabled
		.contextMenu delete 14
		.contextMenu insert 14 command -command "" -label "Distance from..." -state disabled
		.contextMenu delete 16
		.contextMenu insert 16 command -command "" -label "Toggle Selection" -state disabled
	} elseif {[llength $mob_list] == 1} {
		set mob_id [lindex $mob_list 0]
		set mob_name [dict get $MOBdata($mob_id) Name]
		set mob_disp_name [::gmaclock::nameplate_text $mob_name]
		.contextMenu delete 0
		.contextMenu insert 0 command -command "RemovePerson $mob_id; ::gmaproto::clear $mob_id" -label "Remove [::gmaclock::nameplate_text [dict get $MOBdata($mob_id) Name]]"
		.contextMenu delete 3
		.contextMenu insert 3 command -command "KillPerson $mob_id" -label "Toggle Death for $mob_disp_name"
		.contextMenu delete 4
#		.contextMenu insert 4 command -command "ToggleReach $mob_id" -label "Cycle Reach for $mob_name"
		.contextMenu insert 4 cascade -menu [CreateReachSubMenu -shallow $mob_id] -label "Set Reach for $mob_disp_name"
		.contextMenu delete 5
		.contextMenu insert 5 command -command "ToggleSpellArea $mob_id" -label "Toggle Spell Area for $mob_disp_name"
		.contextMenu delete 6
		if {[AllowedToPolymorph $mob_id]} {
			.contextMenu insert 6 cascade -menu [CreatePolySubMenu -shallow $mob_id] -label "Polymorph $mob_disp_name"
		} else {
			.contextMenu insert 6 command -state disabled -label "Polymorph $mob_disp_name"
		}
		.contextMenu delete 7
		.contextMenu insert 7 cascade -menu [CreateSizeSubMenu -shallow $mob_id] -label "Change Size of $mob_disp_name"
		.contextMenu delete 8
		.contextMenu insert 8 cascade -menu [CreateConditionSubMenu -shallow $mob_id] -label "Toggle Condition for $mob_disp_name"
		.contextMenu delete 9
		.contextMenu insert 9 cascade -menu [CreateTagSubMenu -shallow $mob_id] -label "Tag $mob_disp_name"
		.contextMenu delete 10
		.contextMenu insert 10 cascade -menu [CreateElevationSubMenu -shallow $mob_id] -label "Set Elevation for $mob_disp_name"
		.contextMenu delete 11
		.contextMenu insert 11 cascade -menu [CreateMovementModeSubMenu -shallow $mob_id] -label "Set Movement Mode for $mob_disp_name"
		.contextMenu delete 14
		.contextMenu insert 14 command -command "DistanceFromMob $mob_id" -label "Distance from $mob_disp_name..."
		.contextMenu delete 16
		.contextMenu insert 16 command -command "ToggleSelection $mob_id" -label "Toggle Selection for $mob_disp_name"
	} else {
		.contextMenu.del delete 0 end
		.contextMenu.kill delete 0 end
		.contextMenu.reach delete 0 end
		.contextMenu.aoe delete 0 end
		.contextMenu.poly delete 0 end
		.contextMenu.size delete 0 end
		.contextMenu.tag delete 0 end
		.contextMenu.cond delete 0 end
		.contextMenu.elev delete 0 end
		.contextMenu.mmode delete 0 end
		.contextMenu.dist delete 0 end
		.contextMenu.tsel delete 0 end
		set polymorph_qty 0
		foreach mob_id $mob_list {
			set mob_name [dict get $MOBdata($mob_id) Name]
			set mob_disp_name [::gmaclock::nameplate_text $mob_name]
			.contextMenu.del add command -command "RemovePerson $mob_id; ::gmaproto::clear $mob_id" -label $mob_disp_name
			.contextMenu.kill add command -command "KillPerson $mob_id" -label $mob_disp_name
#			.contextMenu.reach add command -command "ToggleReach $mob_id" -label $mob_name
			.contextMenu.reach add cascade -menu [CreateReachSubMenu -deep $mob_id] -label $mob_disp_name
			.contextMenu.aoe add command -command "ToggleSpellArea $mob_id" -label $mob_disp_name
			if {[AllowedToPolymorph $mob_id]} {
				.contextMenu.poly add cascade -menu [CreatePolySubMenu -deep $mob_id] -label $mob_disp_name
				incr polymorph_qty
			} else {
				.contextMenu.poly add command -state disabled -label $mob_disp_name
			}

			.contextMenu.size add cascade -menu [CreateSizeSubMenu -deep $mob_id] -label $mob_disp_name
			.contextMenu.cond add cascade -menu [CreateConditionSubMenu -deep $mob_id] -label $mob_disp_name
			.contextMenu.tag add cascade -menu [CreateTagSubMenu -deep $mob_id] -label $mob_disp_name
			.contextMenu.elev add cascade -menu [CreateElevationSubMenu -deep $mob_id] -label $mob_disp_name
			.contextMenu.mmode add cascade -menu [CreateMovementModeSubMenu -deep $mob_id] -label $mob_disp_name
			.contextMenu.dist add command -command "DistanceFromMob $mob_id" -label $mob_disp_name
			.contextMenu.tsel add command -command "ToggleSelection $mob_id" -label $mob_disp_name
		}
		.contextMenu.del add command -command "RemoveAll $mob_list" -label "(all of the above)"
		.contextMenu.kill add command -command "KillAll $mob_list" -label "(all of the above)"
		.contextMenu.reach add cascade -menu [CreateReachSubMenu -mass $mob_list] -label "(all of the above)"
		if {$polymorph_qty > 1} {
			.contextMenu.poly add cascade -menu [CreatePolySubMenu -mass $mob_list] -label "(all of the above)"
		} else {
			.contextMenu.poly add command -state disabled -label "(all of the above)"
		}
		.contextMenu.size add cascade -menu [CreateSizeSubMenu -mass $mob_list] -label "(all of the above)"
		.contextMenu.tag add cascade -menu [CreateTagSubMenu -mass $mob_list] -label "(all of the above)"
		.contextMenu.cond add cascade -menu [CreateConditionSubMenu -mass $mob_list] -label "(all of the above)"
		.contextMenu.elev add cascade -menu [CreateElevationSubMenu -mass $mob_list] -label "(all of the above)"
		.contextMenu.mmode add cascade -menu [CreateMovementModeSubMenu -mass $mob_list] -label "(all of the above)"
		.contextMenu delete 0
		.contextMenu insert 0 cascade -menu .contextMenu.del -label "Remove"
		.contextMenu delete 3
		.contextMenu insert 3 cascade -menu .contextMenu.kill -label "Toggle Death"
		.contextMenu delete 4
		.contextMenu insert 4 cascade -menu .contextMenu.reach -label "Set Reach"
		.contextMenu delete 5
		.contextMenu insert 5 cascade -menu .contextMenu.aoe -label "Toggle Spell Area"
		.contextMenu delete 6
		.contextMenu insert 6 cascade -menu .contextMenu.poly -label "Polymorph"
		.contextMenu delete 7
		.contextMenu insert 7 cascade -menu .contextMenu.size -label "Change Size"
		.contextMenu delete 8
		.contextMenu insert 8 cascade -menu .contextMenu.cond -label "Toggle Condition"
		.contextMenu delete 9
		.contextMenu insert 9 cascade -menu .contextMenu.tag -label "Tag"
		.contextMenu delete 10
		.contextMenu insert 10 cascade -menu .contextMenu.elev -label "Set Elevation"
		.contextMenu delete 11
		.contextMenu insert 11 cascade -menu .contextMenu.mmode -label "Set Movement Mode"
		.contextMenu delete 14
		.contextMenu insert 14 cascade -menu .contextMenu.dist -label "Distance From..."
		.contextMenu delete 16
		.contextMenu insert 16 cascade -menu .contextMenu.tsel -label "Toggle Selection for"
	}

	set wx [expr [winfo rootx $canvas] + $x]
	set wy [expr [winfo rooty $canvas] + $y]
	DEBUG 3 "popup ($x,$y) -> ($wx,$wy)"
	tk_popup .contextMenu $wx $wy
}

proc MobNameComparison {a b} {
	global MOBdata
	return [string compare -nocase [dict get $MOBdata($a) Name] [dict get $MOBdata($b) Name]]
}

report_progress "Setting up UI: context menu"
menu .contextMenu -tearoff 0
menu .contextMenu.del -tearoff 0
menu .contextMenu.kill -tearoff 0
menu .contextMenu.reach -tearoff 0
menu .contextMenu.aoe -tearoff 0
menu .contextMenu.poly -tearoff 0
menu .contextMenu.size -tearoff 0
menu .contextMenu.tag -tearoff 0
menu .contextMenu.cond -tearoff 0
menu .contextMenu.elev -tearoff 0
menu .contextMenu.mmode -tearoff 0
menu .contextMenu.dist -tearoff 0
menu .contextMenu.tsel -tearoff 0
#menu .addPlayerMenu
.contextMenu add command -command "" -label Remove -state disabled					;# 0
.contextMenu add command -command {AddPlayerMenu player} -label {Add Player...}				;# 1
.contextMenu add command -command {AddPlayerMenu monster} -label {Add Monster...}			;# 2
.contextMenu add command -command "" -label {Toggle Death} -state disabled				;# 3
.contextMenu add command -command "" -label {Set Reach} -state disabled				;# 4
.contextMenu add command -command "" -label {Toggle Spell Area} -state disabled				;# 5
.contextMenu add command -command "" -label {Polymorph} -state disabled					;# 6
.contextMenu add command -command "" -label {Change Size} -state disabled				;# 7
.contextMenu add command -command "" -label {Toggle Condition} -state disabled				;# 8 
.contextMenu add command -command "" -label {Tag} -state disabled					;# 9 
.contextMenu add command -command "" -label {Elevation} -state disabled					;# 10
.contextMenu add command -command "" -label {Movement Mode} -state disabled				;# 11
.contextMenu add separator										;# 12
.contextMenu add command -command "" -label {Distance from...} -state disabled		 		;# 13 
.contextMenu add command -command "" -label {Distance from...} -state disabled				;# 14 
.contextMenu add separator										;# 15 
.contextMenu add command -command "" -label {Toggle Selection} -state disabled				;# 16 
.contextMenu add command -command "ClearSelection" -label {Deselect All} -state disabled		;# 17
#.contextMenu add command -command "FindNearby" -label {Scroll to Visible Objects}			;# 18 REMOVED
#.contextMenu add command -command "SyncView" -label {Scroll Others' Views to Match Mine}		;# 19 REMOVED
#.contextMenu add command -command "refreshScreen" -label {Refresh Display}				;# 20 REMOVED
#.contextMenu add command -command "aboutMapper" -label {About Mapper...}				;# 21 REMOVED
.contextMenu add separator										;# 18; was 22

# AddPlayer name color ?area? ?size? ?id?  defaults to 1x1, generated ID
#
# DEPRECATED
#proc AddPlayer {name color args} {
#	global MOB_X MOB_Y canvas
#
#	set g [ScreenXYToGridXY $MOB_X $MOB_Y]
#	# deprecated # if {[llength $args] > 0} { set area [lindex $args 0] } else { set area 1 }
#	if {[llength $args] > 1} { set size [lindex $args 1] } else { set size 1 }
#	if {[llength $args] > 2} { set id   [lindex $args 2] } else { set id [new_id] }
#	# XXX check for existing player
#	set d [::gmaproto::new_dict PS Gx [lindex $g 0] Gy [lindex $g 1] Color $color Name [AcceptCreatureImageName $name] Size $size CreatureType 2 ID $id]
#	DEBUG 3 "PlaceSomeone $canvas $d"
#	PlaceSomeone $canvas $d
#	::gmaproto::place_someone_d [InsertCreatureImageName $d]
#}

proc AddPlayerD {d} {
	global MOB_X MOB_Y canvas

	set g [ScreenXYToGridXY $MOB_X $MOB_Y]
	dict set d Name [AcceptCreatureImageName [dict get $d Name]]
	dict set d Gx [lindex $g 0]
	dict set d Gy [lindex $g 1]
	PlaceSomeone $canvas $d
	::gmaproto::place_someone_d [InsertCreatureImageName $d]
}

proc InsertCreatureImageName {d} {
	global MOB_IMAGE
	if {[info exists MOB_IMAGE([dict get $d Name])]} {
		return [dict replace $d Name "$MOB_IMAGE([dict get $d Name])=[dict get $d Name]"]
	}
	return $d
}

set MOB_Name {}
set MOB_SIZE M
# deprecated # set MOB_AREA M
set MOB_COLOR red
set MOB_REACH 0

proc AddElevationMenu {mob_id} {
	global NewElevationText
	set NewElevationText {}
	if {[::getstring::tk_getString .atm NewElevationText {Elevation:} -geometry [parent_geometry_ctr]]} {
		ElevatePerson $mob_id $NewElevationText
	}
}

proc AddElevationMenuAll {mob_list} {
	global NewElevationText
	set NewElevationText {}
	if {[::getstring::tk_getString .atm NewElevationText {Elevation:} -geometry [parent_geometry_ctr]]} {
		foreach person $mob_list {
			ElevatePerson $person $NewElevationText
		}
	}
}

proc AddTagMenu {mob_id} {
	global NewTagText
	set NewTagText {}
	if {[::getstring::tk_getString .atm NewTagText {Tag:} -geometry [parent_geometry_ctr]]} {
		TagPerson $mob_id $NewTagText
	}
}

proc AddTagMenuAll {mob_list} {
	global NewTagText
	set NewTagText {}
	if {[::getstring::tk_getString .atm NewTagText {Tag:} -geometry [parent_geometry_ctr]]} {
		foreach person $mob_list {
			TagPerson $person $NewTagText
		}
	}
}

# tile_id is {} if none set or  {name:zoom tilename zoom}
proc SetTilePlaceHolder {obj_id width height tile_id} {
	# Declare a placeholder for an image we don't have yet.
#	global OBJ TILE_ATTR
#	set TILE_ATTR(BBWIDTH:$tile_id) $width
#	set TILE_ATTR(BBHEIGHT:$tile_id) $height
#	set OBJ(_TILEID:$obj_id) $tile_id
	RefreshGrid 0
}

proc AddPlayerMenu {type} {
	global MOB_X MOB_Y canvas check_select_color
	global MOB_Name MOB_SIZE MOB_COLOR MOB_REACH
	# deprecated MOB_AREA

	#catch {destroy .apm}

	switch -exact -- $type {
		player  { set MOB_COLOR green }
		monster { set MOB_COLOR red   }
	}

	set g [ScreenXYToGridXY $MOB_X $MOB_Y]
	#toplevel .apm -class dialog
	create_dialog .apm
	wm title .apm "Add Player or Monster"

	grid [label .apm.lab1 -text {Name:}] 			   -row 0 -column 0 -sticky w
	grid [entry .apm.ent1 -textvariable MOB_Name -width 20] -  -row 0 -column 1 -sticky ew
	::tooltip::tooltip .apm.lab1 {[<image>=]<name>[ #<n>[-<m>]]}
	::tooltip::tooltip .apm.ent1 {[<image>=]<name>[ #<n>[-<m>]]}
	grid [label .apm.lab2 -text {Size Categories:}] 		   -row 1 -column 0 -sticky w
	grid [entry .apm.ent2 -textvariable MOB_SIZE -width 20] -  -row 1 -column 1 -sticky ew
	::tooltip::tooltip .apm.lab2 {<category>[<natural reach>][-><extended reach>][=<space>] [...(if multiple skins)]}
	::tooltip::tooltip .apm.ent2 {<category>[<natural reach>][-><extended reach>][=<space>] [...(if multiple skins)]}
	grid [label .apm.lab4 -text {Threat Zone Color:}] 	   -row 2 -column 0 -sticky w
	grid [entry .apm.ent4 -textvariable MOB_COLOR -width 20] - -row 2 -column 1 -sticky ew
	grid x [ttk::checkbutton .apm.ent5 -text {Extended Reach Active} -variable MOB_REACH] - -sticky w

	grid [button .apm.apply -command "AddMobFromMenu [lindex $g 0] [lindex $g 1] \$MOB_COLOR \$MOB_Name 0 \$MOB_SIZE $type \$MOB_REACH" -text Apply] -sticky w -row 4 -column 0
	grid [button .apm.cancel -command "destroy .apm" -text Cancel] -row 4 -column 1
	grid [button .apm.ok -command "AddMobFromMenu [lindex $g 0] [lindex $g 1] \$MOB_COLOR \$MOB_Name 0 \$MOB_SIZE $type \$MOB_REACH; destroy .apm" -text OK] -sticky e -row 4 -column 2
}

proc ValidateSizeCode {code} {
	if {[llength [CreatureSizeParams $code]] == 0} {
		return false
	}
	return true
}

proc AddMobFromMenu {baseX baseY color name _ sizesstr type reach} {
	global canvas
	global PC_IDs

	set sizes [split $sizesstr]
	foreach size $sizes {
		if {![ValidateSizeCode $size]} {
			say "Size value $size is not valid.  Specify number of squares or type code (upper-case for tall)."
			return
		}
	}

	#
	# names in the form [<image>=]<something>#<start>-<end> generate a block of MOBs
	#
	if {[regexp {(.+)#(\d+)-(\d+)} $name multipattern basename multistart multiend]} {
		for {set i $multistart; set XX 0} {$i <= $multiend} {incr i; incr XX} {
			if {$XX > 8} {
				set XX 0
				incr baseY
			}
			if {$i > $multistart} {
				set id [new_id]
			}
			set apm_id [new_id]
			DEBUG 3 "Multi-add $i of $multistart-$multiend: ${basename}#$i"
			set d [::gmaproto::new_dict PS Gx [expr $baseX+$XX] Gy $baseY Color $color Name [AcceptCreatureImageName "${basename}#$i"] SkinSize $sizes Skin 0 PolyGM false Size $size CreatureType [::gmaproto::to_enum CreatureType $type] ID $apm_id Reach $reach]
			PlaceSomeone $canvas $d
			::gmaproto::place_someone_d [InsertCreatureImageName $d]
		}
	} else {
		# 
		# If this is someone on our static list, use the known ID instead of making up
		# a new one. That really confuses things if we make up another one
		#
		set basename [AcceptCreatureImageName $name]
		if {[info exists PC_IDs($basename)]} {
			DEBUG 1 "User created player token manually for $basename; using pre-set ID of $PC_IDs($basename) for them."
			set apm_id $PC_IDs($basename)
		} else {
			set apm_id [new_id]
		}
		set d [::gmaproto::new_dict PS Gx $baseX Gy $baseY Color $color Name $basename Size $size SkinSize $sizes Skin 0 PolyGM false CreatureType [::gmaproto::to_enum CreatureType $type] ID $apm_id Reach $reach]
		PlaceSomeone $canvas $d
		::gmaproto::place_someone_d [InsertCreatureImageName $d]
	}
}

proc RemovePerson id {
	global canvas MOBdata MOBid MOB_SELECTED

	DEBUG 3 "RemovePerson $id"
	if {[animation_obj_exists $id]} {
		animation_destroy_instance $canvas * $id
	} 
	$canvas delete M#$id
	catch { unset MOBid([dict get $MOBdata($id) Name]) }
	catch { unset MOBdata($id) }
	catch { destroy $canvas.ms$id }
	catch { destroy $canvas.z$id }
	catch {	destroy $canvas.nt_$id }
	if {[info exists MOB_SELECTED($id)] && $MOB_SELECTED($id)} {
		set MOB_SELECTED($id) false
	}
}

proc KillAll args {
	foreach mob $args {
		KillPerson $mob
	}
}

proc RemoveAll args {
	foreach mob $args {
		RemovePerson $mob
		::gmaproto::clear $mob
	}
	# Since this is called when clearing all selected creatures, and those creatures will then cease
	# to exist, we shouldn't leave the selection list around pointing to bogus creatures.
	ClearSelection
}

proc KillPerson id {
	global canvas MOBdata

	dict set MOBdata($id) Killed [expr ![dict get $MOBdata($id) Killed]]
	RenderSomeone $canvas $id
	SendMobChanges $id Killed	
}

proc PolymorphPerson {id skin} {
	global MOBdata canvas
	dict set MOBdata($id) Skin $skin
	if {[llength [dict get $MOBdata($id) SkinSize]] > $skin} {
		ChangeRealSize $id [lindex [dict get $MOBdata($id) SkinSize] $skin]
	}
			
	RenderSomeone $canvas $id
	SendMobChanges $id {Skin Size DispSize}
}

proc PolymorphMass {mob_list skin} {
	foreach mob $mob_list {
		PolymorphPerson $mob $skin
	}
}

proc ChangeDispSize {id code} {
	global MOBdata canvas
	if {[string length $code] > 1} {
		dict set MOBdata($id) CustomReach Enabled false
	}
	dict set MOBdata($id) DispSize $code

	RenderSomeone $canvas $id
	SendMobChanges $id {DispSize}
}

proc ChangeRealSize {id code} {
	global MOBdata
	dict set MOBdata($id) Size $code
	ChangeDispSize $id $code
}

proc ChangeDispSizeAll {mob_list code} {
	foreach mob $mob_list {
		ChangeDispSize $mob $code
	}
}
#
# if a mob has a spell area highlighted, kill it.
# otherwise, set it now
#
proc ToggleSpellArea id {
	global MOBdata canvas

	if {[dict get $MOBdata($id) AoE] ne {}} {
		dict set MOBdata($id) AoE {}
		RenderSomeone $canvas $id
		SendMobChanges $id AoE
	} else {
		canceltool
		bind $canvas <1> "CompleteMOBAoE $id $canvas %x %y"
		bind $canvas <Motion> "DragMOBAoE $id $canvas %x %y"
		bind $canvas <B1-Motion> "DragMOBAoE $id $canvas %x %y"
		bind $canvas <B1-ButtonRelease> {}
	}
}

proc CompleteMOBAoE {id w x y} {
	canceltool
	$w delete AoElocator#$id
	SendMobChanges $id AoE
}

proc DragMOBAoE {id w x y} {
	global MOBdata iscale OBJ_COLOR

	set xx [SnapCoordAlways [$w canvasx $x]]
	set yy [SnapCoordAlways [$w canvasy $y]]
	set gx [CanvasToGrid $xx]
	set gy [CanvasToGrid $yy]
	set r  [GridDistance [dict get $MOBdata($id) Gx] [dict get $MOBdata($id) Gy] $gx $gy]
	dict set MOBdata($id) AoE [dict create Radius $r Color $OBJ_COLOR(fill)]
	RenderSomeone $w $id
	$w create line [expr [dict get $MOBdata($id) Gx] * $iscale] [expr [dict get $MOBdata($id) Gy] * $iscale] \
		[expr $gx * $iscale] [expr $gy * $iscale] \
		-fill black -width 3 -dash - -arrow last \
		-tags [list M#$id AoElocator#$id] -arrowshape [list 15 18  8]
}

proc ToggleReach id {
	global canvas MOBdata
	dict set MOBdata($id) Reach [expr ([dict get $MOBdata($id) Reach] + 1) % 3]
	RenderSomeone $canvas $id
	SendMobChanges $id Reach
}

proc clearplayers {pattern} {
	global MOBdata
	foreach id [array names MOBdata] {
		if {[string match $pattern [::gmaproto::from_enum CreatureType [dict get $MOBdata($id) CreatureType]]]} {
			RemovePerson $id
		}
	}
}


set KillObjID 0
set KillObjIdx 0
proc KillObjAdvance n {
	global KillObjID KillObjIdx canvas OBJ_BLINK OBJdata
	DEBUG 3 "BEGIN KillObjAdvance $n"

	set display_list [lsort -integer -command cmp_obj_attr_z [array names OBJdata]]
	DEBUG 3 "Display list is $display_list"
	if {[llength $display_list] == 0} {
		DEBUG 3 "Empty list; stopping"
		return
	}
	set k 0

	while {$k < 2} {
		DEBUG 3 "Pass $k"
		incr KillObjIdx $n
		DEBUG 3 "trying #$KillObjIdx ($n)"
		if {$KillObjIdx < 0} {
			incr k
			set KillObjIdx [expr [llength $display_list] - 1]
			DEBUG 3 "wrapped to $KillObjIdx; k=$k"
		} elseif {$KillObjIdx >= [llength $display_list]} {
			incr k
			set KillObjIdx 0
			DEBUG 3 "wrapped to $KillObjIdx; k=$k"
		} 
		set KillObjID [lindex $display_list $KillObjIdx]
		if {[dict get $OBJdata($KillObjID) Locked]} {
			DEBUG 3 "Element #$KillObjIdx ($KillObjID) is locked; skipping"
			continue
		}

		DEBUG 3 "Element #$KillObjIdx is $KillObjID"
		if {[info exists OBJdata($KillObjID)]} {
			DEBUG 3 "Setting $KillObjID to blink"
			set OBJ_BLINK $KillObjID
			blink $canvas $KillObjID 0
			return
		}
	}
	# no objects!
	DEBUG 3 "KillObjAdvance: giving up"
	set KillObjID 0
	set KillObjIdx 0
}

proc KillObj {which} {
	global KillObjID
	DEBUG 3 "KillObj $which"

	switch $which {
		prev    { KillObjAdvance -1 }
		next    { KillObjAdvance  1 }
		kill	{ 
			if {$KillObjID != 0} {
				KillObjById $KillObjID
				KillObjAdvance -1
			}
		}
	}
	DEBUG 3 "Kill $which; id=$KillObjID"
}

proc KillObjById {id args} {
	if {$args ne {-nosend}} {
		::gmaproto::clear $id
	}
	RemoveObject $id
}


menu .killmultiple -tearoff 0

proc KillObjUnderMouse {w x y} {
	set cx [$w canvasx $x]
	set cy [$w canvasy $y]
	set candidates {}
	global OBJdata OBJtype

	foreach element [$w find overlapping [expr $cx-2] [expr $cy-2] [expr $cx+2] [expr $cy+2]] {
		foreach elementTag [$w gettags $element] {
			if {[string range $elementTag 0 2] eq {obj}} {
				set target_id [string range $elementTag 3 end]
				if {[info exists OBJdata($target_id)] && [dict get $OBJdata($target_id) Locked]} {
					DEBUG 3 "Object $target_id is locked, not allowing in selection"
					continue
				}
				if {[lsearch -exact $candidates $target_id] < 0} {
					lappend candidates $target_id
				}
				break
			}
		}
	}
	if {[llength $candidates] == 1} {
		KillObjById $candidates
	} elseif {[llength $candidates] > 1} {
		global OBJdata
		.killmultiple delete 0 end
		foreach id $candidates {
			lassign [obj_line_fill_width $id] line fill width
			if {[dict exists $OBJdata($id) Text]} {
				set desc " \"[dict get $OBJdata($id) Text]\""
			} elseif {[dict exists $OBJdata($id) Image]} {
				set desc " \"[dict get $OBJdata($id) Image]\""
			} else {
				set desc ""
			}
			.killmultiple add command -command "KillObjById $id" -label "Delete $OBJtype($id) ($line/$fill)$desc @([dict get $OBJdata($id) X],[dict get $OBJdata($id) Y],[dict get $OBJdata($id) Z]; w=$width; \[[dict get $OBJdata($id) Layer]\]"
		}
		tk_popup .killmultiple [expr [winfo rootx $w] + $x] [expr [winfo rooty $w] + $y]
	}
}
	
proc obj_line_fill_width {id} {
	global OBJdata
	if {[info exists OBJdata($id)]} {
		::gmautil::dassign $OBJdata($id) Line l Fill f Width w
		if {$l eq {}} {set l {no line}}
		if {$f eq {}} {set f {no fill}}
		if {$w eq {}} {set w {no width}}
		return [list $l $f $w]
	}
	return [list N/A N/A N/A]
}

set MO_disp {}
set MO_last_obj {}
proc NudgeObject {w dx dy} {
	global MO_last_obj ClockDisplay
	global OBJdata OBJtype
	DEBUG 3 "NudgeObject w=$w dx=$dx dy=$dy obj=$MO_last_obj"
	if {$MO_last_obj eq {}} {
		set ClockDisplay "No current object to move; move one with mouse first"
		return
	}
	if {[info exists OBJdata($MO_last_obj)]} {
		if {$OBJtype($MO_last_obj) eq {aoe} || $OBJtype($MO_last_obj) eq {saoe}} {
			say "Nudging spell area of effect is not yet implemented."
			return
		}
		dict set OBJdata($MO_last_obj) X [expr [dict get $OBJdata($MO_last_obj) X] + $dx]
		dict set OBJdata($MO_last_obj) Y [expr [dict get $OBJdata($MO_last_obj) Y] + $dy]
		set new_coords {}
		set new_cobj {}
		foreach {xx yy} [$w coords obj$MO_last_obj] {
			lappend new_coords [expr $xx + $dx] [expr $yy + $dy]
			lappend new_cobj [dict create X [expr $xx + $dx] Y [expr $yy + $dy]]
		}
		if {[animation_obj_exists $MO_last_obj]} {
			animation_move_instance $w * $MO_last_obj $new_coords
		} 
		$w coords obj$MO_last_obj $new_coords
		dict set OBJdata($MO_last_obj) Points [lrange $new_cobj 1 end]
		SendObjChanges $MO_last_obj {X Y Points}
	} else {
		set ClockDisplay "Object $MO_last_obj does not exist anymore"
	}
}

proc NudgeObjectZ {w adj} {
	global MO_last_obj ClockDisplay
	global OBJdata
	DEBUG 3 "NudgeObjectZ w=$w adj=$adj obj=$MO_last_obj"
	if {$MO_last_obj eq {}} {
		set ClockDisplay "No current object to move; move one with mouse first"
		return
	}
	DEBUG 4 "NudgeObjectZ sampling object collection Z range"
	set max_z nil
	set min_z nil
	foreach ok [array names OBJdata] {
		set z [dict get $OBJdata($ok) Z]
		DEBUG 5 "-- $ok Z=$z"
		if {$max_z eq {nil}} {
			set min_z [set max_z $z]
		} else {
			if {$max_z == $z} {
				# We're not the only object at this coordinate so to be at max we'd have to be one past that
				set max_z [expr $z + 1]
			} elseif {$max_z < $z} {
				set max_z $z
			}
			if {$min_z == $z} {
				# We're not the only object at this coordinate so to be at min we'd have to be one past that
				set min_z [expr $z - 1]
			} elseif {$min_z > $z} {
				set min_z $z
			}
		}
	}
	DEBUG 4 "- Range is $min_z - $max_z"
	if {$min_z eq {nil}} {set min_z 0}
	if {$max_z eq {nil}} {set max_z 0}

	if {[info exists OBJdata($MO_last_obj)]} {
		set z [dict get $OBJdata($MO_last_obj) Z]
		switch -exact -- $adj {
			up { 
				if {$z >= $max_z} {
					set ClockDisplay "Object $MO_last_obj already top-most on display"
					return
				}
				dict set OBJdata($MO_last_obj) Z [expr $z + 1]
			}
			down {
				if {$z <= $min_z} {
					set ClockDisplay "Object $MO_last_obj already bottom-most on display"
					return
				}
				dict set OBJdata($MO_last_obj) Z [expr $z - 1]
			}
			front {
				if {$z >= $max_z} {
					set ClockDisplay "Object $MO_last_obj already top-most on display"
					return
				}
				dict set OBJdata($MO_last_obj) Z [expr $max_z + 1]
			}
			back {
				if {$z <= $min_z} {
					set ClockDisplay "Object $MO_last_obj already bottom-most on display"
					return
				}
				dict set OBJdata($MO_last_obj) Z [expr $min_z - 1]
			}
			default {
				DEBUG 0 "NudgeObjectZ $w $adj makes no sense"
				return
			}
		}

		refreshScreen
		set ClockDisplay "Object $MO_last_obj new Z=[dict get $OBJdata($MO_last_obj) Z]"
		SendObjChanges $MO_last_obj {Z}
	} else {
		set ClockDisplay "Object $MO_last_obj does not exist anymore"
	}
}

proc MoveObjUnderMouse {w x y} {
	set cx [$w canvasx $x]
	set cy [$w canvasy $y]
	set candidates {}
	global ClockDisplay MO_disp MO_last_obj OBJdata OBJtype
	set MO_disp $ClockDisplay

	foreach element [$w find overlapping [expr $cx-2] [expr $cy-2] [expr $cx+2] [expr $cy+2]] {
		foreach elementTag [$w gettags $element] {
			if {[string range $elementTag 0 2] eq {obj}} {
				set target_id [string range $elementTag 3 end]
				if {[info exists OBJdata($target_id)] && [dict get $OBJdata($target_id) Locked]} {
					DEBUG 3 "Object $target_id is locked, not allowing in selection"
					continue
				}
				if {[lsearch -exact $candidates $target_id] < 0} {
					lappend candidates $target_id
				}
				break
			}
		}
	}
	if {[llength $candidates] == 1} {
		set MO_last_obj $candidates
		MoveObjById $w $candidates
	} elseif {[llength $candidates] > 1} {
		global OBJdata
		global OBJ_MOVING_SELECTED

		if {$OBJ_MOVING_SELECTED ne {}} {
			set MO_last_obj $OBJ_MOVING_SELECTED
			MoveObjById $w $OBJ_MOVING_SELECTED
		} else {
			.killmultiple delete 0 end
			foreach id $candidates {
				lassign [obj_line_fill_width $id] line fill width
				.killmultiple add command -command "set OBJ_MOVING_SELECTED $id" -label "Move $OBJtype($id) ($line/$fill) @([dict get $OBJdata($id) X],[dict get $OBJdata($id) Y],[dict get $OBJdata($id) Z]); w=$width; \[[dict get $OBJdata($id) Layer]\]"
			}
			tk_popup .killmultiple [expr [winfo rootx $w] + $x] [expr [winfo rooty $w] + $y]
		}
	}
}
	

proc DrawScreen {scale show} {
	global canvas cansw cansh
	SquareGrid $canvas $cansw $cansh $show
}

proc blink {w t s} {
	global OBJ_BLINK OBJdata

	if {$OBJ_BLINK ne {} && $OBJ_BLINK==$t} {
		switch $s {
			0 { set fillcolor yellow }
			1 { set fillcolor red }
			2 { set fillcolor blue }
		}

		catch {
			$w itemconfigure obj$t -fill $fillcolor
			catch {$w itemconfigure obj$t -outline $fillcolor}
			after 100 "blink $w $t [expr ($s+1)%3]"
		}
	} else {
		catch {$w itemconfigure obj$t -outline [dict get $OBJdata($t) Line]}
		catch {$w itemconfigure obj$t -fill [dict get $OBJdata($t) Fill}
	}
}

# hightlightMob canvasname mob_id_list_or_empty_for_none
proc highlightMob {w id} {
	global MOBdata MOB_BLINK NextMOBID

	set MOB_BLINK $id

	set objectlist {}
	foreach obj_id [array names MOBdata] {
		if {![dict get $MOBdata($obj_id) Killed]} {
			if {[llength $id] == 0 || [lsearch -exact $id $obj_id] < 0} {
				# either we're setting everyone to normal, or
				# this is not highlighted person anyway
				dict set MOBdata($obj_id) Dim true
				$w itemconfigure MC#$obj_id -outline [dict get $MOBdata($obj_id) Color]
				$w delete MH#$obj_id
			} else {
				# this is the person
				dict set MOBdata($obj_id) Dim false
				$w itemconfigure MC#$obj_id -outline yellow
			}
		}
	}
	if {$id ne {}} {
		blinkMob $w $id 0
	}
}

proc FlashMob {w id step} {FlashGeneric $w $id $step MF#}
proc FlashElement {w id step} {FlashGeneric $w $id $step obj}
proc FlashGeneric {w id step pfx} {
	global _preferences
	if {![dict exists $_preferences flash_updates] || ![dict get $_preferences flash_updates]} {
		return
	}

  if {[catch {
	global animatePlacement
	DEBUG 3 "Flash* $w $id $step $pfx"
	set t [$w type $pfx$id]
	if {$t ne "rectangle" && $t ne "line" && $t ne "oval"} {
		# images can't be flashed by changing the fill colors. We need
		# to draw a rectangle over them and flash that
		if {[catch {
			switch $step {
				3 { $w create rectangle [$w bbox $pfx$id] -fill red -tags FFF$pfx$id }
				2 { $w itemconfigure FFF$pfx$id -fill yellow }
				1 { $w itemconfigure FFF$pfx$id -fill red }
				0 { 
					$w delete FFF$pfx$id 
					if {$pfx eq "MF#"} {
						RenderSomeone $w $id
					} else {
						RefreshGrid $animatePlacement
					}
				}
			}
		} err]} {
			DEBUG 1 "Error in FlashGeneric (image) {$w $id $step $pfx}: $err"
		}
	} else {
		if {[catch {
			switch $step {
				3 { $w itemconfigure $pfx$id -fill red    }
				2 { $w itemconfigure $pfx$id -fill yellow  }
				1 { $w itemconfigure $pfx$id -fill red     }
				0 { 
					if {$pfx eq "MF#"} {
						RenderSomeone $w $id
					} else {
						RefreshGrid $animatePlacement
					}
				}
			}
		} err]} {
			DEBUG 1 "Error in FlashGeneric (non-image [$w type $pfx$id]) {$w $id $step $pfx}: $err"
		}
	}
	update
	if {[incr step -1] >= 0} {
		after 80 "FlashGeneric $w $id $step $pfx"
	}
  } err]} {
    DEBUG 1 "Error in FlashGeneric (overall failure; args={w=$w, id=$id, step=$step, pfx=$pfx}; err=$err"
  }
}

proc blinkMob {w t s} {
	global MOB_BLINK MOBdata

	if {$MOB_BLINK ne {} && $MOB_BLINK eq $t} {
		switch $s {
			0 { set fillcolor #0000ff }
			1 { set fillcolor #00ff00 }
		}

		catch {
			foreach tt $t {
				$w itemconfigure MC#$tt -outline $fillcolor
			}
			after 100 "blinkMob $w [list $t] [expr ($s+1)%2]"
		}
	} else {
		catch {
			foreach tt $t {
				if {[dict get $MOBdata($tt) Dim]} {
					$w itemconfigure MC#$tt -outline [dict get $MOBdata($tt) Color]
				} else {
					$w itemconfigure MC#$tt -outline yellow
				}
			}
		}
	}
}



#
# file upload/download capability for map files
#

# fetch_map_file id						-- ensure we have <id> cached from server
#										   -> throws error if not successful
#										   -> NOSUCH if it's just not on server
#										   otherwise returns filename of cached file
# send_file_to_server id local_file		-- upload local file to server unconditionally
#										   -> throws error if can't send
#
# cache_map_id filename					-> server-side id expected for given filename
# cache_filename name zoom				-> expected path to cached image file
# cache_map_filename id					-> expected path to cached map file
# cache_info filename					-> {exists? age_in_days img_name/map_id zoom frame}
# load_cached_images					-- loads up all images from the cache unless too old
proc cache_map_id {filename} {
	# generate id from filename
	# as base 64 encoding of md5(base filename without extension) with +->_, /->-, drop =
	global ModuleID
	return [string map {+ _ / - = {}} [::base64::encode [::md5::md5 [concat $ModuleID [file rootname [file tail $filename]]]]]]
}
	
proc fetch_map_file {id} {
	global ClockDisplay
	global CURLproxy CURLpath CURLserver CURLinsecure
	global cache_too_old_days
	global my_stdout

	set oldcd $ClockDisplay
	set ClockDisplay "Getting map $id from server..."
	update

	set cache_filename [cache_map_filename $id]
	set cache_stats [cache_info $cache_filename]
	set cache_age 0
	set cache_newer_than 0
	#
	# Maybe the map is already here and recent enough...
	#
	DEBUG 2 "Fetching map file from server, id=$id"
	if {[lindex $cache_stats 0]} {
		set cache_age [lindex $cache_stats 1]
		DEBUG 3 "Found cache file for this map in $cache_filename, age=$cache_age"
		if {$cache_age < $cache_too_old_days} {
			DEBUG 3 "Cache is $cache_age days old, so we'll just use that"
			set ClockDisplay $oldcd
			return $cache_filename
		}
		set cache_newer_than [file mtime $cache_filename]
		DEBUG 3 "Cache is $cache_age days old, so we'll fetch a fresh copy if newer than [clock format $cache_newer_than]"
	} else {
		DEBUG 3 "No cache file found, fetching from server"
	}

	set url "$CURLserver/[string range $id 0 0]/[string range $id 0 1]/$id.map"
	#
	# On Windows, CURL can't create directories as needed because it thinks it has to try
	# to create C: first, which of course it can't do.
	# So we need to hold its little hand through this.
	#
	global tcl_platform
    set CreateOpt -s
	if {$tcl_platform(os) ne "Windows NT"} {
		set CreateOpt --create-dirs
	}
	set opts {}
	if {$CURLinsecure} {
		lappend opts -k
	}
	if {$CURLproxy ne {}} {
		lappend opts --proxy $CURLproxy
	}



	if {[catch {
		DEBUG 1 "Running $CURLpath $CreateOpt $opts --output [file nativename $cache_filename] -f -z [clock format $cache_newer_than] $url"
		flush stdout
		exec $CURLpath $CreateOpt {*}$opts --output [file nativename $cache_filename] -f -z [clock format $cache_newer_than] $url >&@$my_stdout
		DEBUG 3 "Updating cache file time"
		file mtime [file nativename $cache_filename] [clock seconds]
	} err options]} {
		set i [dict get $options -errorcode]
		if {[llength $i] >= 3 && [lindex $i 0] eq {CHILDSTATUS} && [lindex $i 2] == 22} {
			DEBUG 0 "Requested map file ID $id was not found on the server."
			set ClockDisplay $oldcd
			error NOSUCH
		} else {
			DEBUG 0 "Error running $CURLpath to get $url into $cache_filename: $err"
			set ClockDisplay $oldcd
			error "Failed to download map file ID $id from server: $err"
		}
	}
	refreshScreen
	set ClockDisplay $oldcd
	return $cache_filename
}

proc fetch_url {localdir local url} {
	global CURLproxy CURLpath CURLserver CURLinsecure
	global my_stdout

	set opts {}

	if {![file isdirectory $localdir]} {
		if {[file exists $localdir]} {
			tk_messageBox -parent . -type ok -icon error -title "Conflicting File Exists" \
				-message "We cannot complete the operation you requested becuase of a conflicting file."\
				-detail "We need to access the directory [file nativename $localdir], but it appears there is already a file with that name, so we can't make the directory we need."
			return {}
		} else {
			if {[catch {
				file mkdir $localdir
			} err]} {
				tk_messageBox -parent . -type ok -icon error -title "Unable to Create Directory" \
					-message "We cannot complete the operation you requested because we could not create a directory called [file nativename $localdir]."\
					-detail $err
				return {}
			}
		}
	}

	set dest [file join $localdir $local]
	if {$CURLproxy ne {}} {
		lappend opts --proxy $CURLproxy
	}
	if {$CURLinsecure} {
		lappend opts -k
	}
	if {[catch {
		DEBUG 1 "Running $CURLpath $opts --output [file nativename $dest] -f $url"
		exec $CURLpath {*}$opts --output [file nativename $dest] -f $url >&@$my_stdout
	} err options]} {
		set i [dict get $options -errorcode]
		if {[llength $i] >= 3 && [lindex $i 0] eq {CHILDSTATUS} && [lindex $i 2] == 22} {
			DEBUG 0 "Requested map file ID $id was not found on the server."
			tk_messageBox -parent . -type ok -icon error -title "Error Accessing Remote File" \
				-message "We cannot complete the operation you requested because we could not retrieve a remote file."\
				-detail "File not found."
			return {}
		} else {
			tk_messageBox -parent . -type ok -icon error -title "Error Accessing Remote File" \
				-message "We cannot complete the operation you requested because we could not retrieve a remote file."\
				-detail $err
			return {}
		}
	}
	if {[catch {
		set f [open $dest r]
		set d [read $f]
		close $f
	} err]} {
		tk_messageBox -parent . -type ok -icon error -title "Error Accessing Remote File" \
			-message "We cannot complete the operation you requested because we could not read the data we retrieved from the remote site."\
			-detail $err
		return {}
	}
	return $d
}

proc send_file_to_server {id local_file} {
	global SCPserver SCPdest SCPproxy SCPpath SSHpath NCpath SERVER_MKDIRpath
	global my_stdout

	if {$SCPdest eq {} || $SCPserver eq {}} {
		say "No upload server has been configured."
		return
	}

	set destdir "${SCPdest}/[string range $id 0 0]/[string range $id 0 1]"
	set destpath "${SCPserver}:${destdir}/$id.map"

	if {[catch {
		set st [file attributes $local_file -permissions]
		if {$st & 0111} {
			say "$local_file has execute permissions. Removing them and setting world read access."
			file attributes $local_file -permissions 0644
		} elseif {($st & 0444) != 0444} {
			say "$local_file isn't world-readable. Changing that now."
			file attributes $local_file -permissions 0644
		}
	} err]} {
		say "Failed to read or update file attributes for $local_file ($err). Proceeding but the transfer operation may fail as a result."
	}

	if {[catch {
		if {$SCPproxy ne {}} {
			DEBUG 1 "exec: $SSHpath -o \"ProxyCommand $NCpath -X 5 -x $SCPproxy %h %p\" $SCPserver $SERVER_MKDIRpath -p $destdir"
			exec $SSHpath -o "ProxyCommand $NCpath -X 5 -x $SCPproxy %h %p" $SCPserver $SERVER_MKDIRpath -p $destdir >&@$my_stdout
			DEBUG 1 "exec: $SCPpath -p -q -o \"ProxyCommand $NCpath -X 5 -x $SCPproxy %h %p\" $local_file $destpath"
			exec $SCPpath -p -q -o "ProxyCommand $NCpath -X 5 -x $SCPproxy %h %p" $local_file $destpath >&@$my_stdout
		} else {
			DEBUG 1 "exec: $SSHpath $SCPserver $SERVER_MKDIRpath -p $destdir"
			exec $SSHpath $SCPserver $SERVER_MKDIRpath -p $destdir >&@$my_stdout
			DEBUG 1 "exec: $SCPpath $local_file $destpath"
			exec $SCPpath $local_file $destpath >&@$my_stdout
		}
	} err]} {
		DEBUG 0 "Error running $SSHpath or $SCPpath for $local_file -> $destdir: $err"
	}
}
		
#
# load an image file from cache or the web server
#
proc fetch_image {name zoom id} {
	global ClockDisplay
	global ImageFormat
	global CURLproxy CURLpath CURLserver CURLinsecure
	global cache_too_old_days
	global my_stdout
	global forbidden_url

	set age $cache_too_old_days
	set oldcd $ClockDisplay
	set ClockDisplay "Getting image @$zoom from [string range $id 0 5]..."
	update

	set tile_id [tile_id $name $zoom]
	set cache_filename [cache_filename $name $zoom]
	set cache_stats [cache_info $cache_filename]
	set cache_age 0
	set cache_newer_than 0
	#
	# is the image already in our cache? If so, just load that unless
	# the cache is too old.
	#
	DEBUG 2 "Fetching image $name at zoom $zoom, id=$id"
	if {[lindex $cache_stats 0]} {
		set cache_age [lindex $cache_stats 1]
		DEBUG 3 "Found cache file for this image in $cache_filename, age=$cache_age"
		if {$cache_age < $age} {
			DEBUG 3 "Cache is $cache_age days old, so we'll just use that"
			create_image_from_file $tile_id $cache_filename
			set ClockDisplay $oldcd
			return
		}
		set cache_newer_than [file mtime $cache_filename]
		DEBUG 3 "Cache is [lindex $cache_stats 1] days old, so we'll fetch a fresh copy if newer than [clock format $cache_newer_than]"
	} else {
		DEBUG 3 "No cache file found, fetching from server"
	}
	global tcl_platform
	if {$tcl_platform(os) eq "Windows NT"} {
		set CreateOpt -s
	} else {
		set CreateOpt --create-dirs
	}
	set url "$CURLserver/[string range $id 0 0]/[string range $id 0 1]/$id.$ImageFormat"
	set opts {}
	if {$CURLproxy ne {}} {
		lappend opts --proxy $CURLproxy
	}
	if {$CURLinsecure} {
		lappend opts -k
	}
	if {[info exists forbidden_url($url)]} {
		DEBUG 1 "Not asking server for $url because we already got a 404 for that URL."
	} elseif {[catch {
		DEBUG 1 "Running $CURLpath $CreateOpt $opts --output [file nativename $cache_filename] -f -z [clock format $cache_newer_than] $url"
		exec $CURLpath $CreateOpt {*}$opts --output [file nativename $cache_filename] -f -z [clock format $cache_newer_than] $url >&@$my_stdout
		DEBUG 3 "Updating cache file time"
		file mtime [file nativename $cache_filename] [clock seconds]
	} err options]} {
		set i [dict get $options -errorcode]
		if {[llength $i] >= 3 && [lindex $i 0] eq {CHILDSTATUS} && [lindex $i 2] == 22} {
			DEBUG 0 "Requested image file ID $id was not found on the server. We will not ask for it again."
			DEBUG 1 "forbidding [format %s:%.2f $name $zoom]"
			set forbidden_url($url) 1
			set forbidden_url([format %s:%.2f $name $zoom]) 1
		} else {
			DEBUG 0 "Error running $CURLpath to get $url into $cache_filename: $err"
		}
	}
	create_image_from_file $tile_id $cache_filename
	set ClockDisplay $oldcd
	refreshScreen
}

#
# load an animated image file from cache or the web server
#
proc fetch_animated_image {name zoom id frames speed loops} {
	global ClockDisplay
	global ImageFormat
	global CURLproxy CURLpath CURLserver CURLinsecure
	global cache_too_old_days
	global my_stdout


	set age $cache_too_old_days
	set oldcd $ClockDisplay
	set ClockDisplay "Getting animated image @$zoom id [string range $id 0 5]..."
	update

	set tile_id [tile_id $name $zoom]
	set cache_age 0
	set cache_newer_than 0
	
	# TODO check if already exists??
	animation_init $tile_id $frames $speed $loops
	#
	# is the image already in our cache? If so, just load that unless
	# the cache is too old.
	#
	set cache_dirname [cache_file_dir $name $zoom 0]

	for {set n 0} {$n < $frames} {incr n} {
		set cache_filename [cache_filename $name $zoom $n]
		set cache_stats [cache_info $cache_filename]
		DEBUG 2 "Fetching image $name, frame $n at zoom $zoom, id=$id"

		if {[lindex $cache_stats 0]} {
			set cache_age [lindex $cache_stats 1]
			DEBUG 3 "Found cache file for this image frame in $cache_filename, age=$cache_age"

			if {$cache_age < $age} {
				DEBUG 3 "Cache is $cache_age days old, so we'll just use that"
				create_animated_frame_from_file $tile_id $n $cache_filename
				continue
			}
			set cache_newer_than [file mtime $cache_filename]
			DEBUG 3 "Cache is [lindex $cache_stats 1] days old, so we'll fetch a fresh copy if newer than [clock format $cache_newer_than]"
		} else {
			DEBUG 3 "No cache file found, fetching from server"
		}
		global tcl_platform
		if {$tcl_platform(os) eq "Windows NT"} {
		set CreateOpt -s
		} else {
			set CreateOpt --create-dirs
		}
		set url "$CURLserver/[string range $id 0 0]/[string range $id 0 1]/:$n:$id.$ImageFormat"
		set opts {}
		if {$CURLproxy ne {}} {
			lappend opts --proxy $CURLproxy
		}
		if {$CURLinsecure} {
			lappend opts -k
		}
		if {[catch {
			DEBUG 3 "Running $CURLpath $CreateOpt $opts --output [file nativename $cache_filename] -f -z [clock format $cache_newer_than] $url"
			exec $CURLpath $CreateOpt {*}$opts --output [file nativename $cache_filename] -f -z [clock format $cache_newer_than] $url >&@$my_stdout
			DEBUG 3 "Updating cache file time"
			file mtime [file nativename $cache_filename] [clock seconds]
		} err options]} {
			set i [dict get $options -errorcode]
			if {[llength $i] >= 3 && [lindex $i 0] eq {CHILDSTATUS} && [lindex $i 2] == 22} {
				DEBUG 0 "Requested image file ID :$n:$id was not found on the server."
			} else {
				DEBUG 0 "Error running $CURLpath to get $url into $cache_filename: $err"
			}
		}
		create_animated_frame_from_file $tile_id $n $cache_filename
	}
	if {[catch {
		set mf [open [file join $cache_dirname "${name}@[normalize_zoom ${zoom}].meta"] w]
		puts $mf [::gmaproto::json_from_dict AI [dict create \
			Name $name \
			Sizes [list [dict create \
				File $cache_dirname \
				Zoom $zoom \
				IsLocalFile true \
			]] \
			Animation [dict create \
				Frames $frames \
				FrameSpeed $speed \
				Loops $loops \
			]\
		]]
		close $mf
	} err]} {
		DEBUG 0 "Error writing cache metadata for $name at $zoom: $err"
	}
	set ClockDisplay $oldcd
	refreshScreen
}

#
# Initiative Link
#
# To set up, use the -h (and optionally -p) options
#
# The server you connect to will provide the following input:
#
# I {round count seconds minutes hours} playername/*Monsters*/{}
# L roomnamelist
# M roomnamelist
# TB state
# CO state
#
# the time list may in future append more elements than shown here
#


proc UpdateRunClock d {
	global MOB_COMBATMODE ClockDisplay
	if {$MOB_COMBATMODE} {
		set ClockDisplay [format "Round #%d  (%02d:%02d:%02d.%d)"\
			[expr [dict get $d Rounds] + 1]\
			[dict get $d Hours] \
			[dict get $d Minutes] \
			[dict get $d Seconds] \
			[expr [dict get $d Count] % 10]\
		]
	} else {
		set ClockDisplay {}
	}
}

proc BackgroundConnectToServer {tries} {
	::gmaproto::background_redial $tries
}

#
# Server interaction
#
#
# Hooks for specific incoming server messages
#

# simple commands
proc DoCommandCLR   {d} { ClearObjectById [dict get $d ObjID] }
proc DoCommandCO    {d} { setCombatMode [dict get $d Enabled] }
proc DoCommandMARCO {d} { ::gmaproto::polo }
proc DoCommandMARK  {d} { global canvas; start_ping_marker $canvas [dict get $d X] [dict get $d Y] 0 }

proc DoCommandDENIED {d} {
	tk_messageBox -parent . -type ok -icon error -title "Server Closed Connection" \
		-message "[dict get $d Reason]" \
		-detail "The server terminated your session due to the reason stated above. Please correct the cause of this problem before reconnecting."
	exit 1
}



proc DoCommandWORLD {d} {
	global ServerSideConfiguration
	if {[dict exists $d ClientSettings]} {
		set ServerSideConfiguration [dict get $d ClientSettings]
	} else {
		set ServerSideConfiguration {}
	}
	applyServerSideConfiguration
}


proc DoCommandECHO  {d} {
	if {[dict get $d s] eq "__spt__"} {
		_server_ping_reply $d
	}
}
proc DoCommandOA    {d} { 
	SetObjectAttribute [dict get $d ObjID] [dict get $d NewAttrs] 
	if {[::gmaclock::exists .initiative.clock]} {
		::gmaclock::track_health_change .initiative.clock $d
	}
}
proc DoCommandOA+   {d} { AddToObjectAttribute [dict get $d ObjID] [dict get $d AttrName] [dict get $d Values]; RefreshGrid 0; RefreshMOBs }
proc DoCommandOA-   {d} { RemoveFromObjectAttribute [dict get $d ObjID] [dict get $d AttrName] [dict get $d Values]; RefreshGrid 0; RefreshMOBs }
proc DoCommandTB    {d} { global MasterClient; if {!$MasterClient} {toolBarState [dict get $d Enabled]} }

proc DoCommandAV {d} { 
	if {[set grid_label [dict get $d Grid]] ne {}} {
		ScrollToGridLabel $grid_label
	} else {
		AdjustView [dict get $d XView] [dict get $d YView] 
	}
}

proc DoCommandPRIV {d} {
	tk_messageBox -parent . -type ok -icon error -title "Permission Denied" \
		-message "[dict get $d Reason]" \
		-detail "The operation you attempted to carry out which sent the command shown here is only allowed for privileged users, and in the words of Chevy Chase, \"you're not.\"\n\nAttempted command:\n[dict get $d Command]"
}

proc DoCommandTMRQ {d} {
	# clients ignore these upon receipt
}

proc DoCommandTMACK {d} {
	# Acknowledge our timer request. If we're still showing a request dialog, update/dismiss it
	# based on RequestID field
	itr_accepted [dict get $d RequestID]
}

proc DoCommandHPACK {d} {
	# Acknowledge our timer request. If we're still showing a request dialog, update/dismiss it
	# based on RequestID field
	ihr_accepted [dict get $d RequestID]
}

proc DoCommandFAILED {d} {
	# Indicate general failure. If we're still showing a timer request dialog, update it based on
	# IsError, IsDiscretionary, Reason, ReqeustID
	# also: Command
	if {[string range [dict get $d Command] 0 3] eq "TMRQ"} {
		itr_failed [dict get $d RequestID] [dict get $d Reason]
	} elseif {[string range [dict get $d Command] 0 4] eq "HPREQ"} {
		ihr_failed [dict get $d RequestID] [dict get $d Reason]
	} else {
		tk_messageBox -parent . -type ok -icon error -title "Operation Failed" \
			-message "[dict get $d Reason]"
	}
}

proc DoCommandCS {d} {
	global time_abs
	global time_rel
	set args {}
	set time_abs [dict get $d Absolute]
	set time_rel [dict get $d Relative]
	if {[dict get $d Running]} {
		lappend args -running
	}
	if {[::gmaclock::exists .initiative.clock]} {
		::gmaclock::update_time .initiative.clock $time_abs $time_rel {*}$args
	}
}

proc DoCommandIL {d} {
	if {[::gmaclock::exists .initiative.clock]} {
		::gmaclock::set_initiative_slots .initiative.clock [dict get $d InitiativeList]
	}
}

# given a creature dict, enforce the new protocol specs in a backward-compatible way
# so that the Size field contains the value from SkinSize indexed by Skin if those
# are set.
# If SkinSize is empty, set it with the Size field.
# The updated dictionary value is returned.
proc _adjust_creature_sizes {d} {
	set idx [dict get $d Skin]
	if {[llength [set sizes [dict get $d SkinSize]]] > 0} {
		if {$idx < 0 || $idx >= [llength $sizes]} {
			set idx 0
		}
		dict set d Size [lindex $sizes $idx]
		dict set d Skin $idx
	} else {
		dict set d Skin 0
		dict set d SkinSize [list [dict get $d Size]]
	}
	return $d
}

proc DoCommandAC {d} {
	# Add character to the menu
	global PC_IDs
	set d [_adjust_creature_sizes $d]
	set creature_name [AcceptCreatureImageName [dict get $d Name]]
	set id [dict get $d ID]

	if {[info exists PC_IDs($creature_name)]} {
		if {$PC_IDs($creature_name) ne $id} {
			DEBUG 0 "Attempting to add player '$creature_name' with ID $id to menu but ID $PC_IDs($creature_name) is already known for it! Ignoring new request."
		} else {
			DEBUG 1 "Received duplicate AC command for $creature_name (ID $id)"
		}
	} else {
		set PC_IDs($creature_name) $id
		.contextMenu add command -command "AddPlayerD [list $d]" -label $creature_name 
	}
}

# read animation metadata from cache file
proc animation_read_metadata {cachedir name zoom} {
	set f [open [file join $cachedir "${name}@[normalize_zoom ${zoom}].meta"] r]
	set data [read $f]
	close $f
	puts "calling new_dict_from_json command=AI data=($data)"
	return [::gmaproto::new_dict_from_json AI $data]
}

# Create animated image stack on the canvas with the first frame visible
# animation_create canvas x y tid oid ?-start?
proc animation_create {canvas x y tileID objID args} {
	global TILE_ANIMATION

	if {![info exists TILE_ANIMATION($tileID,img,0)] || $TILE_ANIMATION($tileID,img,0) eq {}} {
		DEBUG 1 "Unable to create non-existent animated image $tileID"
		return
	}
	for {set n 0} {$n < $TILE_ANIMATION($tileID,frames)} {incr n} {
		set TILE_ANIMATION($tileID,id,$objID,$n) [\
			$canvas create image $x $y -anchor nw -image $TILE_ANIMATION($tileID,img,$n) \
				-tags [list tiles obj$objID allOBJ animatedTiles]\
				-state [expr $n == 0 ? {{normal}} : {{hidden}}]\
		]
	}
	if {[lsearch -exact $args "-start"] >= 0} {
		animation_start $canvas -tile $tileID
	}
}

proc animation_newid {tileID frameno objID canID} {
	global TILE_ANIMATION
	set TILE_ANIMATION($tileID,id,$objID,$frameno) $canID
}

proc animation_start {canvas opt args} {
	global TILE_ANIMATION
	global _preferences

	if {[dict get $_preferences never_animate]} {
		return
	}

	if {$opt eq "-tile"} {
		set idlist $args
	} elseif {$opt eq "-all"} {
		set idlist {}
		foreach k [array names TILE_ANIMATION -glob "*,frames"] {
			lappend idlist [string range $k 0 end-7]
		}
	} elseif {$opt eq "-unexpired"} {
		set idlist {}
		foreach k [array names TILE_ANIMATION -glob "*,frames"] {
			set id [string range $k 0 end-7]
			if {$TILE_ANIMATION($id,loops) == 0 || $TILE_ANIMATION($id,loop) < $TILE_ANIMATION($id,loops)} {
				lappend idlist $id
			}
		}
	} else {
		error "animation_start: invalid option $opt: must be -tile, -unexpired, or -all"
	}

	foreach id $idlist {
		if {$TILE_ANIMATION($id,task) eq {}} {
			set TILE_ANIMATION($id,current) 0
			set TILE_ANIMATION($id,loop) 0
			set TILE_ANIMATION($id,task) [after $TILE_ANIMATION($id,delay) "_animation_next_frame [list $id $canvas]"]
		}
	}
}

proc _animation_next_frame {id canvas} {
	global TILE_ANIMATION
	global _preferences

	if {[dict get $_preferences never_animate]} {
		animation_stop -all
		return
	}

	if {$TILE_ANIMATION($id,task) ne {}} {
		foreach k [array names TILE_ANIMATION "$id,id,*,$TILE_ANIMATION($id,current)"] {
			$canvas itemconfigure $TILE_ANIMATION($k) -state hidden
		}
		if {[incr TILE_ANIMATION($id,current)] >= $TILE_ANIMATION($id,frames)} {
			set TILE_ANIMATION($id,current) 0
			if {$TILE_ANIMATION($id,loops) > 0 && [incr TILE_ANIMATION($id,loop)] >= $TILE_ANIMATION($id,loops)} {
				# stop here
				foreach k [array names TILE_ANIMATION "$id,id,*,0"] {
					$canvas itemconfigure $TILE_ANIMATION($k) -state normal
				}
				set TILE_ANIMATION($id,task) {}
				return
			}
		}
		foreach k [array names TILE_ANIMATION "$id,id,*,$TILE_ANIMATION($id,current)"] {
			$canvas itemconfigure $TILE_ANIMATION($k) -state normal
		}
		set TILE_ANIMATION($id,task) [after $TILE_ANIMATION($id,delay) "_animation_next_frame [list $id $canvas]"]
	}
}

proc animation_obj_exists {objID} {
	global TILE_ANIMATION
	return [expr [llength [array names TILE_ANIMATION "*,id,$objID,*"]] != 0]
}

# destroy all information about the given animated images
proc animation_destroy_instance {canvas tileID objID} {
	global TILE_ANIMATION

	$canvas delete {*}[lmap {k v} [array get TILE_ANIMATION "$tileID,id,$objID,*"] {set v}]
	array unset TILE_ANIMATION "$tileID,id,$objID,*"
}

proc animation_move_instance {canvas tileID objID new_coords} {
	global TILE_ANIMATION
	foreach {k v} [array get TILE_ANIMATION "$tileID,id,$objID,*"] {
		$canvas coords $v $new_coords
	}
}

proc animation_destroy {opt args} {
	global TILE_ANIMATION

	if {$opt eq "-tile"} {
		set idlist $args
	} elseif {$opt eq "-all"} {
		set idlist {}
		foreach k [array names TILE_ANIMATION -glob "*,frames"] {
			lappend idlist [string range $k 0 end-7]
		}
	} else {
		error "animation_destroy: invalid option $opt: must be -tile or -all"
	}

	foreach id $idlist {
		animation_clear_frames $id
		array unset TILE_ANIMATION "$id,*"
	}
}

proc animation_stop {opt args} {
	global TILE_ANIMATION

	if {$opt eq "-tile"} {
		set idlist $args
	} elseif {$opt eq "-all"} {
		set idlist {}
		foreach k [array names TILE_ANIMATION -glob "*,task"] {
			lappend idlist [string range $k 0 end-5]
		}
	} else {
		error "animation_stop: invalid option $opt: must be -tile or -all"
	}

	foreach id $idlist {
		if {[info exists TILE_ANIMATION($id,task)] && [set task $TILE_ANIMATION($id,task)] ne {}} {
			after cancel $task
			set TILE_ANIMATION($id,task) {}
		}
	}
}

# destroy all tk images for a given animated tile
proc animation_clear_frames {tileID} {
	global TILE_ANIMATION

	animation_stop -tile $tileID
	foreach k [array names TILE_ANIMATION -glob "$tileID,img,*"] {
		image delete $TILE_ANIMATION($k)
		set TILE_ANIMATION($k) {}
	}
}

# add tk image for frame n
proc animation_add_frame {tileID n img} {
	global TILE_ANIMATION

	if {[info exists TILE_ANIMATION($tileID,img,$n)] && [set tki $TILE_ANIMATION($tileID,img,$n)] ne {}} {
		image delete $tki
	}
	set TILE_ANIMATION($tileID,img,$n) $img
}

proc animation_init {tileID frames speed loops} {
	global TILE_ANIMATION

	animation_stop -tile $tileID
	array unset TILE_ANIMATION "$tileID,*"
	set TILE_ANIMATION($tileID,frames) $frames
	set TILE_ANIMATION($tileID,current) 0
	set TILE_ANIMATION($tileID,delay) $speed
	set TILE_ANIMATION($tileID,loops) $loops
	set TILE_ANIMATION($tileID,loop) 0
	set TILE_ANIMATION($tileID,task) {}
	for {set n 0} {$n < $frames} {incr n} {
		set TILE_ANIMATION($tileID,img,$n) {}
	}
}

proc _load_local_animated_file {path name zoom aframes aspeed aloops} {
	global ImageFormat

	set path_components [file split $path]
	set t_id [tile_id $name $zoom]
	animation_init $t_id $aframes $aspeed $aloops
	animation_clear_frames $t_id

	for {set n 0} {$n < $aframes} {incr n} {
		if {[catch {
			set fname [file join {*}[lrange $path_components 0 end-1] ":$n:[lindex $path_components end]"]
			DEBUG 2 "Opening local animation frame file $fname"
			set f [open $fname r]
			fconfigure $f -encoding binary -translation binary
			set raw_data [read $f]
			close $f
		} err]} {
			error "Unable to load image file :$n:$path: $err"
		}
		animation_add_frame $t_id $n [image create photo -format $ImageFormat -data $raw_data]
	}
}

proc DoCommandAI {d} {
	# add image
	global ImageFormat
	if {[dict get $d Animation] eq {}} {
		set aframes 0
		set aspeed 0
		set aloops 0
	} else {
		::gmautil::dassign $d {Animation Frames} aframes {Animation FrameSpeed} aspeed {Animation Loops} aloops
	}
	::gmautil::dassign $d Name name
	foreach instance [dict get $d Sizes] {
		::gmautil::dassign $instance File server_id ImageData raw_data IsLocalFile localp Zoom zoom
		if {$raw_data ne {} && $aframes > 0} {
			error "incoming image $server_id: inline data not supported for animated images"
		}
		if {$raw_data eq {} && $localp} {
			DEBUG 2 "Loading local image file $server_id for $name @$zoom"
			if {$aframes > 0} {
				_load_local_animated_file $server_id $name $zoom $aframes $aspeed $aloops
				continue
			}
			if {[catch {
				set f [open $server_id r]
				fconfigure $f -encoding binary -translation binary
				set raw_data [read $f]
				close $f
			} err]} {
				error "Unable to load image file $server_id: $err"
			}
		} 

		if {$raw_data ne {}} {
			DEBUG 2 "Received binary image data for $name @$zoom"

			global TILE_SET
			set t_id [tile_id $name $zoom]
			if {[info exists TILE_SET($t_id)]} {
				DEBUG 1 "Replacing existing image $TILE_SET($t_id) for ${name} x$zoom"
				image delete $TILE_SET($t_id)
				unset TILE_SET($t_id)
			}
			set TILE_SET($t_id) [image create photo -format $ImageFormat -data $raw_data]
			DEBUG 3 "Defined bitmap for $name at $zoom: $TILE_SET($t_id)"
		} else {
			DEBUG 2 "Caching copy of server image $server_id for $name @$zoom"
			if {$aframes > 0} {
				fetch_animated_image $name $zoom $server_id $aframes $aspeed $aloops
			} else {
				fetch_image $name $zoom $server_id
			}
		}
	}
	update
}

proc DoCommandAI? {d} {
	# query: Do we know where to find an image?
	global TILE_ID

	set name [dict get $d Name]
	foreach instance [dict get $d Sizes] {
		set zoom [dict get $instance Zoom]
		if {[info exists TILE_ID([tile_id $name $zoom])]} {
			# yes, we do! let everyone else know
			::gmaproto::add_image $name [list [dict create \
				File        $TILE_ID([tile_id $name $zoom]) \
				IsLocalFile false \
				Zoom        $zoom \
			]]
		}
	}
}

proc DoCommandCC {d} {
	# clear chat history
	if {[dict get $d DoSilently]} {
		set by {}
	} else {
		set by [dict get $d RequestedBy]
	}

	ClearChatHistory $d
	ChatHistoryAppend [list CC $d [dict get $d MessageID]]
	LoadChatHistory
}

proc DoCommandCLR@ {d} {
	if {[dict get $d IsLocalFile]} {
		set cache_filename [dict get $d File]
	} else {
		if {[catch {set cache_filename [fetch_map_file [dict get $d File]]} err]} {
			if {$err eq {NOSUCH}} {
				DEBUG 0 "WARNING: Requested unload of File ID [dict get $d File] but the server doesn't have it."
			} else {
				error "Error retrieving file ID [dict get $d File] from server: $err"
			}
			return
		}
	}

	global SafMode
	if {$SafMode} {
		toggleSafMode
	}
	unloadfile $cache_filename -nosend -force
}

proc DoCommandCONN {d} {
	global local_user PeerList
	set PeerList {}

	foreach peer [dict get $d PeerList] {
		::gmautil::dassign $peer User peer_user

		if {[dict get $peer IsMe] && $peer_user ne $local_user} {
			set local_user $peer_user
			DEBUG 1 "Correcting my local username to $local_user per server request"
		}
		if {[dict get $peer IsAuthenticated]} {
			if {$peer_user ne {} && $peer_user ne {None}} {
				# we check for "None" because of the behavior of the Python server (sigh)
				if {$peer_user ne $local_user} {
					lappend PeerList $peer_user
					DEBUG 3 "Peerlist=$PeerList"
				} else {
					DEBUG 2 "Excluding $peer (this is my username)"
				}
			} else {
				DEBUG 2 "Excluding $peer (no username given)"
			}
		} else {
			DEBUG 2 "Excluding $peer (not authenticated)"
		}
	}
	global dice_preset_data
	foreach rkey [array names dice_preset_data "cw,*"] {
		set tkey [string range $rkey 3 end]
		set for_user $dice_preset_data(user,$tkey)
		UpdatePeerList $for_user $tkey
	}
}

proc DoCommandDD= {d} {
	# define die-roll preset list (updates us from the server's stored presets)
	global SuppressChat dice_preset_data local_user
	
	if {[set target [dict get $d For]] eq {}} {
		set target $local_user
	}

	# w,userid,presetname		widgetid
	# preset,userid,presetname	user preset
	# sys,preset,presetname		globals
	# delegates,userid
	# delegate_for,userid
	if {! $SuppressChat} {
		if {[catch {
			DisplayChatMessage {} $target
			set tkey [user_key $target]
			foreach k [array names dice_preset_data -glob "w,$tkey,*"] {
				set w $dice_preset_data($k)
				DEBUG 1 "destroy $w preset widget"
				destroy $w
			}
			array unset dice_preset_data "sys,preset,*"
			array unset dice_preset_data "w,$tkey,*"
			if {[dict exists $d Global] && [dict get $d Global]} {
				set global_only true
			} else {
				set global_only false
				# if we're not just receiving the global list, remove our locals since we're reloading them too
				array unset dice_preset_data "preset,$tkey,*"
			}
			# NO, don't do this every time or you'll keep getting enabled presets
			# setting themselves on anytime the presets are refreshed.
			# --- array unset dice_preset_data "en,$tkey,*"
			array unset dice_preset_data "delegates,$tkey"
			array unset dice_preset_data "delegate_for,$tkey"
			# TODO array unset dice_preset_data "recent_die_rolls,$tkey" ??
			# TODO array unset DieRollPresetState $tkey,* ??
			foreach preset [dict get $d Presets] {
				if {$global_only || ([dict exists $preset Global] && [dict get $preset Global])} {
					set dice_preset_data(sys,preset,[dict get $preset Name]) $preset
				} else {
					set dice_preset_data(preset,$tkey,[dict get $preset Name]) $preset
				}
			}
			set dice_preset_data(delegates,$tkey) [dict get $d Delegates]
			set dice_preset_data(delegate_for,$tkey) [dict get $d DelegateFor]
			set wp [sframe content $dice_preset_data(cw,$tkey).p.preset.sf]
			_render_die_roller $wp 0 0 preset $target $tkey -noclear
		} err]} {
			DEBUG 0 "Error updating die preset info for $target: $err"
		}
	}
	after 500 {_update_delegate_list .delegates}
}

proc DoCommandDSM {d} {
	# define status marker
	::gmautil::dassign $d Condition condition Shape shape Color color Description description Transparent transparent
	global MarkerColor MarkerShape MarkerDescription MarkerTransparent

	if {$shape eq {} || $color eq {}} {
		array unset MarkerColor $condition
		array unset MarkerShape $condition
		array unset MarkerTransparent $condition
		array unset MarkerDescription $condition
	} else {
		set MarkerTransparent($condition) $transparent
		set MarkerColor($condition) $color
		set MarkerShape($condition) $shape
		if {$description eq {}} {
			if {![info exists MarkerDescription($condition)]} {
				set MarkerDescription($condition) $condition
			}
		} else {
			set MarkerDescription($condition) $description
		}
	}
}

proc DoCommandI {d} {
	# update initiative clock
	global MOB_COMBATMODE canvas MOB_BLINK NextMOBID MOBdata MOBid
	global CombatantScrollEnabled is_GM
	set ITlist {}

	if {$MOB_COMBATMODE} {
		UpdateRunClock $d

		if {[set actor [dict get $d ActorID]] eq {*Monsters*}} {
			foreach {mob_id mob} [array get MOBdata] {
				if {[dict get $mob CreatureType] == 1 && ![dict get $mob Killed]} {
					lappend ITlist $mob_id
				}
			}
		} else {
			if {[info exists MOBdata($actor)]} {
				set mob_id $actor;		# actor is the mob ID
			} elseif {[info exists MOBid($actor)]} {
				set mob_id $MOBid($actor);	# actor is the mob name
			} elseif {[string range $actor 0 0] eq {/}} {
				set mob_id {};			# actor is a regex of names
				foreach key [array names MOBid -regexp [string range $actor 1 end]] {
					if {![dict get $MOBdata($MOBid($key)) Killed]} {
						lappend ITlist $MOBid($key)
					}
				}
			} else {
				set mob_id {};			# non-existent actor ID
			}

			global CombatantSelected
			if {$mob_id ne {} && [info exists MOBdata($mob_id)] && ![dict get $MOBdata($mob_id) Killed]} {
				set CombatantSelected $mob_id
				lappend ITlist $mob_id
				if {$CombatantScrollEnabled && (![dict get $MOBdata($mob_id) Hidden] || $is_GM)} {
					ScrollToCenterScreenXY [GridToCanvas [dict get $MOBdata($mob_id) Gx]] \
							       [GridToCanvas [dict get $MOBdata($mob_id) Gy]]
				}
			} else {
				set CombatantSelected {}
			}
		}
	}

 	set MOB_BLINK $ITlist
 	highlightMob $canvas $ITlist
 	foreach id $ITlist {
 		PopSomeoneToFront $canvas $id
 	}
}

proc DoCommandL {d} {
	# load map file
	if {[dict get $d CacheOnly]} {
		# just make sure we have a copy on hand (M?)
		if {[dict get $d IsLocalFile]} {
			DEBUG 1 "Server asked us to cache [dict get $d File], but it's a local file (request ignored)"
			return
		}
		if {[catch {fetch_map_file [dict get $d File]} err]} {
			if {$err eq {NOSUCH}} {
				DEBUG 0 "WARNING: Requested pre-load of server file ID [dict get $d File] but the server doesn't have it."
			} else {
				error "Error retrieving server file ID [dict get $d File]: $err"
			}
		}
		return
	}
	if {[dict get $d IsLocalFile]} {
		# use local file (L)
		set file_to_load [dict get $d File]
	} else {
		# fetch server file (unless we already have it cached) (M@)
		if {[catch {set file_to_load [fetch_map_file [dict get $d File]]} err]} {
			if {$err eq {NOSUCH}} {
				DEBUG 0 "WARNING: Requested load of server file ID [dict get $d File] but the server doesn't have it."
			} else {
				error "Error retrieving server file ID [dict get $d File]: $err"
			}
		}
	}
	
	global SafMode
	if {$SafMode} {
		toggleSafMode
	}

	if {[dict get $d Merge]} {
		loadfile $file_to_load -force -merge -nosend;	# M@ M
	} else {
		loadfile $file_to_load -force -nosend;		# L
	}
}

proc DoCommandLS-ARC  {d} {DoLS arc $d}
proc DoCommandLS-CIRC {d} {DoLS circ $d}
proc DoCommandLS-LINE {d} {DoLS line $d}
proc DoCommandLS-POLY {d} {DoLS poly $d}
proc DoCommandLS-RECT {d} {DoLS rect $d}
proc DoCommandLS-SAOE {d} {DoLS aoe $d}
proc DoCommandLS-TEXT {d} {DoLS text $d}
proc DoCommandLS-TILE {d} {DoLS tile $d}
proc DoLS {t d} {
	# load map elements (generic handler for all element types)
	global OBJdata OBJtype
	#DEBUG 0 "Drawing type=$t, data=$d"
	set OBJdata([dict get $d ID]) $d
	set OBJtype([dict get $d ID]) $t
	RefreshGrid false
	RefreshMOBs
	update
}

proc create_timer_widget {id} {
	global timer_progress_data
	global TimerScope
	global local_user

	if {$TimerScope eq "none"} {
		DEBUG 1 "Not showing timer $id because timer display is turned off."
		return
	}
	if {$TimerScope eq "mine" && [lsearch -exact $timer_progress_data(targets:$id) $local_user] < 0} {
		DEBUG 1 "Not showing timer $id because $local_user is not in $timer_progress_data(targets:$id)"
		return
	}

	set wid [to_window_id $id]

	if {[winfo exists .initiative]} {
		pack [progressbar .initiative.clock.timers.$wid -label timer] -side top -fill x -expand 0
		::gmaclock::autosize .initiative.clock
		return .initiative.clock.timers.$wid
	} else {
		return {}
	}
}

proc populate_timer_widgets {} {
	global timer_progress_data
	if {[winfo exists .initiative]} {
		foreach k [array names timer_progress_data w:*] {
			set id [string range $k 2 end]
			if {[info exists timer_progress_data($k)] && $timer_progress_data($k) ne {}} {
				catch {destroy $timer_progress_data($k)}
			}
			set timer_progress_data($k) [create_timer_widget $id]
			update_timer_widget $id
		}
		::gmaclock::autosize .initiative.clock
	}
}

proc update_timer_widget {id} {
	global timer_progress_data
	if {[winfo exists .initiative] && [info exists timer_progress_data(w:$id)] && $timer_progress_data(w:$id) ne {}} {
		if {![info exists timer_progress_data(max:$id)] || $timer_progress_data(max:$id) == 0} {
			$timer_progress_data(w:$id) unknown
		} elseif {![info exists timer_progress_data(value:$id)] || $timer_progress_data(value:$id) <= 0} {
			$timer_progress_data(w:$id) expired
		} else {
			$timer_progress_data(w:$id) set [expr int($timer_progress_data(value:$id) * 100.0 / $timer_progress_data(max:$id))] $timer_progress_data(title:$id)
		}
	}
}

proc DoCommandPROGRESS {d} {
	global progress_data
	global timer_progress_data

	# If we're tracking a timer, we handle it differently from the other progress meters.
	# Those are placed on the initiative timer window but are subject to user filtering
	# options. We track their status even if the user dismissed them (so we don't just
	# put them back when we get an update for them). They are fully removed when the server
	# indicates that they are done.
	
	set id [dict get $d OperationID]


	if {[dict get $d IsTimer]} {
		if {$id eq "*"} {
			if {[dict get $d IsDone]} {
				# We're cancelling all existing progress timers
				foreach tw [array names timer_progress_data w:*] {
					if {$tw ne {}} {
						destroy $timer_progress_data($tw)
					}
					array unset timer_progress_data *:[string range $tw 2 end]
				}
				if {[winfo exists .initiative]} {
					::gmaclock::autosize .initiative.clock
				}
			} else {
				# This request doesn't make sense
				DEBUG 0 "Received progress update $d does not make sense (ignored)"
			}
			return
		}
			
		set timer_progress_data(enabled:$id) true
		set timer_progress_data(targets:$id) [dict get $d Targets]
		set timer_progress_data(title:$id) [dict get $d Title]
		set timer_progress_data(max:$id) [dict get $d MaxValue]
		set timer_progress_data(value:$id) [dict get $d Value]
		if {![info exists timer_progress_data(w:$id)]} {
			# this is a timer we haven't seen yet
			if {[dict get $d IsDone]} {
				# but the server's already saying to forget it, so we're good.
				return
			}
			set timer_progress_data(w:$id) [create_timer_widget $id]
		} elseif {[dict get $d IsDone]} {
			# forget a timer we were tracking
			if {$timer_progress_data(w:$id) ne {}} {
				destroy $timer_progress_data(w:$id)
				if {[winfo exists .initiative]} {
					::gmaclock::autosize .initiative.clock
				}
			}
			array unset timer_progress_data *:$id
			return
		}
		update_timer_widget $id
		return
	}

	if {[dict get $d IsDone]} {
		end_progress $id
		return
	}
	if {![info exists progress_data($id:title)]} {
		begin_progress $id [dict get $d Title] [dict get $d MaxValue]
	}
	if {[dict get $d Value] > 0} {
		update_progress $id [dict get $d Value] [dict get $d MaxValue]
	}
}

proc DoCommandPS {d} {
	global canvas
	dict set d Name [AcceptCreatureImageName [dict get $d Name]]
	PlaceSomeone $canvas $d
	RefreshGrid false
	RefreshMOBs
	update
}

proc DoCommandROLL {d} {
	DisplayDieRoll $d -active
	ChatHistoryAppend [list ROLL $d [dict get $d MessageID]]
}

proc DoCommandTO {d} {
	DisplayChatMessage $d {}
	ChatHistoryAppend [list TO $d [dict get $d MessageID]]
}

#
# Hook for any post-login activities we need to do
#
proc DoCommandLoginSuccessful {} {
	global local_user is_GM _preferences

	set local_user $::gmaproto::username
	if {$local_user eq {GM}} {
		set is_GM true
	}
	refresh_title
	set feature_set {GMA-MARKUP}

	if {[dict get $_preferences colorize_die_rolls]} {
		lappend feature_set DICE-COLOR-BOXES
	}
	if {[dict get $_preferences colorize_die_labels]} {
		lappend feature_set DICE-COLOR-LABELS
	}
	::gmaproto::allow $feature_set
}

#
# Hook for any errors encountered when trying to execute an incoming
# server message (including the case where no DoCommand<cmd> procedure
# is defined)
#
proc DoCommandError {cmd d err} {
	DEBUG 0 "Unable to execute command $cmd from server: $err (with payload $d)"
}

set ServerAvailableVersion {}
proc checkForUpdates {} {
	global ServerAvailableVersion
	global GMAMapperVersion
	global path_tmp dialogbg
	set trynow false

	if {[winfo exists .upgradecheck]} {
		INFO "A Check for Updates window is already open."
		return
	}
	toplevel [set w .upgradecheck] 
	wm title $w "Checking for Upgrades"
	grid [label $w.title -text "Checking for mapper versions newer than the v$GMAMapperVersion you are running now."] - - -sticky w
	grid [label $w.s0]
	grid [label $w.l1 -text "Your current mapper version:"] [label $w.v1 -text $GMAMapperVersion] - -sticky w
	grid [label $w.s1]

	if {$ServerAvailableVersion ne {}} {
		set comp [::gmautil::version_compare $GMAMapperVersion [set upgrade_to [dict get $ServerAvailableVersion Version]]]
		if {$comp == 0} {
			grid [label $w.l2 -text "This version is what your GM recommends."] - - -sticky w
		} elseif {$comp < 0} {
			grid [label $w.l2 -text "Your GM's recommendation:"] [label $w.v2 -text $upgrade_to]\
			     [button $w.b2 -text "Upgrade now from local server" -command {UpgradeAvailable $ServerAvailableVersion}] -sticky w
		} else {
			grid [label $w.l2 -text "Your GM's recommendation:"] [label $w.v2 -text $upgrade_to] - -sticky w
			grid [label $w.ll2 -text "Your mapper is already newer than your GM's recommendation."] - - -sticky w
		}
	} else {
		grid [label $w.l2 -text "Your GM has not designated a required version for you to use"] - - -sticky w
		grid [label $w.ll2 -text "(or we were unable to get that information from the game server at this time)."] - - -sticky w
	}
	grid [label $w.s2]

	set github_info [fetch_url $path_tmp gma_mapper_current_release https://api.github.com/repos/MadScienceZone/gma-mapper/releases/latest]
	if {$github_info eq {}} {
		grid [label $w.l3 -text "We were not able to obtain the latest release information from github."] - - -sticky w
	} else {
		if {[catch {
			set d [json::json2dict $github_info]
			set tag [dict get $d tag_name]
			set tag_pfx [string range $tag 0 0]
			set tag_value [string range $tag 1 end]
		} err]} {
			grid [label $w.l3 -text "We were unable to obtain the latest release information from github."] - - -sticky w
			grid [label $w.ll3 -text "($err)."] - - -sticky w
		} else {
			set gcomp [::gmautil::version_compare $GMAMapperVersion $tag_value]
			if {$gcomp < 0} {
				grid [label $w.l3 -text "Latest public release:"] [label $w.v3 -text $tag] \
				     [button $w.b3 -text "Upgrade now to PUBLIC release" -command "UpgradeAvailable -github [list $tag]"] -sticky w
			} elseif {$gcomp == 0} {
				grid [label $w.l3 -text "This version is the latest public release."] - - -sticky w
			} else {
				grid [label $w.l3 -text "Latest public release:"] [label $w.v3 -text $tag] - -sticky w
				grid [label $w.ll3 -text "Your mapper is already newer than the latest public release."] - - -sticky w
			}
		}
	}
	grid [label $w.s3]
	grid [button $w.exit -text OK -command "destroy $w"] - -
}

# UpgradeAvailable -github tag
# UpgradeAvailable upgrade_dict
proc UpgradeAvailable {args} {
	global GMAMapperVersion BIN_DIR path_install_base
	global UpdateURL path_tmp CURLproxy CURLpath CURLinsecure
	global ServerAvailableVersion

	if {[llength $args] == 2 && [lindex $args 0] eq {-github}} {
		# fetch from github directly
		set tag [lindex $args 1]
		if {[string range $tag 0 0] eq {v}} {
			set tag [string range $tag 1 end]
		}
		set _UpdateURL https://raw.githubusercontent.com/MadScienceZone/gma-mapper/main/signed-releases
		set d [dict create Version $tag Token "mapper-$tag" OS {} Arch {}]
		set from_github true
	} elseif {[llength $args] == 1} {
		# fetch from wherever we configured (possibly local) updates to come from
		set ServerAvailableVersion [set d [lindex $args 0]]
		set _UpdateURL $UpdateURL
		set from_github false
	} else {
		DEBUG 0 "UpgradeAvailable $args: usage error"
		return
	}

	::gmautil::dassign $d Version new_version Token upgrade_file OS os Arch arch
	set comp [::gmautil::version_compare $GMAMapperVersion $new_version]
	if {$os eq {}} {
		set for "for any operating system "
	} else {
		set for "for $os systems "
	}
	if {$arch eq {}} {
		append for "running on any architecture"
	} else {
		append for "for $arch machines"
	}

	if {$from_github} {
		set recommendation "You are currently running version $GMAMapperVersion.\nThe most recent public release $for is $new_version."
	} else {
		set recommendation "You are currently running version $GMAMapperVersion.\nYour game server says that the currently-recommended version $for (as incidated by your GM) is $new_version."
	}

	if {$comp < 0} {
		if {[::gmautil::is_git $BIN_DIR]} {
			tk_messageBox -parent . -type ok -icon info \
				-title "Mapper version $new_version is available"\
				-message "There is a new mapper version, $new_version, available for use. Update your Git repository." \
				-detail "$recommendation\nHowever, since you are running this client from $BIN_DIR, which is inside a Git repository working tree, you should upgrade it by running \"git pull\" rather than using the built-in upgrade feature."
		} else {
			if {$_UpdateURL eq {}} {
				tk_messageBox -parent . -type ok -icon info \
					-title "Mapper version $new_version is available"\
					-message "There is a new mapper version, $new_version, available for use." \
					-detail "$recommendation\nIf you add an update-url value to your mapper configuration file or include an --update-url option when running mapper, this update may be installed automatically for you. Ask your GM for the correct value for that setting."
			} else {
				set answer [tk_messageBox -parent . -type yesno -icon question \
					-title "Mapper version $new_version is available"\
					-message "There is a new mapper version, $new_version, available for use. Do you wish to upgrade now?" \
					-detail "$recommendation\n\nIf you click YES, the new mapper will be downloaded and installed on your computer, and then launched. You will then be using the version $new_version client."]
				if {$answer eq {yes}} {
					# Figure out if $BIN_DIR has the format <install_base>/mapper/<version>/bin
					set install_dirs [file split $BIN_DIR]
					if {[lindex $install_dirs end] eq {bin}
					&&  [lindex $install_dirs end-1] eq $GMAMapperVersion
					&&  [lindex $install_dirs end-2] eq {mapper}} {
						# yes. We propose using the same convention, then.
						set target_dirs [lreplace $install_dirs end-1 end $new_version]
					} else {
						# no. What about <install_base>/mapper/bin?
						if {[lindex $install_dirs end] eq {bin}
						&&  [lindex $install_dirs end-1] eq {mapper}} {
							# yes. propose adding the versioned structure.
							set target_dirs [lreplace $install_dirs end end $new_version]
						} else {
							# (shrug) punt.
							set target_dirs [file split $path_install_base]
							lappend target_dirs $new_version
						}
					}

					set answer [tk_messageBox -parent . -type yesnocancel -icon question \
						-title "Installation Target" \
						-message "This client is running from $BIN_DIR. Should I install the new one in [file join {*}$target_dirs]?"\
						-detail "If you click YES, the new client will be installed in the recommended location to make it easier to maintain all the versions of the mapper you have on your system.\nIf you click NO, you will be prompted to choose the installation directory of your choice.\nIt you click CANCEL, we won't install the new version at this time at all."]
					if {$answer eq {yes}} {
						INFO "Initiating upgrade from $GMAMapperVersion to $new_version from $_UpdateURL"
						::gmautil::upgrade $target_dirs $path_tmp $_UpdateURL $upgrade_file $GMAMapperVersion $new_version mapper bin/mapper.tcl ::INFO $CURLproxy $CURLpath $CURLinsecure
					} elseif {$answer eq {no}} {
						set chosen_dir [tk_chooseDirectory -initialdir [file join {*}$target_dirs] \
							-mustexist true \
							-title "Select Installation Base Directory"]
						if {$chosen_dir eq {}} {
							say "No directory selected; upgrade cancelled."
						} else {
							if {[tk_messageBox -parent . -type yesno -icon question \
								-title "Confirm Installation Directory" \
								-message "Are you sure you wish to install into $chosen_dir?"\
								-detail "If you click YES, we will install the new mapper client into $chosen_dir."] eq {yes}} {
								::gmautil::upgrade [file split $chosen_dir] $path_tmp $_UpdateURL $upgrade_file $GMAMapperVersion $new_version mapper bin/mapper.tcl ::INFO $CURLproxy $CURLpath $CURLinsecure
							} else {
								say "Installation of version $new_version cancelled."
							}
						}
					} else {
						say "Installation of version $new_version cancelled."
					}
				}; # end of "yes, install update"
			}; # end of "have UpdateURL"
		}; # end of (not) in git area
	} elseif {$comp > 0} {
		if {$from_github} {
			INFO "You are running a newer mapper ($GMAMapperVersion) than the latest public release ($new_version $for). If this isn't expected, you may want to nudge your GM and/or system administrator to update the server's advertised version, or follow their advice on which version you should be running."
		} else {
			INFO "You are running a newer mapper ($GMAMapperVersion) than the latest version offered by your server ($new_version $for). If this isn't expected, you may want to nudge your GM and/or system administrator to update the server's advertised version."
		}
	}
}
		
		
proc chat_to_all {for_user tkey} {
	global dice_preset_data local_user

	foreach recipient [array names dice_preset_data "CHAT_TO,$tkey,*"] {
		set dice_preset_data($recipient) 0
	}
	update_chat_to $for_user $tkey
}

proc update_chat_to {for_user tkey} {
	global dice_preset_data
	set q 0
	set klen [string length "CHAT_TO,$tkey,"]
	foreach name [array names dice_preset_data "CHAT_TO,$tkey,*"] {
		if {$dice_preset_data($name)} {
			if {$q > 0} {
				$dice_preset_data(cw,$tkey).p.chat.2.to configure -text "To (multiple):"
				return
			}
			set q 1
			$dice_preset_data(cw,$tkey).p.chat.2.to configure -text "To [string range $name $klen end]:"
		}
	}
	if {$q == 0} {
		$dice_preset_data(cw,$tkey).p.chat.2.to configure -text "To all:"
	}
}

proc RefreshPeerList {} {::gmaproto::query_peers}
		
proc format_with_style {value format} {
	global _preferences

	if {[dict exists $_preferences styles dierolls components $format format]
	&&  [set fmt [dict get $_preferences styles dierolls components $format format]] ne {}} {
		if {[catch {
			set value [format $fmt $value]
		} err]} {
			DEBUG 0 "style formatting error (using $format format=$fmt): $err"
		}
	}
	DEBUG 3 "format_with_style($value, $format) -> $value"
	return $value
}

#
# We collect and report stats for die roll sets of 3 or more results.
# Since we see each result separately, we group them by RequestID (which
# means we by necessity ignore any without an ID), until we see the last
# roll in the set and then report it. Once we report, we remove the
# tracked data.
#
proc CollectRollStats {d} {
	global RollStatCollection
	if {[catch {
		::gmautil::dassign $d RequestID rID {Result Result} x
	} err]} {
		DEBUG 1 "Unable to collect stats: $err"
		return
	}

	if {$rID eq {}} {
		return
	}
	lappend RollStatCollection($rID) $x
	DEBUG 1 "collect $rID -> $RollStatCollection($rID)"
}
proc ReportRollStats {d} {
	global RollStatCollection
	if {[catch {
		::gmautil::dassign $d MoreResults is_more RequestID rID
	} err]} {
		DEBUG 1 "Unable to report stats: $err"
		return {}
	}

	if {$rID eq {} || $is_more} {
		DEBUG 1 "no report for $rID ($is_more)"
		return {}
	}

	if {[set N [llength $RollStatCollection($rID)]] < 3} {
		array unset RollStatCollection $rID
		DEBUG 1 "no report for $rID (not enough data)"
		return {}
	}

	set sum 0
	foreach x $RollStatCollection($rID) {
		incr sum $x
	}
	set mean [expr ($sum * 1.0) / $N]
	set v 0
	set cur {}
	set count 0
	set largest_count 0
	set mode {}
	set sorted [lsort -integer $RollStatCollection($rID)]
	array unset RollStatCollection $rID

	foreach x $sorted {
		set v [expr $v + (($x - $mean) ** 2)]
		if {$cur eq {}} {
			set cur $x
			set count 1
		} elseif {$cur != $x} {
			if {$count == $largest_count} {
				lappend mode $cur
			} elseif {$count > $largest_count} {
				set mode [list $cur]
				set largest_count $count
			}
			set cur $x
			set count 1
		} else {
			incr count
		}
	}
	if {$cur ne {}} {
		if {$count == $largest_count} {
			lappend mode $cur
		} elseif {$count > $largest_count} {
			set mode [list $cur]
		}
	}
	set sd [expr sqrt($v / ($N-1))]
	if {$N % 2 == 0} {
		set med [expr ([lindex $sorted [expr $N/2]] + [lindex $sorted [expr $N/2 - 1]]) / 2.0]
	} else {
		set med [lindex $sorted [expr $N/2]]
	}

	set mode "[list $mode]"
	DEBUG 1 "report for $rID [list $N $mean $sd $med $mode $sum]"
	return [list $N $mean $sd $med $mode $sum]
}


set drd_id 0
proc toIDName {n} {
	return [regsub -all {\W} $n {}]
}
set die_roll_group false
proc DisplayDieRoll {d args} {
	global icon_dieb16 icon_die16 icon_die16g icon_die16c SuppressChat drd_id LastDisplayedChatDate dice_preset_data die_roll_group
	global icon_dbracket_b icon_dbracket_t icon_dbracket_m icon_dbracket__ icon_die16success icon_die16fail

	if {$SuppressChat} {
		return
	}

	::gmautil::dassign $d \
		Sender           from \
		Recipients       recipientlist \
		Title            title \
		RequestID        request_id \
		MoreResults      more_results_coming \
		{Result Result}  result \
		{Result Details} details \
		{Result InvalidRequest} is_invalid \
		{Result ResultSuppressed} is_blind \
		Sent             date_sent \
		ToAll		 to_all \
		ToGM             to_GM \
		Origin		 is_origin \
		Replay		 is_replay


	if {!$is_replay && [string index $request_id 0] eq {#} && [lsearch -exact $args -active] >= 0} {
		lassign [split $request_id {;}] tablename tkey flags roll_id
		global dice_preset_data
		global is_GM
		set tbl {}
		set attrib {}

		if {[string first b $flags] >= 0} {
			set is_blind true
		}

		if {$is_origin && !$is_blind && !$is_invalid} {
			# we're the original requester and this was a table lookup result we started.
			# complete the table lookup and report out the results now
			set preset_data [PresetLists dice_preset_data $tkey]
			if {[string index $tablename 1] eq {#}} {
				set tbl [SearchForPreset $preset_data table [string range $tablename 2 end] -global -details]
			} else {
				set tbl [SearchForPreset $preset_data table [string range $tablename 1 end] -details]
			}
		} elseif {$is_GM && $is_blind && !$is_invalid} {
			# we're the GM and this user sent this blind to us. Can we find the table? maybe it was global.
			if {[string index $tablename 1] eq {#}} {
				set preset_data [PresetLists dice_preset_data GM]
				set tbl [SearchForPreset $preset_data table [string range $tablename 2 end] -global -details]
			} else {
				::gmaproto::chat_message "($from blind-rolled $result on their lookup table $tablename)" {} {} false true false
			}
			set attrib "$from "
		}
		if {$tbl ne {}} {
			foreach {v t} [dict get $tbl table] {
				if {$v eq "*" || $result <= $v} {
					::gmaproto::chat_message "${attrib}rolled $result on [dict get $tbl name]: $t" {} $recipientlist $to_all $to_GM [dict get $tbl markup]
					break
				}
			}
		}
	}

	# Notation to show grouping of multiple result sets
	if {$die_roll_group} {
		# continuing the set we previously started
		if {$more_results_coming} {
			set group_marker $icon_dbracket_m
		} else {
			set group_marker $icon_dbracket_b
			set die_roll_group false
		}
	} elseif {$more_results_coming} {
		set die_roll_group true
		set group_marker $icon_dbracket_t
	} else {
		set group_marker $icon_dbracket__
	}

	CollectRollStats $d
	global local_user dice_preset_data
	if {![info exists dice_preset_data(cw,[root_user_key])]} {
		DisplayChatMessage {} {}
	}
	set w $dice_preset_data(cw,[root_user_key]).p.chat

	if {![winfo exists $w]} {
		DisplayChatMessage {} {}
	}
	set icon $icon_die16
	foreach dd $details {
		switch -exact [dict get $dd Type] {
			"critlabel"        {set icon $icon_die16c; break}
			"success"          {set icon $icon_die16success; break}
			"fail"             {set icon $icon_die16fail; break}
			"short"            {set icon $icon_die16fail}
			"exceeded" - "met" {set icon $icon_die16success}
		}
	}
	if {$is_blind || $is_invalid} {
		set icon $icon_dieb16
	}

	TranscribeDieRoll $from $recipientlist $title $result $details [dict get $d ToAll] [dict get $d ToGM] $is_blind $is_invalid $date_sent
	$w.1.text configure -state normal
	global _preferences LastDisplayedChatDate
	if {[dict exists $_preferences chat_timestamp] && [dict get $_preferences chat_timestamp]} {
		if {$date_sent ne {}} {
			if {[set date_sent_sec [scan_fractional_seconds $date_sent]] != 0} {
				set date_sent_date [clock format [expr int($date_sent_sec)] -format "%A, %B %d, %Y"]
				if {$LastDisplayedChatDate ne $date_sent_date} {
					set LastDisplayedChatDate $date_sent_date
					$w.1.text insert end "\n--$date_sent_date--\n" timestamp
				}
				$w.1.text insert end [clock format [expr int($date_sent_sec)] -format "%H:%M "] timestamp
			} else {
				$w.1.text insert end "??:?? " timestamp
			}
		} else {
			$w.1.text insert end "--:-- " timestamp
		}
	}
	$w.1.text image create end -align baseline -image $icon -padx 2
	$w.1.text image create end -align baseline -image $group_marker -padx 1
	if {!$is_blind && !$is_invalid} {
		$w.1.text insert end [format_with_style $result fullresult] fullresult
		$w.1.text insert end " "
	}
	ChatAttribution $w.1.text $from $recipientlist [dict get $d ToAll] [dict get $d ToGM]
	if {$title != {}} {
		global _preferences colortheme
		if {[catch {
			foreach title_block [split $title "\u2016"] {
				set title_parts [split $title_block "\u2261"]
				switch [llength $title_parts] {
					0 {
						# title was empty?
						error "bug - uncaught empty title string"
					}
					1 {
						set title_fg [dict get $_preferences styles dierolls components title fg $colortheme]
						set title_bg [::tk::Darken $title_fg 40]
					}
					2 {
						set title_fg [lindex $title_parts 1]
						set title_bg [::tk::Darken $title_fg 40]
					}
					default {
						set title_fg [lindex $title_parts 1]
						set title_bg [lindex $title_parts 2]
					}
				}

				set wt $w.1.text.[incr drd_id]
				label $wt -padx 2 -pady 2 -relief groove -foreground $title_fg -background $title_bg -font [dict get $_preferences styles dierolls components title font] -borderwidth 2 -text [lindex $title_parts 0]
				$w.1.text window create end -align bottom -window $wt -padx 2
			}
		} err]} {
			DEBUG 0 "unable to set title block: $err"
			$w.1.text insert end [format_with_style $title title] title 
		}
	}
#				critspec  {$w.1.text insert end "  [lindex $tuple 1]" [lindex $tuple 0]}
	if {[catch {
		foreach dd $details {
			foreach detailparts [split [dict get $dd Value] "\u2016"] {
				set parts [split $detailparts "\u2261"]
				switch [llength $parts] {
					0 {
						$w.1.text insert end [format_with_style [dict get $dd Value] [dict get $dd Type]] [dict get $dd Type]
						DEBUG 3 "DisplayDieRoll: empty value $dd"
					}
					1 {
						$w.1.text insert end [format_with_style [lindex $parts 0] [dict get $dd Type]] [dict get $dd Type]
						DEBUG 3 "DisplayDieRoll: normal value $dd"
					}
					2 {
						$w.1.text tag configure [set tag _custom_fg_[toIDName [lindex $parts 1]]] \
							-foreground [lindex $parts 1] \
							-background [::tk::Darken [lindex $parts 1] 40] \
							-font [$w.1.text tag cget [dict get $dd Type] -font]
						$w.1.text insert end [lindex $parts 0] $tag
						DEBUG 3 "DisplayDieRoll: custom $tag $dd"
					}
					default {
						$w.1.text tag configure \
							[set tag _custom_fg_[toIDName [lindex $parts 1]]_bg_[toIDName [lindex $parts 2]]] \
								-foreground [lindex $parts 1] \
								-background [lindex $parts 2] \
								-font [$w.1.text tag cget [dict get $dd Type] -font]
						$w.1.text insert end [lindex $parts 0] $tag
						DEBUG 3 "DisplayDieRoll: custom $tag $dd"
					}
				}
			}
		}
	} err]} {
		DEBUG 0 $err
	}
	if {[catch {
		if {[llength [set stats [ReportRollStats $d]]] > 0} {
			$w.1.text insert end "\n"
			$w.1.text insert end [format "N=%d μ=%g σ=%g Md=%g Mo=%s Σ=%g" {*}$stats] stats
		}
	} err]} {
		DEBUG 1 "Error reporting stats: $err"
	}

	$w.1.text insert end "\n"
	$w.1.text see end
#	if {![info exists dice_preset_data(chat_lock)] || $dice_preset_data(chat_lock)} {
#		$w.1.text configure -state disabled
#	}
	$w.1.text configure -state disabled
}

proc assert_recent_die_rolls {tkey} {
	global dice_preset_data
	if {![info exists dice_preset_data(recent_die_rolls,$tkey)]} {
		set dice_preset_data(recent_die_rolls,$tkey) {}
	}
}
proc assert_resize_task {tkey} {
	global resize_task
	foreach subkey {recent preset} {
		if {![info exists resize_task($tkey,$subkey)]} {
			set resize_task($tkey,$subkey) {}
		}
	}
}
proc assert_last_known_size {tkey} {
	global last_known_size
	foreach subkey {recent,width recent,height preset,width preset,height} {
		if {![info exists last_known_size($tkey,$subkey)]} {
			set last_known_size($tkey,$subkey) 0
		}
	}
}
assert_resize_task [root_user_key]
assert_last_known_size [root_user_key]
assert_recent_die_rolls [root_user_key]

proc ResizeDieRoller {w width height type for_user tkey} {
	global resize_task last_known_size

	assert_resize_task $tkey
	assert_last_known_size $tkey

	if {$resize_task($tkey,$type) ne {}} {
		if {$resize_task($tkey,$type) eq NO} {
			return
		}
		after cancel $resize_task($tkey,$type)
	}
	if {$last_known_size($tkey,$type,width) != $width || $last_known_size($tkey,$type,height) != $height} {
		set resize_task($tkey,$type) [after 250 "_resize_die_roller $w $width $height $type $for_user $tkey"]
	}
}

proc inhibit_resize_task {flag type for_user tkey} {
	global resize_task
	if {$flag} {
		set resize_task($tkey,$type) NO
	} else {
		set resize_task($tkey,$type) {}
	}
}

#
# (re-)draw the die roll windows. type is "recent" or "preset".
# w is the scrolled frame content frame we are managing.
# if width or height are 0, we find out the dimensions or just render
# a basic layout without them. Otherwise we try our best to adapt to
# something that will fit in that space.
#
# recents:       _______________________________________
#        <w>.<i>| definition          +     [____] [::] |   <-- for <i> in [0,10)
#                 .spec              .plus  .extra .roll
#                _______________________________________
#        <w>.<i>| definition                            |
#               |                     +     [____] [::] |   <-- for <i> in [0,10)
#                 .spec              .plus  .extra .roll
#                                     :
#                                     :
#
# presets:       _______________________________________
#  <w>.preset<i>| [-] mypreset: def   +     [____] [::] |   <-- for <i> in [0,number of presets)
#                .del .name    .def  .plus .extra .roll
#                                     :
#                _____________________:_________________
#        <w>.add|[+] Add new...           [load] [save] |	<-- we don't touch this part here
#                .add .label              .load  .save
#
# global dice_preset_data(name) provides dierollpreset dict for each preset
# global recent_die_rolls       provides {{description extra} {description extra} ...} as list of recent roll descriptions
#
# options in args:
#	-noclear		Do not clear the old contents (because the caller already did)
#
#proc _set_text_spec {w spec} {
#	$w configure -state normal -width [string length $spec]
#	$w delete 1.0 end
#	if [regexp {([^=]+=)?([^|]+)([|].*)?$} $spec _ title diespec mods] {
#		$w insert end $title title $diespec diespec $mods mods
#	} else {
#		$w insert end $spec diespec
#	}
#	$w configure -state disabled
#}

proc _pop_open_extra {w i} {
	if {[$w cget -width] < 19} {
		$w configure -width 19
	}
}

proc _collapse_extra {w i for_user tkey} {
	$w configure -width [expr max(3,[string length [$w get]])]
	if {$i >= 0} {
		global dice_preset_data
		assert_recent_die_rolls $tkey
		set dice_preset_data(recent_die_rolls,$tkey) [lreplace $dice_preset_data(recent_die_rolls,$tkey) $i $i [list [lindex [lindex $dice_preset_data(recent_die_rolls,$tkey) $i] 0] [$w get]]]
	}
}

proc cleanupDieRollSpec {spec} {
	set parts [split $spec =]
	if {[llength $parts] < 2} {
		return $spec
	}
	set res {}
	foreach title_block [split [lindex $parts 0] "\u2016"] {
		lappend res [lindex [split $title_block "\u2261"] 0]
	}
	return [join [list [join $res "\u2016"] [lindex $parts 1]] =]
}

proc DRPexpand {w tkey piname j for_user} {
	global dice_preset_data
	set dice_preset_data(collapse,$tkey,$piname) \
		[lreplace $dice_preset_data(collapse,$tkey,$piname) $j $j \
			[expr ![lindex $dice_preset_data(collapse,$tkey,$piname) $j]]]
	_render_die_roller $w 0 0 preset $for_user $tkey
}
		
proc SetTableColors {row fgvar bgvar} {
	global dark_mode _preferences colortheme
	upvar $fgvar f
	upvar $bgvar b
	set f [dict get $_preferences styles dialogs normal_fg $colortheme]
	if {[expr ($row % 2) == 0]} {
		set b [dict get $_preferences styles dialogs even_bg $colortheme]
	} else {
		set b [dict get $_preferences styles dialogs odd_bg $colortheme]
	}
}

proc _render_die_roller {w width height type for_user tkey args} {
	global dice_preset_data last_known_size icon_delete icon_die16 icon_die16g
	global dark_mode _preferences colortheme icon_blank

	assert_last_known_size $tkey
	if {$width <= 0} {
		set width $last_known_size($tkey,$type,width)
	}

	set row_bg {}
	if {[set b [dict get $_preferences styles dialogs even_bg $colortheme]] ne {}} {
		set row_bg [list [list -bg $b]]
	} else {
		set row_bg [list {}]
	}
	if {[set b [dict get $_preferences styles dialogs odd_bg $colortheme]] ne {}} {
		lappend row_bg [list -bg $b]
	} else {
		lappend row_bg {}
	}

	switch -exact $type {
		recent {
			assert_recent_die_rolls $tkey
			for {set i 0} {$i < [llength $dice_preset_data(recent_die_rolls,$tkey)] && $i < 10} {incr i} {
				$w.$i.spec configure -text [lindex [lindex $dice_preset_data(recent_die_rolls,$tkey) $i] 0]
				$w.$i.extra configure -width [expr max(3,[string length [lindex [lindex $dice_preset_data(recent_die_rolls,$tkey) $i] 1]])] -state normal
				$w.$i.extra delete 0 end
				$w.$i.extra insert end [lindex [lindex $dice_preset_data(recent_die_rolls,$tkey) $i] 1]
				if {$last_known_size($tkey,recent,$i) eq {blank}} {
					# first time, pack them since they weren't there before
					pack $w.$i.roll $w.$i.plus $w.$i.extra -side left
					pack $w.$i.spec -side left -expand 1 -fill x
					$w.$i.extra configure -state normal 
					$w.$i.roll configure -state normal 
					if {[llength [lindex $row_bg [expr $i % 2]]] > 0} {
						$w.$i.spec configure {*}[lindex $row_bg [expr $i % 2]]
					}
					bind $w.$i.extra <FocusIn> "_pop_open_extra $w.$i.extra $i"
					bind $w.$i.extra <FocusOut> "_collapse_extra $w.$i.extra $i $for_user $tkey"
					set last_known_size($tkey,recent,$i) 1
				} else {
					pack configure $w.$i.spec -expand 1 -fill x
				}
			}
			if {[dict get $_preferences styles dierolls compact_recents]} {
				update
				for {set i 0} {$i < [llength $dice_preset_data(recent_die_rolls,$tkey)] && $i < 10} {incr i} {
					set needed_width [expr [winfo width $w.$i.spec] + [winfo width $w.$i.roll] + [winfo width $w.$i.extra] + [winfo width $w.$i.plus]]
					if {$width > 0 && $needed_width >= $width} {
						if {$last_known_size($tkey,recent,$i) != 2} {
							# rearrange widgets into 2 rows to allow more room
							pack forget $w.$i.spec $w.$i.plus $w.$i.extra $w.$i.roll
							pack $w.$i.spec -side bottom -anchor w -expand 1 -fill x
							pack $w.$i.roll $w.$i.plus $w.$i.extra -side left 
							set last_known_size($tkey,recent,$i) 2
						} else {
							pack configure $w.$i.spec -expand 1 -fill x
						}
					} else {
						if {$last_known_size($tkey,recent,$i) != 1} {
							# rearrange widgets into 1 row
							pack forget $w.$i.spec $w.$i.plus $w.$i.extra $w.$i.roll
							pack $w.$i.roll $w.$i.plus $w.$i.extra -side left
							pack $w.$i.spec -side left -expand 1 -fill x
							set last_known_size($tkey,recent,$i) 1
						} else {
							pack configure $w.$i.spec -expand 1 -fill x
						}
					}
				}
			}
		}
		preset {
			global icon_bullet_arrow_down
			global icon_bullet_arrow_right
			set CONTINUE_OUTER_LOOP 42
			if {[lsearch -exact $args -noclear] < 0} {
				foreach pk [array names dice_preset_data "w,$tkey,*"] {
					DEBUG 1 "destroy $dice_preset_data($pk)"
					destroy $dice_preset_data($pk)
				}
				array unset dice_preset_data "w,$tkey,*"
			}
			set preset_data [PresetLists dice_preset_data $tkey -export]
			set i 0
			#
			# Table Names
			#
			global DieRollPresetState
			set prev_grplist {}
			set prev_collapse {}
			foreach {scope preset_set} {g GlobalTables u Tables} {
			    foreach preset [dict get $preset_data $preset_set] {
				set wpi $w.preset$i
				DEBUG 4 "create frame $wpi"
				set dname [dict get $preset DisplayName]
				set pname [dict get $preset Name]
				set piname [to_window_id $scope$pname]

				set grplist [split [dict get $preset Group] "\u25B6"]
				if {![info exists dice_preset_data(collapse,$tkey,$piname)] || \
					[llength $dice_preset_data(collapse,$tkey,$piname)] != [llength $grplist]} {
						set dice_preset_data(collapse,$tkey,$piname) [lmap x $grplist { expr 0 }]
				}
				try {
					set controls {}
					for {set j 0} {$j < [llength $grplist]} {incr j} {
						if {$j < [llength $prev_grplist] && [lindex $prev_grplist $j] eq [lindex $grplist $j]} {
							if {[lindex $prev_collapse $j] eq {} || ![lindex $prev_collapse $j]} {
								# part of closed group we already showed above.
								# same level-j group as the previous line, and since that was closed
								# we will be too. So we don't even need to show this preset at all.
								return -level 0 -code $CONTINUE_OUTER_LOOP
							}
							# part of open group we already showed above. add a spacer here and keep looking.
							lappend controls _
							continue
						} elseif {![lindex $dice_preset_data(collapse,$tkey,$piname) $j]} {
							# start of new group at level j but we're closed here.
							# set an expand button and stop.
							lappend controls >
							set prev_collapse [lreplace $prev_collapse $j end 0]
							break
						} else {
							# start of new group at level j and we're open here.
							# set a collapse button and continue.
							lappend controls v
							set prev_collapse [lreplace $prev_collapse $j end 1]
						}
					}
				} on $CONTINUE_OUTER_LOOP {} {
					continue
				}
				set prev_grplist $grplist
				set wpi $w.preset$i
				set dice_preset_data(w,$tkey,$pname) $wpi
				pack [frame $wpi] -side top -expand 0 -fill x
				set bgcolor [$wpi cget -background]
				try {
					for {set j 0} {$j < [llength $controls]} {incr j} {
						switch [lindex $controls $j] {
							_ {
								pack [button $wpi.gb$j -image $icon_blank -relief flat] -side left
								pack [label $wpi.gl$j -text [lindex $grplist $j] -fg $bgcolor -bg $bgcolor] -side left
							}
							> {
								pack [button $wpi.gb$j -image $icon_bullet_arrow_right -relief flat -command [list DRPexpand $w $tkey $piname $j $for_user]] -side left
								pack [label $wpi.gl$j -text [lindex $grplist $j]] -side left
								return -level 0 -code $CONTINUE_OUTER_LOOP
							}
							v {
								pack [button $wpi.gb$j -image $icon_bullet_arrow_down -relief flat -command [list DRPexpand $w $tkey $piname $j $for_user]] -side left
								pack [label $wpi.gl$j -text [lindex $grplist $j]] -side left
							}
							default {
								pack [label $wpi.gb$j -text "??"] -side left
								pack [label $wpi.gl$j -text "??"] -side left
							}
						}
					}
				} on $CONTINUE_OUTER_LOOP {} {
					incr i
					continue
				}



#				set dice_preset_data(w,$tkey,$pname) $wpi
#				pack [frame $wpi] -side top -expand 0 -fill x
#				set grplist [split [dict get $preset Group] "\u25B6"]
#				if {![info exists dice_preset_data(collapse,$tkey,$piname)] || \
#					[llength $dice_preset_data(collapse,$tkey,$piname)] != [llength $grplist]} {
#						set dice_preset_data(collapse,$tkey,$piname) [lmap x $grplist { expr 0 }]
#				}
#				for {set j 0} {$j < [llength $grplist]} {incr j} {
#					if {[lindex $dice_preset_data(collapse,$tkey,$piname) $j]} {
#						pack [button $wpi.gb$j -image $icon_bullet_arrow_down -relief flat -command [list DRPexpand $w $tkey $piname]] [label $wpi.gl$j -text [lindex $grplist $j]] -side left
#					} else {
#						pack [button $wpi.gb$j -image $icon_bullet_arrow_right -relief flat -command [list DRPexpand $w $tkey $piname]] [label $wpi.gl$j -text [lindex $grplist $j]] -side left
#						break
#					}
#				}
#				if {$j < [llength $grplist]} {
#					incr i
#					continue
#				}

				if {$scope eq "g"} {
					pack [button $wpi.tablename -text "##$dname" -command [list RollTable "##$dname" $for_user $tkey]] -side left
				} {
					pack [button $wpi.tablename -text "#$dname" -command [list RollTable "#$dname" $for_user $tkey]] -side left
				}
				::tooltip::tooltip $wpi.tablename "* [dict get $preset Description]"
				incr i
			   }
			}

			#
			# Modifiers
			#
			global DieRollPresetState
			set prev_grplist {}
			set prev_collapse {}
			foreach {scope preset_set} {g GlobalModifiers u Modifiers} {
			    foreach preset [dict get $preset_data $preset_set] {
				set wpi $w.preset$i
				DEBUG 4 "create frame $wpi"
				set dname [dict get $preset DisplayName]
				set pname [dict get $preset Name]
				set piname [to_window_id $scope$pname]

				set grplist [split [dict get $preset Group] "\u25B6"]
				if {![info exists dice_preset_data(collapse,$tkey,$piname)] || \
					[llength $dice_preset_data(collapse,$tkey,$piname)] != [llength $grplist]} {
						set dice_preset_data(collapse,$tkey,$piname) [lmap x $grplist { expr 0 }]
				}
				try {
					set controls {}
					for {set j 0} {$j < [llength $grplist]} {incr j} {
						if {$j < [llength $prev_grplist] && [lindex $prev_grplist $j] eq [lindex $grplist $j]} {
							if {[lindex $prev_collapse $j] eq {} || ![lindex $prev_collapse $j]} {
								# part of closed group we already showed above.
								# same level-j group as the previous line, and since that was closed
								# we will be too. So we don't even need to show this preset at all.
								return -level 0 -code $CONTINUE_OUTER_LOOP
							}
							# part of open group we already showed above. add a spacer here and keep looking.
							lappend controls _
							continue
						} elseif {![lindex $dice_preset_data(collapse,$tkey,$piname) $j]} {
							# start of new group at level j but we're closed here.
							# set an expand button and stop.
							lappend controls >
							set prev_collapse [lreplace $prev_collapse $j end 0]
							break
						} else {
							# start of new group at level j and we're open here.
							# set a collapse button and continue.
							lappend controls v
							set prev_collapse [lreplace $prev_collapse $j end 1]
						}
					}
				} on $CONTINUE_OUTER_LOOP {} {
					continue
				}
				set prev_grplist $grplist
				set wpi $w.preset$i
				set dice_preset_data(w,$tkey,$pname) $wpi
				pack [frame $wpi] -side top -expand 0 -fill x
				set bgcolor [$wpi cget -background]
				try {
					for {set j 0} {$j < [llength $controls]} {incr j} {
						switch [lindex $controls $j] {
							_ {
								pack [button $wpi.gb$j -image $icon_blank -relief flat] -side left
								pack [label $wpi.gl$j -text [lindex $grplist $j] -fg $bgcolor -bg $bgcolor] -side left
							}
							> {
								pack [button $wpi.gb$j -image $icon_bullet_arrow_right -relief flat -command [list DRPexpand $w $tkey $piname $j $for_user]] -side left
								pack [label $wpi.gl$j -text [lindex $grplist $j]] -side left
								return -level 0 -code $CONTINUE_OUTER_LOOP
							}
							v {
								pack [button $wpi.gb$j -image $icon_bullet_arrow_down -relief flat -command [list DRPexpand $w $tkey $piname $j $for_user]] -side left
								pack [label $wpi.gl$j -text [lindex $grplist $j]] -side left
							}
							default {
								pack [label $wpi.gb$j -text "??"] -side left
								pack [label $wpi.gl$j -text "??"] -side left
							}
						}
					}
				} on $CONTINUE_OUTER_LOOP {} {
					incr i
					continue
				}



#				set dice_preset_data(w,$tkey,$pname) $wpi
#				pack [frame $wpi] -side top -expand 0 -fill x
#				set grplist [split [dict get $preset Group] "\u25B6"]
#				if {![info exists dice_preset_data(collapse,$tkey,$piname)] || \
#					[llength $dice_preset_data(collapse,$tkey,$piname)] != [llength $grplist]} {
#						set dice_preset_data(collapse,$tkey,$piname) [lmap x $grplist { expr 0 }]
#				}
#				for {set j 0} {$j < [llength $grplist]} {incr j} {
#					if {[lindex $dice_preset_data(collapse,$tkey,$piname) $j]} {
#						pack [button $wpi.gb$j -image $icon_bullet_arrow_down -relief flat -command [list DRPexpand $w $tkey $piname]] [label $wpi.gl$j -text [lindex $grplist $j]] -side left
#					} else {
#						pack [button $wpi.gb$j -image $icon_bullet_arrow_right -relief flat -command [list DRPexpand $w $tkey $piname]] [label $wpi.gl$j -text [lindex $grplist $j]] -side left
#						break
#					}
#				}
#				if {$j < [llength $grplist]} {
#					incr i
#					continue
#				}

				if {[set id [string trim [dict get $preset Variable]]] eq {}} {
					set id [dict get $preset DisplaySeq]
					if {[dict get $preset Global]} {
						set t "$dname: (...)[dict get $preset DieRollSpec]"
					} else {
						set t "$dname: [dict get $preset DieRollSpec]"
					}
					if {$scope eq "g"} {
						pack [ttk::checkbutton $wpi.enabled -variable dice_preset_data(en,$tkey,$piname) \
							-command [list DRPScheckVarEn "en,$tkey,$piname" g$id $for_user $tkey u]\
							-text "\[system\] $t"] -side left
						# ^^hack
					} {
						pack [ttk::checkbutton $wpi.enabled -variable dice_preset_data(en,$tkey,$piname) \
							-command [list DRPScheckVarEn "en,$tkey,$piname" u$id $for_user $tkey $scope]\
							-text $t] -side left
					}
				} else {
					if {$scope eq "g"} {
						pack [ttk::checkbutton $wpi.enabled -variable dice_preset_data(en,$tkey,$piname) \
							-command [list DRPScheckVarEn "en,$tkey,$piname" $id $for_user $tkey $scope]\
							-text "\[system\] [dict get $preset DisplayName] (as \$\$\{$id\}): [dict get $preset DieRollSpec]"\
						] -side left
					} {
						pack [ttk::checkbutton $wpi.enabled -variable dice_preset_data(en,$tkey,$piname) \
							-command [list DRPScheckVarEn "en,$tkey,$piname" $id $for_user $tkey $scope]\
							-text "[dict get $preset DisplayName] (as \$\{$id\}): [dict get $preset DieRollSpec]"\
						] -side left
					}
				}
				if {![info exists dice_preset_data(en,$tkey,$piname)]} {
#					trace add variable dice_preset_data(en,$tkey,$piname) {array read write unset} TRACEvar
					set dice_preset_data(en,$tkey,$piname) [::gmaproto::int_bool [dict get $preset Enabled]]
				} else {
					#TRACE "variable dice_preset_data(en,$tkey,$piname) already exists with value $dice_preset_data(en,$tkey,$piname)"
				}
				::tooltip::tooltip $wpi.enabled "* [dict get $preset Description]"
				incr i
			   }
			}

			#
			# open open closed
			# skip all with same 3rd level as the closed one and identical 1st and 2nd
			# ---- ---- process normally when 3rd level stops matching 
			# ----
			#
			# always keep prevous set
			# in loop:
			# 	for group level 0..n in this preset
			#	 	if group matches (implies there were this many levels in previous preset)
			# 			if previous closed, skip this preset entirely
			# 			else place spacer instead of button and label, continue to next level
			# 		else if this level closed
			# 			place button to open, continue to next preset
			# 		else place button to close, continue to next level
			# 	if we haven't abandoned the preset yet, finish rendering it
			#
			set prev_grplist {}
			set prev_collapse {}
			foreach scope {GlobalRolls Rolls} {
			   foreach preset [dict get $preset_data $scope] {
				if {$scope eq "GlobalRolls"} {
					set dieicon $icon_die16g
				} else {
					set dieicon $icon_die16
				}
				set pname [dict get $preset Name]
				set dname [dict get $preset DisplayName]
				set desc [dict get $preset Description]
				set def [dict get $preset DieRollSpec]
				set piname [to_window_id $pname]

				set grplist [split [dict get $preset Group] "\u25B6"]
				if {![info exists dice_preset_data(collapse,$tkey,$piname)] || \
					[llength $dice_preset_data(collapse,$tkey,$piname)] != [llength $grplist]} {
						set dice_preset_data(collapse,$tkey,$piname) [lmap x $grplist { expr 0 }]
				}
				try {
					set controls {}
					for {set j 0} {$j < [llength $grplist]} {incr j} {
						if {$j < [llength $prev_grplist] && [lindex $prev_grplist $j] eq [lindex $grplist $j]} {
							if {[lindex $prev_collapse $j] eq {} || ![lindex $prev_collapse $j]} {
								# part of closed group we already showed above.
								# same level-j group as the previous line, and since that was closed
								# we will be too. So we don't even need to show this preset at all.
								return -level 0 -code $CONTINUE_OUTER_LOOP
							}
							# part of open group we already showed above. add a spacer here and keep looking.
							lappend controls _
							continue
						} elseif {![lindex $dice_preset_data(collapse,$tkey,$piname) $j]} {
							# start of new group at level j but we're closed here.
							# set an expand button and stop.
							lappend controls >
							set prev_collapse [lreplace $prev_collapse $j end 0]
							break
						} else {
							# start of new group at level j and we're open here.
							# set a collapse button and continue.
							lappend controls v
							set prev_collapse [lreplace $prev_collapse $j end 1]
						}
					}
				} on $CONTINUE_OUTER_LOOP {} {
					continue
				}
				set prev_grplist $grplist
				set wpi $w.preset$i
				set dice_preset_data(w,$tkey,$pname) $wpi
				pack [frame $wpi] -side top -expand 0 -fill x
				set bgcolor [$wpi cget -background]
				try {
					for {set j 0} {$j < [llength $controls]} {incr j} {
						switch [lindex $controls $j] {
							_ {
								pack [button $wpi.gb$j -image $icon_blank -relief flat] -side left
								pack [label $wpi.gl$j -text [lindex $grplist $j] -fg $bgcolor -bg $bgcolor] -side left
							}
							> {
								pack [button $wpi.gb$j -image $icon_bullet_arrow_right -relief flat -command [list DRPexpand $w $tkey $piname $j $for_user]] -side left
								pack [label $wpi.gl$j -text [lindex $grplist $j]] -side left
								return -level 0 -code $CONTINUE_OUTER_LOOP
							}
							v {
								pack [button $wpi.gb$j -image $icon_bullet_arrow_down -relief flat -command [list DRPexpand $w $tkey $piname $j $for_user]] -side left
								pack [label $wpi.gl$j -text [lindex $grplist $j]] -side left
							}
							default {
								pack [label $wpi.gb$j -text "??"] -side left
								pack [label $wpi.gl$j -text "??"] -side left
							}
						}
					}
				} on $CONTINUE_OUTER_LOOP {} {
					incr i
					continue
				}

				pack [button $wpi.roll -image $dieicon -command "[list RollPreset $wpi $i $pname $for_user $tkey $scope]"] -side left
				pack [label $w.preset$i.plus -text +] -side left
				pack [entry $w.preset$i.extra -width 3] -side left
				pack [label $w.preset$i.name -text ${dname}: -anchor w -font Tf12 \
					-foreground [dict get $_preferences styles dialogs preset_name $colortheme] \
					{*}[lindex $row_bg [expr $i % 2]]] -side left -padx 2
				pack [label $w.preset$i.def -text [cleanupDieRollSpec $def] -anchor w {*}[lindex $row_bg [expr $i % 2]]] -side left -expand 1 -fill x
				#pack [button $w.preset$i.del -image $icon_delete -command [list DeleteDieRollPreset $preset_name $for_user]] -side right
				::tooltip::tooltip $w.preset$i.name "* $desc"
				::tooltip::tooltip $w.preset$i.def "* $desc"
				bind $w.preset$i.extra <FocusIn> "_pop_open_extra $w.preset$i.extra -1"
				bind $w.preset$i.extra <FocusOut> "_collapse_extra $w.preset$i.extra -1 $for_user $tkey"
				incr i
			}}
			if {[dict get $_preferences styles dierolls compact_recents]} {
				update
				set i 0
				set name_list [lsort -dictionary [array names dice_preset_data "sys,preset,*"]]
				lappend name_list {*}[lsort -dictionary [array names dice_preset_data "preset,$tkey,*"]]
				foreach preset_name $name_list {
					if {[catch {
						set needed_width [expr [winfo width $w.preset$i.name] + \
								   [winfo width $w.preset$i.def] + \
								   [winfo width $w.preset$i.roll] + \
								   [winfo width $w.preset$i.extra] + \
								   [winfo width $w.preset$i.plus]]
					} err]} {
						DEBUG 1 "preset width calculation failed; $err"
						set needed_width 0
					}
					if {$width > 0 && $needed_width >= $width} {
						# move to 2-row format
						pack forget $w.preset$i.def $w.preset$i.del $w.preset$i.name $w.preset$i.roll $w.preset$i.extra $w.preset$i.plus

						pack $w.preset$i.def -side bottom -anchor w -expand 1 -fill x
						pack $w.preset$i.roll $w.preset$i.plus $w.preset$i.extra -side left
						pack $w.preset$i.name -side left -expand 1 -padx 2
						#pack $w.preset$i.del -side right
					} else {
						if {[catch {
							pack configure $w.preset$i.def -expand 1 -fill x
						} err]} {
							DEBUG 1 "preset widget repack error $err"
						}
					}
					incr i
				}
			}
			::gmautil::trigger_size $w
		}
		default {
			DEBUG 0 "_render_die_roller passed unknown type '$type'"
		}
	}
}

proc DRPScheckVarEn {key id for_user tkey {scope u}} {
	global DieRollPresetState
	global dice_preset_data

	if {$scope eq "g"} {
		set DieRollPresetState(sys,gvar_on,$id) [::gmaproto::json_bool $dice_preset_data($key)]
	} else {
		set DieRollPresetState($tkey,on,$id) [::gmaproto::json_bool $dice_preset_data($key)]
	}
}

proc _resize_die_roller {w width height type for_user tkey} {
	global resize_task

	assert_resize_task $tkey
	if {$resize_task($tkey,$type) eq NO} {
		return
	}
	if {[catch {
		global last_known_size
		_render_die_roller $w $width $height $type $for_user $tkey
		set last_known_size($tkey,$type,width) $width
		set last_known_size($tkey,$type,height) $height
	} err]} {
		DEBUG 0 "_render_die_roller($w, $width, $height, $type, $for_user, $tkey) failed with error '$err'"
	}
	set resize_task($tkey,$type) {}
}

proc EDRPsaveAndDestroy {w for_user tkey {system false}} {
	EDRPsaveValues $w $for_user $tkey $system
	destroy $w
}

proc EditSystemDieRollPresets {} {
	global local_user
	DisplayChatMessage {} {}
	EditDieRollPresets $local_user [root_user_key] true
}

proc EditRootDieRollPresets {} {
	global local_user
	DisplayChatMessage {} {}
	EditDieRollPresets $local_user [root_user_key] false
}

proc EditDieRollPresets {for_user tkey {edit_system false}} {
	global dice_preset_data
	global icon_colorwheel
	global icon_bullet_arrow_right
	global is_GM

	if {$edit_system && !$is_GM} {
		DEBUG 0 "You are not authorized to edit system presets."
		return
	}

	set w .edrp[to_window_id $tkey]

	if {[winfo exists $w]} {
		DEBUG 0 "There is already a die roll preset editor window open for user $for_user; not making another."
		return
	}

	toplevel $w
	if {$edit_system} {
		wm title $w "Manage SYSTEM Die-Roll Presets \[as $for_user\]"
		set dictpfx Global
		set tabpfx {Global }
		set varpfx {$$}
	} else {
		wm title $w "Manage Die-Roll Presets for $for_user"
		set dictpfx {}
		set tabpfx {}
		set varpfx {$}
	}
	ttk::notebook $w.n
	sframe new $w.n.r
	sframe new $w.n.gr
	sframe new $w.n.m
	sframe new $w.n.gm
	sframe new $w.n.t
	sframe new $w.n.gt
	sframe new $w.n.c
	sframe new $w.n.gc
	set wnr [sframe content $w.n.r]
	set wngr [sframe content $w.n.gr]
	set wnm [sframe content $w.n.m]
	set wngm [sframe content $w.n.gm]
	set wnt [sframe content $w.n.t]
	set wngt [sframe content $w.n.gt]
	set wnc [sframe content $w.n.c]
	set wngc [sframe content $w.n.gc]
	array set tabid {
		Rolls 0
		Modifiers 1
		Tables 2
		Custom 3
		GlobalRolls 4
		GlobalModifiers 5
		GlobalTables 6
		GlobalCustom 7
	}
	$w.n add $w.n.r -state normal -sticky news -text "${tabpfx}Rolls"
	$w.n add $w.n.m -state normal -sticky news -text "${tabpfx}Modifiers"
	$w.n add $w.n.t -state normal -sticky news -text "${tabpfx}Tables"
	$w.n add $w.n.c -state disabled -sticky news -text Custom
	$w.n add $w.n.gr -state disabled -sticky news -text "Global Rolls"
	$w.n add $w.n.gm -state disabled -sticky news -text "Global Modifiers"
	$w.n add $w.n.gt -state disabled -sticky news -text "Global Tables"
	$w.n add $w.n.gc -state disabled -sticky news -text "Global Custom"
	pack $w.n -expand 1 -fill both
	pack [button $w.can -text Cancel -command "if \[tk_messageBox -type yesno -parent $w -icon warning -title {Confirm Cancel} -message {Are you sure you wish to abandon any changes you made to the die-roll preset list?} -default no] {destroy $w}"] -side left
	pack [button $w.ok -text Save -command [list EDRPsaveAndDestroy $w $for_user $tkey $edit_system]] -side right


	global icon_anchor_n icon_anchor_s icon_delete icon_add icon_pencil
	grid x [label $wnr.t0 -text Group] \
		[label $wnr.t1 -text Name] [label $wnr.t2 -text Description] [label $wnr.t3 -text {Die-Roll Specification}] - \
		x x [button $wnr.add -image $icon_add -command [list EDRPadd $w $for_user $tkey]] -sticky we
	::tooltip::tooltip $wnr.add "Add a new die-roll preset"
	grid x [label $wnt.t0 -text Group] \
		[label $wnt.t1 -text Name] [label $wnt.t2 -text Description] [label $wnt.t3 -text {Die-Roll}] x [label $wnt.t4 -text {Table}] [button $wnt.add -image $icon_add -command [list EDRTadd $w $for_user $tkey]] -sticky we
	::tooltip::tooltip $wnt.add "Add a new table"

	set dice_preset_data(tmp_presets,$tkey) [PresetLists dice_preset_data $tkey]
	array unset dice_preset_data "tmp_presets,$tkey,*"
	if {$edit_system} {
		# move global items to the editable areas
		foreach area {Modifiers Rolls Tables CustomRolls} {
			dict set dice_preset_data(tmp_presets,$tkey) $area [dict get $dice_preset_data(tmp_presets,$tkey) Global$area]
			dict set dice_preset_data(tmp_presets,$tkey) Global$area {}
		}
	}

#
# process the read-only global things.
# This uses some new logic that could be the start of a refactored approach to how the rest of
# this routine could be moved to use in the future as well, which is why it looks a bit different.
#
#
	if {!$edit_system} {
	set mi 0
	set pi 0
	set di 0
	set ti 0
	foreach preset [concat \
		[dict get $dice_preset_data(tmp_presets,$tkey) GlobalModifiers] \
		[dict get $dice_preset_data(tmp_presets,$tkey) GlobalRolls] \
		[dict get $dice_preset_data(tmp_presets,$tkey) GlobalTables] \
		[dict get $dice_preset_data(tmp_presets,$tkey) GlobalCustomRolls] \
	] {
		set pd [GetPresetDetails $preset]
		switch [dict get $pd type] {
			preset {
				if {$pi == 0} {
					# set up the notebook pane
					$w.n tab $tabid(GlobalRolls) -state normal
					grid [label $wngr.tg -text Group] \
						[label $wngr.t0 -text Name] \
						[label $wngr.t1 -text Description] \
						[label $wngr.t2 -text {Die Roll Specification}] \
						-sticky we
				}
				grid [label $wngr.group$pi -text [join [dict get $pd group] "\u25B6"]] \
					[label $wngr.name$pi -text [dict get $pd name] -anchor w -relief groove] \
					[label $wngr.desc$pi -text [dict get $pd description] -anchor w -relief groove] \
					[label $wngr.dspec$pi -text [dict get $pd dieroll] -anchor w -relief groove] \
					-sticky we

				incr pi
			}
			modifier {
				if {$mi == 0} {
					# set up the notebook pane
					$w.n tab $tabid(GlobalModifiers) -state normal
					grid [label $wngm.tg -text Group] [label $wngm.t0 -text On] [label $wngm.t1 -text Name] [label $wngm.t2 -text Description] [label $wngm.t3 -text Expression] \
						x x -sticky ew
				}

				if {[dict get $pd enabled]} {
					set enabled "(en)"
				} else {
					set enabled ""
				}
				if {[set varname [dict get $pd var]] ne {}} {
					set varname "as symbol \$\$\{$varname\}"
				}
				if {[dict get $pd global]} {
					set glb "(...)x"
				} else {
					set glb ""
				}
				grid [label $wngm.group$mi -text [join [dict get $pd group] "\u25B6"]] \
					[label $wngm.en$mi -text $enabled] \
					[label $wngm.name$mi -text [dict get $pd name] -anchor w -relief groove] \
					[label $wngm.desc$mi -text [dict get $pd description] -anchor w -relief groove] \
					[label $wngm.dspec$mi -text [dict get $pd dieroll] -anchor w -relief groove] \
					[label $wngm.asvar$mi -text $varname -anchor w ] \
					[label $wngm.glb$mi -text $glb -anchor w ] \
					-sticky we
				incr mi
			}
			table {
				if {$ti == 0} {
					$w.n tab $tabid(GlobalTables) -state normal
					grid [label $wngt.tg -text Group] [label $wngt.t0 -text Name] \
						[label $wngt.t1 -text Description] [label $wngt.t2 -text {Die Roll}] \
						[label $wngt.t3 -text Table] -sticky we
				}


				grid [label $wngt.group$ti -text [join [dict get $pd group] "\u25B6"]] \
					[label $wngt.name$ti -text [dict get $pd name] -anchor w -relief groove] \
					[label $wngt.desc$ti -text [dict get $pd description] -anchor w -relief groove] \
					[label $wngt.dieroll$ti -text [dict get $pd dieroll] -anchor w -relief groove] \
					[frame $wngt.table$ti] \
					-sticky we
				set tii 0
				set istart 1
				foreach {tabn tabtxt} [dict get $pd table] {
					SetTableColors $tii fgcolor bgcolor
					if {$istart == $tabn} {
						set nlabel $tabn
						set istart [expr $tabn + 1]
					} elseif {$tabn eq "*"} {
						if {$istart ne {}} {
							set nlabel "${istart}+"
						} else {
							set nlabel "*"
						}
					} elseif {$istart eq {}} {
						set nlabel "...-${tabn}"
					} else {
						if {[catch {
							set nlabel [format "%d-%d" $istart $tabn]
							set istart [expr $tabn + 1]
						}]} {
							set nlabel "${istart}-${tabn}"
							set istart {}
						}
					}
					grid [label $wngt.table$ti.n$tii -text $nlabel -anchor e -relief groove -fg $fgcolor -bg $bgcolor] \
						[label $wngt.table$ti.t$tii -text $tabtxt -anchor w -relief groove -fg $fgcolor -bg $bgcolor] \
						-sticky we
					incr tii
				}
				incr ti
			}
			default {
				if {$di == 0} {
					$w.n tab $tabid(GlobalCustom) -state normal
					grid [label $wngc.t0 -text Name] [label $wngc.t1 -text Description] [label $wngc.t2 -text Expression] -sticky ew
				}
				grid [label $wngc.name$di -text [dict get $preset Name] -relief groove -anchor w] \
					[label $wngc.desc$di -text [dict get $preset Description] -relief groove -anchor w] \
					[label $wngc.dspec$di -text [dict get $preset DieRollSpec] -relief groove -anchor w] \
					-sticky ew
				incr di
			}
		}
	}
	}

	#
#	set global_vars [array names dice_preset_data "sys,preset,*"]
#	DEBUG 0 "global_vars $global_vars"







#	 **NEW**		DieRollPresetState(sys,gvar,<name>) = dierollspec
#	 **NEW**		DieRollPresetState(sys,gvar_on,<name>) = enabled (bool)
# dict get preset DisplayName/Description/DieRollSpec/Group/Enabled/Global




	set i 0
	foreach preset [dict get $dice_preset_data(tmp_presets,$tkey) Tables] {
		if {![dict exists $preset Group] || [set pgroup [dict get $preset Group]] eq {}} {
			set pgroup {}
		}
		grid [button $wnt.gbtn$i -image $icon_bullet_arrow_right -command [list EditDRPGroup $wnt.group$i "Groups for Table #$i"]] \
			[label $wnt.group$i -text $pgroup] \
			[entry $wnt.name$i] \
			[entry $wnt.desc$i] \
			[entry $wnt.dspec$i] \
			[button $wnt.edit$i -image $icon_pencil -command [list EDRTtbl $wnt.tbl$i $tkey $i "Table #$i"]] \
			[frame $wnt.tbl$i] \
			[button $wnt.del$i -image $icon_delete -command [list EDRTdel $w $for_user $tkey $i]] -sticky we
		set dice_preset_data(tmp_presets,$tkey,T,$i) $preset
		set dice_preset_data(tmp_presets,$tkey,T,$i,d) [set details [GetPresetDetails $preset]]
		$wnt.name$i insert 0 [dict get $details name]
		$wnt.desc$i insert 0 [dict get $details description]
		$wnt.dspec$i insert 0 [dict get $details dieroll]
		set ti 0
		set istart 1
		foreach {n t} [dict get $details table] {
			SetTableColors $ti fgcolor bgcolor
			if {$istart == $n} {
				set nlabel $n
				set istart [expr $n + 1]
			} elseif {$n eq "*"} {
				if {$istart ne {}} {
					set nlabel "${istart}+"
				} else {
					set nlabel "*"
				}
			} elseif {$istart eq {}} {
				set nlabel "...-${n}"
			} else {
				if {[catch {
					set nlabel [format "%d-%d" $istart $n]
					set istart [expr $n + 1]
				}]} {
					set nlabel "${istart}-${n}"
					set istart {}
				}
			}

			grid [label $wnt.tbl$i.n$ti -text $nlabel -anchor e -relief groove -fg $fgcolor -bg $bgcolor] [label $wnt.tbl$i.t$ti -text $t -anchor w -relief groove -fg $fgcolor -bg $bgcolor] -sticky we
			incr ti
		}
		incr i
	}

	set i 0
	foreach preset [dict get $dice_preset_data(tmp_presets,$tkey) Rolls] {
		set dice_preset_data(tmp_presets,$tkey,R,$i) $preset
		if {![dict exists $preset Group] || [set pgroup [dict get $preset Group]] eq {}} {
			set pgroup {}
		}
		grid [button $wnr.gbtn$i -image $icon_bullet_arrow_right -command [list EditDRPGroup $wnr.group$i "Groups for Preset #$i"]] \
		     [label $wnr.group$i -text $pgroup] \
		     [entry $wnr.name$i] [entry $wnr.desc$i] \
		     [button $wnr.color$i -image $icon_colorwheel -command [list EditColorBoxTitle "EDRP_text,$tkey,$i"]] \
		     [entry $wnr.dspec$i -textvariable dice_preset_data(EDRP_text,$tkey,$i)] \
		     [button $wnr.up$i -image $icon_anchor_n -command [list EDRPraise $w $for_user $tkey $i]] \
		     [button $wnr.dn$i -image $icon_anchor_s -command [list EDRPlower $w $for_user $tkey $i]] \
		     [button $wnr.del$i -image $icon_delete -command [list EDRPdel $w $for_user $tkey $i]] -sticky we
		$wnr.name$i insert 0 [dict get $preset DisplayName]
		$wnr.desc$i insert 0 [dict get $preset Description]
		set dice_preset_data(EDRP_text,$tkey,$i) [dict get $preset DieRollSpec]
		#$wnr.dspec$i insert 0 [dict get $preset DieRollSpec]
		::tooltip::tooltip $wnr.gbtn$i "Edit group(s) to which this preset belongs"
		::tooltip::tooltip $wnr.color$i "Edit color(s) for die-roll title string"
		::tooltip::tooltip $wnr.up$i "Move this die-roll up in the list"
		::tooltip::tooltip $wnr.dn$i "Move this die-roll down in the list"
		::tooltip::tooltip $wnr.del$i "Remove this die-roll from the list"
		if {$i == 0} {
			$wnr.up$i configure -state disabled
		}
		incr i
	}
	if {$i > 0} {
		$wnr.dn[expr $i - 1] configure -state disabled
	}

	grid [label $wnc.t1 -text Name] [label $wnc.t2 -text Description] [label $wnc.t3 -text {Die-Roll Specification}] -sticky we
	set i 0
	if {[llength [set custompresets [dict get $dice_preset_data(tmp_presets,$tkey) CustomRolls]]] > 0} {
		$w.n tab $tabid(Custom) -state normal
		grid [label $wnc.desc -text "These presets don't conform to standard conventions so we can't manage them"] - - - -sticky w
		grid [label $wnc.desc1 -text "as normal. They appear here as-is from your server preset list."] - - - -sticky w
		foreach preset $custompresets {
			grid [entry $wnc.nameC$i] [entry $wnc.descC$i] [entry $wnc.dspecC$i] \
			     [button $wnc.delC$i -image $icon_delete -command [list EDRPdelCustom $w $for_user $tkey $i]] -sticky we
			$wnc.nameC$i insert 0 [dict get $preset Name]
			$wnc.descC$i insert 0 [dict get $preset Description]
			$wnc.dspecC$i insert 0 [dict get $preset DieRollSpec]
			::tooltip::tooltip $wnc.delC$i "Remove this die-roll from the list"
			incr i
		}
	}

	set i 0
	grid [label $wnm.t_] [label $wnm.tg -text Group] [label $wnm.t0 -text On] [label $wnm.t1 -text Name] [label $wnm.t2 -text Description] [label $wnm.t3 -text Expression] \
		x x x x x x [button $wnm.add -image $icon_add -command [list EDRPaddModifier $w $for_user $tkey]] -sticky ew
	foreach preset [dict get $dice_preset_data(tmp_presets,$tkey) Modifiers] {
		set dice_preset_data(tmp_presets,$tkey,M,$i) $preset
		grid [button $wnm.gbtn$i -image $icon_bullet_arrow_right -command [list EditDRPGroup $wnm.group$i "Groups for Modifier #$i"]] \
		     [label $wnm.group$i -text {}] \
		     [ttk::checkbutton $wnm.en$i -text On -offvalue 0 -onvalue 1 -variable dice_preset_data(EDRP_mod_en,$tkey,$i)] \
		     [entry $wnm.name$i] \
		     [entry $wnm.desc$i] \
		     [entry $wnm.dspec$i] \
		     [ttk::checkbutton $wnm.varp$i -text "as symbol ${varpfx}\{" -variable dice_preset_data(EDRP_mod_ven,$tkey,$i) -command [list EDRPcheckVar $w $for_user $tkey $i]]\
		     [entry $wnm.var$i -width 6]\
		     [label $wnm.rb$i -text \} -anchor w] \
		     [ttk::checkbutton $wnm.g$i -text "()x" -variable dice_preset_data(EDRP_mod_g,$tkey,$i)] \
		     [button $wnm.up$i -image $icon_anchor_n -command [list EDRPraiseModifier $w $for_user $tkey $i]] \
		     [button $wnm.dn$i -image $icon_anchor_s -command [list EDRPlowerModifier $w $for_user $tkey $i]] \
		     [button $wnm.del$i -image $icon_delete -command [list EDRPdelModifier $w $for_user $tkey $i]] -sticky ew
	     	::tooltip::tooltip $wnm.g$i "If checked, adds (...) around expression before adding this modifier."
	     	::tooltip::tooltip $wnm.up$i "Move this modifier up in the list"
	     	::tooltip::tooltip $wnm.dn$i "Move this modifier down in the list"
	     	::tooltip::tooltip $wnm.del$i "Remove this modifier from the list"
	     	::tooltip::tooltip $wnm.en$i "If checked, the modifier is in-play"
	     	::tooltip::tooltip $wnm.varp$i "If checked, the modifier is used in place of <var>, otherwise added to all die rolls"
#		trace add variable dice_preset_data(EDRP_mod_en,$tkey,$i) {array read write unset} TRACEvar
		set dice_preset_data(EDRP_mod_en,$tkey,$i) [::gmaproto::int_bool [dict get $preset Enabled]]
#		set dice_preset_data(EDRP_mod_en,$tkey,$i) false
		set dice_preset_data(EDRP_mod_g,$tkey,$i) [::gmaproto::int_bool [dict get $preset Global]]
		if {[dict get $preset Variable] eq {}} {
			set dice_preset_data(EDRP_mod_ven,$tkey,$i) 0
			$wnm.var$i configure -state disabled
			$wnm.g$i configure -state normal
		} else {
			set dice_preset_data(EDRP_mod_ven,$tkey,$i) 1
			$wnm.var$i insert 0 [dict get $preset Variable]
			$wnm.g$i configure -state disabled
			set dice_preset_data(EDRP_mod_g,$tkey,$i) 0
		}
		$wnm.name$i insert 0 [dict get $preset DisplayName]
		$wnm.desc$i insert 0 [dict get $preset Description]
		$wnm.dspec$i insert 0 [dict get $preset DieRollSpec]
		$wnm.group$i configure -text [dict get $preset Group]
		if {$i == 0} {
			$wnm.up$i configure -state disabled
		}
		incr i
	}
	if {$i > 0} {
		$wnm.dn[expr $i - 1] configure -state disabled
	}
	grid columnconfigure $wnr 5 -weight 2
	grid columnconfigure $wnm 5 -weight 2
	grid columnconfigure $wnc 2 -weight 2
	grid columnconfigure $wnt 6 -weight 2
	grid columnconfigure $wngr 3 -weight 2
	grid columnconfigure $wngm 4 -weight 2
	grid columnconfigure $wngt 4 -weight 2


	tkwait window $w
	# TODO render list again
}

#
# Given a die-roll title string, allow editing the colorbox attributes
# then call a callback with the resulting value
#
#  ______________________________________________________________________
# |                                                                  [+] |
# | [______________] [] foreground [C] [] background [C] [example__] [-] |
# | [______________] [] foreground [C] [] background [C] [example__] [-] |
# | [______________] [] foreground [C] [] background [C] [example__] [-] |
# |______________________________________________________________________|
# |[Cancel]__________________________________________________________[OK]|
#
# ≡ 2261
# ‖ 2016
set ECBTstate(seq) 0
proc EditColorBoxTitle {key} {
	global ECBTstate
	global global_bg_color
	global icon_add
	global dice_preset_data
	set w .ecbt[incr ECBTstate(seq)]
	set ECBTstate($w,size) 0
	set ECBTstate($w,key) $key
	set title [string map {<= ≤ >= ≥} $dice_preset_data($key)]

	if {[llength [set parts [split $title =]]] < 2} {
		set ECBTstate($w,spec) $title
		set title {}
	} else {
		set title [lindex $parts 0]
		set ECBTstate($w,spec) [join [lrange $parts 1 end] =]
	}

	toplevel $w -background $global_bg_color
	if {[catch {wm title $w "Edit Colorized Die-Roll Title"}]} {
		wm title $w "Edit Colorized Die-Roll Title $ECBTseq"
	}
	grid [label $w.t1 -text "Title Text"] \
		[label $w.t2 -text "Title Colors"] - - - \
		[label $w.t3 -text "Preview"] \
		[button $w.add -image $icon_add -command "ECBT_add $w"] -sticky we
	grid [button $w.canc -text Cancel -command "ECBT_cancel $w"] - - - - - \
		[button $w.ok -text OK -command "ECBT_ok $w"] -sticky w

	set i 0
	set titles [split $title "\u2016"]
	foreach thisTitle $titles {
		set components [split $thisTitle "\u2261"]
		ECBT_add $w
		ECBT_set $w [incr i] $components
	}
}

proc ECBT_cancel {w} {
	global ECBTstate
	array unset ECBTstate $w,*
	destroy $w
}

proc ECBT_ok {w} {
	global ECBTstate
	global dice_preset_data
	set titles [ECBT_get_titles $w]
	set parts {}
	foreach t $titles {
		set txt [dict get $t Text]
		if {[dict get $t FGen]} {
			append txt "\u2261[::gmacolors::rgb_name [dict get $t Foreground]]"
			if {[dict get $t BGen]} {
				append txt "\u2261[::gmacolors::rgb_name [dict get $t Background]]"
			}
		}
		lappend parts $txt
	}
	
	if {$parts eq {}} {
		set dice_preset_data($ECBTstate($w,key)) $ECBTstate($w,spec)
	} else {
		set dice_preset_data($ECBTstate($w,key)) "[join $parts \u2016]=$ECBTstate($w,spec)"
	}
	ECBT_cancel $w
}

# | [______________] [] foreground [C] [] background [C] [example__] [-] |
#    name            fgen          fg  bgen          bg   ex         del
proc ECBT_fgen {w i} {
	global ECBTstate
	global global_bg_color
	if {$ECBTstate($w,$i,fgen)} {
		$w.fg$i configure -state normal
		$w.bgen$i configure -state normal
	} else {
		$w.fg$i configure -state disabled -text white -background $global_bg_color
		$w.bgen$i configure -state disabled
		set ECBTstate($w,$i,bgen) 0
		set ECBTstate($w,$i,fg) white
		ECBT_bgen $w $i
	}
	ECBT_show_colors $w $i
}

proc ECBT_bgen {w i} {
	global ECBTstate
	global global_bg_color
	if {$ECBTstate($w,$i,bgen)} {
		$w.bg$i configure -state normal
	} else {
		$w.bg$i configure -state disabled -text auto -background $global_bg_color
		set ECBTstate($w,$i,bg) [::tk::Darken $ECBTstate($w,$i,fg) 40]
	}
	ECBT_show_colors $w $i
}

proc ECBT_set_color {w i fld} {
	global ECBTstate
	if {[set chosencolor [tk_chooseColor -initialcolor $ECBTstate($w,$i,$fld) -parent $w -title "Choose $fld color for title"]] ne {}} {
		set ECBTstate($w,$i,$fld) $chosencolor
		$w.$fld$i configure -background $chosencolor -text [::gmacolors::rgb_name $chosencolor]
	}
	if {$fld eq "fg" && !$ECBTstate($w,$i,bgen)} {
		set ECBTstate($w,$i,bg) [::tk::Darken $ECBTstate($w,$i,fg) 40]
	}
	ECBT_show_colors $w $i
}

proc ECBT_show_colors {w i} {
	global ECBTstate
	$w.ex$i configure -foreground $ECBTstate($w,$i,fg) -background $ECBTstate($w,$i,bg)
}

proc ECBT_del {w i} {
	global ECBTstate
	set last $ECBTstate($w,size)
	set titles [lreplace [ECBT_get_titles $w] $i-1 $i-1]
	grid forget $w.title$last $w.fgen$last $w.fg$last $w.bgen$last $w.bg$last $w.ex$last $w.del$last
	destroy $w.title$last $w.fgen$last $w.fg$last $w.bgen$last $w.bg$last $w.ex$last $w.del$last
	incr ECBTstate($w,size) -1
	ECBT_put_titles $w $titles
}

proc ECBT_get_titles {w} {
	global ECBTstate
	set titles {}

	for {set i 1} {$i <= $ECBTstate($w,size)} {incr i} {
		lappend titles [dict create \
			Text       $ECBTstate($w,$i,text) \
			Foreground $ECBTstate($w,$i,fg) \
			Background $ECBTstate($w,$i,bg) \
			FGen       $ECBTstate($w,$i,fgen) \
			BGen       $ECBTstate($w,$i,bgen) \
		]
	}
	return $titles
}

proc ECBT_put_titles {w titles} {
	set i 0
	foreach title $titles {
		incr i
		if {[dict get $title FGen]} {
			if {[dict get $title BGen]} {
				set c [list [dict get $title Text] [dict get $title Foreground] [dict get $title Background]]
			} else {
				set c [list [dict get $title Text] [dict get $title Foreground]]
			}
		} else {
			set c [list [dict get $title Text]]
		}
		ECBT_set $w $i $c
	}
}

proc ECBT_set {w i components} {
	global ECBTstate
	global global_bg_color
	set ECBTstate($w,$i,text) [lindex $components 0]
	if {[llength $components] > 1 && [lindex $components 1] ne {}} {
		# there is a foreground color
		set ECBTstate($w,$i,fgen) 1
		set ECBTstate($w,$i,fg) [string trim [lindex $components 1]]
		if {[catch {
			$w.fg$i configure -state normal -text [::gmacolors::rgb_name [lindex $components 1]] -background [lindex $components 1]
		}]} {
			$w.fg$i configure -state normal -text invalid -background $global_bg_color
		}
		$w.bgen$i configure -state normal

		if {[llength $components] > 2 && [lindex $components 2] ne {}} {
			# there is a background color
			set ECBTstate($w,$i,bgen) 1
			set ECBTstate($w,$i,bg) [string trim [lindex $components 2]]
			if {[catch {
				$w.bg$i configure -state normal -text [::gmacolors::rgb_name [lindex $components 2]]
			}]} {
				$w.bg$i configure -state normal -text invalid -background $global_bg_color
			}

		} else {
			# automatic background color
			set ECBTstate($w,$i,bgen) 0
			if {[catch {
				set ECBTstate($w,$i,bg) [::tk::Darken [string trim [lindex $components 1]] 40]
				$w.bg$i configure -state disabled -text auto -background $ECBTstate($w,$i,bg)
			}]} {
				set ECBTstate($w,$i,bg) [::tk::Darken white 40]
				$w.bg$i configure -state disabled -text auto -background $global_bg_color
			}
		}
	} else {
		# no color set; use white
		set ECBTstate($w,$i,fgen) 0
		set ECBTstate($w,$i,bgen) 0
		set ECBTstate($w,$i,fg) white
		set ECBTstate($w,$i,bg) [::tk::Darken white 40]
		$w.fg$i configure -state disabled -text auto -background $global_bg_color
		$w.bg$i configure -state disabled -text auto -background $global_bg_color
		$w.bgen$i configure -state disabled 
	}
	$w.ex$i configure -foreground $ECBTstate($w,$i,fg) -background $ECBTstate($w,$i,bg)
}

	
proc ECBT_add {w} {
	global ECBTstate icon_delete
	set i [incr ECBTstate($w,size)]
	set ECBTstate($w,$i,fgen) 0
	set ECBTstate($w,$i,text) {}
	set ECBTstate($w,$i,bgen) 0
	set ECBTstate($w,$i,fg) white
	set ECBTstate($w,$i,bg) [::tk::Darken white 40]
	grid forget $w.canc $w.ok
	destroy $w.canc $w.ok
	grid [entry $w.title$i -textvariable ECBTstate($w,$i,text)] \
		[ttk::checkbutton $w.fgen$i -text foreground -variable ECBTstate($w,$i,fgen) -command "ECBT_fgen $w $i"] \
		[button $w.fg$i -text white -state disabled -command "ECBT_set_color $w $i fg"] \
		[ttk::checkbutton $w.bgen$i -state disabled -text background -variable ECBTstate($w,$i,bgen) -command "ECBT_bgen $w $i"] \
		[button $w.bg$i -text auto -state disabled -command "ECBT_set_color $w $i bg"] \
		[label $w.ex$i -relief raised -bd 2 -textvariable ECBTstate($w,$i,text) -foreground white -background [::tk::Darken white 40]] \
		[button $w.del$i -image $icon_delete -command "ECBT_del $w $i"] \
			-sticky ew
	grid [button $w.canc -text Cancel -command "ECBT_cancel $w"] - - - - - \
		[button $w.ok -text OK -command "ECBT_ok $w"] -sticky w
}

#
# while editing, we keep the preset data in the global variable tmp_presets
# which is a dict of
# 	Rolls=> ordered list of dict with DisplayName and DisplaySeq, AreaTag, Group
# 	CustomRolls=>same but with no sequence data (since we couldn't understand it)
# 	Modifiers=>ordered list of dict of ? +AreaTag, Group
# permanent data is in dice_preset_data
# which is an array of presetname=>dict Name Description DieRollSpec
# presetname should track <DisplaySeq>|<DisplayName>
#

# Send the new presets to the server.
# It will send them back to us which will force an update
# in the client at that time.
#
# if system is true, we're sending the system-wide preset list, not our personal set.
#
proc EDRPsaveValues {w for_user tkey {system false}} {
	global dice_preset_data
	set newpresets {}
	EDRPgetValues $w $for_user $tkey
	# Name:
	#   $[<area>]<seq><group>|<name>
	#   \_______/\___/\_____/ \____/
	#   AreaTag    |   Group   Displayname
	#              DisplaySeq
	foreach p [dict get $dice_preset_data(tmp_presets,$tkey) Rolls] {
		if {[string is digit -strict [set n [dict get $p DisplaySeq]]] && [scan $n %d nn] == 1} {

			set n [format "%03d" $nn]
		}
		if {[dict exists $p AreaTag] && [set at [dict get $p AreaTag]] ne {}} {
			set dname "$at$n"
		} else {
			set dname $n
		}
		if {[dict exists $p Group] && [set grp [dict get $p Group]] ne {}} {
			append dname "\u25B6$grp"
		}
		if {[set dn [dict get $p DisplayName]] ne {}} {
			append dname "|$dn"
		}
		lappend newpresets [dict create Name $dname\
						Description [dict get $p Description]\
						DieRollSpec [dict get $p DieRollSpec]]
	}
	foreach p [dict get $dice_preset_data(tmp_presets,$tkey) CustomRolls] {
		lappend newpresets [dict create Name [dict get $p Name] \
						Description [dict get $p Description]\
						DieRollSpec [dict get $p DieRollSpec]]
	}
	foreach p [dict get $dice_preset_data(tmp_presets,$tkey) Modifiers] {
		# Name:
		#   §<seq><group>;<var>;<flags>[;<client>]|<name>
		#    \___/\_____/ \___/ \_____/  \______/  \____/
		#      |     |      |      |      ClientData DisplayName
		#      |     |      |      Global
		#      |     |      |      Enabled
		#      |     Group  Variable
		#      DisplaySeq
		set flags {}
		if {[dict get $p Enabled]} {
			append flags e
		}
		if {[dict get $p Global]} {
			append flags g
		}
		if {[string is digit -strict [set n [dict get $p DisplaySeq]]] && [scan $n %d nn] == 1} {
			set n [format "%03d" $nn]
		}
		set dname "\u00A7$n"
		if {[dict exists $p Group] && [set grp [dict get $p Group]] ne {}} {
			append dname "\u25B6$grp"
		}
		append dname ";[dict get $p Variable];$flags"
		if {[dict exists $p ClientData] && [set cdata [dict get $p ClientData]] ne {}} {
			append dname ";$cdata"
		}
		if {[set dn [dict get $p DisplayName]] ne {}} {
			append dname "|$dn"
		}
		lappend newpresets [dict create Name $dname \
						Description [dict get $p Description]\
						DieRollSpec [dict get $p DieRollSpec]]
	}
	foreach p [dict get $dice_preset_data(tmp_presets,$tkey) Tables] {
		# these are already encoded so just send them out
		lappend newpresets $p
	}
	UpdateDicePresets $newpresets $for_user $system
}

# remove item #i from rolls
proc EDRPdel {w for_user tkey i} {
	global dice_preset_data
	set wnr [sframe content $w.n.r]
	set wnm [sframe content $w.n.m]
	EDRPgetValues $w $for_user $tkey
	dict set dice_preset_data(tmp_presets,$tkey) Rolls [lreplace [dict get $dice_preset_data(tmp_presets,$tkey) Rolls] $i $i]
	set i [llength [dict get $dice_preset_data(tmp_presets,$tkey) Rolls]]
	grid forget $wnr.name$i $wnr.desc$i $wnr.dspec$i $wnr.up$i $wnr.dn$i $wnr.del$i $wnr.gbtn$i $wnr.group$i
	destroy $wnr.name$i $wnr.desc$i $wnr.dspec$i $wnr.up$i $wnr.dn$i $wnr.del$i $wnr.gbtn$i $wnr.group$i
	catch {
		grid forget $wnr.color$i
		destroy $wnr.color$i
	}
	EDRPresequence $w $for_user $tkey
	EDRPupdateGUI $w $for_user $tkey
}

proc EDRPdelModifier {w for_user tkey i} {
	global dice_preset_data

	set wnr [sframe content $w.n.r]
	set wnm [sframe content $w.n.m]
	EDRPgetValues $w $for_user $tkey
	dict set dice_preset_data(tmp_presets,$tkey) Modifiers [lreplace [dict get $dice_preset_data(tmp_presets,$tkey) Modifiers] $i $i]
	set i [llength [dict get $dice_preset_data(tmp_presets,$tkey) Modifiers]]
	grid forget $wnm.en$i $wnm.name$i $wnm.desc$i $wnm.dspec$i $wnm.varp$i $wnm.var$i $wnm.rb$i $wnm.up$i $wnm.dn$i $wnm.del$i $wnm.g$i $wnm.gbtn$i $wnm.group$i
	destroy $wnm.en$i $wnm.name$i $wnm.desc$i $wnm.dspec$i $wnm.varp$i $wnm.var$i $wnm.rb$i $wnm.up$i $wnm.dn$i $wnm.del$i $wnm.g$i $wnm.gbtn$i $wnm.group$i
	EDRPresequence $w $for_user $tkey
	EDRPupdateGUI $w $for_user $tkey
}

proc EDRPdelCustom {w for_user tkey i} {
	global dice_preset_data
	set wnr [sframe content $w.n.r]
	set wnm [sframe content $w.n.m]
	set wnc [sframe content $w.n.c]
	EDRPgetValues $w $for_user $tkey
	dict set dice_preset_data(tmp_presets,$tkey) CustomRolls [lreplace [dict get $dice_preset_data(tmp_presets,$tkey) CustomRolls] $i $i]
	set i [llength [dict get $dice_preset_data(tmp_presets,$tkey) CustomRolls]]
	grid forget $wnc.nameC$i $wnc.descC$i $wnc.dspecC$i $wnc.delC$i
	destroy $wnc.nameC$i $wnc.descC$i $wnc.dspecC$i $wnc.delC$i
	EDRPupdateGUI $w $for_user $tkey
}

# move item #i down one slot
proc EDRPlower {w for_user tkey i} {
	global dice_preset_data
	EDRPgetValues $w $for_user $tkey
	set n [llength [dict get $dice_preset_data(tmp_presets,$tkey) Rolls]]
	if {$i < $n-1} {
		set l [dict get $dice_preset_data(tmp_presets,$tkey) Rolls]
		dict set dice_preset_data(tmp_presets,$tkey) Rolls [lreplace $l $i $i+1 [lindex $l $i+1] [lindex $l $i]]
	}
	EDRPresequence $w $for_user $tkey
	EDRPupdateGUI $w $for_user $tkey
}

proc EDRPlowerModifier {w for_user tkey i} {
	global dice_preset_data
	EDRPgetValues $w $for_user $tkey
	set n [llength [dict get $dice_preset_data(tmp_presets,$tkey) Modifiers]]
	if {$i < $n-1} {
		set l [dict get $dice_preset_data(tmp_presets,$tkey) Modifiers]
		dict set dice_preset_data(tmp_presets,$tkey) Modifiers [lreplace $l $i $i+1 [lindex $l $i+1] [lindex $l $i]]
	}
	EDRPresequence $w $for_user $tkey
	EDRPupdateGUI $w $for_user $tkey
}

proc EDRPraise {w for_user tkey i} {
	global dice_preset_data
	EDRPgetValues $w $for_user $tkey
	set n [llength [dict get $dice_preset_data(tmp_presets,$tkey) Rolls]]
	if {$i > 0} {
		set l [dict get $dice_preset_data(tmp_presets,$tkey) Rolls]
		dict set dice_preset_data(tmp_presets,$tkey) Rolls [lreplace $l $i-1 $i [lindex $l $i] [lindex $l $i-1]]
	}
	EDRPresequence $w $for_user $tkey
	EDRPupdateGUI $w $for_user $tkey
}

proc EDRPraiseModifier {w for_user tkey i} {
	global dice_preset_data
	EDRPgetValues $w $for_user $tkey
	set n [llength [dict get $dice_preset_data(tmp_presets,$tkey) Modifiers]]
	if {$i > 0} {
		set l [dict get $dice_preset_data(tmp_presets,$tkey) Modifiers]
		dict set dice_preset_data(tmp_presets,$tkey) Modifiers [lreplace $l $i-1 $i [lindex $l $i] [lindex $l $i-1]]
	}
	EDRPresequence $w $for_user $tkey
	EDRPupdateGUI $w $for_user $tkey
}

# add a new item at the end of the Rolls list
proc EDRPresequence {w for_user tkey} {
	global dice_preset_data
	set roll_list [dict get $dice_preset_data(tmp_presets,$tkey) Rolls]
	dict set dice_preset_data(tmp_presets,$tkey) Rolls {}
	set i 0
	foreach d $roll_list {
		dict set d DisplaySeq [format %3d [incr i]]
		dict lappend dice_preset_data(tmp_presets,$tkey) Rolls $d
	}

	set mod_list [dict get $dice_preset_data(tmp_presets,$tkey) Modifiers]
	dict set dice_preset_data(tmp_presets,$tkey) Modifiers {}
	set i 0
	foreach d $mod_list {
		dict set d DisplaySeq [format %3d [incr i]]
		dict lappend dice_preset_data(tmp_presets,$tkey) Modifiers $d
	}
}

# pull field values into tmp_presets
proc EDRPgetValues {w for_user tkey} {
	global dice_preset_data
	set wnr [sframe content $w.n.r]
	set wnm [sframe content $w.n.m]
	set wnc [sframe content $w.n.c]
	set wnt [sframe content $w.n.t]
	set n [llength [dict get $dice_preset_data(tmp_presets,$tkey) Rolls]]
	dict set dice_preset_data(tmp_presets,$tkey) Rolls {}
	for {set i 0} {$i < $n} {incr i} {
		set d $dice_preset_data(tmp_presets,$tkey,R,$i)
		dict set d DisplaySeq [format %03d $i]
		dict set d DisplayName [$wnr.name$i get] 
		dict set d Description [$wnr.desc$i get] 
		dict set d DieRollSpec [$wnr.dspec$i get]
		dict set d Group [$wnr.group$i cget -text]

		dict lappend dice_preset_data(tmp_presets,$tkey) Rolls $d
	}

	set n [llength [dict get $dice_preset_data(tmp_presets,$tkey) Tables]]
	dict set dice_preset_data(tmp_presets,$tkey) Tables {}
	for {set i 0} {$i < $n} {incr i} {
		set d $dice_preset_data(tmp_presets,$tkey,T,$i,d)
		if {[dict get $d table] eq {}} {
			tk_messageBox -parent $w -type ok -icon error -title "Invalid table data" \
			-message "The table \"[$wnt.name$i get]\" does not contain any data and won't be saved."
			continue
		}

		dict set d seq [format %03d $i]
		dict set d name [$wnt.name$i get]
		dict set d description [$wnt.desc$i get]
		dict set d dieroll [$wnt.dspec$i get]
		dict set d group [split [$wnt.group$i cget -text] "\u25B6"]
		set dice_preset_data(tmp_presets,$tkey,T,$i,d) $d
		set dice_preset_data(tmp_presets,$tkey,T,$i) [set dd [EncodePresetDetails $d]]

		dict lappend dice_preset_data(tmp_presets,$tkey) Tables $dd
	}

	set n [llength [dict get $dice_preset_data(tmp_presets,$tkey) CustomRolls]]
	dict set dice_preset_data(tmp_presets,$tkey) CustomRolls {}
	for {set i 0} {$i < $n} {incr i} {
		dict lappend dice_preset_data(tmp_presets,$tkey) CustomRolls [dict create \
			Name        [$wnc.nameC$i get] \
			Description [$wnc.descC$i get] \
			DieRollSpec [$wnc.dspecC$i get] \
		]
	}

	set n [llength [dict get $dice_preset_data(tmp_presets,$tkey) Modifiers]]
	dict set dice_preset_data(tmp_presets,$tkey) Modifiers {}
	for {set i 0} {$i < $n} {incr i} {
		set d $dice_preset_data(tmp_presets,$tkey,M,$i)
		set v [string trim [$wnm.var$i get]]
		if {$v ne {}} {
			dict set d Global false
		} else {
			dict set d Global [::gmaproto::json_bool $dice_preset_data(EDRP_mod_g,$tkey,$i)]
		}
		dict set d Variable $v
		dict set d DisplayName [$wnm.name$i get]
		dict set d DisplaySeq [format %03d $i]
		dict set d Description [$wnm.desc$i get]
		dict set d DieRollSpec [$wnm.dspec$i get]
		dict set d Enabled [::gmaproto::json_bool $dice_preset_data(EDRP_mod_en,$tkey,$i)]
		dict set d Group [$wnm.group$i cget -text]
		dict lappend dice_preset_data(tmp_presets,$tkey) Modifiers $d
	}
}

# refresh the existing editor window fields from the data
proc EDRPupdateGUI {w for_user tkey} {
	global dice_preset_data
	set wnr [sframe content $w.n.r]
	set wnm [sframe content $w.n.m]
	set wnc [sframe content $w.n.c]
	set i 0
	foreach p [dict get $dice_preset_data(tmp_presets,$tkey) Rolls] {
		foreach {ww fld} {name DisplayName desc Description dspec DieRollSpec} {
			$wnr.$ww$i delete 0 end
			$wnr.$ww$i insert 0 [dict get $p $fld]
		}
		$wnr.group$i configure -text [dict get $p Group]
		if {$i == 0} {
			$wnr.up$i configure -state disabled
		} else {
			$wnr.up$i configure -state normal
		}
		$wnr.dn$i configure -state normal
		incr i
	}
	if {$i > 0} {
		$wnr.dn[expr $i - 1] configure -state disabled
	}

	set i 0
	foreach p [dict get $dice_preset_data(tmp_presets,$tkey) CustomRolls] {
		foreach {ww fld} {nameC Name descC Description dspecC DieRollSpec} {
			$wnc.$ww$i delete 0 end
			$wnc.$ww$i insert 0 [dict get $p $fld]
		}
		incr i
	}

	set i 0
	foreach p [dict get $dice_preset_data(tmp_presets,$tkey) Modifiers] {
		$wnm.var$i configure -state normal
		foreach {ww fld} {name DisplayName desc Description dspec DieRollSpec var Variable} {
			$wnm.$ww$i delete 0 end
			$wnm.$ww$i insert 0 [dict get $p $fld]
		}
		set dice_preset_data(EDRP_mod_g,$tkey,$i) [::gmaproto::int_bool [dict get $p Global]]
		if {[dict get $p Variable] eq {}} {
			set dice_preset_data(EDRP_mod_ven,$tkey,$i) 0
			$wnm.var$i configure -state disabled
			$wnm.g$i configure -state normal
		} else {
			set dice_preset_data(EDRP_mod_ven,$tkey,$i) 1
			set dice_preset_data(EDRP_mod_g,$tkey,$i) 0
			$wnm.g$i configure -state disabled
		}
		set dice_preset_data(EDRP_mod_en,$tkey,$i) [::gmaproto::int_bool [dict get $p Enabled]]
		$wnm.group$i configure -text [dict get $p Group]

		if {$i == 0} {
			$wnm.up$i configure -state disabled
		} else {
			$wnm.up$i configure -state normal
		}
		$wnm.dn$i configure -state normal
		incr i
	}
	if {$i > 0} {
		$wnm.dn[expr $i - 1] configure -state disabled
	}
}

proc EditDRPGroup {l title} {
	global EDRPdata icon_add

	set w .edrpgrp[set lid [to_window_id $l]]
	if {[winfo exists $w]} {
		DEBUG 1 "There is already a dialog open to edit $title; not making another."
		return
	}
	toplevel $w
	wm title $w $title
	grid [label $w.desc1 -text "Edit the group name(s) or leave any of them blank to remove them."] - -sticky w
	grid [label $w.desc2 -text "Click the \[+\] button to add a sub-group."] - -sticky w
	if {[set EDRPdata($lid,n) [llength [set groups [split [$l cget -text] "\u25B6"]]]] == 0} {
		set EDRPdata($lid,n) 1
	}

	for {set i 0} {$i < $EDRPdata($lid,n)} {incr i} {
		if {$i == 0} {
			grid [label $w.g$i -text Group:] [entry $w.e$i] [button $w.add -image $icon_add -command "EDRPgrpAdd $lid $w"]
		} else {
			grid [label $w.g$i -text Subgroup:] [entry $w.e$i]
		}
		$w.e$i insert 0 [lindex $groups $i]
	}
	grid [button $w.cancel -command "EDRPgrpDest $lid $w" -text Cancel] \
  	     [button $w.ok -command "EDRPgrpSave $lid $w $l" -text OK]
	grid columnconfigure $w 1 -weight 2
}
proc EditDRPGroup {l title} {
	global EDRPdata icon_add

	set w .edrpgrp[set lid [to_window_id $l]]
	if {[winfo exists $w]} {
		DEBUG 1 "There is already a dialog open to edit $title; not making another."
		return
	}
	toplevel $w
	wm title $w $title
	grid [label $w.desc1 -text "Edit the group name(s) or leave any of them blank to remove them."] - -sticky w
	grid [label $w.desc2 -text "Click the \[+\] button to add a sub-group."] - -sticky w
	if {[set EDRPdata($lid,n) [llength [set groups [split [$l cget -text] "\u25B6"]]]] == 0} {
		set EDRPdata($lid,n) 1
	}

	for {set i 0} {$i < $EDRPdata($lid,n)} {incr i} {
		if {$i == 0} {
			grid [label $w.g$i -text Group:] [entry $w.e$i] [button $w.add -image $icon_add -command "EDRPgrpAdd $lid $w"]
		} else {
			grid [label $w.g$i -text Subgroup:] [entry $w.e$i]
		}
		$w.e$i insert 0 [lindex $groups $i]
	}
	grid [button $w.cancel -command "EDRPgrpDest $lid $w" -text Cancel] \
  	     [button $w.ok -command "EDRPgrpSave $lid $w $l" -text OK]
	grid columnconfigure $w 1 -weight 2
}

proc EDRPgrpAdd {k w} {
	global EDRPdata
	grid forget $w.cancel $w.ok
	grid [label $w.g$EDRPdata($k,n) -text Subgroup:] [entry $w.e$EDRPdata($k,n)]
	grid $w.cancel $w.ok
	incr EDRPdata($k,n)
}

proc EDRPgrpSave {k w l} {
	global EDRPdata
	set grp {}
	for {set i 0} {$i < $EDRPdata($k,n)} {incr i} {
		if {[set gp [string trim [$w.e$i get]]] ne {}} {
			lappend grp $gp
		}
	}
	$l configure -text [join $grp "\u25B6"]
	EDRPgrpDest $k $w
}

proc EDRPgrpDest {k w} {
	global EDRPdata
	array unset EDRPdata "$k,*"
	destroy $w
}

proc EDRTtbl {wfld tkey i title} {
	set rw .edrtTbl_${i}_${tkey}
	if {[winfo exists $rw]} {
		return
	}


	global global_bg_color dice_preset_data
	global icon_add icon_delete
	toplevel $rw -background $global_bg_color
	wm title $rw "Edit $title Data \[$tkey#$i\]"
	set w $rw.f
	frame $w
	pack $w -side top -expand true -fill both
	set p [GetPresetDetails $dice_preset_data(tmp_presets,$tkey,T,$i)]
	set dice_preset_data(tmp_presets,$tkey,T,$i,m) [::gmaproto::int_bool [dict get $p markup]]
	grid [ttk::checkbutton $w.markup -text {Allow markup formatting} -variable dice_preset_data(tmp_presets,$tkey,T,$i,m) -onvalue 1 -offvalue 0]  \
		[label $w.ttl -text Table] \
		[button $w.add -image $icon_add -command [list EDRTtblAdd $w $tkey $i]] -sticky we
	grid [frame $w.tbl] - - -sticky new
	set row 0
	foreach {v t} [set tbl [dict get $p table]] {
		grid [entry $w.tbl.v$row -justify right -textvariable dice_preset_data(tmp_presets,$tkey,T,$i,v$row)] \
			[entry $w.tbl.t$row -justify left -textvariable dice_preset_data(tmp_presets,$tkey,T,$i,t$row)] \
			[button $w.tbl.del$row -image $icon_delete -command [list EDRTtblDel $w $tkey $i $row]] \
			-sticky ew
		set dice_preset_data(tmp_presets,$tkey,T,$i,v$row) $v
		set dice_preset_data(tmp_presets,$tkey,T,$i,t$row) $t
		incr row
	}
	set dice_preset_data(tmp_presets,$tkey,T,$i,l) $row
	if {$row > 0} {
		set dice_preset_data(tmp_presets,$tkey,T,$i,v[expr $row-1]) *
		$w.tbl.v[expr $row-1] configure -state disabled -justify center
	}
	pack [button $rw.cancel -text Cancel -command [list EDRTtblCan $rw $tkey $i]] -side left
	pack [button $rw.ok -text Save -command [list EDRTtblSave $rw $tkey $i $wfld]] -side right
	wm protocol $rw WM_DELETE_WINDOW [list EDRTtblCan $rw $tkey $i]
	grid columnconfigure $w.tbl 1 -weight 2
	grid columnconfigure $w 1 -weight 2
}

proc EDRTtblSave {rw tkey i wfld} {
	global dice_preset_data
	set limit $dice_preset_data(tmp_presets,$tkey,T,$i,l)
	set lastidx [expr $limit - 1]
	set newtable {}
	if {$limit == 0} {
		tk_messageBox -parent $rw -type ok -icon error -title "Invalid table data" \
			-message "This table contains errors. Correct the problem before saving the table." \
			-detail "The table does not contain any data."
		return
	}

	for {set r 0} {$r < $limit} {incr r} {
		set v $dice_preset_data(tmp_presets,$tkey,T,$i,v$r)
		set t $dice_preset_data(tmp_presets,$tkey,T,$i,t$r)
		if {$r < $lastidx && ![string is integer -strict $v]} {
			tk_messageBox -parent $rw -type ok -icon error -title "Invalid table data" \
				-message "This table contains errors. Correct the problem before saving the table." \
				-detail "The values in the left column must be integers, except the last one, which must be \"*\". In this case, \"$v\" is not an integer."
			return
		}
		if {$r == $lastidx && $v ne "*"} {
			tk_messageBox -parent $rw -type ok -icon error -title "Invalid table data" \
				-message "This table contains errors. Correct the problem before saving the table." \
				-detail "The values in the left column must be integers, except the last one, which must be \"*\". In this case, your last value is $v instead of \"*\"."
			return
		}
		if {[string trim $t] eq {}} {
			tk_messageBox -parent $rw -type ok -icon error -title "Invalid table data" \
				-message "This table contains errors. Correct the problem before saving the table." \
				-detail "The messages in the right column must not be blank."
			return
		}
		if {$r == 0} {
			set last $v
		} elseif {$r < $lastidx && $v <= $last} {
			tk_messageBox -parent $rw -type ok -icon error -title "Invalid table data" \
				-message "This table contains errors. Correct the problem before saving the table." \
				-detail "The values in the left column must be increasing in order as you go down the table. In this case, the value $v appears after the value $last."
			return
		}
		lappend newtable $v $t
	}
	dict set dice_preset_data(tmp_presets,$tkey,T,$i,d) table $newtable
	dict set dice_preset_data(tmp_presets,$tkey,T,$i,d) markup $dice_preset_data(tmp_presets,$tkey,T,$i,m)
	set dice_preset_data(tmp_presets,$tkey,T,$i,d) [SyncPresetDetailFlags $dice_preset_data(tmp_presets,$tkey,T,$i,d)]
	set widgets [grid slaves $wfld]
	foreach fw $widgets {
		grid forget $fw
		destroy $fw
	}
	set r 0
	set istart 1
	foreach {n t} $newtable {
		SetTableColors $r fgcolor bgcolor
		if {$istart == $n} {
			set nlabel $n
			set istart [expr $n + 1]
		} elseif {$n eq "*"} {
			if {$istart ne {}} {
				set nlabel "${istart}+"
			} else {
				set nlabel "*"
			}
		} elseif {$istart eq {}} {
			set nlabel "...-${n}"
		} else {
			if {[catch {
				set nlabel [format "%d-%d" $istart $n]
				set istart [expr $n + 1]
			}]} {
				set nlabel "${istart}-${n}"
				set istart {}
			}
		}
		grid [label $wfld.n$r -text $nlabel -anchor e -relief groove -fg $fgcolor -bg $bgcolor] [label $wfld.t$r -text $t -anchor w -relief groove -fg $fgcolor -bg $bgcolor] -sticky we
		incr r
	}

	set dice_preset_data(tmp_presets,$tkey,T,$i) [EncodePresetDetails $dice_preset_data(tmp_presets,$tkey,T,$i,d)]
	EDRTtblDest $rw $tkey $i
}

proc EDRTtblCan {w tkey i} {
	if {[tk_messageBox -parent $w -type yesno -icon warning -default no -title "Are you sure?" \
		-message "Are you sure you want to leave this form without saving your work? Any edits you made to this table will be lost."] ne "yes"} {
			return
	}
	EDRTtblDest $w $tkey $i
}
proc EDRTtblDest {w tkey i} {
	global dice_preset_data
	array unset dice_preset_data(tmp_presets,$tkey,T,$i,v*)
	array unset dice_preset_data(tmp_presets,$tkey,T,$i,t*)
	array unset dice_preset_data(tmp_presets,$tkey,T,$i,l)
	array unset dice_preset_data(tmp_presets,$tkey,T,$i,m)
	destroy $w
}

proc EDRTtblAdd {w tkey i} {
	global dice_preset_data icon_delete
	set row $dice_preset_data(tmp_presets,$tkey,T,$i,l)
	if {$row > 0} {
		$w.tbl.v[expr $row - 1] configure -state normal -justify right
		set dice_preset_data(tmp_presets,$tkey,T,$i,v[expr $row - 1]) {}
	}
	grid [entry $w.tbl.v$row -justify right -textvariable dice_preset_data(tmp_presets,$tkey,T,$i,v$row)] \
		[entry $w.tbl.t$row -justify left -textvariable dice_preset_data(tmp_presets,$tkey,T,$i,t$row)] \
		[button $w.tbl.del$row -image $icon_delete -command [list EDRTtblDel $w $tkey $i $row]] \
		-sticky ew
	set dice_preset_data(tmp_presets,$tkey,T,$i,v$row) *
	set dice_preset_data(tmp_presets,$tkey,T,$i,t$row) {}
	$w.tbl.v$row configure -state disabled -justify center
	incr dice_preset_data(tmp_presets,$tkey,T,$i,l)
}

proc EDRTtblDel {w tkey i r} {
	global dice_preset_data
	set row $dice_preset_data(tmp_presets,$tkey,T,$i,l)
	if {$row <= 0 || $i >= $row} {
		return
	}
	for {set ii $r} {$ii < $row-1} {incr ii} {
		set dice_preset_data(tmp_presets,$tkey,T,$i,v$ii) $dice_preset_data(tmp_presets,$tkey,T,$i,v[expr $ii+1])
		set dice_preset_data(tmp_presets,$tkey,T,$i,t$ii) $dice_preset_data(tmp_presets,$tkey,T,$i,t[expr $ii+1])
	}
	array unset dice_preset_data(tmp_presets,$tkey,T,$i,v[expr $row-1]) {}
	array unset dice_preset_data(tmp_presets,$tkey,T,$i,t[expr $row-1]) {}
	grid forget $w.tbl.v[expr $row-1]
	grid forget $w.tbl.t[expr $row-1]
	grid forget $w.tbl.del[expr $row-1]
	destroy $w.tbl.v[expr $row-1]
	destroy $w.tbl.t[expr $row-1]
	destroy $w.tbl.del[expr $row-1]
	incr dice_preset_data(tmp_presets,$tkey,T,$i,l) -1
	if {$row > 1} {
		set dice_preset_data(tmp_presets,$tkey,T,$i,v[expr $row-2]) *
		$w.tbl.v[expr $row-2] configure -justify center -state disabled
	}
}

proc EDRTadd {w for_user tkey} {
	global dice_preset_data icon_anchor_n icon_anchor_s icon_delete icon_colorwheel icon_bullet_arrow_right icon_pencil
	set wnt [sframe content $w.n.t]
	set d [dict create Name {} DisplayName {} DieRollSpec {} DisplaySeq {} Description {} AreaTag {} Group {}]
	dict lappend dice_preset_data(tmp_presets,$tkey) Tables $d
	set i [expr [llength [dict get $dice_preset_data(tmp_presets,$tkey) Tables]] - 1]
	set dice_preset_data(tmp_presets,$tkey,T,$i) $d
	set dice_preset_data(tmp_presets,$tkey,T,$i,d) [GetPresetDetails $d]
	dict set dice_preset_data(tmp_presets,$tkey,T,$i,d) type table
	dict set dice_preset_data(tmp_presets,$tkey,T,$i,d) delim ";"


	grid [button $wnt.gbtn$i -image $icon_bullet_arrow_right -command [list EditDRPGroup $wnt.group$i "Groups for Table #$i"]] \
	     [label $wnt.group$i -text {}] \
	     [entry $wnt.name$i] \
	     [entry $wnt.desc$i] \
	     [entry $wnt.dspec$i] \
	     [button $wnt.edit$i -image $icon_pencil -command [list EDRTtbl $wnt.tbl$i $tkey $i "Table #$i"]] \
	     [frame $wnt.tbl$i] \
	     [button $wnt.del$i -image $icon_delete -command [list EDRTdel $w $for_user $tkey $i]] -sticky we
     	
	::tooltip::tooltip $wnt.gbtn$i "Edit group(s) to which this table belongs"
	::tooltip::tooltip $wnt.edit$i "Edit the table"
	::tooltip::tooltip $wnt.del$i "Remove this table from the list"
}

proc EDRTdel {w for_user tkey i} {
	if {[winfo exists .edrtTbl_${i}_${tkey}]} {
		tk_messageBox -parent . -type ok -icon error -title "Table Editor Still Open" \
			-message "You cannot delete this table while you still have a table editor window for it still open."
		return
	}

	global dice_preset_data
	set wnt [sframe content $w.n.t]
	EDRPgetValues $w $for_user $tkey
	set t [lindex [dict get $dice_preset_data(tmp_presets,$tkey) Tables] $i]
	if {([dict exists $t DisplayName] && [string trim [dict get $t DisplayName]] ne {})
	||  ([dict exists $t Name] && [string trim [dict get $t Name]] ne {})
 	||  [string trim [dict get $t Description]] ne {}
	||  [string trim [dict get $t DieRollSpec]] ne {}} {
		if {[tk_messageBox -parent $w -type yesno -icon warning -default no -title "Are you sure?" \
			-message "Are you sure you want to delete this table from the list?"] ne "yes"} {
				return
		}
	}

	dict set dice_preset_data(tmp_presets,$tkey) Tables [lreplace [dict get $dice_preset_data(tmp_presets,$tkey) Tables] $i $i]
	set i [llength [dict get $dice_preset_data(tmp_presets,$tkey) Tables]]
	grid forget $wnt.group$i $wnt.name$i $wnt.desc$i $wnt.dspec$i $wnt.edit$i $wnt.tbl$i $wnt.del$i $wnt.gbtn$i
	destroy $wnt.group$i $wnt.name$i $wnt.desc$i $wnt.dspec$i $wnt.edit$i $wnt.tbl$i $wnt.del$i $wnt.gbtn$i
}

proc EDRPadd {w for_user tkey} {
	global dice_preset_data icon_anchor_n icon_anchor_s icon_delete icon_colorwheel icon_bullet_arrow_right
	set wnr [sframe content $w.n.r]
	set wnm [sframe content $w.n.m]
	set d [dict create Name {} DisplayName {} DieRollSpec {} DisplaySeq {} Description {} AreaTag {} Group {}]
	dict lappend dice_preset_data(tmp_presets,$tkey) Rolls $d
	set i [expr [llength [dict get $dice_preset_data(tmp_presets,$tkey) Rolls]] - 1]
	set dice_preset_data(tmp_presets,$tkey,R,$i) $d
	grid [button $wnr.gbtn$i -image $icon_bullet_arrow_right -command [list EditDRPGroup $wnr.group$i "Groups for Preset #$i"]] \
	     [label $wnr.group$i -text {}] \
	     [entry $wnr.name$i] [entry $wnr.desc$i] \
	     [button $wnr.color$i -image $icon_colorwheel -command [list EditColorBoxTitle "EDRP_text,$tkey,$i"]] \
	     [entry $wnr.dspec$i -textvariable dice_preset_data(EDRP_text,$tkey,$i)] \
	     [button $wnr.up$i -image $icon_anchor_n -command [list EDRPraise $w $for_user $tkey $i]] \
	     [button $wnr.dn$i -image $icon_anchor_s -command [list EDRPlower $w $for_user $tkey $i]] \
	     [button $wnr.del$i -image $icon_delete -command [list EDRPdel $w $for_user $tkey $i]] -sticky we
	::tooltip::tooltip $wnr.gbtn$i "Edit group(s) to which this preset belongs"
	::tooltip::tooltip $wnr.color$i "Edit color(s) for die-roll title string"
	::tooltip::tooltip $wnr.up$i "Move this die-roll up in the list"
	::tooltip::tooltip $wnr.dn$i "Move this die-roll down in the list"
	::tooltip::tooltip $wnr.del$i "Remove this die-roll from the list"
	EDRPgetValues $w $for_user $tkey
	EDRPresequence $w $for_user $tkey
	EDRPupdateGUI $w $for_user $tkey
}
proc EDRPaddModifier {w for_user tkey} {
	global dice_preset_data icon_anchor_n icon_anchor_s icon_delete icon_bullet_arrow_right
	set wnr [sframe content $w.n.r]
	set wnm [sframe content $w.n.m]
	set d [dict create Global false Enabled false Variable {} Name {} DisplayName {} DieRollSpec {} DisplaySeq {} Description {} Group {} ClientData {}]
	dict lappend dice_preset_data(tmp_presets,$tkey) Modifiers $d
	set i [expr [llength [dict get $dice_preset_data(tmp_presets,$tkey) Modifiers]] - 1]
	set dice_preset_data(tmp_presets,$tkey,M,$i) $d
#	trace add variable dice_preset_data(EDRP_mod_en,$tkey,$i) {array read write unset} TRACEvar
	set dice_preset_data(EDRP_mod_en,$tkey,$i) 0
	set dice_preset_data(EDRP_mod_ven,$tkey,$i) 0
	set dice_preset_data(EDRP_mod_g,$tkey,$i) 0
	grid [button $wnm.gbtn$i -image $icon_bullet_arrow_right -command [list EditDRPGroup $wnm.group$i "Groups for Modifier #$i"]] \
	     [label $wnm.group$i -text {}] \
	     [ttk::checkbutton $wnm.en$i -text On -onvalue 1 -offvalue 0 -variable dice_preset_data(EDRP_mod_en,$tkey,$i)] \
	        [entry $wnm.name$i] \
		[entry $wnm.desc$i] \
		[entry $wnm.dspec$i] \
		[ttk::checkbutton $wnm.varp$i -text "as symbol \${" -variable dice_preset_data(EDRP_mod_ven,$tkey,$i) -command [list EDRPcheckVar $w $for_user $tkey $i]]\
		[entry $wnm.var$i -width 6] \
		[label $wnm.rb$i -text "}" -anchor w] \
		[ttk::checkbutton $wnm.g$i -text "()x" -variable dice_preset_data(EDRP_mod_g,$tkey,$i)]\
		[button $wnm.up$i -image $icon_anchor_n -command [list EDRPraiseModifier $w $for_user $tkey $i]]\
		[button $wnm.dn$i -image $icon_anchor_s -command [list EDRPlowerModifier $w $for_user $tkey $i]]\
		[button $wnm.del$i -image $icon_delete -command [list EDRPdelModifier $w $for_user $tkey $i]]\
		-sticky ew
	::tooltip::tooltip $wnm.g$i "If checked, adds (...) around expression before adding this modifier."
	::tooltip::tooltip $wnm.up$i "Move this modifier up in the list"
	::tooltip::tooltip $wnm.dn$i "Move this modifier down in the list"
	::tooltip::tooltip $wnm.del$i "Remove this modifier from the list"
	::tooltip::tooltip $wnm.en$i "If checked, the modifier is in-play"
	::tooltip::tooltip $wnm.varp$i "If checked, the modifier is used in place of <var>, otherwise added to all die rolls"
	EDRPgetValues $w $for_user $tkey
	EDRPresequence $w $for_user $tkey
	EDRPupdateGUI $w $for_user $tkey
}

# PresetLists arrayname ?-export? -> dict of Rolls, CustomRolls, Modifiers, Tables which hold sorted lists of dicts
# 	-export: also set global array DieRollPresetState with
# 		(var,<name>) = string
# 		(global,<name>) = list of strings to apply to all die rolls
# 		(on,<name>) = bool	true if (var,<name>) or (global,<name>) are enabled
#
proc PresetLists {arrayname tkey args} {
	upvar $arrayname presets
	global DieRollPresetState
	set export [expr [lsearch -exact $args -export] >= 0]
	set mods {}
	set rolls {}
	set custom {}
	set tables {}

	set gmods {}
	set grolls {}
	set gcustom {}
	set gtables {}

	set seq 0
	if {$export} {
		array unset DieRollPresetState "$tkey,*"
		set DieRollPresetState($tkey,apply_order) {}
	}

        set pkeylen [string length "preset,$tkey,"]
	foreach pkey [lsort [array names presets "preset,$tkey,*"]] {
		set pname [string range $pkey $pkeylen end]
		if {[regexp {^#(.*?);(.*?)(?:;([^|]*))?(?:\|(.*))?$} $pname _ sequence flags client dname]} {
			set d $presets($pkey)
			if {$dname eq {}} {
				dict set d DisplayName {unnamed table}
			} else {
				dict set d DisplayName $dname
			}
			dict set d ClientData $client
			foreach {flagcode flagname} {
				m Markup
			} {
				if {[string first $flagcode $flags] >= 0} {
					dict set d $flagname true
				} else {
					dict set d $flagname false
				}
			}

			set sdata [split $sequence "\u25B6"]
			if {[llength $sdata] > 1} {
				dict set d Group [join [lrange $sdata 1 end] "\u25B6"]
				set sdata [lindex $sdata 0]
			} else {
				dict set d Group {}
			}
			if {[scan $sdata %d%s n _] == 1} {
				if {$n <= $seq} {
					set n [incr seq]
				} else {
					set seq $n
				}
				dict set d DisplaySeq $n
			} else {
				dict set d DisplaySeq [incr seq]
			}

			lappend tables $d
		} elseif {[regexp {^§(.*?);(.*?);(.*?)(?:;([^|]*))?(?:\|(.*))?$} $pname _ sequence varname flags client dname]} {
			set d $presets($pkey)
			if {$dname eq {}} {
				dict set d DisplayName {unnamed modifier}
			} else {
				dict set d DisplayName $dname
			}
			dict set d ClientData $client
			dict set d Variable $varname
			foreach {flagcode flagname} {
				e Enabled
				g Global
			} {
				if {[string first $flagcode $flags] >= 0} {
					dict set d $flagname true
				} else {
					dict set d $flagname false
				}
			}

			set sdata [split $sequence "\u25B6"]
			if {[llength $sdata] > 1} {
				dict set d Group [join [lrange $sdata 1 end] "\u25B6"]
				set sdata [lindex $sdata 0]
			} else {
				dict set d Group {}
			}
			if {[scan $sdata %d%s n _] == 1} {
				if {$n <= $seq} {
					set n [incr seq]
				} else {
					set seq $n
				}
				dict set d DisplaySeq $n
			} else {
				dict set d DisplaySeq [incr seq]
			}

			lappend mods $d
			if {$export} {
				if {[set varname [string trim [dict get $d Variable]]] ne {}} {
					if {[string is alpha -strict [string range $varname 0 0]] &&
					([string length $varname] == 1 ||
					[string is alnum -strict [string range $varname 1 end]])} {
						set DieRollPresetState($tkey,var,$varname) [dict get $d DieRollSpec]
						set DieRollPresetState($tkey,on,$varname) [dict get $d Enabled]
						set DieRollPresetState($tkey,g,$varname) false
					} else {
						DEBUG 0 "Invalid modifier variable name <$varname>. This variable will be ignored."
						DEBUG 0 "Variables must begin with a letter and include only letters and numbers."
					}
				} else {
					set id [dict get $d DisplaySeq]
					set DieRollPresetState($tkey,global,u$id) [dict get $d DieRollSpec]
					set DieRollPresetState($tkey,on,u$id) [dict get $d Enabled]
					set DieRollPresetState($tkey,g,u$id) [dict get $d Global]
					lappend DieRollPresetState($tkey,apply_order) u$id
				}
			}
		} else {
			set pieces [split $pname |]
			set d $presets($pkey)

			if {[llength $pieces] < 2} {
				# no |, so this is just a simple name with no other fancy stuff.
				# give it a seqence here, which we'll write out for it later.
				dict set d DisplayName $pname 
				dict set d DisplaySeq [incr seq]
				lappend rolls $d
			} else {
				# content before the | can be $[<area>]<sequence><groups>
				set nstr [lindex $pieces 0]
				if {[regexp {^(\$\[.*?\])(.*)$} $nstr _ areatag rest]} {
					set nstr $rest
					dict set d AreaTag $areatag
				} else {
					dict set d AreaTag {}
				}
				if {[llength [set seqparts [split $nstr "\u25B6"]]] > 1} {
					dict set d Group [join [lrange $seqparts 1 end] "\u25B6"]
					set nstr [lindex $seqparts 0]
				} else {
					dict set d Group {}
				}

				if {[scan $nstr %d%s n _] == 1} {
					if {$n <= $seq} {
						set n [incr seq]
					} else {
						set seq $n
					}
					dict set d DisplayName [join [lrange $pieces 1 end] |] 
					dict set d DisplaySeq $n
					lappend rolls $d
				} else {
					dict set d DisplayName [join [lrange $pieces 1 end] |]
					lappend custom $d
				}
			}
		}
	}

	# process the global set
	set pkeylen [string length "sys,preset,"]
	foreach pkey [lsort [array names presets "sys,preset,*"]] {
		set pname [string range $pkey $pkeylen end]
		if {[regexp {^#(.*?);(.*?)(?:;([^|]*))?(?:\|(.*))?$} $pname _ sequence flags client dname]} {
			set d $presets($pkey)
			if {$dname eq {}} {
				dict set d DisplayName {unnamed table}
			} else {
				dict set d DisplayName $dname
			}
			dict set d ClientData $client
			foreach {flagcode flagname} {
				m Markup
			} {
				if {[string first $flagcode $flags] >= 0} {
					dict set d $flagname true
				} else {
					dict set d $flagname false
				}
			}

			set sdata [split $sequence "\u25B6"]
			if {[llength $sdata] > 1} {
				dict set d Group [join [lrange $sdata 1 end] "\u25B6"]
				set sdata [lindex $sdata 0]
			} else {
				dict set d Group {}
			}
			if {[scan $sdata %d%s n _] == 1} {
				if {$n <= $seq} {
					set n [incr seq]
				} else {
					set seq $n
				}
				dict set d DisplaySeq $n
			} else {
				dict set d DisplaySeq [incr seq]
			}

			lappend gtables $d
		} elseif {[regexp {^§(.*?);(.*?);(.*?)(?:;([^|]*))?(?:\|(.*))?$} $pname _ sequence varname flags client dname]} {
			set d $presets($pkey)
			if {$dname eq {}} {
				dict set d DisplayName {unnamed modifier}
			} else {
				dict set d DisplayName $dname
			}
			dict set d ClientData $client
			dict set d Variable $varname
			foreach {flagcode flagname} {
				e Enabled
				g Global
			} {
				if {[string first $flagcode $flags] >= 0} {
					dict set d $flagname true
				} else {
					dict set d $flagname false
				}
			}

			set sdata [split $sequence "\u25B6"]
			if {[llength $sdata] > 1} {
				dict set d Group [join [lrange $sdata 1 end] "\u25B6"]
				set sdata [lindex $sdata 0]
			} else {
				dict set d Group {}
			}
			if {[scan $sdata %d%s n _] == 1} {
				if {$n <= $seq} {
					set n [incr seq]
				} else {
					set seq $n
				}
				dict set d DisplaySeq $n
			} else {
				dict set d DisplaySeq [incr seq]
			}

			lappend gmods $d
			if {$export} {
				if {[set varname [string trim [dict get $d Variable]]] ne {}} {
					if {[string is alpha -strict [string range $varname 0 0]] &&
					([string length $varname] == 1 ||
					[string is alnum -strict [string range $varname 1 end]])} {
						set DieRollPresetState(sys,gvar,$varname) [dict get $d DieRollSpec]
						set DieRollPresetState(sys,gvar_on,$varname) [dict get $d Enabled]
					} else {
						DEBUG 0 "Invalid modifier variable name <$varname>. This variable will be ignored."
						DEBUG 0 "Variables must begin with a letter and include only letters and numbers."
					}
				} else {
					set id [dict get $d DisplaySeq]
					set DieRollPresetState($tkey,global,g$id) [dict get $d DieRollSpec]
					set DieRollPresetState($tkey,on,g$id) [dict get $d Enabled]
					set DieRollPresetState($tkey,g,g$id) [dict get $d Global]
					lappend DieRollPresetState($tkey,apply_order) g$id
				}
			}
		} else {
			set pieces [split $pname |]
			set d $presets($pkey)

			if {[llength $pieces] < 2} {
				# no |, so this is just a simple name with no other fancy stuff.
				# give it a seqence here, which we'll write out for it later.
				dict set d DisplayName $pname 
				dict set d DisplaySeq [incr seq]
				lappend grolls $d
			} else {
				# content before the | can be $[<area>]<sequence><groups>
				set nstr [lindex $pieces 0]
				if {[regexp {^(\$\[.*?\])(.*)$} $nstr _ areatag rest]} {
					set nstr $rest
					dict set d AreaTag $areatag
				} else {
					dict set d AreaTag {}
				}
				if {[llength [set seqparts [split $nstr "\u25B6"]]] > 1} {
					dict set d Group [join [lrange $seqparts 1 end] "\u25B6"]
					set nstr [lindex $seqparts 0]
				} else {
					dict set d Group {}
				}

				if {[scan $nstr %d%s n _] == 1} {
					if {$n <= $seq} {
						set n [incr seq]
					} else {
						set seq $n
					}
					dict set d DisplayName [join [lrange $pieces 1 end] |] 
					dict set d DisplaySeq $n
					lappend grolls $d
				} else {
					dict set d DisplayName [join [lrange $pieces 1 end] |]
					lappend gcustom $d
				}
			}
		}
	}
	return [dict create Modifiers $mods Rolls $rolls CustomRolls $custom GlobalModifiers $gmods GlobalRolls $grolls GlobalCustomRolls $gcustom Tables $tables GlobalTables $gtables]
}

proc EDRPcheckVar {w for_user tkey i} {
	global dice_preset_data
	set wnr [sframe content $w.n.r]
	set wnm [sframe content $w.n.m]
	$wnm.var$i configure -state normal
	if {! $dice_preset_data(EDRP_mod_ven,$tkey,$i)} {
		$wnm.var$i delete 0 end
		$wnm.var$i configure -state disabled
		$wnm.g$i configure -state normal
	} else {
		$wnm.g$i configure -state disabled
		set dice_preset_data(EDRP_mod_g,$tkey,$i) 0
	}
}
# DisplayChatMessage d ?for_user? ?-noopen? ?-system?
proc DisplayChatMessage {d for_user args} {
	global dark_mode SuppressChat check_select_color
	global icon_die16 icon_info20 icon_arrow_refresh check_menu_color
	global icon_delete icon_add icon_open icon_save ChatTranscript icon_colorwheel
	global last_known_size global_bg_color IThost
	global _preferences colortheme dice_preset_data local_user

	if {$d ne {}} {
		::gmautil::dassign $d Sender from Recipients recipientlist Text message Sent date_sent Markup markup Pin pinned
	} else {
		lassign {} from recipientlist message date_sent
		set markup false
		set pinned false
	}

	if {$for_user eq {}} {
		set for_user $local_user
	}

	if {$SuppressChat} return
	if {![::gmaproto::is_connected]} {
		tk_messageBox -parent . -type ok -icon error -title "No Connection to Server" \
			-message "Your client must be connected to the map server to use this function."
		return
	}

	set tkey [user_key $for_user]

	if {![info exists dice_preset_data(cw,$tkey)]} {
		set dice_preset_data(cw,$tkey) .[new_id]
		set dice_preset_data(user,$tkey) $for_user
		DEBUG 1 "Created new toplevel window $dice_preset_data(cw,$tkey) for $for_user's die rolls"
	}

	set w $dice_preset_data(cw,$tkey)
	set wc   $w.p.chat
	set wpc  $w.p.pinnedchat
	set wrsf $w.p.recent
	set wpsf $w.p.preset

	if {![winfo exists $w]} {
		if {[lsearch -exact $args "-noopen"] >= 0} {
			# this message isn't worth opening a new window;
			# just ignore it
			return
		}
		inhibit_resize_task 1 recent $for_user $tkey
		inhibit_resize_task 1 preset $for_user $tkey
		toplevel $w -background $global_bg_color

		#  ____________________________________
	 	# |                                    |^      \
	 	# |                                    ||      |
	 	# | Chat message window                ||      | chat.1
	 	# |                                    ||      |
	 	# |                                    ||      |
		# |____________________________________|V      /
		# To: [menu] ________________________ [send]   ) chat.2  <- bind return to send
		#     gm
		#     person1
		#     person2
		#	  
		# Roll: [_____________________________](i)---> ) chat.3 help window for syntax
		# Recent: most recent           +[____][:]     \
		#         next recent           +[____][:]     | recent
		#         next recent           +[____][:]     /
		# Preset:
		#         [-] name: roll        +[____][:]     \mouseover to see full description
		#         [-] name: roll        +[____][:]     | preset
		#         [-] name: roll        +[____][:]     /
		#         [+] Add new preset
		#
		# new preset pane:
		# (edit)(import)(export)
		# [x] Modifier name: +[_______] (to all rolls)	§nnn;;e|name
		# [x] Modifier name: +[_______] (as <var>)	§nnn;var;e|name
		# [::]+[__________] Preset name: description
		# [::]+[__________] Preset name: description
		# [::]+[__________] Preset name: description
		#
		# remove/mod AddDieRollPreset
		# add EditDieRollPresets
		# dice_preset_data: array(name)=dict(Description, DieRollSpec)
		#
		# /Rolls\__________________________________________________________
		# | [name________] [desc__________] [rollspec________] [-][^][v]
		# | [name________] [desc__________] [rollspec________] [-][^][v]
		# | [name________] [desc__________] [rollspec________] [-][^][v]
		# |_______________________________________________________________
		#
		# _____/Mods\____________________________________________________________________
		# | [name________] [desc___________] [rollspec_______] [x]as [_______] [-][^][v]
		# | [name________] [desc___________] [rollspec_______] [x]as [_______] [-][^][v]
		# | [name________] [desc___________] [rollspec_______] [x]as [_______] [-][^][v]
		# |_______________________________________________________________
		#
		ttk::panedwindow $w.p -orient vertical 
		if {$for_user eq $local_user} {
			wm title $w "Chat and Die Rolls"
			ttk::labelframe $wc -text "Chat Messages"
		} else {
			wm title $w "Die Rolls for $for_user"
			ttk::labelframe $wc -text "Dice for $for_user"
		}
		ttk::labelframe $wpc -text "Pinned Messages"
		ttk::labelframe $wrsf -text "Recent Rolls"
		ttk::labelframe $wpsf -text "Preset Rolls"
		pack [sframe new $wrsf.sf -anchor w] -side top -fill both -expand 1
		pack [sframe new $wpsf.sf -anchor w] -side top -fill both -expand 1
		set wr [sframe content $wrsf.sf]
		set wp [sframe content $wpsf.sf]
		bind $wrsf <Configure> "ResizeDieRoller $wr %w %h recent $for_user $tkey"
		bind $wpsf <Configure> "ResizeDieRoller $wp %w %h preset $for_user $tkey"

		$w.p add $wpc
		$w.p add $wc
		$w.p add $wrsf
		$w.p add $wpsf
		pack $w.p -side top -expand 1 -fill both 

		for {set i 0} {$i < 10} {incr i} {
			pack [frame $wr.$i] -side top -expand 0 -fill x
			label $wr.$i.spec -anchor w
			button $wr.$i.roll -state disabled -image $icon_die16 -command "Reroll $wr.$i $i $for_user $tkey"
			entry $wr.$i.extra -width 3 -state disabled
			label $wr.$i.plus -text +
			set last_known_size($tkey,recent,$i) blank
		}
		pack [frame $wp.add] -side bottom -expand 0 -fill x
		#pack [button $wp.add.add -image $icon_add -command AddDieRollPreset $for_user $tkey] -side left
		#pack [label $wp.add.label -text "Add new die-roll preset" -anchor w] -side left -expand 1 -fill x
		pack [button $wp.add.add -text "Edit presets..." -command [list EditDieRollPresets $for_user $tkey]] -side left
		pack [button $wp.add.save -image $icon_save -command [list SaveDieRollPresets $w $for_user $tkey]] -side right
		pack [button $wp.add.load -image $icon_open -command [list LoadDieRollPresets $w $for_user $tkey]] -side right
		pack [button $wp.add.upd -image $icon_arrow_refresh -command [list RequestDicePresets $for_user]] -side right

		::tooltip::tooltip $wp.add.save "Export presets to disk file"
		::tooltip::tooltip $wp.add.load "Import presets from disk file"
		::tooltip::tooltip $wp.add.upd "Refresh preset list from server"

		if {$for_user eq $local_user} {
			pack [frame $wpc.1] -side top -expand 1 -fill both
			pack [frame $wc.1] -side top -expand 1 -fill both
		}
		pack [frame $wc.2]\
			 [frame $wc.3]\
			-side top -expand 0 -fill x

		if {$for_user eq $local_user} {
			pack [text $wpc.1.text -yscrollcommand "$wpc.1.sb set" -height 10 -width 10 -state disabled] -side left -expand 1 -fill both
			pack [scrollbar $wpc.1.sb -orient vertical -command "$wpc.1.text yview"] -side right -expand 0 -fill y
			pack [text $wc.1.text -yscrollcommand "$wc.1.sb set" -height 10 -width 10 -state disabled] -side left -expand 1 -fill both
			pack [scrollbar $wc.1.sb -orient vertical -command "$wc.1.text yview"] -side right -expand 0 -fill y
		}
		pack [button $wc.3.tc -image $icon_colorwheel \
			-command [list EditColorBoxTitle "CHAT_dice,$tkey"]] -side left -padx 2
		pack [label $wc.3.l -text Roll: -anchor nw] -side left -padx 2

		pack [entry $wc.3.dice -textvariable dice_preset_data(CHAT_dice,$tkey) -relief sunken] -side left -fill x -expand 1
		pack [button $wc.3.info -image $icon_info20 -command ShowDiceSyntax] -side right
		::tooltip::tooltip $wc.3.info "Display help for how to write die rolls and use the chat window."
		set dice_preset_data(CHAT_blind,$tkey) 0
		set dice_preset_data(CHAT_markup_en,$tkey) [gmaproto::int_bool [dict get $_preferences markup_enabled]]
		set dice_preset_data(CHAT_pinned_en,$tkey) 0
		pack [ttk::checkbutton $wc.3.blind -text GM -variable dice_preset_data(CHAT_blind,$tkey)] -side right
		::tooltip::tooltip $wc.3.blind "Send result of die roll ONLY to the GM."
		#-selectcolor $check_select_color
		#-indicatoron 1 

		menubutton $wc.2.to -menu $wc.2.to.menu -text To: -relief raised
		menu $wc.2.to.menu -tearoff 0
		$wc.2.to.menu add command -label (all) -command [list chat_to_all $for_user $tkey]
		$wc.2.to.menu add checkbutton -label GM -onvalue 1 -offvalue 0 -variable dice_preset_data(CHAT_TO,$tkey,GM) -command [list update_chat_to $for_user $tkey] -selectcolor $check_menu_color

		set dice_preset_data(CHAT_text,$tkey) {}
		global icon_star

		pack $wc.2.to -side left 
		pack [entry $wc.2.entry -relief sunken -textvariable dice_preset_data(CHAT_text,$tkey)] -side left -fill x -expand 1
		pack [button $wc.2.send -command RefreshPeerList -image $icon_arrow_refresh] -side right
		pack [ttk::checkbutton $wc.2.pinned -image $icon_star -variable dice_preset_data(CHAT_pinned_en,$tkey)] -side right	; #TODO
		pack [ttk::checkbutton $wc.2.markup -text M -variable dice_preset_data(CHAT_markup_en,$tkey)] -side right
		::tooltip::tooltip $wc.2.markup "Enable GMA markup formatting codes in chat messages."
#		if {$for_user eq $local_user} {
#			global icon_unlock
#			pack [button $wc.2.lock -command [list ToggleChatLock $wc.2.lock $wc.1.text] -image $icon_unlock] -side right
#			::tooltip::tooltip $wc.2.lock "Unlock the chat window for editing/copying text."
#			set dice_preset_data(chat_lock) true
#		}
		::tooltip::tooltip $wc.2.send "Refresh the list of recipients for messages."
		bind $wc.2.entry <Return> [list SendChatFromWindow $for_user $tkey]
		bind $wc.3.dice <Return> [list SendDieRollFromWindow $w $wr $for_user $tkey]

		set dice_preset_data(CHAT_TO,$tkey,GM) 0
		update_chat_to $for_user $tkey
		UpdatePeerList $for_user $tkey		;# set up what we may have already received
		RefreshPeerList				;# ask for an update as well

		if {$for_user eq $local_user} {
			foreach tag {
				begingroup best bonus constant critlabel critspec dc diebonus diespec discarded
				endgroup exceeded fail from fullmax fullresult iteration label max maximized maxroll 
				met min moddelim normal operator repeat result roll separator short sf success 
				title to until worst system subtotal error notice timestamp stats bold italic bolditalic section subsection
			} {
				if {![dict exists $_preferences styles dierolls components $tag]} {
					DEBUG 0 "Preferences profile is missing a definition for $tag; using default"
					dict set _preferences styles dierolls components $tag [::gmaprofile::default_dieroll_style]
				}
				set options {}
				$wc.1.text tag delete $tag
				$wpc.1.text tag delete $tag
				foreach {k o t} {
					fg         -foreground c
					bg         -background c
					overstrike -overstrike ?
					underline  -underline  ?
					offset     -offset     i
					font       -font       f
				} {
					set v [dict get $_preferences styles dierolls components $tag $k]
					switch -exact $t {
						c {
							if {$v eq {}} continue
							set v [dict get $v $colortheme]
							if {$v eq {}} continue
						}
						f { set v [::gmaprofile::lookup_font $_preferences $v] }
						? { if {$v eq {} || !$v} continue }
						i { if {$v == 0} continue }
					}
					lappend options $o $v
				}

				$wc.1.text tag configure $tag {*}$options
				$wpc.1.text tag configure $tag {*}$options
				DEBUG 3 "Configure tag $tag as $options"
			}
		}

		RequestDicePresets $for_user
		inhibit_resize_task 0 recent $for_user $tkey
		inhibit_resize_task 0 preset $for_user $tkey

		if {$for_user eq $local_user} {
			LoadChatHistory
		} else {
			RequestDicePresets $for_user
		}
	}

	if {$d eq {} || $for_user ne $local_user} {
		return
	}

	set system [expr [lsearch -exact $args "-system"] >= 0] 
	_render_chat_message $wc.1.text $system $message $recipientlist $from [dict get $d ToAll] [dict get $d ToGM] $date_sent $markup $pinned
	if {$system} {
		TranscribeChat (system) $recipientlist $message [dict get $d ToAll] [dict get $d ToGM] $date_sent $markup $pinned
	} else {
		TranscribeChat $from $recipientlist $message [dict get $d ToAll] [dict get $d ToGM] $date_sent $markup $pinned
	}
}

#proc ToggleChatLock {buttonw textw} {
#	global icon_unlock icon_lock dice_preset_data
#	if {![info exists dice_preset_data(chat_lock)] || $dice_preset_data(chat_lock)} {
#		set dice_preset_data(chat_lock) false
#		$textw configure -state normal
#		$buttonw configure -image $icon_lock
#		::tooltip::tooltip $buttonw "Lock the chat window from editing/copying text."
#	} else {
#		set dice_preset_data(chat_lock) true
#		$textw configure -state disabled
#		$buttonw configure -image $icon_unlock
#		::tooltip::tooltip $buttonw "Unlock the chat window for editing/copying text."
#	}
#}

proc _render_chat_message {w system message recipientlist from toall togm {date_sent {}} {markup false} {pinned false}} {
	global SuppressChat _preferences LastDisplayedChatDate dice_preset_data

	if {$pinned} {
		if {[set start [string first .chat.1 $w]] >= 0} {
			set w [string replace $w $start $start+6 .pinnedchat.1]
		}
	}

	if {!$SuppressChat && [winfo exists $w]} {
		$w configure -state normal
		if {$system} {
			$w insert end "$message\n" system
		} else {
			if {[dict exists $_preferences chat_timestamp] && [dict get $_preferences chat_timestamp]} {
				if {$date_sent ne {}} {
					if {[set date_sent_sec [scan_fractional_seconds $date_sent]] != 0} {
						set date_sent_date [clock format [expr int($date_sent_sec)] -format "%A, %B %d, %Y"]
						if {$LastDisplayedChatDate ne $date_sent_date} {
							set LastDisplayedChatDate $date_sent_date
							$w insert end "\n--$date_sent_date--\n" timestamp
						}
						$w insert end [clock format [expr int($date_sent_sec)] -format "%H:%M "] timestamp
					} else {
						$w insert end "??:?? " timestamp
					}
				} else {
					$w insert end "--:-- " timestamp
				}
			}
			ChatAttribution $w $from $recipientlist $toall $togm
			if {$markup} {
				foreach {fontstyle text} [gma::minimarkup::render $message] {
					$w insert end $text $fontstyle
				}
				$w insert end "\n" normal
			} else {
				$w insert end "$message\n" normal
			}
		}
		$w see end
#		if {![info exists dice_preset_data(chat_lock)] || $dice_preset_data(chat_lock)} {
#			$w configure -state disabled
#		}
		$w configure -state disabled
	}
}

#
# get the message ID from a server message or {} if it's not able to be found
#  0     1    2     3     4         5         6
# ROLL from recip title result structured messageID
# TO   from recip msg   msgID
# CC   user target msgID
proc ChatMessageID {message} {
    catch {
        switch -- [lindex $message 0] {
            ROLL	{ return [lindex $message 6] }
            TO      { return [lindex $message 4] }
            CC      { return [lindex $message 3] }
        }
    }
	return {}
}

# translate old-style entries into new ones
# return valid entry or empty string
proc ValidateChatHistoryEntry {e} {
	DEBUG 2 "Validating chat history entry $e"
	if {![string is list $e] || [catch {set n [llength $e]}]} {
		DEBUG 2 "--rejected, invalid format"
		return {}
	}

	# old: 	-system * <message> -1
	# new:	-system <message> -1
	if {[lindex $e 0] eq {-system}} {
		if {$n == 4 && [lindex $e 3] == -1 && [lindex $e 1] eq "*"} {
			DEBUG 3 "--old -system record -> -system [lindex $e 2] -1"
			return [list -system [lindex $e 2] -1]
		}
		if {$n == 3 && [lindex $e 2] == -1} {
			DEBUG 3 "--new -system record -> $e"
			return $e
		}
		DEBUG 3 "--rejected"
		return {}
	}

	switch -exact -- [lindex $e 0] {
		ROLL {
			# old: ROLL from recip title result rlist mid
			# new: ROLL d mid
			if {$n == 7} {
				DEBUG 3 "--old ROLL record from [lindex $e 2]"
				set d [ParseRecipientList [lindex $e 2] ROLL\
					Sender [lindex $e 1]\
					Title  [lindex $e 3]\
					Result [dict create Result [lindex $e 4] Details {}]\
					MessageID [lindex $e 6]\
				]
				set rlist {}
				foreach result [lindex $e 5] {
					lappend rlist [dict create Type [lindex $result 0] Value [lindex $result 1]]
				}
				dict set d Result Details $rlist
				DEBUG 3 "-- -> ROLL $d [dict get $d MessageID]"
				return [list ROLL $d [dict get $d MessageID]]
			}
			if {$n == 3} {
				DEBUG 3 "--new ROLL record -> $e"
				return $e
			}
			DEBUG 3 "--rejected"
			return {}
		}
		TO {
			# old: TO from recip msg mid
			# new: TO d mid
			if {$n == 5} {
				DEBUG 3 "--old TO record from [lindex $e 2]"
				return [list TO [ParseRecipientList [lindex $e 2] TO\
					Sender [lindex $e 1]\
					Text [lindex $e 3]\
					MessageID [lindex $e 4]\
				] [lindex $e 4]]
			}
			if {$n == 3} {
				DEBUG 3 "--new TO record -> $e"
				return $e
			}
			DEBUG 3 "--rejected"
			return {}
		}
		CC {
			# old: CC from target mid
			# new: CC d mid
			if {$n == 4} {
				DEBUG 3 "--old CC record"
				set dd [::gmaproto::new_dict CC \
					RequestedBy [lindex $e 1]\
					Target [lindex $e 2]\
					MessageID [lindex $e 3]\
				]
				if {[lindex $e 1] eq "*"} {
					dict set dd RequestedBy {}
					dict set dd DoSilently true
				}
			
				DEBUG 3 "-- -> CC $dd [lindex $e 3]"
				return [list CC $dd [lindex $e 3]]
			}
			if {$n == 3} {
				DEBUG 3 "--new CC record -> $e"
				return $e
			}
			DEBUG 3 "--rejected"
			return {}
		}
	}
	DEBUG 3 "--rejected (unknown type)"
	return {}
}
	
proc ParseRecipientList {r type args} {
	set d [::gmaproto::new_dict $type {*}$args]
	foreach recip $r {
		if {$recip eq "*"} {
			dict set d ToAll true
		} elseif {$recip eq "%"} {
			dict set d ToGM true
		} else {
			dict lappend d Recipients $recip
		}
	}
	if {[dict get $d ToGM]} {
		dict set d ToAll false
		dict set d Recipients {}
	}
	if {[dict get $d ToAll]} {
		dict set d Recipients {}
	}
	return $d
}


proc ClearChatHistory {d} {
	global ChatHistory
	::gmautil::dassign $d RequestedBy by Target target 

	if {$target eq {} || $target == 0} {
		set ChatHistory {}
	} elseif {$target < 0} {
		set ChatHistory [lrange $ChatHistory end-[expr abs($target)] end]
	} else {
		set old $ChatHistory
		set ChatHistory {}
		foreach msg $old {
			set mID [lindex $msg 2]
			if {$mID eq {} || $mID >= $target} {	
				if {[set msg [ValidateChatHistoryEntry $msg]] ne {}} {
				    lappend ChatHistory $msg
				} else {
				    DEBUG 1 "ClearChatHistory: Invalid message $msg"
				}
			}
		}
	}
	if {[dict get $d DoSilently]} {
		_log_transcription "\[---chat history cleared---\]"
	} elseif {$by eq "*"} {
		_log_transcription "\[---chat history cleared/re-synced---\]"
	} else {
		_log_transcription "\[---chat history cleared by $by---\]"
	}
}

proc BlankChatHistoryDisplay {} {
	global dice_preset_data local_user
	catch {
		set tkey [root_user_key] 
		$dice_preset_data(cw,$tkey).p.chat.1.text configure -state normal
		$dice_preset_data(cw,$tkey).p.chat.1.text delete 1.0 end
#		if {![info exists dice_preset_data(chat_lock)] || $dice_preset_data(chat_lock)} {
#			$dice_preset_data(cw,$tkey).p.chat.1.text configure -state disabled
#		}
		$dice_preset_data(cw,$tkey).p.chat.1.text configure -state disabled
		$dice_preset_data(cw,$tkey).p.pinnnedchat.1.text configure -state normal
		$dice_preset_data(cw,$tkey).p.pinnnedchat.1.text delete 1.0 end
		$dice_preset_data(cw,$tkey).p.pinnnedchat.1.text configure -state disabled
		update
	}
}
#
# Load up the chat window with what's in our in-memory chat history list.
#
proc LoadChatHistory {} {
	global ChatHistory dice_preset_data
	set w $dice_preset_data(cw,[root_user_key]).p.chat.1.text

	set prog_id [begin_progress * "Loading chat messages" [set prog_max [llength $ChatHistory]]]
	set prog_i 0
	foreach msg $ChatHistory {
		update_progress $prog_id [incr prog_i] $prog_max
	if {[set m [ValidateChatHistoryEntry $msg]] ne {}} {
	    lassign $m msg_type d msg_id

            switch -exact -- $msg_type {
		-system { _render_chat_message $w true $d {} {} false false }
                ROLL { DisplayDieRoll $d }
                TO   { 
			set d [lindex $m 1]
			if {[dict exists $d Sent]} {
				set date_sent [dict get $d Sent]
			} else {
				set date_sent {}
			}
			if {[dict get $d Sender] eq {-system}} {
				_render_chat_message $w 1 [dict get $d Text] {} {} false false $date_sent
			} else {
				if {[dict exists $d Markup] && [dict get $d Markup]} {
					set markup true
				} else {
					set markup false
				}
				if {[dict exists $d Pin] && [dict get $d Pin]} {
					set pinned true
				} else {
					set pinned false
				}
				_render_chat_message $w 0 [dict get $d Text] [dict get $d Recipients] [dict get $d Sender] [dict get $d ToAll] [dict get $d ToGM] $date_sent $markup $pinned
			}
		}
                CC	 {
                    set by [dict get $d RequestedBy]
		    if {[dict get $d DoSilently]} {
                        _render_chat_message $w 1 "Chat history cleared." {} {} false false
                    } elseif {$by eq "*"} {
                        _render_chat_message $w 1 "Chat history cleared/re-synced." {} {} false false
                    } else {
                        _render_chat_message $w 1 "Chat history cleared by $by." {} {} false false
                    }
                }
            }
        } else {
            DEBUG 1 "LoadChatHistory: Invalid message $msg"
        }
	}
	end_progress $prog_id
}


set chat_transcript_file {}
proc TranscribeChat {from recipientlist message toall togm {date_sent {}} {markup false} {pinned false}} {
	global ChatTranscript
	if {$markup} {
		set message [gma::minimarkup::strip [gma::minimarkup::render $message]]
	}
	if {$pinned} {
		set pinmsg " **PINNED**"
	} else {
		set pinmsg ""
	}

	if {$ChatTranscript ne {}} {
		if {[set private [Chat_text_attribution $from $recipientlist $toall $togm]] eq {}} {
			_log_transcription "<$date_sent> $from: $message$pinmsg"
		} else {
			_log_transcription "<$date_sent> $from ($private): $message$pinmsg"
		}
	}
}

proc _log_transcription {message} {
	global ChatTranscript chat_transcript_file

	if {$ChatTranscript ne {}} {
		if {$chat_transcript_file eq {}} {
			if {[catch {set chat_transcript_file [open [clock format [clock seconds] -format "$ChatTranscript"] a]} err]} {
				DEBUG 0 "Error writing to chat transcript file $ChatTranscript: $err. No further attempts will be made."
				set ChatTranscript {}
				return
			}
		}
		puts $chat_transcript_file "[clock format [clock seconds]]: $message"
		flush $chat_transcript_file
	}
}

proc TranscribeDieRoll {from recipientlist title result details toall togm {is_blind false} {is_invalid false} {date_sent {}}} {
	global ChatTranscript

	if {$ChatTranscript ne {}} {
		if {$date_sent eq {}} {
			set message *
		} else {
			set message [list $date_sent]
		}
		if {[set private [Chat_text_attribution $from $recipientlist $toall $togm]] eq {}} {
			append message "\[ROLL $result\] $from: "
		} else {
			append message "\[ROLL $result\] $from ($private): "
		}
		if {$is_invalid} {
			append message "ERROR "
		}
		if {$title ne {}} {
			append message "$title: "
		}
		if {[catch {
			foreach dd $details {
				# operator 	"op"
				# label    	" text"
				# [max]roll "{n,n,n,n,n,...,n}"
				# discarded "{n,n,n,n,n,...,n}"
				# maximized	">"
				# diespec	"desc"
				# diebonus	"±n"
				# best		" best of n"
				# worst		" worst of n"
				# result	"n"
				# separator	"="
				# bonus		"±n"
				# limit		", min|max n"
				# repeat	"until/repeat"
				# fullmax	"!"
				# success	"success"
				# fail		"fail"
				# moddelim  " | "
				# critspec	"c..."
				# critlabel	"Confirm:"
				# subtotal      "(n)"
				switch -exact [dict get $dd Type] {
					error  		{append message "\[ERROR: [dict get $dd Value]\] "}
					notice 		{append message "\[[dict get $dd Value]\] "}
					discarded	{append message "(DISCARDED: [dict get $dd Value])"}
					maxroll		{append message "(MAXIMIZED: [dict get $dd Value])"}
					diebonus	{append message "(per-die bonus [dict get $dd Value])"}
					fullmax     	{append message "MAXIMIZED ROLL: [dict get $dd Value]"}
					subtotal    	{append message "([dict get $dd Value])"}
					roll        	{append message "{[dict get $dd Value]}"}
					default 	{append message [dict get $dd Value]}
				}
			}
		} err]} {
			DEBUG 0 "Error transcribing die roll: $err"
			return
		}
		_log_transcription $message
	}
}

proc Chat_text_attribution {from recipientlist toall togm} {
	global local_user

	if {$togm} {return {blind to GM}}
	if {$toall} {return {}}
	if {[llength $recipientlist] == 1} {
		if {$from eq $local_user} {
			return "private to $recipientlist"
		} else {
			return "private"
		}
	} else {
		return "to [join $recipientlist {, }]"
	}
}

#proc AddDieRollPreset {for_user tkey} {
#	global dice_preset_data
#	set w .adrp[to_window_id $tkey]
#	create_dialog $w
#	wm title $w "Add Die-Roll Preset for $for_user"
#	#
#	# Preset Name: [___________________]
#	# Description: [___________________]
#	# Die Roll:    [___________________]
#	#
#	# [Cancel]                    [Save]
#	#
#
#	grid [label $w.nl -text "Preset Name:" -anchor w] \
#	     [entry $w.ne] -sticky news
#	grid [label $w.dl -text "Description:" -anchor w] \
#	     [entry $w.de] -sticky news
#	grid [label $w.rl -text "Die Roll:" -anchor w] \
#	     [entry $w.re] -sticky news
#	grid [button $w.c -text Cancel -command "destroy $w"] -sticky sw
#	grid [button $w.s -text Save -command [list CommitNewPreset $for_user $tkey]] -sticky se -row 3 -column 1
#	grid columnconfigure $w 1 -weight 1
#	grid rowconfigure $w 3 -weight 1
#}

proc SaveDieRollPresets {w for_user tkey} {
	global dice_preset_data

	if {[llength [array names dice_preset_data "preset,$tkey,*"]] == 0 } {
		tk_messageBox -parent $w -type ok -icon error -title "No Presets to Save" -message "You have no presets to save."
		return
	}

	if {[set file [tk_getSaveFile -defaultextension .dice -filetypes {
		{{GMA Die Roll Preset Files} {.dice}}
		{{All Files}        *}
	} -parent $w -title "Save current die-roll presets for $for_user as..."]] eq {}} return

	while {[catch {set f [open $file w]} err]} {
		if {[tk_messageBox -parent . -type retrycancel -icon error -default cancel -title "Error opening file"\
			-message "Unable to open $file: $err" -parent $w] eq "cancel"} {
			return
		}
	}

	if {[catch {
		set plist {}
		foreach {_ d} [array get dice_preset_data "preset,$tkey,*"] {
			lappend plist $d
		}
		::gmafile::save_dice_presets_to_file $f [list [dict create] $plist]
		close $f
	} err]} {
		say "Error saving dice presets: $err"
		catch {close $f}
	}
}

proc LoadDieRollPresets {w for_user tkey} {
	global dice_preset_data

	set old_n [llength [array names dice_preset_data "preset,$tkey,*"]]
	array unset new_preset_list
	if {$old_n > 0} {
		set answer [tk_messageBox -type yesnocancel -parent $w -icon question -title "Merge with existing presets?" \
			-message "You already have $old_n preset[expr $old_n==1 ? {{}} : {{s}}] defined. Do you want the new ones to be MERGED with those?"\
			-detail "If you answer YES, any presets from the file will overwrite existing ones with the same name, and any new ones will be added to your existing set. If you answer NO, all current presets will be deleted and only the ones from the file will exist." -default yes]
		if {$answer eq {yes}} {
			array set new_preset_list [array get dice_preset_data "preset,$tkey,*"]
		} elseif {$answer ne {no}} {
			return
		}
	}

	if {[set file [tk_getOpenFile -defaultextension .dice -filetypes {
		{{GMA Die Roll Preset Files} {.dice}}
		{{All Files}        *}
		} -parent $w -title "Load die roll presets for $for_user from..."]] eq {}} return

	while {[catch {set f [open $file r]} err]} {
		if {[tk_messageBox -parent . -type retrycancel -icon error -default cancel -title "Error opening file"\
			-message "Unable to open $file: $err" -parent $w] eq "cancel"} {
				return
		}
	}

	if {[catch {
		lassign [::gmafile::load_dice_presets_from_file $f] meta plist
		close $f
		DEBUG 1 "Loaded dice presets from version [dict get $meta FileVersion] file created [dict get $meta DateTime]; [dict get $meta Comment]"

		foreach p $plist {
			set new_preset_list([dict get $p Name]) $p
		}
	} err]} {
		tk_messageBox -type ok -icon error -title "Error Loading Preset File" \
			-message "Error loading file: $err" -parent $w
		catch {close $f}
		return
	}

	set deflist {}
	foreach {_ p} [array get new_preset_list] {
		lappend deflist $p
	}
	UpdateDicePresets $deflist $for_user
	RequestDicePresets $for_user
}

proc CommitNewPreset {for_user tkey} {
	global dice_preset_data
	set w .adrp[to_window_id $tkey]

	set name [string trim [$w.ne get]]
	set desc [string trim [$w.de get]]
	set def  [string trim [$w.re get]]

	if {$name eq {}} {
		tk_messageBox -parent . -type ok -icon error -title "Preset Name Required" \
			-message "The preset name must be provided. If it matches the name of an existing preset, it will replace the old one."
		return
	}
	if {$def eq {}} {
		tk_messageBox -parent . -type ok -icon error -title "Preset Definition Required" \
			-message "You didn't specify a die roll expression to store."
		return
	}
	if {[info exists dice_preset_data(preset,$tkey,$name)]} {
		if {! [tk_messageBox -parent . -type yesno -icon question -title "Overwrite previous preset?" \
			-message "There is already a preset for $for_user called \"$name\". Do you want to replace it with this one?" \
			-default no]} {
			return
		}
	}

	set dice_preset_data(preset,$tkey,$name) [dict create Name $name Description $desc DieRollSpec $def]
	set deflist {}
	foreach {_ p} [array get dice_preset_data "preset,$tkey,*"] {
		lappend deflist $p
	}
	UpdateDicePresets $deflist $for_user
	RequestDicePresets $for_user
	destroy $w
}

proc ChatAttribution {w from recipientlist toall togm} {
	global local_user
	if {[set private [Chat_text_attribution $from $recipientlist $toall $togm]] eq {}} {
		$w insert end [format_with_style "${from}: " from] from
	} else {
		$w insert end [format_with_style $from from] from
		$w insert end " ($private)" to
		$w insert end ": " from
	}
}

proc UpdatePeerList {for_user tkey} {
	# Update chat window widgets from peer list
	global PeerList LastKnownPeers check_menu_color dice_preset_data

	if {[catch {
		set tomenu $dice_preset_data(cw,$tkey).p.chat.2.to.menu
		$tomenu delete 2 end
		foreach name [lsort -dictionary -unique $PeerList] {
			if {$name ne {GM}} {
				$tomenu add checkbutton -label $name -onvalue 1 -offvalue 0 -variable dice_preset_data(CHAT_TO,$tkey,$name) -command [list update_chat_to $for_user $tkey] -selectcolor $check_menu_color
				if {![info exists dice_preset_data(CHAT_TO,$tkey,$name)]} {
					set dice_preset_data(CHAT_TO,$tkey,$name) 0
				}
			}
		}
	} err]} {
		DEBUG 1 "UpdatePeerList failed: $err"
	}

	global local_user
	if {$for_user eq $local_user} {
		foreach peer_name [array names LastKnownPeers] {
			if {[lsearch -exact $PeerList $peer_name] < 0} {
				unset LastKnownPeers($peer_name)
				DisplayChatMessage [::gmaproto::new_dict TO Text "$peer_name disconnected."] {} -noopen -system
				ChatHistoryAppend [list -system "$peer_name disconnected." -1]
			}
		}
		foreach peer_name $PeerList {
			if {! [info exists LastKnownPeers($peer_name)]} {
				set LastKnownPeers($peer_name) 1
				DisplayChatMessage [::gmaproto::new_dict TO Text "$peer_name joined."] {} -noopen -system
				ChatHistoryAppend [list -system "$peer_name joined." -1]
			}
		}
	}
}

proc SendDieRoll {recipients dice blind_p for_user tkey} {
	global dice_preset_data
	set d [ParseRecipientList $recipients TO ToGM $blind_p]
	# Special case: table lookups are introduced by die-rolls that look like
	# [title=] #tablename [...]
	if {[regexp -- {^\s*(.*=)?\s*#(#?)\{([a-zA-Z_]\w*)\}(.*?)$} $dice _ title globmark tablename rest] ||
	    [regexp -- {^\s*(.*=)?\s*#(#?)([a-zA-Z_]\w*)(.*?)$} $dice _ title globmark tablename rest]} {
		set preset_data [PresetLists dice_preset_data $tkey]
		if {$globmark eq "#"} {
			set tbl [SearchForPreset $preset_data table $tablename -global -details]
		} else {
			set tbl [SearchForPreset $preset_data table $tablename -details]
		}

		if {$tbl eq {}} {
			tk_messageBox -type ok -icon error -title "Undefined table"\
				-message "You tried to make a die-roll using a random look-up table, but the name of the table does not appear in your die-roll preset list."\
				-detail "Table name: #$globmark$tablename" -parent .
			return
		}
		if {[dict get $d ToGM]} {
			set flags b
		} else {
			set flags {}
		}

		::gmaproto::roll_dice "$title [dict get $tbl dieroll] $rest" [dict get $d Recipients] [dict get $d ToAll] [dict get $d ToGM] "#$globmark$tablename;$tkey;$flags;[new_id]"
	} else {
		::gmaproto::roll_dice $dice [dict get $d Recipients] [dict get $d ToAll] [dict get $d ToGM] [new_id]
	}
}
proc UpdateDicePresets {deflist for_user {system false}} {::gmaproto::define_dice_presets $deflist false $for_user $system}
proc RequestDicePresets {for_user} {::gmaproto::query_dice_presets $for_user}

proc SendChatMessage {recipients message {markup false} {pinned false}} {
	set d [ParseRecipientList $recipients TO]
	foreach msg [split $message "\n"] {
		::gmaproto::chat_message $msg {} [dict get $d Recipients] [dict get $d ToAll] [dict get $d ToGM] $markup $pinned
	}
}

proc RollTable {name for_user tkey} {
	global dice_preset_data
	set w $dice_preset_data(cw,$tkey)
	set wr [sframe content $w.p.recent.sf]
	set dice_preset_data(CHAT_dice,$tkey) $name
	SendDieRollFromWindow $w $wr $for_user $tkey
}

proc SendDieRollFromWindow {w wr for_user tkey} {
	global dice_preset_data

	if {$dice_preset_data(CHAT_dice,$tkey) != {}} {
		_do_roll $dice_preset_data(CHAT_dice,$tkey) {} $w $for_user $tkey

		# update list of most recent 10 rolls
		assert_recent_die_rolls $tkey
		for {set index -1; set i 0} {$i < [llength $dice_preset_data(recent_die_rolls,$tkey)]} {incr i} {
			if {[lindex [lindex $dice_preset_data(recent_die_rolls,$tkey) $i] 0] eq $dice_preset_data(CHAT_dice,$tkey)} {
				set index $i
				break
			}
		}
		if {$index >= 0} {
			if {$index > 0} {
				# move to the top of the list
				set dice_preset_data(recent_die_rolls,$tkey) [linsert [lreplace $dice_preset_data(recent_die_rolls,$tkey) $index $index] 0 [list $dice_preset_data(CHAT_dice,$tkey) {}]]
			}
		} else {
			set dice_preset_data(recent_die_rolls,$tkey) [linsert [lrange $dice_preset_data(recent_die_rolls,$tkey) 0 9] 0 [list $dice_preset_data(CHAT_dice,$tkey) {}]]
		}
		set dice_preset_data(CHAT_dice,$tkey) {}
		_render_die_roller $wr 0 0 recent $for_user $tkey
	}
}

proc Reroll {w index for_user tkey} {
	global dice_preset_data
	assert_recent_die_rolls $tkey

	if {$index >= 0 && $index < [llength $dice_preset_data(recent_die_rolls,$tkey)]} {
		set extra [string trim [$w.extra get]]
		_do_roll [lindex [lindex $dice_preset_data(recent_die_rolls,$tkey) $index] 0] $extra $w $for_user $tkey
	}
}

proc _apply_die_roll_mods {spec extra label {g false}} {
	DEBUG 1 "_apply_die_roll_mods to $spec: $extra ($label) g=$g"
	if {[set extra [string trim $extra]] eq {}} {
		DEBUG 1 " nothing to do, giving up"
		return $spec
	}
	set extra_parts [split $extra |]
	set spec_parts [split $spec |]
	DEBUG 1 " orig: $spec_parts; new: $extra_parts"
	if {[regexp {^([-+*(÷×≤≥]|//|<=|>=)} [lindex $extra_parts 0]]} {
		set op {}
	} else {
		DEBUG 1 " adding leading +"
		set op +
	}
	set s0 [lindex $spec_parts 0]
	if {$g} {
		if {[set titlesep [string first = $s0]] >= 0} {
			# there is a label, don't surround it in brackets
			set s0 "[string range $s0 0 $titlesep]([string range $s0 $titlesep+1 end])"
			DEBUG 1 " grouping $s0"
		} else {
			set s0 "($s0)"
			DEBUG 1 " grouping $s0"
		}
	} 
	if {[lindex $extra_parts 0] eq {}} {
		set newspec $s0
	} else {
		set newspec "$s0 $op [lindex $extra_parts 0] $label"
	}
	if {[llength $spec_parts] > 1} {
		append newspec "|" [join [lrange $spec_parts 1 end] |]
	}
	if {[llength $extra_parts] > 1} {
		append newspec "|" [join [lrange $extra_parts 1 end] |]
	}
	DEBUG 1 " -> $newspec"
	return $newspec
}

proc _apply_die_roll_variables {rollspec for_user tkey} {
	global DieRollPresetState
	set it 0
	foreach {vartype varform} {
		"gvar" {\$\$\{([a-zA-Z][a-zA-Z0-9]*)\}}
		"uvar" {\$\{([a-zA-Z][a-zA-Z0-9]*)\}}
		"gvar" {\$\$([a-zA-Z][a-zA-Z0-9]*)}
		"uvar" {\$([a-zA-Z][a-zA-Z0-9]*)}
	} {
	    while {[regexp -indices $varform $rollspec fieldidx varidx]} {
		DEBUG 1 " substitution of type $vartype $rollspec"
		if {[incr it] > 100} {
			error "too many iterations (circular reference?)"
		}
		set varname [string range $rollspec {*}$varidx]
		if {$vartype eq "gvar"} {
			set vkey "sys,gvar,$varname"
			set onkey "sys,gvar_on,$varname"
		} else {
			set vkey "$tkey,var,$varname"
			set onkey "$tkey,on,$varname"
		}
		if {[info exists DieRollPresetState($vkey)]} {
			if {$DieRollPresetState($onkey)} {
				set rollspec [string replace $rollspec {*}$fieldidx $DieRollPresetState($vkey)]
			} else {
				set rollspec [string replace $rollspec {*}$fieldidx]
			}
		} elseif {$vartype eq "gvar"} {
			error "system global variable <$varname> does not exist."
		} else {
			error "variable <$varname> does not exist for $for_user."
		}
	    }
	}
	DEBUG 1 " substitution result $rollspec"
	return $rollspec
}

proc _do_roll {roll_string extra w for_user tkey} {
	global dice_preset_data local_user
	global DieRollPresetState
	DEBUG 1 "_do_roll($roll_string, $extra, $w, $for_user, $tkey)"

	if {[catch {
		set rollspec [_apply_die_roll_mods $roll_string $extra { ad hoc}]
		DEBUG 1 " after ad hoc: $rollspec apply=[info exists DieRollPresetState($tkey,apply_order)]"
		if {[info exists DieRollPresetState($tkey,apply_order)]} {
			foreach id $DieRollPresetState($tkey,apply_order) {
				DEBUG 1 "  apply $id $DieRollPresetState($tkey,on,$id):$DieRollPresetState($tkey,global,$id):$DieRollPresetState($tkey,g,$id)"
				if {$DieRollPresetState($tkey,on,$id)} {
					set rollspec [_apply_die_roll_mods $rollspec $DieRollPresetState($tkey,global,$id) {} $DieRollPresetState($tkey,g,$id)]
					DEBUG 1 " after $DieRollPresetState($tkey,global,$id): $rollspec"
				}
			}
		}
		set rollspec [_apply_die_roll_variables $rollspec $for_user $tkey]
	} err]} {
		tk_messageBox -type ok -icon error -title "Unable to complete die roll"\
			-message "There was a problem with your die-roll request. It was not sent to the server."\
			-detail $err -parent $w
		return
	}
	DEBUG 1 " sending $rollspec"
	if {$for_user ne $local_user} {
		set rollspec [AddToDieRollTitle $rollspec "(for $for_user)"]
	}
	SendDieRoll [_recipients $for_user $tkey] $rollspec $dice_preset_data(CHAT_blind,$tkey) $for_user $tkey
}

proc AddToDieRollTitle {rollspec s} {
	if {[set eqidx [string first = $rollspec]] >= 0} {
		return "$s $rollspec"
	}
	return "$s=$rollspec"
}

proc RollPreset {w idx name for_user tkey scope} {
	global dice_preset_data

	if {$scope eq "GlobalRolls"} {
		set key "sys,preset"
	} else {
		set key "preset,$tkey"
	}

	if {[info exists dice_preset_data($key,$name)]} {
		set extra [string trim [$w.extra get]]
		_do_roll [dict get $dice_preset_data($key,$name) DieRollSpec] $extra $w $for_user $tkey
	}
}

#proc DeleteDieRollPreset {name for_user} {
#	global dice_preset_data
#	array set new_set [array get dice_preset_data]
#	catch {unset new_set($name)}
#	set deflist {}
#	foreach {_ p} [array get new_set] {
#		lappend deflist $p
#	}
#	UpdateDicePresets $deflist $for_user
#	RequestDicePresets
#}

proc SendChatFromWindow {for_user tkey} {
	global dice_preset_data local_user

	if {$dice_preset_data(CHAT_text,$tkey) != {}} {
		set ctext $dice_preset_data(CHAT_text,$tkey)
		if {$for_user != $local_user} {
			set ctext [format "(for %s) %s" $for_user $ctext]
		}

		if {$dice_preset_data(CHAT_blind,$tkey)} {
			::gmaproto::chat_message $ctext {} {} false true $dice_preset_data(CHAT_markup_en,$tkey) $dice_preset_data(CHAT_pinned_en,$tkey)
		} else {
			SendChatMessage [_recipients $for_user $tkey] $ctext $dice_preset_data(CHAT_markup_en,$tkey) $dice_preset_data(CHAT_pinned_en,$tkey)
		}
		set dice_preset_data(CHAT_text,$tkey) {}
		set dice_preset_data(CHAT_pinned_en,$tkey) 0
	}
}

proc _recipients {for_user tkey} {
	global dice_preset_data

	set recip_list {}
	set recip_idx [string length "CHAT_TO,$tkey,"]
	foreach name [array names dice_preset_data "CHAT_TO,$tkey,*"] {
		if {$dice_preset_data($name)} {
			lappend recip_list [string range $name $recip_idx end]
		}
	}
	if {[llength $recip_list] == 0} {
		set recip_list *
	}

	return $recip_list
}

proc AdjustView {x y} {
	# Adjust canvas so the (x,y) GRID coordinates are at the top left
	.c xview moveto $x
	.c yview moveto $y
}

proc SyncView {} {
	::gmaproto::adjust_view [lindex [.c xview] 0] [lindex [.c yview] 0] [TopLeftGridLabel]
}

proc aboutMapper {} {
	global GMAMapperVersion GMAMapperFileFormat GMAMapperProtocol CoreVersionNumber
	set connection_info {}
	if {[::gmaproto::is_enabled]} {
		if {[::gmaproto::is_connected]} {
			if {[::gmaproto::is_ready]} {
				set connection_info "Connected to ${::gmaproto::host}:${::gmaproto::port} as $::gmaproto::username. The server is version $::gmaproto::server_version and speaks protocol $::gmaproto::protocol."
			} else {
				set connection_info "This mapper is negotiating its connection to $::gmaproto::host."
			}
		} else {
			set connection_info "This mapper wants to connect to ${::gmaproto::host}:${::gmaproto::port}, but it has not yet connected."
		}
	} else {
		set connection_info "This mapper is running offline."
	}


	tk_messageBox -parent . -type ok -icon info -title "About Mapper" \
		-message "GMA Mapper Client, Version $GMAMapperVersion, for GMA $CoreVersionNumber.\n\nCopyright \u00A9 Steve Willoughby, Aloha, Oregon, USA. All Rights Reserved. Distributed under the terms and conditions of the 3-Clause BSD License.\n\nThis client supports file format $GMAMapperFileFormat and server protocol $GMAMapperProtocol." -detail $connection_info
}

proc SyncAllClientsToMe {} {
	global SafMode GMAMapperFileFormat OBJdata OBJtype MOBdata ClockDisplay MOB_IMAGE

	set oldcd $ClockDisplay
	if {[tk_messageBox -parent . -type yesno -icon question -title "Push map data to other clients?" \
			-message "This will push your map data to all other peers, replacing their map contents.  Are you sure?" \
			-default no]} {
		if {$SafMode} {
			# SafMode:
			# (1) Save file to temporary location
			# (2) Upload to server
			# (3) Issue command for clients to download it
			set ClockDisplay "Saving state to temporary file..."
			update
			if {[catch {
				set temp_file [file tempfile temp_name /tmp/mapper_sync_.map]
				file attributes $temp_name -permissions 0644
			} err]} {
				tk_messageBox -type ok -icon error -title "Error writing file"\
					-message "Unable to open temporary file: $err" -parent .
				set ClockDisplay $oldcd
				return
			}

			if {[catch {
				::gmafile::save_arrays_to_file $temp_file [dict create \
					Comment "Dynamic push of map data from one client to the others" \
					Location "Full-map sync" \
					] OBJdata OBJtype MOBdata MOB_IMAGE
				close $temp_file
			} err]} {
				tk_messageBox -type ok -icon error -title "Error writing file"\
					-message "Unable to save temporary file: $err" -parent .
				set ClockDisplay $oldcd
				catch {
					close $temp_file
					file delete $temp_name
				}
				return
			}

			set ClockDisplay "Uploading..."
			update
			saf_loadfile $temp_name $oldcd -nocheck
			::gmaproto::load_from [cache_map_id $temp_name] false false
			file delete $temp_name
			set ClockDisplay $oldcd
		} else {
			DEBUG 3 "SyncAllClientsToMe: sending global wipe"
			::gmaproto::clear *
			DEBUG 3 "SyncAllClientsToMe: sending all objects"

			if {[catch {
				foreach obj_id [array names OBJdata] {
					send_element $obj_id
				}

				foreach mob_id [array names MOBdata] {
					::gmaproto::place_someone_d [InsertCreatureImageName $MOBdata($mob_id)]
				}
			} err]} {
				tk_messageBox -type ok -icon error -title "Error sending data"\
					-message "Unable to send data to clients : $err" -parent .\
					-detail "Partial data may have been sent before the error occurred. In any case, you will need to try again to send the data."
				set ClockDisplay $oldcd
			}
			SyncView
		}
	}
}

proc AddToObjectAttribute {id key vlist} {
	if {[set idlist [ResolveObjectId_OA $id]] eq {}} {
		return
	}
	lassign $idlist a id datatype
	global $a

	if {![dict exists [set ${a}($id)] $key]} {
		DEBUG 0 "Attempt to access field $key in object $id but type $datatype has no such field."
		return
	}
	DEBUG 4 "Adding values to object $id.$key (in $a) from $vlist"
	foreach v $vlist {
		if {[lsearch -exact [dict get [set ${a}($id)] $key] $v] < 0} {
			dict lappend ${a}($id) $key $v
		}
	}
	DEBUG 4 "New value is [dict get [set ${a}($id)] $key]"
}
	
proc RemoveFromObjectAttribute {id key vlist} {
	if {[set idlist [ResolveObjectId_OA $id]] eq {}} {
		return
	}
	lassign $idlist a id datatype
	global $a

	if {![dict exists [set ${a}($id)] $key]} {
		DEBUG 0 "Attempt to access field $key in object $id but type $datatype has no such field."
		return
	}

	DEBUG 4 "Removing values from object $id.$key from $vlist"
	foreach v $vlist {
		if {[set index [lsearch -exact [dict get [set ${a}($id)] $key] $v]] >= 0} {
			dict set ${a}($id) $key [lreplace [dict get [set ${a}($id)] $key] $index $index]
		}
	}
	DEBUG 4 "New value is [dict get [set ${a}($id)] $key]"
}

# @name|id -> {arrayname id commandtype} or {}
proc ResolveObjectId_OA {id} {
	global MOBdata MOBid OBJdata OBJtype
	if {[string range $id 0 0] eq {@}} {
		# @name instead of id
		set key [AcceptCreatureImageName [string range $id 1 end]]
		if {[info exists MOBid($key)]} {
			return [list MOBdata $MOBid($key) PS]
		}
		DEBUG 1 "Attempt to change attribute of non-existent creature $key (IGNORED)"
		return {}
	} elseif {[info exists OBJtype($id)]} {
		set a OBJdata
		if {[catch {set t [::gmaproto::ObjTypeToGMAType $OBJtype($id)]} err]} {
			DEBUG 1 "object $id is of type $OBJtype($id) but we don't have a struct type for that. ($err)"
			return {} 
		}
	} elseif {[info exists MOBdata($id)]} {
		set a MOBdata
		set t PS
	} elseif {[info exists MOBid($id)]} {
		set a MOBdata
		set id $MOBid($id)
		set t PS
	} else {
		DEBUG 1 "Received request to change object $id which does not exist!"
		return {}
	}
	return [list $a $id $t]
}

proc SetObjectAttribute {id kvlist} {
	global canvas MOB_IMAGE MOBid MOBdata
	if {[set idlist [ResolveObjectId_OA $id]] eq {}} {
		return
	}
	
	lassign $idlist a id datatype
	set move_to_Gx {}
	set move_to_Gy {}
	global $a

	DEBUG 4 "Changing attributes of object $id from $kvlist"
	foreach {k v} $kvlist {
		if {$datatype eq "PS" && $k eq "CustomReach"} {
			set v [::gmaproto::new_dict CustomReach {*}$v]
		}

		if {$datatype eq "PS" && $k eq "Gx"} {
			set move_to_Gx $v
		}
		if {$datatype eq "PS" && $k eq "Gy"} {
			set move_to_Gy $v
		}

		if {$datatype eq "PS" && $k eq "Name"} {
			# changing creature name: also need to change the ID reverse mapping
			::gmautil::dassign $MOBdata($id) Name mob_name

			if {$v ne $mob_name} {
				# because it would be silly to panic here if we're "changing" to the same name we already have
				if {[info exists MOBid($v)]} {
					DEBUG 0 "Refusing to change name of creature $id from $mob_name to $v because that name is in use."
					continue
				}
				set old_name $mob_name
				if {[info exists MOB_IMAGE($old_name)]} {
					set MOB_IMAGE($v) $MOB_IMAGE($old_name)
					unset MOB_IMAGE($old_name)
				} else {
					set MOB_IMAGE($v) $old_name
				}
				unset MOBid($old_name)
				set MOBid($v) $id
				DEBUG 5 "-Changed ID reverse pointer MOBid($old_name) to MOBid($v)=$id"
			}
		}
		if {![dict exists [set ${a}($id)] $k]} {
			DEBUG 0 "Attempt to set field $k in object $id but type $datatype has no such field."
		} else {
			if {$k eq {AoE} && $v eq {null}} {
				set v {}
			}
			dict set ${a}($id) $k $v
			DEBUG 5 "-$a $id $k <- $v"
		}
	}
	if {$datatype eq "PS"} {
		if {$move_to_Gx ne {} && $move_to_Gy ne {}} {
			MoveSomeone $canvas $id $move_to_Gx $move_to_Gy
		}
		RefreshMOBs
		FlashMob $canvas $id 3
	} else {
		UpdateObjectDisplay $id
	}
}

proc ClearObjectById {id} {
	global OBJdata OBJtype MOBdata
	DEBUG 3 "ClearObjectById $id"

	if {$id eq "*"} {
		cleargrid
		clearplayers *
	} elseif {$id eq "M*"} {
		clearplayers monster
	} elseif {$id eq "P*"} {
		clearplayers player
	} elseif {$id eq "E*"} {
		cleargrid
	} elseif {[info exists OBJtype($id)]} {
		RemoveObject $id
	} elseif {[info exists MOBdata($id)]} {
		RemovePerson $id
	} elseif {[info exists MOBid($id)]} {
		RemovePerson $MOBid($id)
	} else {
		set name [AcceptCreatureImageName $id]
		if {[info exists MOBid($name)]} {
			RemovePerson $MOBid($name)
		} else {
			DEBUG 1 "Warning: Received request to delete object $id which does not exist."
		}
	}
}

proc SendMobChanges {id attrlist} {
	global MOBdata
	set alist [dict create]
	foreach attr $attrlist {
		dict set alist $attr [dict get $MOBdata($id) $attr]
	}
	::gmaproto::update_obj_attributes $id $alist
}

proc SendObjChanges {id attrlist} {
	global OBJdata
	set d [dict create]
	if {[info exists OBJdata($id)]} {
		foreach attr $attrlist {
			if {[dict exists $OBJdata($id) $attr]} {
				dict set d $attr [dict get $OBJdata($id) $attr]
			} else {
				DEBUG 0 "Attempt to send attribute $attr in object $id, but that field does not exist."
			}
		}
		DEBUG 3 "Sending update to object $id: $d"
		::gmaproto::update_obj_attributes $id $d
	}
}

#
# Placing people on the map:
#
# <<AC>> -> (menu)
# menu -> AddPlayer <name> <<PS>> -> PlaceSomeone <name> <type> -> MoveSomeone -> RenderSomeone
#                                         ^ ^                           ^          ^ ^ ^ ^
#         AddPlayerMenu ----------<<PS>>--+ |                           |          | | | |
#         <<PS>> ---------------------------+                           |          | | | |
# MOB_Drag -----------<<OA>> (at end of drag)---------------------------+          | | | |
# PopSomeoneToFront ---------------------------------------------------------------+ | | |
# RefreshMOBs -----------------------------------------------------------------------+ | |
# KillPerson ------<<OA>>--------------------------------------------------------------+ |
# FlashMob ------------------------------------------------------------------------------+
# <<OA>> -> SetObjectAttribute (change attributes -> refresh/flash)
#
# menu ------------<<CLR>>----> RemovePerson
#                                    ^
# <<CLR>> -> ClearObjectById---------+
#         -> clear{grid,players}
#         -> RemoveObject

#
# Drawing things:
# *tool -> bind <1>=start, <motion>=drag, OBJ_MODE=*
#                   start -> create obj, bind <ESC>/<middle>=end, <1>=NextPoint (line, poly)
#                                                                 <1>=LastPoint (rect, circ)
#                                                                 <1>=LastArcPoint (arc)
#                   nextpoint -> (append coords, continue)
#                   lastpoint -> (cleanup) -> end
#                   lastarcpoint -> commit coords, bind <1>=setangle, <motion>=dragangle
#                   setangle -> update coords, reset bindings for next arc -> end
#                   dragangle -> update coords, continue
#                   end -> (abort if no coords) or commit coords, <<LS>>, reset bindings for *tool
#
# killtool is different

#
# The following code is included from the Tcl Socks 5 client written by Kerem Hadimli:
#
# ---BEGIN-SOCKS5-CODE---
##############################################################################
# Socks5 Client Library v1.1
#     (C)2000 Kerem 'Waster_' HADIMLI
#
# How to use:
#   1) Create your socket connected to the Socks server.
#   2) Call socks:init procedure with these 6 parameters:
#        1- Socket ID : The socket identifier that's connected to the socks5 server.
#        2- Server hostname : The main (not socks) server you want to connect
#        3- Server port : The port you want to connect on the main server
#        4- Authentication : If you want username/password authenticaton enabled, set this to 1, otherwise 0.
#        5- Username : Username to use on Socks Server if authenticaton is enabled. NULL if authentication is not enabled.
#        6- Password : Password to use on Socks Server if authenticaton is enabled. NULL if authentication is not enabled.
#   3) It'll return you a string starting with:
#        a- "OK" if successful, now you can send/receive any data from the socket.
#        b- "ERROR:$explanation" if unsuccesfull, $explanation is the explanation like "Host not found". The socket will be automatically closed on an error.
#
#
# Notes:
#   - This library enters vwait loop (see Tcl man pages), and returns only
#     when SOCKS initialization is complete.
#   - This library uses a global array: socks_idlist. Make sure your program
#     doesn't use that.
#   - NEVER use file IDs instead of socket IDs!
#   - NEVER bind the socket (fileevent) before calling socks:init procedure.
##############################################################################
#
# Author contact information:
#   E-mail :  waster@iname.com
#   ICQ#   :  27216346
#   Jabber :  waster@jabber.org   (New IM System - http://www.jabber.org)
#
##############################################################################
#
#set socks_idlist(stat,$sck) ...
#set socks_idlist(data,$sck) ...

proc socks:init {sck addr port auth user pass} {
global socks_freeid socks_idlist

#  if { [catch {fconfigure $sck}] != 0 } {return "ERROR:Connection closed with Socks Server!"}    ;# Socket doesn't exist

  set ver "\x05"               ;#Socks version
  if {$auth==0} {set method "\x00"; set nmethods "\x01"} \
	elseif {$auth==1} {set method "\x00\x02"; set nmethods "\x02"} \
	else {return "ERROR:"}
  set nomatchingmethod "\xFF"  ;#No matching methods

  set cmd_connect "\x01"  ;#Connect command
  set rsv "\x00"          ;#Reserved
  set atyp "\x03"         ;#Address Type (domain)
  set dlen "[binary format c [string length $addr]]" ;#Domain length (binary 1 byte)
  set port [binary format S $port] ;#Network byte-ordered port (2 binary-bytes)

  set authver "\x01"  ;#User/Pass auth. version
  set ulen "[binary format c [string length $user]]"  ;#Username length (binary 1 byte)
  set plen "[binary format c [string length $pass]]"  ;#Password length (binary 1 byte)

  set a ""

  set socks_idlist(stat,$sck) 0
  set socks_idlist(data,$sck) ""

  fconfigure $sck -translation {binary binary} -blocking 0
  fileevent $sck readable "socks:readable $sck"

  puts -nonewline $sck "$ver$nmethods$method"
  flush $sck

  vwait socks_idlist(stat,$sck)
  set a $socks_idlist(data,$sck)
  if {[eof $sck]} {catch {close $sck}; return "ERROR:Connection closed with Socks Server!"}

  set serv_ver ""; set method $nomatchingmethod
  binary scan $a "cc" serv_ver smethod

  if {$serv_ver!=5} {catch {close $sck}; return "ERROR:Socks Server isn't version 5!"}

  if {$smethod==0} {} \
  elseif {$smethod==2} {  ;#User/Pass authorization required
	if {$auth==0} {catch {close $sck}; return "ERROR:Method not supported by Socks Server!"}

	puts -nonewline $sck "$authver$ulen$user$plen$pass"
	flush $sck

	vwait socks_idlist(stat,$sck)
	set a $socks_idlist(data,$sck)
	if {[eof $sck]} {catch {close $sck}; return "ERROR:Connection closed with Socks Server!"}

	set auth_ver ""; set status "\x00"
	binary scan $a "cc" auth_ver status

	if {$auth_ver!=1} {catch {close $sck}; return "ERROR:Socks Server's authenciation isn't supported!"}
	if {$status!=0} {catch {close $sck}; return "ERROR:Wrong username or password!"}

  } else {
	fileevent $sck readable {}
	unset socks_idlist(stat,$sck)
	unset socks_idlist(data,$sck)
	catch {close $sck}
	return "ERROR:Method not supported by Socks Server!"
  }

#
# We send request4connect
#
  puts -nonewline $sck "$ver$cmd_connect$rsv$atyp$dlen$addr$port"
  flush $sck

  vwait socks_idlist(stat,$sck)
  set a $socks_idlist(data,$sck)
  if {[eof $sck]} {catch {close $sck}; return "ERROR:Connection closed with Socks Server!"}

  fileevent $sck readable {}
  unset socks_idlist(stat,$sck)
  unset socks_idlist(data,$sck)

  set serv_ver ""; set rep ""
  binary scan $a cc serv_ver rep
  if {$serv_ver!=5} {catch {close $sck}; return "ERROR:Socks Server isn't version 5!"}

  if {$rep==0} {fconfigure $sck -translation {auto auto}; return "OK"} \
    elseif {$rep==1} {catch {close $sck}; return "ERROR:Socks server responded:\nGeneral SOCKS server failure"} \
    elseif {$rep==2} {catch {close $sck}; return "ERROR:Socks server responded:\nConnection not allowed by ruleset"} \
    elseif {$rep==3} {catch {close $sck}; return "ERROR:Socks server responded:\nNetwork unreachable"} \
    elseif {$rep==4} {catch {close $sck}; return "ERROR:Socks server responded:\nHost unreachable"} \
    elseif {$rep==5} {catch {close $sck}; return "ERROR:Socks server responded:\nConnection refused"} \
    elseif {$rep==6} {catch {close $sck}; return "ERROR:Socks server responded:\nTTL expired"} \
    elseif {$rep==7} {catch {close $sck}; return "ERROR:Socks server responded:\nCommand not supported"} \
    elseif {$rep==8} {catch {close $sck}; return "ERROR:Socks server responded:\nAddress type not supported"} \
      else {catch {close $sck}; return "ERROR:Socks server responded:\nUnknown Error"}
}

#
# Change the variable value, so 'vwait' loop will end in socks:init procedure.
#
proc socks:readable {sck} {
global socks_idlist
  incr socks_idlist(stat,$sck)
  set socks_idlist(data,$sck) [read $sck]
}
# ---END-SOCKS5-CODE---

proc TRACE args {
	puts "[info level 0]"
}

proc TRACEvar {name1 name2 op} {
	switch $op {
		array 	{ 
			puts "TRACE array $name1" 
		}
		read -
		write -
		unset {
			upvar $name1 v
			if {$name2 eq {}} {
				puts "TRACE $op $name1=$v"
			} else {
				puts "TRACE $op ${name1}($name2)=$v($name2)"
			}
		}
		default	{ puts "TRACE var $name1 $name2 $op" }
	}
}

proc connectToServer {} {
	global ITport IThost
	global ITproxy ITproxyuser ITproxypass ITproxyport
	global local_user ITpassword GMAMapperVersion

	#trace add execution ::gmaproto::_background_poll enterstep TRACE
	::gmaproto::dial $IThost $ITport $local_user $ITpassword $ITproxy $ITproxyport $ITproxyuser $ITproxypass "mapper $GMAMapperVersion"
}

proc WaitForConnectToServer {} {
	connectToServer
	InitializeChatHistory
}
#
#
# hack to try waiting long enough for our windows to appear on-screen
# after which we can look at them to see if the system has dark mode
# engaged and has influenced them. Then we adjust a few of our custom
# colors to ones that are more compatible with that.
#
# The --dark option causes this to happen immediately so we avoid this
# silliness and race condition.
#
if {! $dark_mode } {
	after 500 {
		if {[catch {
			set dark_mode [tk::unsupported::MacWindowStyle isdark .]
		}]} {
			set dark_mode 0 
		}
		if {$dark_mode} {
			.toolbar2.clock configure -foreground white
			refreshScreen
			set colortheme dark
		} else {
			set colortheme light
		}
	}
}

report_progress "Drawing battle grid"
DrawScreen $zoom $animatePlacement
cleargrid

report_progress "Connecting to server..."
if {$IThost ne {}} {
	WaitForConnectToServer
}

#
# canvas_see from the Tcl/Tk FAQ
#
proc canvas_see {c item} {
    set box [$c bbox $item]
    if {![llength $box]} return
    if {![llength [$c cget -scrollregion]]} {
		## People really should set -scrollregion you know...
		foreach {x y x1 y1} $box {
			set x [expr {round(2.5*($x1+$x)/[winfo width $c])}]
			set y [expr {round(2.5*($y1+$y)/[winfo height $c])}]
		}
		$c xview moveto 0
		$c yview moveto 0
		$c xview scroll $x units
		$c yview scroll $y units
    } else {
	## If -scrollregion is set properly, use this
		foreach {x y x1 y1} $box {top btm} [$c yview] \
			{left right} [$c xview] {p q xmax ymax} \
			[$c cget -scrollregion] {
			set xpos [expr {(($x1+$x)/2.0)/$xmax - ($right-$left)/2.0}]
			set ypos [expr {(($y1+$y)/2.0)/$ymax - ($btm-$top)/2.0}]
		}
		$c xview moveto $xpos
		$c yview moveto $ypos
    }
}


proc dumpMenu m {
	set last [$m index last]
	puts "Menu $m; $last entries:"
	for {set i 0} {$i <= $last} {incr i} {
		puts "  Entry $i type [$m type $i]"
	}
}

tk fontchooser configure -parent . -font $CURRENT_FONT
proc toggleFontChooser {} {
	catch {
		tk fontchooser [expr {
			[tk fontchooser configure -visible] ?
			"hide" : "show"}]
	}
}

proc SelectFont {canvas args} {
	global CURRENT_FONT CURRENT_TEXT_WIDGET zoom OBJdata
	DEBUG 3 "SelectFont canvas=$canvas args=$args"

	if {[llength $args] > 0} {
		set font [lindex $args]
	} else {
		DEBUG 3 "SelectFont has no change to report. Stopping."
		return
	}
	set CURRENT_FONT $font
	DEBUG 3 "Current font now $CURRENT_FONT"
	DEBUG 3 "Current widget is $CURRENT_TEXT_WIDGET"
	DEBUG 3 "Actual font ($CURRENT_FONT) -> ([font actual $CURRENT_FONT])"
	if {$CURRENT_TEXT_WIDGET ne {}} {
		DEBUG 3 "Setting obj$CURRENT_TEXT_WIDGET"
		$canvas itemconfigure obj$CURRENT_TEXT_WIDGET -font [ScaleFont [lindex $font 0] $zoom]
		dict set OBJdata($CURRENT_TEXT_WIDGET) Font [TkFontToGMAFont $font]
		DEBUG 3 "OBJ $CURRENT_TEXT_WIDGET font = [dict get $OBJdata($CURRENT_TEXT_WIDGET) Font]"
	}
}


proc PingMarker {w x y} {
	global zoom
	set cx [expr [$w canvasx $x] / $zoom]
	set cy [expr [$w canvasy $y] / $zoom]
	start_ping_marker $w $cx $cy 0
	::gmaproto::mark $cx $cy
}

proc start_ping_marker {w x y seq} {
	global zoom
	if {$seq > 0} {
		$w delete "Ping_${x}_${y}"
	}
	switch $seq {
		0	{ set rings {- - - - 1} }
		1	{ set rings {- - - 1 -} }
		2	{ set rings {- - 1 - -} }
		3	{ set rings {- 1 - - -} }
		4	{ set rings {1 - - - -} }
		5	{ set rings {- - - - 1} }
		6	{ set rings {- - - 1 -} }
		7	{ set rings {- - 1 - -} }
		8	{ set rings {- 1 - - -} }
		9	{ set rings {1 - - - -} }
		10	{ set rings {- - - - 1} }
		11	{ set rings {- - - 1 -} }
		12	{ set rings {- - 1 - -} }
		13	{ set rings {- 1 - - -} }
		14	{ set rings {1 - - - -} }
		default	{ return }
	}
	for {set i 0} {$i < 5} {incr i} {
		if {[lindex $rings $i] ne {-}} {
			$w create oval [expr $x*$zoom - $i*10] [expr $y*$zoom - $i*10] [expr $x*$zoom + $i*10] [expr $y*$zoom + $i*10] \
				-tags "Ping_${x}_${y}" -width 9 -outline black
			$w create oval [expr $x*$zoom - $i*10] [expr $y*$zoom - $i*10] [expr $x*$zoom + $i*10] [expr $y*$zoom + $i*10] \
				-tags "Ping_${x}_${y}" -width 5 -outline red
		}
	}
	after 100 start_ping_marker $w $x $y [expr $seq+1]
}


#
# Preferences Editor
#  edits the various config files in-place, so this will work
#  even if they are symlinks (which is the case with the main dev
#  who has a campaign selector script that links the active profiles
#  to the standard files)
#
#  __________________________________________
# |         | 
# |>Campaign| Selected Campaign (*) aaa  ^      **IF USING --config / --style**
# | General |                   ( ) bbb  |      Suppress this and just say you're
# | Mapper  |                   ( ) ccc  v      editing a specific named file; disable
# | GMA     | [+] [-]                           non-mapper configs
# | Server  |
# |_________|________________________________
#   Always 1 or more campaigns. Detect if none yet and setup default
#   find selection by examining symlinks
#   When selected, we symlink:
#     ~/.gma/gma.conf.<CAMPAIGN> -> ~/.gma.conf
#     ~/.gma/server.<CAMPAIGN>.{init,log,presets,sec} -> ~/.gma/server.{init,log,presets,sec}
#     ~/.gma/mapper/mapper.conf.<CAMPAIGN> -> ~/.gma/mapper/mapper.conf
#     ~/.gma/mapper/style.conf.<CAMPAIGN> -> ~/.gma/mapper/style.conf
#   Be sure to flush and reopen files when you do this so the other tabs work.
#  __________________________________________
# |         | [ ] Enable GM fields              <-- disables stuff players don't need
# | Campaign| [*] Filesystem is case-sensitive
# |>General | Curl path: [file path selector]
# | Mapper  | Curl URL base: [______________]
# | GMA     | Debugging level [0]
# | Server  | [ ] Dark mode
# |         | Server: [rag.com]              
# |         | Port: [2323]                   
# |         | Remote Mkdir: [______________] 
# |         | Module: [____________________] 
# |         | nc path: [___________________] 
# |         | Username: [__________________] 
# |         | [ ] Prompt for password        
# |         | Password: [__________________] 
# |         | Remote file location: [______] 
# |         | SCP path:                      
# |         | SCP server:                    
# |         | SSH path:                      
# |         | Update URL: [___]              
# |         | Proxy host: [___] URL [___]    
# |         |                                
# |         |                                
# |         |                                
# |         |                                
# |         |                                
# |         |                                
# |         |                                
# |_________|________________________________
#  __________________________________________
# |         | [ ] Animation effects
# | Campaign| [ ] Keep toolbar always
# | General | [ ] Preload cached images
# |>Mapper  | [ ] Disable chat/dice window
# | GMA     | Chat transcript [path]
# | Server  |
# |_________|________________________________
#
#      /Display\_________________________
#      | [ ] Animation effects
#      |     Button size: [small/medium/large]
#      |     Chat history limit: [512]
#      |     Major lines every [__] lines; +[0]-> +[0]v
#      |     Minor lines every [__] lines; +[0]-> +[0]v
#
#     /Health\___________________________
#     |      Blur HP 0|[]------------|100%
#     |  [ ] Blur for all creatures
#
#     /Party\_____________________________
#     | Name Image Color [edit] [-]
#     | Name Image Color [edit] [-]
#     | Name Image Color [edit] [-]
#     | Name Image Color [edit] [-]
#     | [+]
#
#     /Fonts\______________________________
#     | [*] Use general font definitions
#     |
#     | name: Sample [edit] [default|-]   --> Family: Size: Weight: Slant: Underline: Overstrike:
#     | [+]
#     |
#
#     /Die-Roll Styles\____________________
#     | [*] Use general style definitions
#     |
#     | Default font: [___]
#     | name: Sample [edit] [default]    --> bg font fg fmt offset overstrike underline
#     |
#     |
#     |
#  __________________________________________
# |         | 
# | Campaign| World (*) AAA ^
# | General |       ( ) BBB |
# | Mapper  |       ( ) CCC v
# |>GMA     | [+] [-]
# | Server  | [ ] Use global network settings  <-- forces default profile 
# |         | Network Profile (*) DDD ^
# |         |                 ( ) EEE v      
# |         | [+] [-]                        
# |         |                                
# |         |                                
# |         |                                
# |         |                                
# |_________|________________________________
#
#     /Network\____________________________
#     | For profile DDD
#     |
#     | Hostname: [___]
#     | Port:     [___]
#     |
#
#     /World\______________________________
#     | For profile AAA
#     |
#     | Blur HP |[]---------|100%
#     | Calendar Type [select]
#     | Database name: [___]
#     | Display name: [____]
#     | [*] use general password
#     | Password: [_____]
#     |
#     /Initiative\_________________________
#     | For profile AAA
#     |
#     | Name Dex Init CON HP
#     |
#     /Casters\____________________________
#     | For profile AAA
#     |
#     | Name CL [edit] [-]
#     | Name CL [edit] [-]
#     | Name CL [edit] [-]
#     | [+]
#     |
#  __________________________________________
# |         |
# | Campaign| 
# | General | Logfile: [___]
# | Mapper  | Port: [2323]
# | GMA     | Save interval: [10]
# |>Server  |
# |_________|________________________________
#
#  /Initial Commands\_____________________
#  | (text editor)
#
#  /Credentials\__________________________
#  | 
#  | User password: [_________]
#  | GM password: [_________]
#  | Personal Passwords Name password [edit] [-]
#  |                    Name password [edit] [-]
#  |                    Name password [edit] [-]
#  |                    [+]
#

proc initiate_hp_request {args} {
	# put up a new dialog to make a request for hp changes. We leave this up until dismissed or accepted by the GM.
	global global_bg_color icon_info20

	set this_request [new_id]
	set w .hprq_$this_request
	if {[lsearch -exact $args -tmp] >= 0} {
		set title "Temporary HP"
		set tmp true
	} else {
		set title "HP Change"
		set tmp false
	}

	toplevel $w -background $global_bg_color
	wm title $w "New ${title} Request"
	grid [label $w.dl -text "Description:"]  -row 0 -column 0 -sticky w
	grid [entry $w.de -width 64]         - - -row 0 -column 1 -sticky we
	if {$tmp} {
		grid [label $w.el -text "Expires:"]      -row 1 -column 0 -sticky w
		grid [entry $w.ee -width 64]         - - -row 1 -column 1 -sticky we
		grid [label $w.tl -text "Targets (CHARACTER name):"]      -row 2 -column 0 -sticky w
		grid [entry $w.te -width 64]             -row 2 -column 1 -sticky we
		grid [button $w.tm -command "ihr_personal_target $w" -text "ME"] -row 2 -column 2
		grid [button $w.tb -command "ihr_build_target_list $w" -text "..."] -row 2 -column 3
		::tooltip::tooltip $w.el {Temporary HP expiration as "@[[[y-]m-]d] h:m[:s[.t]]", "[+-][d:]h:m[:s[.t]]", or "[+-]n units"}
		::tooltip::tooltip $w.ee {Temporary HP expiration as "@[[[y-]m-]d] h:m[:s[.t]]", "[+-][d:]h:m[:s[.t]]", or "[+-]n units"}
		::tooltip::tooltip $w.tl {Players who should receive temporary HP (space-separated)}
		::tooltip::tooltip $w.te {Players who should receive temporary HP (space-separated)}
		::tooltip::tooltip $w.tb {Build list of targets interactively}
		::tooltip::tooltip $w.tm {Just give them to me}
		grid [label $w.xl -text "Requested temporary HP allocation:"]  -row 3 -column 0 -sticky w
		grid [entry $w.xe -width 4]                 -row 3 -column 1 -sticky w
		grid [label $w.ll -text "Lethal damage already against it:"]   -row 4 -column 0 -sticky w
		grid [entry $w.le -width 4]                 -row 4 -column 1 -sticky w
		::tooltip::tooltip $w.xl {How many additional temporary hit points you're asking for now.}
		::tooltip::tooltip $w.xe {How many additional temporary hit points you're asking for now.}
		::tooltip::tooltip $w.ll {How much, if any, damage was already taken against THIS request number of temporary hit points?}
		::tooltip::tooltip $w.le {How much, if any, damage was already taken against THIS request number of temporary hit points?}
		$w.le delete 0 end
		$w.le insert 0 0
	} else {
		grid [label $w.tl -text "Target (CHARACTER name):"]      -row 1 -column 0 -sticky w
		grid [entry $w.te -width 64]             -row 1 -column 1 -sticky we
		grid [button $w.tm -command "ihr_personal_target $w" -text "ME"] -row 1 -column 2
		grid [label $w.xl -text "Max HP:"]          -row 2 -column 0 -sticky w
		grid [entry $w.xe -width 4]                 -row 2 -column 1 -sticky w
		grid [label $w.ll -text "Lethal damage:"]   -row 3 -column 0 -sticky w
		grid [entry $w.le -width 4]                 -row 3 -column 1 -sticky w
		grid [label $w.nl -text "Nonlethal damage:"] -row 4 -column 0 -sticky w
		grid [entry $w.ne -width 4]                 -row 4 -column 1 -sticky w
		::tooltip::tooltip $w.xl {Your total maximum hit points (NOT including temporary HP).}
		::tooltip::tooltip $w.xe {Your total maximum hit points (NOT including temporary HP).}
		::tooltip::tooltip $w.ll {Total lethal damage currently suffered.}
		::tooltip::tooltip $w.le {Total lethal damage currently suffered.}
		::tooltip::tooltip $w.nl {Total nonlethal damage currently suffered.}
		::tooltip::tooltip $w.ne {Total nonlethal damage currently suffered.}
		$w.le delete 0 end
		$w.le insert 0 0
		$w.ne delete 0 end
		$w.ne insert 0 0
	}

	grid x [label $w.ml -text {}] - - -sticky we
	grid [button $w.cancel -command "destroy $w" -text Cancel] -row 6 -column 0 -sticky w
	grid [button $w.info -command "ihr_info" -image $icon_info20] - -row 6 -column 1
	grid [button $w.ok -command "ihr_commit $w $tmp $this_request" -text Request] -row 6 -column 3 -sticky e
	::tooltip::tooltip $w.dl {Describe the nature of your request.}
	::tooltip::tooltip $w.de {Describe the nature of your request.}
	::tooltip::tooltip $w.cancel {Dismiss this dialog box without taking further action.}
	::tooltip::tooltip $w.info {Display help information about requesting hit point changes.}
	::tooltip::tooltip $w.ok {Submit this request to the GM.}
}

proc initiate_timer_request {} {
	# put up a new dialog to make a request for a timer. We leave this up until dismissed or accepted by the GM.
	global global_bg_color icon_info20

	set this_request [new_id]
	set w .tmrq_$this_request
	toplevel $w -background $global_bg_color
	wm title $w "New Timer Request"
	grid [label $w.dl -text "Description:"]  -row 0 -column 0 -sticky w
	grid [entry $w.de -width 64]         - - -row 0 -column 1 -sticky we
	grid [label $w.el -text "Expires:"]      -row 1 -column 0 -sticky w
	grid [entry $w.ee -width 64]         - - -row 1 -column 1 -sticky we
	grid [label $w.tl -text "Targets:"]      -row 2 -column 0 -sticky w
	grid [entry $w.te -width 64]             -row 2 -column 1 -sticky we
	grid [button $w.tm -command "itr_personal_target $w" -text "ME"] -row 2 -column 2
	grid [button $w.tb -command "itr_build_target_list $w" -text "..."] -row 2 -column 3
	grid x [ttk::checkbutton $w.rb -text "Running Now"] - - -sticky w
	grid x [ttk::checkbutton $w.sb -text "Show to Players"] - - -sticky w
	grid x [label $w.ml -text {}] - - -sticky we
	grid [button $w.cancel -command "destroy $w" -text Cancel] -row 6 -column 0 -sticky w
	grid [button $w.info -command "itr_info" -image $icon_info20] - -row 6 -column 1
	grid [button $w.ok -command "itr_commit $w $this_request" -text Request] -row 6 -column 3 -sticky e
	$w.rb state {selected !alternate}
	$w.sb state {selected !alternate}
	::tooltip::tooltip $w.dl {Describe the new timer's purpose.}
	::tooltip::tooltip $w.de {Describe the new timer's purpose.}
	::tooltip::tooltip $w.el {Timer expiration as "@[[[y-]m-]d] h:m[:s[.t]]", "[+-][d:]h:m[:s[.t]]", or "[+-]n units"}
	::tooltip::tooltip $w.ee {Timer expiration as "@[[[y-]m-]d] h:m[:s[.t]]", "[+-][d:]h:m[:s[.t]]", or "[+-]n units"}
	::tooltip::tooltip $w.tl {Players timer is visible to (space-separated, default is visible to all)}
	::tooltip::tooltip $w.te {Players timer is visible to (space-separated, default is visible to all)}
	::tooltip::tooltip $w.tb {Build list of targets interactively}
	::tooltip::tooltip $w.tm {This timer's target is me}
	::tooltip::tooltip $w.rb {Should the timer start off running immediately? Or let the GM start it later?}
	::tooltip::tooltip $w.sb {Should the timer be visible to the players? Or just the GM?}
	::tooltip::tooltip $w.cancel {Dismiss this dialog box without taking further action.}
	::tooltip::tooltip $w.info {Display help information about requesting timers.}
	::tooltip::tooltip $w.ok {Submit this timer request to the GM.}
}

proc itr_info {} {
	set w .timer_request_help
	create_dialog $w
	wm title $w "How to Request a Timer"
	grid [text $w.text -yscrollcommand "$w.sb set"] \
	     [scrollbar $w.sb -orient vertical -command "$w.text yview"]\
		 	-sticky news
	grid columnconfigure $w 0 -weight 1
	grid rowconfigure $w 0 -weight 1
	$w.text tag configure h1 -justify center -font Tf14
	$w.text tag configure p -font Nf12 -wrap word
	$w.text tag configure i -font If12 -wrap word
	$w.text tag configure b -font Tf12 -wrap word

	foreach line {
		{h1 {Requesting Timers}}
		{p {}}
		{p  {The GM tracks a number of timed events for the game. You can request timers of your own (e.g., for actions your character is doing) to be added to that set of events. When you do this, you will create a request that will be sent to the GM's client in real time. They can then make any necessary adjustments and add it to the system. They may also decide not to add it to the system.}
		 i { Note that the GM must be logged in at the same time in order to receive and act on your request.}}
		{p {}}
		{p {To initiate a request, click on the "Request a New Timer" toolbar button (alarm clock with "+" sign) or choose the same option from the Play menu. Fill in the timer's description and expiration time (see below) in the fields provided.}}
		{p {}}
		{p {By default, timers will be visible to all players. If a timer only applies to some people, you can put their login names in the "Targets" field separated by spaces. For example: "} b {Alice Bob Charlie} p {" (although this is } i {not recommended,} p { if someone had spaces in their name, their entire name needs to be enclosed in braces like this: "} b {Alice Bob {This is me}} p {"). To make this easier, you can click on the "} b {ME} p {" button to put your own name in the target list to make the timer personal to you alone, or click the "} b {...} p {" button to bring up a dialog to select from among the logged-in players.}}
		{p {(Note that this doesn't } i {hide} p { your timer, just allows people to ignore it. If they set their maps to show all timers, they'll still see yours too.)}}
		{p {}}
		{p {Check the "Running Now" box if you want the timer to start off running as soon as it's created. Otherwise the GM will have to manually start it later.}}
		{p {Check the "Show to Players" box if you want the timer to be visible on the player map displays. Otherwise it will be added to the GM's time tracker but will only be visible to the GM.}}
		{p {}}
		{p {When ready, click the } b {Request} p { button. If you leave the dialog box up and there is a problem with the request you'll be informed and given the chance to correct the issue and resubmit it, or once the GM accepts the timer the dialog will go away on its own.}}
		{p {}}
		{h1 {Absolute Timers}}
		{p {An absolute timer expires at a specific date and time on the game clock. To create a timer such as this, the expiration time must begin with an }
		 b {@}
		 p { sign.}}
		{p {The full form accepted is }
		 b @ p {[[[} i year b - p {]} i month b - p {]} i day p {] } i hour b : i minute p {[} b : i second p {[} b . i tenths p {]]}}
		{p {Examples:}}
		{b {@12:00} p { (noon today)}}
		{b {@17:30:45} p { (half-past 5 PM plus 45 seconds)}}
		{b {@3-15 8:00} p { (8 AM on the 15th of the 3rd month)}}
		{b {@Absalom-20 10:15} p { (10:15 AM on the 20th of a month called Absalom)}}
		{b {@ABS-20 10:15} p { (as above, using abbreviated month name)}}
		{b {@4722-GOZ-1 00:00} p { (midnight, 1st of Gozran, 4722)}}
		{p {}}
		{h1 {Relative Timers}}
		{p {Relative timers count down until a certain duration of time has elapsed. These }
	     	 i {may}
		 p { begin with an initial }
		 b {+}
		 p { or }
		 b {-}
		 p { to indicate that they expire in the future or already did in the past, respectively (the default is to assume it is in the future). Following this is a time duration in one of the following forms:}}
		{p {[} i {n} p {] [} i {units} p {]}}
		{p {[[} i days b : p {]} i hours b : p {]} i minutes b : i seconds p {[} b . i tenths p {]}}
		{p {Examples:}}
		{b {+5 rounds}}
		{b {10 minutes}}
		{b {1:2:3:4.5} p { (one day, two hours, three minutes, 4.5 seconds)}}
		{b {10} p { (10 initiative counts, i.e. 1.0 seconds)}}
		{b {round} p { (1 round, i.e. defaults to 1 of the given unit)}}
		{b {3 days}}
		{b {1.5 hours}}
		{b {4 weeks}}
		{p {}}
		{p {Defined units include seconds (second, secs, sec, s), rounds (round, rnds, rnd, r), minutes (minute, mins, min, m), hours (hour, hrs, hr, h), weeks (week, wks, wk, w), and days (day, dys, dy, d).}}
	} {
		foreach {f t} $line {
			$w.text insert end $t $f
		}
		$w.text insert end "\n"
	}
}

proc ihr_info {} {
	set w .timer_request_help
	create_dialog $w
	wm title $w "How to Request Adjustments to your Hit Points"
	grid [text $w.text -yscrollcommand "$w.sb set"] \
	     [scrollbar $w.sb -orient vertical -command "$w.text yview"]\
		 	-sticky news
	grid columnconfigure $w 0 -weight 1
	grid rowconfigure $w 0 -weight 1
	$w.text tag configure h1 -justify center -font Tf14
	$w.text tag configure h2 -justify center -font Tf12
	$w.text tag configure p -font Nf12 -wrap word
	$w.text tag configure i -font If12 -wrap word
	$w.text tag configure b -font Tf12 -wrap word

	foreach line {
		{h1 {Requesting Adjustments to Your Hit Points}}
		{p {}}
		{p  {Your character hit points are tracked by GMA along with the other creatures involved in combat, so it's important that the system have an accurate idea of how many hit points you have at all times. There are two kinds of requests you can make to adjust this: updating the GM's record of your character's total hit points and wounds, and requesting a number of temporary hit points.}
		 i { Note that the GM must be logged in at the same time in order to receive and act on your request.}}
		{p {}}
		{h2 {Requesting Temporary Hit Points}}
		{p {If you want to add a number of hit points to your total "pool" of temporary hp, submit a request by choosing "Request Temporary Hit Points..." from the Play menu. Fill in the dialog that pops up with the required information: description of why the request is being made (say, the spell you cast to get the temporary hit points, for example), and when they expire (using any of the forms allowed for timers such as "10 rounds", "12 hours", "[1d4] minutes", or "@12:30").}}
		{p {}}
		{p {List the } b {character names} p { (} i {not} p { player or login names) for all the people who will be receiving these temporary hit points. If you click the "ME" button, your own login name will be filled in (but note that this only works if your login name is exactly the same as your character's name as it appears on the map). Likewise, clicking on the "..." button brings up a selection box to let you choose which of the logged-in users to include in the list of targets (again, assuming their login names match the character names on the map). The names in this target list are separated from each other with spaces.}}
		{p {}}
		{p {Enter the number of hit points you want to add in the next box on the form. If you already have temporary hit poinst allocated to your character, this many will be added to that existing number. If for some reason your character already took damage that was taken off the temporary hit point total, it's better to still ask for the full number you were supposed to have been given but also note the amount of damage in the following field on the form, so both are correctly accounted for.}}
		{p {}}
		{p {When ready, click the } b {Request} p { button. If you leave the dialog box up and there is a problem with the request you'll be informed and given the chance to correct the issue and resubmit it, or once the GM accepts the temporary hit point request the dialog will go away on its own.}}
		{p {}}
		{h2 {Requesting Adjustment To Permanent Hit Point Totals}}
		{p {If you want to correct the GM's records for how many hit points your character currently has, choose "Request Permanent Hit Point Adjustment..." from the Play menu. Fill in the dialog that pops up with the required information: description of why the request is being made (optionally), and the target } b {character name} p { (} i {not} p { player or login name) for your character. If you click the "ME" button, your login name will be filled in (but note that this only works if your login name is exactly the same as your character's name as it appears on the map).}}

		{p {}}
		{p {Enter the number of maximum hit points your character should have when fully healed (not counting any temporary hit points), the amount of current lethal damage suffered, and the amount of current nonlethal damage in the next three fields.}}
		{p {}}
		{p {When ready, click the } b {Request} p { button. If you leave the dialog box up and there is a problem with the request you'll be informed and given the chance to correct the issue and resubmit it, or once the GM accepts the hit point change request the dialog will go away on its own.}}
	} {
		foreach {f t} $line {
			$w.text insert end $t $f
		}
		$w.text insert end "\n"
	}
}

proc ihr_personal_target {w} {
	itr_personal_target $w
}

proc itr_personal_target {w} {
	global local_user
	$w.te delete 0 end
	$w.te insert end [list $local_user]
}

proc ihr_build_target_list {parent} {
	itr_build_target_list $parent
}

proc itr_build_target_list {parent} {
	global global_bg_color PeerList local_user

	set users $PeerList
	lappend users $local_user

	set w ${parent}_t
	catch {destroy $w}
	toplevel $w -background $global_bg_color
	wm title $w "Target List for [$parent.de get]"
	grid columnconfigure $w 1 -weight 2
	grid [ttk::checkbutton $w._all -text "Toggle All" -command "itr_toggle $w"] - - -sticky w
	$w._all state {!selected !alternate}
	foreach name [lsort -dictionary -unique $users] {
		set n [to_window_id $name]
		grid [ttk::checkbutton $w.p$n -text $name] - - -sticky w
		$w.p$n state {!selected !alternate}
	}
	grid [button $w._cancel -command "destroy $w" -text "Cancel"] x [button $w._ok -command "itr_commit_t $parent" -text "Set Targets"]
}

# this is a little janky but we just base our operations on the current peer list
# to keep the timer targets to who is logged in. But that makes the dialog box behave
# oddly if the peer list changes while we are editing the list.
proc itr_toggle {w} {
	global PeerList local_user

	set users $PeerList
	lappend users $local_user

	set toggle [$w._all instate selected]
	foreach name $users {
		catch {
			if {$toggle} {
				$w.p[to_window_id $name] state selected
			} else {
				$w.p[to_window_id $name] state !selected
			}
		}
	}
}

proc itr_commit_t {parent} {
	global PeerList local_user

	set users $PeerList
	lappend users $local_user

	set target_list {}
	foreach name $users {
		catch {
			if {[${parent}_t.p[to_window_id $name] instate selected]} {
				lappend target_list $name
			}
		}
	}
	$parent.te delete 0 end
	$parent.te insert end $target_list
	destroy ${parent}_t
}

proc itr_commit {w request_id} {
	set targets [string trim [$w.te get]]
	set desc [string trim [$w.de get]]
	set exp [string trim [$w.ee get]]
	if {![string is list $targets]} {
		$w.ml configure -foreground red -text "Target list has invalid format (unbalanced braces, maybe?)"
		return
	}
	if {$desc eq {} || $exp eq {}} {
		$w.ml configure -foreground red -text "Description and expiration time are required."
		return
	}
	::gmaproto::timer_request $request_id $desc $exp [$w.rb instate selected] $targets [$w.sb instate selected]
	$w.cancel configure -text Dismiss
	$w.ok configure -text Pending... -state disabled
	$w.ml configure -text "Waiting for GM to accept timer into system..."
	foreach ww {de ee te tb} {
		$w.$ww configure -state disabled
	}
	$w.sb state disabled
	$w.rb state disabled
}

proc ihr_commit {w tmp request_id} {
	set desc [string trim [$w.de get]]
	set targets [string trim [$w.te get]]
	set hp [$w.xe get]
	if {![string is integer $hp]} {
		$w.ml configure -foreground red -text "Invalid hit point value: must be an integer."
		return
	}
	set lethal [$w.le get]
	if {[string trim $lethal] eq {}} {
		set lethal "0"
	}
	if {![string is integer $lethal]} {
		$w.ml configure -foreground red -text "Invalid lethal damage value: must be an integer (enter 0 if none)."
		return
	}

	if {$tmp} {
		set exp [string trim [$w.ee get]]
		if {$exp eq {}} {
			$w.ml configure -foreground red -text "Expiration time is required."
			return
		}
	} else {
		set nonlethal [$w.ne get]
		if {[string trim $nonlethal] eq {}} {
			set nonlethal "0"
		}
		if {![string is integer $nonlethal]} {
			$w.ml configure -foreground red -text "Invalid nonlethal damage value: must be an integer (enter 0 if none)."
			return
		}
	}

	if {![string is list $targets]} {
		$w.ml configure -foreground red -text "Target list has invalid format (unbalanced braces, maybe?)"
		return
	}

	if {$tmp} {
		::gmaproto::hit_point_request_d [dict create \
			Targets $targets \
			Description $desc \
			RequestID $request_id \
			TmpHP [dict create \
				TmpHP $hp \
				LethalDamage $lethal \
				Expires $exp \
			]\
		]
	} else {
		::gmaproto::hit_point_request_d [dict create \
			Targets $targets \
			Description $desc \
			RequestID $request_id \
			Health [dict create \
				MaxHP $hp \
				LethalDamage $lethal \
				NonLethalDamage $nonlethal \
			]\
		]
	}

	$w.cancel configure -text Dismiss
	$w.ok configure -text Pending... -state disabled
	$w.ml configure -text "Waiting for GM to accept hit point request into system..."
	foreach ww {de ee te xe le ne tm tb} {
		catch {$w.$ww configure -state disabled}
	}
}

proc ihr_failed {request_id reason} {
	if {[catch {
		set w .hprq_$request_id
		foreach ww {de ee te xe le ne tm tb} {
			catch {$w.$ww configure -state normal}
		}
		$w.ok configure -state normal -text Request
		$w.cancel configure -text Cancel
		$w.ml configure -text $reason -foreground red
	}]} {
		tk_messageBox -parent . -type ok -icon error -title "HP Request Failed" \
			-message $reason
	}
}

proc ihr_accepted {request_id} {
	set w .hprq_$request_id
	catch {
		$w.ml configure -text "HP request accepted." -foreground "#008800"
		$w.ok configure -command "destroy $w" -text "Ok 5" -state normal
		after 1000 "ihr_destroy $w 4"
	}
}

proc ihr_destroy {w t} {
	catch {
		if {$t == 0} {
			destroy $w
		} else {
			$w.ok configure -text "OK $t"
			after 1000 "ihr_destroy $w [expr $t - 1]"
		}
	}
}

proc itr_failed {request_id reason} {
	if {[catch {
		set w .tmrq_$request_id
		foreach ww {de ee te tb} {
			$w.$ww configure -state normal
		}
		$w.sb state !disabled
		$w.rb state !disabled
		$w.ok configure -state normal -text Request
		$w.cancel configure -text Cancel
		$w.ml configure -text $reason -foreground red
	}]} {
		tk_messageBox -parent . -type ok -icon error -title "Timer Request Failed" \
			-message $reason
	}
}

proc itr_accepted {request_id} {
	set w .tmrq_$request_id
	catch {
		$w.ml configure -text "Timer request accepted." -foreground "#008800"
		$w.ok configure -command "destroy $w" -text "Ok 5" -state normal
		after 1000 "itr_destroy $w 4"
	}
}

proc itr_destroy {w t} {
	catch {
		if {$t == 0} {
			destroy $w
		} else {
			$w.ok configure -text "OK $t"
			after 1000 "itr_destroy $w [expr $t - 1]"
		}
	}
}

proc display_initiative_clock {} {
	global dark_mode
	global global_bg_color
	global time_abs
	global time_rel
	global MOB_COMBATMODE
	global IThost

	if {![::gmaproto::is_connected]} {
		tk_messageBox -parent . -type ok -icon error -title "No Connection to Server" \
			-message "Your client must be connected to the map server to use this function."
		return
	}

	::gmaclock::dest .initiative.clock
	catch {destroy .initiative}
	toplevel .initiative -background $global_bg_color
	wm title .initiative "Game Clock"
	wm protocol .initiative WM_DELETE_WINDOW {
		::gmaclock::dest .initiative.clock
		_destroy_initiative_window
		destroy .initiative
	}

	::gmaclock::initiative_display_window .initiative.clock 20 $dark_mode -background $global_bg_color
	pack .initiative.clock -side top -fill both -expand 1
	pack [ttk::labelframe .initiative.clock.timers -text Timers] -side top -fill x -expand 1
	update
	::gmaclock::draw_face .initiative.clock
	::gmaclock::update_time .initiative.clock $time_abs $time_rel
	::gmaclock::combat_mode .initiative.clock $MOB_COMBATMODE
	populate_timer_widgets
}

proc _destroy_initiative_window {args} {
	global timer_progress_data
	foreach k [array names timer_progress_data w:*] {
		set timer_progress_data($k) {}
	}
}


#
# Perform actions requested by command-line options now
#
report_progress "Adding party members"
foreach charToAdd $OptAddCharacters {
    DEBUG 0 "Adding party members via command-line option is no longer supported."
}
if {$OptPreload} {
    report_progress "Preloading image data..."
    load_cached_images
}
#
# Final setup
#
report_progress "Loading chat history..."
configureChatCapability
if {$UpgradeNotice} {
	say "You are now running the $GMAMapperVersion version of mapper. From now on, remember to run the mapper from [file normalize $argv0] so you will be running this version."
}
report_progress "Configuring SaF"
configureSafCapability
proc clear_report_progress {} {
	global progress_stack
	if {[llength $progress_stack] > 0} {
		after 5000 clear_report_progress
	} else {
		report_progress {}
	}
}
if {![::gmaproto::is_ready] && $IThost ne {}} {
    report_progress "Mapper Client Ready (awaiting server login to complete)"
} else {
    report_progress "Mapper Client Ready"
    after 5000 clear_report_progress
}
update_main_menu

proc ConnectToServerByIdx {idx} {
	global PreferencesData
	global preferences_path
	if {[catch {
		set newdata [::gmaprofile::set_current_profile $PreferencesData $idx]
	}]} {
		tk_messageBox -parent . -type ok -icon error -title "Unable to Connect" -message "Unable to find the requested server profile."
		return
	}
	set profilename [dict get $newdata current_profile]
	tk_messageBox -parent . -type ok -icon warning -title "Not Recommended" -message "We will attempt to reconnect you now to your \"$profilename\" server profile; however, this is not guaranteed to work 100% due to some known issues with the implementation of this feature.\n\nInstead, we recommend either of these methods which will work perfectly:\n(1) On the command line, add a --select '$profilename' switch to the mapper command;\n(2) Select Edit -> Preferences from the menu, click the Servers tab, click on $profilename, save, and click Yes to have the mapper restart with those settings.\nTo see a list of available profiles, run the mapper with the --list-profiles option."
	set PreferencesData $newdata
	#::gmaprofile::save $preferences_path $newdata
	ApplyPreferences $newdata
	global IThost
	::gmaproto::hangup
	WaitForConnectToServer
	refresh_title
}

#
# NEW: Animation support
#   In the cache dir, static images are $cache/_X/name@zoom.ext where X is character 4 of name (may be empty if name is short)
#   PROPOSED: animated images are $cache/_X/name@zoom/:frame:name@zoom.ext
#   PROPOSED: store animated metadata in $cache/_X/name@zoom/name@zoom.meta with image definition json dict
#   PROPOSED: store static metadata in $cache/_X/name@zoom.meta with image definition json dict
#   --DONE--: TILE_ANIMATION(<tileID>,frames) total number of frames
#   --DONE--: TILE_ANIMATION(<tileID>,current) current frame number in [0,frames)
#   --DONE--: TILE_ANIMATION(<tileID>,id,<objid>,<frame>) canvas ID of frame
#   --DONE--: TILE_ANIMATION(<tileID>,img,<frame>) tk image of frame (as TILE_SET is for static images)
#   --DONE--: TILE_ANIMATION(<tileID>,delay) delay between frames in mS
#   --DONE--: TILE_ANIMATION(<tileID>,loops) max loops or 0
#   --DONE--: TILE_ANIMATION(<tileID>,loop) current loop in [0,loops)
#   --DONE--: TILE_ANIMATION(<tileID>,task) task ID managing the animation or empty if stopped
#
#   --DONE--: animate by creating the stack of images with the same Z on the canvas then cycling through by running
#   		<canvas> raise <nextframeIDorTag> <previousframeIDorTag> (remember the ID is returned by canvas create)
#   		better due to alpha transparency: <canvas> itemconfigure <frameIDorTag> -state hidden|normal
#
#   --DONE--: animation_read_metadata <cachedir> <name> <zoom>			reads <cachedir>/X.meta -> dict
#   --DONE--: animation_destroy -tile <tileID>... | -all			destroy images from TILE_ANIMATION and tkimage
#   --DONE--: animation_destroy_instance <canvas> <tileID> <objID>		remove frame instances from canvas and TILE_ANIMATION
#   --DONE--: animation_init <tileID> <frames> <speed> <loops>			set up in system
#   --DONE--: animation_clear_frames <tilID>					remove all tk images
#   --DONE--: animation_add_frame <tilID> <n> <image>				add tk image
#   --DONE--: animation_create <canvas> <x> <y> <tileID> <objID> ?-start?
#   --DONE--: animation_newid <tileID> <frame#> <newCanvasID>
#   --DONE--: animation_start <canvas> -tile <tileiD>... | -all | -unexpired
#   --DONE--: animation_stop  -tile <tileiD>... | -all
#   
#   --DONE--: _load_local_animated_file <path> <name> <zoom> <frames> <speed> <loop>
#
#   PROPOSED: update all of the following to do the right thing w/r/t fetching and caching animated images
#
# TILE_SET(<tileID>) -> tk_image (static)
# TILE_ID(<tileID>) -> server_ID
# ImageFormat -> gif | png
#
# fetch_url <localdir> <local> <url> -> <data>
# 	uses curl to download <url> to <localdir>/<local>, read contents and return them
#
# --DONE-- incoming AI -> DoCommandAI dict
# 	opens file directly if local or embeeded else fetch_image <name> <zoom> <id>
# 	TILE_SET([tile_id <name> <zoom>]) <- image create photo <data>
# 	
# --DONE-- fetch_animated_image <name> <zoom> <id> <frames> <speed> <loops>
# --DONE-- create_animated_frame_from_file <tileID> <frame> <filename>
#          fetch_image <name> <zoom> <id>
# 		create_image_from_file if usable cache file found
# 		run curl to get file from server then create_image_from_file
# 	
#          tile_id <name> <zoom> -> "name:zoom" with zoom as %.2f
# --DONE-- cache_filename <imagepfx> <zoom> [<frame#>] -> path where image file should be located
# --DONE-- cache_file_dir <imagepfx> [<zoom>] [<frame#>] -> directory where cache_filename is to be located
#          cache_info <filename> -> exists? days name zoom {}|frame|-dir
#          create_image_from_file <tileID> <cache_path_name> (updates TILE_SET with cached data; error if file can't be read)
#
# --DONE-- load_cached_images (reads all NEWish cached files via create_image_from_file)
# --DONE-- loadfile <file> ... 
# 	for IMG records, 
# 		server images
#	 		calls fetch_image <imageID> <zoom> <serverID>
# 			updates TILE_ID
# 		local images
# 			reads data, creates tk_image
# 			updates TILE_SET
# 		-> AI to other clients
# --DONE-- RefreshGrid
# 	tile objects
# 		using tileID from FindImage (object.Image) at overall zoom
# 		create canvas image if in TILE_SET already else draw placeholder for it
# --DONE-- UpdateObjectDisplay
# 	tile objects
# 		using tileID from FindImage (object.Image) at overall zoom
# 		itemconfigure canvas object with tkimage from TILE_SET, possibly updating coordinates
# 		
# --DONE-- StartObj
# 	tile objects
# 		create canvas image from TILE_SET tkimage
#
# --DONE-- FindImage <imagepfx> <zoom>
# 	using tileID from tile_id <imagepfx> <zoom>
# 	if not in TILE_SET, call create_image_from_file [cache_filename]
# 	call ::gmaproto::query_image if needed
#
# --TODO-- RenderSomeone <w> <id> [<norecurse?>]
# 	looks for candidate images in TILE_SET; if not there, try FindImage then see if in TILE_SET
# 	creates canvas image frim TILE_SET
# 	
#
# cache file 
#   .../<name>@<zoom>.<ext>
#   .../<name>@<zoom>/:<frame>:<name>@<zoom>.<ext>
#   .../<name>.map
#
# support for multi-user die-roll presets
# DoCommandDD= receives incoming preset updates; now looks for "For" attribute
# 	default (old) behavior: call DisplayChatMessage to force window creation
# 	new (if For): DisplayChatMessage -for <user>
#
#*DisplayChatMessage <d> <USER>|{} ...
#*_render_die_roller <frame> _ _ <type> <USER> <TKEY> ...	update per-user preset window
#*_resize_die_roller <w> <wid> <ht> <type> <USER> <TKEY>
#*ResizeDieRoller <w> <wd> <ht> <type> <USER> <TKEY>
#*::resize_task(type)					==> ::resize_task(<tkey>,<type>)
#*inhibit_resize_task <flag> <type> <USER> <TKEY>
#
#*::dice_preset_data(name)=preset			==> ::dice_preset_data(preset,<tkey>,<name>)=preset	(user=$local_user by default)
#*[sframe .chatwindow.p.preset.sf].preset<i>		==> ::dice_preset_data(w,<tkey>,<name>)		widget displaying preset <i> from set
#*::DRPS_en<i>						==> ::dice_preset_data(en,<tkey>,<name>)
#*::EDRP_text<i>					==> ::dice_preset_data(EDRP_text,<tkey>,<i>)
#*::EDRP_mod_en<i>					==> ::dice_preset_data(EDRP_mod_en,<tkey>,<i>)
#*::EDRP_mod_ven<i>					==> ::dice_preset_data(EDRP_mod_ven,<tkey>,<i>)
#*::EDRP_mod_g<i>					==> ::dice_preset_data(EDRP_mod_g,<tkey>,<i>)
# (new)							==> ::dice_preset_data(delegates,<tkey>)=list
# (new)							==> ::dice_preset_data(delegate_for,<tkey>)=list
#*.chatwindow (toplevel)				==> ::dice_preset_data(cw,<tkey>)
#*.adrp							==> .adrp[to_window_id $tkey]
#*.edrp							==> .edrp[to_window_id $tkey]
#*::last_known_size(k)					==> ::last_known_size(<tkey>,<k>)
#*.chatwindow.p.chat.1 only created for the local use
#*::CHAT_dice						==> ::dice_preset_data(CHAT_dice,<tkey>)
#*::CHAT_blind						==> ::dice_preset_data(CHAT_blind,<tkey>)
#*::CHAT_TO(<recipient>)				==> ::dice_preset_data(CHAT_TO,<tkey>,<recipient>)
#*::CHAT_text						==> ::dice_preset_data(CHAT_text,<tkey>)
#*::recent_die_rolls					==> ::dice_preset_data(recent_die_rolls,<tkey>)
#*_collapse_extra <w> <i> <USER> <TKEY>
#*::DieRollPresetState(<k>)				==> ::DieRollPresetState(<tkey>,<k>)
#*_apply_die_roll_variables <spec> <USER> <TKEY>
#*::tmp_presets						==> ::dice_preset_data(tmp_presets,<tkey>)
#*chat_to_all <USER> <TKEY>
#*update_chat_to <USER> <TKEY>
# panels:
#   recent:
#     from dice_preset_data(recent_die_rolls,<tkey>) (list of roll history) $w.$i.* widgets for element #i
#   preset:
#     from dice_preset_data(preset,<tkey>,<presetname>)=presetdata;
#          dice_preset_data(w,<tkey>,<presetname>)=widget path for preset ($w.preset$i)
#
#*EditDieRollPresets <USER> <TKEY>
#*EDRPgetValues <W> <USER> <TKEY>
#*EDRPsaveValues <W> <USER> <TKEY>
#*DeleteDieRollpreset <name> <USER>
#*UpdateDicePresets <newpresets> <USER>
#*EDRPadd <W> <USER> <TKEY>
#*EDRPraise <W> <USER> <TKEY> <I>
#*EDRPlower <W> <USER> <TKEY> <I>
#*EDRPdel <W> <USER> <TKEY> <I>
#*EDRPdelCustom <W> <USER> <TKEY> <I>
#*EDRPaddModifier <W> <USER> <TKEY>
#*EDRPcheckVar <W> <USER> <TKEY> <I>
#*EDRPraiseModifier <W> <USER> <TKEY> <I>
#*EDRPlowerModifier <W> <USER> <TKEY> <I>
#*EDRPdelModifier <W> <USER> <TKEY> <I>
#*EDRPresequence <W> <USER> <TKEY>
#*EDRPupdateGUI <W> <USER> <TKEY>
#*SaveDieRollPresets <w> <USER> <TKEY>
#*LoadDieRollPresets <w> <USER> <TKEY>
#*RequestDicePresets <USER>
#*RefreshPeerList **NO CHANGE** **NO PARAMS**
#*SendChatFromWindow <USER> <TKEY>
#*SendDieRollFromWindow <W> <RECENT-W> <USER> <TKEY>
#*UpdatePeerList <USER> <TKEY>
#*_recipients <USER> <TKEY>
#*_do_roll <DICE> <EXTRA> <W> <USER> <TKEY>
#*PresetLists dice_preset_data <TKEY> -export
#*DRPScheckVarEn <i> <id>  ==> DRPScheckVarEn <key> <id> <USER> <TKEY>
#*DisplayDieRoll <d>
#*RollPreset <w> <i> <pname> <USER> <TKEY>
#*Reroll <w> <index> <USER> <TKEY>
#*CommitNewPreset <USER> <TKEY>
#*AddDieRollPreset <USER> <TKEY>
#
#*user_key name -> sanitized_name
#
# __TODO__
# [ ] piname change to add g/u prefix dice_preset_data(collapse,<tkey>,<piname>)
# [ ] 	see also DRPexpand, dice_preset_data(en,<tkey>,<piname>), DRPScheckVarEn
#
# PresetLists a tkey ?-export?
# 	Interprets contents of array a from caller's scope
# 	returns dict of Modifiers, Rolls, CustomRolls
#
# 	if -export, also sets global 
# 		DieRollPresetState <tkey>,*	
# 		DieRollPresetState <tkey>,apply_order	{}
# 		for modifiers
# 			with variable names
#	 			DieRollPresetState(<tkey>,var,<name>) = dierollspec
#	 **NEW**		DieRollPresetState(sys,gvar,<name>) = dierollspec
#	 **NEW**		DieRollPresetState(sys,gvar_on,<name>) = enabled (bool)
#	 			DieRollPresetState(<tkey>,on,<name>) = enabled (bool)
#	 			DieRollPresetState(<tkey>,g,<name>) = false
#	 		without names
#	 			DieRollPresetState(<tkey>,global,<seq>) = dierollspec
#	 			DieRollPresetState(<tkey>,on,<name>) = enabled (bool)
#	 			DieRollPresetState(<tkey>,g,<name>) = global (bool)
#	 			DieRollPresetState(<tkey>,apply_order) {...,<seq>}	(append to list)
#
#
# _render_die_roller
# SaveDieRollPresets w user tkey: saves preset,<key>,* to file
# LoadDieRollPresets w user tkey: loads from file, calls UpdateDicePresets <loadedlist> <user> then RequestDicePresets <user>
# UpdateDicePresets
# RequestDicePresets
# CommitNewPreset user tkey: loads from .adrp<window-id-derived-from-<tkey>> to preset,<tkey>,<name> then calls UpdateDicePresets then RequestDicePresets
# RollPreset w idx name user tkey: invokes preset,<tkey>,<name> with ad-hoc extra from <w>.extra widget by calling _do_roll
# _do_roll
#

#
# This is an experimental start of a refactored approach to die-roll modifier/presets which
# may replace some of the more messier earlier code, so there's some duplication here]
# for the moment until this eventually replaces the older stuff.
#

# Given an encoded representation of a preset as stored in die_roll_presets, 
# interpret it in detail, expanding all the relevant information for easy perusal.
#
# the source data is in the form 
# 	dice_preset_data(sys,preset,<Name>) [dict Global Name Description DieRollSpec]
# 	dice_preset_data(preset,<tkey>,<Name>) [dict ...]
# we expand this into a new dictionary
# 	type	preset|modifier|table
# 	group	list
#	seq	int
#	name
#	var	(empty if no variable name assigned)
#	flags	list (original flag list)
#	client	(original client data string)
#	global	bool	true if g flag set      )
#	enabled	bool	true if e flag set      ) consider these read-only; the flags field is the authoritative source
#	markup  bool    true if m flag set      )
#	system	bool	true if system-wide global value
#	table	list	[n0 t0 n1 t1 ... n-1 tN-1 "*" tN]
#	delim	for tables, this is the delimiter character used for the DieRollSpec field.
#	dieroll	dieroll spec (for tables, this is just the die-roll with the table spec removed)
#	description
#	_raw	saved copy of the original dictionary
#

# 
# update the flags value from the discrete flag booleans
#
proc SyncPresetDetailFlags {d} {
	dict set d flags {}
	if [dict get $d enabled] { dict lappend d flags e }
	if [dict get $d global] { dict lappend d flags g }
	if [dict get $d markup] { dict lappend d flags m }
	return $d
}

proc GetPresetDetails {p} {
	set d [dict create \
		client {} \
		delim {} \
		description [dict get $p Description] \
		dieroll [dict get $p DieRollSpec] \
		enabled false \
		flags {} \
		global false \
		group {} \
		markup false \
		name [set name [dict get $p Name]] \
		seq {} \
		system false \
		table {} \
		type preset \
		var {} \
		_raw $p \
	]
	if {[dict exists $p Global] && [dict get $p Global]} {
		dict set d system true
	}
	if {[set baridx [string first "|" $name]] < 0} {
		# no name encoding; this is just a preset
	} elseif {$baridx == 0} {
		# the name is "|name" which really doesn't make sense
		dict set d name [string range $name 1 end]
	} else {
		# the name may be encoded further, let's take a look.
		dict set d name [string range $name $baridx+1 end]
		set flags {}
		if {[string range $name 0 0] eq "\u00A7"} {
			dict set d type modifier
			set flds [split [string range $name 1 $baridx-1] ";"]
			if {[llength $flds] >= 2} {
				dict set d var [lindex $flds 1]
			}
			if {[llength $flds] >= 3} {
				dict set d flags [set flags [split [lindex $flds 2] {}]]
			}
			if {[llength $flds] >= 4} {
				dict set d client [lindex $flds 3]
			}
		} elseif {[string range $name 0 0] eq "#"} {
			dict set d type table
			set flds [split [string range $name 1 $baridx-1] ";"]
			if {[llength $flds] >= 2} {
				dict set d flags [set flags [split [lindex $flds 1] {}]]
			}
			if {[llength $flds] >= 3} {
				dict set d client [lindex $flds 2]
			}
			set delim [string range [set drs [dict get $p DieRollSpec]] 0 0]
			dict set d delim $delim
			set flds [split $drs $delim]
			if {[llength $flds] % 2 != 1 || [lindex $flds 0] ne "" || [lindex $flds end] ne "" || [llength $flds] < 5 || [lindex $flds end-2] ne "*"} {
				dict set d type invalid
			} else {
				dict set d dieroll [lindex $flds 1]
				set tbl {}
				set l 0
				set i 0
				foreach {n t} [lrange $flds 2 end-1] {
					if {$i == [llength $flds]-5} {
						if {$n ne "*"} {
							dict set d type invalid
							break
						}
					} elseif {![string is integer -strict $n]} {
						dict set d type invalid
						break
					}
					incr i 2
					lappend tbl $n $t
				}
				dict set d table $tbl
			}
		} else {
			set flds [split [string range $name 0 $baridx-1] ";"]
		}

		if {[lsearch $flags e] >= 0} {dict set d enabled true}
		if {[lsearch $flags g] >= 0} {dict set d global true}
		if {[lsearch $flags m] >= 0} {dict set d markup true}

		set groups [split [lindex $flds 0] "\u25B6"]
		dict set d seq [lindex groups 0]
		if {[llength $groups] > 1} {
			dict set d group [lrange $groups 1 end]
		}

		#<sequence>[\u25b6.*\u25b6.*...]|
		#\ua7<sequence>[\u25b6.*\u25b6.*...];[<var>];[<flags>][;<client>]|
		##<sequence>[\u25b6.*\u25b6.*...];<flags>][;<client>]|
		#
		#note that <sequence> need not be strictly numeric. GMA, for example, creates
		#temporary battle groups with <sequences> that look like "$[F12]001".
	}
	return $d
}

# SearchForPreset dict type name ?-global? ?-details? -> dict
#
# Given a dictionary of presets such as that returned from PresetLists, which has "type" keys Modifiers, Rolls, CustomRolls, etc., search
# for one particular named entry of the given type, interpreting now names may be encoded for entries of that type, and return it.
# If no such entry is found, return {} instead.
#
# The types supported are: modifier, table, or preset.
# If the -global option is given, search in the global set of presets instead of the local ones.
# If the -details option is given, expand the returned dictionary further into its detailed description by calling GetPresetDetails on it
# and returning that result instead.
#
proc SearchForPreset {d type target_name args} {
	if {[lsearch -exact $args -global] >= 0} {
		set collection {Global}
	} else {
		set collection {}
	}

	switch $type {
		preset   { append collection Rolls }
		modifier { append collection Modifiers }
		table    { append collection Tables }
		default  { error "Unsupported preset type '$type' passed to SearchForPreset '$name'" }
	}
	if {![dict exists $d $collection]} {
		return {}
	}
	foreach p [dict get $d $collection] {
		if {[set baridx [string first {|} [set name [dict get $p Name]]]] >= 0} {
			set name [string range $name $baridx+1 end]
		}
		
		if {$name eq $target_name} {
			if {[lsearch -exact $args -details] >= 0} {
				return [GetPresetDetails $p]
			}
			return $p
		}
	}
	return {}
}

proc _build_preset_group_name {name seq groups {prefix {}} {extra {}}} {
	if {[llength $groups] > 0} {
		if {$seq eq {}} {
			set seq {000}
		}
		set seq [join [list $seq {*}$groups] "\u25B6"]
	}
	if {$seq eq {} && $prefix eq {} && $extra eq {}} {
		return "$prefix$name"
	}
	return "$prefix$seq$extra|$name"
}

#
# EncodePresetDetails reverses GetPresetDetails. Given a dictionary of digested preset details, this re-encodes the preset as the
# GMA server expects to see it.
#
proc EncodePresetDetails {p} {
	switch [dict  get $p type] {
		preset {
			# preset:	Name: <seq>[<groups>]|<name>
			return [dict create \
				Global [dict get $p system] \
				Name	    [_build_preset_group_name [dict get $p name] [dict get $p seq] [dict get $p group]] \
				Description [dict get $p description] \
				DieRollSpec [dict get $p dieroll] \
			]
		}
		modifier {
			# mod:		Name: §<seq>[<groups>];[<var>];[<flags>][;<client>]|<name>
			set extra [join [list \
				[dict get $p var] \
				[join [dict get $p flags] {}] \
				[dict get $p client] \
			] ";"]
			return [dict create \
				Global [dict get $p system] \
				Name	    [_build_preset_group_name [dict get $p name] [dict get $p seq] [dict get $p group] "\u00A7" ";$extra"] \
				Description [dict get $p description] \
				DieRollSpec [dict get $p dieroll] \
			]
		}
		table {
			# table:	Name: #<seq>[<groups>];[<flags>][;<client>]|<name>
			#		DieRollSpec: ;<dieroll>;<n0>;<t0>;...;<nN-1>;<tN-1>;*;<tN>;
			set delim [dict get $p delim]
			set tabletext [join [dict get $p table] {}]
			set delimidx -1
			set delimset ";|,:/~><=!@_^`\001\002\003\004\005\006\007"
			while {[string first $delim $tabletext] >= 0} {
				incr delimidx
				if {$delimidx >= [string length $delimset]} {
					DEBUG 0 "Unable to find a free delimiter for table fields! the table probably won't be able to be represented correctly!"
					break
				}
				DEBUG 1 "Delimiter $delim won't work in table. Trying [string index $delimset $delimidx]"
				set delim [string index $delimset $delimidx]
			}
			
			set extra [join [list \
				[join [dict get $p flags] {}] \
				[dict get $p client] \
			] ";"]
			return [dict create \
				Global      [dict get $p system] \
				Name	    [_build_preset_group_name [dict get $p name] [dict get $p seq] [dict get $p group] "#" ";$extra"] \
				Description [dict get $p description] \
				DieRollSpec [join [list {} \
					[dict get $p dieroll] \
					{*}[dict get $p table] \
					{}] $delim] \
			]
		}
		default {
			# we don't know what it was to start with so we can't put it back together
			# again either, just return back what mess we were given originally.
			return [dict get $p _raw]
		}
	}
}

# DieRollPresetState
# 	<tkey>,on,<varname>		var behind checkbutton (user)
# 	<tkey>,var,<varname>	value
# 	<tkey>,g,<varname>	false for vars
# 	sys,gvar_on,<varname>	var behind checkbutton (user)
#
# 	<tkey>,global,<seq>	mod spec				<tkey>,
# 	<tkey>,on,<seq>		en?			==>
# 	<tkey>,g,<seq>		glob?
# 	<tkey>,apply_order	{<seq>,...}
#
#
#
# @[00]@| GMA-Mapper 4.33.1
# @[01]@|
# @[10]@| Overall GMA package Copyright © 1992–2025 by Steven L. Willoughby (AKA MadScienceZone)
# @[11]@| steve@madscience.zone (previously AKA Software Alchemy),
# @[12]@| Aloha, Oregon, USA. All Rights Reserved. Some components were introduced at different
# @[13]@| points along that historical time line.
# @[14]@| Distributed under the terms and conditions of the BSD-3-Clause
# @[15]@| License as described in the accompanying LICENSE file distributed
# @[16]@| with GMA.
# @[17]@|
# @[20]@| Redistribution and use in source and binary forms, with or without
# @[21]@| modification, are permitted provided that the following conditions
# @[22]@| are met:
# @[23]@| 1. Redistributions of source code must retain the above copyright
# @[24]@|    notice, this list of conditions and the following disclaimer.
# @[25]@| 2. Redistributions in binary form must reproduce the above copy-
# @[26]@|    right notice, this list of conditions and the following dis-
# @[27]@|    claimer in the documentation and/or other materials provided
# @[28]@|    with the distribution.
# @[29]@| 3. Neither the name of the copyright holder nor the names of its
# @[30]@|    contributors may be used to endorse or promote products derived
# @[31]@|    from this software without specific prior written permission.
# @[32]@|
# @[33]@| THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND
# @[34]@| CONTRIBUTORS “AS IS” AND ANY EXPRESS OR IMPLIED WARRANTIES,
# @[35]@| INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# @[36]@| MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# @[37]@| DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS
# @[38]@| BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
# @[39]@| OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# @[40]@| PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# @[41]@| PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# @[42]@| THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
# @[43]@| TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
# @[44]@| THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# @[45]@| SUCH DAMAGE.
# @[46]@|
# @[50]@| This software is not intended for any use or application in which
# @[51]@| the safety of lives or property would be at risk due to failure or
# @[52]@| defect of the software.
