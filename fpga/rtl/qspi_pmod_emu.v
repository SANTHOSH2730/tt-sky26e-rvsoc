/*
 * Copyright (c) 2026 Santhosh
 * SPDX-License-Identifier: Apache-2.0
 *
 * Synthesizable emulation of the Tiny Tapeout QSPI Pmod (16 MB flash +
 * 2 x 8 MB PSRAM) for FPGA testing of tt_um_santhosh_rvsoc, in block RAM.
 *
 * Protocol is identical to test/sim_qspi.v (upstream TinyQV simulation model):
 *   flash : continuous-read (XIP) mode: 6 address nibbles, mode nibble 0xA?,
 *           4 dummy clocks, then data (the SoC expects the flash already in this mode)
 *   PSRAM : QPI mode, 0x0B read (6 addr nibbles + 4 dummy) / 0x02 write
 *
 * Everything runs on the SoC clock. SCK edges are detected one clock late and
 * memory reads are registered (block RAM), so the returned data arrives exactly
 * 2 clocks later than from the simulation model: configure the SoC read
 * latency (SD2:SD0 during reset) to 2.
 *
 * Memories are nibble wide: nibble 2n = byte n bits [7:4], 2n+1 = bits [3:0].
 */
`default_nettype none

module qspi_pmod_emu #(
    parameter ADDR_BITS  = 16,     // byte address bits per device (16 -> 64 KB each)
    parameter FLASH_INIT = ""      // nibble-per-line hex image for the flash
) (
    input  wire       clk,
    input  wire [3:0] sd_in,       // SoC data out & output enable
    output reg  [3:0] sd_out,      // data to the SoC
    input  wire       sck,
    input  wire       cs_flash_n,
    input  wire       cs_ram_a_n,
    input  wire       cs_ram_b_n
);
    localparam NB = ADDR_BITS + 1; // nibble address bits

    // The flash is never written, so Vivado treats it as a ROM. Vivado 2025.1
    // trims it to the part the firmware fills (16 K nibbles for the demo) and
    // builds it from LUTs (about 800) despite rom_style; the PSRAMs use 32 BRAMs.
    (* rom_style = "block" *) reg [3:0] rom   [0:(1<<NB)-1];
    (* ram_style = "block" *) reg [3:0] ram_a [0:(1<<NB)-1];
    (* ram_style = "block" *) reg [3:0] ram_b [0:(1<<NB)-1];

    initial begin
        if (FLASH_INIT != "") $readmemh(FLASH_INIT, rom);
    end

    reg sck_q;
    always @(posedge clk) sck_q <= sck;
    wire rise  = sck & ~sck_q;
    wire fall  = ~sck & sck_q;
    wire idle  = cs_flash_n & cs_ram_a_n & cs_ram_b_n;

    reg [31:0]   cmd;
    reg [5:0]    start_count;
    reg [NB-1:0] addr;
    reg          reading, reading_dummy, writing, error;

    always @(posedge clk) begin
        if (idle) begin
            cmd <= 32'd0;
            start_count <= 6'd0;
            reading <= 1'b0;
            reading_dummy <= 1'b0;
            writing <= 1'b0;
            error <= 1'b0;
            addr <= {NB{1'b0}};
        end else if (rise) begin
            start_count <= start_count + 6'd1;
            if (!reading && !writing && !error)
                cmd <= {cmd[27:0], sd_in};
        end else if (fall) begin
            if (reading || writing) begin
                addr <= addr + 1'b1;
            end else if (reading_dummy) begin
                if (start_count < 6'd8 && cmd[3:0] != 4'b1010) begin
                    error <= 1'b1;
                    reading_dummy <= 1'b0;
                end
                if (start_count == 6'd12) begin
                    reading <= 1'b1;
                    reading_dummy <= 1'b0;
                end
            end else if (!error && start_count == (cs_flash_n ? 6'd8 : 6'd6)) begin
                addr <= {cmd[ADDR_BITS-1:0], 1'b0};
                if (!cs_flash_n || cmd[31:24] == 8'h0B) reading_dummy <= 1'b1;
                else if (cmd[31:24] == 8'h02)           writing <= 1'b1;
                else                                     error <= 1'b1;
            end
        end
    end

    // PSRAM writes (one nibble per SCK rising edge)
    wire wr = rise && writing && !idle;
    always @(posedge clk) if (wr && !cs_ram_a_n)               ram_a[addr] <= sd_in;
    always @(posedge clk) if (wr &&  cs_ram_a_n && !cs_ram_b_n) ram_b[addr] <= sd_in;

    // Registered (block RAM) reads
    reg [3:0] rom_q, ram_a_q, ram_b_q;
    reg [1:0] sel_q;
    reg       rd_q;
    always @(posedge clk) begin
        rom_q   <= rom[addr];
        ram_a_q <= ram_a[addr];
        ram_b_q <= ram_b[addr];
        rd_q    <= reading;
        sel_q   <= !cs_flash_n ? 2'd0 : !cs_ram_a_n ? 2'd1 : !cs_ram_b_n ? 2'd2 : 2'd3;
    end

    always @(*) begin
        if (!rd_q)              sd_out = 4'h0;
        else case (sel_q)
            2'd0:    sd_out = rom_q;
            2'd1:    sd_out = ram_a_q;
            2'd2:    sd_out = ram_b_q;
            default: sd_out = 4'h0;
        endcase
    end
endmodule
