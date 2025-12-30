########################################################################################
#  _______  _______  _______                ___       ______    ______     ______      #
# (  ____ \(       )(  ___  ) Game         /   )     / ___  \  / ____ \   / ___  \     #
# | (    \/| () () || (   ) | Master's    / /) |     \/   \  \( (    \/   \/   \  \    #
# | |      | || || || (___) | Assistant  / (_) (_       ___) /| (____        ___) /    #
# | | ____ | |(_)| ||  ___  |           (____   _)     (___ ( |  ___ \      (___ (     #
# | | \_  )| |   | || (   ) | VTT            ) (           ) \| (   ) )         ) \    #
# | (___) || )   ( || )   ( | Mapper         | |   _ /\___/  /( (___) ) _ /\___/  /    #
# (_______)|/     \||/     \| Client         (_)  (_)\______/  \_____/ (_)\______/     #
#                                                                                      #
########################################################################################
#
# @[00]@| GMA-Mapper 4.36.3
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
# Steve's TCL implementation of a USTAR archive reader.
# version 1.0, 16 July 2020.
# Steve Willoughby <steve@madscience.zone>
#
# Data format:
# 512-byte blocks. First is a header block, followed by
# data blocks, then header block for the next file, etc.
# header blocks are zero-filled to the end.
# numeric fields are in octal ASCII digits unless otherwise
# indicated, may be space-and/or null-filled to the right.
# string fields are null-filled to the right.
# (technically, trailing nulls are supplied for numeric fields
# except for size, mtime, and version, but in our implementation
# we will be as permissive as possible)
# numeric fields may have base256 format if high bit of first char
# is set (not implemented here)
#
# End of archive is two zero-filled blocks
#
#               TAR   USTAR
# Offset Length Field Field Comments
#      0    100 name  name  filename
#    100      8 mode  mode  UNIX mode
#    108      8 uid   uid   UNIX uid 
#    116      8 gid   gid   UNIX gid 
#    124     12 size  size  file size in bytes (0 if link)
#    136     12 mtime mtime file mod time 
#    148      8 chk   chk   header checksum [2]
#    156      1 link  type  file type [1]
#    157    100 lname lname name of linked file
#    257      6 ---   magic "ustar\0"
#    263      2 ---   vers  format version number
#    265     32 ---   uname user name of owner
#    297     32 ---   gname group name of owner
#    319      8 ---   dmaj  device major number
#    327      8 ---   dmin  device minor number
#    335    155 ---   prefx prefix for filename
#    490     22 ---   ---   nulls
#
# [1] file type as ASCII character:
#       TAR USTAR
#       \0   \0    regular file
#        0    0    regular file
#        1    1    link to another file already in this archive
#       ---   2    symbolic link
#       ---   3    character device
#       ---   4    block device
#       ---   5    directory
#       ---   6    FIFO special file
#       ---   7    contiguous file
#       ---   g    global extended header
#       ---   x    extended header with meta data
#       ---  A-Z   custom types
#
# [2] checksum of all bytes in header if the chk field isn't all blanks
#     might be signed but should be unsigned (calculated as if the chk field
#     itself were filled with spaces)

package provide ustar 1.0
package require Tcl 8.5

namespace eval ::ustar {
	namespace export contents format_contents file_contents extract file_extract

	variable nullblock [binary format x512]
}

proc ::ustar::_getblock {stream} {
	set block [read $stream 512]
	if {[string length $block] != 512} {
		error "::ustar::_getblock: unexpected EOF / short read of [string length $block] while reading stream $stream"
	}
	return $block
}

proc ::ustar::_isnull {block} {
	variable nullblock
	return [expr [string compare $block $nullblock] == 0]
}

proc ::ustar::_string {block start len} {
	set data [string range $block $start [expr $start + $len - 1]]
	set null [string first [binary format x] $data]
	if {$null >= 0} {
		set data [string range $data 0 [expr $null - 1]]
	}
	return $data
}

proc ::ustar::_octal {block start len} {
	set data [::ustar::_string $block $start $len]
	if {[scan $data %o odata] != 1} {
		set odata 0
	}
	return $odata
}

