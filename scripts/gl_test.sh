#!/usr/bin/env bash
# Gate-level simulation of the hardened design with the same cocotb tests,
# as in the Tiny Tapeout GL-test action (powered netlist + sky130 cell models).
#   scripts/gl_test.sh                 all tests
#   GL_FILTER=test_boot_hello scripts/gl_test.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source scripts/env.sh
TOP=$(./tt/tt_tool.py --pdk "$PDK" --print-top-module)
NL="runs/wokwi/final/pnl/$TOP.pnl.v"
[ -f "$NL" ] || { echo "no netlist $NL - harden first"; exit 1; }
cp "$NL" test/gate_level_netlist.v
cd test
make -B GATES=yes ${GL_FILTER:+COCOTB_TEST_FILTER=$GL_FILTER} ${GL_MODULES:+COCOTB_TEST_MODULES=$GL_MODULES} \
    > ../logs/gl_test.log 2>&1
cp results.xml ../logs/gl_results.xml 2>/dev/null
grep -E "\*\* test|TESTS=" ../logs/gl_test.log | cut -c1-160
python -m cocotb_tools.check_results results.xml
