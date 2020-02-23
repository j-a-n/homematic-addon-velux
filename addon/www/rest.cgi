#!/bin/tclsh

#  HomeMatic addon to control velux windows and shutters
#
#  Copyright (C) 2020  Jan Schneider <oss@janschneider.net>
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

source /usr/local/addons/velux/lib/velux.tcl
package require http

proc json_string {str} {
	set replace_map {
		"\"" "\\\""
		"\\" "\\\\"
		"\b"  "\\b"
		"\f"  "\\f"
		"\n"  "\\n"
		"\r"  "\\r"
		"\t"  "\\t"
	}
	return "[string map $replace_map $str]"
}

proc get_http_header {request header_name} {
	upvar $request req
	set header_name [string toupper $header_name]
	array set meta $req(meta)
	foreach header [array names meta] {
		if {$header_name == [string toupper $header] } then {
			return $meta($header)
		}
	}
	return ""
}

proc get_session {sid} {
	if {[regexp {@([0-9a-zA-Z]{10})@} $sid match sidnr]} {
		return [lindex [rega_script "Write(system.GetSessionVarStr('$sidnr'));"] 1]
	}
	return ""
}

proc check_session {sid} {
	if {[get_session $sid] != ""} {
		# check and renew session
		set url "http://127.0.0.1/pages/index.htm?sid=$sid"
		set request [::http::geturl $url]
		set code [::http::code $request]
		::http::cleanup $request
		if {[lindex $code 1] == 200} {
			return 1
		}
	}
	return 0
}

proc login {username password} {
	set request [::http::geturl "http://127.0.0.1/login.htm" -query [::http::formatQuery tbUsername $username tbPassword $password]]
	set code [::http::code $request]
	set location [get_http_header $request "location"]
	::http::cleanup $request
	
	if {[string first "error" $location] != -1} {
		error "Invalid username oder password" "Unauthorized" 401
	}
	
	if {![regexp {sid=@([0-9a-zA-Z]{10})@} $location match sid]} {
		error "Too many sessions" "Service Unavailable" 503
	}
	return $sid
}

