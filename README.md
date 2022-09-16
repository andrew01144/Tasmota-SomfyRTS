# Tasmota-SomfyRTS
A Berry script to to control Somfy powered blinds using Tasmota.

## Capabilities
- It emulates any number of Somfy RTS Remotes Control units to control any number of Somfy-powered shades/blinds that use the 433MHz Somfy RTS protocol.
- It requires:
  - An ESP32 module running tasmota32-ir.bin V12.0.2 or later.
  - A 433MHz transmitter module such as the FS1000A. Ideally, the FS1000A should be modified to transmit at 433.42MHz.
- Tasmota compatibility:
  - It requires an ESP32 in order to provide the Berry scripting language.
  - It requires the -ir version of the tasmota binary in order to provide IRsend's Raw format.
  - I don't know if it can be integrated into Tasmota's blinds and shutters functionality.

  
## To demonstrate operation
- Set up the Tasmota device:
  - Take an ESP32 module and install tasmota32-ir.bin V12.0.2 or later.
  - Upload these scripts ```bRFsendCustom_V3.be``` and ```autoexec.be``` to Tasmota's file system. (Not posted yet. Ping me if you need them.)
    - From the Tasmota WebUI: Consoles > Manage File system > Choose File.
    - This adds the ```RFtxSMFY``` command to Tasmota.
  - Configure a GPIO pin for IRsend.
    - From the Tasmota WebUI: Configuration > Configure Module.
  - Connect the ```Data``` pin of an FS1000A 433MHz transmitter module to the IRsend pin of the ESP32.
    - Also connect ```GND``` and ```Vcc``` of the FS1000A to the ```GND``` and ```5V``` pins of the ESP32.
    - If this is an unmodified 433.92 MHz FS1000A, then ensure the FS1000A is within 1 meter of the Somfy blind.
- Pair the ESP32/Tasmota with the blind:
  - Assign an Id to virtual controller #1 in the ESP32
    - Execute this Tasmota command: ```RFtxSMFY {"Idx":1,"Id":123,"RollingCode",1}```
    - *To execute a Tasmota command, paste it into the WebGUI Console, or send it via http or mqtt.*
  - Take your existing Somfy remote control, and press and hold the PROG button for 2 seconds. The blind should jog up and down.
    - The PROG button is on the back of the controller and requires a paperclip to press it.
  - Execute this Tasmota command: ```RFtxSMFY {"Idx":1,"Button":8}```. The blind should jog up and down.
    - The blind is now paired with virtual controller #1 with the Id 123.
    - Repeat this procedure with a different Idx and Id for each blind you want to control.
- Try controlling the blind:
  - Roll up: ```RFtxSMFY {"Idx":1,"Button":2}```
  - Roll down: ```RFtxSMFY {"Idx":1,"Button":4}```
    
## Command parameters
There are two ways of using ```RFtxSMFY```: Stateful or Stateless.
- Stateful: Supports 8 virtual controllers. ```RollingCode``` is maintained on the ESP32 and uses its persistent memory. Examples:
  - ```RFtxSMFY {"Idx":1,"Id":123,"RollingCode",1}``` Set virtual controller #1 to have Id 123 and start its rolling code at 1.
  - ```RFtxSMFY {"Idx":1,"Button",2}``` Transmit 'Up' from virtual controller #1.
  - ```RFtxSMFY {"Idx":1,"Button",4,"StopAfterMs":2500}``` Transmit 'Down' from virtual controller #1, then transmit 'Stop' after 2.5 seconds.
  - ```Idx``` (1-8) The virtual controller number/index.
  - ```Id``` (1-16777215) The Id of this virtual controller; you will pair the blind with this Id. It should be different from the Id of any other controllers you have. Use as many Ids as you need. In Stateful mode, this is stored in persistent memory.
  - ```RollingCode``` (0-65535) The Somfy RTS protocol sends a 'rolling code' that increments by 1 each time a command is transmitted. If there is a significant gap between the rolling code you transmit and the rolling code it last recieved, it will ignore the command. Normally, start at 1. In Stateful mode, this is stored in persistent memory.
  - ```Button``` The buttons on the Somfy Remote Control: Stop/Up/Down/Prog = 1/2/4/8
  - ```StopAfterMs``` Can be used to move a blind for a defined number of milliseconds.
  - *I don't use Stateful mode, so it is less well tested than Stateless mode.*
- Stateless: Supports any number of virtual controllers. The RollingCode must be maintained on the host that sends the commands to Tasmota. Increment the RollingCode once after each command, and twice for StopAfterMs. Stateless commands do not use the ```Idx``` parameter. Examples:
  - ```RFtxSMFY {"Id":123,"RollingCode":6,"Button":2}```
  - ```RFtxSMFY {"Id":123,"RollingCode":7,"Button":4,"StopAfterMs":2500}```
