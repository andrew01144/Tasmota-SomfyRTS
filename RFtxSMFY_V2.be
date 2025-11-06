
# Configuration options:
var modFreq = 0
        # Set to 1 for Tasmota images built with default options. (Default).
        # Set to 0 for Tasmota images built with "#define IR_SEND_USE_MODULATION 0" (Preferred).
var hasCC1101 = 1       # Set to 1 if using a CC1101 transmitter module.
var tasShutters = 1     # Set to 1 to create rules to make Tasmota Shutters generate Somfy commands.



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

 About the Somfy RTS protocol:
    The Somfy RTS protocol is used for controlling motorized blinds that are fitted with Somfy motors.
    Somfy uses 433.42MHz instead of the common 433.92MHz.
        A standard 433.92MHz transmitter like the FS1000A will work, but limits the range to 2 or 3 meters.
        The easiest solution is to buy "433.42MHz TO-39 SAW Resonator Crystals" on eBay to replace the 433.96MHz Resonator on the FS1000A.
        Another solution is to use a CC1101 transmitter that has a programmable transmit frequency.


 Usage:

    mosquitto_pub -t cmnd/esp32-dev-01/RFtxSMFY -m '{"Id":656,"RollingCode":43,"Button":4}'                         # Down
    mosquitto_pub -t cmnd/esp32-dev-01/RFtxSMFY -m '{"Id":656,"RollingCode":43,"Button":4,"StopAfterMs":4000}'      # Down, stop after 4 sec.
    mosquitto_pub -t cmnd/esp32-dev-01/RFtxSMFY -m '{"Id":656,"RollingCode":43,"Button":8,"nFrames":12,"Gap":72}'   # LongPress PROG.
    curl -s --data-urlencode 'cmnd=RFtxSMFY {"Id":656,"RollingCode":43,"Button":4}' http://esp32-dev-01/cm


 How it works:
    It uses IRsend's raw mode, because that is a way to generate a time-accurate bitstream in Tasmota.
    IR signals use a 38kHz a carrier that is modulated by the bitstream. But we don't want this 38kHz carrier.
    There are three options to handle this:
    
    1) Use 1kHz modulation, and use marks of less than 500us (default).
        At 1kHz, marks shorter than 500us will not show the carrier. Obviously, the spaces do not show any carrier.
        For marks longer than 500us, use multiple shorter marks with zero-length spaces between them.
        eg: 1500 becomes 490,0,490,0,490
        The zero-length spaces actually appear as 6us spaces or glitches.
        The FS1000A ignores the glitches.
        The CC1101 transmits some of the glitches, but the Somfy ignores them.
        You can optionally add a small RC low pass filter to the pin to remove the glitches. (1k2, 47nF)
        Set modFreq = 1 to enable the multi-mark logic.
    
    2) Use default 38k modulation anyway.
        It turns out that the FS1000A ignores the 38kHz modulation.
        Not suitable for CC1101.
        Set modFreq = 0 to select default 38kHz carrier, and disable the multi-mark logic.

    3) Disable IR_SEND_USE_MODULATION (preferred).
        Build the Tasmota image with "#define IR_SEND_USE_MODULATION 0".
        Set modFreq = 0 to disable the multi-mark logic.

 Acknowledgments:
    The Somfy frame building code in makeSomfyFrame() originates from https://github.com/Nickduino/Somfy_Remote.
    Additional description of the Somfy RTS protocol can be found here: https://pushstack.wordpress.com/somfy-rts-protocol/
    Tasmota shutter integration: https://github.com/GitHobi/Tasmota/wiki/Somfy-RTS-support-with-Tasmota#using-rules-to-control-blinds

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

var cc1101_freq = 0		# init state of CC1101. Can be 0, 42 or 92.
var rfFreq = 92			# default 92. Can be set elsewhere.
var protocol = ''
    
def SpiInit()
    # Get SPI (actually, Software SPI, SSPI) pins from Tasmota Configuration
    SCK_PIN  = gpio.pin(gpio.SSPI_SCLK)
    MISO_PIN = gpio.pin(gpio.SSPI_MISO)
    MOSI_PIN = gpio.pin(gpio.SSPI_MOSI)
    CS_PIN   = gpio.pin(gpio.SSPI_CS)

    if hasCC1101 && (SCK_PIN < 0 || MISO_PIN < 0 || MOSI_PIN < 0 || CS_PIN < 0)
        print("RFtxSMFY Error: CC1101 SPI pin(s) not defined.")
        hasCC1101 = 0
	end
