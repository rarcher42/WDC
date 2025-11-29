
; Assembled with 64TASS
; 	64tass -c binmon.asm -L binmon.lst --intel-hex -o binmon.hex; 
; Put the above equates into an included file per peripheral or board

        	.cpu    "65816"

		.INCLUDE "via_symbols.inc"
		
	
BS		= $08
LF		= $0A
CR		= $0D
DLE		= $10
CTRL_P  = DLE
SP		= $20
DEL		= $7F
; Frame format characters
ST_X	= $02
CTRL_B	= ST_X
ETX		= $03
CTRL_C	= ETX
SOF		= ST_X
EOF		= ETX
ESC		= DLE
ACK		= $06
NAK		= $15

MASK0		= %00000001
MASK1		= %00000010
MASK2		= %00000100
MASK3		= %00001000
MASK4		= %00010000
MASK5		= %00100000
MASK6		= %01000000
MASK7		= %10000000

; Flag definition to OR for SEP, REP
N_FLAG		= MASK7
M_FLAG		= MASK6
X_FLAG		= MASK4
D_FLAG		= MASK3
I_FLAG		= MASK2
Z_FLAG		= MASK1
C_FLAG		= MASK0

* 		= $40					; Zero page assignments
CMD_STATE	
		.byte	?				; CMD_PROC state
CMD_ERROR	
		.byte	?				; Flag error 
CMD_IX		
		.word	?				; Nexxt char in CMD_BUF  @ *(CMD_BUF + CMD_IX)

EA_L	.byte	?				; 24 bit read pointer LOW
EA_H	.byte	?				; 	" HIGH
EA_B	.byte	?				; 	" PAGE #
EA_PTR	=	EA_L				; Address of EA_PTR

CNT_L	.byte	?				; Must be 16 bits to transfer 16 bit index register
CNT_H	.byte	?
CNT		= CNT_L

TEMP	.byte	?

SIZE_CMD_BUF	= 512			; maximum command length
*		= $0400					; CMD buffer
CMD_BUF		
		.fill	SIZE_CMD_BUF

STACKTOP	= $7EFF					; Top of RAM (I/O 0x7F00-0x7FFF)

* = $F800
		.xl
		.as
START 		
		SEI
		CLC					; Enter native 65c816 mode
		XCE					; 
		REP	#(X_FLAG | D_FLAG)		; 16 bit index, binary mode
		SEP	#M_FLAG				; 8 bit A (process byte stream) 
		LDX	#STACKTOP			; Set 16bit SP to usable RAMtop
		TXS						; Set up the stack pointer
		JSR	INIT_FIFO			; initialize FIFO
		LDY	#VER_MSG
		JSR	PUTSY
CMD_INIT 	
		JSR	INIT_CMD_PROC			; Prepare processor state machine
CMD_LOOP	
		JSR	CMD_PROC			; Run processor state machine
		BRA	CMD_LOOP			; then do it some more


VER_MSG
		.text	CR,LF
		.text  	"************************"
		.text	"*     BinMon v0.1      *"
		.text	"*     Ross Archer      *"
		.text	"* In the Public Domain *"
		.text	"*   27 November 2025   *"
		.text	"************************"
; END main monitor program
QBF_MSG
		.text   CR,LF
		.text   "        _,-=._              /|_/|",CR,LF
		.text   "       *-.}   `=._,.-=-._.,  @ @.>",CR,LF
		.text   "          `._ _,-.   )      _,.-'",CR,LF
		.text   "             `    V.v-'^V''v",CR,CR,LF
		.text   0
		
CMD_TBL 	
		.word	CMD_STATE_INIT
		.word	CMD_STATE_AWAIT_SOF
		.word 	CMD_STATE_COLLECT
		.word	CMD_STATE_TRANSLATE
		.word	CMD_STATE_PROCESS
		.word	CMD_STATE_INIT
; Subroutines begin here


INIT_CMD_PROC	
		STZ	CMD_STATE			; Make sure we start in INIT state
		LDX	#0
		STX	CMD_IX				; Must be w/in bounds before INIT state
		RTS

; Run the command processing FSM
CMD_PROC 	
		; Bounds check the command buffer and discard if overflow would occur
		LDX	CMD_IX	
		CPX	#SIZE_CMD_BUF
		BCC	CMD_PC1
		STZ	CMD_STATE			; discard as command can't be valid