#
# _parse_header <stream>
# 	returns list of header fields or {} if reached end
#
proc ::ustar::_parse_header {stream} {
	set block [::ustar::_getblock $stream]
	if {[::ustar::_isnull $block]} {
		set block [::ustar::_getblock $stream]
		if {[::ustar::_isnull $block]} {
			# 
			# this is the end-of-archive marker
			#
			return {}
		}
		error "::ustar::_parse_header: unexpected null header block encountered"
	}

	set name  [::ustar::_string $block   0 100]
	set mode  [::ustar::_octal  $block 100   8]
	set uid   [::ustar::_octal  $block 108   8]
	set gid   [::ustar::_octal  $block 116   8]
	set size  [::ustar::_octal  $block 124  12]
	set mod   [::ustar::_octal  $block 136  12]
	set chk   [::ustar::_octal  $block 148   8]
	set type  [::ustar::_string $block 156   1]
	set lname [::ustar::_string $block 157 100]
	set magic [::ustar::_string $block 257   6]

	set ssum 0
	set usum 0
	set cblock [string replace $block 148 155 "        "]
	binary scan $cblock c* data
	foreach value $data {
		incr ssum $value
		if {$value < 0} {
			incr value 256
		}
		incr usum $value
	}
	if {$usum != $chk && $ssum != $chk} {
		error "::ustar::_parse_header: bad checksum ($chk in header; u=$usum s=$ssum)"
	}
	if {$magic eq {ustar}} {
		set uname [::ustar::_string $block 265  32]
		set gname [::ustar::_string $block 297  32]
		set major [::ustar::_octal  $block 329   8]
		set minor [::ustar::_octal  $block 337   8]
		set prefx [::ustar::_string $block 345 155]
		
		if {$prefx ne {}} {
			set name "${prefx}/${name}"
		}
	} else {
		set uname {}
		set gname {}
		set major 0
		set minor 0
	}
	if {$type eq {g}} {
		error "::ustar::_parse_header: global metadata records not supported."
	}
	if {$type eq {x}} {
		#
		# Extended header format: keywords in following blocks of file, then this affects next file
		#
		set meta_block {}
		set rsize $size
		while {$rsize > 0} {
			append meta_block [::ustar::_getblock $stream]
			incr rsize -512
		}
		set meta_data [encoding convertfrom utf-8 $meta_block]
		#
		# this data is a sequence of (decimal length) (space) (key)=(value)\n...
		#
		array unset meta_values
		set start 0
		while {$size > 0} {
			if {[set space [string first " " $meta_data $start]] < 0
			|| [scan [string range $meta_data $start $space] %d this_length] != 1} {
				error "::ustar::_parse_header: unable to interpret extended header $name ($rsize bytes left to go)"
			}
			set this_value [string range $meta_data $space+1 [expr $start+$this_length-2]]
			if {[string index $meta_data [expr $start+$this_length-1]] != "\n"} {
				error "::ustar::_parse_header: extended header field $this_value for $name not newline-terminated"
			}
			if {[set sep [string first = $this_value]] < 0} {
				error "::ustar::_parse_header: extended header field $this_value for $name has no equals sign"
			}
			set size [expr $size - $this_length]
			incr start $this_length

			set key [string range $this_value 0 $sep-1]
			set val [string range $this_value $sep+1 end]
			switch $key {
				atime -
				mtime -
				ctime {
					if {[scan $val %f meta_values($key)] != 1} {
						error "::ustar::_parse_header: extended header field $this_value for $name: value $val does not appear to be a valid number."
					}
				}
				size -
				uid -
				gid {
					if {[scan $val %lld meta_values($key)] != 1} {
						error "::ustar::_parse_header: extended header field $this_value for $name: value $val does not appear to be a valid integer."
					}
				}
				linkpath -
				path -
				uname -
				gname {
					set meta_values($key) $val
				}
			}
		}
		set actual_header [::ustar::_parse_header $stream]
		if {[llength $actual_header] == 0} {
			error "::ustar::_parse_header: unexpected end of archive after extended attribute header"
		}
		foreach {key idx} {size 0 path 2 uid 4 uname 5 gid 6 gname 7 mtime 8 linkpath 9} {
			if {[info exists meta_values($key)]} {
				set actual_header [lreplace $actual_header $idx $idx $meta_values($key)]
			}
		}

		return [lreplace $actual_header 12 12 [array get meta_values]]
	}
	#              0      1    2     3     4     5     6     7    8     9      10      11  12
	return [list $size $type $name $mode $uid $uname $gid $gname $mod $lname $major $minor {}]
}
#
# ::ustar::contents stream 
# reads TAR archive from <stream>, return list of contents
#
proc ::ustar::contents {stream} {
	set flist {}

	while {true} {
		set header [::ustar::_parse_header $stream]
		if {[llength $header] == 0} {
			break
		}
		lappend flist $header
		set skip_blocks [expr ([lindex $header 0] + 511) / 512]
		while {$skip_blocks > 0} {
			::ustar::_getblock $stream
			incr skip_blocks -1
		}
	}
	return $flist
}

proc ::ustar::file_contents {path} {
	set f [open $path rb]
	set c [::ustar::contents $f]
	close $f
	return $c
}

