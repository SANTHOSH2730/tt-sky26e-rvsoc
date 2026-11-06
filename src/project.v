/*
 * Copyright (c) 2024 Michael Bell
 * Copyright (c) 2026 Santhosh
 * SPDX-License-Identifier: Apache-2.0
 *
 * TinyQV RISC-V SoC for Tiny Tapeout SKY 26d (sky130A, 2x2 tiles).
 * Adapted from tt_um_MichaelBell_tinyQV (Tiny Tapeout 6), see docs/info.md.
 *
 * Changes from upstream TT06 TinyQV:
 *  - SPI controller, debug UART and debug-signal output muxes removed (MVP).
 *  - UART bit period is programmable (UART_DIV register).
 *  - 32-bit timer with compare interrupt added (TIMER_COUNT / TIMER_CMP).
 *  - Interrupt 3 is the timer (upstream: UART TX idle).
 *  - uo_out[7:2] are plain GPIO outputs; GPIO_SEL only selects uo_out[1:0].
 *
 * Memory map (unchanged from upstream):
 *   0x0000000-0x0FFFFFF  QSPI flash (execute in place)
 *   0x1000000-0x17FFFFF  QSPI PSRAM A
 *   0x1800000-0x1FFFFFF  QSPI PSRAM B
 *   0x8000000-0x800003F  peripherals (word registers, see below)
 */

