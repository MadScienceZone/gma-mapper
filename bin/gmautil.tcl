########################################################################################
#  _______  _______  _______                ___       _______                          #
# (  ____ \(       )(  ___  ) Game         /   )     / ___   )                         #
# | (    \/| () () || (   ) | Master's    / /) |     \/   )  |                         #
# | |      | || || || (___) | Assistant  / (_) (_        /   )                         #
# | | ____ | |(_)| ||  ___  |           (____   _)     _/   /                          #
# | | \_  )| |   | || (   ) |                ) (      /   _/                           #
# | (___) || )   ( || )   ( | Mapper         | |   _ (   (__/\                         #
# (_______)|/     \||/     \| Client         (_)  (_)\_______/                         #
#                                                                                      #
########################################################################################
# version 1.0, 17 July 2020.
# Steve Willoughby <steve@madscience.zone>
#
# @[00]@| GMA 5.1
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
#
# General utility functions

package provide gmautil 1.1
package require Tcl 8.6
package require sha256

namespace eval ::gmautil {
	namespace export is_git verify version_compare upgrade

	variable public_key {
-----BEGIN PUBLIC KEY-----
MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAljm0271r46IM1W3KsNko
Koq++ysns6Gnp5nZLGLqzuhV8ifF3uml12nfO3UPS6vEzD5j//j0iEmchQEeHzuy
jZUDyox4fM4lJ5oQBw2/UU3RBtoR3t/HlyULKvfJf46TRKehKcuTJYqC4FXn7CzS
77OXka2Z/0flwGN/iGFZoG3hH77bLhu5i61hSx4NkTPd0gWfVcNOUI8pbQHngV0x
dwsnoRkiKTnwyPolQn43eUKP/ErM3QmkUdztsRdGoMdC6ukLDXCXOBEVnu4VJCQ+
i/2iUa06anlVPcOy/HrUra/0+KUdXHn/zu9IaD9z6Ll5XRoujSGKVcEiPeZFiPd1
tgvsz1eZiN6wTKqxqU43LG7eNGO2ggaoLtF2ABOpC/91wtQ1/8px5qvenQIBJAqR
PJ7+Af7eyUcQ3neske8I/PfphutOXP0Zj5ypNXDiSxw2qJ3u8erXmRZ4Ph0c9c9m
6KL3+9KYYoQ4nQ/CiBwjf6GKMz3NEXQQF9IMtbAcKEp2lRtVNZ/AyFficx6W3GRk
Z0bSBVrgel+iZQjjKJ2osOoyhAQQp/P5RQQPupgmxkvndc/9gWYE6JX1YJUXCOqL
U64greY1BqGzvJuY4UzIy+1/+4ZPjhYzxBwkbrsW6dZNvsq8zQyK+KxLQiueGzKI
7dPxqfF/kEZTWVPJMOX07OUCAwEAAQ==
-----END PUBLIC KEY-----
}

	variable checklist
}
if {[catch {package require pki 0.10}]} {
	package require pki 0.6
	proc ::gmautil::_parse_public_key {k} {
		# from 0.10 version of pki package
		array set parsed_key [::pki::_parse_pem $k "-----BEGIN PUBLIC KEY-----" "-----END PUBLIC KEY-----" ""]
		set key_seq $parsed_key(data)
		::asn::asnGetSequence key_seq pubkeyinfo
		::asn::asnGetSequence pubkeyinfo pubkey_algoid
		::asn::asnGetObjectIdentifier pubkey_algoid oid
		::asn::asnGetBitString pubkeyinfo pubkey
		set ret(pubkey_algo) [::pki::_oid_number_to_name $oid]

		switch -- $ret(pubkey_algo) {
			"rsaEncryption" {
				set pubkey [binary format B* $pubkey]

				::asn::asnGetSequence pubkey pubkey_parts
				::asn::asnGetBigInteger pubkey_parts ret(n)
				::asn::asnGetBigInteger pubkey_parts ret(e)

				set ret(n) [::math::bignum::tostr $ret(n)]
				set ret(e) [::math::bignum::tostr $ret(e)]
				set ret(l) [expr {int([::pki::_bits $ret(n)] / 8.0000 + 0.5) * 8}]
				set ret(type) rsa
			}
			default {
				error "Unknown algorithm"
			}
		}

		return [array get ret]
	}
} else {
	proc ::gmautil::_parse_public_key {k} {
		return [::pki::pkcs::parse_public_key $k]
	}
}

