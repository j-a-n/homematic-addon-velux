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
#
#
#                                  +---------+
#                                  |         |
#                                  | 7803SRC |
#                                  |         |
#                                  |         |       Velux remote control 3UR B01, 946949, 860963 or KLI 110
#                                  +---------+               +----------------------------------+
#       protect. diode (optional)   |   |   |   3.3V         |                                  |
#  24V------+------->|--------------+   |   +----------------|3V          down   stop   up      |
#           |                           |                    |            (+)    ( )    (+)     |
#  GND--+---)---------------------------+--------------------|GND          |             |      |
#       |   |                                                |             |             |      |
#       |   |                                                +------------ | ----------- | -----+
#       |   |        +---------------------------+                         |             |
#       |   +--------|24V                     OC1|-------------------------+             |
#       +------------|GND                     OC2|---------------------------------------+
#                    |    HMW-IO-12-Sw14-DR      |
#                    |                           |
#
#
#
# ******************************************************************************************************************************************
#
# While the shutter of a velux window is moving, the window movement is blocked and vice versa.
# If up/down command results in a short movement only, decrease short_press_millis.
# If stop command results in direction change, increase long_press_millis.
# If commands are lost, try to increase command_pause_millis.
#
# ******************************************************************************************************************************************

load tclrega.so
source /usr/local/addons/velux/lib/ini.tcl

namespace eval velux {
	variable version_file "/usr/local/addons/velux/VERSION"
	variable ini_file "/usr/local/addons/velux/etc/velux.conf"
	variable log_file "/tmp/velux-addon-log.txt"
	variable log_level 4
	variable lock_start_port 11100
	variable lock_socket
	variable lock_id_log_file 1
	variable lock_id_ini_file 2
	variable lock_id_transmit 3
	variable ventilation_state 0.15
	variable short_press_millis 500
	variable long_press_millis 1500
	variable command_pause_millis 1000
	variable dryrun 0
}

# error=1, warning=2, info=3, debug=4
proc ::velux::write_log {lvl str} {
	variable log_level
	variable log_file
	variable lock_id_log_file
	if {$lvl <= $log_level} {
		acquire_lock $lock_id_log_file
		set fd [open $log_file "a"]
		set date [clock seconds]
		set date [clock format $date -format {%Y-%m-%d %T}]
		set process_id [pid]
		puts $fd "\[${lvl}\] \[${date}\] \[${process_id}\] ${str}"
		close $fd
		#puts "\[${lvl}\] \[${date}\] \[${process_id}\] ${str}"
		release_lock $lock_id_log_file
	}
}

proc ::velux::version {} {
	variable version_file
	set fp [open $version_file r]
	set data [read $fp]
	close $fp
	return [string trim $data]
}

proc ::velux::acquire_lock {lock_id} {
	variable lock_socket
	variable lock_start_port
	set port [expr { $lock_start_port + $lock_id }]
	# 'socket already in use' error will be our lock detection mechanism
	while {1} {
		if { [catch {socket -server dummy_accept $port} sock] } {
			write_log 4 "Could not acquire lock"
			after 25
		} else {
			set lock_socket($lock_id) $sock
			break
		}
	}
}

proc ::velux::release_lock {lock_id} {
	variable lock_socket
	if { [catch {close $lock_socket($lock_id)} errormsg] } {
		write_log 1 "Error '${errormsg}' on closing socket for lock '${lock_id}'"
	}
	unset lock_socket($lock_id)
}

proc ::velux::get_process_id {window_id obj} {
	set param "${obj}_pid"
	catch { set opid [ expr { [get_window_param $window_id $param] } ] }
	if {[info exists opid] && $opid > 0} {
		if { [file exists "/proc/${opid}"] } {
			return $opid
		}
		set_window_param $window_id $param 0
	}
	return 0
}

