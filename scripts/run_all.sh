#!/usr/bin/env bash
# End-to-end flow for tt_um_santhosh_rvsoc, from a clean checkout:
#   1 preflight/install   2 firmware   3 RTL tests   4 FPGA harness sim
#   5 harden (Tiny Tapeout flow)   6 TT precheck   7 gate-level tests
#   8 reports (summary, layout render, PDFs)
# Every step's output is mirrored to logs/live.log (watch: tail -F logs/live.log).
#   scripts/run_all.sh              everything
#   SKIP_HARDEN=1 scripts/run_all.sh   reuse the existing runs/wokwi
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p logs reports
L=scripts/live.sh
FAIL=0
step() { local name="$1"; shift; "$L" "$name" "$@" || { echo "!! step failed: $name"; FAIL=$((FAIL+1)); }; }

step "1/8 preflight (scripts/check_env.sh)" scripts/check_env.sh
source scripts/env.sh

step "2/8 firmware" bash -c "make -C firmware && cp firmware/build/rvsoc_fw.hex test/rvsoc_fw.hex"

step "3/8 RTL tests" bash -c "cd test && make -B > ../logs/rtl_test.log 2>&1; cp results.xml ../logs/rtl_results.xml; \
    grep -E '\*\* test|TESTS=' ../logs/rtl_test.log; python -m cocotb_tools.check_results results.xml"

step "4/8 FPGA harness simulation" make -C fpga sim

if [ "${SKIP_HARDEN:-0}" != "1" ]; then
  step "5/8 harden (LibreLane $LIBRELANE_TAG, Docker)" scripts/harden.sh final "run_all.sh"
fi
test -f runs/wokwi/final/gds/*.gds || { echo "!! no GDS produced"; FAIL=$((FAIL+1)); }

step "6/8 Tiny Tapeout precheck" scripts/precheck.sh

step "7/8 gate-level tests" scripts/gl_test.sh

step "8/8 reports" bash -c "python scripts/make_summary.py && \
    ./tt/tt_tool.py --pdk $PDK --create-png > logs/render.log 2>&1; \
    scripts/docs/make_pdf.sh || echo '(PDFs need a Chromium-based browser; skipped)'"

echo
if [ $FAIL = 0 ]; then echo "run_all: ALL STEPS PASSED"; else echo "run_all: $FAIL step(s) failed"; fi
exit $FAIL