#
# ::gmautil::is_git path
# returns true if <path> is a directory which is inside a Git working tree
#
proc ::gmautil::is_git {path} {
	if {$::tcl_platform(os) eq "Windows NT"} {
		set nulldev NUL
	} else {
		set nulldev /dev/null
	}
	set olddir [pwd]
	set result true
	cd $path
	if {[catch {exec -ignorestderr git rev-parse --is-inside-work-tree <$nulldev >&$nulldev}]} {
		# we end up here if there is no Git installed (or we can't reach it in our PATH),
		# (i.e., the git rev-parse command failed to even run)
		# or if the directory isn't in a git working tree (i.e., the command returned an error)
		set result false
	}
	cd $olddir
	return $result
}

#
# ::gmautil::verify data signature
# returns true if the binary <data> matches the cryptographic
# signature <signature> using our built-in public signing key.
#
#
proc ::gmautil::verify {data signature} {
	variable public_key

	#set key [::pki::pkcs::parse_public_key $public_key]
	set key [::gmautil::_parse_public_key $public_key]
	return [::pki::verify $signature $data $key]
}

#
# compare two version numbers
# return -1 if v1 < v2; +1 if v1 > v2; 0 if v1 == v2
#
proc ::gmautil::version_compare {v1 v2} {
	if {$v1 eq $v2} {
		return 0
	}
	if {![regexp {^([^+-]+)([^-]+)?(?:-(.+))?$} $v1 _ v1base v1build v1pre]} {
		error "version $v1 does not conform to semver standard"
	}
	if {![regexp {^([^+-]+)([^-]+)?(?:-(.+))?$} $v2 _ v2base v2build v2pre]} {
		error "version $v2 does not conform to semver standard"
	}
	set cmp [::gmautil::_vc $v1base $v2base]
	if {$cmp == 0} {
		# the base versions are the same. In this case the one without a prerelease
		# string is older, or we just compare prerelease strings
		if {$v1pre eq {} && $v2pre eq {}} {
			return 0
		}
		if {$v1pre eq {}} {
			return 1
		}
		if {$v2pre eq {}} {
			return -1
		}
		return [::gmautil::_vc $v1pre $v2pre]
	}
	return $cmp
}

proc ::gmautil::_vc {v1 v2} {
	set l1 [split $v1 .]
	set l2 [split $v2 .]
	while {[llength $l2] != [llength $l1]} {
		if {[llength $l2] < [llength $l1]} {
			lappend l2 0
		} else {
			lappend l1 0
		}
	}

	for {set i 0} {$i < [llength $l1]} {incr i} {
		if {[lindex $l1 $i] != [lindex $l2 $i]} {
			if {[lindex $l1 $i] < [lindex $l2 $i]} {
				return -1
			}
			return 1
		}
	}
	return 0
}

if {[::gmautil::version_compare $::tcl_version 8.7] >= 0} {
    proc ::gmautil::lpop {var args} {
	upvar 1 $var l
        return [::lpop l {*}$args]
    }
} else {
    proc ::gmautil::lpop {var index} {
        # pop indexth element from list
        # unlike the built-in one from tcl 8.7, we don't currently
        # consider sublists.
        upvar 1 $var l
        set removed [lindex $l $index]
        set l [lreplace $l $index $index]
        return $removed
    }
}

