
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
MON_GETC	= $E036	; Get character
MON_PUTC	= $E04B	; Put character
MON_ENTRY	= $E0B0

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
TERM_FLAGS	= $0030						; Pick somewhere not used by WDCmon
ECHO_FLAG	= MASK6						; Use bit 6 so BIT can be used
STACKTOP	= $6FFF						; Put stack near top of RAM
* = $2800	
BUFPTR		.byte	?
			.byte 	?
CMDBUF 		.fill	254					;	 

* = $2000	; RAM load address
START 		CLC	
			XCE							; Native mode
			SEP		#(M_FLAG)			; A,M = 8bit
			REP		#(X_FLAG | D_FLAG)	; 16 bit index, binary math
			LDA		#ECHO_FLAG			; Turn on ECHO
			STA		TERM_FLAGS			; For now, just ECHO bit 6
REPEAT		LDX		#PROMPT
			JSR		PUT_STR
			JSR		GETLINE				; Get the next line
			JSR		CRLF
			LDA		#'"'
			JSL		MON_PUTC
			LDX		#CMDBUF
			JSR		PUT_STR
			LDA		#'"'
			JSL		MON_PUTC
			JSR		CRLF
			BRA		REPEAT
			



GETLINE		LDX		#CMDBUF	
GSLP1		JSR		GET_CHR				; With or without echo
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
			RTS
			
			
PUT_STR		LDA		0,X					; X points directly to string
			BEQ		PUTSX
			JSL		MON_PUTC			; print the character
			INX							; point to next character
			BRA		PUT_STR		
PUTSX:		RTS

GET_CHR	    JSL		MON_GETC
			BIT		TERM_FLAGS	; Check for ECHO flag (b7)
			BVC		GCHC1		; Bit 6 = ECHO
			JSL		MON_PUTC	; echo on; repeat it back
GCHC1		RTS

CRLF		LDA		#CR
			JSL		MON_PUTC
			LDA		#LF
			JSL		MON_PUTC
			RTS
			
PUTHEX  	PHA             	;
        	LSR 	A
        	LSR 	A
			LSR 	A
			LSR 	A
        	JSR     PRNIBL
        	PLA
PRNIBL  	AND     #$0F    	; strip off the low nibble
        	CMP     #$0A
        	BCC  	NOTHEX  	; if it's 0-9, add '0' else also add 7
        	ADC     #6      	; Add 7 (6+carry=1), result will be carry clear
NOTHEX  	ADC     #'0'    	; If carry clear, we're 0-9
; Write the character in A as ASCII:
PUTCH		JSL		MON_PUTC
			RTS

QBFMSG	.text 		CR,CR
	.text	"                  VCBmon v 1.00",CR
	.text 	"          ******************************",CR
	.text 	"          *                            *",CR
	.text 	"          *    The Quick brown Dog     *",CR
	.text 	"          *  Jumps over the Lazy Fox!  *",CR
	.text 	"          *                            *",CR
	.text 	"          ******************************",CR

 PROMPT	
	.text	"        _,-=._              /|_/|",CR
 	.text	"       *-.}   `=._,.-=-._.,  @ @._,",CR
 	.text   "          `._ _,-.   )      _,.-'",CR
        .text   "             `    G.m-'^m'm'",CR
	.text   ">"
    .text	0
	
ANYKEY:	.text	LF,LF
	.text 	"Press the ANY key (CTRL-C) to return to monitor",CR
	.text   "else continue foxing:"
	.text	0

