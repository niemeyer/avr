#include "avr/io.h"

.set F_CPU, 1000000

.altmacro

.section .data,"aw",@progbits

relay_delay_table:
	.byte 25 ; seconds
	.byte 35
	.byte 45
	.byte 55

.section .text

; Register usage per gcc-avr conventions:
;
; Call-used (may be changed):     r0 (temp), r18–r27, r30, r31, T-Flag (SREG)
; Call-saved (must be preserved): r1 (zero), r2–r17, r28, r29

; Port and bit number for the button.
.set BTNPORT, _SFR_IO_ADDR(PORTD)
.set BTNPIN, BTNPORT-2
.set BTNBIT, 6

; Port and starting bit number for the leds.
.set LED1PORT, _SFR_IO_ADDR(PORTC)
.set LED2PORT, _SFR_IO_ADDR(PORTC)
.set LED3PORT, _SFR_IO_ADDR(PORTC)
.set LED4PORT, _SFR_IO_ADDR(PORTC)
.set LED1BIT, 2
.set LED2BIT, 3
.set LED3BIT, 4
.set LED4BIT, 5

.set RELAY1PORT, _SFR_IO_ADDR(PORTC)
.set RELAY1PIN, RELAY1PORT-2
.set RELAY1BIT, 1

.set BUZZ1PORT, _SFR_IO_ADDR(PORTB)
.set BUZZ1PIN, BUZZ1PORT-2
.set BUZZ1BIT, 1

.set LONGPRESS, 250



; roll_level rolls around the current level selection.
.macro roll_level
	rcall do_roll_level
.endm
do_roll_level:
	; r8 = (r8+1)%4
	inc r8
	ldi r18, 4
	cp r8, r18
	brne .+2
	clr r8
	ret

; disable_leds turns all leds off.
.macro disable_leds
	rcall do_disable_leds
.endm
do_disable_leds:
	cbi LED1PORT, LED1BIT
	cbi LED2PORT, LED2BIT
	cbi LED3PORT, LED3BIT
	cbi LED4PORT, LED4BIT
	ret

; update_leds turns leds on/off according to the selected level.
.macro update_leds
	rcall do_update_leds
.endm
do_update_leds:
	disable_leds

	; Turn selected leds back on.
	ldi r30, pm_lo8(leds_sbi_addr_end)
	ldi r31, pm_hi8(leds_sbi_addr_end)
	ldi r18, 1   ; Z -= r8 + 1
	add r18, r8
	sub r30, r18
	sbci r31, 0
	ijmp
	sbi LED4PORT, LED4BIT
	sbi LED3PORT, LED3BIT
	sbi LED2PORT, LED2BIT
	sbi LED1PORT, LED1BIT
leds_sbi_addr_end:
	ret


; enable_timer enables the timer with prescaling of clock(IO)/8 (page 110).
.macro enable_timer
	ldi r18, (1<<CS01)
	out _SFR_IO_ADDR(TCCR0B), r18
.endm

; disable_timer disables the timer.
.macro disable_timer
	ldi r18, 0
	out _SFR_IO_ADDR(TCCR0B), r18
.endm

; test_timer_off sets the Z flag if the timer is off.
.macro test_timer_off
	in r18, _SFR_IO_ADDR(TCCR0B)
	andi r18, (1<<CS02)|(1<<CS01)|(1<<CS00)
.endm

; enable_relay turns the relay on.
.macro enable_relay
	sbi RELAY1PORT, RELAY1BIT
.endm

; disable_relay turns the relay off.
.macro disable_relay
	cbi RELAY1PORT, RELAY1BIT
.endm

; test_relay_on sets the Z flag if the relay is on.
.macro test_relay_on
	clz
	sbic RELAY1PIN, RELAY1BIT
	sez
.endm

; buzz turns the buzzer on for n<=255 milliseconds.
.macro buzz n
	sbi BUZZ1PORT, BUZZ1BIT
	ldi r18, n
	mov r9, r18
.endm

; update_buzz decrements the buzzer count and turns the buzzer off
; once the counter reaches zero.
.macro update_buzz
	or r9, r9
	breq .+6
	dec r9
	brne .+2
	cbi BUZZ1PORT, BUZZ1BIT
.endm

; powerdown_mode sets the sleep mode to powerdown (page 39).
.macro powerdown_mode
	ldi r18, (1<<SM1)|(1<<SE)
	out _SFR_IO_ADDR(SMCR), r18
.endm

; idle_mode sets the sleep mode to idle (page 39).
.macro idle_mode
	ldi r18, (1<<SE)
	out _SFR_IO_ADDR(SMCR), r18
.endm


.global PCINT2_vect
PCINT2_vect:
	; Save/restore status register (SREG) if main does anything interesting. (page 14)

	; If timer is on, nothing to do.
	test_timer_off
	breq .+2
	reti

	idle_mode ; Allow timer0.
	enable_timer
	update_leds
	buzz 50

	; Simulate a long press in progress, so no changes are done to the state.
	ldi r18, LONGPRESS
	mov r6, r18
	ldi r18, 1
	mov r7, r18

	reti


