# STATUS: tt_um_santhosh_rvsoc (Tiny Tapeout SKY 26d)

Updated after each phase. Raw logs: `logs/`. Numbers: `reports/summary.md`, `reports/sweep.md`.

## Parameters used

| Parameter | Value | Note |
|-----------|-------|------|
| GH_USER | `SANTHOSH2730` (GitHub) | Top module stays `tt_um_santhosh_rvsoc` (your decision, 6 Nov 2026): Tiny Tapeout only needs a unique `tt_um_` name, and keeping it avoids another 5-hour hardening run. The repository goes under your GitHub account |
| PROJECT_DIR | `~/tt-sky26d-rvsoc` | |
| DESIGN_MODE | adapt-upstream | TT06 TinyQV is Apache-2.0 (permissive) |
| AUTO_PUSH | no | nothing pushed |
| FPGA | PYNQ-Z2 (xc7z020) | flash/PSRAM emulated in BRAM |

## Phase log

1. **Environment.** WSL Ubuntu 22.04 had no network (the Windows vEthernet adapter
   was stuck at 169.254.x). With your approval, `networkingMode=mirrored` was added
   to `C:\Users\santh\.wslconfig` (delete that line to undo). Installed into
   `~/ttsetup` exactly as in the TT local-hardening guide: Python 3.12 venv (uv),
   tt-support-tools (main, 37f5534), LibreLane 3.0.14, cocotb 2.1.0, sky130A PDK
   8afc8346 (the version pinned by LibreLane), Docker image
   ghcr.io/librelane/librelane:3.0.14, and xPack riscv-none-elf-gcc 14.3.0 (RV32E).
   Your existing tools and `~/.ciel` PDK were not modified.
2. **Scaffold.** Cloned TinyTapeout/ttsky-verilog-template (the SKY 26d template;
   the GDS action is pinned to `tt-gds-action@ttsky26d`). tt-support-tools is
   cloned into `tt/` as the guide says (not a submodule: the GitHub action checks
   it out into `tt/` itself).
3. **RTL.** Upstream: MichaelBell/tt06-tinyQV with tinyQV core at dfbd5e38 (the
   original 2x2 TT06 version). Changes are listed in `src/tinyQV/UPSTREAM.txt` and
   `docs/info.md`.
4. **Firmware + tests.** RTL tests pass (see reports). Two upstream core bugs were
   found by the ISA self-test and fixed (FENCE stalled the CPU; CSR immediate
   forms used a register).
5. **Hardening.** 8 iterations at 2x2 (the spec's budget); iteration 8 passes every
   check: Magic DRC 0, LVS clean, antenna 0, hold met at all 9 corners, setup met
   at tt (+1.59 ns). `runs/wokwi` is that run; details in `reports/sweep.md`.
6. **Tiny Tapeout precheck.** Passed locally (`scripts/precheck.sh`, same checks as
   the GitHub Action); reports in `reports/precheck/`.
7. **Gate-level tests.** Same cocotb tests on the powered post-route netlist:
   11/11 pass in 56 min, cycle-identical to RTL (`reports/summary.md`).
8. **FPGA.** PYNQ-Z2 harness simulated end to end (PASS). Vivado 2025.1 found at
   `C:\Xilinx\2025.1`. Board test deferred (board not at hand).
9. **Documentation.** `docs/DESIGN_REPORT.md` (full report with figures),
   `docs/info.md`, `docs/IO_GUIDE.md`, `docs/fpga.md`.

## Decisions

- **Peripherals (MVP):** kept upstream GPIO and UART addresses; removed the
  upstream SPI controller, debug UART and debug-signal muxes (not in the spec,
  and they cost area); added TIMER_COUNT/TIMER_CMP at 0x8000028/0x800002C and
  UART_DIV at 0x8000034, in addresses upstream left unused.
- **Interrupt 3** is now the timer (upstream: "UART TX idle"). Interrupts 0/1
  (ui[0]/ui[1] rising edge) and 2 (UART RX) are unchanged.
- **Timer** is nibble-serial like the CPU: COUNT/CMP rotate 4 bits per clock in
  step with the CPU's nibble counter, with a 4-bit incrementer and comparator. It
  counts every 8 clocks, and a 32-bit read is never torn. This saved ~900 um2
  versus a parallel 32-bit timer.
- **Area for 2x2:** iterations 1-2 overflowed the 2x2 core (81.6 % utilisation
  before buffering). Removed TinyQV's custom 16-bit multiplier (~2400 um2; only
  used by non-standard instructions the compiler never emits) and made the timer
  serial (~900 um2): synthesised area 47.6k -> 44.2k um2 (tt lib, hierarchical).
