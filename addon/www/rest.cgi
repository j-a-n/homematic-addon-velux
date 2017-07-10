#!/bin/tclsh

#  HomeMatic addon to control velux windows and shutters
#
#  Copyright (C) 2017  Jan Schneider <oss@janschneider.net>
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

proc process {} {
	global env
	if { [info exists env(QUERY_STRING)] } {
		set query $env(QUERY_STRING)
		set data ""
		if { [info exists env(CONTENT_LENGTH)] } {
			set data [read stdin $env(CONTENT_LENGTH)]
		}
		set path [split $query {/}]
		set plen [expr [llength $path] - 1]
		#error ">${query}< | >${path}< | >${plen}<" "Debug" 500
		if {[lindex $path 1] == "version"} {
			return "\"[velux::version]\""
		} elseif {[lindex $path 1] == "get_channels"} {
			return [velux::get_channels_json]
		} elseif {[lindex $path 1] == "config"} {
			if {$plen == 1} {
				if {$env(REQUEST_METHOD) == "GET"} {
					return [velux::get_config_json]
				}
			} elseif {[lindex $path 2] == "global"} {
				if {$env(REQUEST_METHOD) == "PUT"} {
					regexp {\"short_press_millis\"\s*:\s*\"([^\"]+)\"} $data match short_press_millis
					regexp {\"long_press_millis\"\s*:\s*\"([^\"]+)\"} $data match long_press_millis
					regexp {\"command_pause_millis\"\s*:\s*\"([^\"]+)\"} $data match command_pause_millis
					velux::update_global_config $short_press_millis $long_press_millis $command_pause_millis
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
	if { [info exists $errorCode] } {
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

