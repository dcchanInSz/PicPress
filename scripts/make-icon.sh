#!/usr/bin/env bash
#
# Renders the app icon and packs it into Resources/AppIcon.icns.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build"
ICON_DIR="$BUILD/icon"
ICONSET="$BUILD/AppIcon.iconset"

mkdir -p "$BUILD"
TMPDIR="$BUILD/tmp" swiftc -O "$ROOT/scripts/make-icon.swift" \
  -module-cache-path "$BUILD/modulecache" \
  -o "$BUILD/make-icon"

rm -rf "$ICON_DIR" "$ICONSET"
mkdir -p "$ICON_DIR" "$ICONSET"
"$BUILD/make-icon" "$ICON_DIR"

MASTER="$ICON_DIR/icon-1024.png"
[[ -f "$MASTER" ]] || { echo "icon render failed" >&2; exit 1; }

render() { # size filename
  sips -z "$1" "$1" "$MASTER" --out "$ICONSET/$2" >/dev/null
}

render 16   icon_16x16.png
render 32   icon_16x16@2x.png
render 32   icon_32x32.png
render 64   icon_32x32@2x.png
render 128  icon_128x128.png
render 256  icon_128x128@2x.png
render 256  icon_256x256.png
render 512  icon_256x256@2x.png
render 512  icon_512x512.png
cp "$MASTER" "$ICONSET/icon_512x512@2x.png"

mkdir -p "$ROOT/Resources"
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
echo "• wrote Resources/AppIcon.icns"
