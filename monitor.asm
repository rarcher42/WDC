
; Assembled with 64TASS
; 		64tass -c bootloader.asm -L bootloader.lst
; 

.INCLUDE	"via_symbols.inc"
.INCLUDE	"acia_symbols.inc"

; Monitor hooks
RAW_GETC	=	$E036
RAW_PUTC	= 	$E04B

CTRL_C	= $03
BS		= $08
LF		= $0A
CR		= $0D
SP		= $20
DEL     = $7F

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


; Put the above equates into an included file per peripheral or board

        .cpu    "65816"
        .as     			; A=8 bits
        .xl     			; X, Y = 16 bits

; Direct page fun
TERMFLAGS = $43
RDRDY	= $01				; 1 = character waiting
XONXOFF = $04				; 0 = hardware handshake 1= XON/XOFF
ECHOOFF = $20

*=$E0

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
DEBUG		.byte 	?


* = $0400			; Command buffer area
CMDBUF 		.fill	256		; can be smaller than 256 but must not cross 8 bit page boundary
							; because we use 8 bit math to determine stuff and nobody will
							; want to type a command longer than 256 characters in any case
CB_W_IX		.word	?		; CMD buffer write index (sometimes in X)
CB_R_IY		.word	?		; CMD buffer read index (AEIOU sometimes Y)
; For GETHEX, first 8-24 bit hex value (leading zeroes to make it 24 bits regardless)
HEXVAL1L	.byte	?
HEXVAL1H	.byte	?
HEXVAL1B	.byte	?
HEXVAL1		=	HEXVAL1L	; 24 bit HEXVAL1
; For GETHEX, 2nd 8-24 bit hex value (leading zeroes to make it 24 bits regardless)
HEXVAL2L	.byte	?
HEXVAL2H	.byte	?
HEXVAL2B	.byte	?
HEXVAL2		=	HEXVAL2L	; 24 bit HEXVAL2
; For GETHEX, 3rd 8-24 bit hex value (leading zeroes to make it 24 bits regardless)
HEXVAL3L	.byte	?
HEXVAL3H	.byte	?
HEXVAL3B	.byte	?
HEXVAL3		=	HEXVAL3L	; 24 bit HEXVAL3

 

STACKTOP	=	$7EFF	; Top of RAM = $07EFF (I/O is $7F00-$7FFF)
* = $2000		
START 		LDY		#QBFMSG				; Start of monitor loop
			JSL		PUT_STR
MONPROMPT	JSL		GETLINE
			JSL		PROCESS_LINE
			BRA		MONPROMPT			; End of monitor loop
	
; Look in the CMDBUF and dispatch to appropriate command. 	
PROCESS_LINE
			LDA		#0
			XBA						; Make sure B=0
			LDA		CMDBUF			; FIXME: allow for leading spaces instead of error message
			CMP		#'A'
			BCC		PLERRXIT		; < 'A', so not a command
			CMP		#'Z'+1
			BCS		PLERRXIT		; > 'Z', so not a command
			; Convert 'A'-'Z' to 0 to 25 for subroutine call table 
			SBC		#'A'-1			; Carry clear, so subtract one less to account for borrow
			ASL		A				; Two bytes per JSR table entry			
			TAX						; index = offset into table (65C816 B=0 A=offset)
			JSR		(MONTBL,X)		; No JSL indirect indexed.  Each table entry MUST end in RTS not RTL!
			BRA		PLIX2
PLERRXIT:	JSL		CRLF
			LDA		#'?'
			JSL		PUTCHAR
			LDY		#CMDBUF
			JSL		PUT_STR_CTRL	; Display buffer contents not understood
			JSL		CRLF
PLIX2		RTL

;--- Get command line.  Imperfect editor, due to no raw get character capability in W265 monitor.  Silly, inflexible omission.
; Never omit a raw layer of I/O, ever.  Basic design error locking user into behaviors they don't need.
GETLINE		JSL		CRLF
			LDA		#'>'
			JSL		PUTCHAR
			JSL		CLRCMD
GLLP1		JSL		GETCHAR				; Do not echo
			CMP		#CR
			BNE		GLNC0
			JSL		PUTCHAR
			BRA		GLXIT1				; end of message
GLNC0		CMP		#CTRL_C
			BNE		GLNC1
			; CTRL-C handler
			LDA		#'^'
			JSL		PUTCHAR
			LDA		#'C'
			JSL		PUTCHAR
			LDA		#CR
			JSL		PUTCHAR
			JSL		CLRCMD				; zotch out any command in buffer
			BRA		GLXIT1
			; CTRL-C
