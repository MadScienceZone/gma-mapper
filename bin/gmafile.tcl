########################################################################################
#  _______  _______  _______                ___          ___       ______              #
# (  ____ \(       )(  ___  )              /   )        /   )     / ___  \             #
# | (    \/| () () || (   ) |             / /) |       / /) |     \/   \  \            #
# | |      | || || || (___) |            / (_) (_     / (_) (_       ___) /            #
# | | ____ | |(_)| ||  ___  |           (____   _)   (____   _)     (___ (             #
# | | \_  )| |   | || (   ) | Game           ) (          ) (           ) \            #
# | (___) || )   ( || )   ( | Master's       | |   _      | |   _ /\___/  /            #
# (_______)|/     \||/     \| Assistant      (_)  (_)     (_)  (_)\______/             #
#                                                                                      #
########################################################################################
#
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
# Mapper JSON data handling functions.
# Steve Willoughby <steve@madscience.zone>
#
# Implements GMA Map File Version 20.
#
#

package require gmaproto 0.1
package require Tcl 8.5

namespace eval ::gmafile {
	variable version 20
	variable min_version 16
	variable max_version 20

	array set _data_payload {
		META     {Timestamp i DateTime s Comment s Location s}
		ARC      {ArcMode i Start f Extent f ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		CIRC     {ArcMode i Start f Extent f ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		CREATURE {ID s Name s Health {o {MaxHP i LethalDamage i NonLethalDamage i Con i IsFlatFooted ? IsStable ? Condition s HPBlur i}} Gx f Gy f Skin i SkinSize l Elev i Color s Note s Size s Area s StatusList l AoE {o {Radius f Color s}} MoveMode i Reach i Killed ? Dim ? CreatureType i}
		IMG      {Name s Sizes {a {File s ImageData b IsLocalFile ? Zoom f}}}
		LINE     {Arrow i ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		MAP      {File s IsLocalFile ? CacheOnly ? Merge ?}
		POLY     {Spline f Join i ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		RECT     {ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		SAOE     {AoEShape i ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		TEXT     {Text s Font {o {Family s Size f Weight i Slant i Anchor i}} ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		TILE     {Image s BBHeight f BBWidth f ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
	}
}

#
# save_to_file fileobj { meta {{type dict}, ...} }
#
proc ::gmafile::save_to_file {f objlist} {
	puts $f "__MAPPER__:$::gmafile::version"
	lassign $objlist meta objs
	if {![dict exists $meta Timestamp]} {
		set now [clock seconds]
		dict set meta Timestamp $now DateTime [clock format $now -format "%d-%b-%Y %H:%M:%S"]
	} elseif {![dict exists $meta DateTime]} {
		dict set meta DateTime [clock format [dict get $meta Timestamp] -format "%d-%b-%Y %H:%M:%S"]
	}
	::json::write aligned true
	::json::write indented true
	puts $f "__META__ [::gmaproto::_encode_payload $meta $::gmafile::_data_payload(META)]"
	foreach r $objs {
		lassign $r record_type record_data
		if {![info exists ::gmafile::_data_payload($record_type)]} {
			error "unable to save record of type '$record_type' to map file"
		}
		puts $f "__${record_type}__ [::gmaproto::_encode_payload $record_data $::gmafile::_data_payload($record_type)]"
	}
	puts $f "__EOF__"
}

#
# load_file fileobj -> { meta {{type dict}, ...} }
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

	dict set meta Version $vid
	set json_data {}
	set rescan true
	while {[gets $f v] >= 0} {
		while $rescan {
			set rescan false

			if {$v eq {}} {
				continue
			}

			if {$v eq "__EOF__"} {
				return [list $meta $objlist]
			}

			#
			# start of __type__ json
			#
			if {![regexp {^__(.*?)__ (.+)$} $v vv record_type json_data]} {
				error "invalid map file format: unexpected data"
			}
			#
			# look for start of next record
			#
			while {[gets $f v] >= 0} {
				if {[string range $v 0 1] eq "__"} {
					#
					# we've read the whole packet now; process it
					#
					if {[info exists ::gmafile::_data_payload($record_type)]} {
						set data [::gmaproto::_construct [::json::json2dict $json_data] $::gmafile::_data_payload($record_type)]
						if {$record_type eq {META}} {
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
		}
	}
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
	set meta [dict create Version $vid]

	puts "f=$f,vid=$vid,oldmeta=$oldmeta"
	if {$vid >= 12} {
		if {[llength $oldmeta] < 2} {
			error "Map file is a version $vid file, but the metadata field is incorrect. Not reading this file."
		}
		if {[llength [lindex $oldmeta 1]] < 2} {
			dict set meta Timestamp [lindex $oldmeta 1]
			dict set meta Datetime  [lindex $oldmeta 1]
		} else {
			dict set meta Timestamp [lindex [lindex $oldmeta 1] 0]
			dict set meta Datetime  [lindex [lindex $oldmeta 1] 1]
		}
		dict set meta Comment [lindex $oldmeta 0]
		dict set meta Location [lindex $oldmeta 0]
	} else {
		error "Map file has no metadata. Not loaded since it's probably in an old format."
	}

	::gmafile::_diag "Loading [dict get $meta Comment]..."
	set imagedict {}
	set file_data {}

	while {[gets $f v] >= 0} {
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
	}

	foreach image_id [dict keys $imagedict] {
		set image_data [dict create Name $image_id]
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
	}
	return [list $meta $file_data]
}

proc ::gmafile::_diag {message} {
	puts $message
}
