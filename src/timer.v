/*
 * Copyright (c) 2026 Santhosh
 * SPDX-License-Identifier: Apache-2.0
 *
 * 32-bit timer with compare interrupt for the TinyQV-based SoC, built
 * nibble-serially like the TinyQV core to save area.
 *
 * TinyQV moves data 4 bits per clock while its nibble counter runs 0..7, and
 * reads a peripheral's nibble k while the counter is k. COUNT and CMP are kept
 * as 32-bit registers that rotate right by 4 bits every clock, locked to that
 * counter (`phase`, from project.v), so nibble k sits in bits [3:0] exactly when the CPU wants
 * it. Consequences:
 *   - reads need only a 4-bit output (cnt_nib / cmp_nib); the SoC replicates it
 *     over the 32-bit read bus;
 *   - COUNT is incremented by a 4-bit serial adder as it rotates, i.e. once per
 *     8 clocks (8 MHz at a 64 MHz clock); all nibbles of one read come from the
 *     same value, so a read is never torn;
 *   - COUNT == CMP is evaluated by a 4-bit serial comparator once per 8 clocks;
 *     IRQ is then set and stays set (sticky) until CMP is written.
 * TinyQV issues peripheral writes while its counter is 0 (checked in simulation).
 */

`default_nettype none

module rvsoc_timer (
    input  wire        clk,
    input  wire        rstn,
    input  wire [2:0]  phase,       // CPU nibble counter (0..7)
    input  wire [31:0] wdata,
    input  wire        wr_count,
    input  wire        wr_cmp,
    output wire [3:0]  cnt_nib,     // COUNT nibble for the current phase
    output wire [3:0]  cmp_nib,     // CMP nibble for the current phase
    output reg         irq
);


    reg  [31:0] cnt;                // rotating: cnt[3:0] is nibble `phase`
    reg  [31:0] cmp;
    reg         carry;              // increment carry between nibbles
    reg         eq;                 // all nibbles so far in this pass equal

    assign cnt_nib = cnt[3:0];
    assign cmp_nib = cmp[3:0];

    wire        cin   = (phase == 3'd0) ? 1'b1 : carry;
    wire [4:0]  sum   = {1'b0, cnt[3:0]} + {4'b0000, cin};
    wire        nib_eq = (cnt[3:0] == cmp[3:0]);
    wire        eq_so_far = ((phase == 3'd0) ? 1'b1 : eq) & nib_eq;

    always @(posedge clk) begin
        if (!rstn) begin
            cnt   <= 32'd0;
            carry <= 1'b0;
        end else if (wr_count) begin
            // write happens in phase 0: store already rotated for phase 1, no increment this pass
            cnt   <= {wdata[3:0], wdata[31:4]};
            carry <= 1'b0;
        end else begin
            cnt   <= {sum[3:0], cnt[31:4]};
            carry <= sum[4];
        end
    end

    always @(posedge clk) begin
        if (!rstn)       cmp <= 32'hFFFF_FFFF;
        else if (wr_cmp) cmp <= {wdata[3:0], wdata[31:4]};
        else             cmp <= {cmp[3:0], cmp[31:4]};
    end

    always @(posedge clk) begin
        if (!rstn || wr_count || wr_cmp) begin
            eq  <= 1'b0;                 // a pass with a write never matches
            if (!rstn || wr_cmp) irq <= 1'b0;
        end else begin
            eq <= eq_so_far;
            if (phase == 3'd7 && eq_so_far) irq <= 1'b1;
        end
    end

`ifdef SIM
    always @(posedge clk) begin
        if (rstn && (wr_count || wr_cmp) && phase != 3'd0)
            $display("%t ERROR rvsoc_timer: write in phase %0d (expected 0)", $time, phase);
    end
`endif

endmodule
