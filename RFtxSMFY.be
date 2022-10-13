


var hasCC1101 = 0                   # Set to 0 for other Tx modules such as FS1000A.
var tasmotaShutterIntegration = 0   # Create rules to make Tasmota Shutters generate Somfy commands.




#-

 Upload this file to the Tasmota file system and load() it from autoexec.be.

 This adds the RFtxSMFY command to Tasmota to generate Somfy-RTS format packets for 433MHz RF transmission.
 Author: Andrew Russell, Sep 2022.


 This program uses Tasmota's IRsend in raw format to create the bit stream.
 To use this code:
    Use an ESP32 to get the Berry scripting language.
    Use the tasmota32-ir.bin image to get support for RAW in IRsend.
    Configure a pin for IRsend.
    Connect this pin to an FS1000A 433Mhz transmitter module.
    Optional:
        - Add this simple RC filter to the IRsend pin to remove unwanted 8us glitches/spaces.
        - The filtered signal looks better on a logic analyzer, but is optional.
        - The FS1000A Tx module ignores the 8us spaces.
        - The CC1101 Tx module appears not to ignore these (I can see them on a receiver module) but the Somfy appears to ignore them.

         ESP32                             FS1000A
            5V ------------------------>-- Vcc
        IRsend ->---/\/\/\/\----------->-- Data
                      1k2        |
                          47nF  ===
                                 |
           GND --------------------------- GND


 About the Somfy RTS protocol:
    The Somfy RTS protocol is used for controlling motorized blinds that are fitted with Somfy motors.
    Somfy uses 433.42MHz instead of the common 433.92MHz.
        A standard 433.92MHz transmitter like the FS1000A will work, but limits the range to 2 or 3 meters.
        The easiest solution is to buy "433.42MHz TO-39 SAW Resonator Crystals" on eBay to replace the 433.96MHz Resonator on the FS1000A.


 Usage:

    mosquitto_pub -t cmnd/esp32-dev-01/RFtxSMFY -m '{"Id":656,"RollingCode":43,"Button":4}'                         # Down
    mosquitto_pub -t cmnd/esp32-dev-01/RFtxSMFY -m '{"Id":656,"RollingCode":43,"Button":4,"StopAfterMs":4000}'      # Down, stop after 4 sec.
    mosquitto_pub -t cmnd/esp32-dev-01/RFtxSMFY -m '{"Id":656,"RollingCode":43,"Button":8,"nFrames":12,"Gap":72}'   # LongPress PROG.
    curl -s --data-urlencode 'cmnd=RFtxSMFY {"Id":656,"RollingCode":43,"Button":4}' http://esp32-dev-01/cm


 How it works:
    It uses Tasmota's IRsend in raw mode.
    We don't want it modulated by IRsend's 38kHz carrier, but even with freq=1, IRsend still modulates at 1kHz.
    (Though actually, it turns out that the FS1000A ignores the 38kHz modulation, so the workaround is overkill)
    Workaround:
        If I keep the marks shorter than 500us, then I won't see the 1kHz modulation. Obviously, I don't see any modulation on spaces.
        For marks longer than 500us, I use multiple shorter marks with zero-length spaces between them.
        eg: 1500 becomes 490,0,490,0,490
        The zero-length spaces actually appears as 8us spaces, so optionally add a small RC low pass filter to the pin to remove them.

 Acknowledgments:
    The Somfy frame building code in makeSomfyFrame() originates from https://github.com/Nickduino/Somfy_Remote.
    Additional description of the Somfy RTS protocol can be found here: https://pushstack.wordpress.com/somfy-rts-protocol/

-#



############################################################################################################
############################################################################################################
############################################################################################################
############################################################################################################


# CC1101 support --------------------------------------------------------


