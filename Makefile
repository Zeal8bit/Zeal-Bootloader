CC=z88dk-z80asm
BIN=bootloader.bin
DUMP=bootloader.dump
FILES=rst_vectors.asm boot.asm uart.asm systems.asm video.asm menu.asm
SRCS=$(addprefix src/,$(FILES))
DISASSEMBLER=$(shell which z88dk-dis z88dk.z88dk-dis | head -1)
BUILDIR=build

define FIND_ADDRESS =
	grep "__SYS_TABLE_head" $(BUILDIR)/src/*.map | cut -f2 -d$$ | cut -f1 -d\;
endef

phony: all clean

# First, we need to build all the source files
# Then move and rename the main binary code to $(BUILDIR)/$(BIN)
# Finally, merge the system/os table to it, its address needs to be retrieved dynamically
all: clean version.txt 
	$(CC) -O$(BUILDIR) -Iinclude/ -m -b $(SRCS)
	cp $(BUILDIR)/src/rst_vectors_RST_VECTORS.bin $(BUILDIR)/$(BIN)
	@# Retrieve the address for the SYS_TABLE. Here is becomes... weird, $(call FIND_ADDRESS) will be replace
	@# by the macro itself, we need to interpret it at runtime, so we surround it with $$(...)
	@# This gives us a hex value, truncate only accepts decimal values so we surround it with $$((...)) to let
	@# bash interpret it to a decimal value
	@truncate -s $$((0x$$($(call FIND_ADDRESS)))) $(BUILDIR)/$(BIN)
	@# Concatenate the SYS_TABLE
	cat $(BUILDIR)/src/*SYS_TABLE.bin >> $(BUILDIR)/$(BIN)
	@# Generate the disassebmly dump for debugging
	$(DISASSEMBLER) -x $(BUILDIR)/src/*.map $(BUILDIR)/$(BIN) > $(BUILDIR)/$(DUMP)

version.txt:
	@echo `git describe --always --tags` > version.txt

clean:
	rm -rf build/ version.txt