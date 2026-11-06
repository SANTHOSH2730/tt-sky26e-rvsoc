## tt_um_santhosh_rvsoc FPGA test harness - PYNQ-Z2 (pins identical on PYNQ-Z1)
## Pins from Xilinx PYNQ v2.7 board constraints (boards/Pynq-Z2/base/vivado/constraints/base.xdc)
## and the Digilent Arty-Z7/PYNQ-Z1 master XDC (sysclk H16).

## 125 MHz PL clock
set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33} [get_ports sysclk]
create_clock -name sysclk -period 8.000 [get_ports sysclk]

## Buttons BTN0..BTN3
set_property -dict {PACKAGE_PIN D19 IOSTANDARD LVCMOS33} [get_ports {btn[0]}]
set_property -dict {PACKAGE_PIN D20 IOSTANDARD LVCMOS33} [get_ports {btn[1]}]
set_property -dict {PACKAGE_PIN L20 IOSTANDARD LVCMOS33} [get_ports {btn[2]}]
set_property -dict {PACKAGE_PIN L19 IOSTANDARD LVCMOS33} [get_ports {btn[3]}]

## Switches SW0, SW1
set_property -dict {PACKAGE_PIN M20 IOSTANDARD LVCMOS33} [get_ports {sw[0]}]
set_property -dict {PACKAGE_PIN M19 IOSTANDARD LVCMOS33} [get_ports {sw[1]}]

## LEDs LD0..LD3
set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports {led[3]}]

## RGB LEDs: rgb[0] LD4 blue, [1] LD4 green, [2] LD4 red, [3] LD5 blue, [4] LD5 green, [5] LD5 red
set_property -dict {PACKAGE_PIN L15 IOSTANDARD LVCMOS33} [get_ports {rgb[0]}]
set_property -dict {PACKAGE_PIN G17 IOSTANDARD LVCMOS33} [get_ports {rgb[1]}]
set_property -dict {PACKAGE_PIN N15 IOSTANDARD LVCMOS33} [get_ports {rgb[2]}]
set_property -dict {PACKAGE_PIN G14 IOSTANDARD LVCMOS33} [get_ports {rgb[3]}]
set_property -dict {PACKAGE_PIN L14 IOSTANDARD LVCMOS33} [get_ports {rgb[4]}]
set_property -dict {PACKAGE_PIN M15 IOSTANDARD LVCMOS33} [get_ports {rgb[5]}]

## Pmod JA (top row pins 1-4 = JA[0..3], bottom row pins 7-10 = JA[4..7])
set_property -dict {PACKAGE_PIN Y18 IOSTANDARD LVCMOS33} [get_ports ja_uart_tx]
set_property -dict {PACKAGE_PIN Y19 IOSTANDARD LVCMOS33 PULLUP true} [get_ports ja_uart_rx]
set_property -dict {PACKAGE_PIN Y16 IOSTANDARD LVCMOS33} [get_ports ja_rts]
set_property -dict {PACKAGE_PIN Y17 IOSTANDARD LVCMOS33 PULLDOWN true} [get_ports ja_in6]
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports {ja_dbg[0]}]
set_property -dict {PACKAGE_PIN U19 IOSTANDARD LVCMOS33} [get_ports {ja_dbg[1]}]
set_property -dict {PACKAGE_PIN W18 IOSTANDARD LVCMOS33} [get_ports {ja_dbg[2]}]
set_property -dict {PACKAGE_PIN W19 IOSTANDARD LVCMOS33} [get_ports {ja_dbg[3]}]

## Pmod JB = uo_out[7:0]
set_property -dict {PACKAGE_PIN W14 IOSTANDARD LVCMOS33} [get_ports {jb[0]}]
set_property -dict {PACKAGE_PIN Y14 IOSTANDARD LVCMOS33} [get_ports {jb[1]}]
set_property -dict {PACKAGE_PIN T11 IOSTANDARD LVCMOS33} [get_ports {jb[2]}]
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports {jb[3]}]
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33} [get_ports {jb[4]}]
set_property -dict {PACKAGE_PIN W16 IOSTANDARD LVCMOS33} [get_ports {jb[5]}]
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33} [get_ports {jb[6]}]
set_property -dict {PACKAGE_PIN W13 IOSTANDARD LVCMOS33} [get_ports {jb[7]}]

## Asynchronous board inputs are synchronised in the RTL; outputs are slow
set_false_path -from [get_ports {btn[*] sw[*] ja_uart_rx ja_in6}]
set_false_path -to [get_ports {led[*] rgb[*] ja_uart_tx ja_rts ja_dbg[*] jb[*]}]

## The chip registers its reset on the falling clock edge (as on silicon)
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