#
# ::gmautil::upgrade
#	fetch, verify, and install an updated version of a program.
#	Stages files first in tmp directory then moves them into place.
#
# 	destination_dir_list
#		list of directories up to top-level install point, e.g.
#		{/ opt games gma mapper <version>}
#		We will install into this with subdirectories like bin, lib, etc.
#
#	tmp_path
#		path to directory where we can stage files temporarily
#
#	source_base_url
#	source_base_file
#		We will download the new file from 
#		<source_base_url>/<source_base_file>.tar.gz and
#		<source_base_url>/<source_base_file>.tar.gz.sig
#
#	old_version
#	new_version
#		Old and new version numbers for the application.
#
#	strip_prefix
#		remove this string (including if prefixed with ./) from the 
#		start of each file extracted from the tar file.
#
#	launch
#		when the installation is done, execute this path relative
#		to the installation directory.
#
#	msg_callback
#		called with a message string to update the user on progress.
#
# 	curl_proxy
#	curl_path
#		path to programs for downloading sources from the server
#
# __checksums__ file at the root of the tar file is read to
# verify the integrity of files after extraction
#
proc ::gmautil::upgrade {destination_dir_list tmp_path source_base_url source_base_file old_version new_version strip_prefix launch msg_callback curl_proxy curl_path} {
	variable checklist

	array unset checklist
	set msg_pfx "Upgrade from $old_version to $new_version:"
	$msg_callback "Beginning upgrade from version $old_version to $new_version..."
	#puts "dest ($destination_dir_list) tmp ($tmp_path) url ($source_base_url) file ($source_base_file) old ($old_version) new ($new_version) pfx ($strip_prefix) launch ($launch) msg ($msg_callback) proxy ($curl_proxy) curl ($curl_path)"

	if {[set comp [::gmautil::version_compare $old_version $new_version]] == 0} {
		tk_messageBox -type ok -icon error -title "Version Numbers are Equal" \
			-message "You appear to be trying to upgrade to the same version you are running now. That doesn't make sense."
		return
	}
	if {$comp > 0} {
		if {[tk_messageBox -type yesno -icon question -title "Downgrade to $new_version?" \
			-message "If you proceed, you will DOWNGRADE the version of this program. Are you sure?" \
			-detail "You are currently running version $old_version, but are trying to install $new_version, which is older. Please make sure you really want to do this before continuing."] ne {yes}} {
			tk_messageBox -type ok -icon error -title "Cancelled" -message "Installation cancelled."
			return
		}
	}

	$msg_callback "$msg_pfx preparing directories..."
	#
	# Ensure target dir is created and empty
	# Ensure that temp directory is created
	#
	if {[catch {
		set destination_dir [file join {*}$destination_dir_list]
		if {[file exists $destination_dir]} {
			if {![file isdirectory $destination_dir]} {
				tk_messageBox -type ok -icon error -title "Destination directory conflict" \
					-message "There is an obstruction in the way of the installation. Cannot proceed."\
					-detail "$destination_dir exists but is not a directory. Please resolve this and try again."
				return
			}
			if {[tk_messageBox -type yesno -icon warning -title "Destination directory exists" \
				-message "The destination directory already exists. Are you sure you wish to overwrite it?" \
				-detail "In order to install into $destination_dir, its existing contents will be overwritten. Do not continue unless you are SURE this is the correct action to take."] ne {yes}} {
				tk_messageBox -type ok -icon info -title "Installation Cancelled" \
					-message "Installation cancelled."
				return
			}
		} else {
			file mkdir $destination_dir
		}

		file mkdir $tmp_path

		$msg_callback "$msg_pfx downloading $new_version from $source_base_url..."
		foreach suffix {tar.gz tar.gz.sig} {
			if [catch {
				if {$curl_proxy ne {}} {
					exec -ignorestderr $curl_path --output [file nativename [file join $tmp_path "${source_base_file}.${suffix}"]] --proxy $curl_proxy -f "${source_base_url}/${source_base_file}.${suffix}"
				} else {
					exec -ignorestderr $curl_path --output [file nativename [file join $tmp_path "${source_base_file}.${suffix}"]] -f "${source_base_url}/${source_base_file}.${suffix}"
				}
			} err options] {
				set i [dict get $options -errorcode]
				if {[llength $i] >= 3 && [lindex $i 0] eq {CHILDSTATUS} && [lindex $i 2] == 22} {
					tk_messageBox -type ok -icon error -title "File not found" \
						-message "We did not find the installation file on the server." \
						-detail "We tried to download $source_base_url/$source_base_file.$suffix from $source_base_url but the server indicated that file does not exist."
					return
				} else {
					tk_messageBox -type ok -icon error -title "File download error" \
						-message "Error downloading file from sever."\
						-detail "We tried to download $source_base_url/$source_base_file.$suffix from $source_base_url but an error occurred: $err"
					return
				}
			}
		}

		$msg_callback "$msg_pfx verifying integrity and authenticity of downloaded file..."
		set source_file_path [file join $tmp_path "${source_base_file}.tar.gz"]
		set source_sig_path  [file join $tmp_path "${source_base_file}.tar.gz.sig"]
		set source_file [open $source_file_path rb]
		set source_sig  [open $source_sig_path  rb]
		set source_data [read $source_file]
		set sig_data    [read $source_sig]
		close $source_file
		close $source_sig

		if {![::gmautil::verify $source_data $sig_data]} {
			tk_messageBox -type ok -icon error -title "File integrity error" \
				-message "The downloaded file does not appear to be genuine or is corrupt."\
				-detail "The file downloaded from the server failed cryptographic signature check. We will not install it. Try again later or check with your GM or system administrator."
			return
		}

		$msg_callback "$msg_pfx unpacking files..."
		::ustar::gzip_extract $source_file_path "::gmautil::_install_file [list $destination_dir_list $strip_prefix ${msg_callback} ${msg_pfx}]"

		$msg_callback "$msg_pfx checking file integrity..."
		foreach key [array names checklist :stat:*] {
			set path [string range $key 6 end]
			$msg_callback "$msg_pfx checking file integrity for $path"
			if {$checklist($key) != 1} {
				$msg_callback "$msg_pfx checking file integrity for $path: FAILED: not unpacked"
				tk_messageBox -type ok -icon error -title "File not unpacked" \
					-message "We did not successfully unpack $path." \
					-detail "Since we were not able to confirm that this file was unpacked from the download, we can't proceed with the installation."
				return
			}
			if {![info exists checklist(:hash:$path)]} {
				$msg_callback "$msg_pfx checking file integrity for $path: FAILED: not in manifest"
				tk_messageBox -type ok -icon error -title "File not in manifest" \
					-message "We did not find $path in the manifest list." \
					-detail "This file was unpacked from the server download but does not appear in the manifest list of files that are supposed to be there. Since we were not able to confirm that this file was unpacked correctly from the download, we can't proceed with the installation."
				return
			}
			set actual_digest [::sha2::sha256 -hex -file $checklist(:path:$path)]
			if {[string compare -nocase $actual_digest $checklist(:hash:$path)] != 0} {
				$msg_callback "$msg_pfx checking file integrity for $path: FAILED: checksum $actual_digest != expected $checklist(:hash:$path)"
				tk_messageBox -type ok -icon error -title "Corrupt file" \
					-message "The installed file $checklist(:path:$path) failed its integrity check."\
					-detail "This file was unpacked but the data did not match what was expected. We cannot proceed with installation. (Expected checksum $checklist(:hash:$path); actual checksum $actual_digest.)"
				return
			}
		}

		$msg_callback "$msg_pfx cleaning up..."
		file delete -- $source_file_path $source_sig_path
	} err]} {
		tk_messageBox -type ok -icon error -title "Installation error" \
			-message "An error was encountered while trying to perform the upgrade."\
			-detail $err
		return
	}

	if {$launch ne {}} {
		global ::argv

		set exec_path [file join {*}$destination_dir_list $launch]
		$msg_callback "$msg_pfx launching $new_version from $exec_path..."
		tk_messageBox -type ok -icon info -title "Installation Complete" \
			-message "We are about to attempt to launch version $new_version now. If this doesn't work, quit this program and run the new one from $exec_path." \
			-detail "The complete command will be $exec_path $::argv"

		if [catch {exec $exec_path {*}$::argv --upgrade-notice &} err1] {
			if [catch {exec wish $exec_path {*}$::argv --upgrade-notice &} err2] {
				tk_messageBox -type ok -icon error -title "Unable to Launch Automatically" \
					-message "We were unable to start the new mapper. Please exit this one and run $exec_path to use the new version."\
					-detail "We tried to start the new mapper twice. The first time we encountered the error $err1; the second time the result was $err2."
				return
			}
		}
				
		$msg_callback "$msg_pfx Exiting in 5 seconds"
		after 1000 [list ::gmautil::_countdown 4 $msg_callback $msg_pfx]
	}
}