end




def SpiWriteBytes(data, nBytes)
    if !hasCC1101 return end
    gpio.digital_write(CS_PIN, 0);
    while gpio.digital_read(MISO_PIN) end       # wait for MISO to go low.
    for b: 0 .. nBytes-1
        var dataToGo = data[b]
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
    
	gpio.pin_mode(CS_PIN, gpio.OUTPUT)
	gpio.digital_write(CS_PIN, 1)
	tasmota.delay(50)

	gpio.pin_mode(SCK_PIN, gpio.OUTPUT)
	gpio.pin_mode(MISO_PIN, gpio.INPUT)
	gpio.pin_mode(MOSI_PIN, gpio.OUTPUT)

	gpio.digital_write(SCK_PIN, 0)
	gpio.digital_write(MOSI_PIN, 0)

	# from SmartRF Studio 7, RegConfigSettings(), with modifications from Elechouse.

	SpiStrobe(0x30)         # SRES
	tasmota.delay(5)

	SpiWriteReg(0x02,0x0D)   # IOCFG0       Elechouse uses 0x0D, SmartRF says 0x06.
	SpiWriteReg(0x03,0x47)   # FIFOTHR
	SpiWriteReg(0x08,0x32)   # PKTCTRL0     from Elechouse ccMode(1), SmartRF says 0x05
	SpiWriteReg(0x0B,0x06)   # FSCTRL1
	
	SpiWriteBytes([0x7E, 0x00,0xC0,0x00,0x00,0x00,0x00,0x00,0x00], 9)   # PATABLE, as per Elechouse.

	if freq == 42
		# 433.42MHz
print('Setting 433.42MHz/Somfy')
		SpiWriteReg(0x0D,0x10)   # FREQ2
		SpiWriteReg(0x0E,0xAB)   # FREQ1
		SpiWriteReg(0x0F,0x85)   # FREQ0
	else
		# 433.92MHz
print('Setting 433.92MHz/Normal')
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
	
	cc1101_freq = freq
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


def myIrSend(listStr)
	if hasCC1101 && cc1101_freq == 0
		SpiInit()	# avoid calling this as it has a delay in it.
		RegConfigSettings(rfFreq)
	end
	if hasCC1101 && cc1101_freq != rfFreq
		RegConfigSettings(rfFreq)
	end
	
    if hasCC1101 SetTx() end
    tasmota.cmd('IRsend ' + str(modFreq) + ',' + listStr)
    if hasCC1101 SetSidle() end
end




############################################################################################################
############################################################################################################
############################################################################################################
############################################################################################################



# Somfy support ----------------------------------------------------------------



import string


var list1


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

  # print(string.format(' pre-obfust: %02x %02x %02x %02x %02x %02x %02x\n', frame[0], frame[1], frame[2], frame[3], frame[4], frame[5], frame[6]))

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
  # print(string.format('post-obfust: %02x %02x %02x %02x %02x %02x %02x\n', frame[0], frame[1], frame[2], frame[3], frame[4], frame[5], frame[6]))

  # Make nFrames frames
  for fn: 1 .. nFrames
    if fn > 1   list1.push(-27000) end  # space between frames.
    var nsync = 0
    if(startFrame && fn == 1)
      # first frame: hardware wake up pulse and fewer sync pulses
	  list1.push( 12000)
	  list1.push(-18000)
      nsync = 2
    else
      # follow-on frames: have more sync pulses
      nsync = 7
    end

    for i: 1 .. nsync
      # software sync pulses
      list1.push( halfDigit * 4)
      list1.push(-halfDigit * 4)
    end
    list1.push( 4700) #4550
    list1.push(-halfDigit)

    # The frame data: for each of 7 bytes, for each bit. 7x8=56 bits.
    # Somfy uses Manchester encoding: rising edge = 1, falling edge = 0.
    for i: 0 .. 6
      var mask = 0x80
      while mask > 0
        if(frame[i] & mask)
          list1.push(-halfDigit)
          list1.push( halfDigit)
        else
          list1.push( halfDigit)
          list1.push(-halfDigit)
        end
        mask >>= 1
      end
    end

  end

end



