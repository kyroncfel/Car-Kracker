''********************************************
''*  K-Bus Tranceiver 1.2 (w/Kracker 0.57)   *
''*  Author: Nick McClanahan (c) 2012        *
''*  See end of file for terms of use.       *
''********************************************

{-----------------REVISION HISTORY-----------------                     
r1.2 (W/ Kracker 0.57):
* Improved RX/TX performance and faster nextcode

r1.1 (W/ Kracker 0.56):
* RxTxPad now sets waittime when shifting from RX to TX
* Added Stop Bit Check
* Improvements to Holdforcode

r1.0 (With Kracker 0.55):                                                        CIRCUIT:                       
  Sync'ed Serial TX object with additonal features for iBus                              3.3v                   
                                                                                                               
Changes from Kracker 0.54:                                                            10k                      
* Complete rewrite, K-bus functions are now bundled with Serial IO              TXPIN ───┻──┳──── Ibus Data 
* Stateless RX                                                                                 │                
                                                                                RXPIN ─────  ┌─ Ibus Gnd  
                                                                                           22k │  │             
                                                                                                              
                                                                           Use method Start(rxpin, txpin, %0110, 9600)
}                                                                       
                                                                        
CON                                                                     
_clkmode = xtal1 + pll16x                               
_xinfreq = 5_000_000                                    

