;;; ============================= 65c51 UART functions ======================================
; 65C51 ACIA equates for serial I/O
;
ACIA_BASE = $7F80		; This is where the 6551 ACIA starts
ACIA_SDR = ACIA_BASE       		; RX'ed bytes read, TX bytes written, here
ACIA_SSR = ACIA_BASE+1     		; Serial data status register
ACIA_SCMD = ACIA_BASE+2     		; Serial command reg. ()
ACIA_SCTL = ACIA_BASE+3     		; Serial control reg. ()
TX_RDY = MASK4
RX_RDY = MASK3
