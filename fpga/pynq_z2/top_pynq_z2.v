/*
 * Copyright (c) 2026 Santhosh
 * SPDX-License-Identifier: Apache-2.0
 *
 * FPGA test harness for tt_um_santhosh_rvsoc on a PYNQ-Z2 (also PYNQ-Z1).
 * PL only (no Zynq PS needed). The exact chip RTL from ../../src is used.
 *
 *   125 MHz sysclk -> MMCM -> 64 MHz chip clock (same as on the real chip)
 *   QSPI flash + 2 PSRAM : emulated in block RAM (qspi_pmod_emu), flash
 *                          preloaded with firmware/build/rvsoc_fw.hex
 *
 * Board I/O (see docs/fpga.md):
 *   BTN0  reset (hold to reset, release to boot)
 *   BTN1  ui[0] IRQ0          BTN2  ui[1] IRQ1        BTN3  ui[5]
 *   SW0   ui[2] mode bit 0    SW1   ui[3] mode bit 1  (00 = demo, 01 = GPIO mirror)
 *   LD0-3 uo[2]..uo[5] (LED chaser)
 *   LD4   green = "Hello, TT!" received, blue = heartbeat (FPGA alive)
 *   LD5   green = "SELFTEST PASS",       red  = a FAIL line was printed
 *   Pmod JA: 1 UART TX (uo[0]) -> USB-UART RX, 2 UART RX (ui[7]) <- USB-UART TX,
 *            3 RTS (uo[1]), 4 ui[6] input,
 *            7 flash CS#, 8 SCK, 9 SD0, 10 PSRAM A CS#   (logic analyser taps)
 *   Pmod JB: uo[0]..uo[7] (all chip outputs, for a logic analyser / LEDs)
 */
`default_nettype none

module top_pynq_z2 #(
    parameter FLASH_INIT = "rvsoc_fw_nibbles.hex",
    parameter LATENCY    = 3'd2,     // QSPI read latency matching qspi_pmod_emu
    parameter FAST_SIM   = 1'b0      // 1: ui[4]=1 (2 Mbaud, short tick) for simulation only
) (
    input  wire       sysclk,        // 125 MHz
    input  wire [3:0] btn,
    input  wire [1:0] sw,
    output wire [3:0] led,
    output wire [5:0] rgb,           // {LD5 R, LD5 G, LD5 B, LD4 R, LD4 G, LD4 B}
    output wire       ja_uart_tx,
    input  wire       ja_uart_rx,
    output wire       ja_rts,
    input  wire       ja_in6,
    output wire [3:0] ja_dbg,        // flash CS#, SCK, SD0, PSRAM A CS#
    output wire [7:0] jb
);

    // ------------------------------------------------------------- clocking
    wire clk;
    wire locked;
`ifdef SIM
    assign clk = sysclk;             // testbench drives 64 MHz directly
    assign locked = 1'b1;
`else
    wire clk_mmcm, clkfb;
    MMCME2_BASE #(
        .CLKIN1_PERIOD(8.000),       // 125 MHz
        .DIVCLK_DIVIDE(5),           // PFD 25 MHz
        .CLKFBOUT_MULT_F(32.000),    // VCO 800 MHz
        .CLKOUT0_DIVIDE_F(12.500)    // 64 MHz
    ) i_mmcm (
        .CLKIN1(sysclk), .CLKFBIN(clkfb), .CLKFBOUT(clkfb),
        .CLKOUT0(clk_mmcm), .LOCKED(locked), .RST(1'b0), .PWRDWN(1'b0),
        .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(), .CLKFBOUTB()
    );
    BUFG i_bufg (.I(clk_mmcm), .O(clk));
`endif

    // ------------------------------------------- input sync and reset
    reg [3:0] btn_s0, btn_s1;
    reg [1:0] sw_s0, sw_s1;
    reg [1:0] rx_s, in6_s;
    always @(posedge clk) begin
        btn_s0 <= btn;  btn_s1 <= btn_s0;
        sw_s0  <= sw;   sw_s1  <= sw_s0;
        rx_s   <= {rx_s[0], ja_uart_rx};
        in6_s  <= {in6_s[0], ja_in6};
    end

    // Reset held for 1024 clocks after lock / BTN0 release
    reg [10:0] por = 11'd0;
    always @(posedge clk) begin
        if (!locked || btn_s1[0]) por <= 11'd0;
        else if (!por[10])        por <= por + 1'b1;
    end
    wire rst_n = por[10];

    // ---------------------------------------------------------- the chip
    wire [7:0] ui_in = {rx_s[1], in6_s[1], btn_s1[3], FAST_SIM, sw_s1[1], sw_s1[0], btn_s1[2], btn_s1[1]};
    wire [7:0] uo_out, uio_out, uio_oe, uio_in;

    tt_um_santhosh_rvsoc i_chip (
        .ui_in  (ui_in),
        .uo_out (uo_out),
        .uio_in (uio_in),
        .uio_out(uio_out),
        .uio_oe (uio_oe),
        .ena    (1'b1),
        .clk    (clk),
        .rst_n  (rst_n)
    );

    // --------------------------------------------- QSPI Pmod emulation
    wire [3:0] sd_from_chip = {uio_out[5:4], uio_out[2:1]} & {uio_oe[5:4], uio_oe[2:1]};
    wire [3:0] sd_to_chip;
    qspi_pmod_emu #(.ADDR_BITS(16), .FLASH_INIT(FLASH_INIT)) i_mem (
        .clk       (clk),
        .sd_in     (sd_from_chip),
        .sd_out    (sd_to_chip),
        .sck       (uio_out[3]),
        .cs_flash_n(uio_out[0]),
        .cs_ram_a_n(uio_out[6]),
        .cs_ram_b_n(uio_out[7])
    );
    // While in reset the chip reads its QSPI latency from SD2:SD0
    wire [3:0] sd_pins = rst_n ? sd_to_chip : {1'b0, LATENCY};
    assign uio_in = {2'b00, sd_pins[3:2], 1'b0, sd_pins[1:0], 1'b0};

    // ------------------------------------------------- on-board checks
    wire hello_ok, selftest_ok, fail_seen;
    uart_watch #(.DIV(FAST_SIM ? 31 : 555)) i_watch (
        .clk(clk), .rst_n(rst_n), .rx(uo_out[0]),
        .hello_ok(hello_ok), .selftest_ok(selftest_ok), .fail_seen(fail_seen)
    );

    reg [25:0] hb = 26'd0;
    always @(posedge clk) hb <= hb + 1'b1;
    wire dim = (hb[2:0] == 3'd0);                 // 1/8 brightness for the RGB LEDs

    assign led = uo_out[5:2];
    assign rgb = {fail_seen & dim, selftest_ok & dim, 1'b0,
                  1'b0, hello_ok & dim, hb[25] & dim};

    // --------------------------------------------------------- Pmods
    assign ja_uart_tx = uo_out[0];
    assign ja_rts     = uo_out[1];
    assign ja_dbg     = {uio_out[6], uio_out[1], uio_out[3], uio_out[0]};
    assign jb         = uo_out;

endmodule
