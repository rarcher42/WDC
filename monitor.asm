
; Assembled with 64TASS
; 		64tass -c bootloader.asm -L bootloader.lst
; 
;

CTRL_C	= 3
BS		= 8
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

        .cpu    "65816"
        .as     			; A=8 bits
        .xl     			; X, Y = 16 bits

; Direct page fun
*=$90
TERM_FLAGS	.byte	?					; Pick somewhere not used by WDCmon
	ECHO_FLAG	= MASK6						; Use bit 6 so BIT can be used
	
REC_TYPE	.byte 	?
DP_START	.byte	?
PTR_L		.byte	?	; Generic pointer
PTR_H		.byte	?
PTR_B		.byte	?
PTR			=		PTR_L

CTR_L		.byte	?	; Counter
CTR_H		.byte	?
CTR_B		.byte	?

SA_L		.byte 	?	; Starting address storage
SA_H		.byte 	?
SA_B		.byte	?
SA			=		SA_L
DATA_CNT	.byte 	?	; Count of record's actual storable data bytes
; A variety of temporary-use variables at discretion and care of coder
TEMP		.byte 	?
EXTRA		.byte	? 	; Used inside loader.  Please don't use elsewhere
TEMP2		.byte	?
SUBTEMP 	.byte	?	; Any subroutine that doesn't call others can use as local scratchpad space
CHART		.byte	?


* = $0400			; Command buffer area
BUFPTR		.byte	?
			.byte 	?
CMDBUF 		.fill	254					;	 

STACKTOP	=	$6000	; Top of RAM = $07EFF (I/O is $7F00-$7FFF)
* = $F800	
START 		SEI
			CLC	
			XCE							; Native mode
			SEP		#(M_FLAG)			; A,M = 8bit
			REP		#(X_FLAG | D_FLAG)	; 16 bit index, binary math
			NOP
			LDX		#STACKTOP
			TXS
			; Load the Databank register (DBR) to $0000
			LDA		#$00
			PHA
			PLD
			; Load the direct page register to $0000
			LDX		#$0000
			PHX
			PLD	
			;
			LDA     #SCTL_V 	; 9600,n,8,1.  rxclock = txclock
			STA 	SCTL		
			LDA     #SCMD_V 	; No parity, no echo, no tx or rx IRQ (for now), DTR*
			STA     SCMD
			JSL		INIT_FIFO
			JSL		INITSER
MONPROMPT	LDY		#QBFMSG
			JSL		PUT_STR
			JSL		GETLINE
			JSL		PROCESS_LINE
			JMP		MONPROMPT
			
				
PUT_STR		LDA		0,Y				; Y points directly to string
			BEQ		PUTSX
			JSL		PUT_CHR
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
		
; Raw I/O wrappers to simplify changing I/O ports.  Probably temporary
PUT_CHR		JSL		MON_PUTC
			RTL
			
GET_CHR	    JSL		MON_GETC
			STA		CHART
			BIT		TERM_FLAGS	; Check for ECHO flag (b7)
			BVC		GCHC1		; Bit 6 = ECHO
			LDA		CHART
			JSL		PUT_CHR		; echo on; repeat it back
GCHC1		CMP		#CTRL_C
			BNE		GCHC2
			JML		MONPROMPT			; FIXME: FUBAR stack memory leak
GCHC2		LDA		CHART
			RTL
GETLINE		LDA		#ECHO_FLAG		
			STA		TERM_FLAGS			; Echo back while editing
			LDX		#CMDBUF	
GSLP1		JSL		GET_CHR				; With or without echo
			CMP		#LF
			BEQ		GSLP1
			CMP		#BS					; We will not tolerate BS here
			BEQ		GSLP1
			STA		0,X					; store it	
			INX
			CMP		#CR					;
			BEQ		GSXIT1
			CMP		#CTRL_C
			BNE		GSLP1
			LDX		#CMDBUF+1
GSXIT1		DEX							; discard the CR
GSXIT2		STZ		0,X					; null-terminate the line
			RTL
			


; ==============================================================================================================================
PROCESS_LINE	
			LDA		#'"'
			JSL		PUT_CHR
			LDY		#CMDBUF
			JSL		PUT_STR
			LDA		#'"'
			JSL		PUT_CHR
			JSL		CRLF
			LDA		CMDBUF
			STA		SDR					; FUBAR - debug of command character
			CMP		#'L'
			BNE		PLIC2
			LDY		#MSG_LOADER
			JSL		PUT_STR
			JSL 	SREC_LOADER
