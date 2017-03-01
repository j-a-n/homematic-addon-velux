#!/bin/tclsh

#  HomeMatic addon to control Velux windows and blinds
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
# dom.GetObject("velux_motion_seconds").Variable("45;30;45;30;45;30");
# dom.GetObject("velux_up_device").Variable("FEN_DUSCHE_AUF;ROL_DUSCHE_AUF;FEN_BAD_AUF;ROL_BAD_AUF;FEN_SPITZBODEN_AUF;ROL_SPITZBODEN_AUF");
# dom.GetObject("velux_down_device").Variable("FEN_DUSCHE_ZU;ROL_DUSCHE_ZU;FEN_BAD_ZU;ROL_BAD_ZU;FEN_SPITZBODEN_ZU;ROL_SPITZBODEN_ZU");
# dom.GetObject("velux_reed_device").Variable("REED_FEN_DUSCHE;;REED_FEN_BAD;;REED_FEN_SPITZBODEN;");
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

set LOGFILE "/usr/local/velux_ctrl/log.txt"
set CUXD_DEV "CUX4000001"
set SYS_VAR_CMD_PID "velux_cmd_pid"
set SYS_VAR_MOTION_SEC "velux_motion_seconds"
set SYS_VAR_LEVEL "velux_level"
set SYS_VAR_UP_DEV "velux_up_device"
set SYS_VAR_DOWN_DEV "velux_down_device"
set SYS_VAR_REED_DEV "velux_reed_device"
set VENTILATION_STATE 0.15
set SHORT_PRESS_TIME 750
set CMD_PAUSE_TIME 1000
set LOCK_START_PORT 11100
set LOCK_ID_LOG_FILE 1
set LOCK_ID_SYS_VAR 2
set LOCK_ID_TRANSMIT 3

set LOGLEVEL 1
set DRYRUN 0

proc port_map {lock_id} {
	global LOCK_START_PORT
	return [expr { $LOCK_START_PORT + $lock_id }]
}

proc acquire_lock {lock_id} {
	global LOCK_SOCKET
	set res 0
	set port [port_map "$lock_id"]
	# 'socket already in use' error will be our lock detection mechanism
	while {1 == 1} {
		if { [catch {socket -server dummy_accept $port} sock] } {
			#puts "Could not acquire lock"
			set res 1
			after 25
		} else {
			set LOCK_SOCKET("$lock_id") "$sock"
			break
		}
	}
	return $res
}

proc release_lock {lock_id} {
	global LOCK_SOCKET
	if { [catch {close $LOCK_SOCKET("$lock_id")} ERRORMSG] } {
		puts "Error '$ERRORMSG' on closing socket for lock '$lock_id'"
	}
	unset LOCK_SOCKET("$lock_id")
}

proc write_log {lvl str} {
	global LOGLEVEL
	global LOCK_ID_LOG_FILE
	if {$lvl <= $LOGLEVEL} {
		acquire_lock $LOCK_ID_LOG_FILE
		global LOGFILE
		set fd [open $LOGFILE "a"]
		set date [clock seconds]
		set date [clock format $date -format {%Y-%m-%d %T}]
		set process_id [pid]
		puts $fd "\[$lvl\] \[$date\] \[$process_id\] $str"
		close $fd
		puts "\[$lvl\] \[$date\] \[$process_id\] $str"
		release_lock $LOCK_ID_LOG_FILE
	}
}

proc log_environment {} {
	global env
	write_log 3 "=== Environment ====================="
	foreach key [array names env] {
		write_log 3 "$key=$env($key)"
	}
	write_log 3 "====================================="
}

proc log_arguments {} {
	global argv
	write_log 3 "=== Arguments ======================="
	foreach arg $argv {
		write_log 3 "$arg"
	}
	write_log 3 "====================================="
}

