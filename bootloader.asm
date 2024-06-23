
;Intel HEX File Downloader
;Ross Archer, 9 February 2001
;
;This program is freeware. Use it, modify it, ridicule it in public, or whatever, so long as authorship credit (blame?) is given somewhere to me for the base program.
;
;Although this program has worked on two different 65C02-based boards, with TASM output files, I make no warranty of fitness or anything else. It's free -- so no matter what, happens you get your money's worth.;
;
;Feel free to write me at dogbert@mindless.com if you are having difficulties or have suggestions for improvement. This is still a work in progress.
;
;To customize for your 6551-equipped 6502 SBC
;[UK users have dispensation to customise it instead.]
;
;    Set ACIA_BASE to the location of your 6551 ACIA (UART).
;    Change ENTRY_POINT as needed, if you prefer to jump somewhere other than to $0200 after downloading code to RAM.
;    Change .org location to locate START wherever you like. I put it in the top 2K of memory since my hardware write-protects the EEPROM there but allows me to write to the lower 30K at will, making this the only 100% safe place for monitor code in EE. YMMV
;    When burning EPROMs, remember to account for the File offset with your programmer. For example, if burning a 32K E(E)PROM, the offset is $8000. If using a 16K E(E)PROM, the offset is $C000, etc. Best to see that your start vectors are in the top six locations in your E(E)PROM as a sanity check before blasting away.
;    ALL RAM-ified programs you download MUST have an entry point at ENTRY_POINT, if only as a jump instruction to somewhere else.
;    If the user program uses NMI or IRQs, it is responsible for writing the RAM "shadow" vectors at RUN-TIME prior to enabling interrupts. This is because the hex monitor initializes them to a "sane" values pointing into the ROM monitor on every reset, so recovery from user program crashes is always possible.
;    A lot of nice things are missing. For example, no timeouts are provided since that would require support of additional timer hardware. It seems that if a download halts, pressing the big red RESET button is the right thing to do anyways. :) This is minimal bootstrap. It does the job needed and little more. 

; ($7FEB, $7FEA):	NMI RAM vector
; ($7FEF, $7FEE):       IRQ RAM vector
; (User program may not set a new RESET vector, or we could load
; an unrecoverable program into SRAM if battery backed, which would
; kill the system until the RAM was removed!)
;
;
; TIDE2VIA
;
;	
	FIFO_VIA_BASE = $7FE0	; TIDE VIA
	IORB	= 	FIFO_VIA_BASE + 0
	IORA	= 	FIFO_VIA_BASE + 1
	DDRB	=	FIFO_VIA_BASE + 2	; PB bitmap: 0=input 1git =output
	DDRA 	=	FIFO_VIA_BASE + 3	; PA bitmap: 0=input 1=output
	T1CL	=	FIFO_VIA_BASE + 4
	T1CH	=	FIFO_VIA_BASE + 5
	T1LL	=	FIFO_VIA_BASE + 6
	T1LH	=	FIFO_VIA_BASE + 7	
	T2CL	=	FIFO_VIA_BASE + 8
	T2CH	=	FIFO_VIA_BASE + 9
	SR	=	FIFO_VIA_BASE + 10
	ACR 	=	FIFO_VIA_BASE + 11
	PCR	=	FIFO_VIA_BASE + 12
	IFR	=	FIFO_VIA_BASE + 13
	IER	=	FIFO_VIA_BASE + 14
	IORA_NH	=	FIFO_VIA_BASE + 15


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
        jsr     INITSER         ; Set up baud rate, parity, etc.
        ; Download Intel hex.  The program you download MUST have its entry
        ; instruction (even if only a jump to somewhere else) at ENTRY_POINT.
HEXDNLD lda     #0
        sta     DLFAIL          ;Start by assuming no D/L failure
        jsr     PUTSTRI
        .text   13,10,13,10
        .text   "Send 6502 code in"
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