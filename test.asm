
; Assembled with 64TASS
; 		64tass -c bootloader.asm -L bootloader.lst
; 
;
; "Kernal"'s of truth:  We will replace these with our own code.
; Temporarily leaning on WDCmon for character I/O and 
; minimal controller initialization.  The 816 version will
; supply its own.  This 265 version will likely be abandoned
; at that point.
;
MON_GETC	= $00E036	; Get character
MON_PUTC	= $00E04B	; Put character
MON_ENTRY	= $00E0B0

CTRL_C	= 3
BS		= 8
LF		= 10
CR		= 13
SP		= 32

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

        .cpu    "65816"
        .as     			; A=8 bits
        .xl     			; X, Y = 16 bits

; Direct page fun
*=$20
TERM_FLAGS	.fill 	1						; Pick somewhere not used by WDCmon
	ECHO_FLAG	= MASK6						; Use bit 6 so BIT can be used
	
TEMP 	  	.byte	?	; May be used within any subroutine 

* = $3800
BUFPTR		.byte	?
			.byte 	?
CMDBUF 		.fill	254	
			;	 

* = $3000	; RAM load address
START 		CLC	
			XCE							; Native mode
			SEP		#(M_FLAG)			; A,M = 8bit
			REP		#(X_FLAG | D_FLAG)	; 16 bit index, binary math
MONITOR		LDA		#ECHO_FLAG			; Turn on ECHO
			STA		TERM_FLAGS			; Set ECHO bit 6
			LDY		#QBFMSG
			JSL		PUT_STR
			JSL		GET_CHR
			CMP		#CTRL_C
			BNE		MONITOR
			BRK							; back to monitor
			
PUT_STR		LDA		0,Y				; X points directly to string
			BEQ		PUTSX
			JSL		MON_PUTC			; print the character
			INY							; point to next character
			BRA		PUT_STR		
PUTSX:		RTL

GETLINE		LDX		#CMDBUF	
GSLP1		JSL		GET_CHR				; With or without echo
			CMP		#LF
			BEQ		GSLP1
			CMP		#BS					; We will not tolerate BS here
			BEQ		GSLP1
			STA		0,X					; store it	
			INX
			CMP		#CR					;
			BEQ		GSXIT1
			CMP		#CTRL_C
			BNE		GSLP1
			LDX		#CMDBUF+1
GSXIT1		DEX							; discard the CR
GSXIT2		STZ		0,X					; null-terminate the line
			RTL
			
GET_CHR	    JSL		MON_GETC
			BIT		TERM_FLAGS			; Check for ECHO flag (b7)
			BVC		GCHC1				; Bit 6 = ECHO
			JSL		MON_PUTC			; echo on; repeat it back
GCHC1		CMP		#CTRL_C
			BNE		GCHC2
			JML		MON_ENTRY			; Bail out to build-in WDCmon immediately!
GCHC2		RTL


QBFMSG	.text 		CR,CR
	.text	"              TARGET PROGRAM @$003000",CR
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
        .text   "             `    G.m-'^m'm'",CR
	.text   ">"
    .text	0