CMD_PC1 	
		; Jump to the current state
		LDA	#0
		XBA					; B = 0
		LDA	CMD_STATE		; get state
		ASL	A				; two bytes per entry
		TAX					; 16 bit table offset (B|A)->X
        JMP	(CMD_TBL,X)		; execute the current state
		; No RTS - that happens in each finite state 


; State 0: INIT
CMD_STATE_INIT  
		STZ	CMD_ERROR			; no command error (yet)
		LDX	#0					; start at beginning of CMD_BUF
		STX	CMD_IX				; store 16 bit pointerkk
		LDA	#1
		STA	CMD_STATE
		RTS
		
; State 1: AWAIT_SOF
CMD_STATE_AWAIT_SOF
		JSR	GET_FRAW
		BCC	CMD_AX1				; Nothing waiting
		CMP	#SOF
		BNE	CMD_AX1
		LDA	#2
		STA	CMD_STATE	
CMD_AX1 	
		RTS

; State 2: COLLECT bytes
CMD_STATE_COLLECT
		JSR	GET_FRAW
		BCC	CMD_CX1				; if nothing in FIFO, quit
		CMP	#SOF
		BNE	CMD_CC1
		STZ	CMD_STATE			; SOF means reset FSM
		BRA	CMD_CX1
CMD_CC1		
		CMP	#EOF
		BNE	CMD_CC2
		LDA	#4
		STA	CMD_STATE
		BRA	CMD_CX1
CMD_CC2		
		CMP	#ESC
		BNE	CMD_CC3
		LDA	#3
		STA	CMD_STATE
		BRA	CMD_CX1
CMD_CC3		
		LDX	CMD_IX
		STA	CMD_BUF,X				; Store in CMD_BUF
		INX					; Increment CMD_IX
		STX	CMD_IX
CMD_CX1 	
		RTS

; State 3: TRANSLATE escaped sequences
CMD_STATE_TRANSLATE
		JSR	GET_FRAW
		BCC	CMD_TX1				; If nothing in FIFO, quit
		CMP	#SOF				; Invalid SOF - abort
		BNE	CMD_TC1
		STZ	CMD_STATE			; SOF means reset FSM
		BRA	CMD_TX1 
CMD_TC1		
		CMP	#EOF
		BNE	CMD_TC2
		STZ	CMD_STATE			; Can't have EOF after ESC, quit
		BRA	CMD_TX1
CMD_TC2		
		CMP	#$11				; ESCaped SOF
		BNE	CMD_TC3
		LDA	#SOF
		BRA	CMD_TXLAT
CMD_TC3		
		CMP	#$12
		BNE	CMD_TC4
		LDA	#ESC
		BRA	CMD_TXLAT
CMD_TC4		
		CMP	#$13
		BNE	CMD_TC5
		LDA	#EOF
		BRA	CMD_TXLAT
CMD_TC5		
		LDA	#1
		STA	CMD_ERROR			; Invalid ESC sequence - flag error
		LDA	#0
CMD_TXLAT	
		LDX	CMD_IX
		STA	CMD_BUF,X		; Store in CMD_BUF
		INX					; Increment CMD_IX
		STX	CMD_IX
CMD_TX1 	
		RTS

; State 4: PROCESS the command
CMD_STATE_PROCESS
		STZ	CMD_STATE			; Upon return to FSM loop, we're looking for a new command
		; Parse and dispatch
		LDA	CMD_BUF				; Get the command
		CMP	#1
		BNE	PCBC1
		JMP	RD_CMD
PCBC1	CMP	#2
		BNE	PCBC2
		JMP	WR_CMD
PCBC2	CMP	#3
		BNE	PCBC3
		JMP	GO_CMD
PCBC3	CMP	#'E'				; echo command
		BNE	PCBERR
		JMP	ECHO_CMD
PCBERR	JSR	SEND_NAK			; Unknown cmd
		RTS
; [01][start-address-Low][start-address-high][start-address-page][LEN_L][LEN_H]		; 
; Read n+1 bytes (1 to 256 inclusive) and Return
; X / CMD_IX is index to next byte
RD_CMD	
		LDA	CMD_BUF+1		; Note: this could be more efficient.  Make it work first.
		STA	EA_L
		LDA	CMD_BUF+2
		STA	EA_H
		LDA	CMD_BUF+3
		STA	EA_B
		; Store 8 bit count as 16 bits for indexing
		LDA	CMD_BUF+4
		STA	CNT_L
		LDA	CMD_BUF+5
		STA	CNT_H
		LDA	#SOF
		JSR	PUTCH			; Unencoded SOF starts frame
		LDY	#0
