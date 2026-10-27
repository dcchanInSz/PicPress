#!/usr/bin/env bash
#
# Prints everything that decides whether macOS will show a security or privacy
# dialog for PicPress: the signing identity, hardened runtime, entitlements,
# Gatekeeper verdict, quarantine flag and notarization ticket.
#
#   ./scripts/doctor.sh
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib-signing.sh
source "$ROOT/scripts/lib-signing.sh"

APP="$ROOT/dist/PicPress.app"
DMG="$ROOT/dist/PicPress.dmg"

section() { printf '\n\033[1m%s\033[0m\n' "$*"; }

section "系统"
printf '  macOS %s (%s) · %s\n' "$(sw_vers -productVersion)" "$(sw_vers -buildVersion)" "$(uname -m)"

section "可用签名身份"
if pp_identities | grep -q .; then
  pp_identities | sed 's/^/  • /'
else
  echo "  （钥匙串里没有代码签名证书）"
fi
IDENTITY="${CODESIGN_IDENTITY:-$(pp_resolve_identity)}"
KIND="$(pp_identity_kind "$IDENTITY")"
printf '\n  将使用：%s\n' "$IDENTITY"
printf '  类型  ：%s\n' "$(pp_identity_label "$IDENTITY")"

app_status="missing"
if [[ -d "$APP" ]]; then
  section "App：$APP"
  if codesign --verify --deep --strict "$APP" 2>/dev/null; then
    echo "  ✓ 签名有效"
    codesign --display --verbose=2 "$APP" 2>&1 \
      | grep -E '^(Identifier|Authority|TeamIdentifier|Timestamp)' | sed 's/^/    /'
  else
    echo "  ✗ 签名无效或未签名"
  fi

  # Note: pipefail + `grep -q` would kill the pipeline with SIGPIPE, so capture first.
  sig_info="$(codesign --display --verbose=2 "$APP" 2>&1)"
  if grep -q 'flags=.*runtime' <<<"$sig_info"; then
    echo "  ✓ 已启用 Hardened Runtime"
  else
    echo "  · 未启用 Hardened Runtime（公证要求开启）"
  fi

  ent="$(codesign --display --entitlements :- "$APP" 2>/dev/null | plutil -p - 2>/dev/null)"
  ent_compact="$(printf '%s' "$ent" | tr -d '[:space:]')"
  if [[ -z "$ent_compact" || "$ent_compact" == "{}" ]]; then
    echo "  ✓ entitlements 为空（不联网、不碰相机/麦克风/照片库/自动化）"
  else
    printf '  · entitlements：\n%s\n' "$(printf '%s' "$ent" | sed 's/^/      /')"
  fi

  if xattr -p com.apple.quarantine "$APP" >/dev/null 2>&1; then
    echo "  ⚠️  带 com.apple.quarantine —— 首次打开会走 Gatekeeper"
  else
    echo "  ✓ 无 quarantine 标记"
  fi

  if xcrun stapler validate "$APP" >/dev/null 2>&1; then
    echo "  ✓ 已钉公证票据（离线也能通过 Gatekeeper）"
  else
    echo "  · 没有公证票据"
  fi

  if out="$(spctl --assess --type execute --verbose=4 "$APP" 2>&1)"; then
    echo "  ✓ Gatekeeper 放行：别人双击不会弹窗"
    app_status="ok"
  else
    echo "  ✗ Gatekeeper 拦截：${out##*: }"
    app_status="rejected"
  fi
fi

if [[ -f "$DMG" ]]; then
  section "DMG：$DMG"
  if out="$(spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG" 2>&1)"; then
    echo "  ✓ 磁盘映像已签名且已公证"
  else
    echo "  ✗ 磁盘映像未通过 Gatekeeper（${out##*: }）"
  fi
fi

section "结论"
if [[ "$app_status" == "ok" ]]; then
  echo "  分发给任何人都不需要「右键 → 打开」，也不会弹 Gatekeeper 警告。"
else
  case "$KIND" in
    adhoc)
      echo "  ad-hoc 签名：每次 make 都会产生新的 cdhash，macOS 视为新 App，"
      echo "  「PicPress 想访问你的…文件夹」这类授权会反复弹。"
      echo "  → 本机开发先跑：make cert（生成稳定身份的本地证书）" ;;
    development)
      echo "  开发证书：本机运行不会弹窗，隐私授权也能记住；但发给别人仍会提示"
      echo "  「无法验证开发者」。"
      echo "  → 要分发：在开发者账号里申请 Developer ID Application 证书后 make release" ;;
    developer-id)
      echo "  Developer ID 证书已就绪，但还没公证。"
      echo "  → 跑：NOTARY_PROFILE=… make release" ;;
    *)
      echo "  本地自签名只能本机使用。"
      echo "  → 要分发：Developer ID Application + 公证（make release）" ;;
  esac
fi

section "重置隐私授权（排查「弹窗反复出现」时用）"
cat <<'EOF'
  tccutil reset SystemPolicyDesktopFolder   com.dcchanin.picpress
  tccutil reset SystemPolicyDocumentsFolder com.dcchanin.picpress
  tccutil reset SystemPolicyDownloadsFolder com.dcchanin.picpress
  tccutil reset SystemPolicyRemovableVolumes com.dcchanin.picpress
  tccutil reset SystemPolicyNetworkVolumes  com.dcchanin.picpress
EOF
