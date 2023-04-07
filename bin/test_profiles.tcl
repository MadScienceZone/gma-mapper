source gmaprofile.tcl
source gmautil.tcl

set animatePlacement 0
set ButtonSize small
set dark_mode 1
set ImageFormat png
set GuideLines 0
set GuideLineOffset {0 0}
set MajorGuideLines 0
set MajorGuideLineOffset {0 0}
set MasterClient 1
set OptPreload 1
set DEBUG_level 0
set debug_protocol_enabled false	;# TODO no variable for this; use ::gmaproto::set_debug ::DEBUGp if enabled
set CURLpath /usr/local/bin/curl
# TODO LoadCustomStyle <file>
#
# per-profile settins
#
set blur_all 0
set blur_pct 0
set IThost {}
set ITpassword {}
set ITport 2323
set ModuleID {}
set SuppressChat 1
set ChatTranscript {}
set ChatHistoryLimit 0
set local_user {}
set CURLproxy {}
set CURLserver {}
set UpdateURL {}
# gm only
set SCPproxy {}
set SERVER_MKDIRpath {}
set NCpath {}
set SCPpath {}
set SCPdest {}
set SCPserver {}
set SSHpath {}


puts [::gmaprofile::editor .profiles [dict create \
	animate      $animatePlacement \
	button_size  $ButtonSize \
	curl_path    $CURLpath \
	dark         $dark_mode \
	debug_level  $DEBUG_level \
	debug_proto  $debug_protocol_enabled \
	guide_lines  [dict create major [dict create interval $MajorGuideLines offsets $MajorGuideLineOffset] \
	                          minor [dict create interval $GuideLines offsets $GuideLineOffset] \
		     ] \
	image_format $ImageFormat \
	keep_tools   $MasterClient \
	preload      $OptPreload \
	profiles [dict create \
		_default [dict create \
			blur_all      $blur_all \
			blur_pct      $blur_pct \
			chat_log      $ChatTranscript \
			chat_limit    $ChatHistoryLimit \
			host          $IThost \
			port          $ITport \
			username      $local_user \
			password      $ITpassword \
			module_id     $ModuleID \
			suppress_chat $SuppressChat \
			curl_proxy    $CURLproxy \
			curl_server   $CURLserver \
			update_url    $UpdateURL \
			scp_proxy     $SCPproxy \
			server_mkdir  $SERVER_MKDIRpath \
			nc_path       $NCpath \
			scp_path      $SCPpath \
			scp_dest      $SCPdest \
			scp_server    $SCPserver \
			ssh_path      $SSHpath \
		]\
	]\
]]
# TODO update mapper state based on returned dict (may require restart)
#
# LoadDefaultStyles
# 	display_styles
# 	dark_mode
# 	default_style_cfg
#
# 	LoadCustomStyle $default_style_cfg
# 		
# 	default_styles [default_style_data]
# 	move each kv from default_styles to display_styles(k), setting all font_* keys to display_styles(default_font)
# 	
