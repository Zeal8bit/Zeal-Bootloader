CC=$(shell which z88dk-z80asm z88dk.z88dk-z80asm | head -1)
BIN=bootloader.bin
MAP=bootloader.map
CONFIG_FILE := include/config.asm

# Process the config file to include only lines of the form 'CONFIG_... = ..' and save them to
# a file named 'bootloader.conf'
$(shell grep -o 'CONFIG_.*=.*' $(CONFIG_FILE) > bootloader.config)
-include bootloader.config

# When ACK_CONTINUE is set, a message will always be displayed before redrawing the main menu
ASMFLAGS=-Iinclude/
FILES=rst_vectors.asm boot.asm uart.asm systems.asm pio.asm menu.asm format.asm i2c.asm

# SRCS must be lazily evaluated since it depends FILES, which may be altered below
SRCS=$(addprefix src/,$(FILES))
DISASSEMBLER=$(shell which z88dk-dis z88dk.z88dk-dis | head -1)
BUILDIR=build

ifeq ($(CONFIG_ENABLE_TESTER),1)
	FILES += tester.asm
endif

ifneq ($(CONFIG_UART_AS_STDOUT),1)
	FILES += video.asm keyboard.asm
endif

define FIND_ADDRESS =
	grep "__SYS_TABLE_head" $(BUILDIR)/src/*.map | cut -f2 -d$$ | cut -f1 -d\;
endef

phony: all clean

# We need to build all the source files and then merge the resulting bootloader binary with the system/os table,
# which address needs to be retrieved dynamically
all: clean version.txt
	$(CC) -O$(BUILDIR) $(ASMFLAGS) -m -b $(SRCS)
	@# Retrieve the address for the SYS_TABLE. Here is becomes... weird, $(call FIND_ADDRESS) will be replace
	@# by the macro itself, we need to interpret it at runtime, so we surround it with $$(...).
	./concat.sh $(BUILDIR)/$(BIN) 0 $(BUILDIR)/src/rst_vectors_RST_VECTORS.bin 0x$$($(call FIND_ADDRESS)) $(BUILDIR)/src/*SYS_TABLE.bin
	@# Copy the map file to the `build/` directory
	cp $(BUILDIR)/src/*.map $(BUILDIR)/$(MAP)

version.txt:
	@echo `git describe --always --tags` > version.txt

clean:
	rm -rf build/ version.txt