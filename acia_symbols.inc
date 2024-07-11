;;; ============================= 65c51 UART functions ======================================
; 65C51 ACIA equates for serial I/O
;
ACIA_BASE = $7F80		; This is where the 6551 ACIA starts
SDR = ACIA_BASE       		; RX'ed bytes read, TX bytes written, here
SSR = ACIA_BASE+1     		; Serial data status register
SCMD = ACIA_BASE+2     		; Serial command reg. ()
SCTL = ACIA_BASE+3     		; Serial control reg. ()
TX_RDY = MASK4
RX_RDY = MASK3


ALL_INPUTS = $00
ALL_OUTPUTS = $FF