GLNC1		CMP		#LF
			BNE		GLNC2
			; LF handler
			BRA		GLLP1
			; LF
GLNC2		CMP		#BS					; We will not tolerate BS here
			BNE		GLNC9
			CMP		#DEL	
			BNE		GLNC9
			; Handle backspace
			STZ		CMDBUF,X
			CPX		#0
			BEQ		GLLP1				; Already backed over the first character. No index to decrement
			JSL		PUTCHAR
			DEX							; change buffer pointer
			STX		CB_W_IX
			STZ		CMDBUF,X			; Character we backed over is now end of string
			BRA		GLLP1
			; enough of this BS stuff
GLNC9		STA		CMDBUF,X					; store it
			JSL		PUTCHAR
			INC		CB_W_IX
			INX
			BRA		GLLP1
GLXIT1		STZ		CMDBUF,X				; null-terminate the line
			RTL
			
TOPUPPER	CMP		#'a'				; Make character PupperCase
			BCC		PUPX1				; A < 'a' so can't be lowercase char
			CMP		#'z'+1				
			BCS		PUPX1				; A > 'z', so can't be lowercase char	
			; Note - carry is clear so we subtract one less
			SBC		#'a'-'A'-1			; Adjust upper case to lower case		
PUPX1		RTL		

CRLF		LDA		#CR
			JSL		PUTCHAR
			LDA		#LF
			JSL		PUTCHAR
			RTL
	

			
CMD_A		LDA		#'A'
			JSL		PUTCHAR
			LDA		#'!'
			JSL		PUTCHAR
			JSL		CRLF
			RTS
			
CMD_B		LDA		#'B'
			JSL		PUTCHAR
			LDA		#'!'
			JSL		PUTCHAR
			JSL		CRLF
			RTS
			
CMD_C		LDA		#'C'
			JSL		PUTCHAR
			LDA		#'!'
			JSL		PUTCHAR
			JSL		CRLF
			RTS
			
CMD_D		LDA		#'D'
			JSL		PUTCHAR
			LDA		#'!'
			JSL		PUTCHAR
			JSL		CRLF
			RTS
			
CMD_E		LDA		#'E'
			JSL		PUTCHAR
			LDA		#'!'
			JSL		PUTCHAR
			JSL		CRLF
			RTS
			
CMD_F		LDA		#'F'
			JSL		PUTCHAR
			LDA		#'!'
			JSL		PUTCHAR
			JSL		CRLF
			RTS

CMD_G		LDA		#'G'
			JSL		PUTCHAR
			LDA		#'!'
			JSL		PUTCHAR
			JSL		CRLF
			RTS
			
CMD_H		LDA		#'H'
			JSL		PUTCHAR
			LDA		#'!'
			JSL		PUTCHAR
			JSL		CRLF
			RTS
			
CMD_I		LDA		#'I'
			JSL		PUTCHAR
			LDA		#'!'
			JSL		PUTCHAR
			JSL		CRLF
			RTS
CMD_J		LDA		#'J'
			JSL		PUTCHAR
			LDA		#'!'
			JSL		PUTCHAR
			JSL		CRLF
			RTS
			
CMD_K		LDA		#'K'
			JSL		PUTCHAR
			LDA		#'!'
			JSL		PUTCHAR
			JSL		CRLF
			RTS
			
CMD_L		LDA		#'L'
			JSL		PUTCHAR
			LDA		#'!'
			JSL		PUTCHAR
			JSL		CRLF
			RTS
CMD_M		LDA		#'M'
			JSL		PUTCHAR
			LDA		#'!'
			JSL		PUTCHAR
			JSL		CRLF
			RTS
			
CMD_N		LDA		#'N'
			JSL		PUTCHAR
			LDA		#'!'
			JSL		PUTCHAR
			JSL		CRLF
			RTS
			
CMD_O		LDA		#'O'
			JSL		PUTCHAR
			LDA		#'!'
			JSL		PUTCHAR
			JSL		CRLF
			RTS
CMD_P		LDA		#'P'
			JSL		PUTCHAR
			LDA		#'!'
			JSL		PUTCHAR
			JSL		CRLF
			RTS
			
CMD_Q		LDA		#'Q'
			JSL		PUTCHAR
			LDA		#'!'
			JSL		PUTCHAR
			JSL		CRLF
			RTS
			
