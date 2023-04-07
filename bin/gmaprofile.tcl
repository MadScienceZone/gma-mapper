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

package provide gmaprofile 0.0
#package require gmautil
#package require Tcl 8.6
#package require sha256

namespace eval ::gmaprofile {
	namespace export editor
	variable _profile {}
	variable _profile_backup {}

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
		global animate button_size bsizetext dark guides image_format keep_tools preload
		global imgtext debug_level debug_proto curl_path
		variable _profile
		set _profile [dict create \
			animate $animate \
			button_size $button_size \
			curl_path $curl_path \
			dark $dark \
			debug_level $debug_level \
			debug_proto $debug_proto \
			guide_lines $guides \
			image_format $image_format \
			keep_tools $keep_tools \
			preload $preload \
		]
	}
	proc _select_server {w servername} {
	}
	proc editor {w d} {
		global animate button_size bsizetext dark guides image_format keep_tools preload
		global imgtext debug_proto debug_level curl_path
		variable _profile
		variable _profile_backup
		set ::gmaprofile::_profile $d
		set ::gmaprofile::_profile_backup $d
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
			preload preload

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

		grid [ttk::checkbutton $w.n.a.animate -text "Animate updates" -variable animate] -sticky w
		grid [ttk::checkbutton $w.n.a.dark -text "Dark theme" -variable dark] -sticky w
		grid [ttk::checkbutton $w.n.a.keep -text "Keep toolbar visible" -variable keep_tools] -sticky w
		grid [ttk::checkbutton $w.n.a.preload -text "Pre-load all cached images" -variable preload] -sticky w
		grid [ttk::menubutton $w.n.a.imgfmt -textvariable imgtext -menu $w.n.a.m_imgfmt] -sticky w
		grid [ttk::menubutton $w.n.a.bsize -textvariable bsizetext -menu $w.n.a.m_bsize] -sticky w

		grid [ttk::label $w.n.t.curl_label -text "Curl program path:"] \
		     [ttk::entry $w.n.t.curl -textvariable curl_path] -sticky w

		grid [ttk::label $w.n.d.level_label -text "Debugging level:"] \
		     [ttk::spinbox $w.n.d.level -values {0 1 2 3 4 5 6} -textvariable debug_level -width 2] -sticky w
		grid [ttk::checkbutton $w.n.d.proto -text "Debug client/server protocol messages" -variable debug_proto] - -sticky w

		grid [listbox $w.n.p.servers -yscrollcommand "$w.n.p.scroll set" -selectmode browse] \
		     [scrollbar $w.n.p.scroll -orient vertical -command "$w.n.p.servers yview"] -sticky nsw 
	        grid [button $w.n.p.add -text {Add New...}] -sticky nw -column 2 -row 0
		
		grid ^ ^ [button $w.n.p.copy -text Copy -state disabled] -sticky nw
		grid ^ ^ [button $w.n.p.del -text Delete -state disabled -foreground red] -sticky sw
		
		bind $w.n.p.servers <<ListboxSelect>> "_select_server $w %W"
		foreach profile [dict keys [dict get $_profile profiles]] {
			$w.n.p.servers insert end $profile
		}

		pack $w.n
		pack [button $w.can -text Cancel -command "::gmaprofile::_cancel; destroy $w"]
		pack [button $w.ok -text Save -command "::gmaprofile::_save; destroy $w"]

		tkwait window $w
		return $::gmaprofile::_profile
	}
}
