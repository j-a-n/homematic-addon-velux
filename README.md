# HomeMatic addon to control Velux windows and shutters
Do not use this addon in the curren state!

## Prerequisites
* This addon depends on CUxD

## Installation / configuration
* Download [addon package](https://github.com/j-a-n/homematic-addon-velux/raw/master/hm-velux.tar.gz)
* Install addon package on ccu via system control


## Close detection by reed switch
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