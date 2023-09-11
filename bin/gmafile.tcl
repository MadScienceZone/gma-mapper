########################################################################################
#  _______  _______  _______                ___        __    _______                   #
# (  ____ \(       )(  ___  ) Game         /   )      /  \  (  ____ \                  #
# | (    \/| () () || (   ) | Master's    / /) |      \/) ) | (    \/                  #
# | |      | || || || (___) | Assistant  / (_) (_       | | | (____                    #
# | | ____ | |(_)| ||  ___  |           (____   _)      | | (_____ \                   #
# | | \_  )| |   | || (   ) |                ) (        | |       ) )                  #
# | (___) || )   ( || )   ( | Mapper         | |   _  __) (_/\____) )                  #
# (_______)|/     \||/     \| Client         (_)  (_) \____/\______/                   #
#                                                                                      #
########################################################################################
#
# @[00]@| GMA-Mapper 4.15
# @[01]@|
# @[10]@| Copyright © 1992–2023 by Steven L. Willoughby (AKA MadScienceZone)
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
# Mapper JSON data handling functions.
# Steve Willoughby <steve@madscience.zone>
#
# Implements GMA Map File Version 21.
#
#

package provide gmafile 1.0
package require gmaproto 1.0
package require Tcl 8.5

namespace eval ::gmafile {
	variable version 22
	variable dice_version 2
	variable min_dice_version 1
	variable max_dice_version 2
	variable min_version 16
	variable max_version 22

