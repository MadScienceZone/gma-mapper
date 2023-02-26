########################################################################################
#  _______  _______  _______                ___       _______     _______              #
# (  ____ \(       )(  ___  ) Game         /   )     (  __   )   (  ____ \             #
# | (    \/| () () || (   ) | Master's    / /) |     | (  )  |   | (    \/             #
# | |      | || || || (___) | Assistant  / (_) (_    | | /   |   | (____               #
# | | ____ | |(_)| ||  ___  |           (____   _)   | (/ /) |   (_____ \              #
# | | \_  )| |   | || (   ) |                ) (     |   / | |         ) )             #
# | (___) || )   ( || )   ( | Mapper         | |   _ |  (__) | _ /\____) )             #
# (_______)|/     \||/     \| Client         (_)  (_)(_______)(_)\______/              #
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

	if {[info exists _clock_state($w)]} {
		error "a gmaclock widget already exists with path $w"
	}

	set _clock_state($w) [dict create \
		calendar [_new_cal] \
		combat_mode false\
		dark_mode false \
		delta_time 0\
		half_hours true \
		hand_scale 2 \
	]

	set opts {}

	for {set i 0} {$i < [llength $args]} {incr i} {
		switch -exact -- [lindex $args $i] {
			-24hr	{dict set _clock_state($w) half_hours false}
			-dark	{dict set _clock_state($w) dark_mode true}
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
	_draw_face $w
}

#proc _window_change {w} {
#	_draw_face $w
#}

# start_clock w ?scale=0? ?callback?
proc start_clock {w {scale 0} {callback {}}} {
	variable _clock_state

	$w delete ticks
	set hm [dict get $_clock_state($w) hm]
	for {set p 0} {$p < $hm} {incr p} {
		_draw_hand $w $p $hm 0.95 1 [expr 0.95-(0.1*$scale)] 2 {face ticks}
	}
	if {$scale < 1} {
		update_clock $w $scale
		after 10 [list ::gmaclock::start_clock $w [expr $scale+0.01] $callback]
	} else {
		update_clock $w
		if {$callback ne {}} {
			{*}$callback
		}
	}
}

proc start_combat {w {scale 0} {callback {}}} {
	variable _clock_state

	dict set _clock_state($w) combat_mode true
	if {[dict get $_clock_state($w) dark_mode]} {
		set fill #aaaaaa
	} else {
		set fill blue
	}
	$w delete ticks
	for {set p 0} {$p < 10} {incr p} {
		_draw_hand $w $p 10 0.95 1 [expr 0.95-(0.95*$scale)] 2 {face ticks} $fill
	}

	if {$scale < 1} {
		update_combat $w $scale
		after 10 [list ::gmaclock::start_combat $w [expr $scale+0.01] $callback]
	} else {
		update_combat $w
		if {$callback ne {}} {
			{*}$callback
		}
	}
}

proc stop_combat {w {scale 1} {callback {}}} {
	variable _clock_state

	if {[dict get $_clock_state($w) dark_mode]} {
		set fill #aaaaaa
	} else {
		set fill blue
	}
	$w delete ticks
	for {set p 0} {$p < 10} {incr p} {
		_draw_hand $w $p 10 0.95 1 [expr 0.95-(0.95*$scale)] 2 {face ticks} $fill
	}

	if {$scale > 0} {
		update_combat $w $scale
		after 10 [list ::gmaclock::stop_combat $w [expr $scale-0.01] $callback]
	} else {
		update_combat $w
		if {$callback ne {}} {
			{*}$callback
		}
	}
	dict set _clock_state($w) combat_mode false
}

# stop_clock w ?scale=1? ?callback?
proc stop_clock {w {scale 1} {callback {}}} {
	variable _clock_state

	$w delete ticks
	set hm [dict get $_clock_state($w) hm]
	dict set _clock_state($w) combat_mode false
	for {set p 0} {$p < $hm} {incr p} {
		_draw_hand $w $p $hm 0.95 1 [expr 0.95-(0.1*$scale)] 2 {face ticks}
	}
	if {$scale > 0} {
		update_clock $w $scale
		after 10 [list ::gmaclock::stop_clock $w [expr $scale-0.01] $callback]
	} else {
		update_clock $w 0
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
		if {[dict get $_clock_state($w) dark_mode]} {
			set fill #aaaaaa
		} else {
			set fill #000000
		}
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
	if {[dict get $_clock_state($w) dark_mode]} {
		set color #aaaaaa
	} else {
		set color #000000
	}
	$w create oval 5 5 [expr $wd-1] [expr $h-1] -width 4 -tags face -outline $color
}

# update_clock w ?scale=1? ?-complete? ?-running?
proc update_clock {w {time_scale 1} args} {
	variable _clock_state
	variable minute_mod
	variable second_mod

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

proc update_combat {w {time_scale 1} {new_delta_time {}}} {
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
	{Neth      NET {30 30}}
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
}
#
# @[00]@| GMA 5.0.0
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
