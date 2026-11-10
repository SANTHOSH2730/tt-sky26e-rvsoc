`default_nettype none
`timescale 1ns / 1ps

/* Board-level test of the PYNQ-Z2 harness, observed only through the board pins.
 *
 * tb_fpga.v takes two shortcuts (MMCM bypassed, FAST_SIM speed-up). This testbench
 * takes none: it runs the design exactly as it is loaded into the FPGA.
 *   - 125 MHz sysclk into the real MMCM (Xilinx UNISIM model) -> 64 MHz chip clock
 *   - ui[4] = 0, so the firmware uses its real-hardware settings (115200 baud UART)
 * It runs on the RTL (Vivado xsim + unisims) and on Vivado's post-route netlist
 * (write_verilog -mode funcsim), i.e. the netlist that is inside the bitstream.
 *
 * Run 1, SW = 00 (demo mode)
 *   BTN0 released -> "Hello, TT!", ISA/PSRAM/TIMER/GPIO PASS, "SELFTEST PASS";
 *   LD4 and LD5 light green, LD5 never red;
 *   BTN1 -> "IRQ0", BTN2 -> "IRQ1";
 *   "Hi<CR>" typed into Pmod JA2 (UART RX) -> echoed back as "Hi<CR><LF>".
 * Run 2, SW = 01 (GPIO mirror mode)
 *   "Hello, TT!", "GPIO PASS", "MIRROR"; then LD0-LD3 and Pmod JB follow
 *   SW0, SW1, BTN3 and Pmod JA4.
 * Prints "[tb_board] PASS" when every check passed.
 */
