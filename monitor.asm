
; Assembled with 64TASS
; 		64tass -c bootloader.asm -L bootloader.lst
; 
; Put the above equates into an included file per peripheral or board

        .cpu    "65816"
        .as     			; A=8 bits
        .xl     			; X, Y = 16 bits
		
.INCLUDE	"via_symbols.inc"
.INCLUDE	"acia_symbols.inc"

; Monitor hooks - These we MUST JSL to
;RAW_GETC	=	$E036
;RAW_PUTC	= 	$E04B

CTRL_C	= $03
BS		= $08
LF		= $0A
CR		= $0D
SP		= $20
DEL    	= $7F

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

; Direcct page fun

*=$E0

REC_TYPE	.byte 	?
PTR_L		.byte	?	; Generic pointer
PTR_H		.byte	?
PTR_B		.byte	?
PTR			=		PTR_L

CTR_L		.byte	?	; Counter
CTR_H		.byte	?
CTR_B		.byte	?
CTR			= 		CTR_L

SA_L		.byte 	?	; Starting address storage for various commands & loader
SA_H		.byte 	?
SA_B		.byte	?
SA			=		SA_L

EA_L		.byte 	?	; Starting address storage for various commands
EA_H		.byte 	?
EA_B		.byte	?
EA			=		EA_L


DATA_CNT	.byte 	?	; Count of record's actual storable data bytes
; A variety of temporary-use variables at discretion and care of coder
FIFO_PIT	.byte	?
SUBTEMP 	.byte	?	; Any subroutine that doesn't call others can use as local scratchpad space
HEXASSY		.byte	?
SRC		.byte	?	; Where did the last character come from?

* = $0400			; Command buffer area
CMDBUF 		.fill	256	; can be smaller than 256 but must not cross 8 bit page boundary
				; because we use 8 bit math to determine stuff and nobody will
				; want to type a command longer than 256 characters in any case
; Read and write pointers into command buffer
CB_RDPTR	.word	?	; 16 bits
CB_WRPTR	.word 	?	; MSByte is always $00.  Waste 1 byte of RAM to avoid two mode changes of X flag
; Parameter metadata
PRM_SA	.word	?		; Parameter start address
PRM_SIZ	.byte	?		; Size of current parameter		
EOLFLAG	.byte	?		; 0 = EOL not found, !0 = EOL has been encountered
BYTECNT	.byte 	?


; 8-24 bit binary I/O buffer for print operations, or to convert incoming to binary 
HEXIO_L	.byte	?
HEXIO_H	.byte	?
HEXIO_B	.byte	?
HEXIO		=	HEXIO_L				; 24 bit HEX value to print

STACKTOP	=	$7EFF				; Top of RAM = $07EFF (I/O is $7F00-$7FFF)
* = $F800
START 	
			SEI
			CLC
			XCE
			REP	#(X_FLAG | D_FLAG)
			SEP	#M_FLAG
			LDX	#STACKTOP
			TXS
			JSR	INIT_FIFO
			JSR	INIT_SER
			; Bit of a kludge to clean up later.  Send prompt to both 
			; FIFO and RS232 to be sure recipient gets header
			STZ	SRC			; First send to FIFO
			LDY	#QBFMSG			; Start of monitor loop
			JSR	PUT_STR
			LDA	#1
			STA	SRC
			LDY	#QBFMSG
			JSR	PUT_STR			; Send out serial port too
			
MONGETL		
			JSR	CRLF			; FIXME: send command prompt to both ports 
			LDA	#'>'			; Should have flag for "both ports", probably.
			JSR	PUTCHAR			; But as RS232 is so very slow, let's not force too much down this narrow pipe
			STZ	SRC
			JSR	CRLF
			LDA	#'>'
			JSR	PUTCHAR
			JSR	GETLINE
			JSR	CRLF
			LDA	#'"'
			JSR	PUTCHAR
			LDY	#CMDBUF
			JSR	PUT_STR
			LDA	#'"'
			JSR	PUTCHAR
			JSR	CRLF
			JSR	PARSELINE
			BRA	MONGETL			; End of monitor loop

; Check both FIFO and ACIA for incoming.  Set SRC to mark which
GETCHAR	    		
			STZ	SRC			; Assume SRC=FIFO
GETCH_C1
			JSR GET_FRAW		; Check FIFO.  Anything waiting?
			BCC	GETC_X1			; Yes, return it
			JSR	GETSER_RAW
			BCS	GETCH_C1
			INC	SRC			; SRC = 1 means async serial
GETC_X1			
			JSR	TOPUPPER		; Make alphabetics Puppercase
			RTS

PUTCHAR		
			PHA
			LDA	SRC
			BNE	PUTCHAR_C2
			PLA
			JSR	PUT_FIFO
			BRA	PUTCHAR_X1
PUTCHAR_C2		
			PLA
			JSR	PUT_SER
PUTCHAR_X1
			RTS


PUTCHARTR	
			CMP	#$20
			BCS	PUTCHAR
			PHA					; Display as hex value
			LDA	#'\'
			JSR	PUTCHAR
			PLA
			JSR	PUTHEXA
