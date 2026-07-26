#!/bin/bash
set -euo pipefail

# Resolve repo root (this script lives in Scripts/, repo root is its parent)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="Helm.app"
BUILD_DIR="$REPO_ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Building release binary"
swift build -c release

echo "==> Assembling $APP_DIR (idempotent)"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$REPO_ROOT/.build/release/HelmApp" "$MACOS_DIR/HelmApp"
cp "$REPO_ROOT/Resources/HelmApp/Info.plist" "$CONTENTS_DIR/Info.plist"

# The ring artwork the icon is built from: the in-app mark draws the same
# shape, so editing the icon in Icon Composer updates the app too.
cp "$REPO_ROOT/Resources/Icon/Helm.icon/Assets/helm-ring.svg" "$RESOURCES_DIR/helm-ring.svg"
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

echo "==> Stripping extended attributes"
xattr -cr "$APP_DIR"

echo "==> Ad-hoc signing"
# Extended attributes (com.apple.FinderInfo lands on the bundle root through
# ordinary Finder/ditto traffic) make codesign refuse the bundle with "resource
# fork, Finder information, or similar detritus not allowed" — and an unsigned
# bundle has no cdhash for TCC to bind Full Disk Access to.
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "==> Done"
echo "App path: $APP_DIR"
