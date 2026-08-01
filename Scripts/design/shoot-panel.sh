#!/usr/bin/env bash
# shoot-panel.sh <out.png> — photographs the menu-bar panel.
#
# The panel is a borderless NSPanel covering a transparent strip from the status
# item to the bottom of the screen, so it is not an AXStandardWindow and
# `shoot.sh`'s frame query cannot find it. The whole screen is captured instead
# and cropped by hand: the panel's position depends on where macOS put the
# status item, which is not ours to predict.
set -euo pipefail
OUT="${1:-/tmp/helm-panel.png}"
APP="$TMPDIR/helm-package/Helm.app"
pkill -f 'MacOS/HelmApp' 2>/dev/null || true; sleep 1
HELM_DEBUG_PANEL=1 open -a "$APP"
sleep 3.5
screencapture -x -o "$OUT"
pkill -f 'MacOS/HelmApp' 2>/dev/null || true
echo "$OUT  (full screen — crop the panel out by hand)"
