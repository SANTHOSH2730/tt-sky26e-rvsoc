# Tests for tt_um_santhosh_rvsoc

cocotb 2.1 + Icarus Verilog. The same tests run on the RTL and on the hardened
gate-level netlist.

| File | What it checks |
|------|----------------|
| `test_soc.py` | Real firmware (`rvsoc_fw.hex`, built from `../firmware`) running from the QSPI flash model, seen only through the pins: boot + `Hello, TT!` (3 QSPI latencies), ISA self-test, PSRAM A/B write/read-back (also checked inside the PSRAM models), timer interrupt (self-test + 100 ms-style LED steps measured on the pins), GPIO write/read-back and input->output loopback, UART RX echo, external interrupts on ui[0]/ui[1] |
| `test_isa_random.py` | Upstream TinyQV instruction-level tests: Python drives the QSPI bus directly and checks random RV32EC ALU / load / store sequences against a reference model (riscv-model). Fewer seeds on gate level; set `RANDOM_SEEDS=n` to override |
| `tb.v` | Testbench: flash + 2 PSRAM model (`sim_qspi.v`, from upstream TinyQV) with programmable read latency, and a UART monitor on uo[0] |

```
make                                   # RTL, all tests
make COCOTB_TEST_FILTER=test_timer_irq # one test
make GATES=yes                         # gate level (copy the netlist first: ../scripts/gl_test.sh does it)
make EXTRA_DEFINES="-DTRACE_FETCH -DTRACE_TIMER"   # print QSPI fetches / timer activity
gtkwave tb.fst tb.gtkw                 # waveform of the pins
```

`rvsoc_fw.hex` is committed, so CI does not need a RISC-V compiler. Rebuild it
with `make -C ../firmware && cp ../firmware/build/rvsoc_fw.hex .`.