CMD_R		LDA		#'R'
			JSL		PUTCHAR
			LDA		#'!'
			JSL		PUTCHAR
			JSL		CRLF
			RTS
CMD_S		LDA		#'S'
			JSL		PUTCHAR
			LDA		#'!'
			JSL		PUTCHAR
			JSL		CRLF
			RTS
			
CMD_T		LDA		#'T'
			JSL		PUTCHAR
			LDA		#'!'
			JSL		PUTCHAR
			JSL		CRLF
			RTS
			
CMD_U		LDA		#'U'
			JSL		PUTCHAR
			LDA		#'!'
			JSL		PUTCHAR
			JSL		CRLF
			RTS
CMD_V		LDA		#'V'
			JSL		PUTCHAR
			LDA		#'!'
			JSL		PUTCHAR
			JSL		CRLF
			RTS
			
CMD_W		LDA		#'W'
			JSL		PUTCHAR
			LDA		#'!'
			JSL		PUTCHAR
			JSL		CRLF
			RTS
			
CMD_X		LDA		#'X'
			JSL		PUTCHAR
			LDA		#'!'
			JSL		PUTCHAR
			JSL		CRLF
			RTS

CMD_Y		LDA		#'Y'
			JSL		PUTCHAR
			LDA		#'!'
			JSL		PUTCHAR
			JSL		CRLF
			RTS
			
CMD_Z		LDA		#'Z'
			JSL		PUTCHAR
			LDA		#'!'
			JSL		PUTCHAR
			JSL		CRLF
			RTS		
				
			
RUNSPOTRUN	LDA		#CR
			JSL		PUTCHAR
			LDY		#MSG_6HEX
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
			JSL		PUTHEX
			LDA		#':'
			JSL		PUTCHAR
			LDA		SA_H
			JSL		PUTHEX
			LDA		SA_L
			JSL		PUTHEX
			LDA		#CR
			JSL		PUTCHAR
			LDY		#MSG_CONFIRM
			JSL		PUT_STR
			JSL		GETCHAR
			JSL		PUTCHAR
			CMP		#'Y'
			BNE		RUNSPOTRUN
			JML		[SA_B]
	
							
; Test code for balky (possibly decoder issue!) SX816 board
ECHO		JSL		GETCHF
			BRA		ECHO
BLABBER		JSL		TXCHDLY
			LDA		#'*'
			STA		SDR
			JSL		PUTCHF
			BRA		BLABBER
	
; MUST JSL not JSR here	
PUTCHARTR	CMP		#$20
			BCS		PUT_RAW
			PHA					; Display as hex value
			LDA		#'\'
			JSL		PUT_RAW
			PLA
			JSL		PUTHEX
PUTCRX1		RTL
			
PUTCHAR		
PUT_RAW		JSL		RAW_PUTC
			RTL

PUT_STR		LDA		0,Y				; Y points directly to string
			BEQ		PUTSX
			JSL		PUT_RAW
			INY						; point to next character
			BRA		PUT_STR		
PUTSX		RTL	

; Show control characters as printable
PUT_STR_CTRL 
			LDA		0,Y				; Y points directly to string
			BEQ		PUTSRX
			JSL		PUTCHARTR		; Show control characters, etc.
			INY						; point to next character
			BRA		PUT_STR_CTRL
PUTSRX		RTL	

GET_RAW		JSL		RAW_GETC
GRXIT1		RTL

			
GETCHAR	    LDA		TERMFLAGS		; relying on W265 SBC char in buffer (temporarily) 
			AND		#%11011111		; Turn off ECHO
			ORA		#%00010000		; Turn off hardware handshaking to 265 (not run)
			STA 	TERMFLAGS
			JSL		GET_RAW
			JSL		TOPUPPER		; Make alphabetics Puppercase
			RTL

CLRCMD		LDX		#0
			STX		CB_W_IX
			STZ		CMDBUF		; Null terminate the empty buffer
			RTL
			
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
SYNC	JSL		GETCHAR				; Wait for "S" to start a new record
		CMP		#'S'
		BNE		SYNC
		LDA		#'@'
		JSL		PUTCHAR
		; Optimistically assume start of record.
		JSL		GETCHAR
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

GETREMS	LDA		#'0'
		JSL		PUTCHAR
		LDA		#'#'
		JSL		PUTCHAR
		JML		SYNC