# For the IRsend raw/condensed format:
# Build a list of individual durations as we encounter them. Remember between calls to frame_bin2text().
var codes


def frame_bin2text()
  #-
    Input:  list1[] (global var, from makeSomfyFrame()): +ve elements are marks, -ve elements are spaces. Values are in uSec.
        like: [12000, -18000, 2560, -2560, 2560, -2560, 4700, -1280, 1280, -1280, 1280, -640, 640, -1280, 640, -640, 640, -640, 640,....]
        It may include adjacent marks and adjacent spaces, like: [... 640, 640, -640, -640, 640, -640 ...] This is not valid for IRsend.

    Return: A string in Tasmota-compatible IRsend Raw/condensed format.
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

  if modFreq == 1
    # If modulation frequency == 1kHz, then marks can be up to 500us.
    # Break up marks longer than maxMark microseconds into multiple shorter marks.
    # Input list2[], output list3[].
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
  else
    # Allow long marks.
    # Suitable for 38kHz modulation with FS1000A Tx module.
    # Or no modulation with any Tx module (set with #define IR_SEND_USE_MODULATION 0).
    list3 = list2
  end

  # if the last element is a space (-ve), then remove it.
  # (this makes it possible to append gaps (spaces) in following steps)
  if protocol == 'somfy' && list3[-1] < 0		# <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    list3.remove(-1)        # could list3.resize(size(list3)-1)
  end


  # Convert to text string in Tasmota IRsend Raw/condensed format, list3[] to sOut.
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
    # condensed format
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


def makeSomfyMessage(id, rCode, button, nFrames, frameGap)

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
var useSomfyFreq = 1    # set to 0 for 433.92MHz, can be useful for diagnostics.


def somfy_stop()
  # Used by the "StopAfterMs" functionality, call-back from tasmota.set_timer()
  button = 1 # stop
  var listStr = makeSomfyMessage(id, rCode+1, button, nFrames, frameGap)
  myIrSend(listStr)
end


