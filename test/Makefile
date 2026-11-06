# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info
#
#   make                  RTL simulation, all tests
#   make GATES=yes        gate-level simulation of gate_level_netlist.v
#   make COCOTB_TEST_MODULES=test_soc COCOTB_TEST_FILTER=test_boot_hello   one test

# defaults
SIM ?= icarus
FST ?= -fst # Use more efficient FST format
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../src
PROJECT_SOURCES = project.v timer.v \
                  tinyQV/cpu/tinyqv.v tinyQV/cpu/alu.v tinyQV/cpu/core.v tinyQV/cpu/counter.v \
                  tinyQV/cpu/cpu.v tinyQV/cpu/decode.v tinyQV/cpu/mem_ctrl.v tinyQV/cpu/qspi_ctrl.v \
                  tinyQV/cpu/register.v tinyQV/peri/uart/uart_tx.v tinyQV/peri/uart/uart_rx.v

ifneq ($(GATES),yes)

# RTL simulation:
SIM_BUILD				= sim_build/rtl
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))
COMPILE_ARGS    += -DSIM

else

# Gate level simulation:
SIM_BUILD				= sim_build/gl
COMPILE_ARGS    += -DGL_TEST
COMPILE_ARGS    += -DFUNCTIONAL
COMPILE_ARGS    += -DUSE_POWER_PINS
COMPILE_ARGS    += -DSIM
COMPILE_ARGS    += -DUNIT_DELAY=\#1
VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/primitives.v
VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v

# this gets copied in by the GDS action workflow
VERILOG_SOURCES += $(PWD)/gate_level_netlist.v

endif

# Allow sharing configuration between design and testbench via `include`:
COMPILE_ARGS 		+= -I$(SRC_DIR)

# Include the testbench sources (QSPI Pmod model from upstream TinyQV):
VERILOG_SOURCES += $(PWD)/tb.v $(PWD)/sim_qspi.v
TOPLEVEL = tb

# Firmware image loaded into the flash model (built by ../firmware, copied here)
COMPILE_ARGS    += -DFW_HEX=\"rvsoc_fw.hex\"

# Debug defines, e.g. make EXTRA_DEFINES="-DTRACE_FETCH -DTRACE_TIMER"
COMPILE_ARGS    += $(EXTRA_DEFINES)

# List test modules to run, separated by commas and without the .py suffix:
COCOTB_TEST_MODULES ?= test_soc,test_isa_random

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim
