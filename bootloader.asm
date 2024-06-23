;
; FIXME:  Lots of stye mismatch and format ugliness due to merging different code.
;	For now, leave it be so it's obvious what is new and old code.
;	Do a clean-up once there's some confidence in the new parts\\
;
;	Also, re-write code directy from WDCmon in case there are copyright issues.
;	It's all very straightforward code because no sense in importing the nonsense.
;
;Intel HEX File Downloader
; R. Archer 6/2024
;This program is freeware. Use it, modify it, ridicule it in public, or whatever, so long as authorship credit (blame?) is given somewhere to me for the base program.
;
; ($7FEB, $7FEA):	NMI RAM vector
; ($7FEF, $7FEE):       IRQ RAM vector
; (User program may not set a new RESET vector, or we could load
; an unrecoverable program into SRAM if battery backed, which would
; kill the system until the RAM was removed!)
;
;
; TIDE2VIA	
; IO for the VIA which is used for the USB debugger interface.
SYSTEM_VIA_IOB              = $7FE0 ; Port B IO register
SYSTEM_VIA_IOA              = $7FE1 ; Port A IO register
SYSTEM_VIA_DDRB             = $7FE2 ; Port B data direction register
SYSTEM_VIA_DDRA             = $7FE3 ; Port A data direction register
SYSTEM_VIA_T1C_L           = $7FE4 ; Timer 1 counter/latches, low-order
SYSTEM_VIA_T1C_H           = $7FE5 ; Timer 1 high-order counter
SYSTEM_VIA_T1L_L           = $7FE6 ; Timer 1 low-order latches
SYSTEM_VIA_T1L_H           = $7FE7 ; Timer 1 high-order latches
SYSTEM_VIA_T2C_L           = $7FE8 ; Timer 2 counter/latches, lower-order
SYSTEM_VIA_T2C_H           = $7FE9 ; Timer 2 high-order counter
SYSTEM_VIA_SR              = $7FEA ; Shift register
SYSTEM_VIA_ACR              = $7FEB ; Auxilliary control register
SYSTEM_VIA_PCR              = $7FEC ; Peripheral control register
SYSTEM_VIA_IFR             = $7FED ; Interrupt flag register
SYSTEM_VIA_IER             = $7FEE ; Interrupt enable register
SYSTEM_VIA_ORA_IRA         = $7FEF ; Port A IO register, but no handshake


; 6551 ACIA equates for serial I/O
;
ACIA_BASE= $7F30	; This is where the 6551 ACIA starts
SDR = ACIA_BASE       	; RX'ed bytes read, TX bytes written, here
SSR = ACIA_BASE+1     	; Serial data status register. A write here
                                ; causes a programmed reset.
SCMD = ACIA_BASE+2     	; Serial command reg. ()
SCTL = ACIA_BASE+3     	; Serial control reg. ()
; Quick n'dirty assignments instead of proper definitions of each parameter
; "ORed" together to build the desired flexible configuration.  We're going
; to run 19200 baud, no parity, 8 data bits, 1 stop bit.  Period.  For now.
;
SCTL_V  = %00011111       ; 1 stop, 8 bits, 19200 baud
SCMD_V  = %00001011       ; No parity, no echo, no tx or rx IRQ, DTR*
TX_RDY  = %00010000       ; AND mask for transmitter ready
RX_RDY  = %00001000       ; AND mask for receiver buffer full
;
; Zero-page storage
DPL =            $00     ; data pointer (two bytes)
DPH  =           $01     ; high of data pointer
RECLEN  =        $02     ; record length in bytes
START_LO  =      $03
START_HI =       $04
RECTYPE =        $05
CHKSUM =         $06     ; record checksum accumulator
DLFAIL=          $07     ; flag for download failure
TEMP =          $08     ; save hex value

; "Shadow" RAM vectors (note each is $8000 below the actual ROM vector)
NMIVEC	= 	 $7EFA	; write actual NMI vector here
IRQVEC   =       $7EFE   ; write IRQ vector here

ENTRY_POINT = 	$2000	; where the RAM program MUST have its first instruction