proc create_sys_var {var} {
	write_log 1 "create system variable \"$var\""
	set s "
	string svName = \"$var\";
	object  svObj = dom.GetObject(svName);
	if (!svObj) {
		object svObjects = dom.GetObject(ID_SYSTEM_VARIABLES);
		svObj = dom.CreateObject(OT_VARDP);
		svObjects.Add(svObj.ID());
		svObj.Name(svName);
		svObj.ValueType(ivtString);
		svObj.ValueSubType(istChar8859);
		
		svObj.DPInfo(\"\");
		svObj.ValueUnit(\"\");
		svObj.State(\"\");
		svObj.Internal(false);
		svObj.Visible(true);
		dom.RTUpdate(false);
	}
	"
	rega_script $s
}

proc get_sys_var {var channel} {
	global LOCK_ID_SYS_VAR
	acquire_lock $LOCK_ID_SYS_VAR
	set idx [expr {$channel - 1}]
	array set ret [rega_script "var val1 = dom.GetObject(\"$var\").State();" ]
	set val $ret(val1)
	write_log 3 "value of system variable \"$var\": $val"
	if {$val == "null"} {
		create_sys_var $var
	}
	set val [lindex [split $val ";"] $idx]
	write_log 3 "system variable \"$var\" value of channel $channel: $val"
	release_lock $LOCK_ID_SYS_VAR
	return $val
}

proc set_sys_var {var channel val} {
	global LOCK_ID_SYS_VAR
	acquire_lock $LOCK_ID_SYS_VAR
	set idx [expr {$channel - 1}]
	array set ret [rega_script "var val1 = dom.GetObject(\"$var\").State();" ]
	set vals [split $ret(val1) ";"]
	while {[llength $vals] < $channel} {
		lappend vals ""
	}
	set vals [lreplace $vals $idx $idx $val]
	set val [join $vals ";"]
	write_log 3 "setting system variable \"$var\" to value: $val"
	rega_script "dom.GetObject(\"$var\").State(\"$val\");"
	release_lock $LOCK_ID_SYS_VAR
}

proc acquire_channel {channel} {
	set bchannel [expr {$channel + 1}]
	if {[expr {$channel % 2}] == 0} {
		set bchannel [expr {$channel - 1}]
	}
	set ll 1
	while {[get_cmd_pid $bchannel] != 0} {
		write_log $ll "waiting for channel $bchannel to clear"
		set ll 3
		after 500
	}
	write_log 2 "channel $channel acquired"
}

proc get_process_age {process_id} {
	set status [catch {exec sh -c "echo \$((\$(cat /proc/uptime | cut -d'.' -f1) - \$(cat /proc/$process_id/stat | cut -d' ' -f22)/100))"} result]
	set seconds 0
	if {$status == 0} {
		set seconds [expr $result]
	}
	write_log 1 "process age of pid $process_id: $seconds second(s)"
	return seconds
}

proc set_level {channel val} {
	global SYS_VAR_LEVEL
	global CUXD_DEV
	set_sys_var $SYS_VAR_LEVEL $channel $val
	write_log 2 "setting device \"CUxD.$CUXD_DEV:$channel.SET_STATE\" to state: $val"
	rega_script "dom.GetObject(\"CUxD.$CUXD_DEV:$channel.SET_STATE\").State(\"$val\");"
}

proc get_level {channel} {
	global SYS_VAR_LEVEL
	set val [get_sys_var $SYS_VAR_LEVEL $channel]
	if [catch { set val [expr $val] }] {
		set val 0
	}
	return $val
}

proc get_cmd_pid {channel} {
	global SYS_VAR_CMD_PID
	set val [get_sys_var $SYS_VAR_CMD_PID $channel]
	if [catch { set val [expr $val] }] {
		set val 0
	}
	return $val
}

proc set_cmd_pid {channel val} {
	global SYS_VAR_CMD_PID
	set_sys_var $SYS_VAR_CMD_PID $channel $val
}

proc get_motion_seconds {channel} {
	global SYS_VAR_MOTION_SEC
	set val [get_sys_var $SYS_VAR_MOTION_SEC $channel]
	if [catch { set val [expr $val] }] {
		set val 0
	}
	return $val
}

proc set_motion_seconds {channel val} {
	global SYS_VAR_MOTION_SEC
	set_sys_var $SYS_VAR_MOTION_SEC $channel $val
}

proc get_down_device {channel} {
	global SYS_VAR_DOWN_DEV
	set val [get_sys_var $SYS_VAR_DOWN_DEV $channel]
	return $val
}

proc set_down_device {channel val} {
	global SYS_VAR_DOWN_DEV
	set_sys_var $SYS_VAR_DOWN_DEV $channel $val
}

proc get_up_device {channel} {
	global SYS_VAR_UP_DEV
	set val [get_sys_var $SYS_VAR_UP_DEV $channel]
	return $val
}

proc set_up_device {channel val} {
	global SYS_VAR_UP_DEV
	set_sys_var $SYS_VAR_UP_DEV $channel $val
}

proc set_device_state {device val} {
	global DRYRUN
	if {$device == ""} {
		return -1
	}
	if {$DRYRUN} {
		write_log 1 "would set device \"$device\" to state: $val (DRYRUN)"
	} else {
		write_log 1 "setting device \"$device\" to state: $val"
		rega_script "dom.GetObject(\"$device\").State($val);"
	}
	return 0
}

proc device_cmd {channel cmd} {
	global LOCK_ID_TRANSMIT
	global SHORT_PRESS_TIME
	global CMD_PAUSE_TIME
	
	set down_device [get_down_device $channel]
	if {$down_device == ""} {
		# down_device not configure, set default
		set_down_device $channel ""
		return -1
	}
	set up_device [get_up_device $channel]
	if {$up_device == ""} {
		# up_device not configure, set default
		set_up_device $channel ""
		return -1
	}
	set up 1
	set down 1
	if {$cmd == "up"} { set down 0 }
	if {$cmd == "down"} { set up 0 }
	acquire_lock $LOCK_ID_TRANSMIT
	set_device_state $up_device $up
	set_device_state $down_device $down
	after $SHORT_PRESS_TIME
	set_device_state $up_device 0
	set_device_state $down_device 0
	after $CMD_PAUSE_TIME
	release_lock $LOCK_ID_TRANSMIT
}

proc device_cmd_up {channel} {
	device_cmd $channel "up"
}

proc device_cmd_down {channel} {
	device_cmd $channel "down"
}

proc device_cmd_stop {channel} {
	device_cmd $channel "stop"
}


proc get_reed_device {channel} {
	global SYS_VAR_REED_DEV
	set val [get_sys_var $SYS_VAR_REED_DEV $channel]
	return $val
}

proc set_reed_device {channel val} {
	global SYS_VAR_REED_DEV
	set_sys_var $SYS_VAR_REED_DEV $channel $val
}

proc get_reed_state {channel} {
	set device [get_reed_device $channel]
	if {$device == ""} {
		return -1
	}
	array set ret [rega_script "var val1 = dom.GetObject(\"$device\").State();" ]
	set val $ret(val1)
	write_log 2 "channel $channel reed device $device state: $val"
	if {$val == "false"} {
		return 1
	}
	if {$val == "true"} {
		return 0
	}
	return -1
}

log_environment
log_arguments

set process_id [pid]
set aborted 0
set target_level -1
set cmd [string tolower [lindex $argv 0]]
if {$cmd == "short" || $cmd == "long" || $cmd == "set"} {
	set cmd "set-level"
}
set channel [lindex $argv 1]
if { $channel == "" && [info exists ::env(CUXD_CHANNEL) ] } {
	set channel [lindex [split $env(CUXD_CHANNEL) ":"] 1]
}
if {$cmd == "set-level"} {
	set target_level [lindex $argv 2]
	if { $target_level == "" } {
		if { [info exists ::env(CUXD_VALUE) ] } {
			set target_level [expr {$env(CUXD_VALUE) / 1000.0}]
		}
	} else {
		set target_level [expr {$target_level / 100.0}]
	}
	write_log 1 "set-level of channel $channel to $target_level"
} elseif {$cmd == "stop"} {
	write_log 1 "stop of channel $channel"
} elseif {$cmd == "close-event"} {
	write_log 1 "close-event of channel $channel"
} else {
	puts "Invalid command \"$cmd\", possible commands are: \"stop\", \"set-level\" and \"close-event\""
	exit 1
}

acquire_channel $channel

if {$cmd == "close-event"} {
	set cmd_pid [get_cmd_pid $channel]
	if {$cmd_pid == 0} {
		# No process running, closed externally (i.e. rainsensor)
		# correcting position to VENTILATION_STATE
		set current_level [get_level $channel]
		write_log 1 "$channel $current_level $VENTILATION_STATE"
		if {$current_level > $VENTILATION_STATE} {
			write_log 2 "Channel $channel closed externally, setting level from $current_level to $VENTILATION_STATE"
			set_level $channel $VENTILATION_STATE
		} else {
			write_log 2 "Channel $channel closed externally, not changing current level of $current_level"
		}
	} else {
		write_log 3 "Channel $channel closed by velux_ctrl"
	}
	exit 0
}

set motion_seconds [get_motion_seconds $channel]
if {$motion_seconds == 0} {
	# motion_seconds not configure, set default
	set motion_seconds 30
	set_motion_seconds $channel $motion_seconds
}
set reed_device [get_reed_device $channel]
if {$reed_device == ""} {
	# reed_device not configure, set default
	set_reed_device $channel ""
}

set cmd_pid [get_cmd_pid $channel]
set_cmd_pid $channel $process_id
if { $cmd_pid != 0 } {
	# Another process running
	if {$target_level == 0 || $target_level == 1} {
		write_log 1 "another process running, target level $target_level => stop movement"
		device_cmd_stop $channel
		set_cmd_pid $channel 0
		exit 0
	}
}

set start_time 0
set ms_elapsed 0
set start_level 0
if {$cmd == "set-level"} {
	set current_level [get_level $channel]
	set reed_state [get_reed_state $channel]
	if {$reed_state == 1 && $current_level > $VENTILATION_STATE} {
		# reed contact closed, correct level to VENTILATION_STATE
		set current_level $VENTILATION_STATE
	}
	set level_diff [expr {$target_level - $current_level}]
	if {$target_level <= 0} {
		# some extra movement to ensure end position
		set level_diff [expr {$level_diff - 0.1}]
	} elseif {$target_level >= 1} {
		# some extra movement to ensure end position
		set level_diff [expr {$level_diff + 0.1}]
	}
	
	write_log 2 "reed_state=$reed_state, current_level=$current_level, target_level=$target_level, level_diff=$level_diff"
	
	if {$level_diff != 0.0} {
		set start_level $current_level
		set level_change 0
		
		if {$level_diff > 0.0} {
			device_cmd_up $channel
		} elseif {$level_diff < 0.0} {
			device_cmd_down $channel
		}
		set start_time [clock clicks]
		
		while {[expr {abs($level_change)}] < [expr {abs($level_diff)}]} {
			after 250
			set cmd_pid [get_cmd_pid $channel]
			if {$cmd_pid != $process_id} {
				write_log 1 "other process started, aborting"
				set aborted 1
				break
			}
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
			if {$level_diff > 0.0 && $new_level > [expr {$VENTILATION_STATE + 0.3}]} {
				set reed_state [get_reed_state $channel]
				if {$reed_state == 1} {
					# reed contact closed, movement failed, correcting level to VENTILATION_STATE and aborting
					write_log 1 "reed contact closed, movement failed, correcting level to VENTILATION_STATE ($VENTILATION_STATE) and aborting"
					set current_level $VENTILATION_STATE
					set target_level $VENTILATION_STATE
					break
				}
			}
			write_log 3 "start_time=$start_time, now=$now, ms_elapsed=$ms_elapsed, level_diff=$level_diff, level_change=$level_change, current_level=$current_level, new_level=$new_level"
			if {$new_level != $current_level} {
				set current_level $new_level
				set_level $channel $current_level
			}
		}
	}
}

if {$aborted == 0} {
	device_cmd_stop $channel
	if {$target_level != -1} {
		set movement_ms [expr {([clock clicks] - $start_time)/1000}]
		write_log 1 "movement completed (channel=$channel, aborted=$aborted, movement_ms=$movement_ms\($ms_elapsed\), start_level=$start_level, target_level=$target_level)"
		set_level $channel $target_level
	}
	# Set cmd pid to zero (no cmd running)
	set_cmd_pid $channel 0
}

write_log 3 "exiting"
exit 0









