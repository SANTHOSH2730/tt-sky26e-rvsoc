# SPDX-FileCopyrightText: © 2024 Michael Bell, © 2026 Santhosh and Dr. O. Vignesh
# SPDX-License-Identifier: Apache-2.0
"""Shared helpers: clock, reset sequence, UART monitor/driver."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Event, with_timeout

CLK_NS = 15.624            # 64 MHz (cocotb needs an even number of ps)
UART_DIV_DEFAULT = 555     # 115200 baud at 64 MHz (clocks per bit - 1)
UART_DIV_FAST = 31         # 2 Mbaud, set by the firmware when ui_in[4] = 1

UI_FAST = 0x10             # ui_in[4]: firmware simulation speed-up
UI_MODE_MIRROR = 0x04      # ui_in[3:2] = 01: GPIO mirror mode


def start_clock(dut, period_ns=CLK_NS):
    cocotb.start_soon(Clock(dut.clk, period_ns, unit="ns").start())


async def reset(dut, latency=1, ui_in=0x80, use_model=False):
    """TinyQV reset: hold rst_n low with the QSPI read latency on SD2:SD0."""
    dut._log.info(f"Reset, latency {latency}, ui_in 0x{ui_in:02x}, model {use_model}")
    dut.ena.value = 1
    dut.ui_in_base.value = ui_in & 0x7F
    dut.uart_rx.value = 1
    dut.use_model.value = 1 if use_model else 0
    dut.qspi_data_in.value = 0
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    dut.rst_n.value = 0
    dut.latency_cfg.value = latency
    await ClockCycles(dut.clk, 1)
    assert dut.uio_oe.value == 0
    await ClockCycles(dut.clk, 9)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)
    assert dut.uio_oe.value == 0b11001001


class UartMonitor:
    """Collects bytes decoded by the Verilog UART monitor in tb.v."""

    def __init__(self, dut):
        self.dut = dut
        self.buf = bytearray()
        self.got_line = Event()
        self.last_count = int(dut.uart_mon_count.value)
        cocotb.start_soon(self._collect())

    async def _collect(self):
        while True:
            await self.dut.uart_mon_count.value_change
            count = int(self.dut.uart_mon_count.value)
            if count != self.last_count:
                self.last_count = count
                b = int(self.dut.uart_mon_byte.value)
                self.buf.append(b)
                if b == 0x0A:
                    self.got_line.set()

    async def readline(self, timeout_us=5000):
        while b"\n" not in self.buf:
            self.got_line.clear()
            try:
                await with_timeout(self.got_line.wait(), timeout_us, "us")
            except Exception:
                raise AssertionError(f"UART timeout after {timeout_us} us, received so far: {bytes(self.buf)!r}")
        i = self.buf.index(b"\n")
        line = bytes(self.buf[: i + 1]).decode(errors="replace")
        del self.buf[: i + 1]
        self.dut._log.info(f"UART: {line!r}")
        return line

    async def expect_line(self, expected, timeout_us=5000):
        line = await self.readline(timeout_us)
        assert line == expected, f"expected {expected!r}, got {line!r}"


async def uart_send(dut, data, div):
    """Bit-bang bytes into ui_in[7] (UART RX of the chip), 8N1."""
    for byte in data:
        dut.uart_rx.value = 0
        await ClockCycles(dut.clk, div + 1)
        for i in range(8):
            dut.uart_rx.value = (byte >> i) & 1
            await ClockCycles(dut.clk, div + 1)
        dut.uart_rx.value = 1
        await ClockCycles(dut.clk, div + 1)


async def boot_firmware(dut, ui_in=UI_FAST, latency=1):
    """Reset with the flash/PSRAM model, check the boot banner, return the monitor."""
    dut.uart_mon_div.value = UART_DIV_DEFAULT
    # In FAST mode the firmware sets UART_DIV=31 (2 Mbaud) before printing anything
    dut.uart_mon_div.value = UART_DIV_FAST if (ui_in & UI_FAST) else UART_DIV_DEFAULT
    await reset(dut, latency=latency, ui_in=ui_in, use_model=True)
    mon = UartMonitor(dut)
    await mon.expect_line("Hello, TT!\r\n", timeout_us=4000)
    return mon
