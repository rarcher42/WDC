
; Assembled with 64TASS
; 		64tass -c bootloader.asm -L bootloader.lst
; 
;
; "Kernal"'s of truth:
;
CTRL_C	= 3
LF		= 10
CR		= 13
SP		= 32


; Monitor hooks - These we MUST JSL to
RAW_GETC = $00E036
RAW_PUTC = $00E04B
FAKEMON  = $002000


			.cpu 	"65816"
			.as					; A=8 bits
			.xl					; X, Y = 16 bits

* = $6000		; RAM load address
START 		
			LDY		#MSG_FOXRAM
			JSR		PUT_STR
POINTLESS	JSL		RAW_GETC
			CMP		#CTRL_C
			BNE		START	
			JML		FAKEMON

; Point Y to null-terminated string
PUT_STR		
			LDA	0,Y				; Y points directly to string
			BEQ	PUTSX
			JSL	RAW_PUTC
			INY						; point to next character
			BRA	PUT_STR		
PUTSX		
			RTS	

MSG_FOXRAM
	.text 	CR,CR
	.text	"        I YAM RUNNING INDA RAM!",CR
 	.text	"        _,-=._              /|_/|",CR
 	.text	"       *-.}   `=._,.-=-._.,  @ @._,",CR
 	.text   "          `._ _,-.   )      _,.-'",CR
    .text   "             `    G.m-'^m'm'",CR
	.text   "          Foxy art by: Dmytro O. Redchuk",CR,CR
	.text   " CTRL-C to return to WDC Monitor",CR
    .text	0

