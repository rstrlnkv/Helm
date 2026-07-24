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
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP_DIR"

echo "==> Done"
echo "App path: $APP_DIR"
