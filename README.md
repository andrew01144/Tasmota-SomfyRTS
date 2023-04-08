# Tasmota-SomfyRTS
A Berry script to to control Somfy powered blinds using Tasmota.

## Capabilities
- It emulates any number of Somfy RTS Remote Control units to control any number of Somfy-powered shades/blinds that use the 433MHz Somfy RTS protocol.
- It requires:
  - An ESP32 module running tasmota32-ir.bin V12.0.2 or later.
    - Do not use the single core -S2 and -C3 parts; WiFi activity can disrupt the timing of the signal.
  - A 433MHz transmitter module.
    - Simplest is the FS1000A. However, it should be modified to transmit at 433.42MHz.
    - Or the CC1101, which has a programmable transmit frequency.
- Tasmota compatibility:
  - It is implemented as a Tasmota Berry script. It is *not* a fork of Tasmota, so should be compatible with future versions of Tasmota.
  - It requires an ESP32 in order to provide the Berry scripting language.
  - It requires the -ir version of the tasmota32 binary in order to support IRsend's Raw format, because it uses Tasmota's IRsend command to generate the Somfy RTS protocol bit stream. 
  - It can be integrated into Tasmota's [Shutters and Blinds](https://tasmota.github.io/docs/Blinds-and-Shutters/) functionality.


 
