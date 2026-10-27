#!/usr/bin/env bash
#
# Packages (and signs) dist/PicPress.dmg from dist/PicPress.app.
# Called by `make dmg` and by scripts/notarize.sh.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib-signing.sh
source "$ROOT/scripts/lib-signing.sh"

APP="$ROOT/dist/PicPress.app"
DMG="$ROOT/dist/PicPress.dmg"
STAGE="$ROOT/.build/dmg"

[[ -d "$APP" ]] || pp_fail "缺少 ${APP}，先跑 make"

codesign --verify --deep --strict "$APP" 2>/dev/null \
  || pp_warn "App 签名校验没通过，打包出来的 dmg 也会被 Gatekeeper 拦"

rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
if ! hdiutil create -quiet -volname "PicPress" -srcfolder "$STAGE" \
  -ov -format UDZO "$DMG"; then
  rm -f "$DMG"
  pp_fail "创建 dmg 失败（hdiutil 需要在普通终端里运行，受限沙盒环境会被拒绝）"
fi

# A signed disk image is what `stapler` attaches the notarization ticket to.
IDENTITY="${CODESIGN_IDENTITY:-$(pp_resolve_identity)}"
"$ROOT/scripts/sign.sh" "$DMG" >/dev/null

pp_note "$DMG"
