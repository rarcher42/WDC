	*= $2000

	; VIA registers
	MMU_MEM_CTRL = $0001
	MMU_IO_CTRL = $0001

	TEXT_BASE = $C000			; Note: This is in I/O page 2
	COLOR_CHOICE_BASE = TEXT_BASE		; Note: This is in I/O page 3

	FG_LUT_BASE = $D800
	BG_LUT_BASE = $D840
	CLUT_SIZE = 4


	BLUE_OFFSET = 0
	GREEN_OFFSET = 1
	RED_OFFSET = 2
	ALPHA_OFFSET = 3


start
	lda MMU_IO_CTRL
	pha			; Save entry I/O page mapping
	; Set up foreground and backgrond color LUT entries
	lda #$02		; Set I/O page to 2
	sta MMU_IO_CTRL
	; Set up a foreground and background entry
	stz FG_LUT_BASE+1*CLUT_SIZE+BLUE_OFFSET		; Foreground(1) Blue = $00
	lda #$80		; BGR= $008080 (yellow)
	sta FG_LUT_BASE+1*CLUT_SIZE+GREEN_OFFSET	
	sta FG_LUT_BASE+1*CLUT_SIZE+RED_OFFSET
	lda #$FF
	sta BG_LUT_BASE+0*CLUT_SIZE+BLUE_OFFSET		; Background(0)=$FF0000 = Blue
	stz BG_LUT_BASE+0*CLUT_SIZE+GREEN_OFFSET
	stz BG_LUT_BASE+0*CLUT_SIZE+RED_OFFSET		
	
	ldx #$FF
	lda #'*'
nextchar
	sta TEXT_BASE,x		; Store character in first 256 bytes of text buffer memory
	dex
	bne nextchar	
	
	lda #$03		; Set I/O page to 3
	sta MMU_IO_CTRL		
	ldx #$FF		; Now fill in color table to FG=1 BG=0 ($10)
	lda #$10
nextcolor
	sta COLOR_CHOICE_BASE,x
	dex
	bne nextcolor 		
	
	pla			; restore entry I/O page mapping
	sta MMU_IO_CTRL

loop
	bra loop
	rts

