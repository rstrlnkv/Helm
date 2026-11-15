#!/bin/bash
set -euo pipefail

# Builds a distributable .zip of the signed Helm.app that Scripts/package-app.sh
# stages in $TMPDIR/helm-package, for the in-app updater (self-downloaded zips
# carry no com.apple.quarantine, so no Gatekeeper prompt). Run package-app.sh first.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

source "$SCRIPT_DIR/staged-bundle.sh"
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
