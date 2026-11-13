# Sourced by make-zip.sh and make-dmg.sh, never run by hand and never sourced by
# package-app.sh (a test copies that script alone into a scratch repo). Sets
# APP_DIR, the signed bundle, and VERSION, or exits with the reason.
#
# The SIGNED bundle, which package-app.sh leaves outside the repo: the checkout
# is meant to stay out from under a file provider (Architecture/Release.md
# § Signing and grants), but if one ever syncs it, a bundle copied back in
# carries com.apple.FinderInfo, which invalidates the signature. Never package
# a copy from build/.
APP_DIR="${TMPDIR:-/tmp}/helm-package/Helm.app"
[ -d "$APP_DIR" ] || { echo "signed Helm.app not found — run Scripts/package-app.sh first" >&2; exit 1; }
codesign --verify --deep --strict "$APP_DIR" || {
  echo "the staged bundle does not verify — do not ship it" >&2; exit 1; }
# Releases ship ad-hoc. A bundle signed with this Mac's own identity
# (`signing-identity.sh`) would tie every user's grants to a key that exists on
# one machine.
# Captured before matching, not piped: under pipefail a `grep -q` that stops
# reading early can fail the pipeline on codesign's broken pipe.
SIGNATURE="$(codesign -dv "$APP_DIR" 2>&1 || true)"
printf '%s\n' "$SIGNATURE" | grep -x 'Signature=adhoc' >/dev/null || {
  echo "the staged bundle is signed with a local identity — package a release" \
       "with: HELM_SIGN_IDENTITY=- bash Scripts/package-app.sh" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
