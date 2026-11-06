#!/usr/bin/env bash
# Hardening sweep over flow knobs, logged to reports/sweep.md.
# Each line of the sweep list: <label> <tiles> <clock_period_ns> <density_pct> [notes...]
# The best passing configuration is NOT applied automatically; src/config.json and
# info.yaml are restored afterwards.
#   scripts/sweep_tiles.sh                 default list below
#   scripts/sweep_tiles.sh my_sweep.txt    your own list
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
LIST="${1:-}"
DEFAULT_LIST="sw1 2x2 15.625 75 64MHz
sw2 2x2 15.625 85 64MHz
sw3 2x2 20 80 50MHz"
cp src/config.json /tmp/rvsoc_config.json.bak
cp info.yaml /tmp/rvsoc_info.yaml.bak
restore() { cp /tmp/rvsoc_config.json.bak src/config.json; cp /tmp/rvsoc_info.yaml.bak info.yaml; }
trap restore EXIT

while read -r label tiles clk dens notes; do
  [ -z "${label:-}" ] && continue
  case "$label" in \#*) continue;; esac
  if [ "$tiles" != "2x2" ] && [ "$tiles" != "3x2" ]; then
    echo "refusing tile size $tiles (only 2x2 or the 3x2 fallback without asking)"; continue
  fi
  python3 - "$clk" "$dens" <<'EOF'
import re, sys
p = "src/config.json"; s = open(p).read()
s = re.sub(r'"CLOCK_PERIOD": [0-9.]+', f'"CLOCK_PERIOD": {sys.argv[1]}', s)
s = re.sub(r'"PL_TARGET_DENSITY_PCT": [0-9.]+', f'"PL_TARGET_DENSITY_PCT": {sys.argv[2]}', s)
open(p, "w").write(s)
EOF
  sed -i "s/tiles: \"[0-9]x[0-9]\"/tiles: \"$tiles\"/" info.yaml
  echo "=== sweep $label: tiles=$tiles clock=$clk ns density=$dens"
  scripts/harden.sh "$label" "sweep: $notes" || true
done < <(if [ -n "$LIST" ]; then cat "$LIST"; else echo "$DEFAULT_LIST"; fi)