PUTCRX1		
			RTS

PUT_STR		
			LDA	0,Y				; Y points directly to string
			BEQ	PUTSX
			JSR	PUTCHAR
			INY					; point to next character
			BRA	PUT_STR		
PUTSX		
			RTS	

; Show control characters as printable
PUT_STR_CTRL 
			LDA	0,Y				; Y points directly to string
			BEQ	PUTSRX
			JSR	PUTCHARTR			; Show control characters, etc.
			INY					; point to next character
			BRA	PUT_STR_CTRL
PUTSRX		
			RTS	

; Init the parser pointers and counters for parsing a new line
INITPARS	
			STZ	PRM_SIZ			; No known parameter size
			STZ	EOLFLAG			; No EOL found yet
			LDX	#CMDBUF
			STX	CB_RDPTR		; Start read pointer at start of command buffer
			STX	PRM_SA			; First parameter starts at command buffer[0]
			RTS

CLRCMD	
			LDX	#$0000			; Not to worry; we want x = 0 where using this
			STX	CB_WRPTR		; Upper byte is 0 but we want 16 bit X to load/store to avoid setting/restoring X flag
			STZ	CMDBUF			; Pre-emptively null terminate the empty buffer
			RTS

;--- Get command line.  Imperfect editor, due to no raw get character capability in W265 monitor.  Silly, inflexible omission.
; Never omit a raw layer of I/O.  Shame on WDC.  Basic design error locking user into behaviors they don't want.
MAXLINE 	= 		132			; MAXLINE should be $FE or less
GETLINE		
			JSR	CLRCMD
			; Side effect of CLRCMD is setting X to $0000
GLNEXT		CPX #MAXLINE		; Maxline must be $FE or lower
			BCS	CTL_C			; Sorry, too long!  Abort the line as it's obvious nonsense
			JSR	GETCHAR			; No echo
			; Handle CR and CTRL-C
			CMP	#CR
			BNE GLCHKCC
			; CR handling
			JSR	PUTCHAR
			BRA	GLXIT1
GLCHKCC	
			; Handle various control characters prior to final filter discarding them
			CMP	#CTRL_C
			BNE	GLCHKBS
			; CTRL-C handler
CTL_C 
			LDA	#'^'
			JSR	PUTCHAR
			LDA	#'C'
			JSR	PUTCHAR
			LDA	#CR
			JSR	PUTCHAR
			JSR	CLRCMD				; zotch out any command in buffer
			BRA	GLXIT1			
GLCHKBS
			; Handle backspace/del logic (currently identical)
			CMP	#BS				; We will not tolerate BS here
			BEQ	GL_DEL
			CMP	#DEL
			BNE	GLNC1			; Neither BS or DEL, continue search
GL_DEL			
			; Handle backspace
			CPX	#0				; Special case: do not print BS if we're at start of buffer
			BEQ	GLNEXT			; Do nothing for BS/DEL in empty buffer
			DEX	
			LDA	#BS				; Now back over the character
								; Note: this is a humane algorithm, because
								; we euthanized the character BEFORE backing over it.
			JSR	PUTCHAR			; print the backspace
			LDA	#SP
			JSR	PUTCHAR
			LDA	#BS
			JSR	PUTCHAR
			; pointing to the next available so decrement
			STZ CMDBUF,X		; Overwrite backed-over character with NULL
			BRA	GLNEXT			; 
GLNC1		
			CMP	#SP
			BCC	GLNEXT			; If not yet handled and < SP, ignore $00-$1F
			; Store the character
			STA	CMDBUF,X		; store it
			INX					; point to next free location
			JSR	PUTCHAR
			STZ	CMDBUF,X		; Null-terminate new blank spot
			BRA	GLNEXT
GLXIT1		
			STX	CB_WRPTR
			RTS
			
; Look in the CMDBUF and dispatch to appropriate command. 	
PARSELINE	
			JSR	INITPARS
FINDCMD		
			JSR	FINDSTART		; Skip over whitespace.  On return CB_RDPTR, PRM_SA hold start of first/next parameter
			LDA	EOLFLAG			; OR if we hit EOL, then there's no command byte on the line and we have nothing to process
			BNE	PLIX2			; We hit an EOL before an actionable character, so quit
			; Attempt to dispatch command by first letter from JSR table
			LDA	#0
			XBA				; Make B zero so when TAX times comes, MSB of X will be 0! (0 emphasis not 0 factorial)
			LDX	CB_RDPTR		; point to command byte
			LDA	0,X			; Get command byte
			INX				; Point past the command byte to save each subroutine from doing this
			STX	CB_RDPTR		; "
			CMP	#'A'
			BCC	PLERRXIT		; < 'A', so not a command
			CMP	#'Z'+1
			BCS	PLERRXIT		; > 'Z', so not a command
			; Convert 'A'-'Z' to 0 to 25 for subroutine call table 
			SBC	#'A'-1			; Carry clear, so subtract one less to account for borrow
			ASL	A			; Two bytes per JSR table entry	
			TAX						; X now holds offset in MONTABLE
			JSR	(MONTBL,X)		; No JSR indirect indexed.  Each table entry MUST end in RTS not RTL!
			BRA	PLIX2			; We're done dispatching.  
			; Whoops, we didn't get 'A'-'Z' so entry not in a JSR table.  Print error
			; including non-printing control characters, '\nn' Python-style
