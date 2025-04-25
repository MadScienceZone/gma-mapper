########################################################################################
#  _______  _______  _______                ___       _______   _____                  #
# (  ____ \(       )(  ___  ) Game         /   )     / ___   ) / ___ \                 #
# | (    \/| () () || (   ) | Master's    / /) |     \/   )  |( (___) )                #
# | |      | || || || (___) | Assistant  / (_) (_        /   ) \     /                 #
# | | ____ | |(_)| ||  ___  |           (____   _)     _/   /  / ___ \                 #
# | | \_  )| |   | || (   ) |                ) (      /   _/  ( (   ) )                #
# | (___) || )   ( || )   ( | Mapper         | |   _ (   (__/\( (___) )                #
# (_______)|/     \||/     \| Client         (_)  (_)\_______/ \_____/                 #
#                                                                                      #
########################################################################################
# Steve Willoughby <steve@madscience.zone>
#
# @[00]@| GMA-Mapper 4.28
# @[01]@|
# @[10]@| Overall GMA package Copyright © 1992–2025 by Steven L. Willoughby (AKA MadScienceZone)
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
#
# General utility functions

package provide gma::minimarkup 1.0
package require Tcl 8.6

namespace eval ::gma::minimarkup {
	namespace export render strip

	# Implements a subset of the GMA markup codes which can be shown in a text box as a single line
	# (so no tables or line breaks, but pretty much everything else). We assume this text will be
	# a single line so we'll ignore line breaks and everything that implies multi-line structures
	# such as tables.
	
	#
	# \e			\
	# \v			|
	# //			toggle italics
	# **			toggle bold
	# \.			zero-width space
	# [S]			section
	# [c]			copyright
	# [R]			registered
	# [<<] [>>]		angle quotes
	# ^o			degrees
	# +/-			plusminus
	# ^.			bullet 2022
	# [0]-[9]		superscript digits
	# AE ae			ligaturees
	# 1/4 1/2 3/4		fractions	(underscore between digit and these is dropped)
	# [x] [/]		mult div signs
	# - -- ---		hyphen, en, em dashes
	# ` ' `` ''		quotes
	# [+] [++]		daggers
	# x1 2x			x before or after a digit turns into a multiplication sign
	# -1			hyphen before a digit becomes a minus sign
	# ==[x]== ==(x)==	title and subtitle
	#
	# Nerfed:
	# @@@...		bullet item	(must start in col 1) 2022 2023 2043 25cb 261e 2605
	# ###...		numbered item   (must start in col 1)
	# [[item]]		link to GMA item
	# [[item|text]]		link to GMA item
	#
	# Ignored:
	# |...|			table columns (must begin in col 1)
	# blank line		paragraph break
	# \\			line break
	#
	
	# strips font style information from rendered text, returning a single
	# string that may contain Unicode characters resulting from markup
	# code interpretation.
	proc strip {rendered_list} {
		set output {}
		foreach {fontstyle text} $rendered_list {
			lappend output $text
		}
		return [join $output {}]
	}