* = $F800
;
START   sei                     ; disable interrupts
        cld                     ; binary mode arithmetic
        ldx     #$FF            ; Set up the stack pointer
        txs                     ;       "
        lda     #>START      ; Initialiaze the interrupt vectors
        sta     NMIVEC+1        ; User program at ENTRY_POINT may change
        sta     IRQVEC+1	; these vectors.  Just do change before enabling
        lda     #<START		; the interrupts, or you'll end up back in the d/l monitor.
        sta     NMIVEC
        sta     IRQVEC
	jsr	INITVIA	; Set up 65C22 to FIFO interface chip (and ROM bank select)
        jsr     INITSER         ; Set up baud rate, parity, etc.
FIFOCHK	jsr	GETFIFO
	bcc	FIFOCHK		; If no character, nothing to echo 		
FIFO_OUT
	jsr	PUTFIFO
	bra	FIFOCHK
        ; Download Intel hex.  The program you download MUST have its entry
        ; instruction (even if only a jump to somewhere else) at ENTRY_POINT.
HEXDNLD lda     #0
        sta     DLFAIL          ;Start by assuming no D/L failure
        jsr     PUTSTRI
        .text   13,10,13,10
        .text   "Send 65C02/65C816 code in"
        .text   " Intel Hex format"
        .text  " at 19200,n,8,1 ->"
        .text   13,10
	.text	0		; Null-terminate unless you prefer to crash.
HDWRECS jsr     GETSER          ; Wait for start of record mark ':'
        cmp     #':'
        bne     HDWRECS         ; not found yet
        ; Start of record marker has been found
        jsr     GETHEX          ; Get the record length
        sta     RECLEN          ; save it
        sta     CHKSUM          ; and save first byte of checksum
        jsr     GETHEX          ; Get the high part of start address
        sta     START_HI
        clc
        adc     CHKSUM          ; Add in the checksum
        sta     CHKSUM          ;
        jsr     GETHEX          ; Get the low part of the start address
        sta     START_LO
        clc
        adc     CHKSUM
        sta     CHKSUM
        jsr     GETHEX          ; Get the record type
        sta     RECTYPE         ; & save it
        clc
        adc     CHKSUM
        sta     CHKSUM
        lda     RECTYPE
        bne     HDER1           ; end-of-record
        ldx     RECLEN          ; number of data bytes to write to memory
        ldy     #0              ; start offset at 0
HDLP1   jsr     GETHEX          ; Get the first/next/last data byte
        sta     (START_LO),y    ; Save it to RAM
        clc
        adc     CHKSUM
        sta     CHKSUM          ;
        iny                     ; update data pointer
        dex                     ; decrement count
        bne     HDLP1
        jsr     GETHEX          ; get the checksum
        clc
        adc     CHKSUM
        bne     HDDLF1          ; If failed, report it
        ; Another successful record has been processed
        lda     #'#'            ; Character indicating record OK = '#'
        sta     SDR             ; write it out but don't wait for output
        jmp     HDWRECS         ; get next record
HDDLF1  lda     #'F'            ; Character indicating record failure = 'F'
        sta     DLFAIL          ; download failed if non-zero
        sta     SDR             ; write it to transmit buffer register
        jmp     HDWRECS         ; wait for next record start
HDER1   cmp     #1              ; Check for end-of-record type
        beq     HDER2
        jsr     PUTSTRI         ; Warn user of unknown record type
        .text   13,10,13,10
        .text   "Unknown record type $"
	.text	0		; null-terminate unless you prefer to crash!
        lda     RECTYPE         ; Get it
	sta	DLFAIL		; non-zero --> download has failed
        jsr     PUTHEX          ; print it
	lda     #13		; but we'll let it finish so as not to
        jsr     PUTSER		; falsely start a new d/l from existing
        lda     #10		; file that may still be coming in for
        jsr     PUTSER		; quite some time yet.
	jmp	HDWRECS
	; We've reached the end-of-record record
HDER2   jsr     GETHEX          ; get the checksum
        clc
        adc     CHKSUM          ; Add previous checksum accumulator value
        beq     HDER3           ; checksum = 0 means we're OK!
        jsr     PUTSTRI         ; Warn user of bad checksum
        .text   13,10,13,10
        .text   "Bad record checksum!",13,10
        .text   0		; Null-terminate or 6502 go bye-bye
        jmp     START
