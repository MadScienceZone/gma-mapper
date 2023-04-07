########################################################################################
#  _______  _______  _______                ___       ______         ___               #
# (  ____ \(       )(  ___  ) Game         /   )     / ___  \       /   )              #
# | (    \/| () () || (   ) | Master's    / /) |     \/   \  \     / /) |              #
# | |      | || || || (___) | Assistant  / (_) (_       ___) /    / (_) (_             #
# | | ____ | |(_)| ||  ___  |           (____   _)     (___ (    (____   _)            #
# | | \_  )| |   | || (   ) |                ) (           ) \        ) (              #
# | (___) || )   ( || )   ( | Mapper         | |   _ /\___/  / _      | |              #
# (_______)|/     \||/     \| Client         (_)  (_)\______/ (_)     (_)              #
#                                                                                      #
########################################################################################
# Profile editor

package provide gmaprofile 1.0
package require json 1.3.3
package require json::write 1.0.3
package require getstring

namespace eval ::gmaprofile {
	namespace export editor
	variable _profile {}
	variable _profile_backup {}
	variable currently_editing_index -1
	variable _file_format {
		GMA_Mapper_preferences_version i
		animate ?
		button_size s
		curl_path s
		current_profile s
		dark ?
		debug_level i
		debug_proto ?
		guide_lines {o {
			major {o {
				interval i
				offsets {o {
					x i
					y i
				}}
			}}
			minor {o {
				interval i
				offsets {o {
					x i
					y i
				}}
			}}
		}}
		image_format s
		keep_tools ?
		preload ?
		profiles {a {
		        name s
			host s
			port i
			username s
			password s
			curl_proxy s
			blur_all ?
			blur_pct i
			suppress_chat ?
			chat_limit i
			chat_log s
			curl_server s
			update_url s
			module_id s
			server_mkdir s
			nc_path s
			scp_path s
			scp_dest s
			scp_server s
			scp_proxy s
		    }
	    	}
	}
	proc default_preferences {} {
		return [dict create \
			animate         false\
			button_size     small\
			curl_path       /usr/bin/curl\
			current_profile offline\
			dark            false\
			debug_level     0\
			debug_proto     false\
			guide_lines [dict create \
				major [dict create interval 0 offsets [dict create x 0 y 0]] \
				minor [dict create interval 0 offsets [dict create x 0 y 0]] \
			]\
			image_format png\
			keep_tools   false\
			preload      false\
			profiles [list [empty_server_profile offline]]\
		]
	}
	proc empty_server_profile {name} {
		return [dict create \
			name $name \
			host {} \
			port 2323 \
			username {} \
			password {} \
			curl_proxy {} \
			blur_all false \
			blur_pct 0 \
			suppress_chat false \
			chat_limit 0 \
			chat_log {} \
			curl_server {} \
			update_url {} \
			module_id {} \
			server_mkdir {} \
			nc_path {} \
			scp_path {} \
			scp_dest {} \
			scp_server {} \
			scp_proxy {} \
		]
	}
	proc _add_new {w} {
		variable _profile
		if {[::getstring::tk_getString .new_profile_name newname {Name of new server profile}] && $newname ne {}} {
			if {[find_server_index $_profile $newname] >= 0} {
				tk_messageBox -type ok -icon error -title "Duplicate name" -message "You tried to add a server called \"$newname\" but that name already exists in the profile set."
				return
			}
			$w.n.p.servers insert end $newname
			dict lappend _profile profiles [empty_server_profile $newname]
			$w.n.p.servers selection clear 0 end
			$w.n.p.servers selection set end
			_select_server $w [expr [$w.n.p.servers index end] - 1]
		}
	}
	proc _copy_selected {w} {
		variable currently_editing_index
		variable _profile
		_save_server $w
		if {$currently_editing_index < 0} {
			tk_messageBox -type ok -icon error -title "No current selection" -message "You can't make a copy of a profile without first selecting the profile to copy from."
			return
		}
		set serverdata [lindex [dict get $_profile profiles] $currently_editing_index]
		set servername [dict get $serverdata name]
		if {[::getstring::tk_getString .new_profile_name newname "Name of new server profile (copy of $servername)"] && $newname ne {}} {
			if {[find_server_index $_profile $newname] >= 0} {
				tk_messageBox -type ok -icon error -title "Duplicate name" -message "You tried to add a server called \"$newname\" but that name already exists in the profile set."
				return
			}
			$w.n.p.servers insert end $newname
			dict set serverdata name $newname
			dict lappend _profile profiles $serverdata
			$w.n.p.servers selection clear 0 end
			$w.n.p.servers selection set end
			_select_server $w [expr [$w.n.p.servers index end] - 1]
		}
	}
	proc _delete_selected {w} {
		variable currently_editing_index
		variable _profile
		if {$currently_editing_index < 0} {
			tk_messageBox -type ok -icon error -title "No current selection" -message "You can't delete a profile without first selecting it."
			return
		}
		set serverdata [lindex [dict get $_profile profiles] $currently_editing_index]
		set servername [dict get $serverdata name]
		if {! [tk_messageBox -type yesno -default no -icon warning -title "Confirm Deletion" -message "Are you SURE you want to delete the server profile \"$servername\"? This operation cannot be undone."]} {
			return
		}
		dict set _profile profiles [lreplace [dict get $_profile profiles] $currently_editing_index $currently_editing_index]
		$w.n.p.servers delete $currently_editing_index
		$w.n.p.servers selection clear 0 end
		set currently_editing_index -1
		dict set _profile current_profile {}
		_select_server $w {}
	}
	proc save {filename data} {
		variable _file_format

		json::write indented true
		json::write aligned true
		dict set data GMA_Mapper_preferences_version 1
		set f [open $filename w]
		puts $f [::gmaproto::_encode_payload $data $_file_format]
		close $f
		json::write indented false
		json::write aligned false
	}