# While the shutter of a velux window is moving, the window movement is blocked and vice versa.
proc ::velux::acquire_window {window_id obj} {
	set lpid 0
	
	set wpid [get_process_id $window_id "window"]
	if {$wpid > 0} {
		if {$obj == "window"} {
			write_log 3 "Killing window process ${wpid}"
			catch { exec kill $wpid }
		} else {
			set lpid $wpid
		}
	}
	
	set spid [get_process_id $window_id "shutter"]
	if {$spid > 0} {
		if {$obj == "shutter"} {
			write_log 3 "Killing window process ${spid}"
			catch { exec kill $spid }
		} else {
			set lpid $spid
		}
	}
	
	if {$obj == "window"} {
		set_window_param $window_id "window_pid" [pid]
	} elseif {$obj == "shutter"} {
		set_window_param $window_id "shutter_pid" [pid]
	}
	
	set ll 3
	while {$lpid && [file exists "/proc/${lpid}"]} {
		write_log $ll "Waiting for process ${lpid} to release window ${window_id}"
		set ll 4
		after 500
	}
	write_log 3 "Window ${window_id} acquired"
}

proc ::velux::release_window {window_id obj} {
	if {$obj == "window"} {
		set_window_param $window_id "window_pid" 0
	} elseif {$obj == "shutter"} {
		set_window_param $window_id "shutter_pid" 0
	}
}

