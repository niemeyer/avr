#include "avr/io.h"

.set F_CPU, 1000000

.altmacro

.section .text

; Register usage per gcc-avr conventions:
;
; Call-used (may be changed):     r0 (temp), r18–r27, r30, r31, T-Flag (SREG)
; Call-saved (must be preserved): r1 (zero), r2–r17, r28, r29

main:
	; Set inverse OC1B pin as output for the led.
	sbi _SFR_IO_ADDR(DDRB), 3

	; Enable timer TC1 with PCK/16k prescaling (attiny85 p.89)
	ldi r18, (1<<CS10)|(1<<CS11)|(1<<CS12)|(1<<CS13)
	out _SFR_IO_ADDR(TCCR1), r18

	; Set OC1B on compare match (250), clear on 0x00 (attiny85 p.86,90)
	ldi r18, (1<<PWM1B) | (1<<COM1B0)
	out _SFR_IO_ADDR(GTCCR), r18
	ldi r18, 250
	out _SFR_IO_ADDR(OCR1B), r18

	; Set the sleep mode to idle (attiny85 p.39).
	ldi r18, (1<<SE)
	out _SFR_IO_ADDR(MCUCR), r18

	; Shutdown unnecessary MCU modules (attiny85 p.38)
	ldi r18, (1<<PRTIM0)|(1<<PRUSI)|(1<<PRADC)
	out _SFR_IO_ADDR(PRR), r18

	sleep
	rjmp .-4


.global main
.global __do_copy_data
.global __do_clear_bss