GET24ADDR
		LDA		#'2'
		JSL		PUTCHAR
		LDA		DATA_CNT	
		SEC		
		SBC		#4			; Data length -= 3 bytes address + 1 byte checksum 
		STA		DATA_CNT	; Adjust data count to include only payload data bytes
		JSL		GETHEX
		STA		PTR_B
		BRA		GET1624
GET16ADDR
		LDA		#'1'
		JSL		PUTCHAR
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
		JSL		PUTCHAR
		JML		SYNC		; FIXME: parse the checksum and end of line
		
; S5, S6 records - record 24 bit value in CTR_B, CTR_H, CTR_L	
CNT16	LDA		#'5'
		JSL		PUTCHAR
		STZ		CTR_B
		BRA		CN16C1
CNT24:	LDA		#'6'
		JSL		PUTCHAR
		JSL		GETHEX
		STA		CTR_B
CN16C1	JSL		GETHEX		; bits 15-8
		STA		CTR_H
		JSL		GETHEX		; bits 7-0
		STA		CTR_L
		LDA		#'#'
		JSL		PUTCHAR
		JML		SYNC		; FIXME: parse the rest of the record & end of line

; S8 or S9 record will terminate the loading, so it MUST be last (and typically is)
SA16	LDA		#'9'
		JSL		PUTCHAR
		STZ		SA_B
		BRA		SA16C1
SA24	LDA		#'8'
		JSL		PUTCHAR
		JSL		GETHEX		; length byte
		STZ		SA_B
SA16C1	JSL		GETHEX		; bits 15-8
		STA		SA_H
		JSL		GETHEX		; bits 7-0
		STA		SA_L
		LDA		#'&'
		JSL		PUTCHAR
GOEOL	JSL		GETCHAR
		CMP		#CR
		BNE		GOEOL
		JML		MONPROMPT

; 24 bit binary pointer increment.  We're in 8 bit accumulator mode, so it's 3 bytes.
INC_PTR	INC		PTR_L		; point to the next byte to save to
		BNE		INCPX1	
		INC		PTR_H	
		BNE		INCPX1
		INC		PTR_B
INCPX1	RTL

; Basic conversions	
GETHEX  JSL 	GETCHAR
		CMP		#CTRL_C
		BNE		GHECC1
		LDA		#'^'
		JSL		PUTCHAR
		LDA		#'C'
		JSL		PUTCHAR
        JML		MONPROMPT
GHECC1	JSL     MKNIBL  	; Convert to 0..F numeric
        ASL     A
        ASL     A
        ASL     A
        ASL     A       	; This is the upper nibble
        AND     #$F0
        STA     SUBTEMP
        JSL     GETCHAR
		CMP		#CTRL_C
		BNE		GHECC2
		LDA		#'^'
		JSL		PUTCHAR
		LDA		#'C'
		JSL		PUTCHAR
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
	
; NOTE:  DO NOT CALL THIS if you're not powering via micro USB as the FIFO chip will never get power and become ready!	
INIT_FIFO
		LDA		#$FF
		STA     SYSTEM_VIA_PCR			; CB2=FAMS=flash A16=1;  CA2=FA15=A15=1; Select flash Bank #3
		STZ 	SYSTEM_VIA_ACR			; Disable PB7, shift register, timer T1 interrupt.  Not absolutely required while interrupts are disabled FIXME: set up timer
		STZ		SYSTEM_VIA_DDRA			; Set PA0-PA7 to all inputs
		STZ		SYSTEM_VIA_DDRB			; In case we're not coming off a reset, make PORT B an input and change output register when it's NOT outputting
		LDA		#FIFO_RD				;
		STA		SYSTEM_VIA_IORB			; Avoid possible glitch by writing to output latch while Port B is still an input (after reset)
		LDA		#(FIFO_RD + FIFO_WR + FIFO_DEBUG)	; Make FIFO RD & WR pins outputs so we can strobe data in and out of the FIFO
		STA		SYSTEM_VIA_DDRB			; Port B: PB2 and PB3 are outputs; rest are inputs from earlier IORB write
		; Defensively wait for ports to settle 
		RTL								; FUBAR - don't wait on the FIFO which stupidly may not even have power if not USB powered
FIFOPWR	NOP								; FIXME: Defensive and possibly unnecessary
		; FIXME: Add timeout here
		LDA		SYSTEM_VIA_IORB
		AND		#FIFO_PWREN				; PB5 = PWRENB. 0=enabled 1=disabled
		BNE		FIFOPWR	
		RTL

		
