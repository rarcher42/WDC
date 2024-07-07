
; Assembled with 64TASS
; 		64tass -c bootloader.asm -L bootloader.lst
; 
;
; "Kernal"'s of truth:
;
CTRL_C		= 3
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

; TIDE2VIA	the system VIA.  Used by many and defined globally
; IO for the VIA which is used for the USB debugger interface.
SYS_VIA_BASE	    = 	$7FE0
SYSTEM_VIA_IORB     =  	SYS_VIA_BASE+0	; Port B IO register
SYSTEM_VIA_IORA     =	SYS_VIA_BASE+1 	; Port A IO register
SYSTEM_VIA_DDRB     = 	SYS_VIA_BASE+2	; Port B data direction register
SYSTEM_VIA_DDRA     = 	SYS_VIA_BASE+3	; Port A data direction register
SYSTEM_VIA_T1C_L    =	SYS_VIA_BASE+4 	; Timer 1 counter/latches, low-order
SYSTEM_VIA_T1C_H    = 	SYS_VIA_BASE+5	; Timer 1 high-order counter
SYSTEM_VIA_T1L_L    = 	SYS_VIA_BASE+6	; Timer 1 low-order latches
SYSTEM_VIA_T1L_H    = 	SYS_VIA_BASE+7	; Timer 1 high-order latches
SYSTEM_VIA_T2C_L    = 	SYS_VIA_BASE+8	; Timer 2 counter/latches, lower-order
SYSTEM_VIA_T2C_H    = 	SYS_VIA_BASE+9	; Timer 2 high-order counter
SYSTEM_VIA_SR       = 	SYS_VIA_BASE+10	; Shift register
SYSTEM_VIA_ACR      = 	SYS_VIA_BASE+11	; Auxilliary control register
SYSTEM_VIA_PCR      =	SYS_VIA_BASE+12	; Peripheral control register
SYSTEM_VIA_IFR	    =	SYS_VIA_BASE+13 ; Interrupt flag register
SYSTEM_VIA_IER      = 	SYS_VIA_BASE+14	; Interrupt enable register
SYSTEM_VIA_ORA_IRA  =	SYS_VIA_BASE+15	; Port A IO register, but no handshake
; System VIA Port B named bitmasks
PB0 = MASK0
PB1 = MASK1
PB2 = MASK2
PB3 = MASK3
PB4 = MASK4
PB5 = MASK5
PB6 = MASK6
PB7 = MASK7
; System VIA Port A named bitmasks
PA0 = MASK0
PA1 = MASK1
PA2 = MASK2
PA3 = MASK3
PA4 = MASK4
PA5 = MASK5
PA6 = MASK6
PA7 = MASK7

ALL_INPUTS = $00
ALL_OUTPUTS = $FF

STACKTOP	=	$6000	; Top of RAM = $07EFF (I/O is $7F00-$7FFF)
	.cpu 	"65816"
	.as	; A=8 bits
	.xl	; X, Y = 16 bits

* = $2000	; RAM load address
START 		SEI
			CLC	
			XCE							; Native mode
			SEP		#(M_FLAG)			; A,M = 8bit
			REP		#(X_FLAG | D_FLAG)	; 16 bit index, binary math
			NOP
			LDX		#STACKTOP
			TXS
			JSL		INIT_FIFO
			JSL		INITSER
MONPROMPT	LDY		#QBFMSG
			JSR		PUT_STR
POINTLESS	BRA		POINTLESS	
	
PUT_STR		LDA		0,Y				; Y points directly to string
			BEQ		PUTSX
			JSL		PUTSER
			INY						; point to next character
			BRA		PUT_STR		
PUTSX:		RTL		
		
; Quick n'dirty assignments instead of proper definitions of each parameter
; "ORed" together to build the desired flexible configuration.  We're going
; to run 9600 baud, no parity, 8 data BITs, 1 stop BIT for monitor.  
;
;;; ============================= 65c51 UART functions ======================================
; 65C51 ACIA equates for serial I/O
;
ACIA_BASE = $7F80		; This is where the 6551 ACIA starts
SDR = ACIA_BASE       		; RX'ed bytes read, TX bytes written, here
SSR = ACIA_BASE+1     		; Serial data status register
SCMD = ACIA_BASE+2     		; Serial command reg. ()
SCTL = ACIA_BASE+3     		; Serial control reg. ()
TX_RDY = MASK4
RX_RDY = MASK3
SCTL_V  = %00011110       ; 9600 baud, 8 bits, 1 stop bit, rxclock = txclock
SCMD_V  = %00001011       ; No parity, no echo, no tx or rx IRQ (for now), DTR*
; Set up baud rate, parity, stop bits, interrupt control, etc. for
; the serial port.
INITSER LDA     #SCTL_V 	; 9600,n,8,1.  rxclock = txclock
		STA 	SCTL		
		LDA     #SCMD_V 	; No parity, no echo, no tx or rx IRQ (for now), DTR*
		STA     SCMD
		RTL

MON_GETC
	; Fallthrough - the intent is for MON_GETC to choose the input device