	#
	# Returns a list of tag text pairs where tag is one of:
	# 	normal, bold, italic, bolditalic, section, subsection
	proc render {mtext} {
		set lines [split $mtext "\n"]
		set levels {}
		# look for list items before we fold the lines back together
		set newlines {}
		foreach line $lines {
			set label ""
			if {[regexp -- {^(@+|#+)\s*(.*?)} $line _ bullets rest]} {
				for {set i 0} {$i < [string length $bullets]} {incr i} {
					if {[string index $bullets $i] eq "@"} {
						if {$i > 5} {
							append label *
						} else {
							append label [lindex [list "\u2022" "\u2023" "\u2043" "\u25cb" "\u261e" "\u2605"] $i]
						}
					} else {
						while {[llength $levels] <= $i} {
							lappend levels 0
						}
						if {$i == [expr [string length $bullets] - 1]} {
							set levels [lreplace $levels $i $i [expr [lindex $levels $i] + 1]]
						} 
						append label "([lindex $levels $i])"
					}
				}
				set line "$label $rest"
			}
			lappend newlines $line
		}
		set srctext "Z[join $newlines { }]"
		foreach {t in out} {
			s {+/-}  "\u00B1"
			s {---}  "\u2014"
			s {--}   "\u2013"
			r {(\d)x} "\\1\u00D7"
			r {x(\d)} "\u00D7\\1"
			s {[x]}   "\u00D7"
			s {[S]}   "\u00A7"
			s {[0]}   "\u00B0"
			s {[1]}   "\u00B9"
			s {[2]}   "\u00B2"
			s {[3]}   "\u00B3"
			s {[4]}   "\u2074"
			s {[5]}   "\u2075"
			s {[6]}   "\u2076"
			s {[7]}   "\u2077"
			s {[8]}   "\u2078"
			s {[9]}   "\u2079"
			r {-(\d)}   "\u2012\\1"
			r {\b1/2\b} "\u00BD"
			r {\b1/4\b} "\u00BC"
			r {\b3/4\b} "\u00BE"
			r {\b(\d+)_1/2\b} "\\1\u00BD"
			r {\b(\d+)_1/4\b} "\\1\u00BC"
			r {\b(\d+)_3/4\b} "\\1\u00BE"
			s {^o}   "\u00B0"
			s {[c]}  "\u00A9"
			s {[R]}  "\u00AE"
			s {[<<]} "\u00AB"
			s {[>>]} "\u00BB"
			s {AE}   "\u00C6"
			s {ae}   "\u00E6"
			s {^.}   "\u2022"
			s {[/]}  "\u00F7"
			s {[+]}  "\u2020"
			s {[++]} "\u2021"
			s {\\v}  "|"
			s {//}   "\001I"
			s {**}   "\001B"
			s {``}   "\u201C"
			s {''}   "\u201D"
			s {`}    "\u2018"
			s {'}    "\u2019"
			r {==\[(.*?)\]==} "\001T\\1\001t"
			r {==\((.*?)\)==} "\001S\\1\001s"
			r {\[\[.*?\|(.+)\]\]} "\001L\\1\001l"
			r {\[\[(.*?)\]\]} "\001L\\1\001l"
			s {\\.}  ""
			s {\\e}  "\\"
		} {
			if {$t == "r"} {
				#DEBUG 0 "Looking to replace /$in/ in $srctext with $out"
				set srctext [regsub -all -- $in $srctext $out]
				#DEBUG 0 ": -> $srctext"
			} else {
				#DEBUG 0 "Looking for $in in $srctext"
				for {set start 0} {[set start [string first $in $srctext $start]] >= 0} {incr start [string length $out]} {
					#DEBUG 0 ": found $in at $start, replacing $start-[expr $start+[string length $in]] with $out"
					set srctext [string replace $srctext $start [expr $start+[string length $in]-1] $out]
					#DEBUG 0 ": -> $srctext"
				}
			}
		}

		set finalset {}
		set italic false
		set bold false
		set link false
		set section false
		set subsection false
		foreach piece [split $srctext "\001"] {
			switch [string range $piece 0 0] {
				"I" {set italic [expr !$italic]}
				"B" {set bold [expr !$bold]}
				"L" {set link true}
				"l" {set link false}
				"S" {set subsection true}
				"s" {set subsection false}
				"T" {set section true}
				"t" {set section false}
			}
			# there's an order of priority to these
			if {$section} {
				lappend finalset section
			} elseif {$subsection} {
				lappend finalset subsection
			} elseif {$link} {
				lappend finalset italic
			} elseif {$bold && $italic} {
				lappend finalset bolditalic
			} elseif {$bold} {
				lappend finalset bold
			} elseif {$italic} {
				lappend finalset italic
			} else {
				lappend finalset normal
			}
			lappend finalset [string range $piece 1 end]
		}
		#DEBUG 0 "final $finalset"
		return $finalset
	}
	proc ShowMarkupSyntax {} {
		set w .markupsyntax
		::create_dialog $w
		wm title $w "Markup Syntax Information"
		grid [text $w.text -yscrollcommand "$w.sb set"] \
		     [scrollbar $w.sb -orient vertical -command "$w.text yview"]\
				-sticky news
		grid columnconfigure $w 0 -weight 1
		grid rowconfigure $w 0 -weight 1
		$w.text tag configure h1 -justify center -font Tf14
		$w.text tag configure p -font Nf12 -wrap word
		$w.text tag configure i -font If12 -wrap word
		$w.text tag configure b -font Tf12 -wrap word

		foreach line {
			{h1 {GMA Markup Syntax}}
			{p {}}
			{p  {The Mapper supports a subset of the GMA Markup formatting codes in chat messages.}}
			{p {}}
			{p  {Recipients whose clients do not support markup formatting will not see the codes in their messages.}}
			{p {}}
			{p  {Simple text effects like bold and italics may be achieved simply by typing }
		         b  {**} i {bold text} b {**} p { or } b {//} i {italic text} b {//} p { (and can be combined, as in } b {**//} i {bold italic text} b {//**}
			 p  {).}}
			{p {}}
			{p {Special characters are represented by easier to type codes, including }
				b {``} p {, } b {''} p {, } b {`} p { and } b {'} p " for \u201C, \u201D, \u2018, and \u2019 quotes; "
				b {---} p {, } b {--} p {, and } b {-} i digit p " for \u2014 (em dash), \u2013 (en dash), and \u2012"
				i digit
				p { (minus sign when the - is followed immediately by a digit). }}
			{b {[x]} p " produces a multiplication sign \u00D7, but a letter " b x p " immediately before or after a digit, "
				p "as in " b {x2} p { or } b {2x} p " is converted to a multiplication sign automatically to give \u00D72 or 2\u00D7."}
			{b {[0]} p {, } b {[1]} p {, ..., } b {[9]} p " provide superscript digits \u00B0, \u00B9, ..., \u2079; "
				b {1/2} p {, } b {1/4} p {, and } b {3/4} p " give fractions \u00BD, \u00BC, \u00BE; if these are to"
				p " appear after other digits, separate them with an underscore, so "
				b {12_1/2} p {, } b {42_1/4} p {, and } b {9_3/4} p 
				" would yield 12\u00BD, 42\u00BC, and 9\u00BE."}
			{p {Finally, }
				b {[S]} p {, } b {+/-} p {, } 
				b {[c]} p {, } b {[R]} p {, } b {^o} p {, } b {[<<]} p {, } b {[>>]} p {, } b {AE} p {, }
				b {ae} p {, } b {^.} p {, } b {[/]} p {, } b {[+]} p {, and } b {[++]}
				p " provide the miscellaneous symbols \u00A7, \u00B1, \u00A9, \u00AE, \u00B0, \u00AB, \u00BB, \u00C6, \u00E6, "
				p "\u2022, \u00F7, \u2020, and \u2021."}
			{p {}}
			{p {Literal } b "\\" p { and } b {|} p { characters may also be written as \e and \v, respectively, for compatibility with other GMA systems where those need to be typed specially, although those shouldn't really be necessary for the mapper itself.}}
			{p {}}
			{p {A zero-width space, or null operation, may be specified as } b {\.} p {, which may be inserted in the middle of other characters so the parser doesn't mistake them for one of the markup sequences described here.}}
			{p {}}
			{p {Section titles and subtitles may be marked up as }
				b {==[Section Title]==} p { and }
				b {==(Subsection Title)==} p {, repsectively.}}
			{p {}}
			{p {Hyperlinks are not fully supported yet, but the syntax for designating them is still recognized as }
				b {[[} i link b {]]} p { (or }
				b {[[} i link b {|} i text b {]]} p { if you want to specify custom text for the link) will for now}
			 	p {just be rendered in italics without actually creating a hyperlink.}}
			{p {}}
			{p {Bullet lists and numbered lists are normally introduced by } b @ p { and } b {#} p { characters at the first column of the line, with repeated characters such as }
				b @@@ p {, } b {###} p {, or } b {#@#} p { to denote nested lists. Since the chat message formatter is oriented for single lines, it will do its best to handle them anyway as in-line lists.}}
			{p {Since multi-line formatting is not supported here, line and paragraph breaks, as well as tables, are not supported at all.}}
			{p {}}
			{p {}}
			{p {This feature requires GMA Mapper version 4.29 and Server version 5.27.0 or later.}}
		} {
			foreach {f t} $line {
				$w.text insert end $t $f
			}
			$w.text insert end "\n"
		}
		$w.text configure -state disabled
	}
}
