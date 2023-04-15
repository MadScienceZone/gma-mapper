#!/usr/bin/env tclsh
proc LetterLabel {x} {
	set l [string index ABCDEFGHIJKLMNOPQRSTUVWXYZ [expr $x % 26]]
	set x [expr $x/26]
	while {$x > 0} {
		incr x -1
		set l "[string index ABCDEFGHIJKLMNOPQRSTUVWXYZ [expr $x % 26]]$l"
		set x [expr $x/26]
	}
	return $l
}

proc LetterLabelToGridXY {label} {
	if [regexp {^([A-Z]+)([0-9]+)$} [string toupper $label] _ xlabel ylabel] {
		set x -1
		foreach letter [split $xlabel {}] {
			incr x
			set x [expr $x*26 + [scan $letter %c] - 65]
		}
		return [list $x $ylabel]
	} 
	error "$label is not a valid map locator value"
}

foreach x $argv {
	if {[catch {set r [LetterLabelToGridXY $x]}]} {
		puts "$x = [LetterLabel $x]"
	} else {
		puts "$x = $r"
	}
}