bufsiz = 128 '16       'buffer size (16, 32, 64, 128, 256, 512) must be factor of 2, max is 512 
bufmsk = bufsiz - 1    'buffer mask used for wrap-around ($00F, $01F, $03F, $07F, $0FF, $1FF)   
bitsiz = 9         
'bitsiz = 8 + 1 + 1     '8 bits + parity + stop   (not coded for 8,0,1 so don't change!!)

LEDTx = 16, LEDRx = 17         'LED's for notification: Rx and Tx denote active transmissions
LEDMsg = 19, LEDBitClock = 18  'BitClock toggles during each bit transition
                                                    
 
RxTxPad = 80    'Padding betwen RX and TX period - this is how long 'default = 100
offsetper = 100 ' how far towards the middle of the bit.  Default = 2800
KbusCog = 6

VAR
  long  cog               'cog flag/id
  '9 contiguous longs:
  long  rx_head       'Start addr of data still in the rx buffer
  long  rx_tail       'End addr of data in the rx buffer
  long  tx_head
  long  tx_tail
  long  rx_pin
  long  tx_pin
  long  rxtx_mode
  long  bit_ticks
  long  buffer_ptr
                     
  byte  rx_buffer[bufsiz]           'transmit and receive buffers
  byte  tx_buffer[bufsiz]

  byte  coderef[40]
  byte  codein[40]    'Storage for successfully received code.  Does not flush
  BYTE  RADstring[32] 'Use to build strings for the RAD display
  byte  outcodeprep[40] 

  
PUB start(rxpin, txpin, mode, baudrate) : okay

'' Start serial driver - starts a cog
'' returns false if no cog available
''
'' mode bit 0 = invert rx
'' mode bit 1 = invert tx
'' mode bit 2 = open-drain/source tx
'' mode bit 3 = ignore tx echo on rx

  stop
  longfill(@rx_head, 0, 4)
  longmove(@rx_pin, @rxpin, 3)
  bit_ticks := clkfreq / baudrate
  buffer_ptr := @rx_buffer
  coginit(kbuscog, @entry, @rx_head)
  okay := 6



''Instructions added specifically for the KBus
PUB codeptr
''Returns a pointer to the codein string
return @codein

PUB holdForCode(matchcode) | codelen, i
''Blocking: holds until a code matching the values @matchcode come in the buffer


codelen := BYTE[matchcode+1] -1
repeat until rxavail

repeat 
  IF rx == BYTE[matchcode]
    result := true
    repeat i from  0 to codelen
      if rx_buffer[(rx_tail + i) & bufmsk ] <> BYTE[matchcode+i+1]
        result := false

    IF result == TRUE     
      repeat codelen + 1
        rx
      return


PUB sendtext(strptr)
''Sends a text string to the RAD

BYTEFILL(@radstring, 0, 32)
radstring[0] := $C8
radstring[1] := 5 + strsize(strptr)
radstring[2] := $80
radstring[3] := $23 
radstring[4] := $42
radstring[5] := $32

bytemove(@radstring+6, strptr, strsize(strptr))
sendcode(@radstring)


PUB sendnav(strptr, pos)
''Sends a text string to the NAV at pos,                    

BYTEFILL(@radstring, 0, 32)
radstring[0] := $F0 
radstring[1] := 6 + strsize(strptr)
radstring[2] := $3B
radstring[3] := $A5
radstring[4] := $62 
radstring[5] := $01
radstring[6] := pos

bytemove(@radstring+7, strptr, strsize(strptr))
sendcode(@radstring)


PUB textscroll(strptr) | strlen, i
BYTEFILL(@radstring, 0, 32) 
radstring[0] := $C8
radstring[1] := 5 + 11
radstring[2] := $80
radstring[3] := $23 
radstring[4] := $42
radstring[5] := $32

strlen := strsize(strptr)
repeat i from 0 to strlen - 11 
  bytemove(@radstring+6, strptr+i, 11)
  sendcode(@radstring)
  IF i == 0
    waitcnt(clkfreq + cnt)
  ELSE
    waitcnt(clkfreq /5 + cnt)   


PUB codecompare(cptr1) | i, codelen
''Compare the code at cptr1 with the code in codein
codelen :=  byte[cptr1][1]

repeat i from 0 to codelen
  if byte[cptr1 + i] == codein[i]
    result := True
  else
    return false
          
PUB clearcode
''The most recently returned code is not cleared from Codein.  This method clears it
bytefill(@codein, 0, 40)




PUB partialcode(ms) | checksum, len, holdtime, base, i
''Next code tests every byte in the RX buffer until it finds a valid message
''That message is stored in Codein
''Call with 0 ms to make blocking

clearcode
base := rx_tail
repeat while rxcount < 5  
len := getrx(1, base)   

repeat i from 0 to len + 1
  codein[i] := rxtime(2)
return TRUE   







PUB nextcode(ms) | checksum, len, holdtime, base, i, blocking
''Next code tests every byte in the RX buffer until it finds a valid message
''That message is stored in Codein
''Call with 0 ms to make blocking

clearcode
blocking := -1
base := rx_tail
checksum :=0
IF ms == 0
  blocking := 0

ms  #>= 5
holdtime := cnt + (ms * 80000)

repeat
  IF (cnt > holdtime) AND (Blocking == -1)                          'in the buffer to test
   return FALSE                                                                                                                 

  IF rxcount < 5           
    next

  len := getrx(1, base)         'Get the length, verify it's possible  
  IF (len == 0) OR (len > 32)                                                                     
    rxtime(2)
    base++
    next

  If rxcount < len + 2
    next  
 
  repeat i from 0 to len             'Calc checksum
    checksum ^= getrx(i, base)

  IF checksum == getrx(Len + 1, base)
    repeat i from 0 to len + 1
      codein[i] := rxtime(2)
    return TRUE   

  ELSE
    rxtime(2)  
    base++  
    checksum := 0


PUB bufferpeek(len) | checksum, holdtime, base, i, blocking

clearcode
blocking := -1
base := rx_tail


repeat i from 0 to len
  codein[i] := getrx(i,base)


                       
PRI getrx(depth, starttail)
'' Gets a byte in the rx buffer, [depth] bytes deep starting at [starttail]
return rx_buffer[(starttail+depth) & bufmsk]

PRI partialmatch(match, length): matching | i
''Determine if the code at codein matches the pattern at match
''Match format: $80, $00, $FF, $24, $01
''Use bytes where you want a matching byte, and $00 where the value might change
'' [length] is how far down the code to test for a match

repeat i from 0 to length -1
  if (BYTE[match][i] == codein[i]) OR (BYTE[match][i] == 0)
    matching := 1   
  else
    matching := -1
    Return FALSE  

return TRUE

PUB sendcode(outcode) | i, codelen, checksum
''Send the code stored as Hex at the location given by codeptr, Checksum is automatically calculated

checksum := 0
codelen := byte[outcode+1] <#  32

repeat i from 0 to codelen
  outcodeprep[i] := byte[outcode+i]
  checksum ^= outcodeprep[i]
outcodeprep[codelen + 1] := checksum

repeat i from 0 to codelen + 1
  tx(outcodeprep[i])


PUB IgnitionStatus : ignstat
''PASSIVE - you'll need to compare every incoming code with this method
''to see if it containts the Ignition status.  -1 means no update 
if partialmatch(@IgnitionCode, 4) 
  ignstat := codein[4]
else
  ignstat:= -1  


PUB OutTemp :Temp | i
''PASSIVE - you'll need to compare every incoming code with this method
'' -1 = no update
if partialmatch(@tempcode, 4)
  Temp := (codein[4] * 9 / 5) + 32
else
  temp:= -1     


PUB CoolTemp :Temp | i
''PASSIVE - you'll need to compare every incoming code with this method
'' -1 = no update

if partialmatch(@tempcode, 4) 
  Temp := (codein[5] * 9 / 5) + 32
else
  temp:= -1   


PUB RPMs :RPM | i
''PASSIVE - you'll need to compare every incoming code with this method
'' -1 = no update
if partialmatch(@RPMCode, 4)
  RPM := codein[5] * 100
else
  rpm := -1    


PUB Speed :mph | i
''PASSIVE - you'll need to compare every incoming code with this method
'' -1 = no update.  This field is updated by the KMB every second

if partialmatch(@RPMCode, 4)
  mph := (codein[4] * 5 / 8) / 2
else
  mph := -1


PUB Odometer :miles | i
''ACTIVE - this method queries the KMB and returns the result

sendcode(@OdometerReq)
repeat 5
  NextCode(50)
  if partialmatch(@OdometerResp, 4)
    BYTE[@miles][2] :=  codein[6]
    BYTE[@miles][1] :=  codein[5]
    BYTE[@miles][0] :=  codein[4]
    Miles := (Miles * 5 /8 )
    RETURN miles
  ELSE
    miles := -1


PUB localtime(strptr)   | i
''ACTIVE - this method queries the KMB and writes the result
''to [strptr].  0 Terminated string

sendcode(@timeReq)
repeat 5
   nextcode(100) 
   if partialmatch(@timeResp, 5)
      BYTEMOVE(strptr, @codein+6, 7)
      BYTE[strptr][7] :=  0
      return TRUE
   ELSE
      Byte[strptr] := 0

return FALSE




PUB fuelAverage(strptr) | i
''ACTIVE - this method queries the KMB and writes the result
''to [strptr].  0 Terminated string

sendcode(@fuelReq) 
repeat 5
  nextcode(50)                         
  if partialmatch(@fuelResp, 5) 
    i := Byte[@codein+1]  - 5
    BYTEMOVE(strptr, @codein+6, i)
    BYTE[strptr][i+1] :=  0
    return TRUE
  ELSE
    Byte[strptr] := 0
RETURN FALSE
    


PUB EstRange(strptr) | i
''ACTIVE - this method queries the KMB and writes the result
''to [strptr].  0 Terminated string

sendcode(@rangeReq) 
repeat 5
  nextcode(50)
  if partialmatch(@rangeResp, 5) 
    i := Byte[@codein+1]  - 5
    BYTEMOVE(strptr, @codein+6, i)
    BYTE[strptr][i+1] :=  0
    RETURN TRUE
  ELSE
    Byte[strptr] := 0

RETURN FALSE

PUB Date(strptr) | i
''ACTIVE - this method queries the KMB and writes the result
''to [strptr].  0 Terminated string

sendcode(@dateReq) 
repeat 5
  nextcode(50)
  if partialmatch(@dateResp, 5)
    i := Byte[@codein+1]  - 5
    BYTEMOVE(strptr, @codein+6, i)
    BYTE[strptr][i+1] :=  0
    RETURN TRUE
  ELSE
    Byte[strptr] := 0
RETURN FALSE   




PUB RxCount : count
{{Get count of characters in receive buffer.
  Returns: number of characters waiting in receive buffer.}}

  count := rx_head - rx_tail
  count -= bufsiz*(count < 0)



PUB stop
'' Stop serial driver - frees a cog

  if cog
    cogstop(KbusCog)
  longfill(@rx_head, 0, 9)

PUB rxflush
'' Flush receive buffer

  repeat while rxcheck => 0
  
PUB rxavail : truefalse
'' Check if byte(s) available
'' returns true (-1) if bytes available

  truefalse := rx_tail <> rx_head

PUB rxcheck : rxbyte

'' Check if byte received (never waits)
'' returns -1 if no byte received, $00..$FF if byte

  rxbyte--
  if rx_tail <> rx_head
    rxbyte := rx_buffer[rx_tail]
    rx_tail := (rx_tail + 1) & bufmsk


PUB rxtime(ms) : rxbyte | t

'' Wait ms milliseconds for a byte to be received
'' returns -1 if no byte received, $00..$FF if byte

  t := cnt
  repeat until (rxbyte := rxcheck) => 0 or (cnt - t) / (clkfreq / 1000) > ms
  

PUB rx : rxbyte

'' Receive byte (may wait for byte)
'' returns $00..$FF

  repeat while (rxbyte := rxcheck) < 0


PUB tx(txbyte)

'' Send byte (may wait for room in buffer)

  repeat until (tx_tail <> (tx_head + 1) & bufmsk)
  tx_buffer[tx_head] := txbyte
  tx_head := (tx_head + 1) & bufmsk

  if rxtx_mode & %1000
    rx


DAT                 

'***********************************
'* Assembly language serial driver *
'***********************************

                        org     0
'
'
' Entry
'
entry                   mov     t1,par                'get structure address
                        add     t1,#4 << 2            'skip past heads and tails

                        rdlong  t2,t1                 'get rx_pin
                        mov     rxmask,#1
                        shl     rxmask,t2

                        add     t1,#4                 'get tx_pin
                        rdlong  t2,t1
                        mov     txmask,#1
                        shl     txmask,t2

                        add     t1,#4                 'get rxtx_mode
                        rdlong  rxtxmode,t1

                        add     t1,#4                 'get bit_ticks
                        rdlong  bitticks,t1

                        add     t1,#4                 'get buffer_ptr
                        rdlong  rxbuff,t1
                        mov     txbuff,rxbuff
                        add     txbuff,#bufsiz

                        or      dira,txmask
                        or      dira, txLED  
                        or      dira, rxled
'                        or      dira, msgled
'                        or      dira, bittimer'

                        mov     txcode,#transmit

receive                 jmpret  rxcode,txcode         'run a chunk of transmit code, then return
                        test    rxmask,ina      wc     '
         if_c           jmp     #receive  
                        or      outa, rxLED 
                        mov     mbit, zero                           
                        mov     rxbits,#bitsiz        'ready to receive byte


                        mov     rxcnt, cnt      
                        add     rxcnt,bitticks        'ready next bit period
                        waitcnt rxcnt, #0

                        'Now in the begining of the first bit


:bit                    add     rxcnt, bitticks       'setup read for next bit

:midbitsample           test    rxmask,ina      wc    'receive bit on rx pin
               IF_c     adds     mbit, #1
               IF_nc    subs     mbit, #1     
                        cmp      rxcnt, cnt     wc ' write C when RXcnt is less than cnt
               IF_nc    jmp     #:midbitsample     
                        cmps    zero, mbit       wc  'write c when mbit is less than 0
                        rcr     rxdata,#1
                        mov     mbit, zero

                        djnz    rxbits,#:bit

                          
                         shr     rxdata,#32-9
'                        shr     rxdata,#32-bitsiz     'justify and trim received byte (ignore checking parity!)



                        and     rxdata,#$FF
                        test    rxtxmode,#%001  wz    'if rx inverted, invert byte
        if_nz           xor     rxdata,#$FF

                        rdlong  t2,par                'save received byte and inc head
                        add     t2,rxbuff
                        wrbyte  rxdata,t2
                        sub     t2,rxbuff
                        add     t2,#1
                        and     t2,#bufmsk
                        wrlong  t2,par
                        andn    outa, rxled
                        jmp     #receive              'byte done, receive next byte



transmit                jmpret  txcode,rxcode         'run a chunk of receive code, then return

                        djnz    txwait, #transmit  WZ
              IF_Z      mov     txwait, #1 


                        mov     t1,par                'check for head <> tail
                        add     t1,#2 << 2
                        rdlong  t2,t1
                        add     t1,#1 << 2
                        rdlong  t3,t1
                        cmp     t2,t3           wz
        if_z            jmp     #transmit


                        or      outa, txled
                        add     t3,txbuff             'get byte and inc tail
                        rdbyte  txdata,t3
                        sub     t3,txbuff
                        add     t3,#1
                        and     t3,#bufmsk
                        wrlong  t3,t1

                        test    txdata,#$FF     wc    'set parity bit (note parity forced!!)
        if_c            or      txdata,#$100          'if parity odd, make even
                        or      txdata,stopbit        'add stop bit  
''                        or      txdata,#$100        'ready byte to transmit
                        shl     txdata,#2
                        or      txdata,#1
                        mov     txbits,#bitsiz+2
                        mov     txcnt,cnt
                        add     txcnt,bitticks        'ready next cnt
                        
:bit                    test    rxtxmode,#%100  wz    'output bit on tx pin according to mode
                        test    rxtxmode,#%010  wc
        if_z_and_c      xor     txdata,#1
                        shr     txdata,#1       wc
        if_z            muxc    outa,txmask        
        if_nz           muxnc   dira,txmask
                        muxc    outa, msgled
                        
                        xor     outa, bittimer
                        waitcnt txcnt, bitticks

                        djnz    txbits,#:bit          'another bit to transmit?
                        andn    outa, txled

                        andn    outa,txmask 
                        
                        jmp     #transmit             'byte done, transmit next byte




txled                   long    1 << LEDtx
mbit                    long    0
zero                    long    0
msgled                  long    1 << LEDMsg          
bittimer                long    1 << LEDBitClock     
rxLED                   long    1 << LEDRx           

txwait                  long  1
txwaittimer             long  RxTxPad

delaytimer              LONG    0
delayperiod             LONG    10

'bitoffset               LONG    2400 - worked with 2400 
bitoffset               LONG    offsetper


stopbit                 long    $200                 'when parity used
stopcheck               LONG     1 << 9


'DATA for kbus RX/TX
TempCode        BYTE $80, $00, $BF, $19                                                           
RPMCode         BYTE $80, $00, $BF, $18
IgnitionCode    BYTE $80, $00, $BF, $11                                                           
                                                                                                  
                                                                                                  
OdometerReq     BYTE $44, $03, $80, $16                                                           
OdometerResp    BYTE $80, $00, $BF, $17                                                           
                                                                                                  
                                                                                                  
timeReq         BYTE $3B, $05, $80, $41, $01, $01                                                 
timeResp        BYTE $80, $00, $FF, $24, $01                                                      
                                                                                                  
dateReq         BYTE $3B, $05, $80, $41, $02, $01                                                 
dateResp        BYTE $80, $00, $FF, $24, $02                                                      
                                                                                                  
fuelReq         BYTE $3B, $05, $80, $41, $04, $01                                                 
fuelResp        BYTE $80, $00, $FF, $24, $04                                                      
                                                                                                  
rangeReq        BYTE $3B, $05, $80, $41, $06, $01                                                 
rangeResp       BYTE $80, $00, $FF, $24, $06      




  


' Uninitialized data
'
t1                      res     1
t2                      res     1
t3                      res     1

rxtxmode                res     1
bitticks                res     1

rxmask                  res     1
rxbuff                  res     1
rxdata                  res     1
rxbits                  res     1
rxcnt                   res     1
rxcode                  res     1

txmask                  res     1
txbuff                  res     1
txdata                  res     1
txbits                  res     1
txcnt                   res     1
txcode                  res     1

{{

┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                   TERMS OF USE: MIT License                                                  │                                                            
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation    │ 
│files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,    │
│modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software│
│is furnished to do so, subject to the following conditions:                                                                   │
│                                                                                                                              │
│The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.│
│                                                                                                                              │
│THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE          │
│WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR         │
│COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,   │
│ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                         │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
}}