
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
    Optional: Add this simple RC filter to the IRsend pin to remove unwanted 8us spaces.
	(Optional, because the FS1000A ignores the 8us spaces, but filtering them out makes the signal look better on a logic analyzer)
	
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
 
    mosquitto_pub -t cmnd/esp32-dev-01/RFtxSMFY -m '{"Id":656,"RollingCode":43,"Button":4}'							# Down
    mosquitto_pub -t cmnd/esp32-dev-01/RFtxSMFY -m '{"Id":656,"RollingCode":43,"Button":4,"StopAfterMs":4000}'		# Down, stop after 4 sec.
	mosquitto_pub -t cmnd/esp32-dev-01/RFtxSMFY -m '{"Id":656,"RollingCode":43,"Button":8,"nFrames":12,"Gap":72}'   # LongPress PROG (_V2 only)
	curl -s --data-urlencode 'cmnd=RFtxSMFY {"Id":656,"RollingCode":43,"Button":4}' http://esp32-dev-01/cm


 How it works:
	It uses Tasmota's IRsend in raw mode.
	We don't want it modulated by IRsend's 38kHz carrier, but even with freq=1, IRsend still modulates at 1kHz.
	(Though actually, it turns out that the FS1000A ignores the 38kHz modulation, so the workaround is overkill)
	Workaround:
		If I keep the marks shorter than 500us, then I won't see the 1kHz modulation. Obviously, I don't see any modulation on spaces.
		For marks longer than 500us, I use multiple shorter marks with zero-length spaces between them.
		eg: 1500 becomes 490,0,490,0,490
		The zero-length space actually appears as an 8us space, so optionally add a small RC low pass filter to the pin to remove them.

 Acknowledgments:
	The Somfy frame building code in makeSomfyFrame() originates from https://github.com/Nickduino/Somfy_Remote.
	Additional description of the Somfy RTS protocol can be found here: https://pushstack.wordpress.com/somfy-rts-protocol/
 
-#




import string


# Section 1 - Somfy protocol


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
		
		makeSomfyFrame(rID, rCode, button, 1, 3)	generate a normal 3-frame message
		makeSomfyFrame(rID, rCode, button, 1, 1)	generate a single start frame
		makeSomfyFrame(rID, rCode, button, 0, 1)	generate a single follow-on frame

  -#
  
  var halfDigit = 640  # length of halfDigit in uSec
  var frame = [0,0,0,0,0,0,0]
  list1 = []
  
  frame[0] = 0xa7
  frame[1] = (button << 4) & 0xf0	# upper nibble is button, lower nibble will be checksum.
  frame[2] = (rCode  >> 8) & 0xff	# 16 bit rolling code
  frame[3] =  rCode        & 0xff
  frame[4] = (rID   >> 16) & 0xff	# 24 bit controller id
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
		list2[iOut] += len	# iOut is always last element of list, could use list2[-1], or list2[size(list2)-1].
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
	    list3.push(-1)		# very short space (which will be filtered out in hardware)
	    list3.push(len2)	# the mark
	  end
	else
	  list3.push(len)
	end
  end

  # if the last element is a space (-ve), then remove it.
  # (this makes it possible to append gaps (spaces) in following steps)
  if list3[-1] < 0
	list3.remove(-1)		# could list3.resize(size(list3)-1)
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
    # var codes = []				# build a list of individual durations as we encounter them.
	for len: list3
	  var lenAbs = len
	  var sign = '+'
	  var code2char = 65			# 65=A
	  if len < 0
		lenAbs = -len
		sign = '-'
		code2char = 97				# 97=a
	  end
      var c = codes.find(lenAbs)
      if c == nil
        # this duration has not been used before, so use the number...
		sOut += sign .. lenAbs
		codes.push(lenAbs)			# ... and store for future use.
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
  makeSomfyFrame(id, rCode, button, 1, 1)	# First frame, result in list1[]
  var listStr  = frame_bin2text()			# reads list1[], returns a string
  if nFrames == 1 return listStr  end
  
  makeSomfyFrame(id, rCode, button, 0, 1)	# Follow-on frames
  var listStr2 = frame_bin2text()
  var gaplet = frameGap * 1000				# gap between frames
  var nGaps = 1
  if gaplet > 32000							# max space seems to be 40,000ms. If larger, then use multiple spaces.
    nGaps = int(gaplet/32000)+1
	gaplet = int(gaplet/nGaps)
  end
  for i: 2 .. nFrames
    listStr += '-' + str(gaplet)			# like -32000
    for j: 2 .. nGaps
	  listStr += '+1-' + str(gaplet)		# like -32000+1-32000
	end
	listStr += listStr2						# append a follow-on frame
  end
  return listStr

end



# These global vars carry the values from somfy_cmd(), through the tasmota.set_timer(), to somfy_stop().
var id
var rCode
var button
var nFrames
var frameGap

  
def somfy_stop()
  # Used by the "StopAfterMs" functionality, call-back from tasmota.set_timer()
  button = 1 # stop
  var listStr = makeMessage(id, rCode+1, button, nFrames, frameGap)
  tasmota.cmd('IRsend 1,' + listStr)
end


def somfy_cmd(cmd, idx, payload, payload_json)
  idx = 0
  id = 0
  rCode = 0
  button = 0
  nFrames = 3
  frameGap = 27
  
  import persist
  if !persist.has('sState')
    persist.sState = [[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0]]
  end
  

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
  
  if idx > 0
    # Stateful mode: id will be remembered, and rCode will be maintained in _persist.json
	if id == 0
	  # id is not supplied, so retrieve it from persist
	  id = persist.sState[idx][0]
	  rCode = persist.sState[idx][1]
	else
	  # id is not supplied, so store it and rCode in persist
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
	tasmota.cmd('IRsend 1,' + listStr)
  end
  
  if idx > 0
    if button != 0
      persist.sState[idx][1] += 1
	end
	persist.save()	# This is required in case the ESP32 reboots without a clean shutdown.
					# comment out while testing to reduce ware on the flash
  end

  # tasmota.resp_cmnd_done()	# causes {"IRSend":"Done"}
  tasmota.resp_cmnd('{"RFtxSMFY":"Done"}')
  
end

tasmota.add_cmd('RFtxSMFY', somfy_cmd)


