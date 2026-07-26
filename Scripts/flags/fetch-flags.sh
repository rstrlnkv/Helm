#!/usr/bin/env bash
# Rebuilds Sources/Modules/Layout/UI/Flags from flag-icons.
#
# The artwork ships as PNG rather than SVG for one reason: `NSImage`'s SVG
# support is CoreSVG, which does not resolve `<use xlink:href>` references.
# China's stars live in a `<defs>` block referenced exactly that way, so
# NSImage rendered a plain red rectangle and reported success. Rendering
# through WebKit once, here, gets the whole format — and a wrong flag is then
# a thing you can see in review rather than something the app decides at
# runtime.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$REPO_ROOT/Sources/Modules/Layout/UI/Flags"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Every region LanguageBadge can name. Keep in step with its table.
REGIONS="ru de nl ua pl at hu ee lt bg am ir es lv th fr it be ie ro
         ca mx pt il by sk si rs hr se dk fi no is ch ge jp kz mk cz
         us gr tw gb au tr kr br cn vn"

echo "==> Fetching 4x3 SVGs from flag-icons"
mkdir -p "$WORK/svg"
for r in $REGIONS; do
  curl -sfS -o "$WORK/svg/$r.svg" \
    "https://raw.githubusercontent.com/lipis/flag-icons/main/flags/4x3/$r.svg" \
    || { echo "!! missing flag: $r" >&2; exit 1; }
done

echo "==> Rendering through WebKit"
swiftc -O -o "$WORK/render" "$REPO_ROOT/Scripts/flags/render-flags.swift"
"$WORK/render" "$WORK/svg" "$WORK/png"

rm -f "$OUT"/*.png
mkdir -p "$OUT"
cp "$WORK/png"/*.png "$OUT/"
echo "==> $(ls "$OUT" | wc -l | tr -d ' ') flags in $OUT"