PUTCHF	STA		TEMP2
		LDA		SYSTEM_VIA_IORB			; Read in FIFO status Port for FIFO
		AND		#FIFO_TXE				; If TXE is low, we can accept data into FIFO.  If high, return immmediately
		SEC								; FIFO is full, so don't try to queue it!	
		BNE		OFX1					; 0 = OK to write to FIFO; 1 = Wait, FIFO full!
		; FIFO has room - write A to FIFO in a series of steps
OFCONT	STZ		SYSTEM_VIA_DDRA			; (Defensive) Start with Port A input/floating 
		LDA		#(FIFO_RD + FIFO_WR + FIFO_DEBUG)	; RD=1 WR=1 (WR must go 1->0 for FIFO write)
		STA		SYSTEM_VIA_IORB			; Make sure write is high (and read too!)
		LDA		TEMP2					; Restore the data to send
		STA		SYSTEM_VIA_IORA			; Set up output value in advance in Port A (still input so doesn't go out yet) 
		LDA		#$FF					; make Port A all outputs with stable output value already set in prior lines
		STA		SYSTEM_VIA_DDRA			; Save data to output latches
		NOP								; Some settling time of data output just to be safe
		NOP
		NOP
		NOP
		NOP
		NOP
		; Now the data's stable on PA0-7, pull WR line low (leave RD high)
		LDA		#(FIFO_RD)			; RD=1 WR=0 (WR1->0 transition triggers FIFO transfer!)
		STA		SYSTEM_VIA_IORB		; Low-going WR pulse should latch data
		NOP		; Hold time following write strobe, to ensure value is latched OK
		NOP
		NOP
		NOP
		NOP
		NOP
		STZ		SYSTEM_VIA_DDRA		; Make port A an input again
		CLC				; signal success of write to caller
OFX1	LDA		TEMP2
		RTL
;
;
		
; On exit:
; If Carry flag is clear, A contains the next byte from the FIFO
; If carry flag is set, there were no characters waiting
GETCHF	
		LDA		SYSTEM_VIA_IORB		; Check RXF flag
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
PUTCH		JSL		PUTCHAR
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

; Quick n'dirty assignments instead of proper definitions of each parameter
; "ORed" together to build the desired flexible configuration.  We're going
; to run 9600 baud, no parity, 8 data BITs, 1 stop BIT for monitor.  
;

SCTL_V  = %00011110       ; 9600 baud, 8 bits, 1 stop bit, rxclock = txclock
SCMD_V  = %00001011       ; No parity, no echo, no tx or rx IRQ (for now), DTR*
; Set up baud rate, parity, stop bits, interrupt control, etc. for
; the serial port.
INIT_SER	LDA     #SCTL_V 	; 9600,n,8,1.  rxclock = txclock
			STA 	SCTL		
			LDA     #SCMD_V 	; No parity, no echo, no tx or rx IRQ (for now), DTR*
			STA     SCMD
			RTL


GETSER		LDA		SSR
			AND		#RX_RDY
			BEQ		GETSER
			LDA		SDR
			CLC					; Temporary compatibility return value for blocking/non-blocking
			RTL



PUTSER		PHA
			STA		SDR
			JSL		TXCHDLY		; Awful kludge
			PLA
			CLC					; Temporary compatibility return value for integration for blocking/non-blocking
			RTL
		
MONTBL		.word 		CMD_A			; Index 0 = "A"
			.word		CMD_B
			.word		CMD_C
			.word		CMD_D
			.word		CMD_E
			.word		CMD_F
			.word		CMD_G
			.word		CMD_H
			.word		CMD_I
			.word		CMD_J
			.word		CMD_K
			.word		CMD_L
			.word		CMD_M
			.word		CMD_N
			.word		CMD_O
			.word		CMD_P
			.word		CMD_Q
			.word		CMD_R
			.word		CMD_S
			.word		CMD_T
			.word		CMD_U
			.word		CMD_V
			.word		CMD_W
			.word		CMD_X
			.word		CMD_Y
			.word		CMD_Z
			;			
			
			
MSG_JUMPING:
	.text	CR,"Jumping to address:",0

MSG_LOADER
	.text	CR,"Loader started!",CR
	.text 	0
	
MSG_6HEX	
	.text	CR,"Enter 6 digit hex address:",0
	
MSG_CONFIRM
	.text	CR,"Is this correct (Y/x)?:",0

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
        .text   "             `    G.m-'^m'm'",CR,CR
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