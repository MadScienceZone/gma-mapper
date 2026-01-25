########################################################################################
#  _______  _______  _______                ___       ______    ______      ______     #
# (  ____ \(       )(  ___  ) Game         /   )     / ___  \  / ____ \    / ____ \    #
# | (    \/| () () || (   ) | Master's    / /) |     \/   \  \( (    \/   ( (    \/    #
# | |      | || || || (___) | Assistant  / (_) (_       ___) /| (____     | (____      #
# | | ____ | |(_)| ||  ___  |           (____   _)     (___ ( |  ___ \    |  ___ \     #
# | | \_  )| |   | || (   ) | VTT            ) (           ) \| (   ) )   | (   ) )    #
# | (___) || )   ( || )   ( | Mapper         | |   _ /\___/  /( (___) ) _ ( (___) )    #
# (_______)|/     \||/     \| Client         (_)  (_)\______/  \_____/ (_) \_____/     #
#                                                                                      #
########################################################################################

proc CreatureSizeParams {size_code} {
	if {[regexp {^\s*([FDTSMLHGCfdtsmlhgc])(\d+)?(?:->(\d+))?(?:=(\d+))?(?::.*)?\s*$} $size_code _ category nat ext sz]} {
		if {$nat ne {}} {set nat [expr int($nat/5)]}
		if {$ext ne {}} {set ext [expr int($ext/5)]}
		if {$sz  ne {}} {set sz  [expr int($sz/5)]}
		return [list $category $nat $ext $sz]
	}
	return {}
}

#
# compute arbitrary threat and reach zones
# ComputedReachMatrix size natural reach -> natural reach matrix
#   size - size category code for creature
#   natural - size category or number of squares of natural reach from creature perimeter
#   reach - size category or number of squares of extended reach from creature perimeter
#
proc MatchesStandardTemplate {size natural extended} {
	set params [CreatureSizeParams $size]
	if {$params eq {}} {
		# the size is completely invald
		return {}
	}
	lassign $params category nat ext space
	set template [ReachMatrix $size]
	if {$template ne {} && $space eq {} && [lindex $template 0] == $natural && [lindex $template 1] == $extended} {
		# effectively reduces to the standard template for the given size
		return $template
	}
	return {}
}

proc ComputedReachMatrix {size natural reach} {
	set template [MatchesStandardTemplate $size $natural $reach]
	if {$template ne {}} {
		return $template
	}
	#
	# We need to compute the threat zones ourselves.
	# We'll take for granted here that the exception for diagonal distances for medium
	# creatures is already taken care of by the standard templates at this point.
	# So we'll just compute based on the distance formula
	#
	set size_g [MonsterSizeValue $size]
	# |<rn>||<rn>|
	# +----------+
	# |    rr    |
	# |    rr    |
	# |    nn    |
	# |    nn    |
	# |rrnnSSnnrr|
	# |rrnnSSnnrr|
	# |    nn    |
	# |    nn    |
	# |    rr    |
	# |    rr    |
	# +----------+
	set matrix_dimension [expr $size_g + max(2*$reach,2*$natural)]
	set distance_to_perimeter [expr max($natural,$reach)]
	set matrix {}
	for {set y 0} {$y < $matrix_dimension} {incr y} {
		set row {}
		for {set x 0} {$x < $matrix_dimension} {incr x} {
			if {$x < $distance_to_perimeter} {
				set reference_x $distance_to_perimeter
			} elseif {$x >= $distance_to_perimeter+$size_g} {
				set reference_x [expr $distance_to_perimeter+$size_g-1]
			} else {
				set reference_x $x
			}
			if {$y < $distance_to_perimeter} {
				set reference_y $distance_to_perimeter
			} elseif {$y >= $distance_to_perimeter+$size_g} {
				set reference_y [expr $distance_to_perimeter+$size_g-1]
			} else {
				set reference_y $y
			}
			set distance [expr int((sqrt(pow(5.0*$x-5.0*$reference_x,2) + pow(5.0*$y-5.0*$reference_y,2)))/5.0)]
			if {$distance > $reach} {
				lappend row 0
			} elseif {$distance > $natural} {
				lappend row 1
			} else {
				lappend row 2
			}
		}
		lappend matrix $row
	}
	return [list $natural $reach $matrix]
}

