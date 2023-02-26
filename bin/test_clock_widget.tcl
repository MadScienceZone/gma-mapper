source gmaclock.tcl
source gmautil.tcl

pack [::gmaclock::widget .c -- -width 200 -height 200]
update
::gmaclock::draw_face .c
::gmaclock::set_time_value .c 1423842384
::gmaclock::_update_clock .c

proc advance {} {
	global adv
	if {[incr adv] > 100} {
		::gmaclock::_stop_clock .c 1 sc
		return
	}
	::gmaclock::advance_clock .c 1
	::gmaclock::_update_clock .c
	after 100 advance
}
proc sc {} {
	global adv
	set adv 0
	::gmaclock::_start_combat .c 0 c_advance
}

proc c_advance {} {
	global adv
	if {[incr adv] > 100} {
		::gmaclock::_stop_combat .c 1 sk
		return
	}
	::gmaclock::advance_clock .c 1
	::gmaclock::advance_delta .c 1
	::gmaclock::_update_combat .c
	after 100 c_advance
}

proc sk {} {
	global adv
	set adv 0
	::gmaclock::_start_clock .c 0 advance
}

sk