HDER3   lda     DLFAIL
        beq     HDEROK
        ;A download failure has occurred
        jsr     PUTSTRI
        .text   13,10,13,10
        .text   "Download Failed",13,10
        .text   "Aborting!",13,10
	.text	0		; null-terminate every string yada yada.
        jmp     START
HDEROK  jsr     PUTSTRI
        .text   13,10,13,10
        .text   "Download Successful!",13,10
        .text   "Jumping to location $"
	.text	0			; by now, I figure you know what this is for. :)
        lda	#>ENTRY_POINT		; Print the entry point in hex
        jsr	PUTHEX
        lda	#<ENTRY_POINT
	jsr	PUTHEX
        jsr	PUTSTRI
        .text   13,10
        .text   0		; stop lemming-like march of the program ctr. thru data
        jmp     ENTRY_POINT	; jump to canonical entry point

;
; Set up baud rate, parity, stop bits, interrupt control, etc. for
; the serial port.
INITSER lda     #SCTL_V 	; Set baud rate 'n stuff
        sta     SCTL
        lda     #SCMD_V 	; set parity, interrupt disable, n'stuff
        sta     SCMD
        rts


; Initializes the system VIA (the USB debugger), and syncs with the USB chip.
INITVIA	STZ     SYSTEM_VIA_ACR	; Disable PB7, shift register, timer T1 interrupt.

        ; Cx1/Cx2 as inputs with negative active edge, for both ports. These
        ; aren't used for the system VIA debugging interface, but the Cx2
        ; lines are connected to the FLASH, and they select the bank. Setting
        ; them as inputs allows the pullups to automatically select the bank
        ; which contains the factory-programmed FLASH bank with the monitor.
        STZ     SYSTEM_VIA_PCR

       
        ; Preset port B output for $18 (TUSB_RDB and PB4-not-connected high).
        lda     #$18
        STA     SYSTEM_VIA_IOB

        ; Set PB2 (TUSB_WR), PB3 (TUSB_RDB), and PB4 (N.C.) as outputs. This
        ; has the effect of writing $FF to the USB FIFO when the RESET button
        ; is pressed. When RESET is pressed, it causes the system VIA to output
        ; high on TUSB_WR, then when this write sets TUSB_WR low, the high-to-
        ; low transition on TUSB_WR triggers a write to the USB FIFO. At this
        ; point, port A (the USB FIFO data lines) are not being driven, and
        ; either float high, or are pulled high internally, because this
        ; triggers a write of $FF to the USB FIFO.
        lda     #$1C
        STA     SYSTEM_VIA_DDRB
        ; Set all IO on port A to inputs.
        STZ     SYSTEM_VIA_DDRA

        ; Read port B (USB status and control lines) and save it on the stack.
        lda     SYSTEM_VIA_IOB
        PHA

        ; Mask out bit 4, which is not connected.
        AND     #$EF

        ; Write the result back. Not sure why since only bit 4 changes, and
        ; it is not connected (according to schematic rev. C, Dec. 15, 2020).
        STA     SYSTEM_VIA_IOB

        ; Delay for $5D*256 loop cycles.
        LDX     #$5D
        JSR     WASTETM

        ; Pull the original port B value, and write it back to the port.
        PLA
        STA     SYSTEM_VIA_IOB

        ; Wait until PB5 (TUSB_PWRENB) goes low, indicating it's powered up.
        lda     #$20
WFPWRBIT    
	LDA	SYSTEM_VIA_IOB
        BNE     WFPWRBIT
        RTS
;
;
; SerRdy : Return
SERRDY  lda     SSR     	; look at serial status
        and     #RX_RDY 	; strip off "character waiting" bit
        rts             	; if zero, nothing waiting.
; Warning: this routine busy-waits until a character is ready.
; If you don't want to wait, call SERRDY first, and then only
; call GETSER once a character is waiting.
GETSER  lda     SSR    		; look at serial status
        and     #RX_RDY 	; see if anything is ready
        beq     GETSER  	; busy-wait until character comes in!
        lda     SDR     	; get the character
        rts
