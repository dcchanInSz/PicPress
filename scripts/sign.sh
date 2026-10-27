#!/usr/bin/env bash
#
# Signs PicPress with the best identity this Mac has, verifies the signature and
# explains what Gatekeeper will do when somebody opens the result.
#
#   ./scripts/sign.sh                        # dist/PicPress.app
#   ./scripts/sign.sh dist/PicPress.app      # explicit app bundle
#   ./scripts/sign.sh dist/picpress-cli      # bare Mach-O
#   ./scripts/sign.sh dist/PicPress.dmg      # disk image
#   CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" ./scripts/sign.sh
#
# Identity order (see scripts/lib-signing.sh): $CODESIGN_IDENTITY →
# Developer ID Application → Apple Development → "PicPress Local Signing" → ad-hoc.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib-signing.sh
source "$ROOT/scripts/lib-signing.sh"

QUIET=0
TARGET="${1:-$ROOT/dist/PicPress.app}"
if [[ "${1:-}" == "--quiet" ]]; then
  QUIET=1
  shift
  TARGET="${1:-$ROOT/dist/PicPress.app}"
  exec 1>/dev/null   # keep stderr: real errors must still surface
fi
ENTITLEMENTS="$ROOT/Resources/PicPress.entitlements"

[[ -e "$TARGET" ]] || pp_fail "找不到要签名的对象：${TARGET}（先跑 make）"

IDENTITY="${CODESIGN_IDENTITY:-$(pp_resolve_identity)}"
KIND="$(pp_identity_kind "$IDENTITY")"
TEAM="$(pp_identity_team "$IDENTITY")"
IS_BUNDLE=0
[[ -d "$TARGET" ]] && IS_BUNDLE=1

pp_note "签名 $(basename "$TARGET")"
printf '  identity : %s\n' "$IDENTITY"
printf '  type     : %s\n' "$(pp_identity_label "$IDENTITY")"
if [[ -n "$TEAM" ]]; then
  printf '  team     : %s\n' "$TEAM"
fi

# Nested code has to be sealed before the bundle that contains it. PicPress
# links libwebp statically today, so this loop is usually a no-op — it is here
# so a future framework/helper does not silently break notarization.
sign_nested_code() {
  local bundle="$1"
  [[ -d "$bundle/Contents/Frameworks" ]] || return 0
  local nested
  while IFS= read -r nested; do
    [[ -n "$nested" ]] || continue
    pp_note "  嵌套组件 $(basename "$nested")"
    codesign --force --sign "$IDENTITY" --timestamp=none "$nested" >/dev/null
  done < <(find "$bundle/Contents/Frameworks" -depth \
    \( -name '*.dylib' -o -name '*.framework' -o -name '*.app' -o -name '*.bundle' \) -print)
}

ERR_FILE="$(mktemp -t picpress-sign)"
trap 'rm -f "$ERR_FILE"' EXIT

if [[ "$TARGET" == *.dmg ]]; then
  MODE=image
elif [[ "$IS_BUNDLE" == "1" ]]; then
  MODE=bundle
else
  MODE=binary
fi

build_args() {
  local stamp="${1:-auto}"
  PP_SIGN_FLAGS=()
  pp_sign_flags "$IDENTITY" "$MODE" "$stamp"
  SIGN_ARGS=("${PP_SIGN_FLAGS[@]}")
  case "$MODE" in
    bundle)
      [[ -f "$ENTITLEMENTS" ]] || pp_fail "缺少 entitlements 文件：$ENTITLEMENTS"
      SIGN_ARGS+=(--entitlements "$ENTITLEMENTS")
      ;;
    binary)
      # A stable identifier keeps the CLI's own TCC/keychain identity fixed.
      SIGN_ARGS+=(--identifier com.dcchanin.picpress.cli)
      ;;
  esac
}

if [[ "$IS_BUNDLE" == "1" ]]; then
  sign_nested_code "$TARGET"
fi

build_args 0
if ! codesign "${SIGN_ARGS[@]}" "$TARGET" 2>"$ERR_FILE"; then
  if grep -qi "timestamp" "$ERR_FILE"; then
    pp_warn "时间戳服务器不可达，退回 --timestamp=none 重签"
    build_args 1
    codesign "${SIGN_ARGS[@]}" "$TARGET"
  else
    cat "$ERR_FILE" >&2
    pp_fail "签名失败"
  fi
fi

codesign --verify --deep --strict "$TARGET" 2>/dev/null || pp_fail "签名校验失败：$TARGET"

if [[ "$QUIET" == "0" ]]; then
  pp_note "验证签名"
  codesign --verify --deep --strict --verbose=2 "$TARGET" 2>&1 | sed 's/^/  /'

  echo
  pp_note "签名详情"
  codesign --display --verbose=4 "$TARGET" 2>&1 \
    | grep -E '^(Identifier|Format|Authority|TeamIdentifier|Timestamp|Runtime Version|Sealed Resources)' \
    | sed 's/^/  /'
  codesign --display --verbose=4 "$TARGET" 2>&1 \
    | grep -oE 'flags=0x[0-9a-f]+\([^)]*\)' | sed 's/^/  /'

  if [[ "$IS_BUNDLE" == "1" ]]; then
    echo
    pp_note "entitlements（越少越好）"
    codesign --display --entitlements :- "$TARGET" 2>/dev/null | plutil -p - 2>/dev/null | sed 's/^/  /'
  fi

  echo
  if [[ "$TARGET" == *.dmg ]]; then
    assess=(spctl --assess --type open --context context:primary-signature --verbose=4 "$TARGET")
  else
    assess=(spctl --assess --type execute --verbose=4 "$TARGET")
  fi

  if assess_out="$("${assess[@]}" 2>&1)"; then
    pp_note "Gatekeeper：通过 —— 别人双击打开时不会弹「无法验证开发者」"
  else
    pp_warn "Gatekeeper：未通过 —— ${assess_out##*source=}"
    case "$KIND" in
      developer-id)
        echo "     证书没问题，但还没公证。跑一次「make release」（需要 Apple ID 凭据）即可消除弹窗。" ;;
      development)
        echo "     开发证书只对本机有效：这台 Mac 上不会弹窗，把 App 发给别人仍会提示「无法验证开发者」。"
        echo "     要分发给别人，请在同一个开发者账号下再申请一张 Developer ID Application 证书。" ;;
      adhoc)
        echo "     ad-hoc 签名的 cdhash 每次构建都会变，macOS 会把每个新构建当成新 App："
        echo "     隐私授权（文件夹访问等）会被重置并重新弹窗。"
        echo "     本机开发建议跑「make cert」生成稳定身份的本地证书。" ;;
      *)
        echo "     本地自签名只能在本机使用；分发请用 Developer ID Application + 公证。" ;;
    esac
  fi

  echo
  pp_note "完成：$TARGET"
fi
