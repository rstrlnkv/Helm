#!/bin/bash
set -euo pipefail

# Builds a distributable .zip of build/Helm.app for the in-app updater (self-
# downloaded zips carry no com.apple.quarantine, so no Gatekeeper prompt).
# Run Scripts/package-app.sh first.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

APP_DIR="$REPO_ROOT/build/Helm.app"
[ -d "$APP_DIR" ] || { echo "build/Helm.app not found — run Scripts/package-app.sh first" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
ZIP="$REPO_ROOT/build/Helm-$VERSION.zip"

echo "==> Zipping $ZIP"
rm -f "$ZIP"
# ditto --keepParent so the archive contains Helm.app at its root, and preserves
# the ad-hoc code signature + extended attributes.
/usr/bin/ditto -c -k --keepParent "$APP_DIR" "$ZIP"

echo "==> Done"
ls -lh "$ZIP"
