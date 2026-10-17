#!/usr/bin/env tclsh
puts "Running unit tests for GMA protocol code (such as they are so far)"
source gmaproto.tcl

set ran 0
set passed 0
foreach {srcdict expected} {
	{foo bar}
	{foo bar s {} i 0 o {} ReceivedTime {} SentTime {}}
} {
	incr ran
	if {[set actual [::gmaproto::_construct $srcdict $::gmaproto::_message_payload(ECHO)]] ne $expected} {
		puts "Test failed: _construct $srcdict -> $actual (expected $expected)"
	} else {
		puts -nonewline .
		incr passed
	}
}

foreach {srcjson expected} {
	{PROTOCOL 42}
		{PROTOCOL 42}
	{//this is a comment}
		{// {//this is a comment}}
	{ECHO {"foo":"bar"}}
		{ECHO {foo bar s {} i 0 o {} ReceivedTime {} SentTime {}}}
	{DD {"For":"spam","Presets":null}}
		{DD {For spam Presets {} Global false}}
	{DD {"For":"spam","Presets":[]}}
		{DD {For spam Presets {} Global false}}
	{DD {"For":"spam","Presets":[{"Name":"p1"},{"Name":"p2","Description":"d2"}]}}
		{DD {For spam Presets {{Name p1 Description {} DieRollSpec {}} {Name p2 Description d2 DieRollSpec {}}} Global false}}
	{PS {}}
		{PS {ID {} Name {} Health {} Gx 0.0 Gy 0.0 Skin 0 SkinSize {} PolyGM false Elev 0 Color {} Note {} Size {} DispSize {} StatusList {} AoE {} MoveMode 0 Reach 0 Killed false Dim false CreatureType 0 Hidden false CustomReach {} Targets {} TargetedModifiers {}}}
	{PS {"Health":null,"AoE":null,"CustomReach":null}}
		{PS {Health {} AoE {} CustomReach {} ID {} Name {} Gx 0.0 Gy 0.0 Skin 0 SkinSize {} PolyGM false Elev 0 Color {} Note {} Size {} DispSize {} StatusList {} MoveMode 0 Reach 0 Killed false Dim false CreatureType 0 Hidden false Targets {} TargetedModifiers {}}}
	{PS {"Health":null,"AoE":{"Radius":1.23},"CustomReach":null}}
		{PS {Health {} AoE {Radius 1.23 Color {}} CustomReach {} ID {} Name {} Gx 0.0 Gy 0.0 Skin 0 SkinSize {} PolyGM false Elev 0 Color {} Note {} Size {} DispSize {} StatusList {} MoveMode 0 Reach 0 Killed false Dim false CreatureType 0 Hidden false Targets {} TargetedModifiers {}}}
	{OA {"ObjID":"@foo","NewAttrs":{"Health":null}}}
		{OA {ObjID @foo NewAttrs {Health {}}}}
	{OA {"ObjID":"@foo","NewAttrs":null}}
		{OA {ObjID @foo NewAttrs {}}}
	{OA+ {"ObjID":"123456xyz","AttrName":"myattr","Values":null}}
		{OA+ {ObjID 123456xyz AttrName myattr Values {}}}
	{OA+ {"ObjID":"123456xyz","AttrName":"myattr","Values":[]}}
		{OA+ {ObjID 123456xyz AttrName myattr Values {}}}
	{OA+ {"ObjID":"123456xyz","AttrName":"myattr","Values":["a","b"]}}
		{OA+ {ObjID 123456xyz AttrName myattr Values {a b}}}
} {
	incr ran
	if {[set actual [::gmaproto::_parse_data_packet $srcjson]] ne $expected} {
		puts "Test failed: _parse_data_packet $srcjson -> $actual (expected $expected)"
	} else {
		puts -nonewline .
		incr passed
	}
}

foreach {src n u b s} {
	hello          ⊘hello          ⊚hello                ⊛aGVsbG8=             ⊜hello
	data;f1;f2|opt ⊘data;f1;f2|opt ⊚data%3Bf1%3Bf2%7Copt ⊛ZGF0YTtmMTtmMnxvcHQ= ⊜data@/f1@/f2@!opt
	{a;b c=d}      {⊘a;b c=d}      ⊚a%3Bb+c%3Dd          ⊛YTtiIGM9ZA==         ⊜a@/b@+c=d
} {
	foreach {enc expected} [list none $n url $u base64 $b simple $s] {
		incr ran
		if {[set actual [::gmaproto::subfield_encode $src $enc]] ne $expected} {
			puts "Test failed: subfield_encode $src ($enc) -> $actual (expected $expected)"
		} else {
			if {[set actual [::gmaproto::subfield_decode $expected]] ne $src} {
			puts "Test failed: subfield_decode $expected ($enc) -> $actual (expected $src)"
			} else {
				puts -nonewline .
				incr passed
			}
		}
	}
}


puts {}
puts [format "Tests run: %3d" $ran]
puts [format "Passed:    %3d" $passed]
puts [format "Failed:    %3d" [expr $ran - $passed]]
