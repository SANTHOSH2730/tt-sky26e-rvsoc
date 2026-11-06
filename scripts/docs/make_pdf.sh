#!/usr/bin/env bash
# PDF versions of the main documents (docs/pdf/), for reading offline and for
# the project journal. Markdown -> HTML (md2html.py) -> PDF with a headless
# Chromium browser: Windows Edge/Chrome when run in WSL, else chromium.
#   scripts/docs/make_pdf.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
source scripts/env.sh >/dev/null 2>&1 || true
DOCS="DESIGN_REPORT IO_GUIDE info fpga"
mkdir -p docs/pdf

BROWSER=""
for b in "/mnt/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" \
         "/mnt/c/Program Files/Microsoft/Edge/Application/msedge.exe" \
         "/mnt/c/Program Files/Google/Chrome/Application/chrome.exe"; do
  [ -x "$b" ] && { BROWSER="$b"; break; }
done
WIN=1
if [ -z "$BROWSER" ]; then
  BROWSER=$(command -v chromium || command -v chromium-browser || command -v google-chrome || true)
  WIN=0
fi
[ -n "$BROWSER" ] || { echo "no Chromium-based browser found"; exit 1; }

if [ $WIN = 1 ]; then
  # stage in the Windows temp dir: the Windows browser reads and writes there
  WTEMP=$(cmd.exe /c "echo %TEMP%" 2>/dev/null | tr -d '\r')
  STAGE=$(wslpath "$WTEMP")/rvsoc_pdf
else
  STAGE="$ROOT/.work/pdf"
fi
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -r docs/images "$STAGE/"
for d in $DOCS; do
  python scripts/docs/md2html.py "docs/$d.md" "$STAGE/$d.html" >/dev/null
  if [ $WIN = 1 ]; then
    IN="file:///$(wslpath -m "$STAGE/$d.html")"; OUT="$(wslpath -w "$STAGE/$d.pdf")"
  else
    IN="file://$STAGE/$d.html"; OUT="$STAGE/$d.pdf"
  fi
  "$BROWSER" --headless=new --disable-gpu --no-pdf-header-footer --print-to-pdf="$OUT" "$IN" >/dev/null 2>&1 || true
  for i in $(seq 1 30); do [ -s "$STAGE/$d.pdf" ] && break; sleep 1; done
  if [ -s "$STAGE/$d.pdf" ]; then cp "$STAGE/$d.pdf" docs/pdf/; chmod 644 "docs/pdf/$d.pdf"; echo "docs/pdf/$d.pdf"; else echo "FAILED: $d"; fi
done