#-
    What the CC1101 support code does:
        Initialize a CC1101 Tx/Rx module to transmit data in ASK/OOK mode at 433.92MHz or 433.42MHz.
        The CC1101 calls this 'asynchronous serial mode'.
        The CC1101 is useful because the transmit frequency can be programmed, thus providing the non-standard 433.42MHz frequency that the Somfy RTS protocol uses.
        The CC1101 is configured using its SPI interface. Once configured, the SPI interface does not need to be used.
        (Although, to be nice, I put the CC1101 into Tx mode before transmitting, and into Idle after transmitting. I could probably leave it in Tx mode.)
        The data to be transmitted should be connected to pin GDO0.


    How I wrote the CC1101 support:

        SPI Interface:
    
            Berry does not have an SPI object (like it does for I2C), so I bit-bang the SPI with gpio read/writes.



        CC1101 setup and register values:

            I used TI's SmartRF Studio 7 tool:
                Configure for Generic 433MHz, low data rate.
                Adjust to 433.92 and 433.42 MHz, Modulation format: ASK/OOK.
                Export 'default set' of registers for each of 433.92 and 433.42.

            I built https://github.com/ruedli/SomfyMQTT, SimpleSomfy.ino
                This uses https://github.com/LSatan/SmartRC-CC1101-Driver-Lib, which is based on work by Elechouse (https://www.elechouse.com/).
                I built and tested this on a Wemos D1 mini (ESP8266).
                Using a Logic Analyzer, I watched the SPI as it boots.
                    I used info from this to modify any relevant register settings that SmartRF Studio gave me.

                I understand most of what the Logic Analyzer shows me.
                    The Elechouse code can calculate the MHz settings; I skipped that and use the settings that SmartRF gave me.
                    The Elechouse code sets the PA table. It turns out this is important. Without the PA table, the Tx pin behaved as active low; I don't know why.
                    The Elechouse code calls a Calibrate() function after setting the freq. I don't understand this, and have not implemented it.



    Thoughts, to do etc
        - Can I write the CC1101 support as a class, to hide all the private functions?
        - Read something from the CC1101, and report an error if it is not present.
		
		- The infinite loop in SpiWriteBytes() is ok.
			If MISO never goes low, I get: BRY: Exception> 'timeout_error' - Berry code running for too long
			But, should I use gpio.INPUT or gpio.INPUT_PULLUP on that pin?
			I don't think it matters.
			If the CC1101 is absent, gpio.INPUT just runs through the code, gpio.INPUT_PULLUP throws the BRY: Exception> 'timeout_error'
		
		
-#

import gpio

var SCK_PIN  = -1
var MISO_PIN = -1
var MOSI_PIN = -1
var CS_PIN   = -1
    
    
def SpiInit()
    # Get SPI (actually, Software SPI, SSPI) pins from Tasmota Configuration
    SCK_PIN  = gpio.pin(gpio.SSPI_SCLK)
    MISO_PIN = gpio.pin(gpio.SSPI_MISO)
    MOSI_PIN = gpio.pin(gpio.SSPI_MOSI)
    CS_PIN   = gpio.pin(gpio.SSPI_CS)

    if hasCC1101 && (SCK_PIN < 0 || MISO_PIN < 0 || MOSI_PIN < 0 || CS_PIN < 0)
        print("RFtxSMFY Error: CC1101 SPI pin(s) not defined.")
        hasCC1101 = 0
        return
    end
    
    gpio.pin_mode(CS_PIN, gpio.OUTPUT)
    gpio.digital_write(CS_PIN, 1)
    tasmota.delay(50)

    gpio.pin_mode(SCK_PIN, gpio.OUTPUT)
    gpio.pin_mode(MISO_PIN, gpio.INPUT)
    gpio.pin_mode(MOSI_PIN, gpio.OUTPUT)

    gpio.digital_write(SCK_PIN, 0)
    gpio.digital_write(MOSI_PIN, 0)
end


def SpiWriteBytes(bytes, nBytes)
    if !hasCC1101 return end
    gpio.digital_write(CS_PIN, 0);
    while gpio.digital_read(MISO_PIN) end       # wait for MISO to go low.
    for b: 0 .. nBytes-1
        var dataToGo = bytes[b]
        var mask = 0x80
        for i: 1 .. 8
            gpio.digital_write(MOSI_PIN, dataToGo & mask ? 1 : 0)
            gpio.digital_write(SCK_PIN, 1)
            gpio.digital_write(SCK_PIN, 0)
            mask >>= 1
        end
    end
    gpio.digital_write(CS_PIN, 1);
end

def SpiWriteReg(addr, value)
    SpiWriteBytes([addr, value], 2)
end

def SpiStrobe(addr)
    SpiWriteBytes([addr], 1)
end


