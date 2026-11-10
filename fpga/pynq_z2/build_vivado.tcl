# Vivado non-project build of the tt_um_santhosh_rvsoc FPGA harness for PYNQ-Z2 (xc7z020clg400-1).
#
#   vivado -mode batch -source build_vivado.tcl -tclargs <repo_root> <nibble_hex> [out_dir]
#
# <repo_root>  : the project folder (contains src/ and fpga/); forward slashes
# <nibble_hex> : flash image from fpga/tools/hex2nib.py (make -C fpga build/rvsoc_fw_nibbles.hex)
# [out_dir]    : where reports and the bitstream go (default <repo_root>/fpga/build)
#
# Outputs in out_dir:
#   rvsoc_pynq_z2.bit        the bitstream (JTAG, or Bitstream() on the PYNQ image)
#   top_pynq_z2_funcsim.v    post-route functional netlist (simulated with fpga/sim/tb_fpga_board.v)
#   top_pynq_z2_routed.dcp   routed checkpoint (open in the Vivado GUI to look at the layout)
#   *.rpt                    utilisation (flat and per module), timing, power, I/O, clocks, DRC

set root [lindex $argv 0]
set nib  [lindex $argv 1]
set out  [expr {[llength $argv] > 2 ? [lindex $argv 2] : "$root/fpga/build"}]
set part xc7z020clg400-1
file mkdir $out

# TinyQV's files declare ports without a net type, and project.v / timer.v set
# `default_nettype none, which Vivado carries into the files read after them:
# so TinyQV goes first.
set chip_src [concat \
    [lsort [glob $root/src/tinyQV/cpu/*.v]] \
    [list $root/src/tinyQV/peri/uart/uart_tx.v $root/src/tinyQV/peri/uart/uart_rx.v] \
    [list $root/src/timer.v $root/src/project.v]]
set fpga_src [list $root/fpga/rtl/qspi_pmod_emu.v $root/fpga/rtl/uart_watch.v $root/fpga/pynq_z2/top_pynq_z2.v]

# -sv: the RTL uses a few SystemVerilog constructs (e.g. a function without inputs in
# uart_rx.v), as Icarus (-g2012) and Yosys accept them.
read_verilog -sv $chip_src
read_verilog $fpga_src
read_xdc $root/fpga/pynq_z2/pynq_z2.xdc

# ---------------------------------------------------------------- synthesis
synth_design -top top_pynq_z2 -part $part -generic [list "FLASH_INIT=\"$nib\""]
report_utilization -file $out/post_synth_utilization.rpt

# ----------------------------------------------------------- implementation
opt_design
place_design
phys_opt_design
route_design

# ------------------------------------------------------------------ reports
report_utilization    -file $out/utilization.rpt
report_utilization    -hierarchical -hierarchical_depth 3 -file $out/utilization_hier.rpt
report_timing_summary -file $out/timing_summary.rpt -max_paths 10
report_clock_utilization -file $out/clock_utilization.rpt
report_power          -file $out/power.rpt
report_io             -file $out/io.rpt
report_drc            -file $out/drc.rpt
report_methodology    -file $out/methodology.rpt

# ------------------------------------------------------------------ outputs
write_checkpoint -force $out/top_pynq_z2_routed.dcp
write_verilog -mode funcsim -force $out/top_pynq_z2_funcsim.v
write_bitstream -force $out/rvsoc_pynq_z2.bit

# ------------------------------------------------------------------ summary
set wns [get_property SLACK [get_timing_paths -delay_type max]]
set whs [get_property SLACK [get_timing_paths -delay_type min]]
foreach c [get_clocks] {
    puts "RVSOC_FPGA_RESULT: clock [get_property NAME $c] period [get_property PERIOD $c] ns"
}
puts "RVSOC_FPGA_RESULT: WNS=$wns ns WHS=$whs ns bitstream=$out/rvsoc_pynq_z2.bit"
foreach t {"Slice LUTs" "Slice Registers" "Block RAM Tile" "Bonded IOB" "MMCME2_ADV"} {
    set used ""
    foreach line [split [report_utilization -return_string] "\n"] {
        if {[regexp "^\\|\\s*${t}\\*?\\s*\\|\\s*(\[0-9.\]+)\\s*\\|.*\\|\\s*(\[0-9.\]+)\\s*\\|\\s*(\[0-9.<\]+)\\s*\\|" $line -> u a p]} {
            set used "$u of $a ($p %)"; break
        }
    }
    puts "RVSOC_FPGA_RESULT: $t: $used"
}
if {$wns < 0 || $whs < 0} { puts "RVSOC_FPGA_RESULT: TIMING NOT MET" } else { puts "RVSOC_FPGA_RESULT: timing met" }
