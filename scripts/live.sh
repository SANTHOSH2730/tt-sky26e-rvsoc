#!/usr/bin/env bash
# Run one build step and mirror its output into logs/live.log, which the
# "live build" terminal window follows (tail -F logs/live.log).
# Usage: scripts/live.sh "Step title" command [args...]
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/logs"
LOG="$ROOT/logs/live.log"
title="$1"; shift
printf '\n\033[1;36m=== [%s] %s ===\033[0m\n\033[0;33m$ %s\033[0m\n' "$(date +%H:%M:%S)" "$title" "$*" | tee -a "$LOG"
"$@" 2>&1 | tee -a "$LOG"
rc=${PIPESTATUS[0]}
if [ "$rc" = 0 ]; then col=2; else col=1; fi
printf '\033[1;3%sm=== [%s] %s: exit %s ===\033[0m\n' "$col" "$(date +%H:%M:%S)" "$title" "$rc" | tee -a "$LOG"
exit "$rc"
