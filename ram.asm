
; Assembled with 64TASS
; 		64tass -c bootloader.asm -L bootloader.lst
; 
;
.INCLUDE	"via_symbols.inc"
.INCLUDE	"acia_symbols.inc"

CTRL_C	= 3
LF		= 10
CR		= 13
SP		= 32

MASK0		= %00000001
MASK1		= %00000010
MASK2		= %00000100
MASK3		= %00001000
MASK4		= %00010000
MASK5		= %00100000
MASK6 		= %01000000
MASK7		= %10000000

; Flag definition to OR for SEP, REP
N_FLAG		= MASK7
V_FLAG		= MASK6
M_FLAG		= MASK5
X_FLAG		= MASK4
D_FLAG		= MASK3
I_FLAG		= MASK2
Z_FLAG		= MASK1
C_FLAG		= MASK0

* = $80
TEMP2		.byte	?
SRCFLAG		.byte 	?					 ; Where did last character come from 0=FIFO 1=ACIA/Serial

STACKTOP    = $07EFF


			.cpu 	"65816"
			.as					; A=8 bits
			.xl					; X, Y = 16 bits

* = $2000		; RAM load address
START 		
			SEI
			CLC
			XCE
			REP	#(X_FLAG | D_FLAG)
			SEP	#M_FLAG
			LDX	#STACKTOP
			TXS
			JSR	INIT_SER
			LDY	#MSG_FOXRAM
			JSR	PUT_STR
POINTLESS	
			JSR	GET_SER
			CMP	#CTRL_C
			BNE	START	
			JML 	$00F800

; Point Y to null-terminated string
PUT_STR		
			LDA	0,Y				; Y points directly to string
			BEQ	PUTSX
			JSR	PUT_SER
			INY					; point to next character
			BRA	PUT_STR		
PUTSX		
			RTS	

			



; FIXME: Quick n'dirty assignments instead of proper definitions of each parameter
; "ORed" together to build the desired flexible configuration.  We're going
; to run 9600 baud, no parity, 8 data BITs, 1 stop BIT for monitor.  
;

INTER_CHAR_DLY = 9167	; 8E6 cycles/sec * 11 bits/byte * 1 sec/ 9600 bits = 9167 cycles/byte
; INTER_CHAR_DLY = INT((CLK_HZ * 11) / BAUD_RATE) + 1


SCTL_V  = %00011110       	; 9600 baud, 8 bits, 1 stop bit, rxclock = txclock
SCMD_V  = %00001011       	; No parity, no echo, no tx or rx IRQ (for now), DTR*
; Set up baud rate, parity, stop bits, interrupt control, etc. for
; the serial port.
INIT_SER	
			LDA     #SCTL_V 		; 9600,n,8,1.  rxclock = txclock
			STA 	ACIA_SCTL		
			LDA     #SCMD_V 		; No parity, no echo, no tx or rx IRQ (for now), DTR*
			STA     ACIA_SCMD
			LDA     #$80			; Disable all VIA interrupts (not that CPU cares as yet if IRQB=0)		
                	STA     SYSTEM_VIA_IER
			LDA	#%00100000		; Put TIMER2 in timed mode
			TRB	SYSTEM_VIA_ACR
               		JSR	SET_SERTMR          	; Delay initial char output one character time in case TX not empty 
			RTS

SET_SERTMR
			; Set TIMER2  to meter out minimum inter-character delay (and clear IFR.5)
			PHA
			LDA     #<INTER_CHAR_DLY	; Load VIA T2 counter with
                	STA     SYSTEM_VIA_T2C_L        ; one byte output time
			LDA     #>INTER_CHAR_DLY
                	STA     SYSTEM_VIA_T2C_H
			PLA
			RTS
			
; Blocking.  OK for dev but not OK for final
PUT_SER
			JSR	PUTSER_RAW
			BCS	PUT_SER
			RTS
; Blocking.  OK for dev but not OK for final
GET_SER
			JSR	GETSER_RAW
			BCS	GET_SER
			RTS

; Non-blocking get serial byte.  If carry set, nothing was received into A. 
; If C=0, a new character is waiting in A
GETSER_RAW		
			LDA	ACIA_SSR
			AND	#RX_RDY
			SEC
			BEQ	GETSER_X1
			; RX_RDY=1.  Read waiting character from SDR
			LDA	ACIA_SDR
			CLC			; C=0 means A holds new received character
GETSER_X1
			RTS



PUTSER_RAW		
			PHA
			JSR	TXCHDLY
			;LDA	#%001000000			; Bit 5 = IFR.5 = Timer 2 overflow
			;BIT     SYSTEM_VIA_IFR
			;SEC					; Still busy outputting last char, so return with C=1 for fail
			;BEQ	PSR_X1				; be sure to balance stack on exit
			PLA
			STA	ACIA_SDR
			;JSR	SET_SERTMR			; Restart TMR2 for one character time; clear IFR.5
			CLC					; C=0 means output was successful
			BRA	PSR_X2				; and return it
PSR_X1
			PLA			; retore 
PSR_X2
			RTS

; A kludge until timers work to limit transmit speed to avoid TX overruns
; This is kind of terrible.  Replace.
TX_DLY_CYCLES = $0940						; Not tuned.  As it's temporary, optimum settings are unimportant.
; $24FF - reliable
; $1280 - reliable
; $0940 - reliable
; $04A0 - not reliable
; $06F0 - reliable.  Good enough for now. We're going to use VIA timer for this soon anyway
; 
; 
		
TXCHDLY		
			PHY
			LDY	#TX_DLY_CYCLES		; FIXME: Very bad work-around until timers are up
; Y = 16 bit delay count
DLY_Y		
			DEY
			NOP
			NOP
			NOP
			BNE	DLY_Y
			PLY
			RTS

		
MSG_FOXRAM
	.text 	CR,CR
	.text	"        I YAM RUNNING INDA RAM!",CR,LF
 	.text	"        _,-=._              /|_/|",CR,LF
 	.text	"       *-.}   `=._,.-=-._.,  @ @._,",CR,LF
 	.text   "          `._ _,-.   )      _,.-'",CR,LF
    .text   "             `    G.m-'^m'm'",CR,LF
	.text   "          Foxy art by: Dmytro O. Redchuk",CR,LF
	.text   " CTRL-C to return to FuzzyMonitoster",CR,LF,CR,LF
    .text	0

