#!/usr/bin/env bash
#
# Notarizes the already signed app + dmg so Gatekeeper never shows the
# "Apple could not verify…" dialog on a fresh Mac.
#
# Requires a **Developer ID Application** certificate (not Apple Development).
# Credentials, pick one:
#
#   1. Keychain profile (recommended, run once):
#        xcrun notarytool store-credentials picpress \
#          --apple-id you@example.com --team-id TEAMID --password app-specific-password
#        NOTARY_PROFILE=picpress make release
#
#   2. Environment:
#        APPLE_ID=… APPLE_TEAM_ID=… APPLE_APP_PASSWORD=… make release
#
#   3. App Store Connect API key:
#        APPLE_KEY_PATH=AuthKey_XXXX.p8 APPLE_KEY_ID=XXXX APPLE_ISSUER_ID=… make release
#
# Apple ID + app-specific password is created at https://appleid.apple.com →
# 登录与安全 → App 专用密码.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib-signing.sh
source "$ROOT/scripts/lib-signing.sh"

APP="$ROOT/dist/PicPress.app"
DMG="$ROOT/dist/PicPress.dmg"
ZIP="$ROOT/.build/PicPress-notarize.zip"
LOG_DIR="$ROOT/.build/notary"

IDENTITY="${CODESIGN_IDENTITY:-$(pp_resolve_identity)}"
KIND="$(pp_identity_kind "$IDENTITY")"

if [[ "$KIND" != "developer-id" ]]; then
  cat >&2 <<EOF
✗ 公证需要 Developer ID Application 证书，当前用的是：$IDENTITY
  （$(pp_identity_label "$IDENTITY")）

  用同一个 Apple 开发者账号再申请一张 Developer ID Application 证书：
    Xcode → Settings… → Accounts → 选中团队 → Manage Certificates… → ＋ → Developer ID Application
  或者 https://developer.apple.com/account/resources/certificates

  申请好后重新跑：
    make release
EOF
  exit 1
fi

# --- credentials ---------------------------------------------------------
AUTH=()
DESC=""
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  AUTH=(--keychain-profile "$NOTARY_PROFILE")
  DESC="keychain profile '$NOTARY_PROFILE'"
elif [[ -n "${APPLE_KEY_PATH:-}" && -n "${APPLE_KEY_ID:-}" && -n "${APPLE_ISSUER_ID:-}" ]]; then
  AUTH=(--key "$APPLE_KEY_PATH" --key-id "$APPLE_KEY_ID" --issuer "$APPLE_ISSUER_ID")
  DESC="App Store Connect API key $APPLE_KEY_ID"
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
  AUTH=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
  DESC="Apple ID $APPLE_ID"
else
  cat >&2 <<'EOF'
✗ 缺少公证凭据。三选一：

  A) 钥匙串里存一份（一次性）：
       xcrun notarytool store-credentials picpress \
         --apple-id <你的 Apple ID> --team-id <TEAMID> --password <App 专用密码>
       NOTARY_PROFILE=picpress make release

  B) 环境变量：
       APPLE_ID=… APPLE_TEAM_ID=… APPLE_APP_PASSWORD=… make release

  C) App Store Connect API Key：
       APPLE_KEY_PATH=AuthKey_XXX.p8 APPLE_KEY_ID=XXX APPLE_ISSUER_ID=… make release
EOF
  exit 1
fi

mkdir -p "$LOG_DIR"

submit() {
  local what="$1" path="$2" out
  pp_note "提交公证：${what}（${DESC}）"
  out="$(xcrun notarytool submit "$path" "${AUTH[@]}" --wait --output-format json 2>&1)" || {
    printf '%s\n' "$out" >&2
    pp_fail "notarytool 提交失败"
  }
  printf '%s\n' "$out" > "$LOG_DIR/$(basename "$path").json"
  local status id
  status="$(printf '%s' "$out" | plutil -extract status raw -o - - 2>/dev/null || true)"
  id="$(printf '%s' "$out" | plutil -extract id raw -o - - 2>/dev/null || true)"
  if [[ "$status" != "Accepted" ]]; then
    pp_warn "公证结果：${status:-未知}（id=${id:-?}）"
    [[ -n "$id" ]] && xcrun notarytool log "$id" "${AUTH[@]}" "$LOG_DIR/$id.json" >&2 || true
    pp_fail "Apple 拒绝了这次提交，日志在上面"
  fi
  pp_note "公证通过（id=${id:-?}）"
}

# --- app ---------------------------------------------------------------
[[ -d "$APP" ]] || pp_fail "缺少 ${APP}，先跑 make"

"$ROOT/scripts/sign.sh" "$APP" >/dev/null
pp_note "打包 app 用于上传"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
submit "PicPress.app" "$ZIP"
pp_note "把公证票据钉到 app 上"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# --- dmg ---------------------------------------------------------------
# Rebuild after stapling so the app inside the image carries its own ticket
# (offline installs keep working).
"$ROOT/scripts/package.sh" >/dev/null
pp_note "上传 dmg"
submit "PicPress.dmg" "$DMG"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo
pp_note "Gatekeeper 检查"
spctl --assess --type execute --verbose=4 "$APP" 2>&1 | sed 's/^/  /' || true
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG" 2>&1 | sed 's/^/  /' || true

echo
pp_note "完成：dist/PicPress.dmg 已签名 + 公证 + 钉票据"
pp_note "任何 Mac 上双击打开都不会再弹「无法验证开发者」"
