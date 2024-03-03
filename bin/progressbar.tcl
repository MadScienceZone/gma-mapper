#
# progressbar adapted from wiki.tcl-lang.org/page/progressbars
# because the standard ttk::progressbar widgets, nice as they may
# be, didn't easily enough suit our purposes for timer gauges.
#
proc progressbar {w args} {
	global gma_timer_label
	array set opt {
		-width 256 -height 16 -relief sunken -borderwidth 1 -style bar -label ""
	}
	array set opt $args
	set style $opt(-style)
	unset opt(-style)  ;# don't let the canvas get this
	array set gma_timer_label [list $w $opt(-label)]
	unset opt(-label)
	eval canvas $w [array get opt]
	set h [$w cget -height]
	switch -- $style {
		bar {
		    $w create rect 1 1 1 [expr {$h-1}] -fill CornflowerBlue \
			-tags {bar status}
		}
		circle {
		    $w create arc  1 1 [expr {$h-1}] [expr {$h-1}] -start 90 \
		     -fill CornflowerBlue -tags {arc status} -extent 0
		}
	}

	$w create text [expr [$w cget -width] / 2] [expr $h / 2] \
		-text "gma_timer_label($w) 0%" -tags txt
	rename $w _$w
	proc $w {args} {
		global gma_timer_label
		set w [lindex [info level 0] 0]
		if {[lindex $args 0] == "set"} {
			set n [lindex $args 1]
			set gma_timer_label($w) [lindex $args 2]
			set h [winfo height $w]
			set width [winfo width $w]
			set color [color:rgb $n]
			$w itemconf txt -text "$gma_timer_label($w) ${n}%"
			$w coords txt [expr $width / 2] [expr $h / 2]
			$w coords bar 1 1 [expr $n * $width / 100] [expr $h - 1]
			$w itemconf status -fill $color -outline $color
			$w itemconf arc -extent [expr $n*-3.599]
		} elseif {[lindex $args 0] == "unknown"} {
			set h [winfo height $w]
			set width [winfo width $w]
			set color "CornflowerBlue"
			$w itemconf txt -text "$gma_timer_label($w) unknown"
			$w coords txt [expr $width / 2] [expr $h / 2]
			$w coords bar 1 1 0 [expr $h - 1]
			$w itemconf status -fill $color -outline $color
		} elseif {[lindex $args 0] == "expired"} {
			set h [winfo height $w]
			set width [winfo width $w]
			set color red
			$w itemconf txt -text "$gma_timer_label($w) EXPIRED"
			$w coords txt [expr $width / 2] [expr $h / 2]
			$w coords bar 1 1 $width [expr $h - 1]
			$w itemconf status -fill $color -outline $color
		} else {
			eval _$w $args 
		}
	}
	set w
}

proc color:rgb {n} {
    # map 0..100 to a red-yellow-green sequence
    set n     [expr {$n < 0? 0: $n > 100? 100: $n}]
    set red   [expr {$n > 75? 60 - ($n * 15 / 25) : 15}]
    set green [expr {$n < 50? $n * 15 / 50 : 15}]
    format    "#%01x%01x0" $red $green
}


#----- Test:
if {[file tail [info script]]==[file tail $argv0]} {
	progressbar .1 -label "This is a timer"
	progressbar .1a -label "This is also a timer"
	progressbar .2 -style circle -height 50 -width 50
	pack .1 .1a .2

	proc test {} {
		for {set i 0} {$i<=10000} {incr i 100} {
		     after $i .1 set [expr $i/100]
		     after $i .1a set [expr $i/100]
		     after $i .2 set [expr $i/100]
		}
	}
	test
	bind . <1> test
}

