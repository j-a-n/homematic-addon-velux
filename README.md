# HomeMatic addon to control velux windows and shutters

## Needed hardware
You will need one original velux remote control for each shutter and each window you want to control.

Register the remote control with the window or shutter you want to operate.
Disassemble the remote control, you will just need the circuit board.
Solder one wire to the up and one to the down button contact.
You do not need to connect the stop contact.

Connect each wire to an open collector output of a HomeMatic IO-module (i.e. HMW-IO-12-Sw14-DR).
Give the ouputs a descriptive name (i.e. "BATHROOM_WINDOW_UP" and "BATHROOM_WINDOW_DOWN") to be able to indentify the outputs in the later configuration.

In order to get rid of the batteries, you can use a DC/DC converter (i.e. 7803SRC) to connect your remote control to 24V.

```
                                  +---------+
                                  |         |
                                  | 7803SRC |
                                  |         |
                                  |         |       Velux remote control 3UR B01, 946949, 860963 or KLI 110
                                  +---------+               +----------------------------------+
       protect. diode (optional)   |   |   |   3.3V         |                                  |
  24V------+------->|--------------+   |   +----------------|3V          down   stop   up      |
           |                           |                    |            (+)    ( )    (+)     |
  GND--+---)---------------------------+--------------------|GND          |             |      |
       |   |                                                |             |             |      |
       |   |                                                +------------ | ----------- | -----+
       |   |        +---------------------------+                         |             |
       |   +--------|24V                     OC1|-------------------------+             |
       +------------|GND                     OC2|---------------------------------------+
                    |    HMW-IO-12-Sw14-DR      |
                    |                           |
```

![velux-rc](https://github.com/j-a-n/homematic-addon-velux/raw/master/doc/velux-rc.png)

## Installation / configuration
* This addon depends on CUxD.
* Download [addon package](https://github.com/j-a-n/homematic-addon-velux/raw/master/hm-velux.tar.gz).
* Install addon package on ccu via system control.
* Open the configuration page and add your windows and shutters / blinds.
* Setup CUxD-Device

### Velux addon configuration
#### Global Config
* Button short press time in milliseconds: How long to close the remote control contact when simulating a short press command (default: 500)
* Button long press time in milliseconds: How long to close the remote control contact when simulating a long press command (default: 1500)
* Command pause time in milliseconds: Pause time between commands send to velux devices (default: 1000)

#### Window config
* Create a new window for each window and shutter combination.
* If your window doesn't have a shutter, then leave the shutter config empty.
* If you want to control a shutter only, then leave the window config empty.
 * Name: A name for the window (i.e. Bathroom window)
 * Window up button channel: Choose the channel connected to the remotes up button (i.e. BATHROOM_WINDOW_UP)
 * Window down button channel: Channel connected to down button (i.e. BATHROOM_WINDOW_DOWN)
 * Window full motion time in seconds: How long does a full window movement take (fully closed <=> fully opened).
 * Window reed switch channel (optional): Reed sensor for window close detection if available
 * Shutter up button channel: Channel connected to up button (window shutter)
 * Shutter down button channel: Channel connected to down button (window shutter)
 * Shutter full motion time in seconds: How long does a full shutter movement take (fully closed <=> fully opened).
* After adding the window, you will see an new entry in the table. Yuu will need the window id (ID) for later configuration.

### CUxD device (Universal-Control-Device)
* Create new (40) 16-channel universal control device in CUxD
 * Serialnumber: choose a free one
 * Name: choose one, i.e: `Velux control`
 * Device-Icon: whatever you want
 * Control: BLIND (Jalousie)
* Configure the new device in HomeMatic Web-UI.
* Use one channel for each window / shutter / blind.
* Configuration for a window:
 * CMD_EXEC: yes
 * CMD_SHORT `/usr/local/addons/velux/velux.tcl set_window <window-id>`
 * CMD_LONG `/usr/local/addons/velux/velux.tcl set_window <window-id>`
 * CMD_STOP `/usr/local/addons/velux/velux.tcl set_window <window-id>`
* Configuration for a shutter:
 * CMD_EXEC: yes
 * CMD_SHORT `/usr/local/addons/velux/velux.tcl set_shutter <window-id>`
 * CMD_LONG `/usr/local/addons/velux/velux.tcl set_shutter <window-id>`
 * CMD_STOP `/usr/local/addons/velux/velux.tcl set_shutter <window-id>`

## Close detection by reed switch
If window is closed by the rain sensor the saved window state will differ from the real window position.
This problem can be solved by an reed contact which is used to monitor the window state.
Just execute the following homematic script when the reed switch detects that the window was closed:
```
string stdout;
string stderr;
var source = dom.GetObject("$src$");
var channel = dom.GetObject(source.Channel());
boolean closed = !source.State();
if (closed) {
   system.Exec("/bin/tclsh /usr/local/addons/velux/velux.tcl window_close_event " # channel.Name(), &stdout, &stderr);
}
```
Please be sure to set the "window reed switch channel" in configuration.
