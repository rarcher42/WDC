; TIDE2VIA	the system VIA.  Used by many and defined globally
; IO for the VIA which is used for the USB debugger interface.
SYS_VIA_BASE	    = 	$7FE0
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

DEBUG_VIA_BASE	    = 	$7FC0
DEBUG_VIA_IORB     =  	DEBUG_VIA_BASE+0	; Port B IO register
DEBUG_VIA_IORA     =	DEBUG_VIA_BASE+1 	; Port A IO register
DEBUG_VIA_DDRB     = 	DEBUG_VIA_BASE+2	; Port B data direction register
DEBUG_VIA_DDRA     = 	DEBUG_VIA_BASE+3	; Port A data direction register
DEBUG_VIA_T1C_L    =	DEBUG_VIA_BASE+4 	; Timer 1 counter/latches, low-order
DEBUG_VIA_T1C_H    = 	DEBUG_VIA_BASE+5	; Timer 1 high-order counter
DEBUG_VIA_T1L_L    = 	DEBUG_VIA_BASE+6	; Timer 1 low-order latches
DEBUG_VIA_T1L_H    = 	DEBUG_VIA_BASE+7	; Timer 1 high-order latches
DEBUG_VIA_T2C_L    = 	DEBUG_VIA_BASE+8	; Timer 2 counter/latches, lower-order
DEBUG_VIA_T2C_H    = 	DEBUG_VIA_BASE+9	; Timer 2 high-order counter
DEBUG_VIA_SR       = 	DEBUG_VIA_BASE+10	; Shift register
DEBUG_VIA_ACR      = 	DEBUG_VIA_BASE+11	; Auxilliary control register
DEBUG_VIA_PCR      =	DEBUG_VIA_BASE+12	; Peripheral control register
DEBUG_VIA_IFR	    =	DEBUG_VIA_BASE+13 ; Interrupt flag register
DEBUG_VIA_IER      = 	DEBUG_VIA_BASE+14	; Interrupt enable register
DEBUG_VIA_ORA_IRA  =	DEBUG_VIA_BASE+15	; Port A IO register, but no handshake

; System VIA Port B named bitmasks
PB0 = MASK0
PB1 = MASK1
PB2 = MASK2
PB3 = MASK3
PB4 = MASK4
PB5 = MASK5
PB6 = MASK6
PB7 = MASK7
; System VIA Port A named bitmasks
PA0 = MASK0
PA1 = MASK1
PA2 = MASK2
PA3 = MASK3
PA4 = MASK4
PA5 = MASK5
PA6 = MASK6
PA7 = MASK7