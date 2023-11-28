########################################################################################
#  _______  _______  _______                ___        __    ______      ______        #
# (  ____ \(       )(  ___  ) Game         /   )      /  \  / ___  \    / ___  \       #
# | (    \/| () () || (   ) | Master's    / /) |      \/) ) \/   )  )   \/   \  \      #
# | |      | || || || (___) | Assistant  / (_) (_       | |     /  /       ___) /      #
# | | ____ | |(_)| ||  ___  |           (____   _)      | |    /  /       (___ (       #
# | | \_  )| |   | || (   ) |                ) (        | |   /  /            ) \      #
# | (___) || )   ( || )   ( | Mapper         | |   _  __) (_ /  /     _ /\___/  /      #
# (_______)|/     \||/     \| Client         (_)  (_) \____/ \_/     (_)\______/       #
#                                                                                      #
########################################################################################
#
#
# Mapper JSON protocol handling functions.
# Steve Willoughby <steve@madscience.zone>
#
# Implements GMA Mapper Protocol >=400.
# // ... \n		ignored
# PROTOCOL <version>\n
# <command> <json> \n
#
# Server negotiation:
# server -> PROTOCOL v		(not required before protocol 400)
# server -> initial greeting (AC, DSM, UPDATES, WORLD)
# server -> OK
#           AUTH <- client		IF authentication required
# server -> GRANTED/DENIED		IF authentication required
# server -> more greeting (AC, DSM, UPDATES, WORLD)
# server -> READY
#
# background_redial -> redial
# dial -> redial (opens socket) -> login
# _receive (queues up input line) -> XXXparseXXX / background_redial
# _protocol_send cmd args (encode) -> XXXsendXXX
# _parse_data_packet raw -> {cmd params} / {ERROR {error raw}} / {// raw} / {PROTOCOL v} / {UNDEFINED raw}
# _legacy_login cmd params	login but for protocols <400
# _login			login client, any protocol
#
# to_enum etype val	-> int
# from_enum etype int	-> val
# _encode_payload inputdict typedict -> json
# _construct input types -> dict
# new_id -> uuid
# _read_poll (pop queued input line) -> _parse_data_packet -> or returns {"" ""} if no data ready
# _show
#
# external dependencies:
# 	::DEBUG level message
# 	::report_progress message
# 	::say message

package provide gmaproto 1.2
package require Tcl 8.5
package require json 1.3.3
package require json::write 1.0.3
package require base64 2.4.2
package require uuid 1.0.1

