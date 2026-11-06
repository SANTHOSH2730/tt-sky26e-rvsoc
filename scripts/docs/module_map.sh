#!/usr/bin/env bash
# Rebuild docs/images/floorplan_modules.png from runs/wokwi/final/odb:
# OpenROAD (LibreLane container) dumps cell boxes + net names, matplotlib plots them.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
source scripts/env.sh
mkdir -p .work/place
cp scripts/docs/dump_place.py .work/place/
docker run --rm --user $(id -u):$(id -g) -v $HOME:$HOME -w $PWD \
  -e ODB=$PWD/runs/wokwi/final/odb/tt_um_santhosh_rvsoc.odb -e OUT=$PWD/.work/place/insts.csv \
  ghcr.io/librelane/librelane:$LIBRELANE_TAG openroad -python -exit .work/place/dump_place.py
python scripts/docs/plot_modules.py