RD_BN1	LDA	[EA_PTR],Y		; Get next byte
		JSR	CHR_ENCODE		; Send the byte there, possibly ESCaped as two bytes
		INY
		CPY	CNT				; Length word
		BNE	RD_BN1
RD_BX1	LDA	#EOF
		JSR	PUTCH			; Unencoded EOF ends frame
		RTS
		
; [02][start-address-Low][start-address-high][start-address-page][b0][b1]...[bn]
; Use CMD_IX to determine last write byte
WR_CMD
		LDA	CMD_BUF+1		; Note: this could be more efficient.  Make it work first.
		STA	EA_L
		LDA	CMD_BUF+2
		STA	EA_H
		LDA	CMD_BUF+3
		STA	EA_B
		; Store 8 bit count as 16 bits for indexing
		LDA	CMD_IX
		STA	CNT_L
		LDA	CMD_IX+1
		STA	CNT_H
		LDX	#4				; Index of first CMD_BUF byte to write
		LDY	#0				; Where to write
WR_BN1	LDA	CMD_BUF,X		; Get the next buffer byte
		STA	[EA_PTR],Y		; Write it out
		INX
		INY
		CPX	CNT
		BNE	WR_BN1
		JSR	SEND_ACK
		RTS
	
; [03][start-address-low][start-address-high][start-address-high]	
GO_CMD	JSR	SEND_ACK
		LDA	CMD_BUF+1		; Note: this could be more efficient.  Make it work first.
		STA	EA_L
		LDA	CMD_BUF+2
		STA	EA_H
		LDA	CMD_BUF+3
		STA	EA_B
		JML [EA_PTR]

ECHO_CMD
		LDA	#SOF
		JSR	PUTCH
		LDX	#0
EC_CM1	LDA	CMD_BUF,X
		JSR	CHR_ENCODE		; Send byte, possibly ESCaping for transmission
		INX
		CPX	CMD_IX
		BNE	EC_CM1
		LDA	#EOF
		JSR	PUTCH
		RTS

NMI_ISR 	
		RTI

IRQ_ISR 	
		RTI

;;;; ============================= New FIFO functions ======================================
; Initializes the system VIA (the USB debugger), and syncs with the USB chip.

FIFO_TXE 	= PB0
FIFO_RXF	= PB1
FIFO_WR 	= PB2
FIFO_RD 	= PB3
FIFO_PWREN 	= PB5
FIFO_DEBUG 	= PB7					; Handy debug toggle 


INIT_FIFO
		LDA	#$FF
		STA 	SYSTEM_VIA_PCR			; CB2=FAMS=flash A16=1;  CA2=FA15=A15=1; Select flash Bank #3
		STZ 	SYSTEM_VIA_ACR			; Disable PB7, shift register, timer T1 interrupt.  Not absolutely required while interrupts are disabled FIXME: set up timer
		STZ	SYSTEM_VIA_DDRA			; Set PA0-PA7 to all inputs
		STZ	SYSTEM_VIA_DDRB			; In case we're not coming off a reset, make PORT B an input and change output register when it's NOT outputting
		LDA	#FIFO_RD				;
		STA	SYSTEM_VIA_IORB			; Avoid possible glitch by writing to output latch while Port B is still an input (after reset)
		LDA	#(FIFO_RD + FIFO_WR)		; Make FIFO RD & WR pins outputs so we can strobe data in and out of the FIFO
		STA	SYSTEM_VIA_DDRB			; Port B: PB2 and PB3 are outputs; rest are inputs from earlier IORB write
		RTS					

		
