
DEVICE=atmega328p
BURNER=buspirate
SERIAL=/dev/ttyUSB0

all: main.ihex

burn:
	avrdude -c $(BURNER) -p $(DEVICE) -P /dev/ttyUSB0 -U flash:w:main.ihex:i

clean:
	rm -f *.o *.elf *.ihex

%.ihex: %.elf
	avr-objcopy --output-target=ihex $< $@

%.elf: %.o
	avr-ld -o $@ $<

%.o: %.S
	avr-gcc -mmcu=$(DEVICE) -o $@ $<
