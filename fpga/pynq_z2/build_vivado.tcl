# Vivado non-project build of the tt_um_santhosh_rvsoc FPGA harness for PYNQ-Z2 (xc7z020clg400-1).
#
#   vivado -mode batch -source build_vivado.tcl -tclargs <repo_root> <nibble_hex> [out_dir]
#
# <repo_root>  : the project folder (contains src/ and fpga/); forward slashes, UNC paths OK
# <nibble_hex> : flash image from fpga/tools/hex2nib.py (make -C fpga build/rvsoc_fw_nibbles.hex)
# [out_dir]    : where reports and the bitstream go (default <repo_root>/fpga/build)

set root [lindex $argv 0]
set nib  [lindex $argv 1]
set out  [expr {[llength $argv] > 2 ? [lindex $argv 2] : "$root/fpga/build"}]
set part xc7z020clg400-1
file mkdir $out

set chip_src [concat \
    [list $root/src/project.v $root/src/timer.v] \
    [glob $root/src/tinyQV/cpu/*.v] \
    [list $root/src/tinyQV/peri/uart/uart_tx.v $root/src/tinyQV/peri/uart/uart_rx.v]]
set fpga_src [list $root/fpga/rtl/qspi_pmod_emu.v $root/fpga/rtl/uart_watch.v $root/fpga/pynq_z2/top_pynq_z2.v]

read_verilog $chip_src
read_verilog $fpga_src
read_xdc $root/fpga/pynq_z2/pynq_z2.xdc

synth_design -top top_pynq_z2 -part $part -generic [list "FLASH_INIT=\"$nib\""]
opt_design
place_design
phys_opt_design
route_design

report_utilization    -file $out/utilization.rpt
report_timing_summary -file $out/timing_summary.rpt -max_paths 10
report_drc            -file $out/drc.rpt
write_bitstream -force $out/rvsoc_pynq_z2.bit

set wns [get_property SLACK [get_timing_paths -delay_type max]]
set whs [get_property SLACK [get_timing_paths -delay_type min]]
puts "RVSOC_FPGA_RESULT: WNS=$wns ns WHS=$whs ns bitstream=$out/rvsoc_pynq_z2.bit"