proc ::velux::get_in_out_channels_json {} {
	set json "\{\"in\":\["
	array set data [rega_script "
		string deviceid;
		foreach(deviceid, dom.GetObject(ID_DEVICES).EnumUsedIDs()) {
			var device = dom.GetObject(deviceid);
			string channelid;
			foreach(channelid,device.Channels().EnumUsedIDs()) {
				var channel = dom.GetObject(channelid);
				if (((channel.ChnLabel() == 'INPUT_OUTPUT') || (channel.ChnLabel() == 'DIGITAL_INPUT') || (channel.ChnLabel() == 'DIGITAL_ANALOG_INPUT')) && ((channel.ChnDirection() == 0) || (channel.ChnDirection() == 1))) {
					WriteLine(channel.Name());
				}
			}
		}
	"]
	set count 0
	foreach d [split [encoding convertfrom utf-8 $data(STDOUT)] "\n"] {
		set d [string trim $d]
		if {$d != ""} {
			set count [ expr { $count + 1} ]
			append json "\"${d}\","
		}
	}
	if {$count > 0} {
		set json [string range $json 0 end-1]
	}
	append json "\],\"out\":\["
	
	array set data [rega_script "
		string deviceid;
		foreach(deviceid, dom.GetObject(ID_DEVICES).EnumUsedIDs()) {
			var device = dom.GetObject(deviceid);
			string channelid;
			foreach(channelid,device.Channels().EnumUsedIDs()) {
				var channel = dom.GetObject(channelid);
				if (((channel.ChnLabel() == 'INPUT_OUTPUT') || (channel.ChnLabel() == 'DIGITAL_OUTPUT') || (channel.ChnLabel() == 'DIGITAL_ANALOG_OUTPUT')) && ((channel.ChnDirection() == 0) || (channel.ChnDirection() == 2))) {
					WriteLine(channel.Name());
				}
			}
		}
	"]
	set count 0
	foreach d [split [encoding convertfrom utf-8 $data(STDOUT)] "\n"] {
		set d [string trim $d]
		if {$d != ""} {
			set count [ expr { $count + 1} ]
			append json "\"${d}\","
		}
	}
	if {$count > 0} {
		set json [string range $json 0 end-1]
	}
	append json "\]\}"
	
	return $json
}

proc ::velux::get_config_json {} {
	variable ini_file
	variable lock_id_ini_file
	variable short_press_millis
	variable long_press_millis
	variable command_pause_millis
	acquire_lock $lock_id_ini_file
	set ini [ini::open $ini_file r]
	set json "\{\"global\":\{"
	set value [json_string [::ini::value $ini "global" "short_press_millis" $short_press_millis]]
	append json "\"short_press_millis\":${value},"
	set value [json_string [::ini::value $ini "global" "long_press_millis" $long_press_millis]]
	append json "\"long_press_millis\":${value},"
	set value [json_string [::ini::value $ini "global" "command_pause_millis" $command_pause_millis]]
	append json "\"command_pause_millis\":${value}"
	append json "\},\"windows\":\["
	set count 0
	foreach section [ini::sections $ini] {
		set idx [string first "window_" $section]
		if {$idx == 0} {
			set count [ expr { $count + 1} ]
			set window_id [string range $section 7 end]
			append json "\{\"id\":\"${window_id}\","
			foreach key [ini::keys $ini $section] {
				set value [::ini::value $ini $section $key]
				set value [json_string $value]
				append json "\"${key}\":\"${value}\","
			}
			set json [string range $json 0 end-1]
			append json "\},"
		}
	}
	if {$count > 0} {
		set json [string range $json 0 end-1]
	}
	append json "\]\}"
	release_lock $lock_id_ini_file
	return $json
}

proc ::velux::read_global_config {} {
	variable ini_file
	variable lock_id_ini_file
	variable short_press_millis
	variable long_press_millis
	variable command_pause_millis
	write_log 4 "Reading global config"
	acquire_lock $lock_id_ini_file
	set ini [ini::open $ini_file r]
	catch {
		set short_press_millis [expr { 0 + [::ini::value $ini "global" "short_press_millis" $short_press_millis] }]
		set long_press_millis [expr { 0 + [::ini::value $ini "global" "long_press_millis" $long_press_millis] }]
		set command_pause_millis [expr { 0 + [::ini::value $ini "global" "command_pause_millis" $command_pause_millis] }]
	}
	release_lock $lock_id_ini_file
}

proc ::velux::update_global_config {short_press_millis long_press_millis command_pause_millis} {
	variable ini_file
	variable lock_id_ini_file
	write_log 4 "Updating global config: short_press_millis=${short_press_millis}, long_press_millis=${long_press_millis}, command_pause_millis=${command_pause_millis}"
	acquire_lock $lock_id_ini_file
	set ini [ini::open $ini_file r+]
	ini::set $ini "global" "short_press_millis" $short_press_millis
	ini::set $ini "global" "long_press_millis" $long_press_millis
	ini::set $ini "global" "command_pause_millis" $command_pause_millis
	ini::commit $ini
	release_lock $lock_id_ini_file
}

proc ::velux::create_window {window_id name window_up_channel window_down_channel window_motion_seconds {window_reed_channel ""} {shutter_up_channel ""} {shutter_down_channel ""} {shutter_motion_seconds 0}} {
	variable ini_file
	variable lock_id_ini_file
	acquire_lock $lock_id_ini_file
	set ini [ini::open $ini_file r+]
	ini::set $ini "window_${window_id}" "name" $name
	ini::set $ini "window_${window_id}" "window_up_channel" $window_up_channel
	ini::set $ini "window_${window_id}" "window_down_channel" $window_down_channel
	ini::set $ini "window_${window_id}" "window_motion_seconds" $window_motion_seconds
	ini::set $ini "window_${window_id}" "window_reed_channel" $window_reed_channel
	ini::set $ini "window_${window_id}" "window_level" "0.0"
	ini::set $ini "window_${window_id}" "window_pid" "0"
	ini::set $ini "window_${window_id}" "shutter_up_channel" $shutter_up_channel
	ini::set $ini "window_${window_id}" "shutter_down_channel" $shutter_down_channel
	ini::set $ini "window_${window_id}" "shutter_motion_seconds" $shutter_motion_seconds
	ini::set $ini "window_${window_id}" "shutter_level" "0.0"
	ini::set $ini "window_${window_id}" "shutter_pid" "0"
	ini::commit $ini
	release_lock $lock_id_ini_file
}

proc ::velux::get_window_ids {} {
	variable ini_file
	variable lock_id_ini_file
	acquire_lock $lock_id_ini_file
	set window_ids [list]
	set ini [ini::open $ini_file r]
	foreach section [ini::sections $ini] {
		set idx [string first "window_" $section]
		if {$idx == 0} {
			lappend window_ids [string range $section 7 end]
		}
	}
	release_lock $lock_id_ini_file
	return $window_ids
}

proc ::velux::get_window {window_id} {
	variable ini_file
	variable lock_id_ini_file
	acquire_lock $lock_id_ini_file
	set window(id) ""
	set ini [ini::open $ini_file r]
	foreach section [ini::sections $ini] {
		set idx [string first "window_${window_id}" $section]
		if {$idx == 0} {
			set window(id) $window_id
			foreach key [ini::keys $ini $section] {
				set value [::ini::value $ini $section $key]
				set window($key) $value
			}
		}
	}
	release_lock $lock_id_ini_file
	if {$window(id) == ""} {
		error "Window ${window_id} not configured."
	}
	return [array get window]
}

proc ::velux::get_window_id_by_param {param val} {
	variable ini_file
	variable lock_id_ini_file
	acquire_lock $lock_id_ini_file
	set window_id ""
	set ini [ini::open $ini_file r]
	foreach section [ini::sections $ini] {
		set idx [string first "window_" $section]
		if {$idx == 0} {
			if {[::ini::value $ini $section $param] == $val} {
				set window_id [string range $section 7 end]
				break
			}
		}
	}
	release_lock $lock_id_ini_file
	if {$window_id == ""} {
		error "Window not found by ${param}=${val}."
	}
	return $window_id
}

proc ::velux::get_window_param {window_id param} {
	array set window [get_window $window_id]
	if { ![info exists window($param)] } {
		if {$param == "window_level" || $param == "shutter_level"} {
			return 0
		}
	}
	return $window($param)
}

proc ::velux::shutter_configured {window_id} {
	if { [velux::get_window_param $window_id "shutter_up_channel"] != ""} {
		return 1
	}
	return 0
}

proc ::velux::set_window_param {window_id param value} {
	variable ini_file
	variable lock_id_ini_file
	write_log 4 "Setting window ${window_id} parameter ${param} to ${value}"
	acquire_lock $lock_id_ini_file
	set ini [ini::open $ini_file r+]
	set found 0
	foreach section [ini::sections $ini] {
		set idx [string first "window_${window_id}" $section]
		if {$idx == 0} {
			set found 1
		}
	}
	if {$found} {
		ini::set $ini "window_${window_id}" $param $value
		ini::commit $ini
	}
	release_lock $lock_id_ini_file
	if {!$found} {
		error "Window ${window_id} not configured."
	}
}

proc ::velux::delete_window {window_id} {
	variable ini_file
	variable lock_id_ini_file
	acquire_lock $lock_id_ini_file
	set ini [ini::open $ini_file r+]
	ini::delete $ini "window_${window_id}"
	ini::commit $ini
	release_lock $lock_id_ini_file
}

proc ::velux::get_level_value {window_id obj} {
	return [ expr { [get_window_param $window_id "${obj}_level"] } ]
}

proc ::velux::set_level_value {window_id obj lvl} {
	global env
	set_window_param $window_id "${obj}_level" $lvl
	if { [info exists ::env(CUXD_CHANNEL) ] } {
		write_log 4 "Setting channel \"CUxD.$env(CUXD_CHANNEL)\" to state: $lvl"
		rega_script "dom.GetObject(\"CUxD.$env(CUXD_CHANNEL).SET_STATE\").State(\"$lvl\");"
	}
	
}

proc ::velux::set_object_states {states} {
	variable dryrun
	upvar $states s
	set rs ""
	foreach object [lsort [array names s]] {
		if {$object == ""} {
			error "Object not set"
		}
		if {$dryrun} {
			write_log 3 "Would set object \"$object\" to state: $s($object) (dryrun)"
		} else {
			write_log 3 "Setting object \"$object\" to state: $s($object)"
			append rs "dom.GetObject(\"$object\").State($s($object));"
		}
	}
	if {$rs != ""} {
		rega_script $rs
	}
	return 0
}

proc ::velux::get_object_state {window_id object} {
	set val -1
	if {$object != ""} {
		array set ret [rega_script "var val1 = dom.GetObject(\"${object}\").State();" ]
		set val $ret(val1)
		write_log 4 "Window ${window_id} object ${object} state: ${val}"
		if {$val == "false"} {
			set val  1
		} elseif {$val == "true"} {
			set val 0
		}
	}
	return $val
}

proc ::velux::get_reed_state {window_id} {
	set channel [get_window_param $window_id "window_reed_channel"]
	if {$channel != ""} {
		return [get_object_state $window_id $channel]
	}
	return -1
}

# Do not send more than one command at once, because of interference
proc ::velux::send_command {window_id obj cmd} {
	variable lock_id_transmit
	variable short_press_millis
	variable long_press_millis
	variable command_pause_millis
	
	velux::write_log 4 "send_command: ${window_id} ${obj} ${cmd}"
	
	array set window [get_window $window_id]
	set up_channel $window(${obj}_up_channel)
	set down_channel $window(${obj}_down_channel)
	
	set up 1
	set down 1
	if {$cmd == "up"} { set down 0 }
	if {$cmd == "down"} { set up 0 }
	acquire_lock $lock_id_transmit
	set states($up_channel) $up
	set states($down_channel) $down
	set_object_states states
	if {$cmd == "stop"} {
		after $long_press_millis
	} else {
		after $short_press_millis
	}
	set states($up_channel) 0
	set states($down_channel) 0
	set_object_states states
	after $command_pause_millis
	release_lock $lock_id_transmit
}

proc velux::window_close_event {window_id_or_channel} {
	variable ventilation_state
	
	set window_id ""
	if { [catch {expr {abs($window_id_or_channel)}}] } {
		set window_id [get_window_id_by_param "window_reed_channel" $window_id_or_channel]
	} else {
		set window_id $window_id_or_channel
	}
	
	set wpid [get_process_id $window_id "window"]
	if {$wpid == 0} {
		# No process running, closed externally (i.e. rainsensor)
		# correcting position to ventilation_state
		set current_level [get_level_value $window_id "window"]
		#write_log 4 "$window_id $current_level $ventilation_state"
		if {$current_level > $ventilation_state} {
			write_log 3 "Window ${window_id} closed externally, setting level from ${current_level} to ${ventilation_state}"
			set_level_value $window_id "window" $ventilation_state
		} else {
			write_log 3 "Window ${window_id} closed externally, not changing current level of ${current_level}"
		}
	} else {
		write_log 4 "Window ${window_id} closed by window process ${wpid}"
	}
}

proc velux::set_level {window_id obj target_level {extra_movement 0.1}} {
	variable ventilation_state
	variable dryrun
	
	array set window [get_window $window_id]
	set up_channel $window(${obj}_up_channel)
	#set down_channel $window(${obj}_down_channel)
	
	if {$target_level == 0 || $target_level == 1} {
		set rpid [get_process_id $window_id $obj]
		if { $rpid > 0 } {
			# Another process running
			set direction "down"
			if {[get_object_state $window_id $up_channel] == 1} {
				set direction "up"
			}
			write_log 1 "Another process running (direction: $direction)"
			acquire_window $window_id $obj
			if {{direction == "up" && $target_level == 0} || {direction == "down" && $target_level == 1}} {
				write_log 1 "Direction change, target level $target_level => stop movement"
				send_command $window_id $obj "stop"
				release_window $window_id $obj
				set_level_value $window_id $obj [get_level_value $window_id $obj]
				return
			} else {
				release_window $window_id $obj
			}
		}
	}
	
	acquire_window $window_id $obj
	
	set motion_seconds $window(${obj}_motion_seconds)
	set current_level [get_level_value $window_id $obj]
	set reed_state -1
	if {$obj == "window"} {
		set reed_state [get_reed_state $window_id]
	}
	if {$reed_state == 1 && $current_level > $ventilation_state && $dryrun == 0} {
		write_log 2 "reed contact closed, correcting level to ventilation_state ${ventilation_state}"
		set current_level $ventilation_state
	}
	set level_diff [expr {$target_level - $current_level}]
	if {$target_level <= 0} {
		# some extra movement to ensure end position
		set level_diff [expr {$level_diff - $extra_movement}]
	} elseif {$target_level >= 1} {
		# some extra movement to ensure end position
		set level_diff [expr {$level_diff + $extra_movement}]
	}
	
	write_log 4 "reed_state=$reed_state, current_level=$current_level, target_level=$target_level, level_diff=$level_diff"
	
	set start_time 0
	set ms_elapsed 0
	set start_level 0
	
	if {$level_diff != 0.0} {
		set start_level $current_level
		set level_change 0
		
		if {$level_diff > 0.0} {
			send_command $window_id $obj "up"
		} elseif {$level_diff < 0.0} {
			send_command $window_id $obj "down"
		}
		set start_time [clock clicks]
		
		while {[expr {abs($level_change)}] < [expr {abs($level_diff)}]} {
			after 250
			#set cmd_pid [get_cmd_pid $channel]
			#if {$cmd_pid != $process_id} {
			#	write_log 1 "other process started, aborting"
			#	set aborted 1
			#	break
			#}
			set now [clock clicks]
			set ms_elapsed [expr {($now - $start_time)/1000}]
			set level_change [expr {round($ms_elapsed / $motion_seconds) / 1000.0}]
			if {$level_diff < 0.0} {
				set level_change [expr {$level_change * -1}]
			}
			set new_level [expr {(round(($start_level + $level_change)*100.0))/100.0}]
			if {$new_level < 0.0} {
				set new_level 0.0
			} elseif {$new_level > 1.0} {
				set new_level 1.0
			}
			
			if {$obj == "window" && $level_diff > 0.0 && $new_level > [expr {$ventilation_state + 0.3}]} {
				set reed_state [get_reed_state $window_id]
				if {$reed_state == 1 && $dryrun == 0} {
					# reed contact closed, movement failed, correcting level to ventilation_state and aborting
					write_log 3 "Reed contact closed, movement failed, correcting level to ventilation_state (${ventilation_state}) and aborting."
					set current_level $ventilation_state
					set target_level $ventilation_state
					break
				}
			}
			write_log 4 "start_time=${start_time}, now=${now}, ms_elapsed=${ms_elapsed}, level_diff=${level_diff}, level_change=${level_change}, current_level=${current_level}, new_level=${new_level}"
			if {$new_level != $current_level} {
				set current_level $new_level
				set_level_value $window_id $obj $current_level
			}
		}
	}
	
	send_command $window_id $obj "stop"
	if {$target_level != -1} {
		set movement_ms [expr {([clock clicks] - $start_time)/1000}]
		write_log 3 "Movement completed (window=${window_id}, obj=${obj}, movement_ms=${movement_ms}\(${ms_elapsed}\), start_level=${start_level}, target_level=${target_level})"
		set_level_value $window_id $obj $target_level
	}
	
	release_window $window_id $obj
}

proc velux::reset {{window_id ""}} {
	set window_ids [list]
	if {$window_id == ""} {
		set window_ids [get_window_ids]
	} else {
		lappend window_ids $window_id
	}
	foreach window_id $window_ids {
		set_level $window_id "window" 0 1.0
		if { [shutter_configured $window_id] } {
			set_level $window_id "shutter" 1.0 1.0
		}
	}
}

velux::read_global_config
