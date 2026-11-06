# FPGA test harness for tt_um_santhosh_rvsoc on PYNQ-Z2 / PYNQ-Z1
#
#   make sim       simulate the whole FPGA design (iverilog), expects "[tb_fpga] PASS"
#   make synth     open-source synthesis check for xc7z020 (Yosys in the LibreLane container)
#   make bit       build the bitstream with Vivado (vivado must be on PATH)
#   make program   program the board over JTAG with Vivado

ROOT     := $(abspath ..)
SRC      := $(ROOT)/src
CHIP_SRC := $(SRC)/project.v $(SRC)/timer.v $(wildcard $(SRC)/tinyQV/cpu/*.v) \
            $(SRC)/tinyQV/peri/uart/uart_tx.v $(SRC)/tinyQV/peri/uart/uart_rx.v
FPGA_SRC := rtl/qspi_pmod_emu.v rtl/uart_watch.v pynq_z2/top_pynq_z2.v
FW_HEX   := $(ROOT)/firmware/build/rvsoc_fw.hex
NIB_HEX  := build/rvsoc_fw_nibbles.hex
LIBRELANE_IMAGE ?= ghcr.io/librelane/librelane:3.0.14

all: sim

build:
	mkdir -p build

$(NIB_HEX): $(FW_HEX) tools/hex2nib.py | build
	python3 tools/hex2nib.py $(FW_HEX) $@

$(FW_HEX):
	$(MAKE) -C $(ROOT)/firmware

# TinyQV's register file uses `buf #1` (simulation-only delay) in files without a
# `timescale, so give them the same 1 ns default that cocotb uses.
sim: $(NIB_HEX)
	echo "+timescale+1ns/1ps" > build/cmds.f
	cd build && iverilog -g2012 -DSIM -f cmds.f -o tb_fpga.vvp -s tb_fpga \
	    $(CHIP_SRC) $(addprefix ../,$(FPGA_SRC)) ../sim/tb_fpga.v
	cd build && vvp -n tb_fpga.vvp -fst | tee sim.log
	grep -q "\[tb_fpga\] PASS" build/sim.log

# Synthesis-only sanity check (catches unsupported constructs, reports LUT/FF/BRAM use)
synth: $(NIB_HEX)
	docker run --rm -v $(ROOT):$(ROOT) -w $(CURDIR)/build $(LIBRELANE_IMAGE) \
	    yosys -q -l yosys_xc7.log -p "read_verilog -DYOSYS_XC7 $(CHIP_SRC) $(addprefix $(CURDIR)/,$(FPGA_SRC)); \
	    synth_xilinx -family xc7 -top top_pynq_z2; stat" >/dev/null
	grep -A40 "=== top_pynq_z2 ===" build/yosys_xc7.log | grep -E "Number of cells|LUT|FD|RAMB|CARRY|MUX" || tail -40 build/yosys_xc7.log

bit: $(NIB_HEX)
	vivado -mode batch -nojournal -log build/vivado.log -source pynq_z2/build_vivado.tcl \
	    -tclargs $(ROOT) $(CURDIR)/$(NIB_HEX)

program:
	vivado -mode batch -nojournal -log build/program.log -source pynq_z2/program_vivado.tcl \
	    -tclargs $(CURDIR)/build/rvsoc_pynq_z2.bit

clean:
	rm -rf build

.PHONY: all sim synth bit program clean
