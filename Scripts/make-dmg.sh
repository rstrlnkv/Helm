#!/bin/bash
set -euo pipefail

# Builds a distributable .dmg from the signed Helm.app that Scripts/package-app.sh
# stages in $TMPDIR/helm-package. Run package-app.sh first.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

source "$SCRIPT_DIR/staged-bundle.sh"
DMG="$REPO_ROOT/build/Helm-$VERSION.dmg"
# Outside the checkout, for the same reason package-app.sh signs there: a
# bundle that passes through a provider-synced folder comes out carrying
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
# Which of the three drawings the window uses. One edit switches it; see
# Scripts/design/make-dmg-background.swift for what each one is.
STYLE="${HELM_DMG_STYLE:-bezel}"
# A dev image says so on its face, and says it from the version rather than
# from anyone remembering to pass a flag: a screenshot of a dev window turns up
# in an issue sooner or later and must not be mistaken for a release.
# The bundle's own HelmChannel says it (package-app.sh writes it; a dev build's
# version carries no suffix). A bundle with no key predates it: the old rule.
CHANNEL="$(/usr/libexec/PlistBuddy -c 'Print :HelmChannel' "$APP_DIR/Contents/Info.plist" 2>/dev/null || true)"
case "$CHANNEL:$VERSION" in
  DEV:*)    DEV_FLAG="--dev" ;;
  :*-dev.*) DEV_FLAG="--dev" ;;
  *)        DEV_FLAG="" ;;
esac
swift "$SCRIPT_DIR/design/make-dmg-background.swift" \
  "$BACKGROUND" "$STYLE" $DEV_FLAG >/dev/null

# dmgbuild writes the .DS_Store itself instead of asking Finder to set the
# window up; dmg-settings.py says why Finder is not asked.
#
# It lives in a virtual environment under build/ rather than in the system
# Python, which Homebrew marks externally managed, and which is not this
# project's to install into. build/ is git-ignored, so a fresh clone pays for
# the environment once.
TOOLS="$REPO_ROOT/build/dmg-tools"
# **The tool is asked to RUN, not to exist.** A venv records the absolute path of
# its interpreter, so moving the repository leaves `bin/dmgbuild` executable and
# broken at once: `[ -x ... ]` said yes, and the build died on
# `bad interpreter: No such file or directory` after the app was already
# packaged. `--help` costs one process and answers the question that matters —
# it, and not `--version`: dmgbuild has no such flag and exits 2 on it when whole.
# The environment is also rebuilt when the pinned requirements change, so a venv
# made before they existed (unpinned) is not reused. The hash is kept beside it.
REQUIREMENTS="$SCRIPT_DIR/dmg-requirements.txt"
REQUIREMENTS_SHA="$(/usr/bin/shasum -a 256 "$REQUIREMENTS" | cut -d" " -f1)"
if ! "$TOOLS/bin/dmgbuild" --help >/dev/null 2>&1 \
   || [ "$(cat "$TOOLS/requirements.sha256" 2>/dev/null)" != "$REQUIREMENTS_SHA" ]; then
  echo "==> Setting up dmgbuild (first run, its interpreter moved, or the pins changed)"
  rm -rf "$TOOLS"
  python3 -m venv "$TOOLS"
  "$TOOLS/bin/pip" install --quiet --require-hashes -r "$REQUIREMENTS"
  echo "$REQUIREMENTS_SHA" > "$TOOLS/requirements.sha256"
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