#
# convert size code to:  reach-dia weapon-dia matrix
#
proc MonsterSizeValue {size} {
	set sz [CreatureSizeParams $size]
	if {$sz ne {}} {
		if {[lindex $sz 3] ne {}} {
			return [lindex $sz 3]
		}
	
		set size [lindex $sz 0]
	}
	switch -exact -- $size {
		F - f { return 0.1 }
		D - d { return 0.2 }
		T - t { return 0.5 }
		S - s - 
		M - m - 1 { return 1 }
		L - l - 2 { return 2 }
		H - h - 3 { return 3 }
		G - g - 4 { return 4 }
		C - c - 6 { return 6 }
		default { return 0 }
	}
}

# -> {area reach matrix}
#
# Spaces with 0 will not be drawn as threatened squares
# with 1 or 3 will be in the reach threat zone.
# with 2 or 3 will be in the normal threat zone
#
proc ReachMatrix {size} {
	switch [string range $size 0 0] {
		F - f -
		D - d -
		T - t { return { 0 0 {
		}}}
		1 -
		S - s -
		M - m { return { 1 2 {
			{ 1 1 1 1 1 }
			{ 1 2 2 2 1 }	
			{ 1 2 2 2 1 }	
			{ 1 2 2 2 1 }	
			{ 1 1 1 1 1 }
		}}}
		l { return { 1 2 {
			{ 1 1 1 1 1 1 }
			{ 1 2 2 2 2 1 }
			{ 1 2 2 2 2 1 }
			{ 1 2 2 2 2 1 }
			{ 1 2 2 2 2 1 }
			{ 1 1 1 1 1 1 }
		}}}
		2 -
		L { return { 2 4 {
			{ 0 0 0 1 1 1 1 0 0 0 }
			{ 0 1 1 1 1 1 1 1 1 0 }
			{ 0 1 2 2 2 2 2 2 1 0 }
			{ 1 1 2 2 2 2 2 2 1 1 }
			{ 1 1 2 2 2 2 2 2 1 1 }
			{ 1 1 2 2 2 2 2 2 1 1 }
			{ 1 1 2 2 2 2 2 2 1 1 }
			{ 0 1 2 2 2 2 2 2 1 0 }
			{ 0 1 1 1 1 1 1 1 1 0 }
			{ 0 0 0 1 1 1 1 0 0 0 }
		}}}
		h { return { 2 4 {
			{ 0 0 0 1 1 1 1 1 0 0 0 }
			{ 0 1 1 1 1 1 1 1 1 1 0 }
			{ 0 1 2 2 2 2 2 2 2 1 0 }
			{ 1 1 2 2 2 2 2 2 2 1 1 }
			{ 1 1 2 2 2 2 2 2 2 1 1 }
			{ 1 1 2 2 2 2 2 2 2 1 1 }
			{ 1 1 2 2 2 2 2 2 2 1 1 }
			{ 1 1 2 2 2 2 2 2 2 1 1 }
			{ 0 1 2 2 2 2 2 2 2 1 0 }
			{ 0 1 1 1 1 1 1 1 1 1 0 }
			{ 0 0 0 1 1 1 1 1 0 0 0 }
		}}}
		3 -
		H { return { 3 6 {
			{ 0 0 0 0 0 1 1 1 1 1 0 0 0 0 0 }
			{ 0 0 0 1 1 1 1 1 1 1 1 1 0 0 0 }
			{ 0 0 1 1 1 1 1 1 1 1 1 1 1 0 0 }
			{ 0 1 1 1 1 2 2 2 2 2 1 1 1 1 0 }
			{ 0 1 1 1 2 2 2 2 2 2 2 1 1 1 0 }
			{ 1 1 1 2 2 2 2 2 2 2 2 2 1 1 1 }
			{ 1 1 1 2 2 2 2 2 2 2 2 2 1 1 1 }
			{ 1 1 1 2 2 2 2 2 2 2 2 2 1 1 1 }
			{ 1 1 1 2 2 2 2 2 2 2 2 2 1 1 1 }
			{ 1 1 1 2 2 2 2 2 2 2 2 2 1 1 1 }
			{ 0 1 1 1 2 2 2 2 2 2 2 1 1 1 0 }
			{ 0 1 1 1 1 2 2 2 2 2 1 1 1 1 0 }
			{ 0 0 1 1 1 1 1 1 1 1 1 1 1 0 0 }
			{ 0 0 0 1 1 1 1 1 1 1 1 1 0 0 0 }
			{ 0 0 0 0 0 1 1 1 1 1 0 0 0 0 0 }
		}}}
		G { return { 4 8 {
			{ 0 0 0 0 0 0 0 1 1 1 1 1 1 0 0 0 0 0 0 0 }
			{ 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 }
			{ 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 }
			{ 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 }
			{ 0 0 1 1 1 1 1 2 2 2 2 2 2 1 1 1 1 1 0 0 }
			{ 0 1 1 1 1 2 2 2 2 2 2 2 2 2 2 1 1 1 1 0 }
			{ 0 1 1 1 1 2 2 2 2 2 2 2 2 2 2 1 1 1 1 0 }
			{ 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 }
			{ 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 }
			{ 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 }
			{ 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 }
			{ 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 }
			{ 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 }
			{ 0 1 1 1 1 2 2 2 2 2 2 2 2 2 2 1 1 1 1 0 }
			{ 0 1 1 1 1 2 2 2 2 2 2 2 2 2 2 1 1 1 1 0 }
			{ 0 0 1 1 1 1 1 2 2 2 2 2 2 1 1 1 1 1 0 0 }
			{ 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 }
			{ 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 }
			{ 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 }
			{ 0 0 0 0 0 0 0 1 1 1 1 1 1 0 0 0 0 0 0 0 }
		}}}
		g { return { 3 6 {
			{ 0 0 0 0 0 1 1 1 1 1 1 0 0 0 0 0 }
			{ 0 0 0 1 1 1 1 1 1 1 1 1 1 0 0 0 }
			{ 0 0 1 1 1 1 1 1 1 1 1 1 1 1 0 0 }
			{ 0 1 1 1 1 1 2 2 2 2 1 1 1 1 1 0 }
			{ 0 1 1 1 2 2 2 2 2 2 2 2 1 1 1 0 }
			{ 1 1 1 1 2 2 2 2 2 2 2 2 1 1 1 1 }
			{ 1 1 1 2 2 2 2 2 2 2 2 2 2 1 1 1 }
			{ 1 1 1 2 2 2 2 2 2 2 2 2 2 1 1 1 }
			{ 1 1 1 2 2 2 2 2 2 2 2 2 2 1 1 1 }
			{ 1 1 1 2 2 2 2 2 2 2 2 2 2 1 1 1 }
			{ 1 1 1 1 2 2 2 2 2 2 2 2 1 1 1 1 }
			{ 0 1 1 1 2 2 2 2 2 2 2 2 1 1 1 0 }
			{ 0 1 1 1 1 1 2 2 2 2 1 1 1 1 1 0 }
			{ 0 0 1 1 1 1 1 1 1 1 1 1 1 1 0 0 }
			{ 0 0 0 1 1 1 1 1 1 1 1 1 1 0 0 0 }
			{ 0 0 0 0 0 1 1 1 1 1 1 0 0 0 0 0 }
		}}}
		C { return { 6 12 {
			{ 0 0 0 0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0 0 }
			{ 0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 }
			{ 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 }
			{ 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 }
			{ 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 }
			{ 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 }
			{ 0 0 1 1 1 1 1 1 1 1 1 1 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 }
			{ 0 0 1 1 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 0 0 }
			{ 0 1 1 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 0 }
			{ 0 1 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 0 }
			{ 0 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 0 }
			{ 1 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 }
			{ 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 }
			{ 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 }
			{ 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 }
			{ 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 }
			{ 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 }
			{ 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 }
			{ 1 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 }
			{ 0 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 0 }
			{ 0 1 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 0 }
			{ 0 1 1 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 0 }
			{ 0 0 1 1 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 0 0 }
			{ 0 0 1 1 1 1 1 1 1 1 1 1 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 }
			{ 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 }
			{ 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 }
			{ 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 }
			{ 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 }
			{ 0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 }
			{ 0 0 0 0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0 0 }
		}}}
		c { return { 4 8 {
			{ 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 }
			{ 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 }
			{ 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 }
			{ 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 }
			{ 0 0 1 1 1 1 1 1 2 2 2 2 2 2 1 1 1 1 1 1 0 0 }
			{ 0 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 0 }
			{ 0 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 0 }
			{ 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 }
			{ 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 }
			{ 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 }
			{ 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 }
			{ 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 }
			{ 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 }
			{ 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 }
			{ 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 }
			{ 0 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2 1 1 1 1 0 }
			{ 0 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 0 }
			{ 0 0 1 1 1 1 1 1 2 2 2 2 2 2 1 1 1 1 1 1 0 0 }
			{ 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 }
			{ 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 }
			{ 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 }
			{ 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 }
		}}}
	}
}

