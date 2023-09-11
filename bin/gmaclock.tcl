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
# Mapper initiative clock display
# Steve Willoughby <steve@madscience.zone>
#

package provide gmaclock 1.0
package require Tcl 8.5

namespace eval ::gmaclock {
	variable _clock_state
	variable PI 3.14159265358979323

# destroy_clock w
proc destroy_clock {w} {
	variable _clock_state

if {[info exists _clock_state($w)]} {
		catch { $w destroy }
		array unset _clock_state $w
	}
}

# widget w ?-24hr? ?-dark? ?-handscale x? ?-calendar name? ?-- canvasopts ...? -> id
proc widget {w args} {
	variable _clock_state
	global ::_preferences

	if {[info exists _clock_state($w)]} {
		error "a gmaclock widget already exists with path $w"
	}

	set _clock_state($w) [dict create \
		calendar [_new_cal] \
		combat_mode false\
		delta_time 0\
		half_hours true \
		hand_scale 2 \
		realtime_tick_task {} \
	]

	set opts {}

	for {set i 0} {$i < [llength $args]} {incr i} {
		switch -exact -- [lindex $args $i] {
			-24hr	{dict set _clock_state($w) half_hours false}
			-dark	{
				#deprecated
			}
			-handscale {
				incr i
				if {$i >= [llength $args]} {
					error "-handscale requires an argument"
				}
				dict set _clock_state($w) hand_scale [lindex $args $i]
			}
			-calendar {
incr i
				if {$i >= [llength $args]} {
					error "-calendar requires an argument"
				}
				if {[lindex $args $i] ne {golarion}} {
					error "only the golarion calendar is currently supported."
				}
			}
			-- {
				set opts [lrange $args $i+1 end]
				break
			}
			default {
				error "unknown option [lindex $args $i]"
			}
		}
	}

	if {[dict get $_clock_state($w) half_hours]} {
		dict set _clock_state($w) hm 12
	} else {
		dict set _clock_state($w) hm 24
	}

	canvas $w {*}$opts
#	bind $w <Configure> "::gmaclock::_window_change $w"
#	_draw_face $w
return $w
}

proc draw_face {w} {
	_draw_face $w.timeclock
}

#proc _window_change {w} {
#	_draw_face $w
#}

# _start_clock w ?scale=0? ?callback?
proc _start_clock {w {scale 0} {callback {}}} {
	variable _clock_state
	_cancel_realtime_tick $w

	$w delete ticks
	set hm [dict get $_clock_state($w) hm]
	for {set p 0} {$p < $hm} {incr p} {
		_draw_hand $w $p $hm 0.95 1 [expr 0.95-(0.1*$scale)] 2 {face ticks}
	}
	if {$scale < 1} {
		_update_clock $w $scale
		after 10 [list ::gmaclock::_start_clock $w [expr $scale+0.01] $callback]
	} else {
		_update_clock $w
		if {$callback ne {}} {
			{*}$callback
		}
	}
}

proc _start_combat {w {scale 0} {callback {}}} {
	variable _clock_state
	_cancel_realtime_tick $w

	dict set _clock_state($w) combat_mode true
	set fill [dict get $::_preferences styles clocks tick_color [::gmaprofile::dlkeypref $::_preferences]]
	$w delete ticks
	for {set p 0} {$p < 10} {incr p} {
		_draw_hand $w $p 10 0.95 1 [expr 0.95-(0.95*$scale)] 2 {face ticks} $fill
	}

	if {$scale < 1} {
		_update_combat $w $scale
		after 10 [list ::gmaclock::_start_combat $w [expr $scale+0.01] $callback]
	} else {
		_update_combat $w
		if {$callback ne {}} {
			{*}$callback
		}
	}
}

proc _stop_combat {w {scale 1} {callback {}}} {
	variable _clock_state
	_cancel_realtime_tick $w

	set fill [dict get $::_preferences styles clocks tick_color [::gmaprofile::dlkeypref $::_preferences]]
	$w delete ticks
	for {set p 0} {$p < 10} {incr p} {
		_draw_hand $w $p 10 0.95 1 [expr 0.95-(0.95*$scale)] 2 {face ticks} $fill
	}

	if {$scale > 0} {
		_update_combat $w $scale
		after 10 [list ::gmaclock::_stop_combat $w [expr $scale-0.01] $callback]
	} else {
		_update_combat $w
		if {$callback ne {}} {
			{*}$callback
		}
	}
	dict set _clock_state($w) combat_mode false
}

# _stop_clock w ?scale=1? ?callback?
proc _stop_clock {w {scale 1} {callback {}}} {
	variable _clock_state
	_cancel_realtime_tick $w

	$w delete ticks
	set hm [dict get $_clock_state($w) hm]
	dict set _clock_state($w) combat_mode false
	for {set p 0} {$p < $hm} {incr p} {
		_draw_hand $w $p $hm 0.95 1 [expr 0.95-(0.1*$scale)] 2 {face ticks}
	}
	if {$scale > 0} {
		_update_clock $w $scale
		after 10 [list ::gmaclock::_stop_clock $w [expr $scale-0.01] $callback]
	} else {
		_update_clock $w 0
		if {$callback ne {}} {
			{*}$callback
		}
	}
}

# _draw_hand w pos total length time_scale start width taglist ?fill={}? ?offset={2 2}? ?lineopts ...?
proc _draw_hand {w position total length time_scale start width taglist {fill {}} {offset {2 2}} args} {
	variable _clock_state
	variable PI

	if {$fill eq {}} {
		set fill [dict get $::_preferences styles clocks hand_color [::gmaprofile::dlkeypref $::_preferences]]
	}

	set radius [expr [winfo width $w] / 2.0]
	set theta [expr -2.0 * $PI * (fmod($position, $total) / $total) * $time_scale + ($PI / 2.0)]
	set x0 [expr $start * $radius * cos($theta)]
	set y0 [expr $start * $radius * sin($theta)]
	set x1 [expr $length * $radius * cos($theta)]
	set y1 [expr $length * $radius * sin($theta)]
	$w create line [expr $x0+$radius+[lindex $offset 0]] [expr -$y0+$radius+[lindex $offset 1]] \
		       [expr $x1+$radius+[lindex $offset 0]] [expr -$y1+$radius+[lindex $offset 1]] \
		       -fill $fill -width $width -tags $taglist {*}$args
}
# _draw_face w
proc _draw_face {w} {
	variable _clock_state
	set wd [expr double([winfo width $w])]
	set h [expr double([winfo height $w])]
	$w delete face
	set color [dict get $::_preferences styles clocks hand_color [::gmaprofile::dlkeypref $::_preferences]]
	$w create oval 5 5 [expr $wd-4] [expr $h-4] -width 4 -tags face -outline $color
}

# _update_clock w ?scale=1? ?-complete? ?-running?
proc _update_clock {w {time_scale 1} args} {
	variable _clock_state
	variable minute_mod
	variable second_mod

	_cancel_realtime_tick $w
	set complete false
	set running false

	for {set i 0} {$i < [llength $args]} {incr i} {
		switch -exact -- [lindex $args $i] {
			-complete { set complete true}
			-running  { set running true}
			default {
				error "unknown option [lindex $args $i]"
			}
		}
	}

	if {$complete} {
		_draw_face $w
	}
	$w delete hands
	::gmautil::dassign $_clock_state($w) hm hm calendar cal hand_scale hand_scale
	::gmautil::dassign $cal fhour fhour fminute fminute fsecond fsecond
	_draw_hand $w $fhour $hm 0.5 $time_scale 0 [expr 3*$hand_scale] hands {} {2 2} -arrow last
	_draw_hand $w $fminute $minute_mod 0.7 $time_scale 0 [expr 2*$hand_scale] hands {} {2 2} -arrow last
	_draw_hand $w $fsecond $second_mod 0.9 $time_scale 0 $hand_scale hands
	if {$running} {
		dict set _clock_state($w) realtime_tick_task [after 100 [list ::gmaclock::_realtime_tick $w]]
		_refresh_clock_display $w
	} 
}

proc _realtime_tick {w} {
	variable _clock_state
	if {[dict get $_clock_state($w) realtime_tick_task] ne {}} {
		advance_time $w 1
		_update_clock $w 1 -running
	}
}

proc _cancel_realtime_tick {w} {
	variable _clock_state
	if {[set id [dict get $_clock_state($w) realtime_tick_task]] ne {}} {
		after cancel $id
	}
	dict set _clock_state($w) realtime_tick_task {}
}

proc _draw_sweep {w position total length {time_scale 1} args} {
	variable _clock_state

	set wd [expr double([winfo width $w])]
	set h [expr double([winfo height $w])]
	set radius [expr $wd / 2.0]
	set d [expr $radius - $length * $radius]
	set ex [expr (fmod($position, $total) / $total) * $time_scale]
	if {360*$ex > 1} {
		$w create arc [expr 5+$d] [expr 5+$d] [expr $wd-1-$d] [expr $h-1-$d] -style pieslice -start 90 -extent [expr -360*$ex] {*}$args
	}
}

proc _update_combat {w {time_scale 1} {new_delta_time {}}} {
	variable _clock_state
	variable round_units
	variable minute_units

	dict set _clock_state($w) combat_mode false
	if {$new_delta_time ne {}} {
		dict set _clock_state($w) delta_time $new_delta_time
	}

	set wd [expr double([winfo width $w])]
	set ht [expr double([winfo height $w])]
	set dt [expr double([dict get $_clock_state($w) delta_time])]
	set cx [expr $wd / 2.0]
	set cy [expr $ht / 2.0]
	set hand_scale [dict get $_clock_state($w) hand_scale]

	$w delete hands
	_draw_sweep $w $dt $round_units 0.9 $time_scale -fill red -tags hands
	_draw_sweep $w [expr $dt / $round_units] 10 0.7 $time_scale -fill green -tags hands
	_draw_sweep $w [expr $dt / $minute_units] 10 0.5 $time_scale -fill blue -tags hands
	_draw_hand $w $dt $round_units 0.9 $time_scale 0 $hand_scale hands
	_draw_hand $w [expr $dt / $round_units] 10 0.7 $time_scale 0 [expr 2*$hand_scale] hands {} {2 2} -arrow last
	_draw_hand $w [expr $dt / $minute_units] 10 0.5 $time_scale 0 [expr 3*$hand_scale] hands {} {2 2} -arrow last
}

#
# minimal implementation of the GMA calendar for Golarion
# 
proc _new_cal {} {
	return [dict create \
		now	0\
		tick	0\
		second	0\
		minute	0\
		hour	0\
		dow	0\
		date	1\
		month	1\
		year	0\
		pom	0\
		season	0\
		fminute 0.0\
		fsecond 0.0\
		fhour	0.0\
	]
}

variable second_units 10
variable round_units  [expr $second_units * 6]
variable minute_units [expr $second_units * 60]
variable hour_units   [expr $minute_units * 60]
variable day_units    [expr $hour_units * 24]
variable week_units   [expr $day_units * 7]
variable pom_units    7
variable season_units [expr 91 * $day_units]
variable tick_mod     10
variable second_mod   60
variable minute_mod   60
variable hour_mod     24
variable dow_mod      7
variable pom_mod      4
variable season_mod   4
variable moon_phase_names {NM 1Q FM 3Q}
variable epoch_year   0
variable epoch_dow    2
variable epoch_pom    0
variable epoch_season 0
variable month_info {
	{Abadius   ABA {31 31}}
	{Calistril CAL {28 29}}
	{Pharast   PHA {31 31}}
	{Gozran    GOZ {30 30}}
	{Desnus    DES {31 31}}
	{Sarenith  SAR {30 30}}
	{Erastus   ERA {31 31}}
	{Arodus    ARO {31 31}}
	{Rova      ROV {30 30}}
	{Lamashan  LAM {31 31}}
	{Neth  NET {30 30}}
	{Kuthona   KUT {31 31}}
}
variable season_names {Winter Spring Summer Fall}
variable day_names {Moonday Toilday Wealday Oathday Fireday Starday Sunday}


proc set_time_value {w current_time} {
	variable _clock_state
	dict set _clock_state($w) calendar now $current_time
	_recalc $w
}

#proc is_leap_year {cal} {
#	upvar $cal d
#	return [expr ([dict get $d calendar year] % 8) == 0]
#}

proc _j {y m d} {
	set m [expr ($m + 9) % 12]
	set y [expr $y - $m / 10]
	return [expr 365*$y + $y/8 + (306*$m + 5)/10 + ($d-1)]
}

proc _ymd {j} {
	set y [expr (10000*$j + 14780) / 3651250]
	set d [expr $j - (365*$y + $y/8)]
	if {$d < 0} {
		set y [expr $y - 1]
		set d [expr $j - (365*$y + $y/8)]
	}
	set m [expr (100*$d + 52) / 3060]
	return [list [expr $y + ($m + 2)/12] [expr ($m+2)%12 + 1] [expr $d-(306*$m+5)/10 + 1]]
}

proc _recalc {w} {
	variable _clock_state
	variable tick_mod
	variable second_units
	variable second_mod
	variable minute_units
	variable minute_mod
	variable hour_units
	variable hour_mod
	variable epoch_dow
	variable dow_mod
	variable epoch_pom
	variable pom_units
	variable pom_mod
	variable epoch_season
	variable season_units
	variable season_mod
	variable day_units

	set j [expr [dict get $_clock_state($w) calendar now] / $day_units]
	set t [expr [dict get $_clock_state($w) calendar now] % $day_units]
	lassign [_ymd $j] year month date
	set season [lindex {0 0 0 1 1 1 2 2 2 3 3 3} [expr $month-1]]
	if {[lsearch {3 6 9 12} $month] >= 0 && $date >= 21} {
		set season [expr ($season + 1) % 4]
	}
	dict set _clock_state($w) calendar year $year
	dict set _clock_state($w) calendar month  $month
	dict set _clock_state($w) calendar date   $date
	dict set _clock_state($w) calendar tick   [expr $t % $tick_mod]
	dict set _clock_state($w) calendar second [expr ($t / $second_units) % $second_mod]
	dict set _clock_state($w) calendar minute [expr ($t / $minute_units) % $minute_mod]
	dict set _clock_state($w) calendar hour   [expr ($t / $hour_units) % $hour_mod]
	dict set _clock_state($w) calendar dow    [expr ($j + $epoch_dow) % $dow_mod]
	dict set _clock_state($w) calendar pom    [expr (($j + $epoch_pom) / $pom_units) % $pom_mod]
	dict set _clock_state($w) calendar season [expr (($j + $epoch_season) / $season_units) % $season_mod]
	dict set _clock_state($w) calendar fsecond [expr fmod(double($t) / $second_units, $second_mod)]
	dict set _clock_state($w) calendar fminute [expr fmod(double($t) / $minute_units, $minute_mod)]
	dict set _clock_state($w) calendar fhour   [expr fmod(double($t) / $hour_units, $hour_mod)]
	dict set _clock_state($w) calendar season $season
}

proc advance_clock {w delta} {
	variable _clock_state
	return [advance_time $w $delta]
}

proc advance_delta {w delta} {
	variable _clock_state
	dict set _clock_state($w) delta_time [expr [dict get $_clock_state($w) delta_time] + $delta]
}
	
proc advance_time {w delta {unit_name {}}} {
	variable _clock_state
	set previous [dict get $_clock_state($w) calendar now]
	if {$unit_name eq {}} {
		dict set _clock_state($w) calendar now [expr $previous+$delta]
	} else {
		error "advance_time with units not yet implemented"
	}
	_recalc $w
	return [expr [dict get $_clock_state($w) calendar now] - $previous]
}



#
# Initiative tracker
#
# from InitiativeDisplayWindow, InitiativeSlot of GMA's MadScienceZone.GMA.GUI.ClockForm
#
# initiative_display_window w ?limit=20? ?dark_mode=false? ?frameopts ...? -> w
#                                        ^^^^^^^^^^^^^^^^^ dark_mode argument deprecated
variable _window_state
proc dest {w} {
	variable _window_state
	destroy_clock $w.timeclock

	if {[info exists _window_state($w)]} {
		catch { $w destroy }
		array unset _window_state $w
	}
}

proc initiative_display_window {w {limit 20} {dark_mode false} args} {
	variable _window_state
	#
	# window paths (under $w)
	#  timeclock	clock widget
	#  timedisp	label
	#  turndisp	label
	#  turntick	label
	#  slotN	label for slot #N (as listed in dlist)
	#
	# state values of note
	#  flist	dict of ".sep"|slot#:field-window-path	list of tk fields we're updating
	#  ilist	dict of slot#:(dict of attr:value (name,hold,ready,health_tracker))
	#  			health_tracker: dict of attr:value (value,is_flat_footed)
	#  dlist	list of slot#s we're displaying
	#

	set _window_state($w) [dict create \
		_autosize_last_height	{} \
		_autosize_inhibit 	false \
		_autosize_task		{} \
		combat_mode		false \
		flist			{} \
		ilist			{} \
		limit			$limit \
	]

	frame $w {*}$args
	widget $w.timeclock -- -width 200 -height 200
	pack $w.timeclock -side top
	pack [label $w.timedisp -anchor n -font [::gmaprofile::lookup_font $::_preferences [dict get $::_preferences styles clocks timedisp_font]]] -side top -fill x
	pack [label $w.turndisp -anchor n -font [::gmaprofile::lookup_font $::_preferences [dict get $::_preferences styles clocks turndisp_font]]] -side top -fill x
	#pack [label $w.turntick -anchor n -font $font_name] -side top -fill x
	_start_clock $w.timeclock
	bind $w <Configure> "::gmaclock::autosize $w"
	return $w
}

# prevent too many calls to _autosize at once
proc autosize {w} {
	variable _window_state

	if {[dict get $_window_state($w) _autosize_inhibit]} {
		return
	}

	if {[set taskID [dict get $_window_state($w) _autosize_task]] ne {}} {
		after cancel $taskID
	}
	dict set _window_state($w) _autosize_task [after 500 "::gmaclock::_autosize $w"]
}

proc _autosize {w} {
	variable _window_state

	set cur_height [winfo height $w]
	if {[dict get $_window_state($w) _autosize_last_height] ne {} \
	&&  [dict get $_window_state($w) _autosize_last_height] == $cur_height} {
		return
	}

	dict set _window_state($w) _autosize_last_height $cur_height
	dict set _window_state($w) _autosize_inhibit true

	set height [expr $cur_height - [winfo height $w.timeclock] - [winfo height $w.timedisp] - [winfo height $w.turndisp]]

	if {[set flist [dict get $_window_state($w) flist]] ne {}} {
		dict for {k fld} $flist {
			pack forget $fld
			destroy $fld
		}
		dict set _window_state($w) flist {}
	}
	pack [label $w.test -background #000000 -font [::gmaprofile::lookup_font $::_preferences [dict get $::_preferences styles clocks default_font]]\
		-foreground #ffffff -text {<---[XXX]--->} -anchor center -relief solid -highlightbackground #ff0000 \
		-highlightthickness 0] -side top -padx 2 -pady 1 -fill x
	update
	set f_height [winfo height $w.test]
	dict set _window_state($w) limit [expr int($height / $f_height)]
	pack forget $w.test
	destroy $w.test
	
	update_initiative_slots $w {} -force
	update
	dict set _window_state($w) _autosize_task {}
	dict set _window_state($w) _autosize_inhibit false
}

# update_initiative_slots w ?limit={}? ?-force?
proc update_initiative_slots {w {limit {}} args} {
	variable _window_state
	variable _clock_state

	set force_redraw false
	set dlkey [::gmaprofile::dlkeypref $::_preferences]
	::gmautil::dassign $::_preferences \
		"styles clocks flist_fg $dlkey" flist_fg \
		"styles clocks flist_bg $dlkey" flist_bg \
		"styles clocks next_fg $dlkey" next_fg \
		"styles clocks next_bg $dlkey" next_bg \
		"styles clocks cur_bg $dlkey" cur_bg \
		"styles clocks ready_bg $dlkey" ready_bg \
		"styles clocks hold_bg $dlkey" hold_bg

	set name_font_x_width [font measure [::gmaprofile::lookup_font $::_preferences [dict get $::_preferences styles clocks default_font]] x]
	if {$name_font_x_width < 8} {
		set icon_readied_action $::icon_hourglass_go_16
		set icon_held_action $::icon_hourglass_16
		set icon_dieing $::icon_cross_16
		set icon_active $::icon_bullet_go_16
		set icon_blank $::icon_blank_16
	} elseif {$name_font_x_width < 20} {
		set icon_readied_action $::icon_hourglass_go_30
		set icon_held_action $::icon_hourglass_30
		set icon_dieing $::icon_cross_30
		set icon_active $::icon_bullet_go_30
		set icon_blank $::icon_blank_30
	} else {
		set icon_readied_action $::icon_hourglass_go_40
		set icon_held_action $::icon_hourglass_40
		set icon_dieing $::icon_cross_40
		set icon_active $::icon_bullet_go_40
		set icon_blank $::icon_blank_40
	}


	if {[lsearch -exact $args -force] >= 0} {
		set force_redraw true
	}
	if {$limit eq {}} {
		set limit [dict get $_window_state($w) limit]
	}
	dict for {k f} [dict get $_window_state($w) flist] {
		$f configure -background $flist_bg 
		catch {
			$f.name configure -background $flist_bg -foreground $flist_fg
			$f.icon configure -background $flist_bg -foreground $flist_fg -image $icon_blank
		}
	}
	if {[dict get $_window_state($w) combat_mode]} {
		dict for {k fld} [dict get $_window_state($w) flist] {
			if {![dict exists $_window_state($w) ilist $k]} {
				DEBUG 1 "slot $k disappeared from initiative list; forcing redraw"
				set force_redraw true
				break
			}
		}
		dict for {k fld} [dict get $_window_state($w) ilist] {
			if {![dict exists $_window_state($w) flist $k]} {
				DEBUG 1 "slot $k introduced to initiative list; forcing redraw"
				set force_redraw true
				break
			}
		}
		set slot [current_initiative_slot $w]
		if {$force_redraw && [set flist [dict get $_window_state($w) flist]] ne {}} {
			dict for {k fld} $flist {
				pack forget $fld
				destroy $fld
			}
			dict set _window_state($w) flist {}
		}
		# dlist is the display list: all the slot numbers in order in which we display someone
		set first_slot -1
		set dlist [lsort -integer [dict keys [dict get $_window_state($w) ilist]]] 

		if {[set cur [lsearch $dlist $slot]] >= 0} {
			if {[set flist [dict get $_window_state($w) flist]] ne {}} {
				dict for {k fld} $flist {
					pack forget $fld
					destroy $fld
				}
				dict set _window_state($w) flist {}
			}
			if {[llength $dlist] > $limit} {
				set first_slot [lindex $dlist 0]
				if {$cur < $limit/2} {
					if {[dict get $_clock_state($w.timeclock) delta_time] >= 60} {
						incr cur [llength $dlist]
						lappend dlist {*}$dlist
						set dlist [lrange $dlist [expr $cur-int($limit/2)] end]
					}
					set dlist [lrange $dlist 0 [expr $limit-1]]
				} else {
					lappend dlist {*}$dlist
					set dlist [lrange $dlist [expr $cur-int($limit/2)] end]
					set dlist [lrange $dlist 0 [expr $limit-1]]
				}
			}

			foreach i $dlist {
				if {$first_slot >= 0 && $i == $first_slot} {
					dict set _window_state($w) flist .sep [label $w.sep -background $next_bg \
						-foreground $next_fg -text "NEXT ROUND" -relief solid]
					pack $w.sep -side top -padx 2 -pady 1 -fill x
				}
				dict set _window_state($w) flist $i [frame $w.slot$i -background $flist_bg \
					-relief solid]

				pack [label $w.slot$i.icon -background $flist_bg -image $icon_blank] -side left
				pack [label $w.slot$i.name -background $flist_bg -foreground $flist_fg \
					-font [::gmaprofile::lookup_font $::_preferences [dict get $::_preferences styles clocks default_font]] \
					-text [dict get $_window_state($w) ilist $i name] -anchor center -relief solid -bd 0] \
						-side top -fill x
				pack $w.slot$i -side top -padx 2 -pady 1 -expand 0 -fill x -ipadx 0 -ipady 0
				if {$i == $slot} {
					$w.slot$i configure -background $cur_bg
					$w.slot$i.icon configure -background $cur_bg -image $icon_active
					$w.slot$i.name configure -background $cur_bg
				} elseif {[dict get $_window_state($w) ilist $i hold]} {
					if {[dict get $_window_state($w) ilist $i ready]} {
						$w.slot$i configure -background $ready_bg
						$w.slot$i.name configure -background $ready_bg
						$w.slot$i.icon configure -background $ready_bg -image $icon_readied_action
					} else {
						$w.slot$i configure -background $hold_bg
						$w.slot$i.name configure -background $hold_bg
						$w.slot$i.icon configure -background $hold_bg -image $icon_held_action
					}
				}

				if {[dict get $_window_state($w) ilist $i health_tracker] ne {}} {
					if {[dict get $_window_state($w) ilist $i health_tracker value] == 0} {
						$w.slot$i configure \
							-highlightbackground [dict get $::_preferences styles clocks zero_hp [::gmaprofile::dlkeypref $::_preferences]] \
							-highlightcolor [dict get $::_preferences styles clocks zero_hp [::gmaprofile::dlkeypref $::_preferences]] \
							-highlightthickness 4
					} elseif {[dict get $_window_state($w) ilist $i health_tracker value] < 0} {
						$w.slot$i configure \
							-highlightbackground [dict get $::_preferences styles clocks negative_hp [::gmaprofile::dlkeypref $::_preferences]] \
							-highlightcolor [dict get $::_preferences styles clocks negative_hp [::gmaprofile::dlkeypref $::_preferences]] \
							-highlightthickness 4 \
							-background [dict get $::_preferences styles clocks slot_bg [::gmaprofile::dlkeypref $::_preferences]]
						$w.slot$i.icon configure -image $icon_dieing \
							-background [dict get $::_preferences styles clocks slot_bg [::gmaprofile::dlkeypref $::_preferences]]
						$w.slot$i.name configure \
							-foreground [dict get $::_preferences styles clocks slot_fg [::gmaprofile::dlkeypref $::_preferences]] \
							-background [dict get $::_preferences styles clocks slot_bg [::gmaprofile::dlkeypref $::_preferences]]
					} elseif {[dict get $_window_state($w) ilist $i health_tracker is_flat_footed]} {
						$w.slot$i configure \
							-highlightbackground [dict get $::_preferences styles clocks flat_footed [::gmaprofile::dlkeypref $::_preferences]] \
							-highlightcolor [dict get $::_preferences styles clocks flat_footed [::gmaprofile::dlkeypref $::_preferences]] \
							-highlightthickness 4
					} else {
						$w.slot$i configure -highlightbackground #000000 -highlightcolor #000000 -highlightthickness 0
					}
				}
			}
		} else {
			if {[dict get $_window_state($w) flist] eq {}} {
				set i 0
				foreach slot [lsort -integer [dict keys [dict get $_window_state($w) ilist]]] {
					if {$i < $limit} {
						dict set _window_state($w) flist $slot [frame $w.slot$slot -background $flist_bg \
							-relief solid]
						pack [label $w.slot$slot.icon -background $flist_bg -image $icon_blank] -side left
						pack [label $w.slot$slot.name -background $flist_bg -foreground $flist_fg\
							-font [::gmaprofile::lookup_font $::_preferences [dict get $::_preferences styles clocks default_font]] \
							-text [dict get $_window_state($w) ilist $slot name] \
							-anchor center -relief solid -bd 0] \
								-side top -fill x
						pack $w.slot$slot -side top -padx 2 -pady 1 -expand 0 -fill x -ipadx 0 -ipady 0
					}
				}
			}

			dict for {i v} [dict get $_window_state($w) flist] {
				if {$i eq {.sep}} {
					continue
				}
				if {[dict get $_window_state($w) ilist $i hold]} {
					if {[dict get $_window_state($w) ilist $i ready]} {
						$w.slot$i configure -background $ready_bg
						$w.slot$i.name configure -background $ready_bg
						$w.slot$i.icon configure -background $ready_bg -image $icon_readied_action
					} else {
						$w.slot$i configure -background $hold_bg
						$w.slot$i.name configure -background $hold_bg
						$w.slot$i.icon configure -background $hold_bg -image $icon_held_action
					}
				} else {
					$w.slot$i configure -background $flist_bg
					$w.slot$i.name configure -background $flist_bg
					$w.slot$i.icon configure -background $flist_bg -image $icon_blank
				}

				if {[dict get $_window_state($w) ilist $i health_tracker] ne {}} {
					if {[dict get $_window_state($w) ilist $i health_tracker value] == 0} {
						$w.slot$i configure \
							-highlightbackground [dict get $::_preferences styles clocks zero_hp [::gmaprofile::dlkeypref $::_preferences]] \
							-highlightcolor [dict get $::_preferences styles clocks zero_hp [::gmaprofile::dlkeypref $::_preferences]] \
							-highlightthickness 4
					} elseif {[dict get $_window_state($w) ilist $i health_tracker value] < 0} {
						$w.slot$i configure \
							-highlightbackground [dict get $::_preferences styles clocks negative_hp [::gmaprofile::dlkeypref $::_preferences]] \
							-highlightcolor [dict get $::_preferences styles clocks negative_hp [::gmaprofile::dlkeypref $::_preferences]] \
							-highlightthickness 4 \
							-background [dict get $::_preferences styles clocks slot_bg [::gmaprofile::dlkeypref $::_preferences]]
						$w.slot$i.icon configure -image $icon_dieing \
							-background [dict get $::_preferences styles clocks slot_bg [::gmaprofile::dlkeypref $::_preferences]] \
							-foreground [dict get $::_preferences styles clocks slot_fg [::gmaprofile::dlkeypref $::_preferences]]
						$w.slot$i.name configure \
							-background [dict get $::_preferences styles clocks slot_bg [::gmaprofile::dlkeypref $::_preferences]] \
							-foreground [dict get $::_preferences styles clocks slot_fg [::gmaprofile::dlkeypref $::_preferences]]
					} elseif {[dict get $_window_state($w) ilist $i health_tracker is_flat_footed]} {
						$w.slot$i configure \
							-highlightbackground [dict get $::_preferences styles clocks flat_footed [::gmaprofile::dlkeypref $::_preferences]] \
							-highlightcolor [dict get $::_preferences styles clocks flat_footed [::gmaprofile::dlkeypref $::_preferences]] \
							-highlightthickness 4
					} else {
						$w.slot$i configure \
							-highlightbackground #000000 \
							-highlightcolor #000000 \
							-highlightthickness 0
					}
				}
			}
		}
	} else {
		if {[dict get $_window_state($w) flist] ne {}} {
			dict for {k f} [dict get $_window_state($w) flist] {
				pack forget $f
				destroy $f
			}
			dict set _window_state($w) flist {}
		}
	}
	update
}

# start_clock w ?clockwidget-opts...?
proc start_clock {w args} {
	variable _window_state
	dict set _window_state($w) combat_mode false
	_start_clock $w.timeclock {*}$args
	update_clock $w
}

# start_combat w ?clockwidget-opts...?
proc start_combat {w args} {
	variable _window_state
	variable _clock_state

	dict set _window_state($w) combat_mode true
	_start_combat $w.timeclock {*}$args
	update_combat $w [dict get $_clock_state($w.timeclock) delta_time]
}

proc stop_clock {w args} { _stop_clock $w.timeclock {*}$args}
proc stop_combat {w args} { _stop_combat $w.timeclock {*}$args}
	
# update_clock w ?clockwidget-opts...?
proc update_clock {w args} {
	_update_clock $w.timeclock 1 {*}$args
	$w.timedisp configure -text [to_string $w.timeclock 2]
	$w.turndisp configure -text {}
	update_initiative_slots $w
}

proc _refresh_clock_display {w} {
	set parent [join [lrange [split $w .] 0 end-1] .]
	$parent.timedisp configure -text [to_string $w 2]
}

# update_combat w ?new_delta_time=0?
proc update_combat {w {new_delta_time 0}} {
	variable _clock_state
	_update_combat $w.timeclock 1 $new_delta_time
	$w.timedisp configure -text [to_string $w.timeclock 2]
	$w.turndisp configure -text [delta_string [dict get $_clock_state($w.timeclock) delta_time]]
	update_initiative_slots $w
}


# current_initiative_slot w -> slot_no
proc current_initiative_slot {w} {
	variable _clock_state
	return [expr [dict get $_clock_state($w.timeclock) delta_time] % 60]
}

# to_string w style -> string
proc to_string {w style} {
	variable _clock_state
	variable month_info

	switch $style {
		2 {	;# style 2: dd-MMM-yyyy HH:MM:SS.T
			return [format "%02d-%s-%d %02d:%02d:%02d.%d" \
				[dict get $_clock_state($w) calendar date] \
				[lindex [lindex $month_info [dict get $_clock_state($w) calendar month]-1] 1]\
				[dict get $_clock_state($w) calendar year] \
				[dict get $_clock_state($w) calendar hour] \
				[dict get $_clock_state($w) calendar minute] \
				[dict get $_clock_state($w) calendar second] \
				[dict get $_clock_state($w) calendar tick] \
			]
		}
		4 {	;# style 4: HH:MM:SS.T
			return [format "%02d:%02d:%02d.%d" \
				[dict get $_clock_state($w) calendar hour] \
				[dict get $_clock_state($w) calendar minute] \
				[dict get $_clock_state($w) calendar second] \
				[dict get $_clock_state($w) calendar tick] \
			]
		}
		default {
			error "date style $style not supported"
		}
	}
}
# delta_string delta ?-strict? -> string	(strict assumed false)
proc delta_string {delta args} {
	variable day_units
	variable hour_units
	variable minute_units
	variable round_units
	variable second_units
	variable tick_mod
	variable hour_mod
	variable minute_mod
	variable second_mod

	set strict [expr [lsearch -exact $args -strict] >= 0]

	if {$delta < 0} {
		set delta [expr -$delta]
		set sign "-"
		set mult -1
	} else {
		set sign "+"
		set mult 1
	}

	if {$strict} {
		if {$delta == 0} {
			return "nil"
		}
		foreach {u lim uname plural} {
			$day_units {} day days
			$hour_units $day_units hour hours
			$minute_units $hour_units minute minutes
			$round_units [expr 10*$minute_units], round rounds
			$second_units $minute_units second seconds
			1 10 {} {}
		} {
			set q [expr $delta / $u]
			if {$delta % $u == 0 && ($lim eq {} || $delta < $lim)} {
				if {$q == 1 && $sign eq {+}} {
					return $uname
				}
				return [format "%s %s" [expr $mult*$q] [expr $q == 1 ? $uname : $plural]]
			}
		}
		set res $sign
		if {$delta >= $day_units} {
			append res [expr $delta / $day_units] :
		}
		if {$delta >= $hour_units} {
			append res [format "%02d:" [expr $delta / $hour_units % $hour_mod]]
		}
		append res [format "%02d:%02d" [expr $delta / $minute_units % $minute_mod] [expr $delta / $second_units % $second_mod]]
		if {$delta % $tick_mod != 0} {
			append res . [expr $delta % $tick_mod]
		}
		return $res
	}
	
	set res $sign
	set days [expr $delta / $day_units]
	set hours [expr $delta / $hour_units % $hour_mod]
	if {$days > 0} {
		append res $days {d }
	}
	if {$days > 0 || $hours > 0} {
		append res [format "%02d:" $hours]
	}
	return [format "%s%02d:%02d.%d %4.1fr" $res \
		[expr $delta / $minute_units % $minute_mod] \
		[expr $delta / $second_units % $second_mod] \
		[expr $delta % $tick_mod] \
		[expr double($delta) / $round_units]]
}


# CO {Enabled:bool}
# combat_mode w enabled callback
proc combat_mode {w enabled {callback {}}} {
	variable _window_state
	if {$enabled} {
		if {! [dict get $_window_state($w) combat_mode]} {
			stop_clock $w 1 [list ::gmaclock::start_combat $w 0 $callback]
		}
	} else {
		if {[dict get $_window_state($w) combat_mode]} {
			stop_combat $w 1 [list ::gmaclock::start_clock $w 0 $callback]
		}
	}
}

# CS {Absolute:int, Relative:int, Running:bool}
# update_time w abs rel	?-running? ?clockwidgetopts...?
proc update_time {w absolute relative args} {
	variable _window_state
	set_time_value $w.timeclock $absolute
	if {[dict get $_window_state($w) combat_mode]} {
		update_combat $w $relative
	} else {
		update_clock $w {*}$args
	}
}

# IL {InitiativeList:[Slot:int, CurrentHP:int, Name:str, IsHolding:bool, HasReadiedAction:bool, IsFlatFooted:bool ...]}
# set_initiative_slots w slotlist ?-force?  (slotlist is a list of slot dicts as above; -force to force redraw)
proc set_initiative_slots {w newlist args} {
	variable _window_state
	set newdict {}
	foreach slotdict $newlist {
		dict set newdict [dict get $slotdict Slot] [dict create \
			name	[dict get $slotdict Name] \
			hold	[dict get $slotdict IsHolding] \
			ready	[dict get $slotdict HasReadiedAction] \
			health_tracker [dict create \
				value [dict get $slotdict CurrentHP] \
				is_flat_footed [dict get $slotdict IsFlatFooted] \
			]\
		]
	}

	dict set _window_state($w) ilist $newdict
	update_initiative_slots $w {} {*}$args
}


# OA {ObjID:@name, NewAttrs:{Health:{IsFlatFooted:bool ...} ...}}
# track_health_change w oadict
proc track_health_change {w oadict} {
	variable _window_state

	# we're only interested in targets with @<name> format
	if {[string length [set name [dict get $oadict ObjID]]] > 1 && [string range $name 0 0] eq {@}} {
		set name [string range $name 1 end]
		dict for {slot_no slot_data} [dict get $_window_state($w) ilist] {
			# and only if <name> is in the initiative list
			if {[dict get $slot_data name] eq $name} {
				# and only if we're getting an update to their health status
				if {[dict exists $oadict NewAttrs Health]} {
					set ff [dict get $oadict NewAttrs Health IsFlatFooted]
					if {bool($ff) != bool([dict get $slot_data health_tracker is_flat_footed])} {
						dict set _window_state($w) ilist $slot_no health_tracker is_flat_footed $ff
						update_initiative_slots $w
						return
					}
				}
			}
		}
	}
}

proc exists {w} {
	variable _window_state
	return [info exists _window_state($w)]
}

}
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