.global TIMER0_COMPA_vect
TIMER0_COMPA_vect:
	; Save/restore status register (SREG) if main does anything interesting. (page 14)
	; 4 clock cycles from interrupt setup (page 15)
	; 3 clock cycles from interrupt vector jmp 

	; Loop runs at 1kHz when timer is on.

	; Reset interrupt timer counter to zero.
	ldi r18, 0
	out _SFR_IO_ADDR(TCNT0), r18

	; Update time tracking registers.
	inc r2
	ldi r18, 200
	cp  r2, r18
	brne time_updated
	clr r2
	inc r3
	ldi r18, 5
	cp  r3, r18
	brne time_updated
	clr r3
	inc r4
time_updated:

	update_buzz
	
	; Load new button state (pin low=pressed, tracked as r7=1).
	mov r20, r7
	clr r7
	sbis BTNPIN, BTNBIT
	inc r7

	; If button state has changed, reset button timer.
	cp r7, r20
	brne button_changed

	; Increment button-state timer.
	; Actions possible after 50ms without state change.
	inc r5
	ldi r18, 50
	cp  r5, r18
	brne button_done
	clr r5
	inc r6
	brne .+4     ; On overflow, put it back to 255.
	ldi r18, 255
	mov r6, r18

	; Handle button action.
	ldi r18, 0
	cp r7, r18
	breq button_released

	ldi r18, 20 ; ~1s
	cp r6, r18
	brsh button_longpressed

	; Normal press not handled until released.
	rjmp button_done

button_changed:
	ldi r18, 1
	cp r7, r18
	breq button_reset ; Button was just pressed.
	cp r6, r18
	brlo button_reset ; Button was pressed for less than 50ms.
	ldi r18, 250
	cp r6, r18
	brsh button_reset ; Button was long pressed.

	; Button pressed and released. Handle it.
	rjmp button_pressed

button_pressed:
	; If relay is on, just turn it off.
	test_relay_on
	brne relay_already_off
	disable_relay
	rjmp button_done
relay_already_off:

	roll_level
	update_leds
	rjmp button_done

button_longpressed:
	; Track long press with a constant.
	ldi r18, LONGPRESS
	cp  r6, r18
	mov r6, r18
	brsh button_done

	; Reset time tracking.
	clr r2
	clr r3
	clr r4

	sbi RELAY1PORT, RELAY1BIT

	buzz 200

	rjmp button_done

button_released:
	rjmp button_done

button_reset:
	; Start over button-pressed timer.
	clr r5
	clr r6

button_done:

	; If button is pressed for 50ms (r6 is 1), buzz (long press or not).
	ldi r18, 1
	cp r7, r18
	brne buzz_updated
	cp r6, r18
	brne buzz_updated
	buzz 50
buzz_updated:

	; If relay is on for long enough, turn it off.
	test_relay_on
	brne relay_updated
	ldi r30, lo8(relay_delay_table)
	ldi r31, hi8(relay_delay_table)
	add r30, r8
	adc r31, r1
	ld r18, Z
	cp r4, r18
	brne relay_updated
	disable_relay
relay_updated:

	; If relay off, button not pressed, and idle for long enough, turn leds and timer off.
	test_relay_on
	breq idle_updated
	ldi r18, 0
	cp r7, r18
	brne idle_updated
	ldi r18, 255
	cp r6, r18
	brne idle_updated
	disable_leds
	disable_timer
	powerdown_mode ; Disable timers too.
idle_updated:

	reti

main:
	; Fixed zero, per avr-gcc convention.
	clr r1

	; Reset time-tracking registers.
	clr r2 ; second / 200 / 25
	clr r3 ; second / 25
	clr r4 ; second

	; Reset button-pressing timer.
	clr r5 ; ms since last change (0-50ms)
	clr r6 ; 50ms slots since last change
	clr r7 ; last state: 0=released, 1=pressed

	; Level selection.
	clr r8

	; Set led, buzzer, and relay pins as output.
	sbi LED1PORT-1, LED1BIT
	sbi LED2PORT-1, LED2BIT
	sbi LED3PORT-1, LED3BIT
	sbi LED4PORT-1, LED4BIT
	sbi BUZZ1PORT-1, BUZZ1BIT
	sbi RELAY1PORT-1, RELAY1BIT

	; Turn led for level r8=0 on.
	;sbi LED1PORT, LED1BIT

	; Pull button pin high.
	sbi BTNPORT, BTNBIT

	; Enable interrupts on PCINT22 (PD6) (page 73/74)
	ldi r18, (1 << PCIE2)
	sts PCICR, r18
	ldi r18, (1 << PCINT22)
	sts PCMSK2, r18

	; Enable interrupt on comparison matches (page 111).
	ldi r18, (1<<OCIE0A)
	sts TIMSK0, r18

	; Generate an interrupt when the timer reaches 125 (1MHz / prescaling 8 / 125 == 1ms) (page 110).
	ldi r18, 125
	out _SFR_IO_ADDR(OCR0A), r18

	; Only turn timer on when a button interrupt is received.
	powerdown_mode

	; Enable interrupts.
	sei

	sleep
	rjmp .-4


.global main
.global __do_copy_data
.global __do_clear_bss
