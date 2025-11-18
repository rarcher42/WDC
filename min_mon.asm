
		.include "ehbasic.asm"

MASK0		= %00000001
MASK1		= %00000010
MASK2		= %00000100
MASK3		= %00001000
MASK4		= %00010000
MASK5		= %00100000
MASK6 		= %01000000
MASK7		= %10000000

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
SYSTEM_VIA_T2L    = 	SYS_VIA_BASE+8	; Timer 2 counter/latches, lower-order
SYSTEM_VIA_T2H    = 	SYS_VIA_BASE+9	; Timer 2 high-order counter
SYSTEM_VIA_SR       = 	SYS_VIA_BASE+10	; Shift register
SYSTEM_VIA_ACR      = 	SYS_VIA_BASE+11	; Auxilliary control register
SYSTEM_VIA_PCR      =	SYS_VIA_BASE+12	; Peripheral control register
SYSTEM_VIA_IFR	    =	SYS_VIA_BASE+13 ; Interrupt flag register
SYSTEM_VIA_IER      = 	SYS_VIA_BASE+14	; Interrupt enable register
SYSTEM_VIA_ORA_IRA  =	SYS_VIA_BASE+15	; Port A IO register, but no handshake

DEBUG_VIA_BASE	    = 	$7FC0
DEBUG_VIA_IORB     =  	DEBUG_VIA_BASE+0	; Port B IO register
DEBUG_VIA_IORA     =	DEBUG_VIA_BASE+1 	; Port A IO register
DEBUG_VIA_DDRB     = 	DEBUG_VIA_BASE+2	; Port B data direction register
DEBUG_VIA_DDRA     = 	DEBUG_VIA_BASE+3	; Port A data direction register
DEBUG_VIA_T1C_L    =	DEBUG_VIA_BASE+4 	; Timer 1 counter/latches, low-order
DEBUG_VIA_T1C_H    = 	DEBUG_VIA_BASE+5	; Timer 1 high-order counter
DEBUG_VIA_T1L_L    = 	DEBUG_VIA_BASE+6	; Timer 1 low-order latches
DEBUG_VIA_T1L_H    = 	DEBUG_VIA_BASE+7	; Timer 1 high-order latches
DEBUG_VIA_T2C_L    = 	DEBUG_VIA_BASE+8	; Timer 2 counter/latches, lower-order
DEBUG_VIA_T2C_H    = 	DEBUG_VIA_BASE+9	; Timer 2 high-order counter
DEBUG_VIA_SR       = 	DEBUG_VIA_BASE+10	; Shift register
DEBUG_VIA_ACR      = 	DEBUG_VIA_BASE+11	; Auxilliary control register
DEBUG_VIA_PCR      =	DEBUG_VIA_BASE+12	; Peripheral control register
DEBUG_VIA_IFR	    =	DEBUG_VIA_BASE+13 ; Interrupt flag register
DEBUG_VIA_IER      = 	DEBUG_VIA_BASE+14	; Interrupt enable register
DEBUG_VIA_ORA_IRA  =	DEBUG_VIA_BASE+15	; Port A IO register, but no handshake


			.org	$F800
			
RES_vec		SEI
			CLD					
			LDX	#$FF				; Only 8 bit stack pointer for this non-65816 adaptation
			TXS
			JSR	INITCHAR
			LDA 	#'*'
			JSR	PUTCHAR
ECHO_LOOP	JSR	GETCHAR				; attempt to get next character in	
			BCC	ECHO_LOOP			; if no character received, back again to start
			JSR	PUTCHAR				; echo it back
			JMP ECHO_LOOP

NMI_vec		RTI


IRQ_vec		RTI


			.org 	$FF00


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


INITCHAR		
INIT_FIFO
			LDA	#$FF
			STA SYSTEM_VIA_PCR			; CB2=FAMS=flash A16=1;  CA2=FA15=A15=1; Select flash Bank #3\
			LDA	#0
			STA SYSTEM_VIA_ACR			; Disable PB7, shift register, timer T1 interrupt.  Not absolutely required while interrupts are disabled FIXME: set up timer
			STA	SYSTEM_VIA_DDRA			; Set PA0-PA7 to all inputs
			STA	SYSTEM_VIA_DDRB			; In case we're not coming off a reset, make PORT B an input and change output register when it's NOT outputting
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
    		STA	SYSTEM_VIA_DDRA			; A==0 thanks to BNE not taken; (Defensive) Start with Port A input/floating 
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
			LDA #0
			STA	SYSTEM_VIA_DDRA			; Make port A an input again
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
			LDA #0
			STA	SYSTEM_VIA_DDRA			; Make Port A inputs
			LDA	#FIFO_RD
			STA	SYSTEM_VIA_IORB			; RD=1 WR=0 (RD must go to 0 to read
			NOP
			LDA	#0
			STA	SYSTEM_VIA_IORB			; RD=0 WR=0	- FIFO presents data to port A	
			NOP
			LDA	SYSTEM_VIA_IORA			; read data in
			PHA
			LDA	#FIFO_RD				; Restore back to inactive signals RD=1 and WR=0
			STA	SYSTEM_VIA_IORB
			PLA
			SEC							; we got a byte!
INFXIT	
			RTS


			.org	$FFE4
NCOP	
		.word	RES_vec		; COP exception in native mode
			.org	$FFE6
NBRK	
		.word	RES_vec		; BRK in native mode
			.org	$FFE8
NABORT	
		.word	RES_vec
			.org	$FFEA
NNMI	
		.word	RES_vec		; NMI interrupt in native mode
			.org	$FFEE
NIRQ	
		.word	RES_vec  

		.org	$FFF4
ECOP	
		.word	RES_vec		; COP exception in 65c02 emulation mode
		.org	$FFF8
EABORT	
		.word	RES_vec
		.org	$FFFA
ENMI		
		.word	NMI_vec		;NMI int in 65c02 emulation mode
		.org	$FFFC
ERESET	
		.word	RES_vec		; RESET exception in all modes
		.org	$FFFE
EIRQ	
		.word	IRQ_vec

.end					; finally.  das Ende.  Fini.  It's over.  Go home!