PLERRXIT:	
			JSR	LOLWUT			; Print non-understood buffer plus ?[CR][LF]
PLIX2		
			RTS
	
			
; Parameter extraction utility.  
; Skip any leading whitespace from current read pointer (FIND parameter start)
; Flag encounter with EOL by setting EOLFLAG to non-zero
; Find parameter start, skipping any leading whitespace but respecting CR, null, and CTRL_C as end of line markers
; AKA:  "Skip whitespace until not whitespace (or EOL)"
;
; Entry:   
;			CB_RDPTR must point into first unprocessed character in the buffer
;			PRM_SA = don't care
;			EOLFLAG = 0 = have not encountered EOL (else why are you calling me?)
;			PRM_SIZ	= don't care
; Exit:
;			CB_RDPTR points to end of parameter or whitespace or EOL
;			PRM_SA points to first character of current Parameter
;			PRM_SIZ = Number of bytes in this parameter
;			
FINDSTART	
			LDY	CB_RDPTR
FSN1		
			LDA	0,Y			; Get next character
			BEQ	FSEOL			; Null --> End of line encountered.  We are done
			CMP	#CR
			BEQ	FSEOL			; CR = end of line also
			CMP	#CTRL_C
			BEQ	FSEOL			; CTRL-C = end of line
			CMP	#SP+1			; if space or less, and not CR or CTRL-C, skip over
			BCS	FSDUN			; A non-whitespace character.  We're done looking
			; A whitespace character that's not special, so keep looking
			INY				; Keep looking for a valid parameter byte
			BRA	FSN1			; Next character
FSEOL		
			LDA	#1
			STA	EOLFLAG
FSDUN		
			STY	CB_RDPTR		; Save pointers by current value of Y
			STY	PRM_SA			; Save pointers by current value of Y
			RTS
			
; Parameter extraction utility.
; Skip valid parameter bytes until whitespace before next parameter, or EOL 
; AKA: "skip non-whitespace until whitespace (or EOL)"
; Flag encounter with EOL by setting EOLFLAG to non-zero
;
; TL;DR: Find the first character of the NEXT parameter or EOL
; On entry:
;			CB_RDPTR = *(next buffer byte to examine)  
;			PRM_SA = don't care
;			EOLFLAG = 0 (presumably; no sense in calling again if we previously hit EOL)
; On exit:
; 			CB_RDPTR = *first byte of next Parameter begin or EOL
;			PRM_SA	= *first character of this parameter 
;			PRM_SIZ = number of bytes in this parameter
;			EOLFLAG indicates whether end of line has been encountered 
;
FINDEND		
			STZ	PRM_SIZ			; No known parameter bytes yet
			LDY	CB_RDPTR
FEN1		
			LDA	0,Y			; Get next character
			BEQ	FEEOL			; Null --> End of line encountered.  We are done
			CMP	#CR
			BEQ	FEEOL			; CR = end of line also
			CMP	#CTRL_C
			BEQ	FEEOL			; CTRL-C = end of line
			CMP	#SP+1			; if space or less, and not CR or CTRL-C, 
			BCC	FEDUN1			; A whitespace character.  We're done looking
			; A non-whitespace character.  Part of current parameter
			INY
			INC	PRM_SIZ			; add one more to size of parameter
			BRA	FEN1
FEEOL		
			LDA	#1
			STA	EOLFLAG
