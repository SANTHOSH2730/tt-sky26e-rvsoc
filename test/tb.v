`default_nettype none
`timescale 1ns / 1ps

/* Testbench for tt_um_santhosh_rvsoc.
 *
 * Two ways to drive the QSPI bus (select with use_model):
 *   use_model = 1 : sim_qspi_pmod (flash + 2 PSRAM) loaded with the firmware
 *                   hex, with a programmable read latency (latency_cfg).
 *   use_model = 0 : cocotb drives qspi_data_in directly (upstream TinyQV
 *                   instruction-level tests).
 * A Verilog UART monitor decodes uo_out[0] so the Python tests only see bytes.
 */
module tb ();

  // Dump only the testbench-level signals (pins), so the waveform stays small.
  initial begin
    $dumpfile("tb.fst");
    $dumpvars(1, tb);
    #1;
  end

  reg clk;
  reg rst_n;
  reg ena;
  reg [6:0] ui_in_base;
  reg uart_rx;
  wire [7:0] ui_in = {uart_rx, ui_in_base};
  wire [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

  tt_um_santhosh_rvsoc user_project (
`ifdef GL_TEST
      .VPWR(VPWR),
      .VGND(VGND),
`endif
      .ui_in  (ui_in),
      .uo_out (uo_out),
      .uio_in (uio_in),
      .uio_out(uio_out),
      .uio_oe (uio_oe),
      .ena    (ena),
      .clk    (clk),
      .rst_n  (rst_n)
  );

  // ------------------------------------------------------------- QSPI Pmod
  wire [3:0] qspi_data_out = {uio_out[5:4], uio_out[2:1]};
  wire [3:0] qspi_data_oe  = {uio_oe[5:4],  uio_oe[2:1]};
  wire qspi_clk_out      = uio_out[3];
  wire qspi_flash_select = uio_out[0];
  wire qspi_ram_a_select = uio_out[6];
  wire qspi_ram_b_select = uio_out[7];

  reg        use_model;
  reg  [3:0] qspi_data_in;     // driven by cocotb when use_model == 0
  reg  [2:0] latency_cfg;

  wire [3:0] model_data;
  reg [19:0] data_buffer;
  always @(posedge clk) data_buffer <= {data_buffer[15:0], model_data};
  wire [3:0] model_delayed = (latency_cfg < 1) ? model_data : data_buffer[(latency_cfg - 1) * 4 +: 4];
  wire [3:0] qspi_to_dut   = use_model ? model_delayed : qspi_data_in;

  // During reset SD2:SD0 carry the read latency (SD3 = 0)
  wire [3:0] qspi_pins_in = rst_n ? qspi_to_dut : {1'b0, latency_cfg};
  assign uio_in = {2'b00, qspi_pins_in[3:2], 1'b0, qspi_pins_in[1:0], 1'b0};

`ifndef FW_HEX
`define FW_HEX "rvsoc_fw.hex"
`endif

  sim_qspi_pmod #(.ROM_BITS(16), .RAM_BITS(16), .INIT_FILE(`FW_HEX)) qspi (
      .qspi_data_in     (qspi_data_out & qspi_data_oe),
      .qspi_data_out    (model_data),
      .qspi_clk         (qspi_clk_out),
      .qspi_flash_select(qspi_flash_select),
      .qspi_ram_a_select(qspi_ram_a_select),
      .qspi_ram_b_select(qspi_ram_b_select),
      .debug_clk        (1'b0),
      .debug_addr       (25'd0),
      .debug_data       ()
  );

`ifdef TRACE_FETCH
  // Debug aid (make COMPILE_ARGS=-DTRACE_FETCH): print every flash fetch address
  // and every PSRAM access as the flash/PSRAM model decodes it.
  always @(negedge qspi_clk_out) begin
    if (!qspi_flash_select && qspi.start_count == 6)
      $display("%t FETCH %06x", $time, qspi.cmd[23:0]);
    if (!(qspi_ram_a_select && qspi_ram_b_select) && qspi.start_count == 8)
      $display("%t RAM%s %s %06x", $time, qspi_ram_a_select ? "B" : "A",
               qspi.cmd[31:24] == 8'h02 ? "W" : "R", qspi.cmd[23:0]);
  end
`endif

`ifdef TRACE_TIMER
  // Debug aid (RTL only): timer writes, reads, current COUNT/CMP and IRQ
  reg [31:0] tr_cnt, tr_cmp;
  always @(posedge clk) begin
    if (user_project.i_timer.phase == 3'd0) begin
      tr_cnt = user_project.i_timer.cnt;
      tr_cmp = user_project.i_timer.cmp;
    end
    if (user_project.i_timer.wr_count || user_project.i_timer.wr_cmp)
      $display("%t TIMER write %s %08x phase %0d", $time, user_project.i_timer.wr_cmp ? "CMP" : "COUNT",
               user_project.i_timer.wdata, user_project.i_timer.phase);
    if ((user_project.connect_peripheral == 4'hA || user_project.connect_peripheral == 4'hB) && user_project.read_n != 2'b11
        && user_project.i_timer.phase == 3'd0)
      $display("%t TIMER read %s count=%08x cmp=%08x irq=%b", $time,
               user_project.connect_peripheral == 4'hA ? "COUNT" : "CMP", tr_cnt, tr_cmp, user_project.i_timer.irq);
  end
  always @(posedge user_project.i_timer.irq) $display("%t TIMER IRQ set count=%08x cmp=%08x", $time, tr_cnt, tr_cmp);
`endif

  // ------------------------------------------------------------ UART monitor
  wire uart_tx  = uo_out[0];
  wire uart_rts = uo_out[1];
  reg  [15:0] uart_mon_div;     // clocks per bit - 1 (must match UART_DIV)
  reg  [7:0]  uart_mon_byte;
  reg  [31:0] uart_mon_count;   // increments once per received byte
  reg  [31:0] uart_mon_errors;  // framing errors
  reg  [7:0]  uart_mon_shift;
  integer     uart_mon_i;

  initial begin
    uart_mon_div    = 16'd555;
    uart_mon_count  = 0;
    uart_mon_errors = 0;
    uart_mon_byte   = 0;
  end

  always begin
    @(negedge uart_tx);
    if (rst_n === 1'b1) begin
      repeat ((uart_mon_div + 1) / 2) @(posedge clk);
      if (uart_tx === 1'b0) begin
        for (uart_mon_i = 0; uart_mon_i < 8; uart_mon_i = uart_mon_i + 1) begin
          repeat (uart_mon_div + 1) @(posedge clk);
          uart_mon_shift[uart_mon_i] = uart_tx;
        end
        repeat (uart_mon_div + 1) @(posedge clk);
        if (uart_tx === 1'b1) begin
          uart_mon_byte  = uart_mon_shift;
          uart_mon_count = uart_mon_count + 1;
        end else begin
          uart_mon_errors = uart_mon_errors + 1;
        end
      end
    end
  end

endmodule
