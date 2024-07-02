;
; Ultra-basic bootloader.  Not yet working.
; R. Archer 6/2024
; Assembled with 64TASS
; 		64tass -c bootloader.asm -L bootloader.lst
; 
;
; AND masks for bit positions
MASK0	=	 %00000001
MASK1	=	 %00000010
MASK2	=	 %00000100
MASK3	=	 %00001000
MASK4	=	 %00010000
MASK5	=	 %00100000
MASK6	=	 %01000000
MASK7	=	 %10000000

; Zero page storage map
* = $20
DP_START	.byte	?
PTR_L		.byte	?	; Generic pointer
PTR_H		.byte	?
PTR_B		.byte	?
CTR_L		.byte	?	; Counter
CTR_H		.byte	?
CTR_B		.byte	?
SA_L		.byte 	?	; Starting address storage
SA_H		.byte 	?
SA_B		.byte	?
DATA_CNT	.byte 	?	; Count of record's actual storable data bytes
EXTRA		.byte	? 	; Used inside loader.  Otherwise, free for use
TEMP 	  	.byte	?	; May be used within any subroutine 

; TIDE2VIA	the system VIA.  Used by many and defined globally
; IO for the VIA which is used for the USB debugger interface.
SYS_VIA_BASE	    = $7FE0
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
ALL_INPUTS = $00
ALL_OUTPUTS = $FF


; "Kernal"'s of truth:
;
GET_CHR 	= $E036
GET_CHR_ECHO 	= $E03C
PUT_CHR		= $E04B
PUT_STR		= $E04E
MONITOR_ENTRY	= $E0B0

LF		= 10
CR		= 13

*= $2000	; Monitor start address
START   	LDX	#QBFMSG
		JSR	PRINT_AT_X
		LDX	#ANYKEY
		JSR	PRINT_AT_X
		JSR	GET_CHR_ECHO	; Await the ANY key...
		BRK			; return to monitor

; Print the string at *(X) 
PRINT_AT_X	LDA	$0000,X		; X points to the first byte on entry
		BEQ	PRAXIT		; We reached the terminating null
		JSR	PUT_CHR		; Write the character out
		INX
		BRA	PRINT_AT_X	; Get the next character	
PRAXIT		RTS	

QBFMSG	.text 	CR,CR
	.text	"               VCBmon-186 v0.01",CR,CR,CR
	.text 	"         ******************************",CR
	.text 	"         *                            *",CR
	.text 	"         *    The Quick brown Dog     *",CR
	.text 	"         *  Jumps over the Lazy Fox!  *",CR
	.text 	"         *                            *",CR
	.text 	"         ******************************",CR,CR

 	.text	"        _,-=._              /|_/|",CR
 	.text	"       *-.}   `=._,.-=-._.,  @ @._,",CR
 	.text   "          `._ _,-.   )      _,.-'",CR
        .text   "             `    G.m-'^m'm'",CR
        .text	0

ANYKEY:	.text	LF,LF
	.text 	"Press the ANY key to return to monitor:"
	.text	0


* = $FFFA
;  start at $FFFA
NMIENT  .word     START
RSTENT  .word     START
IRQENT  .word     START
.end