module tb_fpga_board;
    reg        sysclk = 1'b0;
    reg  [3:0] btn = 4'b0001;            // BTN0 held: reset
    reg  [1:0] sw  = 2'b00;
    reg        rx  = 1'b1;               // Pmod JA2: UART into the chip, idle high
    reg        in6 = 1'b0;               // Pmod JA4: ui[6]
    wire [3:0] led;
    wire [5:0] rgb;
    wire       tx, rts;
    wire [3:0] dbg;
    wire [7:0] jb;

    always #4.0 sysclk = ~sysclk;        // 125 MHz, as on the board (pin H16)

    top_pynq_z2 dut (
        .sysclk(sysclk), .btn(btn), .sw(sw), .led(led), .rgb(rgb),
        .ja_uart_tx(tx), .ja_uart_rx(rx), .ja_rts(rts), .ja_in6(in6),
        .ja_dbg(dbg), .jb(jb)
    );

    // ------------------------------------------- UART receiver (115200 8N1)
    localparam real BIT_NS = 556 * 15.625;   // UART_DIV 555 at 64 MHz = 8687.5 ns
    reg  [8*40-1:0] cur = 0;                  // line being received
    reg  [8*40-1:0] lines [0:63];             // completed lines, CR LF included
    integer nlines = 0, nchars = 0, framing = 0;
    reg  armed = 1'b0;
    reg  [7:0] ch;
    integer k;
    always begin
        @(negedge tx);
        if (armed) begin
            #(BIT_NS / 2);
            if (tx === 1'b0) begin           // still low in mid start bit
                for (k = 0; k < 8; k = k + 1) begin
                    #(BIT_NS);
                    ch[k] = tx;
                end
                #(BIT_NS);
                if (tx !== 1'b1) framing = framing + 1;
                else begin
                    nchars = nchars + 1;
                    if (cur == 0) $write("    UART> ");
                    if (ch != 8'h0D) $write("%c", ch);
                    cur = {cur[8*39-1:0], ch};
                    if (ch == 8'h0A) begin
                        lines[nlines] = cur;
                        nlines = nlines + 1;
                        cur = 0;
                    end
                end
            end
        end
    end

    // -------------------------------------------------- status LEDs, Pmod taps
    reg hello_led = 1'b0, pass_led = 1'b0, fail_led = 1'b0;
    always @(posedge rgb[1]) hello_led = 1'b1;   // LD4 green: "Hello, TT!" seen
    always @(posedge rgb[4]) pass_led  = 1'b1;   // LD5 green: "SELFTEST PASS" seen
    always @(posedge rgb[5]) fail_led  = 1'b1;   // LD5 red:   "FAIL" seen
    integer flash_cs = 0, ram_cs = 0;
    always @(negedge dbg[0]) flash_cs = flash_cs + 1;   // Pmod JA7: flash CS#
    always @(negedge dbg[3]) ram_cs   = ram_cs + 1;     // Pmod JA10: PSRAM A CS#

    // ------------------------------------------------------------- helpers
    integer rd = 0, errors = 0;
    real    t_boot;

    task check(input ok, input [8*64-1:0] what);
        begin
            if (ok) $display("[tb_board] ok    %0s", what);
            else begin
                $display("[tb_board] FAIL  %0s", what);
                errors = errors + 1;
            end
        end
    endtask

    task expect_line(input [8*38-1:0] text, input integer timeout_us);
        reg [8*40-1:0] want;
        begin
            want = {text, 8'h0D, 8'h0A};
            fork : wait_line
                begin wait (nlines > rd); disable wait_line; end
                begin #(timeout_us * 1000.0); disable wait_line; end
            join
            if (nlines > rd) begin
                if (lines[rd] !== want) begin
                    $display("[tb_board] FAIL  expected line \"%0s\"", text);
                    errors = errors + 1;
                end
                rd = rd + 1;
            end else begin
                $display("[tb_board] FAIL  no line \"%0s\" within %0d us", text, timeout_us);
                errors = errors + 1;
            end
        end
    endtask

    task uart_send(input [7:0] b);       // into Pmod JA2, 8N1
        integer i;
        begin
            rx = 1'b0; #(BIT_NS);
            for (i = 0; i < 8; i = i + 1) begin rx = b[i]; #(BIT_NS); end
            rx = 1'b1; #(BIT_NS);
        end
    endtask

    task type_char(input [7:0] c);       // send one character and wait for its echo
        integer n;
        begin
            n = nchars;
            uart_send(c);
            fork : wait_echo
                begin wait (nchars > n); disable wait_echo; end
                begin #500000; disable wait_echo; end
            join
        end
    endtask

    task press(input integer b);         // press a button for 20 us
        begin
            btn[b] = 1'b1; #20000; btn[b] = 1'b0;
        end
    endtask

    task boot(input [1:0] mode);         // hold BTN0 with the mode switches set, release
        begin
            armed = 1'b0;
            btn[0] = 1'b1; sw = mode;
            #5000;
            rd = nlines; cur = 0;
            hello_led = 1'b0; pass_led = 1'b0; fail_led = 1'b0;
            flash_cs = 0; ram_cs = 0;
            armed = 1'b1;
            btn[0] = 1'b0;
            t_boot = $realtime;
            $display("[tb_board] BTN0 released at %0.1f us, SW1:SW0 = %b", t_boot / 1000.0, mode);
        end
    endtask

    // --------------------------------------------------------------- tests
    initial begin
        $display("[tb_board] 125 MHz sysclk -> MMCM -> 64 MHz; UART 115200 8N1; ui[4] = 0");
        #2000;

        // ---------------- run 1: demo mode
        boot(2'b00);
        expect_line("Hello, TT!", 4000);
        $display("[tb_board] boot banner complete %0.0f us after BTN0 release",
                 ($realtime - t_boot) / 1000.0);
        expect_line("ISA PASS", 5000);
        expect_line("PSRAM PASS", 5000);
        expect_line("TIMER PASS", 5000);
        expect_line("GPIO PASS", 5000);
        expect_line("SELFTEST PASS", 5000);
        $display("[tb_board] self-test complete %0.0f us after BTN0 release",
                 ($realtime - t_boot) / 1000.0);
        #20000;
        check(hello_led && pass_led && !fail_led, "LD4 green and LD5 green lit, LD5 never red");
        check(flash_cs > 100 && ram_cs > 10, "flash and PSRAM A chip selects active on Pmod JA7/JA10");
        #200000;                             // the demo loop enables the pin interrupts
        press(1);
        expect_line("IRQ0", 2000);
        press(2);
        expect_line("IRQ1", 2000);
        type_char("H");
        type_char("i");
        type_char(8'h0D);
        expect_line("Hi", 2000);
        check(framing == 0, "no UART framing errors");

        // ---------------- run 2: GPIO mirror mode
        boot(2'b01);
        expect_line("Hello, TT!", 4000);
        expect_line("GPIO PASS", 5000);
        expect_line("MIRROR", 3000);
        #50000;
        // LD3..LD0 = uo[5:2] = {BTN3, ui[4]=0, SW1, SW0}; JB7..JB2 = uo[7:2] = ui[7:2]
        check(led === 4'b0001 && jb[7:2] === 6'b100001, "mirror: SW0=1 -> LD0 on, others off");
        btn[3] = 1'b1; in6 = 1'b1; sw[1] = 1'b1;
        #50000;
        check(led === 4'b1011 && jb[7:2] === 6'b111011, "mirror: BTN3, SW1, JA4 high -> LD3, LD1, JB6 on");
        btn[3] = 1'b0; in6 = 1'b0; sw[1] = 1'b0;
        #50000;
        check(led === 4'b0001 && jb[7:2] === 6'b100001, "mirror: inputs released -> LEDs follow");
        check(jb[0] === 1'b1 && tx === 1'b1, "UART TX idles high on JA1 and JB1");
        check(framing == 0, "no UART framing errors");

        if (errors == 0) $display("[tb_board] PASS (%0d UART characters received, %0.2f ms simulated)",
                                  nchars, $realtime / 1.0e6);
        else             $display("[tb_board] FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #60000000;                           // 60 ms watchdog
        $display("[tb_board] FAIL (watchdog: simulation did not finish)");
        $finish;
    end
endmodule
