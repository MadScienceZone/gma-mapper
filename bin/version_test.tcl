source gmautil.tcl
foreach {x y} {
	1.2 1.2.3
	1.2.3-alpha 1.2.3
	1.2.3 1.2.3-alpha
	1.2-alpha 1.2-beta
	1.2-beta 1.2-alpha
	1.2+foo-alpha.3 1.2+bar-alpha.4
} {
	puts "$x : $y -> [::gmautil::version_compare $x $y]"
}
