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

