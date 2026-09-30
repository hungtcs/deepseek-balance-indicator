#!/bin/bash
# Regenerates the menu bar PNG and the .icns app icon from icon.svg.
# Requires: rsvg-convert (brew install librsvg) and ImageMagick (brew install imagemagick).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG="$ROOT/icon.svg"
RES="$ROOT/Sources/DeepSeekBalanceIndicator/Resources"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> menu bar icon (39x28 px, displayed at 19.5x14 pt as a template image)"
rsvg-convert -h 28 -a "$SVG" -o "$RES/icon.png"

echo "==> app icon"
rsvg-convert -w 820 -a "$SVG" -o "$TMP/whale.png"
magick "$TMP/whale.png" -background none -gravity center -extent 1024x1024 "$TMP/appicon.png"

mkdir -p "$TMP/AppIcon.iconset"
for size in 16 32 64 128 256 512; do
  magick "$TMP/appicon.png" -resize "${size}x${size}" "$TMP/AppIcon.iconset/icon_${size}x${size}.png"
  magick "$TMP/appicon.png" -resize "$((size * 2))x$((size * 2))" "$TMP/AppIcon.iconset/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$TMP/AppIcon.iconset" -o "$ROOT/Assets/AppIcon.icns"

echo "==> done"
ls -l "$RES/icon.png" "$ROOT/Assets/AppIcon.icns"
