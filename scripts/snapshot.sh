#!/usr/bin/env bash
#
# Renders the main window offscreen to PNG files (light, dark, empty, busy).
# Needs a folder of sample images (defaults to /tmp/pixtest/in).
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build"
OUT="${1:-$BUILD/snapshots}"
SAMPLES="${PICPRESS_SAMPLES:-/tmp/pixtest/in}"

mkdir -p "$BUILD/tmp" "$BUILD/modulecache" "$OUT"

TMPDIR="$BUILD/tmp" swiftc -Onone -g -swift-version 5 -target "$(uname -m)-apple-macos14.0" \
  -import-objc-header "$ROOT/Sources/PicPress/WebPBridge.h" \
  -module-cache-path "$BUILD/modulecache" \
  -I "$BUILD/libwebp/include" \
  "$ROOT/Sources/PicPress/Palette.swift" \
  "$ROOT/Sources/PicPress/Controls.swift" \
  "$ROOT/Sources/PicPress/HeaderBar.swift" \
  "$ROOT/Sources/PicPress/FileRowView.swift" \
  "$ROOT/Sources/PicPress/FileListView.swift" \
  "$ROOT/Sources/PicPress/EmptyStateView.swift" \
  "$ROOT/Sources/PicPress/FooterBar.swift" \
  "$ROOT/Sources/PicPress/MainViewController.swift" \
  "$ROOT/Sources/PicPress/ImageCompressor.swift" \
  "$ROOT/Sources/PicPress/CompressionQueue.swift" \
  "$ROOT/Sources/PicPressSnapshot/main.swift" \
  "$BUILD/WebPBridge.o" \
  "$BUILD/libwebp/lib/libwebp.a" \
  "$BUILD/libwebp/lib/libsharpyuv.a" \
  -o "$BUILD/picpress-snapshot"

PICPRESS_SAMPLES="$SAMPLES" "$BUILD/picpress-snapshot" "$OUT/window-light.png"
PICPRESS_SAMPLES="$SAMPLES" "$BUILD/picpress-snapshot" --dark "$OUT/window-dark.png"
PICPRESS_SAMPLES="$SAMPLES" "$BUILD/picpress-snapshot" --empty "$OUT/window-empty.png"
PICPRESS_SAMPLES="$SAMPLES" "$BUILD/picpress-snapshot" --running "$OUT/window-running.png"
