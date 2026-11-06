# Program the PYNQ-Z2 over JTAG (USB cable on the PROG/UART micro-USB port).
#   vivado -mode batch -source program_vivado.tcl -tclargs <path/to/rvsoc_pynq_z2.bit>
set bit [lindex $argv 0]
open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7z020*] 0]
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
puts "Programmed $bit into $dev"
close_hw_target
disconnect_hw_server
close_hw_manager