FEDUN1		
			STY	CB_RDPTR		; Save pointers by current value of read pointer (don't update PRM_SA)
			RTS
			

			
TOPUPPER	
			CMP	#'a'				; Make character PupperCase
			BCC	PUPX1				; A < 'a' so can't be lowercase char
			CMP	#'z'+1				
			BCS	PUPX1				; A > 'z', so can't be lowercase char	
			; Note - carry is clear so we subtract one less
			SBC	#'a'-'A'-1			; Adjust upper case to lower case		
PUPX1		
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
			;LDA #%001000000			; Bit 5 = IFR.5 = Timer 2 overflow
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
			
GET_FIFO	
			JSR GET_FRAW
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
			LDA	#$FF
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
			LDA	#(FIFO_RD + FIFO_WR)		; Make FIFO RD & WR pins outputs so we can strobe data in and out of the FIFO
			STA	SYSTEM_VIA_DDRB			; Port B: PB2 and PB3 are outputs; rest are inputs from earlier IORB write
			JSR	TXCHDLY				; Should wait (with timeout!) on PWERENB signal going low on power up or after.  
			JSR	TXCHDLY				; Timeout is essential in case board is powered off RS232 port, 
			JSR	TXCHDLY				; in which case the FIFO will not get power and this pin will never be (active) low.
			JSR	TXCHDLY
			JSR	TXCHDLY
			RTS					

		
; Non-blocking Put FIFO.  Return with carry flag set if buffer is full and nothing was output. 
; Return carry clear upon successful queuing
PUT_FRAW	
			STA	FIFO_PIT
			LDA	SYSTEM_VIA_IORB			; Read in FIFO status Port for FIFO
			AND	#FIFO_TXE				; If TXE is low, we can accept data into FIFO.  If high, return immmediately
			SEC							; FIFO is full, so don't try to queue it!	
			BNE	OFX1					; 0 = OK to write to FIFO; 1 = Wait, FIFO full!
			; FIFO has room - write A to FIFO in a series of steps
OFCONT	
			STZ	SYSTEM_VIA_DDRA			; (Defensive) Start with Port A input/floating 
			LDA	#(FIFO_RD + FIFO_WR)	; RD=1 WR=1 (WR must go 1->0 for FIFO write)
			STA	SYSTEM_VIA_IORB			; Make sure write is high (and read too!)
			LDA FIFO_PIT				; Restore the data to send
			STA	SYSTEM_VIA_IORA			; Set up output value in advance in Port A (still input so doesn't go out yet) 
			LDA	#$FF					; make Port A all outputs with stable output value already set in prior lines
			STA	SYSTEM_VIA_DDRA			; Save data to output latches
			NOP							; Some settling time of data output just to be safe
			; Now the data's stable on PA0-7, pull WR line low (leave RD high)
			LDA	#(FIFO_RD)				; RD=1 WR=0 (WR1->0 transition triggers FIFO transfer!)
			STA	SYSTEM_VIA_IORB			; Low-going WR pulse should latch data
			NOP							; Hold time following write strobe, to ensure value is latched OK
			STZ	SYSTEM_VIA_DDRA			; Make port A an input again
			CLC							; signal success of write to caller
OFX1	
			LDA	FIFO_PIT
			RTS
;
;
		
; On exit:
; If Carry flag is clear, A contains the next byte from the FIFO
; If carry flag is set, no character was received and A doesn't contain anything meaningful
GET_FRAW	
			LDA	SYSTEM_VIA_IORB			; Check RXF flag
			AND	#FIFO_RXF				; If clear, we're OK to read.  If set, there's no data waiting
			SEC
			BNE INFXIT				; If RXF is 1, then no character is waiting!
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
			
INC_SA24
			CLC
			LDA	PTR_L
			ADC	#1
			STA	PTR_L
			LDA	PTR_H
			ADC	#0
			STA	PTR_H
			LDA	PTR_B
			ADC	#0
			STA	PTR_B
			RTS
DEC_CTR24
			SEC
			LDA	CTR_L			; one less byte to print out
			SBC	#1
			STA	CTR_L
			LDA	CTR_H
			SBC	#0
			STA	CTR_H
			LDA	CTR_B
			SBC	#0
			STA	CTR_B
			RTS

	
; Dump a range of addresses.  For now we won't remember previous dump addresses, so the acceptable formats are:
; "D 00"		- Dump one byte starting at 00:0000
; "D 1234" 	- Dump one byte starting at 00:1234
; "D 00:1234" - Dump one byte starting at 00:1234
;
; "D 00 1F"	- Dump bytes from 00:0000 to 00:001F, inclusive
; "D 1234 3456" - Dump bytes from 00:1234 to 00:3456, inclusive
; "D 00:1234 01:0100" - Dump bytes from 00:1234 to 01:0100, inclusive
; "D 001234 010100" - Dump bytes from 00:1234 to 01:0100, inclusive
; "D 00:1234 010100" - Dump bytes from 00:1234 to 01:0100, inclusive
; "D 001234 01:0100" - Dump bytes from 00:1234 to 01:0100, inclusive
; "D 1234 01:0100" - Dump bytes from 00:1234 to 01:0100, inclusive
; "D 001234 010100" - Dump bytes from 00:1234 to 01:0100, inclusive
;
; Note: at 9600 baud, sending more than 64K of bytes will take approximately "forever" and therefore IS NOT SUPPORTED.
; If the ending address is more than 64K higher than the starting address, you will get less than you asked for 
; because you were being a dumb-dumb. :)
; Second address (if specified) must be higher in memory than first address
CMD_DUMPHEX 
			JSR	CRLF			; Give some space
			JSR	FINDSTART		; Skip over whitespace.  On return CB_RDPTR, PRM_SA hold start of first/next parameter
			LDA	EOLFLAG			; OR if we hit EOL, then there's no command byte on the line and we have nothing to process
			BEQ	CDH_NOTEOL		; Not EOL, so start dumping data		
			BRL	DHEXX1			; We hit an EOL before an actionable character, so quit
CDH_NOTEOL	
			STZ	BYTECNT			; First line and every 16 bytes will show current address
			JSR	FINDEND			; Get the next parameter's start address in PRM_SA and length in PRM_SIZ
			JSR	CONVHEX			; Get starting address in HEXIO
			LDA	HEXIO_B			; Put starting address in PTR
			STA	PTR_B
			LDA	HEXIO_H
			STA	PTR_H
			LDA	HEXIO_L
			STA	PTR_L
			; See if there's an ending address specified
			JSR	FINDSTART		;Get next parameter
			LDA	EOLFLAG			; is there one?
			BEQ	DHSAVEA			; save end address if not EOL after start address read
			; Dump just one byte
			STZ	CTR_B
			STZ	CTR_H
			LDA	#1
			STA	CTR_L
			BRL	DUMPITNOW
DHSAVEA		
			JSR	FINDEND		
			; Compute the number of bytes to Dump
			JSR	CONVHEX			; get 8 to 24 bit end address
			LDA	HEXIO_B
			STA	EA_B
			LDA	HEXIO_H
			STA	EA_H
			LDA	HEXIO_L
			STA	EA_L
			; Compute number of bytes to dump.  EA >= SA.  FIXME, 16 bits only, no SA > EA detection yet
			SEC
			LDA	EA_L	
			SBC	PTR_L
			STA	CTR_L
			LDA	EA_H
			SBC	PTR_H
			STA	CTR_H
			LDA	EA_B
			SBC	PTR_B			; Just to be thorough, should we support > 64K dump someday
			STA	CTR_B
			; Add 1 for starting byte
			CLC				; Probably can make this more efficient
			LDA	CTR_L			; Calculate byte count of dump in CTR
			ADC	#1
			STA	CTR_L
			LDA	CTR_H
			ADC	#0
			STA	CTR_H
			LDA	CTR_B
			ADC	#0
			STA	CTR_B
DUMPITNOW	
			LDA	CTR_L			; Check for done
			ORA	CTR_H
			ORA	CTR_B
			BEQ 	DHEXX1			; We're done
			LDA	BYTECNT
			BNE	DUMPITN1		; 
DHEXC6		
			JSR	CRLF
			LDA	PTR_B
			STA	HEXIO_B
			LDA	PTR_H
			STA	HEXIO_H
			LDA	PTR_L
			STA	HEXIO_L
			JSR	PUTHEX24		; Print the address
			LDA	#':'
			JSR	PUTCHAR
			LDA	#SP
			JSR	PUTCHAR			;
			LDA	#SP
			JSR	PUTCHAR
DUMPITN1	
			LDA	[PTR]			; Dump CTR bytes starting at [PTR]
			JSR	PUTHEXA
			LDA	#' '
			JSR	PUTCHAR
			JSR	INC_SA24		; Next source address
DHEXC3		
			JSR	DEC_CTR24
			INC BYTECNT
			LDA	BYTECNT
			CMP	#16
			BNE	DUMPITNOW
			STZ	BYTECNT
			BRA	DUMPITNOW		; Print the address at start of new line
			; Print the bufstart for parameter and length for debug or comment out
DHEXX1		
			RTS

; "W 00:1234 01 02 03 04"
; "W 001234 AA BB CC DD"
; "W 1234 01"
; "W 20 00 01 02 03"
; "W 0020 00 01 02 03"
CMD_WRITEBYTES
			JSR	CRLF			; Give some space
			JSR	FINDSTART		; Skip over whitespace.  On return CB_RDPTR, PRM_SA hold start of first/next parameter
			LDA	EOLFLAG			; OR if we hit EOL, then there's no command byte on the line and we have nothing to process
			BNE	CWBXX2			; We hit an EOL before an actionable character, so quit
			JSR	FINDEND			; Get the next parameter's start address in PRM_SA and length in PRM_SIZ
			JSR	CONVHEX			; Get starting address in HEXIO
			LDA	HEXIO_B			; Transfer starting address from HEXIO to PTR
			STA	PTR_B
			LDA	HEXIO_H
			STA	PTR_H
			LDA	HEXIO_L
			STA	PTR_L			
CWLOOP1		
			JSR	FINDSTART		; Get next byte
			LDA	EOLFLAG
			BNE	CWBXX2
			JSR	FINDEND			; Find end of Parameter
			JSR	RDHEX8
			STA	[PTR]			; Attempt to store.  If ROM, output will show failure to write
			; Debug start
			LDA	PTR_B
			STA	HEXIO_B
			LDA	PTR_H
			STA	HEXIO_H
			LDA	PTR_L
			STA	HEXIO_L
			JSR	PUTHEX24
			LDA	#'<'
			JSR	PUTCHAR
			LDA	#'-'
			JSR	PUTCHAR
			LDA	[PTR]			; Read the actual byte (if ROM, won't match input)
			JSR	PUTHEXA
			JSR	CRLF
			; Increment PTR
			CLC	
			LDA	PTR_L
			ADC	#1
			STA	PTR_L
			LDA	PTR_H
			ADC	#0
			STA	PTR_H
			LDA	PTR_B
			ADC	#0
			STA	PTR_B			
			BRA	CWLOOP1
CWBXX2		
			RTS		
			
CMD_LOAD	
			LDY	#MSG_LOAD
			JSR	PUT_STR	
			JSR	SREC_LOADER
			RTS

CMD_GO		
			JSR	CRLF			; Give some space
			JSR	FINDSTART		; Skip over whitespace.  On return CB_RDPTR, PRM_SA hold start of first/next parameter
			LDA	EOLFLAG			; OR if we hit EOL, then there's no command byte on the line and we have nothing to process
			BNE	CGXIT1			; We hit an EOL before an actionable character, so quit
			JSR	FINDEND			; Get the next parameter's start address in PRM_SA and length in PRM_SIZ
			JSR	CONVHEX			; Get starting address in HEXIO
			LDA	HEXIO_B			; Transfer starting address from HEXIO to PTR
			STA	PTR_B
			LDA	HEXIO_H
			STA	PTR_H
			LDA	HEXIO_L
			STA	PTR_L	
			LDY	#MSG_JUMP
			JSR	PUT_STR
			JSR	PUTHEX24
			JSR	CRLF			; get rid of return address since we're not returing!
			JML	[PTR]			; There's really no exit
CGXIT1		
			RTS						; Might return if no valid jump address


			
LOLWUT		
			JSR	CRLF
			LDY	#CMDBUF
			JSR	PUT_STR_CTRL		; Display buffer contents not understood; show non-printing too!
			JSR	CRLF
			LDA	#'?'
			JSR	PUTCHAR
CRLF		
			LDA	#LF
			JSR	PUTCHAR
JUSTCR		
			LDA	#CR
			JSR	PUTCHAR
			RTS

; FIXME: implement commands here		
CMD_UNIMPLEMENTED					
			LDY	#MSG_UNIMPLEMENTED
			JSR	PUT_STR
			RTS		
					

PUTCHARDOT		
			CMP	#SP
			BCS	PCDPRINT
			LDA	#'.'
PCDPRINT		
			JSR	PUTCHAR
			RTS
			

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
SYNC	
			JSR	GETCHAR			; Wait for "S" to start a new record
			CMP	#'S'
			BNE	SYNC
			LDA	#'@'
			JSR	PUTCHAR
			; Optimistically assume start of record.
			JSR	GETCHAR
			STA	REC_TYPE										
			JSR	GETHEX			; Get message length byte
			STA	DATA_CNT		; Save number of bytes in record
			LDA	REC_TYPE		; Decode and dispatch	
			BEQ	GETREMS			; read the comment block
			CMP	#'1'
			BEQ	GET16ADDR
			CMP	#'2'
			BEQ	GET24ADDR
			CMP	#'5'
			BNE	SLC4
			BRA	CNT16
SLC4	
			CMP	#'6'
			BNE	SLC2
			BRA	CNT24
SLC2	
			CMP	#'8'
			BNE	SLC1
			BRL	SA24			; Too far for relative branch
SLC1	
			CMP	#'9'
			BNE	SLC3
			BRA	SA16
			; We'll ignore everything else, including the HDR record
SLC3	
			BRA	SYNC

GETREMS	
			LDA	#'0'
			JSR	PUTCHAR
			LDA	#'#'
			JSR	PUTCHAR
			BRA	SYNC
GET24ADDR
			LDA	#'2'
			JSR	PUTCHAR
			LDA	DATA_CNT	
			SEC		
			SBC	#4			; Data length -= 3 bytes address + 1 byte checksum 
			STA	DATA_CNT		; Adjust data count to include only payload data bytes
			JSR	GETHEX
			STA	PTR_B
			BRA	GET1624
GET16ADDR
			LDA	#'1'
			JSR	PUTCHAR
			LDA	DATA_CNT	
			SEC		
			SBC	#3			; Data length -= 2 bytes address + 1 byte checksum 
			STA	DATA_CNT		; Adjust data count to include only payload data bytes
			STZ	PTR_B			; 16 bit records.  Default Bank to 0!  (0+! NOT 0!=1)
GET1624	
			JSR	GETHEX			; Got bank value (or set to 0). Now get high and low address
			STA	PTR_H
			JSR	GETHEX
			STA	PTR_L

; Now check to see if any bytes remain to be written 
SAVDAT:	
			LDA	DATA_CNT		; A record can have 0 data bytes, theoretically. So check at top
			BEQ	SAVDX1			; No more data to PARSELINE
SAVDAT2	
			JSR	GETHEX
			STA	[PTR]			; 24 bit indirect save
			JSR	INC_PTR			; Point to next byte
			DEC	DATA_CNT
			BNE	SAVDAT2
SAVDX1	
			LDA	#'#'
			JSR	PUTCHAR
			BRL	SYNC			; FIXME: parse the checksum and end of line
		
; S5, S6 records - record 24 bit value in CTR_B, CTR_H, CTR_L	
CNT16	
			LDA	#'5'
			JSR	PUTCHAR
			STZ	CTR_B
			BRA	CN16C1
CNT24:	
			LDA	#'6'
			JSR	PUTCHAR
			JSR	GETHEX
			STA	CTR_B
CN16C1	
			JSR	GETHEX			; bits 15-8
			STA	CTR_H
			JSR	GETHEX			; bits 7-0
			STA	CTR_L
			LDA	#'#'
			JSR	PUTCHAR
			BRL	SYNC			; FIXME: parse the rest of the record & end of line

; S8 or S9 record will terminate the loading, so it MUST be last (and typically is)
SA16	
			LDA	#'9'
			JSR	PUTCHAR
			STZ	SA_B
			BRA	SA16C1
SA24	
			LDA	#'8'
			JSR	PUTCHAR
			JSR	GETHEX			; length byte
			STZ	SA_B
SA16C1	
			JSR	GETHEX			; bits 15-8
			STA	SA_H
			JSR	GETHEX			; bits 7-0
			STA	SA_L
			LDA	#'&'
			JSR	PUTCHAR
GOEOL	
			JSR	GETCHAR
			CMP	#CR
			BNE	GOEOL
			RTS

; 24 bit binary pointer increment.  We're in 8 bit accumulator mode, so it's 3 bytes.
INC_PTR
			INC	PTR_L			; point to the next byte to save to
			BNE	INCPX1	
			INC	PTR_H	
			BNE	INCPX1
			INC	PTR_B
INCPX1	
			RTS

; Convert bytes at CB_RDPTR and CB_RDPTR+1 and convert to hex into A
; Note: this advance parameter pointer!
RDHEX8	
			PHY
			LDY	PRM_SA			; Start at beginning of current parameter
RDHX8L1	
			LDA	0,Y			; Get MSB from *(parameter)
			INY				; advance to (hopefully) ASCII LSB
			CMP	#':'			; Kludgey special handling for ':'
			BEQ	RDHX8L1
RDHX8C1	
			JSR	MKNIBL	
			ASL	A			; Note: MKNIBL ANDs off higher 4 bits, so no '1' sign extension can occur
			ASL	A 
			ASL	A 
			ASL	A			; shift left 4 because upper nibble
			STA	HEXASSY			; temporary storage.  Only used within this function. Can re-use in any foreground context.
RDHX8L2	
			LDA	0,Y			; Get LSB *(parameter+1)
			INY				; point to next ASCII hex byte (if any)
			CMP	#':'
			BEQ	RDHX8L2			; Anti-metamucel (ignore colons) Note pathological buffer with all ':' is possible.  We will tolerate. 
			STY	PRM_SA			;	"
			JSR	MKNIBL
			ORA	HEXASSY			; Assemble the parts
			PLY
			RTS				; return the byte in A
		
			
; Look at CMDBUF for PRM_SIZE bytes starting at CMD_RDPTR and attempt to create 8-24 bit hex in HEXIO binary buffer
; On exit, none of the pointers are changed.  Let higher level functions do this
CONVHEX	
			STZ	HEXIO_B			; Only write bytes explicitly set in buffer parameter string, else 0
			STZ	HEXIO_H
			STZ	HEXIO_L
			LDA	PRM_SIZ			; 24 bit cases are "00:1234" or "001234", 16 bit is "1234", 8 bit is "2A"
			CMP	#2			; See if not even 8 bits (must be two digits to qualify as a hex value by fiat)
			BCC	CVHKWIT			; Too short to be a valid hex parameter.  Must be 2 or more characters 
			CMP	#3
			BCS	CHXCHK16
			; Interpret as 8 bits
			JSR	RDHEX8
			STA	HEXIO_L
			BRA	CVHKWIT
CHXCHK16	
			CMP	#5
			BCS	CHXCHK24
			; Interpret as 16 bit value
			JSR	RDHEX8
			STA	HEXIO_H
			JSR	RDHEX8
			STA	HEXIO_L
			BRA	CVHKWIT
CHXCHK24
			CMP	#8
			BCS	CVHKWIT			; Give up if >= 8 characters!
			; 6 digit value
			JSR	RDHEX8
			STA	HEXIO_B
			JSR	RDHEX8
			STA	HEXIO_H
			JSR	RDHEX8
			STA	HEXIO_L
CVHKWIT	
			RTS	

; Basic conversions	
GETHEX  
			JSR GETCHAR
			CMP	#CTRL_C
			BNE	GHECC1
			LDA	#'^'
			JSR	PUTCHAR
			LDA	#'C'
			JSR	PUTCHAR
       		RTS				; bail
GHECC1	
			JSR	MKNIBL  		; Convert to 0..F numeric
			ASL A
			ASL A
			ASL A
			ASL A       		; This is the upper nibble
			AND #$F0
			STA SUBTEMP
			JSR GETCHAR
			CMP	#CTRL_C
			BNE	GHECC2
			LDA	#'^'
			JSR	PUTCHAR
			LDA	#'C'
			JSR	PUTCHAR
			RTS	
GHECC2	
			JSR MKNIBL
        	ORA SUBTEMP
        	RTS
;----------------    

; Print 8 to 24 bit values in HEXIO_B, HEXIO_H, HEXIO_L buffer as this is very commonly needed
PUTHEX24:	
			LDA	HEXIO_B
			JSR	PUTHEXA
			LDA	#':'
			JSR	PUTCHAR
PUTHEX16:	
			LDA	HEXIO_H
			JSR	PUTHEXA
PUTHEX8:	
			LDA	HEXIO_L
			JSR	PUTHEXA
			RTS
	
PUTHEXA  	
			PHA             	;
        	LSR A
        	LSR A
			LSR A
			LSR A
        	JSR PRNIBL	
        	PLA
PRNIBL  	
			AND     #$0F    	; strip off the low nibble
			CMP     #$0A
			BCC  	NOTHEX  	; if it's 0-9, add '0' else also add 7
			ADC     #6      	; Add 7 (6+carry=1), result will be carry clear
NOTHEX  	
			ADC     #'0'    	; If carry clear, we're 0-9
; Write the character in A as ASCII:
PUTCH		
			JSR	PUTCHAR
			RTS


; Convert the ASCII nibble to numeric value from 0-F:
MKNIBL  	
			CMP     #'9'+1  	; See if it's 0-9 or 'A'..'F' (no lowercase yet)	
			BCC     MKNNH   	; If we borrowed, we lost the carry so 0..9
			SBC     #7+1    	; Subtract off extra 7 (sbc subtracts off one less)
        	; If we fall through, carry is set unlike direct entry at MKNNH
MKNNH   	
			SBC     #'0'-1  	; subtract off '0' (if carry clear coming in)
        	AND     #$0F    	; no upper nibble no matter what
        	RTS             	; and return the nibble

* = $F000
MONTBL		
			.word 	CMD_UNIMPLEMENTED		; Index 0 = "A"
			.word	CMD_UNIMPLEMENTED
			.word	CMD_UNIMPLEMENTED
			.word	CMD_UNIMPLEMENTED
			.word	CMD_UNIMPLEMENTED
			.word	CMD_UNIMPLEMENTED
			.word	CMD_GO
			.word	CMD_UNIMPLEMENTED
			.word	CMD_UNIMPLEMENTED
			.word	CMD_GO
			.word	CMD_UNIMPLEMENTED
			.word	CMD_LOAD
			.word	CMD_UNIMPLEMENTED
			.word	CMD_UNIMPLEMENTED
			.word	CMD_UNIMPLEMENTED
			.word	CMD_UNIMPLEMENTED
			.word	CMD_UNIMPLEMENTED
			.word	CMD_DUMPHEX
			.word	CMD_UNIMPLEMENTED
			.word	CMD_UNIMPLEMENTED
			.word	CMD_UNIMPLEMENTED
			.word	CMD_UNIMPLEMENTED
			.word	CMD_WRITEBYTES
			.word	CMD_UNIMPLEMENTED
			.word	CMD_UNIMPLEMENTED
			.word	CMD_UNIMPLEMENTED				

MSG_UNIMPLEMENTED
			.text	CR,"Unimplemented instruction",CR
			.text	0

	
MSG_6HEX	
			.text	CR,"Enter 6 digit hex address:",0
	
MSG_CONFIRM
			.text	CR,"Is this correct (Y/x)?:",0

QBFMSG	
			.text 		CR,LF,CR,LF
			.text	"                 LOLmon v0.1",CR,LF
			.text 	"          ******************************",CR,LF
			.text 	"          *    The Quick brown Dog     *",CR,LF
			.text 	"          *  Jumps over the Lazy Fox!  *",CR,LF
			.text 	"          ******************************",CR,LF

PROMPT	
			.text	CR,LF
			.text	"        _,-=._              /|_/|",CR,LF
			.text	"       *-.}   `=._,.-=-._.,  @ @.>",CR,LF
			.text   "          `._ _,-.   )      _,.-'",CR,LF
			.text   "             `    V.v-'^V''v",CR,CR,LF
			.text	0
	
ANYKEY	
			.text	CR,LF,CR,LF
			.text 	"Press the ANY key (CTRL-C) to return to monitor",CR
			.text   "else continue foxing:"
			.text	0

MSG_LOAD
			.text 	CR,"SEND S19 or S28 S-RECORD file:",CR,LF
			.text 	0
	
MSG_JUMP
			.text 	CR,"Jumping to address: $"
			.text 	0
	
* = $FFE4
NCOP	
		.word	START		; COP exception in native mode
* = $FFE6
NBRK	
		.word	START		; BRK in native mode
* = $FFE8
NABORT	
		.word	START
* = $FFEA
NNMI	
		.word	START		; NMI interrupt in native mode
* = $FFEE
NIRQ	
		.word	START 

* = $FFF4
ECOP	
		.word	START		; COP exception in 65c02 emulation mode
* = $FFF8
EABORT	
		.word	START
* = $FFFA
ENMI		
		.word	START		; NMI interrupt in 65c02 emulation mode
* = $FFFC
ERESET	
		.word	START		; RESET exception in all modes
* = $FFFE
EIRQ	
		.word	START 

.end					; finally.  das Ende.  Fini.  It's over.  Go home!

