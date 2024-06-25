;
; Ultra-basic bootloader.  Not yet working.
; R. Archer 6/2024
; Assembled with 64TASS
; 		64tass -c bootloader.asm -L bootloader.lst
; 
;
; Zero page storage:
;
DPL 		=	$00     ; data pointer (two bytes)
DPH  		=   $01     ; high of data pointer
RECLEN  	=   $02     ; record length in bytes
START_LO  	=   $03
START_HI 	=   $04
RECTYPE 	=   $05
CHKSUM 		=   $06     ; record checksum accumulator
DLFAIL		=   $07     ; flag for download failure
TEMP 		=   $08     ; save hex value

; TIDE2VIA	the system VIA
; IO for the VIA which is used for the USB debugger interface.
SYSTEM_VIA_IORB     = $7FE0 ; Port B IO register
SYSTEM_VIA_IORA     = $7FE1 ; Port A IO register
SYSTEM_VIA_DDRB     = $7FE2 ; Port B data direction register
SYSTEM_VIA_DDRA     = $7FE3 ; Port A data direction register
SYSTEM_VIA_T1C_L    = $7FE4 ; Timer 1 counter/latches, low-order
SYSTEM_VIA_T1C_H    = $7FE5 ; Timer 1 high-order counter
SYSTEM_VIA_T1L_L    = $7FE6 ; Timer 1 low-order latches
SYSTEM_VIA_T1L_H    = $7FE7 ; Timer 1 high-order latches
SYSTEM_VIA_T2C_L    = $7FE8 ; Timer 2 counter/latches, lower-order
SYSTEM_VIA_T2C_H    = $7FE9 ; Timer 2 high-order counter
SYSTEM_VIA_SR       = $7FEA ; Shift register
SYSTEM_VIA_ACR      = $7FEB ; Auxilliary control register
SYSTEM_VIA_PCR      = $7FEC ; Peripheral control register
SYSTEM_VIA_IFR		= $7FED ; Interrupt flag register
SYSTEM_VIA_IER      = $7FEE ; Interrupt enable register
SYSTEM_VIA_ORA_IRA	= $7FEF ; Port A IO register, but no handshake
; System VIA named bitmasks
PB0 = MASK0
PB1 = MASK1
PB2 = MASK2
PB3 = MASK3
PB5 = MASK5
FIFO_TXE = PB0
FIFO_RXF = PB1
FIFO_WR = PB2
FIFO_RD = PB3
FIFO_PWREN = PB5

; 6551 ACIA equates for serial I/O
;
ACIA_BASE= $7F30		; This is where the 6551 ACIA starts
SDR = ACIA_BASE       	; RX'ed bytes read, TX bytes written, here
SSR = ACIA_BASE+1     	; Serial data status register. A write here
                                ; causes a programmed reset.
SCMD = ACIA_BASE+2     	; Serial command reg. ()
SCTL = ACIA_BASE+3     	; Serial control reg. ()
; Quick n'dirty assignments instead of proper definitions of each parameter
; "ORed" together to build the desired flexible configuration.  We're going
; to run 19200 baud, no parity, 8 data BITs, 1 stop BIT.  Period.  For now.
;
SCTL_V  = %00011111       ; 1 stop, 8 BITs, 19200 baud
SCMD_V  = %00001011       ; No parity, no echo, no tx or rx IRQ, DTR*
TX_RDY  = %00010000       ; AND mask for transmitter ready
RX_RDY  = %00001000       ; AND mask for receiver buffer full
;

; "Shadow" RAM vectors (note each is $8000 below the actual ROM vector)
NMIVEC	= 	 $7EFA	; write actual NMI vector here
IRQVEC   =       $7EFE   ; write IRQ vector here

; Lazy stuff
MASK0	=	 %00000001
MASK1	=	 %00000010
MASK2	=	 %00000100
MASK3	=	 %00001000
MASK4	=	 %00010000
MASK5	=	 %00100000
MASK6	=	 %01000000
MASK7	=	 %10000000

*= $F800						; Monitor start address
START   	SEI                     ; disable interrupts
        	CLD                     ; binary mode arithmetic (not required on 65C02 or 65816)
        	LDX     #$FF            ; Set up the stack pointer
        	TXS                     ;       "
        	LDA     #>START      	; Initialiaze the interrupt vectors
        	STA     NMIVEC+1        ; User program at ENTRY_POINT may change
        	STA     IRQVEC+1	; these vectors.  Just do change before enabling
        	LDA     #<START		; the interrupts, or you'll end up back in the d/l monitor.
        	STA     NMIVEC
        	STA     IRQVEC
		JSR	INITVIA		; Set up 65C22 to FIFO interface chip (and ROM bank select)