; Busy wait

GETHEX  jsr     GETSER
        jsr     MKNIBL  	; Convert to 0..F numeric
        asl     a
        asl     a
        asl     a
        asl     a       	; This is the upper nibble
        and     #$F0
        sta     TEMP
        jsr     GETSER
        jsr     MKNIBL
        ora     TEMP
        rts             	; return with the nibble received

; Convert the ASCII nibble to numeric value from 0-F:
MKNIBL  cmp     #'9'+1  	; See if it's 0-9 or 'A'..'F' (no lowercase yet)
        bcc     MKNNH   	; If we borrowed, we lost the carry so 0..9
        sbc     #7+1    	; Subtract off extra 7 (sbc subtracts off one less)
        ; If we fall through, carry is set unlike direct entry at MKNNH
MKNNH   sbc     #'0'-1  	; subtract off '0' (if carry clear coming in)
        and     #$0F    	; no upper nibble no matter what
        rts             	; and return the nibble

; Put byte in A as hexydecascii
PUTHEX  pha             	;
        lsr a
        lsr a
        lsr a
        lsr a
        jsr     PRNIBL
        pla
PRNIBL  and     #$0F    	; strip off the low nibble
        cmp     #$0A
        bcc     NOTHEX  	; if it's 0-9, add '0' else also add 7
        adc     #6      	; Add 7 (6+carry=1), result will be carry clear
NOTHEX  adc     #'0'    	; If carry clear, we're 0-9
; Write the character in A as ASCII:
PUTSER  sta     SDR     	; write to transmit register
WRS1    lda     SSR     	; get status
        and     #TX_RDY 	; see if transmitter is busy
        beq     WRS1    	; if it is, wait
        rts
;Put the string following in-line until a NULL out to the console
PUTSTRI pla			; Get the low part of "return" address (data start address)
        sta     DPL
        pla
        sta     DPH             ; Get the high part of "return" address
                                ; (data start address)
        ; Note: actually we're pointing one short
PSINB   ldy     #1
        lda     (DPL),y         ; Get the next string character
        inc     DPL             ; update the pointer
        bne     PSICHO          ; if not, we're pointing to next character
        inc     DPH             ; account for page crossing
PSICHO  ora     #0              ; Set flags according to contents of Accumulator
        beq     PSIX1           ; don't print the final NULL
        jsr     PUTSER          ; write it out
        jmp     PSINB           ; back around
PSIX1   inc     DPL             ;
        bne     PSIX2           ;
        inc     DPH             ; account for page crossing
PSIX2   jmp     (DPL)           ; return to byte following final NULL
;

; Returns 1 in A if there is data available to be read, 0 if not.
Is_VIA_USB_RX_Data_Avail:

        ; Set all bits on port A to inputs.
        LDA     #$00
        STA     SYSTEM_VIA_DDRA

        ; See if PB1 (TUSB_RXFB) is high.
        LDA     #$02
        bit     SYSTEM_VIA_IOB
        bne     not_zero

        ; It is low, meaning there is data available to read.
        LDA     #$01
        RTS

not_zero	
	LDA     #$00	; It is high, meaning there is no data available to read.
        RTS

; Waits for a byte to be ready on the USB FIFO and then reads it, returning
; the value read in the A register.
; Note: Destroys A, flags
; 
; On exit:
; If C==1 then A contains the next FIFO byte
; If C==0 then there was nothing waiting and A is not guaranteed to mean anything
;
GETFIFO	PHX				; Save X
	STZ     SYSTEM_VIA_DDRA		; D0-D7 from FIFO --> CPU (00 = make all port A pins inputs)
        ; Set up to test PB1 (TUSB_RXFB).
        LDA     #$02
        ; Wait for PB1 (TUSB_RXFB) to be low. This indicates data can be
        ; read from the FIFO by strobing PB3 low then high again.
	BIT     SYSTEM_VIA_IOB	; AND with b1 to see if RXF is low (character awaiting read) or RXF=1 (no data waiting)
       	BEQ     GFRD		; 0 = FIFO has a character, so read it in
	; No character waiting.  Exit with carry clear and A=??
	CLC			; carry clear means nothing is waiting
	BRA GFXIT		; And return with carry clear because is waiting
        ; Perform a read-modify-write on port B, clearing PB3 (TUSB_RDB).
        ; This triggers the FIFO to drive the received byte on port A.