def somfy_cmd(cmd, ix, payload, payload_json)
  var idx = 0
  id = 0
  rCode = 0
  button = 0
  nFrames = 3
  frameGap = 27
  rfFreq = 42	# 433.42MHz


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
    button = payload_json.find("Button")
    var  bTxt = string.tolower(button)
    if   bTxt == 'stop' button = 1
    elif bTxt == 'up'   button = 2
    elif bTxt == 'down' button = 4
    elif bTxt == 'prog' button = 8
    else button = int(button)
    end
  end
  if payload_json != nil && payload_json.find("nFrames") != nil
    nFrames = int(payload_json.find("nFrames"))
  end
  if payload_json != nil && payload_json.find("Gap") != nil
    frameGap = int(payload_json.find("Gap"))
  end
  if payload_json != nil && payload_json.find("UseSomfyFreq") != nil
    useSomfyFreq = int(payload_json.find("UseSomfyFreq"))
  end
  
  protocol = 'somfy'
  


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
    var listStr = makeSomfyMessage(id, rCode, button, nFrames, frameGap)
    myIrSend(listStr)
  end

  if idx > 0
    if button != 0
      persist.sState[idx][1] += 1
    end
	persist.dirty()	 # persist.save() does not notice a change in arrays, so mark it explicitly.
							# Not required V12.0.2. Required V14.2.0.
    persist.save()  # This is required in case the ESP32 reboots without a clean shutdown.
                    # comment out while testing to reduce ware on the flash
					# At some future version, persist.save(true), as per https://github.com/arendst/Tasmota/pull/22246
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
	Rules to connect Somfy blinds to the Tasmota Shutters functionality.
	
	Inspired by https://github.com/GitHobi/Tasmota/wiki/Somfy-RTS-support-with-Tasmota#configuring-tasmota
	
	This code has 3 main functions: I call these F1, F2 and F3.
	F1 provides the connection from the Tasmota-Shutter functionality to the RFtxSMFY command.
	F2 and F3 are nice-to-haves.
	
	
	F1) Send Somfy Up/Down/Stop commands when the state of the Up or Down relays change.
	Tasmota controls shutters and blinds by operating relays; usually one relay for Up, and another relay for Down.
	We need to configure some dummy relays for the Shutters function to connect to.
	Then, a relay change triggers a rule to send an RFtxSMFY command.
	When the Up relay turns on, send a Somfy Up command.
	When the Down relay turns on, send a Somfy Down command.
	When either relay turns off, send a Somfy Stop command.
	So far, so simple.
	
	
	F2) Suppress 'move to configured position' (also known as the 'my' button) commands. 
	Don't send a Somfy Stop when the blind has already stopped.
	eg: ShutterClose will cause the Down relay to turn on for a period, then off.
	This will generate a Somfy Down, then a Somfy Stop.
	But if the Somfy blind receives a Stop when the blind is not moving, it interprets it as 'move to configured position'.
	This is undesirable: ShutterClose would close the blind, then move to the configured position.
	We can fix that with some simple logic:
	When either relay turns off, send a Stop command UNLESS the position is 0 or 100, where the blind will have stopped itself.
	
	Actually, this is not really required, because RFtxSMFY is probably a unique controller ID, for which the 'configured position' has
	not been configured. So, sending a Stop from this controller ID will be ignored.
	
	However, this is still a good thing to do. Without it, we might stop the blind just before it reaches the end-stop.
	
	
	F3) Provide 'Calibrate' commands.
	Send a 'calibrate' Up or Down command even if the blind is already at the 100 or 0 position.
	(Added Jan-2024)
	Consider:
	Assume the blind is at position 90.
	ShutterClose: Tasmota sends a Somfy Down, and when it thinks the blind has reached position 0, it updates the position to 0.
	Next, we move the blind to position 60 using a Somfy hand controller.
	ShutterClose: Tasmota thinks the blind is at 0, so does not send any commands, and the blind stays at 60.
	
	If we always send an Up or Down, even when Tasmota thinks the blind is at the end stop, it will resync in these cases.
	
	The logic for this is a bit more complex:
	If we get a Shutter#Position event where the position is the same as the previously reported position,
	and is 0 or 100, then consider sending an Down or Up command.
	Look in the code for additional checks that need to be done.




	### History
	2022-10-06 - First published integration with Tasmota Shutters.
		Using method described in https://github.com/GitHobi/Tasmota/wiki/Somfy-RTS-support-with-Tasmota#configuring-tasmota 
		Users report that it works, but I have not used it.
	2024-01-15 - Configured Tasmota Shutters on my own system.
		Benefits:
			1. Simplification - action.pl (on my server) no longer needs to maintain state/position.
			2. Tasmota supports realtime stop/start commands, whereas action.pl only provided go-to-position commands.
		'calibrate' function is still provided by action.pl.
	2024-01-21 - New Shutter Integration Berry code:
		1. Provides 'calibrate' function.
		2. Uses json data from the Shutter1#Position trigger, instead of a combination of Shutter1#Position and Power1#State triggers.


	https://tasmota.github.io/docs/_media/berry_short_manual.pdf
	https://berry.readthedocs.io/en/latest/source/en/Reference.html

-#

