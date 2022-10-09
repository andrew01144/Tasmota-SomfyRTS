# Tasmota-SomfyRTS
A Berry script to to control Somfy powered blinds using Tasmota.

## Capabilities
- It emulates any number of Somfy RTS Remote Control units to control any number of Somfy-powered shades/blinds that use the 433MHz Somfy RTS protocol.
- It requires:
  - An ESP32 module running tasmota32-ir.bin V12.0.2 or later.
  - A 433MHz transmitter module.
    - Simplest is the FS1000A. However, it should be modified to transmit at 433.42MHz.
    - Or the CC1101, which has a programmable transmit frequency.
- Tasmota compatibility:
  - It is implemented as a Tasmota Berry script. It is *not* a fork of Tasmota, so should be compatible with future versions of Tasmota.
  - It requires an ESP32 in order to provide the Berry scripting language.
  - It requires the -ir version of the tasmota32 binary in order to support IRsend's Raw format, because it uses Tasmota's IRsend command to generate the Somfy RTS protocol bit stream. 
  - It can probably be integrated into Tasmota's  [Shutters and Blinds](https://tasmota.github.io/docs/Blinds-and-Shutters/) functionality by following [these instructions](#integration-with-tasmota-shutters-and-blinds), but this will require a custom build of Tasmota to include both IR and Shutters.

  
