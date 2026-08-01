#!/usr/bin/env bash
# shoot.sh <module> <WxH> <out.png> — before/after evidence for a design change.
#
# The window is photographed by its CGWindowID, not by cropping a full-screen
# capture to a frame read out of System Events. That earlier arithmetic was
# correct on exactly one setup — a single display whose origin is (0, 0). With
# an external screen attached the window sits at negative coordinates,
# `screencapture` grabs the main display regardless of where the window is, and
# `sips` clamps the negative crop offset to zero: twenty-four photographs of
# empty desktop, and not one error out of any of the three programs involved.
set -euo pipefail
MODULE="${1:-disk}"; SIZE="${2:-940x660}"; OUT="${3:-/tmp/helm-shot.png}"
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$TMPDIR/helm-package/Helm.app"
pkill -f 'MacOS/HelmApp' 2>/dev/null || true; sleep 1
HELM_DEBUG_SHOT="$MODULE:$SIZE" open -a "$APP"
sleep 3
# The harness window opens behind whatever is frontmost; raise it first, or it
# is photographed with another app's window drawn over it.
osascript -e 'tell application "System Events" to set frontmost of process "HelmApp" to true' >/dev/null 2>&1 || true
sleep 1.2
WID=$(swift "$HERE/window-id.swift" Helm) || { echo "no window found"; exit 1; }
# -o drops the window shadow, so the image is the window and nothing else.
screencapture -x -o -l"$WID" "$OUT"
pkill -f 'MacOS/HelmApp' 2>/dev/null || true
echo "$OUT  window=$WID"