PLIC2		CMP		#'G'
			BNE 	PLIC3
			JSL		RUNSPOTRUN
PLIC3		CMP		#'J'
			BNE		PLIC9
			JSL		RUNSPOTRUN
PLIC9		CMP		#CTRL_C
			BNE		PLIX1
			BRK							; return to system monitor
PLIX1		RTL

CRLF		LDA		#CR
			JSL		PUT_CHR
			LDA		#LF
			JSL		PUT_CHR
			RTL
			
RUNSPOTRUN	LDY		#MSG_6HEX
			JSL		PUT_STR
			JSL		GETHEX
			STA		SA_B
			JSL		GETHEX
			STA		SA_H
			JSL		GETHEX
			STA		SA_L
			LDY		#MSG_JUMPING
			JSL		PUT_STR
			LDA		SA_B
			JSR		PUTHEX
			LDA		#':'
			JSR		PUT_CHR
			LDA		SA_H
			JSR		PUTHEX
			LDA		SA_L
			JSR		PUTHEX
			LDA		#CR
			JSL		PUT_CHR
			JMP		[SA]
							

;-----------------------------------------------------------------------------------
; S-record loader 
;S0 06 0000 484452 1B (HDR)
;S1 23 F800 78D8A2FF9A2033F9A2F8A0AE206EF9204BF9A9F88522A9008521A9028525A900 A5
;S5 03 0013 E9
;S9 03 F800 04
; (spaces added for readability; not part of the format)
;
; FIXME: This is a hyper-minimal loader, in fine board bring up tradition.
; Will probably use this loader to develop a much better loader :D
SREC_LOADER	
		LDA		#0					; No echo
		STA		TERM_FLAGS
SYNC	JSL		GET_CHR				; Wait for "S" to start a new record
		CMP		#'S'
		BNE		SYNC
		LDA		#'@'
		STA		SDR
		; Optimistically assume start of record.
		JSL		GET_CHR
		STA		REC_TYPE										
		JSL		GETHEX				; Get message length byte
		STA		DATA_CNT			; Save number of bytes in record
		LDA		REC_TYPE			; Decode and dispatch	
		BEQ		GETREMS				; read the comment block
		CMP		#'1'
		BEQ		GET16ADDR
		CMP		#'2'
		BEQ		GET24ADDR
		CMP		#'5'
		BNE		SLC4
		JML		CNT16
SLC4	CMP		#'6'
		BNE		SLC2
		JML		CNT24
SLC2	CMP		#'8'
		BNE		SLC1
		JML		SA24		; Too far for relative branch
SLC1	CMP		#'9'
		BNE		SLC3
		JML		SA16
		; We'll ignore everything else, including the HDR record
SLC3	JML		SYNC

GETREMS	LDA		#'S'
		JSL		PUT_CHR
		LDA		#'0'
		JSL		PUT_CHR
		JML		SYNC
GET24ADDR
		LDA		#'2'
		STA		SDR
		LDA		DATA_CNT	
		SEC		
		SBC		#4			; Data length -= 3 bytes address + 1 byte checksum 
		STA		DATA_CNT	; Adjust data count to include only payload data bytes
		JSL		GETHEX
		STA		PTR_B
		BRA		GET1624
GET16ADDR
		LDA		#'1'
		STA		SDR
		LDA		DATA_CNT	
		SEC		
		SBC		#3			; Data length -= 2 bytes address + 1 byte checksum 
		STA		DATA_CNT	; Adjust data count to include only payload data bytes
		STZ		PTR_B		; 16 bit records.  Default Bank to 0!  (0+! NOT 0!=1)
GET1624	JSL		GETHEX		; Got bank value (or set to 0). Now get high and low address
		STA		PTR_H
		JSL		GETHEX
		STA		PTR_L

; Now check to see if any bytes remain to be written 
SAVDAT:	LDA		DATA_CNT	; A record can have 0 data bytes, theoretically. So check at top
		BEQ		SAVDX1		; No more data to PROCESS_LINE
SAVDAT2	JSL		GETHEX
		STA		[PTR]		; 24 bit indirect save
		JSL		INC_PTR		; Point to next byte
		DEC		DATA_CNT
		BNE		SAVDAT2
SAVDX1	LDA		#'#'
		STA		SDR
		JML		SYNC		; FIXME: parse the checksum and end of line
		
; S5, S6 records - record 24 bit value in CTR_B, CTR_H, CTR_L	
CNT16	LDA		#'5'
		STA		SDR
		JSL		PUT_CHR
		STZ		CTR_B
		BRA		CN16C1
