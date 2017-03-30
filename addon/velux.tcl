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

source /usr/local/addons/velux/lib/velux.tcl

proc log_environment {} {
	global env
	velux::write_log 4 "=== Environment ====================="
	foreach key [array names env] {
		velux::write_log 4 "${key}=$env($key)"
	}
	velux::write_log 4 "====================================="
}

proc log_arguments {} {
	global argv
	velux::write_log 4 "=== Arguments ======================="
	foreach arg $argv {
		velux::write_log 4 "${arg}"
	}
	velux::write_log 4 "====================================="
}

proc usage {} {
	global argv0
	puts stderr ""
	puts stderr "usage: ${argv0} <window-id> <command> \[parameter\]..."
	puts stderr ""
	puts stderr "possible commands:"
	puts stderr "  set_window \[level\]   set window to level"
	puts stderr "  set_shutter \[level\]  set shutter to level"
	puts stderr "  window_close_event     window close event (reed contact)"
	puts stderr ""
}

proc main {} {
	global argc
	global argv
	global env
	
	log_environment
	log_arguments
	
	set window_id [string tolower [lindex $argv 0]]
	set cmd [string tolower [lindex $argv 1]]
	
	if {$cmd == "set_window" || $cmd == "set_shutter"} {
		set target_level 0.0
		if {$argc >= 3} {
			set target_level [expr {[lindex $argv 2] / 100.0}]
		} elseif { [info exists ::env(CUXD_VALUE) ] } {
			set target_level [expr {$env(CUXD_VALUE) / 1000.0}]
		}
		velux::write_log 4 "Window ${window_id}: ${cmd} to ${target_level}"
		if {$cmd == "set_window"} {
			velux::set_level $window_id "window" $target_level
		} elseif {$cmd == "set_shutter"} {
			velux::set_level $window_id "shutter" $target_level
		}
	} elseif {$cmd == "window_close_event"} {
		velux::write_log 1 "Window ${window_id}: ${cmd}"
		velux::window_close_event $window_id
	} else {
		usage
		exit 1
	}
	velux::write_log 4 "exiting"
}

if { [ catch {
	main
} err ] } {
	velux::write_log 1 $err
	puts stderr "ERROR: $err"
	exit 1
}
exit 0

