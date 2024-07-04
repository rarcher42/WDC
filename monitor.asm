
; Assembled with 64TASS
; 		64tass -c bootloader.asm -L bootloader.lst
; 
;
; "Kernal"'s of truth:
;
MON_GETC	= $E036	; Get character
MON_PUTC	= $E04B	; Put character
MON_ENTRY	= $E0B0

CTRL_C		= 3
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
        .as     ; A=8 bits
        .xl     ; X, Y = 16 bits

; Direct page fun
	.org $0030
TERM_FLAGS	.byte 	0
STACKTOP	= $6FFF				; Put stack near top of RAM

* = $2000	; RAM load address
START 		CLC	
		XCE				; Native mode
		SEP	#(M_FLAG)		; A,M = 8bit
		REP	#(X_FLAG | D_FLAG)	; 16 bit index, binary math
		; LDX	#STACKTOP
		; TXS				; Set stack to STACKTOP
	        LDA	#$80
		STA	TERM_FLAGS	; For now, just ECHO bit 7
REPEAT	        LDX	#QBFMSG
		JSR	PUT_STR		; Print the string at A:X
		LDX	#ANYKEY		
		JSR	PUT_STR
		JSR	GET_CHR_ECHO	; Read in the ANY key
		CMP	#CTRL_C		; SPACE key is the ANY key
		BNE	REPEAT
		BRK
		.byte	$EA
		
PUT_STR		LDA	0,X		; X points directly to string
		BEQ	PUTSX
		JSL	MON_PUTC	; print the character
		INX			; point to next character
		BRA	PUT_STR		
PUTSX:		RTS

GET_CHR	        JSL	MON_GETC
		BIT	TERM_FLAGS	; Check for ECHO flag (b7)
		BPL	GCHC1
		JSL	MON_PUTC	; echo it back
GCHC1		RET

QBFMSG	.text 	CR,CR
	.text	"                  VCBmon v 1.00",CR
	.text 	"          ******************************",CR
	.text 	"          *                            *",CR
	.text 	"          *    The Quick brown Dog     *",CR
	.text 	"          *  Jumps over the Lazy Fox!  *",CR
	.text 	"          *                            *",CR
	.text 	"          ******************************",CR

 	.text	"        _,-=._              /|_/|",CR
 	.text	"       *-.}   `=._,.-=-._.,  @ @._,",CR
 	.text   "          `._ _,-.   )      _,.-'",CR
        .text   "             `    G.m-'^m'm'",CR
	.text   "          Foxy art by: Dmytro O. Redchuk",CR,CR
        .text	0

ANYKEY:	.text	LF,LF
	.text 	"Press the ANY key (CTRL-C) to return to monitor",CR
	.text   "else continue foxing:"
	.text	0

