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
# Wait for the window rather than sleeping at it. A fixed 3 s was enough for
# eleven pages out of twelve and not for Duplicates, which reopens on a stored
# scan before it draws — so one page in the run failed, and which page it was
# depended on the machine's mood.
WID=""
for _ in $(seq 1 40); do
  WID=$(swift "$HERE/window-id.swift" Helm 2>/dev/null) && [ -n "$WID" ] && break
  sleep 0.5
done
[ -n "$WID" ] || { echo "no window found"; exit 1; }
# The harness window opens behind whatever is frontmost, and an *inactive*
# macOS window draws its controls in greyscale: the traffic lights lose their
# colour and a switch that is on looks exactly like one that is off apart from
# where the knob sits. Photographs taken that way read as design defects that
# do not exist, so the activation is asserted rather than attempted.
FRONT=""
for _ in $(seq 1 20); do
  osascript -e 'tell application "System Events" to set frontmost of process "HelmApp" to true' >/dev/null 2>&1 || true
  sleep 0.3
  FRONT=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null || echo "")
  [ "$FRONT" = "HelmApp" ] && break
done
[ "$FRONT" = "HelmApp" ] || { echo "could not bring HelmApp to the front (frontmost=$FRONT)"; exit 1; }
# Let the page settle: the reveal animations are springs and a photograph taken
# mid-spring measures the animation, not the layout.
sleep 1.5
# -o drops the window shadow, so the image is the window and nothing else.
screencapture -x -o -l"$WID" "$OUT"
pkill -f 'MacOS/HelmApp' 2>/dev/null || true
echo "$OUT  window=$WID"