## To demonstrate operation
- Set up the Tasmota device:
  - Take an ESP32 module and install tasmota32-ir.bin V12.0.2 or later.
  - Upload these scripts ```RFtxSMFY.be``` and ```autoexec.be``` to Tasmota's file system.
    - From the Tasmota WebUI: Consoles > Manage File system > Choose File.
    - This adds the ```RFtxSMFY``` command to Tasmota.
  - Configure a GPIO pin for IRsend.
    - From the Tasmota WebUI: Configuration > Configure Module.
  - Connect the ```Data``` pin of an FS1000A 433MHz transmitter module to the IRsend pin of the ESP32.
    - Also connect ```GND``` and ```Vcc``` of the FS1000A to the ```GND``` and ```5V``` pins of the ESP32.
    - If this is an unmodified 433.92 MHz FS1000A, then ensure the FS1000A is within 1 meter of the Somfy blind.
    - If using a CC1101, follow [these instructions](#using-a-cc1101).
- Pair the ESP32/Tasmota with the blind:
  - Assign an Id to virtual controller #1 in the ESP32
    - Execute this Tasmota command: ```RFtxSMFY {"Idx":1,"Id":123,"RollingCode":1}```
    - *To execute a Tasmota command, paste it into the WebGUI Console, or send it via http or mqtt.*
  - Take your existing Somfy remote control, and press and hold the PROG button for 2 seconds. The blind should jog up and down.
    - *The PROG button is on the back of the controller and requires a paperclip to press it.*
  - Execute this Tasmota command: ```RFtxSMFY {"Idx":1,"Button":8}```. The blind should jog up and down.
    - The blind is now paired with virtual controller #1 with the Id 123.
    - Repeat this procedure with a different Idx and Id for each blind you want to control.
- Try controlling the blind:
  - Roll up: ```RFtxSMFY {"Idx":1,"Button":2}```
  - Roll down: ```RFtxSMFY {"Idx":1,"Button":4}```

### Executing Tasmota commands
This is standard Tasmota procedure. There are 3 ways to execute a command.
- From the Tasmota WebUI: Consoles > Console: Paste in the command ```RFtxSMFY {"Idx":1,"Button":2}```
- From Linux, using mqtt: ```mosquitto_pub -t cmnd/my-smfy-esp/RFtxSMFY -m '{"Idx":1,"Button":2}'```
- From Linux, using http: ```curl -s --data-urlencode 'cmnd=RFtxSMFY {"Idx":1,"Button":2}' http://192.168.1.123/cm```

## The RFtxSMFY command
There are two ways of using ```RFtxSMFY```: Stateful or Stateless.
- **Stateful**: Supports 8 virtual controllers. ```RollingCode``` is maintained on the ESP32 and uses its persistent memory. Stateless commands require the ```Idx``` parameter. Examples:
  - ```RFtxSMFY {"Idx":1,"Id":123,"RollingCode":1}``` Initialize virtual controller #1 with Id 123 and start its rolling code at 1. Always set both parameters in this command.
  - ```RFtxSMFY {"Idx":1,"Button":2}``` Transmit 'Up' from virtual controller #1.
  - ```RFtxSMFY {"Idx":1,"Button":4,"StopAfterMs":2500}``` Transmit 'Down' from virtual controller #1, then transmit 'Stop' after 2.5 seconds.
  - You may need to know the current values of ```Id``` and ```RollingCode```, for example, to transfer an existing virtual controller to a different ESP32. These values can be seen by viewing the ```_persist.json``` file in the Tasmota Manage File system Console.
  - *I don't use Stateful mode, so it is less well tested than Stateless mode.*
- **Stateless**: Supports any number of virtual controllers. The RollingCode must be maintained on the host that sends the commands to Tasmota. Increment the RollingCode once after each command, and twice for StopAfterMs. Stateless commands do not use the ```Idx``` parameter. Examples:
  - ```RFtxSMFY {"Id":123,"RollingCode":6,"Button":2}```
  - ```RFtxSMFY {"Id":123,"RollingCode":7,"Button":4,"StopAfterMs":2500}```
- Parameters
  - ```Idx``` (1-8) The virtual controller number/index.
  - ```Id``` (1-16777215) The Id of this virtual controller; you will pair the blind with this Id. It should be different from the Id of any other controllers you have. Use as many Ids as you need. In Stateful mode, this is stored in persistent memory.
  - ```RollingCode``` (0-65535) The Somfy RTS protocol sends a 'rolling code' that increments by 1 each time a command is transmitted. If there is a significant gap between the rolling code you transmit and the rolling code it last recieved, it will ignore the command. Normally, start at 1. In Stateful mode, this is stored in persistent memory.
  - ```Button``` The buttons on the Somfy Remote Control: Stop/Up/Down/Prog = 1/2/4/8
  - ```StopAfterMs``` Can be used to move a blind for a defined number of milliseconds.
  - ```UseSomfyFreq``` (1|0) For use with CC1101, 1: Transmit at 433.42MHz (default), 0: Transmit at 433.92MHz. Can be useful for troubleshooting.


---
---


# 433MHz Transmitter Modules

## Background

Somfy RTS transmits at 433.42MHz, compared to the more usual 433.92MHz. You can use a module that transmits at 433.92MHz, but the range will be limited to a few meters. For a proper solution, you will need a 433.42MHz transmitter. You could use the popular FS1000A and change the Crystal/SAW to 433.42MHz, or the CC1101 which has a software programmable frequency.

## Using an FS1000A
Easy, 3-wire connection. Change the Crystal/SAW to 433.42MHz.

| FS1000A | ESP32    |
|---------|----------|
| 5V      | 5V       |
| Data    | IRsend   |
| GND     | GND      |

## Using a CC1101

Edit ```RFtxSMFY.be``` to enable CC1101 support.
```
var hasCC1101 = 1                   # Set to 0 for other Tx modules such as FS1000A.
```

The CC1101 is configured via an SPI interface which needs to be wired to the ESP32. Choose the GPIO pins you want to use for this. I do not use the ESP32's SPI interface; I simply bit-bang GPIO pins to implement the SPI protocol, so you can choose pretty much any pins that are convenient. Using the Tasmota WebUI, choose Configuration > Configure Module, and define the SPI and IRsend pins.

_The Relay GPIOs are optional, and are defined for integration with the Tasmota Shutter and Blinds functionality. They are not wired to anything._

For example:

![image](https://user-images.githubusercontent.com/18399286/194719453-22dfa4a0-f396-4aeb-9ece-312576d346e7.png)

Then wire these pins to the CC1101 module:

| CC1101 | ESP32    |
|--------|----------|
| 3V3    | 3V3      |
| SCK    | SPI CLK  |
| MISO   | SPI MISO |
| MOSI   | SPI MOSI |
| CSN    | SPI CS   |
| GDO0   | IRsend   |
| GDO2   | not used |
| GND    | GND      |

## Selecting a different frequency
By default, the CC1101 will be configured to the Somfy frequency 433.42MHz. For troubleshooting, it can be useful to use the more standard 433.92MHz to work with other receivers. This can be set using the command ```RFtxSMFY {"UseSomfyFreq":0}```. To switch back to 433.42MHz use ```RFtxSMFY {"UseSomfyFreq":1}```,  or simply reboot the ESP32.

---

# Integration with Tasmota Shutters and Blinds

Edit RFtxSMFY.be to enable tasmotaShutterIntegration.
```
var tasmotaShutterIntegration = 1   # Create rules to make Tasmota Shutters generate Somfy commands.
```
tasmota32-ir.bin does not include support for Shutters, so you will need to build a custom Tasmota binary that includes both IR and Shutters.
> Go to the excellent [TasmoCompiler](https://gitpod.io/#https://github.com/benzino77/tasmocompiler)<br>
Select features: ```ESP32: Generic```, Add: ```IR Support``` _(Shutters is included by default)_.<br>
Custom parameters: ```#define CODE_IMAGE_STR "custom-ir"```<br>
Download firmware.bin

For each of the Blinds/Shutters, you need to configure two relays to unused GPIOs. In the Tasmota WebUI, go to Configuration > Configure Module, and set something like this:

![image](https://user-images.githubusercontent.com/18399286/194704956-8ba6e670-f78d-4bf7-aa54-30386042d936.png)

Then run these commands:
```
SetOption80 1       # Enable Shutter mode.

ShutterRelay1 1     # Shutter1 will use relay1 and relay2.
ShutterMode1 1      # Mode 1: relay1 = up, relay2 = down.

# These commands should operate Shutter1
ShutterOpen1
ShutterPosition1 50
ShutterClose1

ShutterRelay2 3     # Shutter2 will use relay 3 and relay4.
ShutterMode2 1      # Mode 1: relay3 = up, relay4 = down.
```

You should now calibrate the shutter. At minimum, set the open and close times in seconds.
```
ShutterOpenDuration1 9.5
ShutterCloseDuration1 8.5
```

To do the job properly, consult the calibration instructions and videos [here](https://tasmota.github.io/docs/Blinds-and-Shutters/#button-control).

## How it works
This uses the method described [here](https://github.com/GitHobi/Tasmota/wiki/Somfy-RTS-support-with-Tasmota#using-rules-to-control-blinds), except that the rules are implemented in Berry rather than Tasmota rules.

Tasmota Shutter1 (in ShutterMode 1) uses relay1 for up and relay2 for down.
When relay1 turns on, we need to send a Somfy up command.
When relay2 turns on, we need to send a Somfy down command.
When relay1 or relay2 turn off, we might need to send a Somfy stop command, but only if we think the shutter is currently moving.
If we send a 'Stop' when the shutter is stopped, the Somfy will interpret it as a 'Go-My' command.
So, don't send a 'Stop' if the shutter position is 0% or 100%.
This requires that the shutter has been reasonably calibrated, eg: ```ShutterOpenDuration1 9.5``` ```ShutterCloseDuration1 8.5```.


---

# The IRsend signal

This script uses IRsend to generate the Somfy protocol bitstream.
- I use IRsend, as it is the only way I know of to Tasmota to generate an accurately timed bitstream. Using Berry's gpio.digital_write() and tasmota.delay() does not have the required precision.
- By default, the IRsend signal is modulated at 38kHz. Interestingly, you can feed that directly to an FS1000A and it ignores the modulation. However, I decided not to do that.
- I set the modulation frequency to as low as it allows, which is 1kHz, so any "Mark" less than 500us will not show any modulation. If IRsend had a 'no modulation' option, that would be perfect.
- To get longer Marks, I send multiple adjacent Marks. Sadly, the Marks have a tiny Spaces between them, and these appear as glitches on the IRsend signal.

![image](https://user-images.githubusercontent.com/18399286/194718690-cd2effd2-5192-44c0-89d2-3886c64b0a8f.png)

The top trace is the IRsend out from the ESP. The lower trace is the signal as received by an RXB14. The FS1000A filters out the glitches, but the CC1101 transmits some of them. As far as I can tell, when these are transmitted by a CC1101, the Somfy filters them out. So, all is ok.

If you want a completely clean signal, you can add a simple RC filter to the IRsend pin.

---
