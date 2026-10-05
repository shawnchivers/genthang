#
# The xPack GNU RISC-V Embedded GCC
# https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack
#
TARGET_ELF = firmware.elf
TARGET_BIN = firmware.bin
#RISCV = /opt/xpack-riscv-none-elf-gcc-13.2.0-2/bin/riscv-none-elf
# Other toolchains: make RISCV=/usr/bin/riscv64-unknown-elf EXTRA_CFLAGS="-isystem <libc include dir>"
RISCV ?= /usr/local/xpack-riscv-none-embed-gcc-10.1.0-1.1/bin/riscv-none-embed
CC = $(RISCV)-gcc
OBJCOPY = $(RISCV)-objcopy
OBJDUMP = $(RISCV)-objdump
CFLAGS  = -Wall -O2 -g -mabi=ilp32 -march=rv32i -ffreestanding $(EXTRA_CFLAGS)
LFLAGS = -mabi=ilp32 -march=rv32i -Wl,--build-id=none,-Bstatic,-T,baremetal.ld -nostdlib
LIBS = -lgcc

SRCS := start.S firmware.c picorv32.c spi_sd.c spiflash.c fatfs/diskio.c fatfs/ff.c fatfs/ffunicode.c
OBJS := $(SRCS:.c=.o)
OBJS := $(OBJS:.S=.o)
HDRS := $(wildcard *.h)

ifeq ($(VERBOSE),1)
  Q =
else
  Q = @
endif

default: $(TARGET_BIN)
all: default

%.o: %.c $(HDRS)
ifneq ($(VERBOSE),1)
	@echo CC $@
endif
	$(Q)$(CC) $(CFLAGS) -c $< -o $@

%.o: %.S $(HDRS)
ifneq ($(VERBOSE),1)
	@echo CC $@
endif
	$(Q)$(CC) $(CFLAGS) -c $< -o $@

.PRECIOUS: $(TARGET_BIN) $(TARGET_ELF) $(OBJS)

$(TARGET_ELF): $(OBJS)
ifneq ($(VERBOSE),1)
	@echo CC $@
endif
	$(Q)$(CC) $(LFLAGS) $(OBJS) $(LIBS) -o $@

$(TARGET_BIN): $(TARGET_ELF)
ifneq ($(VERBOSE),1)
	@echo OBJCOPY $@
endif
	$(Q)$(OBJCOPY) $(TARGET_ELF) $(TARGET_BIN) -O binary

# 68000 save state stub as big-endian words (ss_stub.h is checked in)
M68K ?= m68k-linux-gnu
ss_stub.h: m68k/savestate.s
	$(Q)$(M68K)-as -m68000 --register-prefix-optional -o m68k/savestate.o $<
	$(Q)$(M68K)-ld -Ttext=0x400100 -e entry -o m68k/savestate.elf m68k/savestate.o
	$(Q)$(M68K)-objcopy -O binary m68k/savestate.elf m68k/savestate.bin
	$(Q)python3 -c 'import sys; b = open(sys.argv[1], "rb").read(); b += bytes(len(b) & 1); \
		w = [b[i] << 8 | b[i + 1] for i in range(0, len(b), 2)]; \
		print("// generated from m68k/savestate.s\nstatic const uint16_t ss_stub[%d] = {" % len(w)); \
		print(",\n".join("    " + ", ".join("0x%04x" % x for x in w[i:i + 8]) for i in range(0, len(w), 8))); \
		print("};")' m68k/savestate.bin > $@

clean:
	$(Q)rm -f $(OBJS) $(TARGET_ELF) $(TARGET_BIN)

.PHONY: default all clean