#
# This takes a mob ID, considers its full (possibly-customized) size
# information, sets a custom reach value if it has a size code that
# dictates that (unless a custom value was already defined)
# and returns -> size area reach matrix custom_reach
#
proc FullCreatureAreaInfo {id} {
	global MOBdata
	global CreatureGridSnap


	# if we have an explicit size override, take that first
	set szparams [CreatureSizeParams [set disp_size [CreatureDisplayedSize $id]]]
	set custom_reach [dict get $MOBdata($id) CustomReach]
	if {$szparams eq {}} {
		# not a valid size code!
		return {}
	}
	lassign $szparams szcode sznat szext szsz
	lassign [ReachMatrix $szcode] std_nat std_ext std_matrix
	if {$szsz eq {}} {
		set szsz [MonsterSizeValue $szcode]
	}

	# No active customization: use standard values or those encoded in size
	if {$custom_reach eq {} || ([dict exists $custom_reach Enabled] && ![dict get $custom_reach Enabled])} {
		if {$szext eq {}} {
			# no encoded ext
			if {$sznat eq {}} {
				# no encoded ext or nat
				set szext $std_ext
				set sznat $std_nat
			} else {
				# encoded nat but not ext
				set szext [expr $sznat * 2]
			}
		} elseif {$sznat eq {}} {
			# encoded ext but not nat
			set sznat $std_nat
		}
	} else {
		# we do have an active custom set of numbers, so use those
		# to set szext, sznat
		set sznat [expr [dict get $custom_reach Natural] / 5]
		set szext [expr [dict get $custom_reach Extended] / 5]
	}
	
	return [list $szsz $sznat $szext [lindex [ComputedReachMatrix $szcode $sznat $szext] 2] $custom_reach]
}

#
# @[00]@| GMA-Mapper 4.36.6
# @[01]@|
# @[10]@| Overall GMA package Copyright © 1992–2026 by Steven L. Willoughby (AKA MadScienceZone)
# @[11]@| steve@madscience.zone (previously AKA Software Alchemy),
# @[12]@| Aloha, Oregon, USA. All Rights Reserved. Some components were introduced at different
# @[13]@| points along that historical time line.
# @[14]@| Distributed under the terms and conditions of the BSD-3-Clause
# @[15]@| License as described in the accompanying LICENSE file distributed
# @[16]@| with GMA.
# @[17]@|
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
#proc show_matrix {a} {
#	foreach value $a {
#		if {[llength $value] > 1} {
#			foreach row $value {
#				puts $row
#			}
#		} else {
#			puts $value
#		}
#	}
#}
#puts "M 1 2"; show_matrix [ComputedReachMatrix M 1 2]
#puts "M 1 3"; show_matrix [ComputedReachMatrix M 1 3]
#puts "M 1 4"; show_matrix [ComputedReachMatrix M 1 4]
#puts "M 2 6"; show_matrix [ComputedReachMatrix M 2 6]