	proc load {filename} {
		variable _file_format

		set f [open $filename r]
		set data [::gmaproto::_construct [json::json2dict [read $f]] $_file_format]
		close $f
		return $data
	}
	# ::gmaproto::_construct input types	types={fieldname s|i|f|?|b|a types|o types|d|l}	-> dict
	# ::gmaproto::_encode_payload input types -> json
	# ::gmaproto::new_dict
	# ::gmaproto::json_bool b	-> true|false
	# ::gmaproto::int_bool b	-> 0|1
	# editor w 
	# create profile editor toplevel window
	proc _bsize {v} {
		global bsizetext button_size
		set bsizetext [format "Button size: %s" $v]
		set button_size $v
	}
	proc _imgfmt {v} {
		global imgtext image_format
		set imgtext [format "Use %s-format images" [string toupper $v]]
		set image_format $v
	}
	proc _cancel {} {
		variable _profile_backup
		variable _profile
		set _profile $_profile_backup
	}
	proc _save {} {
		global animate button_size bsizetext dark image_format keep_tools preload
		global imgtext debug_level debug_proto curl_path profiles
		global major_interval major_offset_x major_offset_y
		global minor_interval minor_offset_x minor_offset_y
		variable _profile

		set _profile [dict replace $_profile \
			animate $animate \
			button_size $button_size \
			curl_path $curl_path \
			dark $dark \
			debug_level $debug_level \
			debug_proto $debug_proto \
			guide_lines [dict create \
				major [dict create \
					interval $major_interval \
					offsets [dict create \
						x $major_offset_x \
						y $major_offset_y\
					]\
				]\
				minor [dict create \
					interval $minor_interval \
					offsets [dict create \
						x $minor_offset_x \
						y $minor_offset_y \
					]\
				]\
			]\
			image_format $image_format \
			keep_tools $keep_tools \
			preload $preload \
		]
	}
	proc _save_server {w} {
		# If there's a current selection, save its values to _profile
		variable currently_editing_index
		if {$currently_editing_index < 0} {
			return
		}
		if {[set cur_idx [$w.n.p.servers curselection]] eq {}} {
			return
		}
		set servername [$w.n.p.servers get $currently_editing_index]
		variable _profile
		global s_hostname s_port s_user s_pass s_curl_proxy s_blur_all
		global s_blur_hp s_suppress_chat s_chat_limit s_chat_log s_curl_server
		global s_update_url s_module_id s_server_mkdir s_nc_path s_scp_path
		global s_scp_dest s_scp_server s_scp_proxy
		dict set _profile current_profile $servername
		if {[catch {scan $s_blur_hp "%d%%" blurpct} err]} {
			set blurpct 0
		}
		set this_entry [dict create \
			name       $servername \
			host       $s_hostname \
			port       $s_port \
			username   $s_user \
			password   $s_pass \
			curl_proxy $s_curl_proxy \
			blur_all   $s_blur_all \
			blur_pct   $blurpct \
			suppress_chat $s_suppress_chat \
			chat_limit $s_chat_limit \
			chat_log   $s_chat_log \
			curl_server $s_curl_server \
			update_url $s_update_url \
			module_id  $s_module_id \
			server_mkdir $s_server_mkdir \
			nc_path      $s_nc_path \
			scp_path     $s_scp_path \
			scp_dest     $s_scp_dest \
			scp_server   $s_scp_server \
			scp_proxy    $s_scp_proxy \
		]
		
		set existing_profiles [dict get $_profile profiles]
		if {[set i [find_server_index $_profile $servername]] >= 0} {
			# replace this entry
			set existing_profiles [lreplace $existing_profiles $i $i $this_entry]
			dict set _profile profiles $existing_profiles
		} else {
			# We didn't find this server in the list, so just append it now
			dict lappend _profile profiles $this_entry
		}
	}
	proc find_server_index {d servername} {
		set existing_profiles [dict get $d profiles]
		for {set i 0} {$i < [llength $existing_profiles]} {incr i} {
			if {[dict get [lindex $existing_profiles $i] name] eq $servername} {
				return $i
			}
		}
		return -1
	}
	proc list_server_names {d} {
		set servers {}
		foreach s [dict get $d profiles] {
			lappend servers [dict get $s name]
		}
		return $servers
	}
	proc _select_server {w serveridx} {
		variable currently_editing_index
		_save_server $w
		if {[llength $serveridx] == 0} {
			# if we just lost focus but didn't select anything, re-select the current entry.
			if {$currently_editing_index >= 0} {
				$w.n.p.servers selection clear 0 end
				$w.n.p.servers selection set $currently_editing_index
				return
			}

			# disable everything
			foreach f {copy del} {
				$w.n.p.$f configure -state  disabled
			}
			foreach f {hostname port user pass phost 
				blurhp nochat chatlim chattx url upd mod
				gmmkd gmncp gmscp gmscpp gmscph gmscpx
			} {
				$w.n.p.settings.$f configure -state disabled
			}
			dict set _profile current_profile {}
			$w.n.p.servers selection clear 0 end
		} else {
			variable _profile
			set currently_editing_index $serveridx
			set servername [$w.n.p.servers get [lindex $serveridx 0]]
			dict set _profile current_profile $servername
			if {[set si [find_server_index $_profile $servername]] < 0} {
				tk_messageBox -type ok -icon error -title "No such server" -message "You tried to select a server called \"$servername\" but no such entry exists in the profile set."
				_select_server $w {}
				return
			}
			# set up everything for the selected server
			set serverdata [lindex [dict get $_profile profiles] $si]

			$w.n.p.copy configure -state normal -text [format "Copy %s" $servername]
			$w.n.p.del configure -state normal -text [format "Delete %s" $servername]
			foreach {fld dfld var} {
				hostname host         s_hostname
				port     port         s_port
				user     username     s_user
				pass     password     s_pass
				phost    curl_proxy   s_curl_proxy
				blurall  blur_all     s_blur_all
				blurhp   blur_pct     s_blur_hp
				nochat   suppress_chat s_suppress_chat
				chatlim  chat_limit   s_chat_limit
				chattx   chat_log     s_chat_log
				url      curl_server  s_curl_server
				upd      update_url   s_update_url
				mod      module_id    s_module_id
				gmmkd    server_mkdir s_server_mkdir
				gmncp    nc_path      s_nc_path
				gmscp    scp_path     s_scp_path
				gmscpp   scp_dest     s_scp_dest
				gmscph   scp_server   s_scp_server
				gmscpx   scp_proxy    s_scp_proxy
			} {
				global $var
				$w.n.p.settings.$fld configure -state normal
				set $var [dict get $serverdata $dfld]
			}
		}
	}
	proc editor {w d} {
		global animate button_size bsizetext dark image_format keep_tools preload
		global imgtext debug_proto debug_level curl_path profiles 
		global major_interval major_offset_x major_offset_y
		global minor_interval minor_offset_x minor_offset_y
		global s_hostname s_port s_user s_pass s_blur_hp
		variable _profile
		variable _profile_backup
		variable currently_editing_index
		set ::gmaprofile::_profile $d
		set ::gmaprofile::_profile_backup $d
		set current_profile {}
		set currently_editing_index -1

		::gmautil::dassign $::gmaprofile::_profile \
			animate animate \
			button_size button_size \
			curl_path curl_path \
			dark dark \
			debug_level debug_level \
			debug_proto debug_proto \
			guide_lines guides \
			image_format image_format \
			keep_tools keep_tools \
			preload preload \
			profiles profiles \
			current_profile current_profile

		set guides [dict merge [dict create \
			major [dict create \
				interval 0\
				offsets [dict create x 0 y 0]]\
			minor [dict create \
				interval 0\
				offsets [dict create x 0 y 0]]\
			] $guides\
		]
		::gmautil::dassign $guides \
			{major interval} major_interval \
			{major offsets x} major_offset_x \
			{major offsets y} major_offset_y \
			{minor interval} minor_interval \
			{minor offsets x} minor_offset_x \
			{minor offsets y} minor_offset_y
		

		if {$image_format eq {}} {
			set image_format png
		}
		if {$button_size eq {}} {
			set button_size small
		}
		_bsize $button_size
		_imgfmt $image_format

		toplevel $w
		ttk::notebook $w.n
		frame $w.n.a
		frame $w.n.d
		frame $w.n.t
		frame $w.n.s
		frame $w.n.p
		$w.n add $w.n.a -state normal -sticky nsew -text Appearance
		$w.n add $w.n.p -state normal -sticky news -text Servers
		$w.n add $w.n.s -state disabled -sticky news -text Styles
		$w.n add $w.n.t -state normal -sticky nsew -text Tools
		$w.n add $w.n.d -state normal -sticky nsew -text Diagnostics

		menu $w.n.a.m_bsize
		$w.n.a.m_bsize add command -label small -command {::gmaprofile::_bsize small}
		$w.n.a.m_bsize add command -label medium -command {::gmaprofile::_bsize medium}
		$w.n.a.m_bsize add command -label large -command {::gmaprofile::_bsize large}
		menu $w.n.a.m_imgfmt
		$w.n.a.m_imgfmt add command -label PNG -command {::gmaprofile::_imgfmt png}
		$w.n.a.m_imgfmt add command -label GIF -command {::gmaprofile::_imgfmt gif}

		grid [ttk::label $w.n.a.title -text "MAPPER APPEARANCE SETTINGS" -anchor center -foreground white -background black] - - - - - - -sticky we -pady 5
		grid [ttk::checkbutton $w.n.a.animate -text "Animate updates" -variable animate] - - - - - - -sticky w
		grid [ttk::checkbutton $w.n.a.dark -text "Dark theme" -variable dark] - - - - - - -sticky w
		grid [ttk::checkbutton $w.n.a.keep -text "Keep toolbar visible" -variable keep_tools] - - - - - - -sticky w
		grid [ttk::checkbutton $w.n.a.preload -text "Pre-load all cached images" -variable preload] - - - - - - -sticky w
		grid [ttk::menubutton $w.n.a.imgfmt -textvariable imgtext -menu $w.n.a.m_imgfmt] - - - - - - -sticky w
		grid [ttk::menubutton $w.n.a.bsize -textvariable bsizetext -menu $w.n.a.m_bsize] - - - - - - -sticky w
		grid [ttk::label $w.n.a.title2 -text "EXTRA GRID LINES" -anchor center -foreground white -background black] - - - - - - -sticky we -pady 5
		grid [ttk::label $w.n.a.majorlbl -text "Major grid lines every"] \
		     [ttk::spinbox $w.n.a.majori -textvariable major_interval -from 0 -to 100 -increment 1 -width 4] \
		     [ttk::label $w.n.a.majorl2 -text "offset by"] \
		     [ttk::spinbox $w.n.a.majorox -textvariable major_offset_x -from -100 -to 100 -increment 1 -width 4] \
		     [ttk::label $w.n.a.majorl3 -text "right, " ] \
		     [ttk::spinbox $w.n.a.majoroy -textvariable major_offset_y -from -100 -to 100 -increment 1 -width 4] \
		     [ttk::label $w.n.a.majorl4 -text "down." ] \
		     	-sticky w
		grid [ttk::label $w.n.a.minorlbl -text "Minor grid lines every"] \
		     [ttk::spinbox $w.n.a.minori -textvariable minor_interval -from 0 -to 100 -increment 1 -width 4] \
		     [ttk::label $w.n.a.minorl2 -text "offset by"] \
		     [ttk::spinbox $w.n.a.minorox -textvariable minor_offset_x -from -100 -to 100 -increment 1 -width 4] \
		     [ttk::label $w.n.a.minorl3 -text "right, " ] \
		     [ttk::spinbox $w.n.a.minoroy -textvariable minor_offset_y -from -100 -to 100 -increment 1 -width 4] \
		     [ttk::label $w.n.a.minorl4 -text "down." ] \
		     	-sticky w

		grid [ttk::label $w.n.t.title -text "PATHS TO SUPPORT PROGRAMS" -anchor center -foreground white -background black] - -sticky we -pady 5
		grid [ttk::label $w.n.t.curl_label -text "Curl program path:"] \
		     [ttk::entry $w.n.t.curl -textvariable curl_path] -sticky w

		grid [ttk::label $w.n.d.title -text "DIAGNOSTIC/DEBUGGING OPTIONS" -anchor center -foreground white -background black] - -sticky we -pady 5
		grid [ttk::label $w.n.d.level_label -text "Debugging level:"] \
		     [ttk::spinbox $w.n.d.level -values {0 1 2 3 4 5 6} -textvariable debug_level -width 2] -sticky w
		grid [ttk::checkbutton $w.n.d.proto -text "Debug client/server protocol messages" -variable debug_proto] - -sticky w

		grid [listbox $w.n.p.servers -yscrollcommand "$w.n.p.scroll set" -selectmode browse] -sticky news
		grid [scrollbar $w.n.p.scroll -orient vertical -command "$w.n.p.servers yview"] -column 1 -row 0 -sticky nsw 
	        grid [button $w.n.p.add -text {Add New...} -command "::gmaprofile::_add_new $w"] -sticky nw -column 2 -row 0
		grid ^ ^ [button $w.n.p.copy -text Copy -state disabled -command "::gmaprofile::_copy_selected $w"] -sticky nw
		grid ^ ^ [button $w.n.p.del -text Delete -state disabled -foreground red -command "::gmaprofile::_delete_selected $w"] -sticky sw
		
		set s $w.n.p.settings
		frame $s
		grid [ttk::label $s.title -text "CONNECTION" -anchor center -foreground white -background black] - - \
		     [ttk::label $s.gmtitle -text "GM SETTINGS" -anchor center -foreground white -background #883333] - \
			     -sticky we -pady 5
		grid [ttk::label $s.hostlabel -text "Hostname:"] \
		     [ttk::entry $s.hostname -textvariable s_hostname] - \
		     [ttk::label $s.gmmkdlbl  -text "Remote mkdir Path:"] \
		     [ttk::entry $s.gmmkd -textvariable s_server_mkdir] \
		     -sticky w
		grid [ttk::label $s.portlabel -text "TCP Port:"] \
		     [ttk::entry $s.port -textvariable s_port] - \
		     [ttk::label $s.gmncplbl  -text "Local nc Path:"] \
		     [ttk::entry $s.gmncp -textvariable s_nc_path] \
		     -sticky w
		grid [ttk::label $s.userlabel -text "User/Character Name:"] \
		     [ttk::entry $s.user -textvariable s_user] - \
		     [ttk::label $s.gmscplbl  -text "Local scp Path:"] \
		     [ttk::entry $s.gmscp -textvariable s_scp_path] \
		     -sticky w
		grid [ttk::label $s.passlabel -text "Password:"] \
		     [ttk::entry $s.pass -textvariable s_pass -show *] - \
		     [ttk::label $s.gmscpplbl  -text "Remote scp Destination:"] \
		     [ttk::entry $s.gmscpp -textvariable s_scp_dest] \
		     -sticky w
		grid [ttk::label $s.phostlbl -text "Proxy Hostname:"] \
		     [ttk::entry $s.phost -textvariable s_curl_proxy] \
		     [ttk::label $w.phelp -text "(used with curl for server images)"] \
		     [ttk::label $s.gmscphlbl -text "Remote Server Hostname:"] \
		     [ttk::entry $s.gmscph -textvariable s_scp_server] \
		     -sticky w

		grid [ttk::label $s.title2 -text "GENERAL SETTINGS" -anchor center -foreground white -background black] - - \
		     [ttk::label $s.gmscpxlbl -text "scp Proxy:"] \
		     [ttk::entry $s.gmscpx -textvariable s_scp_proxy] \
			-sticky we -pady 5
		grid [ttk::checkbutton $s.blurall -text "Blur HP for all creatures" -variable s_blur_all] - - -sticky w
		grid [ttk::label $s.blurlbl -text "Blur HP to"] \
		     [ttk::spinbox $s.blurhp -from 0 -to 100 -increment 1 -textvariable s_blur_hp -width 5 -format "%.0f%%"] \
		     [ttk::label $s.blurhelp -text "(0% to not blur at all)"] -sticky w

		grid [ttk::checkbutton $s.nochat -text "Disable Chat/Die Roll Messages" -variable s_suppress_chat] - - -sticky w
		grid [ttk::label $s.chatlbl -text "Limit Chat History to"] \
		     [ttk::spinbox $s.chatlim -from 0 -to 1000 -increment 50 -textvariable s_chat_limit -width 6] \
		     [ttk::label $s.chathelp -text "(0 to make unlimited)"] -sticky w
		grid [ttk::label $s.chattxlbl -text "Record Chat Transcript to:"] \
		     [ttk::entry $s.chattx -textvariable s_chat_log] \
		     [ttk::label $s.chattxhelp -text "(empty to disable; may use % fields)"] -sticky w
		grid [ttk::label $s.urllbl -text "Server Image Base URL:"] \
		     [ttk::entry $s.url -textvariable s_curl_server] - -sticky we
		grid [ttk::label $s.updlbl -text "Mapper Upgrade URL:"] \
		     [ttk::entry $s.upd -textvariable s_update_url] - -sticky we
		grid [ttk::label $s.modlbl -text "Module Code:"] \
		     [ttk::entry $s.mod -textvariable s_module_id] - -sticky w

	     	grid $s - - - -sticky news

		bind $w.n.p.servers <<ListboxSelect>> "::gmaprofile::_select_server $w \[%W curselection\]"
		_select_server $w {}
		foreach profile [list_server_names $_profile] {
			$w.n.p.servers insert end $profile
			if {$current_profile eq $profile} {
				_select_server $w end
				$w.n.p.servers selection set end
				set currently_editing_index [expr [$w.n.p.servers index end] - 1]
			}
		}

		pack $w.n
		pack [button $w.can -text Cancel -command "::gmaprofile::_cancel; destroy $w"]
		pack [button $w.ok -text Save -command "::gmaprofile::_save_server $w; ::gmaprofile::_save; destroy $w"]

		tkwait window $w
		return $::gmaprofile::_profile
	}
}
