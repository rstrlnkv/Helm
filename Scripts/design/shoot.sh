#!/usr/bin/env bash
# shoot.sh <module> <WxH> <out.png> — before/after evidence for a design change.
set -euo pipefail
MODULE="${1:-disk}"; SIZE="${2:-940x660}"; OUT="${3:-/tmp/helm-shot.png}"
APP="$TMPDIR/helm-package/Helm.app"
pkill -f 'MacOS/HelmApp' 2>/dev/null || true; sleep 1
HELM_DEBUG_SHOT="$MODULE:$SIZE" open -a "$APP"
sleep 3
# The harness window opens behind whatever is frontmost; raise it first.
osascript -e 'tell application "System Events" to set frontmost of process "HelmApp" to true' >/dev/null 2>&1 || true
sleep 1.2
FRAME=$(osascript <<'OSA' 2>/dev/null || echo ""
tell application "System Events" to tell process "HelmApp"
  set w to first window whose subrole is "AXStandardWindow"
  set p to position of w
  set s to size of w
  return (item 1 of p as text) & " " & (item 2 of p as text) & " " & ¬
         (item 1 of s as text) & " " & (item 2 of s as text)
end tell
OSA
)
[ -z "$FRAME" ] && { echo "no window found"; exit 1; }
read -r X Y W H <<< "$FRAME"
screencapture -x -o "$OUT.full.png"
sips -c $((H*2+80)) $((W*2+80)) --cropOffset $((Y*2-40)) $((X*2-40)) \
     "$OUT.full.png" --out "$OUT" >/dev/null
rm -f "$OUT.full.png"
pkill -f 'MacOS/HelmApp' 2>/dev/null || true
echo "$OUT  frame=$FRAME"
