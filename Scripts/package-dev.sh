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
# Run: bash Scripts/package-dev.sh [--no-launch]
#
# `--no-launch` (or HELM_DEV_NO_LAUNCH=1) installs without opening the app:
# a launch writes state (preferences, hotkeys, logs), and a run that wants to
# start from the installed bundle untouched has to be able to ask for that.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

STAGE="${TMPDIR:-/tmp}/helm-package"
SRC="$STAGE/Helm.app"
DEV="$STAGE/Helm Dev.app"
INSTALLED="/Applications/Helm Dev.app"

NO_LAUNCH="${HELM_DEV_NO_LAUNCH:-}"
for arg in "$@"; do
  if [ "$arg" = "--no-launch" ]; then
    NO_LAUNCH=1
  else
    echo "!! unknown argument '$arg'; usage: bash Scripts/package-dev.sh [--no-launch]" >&2
    exit 2
  fi
done

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
# Wait for the old process to be gone, up to about 10 s; never replace a bundle
# that is still running. `pgrep` says 1 for "no match" and 2 or 3 for an error:
# only 1 means gone, anything else leaves the install untouched.
for _ in $(seq 1 20); do
  status=0
  pgrep -f 'Helm Dev.app/Contents/MacOS/HelmApp' >/dev/null || status=$?
  [ "$status" -eq 0 ] || break
  sleep 0.5
done
status=0
pgrep -f 'Helm Dev.app/Contents/MacOS/HelmApp' >/dev/null || status=$?
if [ "$status" -eq 0 ]; then
  echo "!! Helm Dev is still running after 10 s; $INSTALLED left untouched" >&2
  exit 1
elif [ "$status" -ne 1 ]; then
  echo "!! pgrep failed (status $status); cannot tell whether Helm Dev is running; $INSTALLED left untouched" >&2
  exit 1
fi
rm -rf "$INSTALLED"
ditto "$DEV" "$INSTALLED"
xattr -dr com.apple.quarantine "$INSTALLED"
[ -n "$NO_LAUNCH" ] || open "$INSTALLED"

echo "==> $([ -n "$NO_LAUNCH" ] && echo Installed || echo Running): $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INSTALLED/Contents/Info.plist") build $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INSTALLED/Contents/Info.plist")"
