#!/usr/bin/env bash
# shoot-panel.sh <out.png> — photographs the menu-bar panel, on a Mac where that
# is possible. Refuses, loudly, where it is not.
#
# The panel is the one surface this repository cannot photograph unattended, and
# every plausible route was tried before this script settled for refusing:
#
#   • `screencapture -l<windowid>`, which is how shoot.sh takes the settings
#     window, asks the window server for that one window's image. The panel's
#     card is Liquid Glass and the material is composited out of the backdrop,
#     so what comes back is a 712x2796 image of nothing — no error, no warning.
#   • `screencapture -R x,y,w,h` refuses a rect in the global coordinate space
#     ("could not create image from rect") as soon as a display sits at a
#     negative origin, which is any display above or left of the built-in one.
#   • `screencapture -D <id>` returns the desktop picture with no windows on it.
#   • `CGWindowListCreateImage` was obsoleted in macOS 15 and does not compile.
#   • ScreenCaptureKit from a `swift`-run script returns desktop-only content:
#     the Screen Recording grant belongs to `/usr/sbin/screencapture`, which has
#     it, and not to the script. Even the main display comes back as bare
#     wallpaper — menu bar, Dock and every window missing.
#
# What is left is plain `screencapture`, which photographs one display: the
# main one. So the panel can be taken automatically only when it opens there.
# The status item follows the display holding the active menu bar and does not
# move because the pointer did, so on a multi-display Mac this is not something
# the script can arrange.
set -euo pipefail
OUT="${1:-/tmp/helm-panel.png}"
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$TMPDIR/helm-package/Helm.app"
pkill -f 'MacOS/HelmApp' 2>/dev/null || true; sleep 1
HELM_DEBUG_PANEL=1 open -a "$APP"
WID=""
for _ in $(seq 1 40); do
  WID=$(swift "$HERE/window-id.swift" Helm 101 2>/dev/null) && [ -n "$WID" ] && break
  sleep 0.5
done
[ -n "$WID" ] || { echo "no panel found"; pkill -f 'MacOS/HelmApp' 2>/dev/null || true; exit 1; }

# The main display's origin is (0, 0) by definition, so a panel with a negative
# origin is on some other screen and plain screencapture will not see it.
ORIGIN=$(swift - "$WID" <<'OSA'
import CoreGraphics
import Foundation
let wanted = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) ?? 0 : 0
let windows = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows where window[kCGWindowNumber as String] as? Int == wanted {
    let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    print("\(Int(bounds["X"] ?? 0)) \(Int(bounds["Y"] ?? 0))")
    exit(0)
}
exit(1)
OSA
)
read -r PX PY <<< "$ORIGIN"
if [ "$PY" -lt 0 ] || [ "$PX" -lt 0 ]; then
  pkill -f 'MacOS/HelmApp' 2>/dev/null || true
  cat >&2 <<MSG
shoot-panel: the panel opened at ($PX, $PY), which is not the main display.

Only the main display can be photographed in full — see the header of this
script for the five routes that do not work and why. Take this one by hand:

  1. Click Helm's menu-bar icon.
  2. Press Cmd-Shift-4, then Space, then click the panel.
  3. Save the result as $OUT

Or make the display holding Helm's status item the main one in
System Settings > Displays > Arrange, and run this again.
MSG
  exit 2
fi

# The card grows into place on a spring; a photograph taken mid-spring measures
# the animation rather than the layout.
sleep 1.5
screencapture -x -o "$OUT"
pkill -f 'MacOS/HelmApp' 2>/dev/null || true
echo "$OUT  panel at ($PX, $PY) — full main display, crop the panel out by hand"
