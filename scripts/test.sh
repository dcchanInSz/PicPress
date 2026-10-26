#!/usr/bin/env bash
#
# Builds and runs the integration tests (encoder, queue, export).
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build"
MIN_MACOS="${MACOSX_DEPLOYMENT_TARGET:-14.0}"
TARGET="$(uname -m)-apple-macos$MIN_MACOS"

mkdir -p "$BUILD/tmp" "$BUILD/modulecache"

"$ROOT/scripts/fetch-libwebp.sh"

clang -O2 -mmacosx-version-min="$MIN_MACOS" -c "$ROOT/Sources/PicPress/WebPBridge.c" \
  -I "$BUILD/libwebp/include" -o "$BUILD/WebPBridge.o"

# Everything except the app entry point.
SOURCES=()
for file in "$ROOT"/Sources/PicPress/*.swift; do
  [[ "$(basename "$file")" == "main.swift" ]] && continue
  SOURCES+=("$file")
done

echo "• building tests"
TMPDIR="$BUILD/tmp" swiftc -Onone -g -swift-version 5 -target "$TARGET" \
  -import-objc-header "$ROOT/Sources/PicPress/WebPBridge.h" \
  -module-cache-path "$BUILD/modulecache" \
  -I "$BUILD/libwebp/include" \
  "${SOURCES[@]}" \
  "$ROOT/Sources/PicPressTests/main.swift" \
  "$BUILD/WebPBridge.o" \
  "$BUILD/libwebp/lib/libwebp.a" \
  "$BUILD/libwebp/lib/libsharpyuv.a" \
  -o "$BUILD/picpress-tests"

echo ""
"$BUILD/picpress-tests"