def RegConfigSettings(freq)
    # from SmartRF Studio 7, with modifications from Elechouse.

    SpiStrobe(0x30)         # SRES
    tasmota.delay(5)

    SpiWriteReg(0x02,0x0D)   # IOCFG0       Elechouse uses 0x0D, SmartRF says 0x06.
    SpiWriteReg(0x03,0x47)   # FIFOTHR
    SpiWriteReg(0x08,0x32)   # PKTCTRL0     from Elechouse ccMode(1), SmartRF says 0x05
    SpiWriteReg(0x0B,0x06)   # FSCTRL1
    
    SpiWriteBytes([0x7E, 0x00,0xC0,0x00,0x00,0x00,0x00,0x00,0x00], 9)   # PATABLE, as per Elechouse.

    if freq == 42
        # 433.42MHz
        SpiWriteReg(0x0D,0x10)   # FREQ2
        SpiWriteReg(0x0E,0xAB)   # FREQ1
        SpiWriteReg(0x0F,0x85)   # FREQ0
    else
        # 433.92MHz
        SpiWriteReg(0x0D,0x10)   # FREQ2
        SpiWriteReg(0x0E,0xB0)   # FREQ1
        SpiWriteReg(0x0F,0x71)   # FREQ0
    end
    SpiWriteReg(0x10,0xF6)   # MDMCFG4
    SpiWriteReg(0x11,0x83)   # MDMCFG3
    SpiWriteReg(0x12,0x33)   # MDMCFG2      Elechouse uses 0xBF
    SpiWriteReg(0x15,0x15)   # DEVIATN
    SpiWriteReg(0x18,0x18)   # MCSM0
    SpiWriteReg(0x19,0x16)   # FOCCFG
    SpiWriteReg(0x20,0xFB)   # WORCTRL
    SpiWriteReg(0x22,0x11)   # FREND0
    SpiWriteReg(0x23,0xE9)   # FSCAL3
    SpiWriteReg(0x24,0x2A)   # FSCAL2
    SpiWriteReg(0x25,0x00)   # FSCAL1
    SpiWriteReg(0x26,0x1F)   # FSCAL0
    SpiWriteReg(0x2C,0x81)   # TEST2
    SpiWriteReg(0x2D,0x35)   # TEST1
    SpiWriteReg(0x2E,0x09)   # TEST0

    SpiStrobe(0x36)         # SIDLE     seems sensible to do this at this time.
end



def SetTx()
    # from Elechouse
    SpiStrobe(0x36)         # SIDLE
    SpiStrobe(0x35)         # STX
end

def SetSidle()
    # from Elechouse
    SpiStrobe(0x36)         # SIDLE
end


#-
    # example init
    SpiInit()
    if useSomfyFreq
        RegConfigSettings(42)
    else
        RegConfigSettings(0)
    end
    SetTx()
    # SetSidle()
-#


############################################################################################################
############################################################################################################
############################################################################################################
############################################################################################################



# Somfy support ----------------------------------------------------------------



import string


var list1

def markSpace(mark, len)
  # Used by makeSomfyFrame()
  if(mark)
    list1.push(len)
  else
    list1.push(-len)
  end
end


def makeSomfyFrame(rID, rCode, button, startFrame, nFrames)
  #-
        This contains the Somfy protocol logic.
        Original code from https://github.com/Nickduino/Somfy_Remote

        makeSomfyFrame(rID, rCode, button, 1, 3)    generate a normal 3-frame message
        makeSomfyFrame(rID, rCode, button, 1, 1)    generate a single start frame
        makeSomfyFrame(rID, rCode, button, 0, 1)    generate a single follow-on frame

  -#

  var halfDigit = 640  # length of halfDigit in uSec
  var frame = [0,0,0,0,0,0,0]
  list1 = []

  frame[0] = 0xa7
  frame[1] = (button << 4) & 0xf0   # upper nibble is button, lower nibble will be checksum.
  frame[2] = (rCode  >> 8) & 0xff   # 16 bit rolling code
  frame[3] =  rCode        & 0xff
  frame[4] = (rID   >> 16) & 0xff   # 24 bit controller id
  frame[5] = (rID   >>  8) & 0xff
  frame[6] =  rID          & 0xff

  # Checksum calculation: an XOR of all the nibbles
  var checksum = 0;
  for i: 0 .. 6
    checksum = checksum ^ frame[i] ^ (frame[i] >> 4)
  end
  frame[1] |= (checksum & 0x0f)

  if 0
    # Debug: print each byte of frame
    for i: 0 .. 6
      print(string.format('%d: %02x', i, frame[i]))
    end
  end

  if 0
    # Debug: check the checksum, should be zero
    checksum = 0
    for i: 0 .. 6
      checksum = checksum ^ frame[i] ^ (frame[i] >> 4)
    end
    print('Checksum check: ' .. (checksum & 0x0f))
  end

  if 1
    # Obfuscation: XOR each byte with the previous byte (disable for debug)
    for i: 1 .. 6
      frame[i] ^= frame[i-1]
    end
  end

  # Make nFrames frames
  for fn: 1 .. nFrames
    if fn > 1   markSpace(0, 27000) end  # space between frames.
    var nsync = 0
    if(startFrame && fn == 1)
      # first frame: hardware wake up pulse and fewer sync pulses
      markSpace(1, 12000)
      markSpace(0, 18000)
      nsync = 2
    else
      # follow-on frames: have more sync pulses
      nsync = 7
    end

    for i: 1 .. nsync
      # software sync pulses
      markSpace(1, halfDigit * 4)
      markSpace(0, halfDigit * 4)
    end
    markSpace(1, 4700) #4550
    markSpace(0, halfDigit)

    # The frame data: for each byte, for each bit.
    # Somfy uses Manchester encoding: rising edge = 1, falling edge = 0.
    for i: 0 .. 6
      var mask = 0x80
      while mask > 0
        if(frame[i] & mask)
          markSpace(0, halfDigit)
          markSpace(1, halfDigit)
        else
          markSpace(1, halfDigit)
          markSpace(0, halfDigit)
        end
        mask >>= 1
      end
    end

  end

