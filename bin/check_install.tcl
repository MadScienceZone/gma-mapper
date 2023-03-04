#!/usr/bin/env tclsh
#
# Check the dependencies of the mapper tool to be sure they're installed.
#
source gmautil.tcl
set tcllib {
		The %s package is included in the Tcl Standard Library (tcllib).
		It appears that you are either missing this library or it's incomplete
		or out of date.
		You can get a copy of tcllib from www.tcl.tk (or you can use the 
		copy we have in the dependencies directory of the gma source tree 
		if you have a copy of that too).
}
set tklib {
		The %s package is included in the Standard Tk Library (tklib).
		You can obtain a copy of tklib from www.tcl.tk (or the place you
		got your Tcl interpreter from), or you may install from the copy
		we have in the dependencies directory of the gma source tree if you
		have a copy of that too).
}
foreach {package minimum_version instructions} {
	Tcl 8.6 {
		You need the Tcl interpreter to run the mapper tool on your system.
		You obviously have one, since you're running this script now. However,
		the Tcl version must be at least 8.6, which was released in 2012, so
		your version of Tcl is seriously out of date and should be upgraded anyway.
	}
	Tk 8.6 {
		You need the Tk library along with your Tcl installation in order to get
		the graphical user interface to work. It is possible to have Tcl installed
		without Tk, and it may be that is how your system is configured. It is also
		possible that you have a version of Tk that doesn't match the Tcl version,
		or that your Tcl is misconfigued so that it can't find its Tk library.
	}
	base64 2.4.2 tcl
	getstring 0 tk
	inifile 0 tcl
	json 1.3.3 tcl
	json::write 1.0.3 tcl
	md5 2.0.7 tcl
	pki 0.6 tcl
	sha256 0 tcl
	struct::queue 0 tcl
	tooltip 0 tk
	uuid 1.0.1 tcl
} {
	if {$instructions eq {tcl}} {
		set instructions $tcllib
	} elseif {$instructions eq {tk}} {
		set instructions $tklib
	}
	if {[catch {set installed_version [package require $package]} err]} {
		puts "It appears you are missing $package ($err)"
		puts [format $instructions $package]
		continue
	}
	set cmp [::gmautil::version_compare $installed_version $minimum_version]
	if {$cmp == 0 || $minimum_version == 0} {
		puts "Congratulations, you have $package version $installed_version installed."
	} elseif {$cmp < 0} {
		puts "Your installed version of $package is $installed_version, but we require at least version $minimum_version."
		puts [format $instructions $package]
	} else {
		puts "Congratulations, you have $package version $installed_version installed ($minimum_version or later required)."
	}
}
destroy .