proc ::gmautil::_install_file {destination_dir_list prefix callback pfx header data} {
	variable checklist

	set new_file [lindex $header 2]
	if {$new_file eq {__checksums__} 
	|| $new_file eq {./__checksums__}
	|| $new_file eq "$prefix/__checksums__"
	|| $new_file eq "./$prefix/__checksums__"
	} {
		$callback "$pfx reading manifest"
		foreach check_line [split $data \n] {
			if {[regexp {^\s*([0-9a-fA-F]+)\s*([ *?^])(.*)$} $check_line _ checksum type path]} {
				set checklist(:hash:$path) $checksum
				set checklist(:type:$path) $type
			} else {
				$callback "$pfx WARNING: unrecognized entry $check_line in checksums file"
			}
		}
		return
	}

	if {$prefix ne {}} {
		foreach p [list $prefix "./$prefix"] {
			if {[string compare -length [string length $p] $p $new_file] == 0} {
				set new_file [string range $new_file [string length $p] end]
				break
			}
		}
	}
	if {[string range $new_file 0 0] eq "/"} {
		set new_file ".$new_file"
	}
	set new_path [file join {*}$destination_dir_list $new_file]
	set key $new_file
	if {[lindex $header 1] == 5} {
		$callback "$pfx creating directory $new_path"
		file mkdir $new_path
	} else {
		set checklist(:stat:$key) 0
		set checklist(:path:$key) $new_path
		$callback "$pfx unpacking $new_path"
		set f [open $new_path wb]
		puts -nonewline $f $data
		close $f 
		# set file mode where supported, ignore if the OS doesn't support that
		catch {file attributes $new_path -permissions [lindex $header 3]}
		set checklist(:stat:$key) 1
	}
}