proc ::ustar::gzip_contents {path} {
	set f [open $path rb]
	zlib push gunzip $f
	set c [::ustar::contents $f]
	close $f
	return $c
}

#
# ::ustar::extract stream callback
# reads the tar archive, invoking "callback {contents-info} {data}" 
# for each file, where contents-info is the same as would be returned
# by the contents function (but for one file), and data is the binary
# data taken from the file.
#
proc ::ustar::extract {stream callback} {
	while {true} {
		set header [::ustar::_parse_header $stream]
		if {[llength $header] == 0} {
			break
		}

		set data_blocks [expr ([lindex $header 0] + 511) / 512]
		set data {}
		while {$data_blocks > 0} {
			append data [::ustar::_getblock $stream]
			incr data_blocks -1
		}
		# truncate to expected length (so we lose the null padding to the end of the last block)
		set data [string range $data 0 [lindex $header 0]-1]
		eval $callback [list $header $data]
	}
}

proc ::ustar::file_extract {path callback} {
	set f [open $path rb]
	::ustar::extract $f $callback
	close $f
}

proc ::ustar::gzip_extract {path callback} {
	set f [open $path rb]
	zlib push gunzip $f
	::ustar::extract $f $callback
	close $f
}

#
# ::ustar::format_contents contents
# reads contents list as returned by ::ustar::contents, returns
# a formatted multi-line string putting the data in human
# readable format.
#
proc ::ustar::format_contents {contents} {
	set output {}
	array set format { 0 d 2 s 4 d 5 s 6 d 7 s 9 s 10 d 11 d }
	array set types  { 0 - \0 - 1 L 2 l 3 c 4 b 5 d 6 f }

	foreach fld [array names format] {
		set length($fld) 0
	}
	set length(1) 4
	set length(3) 10
	set length(8) 28
	# mode: <type>rwxrwxrwx
	#               S  S  T not exec but set/sticky bit
	#               s  s  t is exec

	foreach item $contents {
		foreach fld [array names format] {
			set l [string length [format %$format($fld) [lindex $item $fld]]]
			if {$l > $length($fld)} {
				set length($fld) $l
			}
		}
	}

	set ulen [expr max($length(4), $length(5))]
	set glen [expr max($length(6), $length(7))]
	append output [format "MODE------ %${ulen}.${ulen}s %${ulen}.${ulen}s %${length(0)}.${length(0)}s MODIFIED-------------------- %-${length(2)}.${length(2)}s\n"\
		"USER----------------------------------------"\
		"GROUP---------------------------------------"\
		"SIZE----------------------------------------"\
		"NAME----------------------------------------"]

	foreach item $contents {
		if {[info exists types([lindex $item 1])]} {
			set type $types([lindex $item 1])
		} else {
			set type -
		}
		set mode [lindex $item 3]

		# MODE------ USER GROUP
		# trwxrwxrwx ...  ...
		if {[lindex $item 5] ne {}} {
			set uname [lindex $item 5]
		} else {
			set uname [format %${ulen}d [lindex $item 4]]
		}

		if {[lindex $item 7] ne {}} {
			set gname [lindex $item 7]
		} else {
			set gname [format %${glen}d [lindex $item 6]]
		}

		set name [lindex $item 2]
		if {[lindex $item 9] ne {}} {
			append name " -> [lindex $item 9]"
		}
		if {$type eq {b} || $type eq {c}} {
			append name [format " <%d,%d>" [lindex $item 10] [lindex $item 11]]
		}

		append output [format "%s%s%s%s%s%s%s%s%s%s %-${ulen}s %-${glen}s %${length(0)}d %s %s\n"\
			$type\
			[expr $mode & 0400 ? {{r}} : {{-}}]\
			[expr $mode & 0200 ? {{w}} : {{-}}]\
			[expr $mode & 04000? [expr $mode & 0100 ? {{{s}}} : {{{S}}}] : [expr $mode & 0100 ? {{{x}}} : {{{-}}}]]\
			[expr $mode & 0040 ? {{r}} : {{-}}]\
			[expr $mode & 0020 ? {{w}} : {{-}}]\
			[expr $mode & 02000? [expr $mode & 0010 ? {{{s}}} : {{{S}}}] : [expr $mode & 0010 ? {{{x}}} : {{{-}}}]]\
			[expr $mode & 0004 ? {{r}} : {{-}}]\
			[expr $mode & 0002 ? {{w}} : {{-}}]\
			[expr $mode & 01000? [expr $mode & 0001 ? {{{t}}} : {{{T}}}] : [expr $mode & 0001 ? {{{x}}} : {{{-}}}]]\
			$uname $gname [lindex $item 0] [clock format [expr int([lindex $item 8])]] $name]
	}

	return $output
}
