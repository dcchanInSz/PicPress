#!/usr/bin/env bash
#
# Creates a self-signed code-signing identity ("PicPress Local Signing") in the
# login keychain. Nothing is uploaded anywhere and the key never leaves this Mac.
#
# Why bother when ad-hoc signing already works?
#   macOS keys per-app privacy decisions (Files & Folders, Apple Events, …) on
#   the app's *signing identity*. Ad-hoc signatures are keyed on the cdhash, so
#   every `make` looks like a brand new app and macOS asks again — that is the
#   "PicPress 想要访问你的『桌面』文件夹" dialog coming back after each build.
#   A stable certificate keeps one identity across rebuilds, so the system asks
#   once and remembers.
#
# This certificate is only trusted on this Mac. To ship the app to other people
# you still need a Developer ID Application certificate + notarization
# (`make release`).
#
# Remove it again with:
#   security delete-certificate -c "PicPress Local Signing" \
#     "$HOME/Library/Keychains/login.keychain-db"
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib-signing.sh
source "$ROOT/scripts/lib-signing.sh"

KEYCHAIN="${PP_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
DAYS="${PP_CERT_DAYS:-3650}"

if pp_identities | grep -Fxq "$PP_LOCAL_CERT_NAME"; then
  pp_note "证书「${PP_LOCAL_CERT_NAME}」已经存在，无需重复创建"
  exit 0
fi

if [[ ! -f "$KEYCHAIN" ]]; then
  pp_fail "找不到钥匙串：$KEYCHAIN"
fi

WORK="$(mktemp -d -t picpress-cert)"
trap 'rm -rf "$WORK"' EXIT

PASS="$(openssl rand -hex 16)"

cat > "$WORK/openssl.cnf" <<EOF
[ req ]
default_bits       = 2048
distinguished_name = dn
prompt             = no
x509_extensions    = codesign

[ dn ]
CN = $PP_LOCAL_CERT_NAME
O  = PicPress

[ codesign ]
basicConstraints     = critical,CA:false
keyUsage             = critical,digitalSignature
extendedKeyUsage     = critical,codeSigning
subjectKeyIdentifier = hash
EOF

pp_note "生成自签名证书「${PP_LOCAL_CERT_NAME}」"
openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days "$DAYS" \
  -config "$WORK/openssl.cnf" \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null

make_p12() {
  openssl pkcs12 -export "$@" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$PP_LOCAL_CERT_NAME" \
    -out "$WORK/identity.p12" -passout "pass:$PASS" 2>/dev/null
}

# OpenSSL 3 defaults to AES-256 + PBKDF2-SHA256, which Security.framework's
# importer cannot read ("MAC verification failed during PKCS12 import").
# -legacy emits the 3DES/RC2 layout the keychain expects; older LibreSSL
# builds already default to it, hence the fallback.
if ! make_p12 -legacy; then
  make_p12
fi

pp_note "导入登录钥匙串（只授权 codesign / security 使用私钥）"
if ! security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASS" \
  -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/productsign >/dev/null 2>"$WORK/import.err"; then
  trap - EXIT   # keep the scratch directory so the manual import can find it
  cat "$WORK/import.err" >&2
  cat >&2 <<EOF

✗ 导入钥匙串失败。可以手动完成这一步：
    1. 双击打开「钥匙串访问」→ 左下角「登录」钥匙串
    2. 文件 → 导入项目… → 选中 $WORK/identity.p12（密码：$PASS）
    3. 再跑一次 make cert 应该就能识别
EOF
  exit 1
fi

if [[ "${PP_TRUST_LOCAL_CERT:-0}" == "1" ]]; then
  pp_note "标记为受信任的代码签名根（可能会弹一次钥匙串密码框）"
  security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"
fi

if ! pp_identities | grep -Fxq "$PP_LOCAL_CERT_NAME"; then
  pp_fail "证书导入后仍然找不到，请检查钥匙串访问权限"
fi

echo
pp_note "完成。之后的签名会自动使用它："
echo "     make        # 构建 + 用「${PP_LOCAL_CERT_NAME}」签名"
echo "     make sign   # 只重新签名现有构建"
echo
pp_note "注意：这张证书只在本机受信。分发给别人仍需 Developer ID + 公证（make release）。"
