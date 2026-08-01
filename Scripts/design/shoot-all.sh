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
FAILED=""
for page in $PAGES; do
  for size in 1060x700 860x540; do
    # One page failing must not abandon the other twenty-three. What is missing
    # is reported at the end, where it can be reshot by hand.
    bash "$HERE/shoot.sh" "$page" "$size" "$OUT/$page-$size.png" || FAILED="$FAILED $page-$size"
  done
done
if [ -n "$FAILED" ]; then
  echo "FAILED:$FAILED"
  exit 1
fi
echo "done -> $OUT"
