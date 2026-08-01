#!/usr/bin/env bash
# shoot-all.sh <outdir> — every page of the settings window, at both sizes.
#
# 1060x700 is the default size; 860x540 is contentMinSize. A layout that only
# works at one width has not been designed yet, which is why both are taken.
set -euo pipefail
OUT="${1:?usage: shoot-all.sh <outdir>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUT"
PAGES="general keep-awake vpn uninstaller homebrew leftovers disk duplicates autopilot layout about log"
for page in $PAGES; do
  for size in 1060x700 860x540; do
    bash "$HERE/shoot.sh" "$page" "$size" "$OUT/$page-$size.png"
  done
done
echo "done -> $OUT"
