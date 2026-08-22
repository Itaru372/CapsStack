#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_PATH="${1:-$ROOT_DIR/outputs/CapsStack.pkg}"

if [[ -z "${NOTARY_PROFILE:-}" ]]; then
  echo "NOTARY_PROFILE に notarytool のKeychainプロファイル名を設定してください。" >&2
  exit 2
fi

xcrun notarytool submit "$PKG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$PKG_PATH"
xcrun stapler validate "$PKG_PATH"
