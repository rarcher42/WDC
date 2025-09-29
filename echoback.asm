
; Assembled with 64TASS
; 		64tass -c stripmon.asm -L stripmon.lst
; 
; Put the above equates into an included file per peripheral or board

        .cpu    "w65c02"

.INCLUDE	"via_symbols.inc"
   
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
M_FLAG		= MASK6
X_FLAG		= MASK4
D_FLAG		= MASK3
I_FLAG		= MASK2
Z_FLAG		= MASK1
C_FLAG		= MASK0


* = $FF00
START 		SEI
			CLD					
			LDX	#$FF				; Only 8 bit stack pointer for this non-65816 adaptation
			TXS
			JSR	INITCHAR
			LDA 	#'*'
			JSR	PUTCHAR
ECHO_LOOP		JSR	GETCHAR				; attempt to get next character in	
			BCC	ECHO_LOOP			; if no character received, back again to start
			JSR	PUTCHAR				; echo it back
			JMP ECHO_LOOP

; ----------- Interface vectors to EhBASIC ------------------
LAB_vec
      .word GETCHAR           ; byte in from FIFO
      .word PUTCHAR           ; byte out to FIFO
      .word LOAD_IT           ; null load vector for EhBASIC
      .word SAVE_IT           ; null save vector for EhBASIC
	  
	  
;;;; ============================= New FIFO functions ======================================
; Initializes the system VIA (the USB debugger), and syncs with the USB chip.

FIFO_TXE = PB0
FIFO_RXF = PB1
FIFO_WR = PB2
FIFO_RD = PB3
FIFO_PWREN = PB5
FIFO_DEBUG = PB7		; Handy debug toggle output free for any use


; Semantics for Lee Davidson's EhBASIC interpreter Input routine
GETCHAR		JSR	GET_FRAW
			BCS	GCX1	; Carry set to indicate A is valid; A contains valid $00-$FF character
			LDA #$00	; Return with Carry clear and A=0 to signify nothing is waiting for us
GCX1		RTS
	

; Semantics for Lee Davidson's EhBASIC interpreter Output routine
; (Preserve A; return with N and Z flags set according to value in A)
PUTCHAR		JMP	PUT_FRAW

LOAD_IT		RTS			; Add LOAD support here
SAVE_IT		RTS			; Add SAVE support here

NMI_ISR		RTI
IRQ_ISR		RTI


INITCHAR		
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
			RTS					

		
; Non-blocking Put FIFO.  Return with carry flag set if buffer is full and nothing was output. 
; Return carry clear upon successful queuing
PUT_FRAW	PHA							; save output character
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
OFX1		PLA							; restore input character, N and Z flags
			RTS
;
;
		
; On exit:
; If Carry flag is set, A contains the next byte from the FIFO
; If carry flag is clear, no character was received and A doesn't contain anything meaningful
GET_FRAW	
			LDA	SYSTEM_VIA_IORB			; Check RXF flag
			AND	#FIFO_RXF				; If clear, we're OK to read.  If set, there's no data waiting
			CLC							; Assume no character (overridden if A != 0)
			BNE INFXIT					; If RXF is 1, then no character is waiting!
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