ECHO		LDA	#'*'
		JSR	FIFOOUT		; Just send something in case FIFOIN hangs so we know we got this far FIXME: remove this
ECHO2		JSR	FIFOIN
		BCC	ECHO2		; Wait for an incoming character
		JSR	FIFOOUT
		BRA	ECHO2


;;;; ============================= New FIFO functions ======================================
; Initializes the system VIA (the USB debugger), and syncs with the USB chip.
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
INITVIA
		STZ     SYSTEM_VIA_PCR			; float CB2 (FAMS) hi so flash A16=1; float CA2 (FA15) hi so flash A15=1 (Bank #3)
		STZ 	SYSTEM_VIA_ACR			; Disable PB7, shift register, timer T1 interrupt.  Not absolutely required while interrupts are disabled FIXME: set up timer
		STZ	SYSTEM_VIA_DDRA			; Set PA0-PA7 to all inputs
		STZ	SYSTEM_VIA_DDRB			; In case we're not coming off a reset, make PORT B an input and change output register when it's NOT outputting
		LDA	#FIFO_RD				;
		STA	SYSTEM_VIA_IORB			; Avoid possible glitch by writing to output latch while Port B is still an input (after reset)
		LDA	#(FIFO_RD + FIFO_WR)	; Make the FIFO RD and FIFO_WR pins outputs so we can strobe data in and out of the FIFO
		STA	SYSTEM_VIA_DDRB			; Port B: PB2 and PB3 are outputs; rest are inputs from earlier IORB write
		; Defensively wait for ports to settle 
		NOP								; FIXME: Defensive and possibly unnecessary
FIFOPWR:
		; FIXME: Add timeout here
		LDA	SYSTEM_VIA_IORB
		AND	#FIFO_PWREN				; PB5 = PWRENB. 0=enabled 1=disabled
		BNE	FIFOPWR	
		RTS
;

; Attempt to output the byte in A.
; If successful, the carry flag will be SET
; If the FIFO is full, it will return immediately with the carry clear.
; Caller is responsible for checking the carry flag with BCC or BCS 
; and re-trying if carry is set.
FIFOOUT 	STA	TEMP			; save output character
		LDA	SYSTEM_VIA_IORB		; Read in FIFO status Port for FIFO
		AND	#FIFO_TXE		; If TXE is low, we can accept data into FIFO.  If high, return immmediately
		CLC
		BNE	OFX1			; 0 = OK to write to FIFO; 1 = Wait, FIFO full!
		; FIFO has room - write A to FIFO in a series of steps
OFCONT		STZ	SYSTEM_VIA_DDRA		; (Defensive) Start with Port A input/floating 
		LDA	#(FIFO_RD + FIFO_WR)	; RD=1 WR=1 (WR must go 1->0 for FIFO write)
		STA	SYSTEM_VIA_IORB		; Make sure write is high (and read too!)
		LDA	#$FF			; make Port A all outputs
		STA	SYSTEM_VIA_DDRA		; Save data to output latches
		LDA	TEMP
		STA	SYSTEM_VIA_IORA		; Write output value to output latches 
		NOP				; Some settling time of data output just to be safe
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
		STZ	SYSTEM_VIA_DDRA		; Make port A an input again
		SEC				; signal success of write to caller
OFX1:	  	RTS
;
;
;
; On return:
; If Carry flag is set, A contains the next byte from the FIFO
; If carry flag is clear, there were no characters waiting
FIFOIN		LDA	SYSTEM_VIA_IORB	; Check RXF flag
		AND	#FIFO_RXF		; If clear, we're OK to read.  If set, there's no data waiting
		CLC
		BNE 	INFXIT			; If RXF is 1, then no character is waiting!
		STZ	SYSTEM_VIA_DDRA		; Make Port A inputs
		LDA	#FIFO_RD
		STA	SYSTEM_VIA_IORB		; RD=1 WR=0 (RD must go to 0 to read
		NOP
		STZ	SYSTEM_VIA_IORB		; RD=0 WR=0	- FIFO presents data to port A	
		NOP
		NOP
		LDA	SYSTEM_VIA_IORA			; read data in
		PHA
		LDA	#FIFO_RD				; Restore back to inactive signals RD=1 and WR=0
		STA	SYSTEM_VIA_IORB
		PLA
		SEC							; we bot a byte!
INFXIT		RTS



; User "shadow" vectors:
GOIRQ		JMP	(IRQVEC)
GONMI		JMP	(NMIVEC)
GORST		JMP	START		; Allowing user program to change this is a mistake

* = $FFFA
;  start at $FFFA
NMIENT  .word     GONMI
RSTENT  .word     GORST
IRQENT  .word     GOIRQ
.end				; finally.  das Ende.  Fini.  It's over.  Go home!

Last page update: March 22, 2001. 
