
; Assembled with 64TASS
; 		64tass -c bootloader.asm -L bootloader.lst
; 
;
.INCLUDE	"via_symbols.inc"

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

STACKTOP    = $07EFF


			.cpu 	"65816"
			.as					; A=8 bits
			.xl					; X, Y = 16 bits

* = $6000		; RAM load address
START 		
			SEI
			CLC
			XCE
			REP	#(X_FLAG | D_FLAG)
			SEP	#M_FLAG
			LDX	#STACKTOP
			TXS
			JSR	INIT_FIFO
			LDY	#MSG_FOXRAM
			JSR	PUT_STR
POINTLESS	JSR	GET_FIFO
			CMP	#CTRL_C
			BNE	START	
			JML $00F800

; Point Y to null-terminated string
PUT_STR		
			LDA	0,Y				; Y points directly to string
			BEQ	PUTSX
			JSR	PUT_FIFO
			INY						; point to next character
			BRA	PUT_STR		
PUTSX		
			RTS	

;;;; ============================= New FIFO functions ======================================
; Initializes the system VIA (the USB debugger), and syncs with the USB chip.

FIFO_TXE = PB0
FIFO_RXF = PB1
FIFO_WR = PB2
FIFO_RD = PB3
FIFO_PWREN = PB5
FIFO_DEBUG = PB7		; Handy debug toggle output free for any use


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
PUT_FIFO	
			JSR	PUT_FRAW
			BCS	PUT_FIFO
			RTS
			
GET_FIFO	JSR GET_FRAW
			BCS	GET_FIFO
			RTS
			
			
; if not bank #3, call from RAM, not from flash!
SEL_BANK3
			LDA	#%11111111
			STA	SYSTEM_VIA_PCR	
			RTS
	
SEL_BANK2
			LDA	#%11111101
			STA	SYSTEM_VIA_PCR	
			RTS
		
SEL_BANK1
			LDA	#%11011111
			STA	SYSTEM_VIA_PCR	
			RTS

SEL_BANK0
			LDA	#%11011101
			STA	SYSTEM_VIA_PCR	
			RTS
		
INIT_SYSVIA
			LDA	#%11111111
			STA	SYSTEM_VIA_PCR	
			STZ	SYSTEM_VIA_DDRA
			STZ	SYSTEM_VIA_DDRB
			RTS
	
; NOTE:  Kludge delay until timer because if powered by RS232 not USB, the FIFO will never report power enable signal and we'll hang forever.	
INIT_FIFO
			LDA	#$FF
			STA SYSTEM_VIA_PCR			; CB2=FAMS=flash A16=1;  CA2=FA15=A15=1; Select flash Bank #3
			STZ SYSTEM_VIA_ACR			; Disable PB7, shift register, timer T1 interrupt.  Not absolutely required while interrupts are disabled FIXME: set up timer
			STZ	SYSTEM_VIA_DDRA			; Set PA0-PA7 to all inputs
			STZ	SYSTEM_VIA_DDRB			; In case we're not coming off a reset, make PORT B an input and change output register when it's NOT outputting
			LDA	#FIFO_RD				;
			STA	SYSTEM_VIA_IORB			; Avoid possible glitch by writing to output latch while Port B is still an input (after reset)
			LDA	#(FIFO_RD + FIFO_WR + FIFO_DEBUG)	; Make FIFO RD & WR pins outputs so we can strobe data in and out of the FIFO
			STA	SYSTEM_VIA_DDRB			; Port B: PB2 and PB3 are outputs; rest are inputs from earlier IORB write
			JSR	TXCHDLY
			JSR	TXCHDLY
			JSR	TXCHDLY
			JSR	TXCHDLY
			JSR	TXCHDLY
			RTS					; FUBAR - don't wait on the FIFO which stupidly may not even have power if not USB powered

		
; Non-blocking Put FIFO.  Return with carry flag set if buffer is full and nothing was output. 
; Return carry clear upon successful queuing
PUT_FRAW	
			STA	TEMP2
			LDA	SYSTEM_VIA_IORB			; Read in FIFO status Port for FIFO
			AND	#FIFO_TXE				; If TXE is low, we can accept data into FIFO.  If high, return immmediately
			SEC							; FIFO is full, so don't try to queue it!	
			BNE	OFX1					; 0 = OK to write to FIFO; 1 = Wait, FIFO full!
			; FIFO has room - write A to FIFO in a series of steps
OFCONT	
			STZ	SYSTEM_VIA_DDRA			; (Defensive) Start with Port A input/floating 
			LDA	#(FIFO_RD + FIFO_WR)	; RD=1 WR=1 (WR must go 1->0 for FIFO write)
			STA	SYSTEM_VIA_IORB			; Make sure write is high (and read too!)
			LDA TEMP2							; Restore the data to send
			STA	SYSTEM_VIA_IORA			; Set up output value in advance in Port A (still input so doesn't go out yet) 
			LDA	#$FF				; make Port A all outputs with stable output value already set in prior lines
			STA	SYSTEM_VIA_DDRA			; Save data to output latches
			NOP					; Some settling time of data output just to be safe
			; Now the data's stable on PA0-7, pull WR line low (leave RD high)
			LDA	#(FIFO_RD)			; RD=1 WR=0 (WR1->0 transition triggers FIFO transfer!)
			STA	SYSTEM_VIA_IORB			; Low-going WR pulse should latch data
			NOP							; Hold time following write strobe, to ensure value is latched OK
			STZ	SYSTEM_VIA_DDRA			; Make port A an input again
			CLC					; signal success of write to caller
OFX1	
			LDA	TEMP2
			RTS
;
;
		
; On exit:
; If Carry flag is clear, A contains the next byte from the FIFO
; If carry flag is set, no character was received and A doesn't contain anything meaningful
GET_FRAW	
			LDA	SYSTEM_VIA_IORB			; Check RXF flag
			AND	#FIFO_RXF			; If clear, we're OK to read.  If set, there's no data waiting
			SEC
			BNE 	INFXIT				; If RXF is 1, then no character is waiting!
			STZ	SYSTEM_VIA_DDRA			; Make Port A inputs
			LDA	#FIFO_RD
			STA	SYSTEM_VIA_IORB			; RD=1 WR=0 (RD must go to 0 to read
			NOP
			STZ	SYSTEM_VIA_IORB			; RD=0 WR=0	- FIFO presents data to port A	
			NOP
			LDA	SYSTEM_VIA_IORA			; read data in
			PHA
			LDA	#FIFO_RD			; Restore back to inactive signals RD=1 and WR=0
			STA	SYSTEM_VIA_IORB
			PLA
			CLC					; we got a byte!
INFXIT	
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

