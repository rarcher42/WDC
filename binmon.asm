
; Assembled with 64TASS
; 	64tass -c binmon.asm -L binmon.lst --intel-hex -o binmon.hex; 
; Put the above equates into an included file per peripheral or board

        	.cpu    "65816"

		.INCLUDE "via_symbols.inc"
   
CTRL_C		= $03
BS		= $08
LF		= $0A
CR		= $0D
SP		= $20
DEL		= $7F
SOF		= $42
EOF		= $00
ESC		= $55

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

* 		= $C0					; Zero page assignments
CMD_STATE	
		.byte	?				; CMD_PROC state
CMD_ERROR	
		.byte	?				; Flag error 
CMD_PTR		
		.word	?				; *(CMD_BUF)

SIZE_CMD_BUF	= 1024					; maximum command length
*		= $0400					; CMD buffer
CMD_BUF		
		.fill	SIZE_CMD_BUF

STACKTOP	= $7EFF					; Top of RAM (I/O 0x7F00-0x7FFF)

* = $F800
START 		
		SEI
		CLC					; Enter native 65c816 mode
		XCE					; 	"
		.xl					; Tell assembler index=16 bits
		REP	#(X_FLAG | D_FLAG)		; 16 bit index, binary mode
		.as					; Tell assembler A=8 bits
		SEP	#M_FLAG				; 8 bit A (process byte stream) 
		LDX	#STACKTOP			; Set 16bit SP to usable RAMtop
		JSR	INIT_FIFO			; initialize FIFO
		LDX	#QBF_MSG
		JSR	PUTSX
CMD_INIT 	
		JSR	INIT_CMD_PROC			; Prepare processor state machine
CMD_LOOP	
		JSR	CMD_PROC			; Run processor state machine
		BRA	CMD_LOOP			; then do it some more

; END main monitor program

; Subroutines begin here


INIT_CMD_PROC	
		STZ	CMD_STATE			; Make sure we start in INIT state
		LDY	#CMD_BUF
		STY	CMD_PTR				; Must be w/in bounds before INIT state
		RTS

; State 0: INIT
CMD_STATE_INIT  
		STZ	CMD_ERROR			; no command error (yet)
		LDY	#CMD_BUF			; start at beginning of CMD_BUF
		STY	CMD_PTR				; store 16 bit pointerkk
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
		LDX	CMD_PTR
		STA	(0,X)				; Store in CMD_BUF
		INX					; Increment CMD_PTR
		STX	CMD_PTR
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
		CMP	#$01				; ESCaped SOF
		BNE	CMD_TC3
		LDA	#SOF
		BRA	CMD_TXLAT
CMD_TC3		
		CMP	#$02
		BNE	CMD_TC4
		LDA	#ESC
		BRA	CMD_TXLAT
CMD_TC4		
		CMP	#$03
		BNE	CMD_TC5
		LDA	#EOF
		BRA	CMD_TXLAT
CMD_TC5		
		LDA	#1
		STA	CMD_ERROR			; Invalid ESC sequence - flag error
		LDA	#0
CMD_TXLAT	
		LDX	CMD_PTR
		STA	(0,X)				; Store in CMD_BUF
		INX					; Increment CMD_PTR
		STX	CMD_PTR
CMD_TX1 	
		RTS

; State 4: PROCESS the command
CMD_STATE_PROCESS
		STZ	CMD_STATE			; Reset FSM 
		JSR	PROCESS_CMD_BUF
		RTS

PROCESS_CMD_BUF
		LDX	#GOT_CMD
		JSR	PUTSX
		RTS

CMD_TBL 	
		.word	CMD_STATE_INIT
		.word	CMD_STATE_AWAIT_SOF
		.word 	CMD_STATE_COLLECT
		.word	CMD_STATE_TRANSLATE
		.word	CMD_STATE_PROCESS
		.word	CMD_STATE_INIT

; Run the command processing FSM
CMD_PROC 	
		; Bounds check the command buffer and discard if overflow would occur
		LDY	CMD_PTR	
		CPY	#(CMD_BUF+SIZE_CMD_BUF)
		BCS	CMD_PC1
		STZ	CMD_STATE			; discard as command can't be valid
CMD_PC1 	
		; Jump to the current state
		LDA	#0
		XBA					; B = 0
		LDA	CMD_STATE			; get state
		ASL	A				; two bytes per entry
		TAX					; 16 bit table offset (B|A)->X
                JMP	(CMD_TBL,X)			; execute the current state
		; No RTS - that happens in each finite state 

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

		
; Non-blocking Put FIFO.  Return with carry flag set if buffer is full and nothing was output. 
; Return carry clear upon successful queuing
PUT_FRAW	
		PHA							; save output character
		LDA	SYSTEM_VIA_IORB			; Read in FIFO status Port for FIFO
		AND	#FIFO_TXE				; If TXE is low, we can accept data into FIFO.  If high, return immmediately
		CLC							; FIFO is full, so don't try to queue it!	Signal failure
		BNE	OFX1					; 0 = OK to write to FIFO; 1 = Wait, FIFO full!
			; FIFO has room - write A to FIFO in a series of steps
OFCONT		STZ	SYSTEM_VIA_DDRA			; (Defensive) Start with Port A input/floating 
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

; Point X at your NULL-TERMNATED data string
PUTSX 		
		LDA	(0,X)
		BEQ	PUTSX1				; Don't print the NULL terminator 
PUTSXL1		
		JSR	PUT_FRAW
		BCC	PUTSXL1				; If FIFO full, let it empty
		INX					; Prepare to get next character
		BRA	PUTSX
PUTSX1 		
		RTS 
;
;

GOT_CMD
		.text	CR,LF
		.text	"Got a command!",CR,LF
		.text	0
QBF_MSG
		.text   CR,LF
		.text   "        _,-=._              /|_/|",CR,LF
		.text   "       *-.}   `=._,.-=-._.,  @ @.>",CR,LF
		.text   "          `._ _,-.   )      _,.-'",CR,LF
		.text   "             `    V.v-'^V''v",CR,CR,LF
		.text   0
		
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
		.word	NMI_ISR		; NMI interrupt in 65c02 emulation mode
* = $FFFC
ERESET	
		.word	START		; RESET exception in all modes
* = $FFFE
EIRQ	
		.word	IRQ_ISR 

.end					; finally.  das Ende.  Fini.  It's over.  Go home!

