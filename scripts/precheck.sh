#!/usr/bin/env bash
# Run the Tiny Tapeout precheck locally: the same checks as the tt-gds-action
# "precheck" job (Magic DRC, KLayout FEOL/BEOL/offgrid/zero-area DRC, pin,
# boundary, power-pin, layer, cell-name, urpm/nwell and Verilog checks).
#
# The precheck needs Magic >= 8.3.568 and KLayout >= 0.30.4 (tt/precheck/
# tool-versions.json). The Ubuntu 22.04 packages are older, so small wrapper
# commands run the versions inside the LibreLane container instead; the Python
# side runs in its own venv (~/ttsetup/precheck-venv).
#
#   scripts/precheck.sh        -> logs/precheck.log, exit 0 when all checks pass
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source scripts/env.sh

PV="$TTSETUP/precheck-venv"
if [ ! -x "$PV/bin/python" ]; then
  echo "[precheck] creating $PV"
  uv venv -q --python 3.12 "$PV" && uv pip install -q --python "$PV/bin/python" -r tt/precheck/requirements.txt \
    || { echo "precheck venv install failed"; exit 1; }
fi

BIN="$TTSETUP/precheck-bin"
mkdir -p "$BIN"
for t in magic klayout; do
  cat > "$BIN/$t" <<EOF
#!/bin/sh
# $t from the LibreLane $LIBRELANE_TAG container (host version too old for the TT precheck)
exec docker run --rm -i --user $(id -u):$(id -g) -v $HOME:$HOME -w "\$PWD" \\
  -e PDK_ROOT="$PDK_ROOT" -e PDK="$PDK" -e HOME="$HOME" \\
  ghcr.io/librelane/librelane:$LIBRELANE_TAG $t "\$@"
EOF
  chmod +x "$BIN/$t"
done

echo "[precheck] creating tt_submission/"
./tt/tt_tool.py --pdk "$PDK" --create-tt-submission > logs/tt_submission.log 2>&1 || { tail -20 logs/tt_submission.log; exit 1; }
TOP=$(./tt/tt_tool.py --pdk "$PDK" --print-top-module)
GDS="$ROOT/tt_submission/$TOP.gds"
[ -f "$GDS" ] || { echo "no $GDS"; exit 1; }

echo "[precheck] running TT precheck on $GDS (log: logs/precheck.log)"
cd tt/precheck
PATH="$BIN:$PV/bin:$PATH" python precheck.py --gds "$GDS" > "$ROOT/logs/precheck.log" 2>&1
rc=$?
cd "$ROOT"
grep -E "INFO: (Running|.*passed|.*PASSED)|ERROR|FAIL|Precheck|precheck" logs/precheck.log | tail -40
echo "[precheck] exit code $rc"
exit $rc