end



# For the IRsend raw/compressed format:
# Build a list of individual durations as we encounter them. Remember between calls to frame_bin2text().
var codes


def frame_bin2text()
  #-
    Input:  list1[] (global var, from makeSomfyFrame()): +ve elements are marks, -ve elements are spaces. Values are in uSec.
        like: [12000, -18000, 2560, -2560, 2560, -2560, 4700, -1280, 1280, -1280, 1280, -640, 640, -1280, 640, -640, 640, -640, 640,....]
        It may include adjacent marks and adjacent spaces, like: [... 640, 640, -640, -640, 640, -640 ...] This is not valid for IRsend.

    Return: A string in Tasmota-compatible IRsend Raw/Compressed format.
        like: "+470-1AbAbAbAbAbAbAbAbAbAbAbAbAbAbAbAbAbAbAbAbAbAbAbA-18000+416bDbDbDbDbD-2560DbDbDbDbDbDe+460bFbFbFbFbFbFbFbFbF-1280DbDb"
        Note: Marks longer than 490us (that's all of them, I think) will be broken into multiple short marks with very small spaces between,
        to stop IRsend's 1kHz modulation showing through.

  -#

  var list2 = []
  var list3 = []
  var sOut = ''

  # combine adjacent elements which have the same sign, list1[] to list2[]
  var iOut = 0
  list2.push(0)
  for len: list1
    var s1 = len >= 0
    var s2 = list2[iOut] >= 0
    if s1 == s2
        list2[iOut] += len  # iOut is always last element of list, could use list2[-1], or list2[size(list2)-1].
    else
        list2.push(len)
        iOut += 1
    end
  end
  # print(list2)

  # break up marks longer than 490us into multiple shorter marks, list2[] to list3[]
  for len: list2
    if len > 0
      var n = 1
      while (len / n) > 490
        n += 1
      end
      var len2 = int(len / n) - 10
      # Needs n marks of len2 uSec each
      list3.push(len2)
      for i: 2 .. n
        list3.push(-1)      # very short space (which will be filtered out in hardware)
        list3.push(len2)    # the mark
      end
    else
      list3.push(len)
    end
  end

  # if the last element is a space (-ve), then remove it.
  # (this makes it possible to append gaps (spaces) in following steps)
  if list3[-1] < 0
    list3.remove(-1)        # could list3.resize(size(list3)-1)
  end


  # Convert to text string in Tasmota IRsend Raw/Compressed format, list3[] to sOut.
  if 0
    # Plus/minus format, without compression.
    for len: list3
      if len >= 0
        sOut += '+' .. len
      else
        sOut += str(len)
      end
    end
  else
    # Compressed format
    # var codes = []                # build a list of individual durations as we encounter them.
    for len: list3
      var lenAbs = len
      var sign = '+'
      var code2char = 65            # 65=A
      if len < 0
        lenAbs = -len
        sign = '-'
        code2char = 97              # 97=a
      end
      var c = codes.find(lenAbs)
      if c == nil
        # this duration has not been used before, so use the number...
        sOut += sign .. lenAbs
        codes.push(lenAbs)          # ... and store for future use.
      else
        # this duration has been used before, so use the single-character code.
        sOut += string.char(c + code2char)
      end
    end
  end

  return sOut

end


def makeMessage(id, rCode, button, nFrames, frameGap)

  codes = []
  makeSomfyFrame(id, rCode, button, 1, 1)   # First frame, result in list1[]
  var listStr  = frame_bin2text()           # reads list1[], returns a string
  if nFrames == 1 return listStr  end

  makeSomfyFrame(id, rCode, button, 0, 1)   # Follow-on frames
  var listStr2 = frame_bin2text()
  var gaplet = frameGap * 1000              # gap between frames
  var nGaps = 1
  if gaplet > 32000                         # max space seems to be 40,000ms. If larger, then use multiple spaces.
    nGaps = int(gaplet/32000)+1
    gaplet = int(gaplet/nGaps)
  end
  for i: 2 .. nFrames
    listStr += '-' + str(gaplet)            # like -32000
    for j: 2 .. nGaps
      listStr += '+1-' + str(gaplet)        # like -32000+1-32000
    end
    listStr += listStr2                     # append a follow-on frame
  end
  return listStr

end



# These global vars carry the values from somfy_cmd(), through the tasmota.set_timer(), to somfy_stop().
var id
var rCode
var button
var nFrames
var frameGap
var cc1101_initialized = 0
var useSomfyFreq = 1    # set to 0 for 433.92MHz, can be useful for diagnostics.


def somfy_stop()
  # Used by the "StopAfterMs" functionality, call-back from tasmota.set_timer()
  button = 1 # stop
  var listStr = makeMessage(id, rCode+1, button, nFrames, frameGap)
  if hasCC1101 SetTx() end
  tasmota.cmd('IRsend 1,' + listStr)
  if hasCC1101 SetSidle() end
end


def somfy_cmd(cmd, ix, payload, payload_json)
  var idx = 0
  id = 0
  rCode = 0
  button = 0
  nFrames = 3
  frameGap = 27


  # parse payload
  if payload_json != nil && payload_json.find("Idx") != nil    # does the payload contain an 'Idx' field?
    idx = int(payload_json.find("Idx"))
  end
  if payload_json != nil && payload_json.find("Id") != nil
    id = int(payload_json.find("Id"))
  end
  if payload_json != nil && payload_json.find("RollingCode") != nil
    rCode = int(payload_json.find("RollingCode"))
  end
  if payload_json != nil && payload_json.find("Button") != nil
    button = int(payload_json.find("Button"))
  end
  if payload_json != nil && payload_json.find("nFrames") != nil
    nFrames = int(payload_json.find("nFrames"))
  end
  if payload_json != nil && payload_json.find("Gap") != nil
    frameGap = int(payload_json.find("Gap"))
  end
  if payload_json != nil && payload_json.find("UseSomfyFreq") != nil
    useSomfyFreq = int(payload_json.find("UseSomfyFreq"))
    cc1101_initialized = 0
  end


  if hasCC1101 && !cc1101_initialized
    SpiInit()
    if useSomfyFreq
        RegConfigSettings(42)
    else
        RegConfigSettings(0)
    end
    cc1101_initialized = 1
    # SetTx()
  end


  import persist
  if idx > 0
    # Stateful mode: id will be remembered, and rCode will be maintained in _persist.json
    if !persist.has('sState')
      # Persistent storage of [id, rCode] for virtual controllers 1 thru 8.
      persist.sState = [[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0]]  # sState[0] not used.
    end
    if id == 0
      # id is not supplied, so retrieve it from persistent storage
      id = persist.sState[idx][0]
      rCode = persist.sState[idx][1]
    else
      # id is not supplied, so store it and rCode in persistent storage
      persist.sState[idx][0] = id
      persist.sState[idx][1] = rCode
    end
  end

  if payload_json != nil && payload_json.find("StopAfterMs") != nil && button != 0
    var delay = int(payload_json.find("StopAfterMs"))
    # set this delay before executing the first tasmota.cmd('IRsend') to get the best start-to-start period.
    tasmota.set_timer(delay, somfy_stop)
    if idx > 0
      persist.sState[idx][1] += 1
    end
  end

  if button != 0
    var listStr = makeMessage(id, rCode, button, nFrames, frameGap)
    # print(listStr)
    if hasCC1101 SetTx() end
    tasmota.cmd('IRsend 1,' + listStr)
    if hasCC1101 SetSidle() end
  end

  if idx > 0
    if button != 0
      persist.sState[idx][1] += 1
    end
    persist.save()  # This is required in case the ESP32 reboots without a clean shutdown.
                    # comment out while testing to reduce ware on the flash
  end

  # tasmota.resp_cmnd_done()    # causes {"IRSend":"Done"}
  tasmota.resp_cmnd('{"RFtxSMFY":"Done"}')

end

tasmota.add_cmd('RFtxSMFY', somfy_cmd)



############################################################################################################
############################################################################################################
############################################################################################################
############################################################################################################



# Tasmota Shutter Integration --------------------------------------------------



#-

    SetOption80 1
    Configure relay1 and relay2 - this seems to be required
    ShutterRelay1 1     # optional/implied
    ShutterMode1 1      # mode 1: relay1 = up, relay2 = down.

    mosquitto_pub -t cmnd/esp32-dev-01/ShutterOpen -m ''
    mosquitto_pub -t cmnd/esp32-dev-01/ShutterPosition -m 50
    mosquitto_pub -t cmnd/esp32-dev-01/ShutterClose -m ''

    Configure relay3 and relay4
    ShutterRelay2 3     # Shutter2 will use relay 3 and 4, required
    ShutterMode2 1


-#

#-
    This implements rules similar to https://github.com/GitHobi/Tasmota/wiki/Somfy-RTS-support-with-Tasmota#using-rules-to-control-blinds

    Tasmota Shutter1 (in ShutterMode 1) uses relay1 for up and relay2 for down.
    When relay1 turns on, we need to send a Somfy up command.
    When relay2 turns on, we need to send a Somfy down command.
    When relay1 or relay2 turn off, we might need to send a Somfy stop command, but only if we think the shutter is currently moving.
    If we send a 'Stop' when the shutter is stopped, the Somfy will interpret it as a 'Go-My' command.
    So, don't send a 'Stop' if the shutter position is 0% or 100%.
    
    This requires that the shutter has been reasonably calibrated, eg: ShutterOpenDuration1 9.5; ShutterCloseDuration1 8.5
-#


if tasmotaShutterIntegration

    def sendCommand(idx, cmd)
        var b
        if cmd == 'up'
            b = 2
        elif cmd == 'down'
            b = 4
        else # cmd == 'stop'
            b = 1
        end
        # print('Somfy', idx, cmd, b)
        somfy_cmd(0, 0, 0, {"Idx": idx, "Button": b} )
        
    end
    
    var position = [0, 0, 0, 0, 0]      # position[0] not used.
    def shutterChange(idx, op, value)
        # print("shutterChange", idx, op, value)
        if op == 'position'
            position[idx] = value
        elif op == 'up' && value == 1
            sendCommand(idx, op)
        elif op == 'down' && value == 1
            sendCommand(idx, op)
        elif op == 'up' || op == 'down'
            # Value must be 0, because 1 has been caught earlier, so Tasmota wants the shutter to stop.
            # Don't send Stop command if shutter is fully open or fully closed.
            # Note: ShutterX#Position must arrive before PowerX#State, and it does.
            if position[idx] > 0 && position[idx] < 100
                sendCommand(idx, 'stop')
            end
        end
    end

    tasmota.add_rule("Shutter1#Position", def (value) shutterChange(1, 'position', value) end )
    tasmota.add_rule("Shutter2#Position", def (value) shutterChange(2, 'position', value) end )
    tasmota.add_rule("Shutter3#Position", def (value) shutterChange(3, 'position', value) end )
    tasmota.add_rule("Shutter4#Position", def (value) shutterChange(4, 'position', value) end )
    tasmota.add_rule("Power1#State",      def (value) shutterChange(1, 'up',       value) end )
    tasmota.add_rule("Power2#State",      def (value) shutterChange(1, 'down',     value) end )
    tasmota.add_rule("Power3#State",      def (value) shutterChange(2, 'up',       value) end )
    tasmota.add_rule("Power4#State",      def (value) shutterChange(2, 'down',     value) end )
    tasmota.add_rule("Power5#State",      def (value) shutterChange(3, 'up',       value) end )
    tasmota.add_rule("Power6#State",      def (value) shutterChange(3, 'down',     value) end )
    tasmota.add_rule("Power7#State",      def (value) shutterChange(4, 'up',       value) end )
    tasmota.add_rule("Power8#State",      def (value) shutterChange(4, 'down',     value) end )

end