	array set _data_payload {
		__META__ {Timestamp i DateTime s Comment s Location s}
		__DMETA__ {Timestamp i DateTime s Comment s}
		ARC      {ArcMode i Start f Extent f ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		CIRC     {ArcMode i Start f Extent f ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		CREATURE {ID s Name s Health {o {MaxHP i LethalDamage i NonLethalDamage i Con i IsFlatFooted ? IsStable ? Condition s HPBlur i}} Gx f Gy f Skin i SkinSize l Elev i Color s Note s Size s DispSize s StatusList l AoE {o {Radius f Color s}} MoveMode i Reach i Killed ? Dim ? CreatureType i Hidden ? CustomReach {o {Enabled ? Natural i Extended i}}}
		IMG      {Name s Sizes {a {File s ImageData b IsLocalFile ? Zoom f}} Animation {o {Frames i FrameSpeed i Loops i}}}
		LINE     {Arrow i ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		MAP      {File s IsLocalFile ? CacheOnly ? Merge ?}
		POLY     {Spline i Join i ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		RECT     {ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		SAOE     {AoEShape i ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		TEXT     {Text s Font {o {Family s Size f Weight i Slant i}} Anchor i ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		TILE     {Image s BBHeight f BBWidth f ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		PRESET   {Name s Description s DieRollSpec s}
	}
}


#
# save_to_file fileobj { meta {{type dict}, ...} }
# save_arrays_to_file fileobj metadict elements elementtypes creatures
#
proc ::gmafile::save_arrays_to_file {f meta elements elementtypes creatures {imagemap {}} {lock_objects false}} {
	set objlist {}
	upvar 1 $elements e
	upvar 1 $elementtypes t
	upvar 1 $creatures c
	if {$imagemap ne {}} {
		upvar 1 $imagemap imap
	} else {
		array unset imap
	}

	foreach id [array names e] {
		set d $e($id)

		if {![info exists t($id)]} {
			::gmafile::_diag "WARNING: Saving map element $id which has no type (not saved)"
			::DEBUG 0 "WARNING: Saving map element $id which has no type (not saved)"
			continue
		}
		
		if {$id ne [dict get $d ID]} {
			::gmafile::_diag "WARNING: Saving map element $id ($t($id)): it thinks its ID is [dict get $d ID]"
			::DEBUG 0 "WARNING: Saving map element $id ($t($id)): it thinks its ID is [dict get $d ID]"
		}

		if [catch {set ot [::gmaproto::ObjTypeToGMAType $t($id)]} err] {
			::gmafile::_diag "WARNING: Saving map element $id ($t($id)): $err (not saved)"
			::DEBUG 0 "WARNING: Saving map element $id ($t($id)): $err (not saved)"
			continue
		}

		if {$lock_objects} {
			dict set d Locked true
		}
		lappend objlist [list $ot $d]
	}

	foreach id [array names c] {
		set d $c($id)
		if {[dict exists $d Name] && [info exists imap([dict get $d Name])]} {
			set d [dict replace $d Name "$imap([dict get $d Name])=[dict get $d Name]"]
		}
		lappend objlist [list CREATURE $d]
	}

	::gmafile::save_to_file $f [list $meta $objlist]
}

proc ::gmafile::save_to_file {f objlist} {
	puts $f "__MAPPER__:$::gmafile::version"
	lassign $objlist meta objs
	if {![dict exists $meta Timestamp]} {
		set now [clock seconds]
		dict set meta Timestamp $now 
		dict set meta DateTime [clock format $now -format "%d-%b-%Y %H:%M:%S"]
	} elseif {![dict exists $meta DateTime]} {
		dict set meta DateTime [clock format [dict get $meta Timestamp] -format "%d-%b-%Y %H:%M:%S"]
	}
	::json::write aligned true
	::json::write indented true
	puts $f "\u00ab__META__\u00bb [::gmaproto::_encode_payload $meta $::gmafile::_data_payload(__META__)]"
	foreach r $objs {
		lassign $r record_type record_data
		if {![info exists ::gmafile::_data_payload($record_type)]} {
			error "unable to save record of type '$record_type' to map file"
		}
		puts $f "\u00ab${record_type}\u00bb [::gmaproto::_encode_payload $record_data $::gmafile::_data_payload($record_type)]"
	}
	puts $f "\u00ab__EOF__\u00bb"
}

#
# load_from_file fileobj -> { meta {{type dict}, ...} }
# Reads mapper object data from the given file into the named array variable
#
proc ::gmafile::load_from_file {f} {
	set vid 0
	set objlist {}
	set meta {}
	
	# initial line MUST now be __MAPPER__:<version>
	# if there is anything after that on the first line we can safely ignore it
	if {[gets $f v] >= 0} {
		if {[regexp {^__MAPPER__:([0-9]+)\s*(.*)$} $v vv vid oldmeta]} {
			if {$vid > $::gmafile::max_version} {
				error "map file is version $vid which is newer than this version of the mapper can read"
			}
			if {$vid < $::gmafile::min_version} {
				error "map file is version $vid which is older than this mapper's minimum supported version ($::gmafile::min_version)"
			}
			if {$vid < 20} {
				return [::gmafile::load_legacy_map_file $f $vid [lindex $oldmeta 0]]
			}
		} else {
			error "map file does not begin with the required __MAPPER__ header line"
		}
	} else {
		error "unable to read from map file"
	}

	::gmafile::_diag "Loading map file..."

	set json_data {}
	set rescan true
	while {[gets $f v] >= 0} {
		while $rescan {
			set rescan false

			if {$v eq {}} {
				continue
			}

			if {$v eq "\u00ab__EOF__\u00bb"} {
				return [list $meta $objlist]
			}

			#
			# start of __type__ json
			#
			if {![regexp "^\u00ab(.*?)\u00bb (.+)\$" $v vv record_type json_data]} {
				error "invalid map file format: unexpected data"
			}
			#
			# look for start of next record
			#
			while {[set status [gets $f v]] >= 0} {
				if {[string range $v 0 0] eq "\u00ab"} {
					#
					# we've read the whole packet now; process it
					#
					if {[info exists ::gmafile::_data_payload($record_type)]} {
						set data [::gmaproto::_construct [::json::json2dict $json_data] $::gmafile::_data_payload($record_type)]
						if {$record_type eq {__META__}} {
							set meta $data
						} else {
							lappend objlist [list $record_type $data]
						}
						set json_data {}
						set record_type {}
						set rescan true
						break
					} else {
						error "map file contains unrecognized record type $record_type"
					}
				} else {
					append json_data $v
				}
			}
			if {$status < 0} {
				break
			}
		}
	}
	dict set meta FileVersion $vid
	error "invalid map file: unexpected end of file"
}


#
# Load up a pre-version-20 data file
# returns the same value as load_from_file, but uses RAW fields
# with old-style (untranslated) data lines, so they are suitable to directly
# insert into the arrays
#
proc ::gmafile::load_legacy_map_file {f vid oldmeta} {
	set meta_timestamp  {}
	set LastFileComment {}
	set meta [dict create FileVersion $vid]

	if {$vid >= 12} {
		if {[llength $oldmeta] < 2} {
			error "Map file is a version $vid file, but the metadata field is incorrect. Not reading this file."
		}
		if {[llength [lindex $oldmeta 1]] < 2} {
			dict set meta Timestamp [lindex $oldmeta 1]
			dict set meta DateTime  [lindex $oldmeta 1]
		} else {
			dict set meta Timestamp [lindex [lindex $oldmeta 1] 0]
			dict set meta DateTime  [lindex [lindex $oldmeta 1] 1]
		}
		dict set meta Comment [lindex $oldmeta 0]
		dict set meta Location [lindex $oldmeta 0]
	} else {
		error "Map file has no metadata. Not loaded since it's probably in an old format."
	}

	set file_lines {}
	while {[gets $f v] >= 0} {
		lappend file_lines $v
	}
	return [::gmafile::load_legacy_map_data $file_lines $meta]
}

# load_legacy_map_data lines metadict -> metadict objlist
# objlist is:
#   IMG	dict<Name:<id>,Sizes:[dict<File,ImageData,IsLocalFile,Zoom>,...]>
#   MAP dict<File,IsLocalFile,CacheOnly,Merge>
#   RAW line
#
proc ::gmafile::load_legacy_map_data {vlist meta} {
	::gmafile::_diag "Loading [llength $vlist] from [dict get $meta Comment]..."
	set imagedict {}
	set file_data {}

	foreach v $vlist {
		if [catch {set LL [llength $v]} err] {
			error "Error loading file: $err"
		}
		if {[string range $v 0 10] eq {__MAPPER__:}} {
			error "Metadata line must appear first in map file, not later."
		}
		#
		# I id zoom file	-> imagedict id zoom = file	(local unless starts with @)
		# F id				-> MAP {File id IsLocalFile f CacheOnly t Merge f}
		# other				-> RAW {whole line}
			
		if {$LL == 4 && [lindex $v 0] eq "I"} {
			lassign $v _ image_id image_zoom image_filename
			dict set imagedict $image_id $image_zoom $image_filename
		} elseif {$LL == 2 && [lindex $v 0] eq "F"} {
			lappend file_data [list MAP [dict create File [lindex $v 1] IsLocalFile false CacheOnly true Merge false]]
		} else {
			lappend file_data [list RAW $v]
		}
		::DEBUG 3 "in: $v"
	}
	::DEBUG 3 "read images: [dict size $imagedict] elements: [llength $file_data]"

	foreach image_id [dict keys $imagedict] {
		set image_data [dict create Name $image_id Animation {}]
		foreach image_size [dict keys [dict get $imagedict $image_id]] {
			set filename [dict get $imagedict $image_id $image_size]
			if {[string range $filename 0 0] eq "@"} {
				dict lappend image_data Sizes [dict create \
					File [string range $filename 1 end] \
					ImageData {} \
					IsLocalFile false \
					Zoom $image_size]
			} else {
				dict lappend image_data Sizes [dict create \
					File $filename
					ImageData {} \
					IsLocalFile true \
					Zoom $image_size]
			}
		}
		lappend file_data [list IMG $image_data]
		DEBUG 3 "added IMG $image_data"
	}
	return [list $meta [::gmafile::upgrade_elements $file_data]]
}

proc ::gmafile::_diag {message} {
	puts $message
}

# convert_elements filedata -> dictlist
# Converts old-style RAW stream elements to new-style dictionaries
proc ::gmafile::upgrade_elements {filedata} {
	array unset OldObjs
	array unset OldMobs
	set new_filedata {}
	foreach record $filedata {
		lassign $record element_type element_data
		if {$element_type eq "RAW"} {
			if {[lindex $element_data 0] eq "P" || [lindex $element_data 0] eq "M"} {
				# P <attr>:<id> <data>		player obj attribute
				# M <attr>:<id> <data>		monster obj attribute
				set OldMobs([lindex $element_data 1]) [lindex $element_data 2]
			} else {
				# <attr>:<id> <data>		map element obj attribute
				set OldObjs([lindex $element_data 0]) [lindex $element_data 1]
			}
		} else {
			# keep new-style elements as-is
			lappend new_filedata $record
		}
	}

	# Now collect creature information and emit new records for them
	foreach mob_id [array names OldMobs NAME:*] {
		set mob_id [string range $mob_id 5 end]
		::gmafile::require_arr OldMobs $mob_id NAME
		::gmafile::default_arr OldMobs $mob_id -value 0 GX GY SKIN ELEV REACH KILLED DIM
		::gmafile::default_arr OldMobs $mob_id HEALTH MOVEMODE COLOR NOTE SKIN SKINSIZE SIZE STATUSLIST AOE 

		if {$OldMobs(HEALTH:$mob_id) eq {}} {
			set health {}
		} else {
			lassign $OldMobs(HEALTH:$mob_id) max ld nld con ff stab cond blur
			set health [dict create MaxHP $max LethalDamage $ld NonLethalDamage $nld Con $con IsFlatFooted $ff IsStable $stab Condition $cond HPBlur $blur]
		}
		if {$OldMobs(AOE:$mob_id) eq {}} {
			set aoe {}
		} else {
			lassign $OldMobs(AOE:$mob_id) r c
			set aoe [dict create Radius $r Color $c]
		}

		lappend new_filedata [list CREATURE [dict create \
			ID $mob_id \
			Name $OldMobs(NAME:$mob_id) \
			Health $health \
			Gx $OldMobs(GX:$mob_id) \
			Gy $OldMobs(GY:$mob_id) \
			Skin $OldMobs(SKIN:$mob_id) \
			SkinSize $OldMobs(SKINSIZE:$mob_id) \
			Elev $OldMobs(ELEV:$mob_id) \
			Color $OldMobs(COLOR:$mob_id) \
			Note $OldMobs(NOTE:$mob_id) \
			Size $OldMobs(SIZE:$mob_id) \
			DispSize $OldMobs(SIZE:$mob_id) \
			StatusList $OldMobs(STATUSLIST:$mob_id) \
			AoE  $aoe \
			MoveMode [::gmaproto::to_enum MoveMode $OldMobs(MOVEMODE:$mob_id)] \
			Reach $OldMobs(REACH:$mob_id) \
			Killed $OldMobs(KILLED:$mob_id) \
			Dim $OldMobs(DIM:$mob_id) \
			CreatureType [::gmaproto::to_enum CreatureType $OldMobs(TYPE:$mob_id)] \
		]]
	}

	# Now do the same with other map elements
	foreach obj_id [array names OldObjs TYPE:*] {
		set obj_id [string range $obj_id 5 end]
		require_arr OldObjs $obj_id X Y Z
		default_arr OldObjs $obj_id -value 0 WIDTH HIDDEN LOCKED
		default_arr OldObjs $obj_id POINTS LINE FILL LAYER LEVEL GROUP DASH
		set obj_type $OldObjs(TYPE:$obj_id)

		switch -exact -- $obj_type {
			arc {
				default_arr OldObjs $obj_id -value 0 START EXTENT
				default_arr OldObjs $obj_id ARCMODE
			}
			circ {
			}
			line {
				default_arr OldObjs $obj_id ARROW
			}
			poly {
				default_arr OldObjs $obj_id -value 0 SPLINE
				default_arr OldObjs $obj_id JOIN
			}
			rect {
			}
			saoe {
				require_arr OldObjs $obj_id AOESHAPE
#				default_arr OldObjs $obj_id ARCMODE START EXTENT
			}
			text {
				require_arr OldObjs $obj_id TEXT FONT
				default_arr OldObjs $obj_id ANCHOR
			}
			tile {
				default_arr OldObjs $obj_id -value 0 BBHEIGHT BBWIDTH
				default_arr OldObjs $obj_id IMAGE
			}
			default {
				error "map element of unsupported type $obj_type"
			}
		}

		set points {}
		foreach {x y} $OldObjs(POINTS:$obj_id) {
			lappend points [dict create X $x Y $y]
		}

		set element [dict create \
			ID $obj_id \
			X $OldObjs(X:$obj_id) \
			Y $OldObjs(Y:$obj_id) \
			Points $points \
			Z $OldObjs(Z:$obj_id) \
			Line $OldObjs(LINE:$obj_id) \
			Fill $OldObjs(FILL:$obj_id) \
			Width $OldObjs(WIDTH:$obj_id) \
			Layer $OldObjs(LAYER:$obj_id) \
			Level $OldObjs(LEVEL:$obj_id) \
			Group $OldObjs(GROUP:$obj_id) \
			Dash [::gmaproto::to_enum Dash $OldObjs(DASH:$obj_id)] \
			Hidden $OldObjs(HIDDEN:$obj_id) \
			Locked $OldObjs(LOCKED:$obj_id) \
		]

		switch -exact -- $obj_type {
			arc {
				dict set element ArcMode [::gmaproto::to_enum ArcMode $OldObjs(ARCMODE:$obj_id)]
				dict set element Start $OldObjs(START:$obj_id)
				dict set element Extent $OldObjs(EXTENT:$obj_id)
				lappend new_filedata [list ARC $element]
			}
			circ {
#				dict set element ArcMode [::gmaproto::to_enum ArcMode $OldObjs(ARCMODE:$obj_id)]
#				dict set element Start $OldObjs(START:$obj_id)
#				dict set element Extent $OldObjs(EXTENT:$obj_id)
				lappend new_filedata [list CIRC $element]
			}
			line {
				dict set element Arrow [::gmaproto::to_enum Arrow $OldObjs(ARROW:$obj_id)]
				lappend new_filedata [list LINE $element]
			}
			poly {
				dict set element Spline $OldObjs(SPLINE:$obj_id)
				dict set element Join [::gmaproto::to_enum Join $OldObjs(JOIN:$obj_id)]
				lappend new_filedata [list POLY $element]
			}
			rect {
				lappend new_filedata [list RECT $element]
			}
			saoe {
				set shape [::gmaproto::to_enum AoEShape $OldObjs(AOESHAPE:$obj_id)]
				dict set element AoEShape $shape
				if {$shape == 0 || $shape == 1} {
#					dict set element ArcMode [::gmaproto::to_enum ArcMode $OldObjs(ARCMODE:$obj_id)]
#					dict set element Start $OldObjs(START:$obj_id)
#					dict set element Extent $OldObjs(EXTENT:$obj_id)
				}
						
				lappend new_filedata [list SAOE $element]
			}
			text {
				# value is {family size normal underline bold overstrike roman italic}
				lassign [lindex $OldObjs(FONT:$obj_id) 0] family size
				set weight 0
				set slant 0
				if {[info exists OldObjs(ANCHOR:$obj_id)]} {
					set anchor [::gmaproto::to_enum Anchor $OldObjs(ANCHOR:$obj_id)]
				} else {
					set anchor 0
				}

				foreach option [lrange $OldObjs(FONT:$obj_id) 2 end] {
					switch -exact -- $option {
						normal { set weight 0 }
						bold   { set weight 1 }
						roman  { set slant 0  }
						italic { set slant 1  }
					}
				}
				dict set element Text $OldObjs(TEXT:$obj_id)
				dict set element Font [dict create \
					Family $family \
					Size $size \
					Weight $weight \
					Slant $slant
				]
				dict set element Anchor [::gmaproto::to_enum Anchor $anchor]
				lappend new_filedata [list TEXT $element]
			} 
			tile {
				dict set element Image $OldObjs(IMAGE:$obj_id)
				dict set element BBHeight $OldObjs(BBHEIGHT:$obj_id)
				dict set element BBWidth $OldObjs(BBWIDTH:$obj_id)
				lappend new_filedata [list TILE $element]
			}
			default {
				::gmafile::_diag "Ignoring object $obj_id since we can't figure out what it is."
			}
		}
	}
	return $new_filedata
}

proc ::gmafile::require_arr {aname id args} {
	upvar $aname arr
	foreach a $args {
		if {![info exists arr($a:$id)]} {
			error "object $id missing required attribute $a"
		}
	}
}

# default_arr arrayname objid ?-value v? ?--? attr ?...?
proc ::gmafile::default_arr {aname id args} {
	upvar $aname arr
	set value {}
	
	while {[string range [lindex $args 0] 0 0] eq "-"} {
		set optname [::gmautil::lpop args 0]
		if {$optname eq "--"} {
			break
		} elseif {$optname eq "-value"} {
			if {[llength $args] < 1} {
				error "-value option requires an argument"
			}
			set value [::gmautil::lpop args 0]
		} else {
			error "unknown option $optname; must be -value or --"
		}
	}
	if {[llength $args] < 1} {
		error "default_arr requires at least one attribute name"
	}

	foreach a $args {
		if {![info exists arr($a:$id)]} {
			set arr($a:$id) $value
		}
	}
}
proc ::gmafile::save_dice_presets_to_file {f objlist} {
	puts $f "__DICE__:$::gmafile::dice_version"
	lassign $objlist meta presets
	if {![dict exists $meta Timestamp]} {
		set now [clock seconds]
		dict set meta Timestamp $now 
		dict set meta DateTime [clock format $now -format "%d-%b-%Y %H:%M:%S"]
	} elseif {![dict exists $meta DateTime]} {
		dict set meta DateTime [clock format [dict get $meta Timestamp] -format "%d-%b-%Y %H:%M:%S"]
	}
	::json::write aligned true
	::json::write indented true
	puts $f "\u00ab__META__\u00bb [::gmaproto::_encode_payload $meta $::gmafile::_data_payload(__DMETA__)]"
	foreach r $presets {
		puts $f "\u00abPRESET\u00bb [::gmaproto::_encode_payload $r $::gmafile::_data_payload(PRESET)]"
	}
	puts $f "\u00ab__EOF__\u00bb"
}

# returns {<meta> <list of preset dicts>}
proc ::gmafile::load_dice_presets_from_file {f} {
	set vid 0
	set objlist {}
	set meta {}
	
	# initial line MUST now be __DICE__:<version>
	# if there is anything after that on the first line we can safely ignore it
	if {[gets $f v] >= 0} {
		if {[regexp {^__DICE__:([0-9]+)\s*(.*)$} $v vv vid oldmeta]} {
			if {$vid > $::gmafile::max_dice_version} {
				error "die roll preset file is version $vid which is newer than this version of the mapper can read"
			}
			if {$vid < $::gmafile::min_dice_version} {
				error "die roll preset file is version $vid which is older than this mapper's minimum supported version ($::gmafile::min_dice_version)"
			}
			if {$vid < 2} {
				return [::gmafile::load_legacy_preset_file $f $vid [lindex $oldmeta 0]]
			}
		} else {
			error "file does not begin with the required __DICE__ header line"
		}
	} else {
		error "unable to read from die roll preset file"
	}

	::gmafile::_diag "Loading die-roll preset file..."

	set json_data {}
	set rescan true
	while {[gets $f v] >= 0} {
		while $rescan {
			set rescan false

			if {$v eq {}} {
				continue
			}

			if {$v eq "\u00ab__EOF__\u00bb"} {
				dict set meta FileVersion $vid
				return [list $meta $objlist]
			}

			#
			# start of __type__ json
			#
			if {![regexp "^\u00ab(.*?)\u00bb (.+)\$" $v vv record_type json_data]} {
				error "invalid map file format: unexpected data"
			}
			#
			# look for start of next record
			#
			while {[set status [gets $f v]] >= 0} {
				if {[string range $v 0 0] eq "\u00ab"} {
					#
					# we've read the whole packet now; process it
					#
					if {$record_type eq {__META__}} {
						set meta [::gmaproto::_construct [::json::json2dict $json_data] $::gmafile::_data_payload(__DMETA__)]
					} elseif {$record_type eq {PRESET}} {
						lappend objlist [::gmaproto::_construct [::json::json2dict $json_data] $::gmafile::_data_payload(PRESET)]
					} else {
						error "die roll preset file contains unrecognized record type $record_type"
					}
					set json_data {}
					set record_type {}
					set rescan true
					break
				} else {
					append json_data $v
				}
			}
			if {$status < 0} {
				break
			}
		}
	}
	error "invalid die roll preset file: unexpected end of file"
}

proc ::gmafile::load_legacy_preset_file {f vid oldmeta} {
	set meta [dict create FileVersion $vid Comment {} DateTime {} Timestamp 0]
	set plist {}

	if {[llength $oldmeta] > 0} {
		dict set meta Timestamp [lindex $oldmeta 0]
		if {[llength $oldmeta] > 1} {
			dict set meta DateTime [lindex $oldmeta 1]
		} else {
			dict set meta DateTime [clock format [lindex $oldmeta 0] -format "%d-%b-%Y %H:%M:%S"]
		}
	}

	while {[gets $f v] >= 0} {
		if {$v eq {}} {
			continue
		}
		if {[llength $v] == 3} {
			lappend plist [dict create \
				Name [lindex $v 0] \
				Description [lindex $v 1] \
				DieRollSpec [lindex $v 2] \
			]
		} else {
			error "Invalid line in legacy die-roll preset file: $v"
		}
	}
	return [list $meta $plist]
}
# @[00]@| GMA-Mapper 4.15
# @[01]@|
# @[10]@| Copyright © 1992–2023 by Steven L. Willoughby (AKA MadScienceZone)
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
