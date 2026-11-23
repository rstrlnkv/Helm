#!/bin/bash
set -euo pipefail

# Rewrites a staged Helm.app as Helm Dev: `bash Scripts/rewrite-as-dev.sh <Helm.app> <Helm Dev.app>`.
#
# Split from `package-dev.sh` so the rewrite can be run (and tested) without installing anything.
# Helm Dev's Launchpad helper is rewritten with it, and the pair must stay a pair: the helper's parent id
# is Helm Dev's, its link scheme is the one Helm Dev declares, so a click on Helm Dev's Dock icon opens
# Helm Dev and never the release. Editing a plist invalidates the seal, so the helper is signed
# again first, then the bundle that holds it.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$1"
DEV="$2"

rm -rf "$DEV"
ditto "$SRC" "$DEV"
PLIST="$DEV/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.helm.app.dev" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Helm Dev" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Helm Dev" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Helm Dev" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleURLTypes:0:CFBundleURLName com.helm.app.dev.launchpad" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleURLTypes:0:CFBundleURLSchemes:0 helm-dev-launchpad" "$PLIST"

HELPER="$DEV/Contents/Helpers/Helm Dev Launchpad.app"
mv "$DEV/Contents/Helpers/Helm Launchpad.app" "$HELPER"
HELPER_PLIST="$HELPER/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.helm.app.dev.launchpad" "$HELPER_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Applications Dev" "$HELPER_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Applications Dev" "$HELPER_PLIST"
# The shown name in every language gets " Dev" after the word, so the Dock holds two apart.
for strings in "$HELPER"/Contents/Resources/*.lproj/InfoPlist.strings; do
  sed -i '' -E 's/";$/ Dev";/' "$strings"
done
/usr/libexec/PlistBuddy -c "Set :HelmParentBundleID com.helm.app.dev" "$HELPER_PLIST"
/usr/libexec/PlistBuddy -c "Set :HelmLaunchpadURL helm-dev-launchpad://toggle" "$HELPER_PLIST"

echo "==> Re-signing"
SIGN_IDENTITY="$(bash "$SCRIPT_DIR/signing-identity.sh" --resolve)"
codesign --force --timestamp=none --sign "$SIGN_IDENTITY" "$HELPER" 2>&1 | sed 's/^/    /'
codesign --force --deep --timestamp=none --sign "$SIGN_IDENTITY" "$DEV" 2>&1 | sed 's/^/    /'
codesign --verify --deep --strict "$DEV"
echo "==> Signature verified"
