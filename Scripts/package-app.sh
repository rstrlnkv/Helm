#!/bin/bash
set -euo pipefail

# Resolve repo root (this script lives in Scripts/, repo root is its parent)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="Helm.app"
BUILD_DIR="$REPO_ROOT/build"
# The bundle is assembled and signed OUTSIDE the repo.
#
# This checkout lives under ~/Documents, which a file provider syncs, and the
# provider stamps com.apple.FinderInfo onto directories it manages faster than
# `xattr -c` removes it. codesign refuses a bundle carrying it ("resource fork,
# Finder information, or similar detritus not allowed"), so signing in place
# here succeeds or fails by luck — and an unsigned bundle has no cdhash for TCC
# to hang Full Disk Access on, which is why the permission kept coming loose.
# TMPDIR (/var/folders/…) is not synced, so the seal survives there.
STAGE_DIR="${TMPDIR:-/tmp}/helm-package"
APP_DIR="$STAGE_DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Building release binary"
# The product, not the package. A bare `swift build -c release` builds every
# target in the manifest, and one of them is `HelmTestSupport` — a plain target
# that imports XCTest, which resolves out of the Xcode-only framework path. So a
# release build needed a full Xcode install where a toolchain had been enough,
# and HelmTestSupport.swiftmodule landed in Release beside HelmApp. Declaring
# `products:` does not fix this by itself (measured: a bare build still builds
# all 466 steps); naming the product is what does — 187 steps, and no harness.
swift build -c release --product HelmApp

echo "==> Assembling $APP_DIR (idempotent)"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$BUILD_DIR"

cp "$REPO_ROOT/.build/release/HelmApp" "$MACOS_DIR/HelmApp"
cp "$REPO_ROOT/Resources/HelmApp/Info.plist" "$CONTENTS_DIR/Info.plist"

# The ring artwork the icon is built from: the in-app mark draws the same
# shape, so editing the icon in Icon Composer updates the app too.
cp "$REPO_ROOT/Resources/Icon/Helm.icon/Assets/helm-ring.svg" "$RESOURCES_DIR/helm-ring.svg"
# SwiftPM resource bundles. A target that declares `resources:` gets its own
# .bundle beside the binary, and `Bundle.module` looks for it next to the
# executable — miss this copy and the flag artwork is simply absent at
# runtime, with every layout quietly falling back to letters and nothing in
# the build saying so.
BUNDLE_COUNT=0
for bundle in "$REPO_ROOT"/.build/release/*.bundle; do
  [ -e "$bundle" ] || continue
  cp -R "$bundle" "$CONTENTS_DIR/Resources/"
  BUNDLE_COUNT=$((BUNDLE_COUNT + 1))
done
echo "==> Resource bundles copied: $BUNDLE_COUNT"
if [ "$BUNDLE_COUNT" -eq 0 ]; then
  echo "!! No SwiftPM resource bundles found — Bundle.module lookups will fail" >&2
  exit 1
fi

# The third-party notice travels with the app, not only with the repo: the
# .app is a distribution too, and MIT asks for the notice in "all copies".
cp "$REPO_ROOT/NOTICE.md" "$RESOURCES_DIR/NOTICE.md"

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

# Build number = git commit count, so About shows a real, increasing build.
BUILD_NO="$(git -C "$REPO_ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NO" "$CONTENTS_DIR/Info.plist" >/dev/null 2>&1 || true
echo "==> Build number: $BUILD_NO"

echo "==> Compiling Liquid Glass app icon (Icon Composer .icon → Assets.car)"
ICONOUT="$BUILD_DIR/iconout"
rm -rf "$ICONOUT" && mkdir -p "$ICONOUT"
xcrun actool "$REPO_ROOT/Resources/Icon/Helm.icon" \
  --compile "$ICONOUT" \
  --platform macosx \
  --minimum-deployment-target 26.0 \
  --app-icon Helm \
  --output-partial-info-plist "$ICONOUT/partial.plist" \
  --output-format human-readable-text
cp "$ICONOUT/Assets.car" "$RESOURCES_DIR/Assets.car"
cp "$ICONOUT/Helm.icns" "$RESOURCES_DIR/Helm.icns"

echo "==> Ad-hoc signing"
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
# Verified here, where the signature is intact. This check was missing: signing
# reported success for months while producing a bundle codesign rejects.
codesign --verify --deep --strict "$APP_DIR"
echo "==> Signature verified"

# A copy in the repo for convenience only. It cannot be verified or installed
# from — the file provider re-stamps its root the moment it lands.
ditto "$APP_DIR" "$BUILD_DIR/$APP_NAME"

echo "==> Done"
echo "Signed app (install and package from here): $APP_DIR"
echo "Convenience copy (do not install):          $BUILD_DIR/$APP_NAME"
