#!/bin/tclsh

#  HomeMatic addon to control velux windows and blinds
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
#                        +---------+
#                        |         |
#                        | 7803SRC |
#                        |         |
#                        |         |            Velux Fernbedienung 3UR B01, 946949, 860963
#                        +---------+               +----------------------------------+
#           Schutzdiode   |   |   |   3.3V         |                                  |
#  24V------+---->|-------+   |   +----------------|3V        runter   stop   hoch    |
#           |                 |                    |            (+)    ( )    (+)     |
#  GND--+---)-----------------+--------------------|GND          |             |      |
#       |   |                                      |             |             |      |
#       |   |                                      +------------ | ----------- | -----+
#       |   |     +---------------------------+                  |             |
#       |   +-----|24V                     OC1|------------------+             |
#       +---------|GND                     OC2|--------------------------------+
#                 |    HMW-IO-12-Sw14-DR      |
#                 |                           |
#
#
#
# ******************************************************************************************************************************************
#
# While the shutter of a velux window is moving, the window movement is blocked and vice versa.
# Therefore channels 1+2, 3+4, 5+6 and so on are understood as channel pairs which will block each other.
# Every set-state command will wait until the associate channel is unsused.
#
# If stop command results in direction change of window / shutter try to increase SHORT_PRESS_TIME.
# If commands are lost, try to increase CMD_PAUSE_TIME.
#
# ******************************************************************************************************************************************
#
# string stdout;
# string stderr;
# var source  = dom.GetObject("$src$");
# var name = source.Name();
# boolean closed = !source.State();
# 
# !!! system.Exec("/bin/sh -c 'echo " # name # " " # source.State() # " >> /tmp/log.txt'" , &stdout, &stderr);
# 
# var channel = "0";
# if (name == "BidCos-Wired.LEQ0975591:15.STATE") {
#    !! Dusche
#    channel = "1";
# }
# if (name == "BidCos-Wired.LEQ0975591:16.STATE") {
#    !! Bad
#    channel = "3";
# }
# if (name == "BidCos-Wired.LEQ0975591:17.STATE") {
#    !! Spitzboden
#    channel = "5";
# }
# 
# !!! system.Exec("/bin/sh -c 'echo " # name + "  " # channel # " " # closed # " >> /tmp/log.txt'" , &stdout, &stderr);
# 
# if (closed && channel != "0") {
#    !!! system.Exec("/bin/sh -c 'echo closed: " # name + "  " # channel # " >> /tmp/log.txt'" , &stdout, &stderr);
#    system.Exec("/bin/tclsh /usr/local/velux_ctrl/cmd.tcl close-event " # channel, &stdout, &stderr);
#    !!! WriteLine("stdout: " # stdout);
#    !!! WriteLine("stderr: " # stderr);
# }
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
	variable short_press_millis 750
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
		puts "\[${lvl}\] \[${date}\] \[${process_id}\] ${str}"
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

proc ::velux::create_window {window_id name window_up_device window_down_device window_motion_seconds {window_reed_device ""} {shutter_up_device ""} {shutter_down_device ""} {shutter_motion_seconds 0}} {
	variable ini_file
	variable lock_id_ini_file
	acquire_lock $lock_id_ini_file
	set ini [ini::open $ini_file r+]
	ini::set $ini "window_${window_id}" "name" $name
	ini::set $ini "window_${window_id}" "window_up_device" $window_up_device
	ini::set $ini "window_${window_id}" "window_down_device" $window_down_device
	ini::set $ini "window_${window_id}" "window_motion_seconds" $window_motion_seconds
	ini::set $ini "window_${window_id}" "window_reed_device" $window_reed_device
	ini::set $ini "window_${window_id}" "window_level" "0.0"
	ini::set $ini "window_${window_id}" "window_pid" "0"
	ini::set $ini "window_${window_id}" "shutter_up_device" $shutter_up_device
	ini::set $ini "window_${window_id}" "shutter_down_device" $shutter_down_device
	ini::set $ini "window_${window_id}" "shutter_motion_seconds" $shutter_motion_seconds
	ini::set $ini "window_${window_id}" "shutter_level" "0.0"
	ini::set $ini "window_${window_id}" "shutter_pid" "0"
	ini::commit $ini
	release_lock $lock_id_ini_file
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
	return [array get window]
}

proc ::velux::get_window_param {window_id param} {
	array set window [get_window $window_id]
	return $window($param)
}

proc ::velux::set_window_param {window_id param value} {
	variable ini_file
	variable lock_id_ini_file
	write_log 4 "Setting window ${window_id} parameter ${param} to ${value}"
	acquire_lock $lock_id_ini_file
	set ini [ini::open $ini_file r+]
	ini::set $ini "window_${window_id}" $param $value
	ini::commit $ini
	release_lock $lock_id_ini_file
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

proc ::velux::get_level {window_id obj} {
	set lvl 0.0
	catch { set lvl [ expr { [get_window_param $window_id "${obj}_level"] } ] }
	return $lvl
}

proc ::velux::set_level {window_id obj lvl} {
	global env
	set_window_param $window_id "${obj}_level" $lvl
	if { [info exists ::env(CUXD_CHANNEL) ] } {
		write_log 4 "Setting device \"CUxD.$env(CUXD_CHANNEL)\" to state: $lvl"
		rega_script "dom.GetObject(\"CUxD.$env(CUXD_CHANNEL).SET_STATE\").State(\"$lvl\");"
	}
	
}

proc ::velux::set_object_state {device val} {
	variable dryrun
	if {$device == ""} {
		error "Device not set"
	}
	if {$dryrun} {
		write_log 3 "Would set device \"$device\" to state: $val (dryrun)"
	} else {
		write_log 3 "Setting device \"$device\" to state: $val"
		rega_script "dom.GetObject(\"$device\").State($val);"
	}
	return 0
}

proc ::velux::get_reed_state {window_id} {
	set device [get_window_param $window_id "window_reed_device"]
	if {$device != ""} {
		array set ret [rega_script "var val1 = dom.GetObject(\"${device}\").State();" ]
		set val $ret(val1)
		write_log 4 "Window ${window_id} reed device ${device} state: ${val}"
		if {$val == "false"} {
			return 1
		} elseif {$val == "true"} {
			return 0
		}
	}
	return -1
}

# Do not send more than one command at once, because of interference
proc ::velux::send_command {window_id obj cmd} {
	variable lock_id_transmit
	variable short_press_millis
	variable command_pause_millis
	
	velux::write_log 4 "send_command: ${window_id} ${obj} ${cmd}"
	
	array set window [get_window $window_id]
	set up_device $window(${obj}_up_device)
	set down_device $window(${obj}_down_device)
	
	set up 1
	set down 1
	if {$cmd == "up"} { set down 0 }
	if {$cmd == "down"} { set up 0 }
	acquire_lock $lock_id_transmit
	set_object_state $up_device $up
	set_object_state $down_device $down
	after $short_press_millis
	set_object_state $up_device 0
	set_object_state $down_device 0
	after $command_pause_millis
	release_lock $lock_id_transmit
}