> ## Getting started
> - Set up the Tasmota device:
>   - Take an ESP32 module and install tasmota32-ir.bin V12.0.2 or later.
>   - Upload these scripts ```RFtxSMFY.be``` and ```autoexec.be``` to Tasmota's file system.
>     - From the Tasmota WebUI: Consoles > Manage File system > Choose File.
>     - This adds the ```RFtxSMFY``` command to Tasmota.
>   - Configure a GPIO pin for IRsend.
>     - From the Tasmota WebUI: Configuration > Configure Module.
>   - Connect the ESP32 to the transmitter module
>     - If using an FS1000A, connect the ESP32's ```GND, 5V, IRsend``` to the FS1000A's ```GND, Vcc, Data```. If this is an unmodified 433.92 MHz FS1000A, then ensure it is within 1 meter of the Somfy blind. More details [here](#using-an-fs1000a). 
>     - If using a CC1101, follow [these instructions](#using-a-cc1101).
> - Pair the ESP32/Tasmota with the blind:
>   - Assign an Id to virtual controller #1 in the ESP32
>     - Execute this Tasmota command: ```RFtxSMFY {"Idx":1,"Id":123,"RollingCode":1}```
>     - *To execute a Tasmota command, paste it into the WebGUI Console, or send it via http or mqtt.*
>   - Take your existing Somfy remote control, and press and hold the PROG button for 2 seconds. The blind should jog up and down.
>     - *The PROG button is on the back of the controller and requires a paperclip to press it.*
>   - Execute this Tasmota command: ```RFtxSMFY {"Idx":1,"Button":8}```. The blind should jog up and down.
>     - The blind is now paired with virtual controller #1 with the Id 123.
>     - Repeat this procedure with a different Idx and Id for each blind you want to control.
> - Try controlling the blind:
>   - Roll up: ```RFtxSMFY {"Idx":1,"Button":2}```
>   - Roll down: ```RFtxSMFY {"Idx":1,"Button":4}```
> - Next steps
>   - Build a Tasmota image with [custom options](#building-a-tasmota-image-with-custom-options) and select ```modFreq = 0```.
>   - Integrate with [Tasmota Shutters and Blinds](#integration-with-tasmota-shutters-and-blinds).

### Executing Tasmota commands
This is standard Tasmota procedure. There are 3 ways to execute a command.
- From the Tasmota WebUI: Consoles > Console: Paste in the command ```RFtxSMFY {"Idx":1,"Button":2}```
- From Linux, using mqtt: ```mosquitto_pub -t cmnd/my-smfy-esp/RFtxSMFY -m '{"Idx":1,"Button":2}'```
- From Linux, using http: ```curl -s --data-urlencode 'cmnd=RFtxSMFY {"Idx":1,"Button":2}' http://192.168.1.123/cm```

## The RFtxSMFY command
There are two ways of using ```RFtxSMFY```: Stateful or Stateless.
- **Stateful**: Supports 8 virtual controllers. ```RollingCode``` is maintained on the ESP32 and uses its persistent memory. Stateful commands require the ```Idx``` parameter. Examples:
  - ```RFtxSMFY {"Idx":1,"Id":123,"RollingCode":1}``` Initialize virtual controller #1 with Id 123 and start its rolling code at 1. Always set both parameters in this command.
  - ```RFtxSMFY {"Idx":1,"Button":2}``` Transmit 'Up' from virtual controller #1.
  - ```RFtxSMFY {"Idx":1,"Button":4,"StopAfterMs":2500}``` Transmit 'Down' from virtual controller #1, then transmit 'Stop' after 2.5 seconds.
  - You may need to know the current values of ```Id``` and ```RollingCode```, for example, to transfer an existing virtual controller to a different ESP32. These values can be seen by viewing the ```_persist.json``` file in the Tasmota Manage File system Console.
  - *I don't use Stateful mode, so it is less well tested than Stateless mode.*
- **Stateless**: Supports any number of virtual controllers. The RollingCode must be maintained on the host that sends the commands to Tasmota. Increment the RollingCode once after each command, and twice for StopAfterMs. Stateless commands do not use the ```Idx``` parameter. Examples:
  - ```RFtxSMFY {"Id":123,"RollingCode":6,"Button":2}```
  - ```RFtxSMFY {"Id":123,"RollingCode":7,"Button":4,"StopAfterMs":2500}```
- **Parameters**
  - ```Idx``` (1-8) The virtual controller number/index.
  - ```Id``` (1-16777215) The Id of this virtual controller; you will pair the blind with this Id. It should be different from the Id of any other controllers you have. Use as many Ids as you need. In Stateful mode, this is stored in persistent memory.
  - ```RollingCode``` (0-65535) The Somfy RTS protocol sends a 'rolling code' that increments by 1 each time a command is transmitted. If there is a significant gap between the rolling code you transmit and the rolling code it last recieved, it will ignore the command. Normally, start at 1. In Stateful mode, this is stored in persistent memory.
  - ```Button``` The buttons on the Somfy Remote Control: Stop/Up/Down/Prog = 1/2/4/8
  - ```StopAfterMs``` Can be used to move a blind for a defined number of milliseconds.
  - ```Gap``` Gap between frames in milliseconds. Default 27.
  - ```nFrames``` Number of frames to send. Default 3.
    - ```{"Idx":1,"Button":8,"nFrames":12,"Gap":72}``` Generates a long press (2 sec) PROG, may be useful for unlearning an Id.
  - ```UseSomfyFreq``` (1|0) For use with CC1101, 1: Transmit at 433.42MHz (default), 0: Transmit at 433.92MHz. Can be useful for troubleshooting.

## Building a Tasmota image with custom options

```tasmota32-ir.bin``` can be used to demonstrate the base functionality of sending Somfy commands, but you will need to build an image with custom options to get the all the functionality you might need. Creating an image with custom options is very easy using the excellent TasmoCompiler, or you can use ```tasmota32gen_custom-ir.bin``` included in this project. When building your own image, you will need these features:
- IR Support - to get the IRsend *raw* capability.
- Tasmota Shutters and Blinds. This is included in most images, but is excluded from the pre-compiled ```tasmota32-ir.bin```.
- ```IR_SEND_USE_MODULATION 0``` to provide an unmodulated IRsend signal. See [discussion](#the-irsend-signal) below.

Go to the [TasmoCompiler](https://gitpod.io/#https://github.com/benzino77/tasmocompiler)<br>
Select features: ```ESP32: Generic```, Add: ```IR Support``` _(Shutters is included by default)_.<br>
Add these custom parameters:
```
#define CODE_IMAGE_STR "custom-ir+nm"
#define IR_SEND_USE_MODULATION 0
```
Download ```firmware.bin```.<br>
In Tasmota, Upgrade Firmware using this image. Then set ```modFreq = 0``` in ```RFtxSMFY.be``` by editing this line:
```
var modFreq = 0
```

---

# 433MHz Transmitter Modules

## Background

Somfy RTS transmits at 433.42MHz, compared to the more usual 433.92MHz. You can use a module that transmits at 433.92MHz, but the range will be limited to a few meters. For a proper solution, you will need a 433.42MHz transmitter. You could use the popular FS1000A and change the Crystal/SAW to 433.42MHz, or use the CC1101 which has a software programmable frequency. Some people prefer the CC1101 as it avoids performing surgery on the FS1000A.

## Using an FS1000A
In my opinion, the FS1000A transmitter module is the easiest solution, with just 3 wires to the ESP32. You can use an unmodified (433.92MHz) module for testing, as long as you are within about 2m of the Somfy. To obtain full range, change the Crystal/SAW to 433.42MHz. Search eBay for "433 Crystal SAW". With only 3 legs, the component is reasonably easy to de-solder without any special tools. The FS1000A is also very tolerant of the [glitches in the IRsend signal](#the-irsend-signal).

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

The CC1101 is configured via an SPI interface which needs to be wired to the ESP32. Choose the GPIO pins you want to use for this. I do not use the ESP32's SPI interface; I simply bit-bang GPIO pins to implement the SPI protocol, so you can choose pretty much any pins that are convenient. Using the Tasmota WebUI, choose Configuration > Configure Module, and define the SSPI (Software SPI) and IRsend pins.

_The Relay GPIOs in the screenshot below are optional, and are defined for integration with the Tasmota Shutter and Blinds functionality. They are not wired to anything._

For example:

![image](https://user-images.githubusercontent.com/18399286/195830142-52cdb940-b715-478a-81d9-111054d5ddaf.png)

Then wire these 7 pins to the CC1101 module:

| CC1101 | ESP32     |
|--------|-----------|
| 3V3    | 3V3       |
| SCK    | SSPI SCLK |
| MISO   | SSPI MISO |
| MOSI   | SSPI MOSI |
| CSN    | SSPI CS   |
| GDO0   | IRsend    |
| GDO2   | not used  |
| GND    | GND       |

### Selecting a different frequency
By default, the CC1101 will be configured to the Somfy frequency 433.42MHz. For troubleshooting, it can be useful to use the more standard 433.92MHz to work with other receivers. This can be set using the command ```RFtxSMFY {"UseSomfyFreq":0}```. To switch back to 433.42MHz use ```RFtxSMFY {"UseSomfyFreq":1}```,  or simply reboot the ESP32.

---

# Integration with Tasmota Shutters and Blinds

You may want to use [Tasmota's support for Shutters and Blinds](https://tasmota.github.io/docs/Blinds-and-Shutters) to allow you to use commands like ```ShutterPosition1 30``` to set the blind to 30%. Tasmota can keep track of the position of the blind, and if it knows how long it takes to open and close it, it can send move-delay-stop commands to move the blind to a specific position. These instructions draw heavily from [GitHobi](https://github.com/GitHobi/Tasmota/wiki/Somfy-RTS-support-with-Tasmota#configuring-tasmota).

### Enable the rules

Edit RFtxSMFY.be to enable Tasmota Shutter integration.
```
var tasShutters = 1   # Create rules to make Tasmota Shutters generate Somfy commands.
```
### Build a Tasmota image with IR and Shutter support

tasmota32-ir.bin does not include support for Shutters, so you will need to build a custom Tasmota binary that includes both IR and Shutters using [this procedure](#building-a-tasmota-image-with-custom-options).

### Tasmota Configuration

For each of the Blinds/Shutters, you need to configure two relays to unused GPIOs.
In this example, I have two blinds, so I will need to assign 4 GPIOs.
In the Tasmota WebUI, go to Configuration > Configure Module, and set something like this:

![image](https://user-images.githubusercontent.com/18399286/194704956-8ba6e670-f78d-4bf7-aa54-30386042d936.png)


Then we need to enable Shutter support: ```SetOption80 1```.

Now tell Tasmota that we have two shutters: ```ShutterRelay1 1``` ```ShutterRelay2 3```. This means that shutter1 is controlled by relay1 (and 2) - and shutter2 is controlled by relay3 (and 4).

Configure ```ShutterMode1 1``` ```ShutterMode2 1```. This means that Relay1 and Relay3 move the shutters Up, and Relay2 and Relay4 move the shutters Down.

Finally, we need to tell Tasmota how many seconds it takes to open and close the Shutters: ```ShutterOpenDuration1 9.5``` ```ShutterCloseDuration1 8.5``` ```ShutterOpenDuration2 12.3``` ```ShutterCloseDuration1 10.9```.

Now, try some of these commands: ```ShutterOpen1``` ```ShutterPosition1 50``` ```ShutterClose1```.

### How the rules work
Tasmota controls the blinds by switching the assigned relays on and off. RFtxSMFY.be sets up rules so that when Tasmota switches an assigned realy, an RFtxSMFY command is generated to move the blind. You don't need to enter these rules, they are included in the RFtxSMFY.be script.

The logic:<br>
When relay1 turns on, we need to send a Somfy up command.<br>
When relay2 turns on, we need to send a Somfy down command.<br>
When relay1 or relay2 turn off, we might need to send a Somfy stop command, but only if we think the shutter is currently moving.<br>
If we send a 'Stop' when the shutter is stopped, the Somfy will interpret it as a 'Go-My' command.<br>
So, don't send a 'Stop' if the shutter position is 0% or 100%.<br>
This requires that the shutter has been reasonably calibrated, eg: ```ShutterOpenDuration1 9.5``` ```ShutterCloseDuration1 8.5```.<br>



---

# The IRsend signal

This script uses IRsend to generate the Somfy protocol bitstream. I use IRsend, as it is the only way I know to get Tasmota to generate an accurately timed bitstream. Using Berry's gpio.digital_write() and tasmota.delay() does not have the required precision. IR signals use a 38kHz a carrier that is modulated by the bitstream. But we don't want this 38kHz carrier. I have three options to handle this:

- Use a 1kHz carrier, and use marks of less than 500us (default).<br>
At 1kHz, marks shorter than 500us will not show the carrier. Obviously, the spaces do not show any carrier.
For marks longer than 500us, I use multiple shorter marks with zero-length spaces between them. eg: 1500 becomes 490,0,490,0,490
Sadly, the zero-length spaces actually appear as 6us glitches. The FS1000A ignores the glitches. The CC1101 transmits some of the glitches, but the Somfy ignores them.
You can optionally add a small RC low pass filter to the pin to remove the glitches (1k2, 47nF).<br>
In ```RFtxSMFY.be```, set modFreq = 1 to enable the multi-mark logic.

- Use the default 38k carrier.<br>
It turns out that the FS1000A ignores the 38kHz modulation (not suitable for CC1101).<br>
In ```RFtxSMFY.be```, set modFreq = 0 to select default 38kHz carrier, and disable the multi-mark logic.

- Disable the carrier (preferred).<br>
Build the Tasmota image with "#define IR_SEND_USE_MODULATION 0".<br>
In ```RFtxSMFY.be```, set modFreq = 0 to disable the multi-mark logic.

![image](https://user-images.githubusercontent.com/18399286/194718690-cd2effd2-5192-44c0-89d2-3886c64b0a8f.png)

The top trace is the IRsend pin of the ESP which drives the GDO0 pin of the CC1101. The lower trace is the signal received by an RXB14.

---

# My usage

I have been using this solution since July 2022 with 100% reliability. I use the Stateless mode, with my host computer maintaining the rolling code, current position, and calculating the move-time to travel to the requested position. I use an FS1000A modified to 433.42MHz, with an RC filter on the IRsend pin. Prior to this, I used an ESP8266 running my own code since May 2018, but have recently been on a mission to eliminate my own firmware from devices in my house.

The other capabilities (Stateful mode, Integration with Tasmota Shutters and Blinds, CC1101, IR_SEND_USE_MODULATION=0, and using unfiltered IRsend) have all been tested, but not with months of usage.


---
