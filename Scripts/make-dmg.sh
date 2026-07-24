#!/bin/bash
set -euo pipefail

# Builds a distributable .dmg from build/Helm.app. Run Scripts/package-app.sh first.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

APP_DIR="$REPO_ROOT/build/Helm.app"
[ -d "$APP_DIR" ] || { echo "build/Helm.app not found — run Scripts/package-app.sh first" >&2; exit 1; }

# Version drives the dmg filename (matches the GitHub release tag vX.Y.Z).
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
DMG="$REPO_ROOT/build/Helm-$VERSION.dmg"
STAGE="$REPO_ROOT/build/dmg-stage"

echo "==> Staging"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP_DIR" "$STAGE/Helm.app"
ln -s /Applications "$STAGE/Applications"   # drag-to-install target

echo "==> Building $DMG"
hdiutil create -volname "Helm $VERSION" \
  -srcfolder "$STAGE" \
  -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"

echo "==> Done"
ls -lh "$DMG"
