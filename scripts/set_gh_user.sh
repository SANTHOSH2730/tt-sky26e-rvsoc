#!/usr/bin/env bash
# Rename the top module to tt_um_<github_user>_rvsoc everywhere it appears.
# Run this BEFORE the final hardening if your GitHub username is not "santhosh".
#   scripts/set_gh_user.sh <github_user>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
NEW="${1:?usage: set_gh_user.sh <github_user>}"
NEW_SAFE=$(echo "$NEW" | tr -c 'A-Za-z0-9_\n' '_')
OLD=$(grep -oE 'top_module:\s*"tt_um_[A-Za-z0-9_]+"' info.yaml | grep -oE 'tt_um_[A-Za-z0-9_]+')
NEWTOP="tt_um_${NEW_SAFE}_rvsoc"
[ "$OLD" = "$NEWTOP" ] && { echo "already $NEWTOP"; exit 0; }
FILES=$(grep -rl "$OLD" info.yaml src test/*.v test/*.py fpga docs README.md 2>/dev/null || true)
for f in $FILES; do sed -i "s/$OLD/$NEWTOP/g" "$f"; done
echo "renamed $OLD -> $NEWTOP in:"; echo "$FILES"
echo "Now re-run: scripts/run_all.sh   (re-hardens with the new name)"
