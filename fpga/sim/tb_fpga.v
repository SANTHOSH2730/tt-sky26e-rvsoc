`default_nettype none
`timescale 1ns / 1ps

/* Simulation of the complete FPGA harness (top_pynq_z2 with SIM defined:
 * the MMCM is bypassed and the testbench supplies the 64 MHz clock).
 * Passes when the on-FPGA UART checker lights "Hello, TT!" and
 * "SELFTEST PASS" and the LED chaser on LD0-LD3 moves. */
module tb_fpga;
    reg        clk = 1'b0;
    reg  [3:0] btn = 4'b0001;        // BTN0 held = reset
    reg  [1:0] sw  = 2'b00;          // demo mode
    wire [3:0] led;
    wire [5:0] rgb;
    wire       ja_uart_tx, ja_rts;
    wire [3:0] ja_dbg;
    wire [7:0] jb;

    always #7.812 clk = ~clk;        // 64 MHz

    top_pynq_z2 #(.FLASH_INIT("rvsoc_fw_nibbles.hex"), .FAST_SIM(1'b1)) dut (
        .sysclk(clk), .btn(btn), .sw(sw), .led(led), .rgb(rgb),
        .ja_uart_tx(ja_uart_tx), .ja_uart_rx(1'b1), .ja_rts(ja_rts), .ja_in6(1'b0),
        .ja_dbg(ja_dbg), .jb(jb)
    );

    // Print the chip's UART output (2 Mbaud in FAST_SIM mode)
    always @(posedge dut.i_watch.strobe) $write("%c", dut.i_watch.data);

    integer moves = 0;
    reg [3:0] last_led = 4'h0;
    always @(posedge clk) if (led != last_led) begin last_led <= led; moves <= moves + 1; end

    initial begin
        $dumpfile("tb_fpga.fst");
        $dumpvars(1, tb_fpga);
        repeat (50) @(posedge clk);
        btn[0] <= 1'b0;              // release reset
        fork : wait_result
            begin
                wait (dut.i_watch.selftest_ok || dut.i_watch.fail_seen);
                disable wait_result;
            end
            begin
                #3000000;            // 3 ms timeout
                disable wait_result;
            end
        join
        #2000000;                    // let the LED chaser run (tick = 250 us)
        $display("\n[tb_fpga] hello_ok=%0d selftest_ok=%0d fail_seen=%0d led_moves=%0d",
                 dut.i_watch.hello_ok, dut.i_watch.selftest_ok, dut.i_watch.fail_seen, moves);
        if (dut.i_watch.hello_ok && dut.i_watch.selftest_ok && !dut.i_watch.fail_seen && moves >= 4)
            $display("[tb_fpga] PASS");
        else
            $display("[tb_fpga] FAIL");
        $finish;
    end
endmodule
