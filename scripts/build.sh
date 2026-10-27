#!/usr/bin/env bash
#
# Builds dist/PicPress.app and dist/picpress-cli.
# Only needs the Xcode Command Line Tools (no Xcode, no Homebrew).
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="PicPress"
BUILD="$ROOT/.build"
DIST="$ROOT/dist"
MIN_MACOS="${MACOSX_DEPLOYMENT_TARGET:-14.0}"
ARCH="$(uname -m)"
TARGET="$ARCH-apple-macos$MIN_MACOS"

mkdir -p "$BUILD/tmp" "$BUILD/modulecache" "$DIST"

"$ROOT/scripts/fetch-libwebp.sh"

echo "• compiling WebP bridge"
clang -O2 -mmacosx-version-min="$MIN_MACOS" -c "$ROOT/Sources/PicPress/WebPBridge.c" \
  -I "$BUILD/libwebp/include" \
  -o "$BUILD/WebPBridge.o"

APP="$DIST/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
  echo "• app icon missing, generating"
  "$ROOT/scripts/make-icon.sh"
fi
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "• compiling $APP_NAME.app ($TARGET)"
TMPDIR="$BUILD/tmp" swiftc -O -swift-version 5 -target "$TARGET" \
  -import-objc-header "$ROOT/Sources/PicPress/WebPBridge.h" \
  -module-cache-path "$BUILD/modulecache" \
  -I "$BUILD/libwebp/include" \
  "$ROOT"/Sources/PicPress/*.swift \
  "$BUILD/WebPBridge.o" \
  "$BUILD/libwebp/lib/libwebp.a" \
  "$BUILD/libwebp/lib/libsharpyuv.a" \
  -o "$APP/Contents/MacOS/$APP_NAME"

echo "• signing (best identity available)"
"$ROOT/scripts/sign.sh" "$APP"

echo "• compiling picpress-cli"
TMPDIR="$BUILD/tmp" swiftc -O -swift-version 5 -target "$TARGET" \
  -import-objc-header "$ROOT/Sources/PicPress/WebPBridge.h" \
  -module-cache-path "$BUILD/modulecache" \
  -I "$BUILD/libwebp/include" \
  "$ROOT/Sources/PicPress/ImageCompressor.swift" \
  "$ROOT/Sources/PicPress/Palette.swift" \
  "$ROOT/Sources/PicPressCLI/main.swift" \
  "$BUILD/WebPBridge.o" \
  "$BUILD/libwebp/lib/libwebp.a" \
  "$BUILD/libwebp/lib/libsharpyuv.a" \
  -o "$DIST/picpress-cli"

"$ROOT/scripts/sign.sh" --quiet "$DIST/picpress-cli"

echo "✓ built:"
echo "   $APP"
echo "   $DIST/picpress-cli"
