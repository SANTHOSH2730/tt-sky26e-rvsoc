# Hardening sweep

Every hardening iteration of the Tiny Tapeout flow (tt-support-tools + LibreLane 3.0.14,
sky130A, 2x2 tiles, clock 15.625 ns = 64 MHz). Iterations 5-8 ran in parallel scratch
copies (`.work/itN`, identical RTL unless noted). Setup WNS is given for the tt corner the
flow signs off (and for ss, which it does not enforce); hold WNS is the worst of all 9
corners. DRC = Magic DRC, LVS = Netgen. "-" = the run stopped before that number existed.

| Iter | Density % | Change tried | Furthest step | Util | GRT usage / overflows | Setup WNS tt (ss) ns | Hold WNS ns | DRC | LVS | Antenna nets | Result |
|---|---|---|---|---|---|---|---|---|---|---|---|
| it1 | 60 | TT template defaults | detailed placement | 83 % | - | +2.8 (-7.0) | - | - | - | - | FAIL DPL-0036: setup repair at the ss corner over-filled the core |
| it2 | 80 | `RSZ_CORNERS` = tt + ff; FENCE/CSR fixes | detailed placement | 90.5 % | - | +3.5 | - | - | - | - | FAIL DPL-0036: 300+ hold buffers for the 0.1 ns hold margin |
| it3 | 80 | no custom multiplier, nibble-serial timer, hold margin 0.05 / 0.03 | detailed routing | 82.9 % | 98.6 % / 4014 | met | met | - | - | - | STOPPED: routing violations not converging (36.7k -> 37.0k) |
| it4 | 80 | no Zicntr counters, 4-bit read bus, `MAX_FANOUT_CONSTRAINT` 16 | detailed routing | 82.7 % | 85.0 % / 1405 | +3.5 | met | - | - | - | STOPPED: 7411 violations after 9 passes, plateauing; 290 hold buffers |
| it5 | 75 | it4 without the register-file delay cells | hold repair | 82.1 % | - | - | - | - | - | - | STOPPED: hold repair added 641 buffers instead (delay cells kept) |
| it6 | 80 | it4 + hold margins PL 0.0 / GRT 0.02 | detailed routing | - | 68.85 % / 378 | met | met | - | - | - | STOPPED after it8 passed: 3 hold buffers; routing stuck at 2-3 violations for 50+ passes |
| it7 | 77 | it6 + density 77 | global routing | - | 68.85 % / 378 | - | - | - | - | - | STOPPED: identical to it6 (the placer raises any target below 84 % to 0.84, GPL-0302) |
| **it8** | **86** | **it6 + density 86** | **signoff** | **78.4 %** | **64.80 % / 165** | **+1.587 (-12.17)** | **+0.0096** | **0** | **clean** | **0** | **PASS: 0 routing violations at pass 20; final design** |

## Final layout (it8) in numbers

From `runs/wokwi/final/metrics.json` (copied to `runs/iterations/it8/`):

| Metric | Value |
|---|---|
| Die / core area | 334.88 x 225.76 um (75,603 um2) / 72,565 um2 |
| Standard cells | 5,752 instances (incl. 1,037 tap cells), 56,923 um2; plus 5,145 fill/decap cells (15,641 um2) |
| Logic | 2,870 combinational cells, 986 flip-flops, 169 clock-tree cells, 66 antenna diodes |
| Placement utilisation | 78.4 % (tt_tool: 83.3 % routing utilisation) |
| Routed wire length | 198,673 um |
| Timing-repair buffers / hold buffers | 132 / 0 |
| Antenna repair | 10 -> 2 -> 1 -> 0 violating nets over three repair rounds |
| Setup WNS at tt (nom / min / max) | +1.991 / +2.407 / +1.587 ns |
| Setup WNS at ff | +4.41 ns |
| Setup WNS at ss (not enforced) | -12.17 ns (274 endpoints): at ss, 100 C, 1.60 V the logic would need a ~28 ns period (~36 MHz) |
| Hold WNS (worst, min_ff) | +0.0096 ns, 0 violations at all 9 corners |
| Magic DRC / Netgen LVS / antenna | 0 / clean / 0 |
| Max slew (informational) | 753 pins at nom_tt, worst 1.40 ns vs 0.75 ns target (see note) |
| Max capacitance | 0 at tt and ff; 24 at ss |
| Power at tt, 64 MHz (STA estimate) | 6.6 mW (internal 4.5, switching 2.1, leakage 0.07 uW) |
| IR drop (worst) | 0.17 mV |

**Note on max slew.** The flow does not treat slew or capacitance as failures
(`MAX_SLEW_VIOLATION_CORNERS` and `MAX_CAP_VIOLATION_CORNERS` are empty). All of the tt slew
violations come from one cause: the resizer chose the delay cell `sky130_fd_sc_hd__clkdlybuf4s25_1`
for all 94 fanout buffers, and a few of them drive 16 loads. STA includes these slow edges in
its delay calculation, setup still has +1.59 ns at tt, and the worst tt slew (1.49 ns at
max_tt) is inside the 1.5 ns range the sky130_fd_sc_hd liberty tables are characterised for.
For a future revision, excluding `clkdlybuf4s*` from the resizer's buffer choice would remove
them; this was not done here because the 2x2 iteration budget (8) was used.