namespace eval ::gmaproto {
	variable protocol 408
	variable min_protocol 333
	variable max_protocol 408
	variable max_max_protocol 499
	variable debug_f {}
	variable legacy false
	variable host {}
	variable port {}
	variable sock {}
	variable send_buffer {}
	variable recv_buffer {}
	variable read_buffer {}
	variable poll_buffer {}
	variable proxy {}
	variable proxy_user {}
	variable proxy_password {}
	variable proxy_port {}
	variable pending_login true
	variable in_redial false
	variable username
	variable password
	variable client
	variable current_stream {}
	variable stream_dict {}
	variable progress_stack {}

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
		echo                      ECHO
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
		AC      {ID s Name s Health {o {MaxHP i LethalDamage i NonLethalDamage i Con i IsFlatFooted ? IsStable ? Condition s HPBlur i}} Gx f Gy f Skin i SkinSize l PolyGM ? Elev i Color s Note s Size s DispSize s StatusList l AoE {o {Radius f Color s}} MoveMode i Reach i Killed ? Dim ? CreatureType i Hidden ? CustomReach {o {Enabled ? Natural i Extended i}}}
		ACCEPT  {Messages l}
		AI      {Name s Sizes {a {File s ImageData b IsLocalFile ? Zoom f}} Animation {o {Frames i FrameSpeed i Loops i}}}
		AI?	{Name s Sizes {a {Zoom f}}}
		ALLOW   {Features l}
		AUTH    {Client s Response b User s}
		AV      {Grid s XView f YView f}
		CC      {RequestedBy s DoSilently ? Target i MessageID i}
		CLR     {ObjID s}
		CLR@    {File s IsLocalFile ?}
		CO      {Enabled ?}
		CONN    {PeerList {a {Addr s User s Client s LastPolo f IsAuthenticated ? IsMe ?}}}
		CS      {Absolute f Relative f Running ?}
		D       {Recipients l ToAll ? ToGM ? RollSpec s RequestID s}
		DD      {For s Presets {a {Name s Description s DieRollSpec s}}}
		DD+     {For s Presets {a {Name s Description s DieRollSpec s}}}
		DD/     {For s Filter s}
		DD=     {Presets {a {Name s Description s DieRollSpec s}}}
		DENIED  {Reason s}
		DR      {}
		DSM     {Condition s Shape s Color s Description s Transparent ?}
		ECHO    {s s i i o d ReceivedTime s SentTime s}
		GRANTED {User s}
		I       {ActorID s Hours i Minutes i Seconds i Rounds i Count i}
		IL      {InitiativeList {a {Slot i CurrentHP i Name s IsHolding ? HasReadiedAction ? IsFlatFooted ?}}}
		L       {File s IsLocalFile ? CacheOnly ? Merge ?}
		LS-ARC  {ArcMode i Start f Extent f ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		LS-CIRC {ArcMode i Start f Extent f ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		LS-LINE {Arrow i ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		LS-POLY {Spline i Join i ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		LS-RECT {ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		LS-SAOE {AoEShape i ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		LS-TEXT {Text s Font {o {Family s Size f Weight i Slant i}} Anchor i ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		LS-TILE {Image s BBHeight f BBWidth f ID s X f Y f Points {a {X f Y f}} Z i Line s Fill s Width i Layer s Level i Group s Dash i Hidden ? Locked ?}
		MARCO   {}
		MARK    {X f Y f}
		OA      {ObjID s NewAttrs d}
		OA+     {ObjID s AttrName s Values l}
		OA-     {ObjID s AttrName s Values l}
		OK      {Protocol i Challenge b ServerStarted s ServerActive s ServerTime s ServerVersion s}
		PRIV    {Command s Reason s}
		POLO    {}
		PROGRESS {OperationID s Title s Value i MaxValue i IsDone ?}
		PS      {ID s Name s Health {o {MaxHP i LethalDamage i NonLethalDamage i Con i IsFlatFooted ? IsStable ? Condition s HPBlur i}} Gx f Gy f Skin i SkinSize l PolyGM ? Elev i Color s Note s Size s DispSize s StatusList l AoE {o {Radius f Color s}} MoveMode i Reach i Killed ? Dim ? CreatureType i Hidden ? CustomReach {o {Enabled ? Natural i Extended i}}}
		READY   {}
		ROLL    {Sender s Recipients l MessageID i ToAll ? ToGM ? Title s Result {o {InvalidRequest ? ResultSuppressed ? Result i Details {a {Type s Value s}}}} RequestID s MoreResults ?}
		SYNC    {}
		SYNC-CHAT {Target i}
		TB      {Enabled ?}
		TO      {Sender s Recipients l MessageID i ToAll ? ToGM ? Text s}
		UPDATES {Packages {a {Name s Instances {a {OS s Arch s Version s Token s}}}}}
		WORLD   {Calendar s}
		/CONN   {}
		Animation {Frames i FrameSpeed i Loops i}
		Health  {MaxHP i LethalDamage i NonLethalDamage i Con i IsFlatFooted ? IsStable ? Condition s HPBlur i}
		Font	{Family s Size f Weight i Slant i}
		CustomReach {Enabled ? Natural i Extended i}
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

# let the user know we're in the middle of some operation which will involve
# a number of server messages, until we receive a note from the server that
# they are done. Call this just after making the request to the server.
# uses:
#	::begin_progress id|* title max|0|* ?-send?
#	::update_progress id value newmax|* ?-send?
#	::end_progress id ?-send?
#
proc ::gmaproto::watch_operation {description} {
	set this_operation_id [::gmaproto::new_id]
	lappend ::gmaproto::progress_stack $this_operation_id
	::gmaproto::_protocol_send ECHO s $this_operation_id
	::begin_progress $this_operation_id $description *
}

proc ::gmaproto::is_enabled {} {
	return [expr {$::gmaproto::host} ne {{}}]
}

proc ::gmaproto::is_connected {} {
	return [expr {$::gmaproto::sock} ne {{}}]
}

proc ::gmaproto::is_ready {} {
	return [expr [::gmaproto::is_connected] && !$::gmaproto::pending_login]
}

proc ::gmaproto::set_debug {f} {
	set ::gmaproto::debug_f $f
	::gmaproto::DEBUG "Debugging client/server protocol interactions"
}

proc ::gmaproto::DEBUG {msg} {
	if {$::gmaproto::debug_f != {}} {
		$::gmaproto::debug_f $msg
	}
	update; #no, this isn't a mistake. putting these here breaks up the work done by the event loop enough to avoid problems.
}

proc ::gmaproto::dial {host port user pass proxy proxyport proxyuser proxypass client} {
	set ::gmaproto::host $host
	set ::gmaproto::port $port
	set ::gmaproto::proxy $proxy
	set ::gmaproto::proxy_port $proxyport
	set ::gmaproto::proxy_user $proxyuser
	set ::gmaproto::proxy_password $proxypass
	set ::gmaproto::username $user
	set ::gmaproto::password $pass
	set ::gmaproto::client $client
	::gmaproto::DEBUG "dial to ${::gmaproto::host}:${::gmaproto::port}"
	::gmaproto::redial
}

proc ::gmaproto::hangup {} {
	::gmaproto::DEBUG "hangup"
	set ::gmaproto::host {}
	::gmaproto::redial
}

# we can call redial anytime we find we want to send something and we have no socket
proc ::gmaproto::redial {} {
	::gmaproto::DEBUG "redial"
	set ::gmaproto::recv_buffer {}
	if {$::gmaproto::host eq {}} {
		::gmaproto::DEBUG "hanging up ($::gmaproto::sock)"
		catch {close $::gmaproto::sock}
		set ::gmaproto::sock {}
		set ::gmaproto::pending_login true
		return
	}

	::gmaproto::DEBUG "attempting to connect to ${::gmaproto::host}:${::gmaproto::port}"
	if {$::gmaproto::sock ne {}} {
		if [catch {close $::gmaproto::sock} err2] {
			::DEBUG 1 "close socket $::gmaproto::sock ($err2)"
		}
		set ::gmaproto::pending_login true
		set ::gmaproto::sock {}
	}

	if {$::gmaproto::proxy ne {}} {
		if {$::gmaproto::proxy_user ne {}} {
			set proxy_auth 1
		} else {
			set proxy_auth 0
			set ::gmaproto::proxy_user {}
			set ::gmaproto::proxy_password {}
		}

		::gmaproto::DEBUG "Contacting proxy server $::gmaproto::proxy ..."
		set ::gmaproto::sock [socket $::gmaproto::proxy $::gmaproto::proxy_port]
		set res [socks:init $::gmaproto::sock $::gmaproto::host $::gmaproto::port $proxy_auth $::gmaproto::proxy_user $::gmaproto::proxy_password]
		::gmaproto::DEBUG "Connection completed."
		if {$res ne {OK}} {
			::DEBUG 0 "FATAL Socks5 proxy $::gmaproto::proxy -- $res"
			error "Socks 5 proxy error $res"
		}
	} else {
		set ::gmaproto::sock [socket $::gmaproto::host $::gmaproto::port]
	}
	fconfigure $::gmaproto::sock -blocking 0
#	fileevent $::gmaproto::sock readable "::gmaproto::_receive $::gmaproto::sock"
	after 10 ::gmaproto::_receive $::gmaproto::sock

	if [catch {::gmaproto::_login} err] {
		say "Attempt to sign on to server failed: $err"
	}
}

proc ::gmaproto::_receive {s} {
	while true {
		append ::gmaproto::read_buffer [read $s 1024]
		if {[eof $s]} {
			::DEBUG 0 "Lost connection to map server"
			close $s
			set ::gmaproto::sock {}
			set ::gmaproto::pending_login true
			::gmaproto::background_redial 1
			return
		}
		if {$::gmaproto::read_buffer eq {}} {
			# nothing read; back off a little
			after 50 ::gmaproto::_receive $s
			return
		}
		if {[set e [string first "\n" $::gmaproto::read_buffer]] >= 0} {
			lappend ::gmaproto::recv_buffer [set event [string range $::gmaproto::read_buffer 0 $e-1]]
			set ::gmaproto::read_buffer [string range $::gmaproto::read_buffer $e+1 end]
			break
		}
	}

	set queue_depth [llength $::gmaproto::recv_buffer]
	::gmaproto::DEBUG "($queue_depth) <- $event"
	if {!$::gmaproto::pending_login && $queue_depth == 1} {
		if {[catch {
			::gmaproto::_dispatch
		} err]} {
			::DEBUG 0 $err
		}
	}
	after 5 ::gmaproto::_receive $s
}

proc ::gmaproto::_dispatch {} {
	if {$::gmaproto::pending_login} {
		::DEBUG 1 "_dispatch not taken (pending login)"
		return
	}
	while true {
		lassign [::gmaproto::_read_poll] cmd params
		::DEBUG 2 "_dispatch: cmd=($cmd), params=($params)"
		if {$cmd eq {}} {
			::DEBUG 2 "_dispatch ends (no more input waiting)"
			return
		}
		if {$cmd eq "//"} {
			continue
		}
		if {$cmd eq "ERROR"} {
			::DEBUG 0 "Unable to interpret server data \"[lindex $params 1]\": [lindex $params 0]"
		} elseif {$cmd eq "UNDEFINED"} {
			::DEBUG 0 "Unable to interpret server command \"$params\""
		} else {
			if {$::gmaproto::debug_f ne {}} {
				$::gmaproto::debug_f "dispatching $cmd to app: $params"
			}
			if {$cmd eq "ECHO" && [llength $::gmaproto::progress_stack] > 0} {
				if {[set watched_idx [lsearch -exact $::gmaproto::progress_stack [dict get $params s]]] >= 0} {
					set watched_id [lindex $::gmaproto::progress_stack $watched_idx]
					::end_progress $watched_id
					set ::gmaproto::progress_stack [lreplace $::gmaproto::progress_stack $watched_idx $watched_idx]
				}
			}
			::gmaproto::_dispatch_to_app $cmd $params
		}
	}
}

proc ::gmaproto::_dispatch_to_app {cmd params} {
	if [catch {::DoCommand$cmd $params} err opts] {
		::DEBUG 0 "err=$err; opts=$opts"
		catch {::DoCommandError $cmd $params $err}
		update
	}
}


proc ::gmaproto::background_redial {tries} {
	if {$::gmaproto::in_redial && $tries <= 1} {
		::DEBUG 0 "Already trying to reconnect, duplicate request ignored"
		return
	}
	set ::gmaproto::in_redial true
	if [catch {::gmaproto::redial} err] {
		::DEBUG 0 "Attempt to reconnect failed ($err); continuing to try... $tries"
		after [expr min($tries*1000,10000)] ::gmaproto::background_redial [expr $tries + 1]
	} else {
		::DEBUG 0 "Connection to server reestablished"
		set ::gmaproto::in_redial false
	}
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
	::gmaproto::_raw_send [::gmaproto::_protocol_encode $command $args]
}

proc ::gmaproto::_protocol_encode_list {objtuple} {
	if {[llength $objtuple] != 2} {
		error "object tuple should have 2 elements: {$objtuple}"
	}
	return [::gmaproto::_protocol_encode {*}$objtuple]
}

proc ::gmaproto::_protocol_encode {oldcommand kvdict} {
	set command [::gmaproto::GMATypeToProtocolCommand $oldcommand]
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
		append message [::gmaproto::_encode_payload $kvdict $::gmaproto::_message_payload($command)]
	}
	return $message
}

proc ::gmaproto::_protocol_encode_struct {oldcommand kvdict} {
	set command [::gmaproto::GMATypeToProtocolCommand $oldcommand]
	#
	# encode as JSON, eliminating zero fields and ones not mentioned in the protocol spec
	#
	if {![info exists ::gmaproto::_message_payload($command)]} {
		error "protocol command $command is not valid"
	}

	if {[llength $::gmaproto::_message_payload($command)] == 0} {
		set message {}
	} else {
		::json::write aligned false
		::json::write indented false
		set message [::gmaproto::_encode_payload $kvdict $::gmaproto::_message_payload($command)]
	}
	return $message
}

# attrname internal_value -> jsonified_value
proc ::gmaproto::_attribute_encode {k v} {
	switch -exact -- $k {
		AoEShape -
		Anchor   -
		ArcMode  -
		Arrow    -
		Dash     -
		Join     -
		MoveMode -
		CreatureType { return $v }

		Dim      -
		Hidden   -
		Killed   -
		Locked   { return [::gmaproto::json_bool $v] }

		BBHeight -
		BBwidth  -
		Elev     -
		Extent   -
		Gx       -
		Gy       -
		Reach    -
		Skin     -
		Spline   -
		Start    -
		Width    -
		X        -
		Y        -
		Z        { return $v }

		AoE      {
			if {$v eq {}} {
				return "null"
			}
			if {[dict exists $v Radius] && [dict exists $v Color]} {
				return "{\"Radius\":[dict get $v Radius],\"Color\":[json::write string [dict get $v Color]]}"
			}
			::DEBUG 0 "AoE value ($v) is not valid; sending null object instead"
			return "null"
		}

		SkinSize   { return [::json::write array {*}$v] }
		StatusList { return [::json::write array {*}[lmap s $v {json::write string $s}]] }

		Font   -
		CustomReach -
		Health { return [::gmaproto::_protocol_encode_struct $k $v] }

		Points {
			set plist {}
			foreach point $v {
				lappend plist "{\"X\":[dict get $point X],\"Y\":[dict get $point Y]}"
			}
			return [::json::write array {*}$plist]
		}
	}
	return [::json::write string $v]
}

# _upgrade_attribute attrname oldvalue -> {newname jsonified_newvalue}
proc ::gmaproto::_upgrade_attribute {k v} {
	switch -exact -- $k {
		AOESHAPE { return [list AoEShape     [::gmaproto::to_enum AoEShape $v]] }
		ANCHOR   { return [list Anchor       [::gmaproto::to_enum Anchor $v]] }
		ARCMODE  { return [list ArcMode      [::gmaproto::to_enum ArcMode $v]] }
		ARROW    { return [list Arrow        [::gmaproto::to_enum Arrow $v]] }
		DASH     { return [list Dash         [::gmaproto::to_enum Dash $v]] }
		JOIN     { return [list Join         [::gmaproto::to_enum Join $v]] }
		MOVEMODE { return [list MoveMode     [::gmaproto::to_enum MoveMode $v]] }
		TYPE     { return [list CreatureType [::gmaproto::to_enum CreatureType $v]] }

		DIM      { return [list Dim    [::gmaproto::json_bool $v]] }
		HIDDEN   { return [list Hidden [::gmaproto::json_bool $v]] }
		KILLED   { return [list Killed [::gmaproto::json_bool $v]] }
		LOCKED   { return [list Locked [::gmaproto::json_bool $v]] }

		BBHEIGHT { return [list BBHeight $v] }
		BBWIDTH  { return [list BBWidth $v] }
		ELEV     { return [list Elev $v] }
		EXTENT   { return [list Extent $v] }
		GX       { return [list Gx $v] }
		GY       { return [list Gy $v] }
		REACH    { return [list Reach $v] }
		SKIN     { return [list Skin $v] }
		SPLINE   { return [list Spline $v] }
		START    { return [list Start $v] }
		WIDTH    { return [list Width $v] }
		X        { return [list X $v] }
		Y        { return [list Y $v] }
		Z        { return [list Z $v] }

		AOE      { return [list AoE "{\"Radius\":[lindex $v 1],\"Color\":[json::write string [lindex $v 2]]}"] }

		SKINSIZE   { return [list SkinSize [::json::write array {*}$v]] }
		STATUSLIST { return [list StatusList [::json::write array {*}[lmap s $v {json::write string $s}]]] }

		HEALTH {
			if {[llength $v] < 7} {
				return [list Health null]
			}
			if {[llength $v] > 7} {
				set blur [lindex $v 7]
			} else {
				set blur 0
			}
			return [list Health "{\"MaxHP\":[lindex $v 0],\"LethalDamage\":[lindex $v 1],\"NonLethalDamage\":[lindex $v 2],\"Con\":[lindex $v 3],\"IsFlatFooted\":[::gmaproto::json_bool [lindex $v 4]],\"IsStable\":[::gmaproto::json_bool [lindex $v 5]],\"Condition\":[::json::write string [lindex $v 6]],\"HPBlur\":$blur}"]
		}
		FONT {
			set weight 0
			set slant 0
			if {[lsearch -exact $v bold] >= 0} {
				set weight 1
			}
			if {[lsearch -exact $v italic] >= 0} {
				set slant 1
			}
			return [list Font "{\"Family\":[json::write string [lindex $v 0]],\"Size\":[lindex $v 1],\"Weight\":$weight,\"Slant\":$slant}"]
		}

		POINTS {
			set plist {}
			foreach {x y} $v {
				lappend plist "{\"X\":$x,\"Y\":$y}"
			}
			return [list Points [::json::write array {*}$plist]]
		}
	}
	return [list [string totitle $k] [::json::write string $v]]
}

# _backport_attribute attrname newvalue -> oldvalue
proc ::gmaproto::_backport_attribute {k v} {
	switch -exact -- $k {
		AoEShape     { return [list AOESHAPE [::gmaproto::from_enum AoEShape $v]] }
		Anchor       { return [list ANCHOR   [::gmaproto::from_enum Anchor $v]] }
		ArcMode      { return [list ARCMODE  [::gmaproto::from_enum ArcMode $v]] }
		Arrow        { return [list ARROW    [::gmaproto::from_enum Arrow $v]] }
		CreatureType { return [list TYPE     [::gmaproto::from_enum CreatureType $v]] }
		Dash         { return [list DASH     [::gmaproto::from_enum Dash $v]] }
		Join         { return [list JOIN     [::gmaproto::from_enum Join $v]] }
		MoveMode     { return [list MOVEMODE [::gmaproto::from_enum MoveMode $v]] }

		Dim      { return [list DIM     [::gmaproto::int_bool $v]] }
		Hidden   { return [list HIDDEN  [::gmaproto::int_bool $v]] }
		Killed   { return [list KILLED  [::gmaproto::int_bool $v]] }
		Locked   { return [list LOCKED  [::gmaproto::int_bool $v]] }

		AoE      { return [list AOE [list radius [dict get $v Radius] [dict get $v Color]]] }

		Health {
			return [list \
				[dict get $v MaxHP]\
				[dict get $v LethalDamage]\
				[dict get $v NonLethalDamage]\
				[dict get $v Con]\
				[::gmaproto::int_bool [dict get $v IsFlatFooted]]\
				[::gmaproto::int_bool [dict get $v IsStable]]\
				[dict get $v Condition]\
				[dict get $v HPBlur]\
			]
		}

		Font {
			set fontspec [list [dict get $v Family] [dict get $v Size]]
			if {[dict get $v Weight] == 1} { lappend fontspec bold }
			if {[dict get $v Slant] == 1} { 
				lappend fontspec italic 
			} else {
				lappend fontsped roman
			}
			return [list FONT $fontspec]
		}
		Points {
			set plist {}
			foreach point $v {
				lappend plist [dict get $point X] [dict get $point Y]
			}
			return [list POINTS $plist]
		}

	}
	return [list [string toupper $k] $v]
}

# _backport_message raw_message -> {old_format_raw_message ...}
proc ::gmaproto::_backport_message {new_message} {
	set nparams {}
	set newlist {}
	::gmaproto::DEBUG "converting $new_message to old-style protocol message"
	lassign [::gmaproto::_parse_data_packet $new_message] cmd params
	switch -exact -- $cmd {
		NIL	{ set cmd "//"; set nparams {} }
		// 	{ set nparams $params }	
		ACCEPT 	{ set nparams [dict get $params Messages] }
		AI {
			set name [dict get $params Name]
			foreach size [dict get $params Sizes] {
				if {[set data [dict get $size ImageData]] ne {}} {
					lappend newlist [list AI $name [dict get $size Zoom]
					lappend newlist [list AI: $data]
					lappend newlist [list AI. 1 {}]
				} else {
					if [dict get $size IsLocalFile] {
						lappend newlist "// unable to translate local image file cmd"
					} else {
						lappend newlist [list AI@ $name [dict get $size Zoom] [dict get $size File]]
					}
				}
			}
		}
		AI? {
			set name [dict get $params Name]
			foreach size [dict get $params Sizes] {
				lappend newlist [list AI? $name [dict get $size Zoom]]
			}
		}
		ALLOW	{ set nparams [dict get $params Features] }
		AUTH	{ set nparams [list [binary encode base64 [dict get $params Response]] [dict get $params User] [dict get $params Client]] }
		AV	{ set nparams [list [dict get $params XView] [dict get $params YView]] }
		CC	{ 
			if [dict get $params DoSilently] {
				set nparams [list * [dict get $params Target]]
			} else {
				set nparams [list {} [dict get $params Target]]
			}
		}
		CLR	{ set nparams [list [dict get $params ObjID]] }
		CLR@	{ set nparams [list [dict get $params File]] }
		CO	{ set nparams [list [::gmaproto::int_bool [dict get $params Enabled]]] }
		D	{ 
				if [dict get $params ToGM] {
					set nparams [list % [dict get $params RollSpec]]
				} elseif [dict get $params ToAll] {
					set nparams [list * [dict get $params RollSpec]]
				} else {
					set nparams [list [dict get $params Recipients] [dict get $params RollSpec]]
				}
		}
		DD - DD+ { set nparams [list [lmap v [dict get $params Presets] {list [dict get $v Name] [dict get $v Description] [dict get $v DieRollSpec]}]] }
		DD/	{ set nparams [list [dict get $params Filter]] }
		DR	{ }
		DSM	{ set nparams [list [dict get $params Condition] [dict get $params Shape] [dict get $params Color] [dict get $params Description]] }
		L	{
			set local [dict get $params IsLocalFile]
			set cache [dict get $params CacheOnly]
			set merge [dict get $params Merge]
			set nparams [list [dict get $params File]]
			if {$cache} {
				set cmd M?
			} elseif {$merge} {
				if {$local} {
					set cmd M
				} else {
					set cmd M@
				}
			} else {
				if {!$local} {
					lappend newlist [list CLR *]
					lappend newlist [list M@ $nparams]
				}
			}
		}
		LS-ARC {
			set d [::gmaproto::start_stream LS]
			set id [dict get $params ID]
			foreach attr {X Y Z Line Fill Width Layer Level Group Hidden Locked
				      Start Extent} {

				::gmaproto::continue_stream d LS: [list [string toupper $attr]:$id [dict get $params $attr]]
			}
			::gmaproto::continue_stream d LS: [list DASH:$id [::gmaproto::from_enum Dash [dict get $params Dash]]]

			set plist {}
			foreach v [dict get $params Points] {
				lappend plist [dict get $v X]
				lappend plist [dict get $v Y]
			}
			::gmaproto::continue_stream d LS: [list POINTS:$id $plist]
			::gmaproto::continue_stream d LS: [list ARCMODE:$id [::gmaproto::from_enum ArcMode [dict get $params ArcMode]]]
			::gmaproto::continue_stream d LS: [list TYPE:$id arc]
			set newlist [::gmaproto::end_stream d LS.]
		}
		LS-CIRC {
			set d [::gmaproto::start_stream LS]
			set id [dict get $params ID]
			foreach attr {X Y Z Line Fill Width Layer Level Group Hidden Locked Start Extent} {
				::gmaproto::continue_stream d LS: [list [string toupper $attr]:$id [dict get $params $attr]]
			}
			::gmaproto::continue_stream d LS: [list DASH:$id [::gmaproto::from_enum Dash [dict get $params Dash]]]
			set plist {}
			foreach v [dict get $params Points] {
				lappend plist [dict get $v X]
				lappend plist [dict get $v Y]
			}
			::gmaproto::continue_stream d LS: [list POINTS:$id $plist]
			::gmaproto::continue_stream d LS: [list TYPE:$id circ]
			set newlist [::gmaproto::end_stream d LS.]
		}
		LS-LINE {
			set d [::gmaproto::start_stream LS]
			set id [dict get $params ID]
			foreach attr {X Y Z Line Fill Width Layer Level Group Hidden Locked} {
				::gmaproto::continue_stream d LS: [list [string toupper $attr]:$id [dict get $params $attr]]
			}
			::gmaproto::continue_stream d LS: [list DASH:$id [::gmaproto::from_enum Dash [dict get $params Dash]]]
			set plist {}
			foreach v [dict get $params Points] {
				lappend plist [dict get $v X]
				lappend plist [dict get $v Y]
			}
			::gmaproto::continue_stream d LS: [list POINTS:$id $plist]
			::gmaproto::continue_stream d LS: [list ARROW:$id [::gmaproto::from_enum Arrow [dict get $params Arrow]]]
			::gmaproto::continue_stream d LS: [list TYPE:$id line]
			set newlist [::gmaproto::end_stream d LS.]
		}
		LS-POLY {
			set d [::gmaproto::start_stream LS]
			set id [dict get $params ID]
			foreach attr {X Y Z Line Fill Width Layer Level Group Hidden Locked Spline} {
				::gmaproto::continue_stream d LS: [list [string toupper $attr]:$id [dict get $params $attr]]
			}
			::gmaproto::continue_stream d LS: [list DASH:$id [::gmaproto::from_enum Dash [dict get $params Dash]]]
			set plist {}
			foreach v [dict get $params Points] {
				lappend plist [dict get $v X]
				lappend plist [dict get $v Y]
			}
			::gmaproto::continue_stream d LS: [list POINTS:$id $plist]
			::gmaproto::continue_stream d LS: [list JOIN:$id [::gmaproto::from_enum Join [dict get $params Join]]]
			::gmaproto::continue_stream d LS: [list TYPE:$id poly]
			set newlist [::gmaproto::end_stream d LS.]
		}
		LS-RECT {
			set d [::gmaproto::start_stream LS]
			set id [dict get $params ID]
			foreach attr {X Y Z Line Fill Width Layer Level Group Hidden Locked} {
				::gmaproto::continue_stream d LS: [list [string toupper $attr]:$id [dict get $params $attr]]
			}
			::gmaproto::continue_stream d LS: [list DASH:$id [::gmaproto::from_enum Dash [dict get $params Dash]]]
			set plist {}
			foreach v [dict get $params Points] {
				lappend plist [dict get $v X]
				lappend plist [dict get $v Y]
			}
			::gmaproto::continue_stream d LS: [list POINTS:$id $plist]
			::gmaproto::continue_stream d LS: [list TYPE:$id rect]
			set newlist [::gmaproto::end_stream d LS.]
		}
		LS-SAOE {
			set d [::gmaproto::start_stream LS]
			set id [dict get $params ID]
			foreach attr {X Y Z Line Fill Width Layer Level Group Hidden Locked} {
				::gmaproto::continue_stream d LS: [list [string toupper $attr]:$id [dict get $params $attr]]
			}
			::gmaproto::continue_stream d LS: [list DASH:$id [::gmaproto::from_enum Dash [dict get $params Dash]]]
			set plist {}
			foreach v [dict get $params Points] {
				lappend plist [dict get $v X]
				lappend plist [dict get $v Y]
			}
			::gmaproto::continue_stream d LS: [list POINTS:$id $plist]
			::gmaproto::continue_stream d LS: [list AOESHAPE:$id [::gmaproto::from_enum AoEShape [dict get $params AoEShape]]]
			::gmaproto::continue_stream d LS: [list TYPE:$id aoe]
			set newlist [::gmaproto::end_stream d LS.]
		}
		LS-TEXT {
			set d [::gmaproto::start_stream LS]
			set id [dict get $params ID]
			foreach attr {X Y Z Line Fill Width Layer Level Group Hidden Locked
				     Text} {
				::gmaproto::continue_stream d LS: [list [string toupper $attr]:$id [dict get $params $attr]]
			}
			::gmaproto::continue_stream d LS: [list DASH:$id [::gmaproto::from_enum Dash [dict get $params Dash]]]
			set plist {}
			foreach v [dict get $params Points] {
				lappend plist [dict get $v X]
				lappend plist [dict get $v Y]
			}
			::gmaproto::continue_stream d LS: [list POINTS:$id $plist]
			::gmaproto::continue_stream d LS: [list ANCHOR:$id [::gmaproto::from_enum Anchor [dict get $params Anchor]]]
			set fontspec [list [dict get $params Font Family] [dict get $params Font Size]]
			if {[dict get $params Font Weight] == 1} {
				lappend fontspec bold
			}
			if {[dict get $params Font Slant] == 1} {
				lappend fontspec italic
			} else {
				lappend fontspec roman
			}
			::gmaproto::continue_stream d LS: [list FONT:$id $fontspec]
			::gmaproto::continue_stream d LS: [list TYPE:$id text]
			set newlist [::gmaproto::end_stream d LS.]
		}
		LS-TILE {
			set d [::gmaproto::start_stream LS]
			set id [dict get $params ID]
			foreach attr {X Y Z Line Fill Width Layer Level Group Hidden Locked Image BBHeight BBWidth} {
				::gmaproto::continue_stream d LS: [list [string toupper $attr]:$id [dict get $params $attr]]
			}
			::gmaproto::continue_stream d LS: [list DASH:$id [::gmaproto::from_enum Dash [dict get $params Dash]]]
			set plist {}
			foreach v [dict get $params Points] {
				lappend plist [dict get $v X]
				lappend plist [dict get $v Y]
			}
			::gmaproto::continue_stream d LS: [list POINTS:$id $plist]
			::gmaproto::continue_stream d LS: [list TYPE:$id tile]
			set newlist [::gmaproto::end_stream d LS.]
		}
		MARK	{ set nparams [list [dict get $params X] [dict get $params Y]] }
		POLO	{ }
		PROGRESS {
			#PROGRESS {OperationID s Title s Value i MaxValue i IsDone ?}
			#// BEGIN id max|* title
			#// UPDATE id value newmax
			#// END id
			global ::gmaproto::old_progress_meters
			set meter_id [dict get $params OperationID]
			set new_max [dict get $params MaxValue]
			if {$new_max == 0} {
				set new_max *
			}
			if {[dict get $params IsDone]} {
				lappend newlist [list // END $meter_id]
				array unset ::gmaproto::old_progress_meters $meter_id
			} else {
				if {![info exists ::gmaproto::old_progress_meters($meter_id)]} {
					set ::gmaproto::old_progress_meters($meter_id) 0
					lappend newlist [list // BEGIN $meter_id $new_max [dict get $params Title]]
				} 
				lappend newlist [list // UPDATE $meter_id [dict get $params Value] $new_max]
			}
		}
		OA	{ 
			set kvlist {}
			dict for {k v} [dict get $params NewAttrs] {
				lappend kvlist {*}[::gmaproto::_backport_attribute $k $v]
			}
			set nparams [list [dict get $params ObjID] $kvlist]
		}
		OA+ - OA- { set nparams [list [dict get $params ObjID] {*}[::gmaproto::_backport_attribute [dict get $params AttrName] [dict get $params Values]]] }
		PS { 
			if {[dict get $params CreatureType] == 2} {
				set ptype player
			} else {
				set ptype monster
			}
			set nparams [list [dict get $params ID] \
				       [dict get $params Color] \
				       [dict get $params Name] \
				       [dict get $params Size] \
				       [dict get $params Size] \
				       $ptype \
				       [dict get $params Gx] \
				       [dict get $params Gy] \
				       [dict get $params Reach]]
		}
		SYNC	{ }
		SYNC-CHAT { set cmd SYNC; set nparams [list CHAT [dict get $params Target]] }
		TB	{ set nparams [list [::gmaproto::int_bool [dict get $params Enabled]]] }
		TO	{
			if [dict get $params ToGM] {
				set nparams [list * % [dict get $params Text]]
			} elseif [dict get $params ToAll] {
				set nparams [list * * [dict get $params Text]]
			} else {
				set nparams [list * [dict get $params Recipients] [dict get $params Text]]
			}
		}
		/CONN	{ }
		default	{ 
			set nparams "Unknown translation for $cmd $params"
			set cmd //
		}
	}
	if {[llength $newlist] > 0} {
		#::gmaproto::DEBUG "converted to:"
		#foreach c $newlist {
			#::gmaproto::DEBUG "-- $c"
		#}
		return $newlist
	}
	#::gmaproto::DEBUG "converted to: $cmd $nparams"
	if {[llength $nparams] == 0} {
		return [list $cmd]
	}
	return [list "$cmd $nparams"]
}

proc ::gmaproto::_raw_send {message} {
	if {![::gmaproto::is_enabled]} {
		::DEBUG 1 "server not configured; not sending \"$message\""
		return
	}

	if {$::gmaproto::legacy} {
		set messages [::gmaproto::_backport_message $message]
	} else {
		set messages [list $message]
	}
	foreach m $messages {
		lappend ::gmaproto::send_buffer $m
		::gmaproto::DEBUG "([llength $::gmaproto::send_buffer]) -> $m"
	}
	if [catch {
		::gmaproto::_transmit
	} err] {
		::DEBUG 0 $err
	}
}

# try sending all queued-up messages now
proc ::gmaproto::_transmit {} {
	if {$::gmaproto::sock eq {}} {
		if {[llength $::gmaproto::send_buffer] > 0} {
			# we don't have an open socket but we used to, so
			# first let's work on getting that established again.
			set ::gmaproto::pending_login true
			::gmaproto::background_redial 1
		}
		return
	}

	set saved {}
	while {[llength $::gmaproto::send_buffer] > 0} {
		set message [::gmautil::lpop ::gmaproto::send_buffer 0]
		if {$::gmaproto::pending_login && $message != "POLO" && [string range $message 0 4] != "AUTH "} {
			::gmaproto::DEBUG "Holding off on $message until login is complete"
			lappend saved $message
		} else {
			if [catch {
				puts $::gmaproto::sock $message
				flush $::gmaproto::sock
			} err] {
				::DEBUG 0 "Lost connection to server ($err)"
				catch {close $::gmaproto::sock}
				set ::gmaproto::sock {}
				set ::gmaproto::pending_login true
				::gmaproto::background_redial 1
				lappend saved $message; #save the message for later
				break
			}
		}
	}
	if {[llength $saved] > 0} {
		# preserved delayed messages for later
		set ::gmaproto::send_buffer [linsert $::gmaproto::send_buffer 0 {*}$saved]
	}
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
				D {
					if {[dict size $v] > 0} {
						dict set a $f [::json::write object {*}[dict map {dk dv} $v {
							set dv [::gmaproto::_encode_payload $dv [lindex $t 1]]
						}]]
					}
				}
				default {
					error "bug: unrecognized type code \"$t\""
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
# Returns list with command name in element 0 or UNDEFINED or ERROR or NIL
# The remaining elements hold data relevant to that command
# 	In case of a parsing error the result is {ERROR <description> <raw_line>}
# 	If the command is not recognized, returns {UNDEFINED <raw_line>}
# 	Comments are returned as {// <raw_line>}, which includes the // in the <raw_line>.
#
proc ::gmaproto::_parse_data_packet {raw_line} {
	set raw_line [string trim $raw_line]
	if {$raw_line eq {}} {
		return [list NIL ""]
	}
	if {[string range $raw_line 0 1] eq "//"} {
		return [list // $raw_line]
	}
	if {[set delim [string first " " $raw_line]] > 0} {
		set command [string range $raw_line 0 [expr $delim - 1]]
		set payload [string trim [string range $raw_line [expr $delim + 1] end]]
		if {$command eq {PROTOCOL}} {
			return [list PROTOCOL $payload]
		}
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

	return [list ERROR [list {input not handled correctly} $raw_input]]
}

proc ::gmaproto::new_dict {command args} {
	return [::gmaproto::_construct [dict create {*}$args] $::gmaproto::_message_payload($command)]
}

proc ::gmaproto::new_dict_from_json {command jsondata} {
	return [::gmaproto::_construct [::json::json2dict $jsondata] $::gmaproto::_message_payload($command)]
}
proc ::gmaproto::json_from_dict {command d} {
	return [::gmaproto::_encode_payload $d $::gmaproto::_message_payload($command)]
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
proc ::gmaproto::json_bool {b} {
	if $b {
		return "true"
	} else {
		return "false"
	}
}
proc ::gmaproto::int_bool {b} {
	if $b {
		return 1
	} else {
		return 0
	}
}
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
			D {
				if {[dict exists $input $field]} {
					if {[set srcdata [dict get $input $field]] eq "null"} {
						dict set input $field {}
					} else {
						dict unset input $field
						dict for {fldk fldv} $srcdata {
							dict set input $field $fldk [::gmaproto::_construct $fldv [lindex $t 1]]
						}
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
				error "bug: unrecognized type code \"$t\""
			}
		}
	}
	return $input
}

proc ::gmaproto::adjust_view {x y grid_label} {
	::gmaproto::_protocol_send AV Grid $grid_label XView $x YView $y
}
proc ::gmaproto::chat_message {message sender recipients to_all to_gm} {
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
	if {$app} {
		::gmaproto::_protocol_send DD+ Presets $plist
	} else {
		::gmaproto::_protocol_send DD Presets $plist
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

proc ::gmaproto::add_image {name sizes {frames 0} {speed 0} {loops 0}} {
	::gmaproto::_protocol_send AI Name $name Sizes $sizes Animation [dict create Frames $frames FrameSpeed $speed Loops $loops]
}

proc ::gmaproto::query_image {name size} {
	::gmaproto::_protocol_send AI? Name $name Sizes [list [dict create Zoom $size]]
}

proc ::gmaproto::query_peers {} {
	::gmaproto::_protocol_send /CONN
}

proc ::gmaproto::place_someone_d {d} {
	::gmaproto::_protocol_send PS {*}$d
}

#proc ::gmaproto::place_someone {obj_id color name size obj_type gx gy reach health skin skin_sizes elevation note status_list aoe move_mode killed dim {hidden false} {custom_reach {}}} {
#	if {$obj_type eq "monster"} {
#		set ct 1
#	} elseif {$obj_type eq "player"} {
#		set ct 2
#	} else {
#		error "invalid object type $obj_type for place_someone"
#	}
#
#	::gmaproto::_protocol_send PS ID $obj_id Name $name Gx $gx Gy $gy Reach $reach Size $size Color $color CreatureType $ct Health $health Skin $skin SkinSize $skin_sizes Elev $elevation Note $note StatusList $status_list AoE $aoe MoveMode $move_mode Killed $killed Dim $dim Hidden $hidden CustomReach $custom_reach
#}

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

proc ::gmaproto::update_clock {a r running} {
	::gmaproto::_protocol_send CS Absolute $a Relative $r Running $running
}

proc ::gmaproto::update_obj_attributes {obj_id kvdict} {
	set a {}
	foreach {k v} [dict get $kvdict] {
		lappend a $k [::gmaproto::_attribute_encode $k $v]
	}
	::gmaproto::_raw_send "OA {\"ObjID\":[json::write string $obj_id],\"NewAttrs\":[json::write object {*}$a]}"
}

proc ::gmaproto::add_obj_attributes {obj_id attr vs} {
	::gmaproto::_raw_send "OA+ {\"ObjID\":[json::write string $obj_id],\"AttrName\":[json::write string $attr],\"Values\":[json::write array {*}$vs]}"
}

proc ::gmaproto::remove_obj_attributes {obj_id attr vs} {
	::gmaproto::_raw_send "OA- {\"ObjID\":[json::write string $obj_id],\"AttrName\":[json::write string $attr],\"Values\":[json::write array {*}$vs]}"
}

proc ::gmaproto::update_status_marker {condition shape color {desc {}} {transparent false}} {
	::gmaproto::_protocol_send DSM Condition $condition Shape $shape Color $color Description $desc Transparent $transparent
}

proc ::gmaproto::write_only {is_main} {
	# deprecated function
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

# _initial_read_poll is like _read_poll but for the very first line
# read from the server. It will try to determine if the server is
# legacy or not, and correct for the case where it is.
proc ::gmaproto::_initial_read_poll {} {
	if {[llength $::gmaproto::poll_buffer] > 0} {
		return [::gmautil::lpop ::gmaproto::poll_buffer 0]
	}
	if {[llength $::gmaproto::recv_buffer] == 0} {
		return [list "" ""]
	}
	set message [lindex $::gmaproto::recv_buffer 0]
	if {[string range $message 0 8] eq "PROTOCOL "} {
		if {[llength $message] != 2} {
			::say "Server PROTOCOL message is malformed; giving up"
			error "Server PROTOCOL message is malformed; giving up"
		}
		set ::gmaproto::protocol [lindex $message 1]
		::gmautil::lpop ::gmaproto::recv_buffer 0; # remove PROTOCOL from input stream
		if {[lindex $message 1] >= 400} {
			# this is NOT legacy; hand off to _read_poll from here...
			return [list // "Protocol version $::gmaproto::protocol"]
		}
	}
	
	# this is a legacy server (protocol < 400); so we need to do a bunch
	# of things to translate data to and from it.
	set ::gmaproto::legacy true
	set ::gmaproto::protocol 333;	# assume this by default for legacy mode
	return [::gmaproto::_read_poll]
}

# _read_poll -> cmd params; cmd=="" if no data available yet
proc ::gmaproto::_read_poll {} {
	if {[llength $::gmaproto::poll_buffer] > 0} {
		return [::gmautil::lpop ::gmaproto::poll_buffer 0]
	}
	if {[llength $::gmaproto::recv_buffer] == 0} {
		return [list "" ""]
	}
	if {$::gmaproto::legacy} {
		set res [list "" ""]
		if [catch {
			set message [::gmautil::lpop ::gmaproto::recv_buffer 0]
			if {[llength $message] > 0} {
				set cmd [lindex $message 0]
				set params [lrange $message 1 end]
				set json [::gmaproto::_repackage_legacy_packet $cmd $params]
				if {[llength $json] == 0} {
					::gmaproto::DEBUG "translated to nothing"
				} else {
					foreach j $json {
						::gmaproto::DEBUG "translated to $j"
						if {[lindex [set translated_j [::gmaproto::_parse_data_packet $j]] 0] ne {NIL}} {
							lappend ::gmaproto::poll_buffer $translated_j
						}
					}
					if {[llength ${::gmaproto::poll_buffer}] > 0} {
						set res [::gmautil::lpop ::gmaproto::poll_buffer 0]
					}
				}
			}
		} err] {
			::gmaproto::DEBUG "ERROR parsing received string \"$message\": $err"
		}
		return $res
	}
	set res [::gmaproto::_parse_data_packet [::gmautil::lpop ::gmaproto::recv_buffer 0]]
	if {[lindex $res 0] eq {NIL}} {
		return [list "" ""]
	}
	return $res
}

#
# _repackage_legacy_packet cmd params -> {jsonstring ...}
#
proc ::gmaproto::_repackage_legacy_packet {cmd params} {
	switch -exact -- $cmd {
		// {
			if {[llength $params] == 3 && [lindex $params 0] eq "CALENDAR" && [lindex $params 1] eq "//"} {
				return [list "WORLD {\"Calendar\":[json::write string [lindex $params 2]]}"]
			}
			if {[llength $params] == 5 && [lindex $params 0] eq "MAPPER" && [lindex $params 1] eq "UPDATE" && [lindex $params 2] eq "//"} {
				return [list "UPDATES {\"Packages\":\[{\"Name\":\"mapper\",\"Instances\":\[{\"Version\":[json::write string [lindex $params 3]],\"Token\":[json::write string [lindex $params 4]]}\]}\]}"]
			}
			if {[llength $params] == 5 && [lindex $params 0] eq "CORE" && [lindex $params 1] eq "UPDATE" && [lindex $params 2] eq "//"} {
				return [list "UPDATES {\"Packages\":\[{\"Name\":\"core\",\"Instances\":\[{\"Version\":[json::write string [lindex $params 3]],\"Token\":[json::write string [lindex $params 4]]}\]}\]}"]
			}
			if {[llength $params] == 4 && [lindex $params 0] eq "BEGIN"} {
				if [catch {set maxvalue [expr int([lindex $params 2])]}] {
					set maxvalue 0
				}
				return [list "PROGRESS {\"OperationID\":[json::write string [lindex $params 1]],\"MaxValue\":$maxvalue,\"Title\":[json::write string [lindex $params 3]]}"]
			}
			if {[llength $params] >= 3 && [lindex $params 0] eq "UPDATE"} {
				if [catch {set value [expr int([lindex $params 2])]}] {
					set value 0
				}
				if {[llength $params] != 4 || [catch {set maxvalue [expr int([lindex $params 2])]}]} {
					set maxvalue 0
				}
				return [list "PROGRESS {\"OperationID\":[json::write string [lindex $params 1]],\"Value\":$value,\"MaxValue\":$maxvalue}"]
			}
			if {[llength $params] == 2 && [lindex $params 0] eq "END"} {
				return [list "PROGRESS {\"OperationID\":[json::write string [lindex $params 1]],\"IsDone\":true}"]
			}
			return [list "// $params"]
		}
		AC {
			# AC name id color area size
			::gmautil::rdist 5 5 AC $params n i c a s
			return [list "AC {\"Name\":[json::write string $n],\"ID\":[json::write string $i],\"Color\":[json::write string $c],\"Size\":[json::write string $s]}"]
		}
		AI {
			# AI name size
			::gmautil::rdist 2 2 AI $params n s
			::gmaproto::_start_stream AI [dict create Name $n Size $s Data {}]
		}
		AI: {
			# AI: data
			::gmautil::rdist 1 1 AI: $params d
			# TODO any packet which contains binary data has base64 encoding done automatically!!
			# TODO checksum ignored for now; it should be based on the raw binary image data
			# rather than what is actually sent with the command.
			::gmaproto::_continue_stream AI [dict create Data $d] {} -append
		}
		AI. {
			# AI. lines checksum
			# TODO checksum ignored for now; it should be based on the raw binary image data
			# rather than what is actually sent with the command.
			::gmautil::rdist 1 2 AI. $params l cs
			set sdata [::gmaproto::_end_stream AI $l {}] 

			return [list "AI {\"Name\":[json::write string [dict get $sdata Name]],\"Sizes\":\[{\"ImageData\":[json::write string [dict get $sdata Data]],\"Zoom\":[dict get $sdata Size]}\]}"]
		}
		AI? {
			# AI? name size
			::gmautil::rdist 2 2 AI? $params n s
			return [list "AI? {\"Name\":[json::write string $n],\"Sizes\":\[{\"Zoom\":$s}\]}"]
		}
		AI@ {
			# AI@ name size id
			::gmautil::rdist 3 3 AI@ $params n s i
			return [list "AI {\"Name\":[json::write string $n],\"Sizes\":\[{\"File\":[json::write string $i],\"Zoom\":$s}\]}"]
		}
		AV {
			# AV x y
			::gmautil::rdist 2 2 AV $params x y
			return [list "AV {\"XView\":$x,\"YView\":$y}"]
		}
		CC {
			# CC *|user target messageID
			::gmautil::rdist 3 3 CC $params u t i
			if {$u == "*"} {
				return [list "CC {\"DoSilently\":true,\"Target\":$t,\"MessageID\":[json::write string $i]}"]
			} else {
				return [list "CC {\"RequestedBy\":[json::write string $u],\"Target\":$t,\"MessageID\":[json::write string $i]}"]
			}
		}
		CLR {
			# CLR id|*|E*|M*|P*|[imagename=]name
			::gmautil::rdist 1 1 CLR $params x
			return [list "CLR {\"ObjID\":[json::write string $x]}"]
		}
		CLR@ {
			# CLR@ id
			::gmautil::rdist 1 1 CLR@ $params i
			return [list "CLR@ {\"File\":[json::write string $i]}"]
		}
		CO {
			# CO bool
			::gmautil::rdist 1 1 CO $params b
			if {$b} {
				return [list "CO {\"Enabled\":true}"]
			} else {
				return [list "CO {}"]
			}
		}
		CS {
			# CS abs rel
			::gmautil::rdist 2 2 CS $params a r
			return [list "CS {\"Absolute\":$a,\"Relative\":$r}"]
		}
		DENIED {
			# DENIED msg
			::gmautil::rdist 0 1 DENIED $params m
			return [list "DENIED {\"Reason\":[json::write string $m]}"]
		}
		DD= {
			# DD=
			::gmaproto::_start_stream DD [dict create Data {}] 
		}
		DD: {
			# DD: pos name desc dice
			::gmautil::rdist 4 4 DD: $params p n d ds
			::gmaproto::_continue_stream DD [dict create Data [list $n $d $ds]] [list $p $n $d $ds] -lappend
		}
		DD. {
			# DD. count checksum
			::gmautil::rdist 1 2 DD. $params l cs
			set sdata [::gmaproto::_end_stream DD $l {}] 
			set plist {}
			foreach preset [dict get $sdata Data] {
				lappend plist "{\"Name\":[json::write string [lindex $preset 0]],\"Description\":[json::write string [lindex $preset 1]],\"DieRollSpec\":[json::write string [lindex $preset 2]]}"
			}

			return [list "DD= {\"Presets\":\[[join $plist ,]\]}"]
		}
		DSM {
			# DSM cond shape color [desc]
			::gmautil::rdist 3 4 DSM $params cnd s c d
			return [list "DSM {\"Condition\":[json::write string $cnd],\"Shape\":[json::write string $s],\"Color\":[json::write string $c],\"Description\":[json::write string $d]}"]
		}
		GRANTED {
			# GRANTED name
			::gmautil::rdist 1 1 GRANTED $params n
			return [list "GRANTED {\"User\":[json::write string $n]}"]
		}
		I {
			# I {r c s m h} id|name|*Monsters*|""|/regex
			::gmautil::rdist 1 2 I $params t i
			::gmautil::rdist 5 5 I-data $t r c s m h
			return [list "I {\"ActorID\":[json::write string $i],\"Hours\":$h,\"Minutes\":$m,\"Seconds\":$s,\"Rounds\":$r,\"Count\":$c}"]
		}
		IL {
			# IL {{name hold? ready? hp flat? slotno} ...}
			::gmautil::rdist 1 1 IL $params il
			set ilist {}
			foreach slot $il {
				::gmautil::rdist 6 6 IL-slot $slot n h r hp f sn
				lappend ilist "{\"Slot\":$sn,\"CurrentHP\":$hp,\"Name\":[json::write string $n],\"IsHolding\":[::gmaproto::json_bool $h],\"HasReadiedAction\":[::gmaproto::json_bool $r],\"IsFlatFooted\":[::gmaproto::json_bool $f]}"
			}
			return [list "IL {\"InitiativeList\":\[[join $ilist ,]\]}"]
		}
		L {
			# L file
			::gmautil::rdist 1 1 L $params f
			return [list "L {\"File\":[json::write string $f],\"IsLocalFile\":true}"]
		}
		LS {
			::gmaproto::_start_stream LS [dict create Data {}]
		}
		LS: {
			# LS: data
			::gmautil::rdist 1 1 LS: $params d
			#::DEBUG 0 "($params) -> $d cs($params)"
			::gmaproto::_continue_stream LS [dict create Data $d] $d -lappend
		}
		LS. {
			# LS. count checksum
			::gmautil::rdist 1 2 LS. $params l cs
			set sdata [::gmaproto::_end_stream LS $l $cs]
			# translate sequence of the following lines into new-style objects
			set objlist [lindex [::gmafile::load_legacy_map_data [dict get $sdata Data] [dict create Comment "from legacy LS data stream"]] 1]
			return [lmap v $objlist {::gmaproto::_protocol_encode_list $v}]
#			return [lmap v $objlist {[list [::gmaproto::GMATypeToProtocolCommand [lindex $v 0]] [lindex $v 1]]}]
#			return [lmap v [::gmafile::upgrade_elements $objlist] {::gmaproto::_protocol_encode_list $v}]
		}
		M {
			# M {file ...}
			::gmautil::rdist 1 1 M $params fs
			set flist {}
			foreach f $fs {
				lappend flist "L {\"File\":[json::write string $f],\"IsLocalFile\":true,\"Merge\":true}"
			}
			return $flist
		}
		M? {
			# M? id
			::gmautil::rdist 1 1 M? $params i
			return [list "L {\"File\":[json::write string $i],\"CacheOnly\":true}"]
		}
		M@ {
			# M@ id
			::gmautil::rdist 1 1 M@ $params i
			return [list "L {\"File\":[json::write string $i],\"Merge\":true}"]
		}
		MARK {
			# MARK x y
			::gmautil::rdist 2 2 MARK $params x y
			return [list "MARK {\"X\":$x,\"Y\":$y}"]
		}
		MARCO {
			# MARCO
			return [list "MARCO {}"]
		}
		OA {
			# OA id {k1 v1 ... kN vN}
			::gmautil::rdist 2 2 OA $params i kvs
			set kvlist {}
			dict for {k v} [dict create {*}$kvs] {
				lassign [::gmaproto::_upgrade_attribute $k $v] k v
				lappend kvlist "[json::write string $k]:$v"
			}
			return [list "OA {\"ObjID\":[json::write string $i],\"NewAttrs\":{[join $kvlist ,]}}"]
		}
		OA+ {
			# OA+ id k {v1 ... vN}
			::gmautil::rdist 3 3 OA+ $params i k vs
			lassign [::gmaproto::_upgrade_attribute $k $vs] k vs
			return [list "OA+ {\"ObjID\":[json::write string $i],\"AttrName\":[json::write string $k],\"Values\":\[[join $vs ,]\]}"]
		}
		OA- {
			# OA- id k {v1 ... vN}
			::gmautil::rdist 3 3 OA- $params i k vs
			lassign [::gmaproto::_upgrade_attribute $k $vs] k vs
			return [list "OA- {\"ObjID\":[json::write string $i],\"AttrName\":[json::write string $k],\"Values\":\[[join $vs ,]\]}"]
		}
		OK {
			# OK v [challenge]
			::gmautil::rdist 1 2 OK $params v c
			return [list "OK {\"Protocol\":$v,\"Challenge\":[json::write string $c]}"]
		}
		PRIV {
			# PRIV mesg
			::gmautil::rdist 0 1 PRIV $params m
			return [list "PRIV {\"Reason\":[json::write string $m]}"]
		}
		PS {
			# PS id color name area size player|monster x y reach?
			::gmautil::rdist 9 9 PS $params i c n a s t x y r
			if {$t eq "monster"} {
				set t 1
			} elseif {$t eq "player"} {
				set t 2
			} else {
				set t 0
			}
			return [list "PS {\"ID\":[json::write string $i],\"Name\":[json::write string $n],\"Gx\":$x,\"Gy\":$y,\"Color\":[json::write string $c],\"Size\":[json::write string $s],\"Reach\":$r,\"CreatureType\":$t}"]
		}
		ROLL {
			# ROLL from reciplist title result structuredlist messageID
			::gmautil::rdist 6 6 ROLL $params f r t res sr i
			set rlist [lmap d $sr {join [list "{\"Type\":[json::write string [lindex $d 0]]" "\"Value\":[json::write string [lindex $d 1]]}"] ,}]
			set result "\"Result\":{\"Result\":$res,\"Details\":\[[join $rlist ,]\]}"
			if {[lsearch -exact $r "%"] >= 0} {
				return [list "ROLL {\"Sender\":[json::write string $f],\"ToGM\":true,\"MessageID\":[json::write string $i],\"Title\":[json::write string $t],$result}"]
			} elseif {[lsearch -exact $r "*"] >= 0} {
				return [list "ROLL {\"Sender\":[json::write string $f],\"ToAll\":true,\"MessageID\":[json::write string $i],\"Title\":[json::write string $t],$result}"]
			} else {
				return [list "ROLL {\"Sender\":[json::write string $f],\"Recipients\":\[[join [lmap v $r {json::write string $v}] ,]\],\"MessageID\":[json::write string $i],\"Title\":[json::write string $t],$result}"]
			}
		}
		TB {
			# TB bool
			::gmautil::rdist 1 1 TB $params b
			if $b {
				return [list "TB {\"Enabled\":true}"]
			} else {
				return [list "TB {}"]
			}
		}
		TO {
			# TO from reciplist|@(me)|*(all)|%(gm) message messageID
			::gmautil::rdist 4 4 TO $params f r m i
			if {[lsearch -exact $r "%"] >= 0} {
				return [list "TO {\"Sender\":[json::write string $f],\"ToGM\":true,\"MessageID\":[json::write string $i],\"Text\":[json::write string $m]}"]
			} elseif {[lsearch -exact $r "*"] >= 0} {
				return [list "TO {\"Sender\":[json::write string $f],\"ToAll\":true,\"MessageID\":[json::write string $i],\"Text\":[json::write string $m]}"]
			} else {
				return [list "TO {\"Sender\":[json::write string $f],\"Recipients\":\[[join [lmap v $r {json::write string $v}] ,]\],\"MessageID\":[json::write string $i],\"Text\":[json::write string $m]}"]
			}
		}
		CONN {
			# CONN
			::gmaproto::_start_stream CONN [dict create Data {}]
		}
		CONN: {
			# CONN: i you|peer addr user client auth? pri? w/o? polo
			::gmautil::rdist 7 9 CONN: $params i who a u c au pr wo po
			::gmaproto::_continue_stream CONN [dict create Data $params] $params -lappend
		}
		CONN. {
			# CONN. count checksum
			#puts "conn."
			::gmautil::rdist 1 2 CONN. $params l cs
			#puts "conn. $l $cs from $params"
			set sdata [::gmaproto::_end_stream CONN $l $cs] 
			set clist {}
			foreach c [dict get $sdata Data] {
				#puts $c
				lassign $c i who a u c au po
				#puts $i
				lappend clist "{\"Addr\":[json::write string $a],\"User\":[json::write string $u],\"Client\":[json::write string $c],\"LastPolo\":$po,\"IsAuthenticated\":[::gmaproto::json_bool $au],\"IsMe\":[::gmaproto::json_bool [expr {$who} eq {{you}}]]}"
			}

			return [list "CONN {\"PeerList\":\[[join $clist ,]\]}"]
		}
		default {
			::gmaproto::DEBUG "Unrecognized incoming command $cmd"
			return [list "// UNKNOWN $cmd $params"]
		}
	}
	return [list "" ""]
}

proc ::gmaproto::_login {} {
	set sync_done false
	set initial_command false
	set ::gmaproto::legacy false
	set update_ready {}

	::gmaproto::DEBUG "begin _login"
	while {!$sync_done} {
		update; #allow other tasks like ::gmaproto::_receive to happen
		if {!$initial_command} {
			lassign [::gmaproto::_initial_read_poll] cmd params
			if {$cmd ne {}} {
				if {$::gmaproto::legacy} {
					::gmaproto::DEBUG "PROTOCOL missing or declared as old; proceeding with legacy protocol support"
				} else {
					::gmaproto::DEBUG "Proceeding with JSON-encoded protocol $::gmaproto::protocol"
				}
				set initial_command true
			}
		} else {
			lassign [::gmaproto::_read_poll] cmd params
		}

		if {$cmd eq {}} {
			continue
		}

		if [catch {
		#
		# Negotiate interaction with server up to successful login.
		#
		switch -exact -- $cmd {
			//	{ ::DEBUG 1 "server: $params" 
				set msg [string trim [string range $params 2 end]]
				if {[string compare -nocase -length 7 $msg notice:] == 0} {
					tk_messageBox -type ok -icon info -message [string range $msg 7 end] -title "Server Notice" -parent .
				}
			}
			AC	{ ::gmaproto::_dispatch_to_app AC $params }
			DSM	{ ::gmaproto::_dispatch_to_app DSM $params }
			MARCO	{ ::gmaproto::DEBUG "Ignored MARCO during login" }
			WORLD	{ set calendar [dict get $params Calendar] }
			DENIED {
				::report_progress "Server denied access"
				::say "Server DENIED access: [dict get $params Reason]"
				error "Server DENIED access: [dict get $params Reason]"
			}
			GRANTED {
				set ::gmaproto::username [dict get $params User]
				::gmaproto::DEBUG "Access granted for [dict get $params User]"
				if {$::gmaproto::legacy} {
					# in legacy mode, we don't have READY, so this is our indication
					# that we're done.
					::gmaproto::DEBUG "Server legacy sign-on completed." 
					set sync_done true
				}
			}
			OK {
				::gmaproto::DEBUG "Server greeting complete"
				::report_progress "Server greeting complete"
				set ::gmaproto::protocol [dict get $params Protocol]
				if {$::gmaproto::protocol == 0} {
					error "This does not appear to be a server which speaks any protocol we understand."
				}
				set challenge [dict get $params Challenge]
				if {$::gmaproto::protocol < $::gmaproto::min_protocol} {
					error "The server speaks a protocol too old for me to understand ($::gmaproto::protocol)"
				}
				if {$::gmaproto::protocol > $::gmaproto::max_max_protocol} {
					error "The server speaks a protocol too new for me to understand at all ($::gmaproto::protocol)"
				}
				if {$::gmaproto::protocol > $::gmaproto::max_protocol} {
					::DEBUG 0 "The server speaks a protocol too new for me; checking for available updates..."
					::DEBUG 0 "It may be possible to proceed with this client but not all commands may work as expected."
				}
				set ::gmaproto::server_version [dict get $params ServerVersion]
				::gmaproto::DEBUG "Connected to server version $::gmaproto::server_version with protocol $::gmaproto::protocol"
				::report_progress "Connected to server version $::gmaproto::server_version with protocol $::gmaproto::protocol"
				if {$challenge ne {}} {
					::gmaproto::DEBUG "Authenticating to server"
					if {$::gmaproto::password eq {?}} {
						if {! [::getstring::tk_getString .password_prompt ::gmaproto::password "Server Password" -title "Log In" -entryoptions {-show *}]} {
							set ::gmaproto::password {}
						}
					}
					if {$::gmaproto::password eq {}} {
						::say "This server requires authentication but no --password option or configuration file line was given."
						error "Authentication required"
					}
					::gmaproto::DEBUG "Server requests authentication (challenge=[binary encode hex $challenge])"
					::report_progress "Authenticating..."
					set response [::gmaproto::auth_response $challenge]
					::gmaproto::_protocol_send AUTH Response $response User $::gmaproto::username Client $::gmaproto::client
					::report_progress "Authenticating... (awaiting server response)"
					::gmaproto::DEBUG "Waiting for server's response"
				} else {
					::gmaproto::DEBUG "Server did not request authentication"
					if {$::gmaproto::legacy} {
						# In legacy mode, this is our only indication that we're done
						::gmaproto::DEBUG "Server legacy sign-on completed." 
						set sync_done true
					}
				}
			}
			READY { 
				::gmaproto::DEBUG "Server sign-on completed." 
				set sync_done true
				::gmaproto::watch_operation "Syncing game state"
			}
			UPDATES {
				foreach p [dict get $params Packages] {
					if {[dict get $p Name] ne {mapper}} {
						continue
					}
					foreach inst [dict get $p Instances] {
						set os [dict get $inst OS]
						set arch [dict get $inst Arch]

						if {($os eq {} || $os eq [::gmautil::my_os]) && ($arch eq {} || $arch eq [::gmautil::my_arch])} {
							if {$update_ready ne {} && 
								(($os ne {} && [dict get $update_ready OS] eq {}) ||
								 ($arch ne {} && [dict get $update_ready Arch] eq {}))} {
								::gmaproto::DEBUG "Updated mapper version [dict get $inst Version] available (OS=[dict get $inst OS], Arch=[dict get $inst Arch], Token=[dict get $inst Token])"
								::gmaproto::DEBUG "This version is more specific than the one I found before, switching to it instead."
								set update_ready $inst
							} elseif {$update_ready eq {}} {
								::gmaproto::DEBUG "Updated mapper version [dict get $inst Version] available (OS=[dict get $inst OS], Arch=[dict get $inst Arch], Token=[dict get $inst Token])"
								set update_ready $inst
							}
						}
					}
				}
			}
			default {
				::gmaproto::DEBUG "Unexpected server message $cmd received while waiting for authentication to complete"
			}
		}
		} err] {
			::say "Error processing login negotiation step: $err"
		}
	}

	set ::gmaproto::pending_login false
	::report_progress "Server login successful."
	after 5000 { ::report_progress "" }
	::gmaproto::_transmit
	::gmaproto::_dispatch
	after 2000 { ::gmaproto::_background_poll }

	if {$update_ready ne {}} {
		if {[catch {::UpgradeAvailable $update_ready} err]} {
			::say "Failed to check for upgrade: $err"
		}
	}

	if [catch ::DoCommandLoginSuccessful err] {
		::gmaproto::DEBUG "Unable to notify application of successful login: $err"
	}
}

proc ::gmaproto::_background_poll {} {
	if {[::gmaproto::is_connected]} {
		if [catch {
			::gmaproto::_transmit
			::gmaproto::_dispatch
		} err] {
			::DEBUG 0 "Error in background communcation poll task: $err"
		}
		after 2000 {::gmaproto::_background_poll}
	} else {
		::DEBUG 0 "Shutting down background communication poll task."
	}
}

# list functions with included checksums for legacy streams
proc ::gmaproto::start_stream {initcmd} {
	return [dict create Checksum [::sha2::SHA256Init] StreamData [list $initcmd]]
}
proc ::gmaproto::continue_stream {dictname contcmd data} {
	upvar 1 $dictname d
	::sha2::SHA256Update [dict get $d Checksum] $data
	dict lappend d StreamData [list $contcmd $data]
}
proc ::gmaproto::end_stream {dictname endcmd} {
	upvar 1 $dictname d
	dict lappend d StreamData [list $endcmd [expr [llength [dict get $d StreamData]] - 1] [::base64::encode [::sha2::SHA256Final [dict get $d Checksum]]]]
	return [dict get $d StreamData]
}

proc ::gmaproto::auth_response {challenge} {
	global ::tcl_platform
	if {[catch {
		binary scan $challenge S passes
		set passes [expr $passes & 0xffff]
		::gmaproto::DEBUG "-- $passes passes"
		set H [::sha2::SHA256Init]
		::sha2::SHA256Update $H $challenge
		::sha2::SHA256Update $H $::gmaproto::password
		set D [::sha2::SHA256Final $H]
		for {set i 0} {$i < $passes} {incr i} {
			set H [::sha2::SHA256Init]
			::sha2::SHA256Update $H $::gmaproto::password
			::sha2::SHA256Update $H $D
			set D [::sha2::SHA256Final $H]
		}
		set response $D
		if {$::gmaproto::username eq {}} {
			if {[catch {
				set ::gmaproto::username $::tcl_platform(user)
			} uerr]} {
				set ::gmaproto::username "($uerr)"
			}
		}
	} err]} {
		::say "Failed to understand server's challenge or compute response ($err)"
		error "Failed to understand server's challenge or compute response ($err)"
	}
	return $response
}

# current_stream
# stream_dict
#
# Legacy data stream handling
# _start_stream cmd dict		begin tracking for named cmd with dict of saved data
# _continue_stream cmd dict cd ?-append|-lappend?
#     					add to accumulated data; -append: append to dict keys; -lappend: dict keys are lists
#     					checksum advanced using cd
# _end_stream cmd -> dict		end tracking, return dict of collected data
#
proc ::gmaproto::_start_stream {cmd d} {
	if {$::gmaproto::current_stream ne {}} {
		::DEBUG 0 "Previous $::gmaproto::current_stream not ended before next $cmd stream started"
	}
	set ::gmaproto::current_stream $cmd
	set ::gmaproto::stream_dict $d
	::gmaproto::DEBUG "Started $cmd stream"
	dict set ::gmaproto::stream_dict __cs [::sha2::SHA256Init]
	dict set ::gmaproto::stream_dict __i 0
}
proc ::gmaproto::_continue_stream {cmd d cd args} {
	if {$::gmaproto::current_stream ne $cmd} {
		if {$::gmaproto::current_stream eq {}} {
			::DEBUG 0 "Stream for $cmd not started; cannot continue"
		} else {
			::DEBUG 0 "Stream data for $cmd received while collecting $::gmaproto::current_stream"
		}
		return
	}
	dict incr ::gmaproto::stream_dict __i
	sha2::SHA256Update [dict get $::gmaproto::stream_dict __cs] $cd
	if {[lsearch -exact $args -append] >= 0} {
		# dict keys are strings to append data onto
		dict for {k v} $d {
			dict append ::gmaproto::stream_dict $k $v
		}
	} elseif {[lsearch -exact $args -lappend] >= 0} {
		# dict keys are lists to add data onto
		dict for {k v} $d {
			dict lappend ::gmaproto::stream_dict $k $v
		}
	} else {
		# merge keys into our dictionary
		set ::gmaproto::stream_dict [dict replace $::gmaproto::stream_dict $d]
	}
}
proc ::gmaproto::_end_stream {cmd expected_len expected_cs} {
	if {$::gmaproto::current_stream ne $cmd} {
		if {$::gmaproto::current_stream eq {}} {
			::DEBUG 0 "Stream for $cmd not started; cannot end"
		} else {
			::DEBUG 0 "Stream end for $cmd received while collecting $::gmaproto::current_stream"
		}
		set ::gmaproto::current_stream {}
		error "$cmd stream aborted"
	}
	set ::gmaproto::current_stream {}
	set digest [::sha2::SHA256Final [dict get $::gmaproto::stream_dict __cs]]
	if {[dict get $::gmaproto::stream_dict __i] != $expected_len} {
		::DEBUG 0 "Stream rejected for $cmd; expected $expected_len but got [dict get $::gmaproto::stream_dict __i]"
		error "$cmd stream rejected (size)"
	}
	if {$expected_cs != {} && [::base64::encode $digest] != $expected_cs} {
		::DEBUG 0 "Stream rejected for $cmd; checksum error"
		error "$cmd stream rejected (checksum) ($expected_cs) != ([::base64::encode $digest])"
	}
	return $::gmaproto::stream_dict
}

proc ::gmaproto::ObjTypeToGMAType {ot args} {
	set ls {}
	if {[lsearch -exact $args {-protocol}] >= 0} {
		set ls {LS-}
	}
	switch $ot {
		arc	{ return "${ls}ARC" }
		circ	{ return "${ls}CIRC" }
		line	{ return "${ls}LINE" }
		poly	{ return "${ls}POLY" }
		rect	{ return "${ls}RECT" }
		aoe - 
		saoe 	{ return "${ls}SAOE" }
		text	{ return "${ls}TEXT" }
		tile	{ return "${ls}TILE" }
	}
	error "No such defined GMA type for $ot"
}

proc ::gmaproto::GMATypeToObjType {gt} {
	switch $gt {
		LS-ARC  - ARC  { return arc  }
		LS-CIRC - CIRC { return circ }
		LS-LINE - LINE { return line }
		LS-POLY - POLY { return poly }
		LS-RECT - RECT { return rect }
		LS-SAOE - SAOE { return aoe  }
		LS-TEXT - TEXT { return text }
		LS-TILE - TILE { return tile }
	}
	error "No such defined object type for $gt"
}

proc ::gmaproto::GMATypeToProtocolCommand {gt} {
	switch $gt {
		LS-ARC  - ARC  { return LS-ARC  }
		LS-CIRC - CIRC { return LS-CIRC }
		LS-LINE - LINE { return LS-LINE }
		LS-POLY - POLY { return LS-POLY }
		LS-RECT - RECT { return LS-RECT }
		LS-SAOE - SAOE { return LS-SAOE }
		LS-TEXT - TEXT { return LS-TEXT }
		LS-TILE - TILE { return LS-TILE }
		CREATURE - PS  { return PS      }
	}
	return $gt
}

# @[00]@| GMA-Mapper 4.17.3
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
