#!/bin/zsh
set -euo pipefail

VERSION="${1:?用法: scripts/package-release.sh <版本号>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ -f "$ROOT/scripts/signing.env" ]; then
    # shellcheck disable=SC1091
    . "$ROOT/scripts/signing.env"
fi

NOTARY_PROFILE="${NOTARY_PROFILE:-PackingProofNotary}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
    echo "错误：未设置 SIGN_IDENTITY" >&2
    echo "请复制 scripts/signing.env.example 为 scripts/signing.env，并填写本机 Developer ID Application 证书名称。" >&2
    exit 1
fi

./scripts/build-app.sh >/dev/null

APP="dist/PackingProofViewer.app"
DMG="dist/PackingProofViewer_v${VERSION}_macOS.dmg"
STAGING="$(mktemp -d)"

mkdir -p "$STAGING"
ditto "$APP" "$STAGING/PackingProofViewer.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "PackingProof 查看端" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG" >/dev/null

codesign --force \
  --timestamp \
  --sign "$SIGN_IDENTITY" \
  "$DMG"

xcrun notarytool submit \
  "$DMG" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

xcrun stapler staple "$DMG"

shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "已生成: $DMG"
