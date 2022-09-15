# Tasmota-SomfyRTS
Berry script to to control Somfy powered blinds using Tasmota.

## Capabilities:
- This enables you to emulate any number of Somfy RTS Remotes Control units to control any number of Somfy-powered shades/blinds that use the 433MHz Somfy RTS protocol.
- Tasmota compatibility:
  - It requires an ESP32 running tasmota32-ir.bin V12.0.2 or later.
  - It requires a 433MHz transmitter module such as the FS1000A. Ideally, the FS1000A should be modified to transmit at 433.42MHz.
  - I don't know if it can be used in conjunction with Tasmota's blinds and shutters functionality.
  - I don't know if using it with Tasmota's blinds and shutters functionality would limit it to a single Id.
- You will need some logic on the host that keeps track of the ```RollingCode```, and increments it each time you send a command.
  - You could add code to bRFsendCustom_V1.be to do this for you on the ESP32, but (1) it must use the ESPs' persistent storage, and (2) you need to maintain a separate RollingCode for each Id that you use.
  
## To demonstrate operation:
- Set up the Tasmota device:
  - Take an ESP32 module and install tasmota32-ir.bin V12.0.2 or later.
  - Upload these scripts ```bRFsendCustom_V1.be``` and ```autoexec.be``` to Tasmota's file system. (These scripts will be here soon)
    - From the Tasmota WebUI: Consoles > Manage File system.
  - Configure a GPIO pin for IRsend.
    - From the Tasmota WebUI: Configuration > Configure Module.
  - Connect the ```Data``` pin of an FS1000A 433MHz transmitter module to the IRsend pin of the ESP32.
    - Also connect ```GND``` and ```Vcc``` of the FS1000A to the ```GND``` and ```5V``` pins of the ESP32.
    - If this is an unmodified 433.92 MHz FS1000A, then ensure the FS1000A is within 1 meter of the Somfy blind.
- Pair the ESP32/Tasmota with the blind:
  - Take your existing Somfy remote control, and press and hold the PROG button for 2 seconds. The blind should jog up and down.
  - Execute this Tasmota command: ```RFtxSMFY {"Id":123,"RollingCode":1,"Button":8}```. The blind should jog up and down.
    - From the Tasmota WebUI: Consoles > Console. Paste in this command.
    - You can also use mqtt or http in the normal Tasmota syntax.
      - e.g. on a Linux machine: ```mosquitto_pub -t cmnd/my-esp-module/RFtxSMFY -m '{"Id":123,"RollingCode":1,"Button":8}'```
    - The blind is now paired with this virtual controller with the Id 123.
    - Repeat this procedure with a different Id for each blind you want to control.
- Try controlling the blind:
  - Roll up: ```RFtxSMFY {"Id":123,"RollingCode":2,"Button":2}```
  - Roll down: ```RFtxSMFY {"Id":123,"RollingCode":3,"Button":4}```
  - Remember to increment the RollingCode each time you issue a command.
  
  ## Command parameters
  - ```RFtxSMFY {"Id":123,"RollingCode":6,"Button":2,"StopAfterMs":2500}```
  - ```Id``` The Id of this virtual controller; you will pair the blind with this Id. It should be different to the Id of any other controllers you have. Use as many Ids as you need.
  - ```RollingCode``` For each Id that you use, increment the rolling code each time you send a command. This is part of the Somfy RTS protocol.
  - ```Button``` The buttons on the Somfy Remobe Control: Stop/Up/Down/Prog = 1/2/4/8
  - ```StopAfterMs``` (optional) Can be used to move a blind for a defined number of milliseconds. Increment the RollingCode by two after using this.
  

