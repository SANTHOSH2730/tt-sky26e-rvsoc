# SPDX-FileCopyrightText: © 2026 Santhosh and Dr. O. Vignesh
# SPDX-License-Identifier: Apache-2.0
"""System tests: real firmware (firmware/ -> test/rvsoc_fw.hex) running from the
QSPI flash model, observed only through the chip pins."""

import random

import cocotb
from cocotb.triggers import ClockCycles
from cocotb.utils import get_sim_time

from test_util import (CLK_NS, UART_DIV_FAST, UI_FAST, UI_MODE_MIRROR, boot_firmware,
                       start_clock, uart_send)


@cocotb.test()
async def test_boot_hello(dut):
    """Boots from flash and prints 'Hello, TT!' on uo_out[0]: at the default
    115200 baud (latency 1), then in fast mode for QSPI read latencies 2 and 3."""
    start_clock(dut)
    for latency, ui in ((1, 0x00), (2, UI_FAST), (3, UI_FAST)):
        t0 = get_sim_time("us")
        await boot_firmware(dut, ui_in=ui, latency=latency)
        dut._log.info(f"latency {latency}: banner after {get_sim_time('us') - t0:.0f} us")
        assert int(dut.uart_mon_errors.value) == 0


@cocotb.test()
async def test_isa_selftest(dut):
    """Firmware ISA self-test (all RV32EC + Zicsr + Zicntr + trap instructions) passes."""
    start_clock(dut)
    mon = await boot_firmware(dut)
    await mon.expect_line("ISA PASS\r\n", timeout_us=2000)


@cocotb.test()
async def test_psram(dut):
    """PSRAM A and B write/read-back; also checks the data really landed in the PSRAM models."""
    start_clock(dut)
    mon = await boot_firmware(dut)
    await mon.expect_line("ISA PASS\r\n", timeout_us=2000)
    await mon.expect_line("PSRAM PASS\r\n", timeout_us=2000)

    def model_word(mem, addr):
        return sum(int(mem[addr + i].value) << (8 * i) for i in range(4))

    pa, pb = 0x12345678, 0xA5A55A5A
    for i in range(16):
        assert model_word(dut.qspi.ram_a, 0x8000 + 4 * i) == pa, f"PSRAM A word {i}"
        assert model_word(dut.qspi.ram_b, 0x0100 + 4 * i) == pb, f"PSRAM B word {i}"
        pa = (pa + 0x11111111) & 0xFFFFFFFF
        pb = ((pb ^ 0x0F0F0F0F) + 0x01010101) & 0xFFFFFFFF
    assert model_word(dut.qspi.ram_a, 0x8040) == 0xC3C2C1C0


@cocotb.test()
async def test_timer_irq(dut):
    """Timer compare interrupt fires and is serviced: self-test line, then the
    interrupt-driven LED chaser on uo_out[7:2] steps every 2000 timer ticks."""
    start_clock(dut)
    mon = await boot_firmware(dut)
    for name in ("ISA", "PSRAM", "TIMER", "GPIO"):
        await mon.expect_line(f"{name} PASS\r\n", timeout_us=2000)
    await mon.expect_line("SELFTEST PASS\r\n", timeout_us=500)

    # Demo mode: one LED step per timer interrupt (2000 ticks x 8 clocks = 16000 clocks)
    def leds():
        return (int(dut.uo_out.value) >> 2) & 0x3F

    times, last = [], leds()
    for _ in range(200000):
        await ClockCycles(dut.clk, 16)
        now = leds()
        if now != last:
            last = now
            times.append(get_sim_time("ns"))
            assert bin(now).count("1") == 1, f"LED pattern 0x{now:02x}"
            if len(times) == 5:
                break
    assert len(times) == 5, "LED chaser did not step"
    for a, b in zip(times[1:], times[2:]):
        period_clk = (b - a) / CLK_NS
        assert 15500 < period_clk < 16500, f"tick period {period_clk:.0f} clocks"
    await mon.expect_line("tick 10\r\n", timeout_us=3000)


@cocotb.test()
async def test_gpio_loopback(dut):
    """GPIO: firmware write/read-back passes, then in mirror mode uo_out[7:2]
    follows ui_in[7:2] for random input patterns."""
    start_clock(dut)
    mon = await boot_firmware(dut, ui_in=UI_FAST | UI_MODE_MIRROR)
    await mon.expect_line("GPIO PASS\r\n", timeout_us=1000)
    await mon.expect_line("MIRROR\r\n", timeout_us=500)
    await ClockCycles(dut.clk, 400)
    for _ in range(12):
        v = random.randint(0, 255)
        dut.ui_in_base.value = v & 0x7F
        dut.uart_rx.value = v >> 7
        await ClockCycles(dut.clk, 400)
        out = int(dut.uo_out.value)
        assert (out & 0xFC) == (v & 0xFC), f"ui_in 0x{v:02x} -> uo_out 0x{out:02x}"
        assert out & 1 == 1, "UART TX must idle high"


@cocotb.test()
async def test_uart_echo(dut):
    """UART RX on ui_in[7]: characters are echoed back by the demo firmware."""
    start_clock(dut)
    mon = await boot_firmware(dut)
    for name in ("ISA", "PSRAM", "TIMER", "GPIO", "SELFTEST"):
        await mon.expect_line(f"{name} PASS\r\n", timeout_us=2000)
    await ClockCycles(dut.clk, 6400)            # 100 us: let the demo loop start
    # The UART has a 1-byte receive buffer and the demo polls it, so type like a
    # person: one character, wait for its echo, then the next.
    for ch in b"Hi TT\r":
        n = len(mon.buf)
        await uart_send(dut, bytes([ch]), UART_DIV_FAST)
        for _ in range(2000):
            if len(mon.buf) > n:
                break
            await ClockCycles(dut.clk, 64)
        assert len(mon.buf) > n, f"no echo for {chr(ch)!r}"
    line = await mon.readline(timeout_us=2000)
    while line.startswith("tick"):
        line = await mon.readline(timeout_us=2000)
    assert line == "Hi TT\r\n", f"echo {line!r}"


@cocotb.test()
async def test_ext_irq(dut):
    """External interrupts: a rising edge on ui_in[0] / ui_in[1] runs the
    interrupt handler, which reports IRQ0 / IRQ1 on the UART."""
    start_clock(dut)
    mon = await boot_firmware(dut)
    for name in ("ISA", "PSRAM", "TIMER", "GPIO", "SELFTEST"):
        await mon.expect_line(f"{name} PASS\r\n", timeout_us=2000)
    await ClockCycles(dut.clk, 6400)            # 100 us: demo loop has enabled the pin IRQs
    base = int(dut.ui_in_base.value)
    for bit, expected in ((0, "IRQ0\r\n"), (1, "IRQ1\r\n")):
        dut.ui_in_base.value = base | (1 << bit)
        await ClockCycles(dut.clk, 200)
        dut.ui_in_base.value = base
        line = await mon.readline(timeout_us=1000)
        while line.startswith("tick"):
            line = await mon.readline(timeout_us=1000)
        assert line == expected, f"ui_in[{bit}] edge -> {line!r}"