CNT24:	LDA		#'6'
		STA		SDR
		JSL		GETHEX
		STA		CTR_B
CN16C1	JSL		GETHEX		; bits 15-8
		STA		CTR_H
		JSL		GETHEX		; bits 7-0
		STA		CTR_L
		LDA		#'#'
		STA		SDR
		JML		SYNC		; FIXME: parse the rest of the record & end of line

; S8 or S9 record will terminate the loading, so it MUST be last (and typically is)
SA16	LDA		#'9'
		STA		SDR
		STZ		SA_B
		BRA		SA16C1
SA24	LDA		#'8'
		STA		SDR
		JSL		GETHEX		; length byte
		STZ		SA_B
SA16C1	JSL		GETHEX		; bits 15-8
		STA		SA_H
		JSL		GETHEX		; bits 7-0
		STA		SA_L
		LDA		#'&'
		STA		SDR
		JML		MONPROMPT

; 24 bit binary pointer increment.  We're in 8 bit accumulator mode, so it's 3 bytes.
INC_PTR	INC		PTR_L		; point to the next byte to save to
		BNE		INCPX1	
		INC		PTR_H	
		BNE		INCPX1
		INC		PTR_B
INCPX1	RTL

; Basic conversions	
GETHEX  JSL 	GET_CHR
		CMP		#CTRL_C
		BNE		GHECC1
		LDA		#'^'
		JSL		PUT_CHR
		LDA		#'C'
		JSL		PUT_CHR
        JML		MONPROMPT
GHECC1	JSL     MKNIBL  	; Convert to 0..F numeric
        ASL     A
        ASL     A
        ASL     A
        ASL     A       	; This is the upper nibble
        AND     #$F0
        STA     SUBTEMP
        JSL     GET_CHR
		CMP		#CTRL_C
		BNE		GHECC2
		LDA		#'^'
		JSL		PUT_CHR
		LDA		#'C'
		JSL		PUT_CHR
		JML		MONPROMPT
GHECC2	JSL     MKNIBL
        ORA    	SUBTEMP
        RTL


		

;

;----------------    
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
; if not bank #3, call from RAM, not from flash!
SEL_BANK3
		LDA		#%11111111
		STA		SYSTEM_VIA_PCR	
		RTL
		
SEL_BANK2
		LDA		#%11111101
		STA		SYSTEM_VIA_PCR	
		RTL
		
SEL_BANK1
		LDA		#%11011111
		STA		SYSTEM_VIA_PCR	
		RTL

SEL_BANK0
		LDA		#%11011101
		STA		SYSTEM_VIA_PCR	
		RTL
		
INIT_SYSVIA
		LDA		#%11111111
		STA		SYSTEM_VIA_PCR	
		STZ		SYSTEM_VIA_DDRA
		STZ		SYSTEM_VIA_DDRB
		RTL
		
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

; Attempt to output the byte in A.
; If successful, the carry flag will be Clear (C=0) 
; If the FIFO is full, it will return immediately with the carry set (C=1)
; Caller is responsible for checking the carry flag with BCC or BCS 
; and re-trying if carry is clear.
PUTCHF	STA		TEMP2
		LDA		SYSTEM_VIA_IORB		; Read in FIFO status Port for FIFO
		AND		#FIFO_TXE			; If TXE is low, we can accept data into FIFO.  If high, return immmediately
		SEC							; FIFO is full, so don't try to queue it!	
		BNE		OFX1				; 0 = OK to write to FIFO; 1 = Wait, FIFO full!
		; FIFO has room - write A to FIFO in a series of steps