proc process {} {
	global env
	if { [info exists env(QUERY_STRING)] } {
		set query $env(QUERY_STRING)
		set path ""
		set sid ""
		set pairs [split $query "&"]
		foreach pair $pairs {
			if {[regexp "^(\[^=\]+)=(.*)$" $pair match varname value]} {
				if {$varname == "sid"} {
					set sid $value
				} elseif {$varname == "path"} {
					set path [split $value "/"]
				}
			}
		}
		set plen [expr [llength $path] - 1]
		
		
		if {[lindex $path 1] == "login"} {
			set data [read stdin $env(CONTENT_LENGTH)]
			regexp {\"username\"\s*:\s*\"([^\"]*)\"} $data match username
			regexp {\"password\"\s*:\s*\"([^\"]*)\"} $data match password
			set sid [login $username $password]
			return "\"${sid}\""
		}
		
		if {![check_session $sid]} {
			error "Invalid session" "Unauthorized" 401
		}
		
		set data ""
		if { [info exists env(CONTENT_LENGTH)] } {
			set data [read stdin $env(CONTENT_LENGTH)]
		}
		
		if {[lindex $path 1] == "get_session"} {
			return "\"[get_session $sid]\""
		} elseif {[lindex $path 1] == "version"} {
			return "\"[velux::version]\""
		} elseif {[lindex $path 1] == "get_channels"} {
			return [velux::get_channels_json]
		} elseif {[lindex $path 1] == "send_command"} {
			regexp {\"window_id\"\s*:\s*\"([^\"]+)\"} $data match window_id
			regexp {\"object\"\s*:\s*\"([^\"]+)\"} $data match object
			regexp {\"command\"\s*:\s*\"([^\"]+)\"} $data match command
			velux::acquire_window $window_id $object
			velux::send_command $window_id $object $command
			velux::release_window $window_id $object
			return "\"ok\""
		} elseif {[lindex $path 1] == "config"} {
			if {$plen == 1} {
				if {$env(REQUEST_METHOD) == "GET"} {
					return [velux::get_config_json]
				}
			} elseif {[lindex $path 2] == "global"} {
				if {$env(REQUEST_METHOD) == "PUT"} {
					regexp {\"log_level\"\s*:\s*\"([^\"]+)\"} $data match log_level
					regexp {\"short_press_millis\"\s*:\s*\"([^\"]+)\"} $data match short_press_millis
					regexp {\"long_press_millis\"\s*:\s*\"([^\"]+)\"} $data match long_press_millis
					regexp {\"command_pause_millis\"\s*:\s*\"([^\"]+)\"} $data match command_pause_millis
					velux::update_global_config $log_level $short_press_millis $long_press_millis $command_pause_millis
					return "\"Global config successfully updated\""
				}
			} elseif {[lindex $path 2] == "window"} {
				if {$plen == 3} {
					if {$env(REQUEST_METHOD) == "PUT"} {
						set id [lindex $path 3]
						#error "${data}" "Debug" 500
						regexp {\"name\"\s*:\s*\"([^\"]+)\"} $data match name
						regexp {\"window_channel\"\s*:\s*\"([^\"]+)\"} $data match window_channel
						regexp {\"window_up_channel\"\s*:\s*\"([^\"]+)\"} $data match window_up_channel
						regexp {\"window_down_channel\"\s*:\s*\"([^\"]+)\"} $data match window_down_channel
						regexp {\"window_motion_seconds\"\s*:\s*\"([^\"]+)\"} $data match window_motion_seconds
						regexp {\"window_reed_channel\"\s*:\s*\"([^\"]+)\"} $data match window_reed_channel
						regexp {\"shutter_channel\"\s*:\s*\"([^\"]+)\"} $data match shutter_channel
						regexp {\"shutter_up_channel\"\s*:\s*\"([^\"]+)\"} $data match shutter_up_channel
						regexp {\"shutter_down_channel\"\s*:\s*\"([^\"]+)\"} $data match shutter_down_channel
						regexp {\"shutter_motion_seconds\"\s*:\s*\"([^\"]+)\"} $data match shutter_motion_seconds
						if { ![info exists window_channel ] } { set window_channel "" }
						if { ![info exists window_up_channel ] } { set window_up_channel "" }
						if { ![info exists window_down_channel ] } { set window_down_channel "" }
						if { ![info exists window_motion_seconds ] } { set window_motion_seconds "" }
						if { ![info exists window_reed_channel ] } { set window_reed_channel "" }
						if { ![info exists shutter_channel ] } { set shutter_channel "" }
						if { ![info exists shutter_up_channel ] } { set shutter_up_channel "" }
						if { ![info exists shutter_down_channel ] } { set shutter_down_channel "" }
						if { ![info exists shutter_motion_seconds ] } { set shutter_motion_seconds "" }
						velux::create_window $id $name $window_channel $window_up_channel $window_down_channel $window_motion_seconds $window_reed_channel $shutter_channel $shutter_up_channel $shutter_down_channel $shutter_motion_seconds
						return "\"Window ${id} successfully created\""
					} elseif {$env(REQUEST_METHOD) == "DELETE"} {
						set id [lindex $path 3]
						velux::delete_window $id
						return "\"Window ${id} successfully deleted\""
					}
				}
			}
		}
	}
	error "invalid request" "Not found" 404
}

if [catch {process} result] {
	set status 500
	if { [regexp {^\d+$} $errorCode ] } {
		set status $errorCode
	}
	puts "Content-Type: application/json"
	puts "Status: $status";
	puts ""
	set result [json_string $result]
	puts -nonewline "\{\"error\":\"${result}\"\}"
} else {
	puts "Content-Type: application/json"
	puts "Status: 200 OK";
	puts ""
	puts -nonewline $result
}