`default_nettype none

module tt_um_santhosh_rvsoc #(
    parameter CLOCK_HZ  = 64_000_000,
    parameter UART_BAUD = 115_200
) (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
/*verilator lint_off UNUSEDSIGNAL*/
    input  wire [7:0] uio_in,   // IOs: Input path - only QSPI data bits used
/*verilator lint_on UNUSEDSIGNAL*/
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
/*verilator lint_off UNUSEDSIGNAL*/
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
/*verilator lint_on UNUSEDSIGNAL*/
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // Peripheral register select = address bits [5:2] in 0x8000000-0x800003F
    localparam PERI_GPIO_OUT    = 4'h0;  // 0x8000000
    localparam PERI_GPIO_IN     = 4'h1;  // 0x8000004
    localparam PERI_GPIO_OUT_SEL= 4'h3;  // 0x800000C
    localparam PERI_UART        = 4'h4;  // 0x8000010
    localparam PERI_UART_STATUS = 4'h5;  // 0x8000014
    localparam PERI_TIMER_COUNT = 4'hA;  // 0x8000028
    localparam PERI_TIMER_CMP   = 4'hB;  // 0x800002C
    localparam PERI_UART_DIV    = 4'hD;  // 0x8000034
    localparam PERI_NONE        = 4'hF;

    localparam UART_DIV_BITS  = 13;
    localparam [UART_DIV_BITS-1:0] UART_DIV_RESET = (CLOCK_HZ - 1) / UART_BAUD;

    // Register the reset on the negative edge of clock for safety.
    /* verilator lint_off SYNCASYNCNET */
    reg rst_reg_n;
    /* verilator lint_on SYNCASYNCNET */
    always @(negedge clk) rst_reg_n <= rst_n;

    // ---------------------------------------------------------------------
    // QSPI Pmod on the bidirectional pins (same pinout as upstream TinyQV):
    //   uio[0] flash CS#, uio[1] SD0, uio[2] SD1, uio[3] SCK,
    //   uio[4] SD2, uio[5] SD3, uio[6] PSRAM A CS#, uio[7] PSRAM B CS#
    // While rst_n is low all uio are inputs and SD2:SD0 give the read latency.
    // ---------------------------------------------------------------------
    wire [3:0] qspi_data_in = {uio_in[5:4], uio_in[2:1]};
    wire [3:0] qspi_data_out;
    wire [3:0] qspi_data_oe;
    wire       qspi_clk_out;
    wire       qspi_flash_select;
    wire       qspi_ram_a_select;
    wire       qspi_ram_b_select;
    assign uio_out = {qspi_ram_b_select, qspi_ram_a_select, qspi_data_out[3:2],
                      qspi_clk_out, qspi_data_out[1:0], qspi_flash_select};
    assign uio_oe = rst_n ? {2'b11, qspi_data_oe[3:2], 1'b1, qspi_data_oe[1:0], 1'b1} : 8'h00;

    // CPU data bus to peripherals
    wire [27:0] addr;
    wire  [1:0] write_n;
    wire  [1:0] read_n;
    wire        read_complete;
    wire [31:0] data_to_write;
    wire        data_ready = 1'b1;   // All peripheral transactions complete immediately
    reg  [31:0] data_from_read;
    wire        counter_0;

    reg  [3:0] connect_peripheral;
    always @(*) begin
        if ({addr[27:6], addr[1:0]} == 24'h800000)
            connect_peripheral = addr[5:2];
        else
            connect_peripheral = PERI_NONE;
    end
    wire peri_write = (write_n != 2'b11);

    // ---------------------------------------------------------------------
    // Peripherals
    // ---------------------------------------------------------------------
    wire       uart_rxd = ui_in[7];
    wire       uart_txd;
    wire       uart_rts;
    wire       uart_tx_busy;
    wire       uart_rx_valid;
    wire [7:0] uart_rx_data;
    reg  [UART_DIV_BITS-1:0] uart_div;

    reg  [1:0] gpio_out_sel;
    reg  [7:0] gpio_out;

    wire [3:0]  timer_cnt_nib;     // nibble-serial timer: current nibble of COUNT
    wire [3:0]  timer_cmp_nib;     // ... and of CMP
    wire        timer_irq;

    // Interrupts: 0,1 rising edge on ui_in[0], ui_in[1]; 2 UART byte received; 3 timer
    reg [1:0] ui_in_reg;
    always @(posedge clk) begin
        ui_in_reg <= ui_in[1:0];
    end
    wire [3:0] interrupt_req = {timer_irq, uart_rx_valid, ui_in_reg[1:0]};

    tinyQV i_tinyqv(
        .clk(clk),
        .rstn(rst_reg_n),

        .data_addr(addr),
        .data_write_n(write_n),
        .data_read_n(read_n),
        .data_read_complete(read_complete),
        .data_out(data_to_write),

        .data_ready(data_ready),
        .data_in(data_from_read),

        .interrupt_req(interrupt_req),

        .spi_data_in(qspi_data_in),
        .spi_data_out(qspi_data_out),
        .spi_data_oe(qspi_data_oe),
        .spi_clk_out(qspi_clk_out),
        .spi_flash_select(qspi_flash_select),
        .spi_ram_a_select(qspi_ram_a_select),
        .spi_ram_b_select(qspi_ram_b_select),

        /* verilator lint_off PINCONNECTEMPTY */
        .debug_instr_complete(),
        .debug_instr_ready(),
        .debug_instr_valid(),
        .debug_fetch_restart(),
        .debug_data_ready(),
        .debug_interrupt_pending(),
        .debug_branch(),
        .debug_early_branch(),
        .debug_ret(),
        .debug_reg_wen(),
        .debug_counter_0(counter_0),
        .debug_data_continue(),
        .debug_stall_txn(),
        .debug_stop_txn(),
        .debug_rd()
        /* verilator lint_on PINCONNECTEMPTY */
    );

    // Outputs: uo[0] UART TX, uo[1] UART RTS (or GPIO 0/1 when selected), uo[7:2] GPIO
    assign uo_out[0]   = gpio_out_sel[0] ? gpio_out[0] : uart_txd;
    assign uo_out[1]   = gpio_out_sel[1] ? gpio_out[1] : uart_rts;
    assign uo_out[7:2] = gpio_out[7:2];

    // CPU nibble phase 0..7, locked to TinyQV's nibble counter (counter_0 = phase 0)
    reg [2:0] nib_phase;
    always @(posedge clk) begin
        nib_phase <= counter_0 ? 3'd1 : nib_phase + 3'd1;
    end

    // Read data. TinyQV consumes data_in[4k+3:4k] while its nibble counter is k
    // (sign extension uses the current nibble too), so only the current nibble
    // is selected and replicated over the 32-bit bus: a 4-bit mux instead of 32.
    reg [7:0] rd_byte;
    reg [3:0] rd_nib;
    always @(*) begin
        case (connect_peripheral)
            PERI_GPIO_OUT:     rd_byte = uo_out;
            PERI_GPIO_IN:      rd_byte = ui_in;
            PERI_GPIO_OUT_SEL: rd_byte = {6'b111111, gpio_out_sel};
            PERI_UART:         rd_byte = uart_rx_data;
            PERI_UART_STATUS:  rd_byte = {6'b000000, uart_rx_valid, uart_tx_busy};
            default:           rd_byte = 8'hFF;
        endcase
        case (connect_peripheral)
            PERI_TIMER_COUNT: rd_nib = timer_cnt_nib;
            PERI_TIMER_CMP:   rd_nib = timer_cmp_nib;
            PERI_UART_DIV:    rd_nib = (nib_phase == 3'd0) ? uart_div[3:0] :
                                       (nib_phase == 3'd1) ? uart_div[7:4] :
                                       (nib_phase == 3'd2) ? uart_div[11:8] :
                                       (nib_phase == 3'd3) ? {3'b000, uart_div[12]} : 4'h0;
            PERI_GPIO_OUT, PERI_GPIO_IN, PERI_GPIO_OUT_SEL, PERI_UART, PERI_UART_STATUS:
                              rd_nib = (nib_phase == 3'd0) ? rd_byte[3:0] :
                                       (nib_phase == 3'd1) ? rd_byte[7:4] : 4'h0;
            default:          rd_nib = 4'hF;   // unmapped: reads 0xFFFFFFFF
        endcase
        data_from_read = {8{rd_nib}};
    end

    // GPIO out and UART divisor registers
    always @(posedge clk) begin
        if (!rst_reg_n) begin
            gpio_out_sel <= 2'b00;
            gpio_out     <= 8'h00;
            uart_div     <= UART_DIV_RESET;
        end else if (peri_write) begin
            if (connect_peripheral == PERI_GPIO_OUT)     gpio_out     <= data_to_write[7:0];
            if (connect_peripheral == PERI_GPIO_OUT_SEL) gpio_out_sel <= data_to_write[1:0];
            if (connect_peripheral == PERI_UART_DIV)     uart_div     <= data_to_write[UART_DIV_BITS-1:0];
        end
    end

    uart_tx #(.DIV_BITS(UART_DIV_BITS)) i_uart_tx(
        .clk(clk),
        .resetn(rst_reg_n),
        .cycles_per_bit(uart_div),
        .uart_txd(uart_txd),
        .uart_tx_en(peri_write && connect_peripheral == PERI_UART),
        .uart_tx_data(data_to_write[7:0]),
        .uart_tx_busy(uart_tx_busy)
    );

    uart_rx #(.DIV_BITS(UART_DIV_BITS)) i_uart_rx(
        .clk(clk),
        .resetn(rst_reg_n),
        .cycles_per_bit(uart_div),
        .uart_rxd(uart_rxd),
        .uart_rts(uart_rts),
        .uart_rx_read(connect_peripheral == PERI_UART && read_complete),
        .uart_rx_valid(uart_rx_valid),
        .uart_rx_data(uart_rx_data)
    );

    rvsoc_timer i_timer(
        .clk(clk),
        .rstn(rst_reg_n),
        .phase(nib_phase),
        .wdata(data_to_write),
        .wr_count(peri_write && connect_peripheral == PERI_TIMER_COUNT),
        .wr_cmp(peri_write && connect_peripheral == PERI_TIMER_CMP),
        .cnt_nib(timer_cnt_nib),
        .cmp_nib(timer_cmp_nib),
        .irq(timer_irq)
    );

    // read_n is only needed by the CPU-side handshake
    wire _unused = &{ena, read_n, uio_in[7:6], uio_in[3], uio_in[0], 1'b0};

endmodule