proc ::gmautil::_countdown {sec cb pfx} {
	if {$sec <= 0} {
		$cb "$pfx Exiting now"
		exit 0
	}
	if {$sec < 2} {
		$cb "$pfx Exiting in $sec second"
	} else {
		$cb "$pfx Exiting in $sec seconds"
	}
	after 1000 [list ::gmautil::_countdown [expr $sec - 1] $cb $pfx]
}

proc ::gmautil::rdist {minargs maxargs cmd arglist args} {
    if {[llength $arglist] < $minargs} {
        error "$cmd has only [llength $arglist] parameters but $minargs are required ($arglist)"
    }
    if {[llength $arglist] > $maxargs} {
        error "$cmd has [llength $arglist] parameters but only up to $maxargs are allowed ($arglist)"
    }
    for {set i 0} {$i < [llength $args]} {incr i} {
        upvar 1 [lindex $args $i] v
        if {$i < [llength $arglist]} {
            set v [lindex $arglist $i]
        } else {
            set v {}
        }
    }
}

# we standardize these values as:
#   linux, freebsd, darwin, windows
#   amd64
proc ::gmautil::my_os {} {
    switch $::tcl_platform(os) {
        Darwin  { return darwin }
        Linux   { return linux }
        FreeBSD { return freebsd }
    }
    return $::tcl_platform(os)
}

proc ::gmautil::my_arch {} {
    switch $::tcl_platform(machine) {
        x86_64  { return amd64 }
    }
    return $::tcl_platform(machine)
}

# export the keys of a dictionary to local variables 
# if a key has space-separated words, it is treated as a list of sub-keys.
proc ::gmautil::dassign {dictval args} {
    foreach {k var} $args {
        upvar 1 $var v
        set v [dict get $dictval {*}$k]
    }
}

