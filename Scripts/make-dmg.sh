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
# Outside the checkout, for the same reason package-app.sh signs there: a
# bundle that passes through the synced folder comes out carrying
# com.apple.FinderInfo, and the dmg would ship a bundle codesign rejects.
STAGE="${TMPDIR:-/tmp}/helm-dmg-stage"

echo "==> Staging"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
# ditto, not cp -R: it carries the signature and adds nothing of its own.
ditto "$APP_DIR" "$STAGE/Helm.app"
# The seal must still be intact in what actually gets packed. dmgbuild adds the
# Applications link itself, from Scripts/dmg-settings.py.
codesign --verify --deep --strict "$STAGE/Helm.app"

echo "==> Drawing the window"
BACKGROUND="$STAGE/background.png"
swift "$SCRIPT_DIR/design/make-dmg-background.swift" "$BACKGROUND" >/dev/null

# dmgbuild writes the .DS_Store itself instead of asking Finder to set the
# window up. That is why it is here rather than an AppleScript: on macOS 26
# Finder takes the view options, reports them back correctly, and draws its
# default window anyway — confirmed against Homebrew's create-dmg, which does
# the same dance and gets the same nothing.
#
# It lives in a virtual environment under build/ rather than in the system
# Python, which Homebrew marks externally managed, and which is not this
# project's to install into.
TOOLS="$REPO_ROOT/build/dmg-tools"
if [ ! -x "$TOOLS/bin/dmgbuild" ]; then
  echo "==> Setting up dmgbuild (first run)"
  python3 -m venv "$TOOLS"
  "$TOOLS/bin/pip" install --quiet dmgbuild
fi

echo "==> Building $DMG"
export HELM_APP="$STAGE/Helm.app"
export HELM_BACKGROUND="$BACKGROUND"
export HELM_VOLUME_ICON="$APP_DIR/Contents/Resources/Helm.icns"
"$TOOLS/bin/dmgbuild" -s "$SCRIPT_DIR/dmg-settings.py" "Helm $VERSION" "$DMG" >/dev/null
rm -rf "$STAGE"

echo "==> Done"
ls -lh "$DMG"
echo "sha256 $(basename "$DMG") $(/usr/bin/shasum -a 256 "$DMG" | cut -d" " -f1)"
