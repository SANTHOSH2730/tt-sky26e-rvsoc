# Firmware for tt_um_santhosh_rvsoc (RV32EC, executes from QSPI flash)
#   make            -> build/rvsoc_fw.{elf,bin,hex,lst}
# Toolchain: xPack riscv-none-elf-gcc (installed by scripts/check_env.sh)

PREFIX  ?= riscv-none-elf-
CC      = $(PREFIX)gcc
OBJCOPY = $(PREFIX)objcopy
OBJDUMP = $(PREFIX)objdump
SIZE    = $(PREFIX)size

ARCH    = -march=rv32ec_zicsr -mabi=ilp32e
CFLAGS  = $(ARCH) -Os -g -ffreestanding -fno-builtin -nostdlib -nostartfiles \
          -ffunction-sections -fdata-sections -msmall-data-limit=0 -mno-relax \
          -Wall -Wextra -Werror
LDFLAGS = $(ARCH) -nostdlib -nostartfiles -mno-relax -T link.ld \
          -Wl,--gc-sections -Wl,-Map,build/rvsoc_fw.map

SRCS = start.S isa_test.S main.c
OUT  = build/rvsoc_fw

all: $(OUT).elf $(OUT).bin $(OUT).hex $(OUT).lst size

build:
	mkdir -p build

$(OUT).elf: $(SRCS) rvsoc.h link.ld | build
	$(CC) $(CFLAGS) $(LDFLAGS) $(SRCS) -o $@

$(OUT).bin: $(OUT).elf
	$(OBJCOPY) -O binary $< $@

# Byte-per-entry Verilog hex ($readmemh) for the flash models (sim and FPGA)
$(OUT).hex: $(OUT).elf
	$(OBJCOPY) -O verilog $< $@

$(OUT).lst: $(OUT).elf
	$(OBJDUMP) -d -M no-aliases $< > $@

size: $(OUT).elf
	$(SIZE) $<

clean:
	rm -rf build

.PHONY: all size clean
