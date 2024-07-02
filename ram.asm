
; Assembled with 64TASS
; 		64tass -c bootloader.asm -L bootloader.lst
; 
;
; "Kernal"'s of truth:
;
GET_CHR 	= $E036
GET_CHR_ECHO 	= $E03C
PUT_CHR		= $E04B
PUT_STR		= $E04E
MONITOR_ENTRY	= $E0B0

LF		= 10
CR		= 13

*= $2000	; RAM load address
	.cpu 	"65816"
	.as	; A=8 bits
	.xl	; X, Y = 16 bits

START   	LDA	#$00		; Page# = 0
		LDX	#QBFMSG
		JSL	PUT_STR		; Print the string at A:X
		LDA	#0
		LDX	#ANYKEY		
		JSL	PUT_STR
		JSL	GET_CHR_ECHO	; Read in the ANY key
		JML	MONITOR_ENTRY



QBFMSG	.text 	CR,CR
	.text 	"          ******************************",CR
	.text 	"          *                            *",CR
	.text 	"          *    The Quick brown Dog     *",CR
	.text 	"          *  Jumps over the Lazy Fox!  *",CR
	.text 	"          *                            *",CR
	.text 	"          ******************************",CR

 	.text	"        _,-=._              /|_/|",CR
 	.text	"       *-.}   `=._,.-=-._.,  @ @._,",CR
 	.text   "          `._ _,-.   )      _,.-'",CR
        .text   "             `    G.m-'^m'm'        Dmytro O. Redchuk",CR
        .text	0

ANYKEY:	.text	LF,LF
	.text 	"Press the ANY key to return to monitor:"
	.text	0

