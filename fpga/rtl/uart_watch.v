/*
 * Copyright (c) 2026 Santhosh
 * SPDX-License-Identifier: Apache-2.0
 *
 * On-FPGA checker for the chip's UART TX (no PC needed): decodes 8N1 at a fixed
 * bit period and raises sticky flags when it sees
 *   "Hello, TT!"     -> hello_ok
 *   "SELFTEST PASS"  -> selftest_ok
 *   "FAIL"           -> fail_seen
 */
`default_nettype none

module uart_watch #(
    parameter DIV = 555                 // clocks per bit - 1 (555 = 115200 @ 64 MHz)
) (
    input  wire clk,
    input  wire rst_n,
    input  wire rx,
    output reg  hello_ok,
    output reg  selftest_ok,
    output reg  fail_seen
);
    // ---------------- 8N1 receiver
    reg [1:0]  rx_s;
    reg [15:0] cnt;
    reg [3:0]  bitn;
    reg [7:0]  shift;
    reg        busy;
    reg        strobe;
    reg [7:0]  data;
    always @(posedge clk) begin
        rx_s   <= {rx_s[0], rx};
        strobe <= 1'b0;
        if (!rst_n) begin
            busy <= 1'b0;
            rx_s <= 2'b11;
        end else if (!busy) begin
            if (!rx_s[1]) begin            // start bit
                busy <= 1'b1;
                cnt  <= DIV / 2;
                bitn <= 4'd0;
            end
        end else if (cnt != 0) begin
            cnt <= cnt - 1'b1;
        end else begin
            cnt <= DIV;
            bitn <= bitn + 1'b1;
            if (bitn == 4'd0) begin
                if (rx_s[1]) busy <= 1'b0;  // glitch, not a start bit
            end else if (bitn <= 4'd8) begin
                shift <= {rx_s[1], shift[7:1]};
            end else begin
                busy <= 1'b0;
                if (rx_s[1]) begin          // valid stop bit
                    data   <= shift;
                    strobe <= 1'b1;
                end
            end
        end
    end

    // ---------------- string matchers
    localparam [8*10-1:0] S_HELLO = "Hello, TT!";
    localparam [8*13-1:0] S_PASS  = "SELFTEST PASS";
    localparam [8*4-1:0]  S_FAIL  = "FAIL";

    reg [3:0] i_hello, i_pass;
    reg [2:0] i_fail;
    wire [7:0] c_hello = S_HELLO[(9  - i_hello) * 8 +: 8];
    wire [7:0] c_pass  = S_PASS [(12 - i_pass)  * 8 +: 8];
    wire [7:0] c_fail  = S_FAIL [(3  - i_fail)  * 8 +: 8];

    always @(posedge clk) begin
        if (!rst_n) begin
            i_hello <= 0; i_pass <= 0; i_fail <= 0;
            hello_ok <= 1'b0; selftest_ok <= 1'b0; fail_seen <= 1'b0;
        end else if (strobe) begin
            if (data == c_hello) begin
                if (i_hello == 4'd9) begin hello_ok <= 1'b1; i_hello <= 0; end
                else i_hello <= i_hello + 1'b1;
            end else i_hello <= (data == S_HELLO[79:72]) ? 4'd1 : 4'd0;

            if (data == c_pass) begin
                if (i_pass == 4'd12) begin selftest_ok <= 1'b1; i_pass <= 0; end
                else i_pass <= i_pass + 1'b1;
            end else i_pass <= (data == S_PASS[103:96]) ? 4'd1 : 4'd0;

            if (data == c_fail) begin
                if (i_fail == 3'd3) begin fail_seen <= 1'b1; i_fail <= 0; end
                else i_fail <= i_fail + 1'b1;
            end else i_fail <= (data == S_FAIL[31:24]) ? 3'd1 : 3'd0;
        end
    end
endmodule
