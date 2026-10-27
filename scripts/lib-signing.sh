#!/usr/bin/env bash
#
# Shared code-signing helpers (macOS /bin/bash 3.2 compatible).
# Sourced by sign.sh, notarize.sh, package.sh and doctor.sh — not executed.

PP_LOCAL_CERT_NAME="${PP_LOCAL_CERT_NAME:-PicPress Local Signing}"

pp_note() { printf '• %s\n' "$*"; }
pp_warn() { printf '⚠️  %s\n' "$*" >&2; }
pp_fail() { printf '✗ %s\n' "$*" >&2; exit 1; }

# Every code-signing identity in the keychain, one per line, quoted name only.
pp_identities() {
  security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/^[[:space:]]*[0-9][0-9]*) [0-9A-Fa-f]* "\(.*\)"[[:space:]]*$/\1/p'
}

pp_first_identity_matching() {
  pp_identities | grep -F "$1" | head -n 1 || true
}

# Best identity this Mac can use, in descending order of usefulness:
#   1. $CODESIGN_IDENTITY (explicit override)
#   2. Developer ID Application — the only kind Apple accepts for notarization
#   3. Apple Development / Mac Developer — stable identity for local builds
#   4. PicPress Local Signing — self-signed, created by `make cert`
#   5. "-" — ad-hoc; Gatekeeper and TCC treat every build as a brand new app
pp_resolve_identity() {
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    printf '%s' "$CODESIGN_IDENTITY"
    return 0
  fi
  local candidate
  for pattern in "Developer ID Application" "Apple Development" "Mac Developer" "$PP_LOCAL_CERT_NAME"; do
    candidate="$(pp_first_identity_matching "$pattern")"
    if [[ -n "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  printf '%s' "-"
}

# adhoc | developer-id | development | other
pp_identity_kind() {
  case "$1" in
    "-") printf '%s' "adhoc" ;;
    *"Developer ID Application"*) printf '%s' "developer-id" ;;
    *"Apple Development"*|*"Mac Developer"*|*"iPhone Developer"*) printf '%s' "development" ;;
    *) printf '%s' "other" ;;
  esac
}

# Team identifier embedded in the certificate common name, e.g. 7HN4X9Q55S.
pp_identity_team() {
  printf '%s' "$1" | sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p'
}

# Human readable one-liner for reports.
pp_identity_label() {
  case "$(pp_identity_kind "$1")" in
    adhoc)       printf '%s' "ad-hoc（临时签名，每次构建都是「新 App」）" ;;
    developer-id) printf '%s' "Developer ID（可分发给任何人 + 可公证）" ;;
    development) printf '%s' "开发证书（只对本机有效，不能分发、不能公证）" ;;
    *)           printf '%s' "本地自签名（身份稳定，只能本机使用）" ;;
  esac
}

# Signing flags shared by every codesign invocation.
#   $1 identity   — as returned by pp_resolve_identity
#   $2 mode       — bundle | binary | image
#                   images take neither hardened runtime nor entitlements
#   $3 timestamp  — auto | none (none when Apple's TSA is unreachable)
# Sets PP_SIGN_FLAGS as an array; callers append --entitlements themselves.
pp_sign_flags() {
  local identity="$1"
  local mode="${2:-bundle}"
  local stamp="${3:-auto}"
  local kind
  kind="$(pp_identity_kind "$identity")"

  PP_SIGN_FLAGS=(--force --sign "$identity")

  # Hardened runtime is mandatory for notarization. It is harmless (and closer
  # to the shipped build) for local identities too, but meaningless for a dmg.
  if [[ "$mode" != "image" ]]; then
    PP_SIGN_FLAGS+=(--options runtime)
  fi

  case "$kind:$stamp" in
    adhoc:*|*:none)
      # Ad-hoc signatures cannot carry a timestamp, and a failed TSA round trip
      # must not block a local build.
      PP_SIGN_FLAGS+=(--timestamp=none)
      ;;
    *)
      PP_SIGN_FLAGS+=(--timestamp)
      ;;
  esac
}
