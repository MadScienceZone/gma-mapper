########################################################################################
#  _______  _______  _______                ___       _______  ______      _______     #
# (  ____ \(       )(  ___  ) Game         /   )     / ___   )/ ___  \    / ___   )    #
# | (    \/| () () || (   ) | Master's    / /) |     \/   )  |\/   \  \   \/   )  |    #
# | |      | || || || (___) | Assistant  / (_) (_        /   )   ___) /       /   )    #
# | | ____ | |(_)| ||  ___  |           (____   _)     _/   /   (___ (      _/   /     #
# | | \_  )| |   | || (   ) |                ) (      /   _/        ) \    /   _/      #
# | (___) || )   ( || )   ( | Mapper         | |   _ (   (__/\/\___/  / _ (   (__/\    #
# (_______)|/     \||/     \| Client         (_)  (_)\_______/\______/ (_)\_______/    #
#                                                                                      #
########################################################################################
# Profile editor

package provide gmaprofile 1.4
package require gmacolors
package require json 1.3.3
package require json::write 1.0.3
package require getstring

namespace eval ::gmaprofile {
	namespace export editor
	variable _fontid 0
	variable lockout_select_fbn false
	variable _profile {}
	variable _profile_backup {}
	variable currently_editing_index -1
	variable font_catalog
	variable font_repository
	variable _default_color_table
	variable minimum_file_version 1
	variable maximum_file_version 8
	array set _default_color_table {
		fg,light           #000000
		normal_fg,light    #000000
		bg,light           #cccccc
		normal_bg,light    #cccccc
		fg,dark            #aaaaaa
		normal_fg,dark     #aaaaaa
		bg,dark            #232323
		normal_bg,dark     #232323
		check_select,light #000000
		check_select,dark  #ffffff
		check_menu,light   #000000
		check_menu,dark    #ffffff
		bright_fg,light    #000000
		bright_fg,dark     #ffffff
		grid,light         blue
		grid,dark          #aaaaaa
		grid_minor,light   #b00b03
		grid_minor,dark    #b00b03
		grid_major,light   #345f12
		grid_major,dark    #345f12
		hand_color,light   black
		hand_color,dark    #aaaaaa
		tick_color,light   blue
		tick_color,dark    #aaaaaa
		flist_fg,light     black
		flist_fg,dark      white
		flist_bg,light     white
		flist_bg,dark      #232323
		next_fg,light      white
		next_fg,dark       white
		next_bg,light      black
		next_bg,dark       #cc0000
		cur_bg,light       #9cffb4  
		cur_bg,dark        #003300
		ready_bg,light     #ff3333
		ready_bg,dark      #ff0000
		hold_bg,light      #ffaaaa
		hold_bg,dark       #610400
		zero_hp,light	   #ff0000
		zero_hp,dark	   #ff0000
		negative_hp,light  #000000
		negative_hp,dark   #000000
		slot_fg,light      #000000
		slot_fg,dark       #666666
		slot_bg,light      #666666
		slot_bg,dark       #232323
		flat_footed,light  #3333ff
		flat_footed,dark   #3333ff
		preset_name,dark   cyan
		preset_name,light  blue
	}
	variable _file_format {
		GMA_Mapper_preferences_version i
		animate ?
		button_size s
		chat_timestamp ?
		colorize_die_rolls ?
		curl_path s
		curl_insecure ?
		current_profile s
		dark ?
		debug_level i
		debug_proto ?
		flash_updates ?
		scaling f
		show_timers s
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
		menu_button ?
		never_animate ?
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
			ssh_path s
		    }
	    	}
		fonts {D {family s size f weight i slant i overstrike ? underline ?}}
		styles {o {
			clocks {o {
				hand_color     {o {dark s light s}}
				tick_color     {o {dark s light s}}
				flist_fg       {o {dark s light s}}
				flist_bg       {o {dark s light s}}
				next_fg        {o {dark s light s}}
				next_bg        {o {dark s light s}}
				cur_bg         {o {dark s light s}}
				ready_bg       {o {dark s light s}}
				hold_bg        {o {dark s light s}}
				zero_hp        {o {dark s light s}}
				negative_hp    {o {dark s light s}}
				slot_fg        {o {dark s light s}}
				slot_bg        {o {dark s light s}}
				flat_footed    {o {dark s light s}}
				timedisp_font  s
				turndisp_font  s
				default_font   s
			}}
			dialogs {o {
				heading_fg     {o {dark s light s}}
				normal_fg      {o {dark s light s}}
				normal_bg      {o {dark s light s}}
				highlight_fg   {o {dark s light s}}
				odd_bg         {o {dark s light s}}
				even_bg        {o {dark s light s}}
				check_select   {o {dark s light s}}
				check_menu     {o {dark s light s}}
				bright_fg      {o {dark s light s}}
				grid           {o {dark s light s}}
				grid_minor     {o {dark s light s}}
				grid_major     {o {dark s light s}}
				preset_name    {o {dark s light s}}
			}}
			dierolls {o {
				compact_recents ?
				components {D {
					fg {o {dark s light s}}
					bg {o {dark s light s}}
					font s
					format s
					overstrike ?
					underline ?
					offset i
				}}
			}}
		}}
	}
	variable _description
	array set _description {
		best       {When making "best of n" die rolls, this displays the number of rolls to attempt.}
		begingroup {The operator (i.e., "(") which signals the start of a grouped sub-expression.}
		bonus      {An extra bonus added or subtracted from the roll, such as when confirming a critical hit with a bonus to the confirmation roll only.}
		constant   {A constant value in the die roll expression, such as a bonus or penalty.}
		critlabel  {An indicator that this roll is to confirm a critical hit.}
		critspec   {An indicator that this roll may be subject to confirmation as a critical hit.}
		dc         {An indicator of the target DC for this roll.}
		diebonus   {A bonus or penalty applied to every die rolled for a particular diespec value (but not others in a multiple-die-roll request).}
		diespec    {A die-roll specification such as "3d12" which indicates a random component of the overall expression.}
		discarded  {When making "best of n" or "worst of n" rolls, this indicates a set of die rolls that were discarded to get the required results.}
		endgroup   {The operator (i.e., ")") which signals the end of a grouped sub-expression.}
		error      {An error message from the server indicating what went wrong with your die roll request.}
		exceeded   {When making a roll with a DC target, or using "|until", this indicates the amount by which this roll exceeded the target.}
		fail       {If the roll includes clear success/fail criteria, this indicates why the roll failed.}
		from       {For chat messages and die rolls, this indicates who requested the roll.}
		fullmax    {An indicator that the whole die-roll expression was forced to yield its maximum possible value.}
		fullresult {The overall result of the die roll, displayed at the start of the line before the other details.}
		iteration  {When making multiple rolls due to "|until" or "|repeat" options, this shows the roll number in that sequence.}
		label      {An arbitrary label placed on a component (e.g., the "fire" in "1d6 fire").}
		max        {Indicates a maximum limit placed on the result of the die roll (via the "|max" option).}
		maximized  {An indicator that some or all of a diespec is rolled at maximum value. (For example, a ">" character in this style is placed before a diespec if the first of its dice should be taken at maximum value, as in ">3d6".)}
		maxroll    {This shows the actual results of the individual dice rolled (when they are forced to maximum value).}
		met        {When a specific DC target is known for the die roll, this indicates that it was exactly met.}
		min        {Indicates a minimum limit placed on the result of the die roll (via the "|min" option).}
		moddelim   {This styles the delimiter used to separate modifiers from each other and the die roll specification.}
		normal     {This is the style for text that doesn't fit into any other categories.}
		notice     {A notice sent to you from the server about your die-roll results.}
		operator   {A math operator (such as "+", "-", etc.) between components of the die-roll request.}
		repeat     {An indicator that you want the die-roll expression repeated a number of times.}
		result     {The overal result of the die-roll request.}
		roll       {This shows the actual results of the individual dice rolled (when forced to maximum value, the "maxroll" style is used instead).}
		separator  {Any punctuation that is used as a separator in the die-roll expression.}
		sf         {An indicator that the "|sf" option was used to check for natural min and max rolls as automatic failure or success, along with custom labels, if any, for the success and failure outcomes.}
		short      {When making a roll with a DC target, or using "|until", this indicates the amount by which this roll fell short of the target.}
		subtotal   {This shows a subtotal at various places in a complex, multi-dice roll expression.}
		success    {If the roll includes clear success/fail criteria, this indicates why the roll succeeded.}
		system     {This gives the style to display system messages in the chat window.}
		timestamp  {This gives the style to display timestamps on messages in the chat window.}
		title      {A user-supplied title applied to the die-roll expression.}
		to         {If the die-roll expression or chat message was addressed to specific people, this displays the list of recipients.}
		until      {An indicator that you want to repeat the roll until a specified target value is reached.}
		worst      {When making "worst of n" die rolls, this displays the number of rolls to attempt.}
	}

	proc fix_missing_dieroll_styles {pvar} {
		upvar $pvar prof
		set dprof [default_styles]
		dict for {stylename styledata} [dict get $dprof dierolls components] {
			if {![dict exists $prof styles dierolls components $stylename]} {
				::DEBUG 0 "Preferences missing die-roll style \"$stylename\"; using default"
				dict set prof styles dierolls components $stylename $styledata
			}
		}
		if {![dict exists $prof styles dierolls compact_recents]} {
			dict set prof styles dierolls compact_recents false
		}
	}

	proc fix_missing_dialog_styles {pvar} {
		upvar $pvar prof
		set dprof [default_styles]
		dict for {stylename styledata} [dict get $dprof dialogs] {
			if {![dict exists $prof styles dialogs $stylename] || [dict get $prof styles dialogs $stylename] eq {}} {
				::DEBUG 0 "Preferences missing dialog style \"$stylename\"; using default"
				dict set prof styles dialogs $stylename $styledata
			}
		}
	}
	proc fix_missing_clock_styles {pvar} {
		upvar $pvar prof
		set dprof [default_styles]
		dict for {stylename styledata} [dict get $dprof clocks] {
			if {![dict exists $prof styles clocks $stylename] || [dict get $prof styles clocks $stylename] eq {}} {
				::DEBUG 0 "Preferences missing clock style \"$stylename\"; using default"
				dict set prof styles clocks $stylename $styledata
			}
		}
	}
	proc fix_missing {prefs} {
		upvar $prefs p
		fix_missing_dieroll_styles p
		fix_missing_dialog_styles p
		fix_missing_clock_styles p
		if {![dict exists $p scaling] || [dict get $p scaling] == 0.0} {
			dict set p scaling 1.0
		}
		if {![dict exists $p show_timers]} {
			dict set p show_timers mine
		}
	}
	proc default_preferences {} {
		return [dict create \
			animate         false\
			button_size     small\
			chat_timestamp  true\
			colorize_die_rolls true\
			curl_path       [::gmautil::searchInPath curl]\
			curl_insecure   false\
			current_profile offline\
			dark            false\
			debug_level     0\
			debug_proto     false\
			flash_updates	false\
			guide_lines [dict create \
				major [dict create interval 0 offsets [dict create x 0 y 0]] \
				minor [dict create interval 0 offsets [dict create x 0 y 0]] \
			]\
			image_format png\
			keep_tools   false\
			menu_button  false\
			never_animate false\
			preload      false\
			profiles     [list [empty_server_profile offline]]\
			fonts        [default_fonts]\
			scaling      1.0\
			show_timers  mine\
			styles       [default_styles]\
		]
	}
	proc _add_new_font {w} {
		#
		# _add_new_font profilewindow
		#
		# Add and select new default font
		#
		variable _profile
		if {[::getstring::tk_getString $w.new_font_name newname {Name of new font}] && $newname ne {}} {
			if {[dict exists $_profile fonts $newname]} {
				tk_messageBox -type ok -icon error -title "Duplicate name" -message "You tried to add a font called \"$newname\" but that name already exists in the font set." -parent $w
				return
			}
			$w.n.s.n.f.fonts insert end $newname
			dict set _profile fonts $newname [tk_font_to_dict TkDefaultFont]
			$w.n.s.n.f.fonts selection clear 0 end
			$w.n.s.n.f.fonts selection set end
			_select_font_by_name $w.n.s.n $newname
		}
	}
	proc _selected_font_name {lb} {
		if {[llength [set sel [$lb curselection]]] == 0} {
			return {}
		}
		return [$lb get [lindex $sel 0]]
	}
	proc _selected_dieroll_style_name {lb} {
		if {[llength [set sel [$lb curselection]]] == 0} {
			return {}
		}
		return [$lb get [lindex $sel 0]]
	}
	proc _copy_selected_font {w} {
		variable _profile
		set st $w.n.s.n
		set lb $st.f.fonts

		if {[set srcfont [_selected_font_name $lb]] eq {}} {
			tk_messageBox -type ok -icon error -title "No current selection" -message "You can't make a copy of a font without first selecting the font to copy from." -parent $w
			return
		}
		set srcdata [dict get $_profile fonts $srcfont]
		if {[::getstring::tk_getString $w.new_font_name newname "Name of new font (copy of $srcfont)"] && $newname ne {}} {
			if {[dict exists $_profile fonts $newname]} {
				tk_messageBox -type ok -icon error -title "Duplicate name" -message "You tried to add a font called \"$newname\" but that name already exists in the font set." -parent $w
				return
			}
			$lb insert end $newname
			dict set _profile fonts $newname $srcdata
			$lb selection clear 0 end
			$lb selection set end
			_select_font_by_name $st $newname
		}
	}
	proc _delete_selected_font {w} {
		variable _profile
		set st $w.n.s.n
		set lb $st.f.fonts

		if {[set srcfont [_selected_font_name $lb]] eq {}} {
			tk_messageBox -type ok -icon error -title "No current selection" -message "You can't delete a font without first selecting which one you want to delete." -parent $w
			return
		}
		if {![dict exists $_profile fonts $srcfont]} {
			tk_messageBox -type ok -icon error -title "No such font name" -message "You tried to delete a font called \"$srcfont\" but that name does not exist in the font set." -parent $w
			return
		}
		set references {}
		dict for {stylename styledata} [dict get $_profile styles dierolls components] {
			if {[dict get $styledata font] eq $srcfont} {
				lappend references $stylename
			}
		}
		foreach ff {timedisp_font turndisp_font default_font} {
			if {[dict get $_profile styles clocks $ff] eq $srcfont} {
				lappend references "clock"
				break
			}
		}
		if {[llength $references] > 0} {
			tk_messageBox -type ok -icon error -title "Font in use!" -message "You cannot delete font \"$srcfont\" because it is referenced by one or more dieroll styles." -detail [join $references {, }] -parent $w
			return
		}
		if {! [tk_messageBox -type yesno -default no -icon warning -title "Confirm Deletion" -message "Are you SURE you want to delete the font \"$srcfont\"? This operation cannot be undone." -parent $w]} {
			return
		}
		if {[llength [set idx [$lb curselection]]] == 0} {
			tk_messageBox -type ok -icon error -title "Unable to delete" -message "An error prevented the deletion of the font \"$srcfont\"." -detail "Unable to find the listbox's current selection." -parent $w
			return
		}
		$lb delete [lindex $idx 0]
		$lb selection clear 0 end
		_select_font_by_name $st {}
		dict unset _profile fonts $srcfont
	}
	proc _select_font_by_name {st name} {
		if {$name eq {}} {
			$st.f.copy configure -state disabled -text "Copy"
			$st.f.del configure -state disabled -text "Delete"
			_describe_font $st.f.name {}
			_display_pangram $st.f.sample {}

			$st.f.fonts selection clear 0 end
		} else {
			variable _profile
			# update buttons
			$st.f.copy configure -state normal -text "Copy $name"
			$st.f.del configure -state normal -text "Delete $name"
			# show sample displays
			_describe_font $st.f.name [set fontd [dict get $_profile fonts $name]]
			_display_pangram $st.f.sample [define_font $fontd]
		}
	}
	proc _select_font_by_idx {st idx} {
		if {$idx eq {}} {
			_select_font_by_name $st {}
		} else {
			_select_font_by_name $st [$st.f.fonts get $idx]
		}
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
			chat_limit 500 \
			chat_log {} \
			curl_server {} \
			update_url {} \
			module_id {} \
			server_mkdir {} \
			nc_path [::gmautil::searchInPath nc] \
			scp_path [::gmautil::searchInPath scp] \
			scp_dest {} \
			scp_server {} \
			scp_proxy {} \
			ssh_path [::gmautil::searchInPath ssh] \
		]
	}
	proc _add_new {w} {
		variable _profile
		if {[::getstring::tk_getString $w.new_profile_name newname {Name of new server profile}] && $newname ne {}} {
			if {[find_server_index $_profile $newname] >= 0} {
				tk_messageBox -type ok -icon error -title "Duplicate name" -message "You tried to add a server called \"$newname\" but that name already exists in the profile set." -parent $w
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
			tk_messageBox -type ok -icon error -title "No current selection" -message "You can't make a copy of a profile without first selecting the profile to copy from." -parent $w
			return
		}
		set serverdata [lindex [dict get $_profile profiles] $currently_editing_index]
		set servername [dict get $serverdata name]
		if {[::getstring::tk_getString $w.new_profile_name newname "Name of new server profile (copy of $servername)"] && $newname ne {}} {
			if {[find_server_index $_profile $newname] >= 0} {
				tk_messageBox -type ok -icon error -title "Duplicate name" -message "You tried to add a server called \"$newname\" but that name already exists in the profile set." -parent $w
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
			tk_messageBox -type ok -icon error -title "No current selection" -message "You can't delete a profile without first selecting it." -parent $w
			return
		}
		set serverdata [lindex [dict get $_profile profiles] $currently_editing_index]
		set servername [dict get $serverdata name]
		if {! [tk_messageBox -type yesno -default no -icon warning -title "Confirm Deletion" -message "Are you SURE you want to delete the server profile \"$servername\"? This operation cannot be undone." -parent $w]} {
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
		dict set data GMA_Mapper_preferences_version 8
		set f [open $filename w]
		puts $f [::gmaproto::_encode_payload $data $_file_format]
		close $f
		json::write indented false
		json::write aligned false
	}

	proc load {filename} {
		variable _file_format
		variable minimum_file_version 
		variable maximum_file_version 


		set f [open $filename r]
		set data [::gmaproto::_construct [json::json2dict [read $f]] $_file_format]
		set v [dict get $data GMA_Mapper_preferences_version]
		if {$v < $minimum_file_version} {
			tk_messageBox -type ok -icon error -title "Outdated Preferences" -message "Your saved preferences file is of a format too old to be read by this version of the mapper." -detail "$filename is version $v, but the minimum version supported is $minimum_file_version." -parent .
		}
		if {$v > $maximum_file_version} {
			tk_messageBox -type ok -icon error -title "Unsuppored Preferences" -message "Your saved preferences file is of a format newer than what this version of the mapper is designed to use." -detail "$filename is version $v, but the maximum version supported is $maximum_file_version." -parent .
		}
		close $f
		if {![dict exists $data fonts] || [dict size [dict get $data fonts]] == 0} {
			puts "** Preferences data is missing font list; setting to default **"
			dict set data fonts [default_fonts]
		}
		dict for {font_name font_dict} [default_fonts] {
			if {![dict exists $data fonts $font_name]} {
				puts "** Preferences data is missing font $font_name; setting to default $font_dict **"
				dict set data fonts $font_name $font_dict
			}
		}
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
	proc _show_timers {v} {
		global t_show_timers show_timers
		switch -exact $v {
			none { set t_show_timers "Show no timers"; set show_timers none }
			all { set t_show_timers "Show all timers"; set show_timers all }
			default { set t_show_timers "Show only my timers"; set show_timers mine }
		}
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
		global animate colorize_die_rolls button_size bsizetext show_timers scaling dark image_format keep_tools preload
		global imgtext debug_level debug_proto curl_path curl_insecure profiles menu_button never_animate
		global major_interval major_offset_x major_offset_y
		global minor_interval minor_offset_x minor_offset_y flash_updates
		global chat_timestamp
		variable _profile

		set _profile [dict replace $_profile \
			animate $animate \
			button_size $button_size \
			chat_timestamp $chat_timestamp \
			colorize_die_rolls $colorize_die_rolls \
			curl_path $curl_path \
			curl_insecure $curl_insecure \
			dark $dark \
			debug_level $debug_level \
			debug_proto $debug_proto \
			flash_updates $flash_updates \
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
			menu_button $menu_button\
			never_animate $never_animate\
			keep_tools $keep_tools \
			preload $preload \
			scaling $scaling \
			show_timers $show_timers \
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
		global s_update_url s_module_id s_server_mkdir s_nc_path s_scp_path s_ssh_path
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
			ssh_path     $s_ssh_path \
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
			#if {$currently_editing_index >= 0} {
			#	$w.n.p.servers selection clear 0 end
			#	$w.n.p.servers selection set $currently_editing_index
			#	return
			#}

			# disable everything
			foreach f {copy del} {
				$w.n.p.$f configure -state  disabled
			}
			foreach f {hostname port user pass phost 
				blurhp nochat chatlim chattx url upd mod
				gmmkd gmncp gmscp gmscpp gmscph gmscpx gmsshp
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
				tk_messageBox -type ok -icon error -title "No such server" -message "You tried to select a server called \"$servername\" but no such entry exists in the profile set." -parent $w
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
				gmsshp   ssh_path     s_ssh_path
			} {
				global $var
				$w.n.p.settings.$fld configure -state normal
				set $var [dict get $serverdata $dfld]
			}
			set s_blur_all [::gmaproto::int_bool $s_blur_all]
			set s_suppress_chat [::gmaproto::int_bool $s_suppress_chat]
		}
	}
	proc set_current_profile {d idx} {
		dict set d current_profile [dict get [lindex [dict get $d profiles] $idx] name]
		return $d
	}

	proc editor {w d} {
		global animate button_size bsizetext colorize_die_rolls show_timers scaling dark image_format keep_tools preload chat_timestamp
		global imgtext debug_proto debug_level curl_path curl_insecure profiles menu_button never_animate
		global major_interval major_offset_x major_offset_y
		global minor_interval minor_offset_x minor_offset_y flash_updates
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
			chat_timestamp chat_timestamp \
			colorize_die_rolls colorize_die_rolls \
			curl_path curl_path \
			curl_insecure curl_insecure \
			dark dark \
			debug_level debug_level \
			debug_proto debug_proto \
			flash_updates flash_updates\
			guide_lines guides \
			image_format image_format \
			keep_tools keep_tools \
			menu_button menu_button \
			never_animate never_animate\
			preload preload \
			profiles profiles \
			current_profile current_profile \
			scaling scaling \
			show_timers show_timers

		set animate [::gmaproto::int_bool $animate]
		set flash_updates [::gmaproto::int_bool $flash_updates]
		set colorize_die_rolls [::gmaproto::int_bool $colorize_die_rolls]
		set chat_timestamp [::gmaproto::int_bool $chat_timestamp]
		set dark [::gmaproto::int_bool $dark]
		set menu_button [::gmaproto::int_bool $menu_button]
		set never_animate [::gmaproto::int_bool $never_animate]
		set keep_tools [::gmaproto::int_bool $keep_tools]
		set preload [::gmaproto::int_bool $preload]
		set debug_proto [::gmaproto::int_bool $debug_proto]

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
		wm title $w "Mapper Preferences"
		ttk::notebook $w.n
		frame $w.n.a
		frame $w.n.d
		frame $w.n.t
		frame $w.n.s
		frame $w.n.p
		$w.n add $w.n.a -state normal -sticky nsew -text Appearance
		$w.n add $w.n.p -state normal -sticky news -text Servers
		$w.n add $w.n.s -state normal -sticky news -text Styles
		$w.n add $w.n.t -state normal -sticky nsew -text Tools
		$w.n add $w.n.d -state normal -sticky nsew -text Diagnostics

		ttk::notebook $w.n.s.n
		set st $w.n.s.n
		frame $st.f
		frame $st.d
		frame $st.r
		frame $st.c
		frame $st.cl
		$st add $st.f -state normal -sticky news -text Fonts
		$st add $st.d -state normal -sticky news -text Dialogs
		$st add $st.r -state normal -sticky news -text {Die Rolls/Chat}
		$st add $st.c -state normal -sticky news -text Colors
		$st add $st.cl -state normal -sticky news -text Clocks

		grid x [label $st.d.tl -text {Light Mode}] [label $st.d.td -text {Dark Mode}]
		set row 1
		foreach {wp name fld} {
			hfg {Heading color}          heading_fg
			nfg {Normal text color}      normal_fg
			nbg {Normal text background} normal_bg
			ifg {Highlighted text color} highlight_fg
			obg {Odd-row background}     odd_bg
			ebg {Even-row background}    even_bg
			pre {Die-roll preset name color} preset_name
		} {
			grid configure [label $st.d.l$wp -text "$name:"] -column 0 -row $row -padx 5 -sticky w
			set col 1
			foreach theme {light dark} {
				set color [dict get $_profile styles dialogs $fld $theme]
				grid configure [button $st.d.$wp$theme -bg $color -text [::gmacolors::rgb_name $color] \
					-highlightcolor $color -highlightbackground $color -highlightthickness 2 \
					-command "::gmaprofile::_set_dialog_color [list $st $st.d.$wp$theme $theme $name $fld]"]\
					-column $col -row $row -padx 1 -pady 1 -sticky we
				incr col
			}
			grid configure [button $st.d.${wp}reset -text "Reset to Default" \
				-command "::gmaprofile::_reset_default_dialog_color [list $st $st.d.$wp $fld]"]\
				-column 3 -row $row -padx 5 -pady 1 -sticky we
			incr row
		}
		
		grid [label $st.d.exll -text "Light Mode Example:"] [text $st.d.extl -height 13] - - -sticky news
		grid [label $st.d.exld -text "Dark Mode Example:"]  [text $st.d.extd -height 13] - - -sticky news
		_refresh_dialog_examples $st


		grid x [label $st.c.tl -text {Light Mode}] [label $st.c.td -text {Dark Mode}]
		set row 1
		foreach {wp name fld} {
			grid {Normal 5' grid color}   grid
			gmin {Minor guide grid color} grid_minor
			gmaj {Major guide grid color} grid_major
			chkm {Check menu color}       check_menu
			chks {Checkbox select color}  check_select
		} {
			grid configure [label $st.c.l$wp -text "$name:"] -column 0 -row $row -padx 5 -sticky w
			set col 1
			foreach theme {light dark} {
				set color [dict get $_profile styles dialogs $fld $theme]
				grid configure [button $st.c.$wp$theme -bg $color -text [::gmacolors::rgb_name $color] \
					-highlightcolor $color -highlightbackground $color -highlightthickness 2 \
					-command "::gmaprofile::_set_dialog_color [list $st $st.c.$wp$theme $theme $name $fld]"]\
					-column $col -row $row -padx 1 -pady 1 -sticky we
				incr col
			}
			grid configure [button $st.c.${wp}reset -text "Reset to Default" \
				-command "::gmaprofile::_reset_default_dialog_color [list $st $st.c.$wp $fld]"]\
				-column 3 -row $row -padx 5 -pady 1 -sticky we
			incr row
		}
#		menu $st.r.ftmenu -postcommand "::gmaprofile::_update_font_menu $st $st.r.ftmenu PEsFT"
#		_update_font_menu $st $st.r.ftmenu PEsFT
#	 	grid ^ ^ [label $st.r.ften -text "Font:"] \
#			 [ttk::menubutton $st.r.ft -menu $st.r.ftmenu -textvariable PEsFT] - - - -sticky w
		
		grid x [label $st.cl.tl -text {Light Mode}] [label $st.cl.td -text {Dark Mode}]
		set row 1
		foreach {wp name fld} {
			hand {Clock hands}                  hand_color
			tick {Clock tick marks}             tick_color
			ffg  {Initiative list text color}   flist_fg
			fbg  {Initiative list background}   flist_bg
			nexf {Next round marker color}      next_fg
			nexb {Next round marker background} next_bg
			cur  {Current actor background}     cur_bg
			rdy  {Readied action background}    ready_bg
			hold {Held action background}       hold_bg
			hp0  {Frame: zero hit points}       zero_hp
			hpng {Frame: negative hit points}   negative_hp
			flat {Frame: flat-footed}           flat_footed
			sfg  {Negative hit point text color} slot_fg
			sbg  {Negative hit point background} slot_bg
		} {
			grid configure [label $st.cl.l$wp -text "$name:"] -column 0 -row $row -padx 5 -sticky w
			set col 1
			foreach theme {light dark} {
				set color [dict get $_profile styles clocks $fld $theme]
				grid configure [button $st.cl.$wp$theme -bg $color -text [::gmacolors::rgb_name $color] \
					-highlightcolor $color -highlightbackground $color -highlightthickness 2 \
					-command "::gmaprofile::_set_clock_color [list $st $st.cl.$wp$theme $theme $name $fld]"]\
					-column $col -row $row -padx 1 -pady 1 -sticky we
				incr col
			}
			grid configure [button $st.cl.${wp}reset -text "Reset to Default" \
				-command "::gmaprofile::_reset_default_clock_color [list $st $st.cl.$wp $fld]"]\
				-column 3 -row $row -padx 5 -pady 1 -sticky we
			incr row
		}

		foreach {mn fld mdesc mvar} {
			1 timedisp_font "Time display font"    PEsCF1
			2 turndisp_font "Turn display font"    PEsCF2
			3 default_font  "Initiative list font" PEsCF3
		} {
			menu $st.cl.ftmenu$mn -postcommand "::gmaprofile::_update_clock_font_menu [list $st $st.cl.ftmenu$mn $mdesc $mvar $fld]"
			_update_clock_font_menu $st $st.cl.ftmenu$mn $mdesc $mvar $fld
			grid [label $st.cl.ften$mn -text $mdesc] \
				 [ttk::menubutton $st.cl.ft$mn -menu $st.cl.ftmenu$mn -textvariable $mvar] - - - -sticky w
			global $mvar
			set $mvar [dict get $_profile styles clocks $fld]
		}
		
		grid [listbox $st.r.styles -yscrollcommand "$st.r.scroll set" -selectmode browse\
			-selectforeground white -selectbackground blue\
			-exportselection false\
			] -sticky news
		grid [scrollbar $st.r.scroll -orient vertical -command "$st.r.styles yview"] -column 1 -row 0 -sticky nsw
		grid [text $st.r.description -relief flat -height 3 -wrap word -font TkDefaultFont] -sticky news -column 2 -row 0 -columnspan 4
		grid ^ ^ x [label $st.r.tl -text {Light Mode}] [label $st.r.td -text {Dark Mode}]
		grid ^ ^ [ttk::checkbutton $st.r.fgen -text "Text color:" -variable PEsFGen \
			      -command "::gmaprofile::_enable_style $st \$PEsFGen {fglt fg light fgdk fg dark}"] \
			 [button $st.r.fglt -command "::gmaprofile::_set_style_color $st fglt fg light"] \
			 [button $st.r.fgdk -command "::gmaprofile::_set_style_color $st fgdk fg dark"] \
			 [label $st.r.ltex -text {Sample (light mode)}] -sticky w
		grid ^ ^ [ttk::checkbutton $st.r.bgen -text "Background color:" -variable PEsBGen \
			      -command "::gmaprofile::_enable_style $st \$PEsBGen {bglt bg light bgdk bg dark}"] \
			 [button $st.r.bglt -command "::gmaprofile::_set_style_color $st bglt bg light"] \
			 [button $st.r.bgdk -command "::gmaprofile::_set_style_color $st bgdk bg dark"] \
			 [label $st.r.dkex -text {Sample (dark mode)}] -sticky w
		grid configure $st.r.fglt -sticky we
		grid configure $st.r.fgdk -sticky we
		grid configure $st.r.bglt -sticky we
		grid configure $st.r.bgdk -sticky we

		menu $st.r.ftmenu -postcommand "::gmaprofile::_update_font_menu $st $st.r.ftmenu PEsFT"
		_update_font_menu $st $st.r.ftmenu PEsFT
	 	grid ^ ^ [label $st.r.ften -text "Font:"] \
			 [ttk::menubutton $st.r.ft -menu $st.r.ftmenu -textvariable PEsFT] - - - -sticky w

		grid ^ ^ [label $st.r.fmen -text "Display Format:"] \
			 [entry $st.r.fmfmt -validate key -validatecommand "::gmaprofile::_set_style_format [list $st %W %P]"] - \
			 [label $st.r.fmlbl -text {(_=leading/trailing space; blank for default format)}] -sticky w

		grid ^ ^ [ttk::checkbutton $st.r.oven -text "Overstrike" -variable PEsOVen \
			      -command "::gmaprofile::_set_style_overstrike $st \$PEsOVen"] -sticky w
		grid ^ ^ [ttk::checkbutton $st.r.unen -text "Underline" -variable PEsUNen \
			      -command "::gmaprofile::_set_style_underscore $st \$PEsUNen"] -sticky w
		grid ^ ^ [label $st.r.oflbl -text {Raise (Lower) text by:}] \
		         [ttk::spinbox $st.r.ofamt -validate all \
			 	-validatecommand "::gmaprofile::_set_style_offset [list $st %W %P]" \
			 	-command "::gmaprofile::_set_style_offset [list $st $st.r.ofamt -spin]" \
				-from -100 -to 100 -increment 1 -width 4] -sticky w

		grid ^ ^ [button $st.r.reset -text {Reset to Default Values} -command "::gmaprofile::_reset_style $st"] -sticky w
		grid [ttk::checkbutton $st.r.compact -text "Use less compact layout for die roll presets" -variable PEsCRen \
			-command "::gmaprofile::_set_style_compact $st \$PEsCRen"] - - - - -sticky w
		global PEsCRen
		set PEsCRen [::gmaproto::int_bool [dict get $_profile styles dierolls compact_recents]]

		grid rowconfigure $st.r 11 -weight 2
		grid rowconfigure $st.r 12 -weight 2

		foreach stylename [lsort [dict keys [dict get $_profile styles dierolls components]]] {
			$st.r.styles insert end $stylename
		}
		bind $st.r.styles <<ListboxSelect>> "::gmaprofile::_select_dieroller_style $st \[%W curselection\]"

		grid [label $st.r.lexl -text "Light mode example:"] - [text $st.r.exl -height 8 -yscrollcommand "$st.r.exls set"] - - - \
		     [scrollbar $st.r.exls -orient vertical -command "$st.r.exl yview"] -sticky nes
		grid [label $st.r.lexd -text "Dark mode example:"] - [text $st.r.exd -height 8 -yscrollcommand "$st.r.exds set"] - - - \
		     [scrollbar $st.r.exds -orient vertical -command "$st.r.exd yview"] -sticky nes
		grid columnconfigure $st.r 2 -weight 2
		_select_dieroller_style $st {}
		_refresh_dieroller_examples $st

		grid [listbox $st.f.fonts -yscrollcommand "$st.f.scroll set" -selectmode browse\
			-selectforeground white -selectbackground blue\
			-exportselection false\
			] -sticky news
		grid [scrollbar $st.f.scroll -orient vertical -command "$st.f.fonts yview"] -column 1 -row 0 -sticky nsw 
	        grid [button $st.f.add -text {Add New...} -command "::gmaprofile::_add_new_font $w"] -sticky nw -column 2 -row 0
		grid ^ ^ [button $st.f.copy -text Copy -state disabled -command "::gmaprofile::_copy_selected_font $w"] -sticky nw
		grid ^ ^ [button $st.f.del -text Delete -state disabled -foreground red -command "::gmaprofile::_delete_selected_font $w"] -sticky sw
		tk fontchooser configure -parent $w -title "Choose Font" -command "::gmaprofile::_new_font_chosen $w"
		catch {tk fontchooser hide}
		grid [button $st.f.choose -text "Show Font Chooser" -command "::gmaprofile::_toggle_chooser $w"] - - -sticky nws
		_chooser_visibility $w
		bind $w <<TkFontchooserVisibility>> [list ::gmaprofile::_chooser_visibility $w]
		bind $w <<TkFontchooserFontChanged>> {}
		bind $st.f.fonts <<ListboxSelect>> "::gmaprofile::_select_font_by_idx $st \[%W curselection\]"
		grid [label $st.f.name -text ""] - - - -sticky w
		grid [label $st.f.sample -text ""] - - - - -sticky w
		_select_font_by_name $st {}
		foreach font [dict keys [dict get $_profile fonts]] {
			$st.f.fonts insert end $font
		}


		grid $w.n.s.n -sticky news
		grid columnconfigure $w.n.s.n 0 -weight 0
		grid columnconfigure $w.n.s.n 3 -weight 2
		grid columnconfigure $w.n.s 0 -weight 2
		grid columnconfigure $w.n 0 -weight 2

		set sep_fg white
		if $dark {
			set sep_bg #000090
		} else {
			set sep_bg black
		}


		menu $w.n.a.m_bsize
		$w.n.a.m_bsize add command -label small -command {::gmaprofile::_bsize small}
		$w.n.a.m_bsize add command -label medium -command {::gmaprofile::_bsize medium}
		$w.n.a.m_bsize add command -label large -command {::gmaprofile::_bsize large}
		menu $w.n.a.m_imgfmt
		$w.n.a.m_imgfmt add command -label PNG -command {::gmaprofile::_imgfmt png}
		$w.n.a.m_imgfmt add command -label GIF -command {::gmaprofile::_imgfmt gif}
		menu $w.n.a.m_show_timers
		$w.n.a.m_show_timers add command -label "Show no timers" -command {::gmaprofile::_show_timers none}
		$w.n.a.m_show_timers add command -label "Show only my timers" -command {::gmaprofile::_show_timers mine}
		$w.n.a.m_show_timers add command -label "Show all timers" -command {::gmaprofile::_show_timers all}
		::gmaprofile::_show_timers $show_timers

		grid [ttk::label $w.n.a.title -text "MAPPER APPEARANCE SETTINGS" -anchor center -foreground $sep_fg -background $sep_bg] - - - - - - -sticky we -pady 5
		grid [ttk::checkbutton $w.n.a.animate -text "Animate updates" -variable animate] - - - - - - -sticky w
		grid [ttk::checkbutton $w.n.a.flash -text "Flash objects when they are updated" -variable flash_updates] - - - - - - -sticky w
		grid [ttk::checkbutton $w.n.a.chat_timestamp -text "Show timestamp in chat messages" -variable chat_timestamp] - - - - - - -sticky w
		grid [ttk::checkbutton $w.n.a.cdr -text "Enable colors in die-roll titles" -variable colorize_die_rolls] - - - - - - -sticky w
		grid [ttk::checkbutton $w.n.a.dark -text "Dark theme" -variable dark] - - - - - - -sticky w
		grid [ttk::label $w.n.a.scalingl -text "Visual scaling factor:"] [ttk::spinbox $w.n.a.scaling -textvariable scaling -from 1.0 -to 100.0 -increment 1.0 -format "%.1f" -width 5] -sticky we
		grid [ttk::checkbutton $w.n.a.menu_button -text "Use menu button instead of menu bar" -variable menu_button] - - - - - - -sticky w
		grid [ttk::checkbutton $w.n.a.never_animate -text "Never play animated images" -variable never_animate] - - - - - - -sticky w
		grid [ttk::checkbutton $w.n.a.keep -text "Keep toolbar visible" -variable keep_tools] - - - - - - -sticky w
		grid [ttk::menubutton $w.n.a.show_timers -textvariable t_show_timers -menu $w.n.a.m_show_timers] - - - - - - -sticky w
		grid [ttk::checkbutton $w.n.a.preload -text "Pre-load all cached images" -variable preload] - - - - - - -sticky w
		grid [ttk::menubutton $w.n.a.imgfmt -textvariable imgtext -menu $w.n.a.m_imgfmt] - - - - - - -sticky w
		grid [ttk::menubutton $w.n.a.bsize -textvariable bsizetext -menu $w.n.a.m_bsize] - - - - - - -sticky w
		grid [ttk::label $w.n.a.title2 -text "EXTRA GRID LINES" -anchor center -foreground $sep_fg -background $sep_bg] - - - - - - -sticky we -pady 5
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

		grid [ttk::label $w.n.t.title -text "PATHS TO SUPPORT PROGRAMS" -anchor center -foreground $sep_fg -background $sep_bg] - -sticky we -pady 5
		grid [ttk::label $w.n.t.curl_label -text "Curl program path:"] \
		     [ttk::entry $w.n.t.curl -textvariable curl_path] -sticky w
	     	grid [ttk::checkbutton $w.n.t.curl_k -text "Run Curl in insecure mode" -variable curl_insecure] - -sticky w

		grid [ttk::label $w.n.d.title -text "DIAGNOSTIC/DEBUGGING OPTIONS" -anchor center -foreground $sep_fg -background $sep_bg] - -sticky we -pady 5
		grid [ttk::label $w.n.d.level_label -text "Debugging level:"] \
		     [ttk::spinbox $w.n.d.level -values {0 1 2 3 4 5 6} -textvariable debug_level -width 2] -sticky w
		grid [ttk::checkbutton $w.n.d.proto -text "Debug client/server protocol messages" -variable debug_proto] - -sticky w

		grid [listbox $w.n.p.servers -yscrollcommand "$w.n.p.scroll set" -selectmode browse\
			-selectforeground white -selectbackground blue\
			-exportselection false\
			] -sticky news
		grid [scrollbar $w.n.p.scroll -orient vertical -command "$w.n.p.servers yview"] -column 1 -row 0 -sticky nsw 
	        grid [button $w.n.p.add -text {Add New...} -command "::gmaprofile::_add_new $w"] -sticky nw -column 2 -row 0
		grid ^ ^ [button $w.n.p.copy -text Copy -state disabled -command "::gmaprofile::_copy_selected $w"] -sticky nw
		grid ^ ^ [button $w.n.p.del -text Delete -state disabled -foreground red -command "::gmaprofile::_delete_selected $w"] -sticky sw
		
		set s $w.n.p.settings
		frame $s
		grid [ttk::label $s.title -text "CONNECTION" -anchor center -foreground $sep_fg -background $sep_bg] - - \
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
		     [ttk::entry $s.pass -textvariable s_pass -show *] \
		     [button $s.passvis -command "::gmaprofile::_toggle_password_visibility $s" -text "show"] \
		     [ttk::label $s.gmscpplbl  -text "Remote scp Destination:"] \
		     [ttk::entry $s.gmscpp -textvariable s_scp_dest] \
		     -sticky w
		grid [ttk::label $s.phostlbl -text "Proxy Hostname:"] \
		     [ttk::entry $s.phost -textvariable s_curl_proxy] \
		     [ttk::label $w.phelp -text "(used with curl for server images)"] \
		     [ttk::label $s.gmscphlbl -text "Remote Server Hostname:"] \
		     [ttk::entry $s.gmscph -textvariable s_scp_server] \
		     -sticky w

		grid [ttk::label $s.title2 -text "GENERAL SETTINGS" -anchor center -foreground $sep_fg -background $sep_bg] - - \
		     [ttk::label $s.gmscpxlbl -text "scp Proxy:"] \
		     [ttk::entry $s.gmscpx -textvariable s_scp_proxy] \
			-sticky we -pady 5

		grid [ttk::checkbutton $s.blurall -text "Blur HP for all creatures" -variable s_blur_all] - - \
		     [ttk::label $s.gmsshplbl -text "ssh Path:"] \
		     [ttk::entry $s.gmsshp -textvariable s_ssh_path] \
			-sticky w

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
		     [ttk::entry $s.url -textvariable s_curl_server] - - - -sticky we
		grid [ttk::label $s.updlbl -text "Mapper Upgrade URL:"] \
		     [ttk::entry $s.upd -textvariable s_update_url] - - - -sticky we
		grid [ttk::label $s.modlbl -text "Module Code:"] \
		     [ttk::entry $s.mod -textvariable s_module_id] - -sticky w

	     	grid $s - - - -sticky news

		bind $w.n.p.servers <<ListboxSelect>> "::gmaprofile::_select_server $w \[%W curselection\]"
		_select_server $w {}
		foreach profile [list_server_names $_profile] {
			$w.n.p.servers insert end $profile
			if {$current_profile eq $profile || $current_profile eq {}} {
				_select_server $w end
				$w.n.p.servers selection set end
				set currently_editing_index [expr [$w.n.p.servers index end] - 1]
			}
		}

		pack $w.n
		pack [button $w.can -text Cancel -command "::gmaprofile::_cancel; destroy $w"] -side left
		pack [button $w.ok -text Save -command "::gmaprofile::_save_server $w; ::gmaprofile::_save; destroy $w"] -side right

		tkwait window $w
		return $::gmaprofile::_profile
	}

	proc _chooser_visibility {w} {
		if {[tk fontchooser configure -visible]} {
			$w.n.s.n.f.choose configure -text "Hide Font Chooser"
		} else {
			$w.n.s.n.f.choose configure -text "Show Font Chooser"
		}
	}

	proc _toggle_chooser {w} {
		if {[tk fontchooser configure -visible]} {
			tk fontchooser hide
		} else {
			tk fontchooser show
		}
	}

	proc _new_font_chosen {w newfont} {
		variable _profile
		if {[llength $newfont] < 2} {
			puts "Can't understand font \"$newfont\""
			tk_messageBox -type ok -icon error -title "Invalid Font Data" -message "You selected a new font, but I am unable to understand what it means." -parent $w
			return
		}
		if {[set newfontname [_selected_font_name $w.n.s.n.f.fonts]] eq {}} {
			tk_messageBox -type ok -icon error -title "No Font Selected" -message "You selected a new font, but did not select which font that was supposed to modify." -parent $w
			return
		}
		set fontd [dict create family [lindex $newfont 0] \
			  size   [lindex $newfont 1] \
			  weight [expr [lsearch -exact [lrange $newfont 2 end] bold] >= 0 ? 1 : 0] \
			  slant  [expr [lsearch -exact [lrange $newfont 2 end] italic] >= 0 ? 1 : 0] \
			  overstrike [expr [lsearch -exact [lrange $newfont 2 end] overstrike] >= 0 ? 1 : 0] \
			  underline  [expr [lsearch -exact [lrange $newfont 2 end] underline] >= 0 ? 1 : 0] \
		]
		dict set _profile fonts $newfontname $fontd
		_describe_font $w.n.s.n.f.name $fontd
		_display_pangram $w.n.s.n.f.sample [define_font $fontd]
		#_refresh_dialog_examples $w.n.s.n
	}
	proc _describe_font {w d} {
		if {$d eq {}} {
			$w configure -text ""
			return
		}
		set desc "[dict get $d family] [dict get $d size]"
		if {[dict get $d weight] > 0} {append desc ", bold"}
		if {[dict get $d slant] > 0}  {append desc ", italic"}
		if {[dict get $d overstrike]}  {append desc ", overstrike"}
		if {[dict get $d underline]}  {append desc ", underline"}
		$w configure -text "$desc: "
	}

	proc _display_pangram {w fnt} {
		if {$fnt eq {}} {
			$w configure -text ""
			return
		}
		set pangram_list [list \
			"Waltz, bad nymph, for quick jigs vex" \
			"Glib jocks quiz nymph to vex dwarf." \
			"Sphinx of black quartz, judge my vow." \
			"How quickly daft jumping zebras vex!" \
			"The five boxing wizards jump quickly." \
			"Jackdaws love my big sphinx of quartz." \
			"Pack my box with five dozen liquor jugs." \
		]

		$w configure -text "[lindex $pangram_list [expr [clock clicks] % [llength $pangram_list]]]; 0,123,456,789 +-*/ [](){}?!" -font $fnt
	}
	proc _font_name_hash {d} {
		# derive a unique but deterministic name for a font based on its properties.
		return "Ft_[::md5::md5 -hex $d]"
	}
	proc tk_font_to_dict {font} {
		return [dict create \
			family     [font configure $font -family] \
			size       [font configure $font -size] \
			weight     [expr {[font configure $font -weight]} eq {{bold}}  ? 1 : 0] \
			slant      [expr {[font configure $font -slant]} eq {{italic}} ? 1 : 0] \
			overstrike [font configure $font -overstrike] \
			underline  [font configure $font -underline] \
		]
	}

	proc lookup_font {prefs name} {
		if {[dict exists $prefs fonts $name]} {
			return [define_font [dict get $prefs fonts $name]]
		}
		::DEBUG 0 "No such font \"$name\" defined; using default"
		return [define_font [tk_font_to_dict TkDefaultFont]]
	}

	proc define_font {d} {
		# define a Tk font from the given dictionary and return its name. If that font
		# already exists, just return the name.
		set weights [list normal bold]
		set slants  [list roman italic]
		variable font_repository
		set f [_font_name_hash $d]
		if {! [info exists font_repository($f)]} {
			font create $f -family [dict get $d family] -size [dict get $d size] \
				-weight [lindex $weights [dict get $d weight]] \
				-slant  [lindex $slants  [dict get $d slant]] \
				-overstrike [dict get $d overstrike] \
				-underline [dict get $d underline]
			set font_repository($f) [list $d]
		}
		return $f
	}
	# The default set of fonts
	proc default_fonts {} {
		return [dict create \
			Normal [dict create family Helvetica size 12 weight 0 slant 0 overstrike false underline false] \
			Important [dict create family Helvetica size 12 weight 1 slant 0 overstrike false underline false] \
			Special [dict create family Times     size 12 weight 0 slant 1 overstrike false underline false] \
			System [dict create family Times     size 10 weight 0 slant 1 overstrike false underline false] \
			Tiny [dict create family Helvetica     size 8 weight 0 slant 0 overstrike false underline false] \
			FullResult [dict create family Helvetica size 16 weight 1 slant 0 overstrike false underline false] \
			Result [dict create family Helvetica size 14 weight 0 slant 0 overstrike false underline false] \
			ClockTime [dict create family Helvetica size 16 weight 0 slant 0 overstrike false underline false] \
			ClockList [dict create family Helvetica size 24 weight 0 slant 0 overstrike false underline false] \
		]
	}
	proc _refresh_dialog_examples {st} {
		variable _profile
		foreach {w theme} {extl light extd dark} {
			$st.d.$w configure \
				-foreground [dict get $_profile styles dialogs normal_fg $theme]\
				-background [dict get $_profile styles dialogs normal_bg $theme]

			$st.d.$w configure -state normal
			$st.d.$w tag configure heading   -foreground [dict get $_profile styles dialogs heading_fg $theme]
			$st.d.$w tag configure highlight -foreground [dict get $_profile styles dialogs highlight_fg $theme]
			$st.d.$w tag configure odd       -background [dict get $_profile styles dialogs odd_bg $theme]
			$st.d.$w tag configure even      -background [dict get $_profile styles dialogs even_bg $theme]
			$st.d.$w delete 1.0 end
			$st.d.$w insert end "Example Heading\n" heading \
				            "Odd-numbered row: normal, " odd "highlighted\n" {odd highlight} \
				            "Even-numbered row: normal, " even "highlighted\n" {even highlight} \
				            "Odd-numbered row: normal, " odd "highlighted\n" {odd highlight}  \
				            "Even-numbered row: normal, " even "highlighted\n" {even highlight} 
			$st.d.$w configure -state disabled
		}
	}
	proc _reset_default_dialog_color {st btn key} {
		variable _profile
		set d [default_styles]
		dict set _profile styles dialogs $key light [set lt [dict get $d dialogs $key light]]
		dict set _profile styles dialogs $key dark [set dk [dict get $d dialogs $key dark]]
		${btn}light configure -bg $lt -text [::gmacolors::rgb_name $lt] \
			-highlightcolor $color -highlightbackground $color -highlightthickness 2 
		${btn}dark configure -bg $dk -text [::gmacolors::rgb_name $dk] \
			-highlightcolor $color -highlightbackground $color -highlightthickness 2 
		_refresh_dialog_examples $st
		_refresh_dieroller_examples $st
	}
	proc _reset_default_clock_color {st btn key} {
		variable _profile
		set d [default_styles]
		dict set _profile styles clocks $key light [set lt [dict get $d clocks $key light]]
		dict set _profile styles clocks $key dark [set dk [dict get $d clocks $key dark]]
		${btn}light configure -bg $lt -text [::gmacolors::rgb_name $lt] \
			-highlightcolor $color -highlightbackground $color -highlightthickness 2 
		${btn}dark configure -bg $dk -text [::gmacolors::rgb_name $dk] \
			-highlightcolor $color -highlightbackground $color -highlightthickness 2 
	}
	proc _set_dialog_color {st btn theme style key} {
		variable _profile
		if {[set chosencolor [tk_chooseColor -initialcolor [dict get $_profile styles dialogs $key $theme] -parent $btn -title "Choose color for $style ($theme mode)"]] ne {}} {
			dict set _profile styles dialogs $key $theme $chosencolor
			$btn configure -bg $chosencolor -text [::gmacolors::rgb_name $chosencolor] \
				-highlightcolor $chosencolor -highlightbackground $chosencolor -highlightthickness 2 
		}
		_refresh_dialog_examples $st
		_refresh_dieroller_examples $st
	}
	proc _set_clock_color {st btn theme style key} {
		variable _profile
		if {[set chosencolor [tk_chooseColor -initialcolor [dict get $_profile styles clocks $key $theme] -parent $btn -title "Choose color for $style ($theme mode)"]] ne {}} {
			dict set _profile styles clocks $key $theme $chosencolor
			$btn configure -bg $chosencolor -text [::gmacolors::rgb_name $chosencolor] \
				-highlightcolor $chosencolor -highlightbackground $chosencolor -highlightthickness 2 
		}
	}


	# name translations
	# OLD display_styles	NEW dictionary keys in _preferences
	#
	# bg_dialog		dialogs normal_bg dark|light
	# fg_dialog_heading	dialogs heading_fg dark|light
	# fg_dialog_normal	dialogs normal_fg dark|light
	# fg_dialog_highlight	dialogs highlight_fg dark|light
	# bg_list_even		dialogs even_bg dark|light
	# bg_list_odd		dialogs odd_bg dark|light
	# font_*		dierolls components * font
	# fg_*			dierolls components * fg dark|light
	# bg_*			dierolls components * bg dark|light
	# fmt_*			dierolls components * format
	# overstrike_*		dierolls components * overstrike
	# underline_*		dierolls components * underline
	# offset_*		dierolls components * offset
	#   (includes normal, system, etc) in chat channel
	# collapse_descriptions dierolls compact_recents
	#
	# Note: an empty color value means to use the prevailing dialog/window styling
	proc default_styles {} {
		return [dict create \
		  clocks [dict create \
		    hand_color  [dict create dark [default_color hand_color dark] light [default_color hand_color light]]\
		    tick_color  [dict create dark [default_color tick_color dark] light [default_color tick_color light]]\
		    flist_fg    [dict create dark [default_color flist_fg dark] light [default_color flist_fg light]]\
		    flist_bg    [dict create dark [default_color flist_bg dark] light [default_color flist_bg light]]\
		    next_fg     [dict create dark [default_color next_fg dark] light [default_color next_fg light]]\
		    next_bg     [dict create dark [default_color next_bg dark] light [default_color next_bg light]]\
		    cur_bg      [dict create dark [default_color cur_bg dark] light [default_color cur_bg light]]\
		    ready_bg    [dict create dark [default_color ready_bg dark] light [default_color ready_bg light]]\
		    hold_bg     [dict create dark [default_color hold_bg dark] light [default_color hold_bg light]]\
		    zero_hp     [dict create dark [default_color zero_hp dark] light [default_color zero_hp light]]\
		    negative_hp [dict create dark [default_color negative_hp dark] light [default_color negative_hp light]]\
		    slot_fg     [dict create dark [default_color slot_fg dark] light [default_color slot_fg light]]\
		    slot_bg     [dict create dark [default_color slot_bg dark] light [default_color slot_bg light]]\
		    flat_footed [dict create dark [default_color flat_footed dark] light [default_color flat_footed light]]\
		    timedisp_font  "ClockTime"\
		    turndisp_font  "ClockTime"\
		    default_font   "ClockList"\
		  ] \
		  dialogs [dict create \
		    heading_fg   [dict create dark cyan   light blue] \
		    normal_fg    [dict create dark [default_color fg dark] light [default_color fg light]] \
		    normal_bg    [dict create dark [default_color bg dark] light [default_color bg light]] \
		    highlight_fg [dict create dark yellow light red] \
		    odd_bg       [dict create dark [default_color bg dark] light [default_color bg light]] \
		    even_bg      [dict create dark #000090 light #bbbbff] \
		    grid         [dict create dark [default_color grid dark] light [default_color grid light]] \
		    grid_minor   [dict create dark [default_color grid_minor dark] light [default_color grid_minor light]] \
		    grid_major   [dict create dark [default_color grid_major dark] light [default_color grid_major light]] \
		    check_select [dict create dark [default_color check_select dark] light [default_color check_select light]] \
		    check_menu   [dict create dark [default_color check_menu dark] light [default_color check_menu light]] \
		    bright_fg    [dict create dark [default_color bright_fg dark]  light [default_color bright_fg light]] \
		    preset_name  [dict create dark [default_color preset_name dark]  light [default_color preset_name light]] \
		  ]\
			dierolls [dict create \
				compact_recents false \
				components [dict create \
					begingroup  [dict create fg [dict create dark {} light {}] bg [dict create dark {} light {}] font Normal format {} overstrike false underline false offset 0]\
					best      [dict create fg [dict create dark #aaaaaa light #888888] bg [dict create dark {} light {}] font Special format { best of %s} overstrike false underline false offset 0]\
					bonus     [dict create fg [dict create dark #fffb00 light #f05b00] bg [dict create dark {} light {}] font Normal format {} overstrike false underline false offset 0]\
					constant  [dict create fg [dict create dark {} light {}] bg [dict create dark {} light {}] font Normal format {} overstrike false underline false offset 0]\
					critlabel [dict create fg [dict create dark #fffb00 light #f05b00] bg [dict create dark {} light {}] font Special format {Confirm: } overstrike false underline false offset 0]\
					critspec  [dict create fg [dict create dark #fffb00 light #f05b00] bg [dict create dark {} light {}] font Special format {} overstrike false underline false offset 0]\
					dc        [dict create fg [dict create dark #aaaaaa light #888888] bg [dict create dark {} light {}] font Special format {DC %s: } overstrike false underline false offset 0]\
					diebonus  [dict create fg [dict create dark red light red] bg [dict create dark {} light {}] font Special format {(%s per die)} overstrike false underline false offset 0]\
					diespec   [dict create fg [dict create dark {} light {}] bg [dict create dark {} light {}] font Normal format {} overstrike false underline false offset 0]\
					discarded [dict create fg [dict create dark #aaaaaa light #888888] bg [dict create dark {} light {}] font Normal format {{%s}} overstrike true underline false offset 0]\
					endgroup  [dict create fg [dict create dark {} light {}] bg [dict create dark {} light {}] font Normal format {} overstrike false underline false offset 0]\
					error     [dict create fg [dict create dark red light red] bg [dict create dark {} light {}] font Normal format {ERROR: %s} overstrike false underline false offset 0]\
					exceeded  [dict create fg [dict create dark #00fa92 light green] bg [dict create dark {} light {}] font Special format { exceeded DC by %s} overstrike false underline false offset 0]\
					fail      [dict create fg [dict create dark red light red] bg [dict create dark {} light {}] font Important format {(%s) } overstrike false underline false offset 0]\
					from      [dict create fg [dict create dark cyan light blue] bg [dict create dark {} light {}] font Normal format {} overstrike false underline false offset 0]\
					fullmax   [dict create fg [dict create dark red light red] bg [dict create dark {} light {}] font Important format {maximized} overstrike false underline false offset 0]\
					fullresult [dict create fg [dict create dark blue light #ffffff] bg [dict create dark white light blue] font FullResult format {} overstrike false underline false offset 0]\
					iteration [dict create fg [dict create dark #aaaaaa light #888888] bg [dict create dark {} light {}] font Special format { (roll #%s)} overstrike false underline false offset 0]\
					label     [dict create fg [dict create dark cyan light blue] bg [dict create dark {} light {}] font Special format { %s} overstrike false underline false offset 0]\
					max       [dict create fg [dict create dark #aaaaaa light #888888] bg [dict create dark {} light {}] font Special format {max %s} overstrike false underline false offset 0]\
					maximized [dict create fg [dict create dark red light red] bg [dict create dark {} light {}] font Important format {>} overstrike false underline false offset 0]\
					maxroll   [dict create fg [dict create dark red light red] bg [dict create dark {} light {}] font Important format {{%s}} overstrike false underline false offset 0]\
					met       [dict create fg [dict create dark #00fa92 light green] bg [dict create dark {} light {}] font Special format {successful} overstrike false underline false offset 0]\
					min       [dict create fg [dict create dark #aaaaaa light #888888] bg [dict create dark {} light {}] font Special format {min %s} overstrike false underline false offset 0]\
					moddelim  [dict create fg [dict create dark #fffb00 light #f05b00] bg [dict create dark {} light {}] font Normal format { | } overstrike false underline false offset 0]\
					normal    [dict create fg [dict create dark {} light {}] bg [dict create dark {} light {}] font Normal format {} overstrike false underline false offset 0]\
					notice    [dict create fg [dict create dark yellow light red] bg [dict create dark {} light {}] font Special format {[%s] } overstrike false underline false offset 0]\
					operator  [dict create fg [dict create dark {} light {}] bg [dict create dark {} light {}] font Normal format {} overstrike false underline false offset 0]\
					repeat    [dict create fg [dict create dark #aaaaaa light #888888] bg [dict create dark {} light {}] font Special format {repeat %s} overstrike false underline false offset 0]\
					result    [dict create fg [dict create dark {} light {}] bg [dict create dark {} light {}] font Result format {} overstrike false underline false offset 0]\
					roll      [dict create fg [dict create dark #00fa92 light green] bg [dict create dark {} light {}] font Normal format {{%s}} overstrike false underline false offset 0]\
					separator [dict create fg [dict create dark {} light {}] bg [dict create dark {} light {}] font Normal format {=} overstrike false underline false offset 0]\
					sf        [dict create fg [dict create dark #aaaaaa light #888888] bg [dict create dark {} light {}] font Special format {} overstrike false underline false offset 0]\
					short     [dict create fg [dict create dark red light red] bg [dict create dark {} light {}] font Special format { missed DC by %s} overstrike false underline false offset 0]\
					subtotal  [dict create fg [dict create dark #00fa92 light green] bg [dict create dark {} light {}] font Normal format {(%s)} overstrike false underline false offset 0]\
					success   [dict create fg [dict create dark #00fa92 light green] bg [dict create dark {} light {}] font Important format {(%s) } overstrike false underline false offset 0]\
					system    [dict create fg [dict create dark cyan light blue] bg [dict create dark {} light {}] font System format {} overstrike false underline false offset 0]\
					timestamp [dict create fg [dict create dark #888888 light #888888] bg [dict create dark {} light {}] font Tiny format {} overstrike false underline false offset 0]\
					title     [dict create fg [dict create dark #aaaaaa light #ffffff] bg [dict create dark #000044 light #c7c0ae] font Normal format {} overstrike false underline false offset 0]\
					to        [dict create fg [dict create dark red light red] bg [dict create dark {} light {}] font Special format {} overstrike false underline false offset 0]\
					until     [dict create fg [dict create dark #aaaaaa light #888888] bg [dict create dark {} light {}] font Special format {until %s} overstrike false underline false offset 0]\
					worst     [dict create fg [dict create dark #aaaaaa light #888888] bg [dict create dark {} light {}] font Special format { worst of %s} overstrike false underline false offset 0]\
				]\
			]\
		]
	}
	proc default_dieroll_style {} {
		return [dict create \
			fg [dict create dark {} light {}] \
			bg [dict create dark {} light {}] \
			font [invent_font [tk_font_to_dict TkDefaultFont]]\
			format {} \
			overstrike false \
			underline false \
			offset 0]
	}
	proc _select_dieroller_style {st idx} {
		variable _description
		variable _profile
		global PEsFT
		$st.r.description configure -state normal
		$st.r.description delete 1.0 end
		if {[llength $idx] > 0} {
			set stylename [$st.r.styles get [lindex $idx 0]]
			if {[info exists _description($stylename)]} {
				$st.r.description insert end $_description($stylename)
			}

			::gmautil::dassign $_profile \
				"styles dierolls components $stylename fg light" fgcolor_l \
				"styles dierolls components $stylename fg dark" fgcolor_d \
				"styles dierolls components $stylename bg light" bgcolor_l \
				"styles dierolls components $stylename bg dark" bgcolor_d \
				"styles dierolls components $stylename font" PEsFT \
				"styles dierolls components $stylename format" fmt \
				"styles dierolls components $stylename overstrike" ov \
				"styles dierolls components $stylename underline" ul \
				"styles dierolls components $stylename offset" offamt

			global PEsFGen PEsBGen PEsOVen PEsUNen
			set neutral_bg [[winfo parent $st] cget -background]
			set PEsOVen [::gmaproto::int_bool $ov]
			set PEsUNen [::gmaproto::int_bool $ul]
			$st.r.ofamt delete 0 end
			$st.r.ofamt insert end $offamt
			if {$fgcolor_l eq {} && $fgcolor_d eq {}} {
				set PEsFGen 0
				$st.r.fglt configure -text {} -background $neutral_bg -state disabled
				$st.r.fgdk configure -text {} -background $neutral_bg -state disabled
			} else {
				set PEsFGen 1
				$st.r.fglt configure -text [::gmacolors::rgb_name $fgcolor_l] -bg $fgcolor_l -state normal\
					-highlightcolor $fgcolor_l -highlightbackground $fgcolor_l -highlightthickness 2 
				$st.r.fgdk configure -text [::gmacolors::rgb_name $fgcolor_d] -bg $fgcolor_d -state normal\
					-highlightcolor $fgcolor_d -highlightbackground $fgcolor_d -highlightthickness 2 
			}

			if {$bgcolor_l eq {} && $bgcolor_d eq {}} {
				set PEsBGen 0
				$st.r.bglt configure -text {} -background $neutral_bg -state disabled\
					-highlightcolor $neutral_bg -highlightbackground $neutral_bg -highlightthickness 2 
				$st.r.bgdk configure -text {} -background $neutral_bg -state disabled\
					-highlightcolor $neutral_bg -highlightbackground $neutral_bg -highlightthickness 2 
			} else {
				set PEsBGen 1
				$st.r.bglt configure -text [::gmacolors::rgb_name $bgcolor_l] -bg $bgcolor_l -state normal\
					-highlightcolor $bgcolor_l -highlightbackground $bgcolor_l -highlightthickness 2 
				$st.r.bgdk configure -text [::gmacolors::rgb_name $bgcolor_d] -bg $bgcolor_d -state normal\
					-highlightcolor $bgcolor_d -highlightbackground $bgcolor_d -highlightthickness 2 
			}
			$st.r.description configure -state disabled
			$st.r.fmfmt delete 0 end
			$st.r.fmfmt insert end [_spaces_to_under $fmt]
		}
		_refresh_dieroller_examples $st
	}
	proc default_color {key theme} {
		variable _default_color_table
		return $_default_color_table($key,$theme)
	}
	proc preferred_color {prefdata key theme} {
		if {$key eq {fg}} {
			set key normal_fg
		} elseif {$key eq {bg}} {
			set key normal_bg
		}
		if {![dict exists $prefdata styles dialogs $key $theme]} {
			return [default_color $key $theme]
		}
		return [dict get $prefdata styles dialogs $key $theme]
	}

	proc _enable_style {st enabled buttons} {
		variable _profile
		if {[set stylename [_selected_dieroll_style_name $st.r.styles]] eq {}} {
			return
		}
		set neutral_bg [[winfo parent $st] cget -background]
		foreach {b key theme} $buttons {
			set btn $st.r.$b
			if {$enabled} {
				if {[set def [dict get [default_styles] dierolls components $stylename $key $theme]] eq {}} {
					set def [default_color $key $theme]
				}

				dict set _profile styles dierolls components $stylename $key $theme $def
				$btn configure -state normal -background $def -text [::gmacolors::rgb_name $def]
			} else {
				dict set _profile styles dierolls components $stylename $key $theme {}
				$btn configure -background $neutral_bg -text {} -state disabled
			}
		}
		_refresh_dieroller_examples $st
	}
	proc _set_style_color {st btnw key theme} {
		variable _profile
		set btn $st.r.$btnw
		if {[set stylename [_selected_dieroll_style_name $st.r.styles]] eq {}} {
			return
		}
		if {[set chosencolor [tk_chooseColor -initialcolor [dict get $_profile styles dierolls components $stylename $key $theme] -parent $btn -title "Choose color for $stylename ($theme mode)"]] ne {}} {
			dict set _profile styles dierolls components $stylename $key $theme $chosencolor
			$btn configure -background $chosencolor -text [::gmacolors::rgb_name $chosencolor]\
				-highlightcolor $chosencolor -highlightbackground $chosencolor -highlightthickness 2 
			_refresh_dieroller_examples $st
		}
	}
	proc _set_style_overstrike {st en} {
		variable _profile

		if {[set stylename [_selected_dieroll_style_name $st.r.styles]] eq {}} {
			return
		}
		dict set _profile styles dierolls components $stylename overstrike $en
		_refresh_dieroller_examples $st
	}
	proc _set_style_underline {st en} {
		variable _profile

		if {[set stylename [_selected_dieroll_style_name $st.r.styles]] eq {}} {
			return
		}
		dict set _profile styles dierolls components $stylename underline $en
		_refresh_dieroller_examples $st
	}

	proc _update_font_menu {st m var} {
		variable _profile
		$m delete 0 end
		foreach fontname [dict keys [dict get $_profile fonts]] {
			$m add command -label $fontname -command "::gmaprofile::_set_style_font [list $st $fontname $var]"
		}
	}
	proc _update_clock_font_menu {st m desc var fld} {
		variable _profile
		$m delete 0 end
		foreach fontname [dict keys [dict get $_profile fonts]] {
			$m add command -label $fontname -command "::gmaprofile::_set_clock_font [list $st $fontname $var $fld]"
		}
	}
	proc _set_style_font {st fontname var} {
		variable _profile
		global $var
		if {[set stylename [_selected_dieroll_style_name $st.r.styles]] eq {}} {
			set $var {}
			return
		}
		dict set _profile styles dierolls components $stylename font $fontname
		set $var $fontname
		_refresh_dieroller_examples $st
	}
	proc _set_clock_font {st fontname var fld} {
		variable _profile
		global $var
		dict set _profile styles clocks $fld $fontname
		set $var $fontname
	}
	proc _under_to_spaces {s} {
		set s [string trim $s]
		if {[string index $s 0] eq {_}} {
			set s [string replace $s 0 0 { }]
		}
		if {[string index $s end] eq {_}} {
			set s [string replace $s end end { }]
		}
		return $s
	}
	proc _spaces_to_under {s} {
		if {[string index $s 0] eq { }} {
			set s [string replace $s 0 0 _]
		}
		if {[string index $s end] eq { }} {
			set s [string replace $s end end _]
		}
		return $s
	}
	proc _set_style_format {st e fmt} {
		variable _profile
		if {[set stylename [_selected_dieroll_style_name $st.r.styles]] ne {}} {
			dict set _profile styles dierolls components $stylename format [_under_to_spaces $fmt]
		}
		_refresh_dieroller_examples $st
		return 1
	}
	proc _reset_style {st} {
		variable _profile
		if {[set stylename [_selected_dieroll_style_name $st.r.styles]] ne {}} {
			dict set _profile styles dierolls components $stylename [dict get [default_styles] dierolls components $stylename]
			_select_dieroller_style $st [$st.r.styles curselection]
		}
	}
	proc _set_style_offset {st e v} {
		variable _profile

		set val $v
		if {$v eq {-spin}} {
			set val [$e get]
		}
		if {[set stylename [_selected_dieroll_style_name $st.r.styles]] ne {}} {
			if {$val eq {}} {
				dict set _profile styles dierolls components $stylename offset 0
				return 1
			}
			if {[catch {set val [expr int($val)]} err]} {
				return 0
			}
			dict set _profile styles dierolls components $stylename offset $val
			_refresh_dieroller_examples $st
		}
		if {$v eq {-spin}} {
			return 0
		} else {
			return 1
		}
	}
	proc attempt_format {fmt s} {
		if {$fmt eq {}} {
			return $s
		}
		if {[catch {set txt [format $fmt $s]}]} {
			return **ERROR**
		}
		return $txt
	}
	proc _refresh_dieroller_examples {st} {
		variable _profile
		if {[set stylename [_selected_dieroll_style_name $st.r.styles]] ne {}} {
			if {[set slfg [dict get $_profile styles dierolls components $stylename fg light]] eq {}} {
				set slfg #000000
			}
			if {[set sdfg [dict get $_profile styles dierolls components $stylename fg dark]] eq {}} {
				set sdfg #aaaaaa
			}
			if {[set slbg [dict get $_profile styles dierolls components $stylename bg light]] eq {}} {
				set slbg #cccccc
			}
			if {[set sdbg [dict get $_profile styles dierolls components $stylename bg dark]] eq {}} {
				set sdbg #232323
			}
			set xf [lookup_font $_profile [dict get $_profile styles dierolls components $stylename font]]

			set fmt [dict get $_profile styles dierolls components $stylename format]
			$st.r.ltex configure -foreground $slfg -background $slbg -font $xf -text "Sample (light mode): [attempt_format $fmt value]"
			$st.r.dkex configure -foreground $sdfg -background $sdbg -font $xf -text "Sample (dark mode): [attempt_format $fmt value]"
		}
		foreach {ww th} {l light d dark} {
			set drd_id 0
			$st.r.ex$ww configure -foreground [dict get $_profile styles dialogs normal_fg $th]\
				              -background [dict get $_profile styles dialogs normal_bg $th]
			foreach tag [dict keys [dict get $_profile styles dierolls components]] {
				set options {}
				$st.r.ex$ww tag delete $tag

				foreach {k o t} {
					fg         -foreground c
					bg         -background c
					overstrike -overstrike ?
					underline  -underline  ?
					offset     -offset     i
					font       -font       f
				} {
					set v [dict get $_profile styles dierolls components $tag $k]
					switch -exact $t {
						c {
							if {$v eq {}} continue
							set v [dict get $v $th]
							if {$v eq {}} continue
						}
						f { set v [lookup_font $_profile $v] }
						? { if {$v eq {} || !$v} continue }
						i { if {$v == 0} continue }
					}
					lappend options $o $v
				}
				if {$stylename eq $tag} {
					lappend options -underline 1
				}
				$st.r.ex$ww tag configure $tag {*}$options
			}
			$st.r.ex$ww configure -state normal
			$st.r.ex$ww delete 1.0 end
			foreach {tag text} {
				timestamp {12:34 }
				system {System message}
				- -
				timestamp {12:34 }
				from   {Steve: }
				normal {Hello, this is a chat message.}
				- -
				timestamp {12:34 }
				from   Steve
				to     { (to Alice, Bob)}
				from   {: }
				normal {This is a private chat message.}
				- -
				timestamp {12:34 }
				fullresult 23
				{}         { }
				from       {Bob: }
				title      Magic
				critlabel   Confirm:
				result      23
				success     HIT
				separator   =
				begingroup  (
				diespec     1d20
				roll        20
				operator    +
				constant    3
				label       luck
				endgroup    )
				bonus       +2
				moddelim    |
				min         5
				moddelim    |
				max         50
				moddelim    |
				critspec    c
				- -
				timestamp {12:34 }
				fullresult 27
				{}         { }
				from       {Bob: }
				result      27
				separator   =
				maximized   >
				diespec     5d6
				subtotal    16
				roll        6,3,5,1,1
				operator    +
				diespec     3d8
				subtotal    11
				best        2
				roll        3,3,5
				discarded   1,5,3
				- -
				timestamp {12:34 }
				fullresult  0
				{}          { }
				from   {Alice: }
				fail        fail
				separator   =
				diespec     52%
				maxroll     100
				moddelim    |
				fullmax     maximized
				- -
				timestamp {12:34 }
				fullresult  1 {} { }
				from   {Alice: }
				success     miss
				separator   =
				diespec     52%
				label       miss
				roll        37
				- -
				timestamp {12:34 }
				fullresult 14 {} { }
				from   {Alice: }
				result     14
				separator  =
				diespec    2d10
				subtotal   14
				roll       8,6
				moddelim   |
				until      18
				iteration  1
				short      4
				- -
				timestamp {12:34 }
				fullresult 7 {} { }
				from   {Alice: }
				result     7
				separator  =
				diespec    2d6
				subtotal   7
				worst      3
				roll       6,1
				discarded  4,5
				discarded  4,6
				moddelim   |
				repeat     3
				iteration  1
				moddelim   |
				dc         5
				exceeded   2
				- -
				timestamp {12:34 }
				fullresult 21 {} { }
				from   {Alice: }
				result     21
				separator  =
				diespec    1d20
				diebonus   +1
				roll       18
				operator   +
				constant   3
				moddelim   |
				dc         21
				met        successful
				- -
				timestamp {12:34 }
				from   {Alice: }
				notice     {roll to GM}
				diespec    6d6
				- -
				timestamp {12:34 }
				fullresult 4 {} { }
				from   {Alice: }
				result     4
				success    triumph
				separator  =
				diespec    1d4
				roll       4
				moddelim   |
				sf         {sf defeat/triumph}
				- -
				timestamp {12:34 }
				error      {Error message from server!}
			} {
				if {$tag eq {-}} {
					$st.r.ex$ww insert end "\n"
					continue
				}
				if {$tag eq {title}} {
					set tfg [dict get $_profile styles dierolls components title fg $th]
					if {$tfg eq {}} {
						set tfg [dict get $_profile styles dialogs normal_fg $th]
					}
					set wt $st.r.ex$ww.[incr drd_id]
					label $wt -padx 2 -pady 2 -relief groove \
						-foreground $tfg -background [::tk::Darken $tfg 40]\
						-font [::gmaprofile::lookup_font $_profile [dict get $_profile styles dierolls components title font]] \
						-borderwidth 2 -text $text
					$st.r.ex$ww window create end -align bottom -window $wt -padx 2
					continue
				}
				if {$tag ne {}} {
					if {[set fmt [dict get $_profile styles dierolls components $tag format]] ne {}} {
						set text [attempt_format $fmt $text]
					}
				}
				$st.r.ex$ww insert end $text $tag
			}
			$st.r.ex$ww configure -state disabled
		}
	}

	proc _set_style_compact {st en} {
		variable _profile
		dict set _profile styles dierolls compact_recents $en
	}

	#
	# Die Rolls_________________________
	# |style1|^|  <Description>
	# |style2| |  []Text color:        [] []       Sample
	# |style3| |  []Background color:  [] []
	# |style4| |  []Font:              [menu]
	# |style5| |  []Display Format:    [_________] (Use _ for leading/trailing spaces; blank for default format)
	# |style6| |  []Overstrike
	# |style7| |  []Underline
	# |style7| |  []Raise (Lower) text by: [___^] from baseline
	# |style7| |
	# |style7| |  [Restore Default Settings]
	# |______|v|
	#
	# [] use more compact layout for recent die rolls
	#
	# Die-roll title: ...
	#
	proc dlkeyint {is_dark} {
		if {$is_dark} {
			return dark
		} else {
			return light
		}
	}
	proc dlkeypref {prefs} {
		return [dlkeyint [dict get $prefs dark]]
	}

	proc invent_font {fontdict} {
		variable _profile
		variable _fontid
		dict set _profile fonts gmafont[incr _fontid] [define_font $fontdict]
		return gmafont$_fontid
	}
	proc _toggle_password_visibility {s} {
		if {[$s.pass cget -show] eq {}} {
			$s.pass configure -show *
			$s.passvis configure -text show
		} else {
			$s.pass configure -show {}
			$s.passvis configure -text hide
		}
	}
}