if tasShutters

	
	def sendCommand(idx, cmd, cal)
	    # cal: nil or 'Calibrate'	
		# print('--------- Somfy', idx, cmd)
        somfy_cmd(0, 0, 0, {"Idx": idx, "Button": cmd} )
		
		if false
			# optional diagnostic mqtt messages
			import string
			import mqtt
			var logStr = string.format("%s,%d,%s,%s",
				tasmota.time_str(tasmota.rtc()['local']),
				idx+0, cmd, cal ? cal : '')

			mqtt.publish('shutterlog/log', logStr)
		end
    end
    
	#-
		"Shutter is moving" can be determined from:
			Relays: There is and up and a down relay. If either is ON, the shutter is moving. If both are OFF it is stopped.
			Direction: 1:up, -1:down, 0:off.
			We will use Direction, because it is provided along with Position and Target by the Shutter1#Position trigger.
	-#
	
	var moveState = [0,0,0,0,0]		# previous Direction state, so we can detect a change. (index 0 is not used)
	var cmndRcvd = [false, false, false, false, false]
	
	def shutterPos(v, trigger, msg)
		# triggered by Shutter1#Position
		# msg eg {"Shutter1":{"Position":0,"Direction":0,"Target":0,"Tilt":0}}
		
		#-
			We have entered this function because we have received a Shutter Position update, this could be triggered by:
				1) Any Shutter-move command for this Shutter, and a motor needs to be turned on or off.
					Position != Target, and Direction != 0, and Direction has changed. We [probably] need to send a Somfy command.
				2) Any Shutter-move command for this Shutter, even if it is already in the target position, and a motor does NOT need to be turned on or off.
					Position == Target, and Direction == 0. If we are on an end-stop, we would like to send a calibrate Somfy command.
				3) This Shutter is moving, and we are getting position updates.
					Position != Target, and Direction != 0, and Direction has NOT changed. Not action required.
				4) Another Shutter is moving; Tasmota sends updates on all Shutters when this is happening.
					Position == Target, and Direction == 0. No action required.
			Problem: It is very difficult to differentiate #4 from #2.
		-#
		
		var idx = int(trigger[7])	# character at position 7 is idx
		var s = msg["Shutter"..idx]
		# print("============", idx, s["Direction"], s["Target"], s["Position"])
		
		if moveState[idx] != s["Direction"]
			# Tasmota started or stopped a shutter motor, so send a Somfy up, down, or stop command.
			if s["Direction"] > 0
				sendCommand(idx, 'up')
			elif s["Direction"] < 0
				sendCommand(idx, 'down')
			else
				# Send a 'stop', unless Tasmota thinks the blind is already at the end-stop.
				if s["Position"] > 0 && s["Position"] < 100
					sendCommand(idx, 'stop')
				end
			end
			moveState[idx] = s["Direction"]
		else
			#-
				This is a Position update with no change to motors.
				Either: We have received a move-to-position command, but Tasmota thinks the shutter
					is already at that position, so does not turn on any motors.
					In this case, and if it is at an end-stop, we would like to send a calibrate command.
				Or: Another shutter is moving, and we are getting position updates on all shutters,
					in which case we need to ignore it.
			-#
			
			if false
				# Method #1: Another shutter is moving, so don't send a calibrate.
				# Problem: It omits the calibrate if both shutters have a command.
				if s["Target"] == s["Position"] && (s["Position"] == 0 || s["Position"] == 100)
					# We are sitting at an end-stop, so we may want to send a calibrate-move.
					# If any [other] shutters are moving, then this is just a position update, NOT a move-to-position command.
					var anyMoving = false
					for m: moveState
						if m != 0 anyMoving = true end
					end
					if !anyMoving
						var dir = s["Position"] < 50 ? 'down' : 'up'
						sendCommand(idx, dir, 'Calibrate')
					end
				end
			else
				# Method #2: Send a calibrate if we received a command for this shutter.
				# Problem: This only works for mqtt commands, because I use an mqtt interposer to detect the command.
				if (s["Position"] == 0 || s["Position"] == 100) && cmndRcvd[idx]
					var dir = s["Position"] < 50 ? 'down' : 'up'
					sendCommand(idx, dir, 'Calibrate')
				end
			end
			
		end
		
		cmndRcvd[idx] = false
	end
	
	
	import mqtt
	import string
	
	def mqttIn(topic, x, payload)
		# Purpose: Set a flag in cmndRcvd[] if we get a ShutterMove command. Used above in calibrate logic.
		# All mqtt commands
		topic = string.tolower(topic)
		if string.find(topic, 'shutter') >= 0
			# All Shutter commands.
			# Now look for specific Shutter-Move commands. This might not be necessary.
			var shutterCommands = ['ShutterOpen', 'ShutterClose', 'ShutterPosition', 'ShutterChange', 'ShutterToggle',
				'ShutterToggleDir', 'ShutterStop', 'ShutterStopOpen', 'ShutterStopClose', 'ShutterStopPosition',
				'ShutterStopToggle', 'ShutterStopToggleDir' ]
			for c: shutterCommands
				if string.find(topic, string.tolower(c)) >= 0
					# print('------- Setting cmndRcvd for', c)
					cmndRcvd[ int(topic[-1]) ] = true	# last char of topic is idx, eg ShutterClose1
					break
				end
			end

		end
		return false	# 'return false' allows Tasmota to process the message, else it will be discarded.
	end
	
	
	mqtt.subscribe('cmnd/' + tasmota.cmd('Topic', true)['Topic'] + '/+', mqttIn)	# Interpose all mqtt commands to this node.
    tasmota.add_rule("Shutter1#Position", shutterPos )
	tasmota.add_rule("Shutter2#Position", shutterPos )
	tasmota.add_rule("Shutter3#Position", shutterPos )
	tasmota.add_rule("Shutter4#Position", shutterPos )
	
    
end