OFCONT	STZ	SYSTEM_VIA_DDRA			; (Defensive) Start with Port A input/floating 
		LDA		#(FIFO_RD + FIFO_WR)	; RD=1 WR=1 (WR must go 1->0 for FIFO write)
		STA		SYSTEM_VIA_IORB			; Make sure write is high (and read too!)
		LDA		TEMP2					; Restore the data to send
		STA		SYSTEM_VIA_IORA			; Set up output value in advance in Port A (still input so doesn't go out yet) 
		LDA		#$FF					; make Port A all outputs with stable output value already set in prior lines
		STA		SYSTEM_VIA_DDRA			; Save data to output latches
		NOP							; Some settling time of data output just to be safe
		NOP
		NOP
		NOP
		NOP
		NOP
		; Now the data's stable on PA0-7, pull WR line low (leave RD high)
		LDA	#(FIFO_RD)		; RD=1 WR=0 (WR1->0 transition triggers FIFO transfer!)
		STA	SYSTEM_VIA_IORB		; Low-going WR pulse should latch data
		NOP				; Hold time following write strobe, to ensure value is latched OK
		NOP
		NOP
		NOP
		NOP
		NOP
		STZ	SYSTEM_VIA_DDRA		; Make port A an input again
		CLC				; signal success of write to caller
OFX1	LDA		TEMP2
		RTL
;
;
		
; On exit:
; If Carry flag is clear, A contains the next byte from the FIFO
; If carry flag is set, there were no characters waiting
GETCHF	LDA		SYSTEM_VIA_IORB		; Check RXF flag
		AND		#FIFO_RXF			; If clear, we're OK to read.  If set, there's no data waiting
		SEC
		BNE 	INFXIT				; If RXF is 1, then no character is waiting!
		STZ		SYSTEM_VIA_DDRA		; Make Port A inputs
		LDA		#FIFO_RD
		STA		SYSTEM_VIA_IORB		; RD=1 WR=0 (RD must go to 0 to read
		NOP
		STZ		SYSTEM_VIA_IORB		; RD=0 WR=0	- FIFO presents data to port A	
		NOP
		NOP
		NOP
		NOP
		LDA		SYSTEM_VIA_IORA		; read data in
		PHA
		LDA		#FIFO_RD		; Restore back to inactive signals RD=1 and WR=0
		STA		SYSTEM_VIA_IORB
		PLA
		CLC				; we got a byte!
INFXIT	RTL

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

			
	
PUTHEX  	PHA             	;
        	LSR 	A
        	LSR 	A
			LSR 	A
			LSR 	A
        	JSL     PRNIBL
        	PLA
PRNIBL  	AND     #$0F    	; strip off the low nibble
        	CMP     #$0A
        	BCC  	NOTHEX  	; if it's 0-9, add '0' else also add 7
        	ADC     #6      	; Add 7 (6+carry=1), result will be carry clear
NOTHEX  	ADC     #'0'    	; If carry clear, we're 0-9
; Write the character in A as ASCII:
PUTCH		JSL		PUT_CHR
			RTL

        ; 
; Convert the ASCII nibble to numeric value from 0-F:
MKNIBL  	CMP     #'9'+1  	; See if it's 0-9 or 'A'..'F' (no lowercase yet)
        	BCC     MKNNH   	; If we borrowed, we lost the carry so 0..9
        	SBC     #7+1    	; Subtract off extra 7 (sbc subtracts off one less)
        	; If we fall through, carry is set unlike direct entry at MKNNH
MKNNH   	SBC     #'0'-1  	; subtract off '0' (if carry clear coming in)
        	AND     #$0F    	; no upper nibble no matter what
        	RTL             	; and return the nibble

MSG_JUMPING:
	.text	CR,"Jumping to address:",0

MSG_LOADER
	.text	CR,"Loader started!",CR
	.text 	0
	
MSG_6HEX	
	.text	CR,"Enter 6 digit hex address:",0

QBFMSG	.text 		CR,CR
	.text	"                  VCBmon v 1.00",CR
	.text 	"          ******************************",CR
	.text 	"          *                            *",CR
	.text 	"          *    The Quick brown Dog     *",CR
	.text 	"          *  Jumps over the Lazy Fox!  *",CR
	.text 	"          *                            *",CR
	.text 	"          ******************************",CR
 PROMPT	
	.text	CR
	.text	"        _,-=._              /|_/|",CR
 	.text	"       *-.}   `=._,.-=-._.,  @ @._,",CR
 	.text   "          `._ _,-.   )      _,.-'",CR
        .text   "             `    G.m-'^m'm'",CR
	.text   ">"
    .text	0
	
ANYKEY:	.text	LF,LF
	.text 	"Press the ANY key (CTRL-C) to return to monitor",CR
	.text   "else continue foxing:"
	.text	0

* = $FFE4
NCOP	.word		START		; COP exception in native mode
* = $FFE6
NBRK	.word		START		; BRK in native mode
* = $FFE8
NABORT	.word		START
* = $FFEA
NNMI	.word		START		; NMI interrupt in native mode
* = $FFEE
NIRQ	.word		START 

* = $FFF4
ECOP	.word		START		; COP exception in 65c02 emulation mode
* = $FFF8
EABORT	.word		START
* = $FFFA
ENMI	.word		START		; NMI interrupt in 65c02 emulation mode
* = $FFFC
ERESET	.word		START		; RESET exception in all modes
* = $FFFE
EIRQ	.word		START 

.end				; finally.  das Ende.  Fini.  It's over.  Go home!