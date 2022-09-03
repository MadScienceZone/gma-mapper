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
# Mapper JSON protocol handling functions.
# Steve Willoughby <steve@madscience.zone>
#
# Implements GMA Mapper Protocol 400.
# // ... \n		ignored
# <command> <json> \n
#
# Server negotiation:
# server -> initial greeting (AC, DSM, UPDATES, WORLD)
# server -> OK
#           AUTH <- client		IF authentication required
# server -> GRANTED/DENIED		IF authentication required
# server -> more greeting (AC, DSM, UPDATES, WORLD)
# server -> READY
#

package provide gmaproto 0.1
package require Tcl 8.5
package require json 1.3.4
package require json::write 1.0.3
package require base64 2.4.2
package require uuid 1.0.1

namespace eval ::gmaproto {
	variable protocol 400
	variable min_protocol 400
	variable max_protocol 400

	variable _message_map
	array set _message_map {
		add_image                 AI
		add_obj_attributes        OA+
		adjust_view               AV
		chat_message              TO
		clear                     CLR
		clear_chat                CC
		clear_from                CLR@
		combat_mode               CO
		comment                   //
		load_from                 L
		load_arc                  LS-ARC
		load_circle               LS-CIRC
		load_line                 LS-LINE
		load_polygon              LS-POLY
		load_rectangle            LS-RECT
		load_spell_area_of_effect LS-SAOE
		load_text                 LS-TEXT
		load_tile                 LS-TILE
		marco                     MARCO
		mark                      MARK
		place_someone             PS
		query_image               AI?
		remove_obj_attributes     OA-
		roll_result               ROLL
		toolbar                   TB
		update_clock              CS
		update_dice_presets       DD=
		update_initiative_list    IL
		update_obj_attributes     OA
		update_peer_list          CONN
		update_progress           PROGRESS
		update_status_marker      DSM
		update_turn               I
	}
	array set _message_payload {
		AC      {Name s ObjID s Color s Area s Size s}
		ACCEPT  {Messages l}
		AI      {Name s Sizes {a {File s ImageData b IsLocalFile ? Zoom f}}}
		AI?	    {Name s Sizes {a {Zoom f}}}
		ALLOW   {Features l}
		AUTH    {Client s Response b User s}
		AV      {XView f YView f}
		CC      {RequestedBy s DoSilently ? Target i MessageID i}
		CLR     {ObjID s}
		CLR@    {File s IsLocalFile ?}
		CO      {Enabled ?}
		CONN    {PeerList {a {Addr s User s Client s LastPolo f IsAuthenticated ? IsMe ? IsMain ? IsWriteOnly ?}}}
		CS      {Absolute f Relative f}
		D       {Recipients l ToAll ? ToGM ? RollSpec s}
		DD      {For s Presets {a {Name s Description s DieRollSpec s}}}
		DD+     {For s Presets {a {Name s Description s DieRollSpec s}}}
		DD/     {For s Filter s}
		DD=     {Presets {a {Name s Description s DieRollSpec s}}}
		DENIED  {Reason s}
		DR      {}
		DSM     {Condition s Shape s Color s Description s}
		GRANTED {User s}
		I       {ActorID s Hours i Minutes i Seconds i Rounds i Count i}
		IL      {InitiativeList {a {Slot i CurrentHP i Name s IsHolding ? HasReadiedAction ? IsFlatFooted ?}}}
		L       {File s IsLocalFile ? CacheOnly ? Merge ?}
		LS-ARC  {ArcMode i Start f Extent f ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		LS-CIRC {ArcMode i Start f Extent f ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		LS-LINE {Arrow i ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		LS-POLY {Spline f Join i ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		LS-RECT {ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		LS-SAOE {AoEShape i ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		LS-TEXT {Text s Font {o {Family s Size f Weight i Slant i Anchor i}} ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		LS-TILE {Image s BBHeight f BBWidth f ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		MARCO   {}
		MARK    {X f Y f}
		OA      {ObjID s NewAttrs d}
		OA+     {ObjID s AttrName s Values l}
		OA-     {ObjID s AttrName s Values l}
		OK      {Protocol i Challenge b}
		PRIV    {Command s Reason s}
		POLO    {}
		PROGRESS {OperationID s Title s Value i MaxValue i IsDone ?}
		PS      {ID s Name s Health {o {MaxHP i LethalDamage i NonLethalDamage i Con i IsFlatFooted ? IsStable ? Condition s HPBlur i}} Gx f Gy f Skin i SkinSize l Elev i Color s Note s Size s Area s StatusList l AoE {o {Radius f Color s}} MoveMode i Reach i Killed ? Dim ? CreatureType i}
		READY   {}
		ROLL    {Sender s Recipients l MessageID i ToAll ? ToGM ? Title s Result {o {Result i Details {a {Type s Value s}}}}}
		SYNC    {}
		SYNC-CHAT {Target i}
		TB      {Enabled ?}
		TO      {Sender s Recipients l MessageID i ToAll ? ToGM ? Text s}
		UPDATES {Packages {a {Name s Instances {a {OS s Arch s Version s Token s}}}}}
		WORLD   {Calendar s}
		/CONN   {}
	}
	variable all_messages {}
	foreach {_ v} [array get _message_map] {lappend all_messages $v}

	variable _enum_encodings [dict create \
		Dash     {{} - , . -. -..} \
		ArcMode  {pieslice arc chord} \
		Arrow    {none first last both} \
		Join     {bevel miter round} \
		AoEShape {cone radius ray} \
		Weight   {normal bold} \
		Slant    {roman italic} \
		Anchor   {center n s e w ne nw sw se} \
		MoveMode {land burrow climb fly swim} \
	    CreatureType {unknown monster player} \
	]
}

proc ::gmaproto::to_enum {key value} {
	if {![dict exists $::gmaproto::_enum_encodings $key]} {
		error "no such enum type $key"
	}
	if {$value eq {}} {
		return 0
	}
	if {[set idx [lsearch -exact [dict get $::gmaproto::_enum_encodings $key] $value]] < 0} {
		return 0
	}
	return $idx
}

proc ::gmaproto::from_enum {key value} {
	if {![dict exists $::gmaproto::_enum_encodings $key]} {
		error "no such enum type $key"
	}
	if {$value < 0 || $value >= [llength [dict get $::gmaproto::_enum_encodings $key]]} {
		error "enum value $value out of range for $key"
	}
	return [lindex [dict get $::gmaproto::_enum_encodings $key] $value]
}


#
# _protocol_send command ?name value ...?
#
proc ::gmaproto::_protocol_send {command args} {
	#
	# encode as JSON, eliminating zero fields and ones not mentioned in the protocol spec
	#
	if {![info exists ::gmaproto::_message_payload($command)]} {
		error "protocol command $command is not valid"
	}

	if {[llength $::gmaproto::_message_payload($command)] == 0} {
		set message $command
	} else {
		::json::write aligned false
		::json::write indented false
		set message "$command "
		append message [::gmaproto::_encode_payload $args $::gmaproto::_message_payload($command)]
	}
	# TODO send $message
	return "-> <$message>" 
}

proc ::gmaproto::_encode_payload {input_dict type_dict} {
	set a [dict create]
	foreach {f t} $type_dict {
		if {[dict exists $input_dict $f]} {
			set v [dict get $input_dict $f]
			switch -exact -- [lindex $t 0] {
				s {
					if {$v ne {}} {
						dict set a $f [::json::write string $v]
					}
				}
				l {
					if {[llength $v] > 0} {
						set ss {}
						foreach s $v {
							lappend ss [::json::write string $s]
						}
						dict set a $f [::json::write array {*}$ss]
					}
				}
				i {
					if {$v != "" && [string is integer $v] && $v != 0} {
						dict set a $f $v
					}
				}
				f {
					if {$v != "" && [string is double $v] && $v != 0.0} {
						dict set a $f  $v
					}
				}
				? {
					if {[string is true -strict $v]} {
						dict set a $f true
					} 
				}
				b {
					if {$v ne {}} {
						dict set a $f [::json::write string [::base64::encode -maxlen 0 $v]]
					}
				}
				o {
					if {$v ne {}} {
						dict set a $f [::gmaproto::_encode_payload $v [lindex $t 1]]
					}
				}
				a {
					if {[llength $v] > 0} {
						set vlist {}
						foreach obj $v {
							lappend vlist [::gmaproto::_encode_payload $obj [lindex $t 1]]
						}
						dict set a $f [::json::write array {*}$vlist]
					}
				}
				d {
					if {[dict size $v] > 0} {
						dict set a $f [::json::write object {*}[dict map {dk dv} $v {
							set dv [::json::write string $dv]
						}]]
					}
				}
				default {
					error "bug: unrecognized type code $t"
				}
			}
		}
	}
	return [::json::write object {*}$a]
}

proc ::gmaproto::_show {} {
	namespace eval ::gmaproto {
		global protocol min_protocol max_protocol all_messages
		puts "GMA Mapper Protocol $protocol ($min_protocol..$max_protocol)"
		puts "all messages: $all_messages"
	}
}

#
# parse a raw text line received
# Returns list with command name in element 0 or UNDEFINED or ERROR
# The remaining elements hold data relevant to that command
# 	In case of a parsing error the result is {ERROR <description> <raw_line>}
# 	If the command is not recognized, returns {UNDEFINED <raw_line>}
# 	Comments are returned as {// <raw_line>}, which includes the // in the <raw_line>.
#
proc ::gmaproto::parse_data_packet {raw_line} {
	set raw_line [string trim $raw_line]
	if {[string range $raw_line 0 1] eq "//"} {
		return [list // $raw_line]
	}
	if {[set delim [string first " " $raw_line]] > 0} {
		set command [string range $raw_line 0 [expr $delim - 1]]
		set payload [string trim [string range $raw_line [expr $delim + 1] end]]
		if {$payload ne {}} {
			if {[catch {set json_payload [::json::json2dict $payload]} err]} {
				return [list ERROR [list $err $raw_line]]
			}
		} else {
			set json_payload {}
		}
	} else {
		set command $raw_line
		set json_payload {}
	}

	if {[info exists ::gmaproto::_message_payload($command)]} {
		return [list $command [::gmaproto::_construct $json_payload $::gmaproto::_message_payload($command)]]
	} else {
		return [list UNDEFINED $raw_line]
	}

	return [list ERROR {input not handled correctly} $raw_input]
}

#
# _construct input_dict type_dict
# returns a dict with the fields specified in type_dict defaulted to zero values
# if missing from input_dict. If the value from input_dict violates the type
# constraint, return an error.
# 
# Supported types:
#   s     string; the value "null" is mapped to the empty string
#          because apparently ::json::json2dict can't tell the difference
#          between null and "null".
#   i     int; the value "null" is mapped to 0.
#   f     float; the value "null" is mapped to 0.0.
#   ?     bool; the value is mapped to 0 or 1.
#   b     binary; the value is decoded from base 64.; null -> empty
#   a     array of values; this is followed by a nested type list
#   o     object; this is followed by a nested type list
#   d     dictionary of name:value values
#   l     list of strings
#
proc ::gmaproto::_construct {input types} {
	foreach {field t} $types {
		switch -exact -- [lindex $t 0] {
			s {
				if {[dict exists $input $field]} {
					if {[dict get $input $field] eq "null"} {
						dict set input $field ""
					}
				} else {
					dict set input $field ""
				}
			}
			l {
				if {[dict exists $input $field]} {
					if {[dict get $input $field] eq "null"} {
						dict set input $field ""
					} elseif {[catch {llength [dict get $input $field]} err]} {
						error "value for $field is not a valid list: $err"
					}
				} else {
					dict set input $field ""
				}
			}
			i {
				if {[dict exists $input $field]} {
					if {[dict get $input $field] eq "null"} {
						dict set input $field 0
					} elseif {![string is integer -strict [dict get $input $field]]} {
						error "value for $field is not an integer: [dict get $input $field]"
					}
				} else {
					dict set input $field 0
				}
			}
			f {
				if {[dict exists $input $field]} {
					if {[dict get $input $field] eq "null"} {
						dict set input $field 0.0
					} elseif {![string is double -strict [dict get $input $field]]} {
						error "value for $field is not a float: [dict get $input $field]"
					}
				} else {
					dict set input $field 0.0
				}
			}
			? {
				if {[dict exists $input $field]} {
					set v [dict get $input $field]
					if {$v eq "null"} {
						dict set input $field false
					} elseif {[string is false -strict $v]} {
						dict set input $field false
					} elseif {[string is true -strict $v]} {
						dict set input $field true
					} else {
						error "value for $field is not a boolean: $v"
					}
				} else {
					dict set input $field false
				}
			}
			b {
				if {[dict exists $input $field]} {
					if {[dict get $input $field] eq "null"} {
						dict set input $field {}
					} elseif {[catch {dict set input $field [::base64::decode [dict get $input $field]]} err]} {
						error "unable to decode base64 value for $field: $err"
					}
				} else {
					dict set input $field {}
				}
			}
			a {
				if {[dict exists $input $field]} {
					if {[dict get $input $field] eq "null"} {
						dict set input $field {}
					} else {
						set vlist {}
						foreach v [dict get $input $field] {
							lappend vlist [::gmaproto::_construct $v [lindex $t 1]]
						}
						dict set input $field $vlist
					}
				} else {
					dict set input $field {}
				}
			}
			o {
				if {[dict exists $input $field]} {
					if {[dict get $input $field] eq "null"} {
						dict set input $field {}
					} else {
						dict set input $field [::gmaproto::_construct [dict get $input $field] [lindex $t 1]]
					}
				} else {
					dict set input $field {}
				}
			}
			d {
				if {[dict exists $input $field]} {
					if {[dict get $input $field] eq "null"} {
						dict set input $field {}
					}
				} else {
					dict set input $field {}
				}
			}

			default {
				error "bug: unrecognized type code $t"
			}
		}
	}
	return $input
}

proc ::gmaproto::adjust_view {x y} {
	::gmaproto::_protocol_send AV XView $x YView $y
}
proc ::gmaproto::chat_messsage {message sender recipients to_all to_gm} {
	::gmaproto::_protocol_send TO Recipients $recipients ToAll $to_all ToGM $to_gm Text $message
}
proc ::gmaproto::clear {obj_id} {
	::gmaproto::_protocol_send CLR ObjID $obj_id
}
proc ::gmaproto::clear_chat {silent target} {
	::gmaproto::_protocol_send CC DoSilently $silent Target $target
}
proc ::gmaproto::clear_from {server_id} {
	::gmaproto::_protocol_send CLR@ File $server_id
}
proc ::gmaproto::combat_mode {enabled} {
	::gmaproto::_protocol_send CO Enabled $enabled
}
proc ::gmaproto::comment {text} {
	::gmaproto::_protocol_send_raw "// $text"
}
proc ::gmaproto::define_dice_presets {plist app} {
	set p {}
	foreach p in $plist {
		if {[llength $p] != 3} {
			error "dice presets must be 3-element tuples"
		}
		lappend p [dict create Name [lindex $p 0] Description [lindex $p 1] DieRollSpec [lindex $p 2]]
	}
	if {$app} {
		::gmaproto::_protocol_send DD+ Presets $p
	} else {
		::gmaproto::_protocol_send DD Presets $p
	}
}

proc ::gmaproto::filter_dice_presets {regex} {
	::gmaproto::_protocol_send DD/ Filter $regex
}

proc ::gmaproto::load_from {server_id cache_only merge} {
	::gmaproto::_protocol_send L File $server_id CacheOnly $cache_only Merge $merge
}

proc ::gmaproto::mark {x y} {
	::gmaproto::_protocol_send MARK X $x Y $y
}

proc ::gmaproto::query_dice_presets {} {
	::gmaproto::_protocol_send DR
}

proc ::gmaproto::add_image {name sizes} {
	::gmaproto::_protocol_send AI Name $name Sizes $sizes
}

proc ::gmaproto::query_image {name size} {
	::gmaproto::_protocol_send AI? Name $name Zoom $size
}

proc ::gmaproto::query_peers {} {
	::gmaproto::_protocol_send /CONN
}

proc ::gmaproto::place_someone {obj_id color name area size obj_type gx gy reach health skin skin_sizes elevation note status_list aoe move_mode killed dim} {
	if {$obj_type eq "monster"} {
		set ct 1
	} elseif {$obj_type eq "player"} {
		set ct 2
	} else {
		error "invalid object type $obj_type for place_someone"
	}


	::gmaproto::_protocol_send PS ID $obj_id Name $name Gx $gx Gy $gy Reach $reach Area $area Size $size Color $color CreatureType $ct Health $health Skin $skin SkinSize $skin_sizes Elev $elevation Note $note StatusList $status_list AoE $aoe MoveMode $move_mode Killed $killed Dim $dim
}

proc ::gmaproto::polo {} {
	::gmaproto::_protocol_send POLO
}

proc ::gmaproto::roll_dice {spec recipients to_all blind_to_gm} {
	::gmaproto::_protocol_send D Recipients $recipients ToAll $to_all ToGM $blind_to_gm RollSpec $spec
}

proc ::gmaproto::sync_chat {target} {
	::gmaproto::_protocol_send SYNC-CHAT Target $target
}

proc ::gmaproto::sync {} {
	::gmaproto::_protocol_send SYNC
}

proc ::gmaproto::toolbar {enabled} {
	::gmaproto::_protocol_send TB Enabled $enabled
}

proc ::gmaproto::update_clock {a r} {
	::gmaproto::_protocol_send CS Absolute $a Relative $r
}

proc ::gmaproto::update_obj_attributes {obj_id kvdict} {
	::gmaproto::_protocol_send OA ObjID $obj_id NewAttrs $kvdict
}

proc ::gmaproto::add_obj_attributes {obj_id attr vs} {
	::gmaproto::_protocol_send OA+ ObjID $obj_id AttrName $attr Values $vs
}

proc ::gmaproto::remove_obj_attributes {obj_id attr vs} {
	::gmaproto::_protocol_send OA- ObjID $obj_id AttrName $attr Values $vs
}

proc ::gmaproto::update_status_marker {condition shape color} {
	::gmaproto::_protocol_send DSM Condition $condition Shape $shape Color $color
}

proc ::gmaproto::write_only {is_main} {
	if {$is_main} {
		::gmaproto::_protocol_send NO+
	} else {
		::gmaproto::_protocol_send NO
	}
}

proc ::gmaproto::subscribe {msg_list} {
	if {[llength $msg_list] == 0} {
		set ::gmaproto::_subscribed_messages $::gmaproto::all_messages	;# TODO
		::gmaproto::_protocol_send ACCEPT
	} else {
		set ::gmaproto::_subscribed_messages $msg_list ;# TODO
		::gmaproto::_protocol_send ACCEPT Messages $msg_list
	}
}

proc ::gmaproto::allow {features} {
	::gmaproto::_protocol_send ALLOW Features $features
}

proc ::gmaproto::ls {type datadict} {
	::gmaproto::_protocol_send LS-$type {*}$datadict
}

proc ::gmaproto::update_progress {id title value max done} {
	if {$id eq "*"} {
		set id [::gmaproto::new_id]
	}
	if {$max eq "*"} {
		set max 0
	}
	::gmaproto::_protocol_send PROGRESS OperationID $id Title $title Value $value MaxValue $max IsDone $done
	return $id
}

proc ::gmaproto::new_id {} {
	return [string tolower [string map {- {}} [::uuid::uuid generate]]]
}

proc ::gmaproto::_login {} {
	set sync_done false
	set preamble {}
	array set characters {}

	while {!$sync_done} {
		lassign [::gmaproto::_read_poll] cmd params
		if {$cmd eq {}} {
			continue
		}

		switch -exact -- $cmd {
			//    { 
				lappend preamble $params 
			}

			READY { 
				::gmaproto::_diag "Server sign-on completed." 
				set sync_done false
			}

			AC {
				# TODO store character
			}

			DSM {
				# TODO store marker
			}

			UPDATES {
				foreach p [dict get $params Packages] {
					set pkg_name [dict get $p Name]
					foreach inst [dict get $p Instances] {
						# TODO store into list of updates
					}
				}
			}

			WORLD {
				# TODO set that
			}

			GRANTED {
				# TODO store username
				::gmaproto::_diag "Access granted for [dict get $params User]"
			}

			DENIED {
				set why [dict get $params Reason]
				if {$why eq {}} {
					::gmaproto::_diag "Access denied to server."
					error "access denied to server"
				}
				::gmaproto::_diag "Access denied to server: $why"
				error "access denied to server: $why"
			}

			OK {
				set supported_protocol [dict get $params Protocol]
				if {$supported_protocol == 0} {
					error "This does not appear to be a server which speaks any protocol we understand."
				}
				set challenge [dict get $params Challenge]
				if {$supported_protocol < ::gmaproto::min_protocol} {
					error "The server speaks a protocol too old for me to understand ($supported_protocol)"
				}
				if {$supported_protocol > ::gmaproto::max_protocol} {
					error "The server speaks a protocol too new for me to understand ($supported_protocol)"
				}
				if {$challenge ne {}} {
					::gmaproto::_diag "Authenticating to server"
					# TODO authenticate
					::gmaproto::_protocol_send AUTH Response XXX User XXX Client XXX
					::gmaproto::_diag "Authenticating to server (awaiting response)"
				} else {
					::gmaproto::_diag "Server did not request authentication"
				}
			}

			default {
				::gmaproto::_diag "Unexpected server message $cmd received while waiting for authentication to complete"
			}
		}
	}

	# TODO send initial commands
	
}