GFRD: 	lda     SYSTEM_VIA_IOB
        ora     #$08    ; Save a copy of port B with PB3 set high.
        tax     ; This will be used later.
        and     #$F7
        STA     SYSTEM_VIA_IOB

        ; Wait for the FIFO to drive the data and the lines to settle
        ; (between 20ns and 50ns, according to the datasheet).
        nop	; FIXME: This is some dumb bullshift. That's ONE machine cycle.  
	; At 2 cycles per instruction at most one NOP should be required to accomplish the above comment.  
        nop	; FIXME: Will retain for now in case it's papering over some other problem that the original firmware is working around.	
        nop	
        NOP

        ; Read the data byte from the FIFO on port A.
        LDA     SYSTEM_VIA_IOA		

        ; Restore the original value of port B, while setting PB3 high again.
        stx     SYSTEM_VIA_IOB
	SEC		; Signal that a valid character is waiting
GFXIT	PLX		; Restore X as it was used in routine
	RTS

; The different case styles are deliberate but intended to be temporary.
; Makes "new"/FIFO code obvious until it's debugged. Normalize style after integrated.
;
; Sends the byte stored in A to the debugger, waiting until it can be sent.
PUTFIFO		
	STZ     SYSTEM_VIA_DDRA		; Set all bits on port A to inputs.

        ; Write register A to port A. This has no effect on the actual
        ; output pin until port A is set as an output.
       	STA     SYSTEM_VIA_IOA

        ; Set up register A to test port B, bit 0 (TUSB_TXEB).
        LDA     #$01

        ; Wait for PB0 (TUSB_TXEB) to be low. This indicates data can be
        ; written to the FIFO by strobing PB2 (TUSB_WR) high then low.
WFTXEBL		
	bit     SYSTEM_VIA_IOB
        BNE     WFTXEBL

        ; Perform a read-modify-write on port B, setting bit 2 (TUSB_WR).
        ; Save the original value in X temporarily.
        lda     SYSTEM_VIA_IOB
        AND     #$FB	; Save a copy of port B with PB2 low.
        TAX
        ora     #$04	; Set PB2 high.
        STA     SYSTEM_VIA_IOB

        ; Set all bits on port A to outputs. This causes the pin outputs
        ; to be set to what we wrote to port A earlier in the subroutine.
        lda     #$FF
        STA     SYSTEM_VIA_DDRA

        ; Wait for the port A outputs to settle. The datasheet says this
        ; must be held at least 20 ns before PB2 (TUSB_WR) is brought low.
        NOP
        NOP

        ; Write the original port B value back, setting PB2 back to low.
        STX     SYSTEM_VIA_IOB

        ; Read port A. But why? The values read should be the actual
        ; values driven on the pins, which may not be what we commanded
        ; them to if, for example, they are heavily loaded. This value
        ; is returned in the A register, and could be examined by the
        ; caller. But this is not used anywhere in the monitor.
        LDA     SYSTEM_VIA_IOA

        ; Set all bits in port A as inputs.
        ldx     #$00
        STX     SYSTEM_VIA_DDRA

        ; All done.
        rts

; A subroutine which does absolutely nothing.
Do_Nothing_Subroutine_1:
        rts

; Delays by looping 256*X times.
WASTETM	phx
        ldx     #$00
loop_256_times:
        dex
        bne     loop_256_times
        plx
        dex
        bne    	WASTETM
        rts


; User "shadow" vectors:
GOIRQ	jmp	(IRQVEC)
GONMI	jmp	(NMIVEC)
GORST	jmp	START		; Allowing user program to change this is a mistake

* = $FFFA
;  start at $FFFA
NMIENT  .word     GONMI
RSTENT  .word     GORST
IRQENT  .word     GOIRQ
.end				; finally.  das Ende.

Last page update: March 22, 2001. 