- **More area for routability (iteration 4):** iteration 3 placed and met timing
  but global routing was 98.6 % full and detailed routing did not converge. So
  the Zicntr counters (rdcycle/rdtime/rdinstret, ~1600 um2; not required by the
  spec, TIMER_COUNT gives time) were removed, the peripheral read bus was made
  4 bits wide (TinyQV only consumes one nibble per clock), and
  MAX_FANOUT_CONSTRAINT was raised to 16 (fewer fanout-only buffers; slew and
  cap are still repaired).
- **Hold margins** set to PL 0.0 / GRT 0.02 ns (TT default 0.1 / 0.05): TinyQV's
  rotating register file has ~460 flop-to-flop paths just under 0.1 ns, and
  buffering them all overflowed 2x2 (290 buffers at 0.05 / 0.03, 3 at 0.0 / 0.02).
  Signoff still requires hold >= 0 at all corners; final worst hold slack +0.0096 ns.
- **Placement density 86 %** (TT default 60): the placer never spreads this design
  below 84 %, so lower values had no effect; 86 % shortened wiring enough for
  detailed routing to reach 0 violations.
- **Max slew** warnings (753 pins at tt) are left as they are: the flow does not
  enforce slew, all come from 94 weak fanout buffers (`clkdlybuf4s25_1`) the
  resizer chose, STA includes them and setup still passes. A fix would need
  another hardening run beyond the 8-run budget (see `reports/sweep.md`).
- **uo[7:2]** are always GPIO; GPIO_SEL only switches uo[1:0] (UART TX/RTS).
- **FENCE** is decoded as a NOP; **CSRRWI/CSRRSI/CSRRCI** use their immediate
  (zimm[4] is not available in this core and reads as 0).
- **Timing signoff:** the TT/LibreLane flow enforces setup at the typical
  corners (`TIMING_VIOLATION_CORNERS = *tt*`) and hold at all corners. The 64 MHz
  CPU path does not close at the slow corner (ss, 100 C, 1.60 V), and repairing
  it over-fills 2x2, so `RSZ_CORNERS` is set to tt + ff. The ss slack is reported
  in `reports/summary.md`.
- **Firmware modes** are chosen with ui[3:2] at reset; ui[4] = simulation-only
  fast mode (2 Mbaud). One image serves simulation, FPGA and silicon.
- **Simulation:** Icarus 11 needs `+timescale+1ns/1ps` because TinyQV's register
  file uses `buf #1` (cocotb's Makefile already passes it).

## Your remaining manual steps

1. Top module name: kept as `tt_um_santhosh_rvsoc` (decided). If Tiny Tapeout ever
   reports it as taken, rename with `scripts/set_gh_user.sh <name>` and re-harden.
2. Create the GitHub repo under SANTHOSH2730, push, and enable Actions + Pages (docs:
   Settings > Pages > Source: GitHub Actions). Not done because AUTO_PUSH=no.
3. Check that the gds, docs, test and fpga workflows pass on GitHub.
4. Submit the repo at app.tinytapeout.com (SKY 26d) before **30 Nov 2026**.
5. FPGA hardware test: **deferred by you until the PYNQ-Z2 is at hand.** The FPGA
   harness already passes in simulation (`make -C fpga sim`). When the board is
   available, ask Claude to connect, build the bitstream
   (`fpga/pynq_z2/build_on_windows.ps1 -Program`) and run the checks in
   `docs/fpga.md` section 4.
