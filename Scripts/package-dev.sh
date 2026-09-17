#!/bin/bash
set -euo pipefail

# Build this worktree and install it as **Helm Dev**, beside the real Helm.
#
# Why a separate bundle rather than replacing /Applications/Helm.app:
#
# - Unless this Mac names a signing identity (`signing-identity.sh`), the
#   bundle is ad-hoc signed, so its cdhash is a hash of its contents and every
#   build is a different program to TCC. Installing over the real app then
#   drops Accessibility and Full Disk Access every single time, and this is a
#   loop somebody watches after each rebuild.
# - A different bundle id is a different preferences domain, so the dev build
#   cannot write over settings the real app is using.
#
# The two look identical in the menu bar — same icon, same ring. The dev one is
# the one whose right-click menu says "Helm Dev".
#
# `Scripts/package-dev.sh` is tracked by git like the rest of the tree, so a
# change here travels with a commit and can be recovered from one.
#
# Run: bash Scripts/package-dev.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

STAGE="${TMPDIR:-/tmp}/helm-package"
SRC="$STAGE/Helm.app"
DEV="$STAGE/Helm Dev.app"
INSTALLED="/Applications/Helm Dev.app"

bash "$SCRIPT_DIR/package-app.sh"

echo "==> Rewriting the bundle as Helm Dev"
rm -rf "$DEV"
ditto "$SRC" "$DEV"
PLIST="$DEV/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.helm.app.dev" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Helm Dev" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Helm Dev" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Helm Dev" "$PLIST"

# Editing Info.plist invalidates the seal `package-app.sh` just made: the
# plist is inside what was signed. Re-sign, do not repair.
echo "==> Re-signing"
codesign --force --deep --timestamp=none \
  --sign "$(bash "$SCRIPT_DIR/signing-identity.sh" --resolve)" "$DEV" 2>&1 | sed 's/^/    /'
codesign --verify --deep --strict "$DEV"
echo "==> Signature verified"

echo "==> Installing to $INSTALLED"
pkill -f 'Helm Dev.app/Contents/MacOS/HelmApp' 2>/dev/null || true
sleep 1
rm -rf "$INSTALLED"
ditto "$DEV" "$INSTALLED"
xattr -dr com.apple.quarantine "$INSTALLED"
open "$INSTALLED"

echo "==> Running: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INSTALLED/Contents/Info.plist") build $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INSTALLED/Contents/Info.plist")"