; On exit:
; If Carry flag is set, A contains the next byte from the FIFO
; If carry flag is clear, no character was received and A doesn't contain anything meaningful
GET_FRAW
		LDA	SYSTEM_VIA_IORB			; Check RXF flag
		AND	#FIFO_RXF				; If clear, we're OK to read.  If set, there's no data waiting
		CLC							; Assume no character (overridden if A != 0)
		BNE 	INFXIT					; If RXF is 1, then no character is waiting!
		STZ	SYSTEM_VIA_DDRA			; Make Port A inputs
		LDA	#FIFO_RD
		STA	SYSTEM_VIA_IORB			; RD=1 WR=0 (RD must go to 0 to read
		NOP
		STZ	SYSTEM_VIA_IORB			; RD=0 WR=0	- FIFO presents data to port A	
		NOP
		LDA	SYSTEM_VIA_IORA			; read data in
		PHA
		LDA	#FIFO_RD				; Restore back to inactive signals RD=1 and WR=0
		STA	SYSTEM_VIA_IORB
		PLA
		SEC							; we got a byte!
INFXIT	
		RTS


	
; Non-blocking Put FIFO.  Return with carry flag set if buffer is full and nothing was output. 
; Return carry clear upon successful queuing.  Save input char so it doesn't need to be reloaded should FIFO be full
PUT_FRAW	
		PHA							; save output character
		LDA	SYSTEM_VIA_IORB			; Read in FIFO status Port for FIFO
		AND	#FIFO_TXE				; If TXE is low, we can accept data into FIFO.  If high, return immmediately
		CLC							; FIFO is full, so don't try to queue it!	Signal failure
		BNE	OFX1					; 0 = OK to write to FIFO; 1 = Wait, FIFO full!
			; FIFO has room - write A to FIFO in a series of steps
OFCONT		
		STZ	SYSTEM_VIA_DDRA			; (Defensive) Start with Port A input/floating 
		LDA	#(FIFO_RD + FIFO_WR)	; RD=1 WR=1 (WR must go 1->0 for FIFO write)
		STA	SYSTEM_VIA_IORB			; Make sure write is high (and read too!)
		PLA							; Restore the data to send
		PHA							; Also save for exit restore
		STA	SYSTEM_VIA_IORA			; Set up output value in advance in Port A (still input so doesn't go out yet) 
		LDA	#$FF					; make Port A all outputs with stable output value already set in prior lines
		STA	SYSTEM_VIA_DDRA			; Save data to output latches
		NOP							; Some settling time of data output just to be safe
		; Now the data's stable on PA0-7, pull WR line low (leave RD high)
		LDA	#(FIFO_RD)				; RD=1 WR=0 (WR1->0 transition triggers FIFO transfer!)
		STA	SYSTEM_VIA_IORB			; Low-going WR pulse should latch data
		NOP							; Hold time following write strobe, to ensure value is latched OK
		STZ	SYSTEM_VIA_DDRA			; Make port A an input again
		SEC							; signal success of write to caller
OFX1		
		PLA							; restore input character, N and Z flags
		RTS
; SEND NAK packet
SEND_NAK
		LDA	#NAK
		STA	TEMP
		BRA	SENDC1
; SEND ACK packet
SEND_ACK
		LDA	#ACK
		STA	TEMP
SENDC1	LDA	#SOF
		JSR	PUTCH
		LDA	TEMP
		JSR	PUTCH
		LDA	#EOF
		BRA	PUTCH

; This subroutine translates SOF ESC and EOF for inside-packet protection of OOB characters.  Enter at PUTCH by itself for untranslated output	
CHR_ENCODE
		CMP	#SOF
		BNE	WENC1
		LDA	#ESC
		JSR	PUTCH
		LDA	#$11
		BRA	PUTCH
WENC1	CMP	#ESC
		BNE	WENC2
		LDA	#ESC
		JSR	PUTCH
		LDA	#$12
		BRA	PUTCH
WENC2	CMP	#EOF
		BNE	PUTCH
		LDA	#ESC
		JSR	PUTCH
		LDA	#$13
PUTCH	; Blocking char output
		JSR	PUT_FRAW
		BCC	PUTCH
		RTS
; Point Y at your NULL-TERMNATED data string
PUTSY 		
		LDA	0,Y
		BEQ	PUTSY1				; Don't print the NULL terminator 
PUTSXL1		
		JSR	PUTCH
		INY						; Prepare to get next character
		BRA	PUTSY
PUTSY1 		
		RTS 
;
;




;;; Exception / Reset / Interrupt vectors in native and emulation mode
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
		.word	NMI_ISR		; NMI interrupt in native mode
* = $FFEE
NIRQ	
		.word	IRQ_ISR 

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

