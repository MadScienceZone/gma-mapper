#!/usr/bin/env wish
########################################################################################
#  _______  _______  _______             ______         ___    _______      ______     #
# (  ____ \(       )(  ___  ) Game      / ___  \       /   )  / ___   )    / ____ \    #
# | (    \/| () () || (   ) | Master's  \/   \  \     / /) |  \/   )  |   ( (    \/    #
# | |      | || || || (___) | Assistant    ___) /    / (_) (_     /   )   | (____      #
# | | ____ | |(_)| ||  ___  |             (___ (    (____   _)  _/   /    |  ___ \     #
# | | \_  )| |   | || (   ) |                 ) \        ) (   /   _/     | (   ) )    #
# | (___) || )   ( || )   ( | Mapper    /\___/  / _      | |  (   (__/\ _ ( (___) )    #
# (_______)|/     \||/     \| Client    \______/ (_)     (_)  \_______/(_) \_____/     #
#                                                                                      #
########################################################################################
#
# GMA Mapper Client with background I/O processing.
# @[00]@| GMA 4.4.3
# @[01]@|
# @[10]@| Copyright © 1992–2022 by Steven L. Willoughby (AKA MadScienceZone)
# @[11]@| steve@madscience.zone (previously AKA Software Alchemy),
# @[12]@| Aloha, Oregon, USA. All Rights Reserved.
# @[13]@| Distributed under the terms and conditions of the BSD-3-Clause
# @[14]@| License as described in the accompanying LICENSE file distributed
# @[15]@| with GMA.
# @[16]@|
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
#
# Auto-configure values
set GMAMapperVersion {3.42.6}     ;# @@##@@
set GMAMapperFileFormat {17}        ;# @@##@@
set GMAMapperProtocol {333}         ;# @@##@@
set GMAVersionNumber {4.4.3}            ;# @@##@@
# legacy variables (TODO: change to new ones)
set MapperVersion $GMAMapperVersion
set FileVersion $GMAMapperFileFormat
set ProtocolVersion $GMAMapperProtocol
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
set CURLserver https://www.rag.com/gma/map
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
set __generate_style_config {}
set __generate_config {}
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
#
#---------------------------[END CONFIG]--------------------------------------
#
# begin_progress id|* title maxvalue|* ?-send? -> id
# 
set ClockProgress 0
set progress_stack {}
proc begin_progress { id title max args } {
    if [catch {
        DEBUG 1 "begin_progress [list $id $title $max $args]"
        global ClockProgress progress_stack progress_data ClockDisplay
        if {$id eq "*"} {
            set id [new_id]
        }
        if {$args eq {-send}} {
            ITsend [list // BEGIN $id $max $title]
        }
        grid .toolbar2.progbar -row 0 -column 2 -sticky e
        set ClockProgress 0
        if {$max eq "*"} {
            .toolbar2.progbar configure -mode indeterminate
            .toolbar2.progbar start
        } else {
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
    } err] {
        DEBUG 0 "begin_progress $id: $err"
    }
    return $id
}

#
# update_progress id value newmax|* ?-send?
#
proc update_progress { id value newmax args } {
    if [catch {
        DEBUG 1 "update_progress [list $id $value $newmax $args]"
        global ClockProgress progress_stack progress_data ClockDisplay
        if {$args eq {-send}} {
            ITsend [list // UPDATE $id $value $newmax]
        }
        if [info exists progress_data($id:title)] {
            if {$newmax ne {} && $newmax ne "*"} {
                if {$progress_data($id:max) eq "*"} {
                    .toolbar2.progbar stop
                    .toolbar2.progbar configure -mode determinate
                }
                set progress_data($id:max) $max
                .toolbar2.progbar configure -maximum $newmax
            }
            if {$progress_data($id:max) eq "*"} {
                set progress_data($id:value) [expr $progress_data($id:value) + $value]
                if {$id eq [lindex $progress_stack end]} {
                    .toolbar2.progbar step $value
                }
            } else {
                set progress_data($id:value) $value
                if {$id eq [lindex $progress_stack end]} {
                    set ClockProgress $value
                }
            }
            update
        }
    } err] {
        DEBUG 0 "update_progress $id: $err"
    }
}

#
# end_progress id ?-send?
#    
proc end_progress {id args} {
    if [catch {
        global ClockProgress progress_stack progress_data ClockDisplay
        if {$args eq {-send}} {
            ITsend [list // END $id]
        }
        if {$progress_data($id:max) eq "*"} {
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
    } err] {
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

report_progress "Starting up..."
set dark_mode 0
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
set default_config    [file normalize [file join ~ .gma mapper mapper.conf]]
set default_style_cfg [file normalize [file join ~ .gma mapper style.conf]]
set path_install_base [file normalize [file join ~ .gma mapper]]

if [catch {set local_user $::tcl_platform(user)}] {set local_user __unknown__}
set ChatTranscript 	{}

proc say {msg} {
	tk_messageBox -type ok -icon warning -title "Warning" -message $msg
}

#
# We now accept image:name wherever a creature name coule be input.
# to facilitate this, the following functions will take an input creature
# name, and:
#	SplitCreatureImageName:  return a list of two elements: bare name and
#							 image name (or just bare name if there was no
#                            separate image given).
#	AcceptCreatureImageName: return the bare name, storing the image name 
#							 in MOB_IMAGE if one was specified.
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

proc ScaleFont {fontspec factor} {
	array set _base_font_info [font actual $fontspec]
	if [info exists _base_font_info(-size)] {
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

proc CheckProtocolCompatibility {v} {
	global ProtocolVersion
	DEBUG 1 "Service protocol is $v; we support up to $ProtocolVersion."
	if {$v > $ProtocolVersion} {
		say "This map client only supports map protocols up to version $ProtocolVersion. This server uses version $v. YOU SHOULD UPGRADE your mapper client before proceeding."
	} elseif {$v < $ProtocolVersion} {
		say "This map client supports map protocol version $ProtocolVersion. Your server is at version $v. While the map won't mind this, it may issue commands the other clients and server won't know how to interpret. YOU SHOULD UPGRADE the rest of your GMA system to the same version."
	}
}
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
proc DEBUG {level msg} {
	global DEBUG_level DEBUG_file path_DEBUG_file dark_mode

	if {$dark_mode} {
		set fgcolor(0) red
		set bgcolor(0) yellow
		set fgcolor(1) yellow
		set bgcolor(1) #232323
		set fgcolor(2) black
		set bgcolor(2) yellow
		set fgcolor(3) white
		set bgcolor(3) #232323
		set dialogbg #232323
	} else {
		set fgcolor(0) red
		set bgcolor(0) yellow
		set fgcolor(1) red
		set bgcolor(1) #cccccc
		set fgcolor(2) black
		set bgcolor(2) yellow
		set fgcolor(3) blue
		set bgcolor(3) #cccccc
		set dialogbg #cccccc
	}

	if {$level <= $DEBUG_level} {
		if {![winfo exists .debugwindow]} {
			toplevel .debugwindow -background $dialogbg
			grid [text .debugwindow.text -yscrollcommand {.debugwindow.sb set}] \
				[scrollbar .debugwindow.sb -orient vertical -command {.debugwindow.text yview}] -sticky news
			foreach l {0 1 2 3} {
				.debugwindow.text tag configure level$l -foreground $fgcolor($l) -background $bgcolor($l)
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

proc default_style_data {} {
	global dark_mode

	set default_styles {
		font_best       If12
		font_bonus      Hf12
		font_constant   Hf12
		font_critlabel  If12
		font_critspec   If12
		font_dc			If12
		font_diebonus   If12
		font_diespec    Hf12
		font_discarded  Hf12
		font_exceeded	If12
		font_fail       Tf12
		font_from       Hf12
		font_fullmax    Tf12
		font_fullresult Tf16
		font_iteration	If12
		font_label      If12
		font_max		If12
		font_maximized  Tf12
		font_maxroll    Tf12
		font_met     	If12
		font_min		If12
		font_moddelim   Hf12
		font_normal     Hf12
		font_operator   Hf12
		font_repeat     If12
		font_result     Hf14
		font_roll       Hf12
		font_subtotal   Hf12
		font_separator  Hf12
		font_short   	If12
		font_sf         If12
		font_system     If10
		font_success    Tf12
		font_title      Hf12
		font_to         If12
		font_until		If12
		font_worst      If12
		font_comment	If12
		fg_diebonus     red
		fg_fail         red
		fg_fullmax      red
		fg_maximized    red
		fg_maxroll      red
		fg_short        red
		fg_to           red
		overstrike_discarded 1
		fmt_best		{ best of %s}
		fmt_worst	{ worst of %s}
		fmt_critlabel	{Confirm: }
		fmt_dc			{DC %s: }
		fmt_discarded	{{%s}}
		fmt_exceeded	{exceeded DC by %s}
		fmt_fail        {(%s) }
		fmt_fullmax		maximized
		fmt_fullresult	{%s}
		fmt_iteration	{ (roll #%s)}
		fmt_label		{ %s}
		fmt_max			{max %s}
		fmt_maximized	>
		fmt_maxroll		{{%s}}
		fmt_met			successful
		fmt_min			{min %s}
		fmt_moddelim	{ | }
		fmt_repeat		{repeat %s}
		fmt_roll		{{%s}}
		fmt_subtotal    {(%s)}
		fmt_separator	=
		fmt_success     {(%s) }
		fmt_short		{missed DC by %s}
		fmt_title		{%s}
		collapse_descriptions 0
	}
	if $dark_mode {
		append default_styles {
			fg_best       #aaaaaa
			fg_bonus      #fffb00
			fg_comment    #fffb00
			fg_critlabel  #fffb00
			fg_critspec   #fffb00
			fg_dc         #aaaaaa
			fg_discarded  #aaaaaa
			fg_exceeded   #00fa92
			fg_from       cyan
			fg_iteration  #aaaaaa
			fg_label      cyan
			fg_max        #aaaaaa
			fg_met		  #00fa92
			fg_min        #aaaaaa
			fg_moddelim   #fffb00
			fg_repeat     #aaaaaa
			fg_roll       #00fa92
			fg_subtotal   #00fa92
			fg_sf         #aaaaaa
			fg_success    #00fa92
			fg_system     cyan
			fg_until      #aaaaaa
			fg_worst      #aaaaaa
			bg_fullresult blue
			fg_title      #aaaaaa
			bg_title      #000044
		}
	} else {
		append default_styles {
			bg_fullresult blue
			fg_fullresult #ffffff
			fg_best       #888888
			fg_bonus      #f05b00
			fg_comment    #f05b00
			fg_critlabel  #f05b00
			fg_critspec   #f05b00
			fg_dc         #888888
			fg_discarded  #888888
			fg_exceeded   green
			fg_from       blue
			fg_iteration  #888888
			fg_label      blue
			fg_max        #888888
			fg_met        green
			fg_min        #888888
			fg_moddelim   #f05b00
			fg_repeat     #888888
			fg_roll       green
			fg_subtotal   green
			fg_sf         #888888
			fg_success    green
			fg_system     blue
			fg_until      #888888
			fg_worst      #888888
			fg_title      #ffffff
			bg_title      #c7c0ae
		}
	}
	return $default_styles
}


proc LoadDefaultStyles {} {
	global display_styles dark_mode default_style_cfg

	if {$default_style_cfg ne {} && [file exists $default_style_cfg]} {
		LoadCustomStyle $default_style_cfg
	}

	#
	# Load up the default settings if they haven't already been
	# set by custom settings loaded previously
	#
	set default_styles [default_style_data]

	foreach {key value} $default_styles {
		if {! [info exists display_styles($key)]} {
			if {[string range $key 0 4] eq {font_}
			&&  [info exists display_styles(default_font)]} {
				set value $display_styles(default_font)
			}
			set display_styles($key) $value
		}
	}
}

proc LoadCustomStyle {filename} {
	# Load up styles from specified file
	# sections <h> -> list of all section names
	# keys <h> <s> -> liset of all keys in section <s>
	# get <h> <s> -> list of k,v pairs from section <s>
	# exists <h> <s> [<k>] -> does <s> (and key <k>) exist?
	# value <h> <s> <k> [<default>] -> value
	# 
	# [mapper]
	# dierolls=DIEROLLSTYLE
	# fonts=FONTS
	#
	# [DIEROLLSTYLE]
	# stylesetting=value
	#
	# [FONTS]
	# name=def
	# 
	global display_styles default_style_cfg
	set default_style_cfg {}	; # prevent loading the default one since we're loading this one

	if [catch {
		array unset fontdefs 
		set stylefile [::ini::open $filename r]
		if [::ini::exists $stylefile mapper] {
			if [::ini::exists $stylefile mapper fonts] {
				set f_style [::ini::value $stylefile mapper fonts]
				if [::ini::exists $stylefile $f_style] {
					foreach {fontname fontdef} [::ini::get $stylefile $f_style] {
						set fontdefs($fontname) 1
						font create CustomFont__$fontname {*}$fontdef
					}
				} else {
					say "Your style configuration file $filename asked for font definition set $f_style but that doesn't seem to exist."
				}
			} else {
				DEBUG 1 "Style file $filename does not define fonts for the mapper. (ignored)"
			}
						
			if [::ini::exists $stylefile mapper dierolls] {
				set dr_style [::ini::value $stylefile mapper dierolls]
				if [::ini::exists $stylefile $dr_style] {
					foreach {key value} [::ini::get $stylefile $dr_style] {
						if {[string range $key 0 4] eq {font_} || $key eq {default_font}} {
							if {! [info exists fontdefs($value)]} {
								say "Your style configuration file $filename asked for font $value but you didn't define one with that name."
							}
							set value CustomFont__$value
						} elseif {[string range $key 0 3] eq {fmt_}} {
							set value [string trim [string trim $value] |]
						}
						set display_styles($key) $value
					}
				} else {
					say "Your style configuration file $filename asked for die roll style $dr_style but that does not seem to exist in the file."
				}
			} else {
				DEBUG 1 "No dierolls setting in \[mapper\] stanza of $filename (ignored)"
			}
		} else {
			say "Your style configuration file does not define any settings for the mapper program."
		}
		::ini::close $stylefile
	} err] {
		say "Unable to load styles from $filename: $err"
	}
}
#
# Generate a new unique ID for an object.
#
proc new_id {} {
	return [string tolower [string map {- {}} [::uuid::uuid generate]]]
}

# SHA256 checksum calculation (if possible)
if [catch {
	package require sha256
}] {
	DEBUG 0 "WARNING: SHA256 support missing (install Tcllib!); data stream validation will NOT occur!"
	proc cs_init {} { return {}}
	proc cs_upate {t s} {}
	proc cs_final {t} {return {}}
	proc cs_match {expected advertised} {return 1}
} else {
	proc cs_init {} {
		return [::sha2::SHA256Init]
	}
	proc cs_update {t s} {
		::sha2::SHA256Update $t $s
	}
	proc cs_final {t} {
		return [::base64::encode [::sha2::SHA256Final $t]]
	}
	proc cs_match {expected advertised} {
		if [string equal $advertised {}] {
			DEBUG 1 "WARNING: remote data stream did not include checksum!"
			return 1
		}
		return [string equal $advertised $expected]
	}
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
foreach module {scrolledframe ustar gmautil} {
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
#set iscale 100
#set rscale 100.0
#
# Runtime Argument Processing
#
report_progress "parsing configuration and command-line arguments"
proc usage {} {
	global argv0
	global MapperVersion
	global stderr
	global ChatHistoryLimit

	puts $stderr "This is mapper, version $MapperVersion"
	puts $stderr "Usage: $argv0 \[-display name\] \[-geometry value\] \[other wish options...\] -- \[--help]"
	puts $stderr {        [-A] [-a] [-B] [-b pct] [-C file] [-c name[:color]] [-D] [-d]}
	puts $stderr {        [-G n[+x[:y]]] [-g n[+x[:y]]] [-h hostname] [-k] [-l] [-M moduleID]}
	puts $stderr {        [-n] [-P pass] [-p port] [-s stylefile] [-t transcriptfile] [-u name]}
	puts $stderr {        [-x proxyurl] [-X proxyhost] [--button-size size] [--chat-history n]}
	puts $stderr {        [--curl-path path] [--curl-url-base url] [--generate-config path]}
	puts $stderr {        [--generate-style-config path] [--mkdir-path path] [--nc-path path]}
	puts $stderr {        [--no-blur-all] [--scp-path path] [--scp-dest dir] [--scp-server hostname]}
	puts $stderr {        [--update-url url] [mapfiles...]}
	puts $stderr {Each option and its argument must appear in separate CLI parameters (words).}
	puts $stderr {   -A, --animate:     Enable animation of drawing onto the map}
	puts $stderr {   -a, --no-animate:  Suppress animation of drawing onto the map}
	puts $stderr {   -B, --blur-all:    Apply --blur-hp to all creatures, not just monsters}
	puts $stderr {       --no-blur-all: Cancel the effect of --blur-all [default]}
	puts $stderr {   -b, --blur-hp:     Change imprecision factor for health bar displays (0 for full precision) [0]}
	puts $stderr {       --button-size: Set button size to "small" (default), "medium", or "large"}
	puts $stderr {   -C, --config:      Read options from specified file (subsequent options further modify)}
	puts $stderr {   -c, --character:   Add another character name for menu}
	puts $stderr {   -D, --debug:       Increase debug output level}
	puts $stderr {   -d, --dark:        Adjust colors for dark mode}
	puts $stderr {   -G, --major:       Set major grid guidlines every n (offset by x and/or y)}
	puts $stderr {   -g, --guide:       Set minor grid guidlines every n (offset by x and/or y)}
	puts $stderr {       --help:        Print this information and exit}
	puts $stderr {   -h, --host:        Hostname for initiative tracker [none]}
	puts $stderr {   -k, --keep-tools:  Don't allow remote disabling of the toolbar}
	puts $stderr {   -l, --preload:     Load all cached images at startup}
	puts $stderr {   -M, --module:      Set module ID (SaF GM role only)}
	puts $stderr {   -n, --no-chat:		Do not display incoming chat messages}
	puts $stderr {   -P, --password:    Password to log in to the map service}
	puts $stderr {   -p, --port:        Port for initiative tracker [2323]}
	puts $stderr {   -s, --style:       Read style settings from specified file}
	puts $stderr {   -t, --transcript:  Specify file to record a transcript of chat messages and die rolls.}
	puts $stderr {   -u, --username:    Set the name you go by on your game server}
	puts $stderr {   -x, --proxy-url:   Proxy url for retrieving image data (usually like -x http://proxy.example.com:8080)}
	puts $stderr {   -X, --proxy-host:  SOCKS 5 proxy host and port for SSH/SCP (usually like -X proxy.example.com:8080)}
#	puts $stderr {   -P: SOCKS5 password}
#	puts $stderr {   -S: SOCKS5 proxy hostname}
#	puts $stderr {   -U: SOCKS5 username}
#	puts $stderr {   -s: SOCKS5 proxy TCP port}
	global CURLpath CURLserver SCPpath SSHpath SCPdest SCPserver NCpath SERVER_MKDIRpath
	puts $stderr "   --chat-history:   number of chat messages to retain between sessions \[$ChatHistoryLimit\]"
	puts $stderr "   --curl-path:      pathname of curl command to invoke \[$CURLpath\]"
	puts $stderr "   --curl-url-base:  base URL for stored data \[$CURLserver\]"
	puts $stderr "   --mkdir-path:     pathname of server-side mkdir command \[$SERVER_MKDIRpath\]"
	puts $stderr "   --nc-path:        pathname of nc command to invoke \[$NCpath\]"
	puts $stderr "   --scp-path:       pathname of scp command to invoke \[$SCPpath\]"
	puts $stderr "   --scp-dest:       server-side top-level storage directory \[$SCPdest\]"
	puts $stderr "   --scp-server:     storage server hostname \[$SCPserver\]"
	puts $stderr "   --ssh-path:       pathname of ssh command to invoke \[$SSHpath\]"
	puts $stderr "   --generate-style-config: append example style.conf file to specified pathname."
	puts $stderr "   --generate-config: append example mapper.conf file to specified pathname."
	puts $stderr "   --update-url:     base URL to automatically download software updates from."
	puts $stderr {   If map files are named, they are loaded at startup.}
	exit 1
}

# Initiative Tracking
set IThost {}
set ITport 2323
set ITsock {}
set ITbuffer {}
set ITpassword {}
set MasterClient 0
set ButtonSize small

proc getarg {opt} {
	global argv argc stderr
	upvar argi i

	if {[incr i] < $argc} {
		return [lindex $argv $i]
	}
	puts $stderr "Option $opt requires a parameter!"
	usage
}

if {[file exists $default_config]} {
	set argc [expr $argc + 2]
	set argv [linsert $argv 0 --config $default_config]
}

#
# Set up for delayed actions prompted by the command line options
#
set OptAddCharacters {}
set OptPreload 0

for {set argi 0} {$argi < $argc} {incr argi} {
	set option [lindex $argv $argi]
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
			set config_file [open $config_filename]
			while {[gets $config_file config_line] >= 0} {
				if {[string range $config_line 0 0] eq {#}} {
					continue
				}
				set c_args [split $config_line =]
				if {[llength $c_args] == 1} {
					# singleton argument
					incr argc
					set argv [linsert $argv [expr $argi + 1] "--$c_args"]
				} elseif {[llength $c_args] == 0} {
					# empty? Weird. ignore it.
				} else {
					# arg=value pair
					incr argc 2
					set argv [linsert $argv [expr $argi + 1] "--[lindex $c_args 0]" [join [lrange $c_args 1 end] =]]
				}
			}
			close $config_file
		}
		-c - --character { 
				set charToAdd [split [getarg -c] :]
				if {[llength $charToAdd] == 1} {
					lappend charToAdd blue
				} elseif {[llength $charToAdd] > 2} {
					puts $stderr "Option -c syntax error: should be '-c name\[:color\]'"
					usage
				}
                lappend OptAddCharacters $charToAdd
			}
		-D - --debug  { incr DEBUG_level }
		-d - --dark {set dark_mode 1}
		--help { usage }
		-h - --host { 
			set IThost [getarg -h] 
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
		-s - --style      { LoadCustomStyle [getarg -s] }
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
		--generate-style-config { set __generate_style_config [getarg --generate-style-config] }
		--generate-config       { set __generate_config [getarg --generate-config] }
		--update-url      { set UpdateURL [getarg --update-url] }
		--upgrade-notice  { set UpgradeNotice true }
		default {
			if {[string range $option 0 0] eq "-"} {
				usage
			}
			DEBUG 2 "Loading map from file $option"
			loadfile 1 $option
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
if {$dark_mode} {
	tk_setPalette background #232323 
    option add "*foreground" "#aaaaaa"
	set check_select_color #232323
	set check_menu_color #ffffff
	set global_bg_color #232323
	ttk::style configure TFrame -background $global_bg_color -foreground #ffffff
	ttk::style configure TPanedwindow -background $global_bg_color -foreground #ffffff
	ttk::style configure TLabelframe -background $global_bg_color -foreground #ffffff
	ttk::style configure TLabelframe.Label -background $global_bg_color -foreground #aaaaaa
	ttk::style configure TLabel -background $global_bg_color -foreground #ffffff
} else {
	set check_select_color #ffffff
	set check_menu_color #000000	; # XXX foreground
	set global_bg_color #cccccc
}

#
# tile ID
# 

proc tile_id {name zoom} {
	return "$name:$zoom"
}

#
# cache file name from name and zoom
#
proc cache_filename {name zoom} {
	global tcl_platform path_cache

	if {$tcl_platform(os) eq "Windows NT"} {
		file mkdir $path_cache
		file mkdir [file nativename [file join $path_cache _[string range $name 4 4]]]
	}
	return [file nativename [file join $path_cache _[string range $name 4 4] "$name@${zoom}.gif"]]
}
proc cache_file_dir {name} {
	global path_cache
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
#   pathname -> {exists? age(days) name zoom}
#   if the name is in an invalid format, name and zoom are empty strings
#
proc cache_info {cache_filename} {
	if [regexp {/([^/]+)@([0-9.]+)\.gif} $cache_filename x image_name image_zoom] {
		if [file exists $cache_filename] {
			return [list 1 [expr ([clock seconds] - [file mtime $cache_filename]) / (24*60*60)] $image_name $image_zoom]
		}
		return [list 0 0 $image_name $image_zoom]
	}
	if [regexp {/([^/]+)\.map} $cache_filename x map_name] {
		if [file exists $cache_filename] {
			return [list 1 [expr ([clock seconds] - [file mtime $cache_filename]) / (24*60*60)] $map_name {}]
		}
		return [list 0 0 $map_name {}]
	}
		
	return [list 0 0 {} {}]
}

#
# load an image from cache file
#
proc create_image_from_file {tile_id filename} {
	global TILE_SET

	if [catch {set image_file [open $filename r]} err] {
		DEBUG 0 "Can't open image file $filename ($tile_id): $err"
		return
	}
	fconfigure $image_file -encoding binary -translation binary
	if [catch {set image_data [read $image_file]} err] {
		DEBUG 0 "Can't read data from image file $filename ($tile_id): $err"
		close $image_file
		return
	}
	close $image_file
	if [info exists TILE_SET($tile_id)] {
		DEBUG 1 "Replacing existing image $TILE_SET($tile_id) for $tile_id"
		image delete $TILE_SET($tile_id)
		unset TILE_SET($tile_id)
	}
	if [catch {set TILE_SET($tile_id) [image create photo -format gif -data $image_data]} err] {
		DEBUG 0 "Can't use data read from image file $filename ($tile_id): $err"
		return
	}
}

#
# preload all the cached images into the map
#
proc load_cached_images {} {
	global cache_too_old_days path_cache

	DEBUG 1 "Loading cached images"
	puts "preloading cached images..."
	set i 0
	foreach cache_dir [glob -nocomplain -directory $path_cache _*] {
		DEBUG 2 "-scanning $cache_dir"
		foreach cache_filename [glob -nocomplain -directory $cache_dir *.gif] {
			set cache_stats [cache_info $cache_filename]
			if {[incr i] % 20 == 0} {
				puts -nonewline .
				if {$i % 100 == 0} {
					puts -nonewline $i
				}
				flush stdout
			}
			if {![lindex $cache_stats 0]} {
				DEBUG 0 "Cache file $cache_filename disappeared!"
				continue
			}
			if {[lindex $cache_stats 2] eq {} || [lindex $cache_stats 3] eq {}} {
				DEBUG 0 "Cache file $cache_filename not recognized (ignoring, but it shouldn't be there.)"
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
	foreach old_cache [glob -nocomplain -types f -directory $path_cache -tails *.gif] {
		set new_location [cache_file_dir $old_cache]
		set old_location [file join $path_cache $old_cache]
		DEBUG 0 "Moving old image file $old_location -> $new_location"
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
		DEBUG 0 "Moving old map file $old_location -> $new_location"
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
			if [catch {file delete $cache_filename} err] {
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
				if [catch {file delete $log_filename} err] {
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

foreach icon_name {
	line rect poly circ arc blank play
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
	delete add menu
} {
	if {$dark_mode && [file exists "${ICON_DIR}/d_${icon_name}${icon_size}.gif"]} {
		set icon_filename "${ICON_DIR}/d_${icon_name}${icon_size}.gif"
	} else {
		set icon_filename "${ICON_DIR}/${icon_name}${icon_size}.gif"
	}
	set icon_$icon_name [image create photo -format gif -file $icon_filename]
}

set canvas [canvas .c -height $canh -width $canw -scrollregion [list 0 0 $cansw $cansh] -xscrollcommand {.xs set} -yscrollcommand {.ys set}]
#set canvas [canvas .c -height $cansh -width $cansw -xscrollcommand {.xs set} -yscrollcommand {.ys set}]

grid [frame .toolbar] -sticky ew
grid [frame .toolbar2] -sticky ew
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
	lassign [.xs get] xstartfrac xendfrac
	lassign [.ys get] ystartfrac yendfrac
	if {$dark_mode} {
		set gridcolor #aaaaaa
	} else {
		set gridcolor blue
	}

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


proc toolBarState {state} {
    global toolbar_current_state
	if {$state} {
		grid configure .toolbar -row 0 -column 0 -sticky ew
        .toolbar2.menu.main_menu.view entryconfigure *Toolbar -label "Hide Toolbar" -command {toolBarState 0}
	} else {
		grid forget .toolbar 
        .toolbar2.menu.main_menu.view entryconfigure *Toolbar -label "Show Toolbar" -command {toolBarState 1}
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
	 [button .toolbar.snap -image $icon_snap_0 -command gridsnap] \
	 [button .toolbar.width -image [set icon_width_$initialwidth] -command setwidth] \
	 [label  .toolbar.sp2  -text "   "] \
	 [button .toolbar.clear -image $icon_clear -command {cleargrid; ITsend [list CLR E*]}] \
	 [button .toolbar.clearp -image $icon_clear_players -command {clearplayers *; ITsend [list CLR P*]; ITsend [list CLR M*]}] \
	 [label  .toolbar.sp3  -text "   "] \
	 [button .toolbar.combat -image $icon_combat -command togglecombat] \
	 [button .toolbar.showhp -image $icon_heart -command toggleShowHealthStats] \
	 [button .toolbar.aoe -image $icon_wand -command aoetool] \
	 [button .toolbar.aoebound -image $icon_wandbound -command aoeboundtool] \
	 [button .toolbar.ruler -image $icon_ruler -command rulertool] \
	 [button .toolbar.griden -image $icon_snap_1 -command toggleGridEnable] \
	 [button .toolbar.chat -image $icon_die20 -command {DisplayChatMessage {} {} {}}] \
	 [label  .toolbar.sp4  -text "   "] \
	 [button .toolbar.zi   -image $icon_zoom_in -command {zoomInBy 2}] \
	 [button .toolbar.zo   -image $icon_zoom_out -command {zoomInBy 0.5}] \
	 [button .toolbar.refresh -image $icon_zoom -command resetZoom] \
	 [button .toolbar.load -image $icon_open -command {loadfile 0 {}}] \
	 [button .toolbar.merge -image $icon_merge -command {loadfile 1 {}}] \
	 [button .toolbar.unload -image $icon_unload -command {unloadfile {}}] \
	 [button .toolbar.sync -image $icon_blank -command {} -state disabled] \
	 [button .toolbar.saf  -image $icon_saf -command toggleSafMode] \
	 [button .toolbar.polo -image $icon_arrow_refresh -command SyncFromServer] \
	 [button .toolbar.save -image $icon_save -command savefile] \
	 [button .toolbar.exit -image $icon_exit -command exitchk] 

grid [menubutton .toolbar2.menu -image $icon_menu -relief raised -menu .toolbar2.menu.main_menu] -row 0 -column 0 -sticky w
grid [label   .toolbar2.clock -anchor w -font {Helvetica 18} -textvariable ClockDisplay]         -row 0 -column 1 -sticky we 
grid [ttk::progressbar .toolbar2.progbar -orient horizontal -length 200 -variable ClockProgress] -row 0 -column 2 -sticky e
grid columnconfigure .toolbar2 1 -weight 2
grid forget .toolbar2.progbar

set mm .toolbar2.menu.main_menu
tooltip::tooltip .toolbar2.menu "Main Application Menu"
menu $mm
$mm add cascade -menu $mm.file -label File
$mm add cascade -menu $mm.edit -label Edit
$mm add cascade -menu $mm.view -label View
$mm add cascade -menu $mm.play -label Play
$mm add cascade -menu $mm.help -label Help
menu $mm.file
$mm.file add command -command {loadfile 0 {}} -label "Load Map File..."
$mm.file add command -command {loadfile 1 {}} -label "Merge Map File..."
$mm.file add command -command savefile -label "Save Map File..."
$mm.file add separator
$mm.file add command -command exitchk -label Exit
menu $mm.edit
$mm.edit add command -command playtool -label "Normal Play Mode"
$mm.edit add separator
$mm.edit add command -command {cleargrid; ITsend [list CLR E*]} -label "Clear All Map Elements"
$mm.edit add command -command {clearplayers monster; ITsend [list CLR M*]} -label "Clear All Monsters"
$mm.edit add command -command {clearplayers player; ITsend [list CLR P*]} -label "Clear All Players"
$mm.edit add command -command {clearplayers *; ITsend [list CLR P*]; ITsend [list CLR M*]} -label "Clear All Creatures"
$mm.edit add command -command {cleargrid; clearplayers *; ITsend [list CLR *]} -label "Clear All Objects"
$mm.edit add separator
$mm.edit add command -command linetool -label "Draw Lines"
$mm.edit add command -command recttool -label "Draw Rectangles"
$mm.edit add command -command polytool -label "Draw Polygons"
$mm.edit add command -command circtool -label "Draw Circles/Ellipses"
$mm.edit add command -command arctool  -label "Draw Arcs"
$mm.edit add command -command texttool -label "Add Text..."
$mm.edit add command -command killtool -label "Remove Objects"
$mm.edit add command -command movetool -label "Move Objects"
$mm.edit add command -command stamptool -label "Stamp Objects"
$mm.edit add separator
$mm.edit add command -command toggleNoFill -label "Toggle Fill/No-Fill"
$mm.edit add command -command {colorpick fill} -label "Choose Fill Color..."
$mm.edit add command -command {colorpick line} -label "Choose Outline Color..."
$mm.edit add separator
$mm.edit add command -command gridsnap -label "Cycle Grid Snap"
$mm.edit add command -command setwidth -label "Cycle Line Thickness"
$mm.edit add separator
$mm.edit add command -command {unloadfile {}} -label "Remove Elements from File..."
menu $mm.view
$mm.view add command -command {toolBarState 0} -label "Hide Toolbar"
$mm.view add command -command {toggleGridEnable} -label "Toggle Grid"
$mm.view add command -command {toggleShowHealthStats} -label "Toggle Health Stats"
$mm.view add separator
$mm.view add command -command {zoomInBy 2} -label "Zoom In"
$mm.view add command -command {zoomInBy 0.5} -label "Zoom Out"
$mm.view add command -command {resetZoom} -label "Restore Zoom"
$mm.view add separator
$mm.view add command -command {FindNearby} -label "Scroll to Visible Objects"
$mm.view add command -command {SyncView} -label "Scroll Others' Views to Match Mine"
$mm.view add command -command {refreshScreen} -label "Refresh Display"
menu $mm.play
$mm.play add command -command {togglecombat} -label "Toggle Combat Mode"
$mm.play add command -command {aoetool} -label "Indicate Area of Effect"
$mm.play add command -command {rulertool} -label "Measure Distance Along Line(s)"
$mm.play add command -command {DisplayChatMessage {} {} {}} -label "Show Chat/Die-roll Window"
$mm.play add separator
$mm.play add command -command {ClearSelection} -label "Deselect All"
menu $mm.help
$mm.help add command -command {aboutMapper} -label "About Mapper..."

proc configureChatCapability {} {
	global ITsock icon_blank

	if {$ITsock eq {}} {
		.toolbar.chat configure -image $icon_blank -state disabled
		tooltip::tooltip .toolbar.chat "Chat/die roll tool is not available unless connected to a server."
	}
}

proc configureSafCapability {} {
	global SCPdest SCPserver icon_blank

	if {$SCPdest eq {} || $SCPserver eq {}} {
		.toolbar.saf configure -image $icon_blank -state disabled
		tooltip::tooltip .toolbar.saf "Store-and-forward mode is not configured for this client."
	}
}

set SafMode 0
proc toggleSafMode {} {
	global SafMode icon_blank icon_saf_group_go
	playtool
	if [set SafMode [expr !$SafMode]] {
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
		tooltip::tooltip .toolbar.sync {Push this map to all other clients (USE THIS WITH CARE)}
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
		tooltip::tooltip clear .toolbar.sync
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
	kill	{Mode Select: Delete Objects}
	move	{Mode Select: Move Objects}
	stamp	{Mode Select: Stamp Images/Textures}
	nfill	{Toggle Fill/No-Fill Mode}
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
		tooltip::tooltip clear .toolbar.$btn
	} else {
		tooltip::tooltip .toolbar.$btn $tip
	}
}

proc exitchk {} {
	global OBJ_MODIFIED OBJ_FILE

	if {$OBJ_MODIFIED 
	&& [tk_messageBox -type yesno -default no -icon warning -title "Abandon changes to $OBJ_FILE?"\
		-message "You have unsaved changes to this map.  Do you want to abandon them and exit anyway?"]\
		ne "yes"} {
		return
	}
	exit
}

set NoFill 0
proc toggleNoFill {} {
	global NoFill

	if {$NoFill} {
		.toolbar.nfill configure -relief raised
		.toolbar.cfill configure -state normal
		set NoFill 0
	} else {
		.toolbar.nfill configure -relief sunken
		.toolbar.cfill configure -state disabled
		set NoFill 1
	}
}

set ShowHealthStats 0
proc toggleShowHealthStats {} {
	global ShowHealthStats

	set ShowHealthStats [expr !$ShowHealthStats]
	RefreshMOBs
}

proc togglecombat {} {
	global MOB_COMBATMODE
	setCombatMode [expr !$MOB_COMBATMODE]
	ITsend [list CO $MOB_COMBATMODE]
}

proc SyncFromServer {} {
	cleargrid
	clearplayers *
	ITsend SYNC
}

proc ReconnectToServer {} {
	global ITreceive_queue
	DEBUG 1 "IPC incoming queue was $ITreceive_queue"
	set ITreceive_queue {}
	DEBUG 1 "-now cleared"
	ITsend POLO
}

set DHS_Saved_ClockDisplay {}

proc blur_hp {maxhp lethal} {
	global blur_pct

	if {$blur_pct <= 0 || $maxhp <= $lethal} {
		return [expr $maxhp - $lethal]
	} else {
		if [catch {
			set mf [expr $maxhp * ($blur_pct / 100.0)]
			set res [expr max(1, int(int(($maxhp - $lethal) / $mf) * $mf))]
		} err] {
			DEBUG 0 "Error calculating blurred HP total: $err; falling back on true value"
			return [expr $maxhp - $lethal]
		}
		return $res
	}
}

proc CreateHealthStatsToolTip {mob_id} {
	global MOB
	if {$mob_id eq {} || ![info exists MOB(NAME:$mob_id)]} {
		return {}
	}

	# get the list of applied conditions
	set conditions {}

	if {$MOB(KILLED:$mob_id)} {
		set dead 1
	} else {
		set dead 0
	}

	if {[info exists MOB(_CONDITION:$mob_id)] && $MOB(_CONDITION:$mob_id) ne {}} {
		switch -exact -- $MOB(_CONDITION:$mob_id) {
			dead {
				set dead 1
			}
			flat {
				lappend conditions flat-footed
			}
			default {
				lappend conditions $MOB(_CONDITION:$mob_id)
			}
		}
	}
	if {[info exists MOB(STATUSLIST:$mob_id)] && [llength $MOB(STATUSLIST:$mob_id)] > 0} {
		lappend conditions {*}$MOB(STATUSLIST:$mob_id)
	}
	if {[info exists MOB(HEALTH:$mob_id)]} {
		DistributeZero $MOB(HEALTH:$mob_id) maxhp lethal nonlethal con flatp stablep hcondition server_blur_pct
		if {$flatp ne {} && $flatp && [lsearch -exact $conditions flat-footed] < 0} {
			lappend conditions flat-footed
		}
		if {$stablep ne {} && $stablep && [lsearch -exact $conditions stable] < 0} {
			lappend conditions stable
		}
		set tiptext "$MOB(NAME:$mob_id):"

		global blur_all blur_pct
		set client_blur {}
		set server_blur {}
		if {$blur_all || $MOB(TYPE:$mob_id) ne {player}} {
			set hp_remaining [blur_hp $maxhp $lethal]
			if {$blur_pct > 0} {
				set client_blur [format "(\u00B1%d%%)" $blur_pct]
			}
		} else {
			set hp_remaining [expr $maxhp - $lethal]
		}
		if {$server_blur_pct ne {} && $server_blur_pct > 0} {
			set server_blur [format "\u00B1%d%%" $server_blur_pct]
		}
		if {!$dead} {
			if {$MOB(TYPE:$mob_id) eq {player}} {
				if {$maxhp == 0} {
					if {$lethal == 0} {
						append tiptext " no lethal wounds"
					} else {
						append tiptext [format " %d%s%s lethal wounds" $lethal $client_blur $server_blur]
					}
				} else {
					append tiptext [format " %d/%d%s%s HP" $hp_remaining $maxhp $client_blur $server_blur]
				}
				if {$nonlethal != 0} {
					append tiptext [format " (%d non-lethal)" $nonlethal]
				}
			} else {
				# not a player; so we're not quite as direct about health status
				if {$maxhp == 0} {
					# we don't know the creatures's hit point total
					append tiptext [format " %d%s%s lethal damage" $lethal $client_blur $server_blur]
					if {$nonlethal != 0} {
						append tiptext [format " (%d non-lethal)" $nonlethal]
					}
				} else {
					# otherwise we know more about what the damage means in context
					if {$lethal > $maxhp} {
						if {[lsearch -exact $conditions dying] < 0} {
							lappend conditions dying
						} 
					} else {
						append tiptext [format " %d%%%s%s HP" [expr (100 * $hp_remaining)/$maxhp] $client_blur $server_blur]
						if {$nonlethal != 0 && $maxhp != $lethal} {
							append tiptext [format " (%d%% of remaining hp non-lethal)" [expr (100*$nonlethal)/$hp_remaining]]
						}
					}
				}
			}
		} else {
			append tiptext " dead."
		}
	}

	if {[info exists MOB(ELEV:$mob_id)] && $MOB(ELEV:$mob_id) != 0} {
		append tiptext [format "; elevation %d ft" $MOB(ELEV:$mob_id)]
	}
	if {[info exists MOB(MOVEMODE:$mob_id)] && $MOB(MOVEMODE:$mob_id) != {}} {
		switch -exact -- $MOB(MOVEMODE:$mob_id) {
			land {
			}
			fly - climb - burrow {
				append tiptext [format " (%sing)" $MOB(MOVEMODE:$mob_id)]
			}
			swim {
				append tiptext " (swimming)"
			}
			default {
				append tiptext [format " (%s)" $MOB(MOVEMODE:$mob_id)]
			}
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

proc DisplayHealthStats {mob_id} {
	global MOB
	global ClockDisplay
	global DHS_Saved_ClockDisplay

	if {$mob_id ne {}} {
		if {[string range $ClockDisplay 0 1] ne {::}} {
			set DHS_Saved_ClockDisplay $ClockDisplay
		}

		if {[info exists MOB(HEALTH:$mob_id)]} {
			set h $MOB(HEALTH:$mob_id)
		} else {
			set h {}
		}

		if {$MOB(KILLED:$mob_id)} {
			set health "DEAD"
			set dead 1
		} else {
			set health {}
			set dead 0
		}

		if {[info exists MOB(STATUSLIST:$mob_id)] && $MOB(STATUSLIST:$mob_id) ne {}} {
			append health " :: " $MOB(STATUSLIST:$mob_id)
		}

		if {[llength $h] < 7} {
			set ClockDisplay [format ":: %s %s" $MOB(NAME:$mob_id) $health]
		} else {
			DistributeVars $h maxhp lethal nonlethal grace flatp stablep condition server_blur_hp
			global blur_all blur_pct
			set client_blur {}
			set server_blur {}
			if {$blur_all || $MOB(TYPE:$mob_id) ne {player}} {
				set hp_remaining [blur_hp $maxhp $lethal]
				if {$blur_pct > 0} {
					set client_blur [format "(to %d%%)" $blur_pct]
				}
			} else {
				set hp_remaining [expr $maxhp - $lethal]
			}

			if {$server_blur_hp ne {} && $server_blur_hp > 0} {
				set server_blur [format "(to %d%%)" $server_blur_hp]
			}

			if {!$dead} {
				if {$MOB(TYPE:$mob_id) eq {player}} {
					set health [format "%d/%d HP %s %s" $hp_remaining $maxhp $client_blur $server_blur]
					if {$nonlethal != 0} {
						append health [format " (%d NL)" $nonlethal]
					}
				} else {
					if {$maxhp == 0} {
						set health [format "%d lethal %d non %s %s" $lethal $nonlethal $client_blur $server_blur]
					} else {
						if {$lethal > $maxhp} {
							set health "DYING"
						} else {
							set health [format "%d%% HP %s %s" [expr (100 * $hp_remaining) / $maxhp] $client_blur $server_blur]
							if {$nonlethal != 0 && $maxhp != $lethal} {
								append health [format " (%d%% NL)" [expr (100 * $nonlethal) / $hp_remaining]]
							}
						}
					}
				}
			}
			if {$flatp} {
				append health " Flat-footed"
			}
			if {$stablep} {
				append health " Stabilized"
			}
			if {[info exists MOB(_CONDITION:$mob_id)] && $MOB(_CONDITION:$mob_id) ne {}} {
				append health " \[$MOB(_CONDITION:$mob_id)\]"
			}
			if {[info exists MOB(ELEV:$mob_id)] && $MOB(ELEV:$mob_id) != 0} {
				append health [format " Elev %d'" $MOB(ELEV:$mob_id)]
			}
			if {[info exists MOB(MOVEMODE:$mob_id)] && $MOB(MOVEMODE:$mob_id) ne {}} {
				append health [format " (%s)" $MOB(MOVEMODE:$mob_id)]
			}
			if {[info exists MOB(STATUSLIST:$mob_id)] && $MOB(STATUSLIST:$mob_id) ne {}} {
				append health " :: " $MOB(STATUSLIST:$mob_id)
			}
			set ClockDisplay ":: $MOB(NAME:$mob_id) $health"
		}
	} else {
		set ClockDisplay $DHS_Saved_ClockDisplay
		set DHS_Saved_ClockDisplay {}
	}
}

proc setCombatMode {mode} {
	global MOB_COMBATMODE MOB_BLINK ClockDisplay
	
	set MOB_COMBATMODE $mode
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
#
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
proc mergeElement {vid vtag value} {
#OLD CODE---TRANSLATE FILE'S INTEGERS TO OUR OWN SEQUENCE
#
#	global OBJ OBJ_NEXT_ID OBJ_XL
#
#	if {![info exists OBJ_XL($vid)]} {
#		# new object ID, set up translation
#		set OBJ_XL($vid) [incr OBJ_NEXT_ID]
#		#puts "\[DEBUG\] obj xl $vid => $OBJ_NEXT_ID"
#	}
#	set id $OBJ_XL($vid)
#	set OBJ(${vtag}:$id) $value
#	#puts "\[DEBUG\] /${vtag}/ /$id/  <- /$value/"
#
#NEW CODE---USE UUID FOR OBJECTS, GENERATING THEM IF NECESSARY
#
	global OBJ OBJ_XL OBJ_NEXT_Z
	if {[string length $vid] == 32} {
		# already a UUID (naive but probably adequate assumption), just keep it
		# (also assumes they have a Z coordinate and all that good stuff already)
		set id $vid
	} else {
		# translate vid -> new UUID
		if {![info exists OBJ_XL($vid)]} {
			set id [new_id]
			set OBJ_XL($vid) $id
			# add Z coordinate (will be overridden if object has its own)
			set OBJ(Z:$id) [incr OBJ_NEXT_ID]
		} else {
			set id $OBJ_XL($vid)
		}
	}
	set OBJ(${vtag}:$id) $value
	if {$vtag eq "Z" && $value > $OBJ_NEXT_Z} {
		set OBJ_NEXT_Z $value
	}
	return $id
}

proc mergePerson {vid vtag value} {
	global MOB 
	global PC_IDs

	set id $vid
	if {$vtag eq "NAME"} {
		#
		# Detect player with ID not matching our static list
		#
		set value [AcceptCreatureImageName $value]
		if {[info exists PC_IDs($value)] && $PC_IDs($value) ne $id} {
			DEBUG 0 "Conflict with ID of merged PC $value ($id should be $PC_IDs($value); RECOMMEND CORRECTING DATA AND RELOADING."
		}
		set MOB(ID:$value) $id
		DEBUG 4 "----> set MOB(ID:$value) $id"
	}
	set MOB(${vtag}:$id) $value
	DEBUG 4 "----> set MOB(${vtag}:$id) $value"
	return $id
}

proc garbageCollectGrid {} {
	global OBJ

	foreach key [array names OBJ] {
		if {![regexp {^[_A-Z]+:([0-9a-fA-F_#]+)$} $key xx id]} {
			unset OBJ($key)
			DEBUG 2 "\[GC\] REMOVED BOGUS KEY /$key/ from object list (invalid key)"
			continue
		}
		if {![info exists OBJ(TYPE:$id)]} {
			unset OBJ($key)
			DEBUG 2 "\[GC\] REMOVED EXTRA KEY /$key/ from object list (undefined object)"
			continue
		}
	}
}

#
# To support Store-and-Forward mode, saf_loadfile
# ensures that the server has the most up-to-date version
# of <file> and that we can download a copy of it to
# our cache.
#
# interacts with the user and returns true if successful
proc map_modtime {filename desc} {
	if [catch {set f [open $filename]} err] {
		tk_messageBox -type ok -icon error -title "Error opening file"\
			-message "Unable to open $desc: $err" -parent .
		return -1
	}

	set cache_mtime 0
	if {[gets $f v] >= 0} {
		if {[regexp {^__MAPPER__:([0-9]+)$} [lindex $v 0] vv vid]} {
			if [catch {
				if {$vid >= 12 && [llength $v] > 1 && [llength [lindex $v 1]] > 1} {
					set cache_mtime [lindex [lindex [lindex $v 1] 1] 0]
				} 
			} err] {
				DEBUG 0 "Can't read modification time from $desc: $err"
				set cache_mtime 0
			}
		}
	}
	close $f
	return $cache_mtime
}

proc saf_loadfile {file oldcd args} {
	global ClockDisplay

	set server_id [cache_map_id $file]
	if {$args ne {-nocheck}} {
		if [catch {set cache_filename [fetch_map_file $server_id]} err] {
			DEBUG 1 "saf_loadfile: fetch_map_file $server_id failed: $err"
			if {$err eq {NOSUCH}} {
				# not on server yet
				set ClockDisplay "$file not yet on server. Sending..."
				update
				if [catch {send_file_to_server $server_id $file} err] {
					tk_messageBox -type ok -icon error -title "Error sending file"\
						-message "Unable to send $file to server: $err" -parent .
					set ClockDisplay $oldcd
					return 0
				}
				if [catch {set cache_filename [fetch_map_file $server_id]} err] {
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
				-message "Can't get server-side file's timestamp from metadata; sending new copy over to be safe."
		}
	} else {
		set cache_mtime 0	; # force send if we're unconditionally sending anyway
	}
	set source_mtime [map_modtime $file "source copy of $file"]
	if {$cache_mtime < $source_mtime} {
		set ClockDisplay "Sending new copy to server..."
		DEBUG 1 "Cached file $cache_mtime, source $source_mtime"
		update
		if [catch {send_file_to_server $server_id $file} err] {
			tk_messageBox -type ok -icon error -title "Error sending file"\
				-message "Unable to send $file to server: $err" -parent .
			set ClockDisplay $oldcd
			return 0
		}
		if [catch {set cache_filename [fetch_map_file $server_id]} err] {
			tk_messageBox -type ok -icon error -title "Error sending file"\
				-message "Uploaded $file but still can't get it from the server: $err" -parent .
			set ClockDisplay $oldcd
			return 0
		}
	}
	return 1
}

#
# new file format:
# field:id value
#
# monsters now saved; format for them is:
# M field:id value
#
# players, too:
# P field:id value
#

proc loadfile {merge file args} {
####	global OBJ OBJ_NEXT_ID OBJ_FILE OBJ_MODIFIED OBJ_XL MOB_XL
	global OBJ OBJ_FILE OBJ_MODIFIED OBJ_XL ClockDisplay LastFileComment
	set no_send [expr {$args} eq {{-nosend}}]
	
	if {$OBJ_MODIFIED && !$merge && !$no_send
	&& [tk_messageBox -type yesno -default no -icon warning -title "Abandon changes to $OBJ_FILE?"\
		-message "You have unsaved changes to this map.  Do you want to abandon them and load a new map anyway?"]\
		ne "yes"} {
		return

	}

	global okToLoadMonsters okToLoadPlayers
	if {$no_send} {
		set okToLoadMonsters yes
		set okToLoadPlayers yes
	} else {
		set okToLoadPlayers ?
		set okToLoadMonsters ?
	}

	if {$file eq {}} {
		if {[set file [tk_getOpenFile -defaultextension .map -filetypes {
			{{GMA Mapper Files} {.map}}
			{{All Files}        *}
		} -parent . -title "Load current map from..."]] eq {}} return
	}

	set oldcd $ClockDisplay

	#
	# Store-and-Forward Mode:
	#  (1) Ensure we have a cached version from the server
	#  (2) If we don't, or it's older than the local one, upload the local file to the server and try again
	#  (3) Send CLR unless merging then M@ to peers
	#  (4) Proceed to load the local file
	#
	global SafMode
	if {$SafMode} {
		if {![saf_loadfile $file $oldcd]} {
			return
		}
		# Now the server has an updated version of our file and we confirmed we can
		# download it.
		# Tell the others
		if {!$merge} {
			ITsend [list CLR *]
		}
		if {!$no_send} {
			ITsend [list M@ [cache_map_id $file]]
		}
		set ClockDisplay $oldcd
	}

	while {[catch {
        set f [open $file r]
        set f_size [file size $file]
    } err]} {
		if {[tk_messageBox -type retrycancel -icon error -default cancel -title "Error opening file"\
			-message "Unable to open $file: $err" -parent .] eq "cancel"} {
				return
		}
	}

	#resetZoom

	if {!$merge} {
		cleargrid
		#set OBJ_NEXT_Z 0
	}

	#
	# Read first line for metadata
	#
#	set totalElements 0
#	set totalPlayers  0
#	set totalMonsters 0
#	set totalFiles    0
#	set totalImages   0
#	set loadedElements 0
#	set loadedPlayers  0
#	set loadedMonsters 0
#	set loadedFiles    0
#	set loadedImages   0
	set meta_timestamp  {}
	set LastFileComment {}

	if {[gets $f v] >= 0} {
		if {[regexp {^__MAPPER__:([0-9]+)$} [lindex $v 0] vv vid]} {
			global FileVersion		
			if {$vid > $FileVersion} {
				tk_messageBox -type ok -icon error -title "Unsupported file format"\
					-message "Map file $file is a version $vid format file. You need to upgrade your mapper client to read this file." -parent .
				return
			}
			if {$FileVersion >= 12} {
				if {[llength $v] != 2 || [llength [lindex $v 1]] < 2} {
					tk_messageBox -type ok -icon error -title "Invalid file"\
						-message "Map file $file is a version $vid format file, but the metadata field is incorrect. Not reading this file." -parent .
					return
				}
				DistributeVars [lindex $v 1] LastFileComment meta_timestamp
			}
		} else {
			tk_messageBox -type ok -icon warning -title "Unsupported file format"\
				-message "Map file $file has no metadata. We don't know if we're compatible with it, but we'll try to load it anyway. You should update your map files." -parent .
			seek $f 0 start
		}
	} else {
		tk_messageBox -type ok -icon warning -title "Can't read file"\
			-message "Map file $file can't be read or may be empty." -parent .
		return
	}

#	set totalObjects [expr $totalElements + $totalPlayers + $totalMonsters + $totalFiles + $totalImages]

	# count objects to load
#	set totalObjects 0
#	while {[gets $f v] >= 0} {
#		incr totalObjects
#	}
#	seek $f 0 start
#	set loadedObjects 0
		
	catch {unset OBJ_XL}
#	catch {unset MOB_XL}
#	global okToLoadPlayers okToLoadMonsters
#	set okToLoadPlayers ?
#	set okToLoadMonsters ?
	set ClockDisplay "Loading $LastFileComment..."
	update

	if {!$no_send} {
		StartSendElementSet $merge
        set f_prog [begin_progress * "Loading $LastFileComment..." $f_size -send]
    } else {
        set f_prog [begin_progress * "Loading $LastFileComment..." $f_size]
	}
	while {[gets $f v] >= 0} {
#		incr loadedObjects
#		if {$loadedObjects % 10 == 0} {
#			set ClockDisplay [format "Loading %03d/%03d (%d%%)" $loadedObjects $totalObjects [expr $totalObjects > 0 ? $loadedObjects * 100 / $totalObjects : 0]]
#			update
#		}


# Loading 999/999 obj, 999/999 pc, 999/999 npc, 999/999 img, 999/999 map; 999%
# set ClockDisplay [format "Loading %03d/%03d obj, %02d/%02d pc, %02d/%02d npc, %03d/%03d img, %02d/%02d map; %3d%%" $loadedElements $totalElements $loadedPlayers $totalPlayers $loadedMonsters $totalMonsters $loadedImages $totalImages $loadedFiles $totalFiles [expr ($totalObjects > 0) ? ($loadedElements+$loadedPlayers+$loadedMonsters+$loadedImages+$loadedFiles) * 100 / $totalObjects : 0]]
# update


		if [catch {set LL [llength $v]} err] {
			tk_messageBox -type ok -icon error -title "Error loading file"\
				-message $err -parent .
			if {!$no_send} {
				FinishSendElementSet
                end_progress $f_prog -send
			} else {
                end_progress $f_prog
            }
			set ClockDisplay $oldcd
			return
		}
		if {[string range $v 0 10] eq {__MAPPER__:}} {
			tk_messageBox -type ok -icon error -title "Error loading file"\
				-message "Metadata line must appear first in map file." -parent .
			if {!$no_send} {
				FinishSendElementSet
                end_progress $f_prog -send
			} else {
                end_progress $f_prog
            }
			set ClockDisplay $oldcd
			return
		}
			
		if {$LL == 4 && [lindex $v 0] eq "I"} {
			DistributeVars $v xx image_id image_zoom image_filename
			DEBUG 2 "Defining image $image_id at zoom $image_zoom from $image_filename"
			if {[string range $image_filename 0 0] eq "@"} {
				DEBUG 3 "Image is found on server. Retrieving..."
				set image_filename [string range $image_filename 1 end]
				fetch_image $image_id $image_zoom $image_filename
				global TILE_ID
				set TILE_ID([tile_id $image_id $image_zoom]) $image_filename
				if {!$SafMode && !$no_send} {
					DEBUG 3 "Sending on to other clients..."
					ITsend [list AI@ $image_id $image_zoom $image_filename]
                    update_progress $f_prog [tell $f] * -send
				} else {
                    update_progress $f_prog [tell $f] *
                }
			} else {
				if [catch {set image_file [open $image_filename r]} err] {
					DEBUG 0 "Can't open image file $image_filename for $image_id at zoom $image_zoom: $err"
					continue
				}
				fconfigure $image_file -encoding binary -translation binary 
				if [catch {set image_data [read $image_file]} err] {
					DEBUG 0 "Can't read data from image file $image_filename: $err"
					close $image_file
					continue
				}
				close $image_file
				global TILE_SET
				if [info exists TILE_SET([tile_id $image_id $image_zoom])] {
					DEBUG 1 "Replacing existing image $TILE_SET([tile_id $image_id $image_zoom]) for ${image_id} x$image_zoom"
					image delete $TILE_SET([tile_id $image_id $image_zoom])
					unset TILE_SET([tile_id $image_id $image_zoom])
				}
				if [catch {set TILE_SET([tile_id $image_id $image_zoom]) [image create photo -format gif -data $image_data]} err] {
					DEBUG 0 "Can't use data read from image file $image_filename: $err"
					continue
				}
				DEBUG 3 "Created image $TILE_SET([tile_id $image_id $image_zoom]) for $image_id, zoom $image_zoom len=[string length $image_data]"
				#
				# Looks like the image is valid.  Send it to everyone else too...
				#
				if {!$SafMode && !$no_send} {
					set encoded_image [base64::encode -maxlen 1024 $image_data]
					set image_cs [cs_init]
					cs_update $image_cs $image_data
					set image_chk [cs_final $image_cs]
					ITsend [list AI $image_id $image_zoom]
					foreach image_line $encoded_image {
						ITsend [list AI: $image_line]
					}
					ITsend [list AI. [llength $encoded_image] $image_chk]
				}
			}
			continue
		}
		if {$LL == 2 && [lindex $v 0] eq "F"} {
			set map_id [lindex $v 1]
			DEBUG 2 "Defining map file $map_id"
			if [catch {
				set cache_filename [fetch_map_file $map_id]
				DEBUG 1 "Pre-load: map ID $map_id cached as $cache_filename"
			} err] {
				if {$err eq {NOSUCH}} {
					DEBUG 0 "We were asked to pre-load map file with ID $map_id but the server doesn't have it"
				} else {
					say "Error retrieving map ID $map_id from server: $err"
				}
			}
			if {!$no_send} {
				ITsend [list M? $map_id]
                update_progress $f_prog [tell $f] * -send
			} else {
                update_progress $f_prog [tell $f] *
            }
			continue
		}

		if {!$no_send} {
			ContinueSendElementSet $v
            update_progress $f_prog [tell $f] * -send
		} else {
            update_progress $f_prog [tell $f] *
        }
		if [catch {loadElement $v} err] {
			catch { cleargrid }
			catch { unset OBJ }
			#set OBJ_NEXT_Z 0
			close $f
			tk_messageBox -type ok -icon error -title "Error loading file"\
				-message $err -parent .
			if {!$no_send} {
				FinishSendElementSet
                end_progress $f_prog -send
			} else {
                end_progress $f_prog
            }
			set ClockDisplay $oldcd
			return
		}
	}
	close $f
	if {!$no_send} {
		FinishSendElementSet
        end_progress $f_prog -send
	} else {
        end_progress $f_prog
    }
	garbageCollectGrid
	RefreshGrid 0
	RefreshMOBs
	modifiedflag $file 0
	set ClockDisplay $oldcd
	update
}

proc unloadfile {file args} {
####	global OBJ OBJ_NEXT_ID OBJ_FILE OBJ_MODIFIED OBJ_XL MOB_XL
	global OBJ OBJ_FILE OBJ_MODIFIED OBJ_XL SafMode ClockDisplay
	set no_send [expr {$args} eq {{-nosend}}]

	if {$file eq {}} {
		if {[set file [tk_getOpenFile -defaultextension .map -filetypes {
			{{GMA Mapper Files} {.map}}
			{{All Files}        *}
		} -parent . -title "Delete elements from..."]] eq {}} return
	}

    #
    # If we're being told remotely to do this, don't prompt the user
    # 
    if {!$no_send} {
        if {[tk_messageBox -type yesno -default no -icon warning -title "Remove Elements?"\
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
		if {!$no_send} {
			ITsend [list CLR@ [cache_map_id $file]]
		}
		set ClockDisplay $oldcd
	}

	while {[catch {set f [open $file r]} err]} {
		if {[tk_messageBox -type retrycancel -icon error -default cancel -title "Error opening file"\
			-message "Unable to open $file: $err" -parent .] eq "cancel"} {
				return
		}
	}

	while {[gets $f v] >= 0} {
		if [regexp {^TYPE:([0-9a-zA-Z_#]+)} [lindex $v 0] vv vid] {
			DEBUG 2 "Removing $file element $vid"
			if {$SafMode || $no_send} {
				KillObjById $vid -nosend
			} else {
				KillObjById $vid
			}
		}
	}
	close $f
	garbageCollectGrid
	RefreshGrid 0
}


proc loadElement {args} {
	global okToLoadMonsters okToLoadPlayers
	global OBJ OBJ_NEXT_Z FLASH_OBJ_LIST FLASH_MOB_LIST
	set flashmode 0

	# usage: loadElement ?-flash? data
	if {[lindex $args 0] eq "-flash"} {
		set v [lindex $args 1]
		set flashmode 1
	} else {
		set v [lindex $args 0]
	}

	#
	# Ensure that lines are all 2-element TCL lists of the
	# form "<tag> <value>", where <tag> is "<LETTERS>:<digits>"
	# 
	# or 3-elements TCL lists with M or P as first element
	#
	set err "Syntax error in map file"
	if {[catch {set L [llength $v]} err]} {
		error "Format error in file line \"$v\": $err"
	}


	if {$L == 3} {
		# new format player or monster 
		if {[lindex $v 0] eq "M"} {
			if {$okToLoadMonsters eq "?"} {
				set okToLoadMonsters [tk_messageBox -type yesno -icon question -title "File contains monsters"\
					-message "Do you wish to load the monsters from this file as well?" -parent .\
					-default yes]
			}
			if {$okToLoadMonsters ne "yes"} {
				return
			}
		} elseif {[lindex $v 0] eq "P"} {
			if {$okToLoadPlayers eq "?"} {
				set okToLoadPlayers [tk_messageBox -type yesno -icon question -title "File contains players"\
					-message "Do you wish to load the players saved to this file as well?" -parent .\
					-default yes]
			}
			if {$okToLoadPlayers ne "yes"} {
				return
			}
		} else {
			error "Syntax error in line \"$v\" of data file: invalid tag"
		}
		if {![regexp {^([A-Z_]+):([0-9a-zA-Z_#]+)$} [lindex $v 1] vv vtag vid]
		|| [catch {set vid [mergePerson $vid $vtag [lindex $v 2]]} err]} {
			error "Error setting creature map value \"$v\": $err"
		}
		if {$flashmode && $vtag eq "NAME"} {
			lappend FLASH_MOB_LIST $vid
		}
	} else {
		if {$L == 2 && [lindex $v 0] eq {F}} {
			#
			# F id 
			# fetch stored map file
			#
			if [catch fetch_map_file [lindex $v 1] err] {
				if {$err eq {NOSUCH}} {
					DEBUG 0 "Warning: File ID [lindex $v 1] is not available on the server."
				} else {
					DEBUG 0 "Error retrieving file ID [lindex $v 1]: $err"
				}
			}
		} else {
			if { $L != 2
			|| ![regexp {^([A-Z_]+):([0-9a-fA-F_#]+)$} [lindex $v 0] vv vtag vid]
			|| [catch {set vid [mergeElement $vid $vtag [lindex $v 1]]} err]} {
				error "Error setting map value \"$v\": $err"
			}
			if {$flashmode && $vtag eq "X"} {
				lappend FLASH_OBJ_LIST $vid
			}

			#
			# handle backward compatibility with old file formats
			#
			if {[string range $vv 0 3] eq {TYPE}} {
				switch -exact -- [lindex $v 1] {
					line {
						if {![info exists OBJ(ARROW:$vid)]}  {set OBJ(ARROW:$vid) none}
						if {![info exists OBJ(DASH:$vid)]}   {set OBJ(DASH:$vid) {}}
					}
					poly {
						if {![info exists OBJ(JOIN:$vid)]}   {set OBJ(JOIN:$vid) bevel}
						if {![info exists OBJ(SPLINE:$vid)]} {set OBJ(SPLINE:$vid) 0}
						if {![info exists OBJ(DASH:$vid)]}   {set OBJ(DASH:$vid) {}}
					}
					arc {
						if {![info exists OBJ(ARCMODE:$vid)]} {set OBJ(ARCMODE:$vid) pieslice}
						if {![info exists OBJ(START:$vid)]}   {set OBJ(START:$vid) 0}
						if {![info exists OBJ(EXTENT:$vid)]}  {set OBJ(EXTENT:$vid) 359}
						if {![info exists OBJ(DASH:$vid)]}   {set OBJ(DASH:$vid) {}}
					}
					rect -
					circ {
						if {![info exists OBJ(DASH:$vid)]}   {set OBJ(DASH:$vid) {}}
					}
				}
			}
		}
	}
}



proc savefile {} {
	global OBJ OBJ_FILE MOB FileVersion LastFileComment 

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

	set lock_objects [tk_messageBox -type yesno -icon question -title {Lock objects?} -message {Do you wish to lock all map objects in this file?} -detail {When locked, map objects cannot be further modified by clients. This helps avoid accidentally disturbing the map background while people are interacting with the map during a game.} -default yes]

	::getstring::tk_getString .meta_comment LastFileComment {Map Name/Comment:}
	set now [clock seconds]
	puts $f [list "__MAPPER__:$FileVersion" [list $LastFileComment [list $now [clock format $now]]]]
	
	#
	# take care to preserve object ordering
	# XXX not really important now with Z coordinates
	#
	set objectlist {}
	foreach obj [array names OBJ X:*] {
		lappend objectlist [string range $obj 2 end]
	}
	foreach obj [lsort $objectlist] {
		if {$lock_objects eq yes} {
			puts $f [list LOCKED:$obj 1]
		}
		foreach key [array names OBJ *:$obj] {
			puts $f [list $key $OBJ($key)]
		}
	}

	#
	# save the player positions, if any
	#
	set objectlist {}
	foreach obj [array names MOB NAME:*] {
		lappend objectlist [string range $obj 5 end]
	}
	global MOB_IMAGE
	foreach obj [lsort $objectlist] {
		foreach key [array names MOB *:$obj] {
			if {[string range $key 0 4] eq "NAME:" && [info exists MOB_IMAGE($MOB($key))]} {
				set save_value "$MOB_IMAGE($MOB($key))=$MOB($key)"
			} else {
				set save_value $MOB($key)
			}

			if {[string range $key 0 0] eq {_}} {
				DEBUG 3 "(skipping attribute $key)"
			} elseif {$MOB(TYPE:$obj) eq "player"} {
				puts $f [list P $key $save_value]
			} else {
				puts $f [list M $key $save_value]
			}
		}
	}

	#foreach {key value} [array get OBJ] {
	#	puts $f [list $key $value]
	#}
	close $f
	modifiedflag $file 0
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

	if {$ModuleID ne {}} {
		set tag "\[$ModuleID\] "
	} else {
		set tag {}
	}

	if {$OBJ_MODIFIED} {
		wm title . "${tag}Mapper: $OBJ_FILE (*) $TX_QUEUE_STATUS"
	} else {
		wm title . "${tag}Mapper: $OBJ_FILE $TX_QUEUE_STATUS"
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
	global OBJ canvas animatePlacement
	$canvas delete obj$id

	if $animatePlacement update
#	foreach key {TYPE X Y Z LEVEL GROUP HIDDEN POINTS FILL LINE LAYER WIDTH JOIN SPLINE ARCMODE START EXTENT} {
#		catch { unset OBJ(${key}:$id) }
#	}
	foreach key [array name OBJ *:$id] {
		catch { unset OBJ($key) }
	}
}

proc cleargrid {} {
	global OBJ canvas

	foreach obj [array names OBJ X:*] {
		set id [string range $obj 2 end]
		RemoveObject $id
	}
	modifiedflag "untitled" 0
}

proc zoomInBy factor {
	global zoom
	global iscale
	global rscale
	global canvas

	set oldx   [lindex [$canvas xview] 0]
	set oldy   [lindex [$canvas yview] 0]
	set zoom   [expr $zoom * $factor]
	set rscale [expr $rscale * $factor]
	set iscale [expr int($rscale)]
	refreshScreen
	$canvas xview moveto [expr $oldx * $factor]
	$canvas yview moveto [expr $oldy * $factor]
}

proc resetZoom {} {
	global zoom
	global rscale
	global canvas
	if {$zoom != 1} {
		set oldx   [lindex [$canvas xview] 0]
		set oldy   [lindex [$canvas yview] 0]
		set factor [expr 50.0 / $rscale]
		set zoom 1.0
		set rscale 50.0
		zoomInBy 1
		$canvas xview moveto [expr $oldx * $factor]
		$canvas yview moveto [expr $oldy * $factor]
	}
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

proc gridsnap {} {
	global OBJ_SNAP

	set OBJ_SNAP [expr ($OBJ_SNAP + 1) % 5]
	global icon_snap_$OBJ_SNAP
	.toolbar.snap configure -image [set icon_snap_$OBJ_SNAP]
}

proc setwidth {} {
	global OBJ_WIDTH

	set OBJ_WIDTH [expr ($OBJ_WIDTH+1)%10]
	global icon_width_$OBJ_WIDTH
	.toolbar.width configure -image [set icon_width_$OBJ_WIDTH]
}

proc playtool {} {
	canceltool
	.toolbar.nil configure -relief sunken
}

proc canceltool {} {
	global OBJ_MODE canvas OBJ_BLINK icon_blank
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
	set OBJ_MODE nil
	bind $canvas <Control-ButtonPress-4> {zoomInBy 2}
	bind $canvas <Control-ButtonPress-5> {zoomInBy 0.5}
    bind $canvas <Control-MouseWheel> {zoomInBy [expr {%D>0 ? 2 : 0.5}]}
	bind $canvas <1> "MOB_StartDrag $canvas %x %y"
	bind $canvas <Control-1> "MOB_SelectEvent $canvas %x %y"
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
proc aoeboundtool {} {
	global OBJ canvas OBJ_MODE JOINSTYLE SPLINE
	global icon_join_bevel icon_spline_0
	canceltool
	bind $canvas <1> "StartObj $canvas %x %y"
	bind $canvas <Motion> "ObjDrag $canvas %x %y"
	bind $canvas <B1-Motion> "ObjDrag $canvas %x %y"
	bind $canvas <B1-ButtonRelease> {}
	.toolbar.aoebound configure -relief sunken
	$canvas configure -cursor rtl_logo
	set OBJ_MODE aoebound
	.toolbar.mode configure -image $icon_join_bevel -command toggleJoinStyle
	.toolbar.mode2 configure -image $icon_spline_0 -command toggleSpline
	::tooltip::tooltip .toolbar.mode {Cycle join style}
	::tooltip::tooltip .toolbar.mode2 {Cycle spline level}
	set JOINSTYLE bevel
	set SPLINE 0
}

proc aoetool {} {
	global OBJ canvas OBJ_MODE AOE_SHAPE AOE_SPREAD
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
	set OBJ_MODE aoe
	set AOE_SHAPE radius
	set AOE_SPREAD 0
}

proc rulertool {} {
	global OBJ canvas OBJ_MODE
	canceltool
	bind $canvas <1> "StartObj $canvas %x %y"
	bind $canvas <Motion> "ObjDrag $canvas %x %y"
	bind $canvas <B1-Motion> "ObjDrag $canvas %x %y"
	bind $canvas <B1-ButtonRelease> {}
	.toolbar.ruler configure -relief sunken
	$canvas configure -cursor crosshair
	set OBJ_MODE ruler
}

proc linetool {} {
	global OBJ canvas OBJ_MODE ARROWSTYLE DASHSTYLE icon_arrow_none icon_dash0
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
	set OBJ_MODE line
}

proc polytool {} {
	global OBJ canvas OBJ_MODE JOINSTYLE SPLINE
	global icon_join_bevel icon_spline_0 icon_dash0 DASHSTYLE
	canceltool
	bind $canvas <1> "StartObj $canvas %x %y"
	bind $canvas <Motion> "ObjDrag $canvas %x %y"
	bind $canvas <B1-Motion> "ObjDrag $canvas %x %y"
	bind $canvas <B1-ButtonRelease> {}
	.toolbar.poly configure -relief sunken
	$canvas configure -cursor rtl_logo
	set OBJ_MODE poly
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
	set OBJ_MODE text
	DEBUG 3 "Selected text mode"
	set ClockDisplay $CurrentTextString
	catch {tk fontchooser configure -font [lindex $CURRENT_FONT 0] -command [list SelectFont $canvas]}
	bind . <<TkFontchooserFontChanged>> [list SelectFont $canvas]
}

proc SelectText {x y} {
	global ClockDisplay CurrentTextString 
	global _newtextstring
	set _newtextstring {}
	if {[::getstring::tk_getString .textstring _newtextstring {Text string to place:}]} {
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
	set OBJ_MODE tile
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
	if {[::getstring::tk_getString .tilename _newtilename {Tile base name:}]} {
		set CurrentStampTile [list [FindImage $_newtilename $zoom] $_newtilename $zoom]
		set ClockDisplay $CurrentStampTile
	}
}



#	while 1 {
#		if {[set file [tk_getOpenFile -defaultextension .gif -filetypes {
#			{{GIF Image Files} {.gif}}
#			{{All Files}            *}
#		} -parent . -title "Load tile image from..."]] eq {}} {
#			DEBUG 3 "No tile file selected; abandoned operation"
#			return
#		}
#
#		if [regexp {^(.*)/(.*?)@(\d+)\.gif$} $file x dirpath tilename tilepx] {
#			DEBUG 3 "Tile is $tilename at $tilepx pixels, in dir $dirpath"
#			break
#		} else {
#			if {[tk_messageBox -type retrycancel -icon error -default cancel -title "Error in tile filename"\
#				-message "Unable to understand filename $file: Expecting <name>@<size>.gif pattern"\
#				-parent .] eq "cancel"} {
#				return
#			}
#		}
#	}
#
#	#
#	# Load up all the sizes of this image that we can find
#	# We take the filename as specified, which we assume to be
#	# the default zoom level; then we try scaling up and down
#	# until we can't find a file defined at that size.
#	#
#	LoadTile $dirpath $tilename $tilepx
#}

proc PlaceTile {canvas x y} {
	DEBUG 0 "PlaceTile not implemented"
}

#proc LoadTile {dirpath tilename tilepx} {
#	global TILE_SET
#	foreach zoom {1.0 2.0 4.0 0.5 0.25} {
#		set tilepath [file join $dirpath "$tilename@[expr int($zoom * $tilepx)].gif"]
#		if {[catch {set f [open $tilepath r]} err]} {
#			DEBUG 0 "Error loading tile from $tilepath: $err"
#		} else {
#			DEBUG 3 "Loading tile image for $tilename, zoom factor $zoom from $tilepath"
#			close $f
#			set TILE_SET([tile_id $tilename $zoom]) [image create photo -format gif -file $tilepath]
#			DEBUG 3 "def $tilename:$zoom = $TILE_SET([tile_id $tilename $zoom])"
#		}
#	}
#}


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
	global OBJ canvas OBJ_MODE 
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
	set OBJ_MODE rect
}

proc circtool {} {
	global OBJ canvas OBJ_MODE
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
	set OBJ_MODE circ
	set DASHSTYLE {}
}

proc arctool {} {
	global OBJ canvas OBJ_MODE ARCMODE icon_arc_pieslice
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
	set OBJ_MODE arc
	.toolbar.mode configure -image $icon_arc_pieslice -command toggleArcMode
	::tooltip::tooltip .toolbar.mode {Cycle arc style}
	set ARCMODE pieslice
	set DASHSTYLE {}
}

proc toggleArcMode {} {
	global OBJ OBJ_CURRENT ARCMODE icon_arc_arc icon_arc_pieslice icon_arc_chord

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
	set OBJ_MODE kill
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
	bind . <Key-h> "NudgeObject $canvas -1 0"
	bind . <Key-l> "NudgeObject $canvas 1 0"
	bind . <Key-k> "NudgeObject $canvas 0 -1"
	bind . <Key-j> "NudgeObject $canvas 0 1"
	bind . <Key-Left> "NudgeObject $canvas -1 0"
	bind . <Key-Right> "NudgeObject $canvas 1 0"
	bind . <Key-Up> "NudgeObject $canvas 0 -1"
	bind . <Key-Down> "NudgeObject $canvas 0 1"
	bind $canvas <Motion> {}
	$canvas configure -cursor fleur
	.toolbar.move configure -relief sunken
	set OBJ_MODE move
	DEBUG 3 "Selected move mode"
}

set OBJ_CURRENT 0
set CURRENT_TEXT_WIDGET {}
set CURRENT_FONT {TkDefaultFont}
set ARCMODE pieslice

proc cmp_obj_attr {a b} {
	global OBJ
	set z [expr $OBJ($a) - $OBJ($b)]
	if $z {
		return $z
	}
	return [string compare $a $b]
}

#
# Compare elements of OBJ based on the values of these attributes
# passed but giving precedence to image tiles
#
proc cmp_obj_attr_img {a b} {
	global OBJ
#	# this is a shortcut which assumes a 2-character prefix like Z:
#	# on the attribute, but avoids a slower function to derive the object
#	# ID
#	set at $OBJ(TYPE:[string range $a 2 end])
#	set bt $OBJ(TYPE:[string range $b 2 end])
#	if {$at ne $bt} {
#		if {$at eq {tile}} {
#			return -1
#		} elseif {$bt eq {tile}} {
#			return 1
#		}
#	}
	set z [expr $OBJ($a) - $OBJ($b)]
	if $z {
		return $z
	}
	# fall back to ID order if at same Z level
	return [string compare $a $b]
}

#
# Compare MOB IDs and sort them first as {dead, monster, player}, then in ID order 
# sort keys are ID:<name>. The monster ID is at $OBJ(ID:<name>).
#
proc major_mob_sort {id} {
	global MOB

	if {$MOB(KILLED:$id)} {return 0}
	if {$MOB(TYPE:$id) eq "monster"} {return 1}
	return 2
}

proc cmp_mob_living {a b} {
	global MOB
	set id_a $MOB($a)
	set id_b $MOB($b)
	set ord_a [major_mob_sort $id_a]
	set ord_b [major_mob_sort $id_b]

	DEBUG 4 "cmp_mob_living $a $b: id_a=$id_a id_b=$id_b ord_a=$ord_a ord_b=$ord_b"
	if {$ord_a == $ord_b} {
		DEBUG 4 "-> [string compare $id_a $id_b] (minor sort)"
		return [string compare $id_a $id_b]
	}
	DEBUG 4 "-> [expr $ord_a - $ord_b] (major sort)"
	return [expr $ord_a - $ord_b]
}


proc RefreshGrid {show} {
	global canvas OBJ ARCMODE SPLINE zoom animatePlacement
	global AoeZoneLast
	set AoeZoneLast {}
	#
	# draw in Z coordinate order within 2 groups: image tiles, everything else,
	# with the grid sitting on top
	#
	set display_list [lsort -integer -command cmp_obj_attr_img [array names OBJ Z:*]]
	foreach Zid $display_list {
		set id [string range $Zid 2 end]
	    if [catch {
		if {[info exists OBJ(X:$id)]} {
			$canvas delete obj$id
			if $animatePlacement update
			#DEBUG 3 "rendering object $id $OBJ(TYPE:$id)"
			foreach var {POINTS X Y} {
				catch {unset $var}
				if {[info exists OBJ($var:$id)]} {
					if {$zoom != 1} {
						foreach x $OBJ($var:$id) {
							lappend $var [expr $x * $zoom]
							#DEBUG 3 "scale x$zoom: $var $id $x->[set $var]"
						}
					} else {
						set $var $OBJ($var:$id)
						#DEBUG 3 "no scale: $var $id $OBJ($var:$id)->[set $var]"
					}
				}
			}
				
			switch $OBJ(TYPE:$id) {
				poly {
					$canvas create polygon "$X $Y $POINTS"\
						-fill $OBJ(FILL:$id) -outline $OBJ(LINE:$id) -width $OBJ(WIDTH:$id) -tags [list obj$id allOBJ]\
						-joinstyle $OBJ(JOIN:$id) -smooth [expr $OBJ(SPLINE:$id) != 0] \
						-splinesteps $OBJ(SPLINE:$id) -dash $OBJ(DASH:$id)
				}
				line {
					$canvas create line "$X $Y $POINTS"\
						-fill $OBJ(FILL:$id) -width $OBJ(WIDTH:$id) -tags [list obj$id allOBJ] \
						-dash $OBJ(DASH:$id) -arrow $OBJ(ARROW:$id)
				}
				rect {
					$canvas create rectangle "$X $Y $POINTS"\
						-fill $OBJ(FILL:$id) -outline $OBJ(LINE:$id) -width $OBJ(WIDTH:$id) \
						-dash $OBJ(DASH:$id) -tags [list obj$id allOBJ]
				}
				circ {
					$canvas create oval "$X $Y $POINTS"\
						-fill $OBJ(FILL:$id) -outline $OBJ(LINE:$id) -width $OBJ(WIDTH:$id) \
						-dash $OBJ(DASH:$id) -tags [list obj$id allOBJ]
				}
				arc {
					$canvas create arc "$X $Y $POINTS"\
						-fill $OBJ(FILL:$id) -outline $OBJ(LINE:$id) -style $OBJ(ARCMODE:$id) \
						-start $OBJ(START:$id) -extent $OBJ(EXTENT:$id)\
						-dash $OBJ(DASH:$id) \
						-width $OBJ(WIDTH:$id) -tags [list obj$id allOBJ]
				}
				text {
					$canvas create text $X $Y -fill $OBJ(FILL:$id) -anchor $OBJ(ANCHOR:$id) -font [ScaleFont [lindex $OBJ(FONT:$id) 0] $zoom] -justify left -text $OBJ(TEXT:$id) -tags [list obj$id allOBJ]
				}
				aoe {
					$canvas create line [expr $X-10] $Y [expr $X+10] $Y $X $Y $X [expr $Y-10] $X [expr $Y+10]\
						-fill $OBJ(FILL:$id) -width 3 -tags [list obj$id allOBJ]
					DistributeVars $POINTS tx ty
					$canvas create oval [expr $tx-10] [expr $ty-10] [expr $tx+10] [expr $ty+10] -width 3 -outline $OBJ(FILL:$id) -tags [list obj$id]
					$canvas create line [expr $tx-5] [expr $ty-5] [expr $tx+5] [expr $ty+5] -width 3 -fill $OBJ(FILL:$id) -tags [list obj$id]
					$canvas create line [expr $tx-5] [expr $ty+5] [expr $tx+5] [expr $ty-5] -width 3 -fill $OBJ(FILL:$id) -tags [list obj$id]
					DrawAoeZone $canvas $id "$X $Y $POINTS"
				}
				tile {
					global TILE_SET
					# TYPE tile
					# X,Y  upper left corner
					# IMAGE image ID
					set tile_id [FindImage $OBJ(IMAGE:$id) $zoom]
					if [info exists TILE_SET($tile_id)] {
						$canvas create image $X $Y -anchor nw -image $TILE_SET($tile_id) -tags [list obj$id tiles allOBJ]
					} else {
						DEBUG 1 "Warning: no image $tile_id for $OBJ(IMAGE:$id) @ $zoom available. Looking for it..."
						global TILE_ATTR
						if {[info exists OBJ(_TILEID:$id)]} {
							set bbti $OBJ(_TILEID:$id)
							if {[info exists TILE_ATTR(BBWIDTH:$bbti)] && [info exists TILE_ATTR(BBHEIGHT:$bbti)]} {
								set bbxx [expr $X + $TILE_ATTR(BBWIDTH:$bbti)]
								set bbyy [expr $Y + $TILE_ATTR(BBHEIGHT:$bbti)]
								$canvas create polygon "$X $Y $bbxx $Y $bbxx $bbyy $X $bbyy $X $Y $bbxx $bbyy $X $bbyy $bbxx $Y" \
									-fill {} -outline red -width 5 -tags [list obj$id allOBJ]
								$canvas create text [expr $X + ($TILE_ATTR(BBWIDTH:$bbti)/2)] [expr $Y + ($TILE_ATTR(BBHEIGHT:$bbti)/2)] -fill red -anchor center -text $bbti -tags [list obj$id allOBJ]
							}
						}
					}
				}
				default {
					say "ERROR: weird object $id; type=$OBJ(TYPE:$id)"
				}
			}
			if $show {
				update
			}
		}
	    } err] {
			global OBJ_XL
			set file_id (unknown)
			foreach kk [array names OBJ_XL] {
				if {$OBJ_XL($kk) == $id} {
					set file_id $kk
					break
				}
			}
	        say "ERROR: Unable to render object $id (file obj $file_id): $err"
	    }
	}
	$canvas raise grid
	update
}

#
# update the visual display of an on-screen object to match
# the values in the OBJ array.
#
proc UpdateObjectDisplay {id} {
	global canvas OBJ ARCMODE SPLINE zoom animatePlacement
	if [catch {
		if {[info exists OBJ(X:$id)]} {
			foreach var {POINTS X Y} {
				catch {unset $var}
				if {[info exists OBJ($var:$id)]} {
					if {$zoom != 1} {
						foreach x $OBJ($var:$id) {
							lappend $var [expr $x * $zoom]
						}
					} else {
						set $var $OBJ($var:$id)
					}
				}
			}
				
			switch $OBJ(TYPE:$id) {
				poly {
					$canvas coords obj$id "$X $Y $POINTS"
					$canvas itemconfigure obj$id -fill $OBJ(FILL:$id) -outline $OBJ(LINE:$id) -width $OBJ(WIDTH:$id) \
						-joinstyle $OBJ(JOIN:$id) -smooth [expr $OBJ(SPLINE:$id) != 0] -splinesteps $OBJ(SPLINE:$id)
				}
				line {
					$canvas coords obj$id "$X $Y $POINTS"
					$canvas itemconfigure obj$id -fill $OBJ(FILL:$id) -width $OBJ(WIDTH:$id)
				}
				rect {
					$canvas coords obj$id "$X $Y $POINTS"
					$canvas itemconfigure obj$id -fill $OBJ(FILL:$id) -outline $OBJ(LINE:$id) -width $OBJ(WIDTH:$id)
				}
				circ {
					$canvas coords obj$id "$X $Y $POINTS"
					$canvas itemconfigure obj$id -fill $OBJ(FILL:$id) -outline $OBJ(LINE:$id) -width $OBJ(WIDTH:$id)
				}
				arc {
					$canvas coords obj$id "$X $Y $POINTS"
					$canvas itemconfigure obj$id -fill $OBJ(FILL:$id) -outline $OBJ(LINE:$id) -style $OBJ(ARCMODE:$id) \
						-start $OBJ(START:$id) -extent $OBJ(EXTENT:$id)\
						-width $OBJ(WIDTH:$id)
				}
				text {
					$canvas coords obj$id "$X $Y"
					$canvas itemconfigure obj$id -fill $OBJ(FILL:$id) \
						-font $OBJ(FONT:$id) -anchor $OBJ(ANCHOR:$id) -text $OBJ(TEXT:$id)
				}
				aoe {
					$canvas delete obj$id
					$canvas create line [expr $X-10] $Y [expr $X+10] $Y $X $Y $X [expr $Y-10] $X [expr $Y+10]\
						-fill $OBJ(FILL:$id) -width 3 -tags [list obj$id allOBJ]
					DistributeVars $POINTS tx ty
					$canvas create oval [expr $tx-10] [expr $ty-10] [expr $tx+10] [expr $ty+10] -width 3 -outline $OBJ(FILL:$id) -tags [list obj$id]
					$canvas create line [expr $tx-5] [expr $ty-5] [expr $tx+5] [expr $ty+5] -width 3 -fill $OBJ(FILL:$id) -tags [list obj$id]
					$canvas create line [expr $tx-5] [expr $ty+5] [expr $tx+5] [expr $ty-5] -width 3 -fill $OBJ(FILL:$id) -tags [list obj$id]
					DrawAoeZone $canvas $id "$X $Y $POINTS"
				}
				tile {
					global TILE_SET
					# TYPE tile
					# X,Y  upper left corner
					# IMAGE image ID
					set tile_id [FindImage $OBJ(IMAGE:$id) $zoom]
					if [info exists TILE_SET($tile_id)] {
						$canvas coords obj$id $X $Y
						$canvas itemconfigure obj$id -image $TILE_SET($tile_id)
					} else {
						DEBUG 1 "Warning: no image $tile_id for $OBJ(IMAGE:$id) @ $zoom available. Looking for it..."
						global TILE_ATTR
						if {[info exists OBJ(_TILEID:$id)]} {
							set bbti $OBJ(_TILEID:$id)
							if {[info exists TILE_ATTR(BBWIDTH:$bbti)] && [info exists TILE_ATTR(BBHEIGHT:$bbti)]} {
								set bbxx [expr $X + $TILE_ATTR(BBWIDTH:$bbti)]
								set bbyy [expr $Y + $TILE_ATTR(BBHEIGHT:$bbti)]
								$canvas create polygon "$X $Y $bbxx $Y $bbxx $bbyy $X $bbyy $X $Y $bbxx $bbyy $X $bbyy $bbxx $Y" \
									-fill {} -outline red -width 5 -tags [list obj$id allOBJ]
								$canvas create text [expr $X + ($TILE_ATTR(BBWIDTH:$bbti)/2)] [expr $Y + ($TILE_ATTR(BBHEIGHT:$bbti)/2)] -fill red -anchor center -text $bbti -tags [list obj$id allOBJ]
							}
						}
					}
				}
				default {
					say "ERROR: weird object $id; type=$OBJ(TYPE:$id)"
				}
			}
			update
		}
	    } err] {
			global OBJ_XL
			set file_id (unknown)
			foreach kk [array names OBJ_XL] {
				if {$OBJ_XL($kk) == $id} {
					set file_id $kk
					break
				}
			}
	        say "ERROR: Unable to render object $id (file obj $file_id): $err"
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
		 p  {the conversation, so the message goes to all of them. Selecting "all" will clear the recipient selection. The message is sent when you press Return in the entry field.}}
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
		 p { to, respectively, add, subtract, multiply, or divide the following value from the total so far.}}
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
		{h1 {Presets}}
		{p {}}
		{p {Saving preset rolls to the server allows them to be available any time your client connects to it. Each preset is given a unique name. If another preset is added with the same name, it will replace the previous one.}}
		{p {If a vertical bar (|) appears in the preset name, everything up to and including the bar is not displayed in the tool, but the sort order of the preset display is based on the entire name. This allows you to sort the entries in any arbitrary order without cluttering the display if you wish. This is most convenient if you save your presets to a file, edit them, and load them back again.}}
		{p {The save file for presets is a simple text file. Each line describes a single preset, with 3 space-delimited fields on the line: preset name, description of the preset, and the die roll string. If any spaces are contained in a field, surround that field in curly braces. (Specifically, each line must be a legal 3-element Tcl list string).}}
		{p {Example: } b {Preset1 {This is an example preset.} 1d20+12}}
		{p {Another: } b {{Attack Roll} {a basic attack} {d20+{12/7} + 1 awesome bonus}}}
	} {
		foreach {f t} $line {
			$w.text insert end $t $f
		}
		$w.text insert end "\n"
	}
	# XXX TODO presets
}


proc StartObj {w x y} {
	global OBJ OBJ_CURRENT canvas OBJ_SNAP OBJ_MODE OBJ_COLOR OBJ_WIDTH OBJ_MODIFIED ARCMODE
	global NoFill JOINSTYLE SPLINE DASHSTYLE ARROWSTYLE
	global BUTTON_MIDDLE BUTTON_RIGHT
	global OBJ_NEXT_Z zoom
	global animatePlacement

	modifiedflag - 1
	if {$OBJ_MODE == "aoebound"} {
		set OBJ_CURRENT AOE_GLOBAL_BOUND
		$w delete obj$OBJ_CURRENT
		RemoveObject $OBJ_CURRENT
	} else {
		set OBJ_CURRENT [new_id]
	}
	set OBJ(POINTS:$OBJ_CURRENT) {}
	if {$OBJ_MODE ne "tile"} {
		if $NoFill {
			set OBJ(FILL:$OBJ_CURRENT) {}
		} else {
			set OBJ(FILL:$OBJ_CURRENT) $OBJ_COLOR(fill)
		}
		if {$OBJ_MODE ne "text"} {
			set OBJ(LINE:$OBJ_CURRENT) $OBJ_COLOR(line)
			set OBJ(WIDTH:$OBJ_CURRENT) $OBJ_WIDTH
			set OBJ(DASH:$OBJ_CURRENT) $DASHSTYLE
		}
	}
	set OBJ(LAYER:$OBJ_CURRENT) walls
	bind $canvas $BUTTON_MIDDLE "EndObj $canvas"
	bind . <Key-Escape> "EndObj $canvas"
	set OBJ(TYPE:$OBJ_CURRENT) $OBJ_MODE
	set x [$canvas canvasx $x]
	set y [$canvas canvasy $y]
	set OBJ(Z:$OBJ_CURRENT) [incr OBJ_NEXT_Z]
	switch $OBJ_MODE {
		ruler {
			$canvas create line [SnapCoord $x] [SnapCoord $y] [SnapCoord $x] [SnapCoord $y] -fill $OBJ(FILL:$OBJ_CURRENT) -width 3 -tags [list obj$OBJ_CURRENT allOBJ] -dash -
			bind $canvas <1> "NextPoint $canvas %x %y"
			$canvas create window $x [expr $y - 20] -window $canvas.distanceLabel -tags [list obj_distance$OBJ_CURRENT allOBJ]
		}
		line {
			$canvas create line [SnapCoord $x] [SnapCoord $y] [SnapCoord $x] [SnapCoord $y] -fill $OBJ(FILL:$OBJ_CURRENT) -width $OBJ_WIDTH -tags [list obj$OBJ_CURRENT allOBJ] -dash $DASHSTYLE -arrow $ARROWSTYLE
			bind $canvas <1> "NextPoint $canvas %x %y"
			set OBJ(ARROW:$OBJ_CURRENT) $ARROWSTYLE
		}
		tile {
			global CurrentStampTile TILE_SET
			# If we don't have a current tile, make one try to set it
			if {[llength $CurrentStampTile] == 0} {
				SelectTile $x $y
			}
			# Have one now? stamp it
			if {[llength $CurrentStampTile] > 0} {
				set iid [lindex $CurrentStampTile 0]
				if [info exists TILE_SET($iid)] {
					$canvas create image [SnapCoord $x] [SnapCoord $y] -anchor nw -image $TILE_SET($iid) -tags "tiles obj$OBJ_CURRENT"
				} else {
					say "Unable to load image $CurrentStampTile. Be sure to define and upload it."
					#catch {destroy .stbx}
					#toplevel .stbx -class dialog
					create_dialog .stbx
					wm title .stbx "Image Not Found"
					global STBX_X STBX_Y TILE_ATTR
					set bbti [lindex $CurrentStampTile 0]
					if {[info exists TILE_ATTR(BBWIDTH:$bbti)] && [info exists TILE_ATTR(BBHEIGHT:$bbti)]} {
						set STBX_X $TILE_ATTR(BBWIDTH:$bbti)
						set STBX_Y $TILE_ATTR(BBHEIGHT:$bbti)
					} else {
						set STBX_X 50
						set STBX_Y 50
					}
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
				set OBJ(IMAGE:$OBJ_CURRENT) [lindex $CurrentStampTile 1]
			} else {
				DEBUG 0 "Removing OBJ(*:$OBJ_CURRENT)"
				array unset OBJ *:$OBJ_CURRENT
			}
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
					-fill $OBJ(FILL:$OBJ_CURRENT) \
					-tags "tiles obj$OBJ_CURRENT"
				set CURRENT_TEXT_WIDGET $OBJ_CURRENT
				set OBJ(TEXT:$OBJ_CURRENT) $CurrentTextString
				set OBJ(FONT:$OBJ_CURRENT) $CURRENT_FONT
				set OBJ(ANCHOR:$OBJ_CURRENT) $CurrentAnchor
			} else {
				DEBUG 0 "Removing OBJ(*:$OBJ_CURRENT)"
				array unset OBJ *:$OBJ_CURRENT
			}
		}
		aoebound {
			$canvas create line [SnapCoord $x] [SnapCoord $y] [SnapCoord $x] [SnapCoord $y] -width 3 -fill $OBJ_COLOR(line) -tags [list obj$OBJ_CURRENT allOBJ] -dash -
			bind $canvas <1> "NextPoint $canvas %x %y"
		}
		poly {
			$canvas create polygon [SnapCoord $x] [SnapCoord $y] [SnapCoord $x] [SnapCoord $y] -fill $OBJ(FILL:$OBJ_CURRENT) -width $OBJ_WIDTH -outline $OBJ_COLOR(line) -tags [list obj$OBJ_CURRENT allOBJ] -joinstyle $JOINSTYLE -smooth [expr $SPLINE != 0] -splinesteps $SPLINE -dash $DASHSTYLE
			set OBJ(JOIN:$OBJ_CURRENT) $JOINSTYLE
			set OBJ(SPLINE:$OBJ_CURRENT) $SPLINE
			bind $canvas <1> "NextPoint $canvas %x %y"
		}
		rect {
			$canvas create rectangle [SnapCoord $x] [SnapCoord $y] [SnapCoord $x] [SnapCoord $y] -fill $OBJ(FILL:$OBJ_CURRENT) -outline $OBJ_COLOR(line) -width $OBJ_WIDTH -tags [list obj$OBJ_CURRENT allOBJ] -dash $DASHSTYLE
			bind $canvas <1> "LastPoint $canvas %x %y"
		}
		circ {
			$canvas create oval [SnapCoord $x] [SnapCoord $y] [SnapCoord $x] [SnapCoord $y] -fill $OBJ(FILL:$OBJ_CURRENT) -outline $OBJ_COLOR(line) -width $OBJ_WIDTH -tags [list obj$OBJ_CURRENT allOBJ] -dash $DASHSTYLE
			bind $canvas <1> "LastPoint $canvas %x %y"
		}
		arc  {
			$canvas create arc  [SnapCoord $x] [SnapCoord $y] [SnapCoord $x] [SnapCoord $y] -fill $OBJ(FILL:$OBJ_CURRENT) -outline $OBJ_COLOR(line) -width $OBJ_WIDTH -tags [list obj$OBJ_CURRENT allOBJ] -style $ARCMODE -start 0 -extent 359 -dash $DASHSTYLE
			bind $canvas <1> "LastArcPoint $canvas %x %y"
			set OBJ(ARCMODE:$OBJ_CURRENT) $ARCMODE
		}
		aoe {
			global DistanceLabelText AOE_SHAPE AOE_START

			set a_x [SnapCoordAlways $x]
			set a_y [SnapCoordAlways $y]
			$canvas create line [expr $a_x-10] $a_y [expr $a_x+10] $a_y -fill $OBJ(FILL:$OBJ_CURRENT) -width 4 -tags [list obj$OBJ_CURRENT allOBJ]
			$canvas create line $a_x [expr $a_y-10] $a_x [expr $a_y+10] -fill $OBJ(FILL:$OBJ_CURRENT) -width 4 -tags [list obj$OBJ_CURRENT allOBJ]
			$canvas create line $a_x $a_y $a_x $a_y -dash - -fill $OBJ(FILL:$OBJ_CURRENT) -width 3 -tags [list obj$OBJ_CURRENT obj_locator$OBJ_CURRENT allOBJ] -arrow last
			bind $canvas <1> "LastAoePoint $canvas %x %y"
			set DistanceLabelText {}
			set OBJ(AOESHAPE:$OBJ_CURRENT) $AOE_SHAPE
			switch $AOE_SHAPE {
				radius {
					$canvas create oval $a_x $a_y $a_x $a_y \
						-outline $OBJ_COLOR(line) -width 3 -dash - \
						-tags [list obj$OBJ_CURRENT obj_locator_radius$OBJ_CURRENT allOBJ]
				}
				cone   {
					#$canvas create line $a_x $a_y $a_x $a_y -dash - \
					#	-fill $OBJ_COLOR(line) -width 3 -tags [list obj$OBJ_CURRENT obj_locator_cone1_$OBJ_CURRENT allOBJ]
					#$canvas create line $a_x $a_y $a_x $a_y -dash - \
					#	-fill $OBJ_COLOR(line) -width 3 -tags [list obj$OBJ_CURRENT obj_locator_cone2_$OBJ_CURRENT allOBJ]
					$canvas create arc $a_x $a_y $a_x $a_y -dash - \
						-outline $OBJ_COLOR(line) -width 3 -start 0 -extent 90 \
						-tags [list obj$OBJ_CURRENT obj_locator_cone3_$OBJ_CURRENT allOBJ]
				}
			}
			$canvas create window $a_x [expr $a_y - 20] -window $canvas.distanceLabel -tags [list obj_distance$OBJ_CURRENT allOBJ]
			set AOE_START [list [CanvasToGrid $a_x] [CanvasToGrid $a_y]]
		}
	}

	if {$OBJ_MODE == "aoe"} {
		set OBJ(X:$OBJ_CURRENT) [expr $a_x / $zoom]
		set OBJ(Y:$OBJ_CURRENT) [expr $a_y / $zoom]
		set OBJ(Z:$OBJ_CURRENT) 99999999
	} elseif {$OBJ_MODE == "aoebound"} {
		set OBJ(X:$OBJ_CURRENT) [expr [SnapCoord $x] / $zoom]
		set OBJ(Y:$OBJ_CURRENT) [expr [SnapCoord $y] / $zoom]
		set OBJ(Z:$OBJ_CURRENT) 99999999
	} elseif {$OBJ_MODE == "tile" || $OBJ_MODE == "text"} {
		set OBJ(X:$OBJ_CURRENT) [expr [SnapCoord $x] / $zoom]
		set OBJ(Y:$OBJ_CURRENT) [expr [SnapCoord $y] / $zoom]
		EndObj $canvas
	} else {
		set OBJ(X:$OBJ_CURRENT) [expr [SnapCoord $x] / $zoom]
		set OBJ(Y:$OBJ_CURRENT) [expr [SnapCoord $y] / $zoom]
	}
	$canvas raise grid
	if $animatePlacement update
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
	global OBJ OBJ_CURRENT OBJ_SNAP canvas zoom DistanceLabelText AOE_START

	set xx  [SnapCoordAlways [$canvas canvasx $x]]
	set yy  [SnapCoordAlways [$canvas canvasy $y]]
	set gx  [CanvasToGrid $xx]
	set gy  [CanvasToGrid $yy]

	if {$OBJ_CURRENT != 0} {
		global iscale PI

		set radius_grids [GridDistance [lindex $AOE_START 0] [lindex $AOE_START 1] $gx $gy]
		set radius_feet  [expr $radius_grids * 5]
		set r [expr $radius_grids * $iscale]
		set x0	[expr $OBJ(X:$OBJ_CURRENT) * $zoom]
		set y0	[expr $OBJ(Y:$OBJ_CURRENT) * $zoom]

		$w coords obj_locator$OBJ_CURRENT "$x0 $y0 $xx $yy"
		set DistanceLabelText [format "%d feet" $radius_feet]
		
		switch $OBJ(AOESHAPE:$OBJ_CURRENT) {
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
	global OBJ iscale PI
	
	if {[llength $coords] != 4} {
		say "ERROR: DrawAoeZone coordinates value {$coords} invalid"
		return
	}
	DistributeVars $coords x0 y0 xx yy
	set gx0 [CanvasToGrid $x0]
	set gy0 [CanvasToGrid $y0]
	set gxx [CanvasToGrid $xx]
	set gyy [CanvasToGrid $yy]
	set radius_grids [GridDistance $gx0 $gy0 $gxx $gyy]
	set r [expr $radius_grids * $iscale]

	_DrawAoeZone $w $id $gx0 $gy0 $gxx $gyy $r $OBJ(FILL:$id) $OBJ(AOESHAPE:$id) [list AoEZoneCrossHatch$id obj$id allOBJ]
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
		DistributeVars [split $point ,] c1 r1
		#puts "Looking at neighbors of ($point) (column $c1, row $r1)"
		foreach neighbor [NeighborsOf $c1 $r1] {
			if {![info exists weights($neighbor)]} {
				# we haven't already computed a value for this square, so proceed now...
				DistributeVars [split $neighbor ,] cc rr
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
						DistributeVars [split $npoint ,] nc nr
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

proc ObjDrag {w x y} {
	global OBJ OBJ_CURRENT OBJ_SNAP canvas zoom
	if {$OBJ_CURRENT != 0} {
		set new_coords "[ZoomVector $OBJ(X:$OBJ_CURRENT) $OBJ(Y:$OBJ_CURRENT) $OBJ(POINTS:$OBJ_CURRENT)] [SnapCoord [$canvas canvasx $x]] [SnapCoord [$canvas canvasy $y]]"
		if {[catch {
			$w coords obj$OBJ_CURRENT $new_coords
		} err]} {
			DEBUG 0 "Warning: Updating $OBJ_CURRENT coordinates to $new_coords failed: $err"
		}
		if {$OBJ(TYPE:$OBJ_CURRENT) == "ruler"} {
			global DistanceLabelText
			set d [DistanceAlongRoute $new_coords]
			set DistanceLabelText [format "%d grid%s, %d ft" $d [expr $d==1 ? {{}} : {{s}}] [expr $d*5] [expr ($d*5)==1 ? {{}} : {{s}}]]
		}
		update
	}
}

proc NextPoint {w x y} {
	global OBJ OBJ_CURRENT OBJ_SNAP canvas zoom
	set x [$canvas canvasx $x]
	set y [$canvas canvasy $y]
	lappend OBJ(POINTS:$OBJ_CURRENT) [expr [SnapCoord $x] / $zoom] [expr [SnapCoord $y] / $zoom]
	$w coords obj$OBJ_CURRENT "[ZoomVector $OBJ(X:$OBJ_CURRENT) $OBJ(Y:$OBJ_CURRENT) $OBJ(POINTS:$OBJ_CURRENT)] [SnapCoord $x] [SnapCoord $y]"
	update
}

proc LastPoint {w x y} {
	global OBJ OBJ_CURRENT OBJ_SNAP canvas zoom
	set x [$canvas canvasx $x]
	set y [$canvas canvasy $y]
	lappend OBJ(POINTS:$OBJ_CURRENT) [expr [SnapCoord $x] / $zoom] [expr [SnapCoord $y] / $zoom]
	EndObj $w 
}

proc LastAoePoint {w x y} {
	global OBJ OBJ_CURRENT OBJ_SNAP canvas zoom
	set x [$canvas canvasx $x]
	set y [$canvas canvasy $y]
	set xx [SnapCoordAlways $x]
	set yy [SnapCoordAlways $y]
	lappend OBJ(POINTS:$OBJ_CURRENT) [expr $xx / $zoom] [expr $yy / $zoom]
	$w delete obj_distance$OBJ_CURRENT
	$w delete obj_locator$OBJ_CURRENT
	$w delete obj_locator_radius$OBJ_CURRENT
	#$w delete obj_locator_cone1_$OBJ_CURRENT
	#$w delete obj_locator_cone2_$OBJ_CURRENT
	$w delete obj_locator_cone3_$OBJ_CURRENT
	$canvas create oval [expr $xx-10] [expr $yy-10] [expr $xx+10] [expr $yy+10] -width 3 -outline $OBJ(FILL:$OBJ_CURRENT) -tags [list obj$OBJ_CURRENT]
	$canvas create line [expr $xx-5] [expr $yy-5] [expr $xx+5] [expr $yy+5] -width 3 -fill $OBJ(FILL:$OBJ_CURRENT) -tags [list obj$OBJ_CURRENT]
	$canvas create line [expr $xx-5] [expr $yy+5] [expr $xx+5] [expr $yy-5] -width 3 -fill $OBJ(FILL:$OBJ_CURRENT) -tags [list obj$OBJ_CURRENT]
	EndObj $w 
}
	
proc LastArcPoint {w x y} {
	global OBJ OBJ_CURRENT OBJ_SNAP canvas zoom
	set x [$canvas canvasx $x]
	set y [$canvas canvasy $y]
	lappend OBJ(POINTS:$OBJ_CURRENT) [expr [SnapCoord $x] / $zoom] [expr [SnapCoord $y] / $zoom]
	bind $w <1>         "SetArcStartAngle $w %x %y"
	bind $w <B1-Motion> "DragArcStartAngle $w %x %y"
	bind $w <Motion>    "DragArcStartAngle $w %x %y"
}

proc DragArcStartAngle {w x y} {
	global OBJ OBJ_CURRENT OBJ_SNAP ARCMODE canvas
	#set x [$canvas canvasx $x]
	#set y [$canvas canvasy $y]
	set OBJ(START:$OBJ_CURRENT) [expr $x % 360]
	set OBJ(EXTENT:$OBJ_CURRENT) [expr $y % 360]
	set OBJ(ARCMODE:$OBJ_CURRENT) $ARCMODE
	$w itemconfigure obj$OBJ_CURRENT -start $OBJ(START:$OBJ_CURRENT) -extent $OBJ(EXTENT:$OBJ_CURRENT) -style $ARCMODE
}

proc SetArcStartAngle {w x y} {
	DragArcStartAngle $w $x $y
	EndObj $w
	arctool
}

proc EndObj w {
	global OBJ OBJ_CURRENT
	global BUTTON_MIDDLE BUTTON_RIGHT
	if {$OBJ(TYPE:$OBJ_CURRENT) != "tile" 
	&& $OBJ(TYPE:$OBJ_CURRENT) != "text" 
	&& $OBJ(POINTS:$OBJ_CURRENT) == {}} {
		$w delete obj$OBJ_CURRENT
		RemoveObject $OBJ_CURRENT
		$w delete obj_distance$OBJ_CURRENT
	} elseif {$OBJ(TYPE:$OBJ_CURRENT) == "ruler"} {
		# Rulers are only temporary. I suppose we could plant a flag at the endpoint or something
		# but right now we don't need to.
		$w delete obj$OBJ_CURRENT
		RemoveObject $OBJ_CURRENT
		$w delete obj_distance$OBJ_CURRENT
	} elseif {$OBJ(TYPE:$OBJ_CURRENT) != "aoe"} {
		$w coords obj$OBJ_CURRENT [ZoomVector $OBJ(X:$OBJ_CURRENT) $OBJ(Y:$OBJ_CURRENT) $OBJ(POINTS:$OBJ_CURRENT)]
	}
	bind $w <1> "StartObj $w %x %y"
	bind $w $BUTTON_MIDDLE {}
	bind . <Key-Escape> {}
	update
	if [info exists OBJ(TYPE:$OBJ_CURRENT)] {
		StartSendElementSet 1
		foreach key [array names OBJ *:$OBJ_CURRENT] {
			ContinueSendElementSet [list $key $OBJ($key)]
		}
		FinishSendElementSet
	}
	set OBJ_CURRENT 0
}

proc SquareGrid {w xx yy show} {
	global iscale GuideLines MajorGuideLines GuideLineOffset MajorGuideLineOffset GridEnable dark_mode
	$w delete grid
	if {! $GridEnable} {
		return
	}
	if {$dark_mode} {
		set gridcolor #aaaaaa
	} else {
		set gridcolor blue
	}

	for {set x 0} {($x * $iscale) < $xx} {incr x} {
		if {$MajorGuideLines > 0 && (($x - [lindex $MajorGuideLineOffset 0]) % $MajorGuideLines) == 0} {
			set SGfc "#345F12"
			set SGw 3
		} elseif {$GuideLines > 0 && (($x - [lindex $GuideLineOffset 0]) % $GuideLines) == 0} {
			set SGfc "#B00B03"
			set SGw  2
		} else {
			set SGfc $gridcolor
			set SGw  1
		}
		$w create line [expr $x*$iscale] 0 [expr $x*$iscale] $yy -fill $SGfc -tags "grid" -width $SGw
		if $show update
	}
	for {set y 0} {($y * $iscale) < $yy} {incr y} {
		if {$MajorGuideLines > 0 && (($y - [lindex $MajorGuideLineOffset 1]) % $MajorGuideLines) == 0} {
			set SGfc "#345F12"
			set SGw 3
		} elseif {$GuideLines > 0 && (($y - [lindex $GuideLineOffset 1]) % $GuideLines) == 0} {
			set SGfc "#B00B03"
			set SGw  2
		} else {
			set SGfc $gridcolor
			set SGw  1
		}
		$w create line 0 [expr $y*$iscale] $xx [expr $y*$iscale] -fill $SGfc -tags "grid" -width $SGw
		if $show update
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
#   MOB(AREA:<id>)  <grids surrounding object for threat area> or size code
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

proc PlaceSomeone {w x y c n a s t id reach} {
	global MOB NextMOBID OBJ_NEXT_Z canvas

	if {[info exists MOB(ID:$n)] && $id ne $MOB(ID:$n)} {
		DEBUG 1 "Placing $n (ID $id) but already have one with ID $MOB(ID:$n)"
		DEBUG 1 "--Removing old one"
		ITsend [list CLR $MOB(ID:$n)]
		RemovePerson $MOB(ID:$n)
	}

	if {![info exists MOB(NAME:$id)]} {
		DEBUG 1 "--Adding new person $id"
		set MOB(NAME:$id) $n
		set MOB(ID:$n)    $id
		set MOB(AREA:$id) $a
		set MOB(SIZE:$id) $s
		set MOB(KILLED:$id) 0
		set MOB(SKIN:$id) 0
		set MOB(NOTE:$id) {}
		set MOB(DIM:$id) 0
		set MOB(TYPE:$id) $t
		set MOB(REACH:$id) $reach
		set MOB(ELEV:$id) 0
		set MOB(MOVEMODE:$id) {}
		set MOB(HEALTH:$id) {}
		DEBUG 1 "--Done"
	} else {
		DEBUG 1 "PlaceSomeone $n using existing id $id"
	}

	set MOB(COLOR:$id) $c
	MoveSomeone $w $id $x $y
}

proc MoveSomeone {w id x y} {
	global MOB

	set MOB(GX:$id) $x
	set MOB(GY:$id) $y

	RenderSomeone $w $id
}

#
# convert size code to:  reach-dia weapon-dia matrix
#
proc MonsterSizeValue {size} {
	switch $size {
		F - f { return 0.1 }
		D - d { return 0.2 }
		T - t { return 0.5 }
		S - s - 
		M - m - m20 - M20 - 1 { return 1 }
		L - l - l0 - L0 - 2 { return 2 }
		H - h - 3 { return 3 }
		G - g - 4 { return 4 }
		C - c - 6 { return 6 }
		default { return 0 }
	}
}

# -> {area reach matrix}
#
# Spaces with 0 will not be drawn as threatened squares
# with 1 or 3 will be in the reach threat zone.
# with 2 or 3 will be in the normal threat zone
#
proc ReachMatrix {size} {
	switch $size {
		F - f -
		D - d -
		T - t { return { 0 0 {
		}}}
		1 -
		S - s -
		M - m { return { 1 2 {
			{ 1 1 1 1 1 }
			{ 1 2 2 2 1 }	
			{ 1 2 2 2 1 }	
			{ 1 2 2 2 1 }	
			{ 1 1 1 1 1 }
		}}}
		l { return { 1 2 {
			{ 1 1 1 1 1 1 }
			{ 1 2 2 2 2 1 }
			{ 1 2 2 2 2 1 }
			{ 1 2 2 2 2 1 }
			{ 1 2 2 2 2 1 }
			{ 1 1 1 1 1 1 }
		}}}
		2 -
		L { return { 2 4 {
			{ 0 0 0 1 1 1 1 0 0 0 }
			{ 0 1 1 1 1 1 1 1 1 0 }
			{ 0 1 3 2 2 2 2 3 1 0 }
			{ 1 1 2 2 2 2 2 2 1 1 }
			{ 1 1 2 2 2 2 2 2 1 1 }
			{ 1 1 2 2 2 2 2 2 1 1 }
			{ 1 1 2 2 2 2 2 2 1 1 }
			{ 0 1 3 2 2 2 2 3 1 0 }
			{ 0 1 1 1 1 1 1 1 1 0 }
			{ 0 0 0 1 1 1 1 0 0 0 }
		}}}
		M20 -
		m20 {
			return { 1 4 {
			{ 0 0 0 1 1 1 0 0 0 }
			{ 0 1 1 1 1 1 1 1 0 }
			{ 0 1 1 1 1 1 1 1 0 }
			{ 1 1 1 2 2 2 1 1 1 }
			{ 1 1 1 2 2 2 1 1 1 }
			{ 1 1 1 2 2 2 1 1 1 }
			{ 0 1 1 1 1 1 1 1 0 }
			{ 0 1 1 1 1 1 1 1 0 }
			{ 0 0 0 1 1 1 0 0 0 }
		}}}
		L0 -
		l0 {
			return { 0 0 {
			{ 0 0 }
			{ 0 0 }
		}}}
		h { return { 2 4 {
			{ 0 0 0 1 1 1 1 1 0 0 0 }
			{ 0 1 1 1 1 1 1 1 1 1 0 }
			{ 0 1 3 2 2 2 2 2 3 1 0 }
			{ 1 1 2 2 2 2 2 2 2 1 1 }
			{ 1 1 2 2 2 2 2 2 2 1 1 }
			{ 1 1 2 2 2 2 2 2 2 1 1 }
			{ 1 1 2 2 2 2 2 2 2 1 1 }
			{ 1 1 2 2 2 2 2 2 2 1 1 }
			{ 0 1 3 2 2 2 2 2 3 1 0 }
			{ 0 1 1 1 1 1 1 1 1 1 0 }
			{ 0 0 0 1 1 1 1 1 0 0 0 }
		}}}
		3 -
		H { return { 3 6 {
			{ 0 0 0 0 0 1 1 1 1 1 0 0 0 0 0 }
			{ 0 0 0 1 1 1 1 1 1 1 1 1 0 0 0 }
			{ 0 0 1 1 1 1 1 1 1 1 1 1 1 0 0 }
			{ 0 1 1 1 1 2 2 2 2 2 1 1 1 1 0 }
			{ 0 1 1 1 2 2 2 2 2 2 2 1 1 1 0 }
			{ 1 1 1 2 2 2 2 2 2 2 2 2 1 1 1 }
			{ 1 1 1 2 2 2 2 2 2 2 2 2 1 1 1 }
			{ 1 1 1 2 2 2 2 2 2 2 2 2 1 1 1 }
			{ 1 1 1 2 2 2 2 2 2 2 2 2 1 1 1 }
			{ 1 1 1 2 2 2 2 2 2 2 2 2 1 1 1 }
			{ 0 1 1 1 2 2 2 2 2 2 2 1 1 1 0 }
			{ 0 1 1 1 1 2 2 2 2 2 1 1 1 1 0 }
			{ 0 0 1 1 1 1 1 1 1 1 1 1 1 0 0 }
			{ 0 0 0 1 1 1 1 1 1 1 1 1 0 0 0 }
			{ 0 0 0 0 0 1 1 1 1 1 0 0 0 0 0 }
		}}}
		G { return { 4 8 {
			{ 0 0 0 0 0 0 0 1 1 1 1 1 1 0 0 0 0 0 0 0 }
			{ 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 }
			{ 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 }
			{ 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 }
			{ 0 0 1 1 1 1 1 1 2 2 2 2 1 1 1 1 1 1 0 0 }
			{ 0 1 1 1 1 1 2 2 2 2 2 2 2 2 1 1 1 1 1 0 }
			{ 0 1 1 1 1 2 2 2 2 2 2 2 2 2 2 1 1 1 1 0 }
			{ 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 }
			{ 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 }
			{ 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 }
			{ 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 }
			{ 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 }
			{ 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 }
			{ 0 1 1 1 1 2 2 2 2 2 2 2 2 2 2 1 1 1 1 0 }
			{ 0 1 1 1 1 1 2 2 2 2 2 2 2 2 1 1 1 1 1 0 }
			{ 0 0 1 1 1 1 1 1 2 2 2 2 1 1 1 1 1 1 0 0 }
			{ 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 }
			{ 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 }
			{ 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 }
			{ 0 0 0 0 0 0 0 1 1 1 1 1 1 0 0 0 0 0 0 0 }
		}}}
		g { return { 3 6 {
			{ 0 0 0 0 0 1 1 1 1 1 1 0 0 0 0 0 }
			{ 0 0 0 1 1 1 1 1 1 1 1 1 1 0 0 0 }
			{ 0 0 1 1 1 1 1 1 1 1 1 1 1 1 0 0 }
			{ 0 1 1 1 1 1 2 2 2 2 1 1 1 1 1 0 }
			{ 0 1 1 1 2 2 2 2 2 2 2 2 1 1 1 0 }
			{ 1 1 1 1 2 2 2 2 2 2 2 2 1 1 1 1 }
			{ 1 1 1 2 2 2 2 2 2 2 2 2 2 1 1 1 }
			{ 1 1 1 2 2 2 2 2 2 2 2 2 2 1 1 1 }
			{ 1 1 1 2 2 2 2 2 2 2 2 2 2 1 1 1 }
			{ 1 1 1 2 2 2 2 2 2 2 2 2 2 1 1 1 }
			{ 1 1 1 1 2 2 2 2 2 2 2 2 1 1 1 1 }
			{ 0 1 1 1 2 2 2 2 2 2 2 2 1 1 1 0 }
			{ 0 1 1 1 1 1 2 2 2 2 1 1 1 1 1 0 }
			{ 0 0 1 1 1 1 1 1 1 1 1 1 1 1 0 0 }
			{ 0 0 0 1 1 1 1 1 1 1 1 1 1 0 0 0 }
			{ 0 0 0 0 0 1 1 1 1 1 1 0 0 0 0 0 }
		}}}
		C { return { 6 12 {
			{ 0 0 0 0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0 0 }
			{ 0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 }
			{ 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 }
			{ 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 }
			{ 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 }
			{ 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 }
			{ 0 0 1 1 1 1 1 1 1 1 1 1 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 }
			{ 0 0 1 1 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 0 0 }
			{ 0 1 1 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 0 }
			{ 0 1 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 0 }
			{ 0 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 0 }
			{ 1 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 }
			{ 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 }
			{ 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 }
			{ 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 }
			{ 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 }
			{ 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 }
			{ 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 }
			{ 1 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 }
			{ 0 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 0 }
			{ 0 1 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 0 }
			{ 0 1 1 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 0 }
			{ 0 0 1 1 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 0 0 }
			{ 0 0 1 1 1 1 1 1 1 1 1 1 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 }
			{ 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 }
			{ 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 }
			{ 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 }
			{ 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 }
			{ 0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 }
			{ 0 0 0 0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0 0 }
		}}}
		c { return { 4 8 {
			{ 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 }
			{ 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 }
			{ 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 }
			{ 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 }
			{ 0 0 1 1 1 1 1 1 2 2 2 2 2 2 1 1 1 1 1 1 0 0 }
			{ 0 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 0 }
			{ 0 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 0 }
			{ 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 }
			{ 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 }
			{ 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 }
			{ 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 }
			{ 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 }
			{ 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 }
			{ 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 }
			{ 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 }
			{ 0 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 0 }
			{ 0 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 0 }
			{ 0 0 1 1 1 1 1 1 2 2 2 2 2 2 1 1 1 1 1 1 0 0 }
			{ 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 }
			{ 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 }
			{ 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 }
			{ 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 }
		}}}
	}
}

proc MOBCenterPoint {id} {
	global MOB iscale
	set x $MOB(GX:$id)
	set y $MOB(GY:$id)
	set r [expr [MonsterSizeValue $MOB(SIZE:$id)] / 2.0]
	return [list [expr ($x+$r)*$iscale] [expr ($y+$r)*$iscale] [expr $r*$iscale]]
}

proc FindImage {image_pfx zoom} {
	global TILE_SET TILE_RETRY

	set tile_id [tile_id $image_pfx $zoom]
	if {! [info exists TILE_SET($tile_id)]} {
		DEBUG 1 "Asked for image $image_pfx at zoom $zoom, but that image isn't already loaded."
		set cache_filename [cache_filename $image_pfx $zoom]
		if {[lindex [cache_info $cache_filename] 0]} {
			DEBUG 1 "--Cache file $cache_filename exists, using that..."
			create_image_from_file $tile_id $cache_filename
		} else {
			DEBUG 1 "--No cached copy exists, either. Asking for help..."
            if {![info exists TILE_RETRY($tile_id)]} {
                # first reference: ask now and wait for 10
                set TILE_RETRY($tile_id) 10
                ITsend [list AI? $image_pfx $zoom]
            } elseif {$TILE_RETRY($tile_id) <= 0} {
                # subsequent times: ask every 50
                ITsend [list AI? $image_pfx $zoom]
                set TILE_RETRY($tile_id) 50
            } else {
                incr TILE_RETRY($tile_id) -1
            }
		}
	}

	return $tile_id
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

array set MarkerDescription {
	bleed	    		{Bleeding: take damage each turn unless stopped by a DC 15 Heal check or any spell that cures hit point damage.}
	{ability drained} 	{Ability Drained}
	{energy drained}  	{Energy Drained: has negative levels. Take cumulative -1 penalty per level drained on all ability checks, attack rolls, combat maneuver checks, combat maneuver defense, saving throws, and skill checks. Current and total hit points reduce by 5 per negative level. Treated as level reduction for level-dependent variables. No loss of prepared spells or slots. Daily saving throw to remove each negative level unless permanent.  If negative levels >= hit dice, dies.}
	poisoned    		{Poisoned: may have onset delay and additional saving throws andadditional damage over time as the poison runs its course.}
	deafened			{Deafened: cannot hear. -4 initiative, automatically fails Perception checks based on sound, -4 on opposed Perception checks, 20% of spell failure when casting spells with verbal components.}
	stable      		{Stable: no longer dying but unconscious. May make DC 10 Constitution check hourly to become conscious and disabled even with negative hit points, with check penalty equal to negative hit points. If became stable without help, can make hourly Con check to become stable as above but failure causes 1 hit point damage.}

	blinded     		{Blinded: cannot see, -2 AC, no Dexterity bonus to AC, -4 on most Strength- and Dexterity-based skill checks and opposed Perception skill checks. All checks and activities that rely on vision automatically fail. Opponents have total concealment (50% miss chance). Must make DC 10 Acrobatics check to move faster than 1/2 speed.}
 	dazzled     		{Dazzled: unable to see well because of overstimulation of the eyes. -1 on attack rolls and sight-based Perception checks.}
 
	confused    		{Confused: cannot act normally or tell ally from foe, treating all as enemies. Action is random: 01-25%=normal, 26-50%=babble incoherently, 51-75%=deal 1d8+Str modifier damage to self, 76-100%=attack nearest creature. No attack of opportunity unless against creature most recently attacked or who attacked them.}
	cowering    		{Cowering: frozen in fear and can take no actions. -2 AC, no Dexterity bonus.}
	dazed       		{Dazed: unable to act normally (no actions, no AC penalty).}
	fascinated 			{Fascinated: entranced by Su or Sp effect. Stand or sit quietly, taking no other actions. -4 on skill checks made as reactions. Potential threats grant new saving throw against fascinating effect. Obvious threat make shake creature free of the spell as standard action.}
	paralyzed  			{Paralyzed: frozen in place, unable to move or act. Effective Dexterity and Strength of 0. Helpless but can take purely mental actions. Winged flying creatures fall. Swimmers may drown. Others may move through space of paralyzed creatures, but counts as 2 spaces.}
	helpless   			{Helpless: paralyzed, held, bound, sleeping, unconscious, etc. Effective Dexterity of 0. Melee attackers get +4 bonus (no bonus for ranged). Can be sneak attacked. Subject to coup de grâce (full-round action with automatic critical hit, Fort save DC 10 + damage dealt or die; if immune to critical hits, then critical damage not taken nor Fort save required).}
	staggered  			{Staggered: only single move or standard action. No full-round actions but ok to make free, swift, and immediate actions.}
	stunned    			{Stunned: drop everything held, take no actions, -2 AC, lose Dexterity bonus to AC.}

	dying       		{Dying: unconscious, no actions. Each turn make DC 10 Constitution check to stabilize, at penalty equal to current (negative) hit points. Natural 20=auto success. If check failed, take 1 hp damage.}
	disabled    		{Disabled: conscious, make take a single move or standard action but not both nor full-round actions; swift, immediate, and free actions are ok. Move at 1/2 speed. Std actions that are strenuous deal 1 point of damage at completion.}
	unconscious 		{Unconscious: knocked out and helpless.}
	petrified   		{Petrified: turned to stone, unconscious. Broken pieces must be reattached when turning to flesh to avoid permanent damage.}


	entangled   		{Entangled: ensnared, move at 1/2 speed, cannot run or charge, -2 attack, -4 Dexterity. Spellcasting requires concentration DC 15+spell level or lose spell.}
	grappled    		{Grappled: restrained, cannot move, -4 Dexterity, -2 attacks and combat maneuver checks except those made to grapple or escape grapple. No action requiring two hands. Spellcasting requires concentration DC 10 + grappler's CMB + spell level) or lose spell. Cannot make attack of opportunity. Cannot use Stealth against grappler but if becomes invisible, gain +2 on CMD to avoid being grappled.}
	pinned      		{Pinned: tightly bound. Cannot move. No Dexterity bonus, plus -4 AC. May attempt to free with CMB or Escape Artist check, take verbal and mental actions, but not cast spells with somatic or material components. Spell casting requires concentration DC 10 + grappler's CMB + spell level or lose spell. More severe than (and does not stack with) grapple condition.}
	prone       		{Prone: lying on ground. -4 on melee attacks, cannot use ranged weapon except crossbows. +4 AC vs. ranged attacks but -4 AC vs. melee attacks. Standing up is a move-equivalent action that provokes attacks of opportunity.}

	exhausted   		{Exhausted: move 1/2 speed, cannot run or charge, -6 Strength and Dexterity. Change to fatigued after 1 hour of complete rest.}
	fatigued    		V
	nauseated   		{Nauseated: Cannot attack, cast spells, concentrate on spells, or do anything else requiring attention. Can only take a single move action.}
	sickened    		{Sickened: -2 on attacks, weapon damage, saving throws, skill checks, ability checks.}

	flat-footed 		{Flat-Footed: not yet acted during combat, unable to react normally to the situation. Loses Dexterity bonus to AC, cannot make attacks of opportunity.}
	incorporeal 		{Incorporeal: no physical body. Immune to nonmagic attacks, 50% damage from magic weapons, spells, Sp effects, Su effects. Full damage from other incorporeal creatures and effects as well as force effects.}
	invisible   		{Invisible: +2 attack vs. sighted opponent, ignore opponent Dexterity bonus to AC.}

	shaken      		{Shaken: -2 on attacks, saving throws, skill checks, ability checks.}
	frightened  		{Frightened: flees from source of fear if possible, else fight. -2 attacks, saving throws, skill checks, and ability checks. Can use special abilities and spells to flee (MUST do so if they are only way to escape).}
	panicked    		{Panicked: drop anything held and flee at top speed along random path. -2 on saving throws, skill checks, ability checks. If cornered, cowers. Can use special abilities and spells to flee (MUST if that's the only way to escape).}
}

proc DefineStatusMarker {condition shape color description} {
	global MarkerColor MarkerShape MarkerDescription
	if {$shape eq {} || $color eq {}} {
		array unset MarkerColor $condition
		array unset MarkerShape $condition
	} else {
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

proc CreatureStatusMarker {w id x y s} {
	global MOB MarkerColor MarkerShape
	
	# HEALTH conditions
	#  normal/{} flat staggered unconscious stable disabled dying
	# dying: half-slash through the token
	set conditions {}
	if [info exists MOB(_CONDITION:$id)] {
		lappend conditions $MOB(_CONDITION:$id)
	}
	if [info exists MOB(STATUSLIST:$id)] {
		foreach condition $MOB(STATUSLIST:$id) {
			lappend conditions $condition
		}
	}
	if {[info exists MOB(HEALTH:$id)] && [llength $MOB(HEALTH:$id)] >= 6} {
		if [lindex $MOB(HEALTH:$id) 4] {
			lappend conditions flat-footed
		}
		if [lindex $MOB(HEALTH:$id) 5] {
			lappend conditions stable
		}
	}
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
				set color $MOB(COLOR:$id)
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
			switch -exact $MarkerShape($condition) {
				|v		{
							$w create polygon [expr $x+$vlo] [expr $y+($s*.5)] \
									  [expr $x+$vlo+10] [expr $y+($s*.5)] \
									  [expr $x+$vlo+5] [expr $y+($s*.5)+15] \
									  [expr $x+$vlo] [expr $y+($s*.5)] \
								-fill $color -width 1 -outline white -tags $tags -dash $dashpattern
							incr vlo 10
						}
				v|		{
							$w create polygon [expr $x1-$vro] [expr $y+($s*.5)] \
											  [expr $x1-$vro-10] [expr $y+($s*.5)] \
											  [expr $x1-$vro-5] [expr $y+($s*.5)+15] \
											  [expr $x1-$vro] [expr $y+($s*.5)] \
								-fill $color -width 1 -outline white -tags $tags -dash $dashpattern
							incr vro 10
						}
				|o		{
							$w create oval [expr $x+$vlo] [expr $y+($s*.5)] \
									  	   [expr $x+$vlo+15] [expr $y+($s*.5)+15] \
								-fill $color -width 1 -outline white -tags $tags -dash $dashpattern
							incr vlo 15
						}
				o|		{
							$w create oval [expr $x1-$vro] [expr $y+($s*.5)] \
									  	   [expr $x1-$vro-15] [expr $y+($s*.5)+15] \
								-fill $color -width 1 -outline white -tags $tags -dash $dashpattern
							incr vro 15
						}
				|<>		{
							$w create polygon [expr $x+$vlo+5] [expr $y+($s*.5)] \
									  	      [expr $x+$vlo+10] [expr $y+($s*.5)+7] \
									  	      [expr $x+$vlo+5] [expr $y+($s*.5)+15] \
									  	      [expr $x+$vlo] [expr $y+($s*.5)+7] \
									  	      [expr $x+$vlo+5] [expr $y+($s*.5)] \
								-fill $color -width 1 -outline white -tags $tags -dash $dashpattern
							incr vlo 10
						}
				<>|		{
							$w create polygon [expr $x1-$vro-5] [expr $y+($s*.5)] \
									  	      [expr $x1-$vro-10] [expr $y+($s*.5)+7] \
									  	      [expr $x1-$vro-5] [expr $y+($s*.5)+15] \
									  	      [expr $x1-$vro] [expr $y+($s*.5)+7] \
									  	      [expr $x1-$vro-5] [expr $y+($s*.5)] \
								-fill $color -width 1 -outline white -tags $tags -dash $dashpattern
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

proc RenderSomeone {w id} {
	DEBUG 3 "RenderSomeone $w $id"
	global MOB ThreatLineWidth iscale SelectLineWidth ThreatLineHatchWidth ReachLineColor
	global HealthBarWidth HealthBarFrameWidth HealthBarConditionFrameWidth
	global ShowHealthStats

	set x $MOB(GX:$id)
	set y $MOB(GY:$id)
	DistributeVars [ReachMatrix $MOB(AREA:$id)] mob_area mob_reach mob_matrix
	set mob_size [MonsterSizeValue $MOB(SIZE:$id)]

	# If somehow we have a misaligned creature that's at least "small",
	# snap to even grid boundary
	if {$mob_size >= 1 && ($x != int($x) || $y != int($y))} {
		set x [expr int($x)]
		set y [expr int($y)]
		set MOB(GX:$id) $x
		set MOB(GY:$id) $y
	}

	$w delete "M#$id"


	# spell area of effect
	if {[info exists MOB(AOE:$id)] && [llength $MOB(AOE:$id)] == 3} {
		DistributeVars $MOB(AOE:$id) aoe_type aoe_radius aoe_color
		set aoe_radius [expr $aoe_radius * $iscale]; #convert to canvas units for rendering
		switch $aoe_type {
			radius {
				set GX0 $MOB(GX:$id)
				set GY0 $MOB(GY:$id)
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
				set sz [MonsterSizeValue $MOB(SIZE:$id)]
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
	#$w create rectangle [expr $x*50] [expr $y*50] [expr ($x+1)*50] [expr ($y+1)*50] -outline red -tags "M#$id" -fill $MOB(COLOR:$id) -stipple gray25
	global MOB_COMBATMODE
	if {$MOB_COMBATMODE && !$MOB(KILLED:$id)} {
		if {$MOB(DIM:$id)} {
			$w create arc [expr ($x-$mob_area)*$iscale] [expr ($y-$mob_area)*$iscale] [expr ($x+$mob_size+$mob_area)*$iscale] [expr ($y+$mob_area+$mob_size)*$iscale] -outline $MOB(COLOR:$id) -width $ThreatLineWidth -tags "M#$id MC#$id MT=$MOB(TYPE:$id) allMOB MCzone" -dash . -start 0 -extent 359.9 -style arc
			if {$MOB(REACH:$id)} {
				$w create arc [expr ($x-$mob_reach)*$iscale] [expr ($y-$mob_reach)*$iscale] [expr ($x+$mob_size+$mob_reach)*$iscale] [expr ($y+$mob_reach+$mob_size)*$iscale] -outline $MOB(COLOR:$id) -width $ThreatLineWidth -tags "M#$id MR#$id MT=$MOB(TYPE:$id) allMOB MCzone" -dash . -start 0 -extent 359.9 -style arc
			}
		} else {
			set Xstart [expr ($x-$mob_reach)]
			set yy [expr ($y-$mob_reach)]
			switch $MOB(REACH:$id) {
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
			set color $MOB(COLOR:$id)
			foreach row $mob_matrix {
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
										   -tags "M#$id MF#$id MH#$id MT=$MOB(TYPE:$id) allMOB"
						}
					}
					incr xx
				}
				incr yy
			}

			$w create arc [expr ($x-$mob_area)*$iscale] [expr ($y-$mob_area)*$iscale] [expr ($x+$mob_size+$mob_area)*$iscale] [expr ($y+$mob_area+$mob_size)*$iscale] -outline red -width $ThreatLineWidth -tags "MF#$id M#$id MC#$id MT=$MOB(TYPE:$id) allMOB MCzone" -dash . -start 0 -extent 359.9 -style arc
			if {$MOB(REACH:$id)} {
				$w create arc [expr ($x-$mob_reach)*$iscale] [expr ($y-$mob_reach)*$iscale] [expr ($x+$mob_size+$mob_reach)*$iscale] [expr ($y+$mob_reach+$mob_size)*$iscale] -outline $ReachLineColor -width $ThreatLineWidth -tags "M#$id MF#$id MR#$id MT=$MOB(TYPE:$id) allMOB MCzone" -dash . -start 0 -extent 359.9 -style arc
			}
		}
	}
		
	# nametag
	global MOB_IMAGE
	set mob_name [set mob_img_name $MOB(NAME:$id)]
	if [info exists MOB_IMAGE($mob_name)] {
		set mob_img_name $MOB_IMAGE($mob_name)
	} elseif [regexp {^(.*) #\d+$} $mob_name mob_full_name mob_creature_name mob_sequence] {
		set mob_img_name $mob_creature_name
	}

	#
	# prefix to use based on skin selected and possibly if alive
	#
	set image_candidates {}
	set skin_idx $MOB(SKIN:$id)

	if {$MOB(KILLED:$id)} {
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

	global zoom 
	global TILE_SET
	#set tile_id [FindImage $image_pfx $zoom]
    #
    # Run through each possible name to see if we have that name 
    # cached already, before broadcasting a request for one.
    #
    set found_image false
    DEBUG 3 "Looking up image at zoom $zoom for each of: $image_candidates"
	foreach image_pfx $image_candidates {
		#
		# if we already know we have this image, just use it
		#
		if {[info exists TILE_SET($image_pfx:$zoom)]} {
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
            FindImage $ip $zoom
            if {[info exists TILE_SET($ip:$zoom)]} {
                DEBUG 3 "-- Found $ip, using that."
                set image_pfx $ip
                break
            }
        }
	}

	#
	# if we found a copy of the image, it will now appear in TILE_SET.
	#
	if [info exists TILE_SET($image_pfx:$zoom)] {
		DEBUG 3 "$image_pfx:$zoom = $TILE_SET($image_pfx:$zoom)"
		$w create oval [expr $x*$iscale] [expr $y*$iscale] [expr ($x+$mob_size)*$iscale] [expr ($y+$mob_size)*$iscale] -fill $fillcolor -tags "mob MF#$id M#$id MN#$id allMOB"
		$w create image [expr $x*$iscale] [expr $y*$iscale] -anchor nw -image $TILE_SET($image_pfx:$zoom) -tags "mob M#$id MN#$id allMOB"
		$w create text [expr $x*$iscale] [expr $y*$iscale] -anchor nw -fill black -font [FontBySize $MOB(SIZE:$id)] -text $mob_name -tags "M#$id MF#$id MT#$id allMOB"
	} else {
		DEBUG 3 "No $image_pfx:$zoom found in TILE_SET"
		$w create oval [expr $x*$iscale] [expr $y*$iscale] [expr ($x+$mob_size)*$iscale] [expr ($y+$mob_size)*$iscale] -fill $fillcolor -tags "mob MF#$id M#$id MN#$id allMOB"
		$w create text [expr ($x+(.5*$mob_size))*$iscale] [expr ($y+(.5*$mob_size))*$iscale] -fill $textcolor -font [FontBySize $MOB(SIZE:$id)] -text $mob_name -tags "M#$id MF#$id MT#$id allMOB"
	}
	if {$MOB(KILLED:$id)} {
		$w create line [expr $x*$iscale] [expr $y*$iscale] [expr ($x+$mob_size)*$iscale] [expr ($y+$mob_size)*$iscale] -fill $MOB(COLOR:$id) -width 7 -tags "mob MF#$id M#$id MN#$id allMOB"
		$w create line [expr $x*$iscale] [expr ($y+$mob_size)*$iscale] [expr ($x+$mob_size)*$iscale] [expr $y*$iscale] -fill $MOB(COLOR:$id) -width 7 -tags "mob MF#$id M#$id MN#$id allMOB"
	}
		
	#
	# Bind mouseover events for the token
	#
	#$w bind M#$id <Enter> "DisplayHealthStats $id"
	#$w bind M#$id <Leave> "DisplayHealthStats {}"
	tooltip::tooltip $w -items MN#$id [CreateHealthStatsToolTip $id]
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
	set its_dead_jim $MOB(KILLED:$id)
	set show_healthbar 0
	set health {}
	set maxhp 0
	set lethal 0
	set nonlethal 0
	set grace 0
	set flatp 0
	set stablep 0
	set server_blur_hp 0
	if {[info exists MOB(_CONDITION:$id)]} {
		set condition $MOB(_CONDITION:$id)
	} else {
		set condition {}
	}

	if {[info exists MOB(HEALTH:$id)]} {
		set health $MOB(HEALTH:$id)
		if {[llength $health] >= 7} {
			set show_healthbar 1
			DistributeVars $health maxhp lethal nonlethal grace flatp stablep condition server_blur_hp
			global blur_all blur_pct
			if {$blur_all || $MOB(TYPE:$id) ne {player}} {
				set hp_remaining [blur_hp $maxhp $lethal]
			} else {
				set hp_remaining [expr $maxhp - $lethal]
			}
			DEBUG 2 "Health $id: $health max=$maxhp l=$lethal n=$nonlethal x=$grace ff=$flatp st=$stablep cond=$condition hpr=$hp_remaining ba=$blur_all b=$blur_pct server_b=$server_blur_hp"

			if {$its_dead_jim} {
				set condition {}
			} elseif {$condition eq {}} {
				# calculate condition automatically, otherwise it's forced
				if {$maxhp <= 0 || ($maxhp-$lethal <= -$grace)} { 
					set condition dead 
					# We're making the change locally here instead of broadcasting it out
					# because all the other map clients will be acting on the same logic
					# themselves and we don't need a storm of "this creature died" messages.
					set MOB(KILLED:$id) 1
					set its_dead_jim 1
					# Oh, no! We're already past the point where this would have been
					# useful to know. Start over and re-render them as a corpse this time.
					RenderSomeone $w $id
					return
				} elseif {$lethal > $maxhp && -$grace < $maxhp-$lethal} {
					set condition dying
				} elseif {$lethal == $maxhp} {
					set condition disabled
				} elseif {$nonlethal > 0 && $lethal+$nonlethal > $maxhp} {
					set condition unconscious
				} elseif {$nonlethal > 0 && $lethal+$nonlethal == $maxhp} {
					set condition staggered
				} elseif {$flatp} {
					set condition flat
				}
			}
			set MOB(_CONDITION:$id) $condition
		}
		# x,y 		grid coords
		# mob_size	grids across/down
		# iscale	multiplier to turn grids to pixels
		set Xhw [expr $mob_size * $iscale]
		set Xh0 [expr $x * $iscale]
		set Xhl [expr ($x + $mob_size) * $iscale]
		set Yh0 [expr ($y + $mob_size) * $iscale]
		set Yh1 [expr ($y + $mob_size) * $iscale - $HealthBarWidth]
		set Thl [list "M#$id" "MHB#$id" "allMOB"]
		set TxX [expr $Xh0 + 0.5*$Xhw]
		set TxY [expr $Yh0 - 0.5*$HealthBarWidth]
		set full_stats [expr $ShowHealthStats && {$MOB(TYPE:$id)} eq {{player}}]

		set bw $HealthBarFrameWidth
		set bc black
	} 

	CreatureStatusMarker $w $id [expr $x*$iscale] [expr $y*$iscale] [expr $mob_size*$iscale]
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
					set Xhb [expr max($Xh0, $Xhl - ($Xhw * (double($lethal - $maxhp)/$grace)))]
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
					$w create text $TxX $TxY -anchor center -fill white -text [format "%d/%d" [expr $maxhp-$lethal] $maxhp] -tags $Thl
				}
			} else {
				# not quite dead yet:
				#
				#   |<----------------Xhw------------------->|
				#   |________________________________________|
				#   |////////////|::::::::::|################|
				#  Xh0   health  |   non-l  |     lethal    Xhl
				#               Xhh        Xhn
				#
				# XXX if maxhp=0
				# XXX set width and outline based on condition

				if {$maxhp <= 0} {
					DEBUG 0 "$id has max HP of $maxhp; how did we even get this far without noticing that? BUG!"
					return
				}

				switch -exact $condition {
					flat			{ set bw $HealthBarConditionFrameWidth; set bc blue }
					staggered		{ set bw $HealthBarConditionFrameWidth; set bc yellow }
					unconscious		{ set bw $HealthBarConditionFrameWidth; set bc purple }
					stable			{ set bw $HealthBarConditionFrameWidth; set bc sienna }
					disabled		{ set bw $HealthBarConditionFrameWidth; set bc red }
				}

				# using maxhp-hp_remaining instead of lethal to account for blurring
				# we don't blur nonlethal for now but it's showing relative to the blurred lethal damage
				set Xhn [expr max($Xh0, $Xhl - ($Xhw * (double($maxhp-$hp_remaining)/$maxhp)))]
				set Xhh [expr max($Xh0, $Xhn - ($Xhw * (double($nonlethal)/$maxhp)))]
				DEBUG 3 "-- X: $Xhw $Xh0 $Xhl $Xhn $Xhh; Y: $Yh0 $Yh1; $Thl"
				$w create rectangle $Xh0 $Yh0 $Xhh $Yh1 -width $bw -outline $bc -fill green -tags $Thl
				if {$nonlethal > 0} {
					$w create rectangle $Xhh $Yh0 $Xhn $Yh1 -width $bw -outline $bc -fill yellow -tags $Thl
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

	# in case we loaded up an old creature token without elevation
	# or movement mode, set defaults on them now
	if {![info exists MOB(ELEV:$id)]} {
		set MOB(ELEV:$id) 0
	}
	if {![info exists MOB(MOVEMODE:$id)]} {
		set MOB(MOVEMODE:$id) {}
	}
	if {$MOB(ELEV:$id) != 0} {
		set fillcolor black
		set textcolor white
		switch $MOB(MOVEMODE:$id) {
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
		$w.z$id configure -foreground $textcolor -background $fillcolor -text $MOB(ELEV:$id) -font [FontBySize $MOB(SIZE:$id)]
	}

	#
	# Status tag
	#
	if {[info exists MOB(NOTE:$id)] && ![string equal $MOB(NOTE:$id) {}]} {
		if {![winfo exists $w.ms$id]} {
			catch {label $w.ms$id -text {} -foreground white -background blue}
		}
		$w create window [expr ($x+($mob_size))*$iscale] [expr ($y+$mob_size)*$iscale] -tags "M#$id MT#$id allMOB" -anchor se -window $w.ms$id 
		$w.ms$id configure -text $MOB(NOTE:$id) -font [FontBySize $MOB(SIZE:$id)]
		#$w create text [expr ($x+(.5*$mob_size))*$iscale] [expr ($y+$mob_size)*$iscale] -fill red -text $MOB(NOTE:$id) -tags "M#$id MF#$id MT#$id allMOB" -anchor s
	}
	#$w itemconfigure g$x,$y -fill $MOB(COLOR:$id) -stipple gray25

	#
	# selection
	#
	if {[info exists MOB(_SELECTED:$id)] && $MOB(_SELECTED:$id)} {
		$w create rectangle [expr $x*$iscale] [expr $y*$iscale] [expr ($x+$mob_size)*$iscale] [expr ($y+$mob_size)*$iscale] -outline blue -width $SelectLineWidth -tags "M#$id allMOB" ;#-fill $MOB(COLOR:$id) -stipple gray25
	}
	#
	# Threat zones
	# Find all of the instances of one being threatening another, and draw
	# arrows between them, indicating player-vs-monster sides as not threatening
	# each other.  We'll draw arrows tangent to the nametag ovals between
	# threatener and threatenee.
	#
	if $MOB_COMBATMODE {
		global PI
		$w delete "MArrows"
		DEBUG 4 "Deleting arrows, redrawing them"

		foreach tag [array names MOB NAME:*] {
			set mob_id [string range $tag 5 end]
			DEBUG 1 "Looking for location of $mob_id"
			if {!$MOB(KILLED:$mob_id)} {
				set xx $MOB(GX:$mob_id)
				set yy $MOB(GY:$mob_id)
				set sz [MonsterSizeValue $MOB(SIZE:$mob_id)]
				DEBUG 1 "- Found at ($xx,$yy), size=$sz:"
				for {set xi 0} {$xi < $sz} {incr xi} {
					for {set yi 0} {$yi < $sz} {incr yi} {
						lappend WhereIsMOB([expr $xx+$xi],[expr $yy+$yi]) $mob_id
						DEBUG 1 "-- ($xx+$xi, $yy+$yi) = $WhereIsMOB([expr $xx+$xi],[expr $yy+$yi])"
					}
				}
			}
		}

		foreach threatening_tag [array names MOB NAME:*] {
			set threatening_mob_id [string range $threatening_tag 5 end]
			DEBUG 1 "Checking who $threatening_mob_id is threatening"
			if {$MOB(KILLED:$threatening_mob_id)} continue
			DistributeVars [ReachMatrix $MOB(AREA:$threatening_mob_id)] ar re mat
			DistributeVars [MOBCenterPoint $threatening_mob_id] xc yc rc
			set sz [MonsterSizeValue $MOB(SIZE:$threatening_mob_id)]
			DEBUG 1 "-- area $ar reach $re ($xc,$yc) r=$rc"
			set Xstart [expr ($MOB(GX:$threatening_mob_id) - $re)]
			set yy [expr ($MOB(GY:$threatening_mob_id) - $re)]
			array unset target
			if {$MOB(REACH:$threatening_mob_id)} {
				set matbit 1
			} else {
				set matbit 2
			}
			foreach row $mat {
				set xx $Xstart
				foreach col $row {
					DEBUG 1 "--- @($xx,$yy) m=$col"
					if {$col & $matbit} {
						if [info exists WhereIsMOB($xx,$yy)] {
							DEBUG 1 "---- something is here: $WhereIsMOB($xx,$yy)"
							foreach target_id $WhereIsMOB($xx,$yy) {
								if {$target_id ne $threatening_mob_id
								&& $MOB(TYPE:$target_id) ne $MOB(TYPE:$threatening_mob_id)
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
				DistributeVars [MOBCenterPoint $target_id] Txc Tyc Trc
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
						$w create line $AOx $AOy $ADx $ADy -arrow last -fill red -width 5 -tags "MArrows M#$threatening_mob_id M#$target_id"
					}
#					if {$target($target_id) & 2} {
#						$w create line $AOx $AOy $ADx $ADy -arrow last -fill red -width 5 -tags "MArrows M#$threatening_mob_id M#$target_id"
#					} elseif {$MOB(REACH:$threatening_mob_id)} {
#						$w create line $AOx $AOy $ADx $ADy -arrow last -fill $ReachLineColor -width 3 -tags "MArrows M#$threatening_mob_id M#$target_id"
#					}
				}
			}
		}
	}
}

proc DistributeZero {v args} {
	set i 0
	foreach name $args {
		upvar $name t
		if {$i >= [llength $v]} {
			set t 0
		} else {
			set t [lindex $v $i]
			incr i
		}
	}
}

proc DistributeVars {v args} {
	set i 0
	foreach name $args {
		upvar $name t
		set t [lindex $v $i]
		incr i
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
	DistributeVars [$w coords "MN#$mob_id"] x1 y1 x2 y2
	set Rx [expr ($x2 - $x1) / 2.0]
	set Ry [expr ($y2 - $y1) / 2.0]
	return [concat $zone_coords [list [expr $Rx + $x1] [expr $Ry + $y1] $Rx $Ry $x1 $y1 $x2 $y2]]
}

#
# Selection of on-screen objects
#
proc AddToSelection {id} {
	global MOB canvas
	DEBUG 3 "Selecting $id"
	if {[info exists MOB(GX:$id)]} {
		set MOB(_SELECTED:$id) 1
		DEBUG 3 "selected $MOB(_SELECTED:$id)"
		RenderSomeone $canvas $id
	} else {
		DEBUG 3 "No key GX:$id found"
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
	global MOB canvas
	DEBUG 3 "Selecting $id"
	if {[info exists MOB(GX:$id)]} {
		if {[info exists MOB(_SELECTED:$id)]} {
			set MOB(_SELECTED:$id) [expr !$MOB(_SELECTED:$id)]
		} else {
			set MOB(_SELECTED:$id) 1
		}
		DEBUG 3 "selected $MOB(_SELECTED:$id)"
		RenderSomeone $canvas $id
	} else {
		DEBUG 3 "No key GX:$id found"
	}
	SetSelectionContextMenu
}

proc RemoveFromSelection {id} {
	global MOB canvas
	if {[info exists MOB(_SELECTED:$id)]} {
		set MOB(_SELECTED:$id) 0
		RenderSomeone $canvas $id
	}
	SetSelectionContextMenu
}

proc ClearSelection {} {
	global MOB canvas
	foreach key [array names MOB _SELECTED:*] {
		set id [string range $key 10 end]
		set MOB(_SELECTED:$id) 0
		RenderSomeone $canvas $id
	}
	SetSelectionContextMenu
}

proc GetSelectionList {} {
	global MOB
	set result {}
	foreach key [array names MOB _SELECTED:*] {
		if {$MOB($key)} {
			lappend result [string range $key 10 end]
		}
	}
	return $result
}


#
# The click-and-drag logic works in screen x,y coordinates.
# we need to convert that to an object.
#

proc RefreshMOBs {} {
	global MOB canvas

	DEBUG 3 "RefreshMOBs start ([array names MOB ID:*])"
	foreach key [lsort -command cmp_mob_living [array names MOB ID:*]] {
		set id $MOB($key)
		DEBUG 3 "Rendering $id ($key)"
		RenderSomeone $canvas $id
	}
	DEBUG 3 "RefreshMOBs end"
}

proc ScreenXYToMOBID {w x y} {
	global MOB
	DistributeVars [ScreenXYToGridXY $x $y -exact] gx gy

	DEBUG 3 "Looking for object at $x,$y (grid $gx,$gy)..."
	set mob_list {}
	foreach key [array names MOB ID:*] {
		set id $MOB($key)
		set msz [expr max(1, [MonsterSizeValue $MOB(SIZE:$id)])]
		set mx0 [expr int($MOB(GX:$id))]
		set mx1 [expr $mx0 + $msz]
		set my0 [expr int($MOB(GY:$id))]
		set my1 [expr $my0 + $msz]
		if {$mx0 <= $gx && $gx < $mx1 && $my0 <= $gy && $gy < $my1} {
			DEBUG 3 "...found $id ($MOB(NAME:$id))"
			lappend mob_list $id
		}
		DEBUG 3 "... $id ($MOB(NAME:$id)) is at ($gx,$gy)"
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
	global canvas iscale MOB_MOVING MOB

	if {$args ne {-exact} && $MOB_MOVING ne {}} {
		DEBUG 3 "ScreenXYToGridXY $x $y $args for MOB $MOB_MOVING"
		set mob_size [MonsterSizeValue $MOB(SIZE:$MOB_MOVING)]
		DEBUG 3 "--size $mob_size"
		if {$mob_size < 1} {
			DEBUG 3 "-- calc as [list [expr int([$canvas canvasx $x]/($iscale*$mob_size))*$mob_size] [expr int([$canvas canvasy $y]/($iscale*$mob_size))*$mob_size]]"
			return [list [expr int([$canvas canvasx $x]/($iscale*$mob_size))*$mob_size] [expr int([$canvas canvasy $y]/($iscale*$mob_size))*$mob_size]]
		}
	}

	return [list [expr int(([$canvas canvasx $x])/$iscale)] \
		[expr int(([$canvas canvasy $y])/$iscale)]]
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
	global OBJ OBJ_MOVING OBJ_MOVING_SELECTED ClockDisplay
	if [info exists OBJ(X:$id)] {
		set OBJ_MOVING [list $id [$w coords obj$id]]
		set OBJ_MOVING_SELECTED {}
		set ClockDisplay $OBJ_MOVING
	}
}

proc MoveObjDrag {w x y} {
	global OBJ OBJ_MOVING
	if {$OBJ_MOVING ne {}} {
		DistributeVars $OBJ_MOVING id old_coords
		set cx [SnapCoord [$w canvasx $x]]
		set cy [SnapCoord [$w canvasy $y]]
		set dx [expr $cx - $OBJ(X:$id)]
		set dy [expr $cy - $OBJ(Y:$id)]
		set new_coords {}
		foreach {xx yy} $old_coords {
			lappend new_coords [expr $xx + $dx] [expr $yy + $dy]
		}
		$w coords obj$id $new_coords
		DEBUG 3 "MoveObjDrag $w $x $y for object $id: dx=$dx, dy=$dy; $old_coords -> $new_coords"
	}
}

proc MoveObjEndDrag {w} {
	global OBJ OBJ_MOVING ClockDisplay MO_disp
	set ClockDisplay $MO_disp
	if {$OBJ_MOVING ne {}} {
		DistributeVars $OBJ_MOVING id
		set obj_coords [$w coords obj$id]
		set OBJ(X:$id) [lindex $obj_coords 0]
		set OBJ(Y:$id) [lindex $obj_coords 1]
		set OBJ(POINTS:$id) [lrange $obj_coords 2 end]
		SendObjChanges $id {X Y POINTS}
		set OBJ_MOVING {}
	}
}


menu .movemobmenu -tearoff 0
set MOB_DISAMBIG {}
set MOB_MOVING {}
proc MOB_StartDrag {w x y} {
	global MOB_MOVING MOB_DISAMBIG MOB DistanceLabelText MOB_StartGxGy MOB_TrackXY
	set MOB_MOVING [ScreenXYToMOBID $w $x $y]
	if {[llength $MOB_MOVING] > 1} {
		if {$MOB_DISAMBIG ne {}} {
			set MOB_MOVING $MOB_DISAMBIG
			set MOB_DISAMBIG {}
		} else {
			.movemobmenu delete 0 end
			foreach mob_id $MOB_MOVING {
				.movemobmenu add command -command "set MOB_DISAMBIG $mob_id" -label "Move $MOB(NAME:$mob_id)"
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
		set MOB_StartGxGy [list $MOB(GX:$MOB_MOVING) $MOB(GY:$MOB_MOVING)]
		set MOB_TrackXY [list $cx $cy $cx $cy]
		bind $w <B1-Motion> "MOB_Drag $w %x %y"
	} else {
		# no mobs being dragged? scroll the canvas instead
		$w scan mark $x $y
		bind $w <B1-Motion> "$w scan dragto %x %y 1; battleGridLabels"
	}
}

proc MOB_SelectEvent {w x y} {
	global MOB_DISAMBIG MOB
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
			if {[info exists MOB(_SELECTED:$mob_id)] && $MOB(_SELECTED:$mob_id)} {
				set label "Deselect $MOB(NAME:$mob_id)"
			} else {
				set label "Select $MOB(NAME:$mob_id)"
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
	global MOB

	if {$MOB(GX:$mob_id) != [lindex $grid_xy 0]
	||  $MOB(GY:$mob_id) != [lindex $grid_xy 1]} {
		return [list [expr [lindex $grid_xy 0] - $MOB(GX:$mob_id)] [expr [lindex $grid_xy 1] - $MOB(GY:$mob_id)]]
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
	global MOB MOB_MOVING DistanceLabelText MOB_StartGxGy MOB_TrackXY

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
		if {$MOB(GX:$MOB_MOVING) != [lindex $gridxy 0]
		||  $MOB(GY:$MOB_MOVING) != [lindex $gridxy 1]} {
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
						MoveSomeone $w $other_mob [expr $MOB(GX:$other_mob) + [lindex $delta_xy 0]] [expr $MOB(GY:$other_mob) + [lindex $delta_xy 1]]
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
			SendMobChanges $mob_id {GX GY}
		}
		SendMobChanges $MOB_MOVING {GX GY}
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
	global MOB

	if {[llength $mob_id] != 1} { 
		return 0 ; # not just one target, so no.
	}
	if {[info exists MOB($attr:$mob_id)]} {
		if {$MOB($attr:$mob_id) == $value} {
			return 1
		}
	}
	return 0
}

#
# Is the current value of the mob's attribute one of the values in the list <value>?
#
proc MobStateList {mob_id attr value} {
	global MOB

	if {[llength $mob_id] != 1} { 
		return 0 ; # not just one target, so no.
	}
	if {[info exists MOB($attr:$mob_id)]} {
		if {[lsearch -exact $value $MOB($attr:$mob_id)] >= 0} {
			return 1
		}
	}
	return 0
}

#
# Does the value of the mob's attribute (which is a list) contain <value> as an element?
#
proc MobStateFlag {mob_id attr value} {
	global MOB

	if {[llength $mob_id] != 1} { 
		return 0 ; # not just one target, so no.
	}
	if {[info exists MOB($attr:$mob_id)]} {
		if {[lsearch -exact $MOB($attr:$mob_id) $value] >= 0} {
			return 1
		}
	}
	return 0
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
		if [MobState $mob_list MOVEMODE $value] {
			$mid add command -command [list $cmd $mob_list $value] -label $label -foreground #ff0000
		} else {
			$mid add command -command [list $cmd $mob_list $value] -label $label
		}
	}
	return $mid
}

proc MovementModePerson {mob_id movemode} {
	global MOB canvas
	set MOB(MOVEMODE:$mob_id) $movemode
	RenderSomeone $canvas $mob_id
	SendMobChanges $mob_id {MOVEMODE}
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
		if [MobState $mob_list ELEV $value] {
			$mid add command -command [list $cmd $mob_list $value] -label $label -foreground #ff0000
		} else {
			$mid add command -command [list $cmd $mob_list $value] -label $label
		}
	}
	$mid add command -command [list $ncmd $mob_list] -label (Set)
	return $mid
}

proc ElevatePerson {mob_id elev} {
	global MOB canvas
	if {[regexp {^[+\-]} $elev] } {
		catch {set MOB(ELEV:$mob_id) [expr $MOB(ELEV:$mob_id) + $elev]}
	} else {
		set MOB(ELEV:$mob_id) $elev
	}
	RenderSomeone $canvas $mob_id
	SendMobChanges $mob_id {ELEV}
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
	global MOB OBJ
	if {[set idlist [ResolveObjectId_OA $id]] eq {}} {
		return 0
	}
	DistributeVars $idlist a id
	if {$value eq {__clear__}} {
		DEBUG 4 "Clearing $id.$key completely (in $a)"
		set ${a}($key:$id) {}
		return -1
	}
	DEBUG 4 "Toggling value $value in object $id.$key (in $a)"
	if {![info exists ${a}($key:$id)]} {
		set ${a}($key:$id) [list $value]
		DEBUG 4 "Trivially added; was no attribute before"
		return 1
	}
	if {[set index [lsearch -exact [set ${a}($key:$id)] $value]] >= 0} {
		set ${a}($key:$id) [lreplace [set ${a}($key:$id)] $index $index]
		DEBUG 4 "Removed attribute; now [set ${a}($key:$id)]"
		return -1
	} else {
		lappend ${a}($key:$id) $value
		DEBUG 4 "Added attribute; now [set ${a}($key:$id)]"
		return 1
	}
}
	

proc CondPerson {mob_id condition} {
	global MOB canvas

	if {[ToggleObjectAttribute $mob_id STATUSLIST $condition] != 0} {
		RenderSomeone $canvas $mob_id
		SendMobChanges $mob_id {STATUSLIST}
	}
}

proc CondAll {mob_list condition} {
	foreach mob $mob_list {
		CondPerson $mob $condition
	}
}

proc CreateConditionSubMenu {args} {
	global MarkerShape MarkerColor

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
	foreach condition [lsort [array names MarkerShape]] {
		if {[info exists MarkerColor($condition)] && $MarkerColor($condition) ne {} && $MarkerShape($condition) ne {}} {
			if {[MobStateFlag $mob_list STATUSLIST $condition]} {
				$mid add command -command [list $cmd $mob_list $condition] -label $condition -foreground #ff0000
			} else {
				$mid add command -command [list $cmd $mob_list $condition] -label $condition
			}
		}
	}
	$mid add command -command [list $cmd $mob_list __clear__] -label "(clear all)"
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
		if {[MobState $mob_list NOTE $tag]} {
			$mid add command -command [list $cmd $mob_list $tag] -label $tag -foreground #ff0000
		} else {
			$mid add command -command [list $cmd $mob_list $tag] -label $tag
		}
	}
	#dumpMenu $mid
	return $mid
}

proc TagPerson {mob_id tag} {
	global MOB TagHistory canvas
	set MOB(NOTE:$mob_id) $tag
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
	SendMobChanges $mob_id {NOTE}
}

proc TagAll {mob_list tag} {
	foreach mob $mob_list {
		TagPerson $mob $tag
	}
}

proc CreatePolySubMenu {args} {
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
	#
	# Find the maximum number of skins for the monster(s) we're dealing with here
	#
	set max_skin 0
	foreach mi $mob_list {
		if {[info exists MOB(SKINSIZE:$mi)]} {
			set max_skin [expr max($max_skin, [llength $MOB(SKINSIZE:$mi)])]
		} else {
			set max_skin [expr max($max_skin, 4)]
		}
	}

	for {set i 0} {$i < $max_skin} {incr i} {
		if {[MobState $mob_list SKIN $i]} {
			$mid add command -command [list $cmd $mob_list $i] -label [expr $i==0 ? {{Base}} : "{# $i}"] -foreground #ff0000
		} else {
			$mid add command -command [list $cmd $mob_list $i] -label [expr $i==0 ? {{Base}} : "{# $i}"]
		}
	}
	return $mid
}

proc CreateSizeSubMenu {args} {
	if {[lindex $args 0] == {-mass}} {
		set mob_id __mass__
		set mob_list [lindex $args 1]
		set cmd ChangeSizeAll
		set sub size.m_
	} else {
		set sub [expr [string equal [lindex $args 0] {-deep}] ? {{size.m_}} : {{size_m_}}]
		set mob_list [set mob_id [lindex $args 1]]
		set cmd ChangeSize
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
		h {Huge (long)}
		H {Huge (tall)}
		g {Gargantuan (long)}
		G {Gargantuan (tall)}
		c {Colossal (long)}
		C {Colossal (tall)}
	} {
		if {[MobStateList $mob_list SIZE $size_code]} {
			$mid add command -command [list $cmd $mob_list [lindex $size_code 0]] -label $size_name -foreground #ff0000
		} else {
			$mid add command -command [list $cmd $mob_list [lindex $size_code 0]] -label $size_name
		}
	}
	return $mid
}

proc DoContext {x y} {
	global MOB_X MOB_Y canvas MOB
	set MOB_X $x
	set MOB_Y $y

	set mob_list [lsort -unique -command MobNameComparison [concat [ScreenXYToMOBID $canvas $x $y] [GetSelectionList]]]
	DEBUG 3 "DoContext mob_list $mob_list from [ScreenXYToMOBID $canvas $x $y] + [GetSelectionList]"

	if {[llength $mob_list] == 0} {
		.contextMenu delete 0
		.contextMenu insert 0 command -command "" -label "Remove" -state disabled
		.contextMenu delete 3
		.contextMenu insert 3 command -command "" -label "Toggle Death" -state disabled
		.contextMenu delete 4
		.contextMenu insert 4 command -command "" -label "Cycle Reach" -state disabled
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
	} elseif {[llength $mob_list] == 1} {
		set mob_id [lindex $mob_list 0]
		.contextMenu delete 0
		.contextMenu insert 0 command -command "RemovePerson $mob_id; ITsend \[list CLR $mob_id\]" -label "Remove $MOB(NAME:$mob_id)"
		.contextMenu delete 3
		.contextMenu insert 3 command -command "KillPerson $mob_id" -label "Toggle Death for $MOB(NAME:$mob_id)"
		.contextMenu delete 4
		.contextMenu insert 4 command -command "ToggleReach $mob_id" -label "Cycle Reach for $MOB(NAME:$mob_id)"
		.contextMenu delete 5
		.contextMenu insert 5 command -command "ToggleSpellArea $mob_id" -label "Toggle Spell Area for $MOB(NAME:$mob_id)"
		.contextMenu delete 6
		.contextMenu insert 6 cascade -menu [CreatePolySubMenu -shallow $mob_id] -label "Polymorph $MOB(NAME:$mob_id)"
		.contextMenu delete 7
		.contextMenu insert 7 cascade -menu [CreateSizeSubMenu -shallow $mob_id] -label "Change Size of $MOB(NAME:$mob_id)"
		.contextMenu delete 8
		.contextMenu insert 8 cascade -menu [CreateConditionSubMenu -shallow $mob_id] -label "Toggle Condition for $MOB(NAME:$mob_id)"
		.contextMenu delete 9
		.contextMenu insert 9 cascade -menu [CreateTagSubMenu -shallow $mob_id] -label "Tag $MOB(NAME:$mob_id)"
		.contextMenu delete 10
		.contextMenu insert 10 cascade -menu [CreateElevationSubMenu -shallow $mob_id] -label "Set Elevation for $MOB(NAME:$mob_id)"
		.contextMenu delete 11
		.contextMenu insert 11 cascade -menu [CreateMovementModeSubMenu -shallow $mob_id] -label "Set Movement Mode for $MOB(NAME:$mob_id)"
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
		foreach mob_id $mob_list {
			.contextMenu.del add command -command "RemovePerson $mob_id; ITsend \[list CLR $mob_id\]" -label $MOB(NAME:$mob_id)
			.contextMenu.kill add command -command "KillPerson $mob_id" -label $MOB(NAME:$mob_id)
			.contextMenu.reach add command -command "ToggleReach $mob_id" -label $MOB(NAME:$mob_id)
			.contextMenu.aoe add command -command "ToggleSpellArea $mob_id" -label $MOB(NAME:$mob_id)
			.contextMenu.poly add cascade -menu [CreatePolySubMenu -deep $mob_id] -label $MOB(NAME:$mob_id)
			.contextMenu.size add cascade -menu [CreateSizeSubMenu -deep $mob_id] -label $MOB(NAME:$mob_id)
			.contextMenu.cond add cascade -menu [CreateConditionSubMenu -deep $mob_id] -label $MOB(NAME:$mob_id)
			.contextMenu.tag add cascade -menu [CreateTagSubMenu -deep $mob_id] -label $MOB(NAME:$mob_id)
			.contextMenu.elev add cascade -menu [CreateElevationSubMenu -deep $mob_id] -label $MOB(NAME:$mob_id)
			.contextMenu.mmode add cascade -menu [CreateMovementModeSubMenu -deep $mob_id] -label $MOB(NAME:$mob_id)
		}
		.contextMenu.del add command -command "RemoveAll $mob_list" -label "(all of the above)"
		.contextMenu.kill add command -command "KillAll $mob_list" -label "(all of the above)"
		.contextMenu.poly add cascade -menu [CreatePolySubMenu -mass $mob_list] -label "(all of the above)"
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
		.contextMenu insert 4 cascade -menu .contextMenu.reach -label "Cycle Reach"
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
	}

	set wx [expr [winfo rootx $canvas] + $x]
	set wy [expr [winfo rooty $canvas] + $y]
	DEBUG 3 "popup ($x,$y) -> ($wx,$wy)"
	tk_popup .contextMenu $wx $wy
}

proc MobNameComparison {a b} {
	global MOB
	return [string compare -nocase $MOB(NAME:$a) $MOB(NAME:$b)]
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
#menu .addPlayerMenu
.contextMenu add command -command "" -label Remove -state disabled							;# 0
.contextMenu add command -command {AddPlayerMenu player} -label {Add Player...}				;# 1
.contextMenu add command -command {AddPlayerMenu monster} -label {Add Monster...}			;# 2
.contextMenu add command -command "" -label {Toggle Death} -state disabled					;# 3
.contextMenu add command -command "" -label {Cycle Reach} -state disabled					;# 4
.contextMenu add command -command "" -label {Toggle Spell Area} -state disabled				;# 5
.contextMenu add command -command "" -label {Polymorph} -state disabled						;# 6
.contextMenu add command -command "" -label {Change Size} -state disabled					;# 7
.contextMenu add command -command "" -label {Toggle Condition} -state disabled				;# 8 
.contextMenu add command -command "" -label {Tag} -state disabled							;# 9 
.contextMenu add command -command "" -label {Elevation} -state disabled						;# 10
.contextMenu add command -command "" -label {Movement Mode} -state disabled					;# 11
.contextMenu add separator																	;# 12
.contextMenu add command -command "ClearSelection" -label {Deselect All} -state disabled	;# 13
.contextMenu add command -command "FindNearby" -label {Scroll to Visible Objects}			;# 14
.contextMenu add command -command "SyncView" -label {Scroll Others' Views to Match Mine}	;# 15
.contextMenu add command -command "refreshScreen" -label {Refresh Display}					;# 16
.contextMenu add command -command "aboutMapper" -label {About Mapper...}					;# 17
.contextMenu add separator																	;# 18

# AddPlayer name color ?area? ?size? ?id?  defaults to 1x1, generated ID
proc AddPlayer {name color args} {
	global MOB_X MOB_Y canvas

	set g [ScreenXYToGridXY $MOB_X $MOB_Y]
	if {[llength $args] > 0} { set area [lindex $args 0] } else { set area 1 }
	if {[llength $args] > 1} { set size [lindex $args 1] } else { set size 1 }
	if {[llength $args] > 2} { set id   [lindex $args 2] } else { set id [new_id] }
	# XXX check for existing player
	DEBUG 3 "PlaceSomeone $canvas [lindex $g 0] [lindex $g 1] $color $name $area $size $id 0"
	PlaceSomeone $canvas [lindex $g 0] [lindex $g 1] $color $name $area $size player $id 0
	ITsend [list PS $id $color $name $area $size player [lindex $g 0] [lindex $g 1] 0]
}

set MOB_Name {}
set MOB_SIZE M
set MOB_AREA M
set MOB_COLOR red
set MOB_REACH 0

proc AddElevationMenu {mob_id} {
	global NewElevationText
	set NewElevationText {}
	if {[::getstring::tk_getString .atm NewElevationText {Elevation:}]} {
		ElevatePerson $mob_id $NewElevationText
	}
}

proc AddElevationMenuAll {mob_list} {
	global NewElevationText
	set NewElevationText {}
	if {[::getstring::tk_getString .atm NewElevationText {Elevation:}]} {
		foreach person $mob_list {
			ElevatePerson $person $NewElevationText
		}
	}
}

proc AddTagMenu {mob_id} {
	global NewTagText
	set NewTagText {}
	if {[::getstring::tk_getString .atm NewTagText {Tag:}]} {
		TagPerson $mob_id $NewTagText
	}
}

proc AddTagMenuAll {mob_list} {
	global NewTagText
	set NewTagText {}
	if {[::getstring::tk_getString .atm NewTagText {Tag:}]} {
		foreach person $mob_list {
			TagPerson $person $NewTagText
		}
	}
}

# tile_id is {} if none set or  {name:zoom tilename zoom}
proc SetTilePlaceHolder {obj_id width height tile_id} {
	# Declare a placeholder for an image we don't have yet.
	global OBJ TILE_ATTR
	set TILE_ATTR(BBWIDTH:$tile_id) $width
	set TILE_ATTR(BBHEIGHT:$tile_id) $height
	set OBJ(_TILEID:$obj_id) $tile_id
	RefreshGrid 0
}

proc AddPlayerMenu {type} {
	global MOB_X MOB_Y canvas check_select_color
	global MOB_Name MOB_SIZE MOB_AREA MOB_COLOR MOB_REACH

	#catch {destroy .apm}

	switch -exact -- $type {
		player  { set MOB_COLOR green }
		monster { set MOB_COLOR red   }
	}

	set g [ScreenXYToGridXY $MOB_X $MOB_Y]
	#toplevel .apm -class dialog
	create_dialog .apm
	wm title .apm "Add Player or Monster"
	pack [frame .apm.1] \
	     [frame .apm.2] \
		 [frame .apm.3] \
		 [frame .apm.4] \
		 [frame .apm.5] \
		 [frame .apm.6] \
		 -side top
	pack [label .apm.1.lab -text {Name:}] \
	     [entry .apm.1.ent -textvariable MOB_Name -width 20] \
		 -side left -anchor w
	pack [label .apm.2.lab -text {Size:}] \
		 [entry .apm.2.ent -textvariable MOB_SIZE -width 3 -validate key -validatecommand {set MOB_AREA "%P"; return 1}] \
		 -side left -anchor w
	pack [label .apm.3.lab -text {Area:}] \
		 [entry .apm.3.ent -textvariable MOB_AREA -width 3] \
		 -side left -anchor w
	pack [label .apm.4.lab -text {Color:}] \
		 [entry .apm.4.ent -textvariable MOB_COLOR -width 20] \
		 -side left -anchor w
	pack [checkbutton .apm.5.ent -text "Reach?" -variable MOB_REACH -selectcolor $check_select_color] \
		 -side left -anchor w
	pack [button .apm.6.apply -command \
		"AddMobFromMenu [lindex $g 0] [lindex $g 1] \$MOB_COLOR \$MOB_Name \$MOB_AREA \$MOB_SIZE $type \$MOB_REACH" -text Apply] \
	     [button .apm.6.cancel -command "destroy .apm" -text Cancel] \
	     [button .apm.6.ok -command \
		 "AddMobFromMenu [lindex $g 0] [lindex $g 1] \$MOB_COLOR \$MOB_Name \$MOB_AREA \$MOB_SIZE $type \$MOB_REACH; destroy .apm" -text Ok] \
		 -side right
}

proc ValidateSizeCode {code} {
	#
	# return true if code is valid
	#
	if {[string is integer -strict $code]} {return 1}
	if {$code eq {m20} || $code eq {M20}} {return 1}
	if {$code eq {l0} || $code eq {L0}} {return 1}
	if {[string length $code] != 1} {return 0}
	if {[string first $code FDTSMLHGCfdtsmlhgc] < 0} {return 0}
	return 1
}

proc AddMobFromMenu {baseX baseY color name area size type reach} {
	global canvas
	global PC_IDs

	if {![ValidateSizeCode $area]} {
		say "Area value $area is not valid.  Specify number of squares or type code (upper-case for tall)."
		return
	}
	if {![ValidateSizeCode $size]} {
		say "Size value $size is not valid.  Specify number of squares or type code (upper-case for tall)."
		return
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
			PlaceSomeone $canvas [expr $baseX+$XX] $baseY $color [AcceptCreatureImageName "${basename}#$i"] $area $size $type $apm_id $reach
			ITsend [list PS $apm_id $color "${basename}#$i" $area $size $type [expr $baseX+$XX] $baseY $reach]
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
		PlaceSomeone $canvas $baseX $baseY $color $basename $area $size $type $apm_id $reach
		ITsend [list PS $apm_id $color $name $area $size $type $baseX $baseY $reach]
	}
}

proc RemovePerson id {
	global canvas MOB

	DEBUG 3 "RemovePerson $id"
	$canvas delete M#$id
	unset MOB(ID:$MOB(NAME:$id))
	foreach key [array names MOB *:$id] {
		unset MOB($key)
	}
	catch {
		destroy $canvas.ms$id
		destroy $canvas.z$id
	}
	#error "RemovePerson called!"
}

proc KillAll args {
	foreach mob $args {
		KillPerson $mob
	}
}

proc RemoveAll args {
	foreach mob $args {
		RemovePerson $mob
		ITsend [list CLR $mob]
	}
}

proc KillPerson id {
	global canvas MOB

	set MOB(KILLED:$id) [expr !$MOB(KILLED:$id)]
	RenderSomeone $canvas $id
	SendMobChanges $id KILLED	
}

proc PolymorphPerson {id skin} {
	global MOB canvas
	set MOB(SKIN:$id) $skin
	if {[info exists MOB(SKINSIZE:$id)]} {
		if {[llength $MOB(SKINSIZE:$id)] > $skin} {
			ChangeSize $id [lindex $MOB(SKINSIZE:$id) $skin]
		}
	}
			
	RenderSomeone $canvas $id
	SendMobChanges $id SKIN
}

proc PolymorphMass {mob_list skin} {
	foreach mob $mob_list {
		PolymorphPerson $mob $skin
	}
}

proc ChangeSize {id code} {
	global MOB canvas
	set MOB(SIZE:$id) $code
	set MOB(AREA:$id) $code
	RenderSomeone $canvas $id
	SendMobChanges $id {SIZE AREA}
}

proc ChangeSizeAll {mob_list code} {
	foreach mob $mob_list {
		ChangeSize $mob $code
	}
}
#
# if a mob has a spell area highlighted, kill it.
# otherwise, set it now
#
proc ToggleSpellArea id {
	global MOB canvas

	if {[info exists MOB(AOE:$id)] && [llength $MOB(AOE:$id)] > 0} {
		set MOB(AOE:$id) {}
		RenderSomeone $canvas $id
		SendMobChanges $id AOE
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
	SendMobChanges $id AOE
}

proc DragMOBAoE {id w x y} {
	global MOB iscale OBJ_COLOR

	set xx [SnapCoordAlways [$w canvasx $x]]
	set yy [SnapCoordAlways [$w canvasy $y]]
	set gx [CanvasToGrid $xx]
	set gy [CanvasToGrid $yy]
	set r  [GridDistance $MOB(GX:$id) $MOB(GY:$id) $gx $gy]
	set MOB(AOE:$id) [list radius $r $OBJ_COLOR(fill)]
	#DEBUG 1 "Setting MOB $id AoE ($MOB(GX:$id),$MOB(GY:$id))-($gx,$gy)=$r"
	RenderSomeone $w $id
	$w create line [expr $MOB(GX:$id) * $iscale] [expr $MOB(GY:$id) * $iscale] [expr $gx * $iscale] [expr $gy * $iscale] \
		-fill black -width 3 -dash - -arrow last -tags [list M#$id AoElocator#$id]
}

proc ToggleReach id {
	global canvas MOB
	if {[info exists MOB(REACH:$id)]} {
		set MOB(REACH:$id) [expr ($MOB(REACH:$id) + 1) % 3]
	} else {
		set MOB(REACH:$id) 1
	}
	RenderSomeone $canvas $id
	SendMobChanges $id REACH
}

proc clearplayers {pattern} {
	global MOB
	foreach nkey [array names MOB NAME:*] {
		set id [string range $nkey 5 end]
		if [string match $pattern $MOB(TYPE:$id)] {
			RemovePerson $id
		}
	}
}

#proc RemoveSomeone {canvas id} {
	#global canvas
	#global MOB_X MOB_Y MOB
	#if {[set id [ScreenXYToMOBID $canvas $MOB_X $MOB_Y]] ne {}} {
	#RemovePerson $id
	#}
#}

#proc ToggleKillState {} {
#	global canvas
#	global MOB_X MOB_Y MOB
#	if {[set id [ScreenXYToMOBID $canvas $MOB_X $MOB_Y]] ne {}} {
#		KillPerson $id
#	}
#}

set KillObjID 0
set KillObjIdx 0
proc KillObjAdvance n {
	global KillObjID KillObjIdx canvas OBJ_BLINK OBJ
	DEBUG 3 "BEGIN KillObjAdvance $n"

	set display_list [lsort -integer -command cmp_obj_attr [array names OBJ Z:*]]
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
		set KillObjID [string range [lindex $display_list $KillObjIdx] 2 end]
		if {[info exists OBJ(LOCKED:$KillObjID)] && $OBJ(LOCKED:$KillObjID) != 0} {
			DEBUG 3 "Element #$KillObjIdx ($KillObjID) is locked; skipping"
			continue
		}

		DEBUG 3 "Element #$KillObjIdx is $KillObjID"
		if {[info exists OBJ(X:$KillObjID)]} {
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

#
# Initiative order change
#
#set MobTurnID 0
#proc MobTurnAdvance n {
#	global MobTurnID NextMOBID MOB canvas MOB_BLINK
#
#	if {$NextMOBID <= 0} return
#	set k 0
#	while {$k < 2} {
#		incr MobTurnID $n
#		if {$MobTurnID < 0} {
#			incr k
#			set MobTurnID [expr $NextMOBID]
#		} elseif {$MobTurnID > $NextMOBID} {
#			incr k
#			set MobTurnID 0
#		}
#		if {$MobTurnID == 0} {
#			highlightMob $canvas [list $MobTurnID]
#		#	set MOB_BLINK {}
#			return
#		}
#		if {[info exists MOB(NAME:$MobTurnID)] && !$MOB(KILLED:$MobTurnID)} {
#		#	set MOB_BLINK [list $MobTurnID]
#			highlightMob $canvas [list $MobTurnID]
#			PopSomeoneToFront $canvas $MobTurnID
#			#blinkMob $canvas $MobTurnID 0
#			return
#		}
#	}
#	set MobTurnID 0
#	hightlightMob $canvas 0
#	DEBUG 3 "MobTurnAdvance $n: giving up!"
#}
			

#
#proc MobTurn {which} {
#	switch $which {
#		prev { MobTurnAdvance -1 }
#		next { MobTurnAdvance  1 }
#	}
#}

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
		ITsend [list CLR $id]
	}
	RemoveObject $id
}


menu .killmultiple -tearoff 0

proc KillObjUnderMouse {w x y} {
	set cx [$w canvasx $x]
	set cy [$w canvasy $y]
	set candidates {}
	global OBJ

	foreach element [$w find overlapping [expr $cx-2] [expr $cy-2] [expr $cx+2] [expr $cy+2]] {
		foreach elementTag [$w gettags $element] {
			if {[string range $elementTag 0 2] eq {obj}} {
				set target_id [string range $elementTag 3 end]
				if {[info exists OBJ(LOCKED:$target_id)] && $OBJ(LOCKED:$target_id) != 0} {
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
		global OBJ
		.killmultiple delete 0 end
		foreach id $candidates {
			DistributeVars [obj_line_fill_width $id] line fill width
			if [info exists OBJ(TEXT:$id)] {
				set desc " \"$OBJ(TEXT:$id)\""
			} elseif [info exists OBJ(IMAGE:$id)] {
				set desc " \"$OBJ(IMAGE:$id)\""
			} else {
				set desc ""
			}
			.killmultiple add command -command "KillObjById $id" -label "Delete $OBJ(TYPE:$id) ($line/$fill)$desc @($OBJ(X:$id),$OBJ(Y:$id),$OBJ(Z:$id); w=$width; \[$OBJ(LAYER:$id)\]"
		}
		tk_popup .killmultiple [expr [winfo rootx $w] + $x] [expr [winfo rooty $w] + $y]
	}
}
	
proc obj_line_fill_width {id} {
	global OBJ
	if [info exists OBJ(LINE:$id)] {
		set line $OBJ(LINE:$id)
	} else {
		set line "no line"
	}
	if [info exists OBJ(FILL:$id)] {
		set fill $OBJ(FILL:$id)
	} else {
		set fill "no fill"
	}
	if [info exists OBJ(WIDTH:$id)] {
		set width $OBJ(WIDTH:$id)
	} else {
		set width "no width"
	}
	return [list $line $fill $width]
}

set MO_disp {}
set MO_last_obj {}
proc NudgeObject {w dx dy} {
	global MO_last_obj ClockDisplay
	global OBJ
	DEBUG 3 "NudgeObject w=$w dx=$dx dy=$dy obj=$MO_last_obj"
	if {$MO_last_obj eq {}} {
		set ClockDisplay "No current object to move; move one with mouse first"
		return
	}
	if [info exists OBJ(X:$MO_last_obj)] {
		set OBJ(X:$MO_last_obj) [expr $OBJ(X:$MO_last_obj) + $dx]
		set OBJ(Y:$MO_last_obj) [expr $OBJ(Y:$MO_last_obj) + $dy]
		set new_coords {}
		foreach {xx yy} [$w coords obj$MO_last_obj] {
			lappend new_coords [expr $xx + $dx] [expr $yy + $dy]
		}
		$w coords obj$MO_last_obj $new_coords
		set OBJ(POINTS:$MO_last_obj) [lrange $new_coords 2 end]
		SendObjChanges $MO_last_obj {X Y POINTS}
	} else {
		set ClockDisplay "Object $MO_last_obj does not exist anymore"
	}
}

proc NudgeObjectZ {w adj} {
	global MO_last_obj ClockDisplay
	global OBJ
	DEBUG 3 "NudgeObjectZ w=$w adj=$adj obj=$MO_last_obj"
	if {$MO_last_obj eq {}} {
		set ClockDisplay "No current object to move; move one with mouse first"
		return
	}
	DEBUG 4 "NudgeObjectZ sampling object collection Z range"
	set max_z nil
	set min_z nil
	foreach ok [array names OBJ Z:*] {
		DEBUG 5 "-- $ok Z=$OBJ($ok)"
		if {$max_z eq {nil}} {
			set min_z [set max_z $OBJ($ok)]
		} else {
			if {$max_z == $OBJ($ok)} {
				# We're not the only object at this coordinate so to be at max we'd have to be one past that
				set max_z [expr $OBJ($ok) + 1]
			} elseif {$max_z < $OBJ($ok)} {
				set max_z $OBJ($ok)
			}
			if {$min_z == $OBJ($ok)} {
				# We're not the only object at this coordinate so to be at max we'd have to be one past that
				set min_z [expr $OBJ($ok) - 1]
			} elseif {$min_z > $OBJ($ok)} {
				set min_z $OBJ($ok)
			}
		}
	}
	DEBUG 4 "- Range is $min_z - $max_z"
	if {$min_z eq {nil}} {set min_z 0}
	if {$max_z eq {nil}} {set max_z 0}

	if [info exists OBJ(Z:$MO_last_obj)] {
		set z $OBJ(Z:$MO_last_obj)
		switch -exact -- $adj {
			up { 
				if {$z >= $max_z} {
					set ClockDisplay "Object $MO_last_obj already top-most on display"
					return
				}
				set OBJ(Z:$MO_last_obj) [expr $z + 1] 
			}
			down {
				if {$z <= $min_z} {
					set ClockDisplay "Object $MO_last_obj already bottom-most on display"
					return
				}
				set OBJ(Z:$MO_last_obj) [expr $z - 1] 
			}
			front {
				if {$z >= $max_z} {
					set ClockDisplay "Object $MO_last_obj already top-most on display"
					return
				}
				set OBJ(Z:$MO_last_obj) [expr $max_z + 1]
			}
			back {
				if {$z <= $min_z} {
					set ClockDisplay "Object $MO_last_obj already bottom-most on display"
					return
				}
				set OBJ(Z:$MO_last_obj) [expr $min_z - 1]
			}
			default {
				DEBUG 0 "NudgeObjectZ $w $adj makes no sense"
				return
			}
		}

		refreshScreen
		set ClockDisplay "Object $MO_last_obj new Z=$OBJ(Z:$MO_last_obj)"
		SendObjChanges $MO_last_obj {Z}
	} else {
		set ClockDisplay "Object $MO_last_obj does not exist anymore"
	}
}

proc MoveObjUnderMouse {w x y} {
	set cx [$w canvasx $x]
	set cy [$w canvasy $y]
	set candidates {}
	global ClockDisplay MO_disp MO_last_obj OBJ
	set MO_disp $ClockDisplay

	foreach element [$w find overlapping [expr $cx-2] [expr $cy-2] [expr $cx+2] [expr $cy+2]] {
		foreach elementTag [$w gettags $element] {
			if {[string range $elementTag 0 2] eq {obj}} {
				set target_id [string range $elementTag 3 end]
				if {[info exists OBJ(LOCKED:$target_id)] && $OBJ(LOCKED:$target_id) != 0} {
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
		global OBJ
		global OBJ_MOVING_SELECTED

		if {$OBJ_MOVING_SELECTED ne {}} {
			set MO_last_obj $OBJ_MOVING_SELECTED
			MoveObjById $w $OBJ_MOVING_SELECTED
		} else {
			.killmultiple delete 0 end
			foreach id $candidates {
				DistributeVars [obj_line_fill_width $id] line fill width
				.killmultiple add command -command "set OBJ_MOVING_SELECTED $id" -label "Move $OBJ(TYPE:$id) ($line/$fill) @($OBJ(X:$id),$OBJ(Y:$id),$OBJ(Z:$id); w=$width; \[$OBJ(LAYER:$id)\]"
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
	global OBJ_BLINK OBJ

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
		catch {$w itemconfigure obj$t -outline $OBJ(LINE:$t)}
		catch {$w itemconfigure obj$t -fill $OBJ(FILL:$t)}
	}
}

# hightlightMob canvasname mob_id_list_or_empty_for_none
proc highlightMob {w id} {
	global MOB MOB_BLINK NextMOBID

	set MOB_BLINK $id

	set objectlist {}
	foreach obj [array names MOB NAME:*] {
		set obj_id [string range $obj 5 end]

		if {!$MOB(KILLED:$obj_id)} {
			if {[llength $id] == 0 || [lsearch -exact $id $obj_id] < 0} {
				# either we're setting everyone to normal, or
				# this is not highlighted person anyway
				set MOB(DIM:$obj_id) 1
				$w itemconfigure MC#$obj_id -outline $MOB(COLOR:$obj_id)
				$w delete MH#$obj_id
			} else {
				# this is the person
				set MOB(DIM:$obj_id) 0
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
	global MOB_BLINK MOB

	if {$MOB_BLINK ne {} && $MOB_BLINK eq $t} {
		switch $s {
			0 { set fillcolor #0000ff }
			1 { set fillcolor #00ff00 }
		}

		catch {
			foreach tt $t {
				$w itemconfigure MC#$tt -outline $fillcolor
#				$w itemconfigure MT#$tt -fill $fillcolor
			}
			after 100 "blinkMob $w [list $t] [expr ($s+1)%2]"
		}
	} else {
		catch {
			foreach tt $t {
				if $MOB(DIM:$tt) {
					$w itemconfigure MC#$tt -outline $MOB(COLOR:$tt)
#					$w itemconfigure MT#$tt -fill black
				} else {
					$w itemconfigure MC#$tt -outline yellow
#					$w itemconfigure MT#$tt -fill black
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
# cache_info filename					-> {exists? age_in_days img_name/map_id zoom}
# load_cached_images					-- loads up all images from the cache unless too old
proc cache_map_id {filename} {
	# generate id from filename
	# as base 64 encoding of md5(base filename without extension) with +->_, /->-, drop =
	global ModuleID
	return [string map {+ _ / - = {}} [::base64::encode [::md5::md5 [concat $ModuleID [file rootname [file tail $filename]]]]]]
}
	


proc fetch_map_file {id} {
	global ClockDisplay
	global CURLproxy CURLpath CURLserver
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
	if [lindex $cache_stats 0] {
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
	if [catch {
		if {$CURLproxy ne {}} {
			DEBUG 3 "Running $CURLpath $CreateOpt --output [file nativename $cache_filename] --proxy $CURLproxy -f -z [clock format $cache_newer_than] $url"
			exec $CURLpath $CreateOpt --output [file nativename $cache_filename] --proxy $CURLproxy -f -z [clock format $cache_newer_than] $url >&@$my_stdout
		} else {
			DEBUG 3 "Running $CURLpath $CreateOpt --output [file nativename $cache_filename] -f -z [clock format $cache_newer_than] $url"
			exec $CURLpath $CreateOpt --output [file nativename $cache_filename] -f -z [clock format $cache_newer_than] $url >&@$my_stdout
		}
		DEBUG 3 "Updating cache file time"
        file mtime [file nativename $cache_filename] [clock seconds]
	} err options] {
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

proc send_file_to_server {id local_file} {
	global SCPserver SCPdest SCPproxy SCPpath SSHpath NCpath SERVER_MKDIRpath
	global my_stdout

	if {$SCPdest eq {} || $SCPserver eq {}} {
		say "No upload server has been configured."
		return
	}

	set destdir "${SCPdest}/[string range $id 0 0]/[string range $id 0 1]"
	set destpath "${SCPserver}:${destdir}/$id.map"

	if [catch {
		set st [file attributes $local_file -permissions]
		if {$st & 0111} {
			say "$local_file has execute permissions. Removing them and setting world read access."
			file attributes $local_file -permissions 0644
		} elseif {($st & 0444) != 0444} {
			say "$local_file isn't world-readable. Changing that now."
			file attributes $local_file -permissions 0644
		}
	} err] {
		say "Failed to read or update file attributes for $local_file ($err). Proceeding but the transfer operation may fail as a result."
	}

	if [catch {
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
	} err] {
		DEBUG 0 "Error running $SSHpath or $SCPpath for $local_file -> $destdir: $err"
	}
}
		
#
# load an image file from cache or the web server
#
proc fetch_image {name zoom id} {
	global ClockDisplay
	global CURLproxy CURLpath CURLserver
	global cache_too_old_days
	global my_stdout

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
	if [lindex $cache_stats 0] {
		set cache_age [lindex $cache_stats 1]
		DEBUG 3 "Found cache file for this image in $cache_filename, age=$cache_age"
		if {$cache_age < $cache_too_old_days} {
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
	set url "$CURLserver/[string range $id 0 0]/[string range $id 0 1]/$id.gif"
	if [catch {
		if {$CURLproxy ne {}} {
			DEBUG 3 "Running $CURLpath $CreateOpt --output [file nativename $cache_filename] --proxy $CURLproxy -f -z [clock format $cache_newer_than] $url"
			exec $CURLpath $CreateOpt --output [file nativename $cache_filename] --proxy $CURLproxy -f -z [clock format $cache_newer_than] $url >&@$my_stdout
		} else {
			DEBUG 3 "Running $CURLpath $CreateOpt --output [file nativename $cache_filename] -f -z [clock format $cache_newer_than] $url"
			exec $CURLpath $CreateOpt --output [file nativename $cache_filename] -f -z [clock format $cache_newer_than] $url >&@$my_stdout
		}
		DEBUG 3 "Updating cache file time"
        file mtime [file nativename $cache_filename] [clock seconds]
	} err options] {
		set i [dict get $options -errorcode]
		if {[llength $i] >= 3 && [lindex $i 0] eq {CHILDSTATUS} && [lindex $i 2] == 22} {
			DEBUG 0 "Requested image file ID $id was not found on the server."
		} else {
			DEBUG 0 "Error running $CURLpath to get $url into $cache_filename: $err"
		}
	}
	create_image_from_file $tile_id $cache_filename
	set ClockDisplay $oldcd
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


proc UpdateRunClock newtime {
	global MOB_COMBATMODE ClockDisplay
	if {$MOB_COMBATMODE} {
		set ClockDisplay [format "Round #%d  (%02d:%02d:%02d.%d)"\
			[expr [lindex $newtime 0] + 1]\
			[lindex $newtime 4]\
			[lindex $newtime 3]\
			[lindex $newtime 2]\
			[expr [lindex $newtime 1] % 10]\
		]
	} else {
		set ClockDisplay {}
	}
}


set ITpending_auth true
proc ITsend data {
	global ITsock ITbuffer ITpending_auth
	#
	# Test that the data forms a proper TCL list with no embedded
	# newlines and other crap that will cause havoc to the server
	# and our peers.
	#

	if [catch {
		set l [llength $data]
	} err] {
		DEBUG 0 "ITsend: I refuse to send the message \"$data\" to the server: $err"
		return
	}

	if {$l < 1} {
		DEBUG 0 "ITsend: I refuse to send the message \"$data\" to the server: it appears to have no meaningful content."
		return
	}

	if {![string is print $data]} {
		DEBUG 0 "ITsend: I refuse to send the message \"$data\" to the server: it contains invalid characters."
		return
	}

	if {![string is list $data]} {
		DEBUG 0 "ITsend: I refuse to send the message \"$data\" to the server: it is not a properly-formed list string."
		return
	}

    if {$ITpending_auth && [lindex $data 0] != "POLO" && [lindex $data 0] != "AUTH"} {
        DEBUG 1 "ITsend: queueing request \"$data\" until after authentication succeeds"
        lappend ITbuffer "$data"
        return
    }

	if {$ITsock ne {}} {
		if [catch {
            while {$ITbuffer ne {}} {
                puts $ITsock [lindex $ITbuffer 0]
                flush $ITsock
                DEBUG 1 "sent delayed command <[lindex $ITbuffer 0]>"
                set ITbuffer [lreplace $ITbuffer 0 0]
                DEBUG 2 "buffer now $ITbuffer"
            }
			puts $ITsock "$data"
			flush $ITsock
			DEBUG 4 "sent $ITsock <- $data"
		} error] {
			DEBUG 0 "Lost connection to server ($error)."
			DEBUG 0 "Attempting to reconnect..."
			# save our message for later
			catch {close $ITsock}
			set ITsock {}
			lappend ITbuffer "$data"
            DEBUG 1 "Saved $data to outgoing buffer"
            DEBUG 2 "ITsend buffer now $ITbuffer"
			BackgroundConnectToServer 1
		}
	} elseif {$ITbuffer ne {}} {
		# there's no socket but there USED to be, so queue up
		# the message for when we get that connection back again
		# (otherwise if there's never been a socket, we aren't even
		# trying to talk to a server at all, so ignore this request)
		lappend ITbuffer "$data"
		DEBUG 1 "Saved more output ($data) waiting for connection to be reestablished."
        DEBUG 2 "ITsend buffer now $ITbuffer"
	}
}

proc BackgroundConnectToServer {tries} {
	global ITbuffer ITpending_auth

	if [catch {connectToServer} err] {
		DEBUG 0 "Attempt to reconnect failed ($err); continuing to try... $tries"
		after [expr min($tries*1000,10000)] BackgroundConnectToServer [expr $tries + 1]
	} else {
		DEBUG 0 "Connection to server reestablished"
        set ITpending_auth true
		if {$ITbuffer ne {}} {
			set saved $ITbuffer
			set ITbuffer {}
			foreach packet $saved {
				DEBUG 1 "Sending queued packet <$packet> to server"
				ITsend $packet
			}
		}
	}
}
		

#proc ITsendObjStream {....} {
#}

#
# We had a maddening situation where a map update from a remote
# source would throw an exception and wipe out random bits of 
# the map.  I traced it down to a timing issue due to the ITreceive
# procedure being called as a callback whenever data arrives on the
# control socket.  When the SYNC operation is done by one map, it 
# sends "CLR *" then a dump of all the objects which should be on
# the other maps.  Problem: the map may not be finished executing
# the CLR before another incoming ITreceive interrupts it to pile
# more data into the map.  Then the CLR continues, *deleting* the
# objects (some of them, anyway), which now confuse the mapper because
# they should have been there and suddenly... aren't.
#
# Instead, we'll consider that ITreceive may be invoked before a
# previous call is done, but we're not really multi-threaded--i.e.,
# they won't be *concurrent* or create the need for a true mutex
# or something.  So, we'll have a global queue of input events.  If
# the queue is empty, we'll just run the event we have.  If not,
# we'll store this one in the queue and return immediately.  At the
# end of the execution, we'll call ITreceive recursively as needed to
# burn up all the events queued earlier.
#

proc RequireArgs {min max event} {
	if {[llength $event] < $min || [llength $event] > $max} {
		DEBUG 0 "Received command <$event> with [llength $event] values; $min-$max expected."
		return 0
	}
	return 1
}

set ITreceive_queue {}
set ITpreamble 2
proc ITreceive socketID {
	global MOB_COMBATMODE canvas ITsock ITreceive_queue ITpreamble ITpending_auth
	if {[gets $socketID event] == -1} {
		if [eof $socketID] {
			DEBUG 0 "Lost connection to map server"
			close $socketID
			set ITsock {}
			lappend ITbuffer POLO
			BackgroundConnectToServer 1
			return
		}
		# insufficient data yet for a complete line
		DEBUG 3 "ITreceive still waiting for complete line"
		return
	}

	lappend ITreceive_queue $event
	set queue_depth [llength $ITreceive_queue]
	DEBUG 4 "recv $ITsock -> $event, queue now $queue_depth deep"

	if {$queue_depth > 1} {
		DEBUG 4 "ITreceive postponing $event until previous tasks have completed."
		return
	}

	while {[llength $ITreceive_queue] > 0} {
		global MasterClient
		set event [lindex $ITreceive_queue 0]
		DEBUG 4 "Executing top event from queue: $event"

        if {$ITpreamble == 1} {
            report_progress "Ready"
            set ITpreamble 0
        }

		switch -exact -- [lindex $event 0] {
			OK {
				DEBUG 4 "Server greeting complete"
				report_progress "Server greeting complete"
				set ITpreamble 0
				if {[llength $event] > 1} {
					set server_protocol [lindex $event 1]
					CheckProtocolCompatibility $server_protocol
					if {$server_protocol >= 321 && [llength $event] > 2} {
						# 321 and up require authentication
						global ITpassword
						set server_nonce [lindex $event 2]
                        if {$ITpassword eq {?}} {
                            if {! [::getstring::tk_getString .password_prompt ITpassword "Server Password" -title "Log In" -entryoptions {-show *}]} {
                                set ITpassword {}
                            }
                        }
						if {$ITpassword eq {}} {
							say "This server requires authentication but no --password option or configuration file line was given."
							exit 1
						}
						# authenticate now
                        set ITpreamble 1
						DEBUG 4 "Server requests authentication (challenge=$server_nonce)"
                        report_progress "Authenticating..."
						if {[catch {
							set challenge [base64::decode $server_nonce]
							binary scan $challenge S passes
							set passes [expr $passes & 0xffff]
                            set auth_prog [begin_progress * Authenticating... $passes]
							DEBUG 4 "-- $passes passes"
							set H [::sha2::SHA256Init]
							::sha2::SHA256Update $H $challenge
							::sha2::SHA256Update $H $ITpassword
							set D [::sha2::SHA256Final $H]
							for {set i 0} {$i < $passes} {incr i} {
                                if {$i % 100 == 0} {
                                    update_progress $auth_prog $i *
                                    #report_progress_noconsole "Authenticating: [expr int($i * 100 / $passes)]%..."
                                }
								set H [::sha2::SHA256Init]
								::sha2::SHA256Update $H $ITpassword
								::sha2::SHA256Update $H $D
								set D [::sha2::SHA256Final $H]
							}
							set response [base64::encode $D]
							DEBUG 4 "-- sending response $response"
#							if {[catch {
#								set local_user $::tcl_platform(user)
#							} uerr]} {
#								set local_user "($uerr)"
#							}
							global local_user GMAMapperVersion
							ITsend [list AUTH $response $local_user "mapper $GMAMapperVersion"]
                            end_progress $auth_prog
							ITsend [list ALLOW [list DICE-COLOR-BOXES]]
						} err]} {
							say "Failed to understand server's challenge or compute our response ($err)"
							exit 1
						}
						if {[catch {
                            report_progress "Loading chat history..."
							InitializeChatHistory
						} err]} {
							say "Error loading chat history: $err (Warning only)"
						}
					} else {
						# no support/need for authentication
						set ITpending_auth false
						ITsend [list ALLOW [list DICE-COLOR-BOXES]]
				        }
				}
			}
			DENIED {
				if {[llength $event] > 1} {
					say "Server DENIED access: [lindex $event 1]"
				} else {
					say "Server DENIED access for unspecified reason."
				}
                report_progress "Server denied access"
                exit 1  ; # we're not getting any farther if this happens
			}
            GRANTED {
                report_progress "Server login successful"
                set ITpending_auth false
                after 5000 {report_progress ""}
                ITsend //
            }
			I {
				if {$MOB_COMBATMODE} {
					if [RequireArgs 3 3 $event] {
						UpdateRunClock [lindex $event 1]
						ITupdate [AcceptCreatureImageName [lindex $event 2]]
					}
				}
			}
			L {
				if [RequireArgs 2 2 $event] {
					foreach file [lindex $event 1] {
						loadfile 0 $file
					}
				}
			}
			M {
				if [RequireArgs 2 2 $event] {
					foreach file [lindex $event 1] {
						loadfile 1 $file
					}
				}
			}
			M? { 
				if [catch {fetch_map_file [lindex $event 1]} err] {
					if {$err eq {NOSUCH}} {
						DEBUG 0 "WARNING: Requested pre-load of file ID [lindex $event 1] but the server doesn't have it."
					} else {
						say "Error retrieving file ID [lindex $event 1] from server: $err"
					}
				}
			}
			M@ {
				if [catch {set cache_filename [fetch_map_file [lindex $event 1]]} err] {
					if {$err eq {NOSUCH}} {
						DEBUG 0 "WARNING: Requested load of remote file ID [lindex $event 1] but the server doesn't have it."
					} else {
						say "Error retrieving file ID [lindex $event 1] from server: $err"
					}
				} else {
					global SafMode
					if $SafMode {
						toggleSafMode
					}
					loadfile 1 $cache_filename -nosend
				}
			}
			MARCO { ITsend POLO }
			MARK { if [RequireArgs 3 3 $event] {start_ping_marker $canvas [lindex $event 1] [lindex $event 2] 0}}
			POLO { DEBUG 4 "POLO received" }

			AI  { if [RequireArgs 3 3 $event] {StartImageStream   [lindex $event 1] [lindex $event 2] }}
			AI: { if [RequireArgs 2 2 $event] {ContinueImageStream [lindex $event 1]                  }}
			AI. { if [RequireArgs 3 3 $event] {EndImageStream     [lindex $event 1] [lindex $event 2] }}
			AI@ { 
				if [RequireArgs 4 4 $event] {
					fetch_image [lindex $event 1] [lindex $event 2] [lindex $event 3] 
				}
			}
			AI? {
				if [RequireArgs 3 3 $event] {
					global TILE_ID
					if [info exists TILE_ID([tile_id [lindex $event 1] [lindex $event 2]])] {
						ITsend [list AI@ [lindex $event 1] [lindex $event 2] $TILE_ID([tile_id [lindex $event 1] [lindex $event 2]])]
					}
				}
			}

			CONN { StartConnStream }
			CONN: { if [RequireArgs 10 10 $event] { ContinueConnStream [lrange $event 1 end] }}
			CONN. { if [RequireArgs 3 3 $event] { EndConnStream [lindex $event 1] [lindex $event 2]}}

			LS  { StartObjStream                                         }
			LS: { if [RequireArgs 2 2 $event] {ContinueObjStream  [lindex $event 1]                   }}
			LS. { if [RequireArgs 3 3 $event] {EndObjStream       [lindex $event 1] [lindex $event 2] }}
			CLR { if [RequireArgs 2 2 $event] {ClearObjectById    [lindex $event 1]}}
			CC  { if [RequireArgs 4 4 $event] {
					ClearChatHistory   [lindex $event 1] [lindex $event 2] [lindex $event 3]
					ChatHistoryAppend $event
					LoadChatHistory
				}
			}
			CLR@ { 
				if [catch {set cache_filename [fetch_map_file [lindex $event 1]]} err] {
					if {$err eq {NOSUCH}} {
						DEBUG 0 "WARNING: Requested unload of file ID [lindex $event 1] but the server doesn't have it."
					} else {
						say "Error retrieving file ID [lindex $event 1] from server: $err"
					}
				} else {
                    global SafMode
                    if $SafMode {
                        toggleSafMode
                    }
                    unloadfile $cache_filename -nosend
                }
			}
			OA  { if [RequireArgs 3 3 $event] {SetObjectAttribute [lindex $event 1] [lindex $event 2] }}
			OA+ {
					if [RequireArgs 4 4 $event] { 
						AddToObjectAttribute [lindex $event 1] [lindex $event 2] [lindex $event 3] 
						RefreshGrid 0
						RefreshMOBs
					}
				}
			OA- {
					if [RequireArgs 4 4 $event] { 
						RemoveFromObjectAttribute [lindex $event 1] [lindex $event 2] [lindex $event 3] 
						RefreshGrid 0
						RefreshMOBs
					}
				}
			DSM { 	
					if [RequireArgs 4 5 $event] {
						if {[llength $event] > 4} {
							DefineStatusMarker [lindex $event 1] [lindex $event 2] [lindex $event 3] [lindex $event 4]
						} else {
							DefineStatusMarker [lindex $event 1] [lindex $event 2] [lindex $event 3] ""
						}
					}
				}
			TB  {
					if [RequireArgs 2 2 $event] { 
						if {!$MasterClient} {
							toolBarState  [lindex $event 1]               
						}
					}
				}
			CO  { if [RequireArgs 2 2 $event] {setCombatMode [lindex $event 1] }}
			AC  {
					if [RequireArgs 6 6 $event] { 
						# AC name id color area size
						# 0    1  2    3     4    5
						global PC_IDs
						set creature_name [AcceptCreatureImageName [lindex $event 1]]
						if {[info exists PC_IDs($creature_name)]} {
							if {$PC_IDs($creature_name) ne [lindex $event 2]} {
								DEBUG 0 "Attempting to add player '$creature_name' with ID [lindex $event 2] to menu but ID $PC_IDs($creature_name) is already known for it! Ignoring new request."
							} else {
								DEBUG 1 "Received duplicate AC command for [lindex $event 1] (ID [lindex $event 2])"
							}
						} else {
							set PC_IDs($creature_name) [lindex $event 2]
							.contextMenu add command -command "AddPlayer $creature_name [lindex $event 3] [lindex $event 4] [lindex $event 5] [lindex $event 2]" -label $creature_name 
						}
					}
				}
			PS {
					if [RequireArgs 10 10 $event] { 
						# PS id color name area size player|monster x y reach
						#  0  1   2    3   4     5        6         7 8  9
						DEBUG 4 "PlaceSomeone $canvas [lindex $event 7] [lindex $event 8] [lindex $event 2] [lindex $event 3] [lindex $event 4] [lindex $event 5] [lindex $event 6] [lindex $event 1] [lindex $event 9]"
						set creature_name [AcceptCreatureImageName [lindex $event 3]]
						PlaceSomeone $canvas [lindex $event 7] [lindex $event 8] [lindex $event 2] $creature_name \
							[lindex $event 4] [lindex $event 5] [lindex $event 6] [lindex $event 1] [lindex $event 9]
						FlashMob $canvas [lindex $event 1] 3
					}
				}
			AV {
				# AV x y
				# 0  1 2
				if [RequireArgs 3 3 $event] {AdjustView [lindex $event 1] [lindex $event 2]}
			}
			// {
				if {$ITpreamble > 1} {
					if {[llength $event] == 6
					&&  [lindex $event 1] eq {MAPPER}
					&&  [lindex $event 2] eq {UPDATE}
					&&  [lindex $event 3] eq {//}} {
						global GMAMapperVersion BIN_DIR path_install_base

						set new_version [lindex $event 4]
						set comp [::gmautil::version_compare $GMAMapperVersion $new_version]
						if {$comp < 0} {
							if {[::gmautil::is_git $BIN_DIR]} {
								tk_messageBox -type ok -icon info \
									-title "Mapper version $new_version is available" \
									-message "There is a new mapper version, $new_version, available for use. Update your Git repository." \
									-detail "You are currently running version $GMAMapperVersion.\nHowever, since you are running this client from $BIN_DIR, which is inside a Git repository working tree, you should upgrade it by running \"git pull\" rather than using the built-in upgrade feature."
							} else { ;# not in git area
								set upgrade_file [lindex $event 5]
								global UpdateURL
								if {$UpdateURL eq {}} {
									tk_messageBox -type ok -icon info \
										-title "Mapper version $new_version is available" \
										-message "There is a new mapper version, $new_version, available for use."\
										-detail "You are currently running version $GMAMapperVersion.\nIf you add an update-url value to your mapper configuration file or include an --update-url option when running mapper, this update may be installed automatically for you. Ask your GM for the correct value for that setting."
								} else { ;# we have UpdateURL, let's proceed
									set answer [tk_messageBox -type yesno -icon question \
										-title "Mapper version $new_version is available" \
										-detail "If you click YES, the new mapper will be downloaded from the server, installed, and then launched. You will then be using the new client." \
										-message "You are running version $GMAMapperVersion of the mapper client, but version $new_version is now available. Do you wish to install the new version now?"]
									if {$answer eq {yes}} {
										global path_tmp
										global CURLproxy
										global CURLpath
										#
										# Figure out if $BIN_DIR has the format
										#   <install_base>/mapper/<version>/bin
										#
										set install_dirs [file split $BIN_DIR]
										if {[lindex $install_dirs end] eq {bin}
										&&  [lindex $install_dirs end-1] eq $GMAMapperVersion
										&&  [lindex $install_dirs end-2] eq {mapper}} {
											#
											# aha, it does. We propose using the same naming 
											# convention, then.
											#
											set target_dirs [lreplace $install_dirs end-1 end $new_version]
										} else {
											#
											# Nope. What about <install_base>/mapper/bin?
											#
											if {[lindex $install_dirs end] eq {bin}
											&&  [lindex $install_dirs end-1] eq {mapper}} {
												# 
												# yes, so we'll propose adding the versioned structure there.
												#
												set target_dirs [lreplace $install_dirs end end $new_version]
											} else {
												#
												# We have no idea. Punt.
												#
												set target_dirs [file split $path_install_base]
												lappend target_dirs $new_version
											}
										}

										set answer [tk_messageBox -type yesnocancel -icon question \
											-title "Installation Target" \
											-message "This client is running from $BIN_DIR. Should I install the new one in [file join {*}$target_dirs]?"\
											-detail "If you click YES, the new client will be installed in the recommended location to make it easier to maintain all the versions of the mapper you have on your system.\nIf you click NO, you will be prompted to choose the installation directory of your choice.\nIt you click CANCEL, we won't install the new version at this time at all."]
										if {$answer eq {yes}} {
											::gmautil::upgrade $target_dirs $path_tmp $UpdateURL $upgrade_file $GMAMapperVersion $new_version mapper bin/mapper.tcl display_message $CURLproxy $CURLpath
										} elseif {$answer eq {no}} {
											set chosen_dir [tk_chooseDirectory -initialdir [file join {*}$target_dirs] \
												-mustexist true \
												-title "Select Installation Base Directory"]
											if {$chosen_dir eq {}} {
												say "No directory selected; upgrade cancelled."
											} else {
												if {[tk_messageBox -type yesno -icon question \
													-title "Confirm Installation Directory" \
													-message "Are you sure you wish to install into $chosen_dir?"\
													-detail "If you click YES, we will install the new mapper client into $chosen_dir."] eq {yes}} {
													::gmautil::upgrade [file split $chosen_dir] $path_tmp $UpdateURL $upgrade_file $GMAMapperVersion $new_version mapper bin/mapper.tcl display_message $CURLproxy $CURLpath
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
							DEBUG 0 "You appear to be running a newer mapper ($GMAMapperVersion) than the latest version offered by your server ([lindex $event 4]). If this isn't expected, you may want to nudge your system administrator to update the server's advertised version."
						}
					}; # // MAPPER UPDATE // 
				} elseif {[llength $event] == 5 && [lindex $event 1] eq "BEGIN"} {
                    # // BEGIN <id> <max> <title>
                    begin_progress [lindex $event 2] [lindex $event 4] [lindex $event 3]
                } elseif {[llength $event] >= 4 && [lindex $event 1] eq "UPDATE"} {
                    # // UPDATE <id> <val> [<newmax>]
                    if {[llength $event] > 4} {
                        set newmax [lindex $event 4]
                    } else {
                        set newmax *
                    }
                    update_progress [lindex $event 2] [lindex $event 3] $newmax
                } elseif {[llength $event] == 3 && [lindex $event 1] eq "END"} {
                    # // END <id>
                    end_progress [lindex $event 2]
                }
				# otherwise ignore the comment
			}
			DD= { StartDD }
			DD: {
				if [RequireArgs 5 5 $event] {ContinueDD [lindex $event 1] [lindex $event 2] [lindex $event 3] [lindex $event 4]}
			}
			DD. {
				if [RequireArgs 3 3 $event] {EndDD [lindex $event 1] [lindex $event 2]}
			}
			ROLL {
				if [RequireArgs 7 7 $event] {
					DisplayDieRoll [lindex $event 1] [lindex $event 2] [lindex $event 3] [lindex $event 4] [lindex $event 5]
					ChatHistoryAppend $event
				}
			}
			TO {
				if [RequireArgs 5 5 $event] {
					DisplayChatMessage [lindex $event 1] [lindex $event 2] [lindex $event 3]
					ChatHistoryAppend $event
				}
			}
			CS - D - DD - DR {
				# We don't care about this command, ignore it
			}

			default {
				DEBUG 1 "IT: INVALID \"$event\""
			}
		}

		set ITreceive_queue [lreplace $ITreceive_queue 0 0]
		DEBUG 4 "Removing event from queue.  Depth now [llength $ITreceive_queue]"
	}
}

set DDchk {}
set DDcnt 0
set DDdup 0

proc StartDD {} {
	global DDchk DDcnt DDdata DDdup

	catch {unset DDdata}
	if {$DDcnt > 0} {
		DEBUG 0 "ERROR: Preset data stream started before previous one terminated!"
	}
	set DDchk [cs_init]
	set DDcnt 0
	set DDdup 0
	DEBUG 2 "Starting preset data stream from server"
}

proc ContinueDD {idx name desc roll} {
	global DDchk DDcnt DDdata DDdup
	if {$idx != $DDcnt} {
		DEBUG 0 "ERROR: Preset data stream element out of order (got $idx, expected $DDcnt)"
	}
	incr DDcnt
	cs_update $DDchk [list $idx $name $desc $roll]
	if {[info exists DDdata($name)]} {
		incr DDdup
		DEBUG 1 "Got duplicate die-roll preset $name (ignored)"
	} else {
		set DDdata($name) [list $desc $roll]
	}
	DEBUG 2 "Got DD #DDcnt: name=$name, desc=$desc, roll=$roll"
}

proc EndDD {count checksum} {
	global DDchk DDcnt DDdata dice_preset_data SuppressChat DDdup
	global icon_delete icon_die16 dark_mode
	set cs [cs_final $DDchk]

	set checksum 0	; # TODO fix checksum error in unicode data stream

	DEBUG 2 "End preset data stream, $DDcnt records, check $cs"
	if {[array size DDdata] != $count - $DDdup} {
		DEBUG 0 "INTERNAL ERROR in data stream: Received $DDcnt records ($DDdup duplicate), buffer has [array size DDdata]!"
	} elseif {$DDcnt != $count} {
		DEBUG 0 "ERROR in data stream: Received $DDcnt records ($DDdup duplicate), expected $count!"
	} elseif {$checksum != 0 && ![cs_match $cs $checksum]} {
		DEBUG 0 "ERROR in data stream: Received data checksum mismatch!"
		DEBUG 0 "-- Server's checksum: $checksum"
		DEBUG 0 "-- Our calculation:   $cs"
	} else {
		if {$checksum == 0} {
			DEBUG 2 "Not checking checksum (none given to us)"
		}
		# good to go...
		DEBUG 2 "Committing preset data stream"
		DEBUG 3 "presets before change: [array get dice_preset_data]"
		if {! $SuppressChat} {
			if [catch {
				DisplayChatMessage {} {} {};	# force window open if it wasn't already
				set wp [sframe content .chatwindow.p.preset.sf]
				for {set i 0} {$i < [array size dice_preset_data]} {incr i} {
					DEBUG 1 "destroy $wp.preset$i"
					destroy $wp.preset$i
				}
				array unset dice_preset_data
				array set dice_preset_data [array get DDdata]
				_render_die_roller $wp 0 0 preset -noclear
			} err] {
				DEBUG 0 "Error updating die preset info: $err"
			}
		}
		if {$DDdup > 0} {
			DEBUG 0 "WARNING: Received $DDdup duplicate die-roll presets"
		}
	}
	set DDchk {}
	set DDcnt 0
	set DDdup 0
	catch {unset DDdata}
}
	
proc chat_to_all {} {
	global CHAT_TO

	foreach recipient [array names CHAT_TO] {
		set CHAT_TO($recipient) 0
	}
	update_chat_to
}

proc update_chat_to {} {
	global CHAT_TO
	set q 0
	foreach name [array names CHAT_TO] {
		if {$CHAT_TO($name)} {
			if {$q > 0} {
				.chatwindow.p.chat.2.to configure -text "To (multiple):"
				return
			}
			set q 1
			.chatwindow.p.chat.2.to configure -text "To $name:"
		}
	}
	if {$q == 0} {
		.chatwindow.p.chat.2.to configure -text "To all:"
	}
}

proc RefreshPeerList {} {ITsend /CONN}
		
proc format_with_style {value format} {
	global display_styles

	if [info exists display_styles(fmt_$format)] {
		if [catch {
			set value [format $display_styles(fmt_$format) $value]
		} err] {
			DEBUG 0 "style formatting error (using fmt_$format=$display_styles(fmt_$format)): $err"
		}
	}
	DEBUG 3 "format_with_style($value, $format) -> $value"
	return $value
}

set drd_id 0
proc DisplayDieRoll {from recipientlist title result details} {
	global icon_die16 icon_die16c SuppressChat drd_id

	if {$SuppressChat} {
		return
	}

	set w .chatwindow.p.chat

	if {![winfo exists $w]} {
		DisplayChatMessage {} {} {}
	}
	set icon $icon_die16
	foreach tuple $details {
		if {[lindex $tuple 0] eq "critlabel"} {
			set icon $icon_die16c
			break
		}
	}

	TranscribeDieRoll $from $recipientlist $title $result $details
	$w.1.text configure -state normal
	$w.1.text image create end -align baseline -image $icon -padx 2
	$w.1.text insert end [format_with_style $result fullresult] fullresult
	$w.1.text insert end " "
	ChatAttribution $w.1.text $from $recipientlist
	if {$title != {}} {
		global display_styles
		if [catch {
			foreach title_block [split $title "\u2016"] {
				set title_parts [split $title_block "\u2261"]
				switch [llength $title_parts] {
					0 {
						# title was empty?
						error "bug - uncaught empty title string"
					}
					1 {
						set title_fg $display_styles(fg_title)
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
				label $wt -padx 2 -pady 2 -relief groove -foreground $title_fg -background $title_bg -font $display_styles(font_title) -borderwidth 2 -text [lindex $title_parts 0]
				$w.1.text window create end -align bottom -window $wt -padx 2
			}
		} err] {
			DEBUG 0 "unable to set title block: $err"
			$w.1.text insert end [format_with_style $title title] title 
		}
	}
#				critspec  {$w.1.text insert end "  [lindex $tuple 1]" [lindex $tuple 0]}
	if [catch {
		foreach tuple $details {
			$w.1.text insert end [format_with_style [lindex $tuple 1] [lindex $tuple 0]] [lindex $tuple 0]
			DEBUG 3 "DisplayDieRoll: $tuple"
		}
	} err] {
		DEBUG 0 $err
	}
	$w.1.text insert end "\n"
	$w.1.text see end
	$w.1.text configure -state disabled
}

array set resize_task {
	recent	{}
	preset 	{}
}
array set last_known_size {
	recent,width	0
	recent,height	0
	preset,width	0
	preset,height	0
}

proc ResizeDieRoller {w width height type} {
	global resize_task last_known_size

	if {$resize_task($type) ne {}} {
		if {$resize_task($type) eq NO} {
			return
		}
		after cancel $resize_task($type)
	}
	if {$last_known_size($type,width) != $width || $last_known_size($type,height) != $height} {
		set resize_task($type) [after 250 "_resize_die_roller $w $width $height $type"]
	}
}

proc inhibit_resize_task {flag type} {
	global resize_task
	if {$flag} {
		set resize_task($type) NO
	} else {
		set resize_task($type) {}
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
# global dice_preset_data(name) provides {description definition} for each preset
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

proc _collapse_extra {w i} {
	$w configure -width [expr max(3,[string length [$w get]])]
	if {$i >= 0} {
		global recent_die_rolls
		set recent_die_rolls [lreplace $recent_die_rolls $i $i [list [lindex [lindex $recent_die_rolls $i] 0] [$w get]]]
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

		
proc _render_die_roller {w width height type args} {
	global dice_preset_data recent_die_rolls icon_delete icon_die16
	global dark_mode last_known_size display_styles

	if {$width <= 0} {
		set width $last_known_size($type,width)
	}

	set row_bg {}
	if [info exists display_styles(bg_list_even)] {
		set row_bg [list [list -bg $display_styles(bg_list_even)]]
	} else {
		set row_bg [list {}]
	}
	if [info exists display_styles(bg_list_odd)] {
		lappend row_bg [list -bg $display_styles(bg_list_odd)]
	} else {
		lappend row_bg {}
	}

	switch -exact $type {
		recent {
			for {set i 0} {$i < [llength $recent_die_rolls] && $i < 10} {incr i} {
				$w.$i.spec configure -text [lindex [lindex $recent_die_rolls $i] 0]
				$w.$i.extra configure -width [expr max(3,[string length [lindex [lindex $recent_die_rolls $i] 1]])] -state normal
				$w.$i.extra delete 0 end
				$w.$i.extra insert end [lindex [lindex $recent_die_rolls $i] 1]
				if {$last_known_size(recent,$i) eq {blank}} {
					# first time, pack them since they weren't there before
					pack $w.$i.roll $w.$i.plus $w.$i.extra -side left
					pack $w.$i.spec -side left -expand 0 -fill none
					$w.$i.extra configure -state normal 
					$w.$i.roll configure -state normal 
					if {[llength [lindex $row_bg [expr $i % 2]]] > 0} {
						$w.$i.spec configure {*}[lindex $row_bg [expr $i % 2]]
					}
					bind $w.$i.extra <FocusIn> "_pop_open_extra $w.$i.extra $i"
					bind $w.$i.extra <FocusOut> "_collapse_extra $w.$i.extra $i"
					set last_known_size(recent,$i) 1
				} else {
					pack configure $w.$i.spec -expand 0 -fill none
				}
			}
			if {$display_styles(collapse_descriptions)} {
				update
				for {set i 0} {$i < [llength $recent_die_rolls] && $i < 10} {incr i} {
					set needed_width [expr [winfo width $w.$i.spec] + [winfo width $w.$i.roll] + [winfo width $w.$i.extra] + [winfo width $w.$i.plus]]
					if {$width > 0 && $needed_width >= $width} {
						if {$last_known_size(recent,$i) != 2} {
							# rearrange widgets into 2 rows to allow more room
							pack forget $w.$i.spec $w.$i.plus $w.$i.extra $w.$i.roll
							pack $w.$i.spec -side bottom -anchor w -expand 1 -fill x
							pack $w.$i.roll $w.$i.plus $w.$i.extra -side left 
							set last_known_size(recent,$i) 2
						} else {
							pack configure $w.$i.spec -expand 1 -fill x
						}
					} else {
						if {$last_known_size(recent,$i) != 1} {
							# rearrange widgets into 1 row
							pack forget $w.$i.spec $w.$i.plus $w.$i.extra $w.$i.roll
							pack $w.$i.roll $w.$i.plus $w.$i.extra -side left
							pack $w.$i.spec -side left -expand 1 -fill x
							set last_known_size(recent,$i) 1
						} else {
							pack configure $w.$i.spec -expand 1 -fill x
						}
					}
				}
			}
		}
		preset {
			if {[lsearch -exact $args -noclear] < 0} {
				for {set i 0} {$i < [array size dice_preset_data]} {incr i} {
					DEBUG 1 "destroy $w.preset$i"
					destroy $w.preset$i
				}
			}
			set i 0
			foreach preset_name [lsort -dictionary [array names dice_preset_data]] {
				set desc [lindex $dice_preset_data($preset_name) 0]
				set def [lindex $dice_preset_data($preset_name) 1]
				if {[set namediv [string first | $preset_name]] >= 0} {
					set pname [string range $preset_name $namediv+1 end]
				} else {
					set pname $preset_name
				}

				DEBUG 4 "create frame $w.preset$i"
				pack [frame $w.preset$i] -side top -expand 0 -fill x
				pack [button $w.preset$i.roll -image $icon_die16 -command "RollPreset $w.preset$i $i {$preset_name}"] -side left
				pack [label $w.preset$i.plus -text +] -side left
				pack [entry $w.preset$i.extra -width 3] -side left
				pack [label $w.preset$i.name -text ${pname}:  -anchor w -font Tf12 -foreground [expr $dark_mode ? {{cyan}} : {{blue}}] {*}[lindex $row_bg [expr $i % 2]]] -side left -padx 2
				pack [label $w.preset$i.def -text [cleanupDieRollSpec $def] -anchor w {*}[lindex $row_bg [expr $i % 2]]] -side left -expand 0 -fill none
				pack [button $w.preset$i.del -image $icon_delete -command "DeleteDieRollPreset {$preset_name}"] -side right
				tooltip::tooltip $w.preset$i.name $desc
				tooltip::tooltip $w.preset$i.def $desc
				bind $w.preset$i.extra <FocusIn> "_pop_open_extra $w.preset$i.extra -1"
				bind $w.preset$i.extra <FocusOut> "_collapse_extra $w.preset$i.extra -1"
				incr i
			}
			if {$display_styles(collapse_descriptions)} {
				update
				set i 0
				foreach preset_name [lsort -dictionary [array names dice_preset_data]] {
					set needed_width [expr [winfo width $w.preset$i.del] + \
										   [winfo width $w.preset$i.name] + \
										   [winfo width $w.preset$i.def] + \
										   [winfo width $w.preset$i.roll] + \
										   [winfo width $w.preset$i.extra] + \
										   [winfo width $w.preset$i.plus]]
					if {$width > 0 && $needed_width >= $width} {
						# move to 2-row format
						pack forget $w.preset$i.def $w.preset$i.del $w.preset$i.name $w.preset$i.roll $w.preset$i.extra $w.preset$i.plus

						pack $w.preset$i.def -side bottom -anchor w -expand 1 -fill x
						pack $w.preset$i.roll $w.preset$i.plus $w.preset$i.extra -side left
						pack $w.preset$i.name -side left -expand 1 -padx 2
						pack $w.preset$i.del -side right
					} else {
						pack configure $w.preset$i.def -expand 1 -fill x
					}
					incr i
				}
			}
		}
		default {
			DEBUG 0 "_render_die_roller passed unknown type '$type'"
		}
	}
}


proc _resize_die_roller {w width height type} {
	global resize_task

	if {$resize_task($type) eq NO} {
		return
	}
	if [catch {
		global last_known_size
		_render_die_roller $w $width $height $type
		set last_known_size($type,width) $width
		set last_known_size($type,height) $height
	} err] {
		DEBUG 0 "_render_die_roller($w, $width, $height, $type) failed with error '$err'"
	}
	set resize_task($type) {}
}

proc DisplayChatMessage {from recipientlist message args} {
	global dark_mode SuppressChat CHAT_TO CHAT_text ITsock check_select_color
	global icon_die16 icon_info20 icon_arrow_refresh check_menu_color
	global icon_delete icon_add icon_open icon_save ChatTranscript
	global last_known_size display_styles CHAT_blind global_bg_color

	if $SuppressChat return
	if {$ITsock == {}} {
		tk_messageBox -type ok -icon error -title "No Connection to Server" \
			-message "Your client must be connected to the map server to use this function."
		return
	}

	set w .chatwindow
	set wc   $w.p.chat
	set wrsf $w.p.recent
	set wpsf $w.p.preset

	if {![winfo exists $w]} {
		if {[lsearch -exact $args "-noopen"] >= 0} {
			# this message isn't worth opening a new window;
			# just ignore it
			return
		}
		inhibit_resize_task 1 recent
		inhibit_resize_task 1 preset
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
		# Preset: [-] name: roll        +[____][:]     \mouseover to see full description
		#         [-] name: roll        +[____][:]     | preset
		#         [-] name: roll        +[____][:]     /
		#         [+] Add new preset
		#
		wm title $w "Chat and Die Rolls"
		ttk::panedwindow $w.p -orient vertical 
		ttk::labelframe $wc -text "Chat Messages"
		ttk::labelframe $wrsf -text "Recent Rolls"
		ttk::labelframe $wpsf -text "Preset Rolls"
		pack [sframe new $wrsf.sf -anchor w] -side top -fill both -expand 1
		pack [sframe new $wpsf.sf -anchor w] -side top -fill both -expand 1
		set wr [sframe content $wrsf.sf]
		set wp [sframe content $wpsf.sf]
		bind $wrsf <Configure> "ResizeDieRoller $wr %w %h recent"
		bind $wpsf <Configure> "ResizeDieRoller $wp %w %h preset"

		$w.p add $wc
		$w.p add $wrsf
		$w.p add $wpsf
		pack $w.p -side top -expand 1 -fill both 

		for {set i 0} {$i < 10} {incr i} {
			pack [frame $wr.$i] -side top -expand 0 -fill x
			label $wr.$i.spec -anchor w
			button $wr.$i.roll -state disabled -image $icon_die16 -command "Reroll $wr.$i $i"
			entry $wr.$i.extra -width 3 -state disabled
			label $wr.$i.plus -text +
			set last_known_size(recent,$i) blank
		}
		pack [frame $wp.add] -side bottom -expand 0 -fill x
		pack [button $wp.add.add -image $icon_add -command AddDieRollPreset] -side left
		pack [label $wp.add.label -text "Add new die-roll preset" -anchor w] -side left -expand 1 -fill x
		pack [button $wp.add.save -image $icon_save -command "SaveDieRollPresets $w"] -side right
		pack [button $wp.add.load -image $icon_open -command "LoadDieRollPresets $w"] -side right
		tooltip::tooltip $wp.add.load "Load presets from disk file"
		tooltip::tooltip $wp.add.save "Save presets to disk file"

		pack [frame $wc.1] -side top -expand 1 -fill both
		pack [frame $wc.2]\
			 [frame $wc.3]\
			-side top -expand 0 -fill x

		pack [text $wc.1.text -yscrollcommand "$wc.1.sb set" -height 10 -width 10 -state disabled] -side left -expand 1 -fill both
		pack [scrollbar $wc.1.sb -orient vertical -command "$wc.1.text yview"] -side right -expand 0 -fill y
		pack [label $wc.3.l -text Roll: -anchor nw] -side left -padx 2

		pack [entry $wc.3.dice -textvariable CHAT_dice -relief sunken] -side left -fill x -expand 1
		pack [button $wc.3.info -image $icon_info20 -command ShowDiceSyntax] -side right
		tooltip::tooltip $wc.3.info "Display help for how to write die rolls and use the chat window."
		set CHAT_blind 0
		pack [checkbutton $wc.3.blind -text GM -variable CHAT_blind -indicatoron 1 -selectcolor $check_select_color] -side right

		menubutton $wc.2.to -menu $wc.2.to.menu -text To: -relief raised
		menu $wc.2.to.menu -tearoff 0
		$wc.2.to.menu add command -label (all) -command chat_to_all
		$wc.2.to.menu add checkbutton -label GM -onvalue 1 -offvalue 0 -variable CHAT_TO(GM) -command update_chat_to -selectcolor $check_menu_color

		set CHAT_text {}

		pack $wc.2.to -side left 
		pack [entry $wc.2.entry -relief sunken -textvariable CHAT_text] -side left -fill x -expand 1
		pack [button $wc.2.send -command {RefreshPeerList} -image $icon_arrow_refresh] -side right
		tooltip::tooltip $wc.2.send "Refresh the list of recipients for messages."
		bind $wc.2.entry <Return> SendChatFromWindow
		bind $wc.3.dice <Return> SendDieRollFromWindow
		set CHAT_TO(GM) 0
		update_chat_to
		UpdatePeerList		;# set up what we may have already received
		RefreshPeerList		;# ask for an update as well

		foreach tag {
			best bonus comment constant critlabel critspec dc diebonus diespec discarded
			exceeded fail from fullmax fullresult iteration label max maximized maxroll 
			met min moddelim normal operator repeat result roll separator short sf success 
			title to until worst system subtotal
		} {
			set options {}
			foreach {stylekey optkey} "fg_$tag -foreground bg_$tag -background overstrike_$tag -overstrike font_$tag -font underline_$tag -underline offset_$tag -offset" {
				if [info exists display_styles($stylekey)] {
					lappend options $optkey $display_styles($stylekey)
				}
			}
			$wc.1.text tag configure $tag {*}$options
			DEBUG 3 "Configure tag $tag as $options"
		}

		RequestDicePresets
		inhibit_resize_task 0 recent
		inhibit_resize_task 0 preset

		LoadChatHistory
	}

	if {$message == {} && $recipientlist == {} && $from == {}} {
		return
	}

	set system [expr [lsearch -exact $args "-system"] >= 0] 
	_render_chat_message $wc.1.text $system $message $recipientlist $from
	if {$system} {
		TranscribeChat (system) $recipientlist $message
	} else {
		TranscribeChat $from $recipientlist $message
	}
}

proc _render_chat_message {w system message recipientlist from} {
	global SuppressChat

	if {!$SuppressChat && [winfo exists $w]} {
		$w configure -state normal
		if {$system} {
			$w insert end "$message\n" system
		} else {
			ChatAttribution $w $from $recipientlist
			$w insert end "$message\n" normal
		}
		$w see end
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

# check if the string at least appears to be a valid message
proc IsMessageValid {message} {
    if {![string is list $message] || [catch {set n [llength $message]}]} {
        return false
    }
    switch -- [lindex $message 0] {
        ROLL    {if {$n != 7} {return false} else {return true}}
        TO      {if {$n != 5} {return false} else {return true}}
        CC      {if {$n != 4} {return false} else {return true}}
        -system {if {$n != 4} {return false} else {return true}}
    }
    return false
}
	
proc ClearChatHistory {by target messageID} {
	global ChatHistory
	if {$target eq {}} {
		set ChatHistory {}
	} elseif {$target < 0} {
		set ChatHistory [lrange $ChatHistory end-[expr abs($target)] end]
	} else {
		set old $ChatHistory
		set ChatHistory {}
		foreach msg $old {
			set mID [ChatMessageID $msg]
			if {$mID eq {} || $mID >= $target} {	
                if {[IsMessageValid $msg]} {
                    lappend ChatHistory $msg
                } else {
                    DEBUG 1 "ClearChatHistory: Invalid message $msg"
                }
			}
		}
	}
	if {$by eq {}} {
		_log_transcription "\[---chat history cleared---\]"
	} elseif {$by eq "*"} {
		_log_transcription "\[---chat history cleared/re-synced---\]"
	} else {
		_log_transcription "\[---chat history cleared by $by---\]"
	}
}

#
# Load up the chat window with what's in our in-memory chat history list.
#
proc LoadChatHistory {} {
	global ChatHistory
	set w .chatwindow.p.chat.1.text

	foreach msg $ChatHistory {
		switch -- [lindex $msg 0] {
			ROLL { DisplayDieRoll {*}[lrange $msg 1 5] }
			TO   { _render_chat_message $w [expr "{[lindex $msg 1]}" eq {{-system}}] [lindex $msg 3] [lindex $msg 2] [lindex $msg 1] }
			CC	 {
				set by [lindex $msg 1]
				if {$by eq {}} {
					_render_chat_message $w 1 "Chat history cleared." {} {}
				} elseif {$by eq "*"} {
					_render_chat_message $w 1 "Chat history cleared/re-synced." {} {}
				} else {
					_render_chat_message $w 1 "Chat history cleared by $by." {} {}
				}
			}
		}
	}
}
#
# Load up the chat window with what's in our in-memory chat history list.
#
proc LoadChatHistory {} {
	global ChatHistory
	set w .chatwindow.p.chat.1.text

	foreach msg $ChatHistory {
        if {[IsMessageValid $msg]} {
            switch -- [lindex $msg 0] {
                ROLL { DisplayDieRoll {*}[lrange $msg 1 5] }
                TO   { _render_chat_message $w [expr "{[lindex $msg 1]}" eq {{-system}}] [lindex $msg 3] [lindex $msg 2] [lindex $msg 1] }
                CC	 {
                    set by [lindex $msg 1]
                    if {$by eq {}} {
                        _render_chat_message $w 1 "Chat history cleared." {} {}
                    } elseif {$by eq "*"} {
                        _render_chat_message $w 1 "Chat history cleared/re-synced." {} {}
                    } else {
                        _render_chat_message $w 1 "Chat history cleared by $by." {} {}
                    }
                }
            }
        } else {
            DEBUG 1 "LoadChatHistory: Invalid message $msg"
        }
	}
}


set chat_transcript_file {}
proc TranscribeChat {from recipientlist message} {
	global ChatTranscript
	if {$ChatTranscript ne {}} {
		if {[set private [Chat_text_attribution $from $recipientlist]] eq {}} {
			_log_transcription "$from: $message"
		} else {
			_log_transcription "$from ($private): $message"
		}
	}
}

proc _log_transcription {message} {
	global ChatTranscript chat_transcript_file

	if {$ChatTranscript ne {}} {
		if {$chat_transcript_file eq {}} {
			if [catch {set chat_transcript_file [open [clock format [clock seconds] -format "$ChatTranscript"] a]} err] {
				DEBUG 0 "Error writing to chat transcript file $ChatTranscript: $err. No further attempts will be made."
				set ChatTranscript {}
				return
			}
		}
		puts $chat_transcript_file "[clock format [clock seconds]]: $message"
		flush $chat_transcript_file
	}
}

proc TranscribeDieRoll {from recipientlist title result details} {
	global ChatTranscript

	if {$ChatTranscript ne {}} {
		if {[set private [Chat_text_attribution $from $recipientlist]] eq {}} {
			set message "\[ROLL $result\] $from: "
		} else {
			set message "\[ROLL $result\] $from ($private): "
		}
		if {$title ne {}} {
			append message "$title: "
		}
		if [catch {
			foreach tuple $details {
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
				switch -exact [lindex $tuple 0] {
					discarded	{append message "(DISCARDED: [lindex $tuple 1])"}
					maxroll		{append message "(MAXIMIZED: [lindex $tuple 1])"}
					diebonus	{append message "(per-die bonus [lindex $tuple 1])"}
					fullmax     {append message "MAXIMIZED ROLL: [lindex $tuple 1]"}
					subtotal    {append message "([lindex $tuple 1])"}
					roll        {append message "{[lindex $tuple 1]}"}
					default 	{append message [lindex $tuple 1]}
				}
			}
		} err] {
			DEBUG 0 "Error transcribing die roll: $err"
			return
		}
		_log_transcription $message
	}
}

proc Chat_text_attribution {from recipientlist} {
	global local_user

	if {[llength $recipientlist] == 1} {
		if {$recipientlist == {%}} {
			return {blind to GM}
		} elseif {$recipientlist == "*"} {
			return {}
		} elseif {$from eq $local_user} {
			return "private to $recipientlist"
		} else {
			return "private"
		}
	} else {
		if {[lsearch -exact $recipientlist %] >= 0} {
			return {blind to GM}
		} elseif {[lsearch -exact $recipientlist *] >= 0} {
			return {}
		} else {
			return "to [join $recipientlist {, }]"
		}
	}
}

proc AddDieRollPreset {} {

	set w .adrp
	create_dialog $w
	wm title $w "Add Die-Roll Preset"
	#
	# Preset Name: [___________________]
	# Description: [___________________]
	# Die Roll:    [___________________]
	#
	# [Cancel]                    [Save]
	#

	grid [label $w.nl -text "Preset Name:" -anchor w] \
	     [entry $w.ne] -sticky news
	grid [label $w.dl -text "Description:" -anchor w] \
	     [entry $w.de] -sticky news
	grid [label $w.rl -text "Die Roll:" -anchor w] \
	     [entry $w.re] -sticky news
	grid [button $w.c -text Cancel -command "destroy $w"] -sticky sw
	grid [button $w.s -text Save -command "CommitNewPreset"] -sticky se -row 3 -column 1
	grid columnconfigure $w 1 -weight 1
	grid rowconfigure $w 3 -weight 1
}

proc SaveDieRollPresets {w} {
	global dice_preset_data

	if {[array size dice_preset_data] == 0} {
		tk_messageBox -parent $w -type ok -icon error -title "No Presets to Save" -message "You have no presets to save."
		return
	}

	if {[set file [tk_getSaveFile -defaultextension .dice -filetypes {
		{{GMA Die Roll Preset Files} {.dice}}
		{{All Files}        *}
	} -parent $w -title "Save current die-roll presets as..."]] eq {}} return

	while {[catch {set f [open $file w]} err]} {
		if {[tk_messageBox -type retrycancel -icon error -default cancel -title "Error opening file"\
			-message "Unable to open $file: $err" -parent $w] eq "cancel"} {
			return
		}
	}

	set now [clock seconds]
	puts $f [list "__DICE__:1" $now [clock format $now]]
	foreach name [array names dice_preset_data] {
		puts $f [list $name [lindex $dice_preset_data($name) 0] [lindex $dice_preset_data($name) 1]]
	}
	close $f
}

proc LoadDieRollPresets {w} {
	global dice_preset_data

	set old_n [array size dice_preset_data]
	array unset new_preset_list
	if {$old_n > 0} {
		set answer [tk_messageBox -type yesnocancel -parent $w -icon question -title "Merge with existing presets?" \
			-message "You already have $old_n preset[expr $old_n==1 ? {{}} : {{s}}] defined. Do you want the new ones to be MERGED with those? (If you answer YES, any presets from the file will overwrite existing ones with the same name. If you answer NO, all current presets will be deleted and only the ones from the file will exist." -default yes]
		if {$answer eq {yes}} {
			array set new_preset_list [array get dice_preset_data]
		} elseif {$answer ne {no}} {
			return
		}
	}
	if {[set file [tk_getOpenFile -defaultextension .dice -filetypes {
		{{GMA Die Roll Preset Files} {.dice}}
		{{All Files}        *}
		} -parent $w -title "Load die roll presets from..."]] eq {}} return

	while {[catch {set f [open $file r]} err]} {
		if {[tk_messageBox -type retrycancel -icon error -default cancel -title "Error opening file"\
			-message "Unable to open $file: $err" -parent $w] eq "cancel"} {
				return
		}
	}

	if [catch {
		if {[gets $f v] >= 0} {
			if {[regexp {^__DICE__:([0-9]+)$} [lindex $v 0] vv vid]} {
				if {$vid != 1} {
					tk_messageBox -type ok -icon error -title "Invalid Preset File" \
						-message "Unsupported die roll preset file version ($vid). We're expecting version 1." -parent $w
					error "invalid preset"
				}
			} else {
				tk_messageBox -type ok -icon error -title "Invalid Preset File" \
					-message "File does not begin with metadata line." -parent $w
				error "invalid preset"
			}
		} else {
			tk_messageBox -type ok -icon error -title "Invalid Preset File" \
				-message "File does not seem to have any data." -parent $w
			error "invalid preset"
		}
		while {[gets $f v] >= 0} {
			set ll 0
			if {[catch {set ll [llength $v]}] || $ll != 3} {
				tk_messageBox -type ok -icon error -title "Invalid Preset File" \
					-message "Malformed file data line: $v" -parent $w
				error "invalid preset"
			}
			set new_preset_list([lindex $v 0]) [lrange $v 1 2]
		}
	} err] {
		tk_messageBox -type ok -icon error -title "Error Loading Preset File" \
			-message "Error loading file: $err" -parent $w
		close $f
		return
	}

	close $f

	set deflist {}
	foreach preset_name [array names new_preset_list] {
		set dd [lindex $new_preset_list($preset_name) 0]
		set dr [lindex $new_preset_list($preset_name) 1]
		lappend deflist [list $preset_name $dd $dr]
	}
	UpdateDicePresets $deflist
	RequestDicePresets
}

proc CommitNewPreset {} {
	global dice_preset_data
	set w .adrp

	set name [string trim [$w.ne get]]
	set desc [string trim [$w.de get]]
	set def  [string trim [$w.re get]]

	if {$name eq {}} {
		tk_messageBox -type ok -icon error -title "Preset Name Required" \
			-message "The preset name must be provided. If it matches the name of an existing preset, it will replace the old one."
		return
	}
	if {$def eq {}} {
		tk_messageBox -type ok -icon error -title "Preset Definition Required" \
			-message "You didn't specify a die roll expression to store."
		return
	}
	if {[info exists dice_preset_data($name)]} {
		if {! [tk_messageBox -type yesno -icon question -title "Overwrite previous preset?" \
			-message "There is already a preset called \"$name\". Do you want to replace it with this one?" \
			-default no]} {
			return
		}
	}

	set dice_preset_data($name) [list $desc $def]
	set deflist {}
	foreach preset_name [array names dice_preset_data] {
		set dd [lindex $dice_preset_data($preset_name) 0]
		set dr [lindex $dice_preset_data($preset_name) 1]
		lappend deflist [list $preset_name $dd $dr]
	}
	UpdateDicePresets $deflist
	RequestDicePresets
	destroy $w
}

proc ChatAttribution {w from recipientlist} {
	global local_user
	if {[set private [Chat_text_attribution $from $recipientlist]] eq {}} {
		$w insert end [format_with_style "${from}: " from] from
	} else {
		$w insert end [format_with_style $from from] from
		$w insert end " ($private)" to
		$w insert end ": " from
	}
}

proc UpdatePeerList {} {
	# Update chat window widgets from peer list
	global PeerList CHAT_TO LastKnownPeers check_menu_color

	DEBUG 3 "UpdatePeerList: PeerList=$PeerList, CHAT_TO=[array get CHAT_TO]"
	if [catch {
		.chatwindow.p.chat.2.to.menu delete 2 end
		foreach name [lsort -dictionary -unique $PeerList] {
			if {$name ne {GM}} {
				.chatwindow.p.chat.2.to.menu add checkbutton -label $name -onvalue 1 -offvalue 0 -variable CHAT_TO($name) -command update_chat_to -selectcolor $check_menu_color
				if {![info exists CHAT_TO($name)]} {
					set CHAT_TO($name) 0
				}
			}
		}
	} err] {
		DEBUG 1 "UpdatePeerList failed: $err"
	}

	foreach peer_name [array names LastKnownPeers] {
		if {[lsearch -exact $PeerList $peer_name] < 0} {
			unset LastKnownPeers($peer_name)
			DisplayChatMessage {} * "$peer_name disconnected." -noopen -system
			ChatHistoryAppend [list -system * "$peer_name disconnected." -1]
		}
	}
	foreach peer_name $PeerList {
		if {! [info exists LastKnownPeers($peer_name)]} {
			set LastKnownPeers($peer_name) 1
			DisplayChatMessage {} * "$peer_name joined." -noopen -system
			ChatHistoryAppend [list -system * "$peer_name joined." -1]
		}
	}
}

proc SendDieRoll {recipients dice blind_p} { 
	if {$blind_p} {
		set recipients {%}
	}
	ITsend [list D $recipients $dice] 
}

proc UpdateDicePresets {deflist} {ITsend [list DD $deflist]}
proc RequestDicePresets {} {ITsend [list DR]}
proc SendChatMessage {recipients message} {
	foreach msg [split $message "\n"] {
		ITsend [list TO - $recipients $msg]
	}
}

set recent_die_rolls {}
proc SendDieRollFromWindow {} {
	global CHAT_dice recent_die_rolls CHAT_blind
	set wr [sframe content .chatwindow.p.recent.sf]

	if {$CHAT_dice != {}} {
		SendDieRoll [_recipients] $CHAT_dice $CHAT_blind

		# update list of most recent 10 rolls
		for {set index -1; set i 0} {$i < [llength $recent_die_rolls]} {incr i} {
			if {[lindex [lindex $recent_die_rolls $i] 0] eq $CHAT_dice} {
				set index $i
				break
			}
		}
		if {$index >= 0} {
			if {$index > 0} {
				# move to the top of the list
				set recent_die_rolls [linsert [lreplace $recent_die_rolls $index $index] 0 [list $CHAT_dice {}]]
			}
		} else {
			set recent_die_rolls [linsert [lrange $recent_die_rolls 0 9] 0 [list $CHAT_dice {}]]
		}
		set CHAT_dice {}
		_render_die_roller $wr 0 0 recent
	}
}

proc Reroll {w index} {
	global recent_die_rolls

	if {$index >= 0 && $index < [llength $recent_die_rolls]} {
		set extra [string trim [$w.extra get]]
		_do_roll [lindex [lindex $recent_die_rolls $index] 0] $extra
	}
}

proc _do_roll {roll_string extra} {
	global CHAT_blind
	if {$extra ne {}} {
		# Leading -/+ sign or | option lead-in?
		if {[string range [string trim $extra] 0 0] eq {-} ||
		    [string range [string trim $extra] 0 0] eq {+} ||
		    [string range [string trim $extra] 0 0] eq {|}} {
			set op {}
		} else {
			set op +
		}
		# Need to insert ad-hoc before any global stuff
		if {[string first "|" $extra] < 0} {
			append extra " <ad hoc>"
		}
		set bits [split $roll_string |]
		if {[llength $bits] > 1} {
			SendDieRoll [_recipients] [join [lreplace $bits 0 0 [concat [lindex $bits 0] " $op $extra"]] |] $CHAT_blind
		} else {
			SendDieRoll [_recipients] "$roll_string $op $extra" $CHAT_blind
		}
	} else {
		SendDieRoll [_recipients] $roll_string $CHAT_blind
	}
}

proc RollPreset {w idx name} {
	global dice_preset_data

	if {[info exists dice_preset_data($name)]} {
		set extra [string trim [$w.extra get]]
		_do_roll [lindex $dice_preset_data($name) 1] $extra
	}
}

proc DeleteDieRollPreset {name} {
	global dice_preset_data
	array set new_set [array get dice_preset_data]
	catch {unset new_set($name)}
	set deflist {}
	foreach preset_name [array names new_set] {
		set dd [lindex $new_set($preset_name) 0]
		set dr [lindex $new_set($preset_name) 1]
		lappend deflist [list $preset_name $dd $dr]
	}
	UpdateDicePresets $deflist
	RequestDicePresets
}

proc SendChatFromWindow {} {
	global CHAT_text

	if {$CHAT_text != {}} {
		SendChatMessage [_recipients] $CHAT_text
		set CHAT_text {}
	}
}

proc _recipients {} {
	global CHAT_TO

	set recip_list {}
	foreach name [array names CHAT_TO] {
		if {$CHAT_TO($name)} {
			lappend recip_list $name
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
	ITsend [list AV [lindex [.c xview] 0] [lindex [.c yview] 0]]
}

proc aboutMapper {} {
	global GMAMapperVersion GMAMapperFileFormat GMAMapperProtocol GMAVersionNumber

	tk_messageBox -type ok -icon info -title "About Mapper" \
		-message "GMA Mapper Client, Version $GMAMapperVersion, for GMA $GMAVersionNumber.\n\nCopyright (c) Steve Willoughby, Aloha, Oregon, USA. All Rights Reserved. Distributed under the terms and conditions of the 3-Clause BSD License.\n\nThis client supports file format $GMAMapperFileFormat and server protocol $GMAMapperProtocol."
}

proc SyncAllClientsToMe {} {
	global SafMode FileVersion OBJ MOB ClockDisplay

	set oldcd $ClockDisplay
	if [tk_messageBox -type yesno -icon question -title "Push map data to other clients?" \
			-message "This will push your map data to all other peers, replacing their map contents.  Are you sure?" \
			-default no] {
		if {$SafMode} {
			# SafMode: 
			# (1) Save file to temporary location
			# (2) Upload to server
			# (3) Issue command for clients to download it
			set ClockDisplay "Saving state to temporary file..."
			update
			if [catch {
				set temp_file [file tempfile temp_name /tmp/mapper_sync_.map]
				file attributes $temp_name -permissions 0644
			} err] {
				tk_messageBox -type ok -icon error -title "Error writing file"\
					-message "Unable to open temporary file: $err" -parent .
				set ClockDisplay $oldcd
				return
			}
			set now [clock seconds]
			puts $temp_file [list __MAPPER__:$FileVersion [list {dynamic push of map state to clients} [list $now [clock format $now]]]]

			foreach obj [array names OBJ X:*] {
				set obj_id [string range $obj 2 end]
				foreach key [array names OBJ *:$obj_id] {
					puts $temp_file [list $key $OBJ($key)]
				}
			}

			foreach obj [array names MOB NAME:*] {
				set obj_id [string range $obj 5 end]
				foreach key [array names MOB *:$obj_id] {
					if {$MOB(TYPE:$obj_id) eq "player"} {
						puts $temp_file [list P $key $MOB($key)]
					} else {
						puts $temp_file [list M $key $MOB($key)]
					}
				}
			}
			close $temp_file
			set ClockDisplay "Uploading..."
			update
			saf_loadfile $temp_name $oldcd -nocheck
			ITsend [list CLR *]
			ITsend [list M@ [cache_map_id $temp_name]]
			file delete $temp_name
			set ClockDisplay $oldcd
		} else {
			DEBUG 3 "SyncAllClientsToMe: sending global wipe"
			ITsend [list CLR *]
			DEBUG 3 "SyncAllClientsToMe: sending all objects"

			StartSendElementSet 1
			foreach obj [array names OBJ X:*] {
				set obj_id [string range $obj 2 end]
				foreach key [array names OBJ *:$obj_id] {
					ContinueSendElementSet [list $key $OBJ($key)]
				}
			}

			foreach obj [array names MOB NAME:*] {
				set obj_id [string range $obj 5 end]
				foreach key [array names MOB *:$obj_id] {
					if {$MOB(TYPE:$obj_id) eq "player"} {
						ContinueSendElementSet [list P $key $MOB($key)]
					} else {
						ContinueSendElementSet [list M $key $MOB($key)]
					}
				}
			}
			FinishSendElementSet
			SyncView
		}
	}
}

proc AddToObjectAttribute {id key vlist} {
	global MOB OBJ
	if {[set idlist [ResolveObjectId_OA $id]] eq {}} {
		return
	}
	DistributeVars $idlist a id
	DEBUG 4 "Adding values to object $id.$key (in $a) from $vlist"
	if {![info exists ${a}($key:$id)]} {
		set ${a}($key:$id) {}
		DEBUG 4 "Creating new attribute"
	} else {
		DEBUG 4 "Starting value [set ${a}($key:$id)]"
	}
	foreach v $vlist {
		if {[lsearch -exact [set ${a}($key:$id)] $v] < 0} {
			lappend ${a}($key:$id) $v
		}
	}
	DEBUG 4 "New value is [set ${a}($key:$id)]"
}
	
proc RemoveFromObjectAttribute {id key vlist} {
	global MOB OBJ
	if {[set idlist [ResolveObjectId_OA $id]] eq {}} {
		return
	}
	DistributeVars $idlist a id
	DEBUG 4 "Removing values from object $id.$key from $vlist"
	if {![info exists ${a}($key:$id)]} {
		set ${a}($key:$id) {}
		DEBUG 4 "Creating new attribute; trivially done here."
		return
	} else {
		DEBUG 4 "Starting value [set ${a}($key:$id)]"
	}
	foreach v $vlist {
		if {[set index [lsearch -exact [set ${a}($key:$id)] $v]] >= 0} {
			set ${a}($key:$id) [lreplace [set ${a}($key:$id)] $index $index]
		}
	}
	DEBUG 4 "New value is [set ${a}($key:$id)]"
}

proc ResolveObjectId_OA {id} {
	global MOB OBJ
	if {[string range $id 0 0] eq {@}} {
		# @name instead of id
		set key [AcceptCreatureImageName [string range $id 1 end]]
		if [info exists MOB(ID:$key)] {
			return [list MOB $MOB(ID:$key)]
		}
		DEBUG 1 "Attempt to change attribute of non-existent creature $key (IGNORED)"
		return {}
	} elseif [info exists OBJ(TYPE:$id)] {
		set a OBJ
	} elseif [info exists MOB(TYPE:$id)] {
		set a MOB
	} elseif [info exists MOB(ID:$id)] {
		set a MOB
		set id $MOB(ID:$id)
	} else {
		DEBUG 1 "Received request to change object $id which does not exist!"
		return {}
	}
	return [list $a $id]
}

proc SetObjectAttribute {id kvlist} {
	global MOB OBJ canvas MOB_IMAGE
	if {[set idlist [ResolveObjectId_OA $id]] eq {}} {
		return
	}
	DistributeVars $idlist a id
	DEBUG 4 "Changing attributes of object $id from $kvlist"
	foreach {k v} $kvlist {
		if {$a eq "MOB" && $k eq "NAME"} {
			# changing creature name: also need to change the ID reverse mapping
			if {$v ne $MOB(NAME:$id)} {
				# because it would be silly to panic here if we're "changing" to the same name we already have
				if {[info exists MOB(ID:$v)]} {
					DEBUG 0 "Refusing to change name of creature $id from $MOB(NAME:$id) to $v because that name is in use."
					continue
				}
				set old_name $MOB(NAME:$id)
				if {[info exists MOB_IMAGE($old_name)]} {
					set MOB_IMAGE($v) $MOB_IMAGE($old_name)
					unset MOB_IMAGE($old_name)
				} else {
					set MOB_IMAGE($v) $old_name
				}
				unset MOB(ID:$old_name)
				set MOB(ID:$v) $id
				DEBUG 5 "-Changed ID reverse pointer MOB(ID:$old_name) to MOB(ID:$v)=$id"
			}
		}
		set ${a}($k:$id) $v
		DEBUG 5 "-${a}($k:$id) <- $v"
	}
	if {$a eq "MOB"} {
		RefreshMOBs
		FlashMob $canvas $id 3
	} else {
		UpdateObjectDisplay $id
	}
}

proc ClearObjectById {id} {
	global OBJ MOB
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
	} elseif [info exists OBJ(TYPE:$id)] {
		RemoveObject $id
	} elseif [info exists MOB(TYPE:$id)] {
		RemovePerson $id
	} elseif [info exists MOB(ID:$id)] {
		RemovePerson $MOB(ID:$id)
	} else {
		set name [AcceptCreatureImageName $id]
		if [info exists MOB(ID:$name)] {
			RemovePerson $MOB(ID:$name)
		} else {
			DEBUG 1 "Warning: Received request to delete object $id which does not exist."
		}
	}
}

set LSchk {}
set LScnt 0
set LSdata {}
proc StartObjStream {} {
	global LSchk LScnt LSdata

	if {$LScnt > 0} {
		# if we received an unterminated LS, abandon it now
		# we don't care if the LS wasn't followed by any data, though.
		DEBUG 0 "ERROR: Object stream started before previous one terminated!"
	}
	set LSchk [cs_init]
	set LSdata {}
	set LScnt 0
	DEBUG 2 "Starting object stream from server"
}

proc ContinueObjStream {data} {
	global LSchk LScnt LSdata
	lappend LSdata $data
	incr LScnt
	cs_update $LSchk $data
	DEBUG 2 "Got LS #$LScnt: $data"
}

proc EndObjStream {count checksum} {
	global LSchk LScnt LSdata FLASH_OBJ_LIST FLASH_MOB_LIST canvas
	set cs [cs_final $LSchk]

	DEBUG 2 "End object stream, $LScnt records, check $cs"
	if {[llength $LSdata] != $LScnt} {
		DEBUG 0 "INTERNAL ERROR in data stream: Received $LScnt records, buffer has [llength $LSdata]!"
	} elseif {$LScnt != $count} {
		DEBUG 0 "ERROR in data stream: Received $LScnt records, expected $count!"
	} elseif {![cs_match $cs $checksum]} {
		DEBUG 0 "ERROR in data stream: Received data checksum mismatch!"
		DEBUG 0 "-- Server's checksum: $checksum"
		DEBUG 0 "-- Our calculation:   $cs"
	} else {
		# good to go...
		DEBUG 2 "Committing data stream for object"
		#
		# HACK!  yuck.
		#
		global okToLoadMonsters okToLoadPlayers
		set okToLoadMonsters yes
		set okToLoadPlayers yes
		#
		#
		set FLASH_OBJ_LIST {}
		set FLASH_MOB_LIST {}
		foreach line $LSdata {
			DEBUG 3 "--loading element $line"
			loadElement -flash $line
		}
		DEBUG 3 "--Existing MOBs now:"
		global MOB
		foreach mob_id [array name MOB ID:*] {
			set i $MOB($mob_id)
			DEBUG 3 "----$mob_id $i"
			DEBUG 3 "------GX:$i = $MOB(GX:$i)"
		}
		DEBUG 3 "--End."
		foreach mob_id $FLASH_MOB_LIST {
			FlashMob $canvas $mob_id 3
		}
#		foreach obj_id $FLASH_OBJ_LIST {
#			FlashElement $canvas $obj_id 3
#		}
		set FLASH_OBJ_LIST {}
		set FLASH_MOB_LIST {}
	}
	garbageCollectGrid
	RefreshGrid 0
	RefreshMOBs
	modifiedflag - 1
	set LSchk {}
	set LScnt 0
	set LSdata {}
}

set CONNchk {}
set CONNcnt 0
set CONNdata {}
proc StartConnStream {} {
	global CONNchk CONNcnt CONNdata

	if {$CONNcnt > 0} {
		# if we received an unterminated CONN, abandon it now
		# we don't care if the CONN wasn't followed by any data, though.
		DEBUG 0 "ERROR: Connection data stream started before previous one terminated!"
	}
	set CONNchk [cs_init]
	set CONNdata {}
	set CONNcnt 0
	DEBUG 2 "Starting connection data stream from server"
}

proc ContinueConnStream {data} {
	global CONNchk CONNcnt CONNdata
	lappend CONNdata $data
	incr CONNcnt
	cs_update $CONNchk $data
	DEBUG 2 "Got CONN #$CONNcnt: $data"
}

proc EndConnStream {count checksum} {
	global CONNchk CONNcnt CONNdata PeerList local_user
	set cs [cs_final $CONNchk]

	DEBUG 2 "End connection data stream, $CONNcnt records, check $cs"
	if {[llength $CONNdata] != $CONNcnt} {
		DEBUG 0 "INTERNAL ERROR in data stream: Received $CONNcnt records, buffer has [llength $CONNdata]!"
	} elseif {$CONNcnt != $count} {
		DEBUG 0 "ERROR in data stream: Received $CONNcnt records, expected $count!"
	} elseif {$checksum != 0 && ![cs_match $cs $checksum]} {
		DEBUG 0 "ERROR in data stream: Received data checksum mismatch!"
		DEBUG 0 "-- Server's checksum: $checksum"
		DEBUG 0 "-- Our calculation:   $cs"
	} else {
		if {$checksum == 0} {
			DEBUG 2 "Not checking checksum (none given to us)"
		}
		# good to go...
		DEBUG 2 "Committing data stream for object"
		set PeerList {}
		#if [catch {set local_user $::tcl_platform(user)}] {set local_user __unknown__}
		#
		# 0 1        2    3    4      5    6   7   8
		# i you|peer addr user client auth pri w/o polo
		#
		foreach line $CONNdata {
			if {[llength $line] != 9} {
				DEBUG 0 "Error in peer record $line"
			} else {
				if {[lindex $line 1] eq {you} && [lindex $line 3] ne $local_user} {
					set local_user [lindex $line 3]
					DEBUG 1 "Changing local user to $local_user"
				}
					
				#if {[lindex $line 1] == {peer}} {                  }
					if {[lindex $line 5]} {
						if {![lindex $line 7]} {
							if {[lindex $line 3] ne {} && [lindex $line 3] ne {None}} {
#								if {[lindex $line 3] ne $local_user} {				}
									lappend PeerList [lindex $line 3]
									DEBUG 3 "PeerList=$PeerList"
#{								} else {
#									DEBUG 2 "Excluding $line (this is my username)"
#								}
							} else {
								DEBUG 2 "Excluding $line (no username given)"
							}
						} else {
							DEBUG 2 "Excluding $line (client not listening)"
						}
					} else {
						DEBUG 2 "Excluding $line (not authenticated)"
					}
#{				} else {
#					DEBUG 2 "Excluding $line (this is my own connection)"
#				}
			}
		}
	}
	set CONNchk {}
	set CONNcnt 0
	set CONNdata {}

	UpdatePeerList
}

set AIcnt 0
set AIdata {}
set AIname {}
set AIzoom 1.0
set AIcd {}
set AIn 0
proc StartImageStream {name zoom} {
	global AIcnt AIdata AIname AIzoom AIcd ClockDisplay AIn

	if {$AIcnt > 0} {
		# if we received an unterminated AI, abandon it now
		# we don't care if the AI wasn't followed by any data, though.
		DEBUG 0 "ERROR: Image stream started before previous one terminated!"
	}
	set AIdata {}
	set AIcnt 0
	set AIname $name
	set AIzoom $zoom
	DEBUG 2 "Starting image stream from server for $AIname at zoom factor $AIzoom"
	set AIcd $ClockDisplay
	set ClockDisplay "Loading Image [incr AIn]..."
	update
}

proc ContinueImageStream {data} {
	global AIcnt AIdata AIname ClockDisplay
	append AIdata $data
	incr AIcnt
	#DEBUG 2 "Got AI line #$AIcnt for $AIname: $data"
}

proc EndImageStream {count checksum} {
	global AIcnt AIdata AIname AIzoom AIcd ClockDisplay


	DEBUG 2 "End image stream for $AIname, $AIcnt records"
	if {$AIcnt != $count} {
		DEBUG 0 "ERROR in image data stream for $AIname: Received $AIcnt records, expected $count!"
	} elseif {[catch {set img_data [base64::decode $AIdata]} err]} {
		DEBUG 0 "ERROR decoding image data for $AIname: $err"
	} else {
		set chk [cs_init]
		cs_update $chk $img_data
		set chk_64 [cs_final $chk]

		if {![cs_match $chk_64 $checksum]} {
			DEBUG 0 "ERROR in data stream: Received image $AIname checksum mismatch!"
			DEBUG 0 "-- Server's checksum: $checksum"
			DEBUG 0 "-- Our calculation:   $chk_64"
		} else {
			global TILE_SET
			if [info exists TILE_SET($AIname:$AIzoom)] {
				DEBUG 1 "Replacing existing image $TILE_SET($AIname:$AIzoom) for ${AIname} x$AIzoom"
				image delete $TILE_SET($AIname:$AIzoom)
				unset TILE_SET($AIname:$AIzoom)
			}
			set TILE_SET($AIname:$AIzoom) [image create photo -format gif -data $img_data]
			DEBUG 3 "Defined bitmap for $AIname at $AIzoom: $TILE_SET($AIname:$AIzoom)"
		}
	}
			
	#garbageCollectGrid
	#RefreshGrid 0
	#RefreshMOBs
	#modifiedflag - 1
	set AIcnt 0
	set AIdata {}
	set AIname {}
	set AIzoom 1.0
	set ClockDisplay $AIcd
	update
}

proc ITupdate mobname {
	global canvas MOB_BLINK NextMOBID MOB

	set ITlist {}
	switch -exact -- $mobname {
		*Monsters* { 
			foreach key [array names MOB NAME:*] {
				set mob_id [string range $key 5 end]
				if {$MOB(TYPE:$mob_id) eq "monster" && !$MOB(KILLED:$mob_id)} {
					lappend ITlist $mob_id
				}
			}
		}
		{} {
			set ITlist {}
		}
		default { 
			if [info exists MOB(NAME:$mobname)] {
				set mob_id $mobname;			# This IS the id number.
			} elseif [info exists MOB(ID:$mobname)] {
				set mob_id $MOB(ID:$mobname);	# Look up name to get the ID.
			} elseif {[string range $mobname 0 0] eq {/}} {
				# /<regex> on mob names
				foreach key [array names MOB -regexp "^ID:[string range $mobname 1 end]"] {
					lappend ITlist $MOB($key)
				}
			} else {
				set mob_id {}
			}

			if {$mob_id ne {} && !$MOB(KILLED:$mob_id)} {
				lappend ITlist $mob_id
			}
		}
	}

	set MOB_BLINK $ITlist
	highlightMob $canvas $ITlist
	foreach id $ITlist {
		PopSomeoneToFront $canvas $id
	}
}

proc SendMobChanges {id attrlist} {
	global ITsock MOB
	set alist {}
	foreach attr $attrlist {
		lappend alist $attr $MOB(${attr}:$id)
	}
	DEBUG 3 "Sending [list OA $id $attrlist]"
	ITsend [list OA $id $alist]
}

proc SendObjChanges {id attrlist} {
	global ITsock OBJ
	set alist {}
	foreach attr $attrlist {
		lappend alist $attr $OBJ(${attr}:$id)
	}
	DEBUG 3 "Sending [list OA $id $attrlist]"
	ITsend [list OA $id $alist]
}

set SSEScheck {}
set SSEScount 0

proc StartSendElementSet {mergeflag} {
	global SSEScheck SSEScount SafMode

	if {!$SafMode} {
		DEBUG 2 "Starting to send map elements (mergeflag=$mergeflag)"
		if {$SSEScheck ne {}} {
			DEBUG 1 "Warning: Another set of elements was underway (abandoned now)!"
			cs_final $SSEScheck
		}
		if {!$mergeflag} {
			ITsend [list CLR E*]
		}
		set SSEScheck [cs_init]
		set SSEScount 0
		ITsend LS
	}
}

proc ContinueSendElementSet {data} {
	global SSEScheck SSEScount SafMode

	if {!$SafMode} {
		DEBUG 3 "ContinueSendElementSet: #$SSEScount data=$data"
		incr SSEScount
		cs_update $SSEScheck $data
		ITsend [list LS: $data]
	}
}

proc FinishSendElementSet {} {
	global SSEScheck SSEScount SafMode

	if {!$SafMode} {
		set cs [cs_final $SSEScheck]
		DEBUG 2 "Finished sending elements (count=$SSEScount, checksum=$cs)"
		ITsend [list LS. $SSEScount $cs]
	}
	set SSEScount 0
	set SSEScheck {}
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


# XXX TODO XXX


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



#proc WaitForConnectToServer {} {
#	while 1 {
#		if [catch {connectToServer} err] {
#			DEBUG 0 "Connection failed: $err"
#			DEBUG 1 "Retrying in 10 seconds"
#			#sleep 10
#		} else {
#			return
#		}
#	}
#}


proc connectToServer {} {
	global ITsock ITport IThost proxy_auth 
	global ITproxy ITproxyuser ITproxypass ITproxyport
	#
	# Contact the remote timekeeper server
	#
	if {$ITsock ne {}} {
		if [catch {close $ITsock} err2] {
			DEBUG 1 "close socket $ITsock: $err2"
		}
		set ITsock {}
	}
		
	if {$ITproxy ne {}} {
		if {$ITproxyuser ne {}} {
			set proxy_auth 1
		} else {
			set proxy_auth 0
			set ITproxyuser {}
			set ITproxypass {}
		}

		DEBUG 0 "Contacting proxy server $ITproxy..."
		set ITsock [socket $ITproxy $ITproxyport]
		set res [socks:init $ITsock $IThost $ITport $proxy_auth $ITproxyuser $ITproxypass]
		DEBUG 1 puts "Connection completed."
		if {$res ne {OK}} {
			puts "Socks5 proxy $ITproxy: $res"
			exit 1
		}
	} else {
		set ITsock [socket $IThost $ITport]
	}
	fconfigure $ITsock -blocking 0 
	fileevent $ITsock readable "ITreceive $ITsock"
	#fileevent $ITsock writable "ITtransmit $ITsock"
}
# TODO gets puts read flush close
# TODO ITreceive ITtransmit

proc WaitForConnectToServer {} {
	connectToServer
}

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
	global CURRENT_FONT CURRENT_TEXT_WIDGET zoom OBJ
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
		set OBJ(FONT:$CURRENT_TEXT_WIDGET) $font
		DEBUG 3 "OBJ(FONT:$CURRENT_TEXT_WIDGET)=$OBJ(FONT:$CURRENT_TEXT_WIDGET)"
	}
}

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
	after 1000 {
		if [catch {
			set dark_mode [tk::unsupported::MacWindowStyle isdark .]
		}] {
			set dark_mode 0 
		}
		if $dark_mode {
			.toolbar2.clock configure -foreground white
			refreshScreen
		}
		LoadDefaultStyles
	}
} else {
	LoadDefaultStyles
}

#
# functions that perform one-time operations and then exit
#
# --generate-style-config: output to the specified file a full
#                          list of configuration options and their
#                          current values for styles
#
if {$__generate_style_config ne {}} {
	set f [open $__generate_style_config a]
	array set def_settings [default_style_data]
	puts $f {
;------------------------------------------------------------------------------
; The following settings were automatically generated by the mapper client.
; This shows the full set of possible style configurations currently supported
; for this client, with the values that are built-in to the mapper client.
; You can delete any of these you don't want to change, so you get the built-
; in values by default. (That way if the built-in values change, you'll get
; the current ones instead of these.)
;------------------------------------------------------------------------------
[mapper]
dierolls=mapper_default_die_rolls
fonts=mapper_default_fonts

[mapper_default_fonts]
Tf16=-family Helvetica -size 16 -weight bold
Tf14=-family Helvetica -size 14 -weight bold
Tf12=-family Helvetica -size 12 -weight bold
Tf10=-family Helvetica -size 10 -weight bold
Tf8 =-family Helvetica -size  8 -weight bold
Hf14=-family Helvetica -size 14
Hf12=-family Helvetica -size 12
Hf10=-family Helvetica -size 10
If12=-family Times     -size 12 -slant italic
If10=-family Times     -size 10 -slant italic
Nf10=-family Times     -size 10
Nf12=-family Times     -size 12

[mapper_default_die_rolls]
collapse_descriptions = 0
;default_font= XXX set this to a font if you want it to be the default for all styles XXX
;bg_list_even= XXX set this to a color for even-numbered list rows
;bg_list_odd= XXX set this to a color for odd-numbered list rows}
	array unset elements
	array set def {
		font {}
		fg   {}
		bg   {}
		overstrike 0
		underline 0
		fmt  %s
	}

	foreach name [array names def_settings] {
		if {[set index [string first _ $name]] >= 0} {
			set elements([string range $name $index+1 end]) 1
		}
	}
	foreach name [lsort [array names elements]] {
		foreach style [lsort [array names def]] {
			if {[info exists "def_settings(${style}_${name})"]} {
				set v $def_settings(${style}_${name})
				if {$style eq {fmt}} {
					if {[string range $v 0 0] eq { }} {
						set v "|$v"
					}
					if {[string range $v end end] eq { }} {
						set v "$v|"
					}
				}
				puts $f "${style}_${name}=$v"
			} elseif {$def($style) eq {}} {
				puts $f ";${style}_${name}= XXX SYSTEM DEFAULT VALUE XXX"
			} else {
				puts $f "${style}_${name}=$def($style)"
			}
		}
	}
	puts $f {;------------------------------------------------------------------------------
; End of default generated values
;------------------------------------------------------------------------------}
	close $f
	exit 0
}
#
# --generate-config:       output to the specified file a full
#                          list of configuration options and their
#                          current values
#
if {$__generate_config ne {}} {
	set f [open $__generate_config a]
	puts $f {
#------------------------------------------------------------------------------
# The following settings were automatically generated by the mapper client.
# This shows the full set of possible mapper configurations currently supported
# for this client, with the values that are built-in to the mapper client.
# You can delete any of these you don't want to change, so you get the built-
# in values by default. (That way if the built-in values change, you'll get
# the current ones instead of these.)
# 
# Commented-out options are off by default. Un-comment them to enable them.
#------------------------------------------------------------------------------
no-animate
#animate
#blur-all
no-blur-all
#blur-hp=PERCENT
#character=NAME[:COLOR]  (you should never enable this)
#set this to the maximum number of chat/die roll messages you want to retain
chat-history=500
#enable more of these to increase debugging output
#debug
#debug
#debug
#debug
#debug
#debug
#dark
#host=YOUR_GAME_SERVER_HOSTNAME
#port=2323
#guide=INTERVAL[+OFFSET[:YOFFSET]]
#major=INTERVAL[+OFFSET[:YOFFSET]]
#module=CODE
#keep-tools
#no-chat
#style=~/.gma/mapper/style.conf
#transcript=PATHNAME
#username=MYNAME
#proxy-url=CURL-PROXY-URL
#proxy-host=SSH-PROXY-HOST
#preload
#curl-path=PATH
#curl-url-base=YOUR_GAME_SERVER_URL
#mkdir-path=PATH
#nc-path=PATH
#scp-path=PATH
#scp-dest=YOUR_GAME_SERVER_DIR
#scp-server=YOUR_GAME_SERVER
#ssh-path=PATH
#update-url=YOUR_GAME_SERVER_UPGRADE_URL
#------------------------------------------------------------------------------
# End of default generated values
#------------------------------------------------------------------------------
}
	close $f
	exit 0
}

# IThost ITport 
set ChatHistory {}
set ChatHistoryFile {}
set ChatHistoryFileHandle {}
set ChatHistoryLastMessageID 0
# We only use ChatHistoryLastMessageID while loading the saved data. From that point on
# we get the messages in real time and don't ask the server to catch us up again, (or
# if we do, we can look at our in-memory history for that instead of taking time to update
# this for every message).

proc InitializeChatHistory {} {
	global ChatHistoryFile ChatHistory ChatHistoryFileHandle ChatHistoryLastMessageID
	global path_cache IThost ITport ChatHistoryLimit local_user

	if {$IThost ne {}} {
		set ChatHistoryFile [file join $path_cache "${IThost}-${ITport}-${local_user}-chat.history"]
		DEBUG 1 "Loading chat history from $ChatHistoryFile"
		if {! [file exists $ChatHistoryFile]} {
			DEBUG 1 "-Creating new file; did not find an existing one"
		} else {
			if [catch {set ChatHistoryFileHandle [open $ChatHistoryFile]} err] {
				DEBUG 0 "Unable to read chat history file $ChatHistoryFile ($err). We will try asking the server for a new history download."
				set ChatHistoryFileHandle {}
			} else {
				while {[gets $ChatHistoryFileHandle msg] >= 0} {
                    if {[IsMessageValid $msg]} {
                        switch -- [lindex $msg 0] {
                            TO		{ set ChatHistoryLastMessageID [expr max($ChatHistoryLastMessageID, [lindex $msg 4])] }
                            ROLL	{ set ChatHistoryLastMessageID [expr max($ChatHistoryLastMessageID, [lindex $msg 6])] }
                            CC		{ set ChatHistory {} }
                        }
                        lappend ChatHistory $msg
                    } else {
                        DEBUG 1 "InitializeChatHistory: rejecting invalid message $msg from $ChatHistoryFile"
                    }
				}
				close $ChatHistoryFileHandle
				set ChatHistoryFileHandle {}

				if {$ChatHistoryLimit > 0 && [llength $ChatHistory] > $ChatHistoryLimit} {
					DEBUG 1 "Chat history contains [llength $ChatHistory] items; trimming it back to $ChatHistoryLimit."
					if [catch {set ChatHistoryFileHandle [open $ChatHistoryFile w]} err] {
						DEBUG 0 "Unable to overwrite the chat history in $ChatHistoryFile ($err). No history will be kept now."
						set ChatHistoryFileHandle {}
					} else {
						set ChatHistory [lrange $ChatHistory end-$ChatHistoryLimit end]
						foreach msg $ChatHistory {
							puts $ChatHistoryFileHandle $msg
						}
						flush $ChatHistoryFileHandle
					}
				}
			}
		}

		if {$ChatHistoryFileHandle eq {}} {
			if [catch {set ChatHistoryFileHandle [open $ChatHistoryFile a]} err] {
				DEBUG 0 "Unable to append to or create chat history file $ChatHistoryFile ($err). No history will be kept."
				set ChatHistoryFileHandle {}
			}
		}
		DEBUG 1 "Chat history now has [llength $ChatHistory] items."
		if {$ChatHistoryLastMessageID <= 0} {
			if {$ChatHistoryLimit > 0} {
				DEBUG 1 "We don't have any loaded history; asking server for up to $ChatHistoryLimit messages."
				ITsend [list SYNC CHAT -$ChatHistoryLimit]
			} else {
				DEBUG 1 "We don't have any loaded history; asking server all messages."
				ITsend [list SYNC CHAT]
			}
		} else {
			DEBUG 1 "Asking server for any new messages since $ChatHistoryLastMessageID."
			ITsend [list SYNC CHAT $ChatHistoryLastMessageID]
		}
	}
}

set _last_known_message_id 0
# ChatHistoryAppend {CC _ _ ID}
# ChatHistoryAppend {ROLL _ _ _ _ _ ID}
# ChatHistoryAppend {TO _ _ _ ID}
# ChatHistoryAppend {-system * msg -1}

proc ChatHistoryAppend {event} {
	global ChatHistory ChatHistoryFileHandle _last_known_message_id
    if {[IsMessageValid $event]} {
        set mid [ChatMessageID $event]
        if {$mid eq {} || $mid < 0} {
            set mid ${_last_known_message_id}
        }
        if {$mid >= ${_last_known_message_id}} {
            lappend ChatHistory $event
            set _last_known_message_id $mid
            if {$ChatHistoryFileHandle ne {}} {
                puts $ChatHistoryFileHandle $event
                flush $ChatHistoryFileHandle
            }
        } else {
            DEBUG 1 "Rejected chat message $event; message ID $mid < ${_last_known_message_id}"
        }
    } else {
        DEBUG 1 "Rejected invalid chat message '$event'"
    }
}

proc PingMarker {w x y} {
	global zoom
	set cx [expr [$w canvasx $x] / $zoom]
	set cy [expr [$w canvasy $y] / $zoom]
	start_ping_marker $w $cx $cy 0
	ITsend [list MARK $cx $cy]
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
#
# Perform actions requested by command-line options now
#

report_progress "Adding party members"
foreach charToAdd $OptAddCharacters {
    set c_name [AcceptCreatureImageName [lindex $charToAdd 0]]
    .contextMenu add command -command "AddPlayer $c_name [lindex $charToAdd 1]" -label $c_name
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
report_progress "Drawing battle grid"
DrawScreen $zoom $animatePlacement
cleargrid
if {$ITpreamble && $IThost ne {}} {
    report_progress "Mapper Client Ready (awaiting server login to complete)"
} else {
    report_progress "Mapper Client Ready"
    after 5000 {report_progress {}}
}
