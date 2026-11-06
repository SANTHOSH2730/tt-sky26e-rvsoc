#!/usr/bin/env bash
# One hardening iteration with the official Tiny Tapeout flow
# (tt-support-tools + LibreLane in Docker), exactly as in
# https://www.tinytapeout.com/guides/local-hardening
#
# Usage: scripts/harden.sh <label> ["notes for reports/sweep.md"]
# Results: runs/wokwi (flow output), logs/harden_<label>.log, a row in reports/sweep.md
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source scripts/env.sh
LABEL="${1:-manual}"
NOTES="${2:-}"
mkdir -p logs reports
LOG="logs/harden_${LABEL}.log"

echo "[harden $LABEL] create-user-config"
./tt/tt_tool.py --pdk "$PDK" --create-user-config > "$LOG" 2>&1 || { tail -20 "$LOG"; exit 1; }
echo "[harden $LABEL] harden (LibreLane $LIBRELANE_TAG in Docker) - log: $LOG"
./tt/tt_tool.py --pdk "$PDK" --harden >> "$LOG" 2>&1
rc=$?
echo "[harden $LABEL] flow exit code $rc"
./tt/tt_tool.py --pdk "$PDK" --print-warnings > "logs/warnings_${LABEL}.log" 2>&1
./tt/tt_tool.py --pdk "$PDK" --print-stats    > "logs/stats_${LABEL}.log" 2>&1
./tt/tt_tool.py --pdk "$PDK" --print-cell-category > "logs/cells_${LABEL}.log" 2>&1
python scripts/metrics.py runs/wokwi "$LABEL" "$NOTES"
mkdir -p "runs/iterations/$LABEL"
cp runs/wokwi/final/metrics.json "runs/iterations/$LABEL/" 2>/dev/null || true
exit $rc
