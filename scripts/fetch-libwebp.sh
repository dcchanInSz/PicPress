#!/usr/bin/env bash
#
# Downloads libwebp and builds a static library into .build/libwebp.
# No Homebrew, no system packages — just the C compiler from the
# Command Line Tools.
#
set -euo pipefail

LIBWEBP_VERSION="${LIBWEBP_VERSION:-1.5.0}"
LIBWEBP_SHA256="${LIBWEBP_SHA256:-7d6fab70cf844bf6769077bd5d7a74893f8ffd4dfb42861745750c63c2a5c92c}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build"
DEST="$BUILD/libwebp"
MIN_MACOS="${MACOSX_DEPLOYMENT_TARGET:-14.0}"

if [[ -f "$DEST/lib/libwebp.a" && -f "$DEST/lib/libsharpyuv.a" && -f "$DEST/include/webp/encode.h" ]]; then
  echo "• libwebp $LIBWEBP_VERSION already built"
  exit 0
fi

mkdir -p "$BUILD"
cd "$BUILD"

TARBALL="libwebp-$LIBWEBP_VERSION.tar.gz"
if [[ ! -f "$TARBALL" ]]; then
  echo "• downloading libwebp $LIBWEBP_VERSION"
  curl -fL --retry 3 --max-time 120 \
    -o "$TARBALL" \
    "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-$LIBWEBP_VERSION.tar.gz"
fi

ACTUAL_SHA="$(shasum -a 256 "$TARBALL" | awk '{print $1}')"
if [[ "$LIBWEBP_SHA256" != "skip" && "$ACTUAL_SHA" != "$LIBWEBP_SHA256" ]]; then
  echo "✗ checksum mismatch for $TARBALL" >&2
  echo "  expected $LIBWEBP_SHA256" >&2
  echo "  actual   $ACTUAL_SHA" >&2
  exit 1
fi

echo "• building libwebp $LIBWEBP_VERSION (static, macOS $MIN_MACOS+)"
rm -rf "libwebp-$LIBWEBP_VERSION"
tar xzf "$TARBALL"
cd "libwebp-$LIBWEBP_VERSION"
make -f makefile.unix src/libwebp.a sharpyuv/libsharpyuv.a -j"$(sysctl -n hw.ncpu)" \
  EXTRA_FLAGS="-mmacosx-version-min=$MIN_MACOS" >/dev/null

mkdir -p "$DEST/lib" "$DEST/include"
cp src/libwebp.a sharpyuv/libsharpyuv.a "$DEST/lib/"
rm -rf "$DEST/include/webp"
cp -R src/webp "$DEST/include/"
echo "• libwebp ready at .build/libwebp"