GETSER	LDA		SSR
		AND		#RX_RDY
		BEQ		GETSER
		LDA		SDR
		CLC					; Temporary compatibility return value for blocking/non-blocking
		RTL

MON_PUTC
	; Fallthrough - the intent is to have MON_PUTC choose the output device 
PUTSER	PHA
		STA		SDR
	 	JSL		TXCHDLY		; Awful kludge
		PLA
		CLC					; Temporary compatibility return value for integration for blocking/non-blocking
		RTL
		  
;;;; ============================= New FIFO functions ======================================
; Initializes the system VIA (the USB debugger), and syncs with the USB chip.

FIFO_TXE = PB0
FIFO_RXF = PB1
FIFO_WR = PB2
FIFO_RD = PB3
FIFO_PWREN = PB5


; On exit:
;
; 1.	CA2 and CB2 are floating; This ensures writes to system VIA port B don't inadvertently change 
;		the flash bank#.  This is accomplished by writing $00 to SYSTEM_VIA_PCR 
;		Bank # is 0-3, 32K blocks as follows:
;		CB2 supplies A16 to SST39F010A FLASH
;		CA2 supplies A15 to SST39F010A FLASH
;
;    	CB2=0 CA2=0: Bank 0: 	FLASH address: $00.0000 - $00.7FFF	CPU address $00.8000-$00.FFFF - Free
;		CB2=0 CA2=1: Bank 1: 	FLASH address  $00.8000 - $00.FFFF	CPU address $00.8000-$00.FFFF - Free
;		CB2=1 CA2=0: Bank 2: 	FLASH address  $01.0000 - $01.7FFF	CPU address $00.8000-$00.FFFF - Free
;       CB2=1 CA2=1: Bank 3: 	FLASH address  $01.8000 - $01.FFFF  CPU address $00.8000-$00.FFFF - MONITOR 
;
;	It probably goes without saying that trying to change the bank while running from flash requires some trickery.
;   The easiest way to swap banks is to do so from a program running in RAM, but consider that system vectors
;	will change and it may make sense to have a vector and handler in place in each block before a block change.
;	
;
; 2.	System VIA port A is set to all inputs.  Port A is a bi-directional data transfer port to and from the FT245 FIFO
;
; 3.	System VIA port B is set to inputs, except PB2 and PB3, outputs to the FIFO's RD and WR lines, respectively
;
;
;
; 

INIT_FIFO
		LDA		#$FF
		STA     SYSTEM_VIA_PCR			; CB2=FAMS=flash A16=1;  CA2=FA15=A15=1; Select flash Bank #3
		STZ 	SYSTEM_VIA_ACR			; Disable PB7, shift register, timer T1 interrupt.  Not absolutely required while interrupts are disabled FIXME: set up timer
		STZ		SYSTEM_VIA_DDRA			; Set PA0-PA7 to all inputs
		STZ		SYSTEM_VIA_DDRB			; In case we're not coming off a reset, make PORT B an input and change output register when it's NOT outputting
		LDA		#FIFO_RD				;
		STA		SYSTEM_VIA_IORB			; Avoid possible glitch by writing to output latch while Port B is still an input (after reset)
		LDA		#(FIFO_RD + FIFO_WR)	; Make the FIFO RD and FIFO_WR pins outputs so we can strobe data in and out of the FIFO
		STA		SYSTEM_VIA_DDRB			; Port B: PB2 and PB3 are outputs; rest are inputs from earlier IORB write
		; Defensively wait for ports to settle 
		NOP		; FIXME: Defensive and possibly unnecessary
		RTL		; FUBAR - premature exit
FIFOPWR
		; FIXME: Add timeout here
		LDA		SYSTEM_VIA_IORB
		AND		#FIFO_PWREN				; PB5 = PWRENB. 0=enabled 1=disabled
		BNE		FIFOPWR	
		RTL

; A kludge until timers work to limit transmit speed to avoid TX overruns
; This is kind of terrible.  Replace.
TX_DLY_CYCLES = $0940			; Not tuned.  As it's temporary, optimum settings are unimportant.
; $24FF - reliable
; $1280 - reliable
; $0940 - reliable
; $04A0 - not reliable
; $06F0 - reliable.  Good enough for now. We're going to use VIA timer for this soon anyway
; 
; 
TXCHDLY		PHY
			LDY		#TX_DLY_CYCLES		; FIXME: Very bad work-around until timers are up
; Y = 16 bit delay count
DLY_Y		DEY
			NOP
			NOP
			NOP
			BNE		DLY_Y
			PLY
			RTL

			

QBFMSG	.text 	CR,CR
	.text	"                  I YAM INDA RAM!",CR
 	.text	"        _,-=._              /|_/|",CR
 	.text	"       *-.}   `=._,.-=-._.,  @ @._,",CR
 	.text   "          `._ _,-.   )      _,.-'",CR
        .text   "             `    G.m-'^m'm'",CR
	.text   "          Foxy art by: Dmytro O. Redchuk",CR,CR
        .text	0

