#!/bin/bash
set -euo pipefail

# Builds a distributable .dmg from build/Helm.app. Run Scripts/package-app.sh first.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# The SIGNED bundle, which package-app.sh leaves outside the repo: this checkout
# is file-provider-synced, and a bundle copied back into it carries
# com.apple.FinderInfo, which invalidates the signature. Never package build/.
APP_DIR="${TMPDIR:-/tmp}/helm-package/Helm.app"
[ -d "$APP_DIR" ] || { echo "signed Helm.app not found — run Scripts/package-app.sh first" >&2; exit 1; }
codesign --verify --deep --strict "$APP_DIR" || {
  echo "the staged bundle does not verify — do not ship it" >&2; exit 1; }

# Version drives the dmg filename (matches the GitHub release tag vX.Y.Z).
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
DMG="$REPO_ROOT/build/Helm-$VERSION.dmg"
STAGE="$REPO_ROOT/build/dmg-stage"

echo "==> Staging"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
# ditto, not cp -R: it carries the signature and adds nothing of its own.
ditto "$APP_DIR" "$STAGE/Helm.app"
ln -s /Applications "$STAGE/Applications"   # drag-to-install target

echo "==> Building $DMG"
hdiutil create -volname "Helm $VERSION" \
  -srcfolder "$STAGE" \
  -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"

echo "==> Done"
ls -lh "$DMG"
echo "sha256 $(basename "$DMG") $(/usr/bin/shasum -a 256 "$DMG" | cut -d" " -f1)"
