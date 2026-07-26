#!/bin/bash
set -euo pipefail

# Builds a distributable .zip of build/Helm.app for the in-app updater (self-
# downloaded zips carry no com.apple.quarantine, so no Gatekeeper prompt).
# Run Scripts/package-app.sh first.
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

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
ZIP="$REPO_ROOT/build/Helm-$VERSION.zip"

echo "==> Zipping $ZIP"
rm -f "$ZIP"
# ditto --keepParent so the archive contains Helm.app at its root, and preserves
# the ad-hoc code signature + extended attributes.
/usr/bin/ditto -c -k --keepParent "$APP_DIR" "$ZIP"

echo "==> Done"
ls -lh "$ZIP"

# The line the release notes must carry: the in-app updater refuses to install
# an asset silently unless the release publishes its digest, and refuses
# outright if the bytes disagree.
echo
echo "Add this line to the release notes:"
echo "sha256 $(basename "$ZIP") $(/usr/bin/shasum -a 256 "$ZIP" | cut -d" " -f1)"
