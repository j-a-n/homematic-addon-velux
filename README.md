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
                                  |         |            Velux remote control 3UR B01, 946949, 860963 or KLI 110
                                  +---------+               +----------------------------------+
       protect. diode (optional)   |   |   |   3.3V         |                                  |
  24V------+------->|--------------+   |   +----------------|3V          up     stop   down    |
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

## Installation / configuration
* This addon depends on CUxD.
* Download [addon package](https://github.com/j-a-n/homematic-addon-velux/raw/master/hm-velux.tar.gz).
* Install addon package on ccu via system control.
* Open the configuration page and add your windows and shutters.

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