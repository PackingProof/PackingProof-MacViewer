#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ -f "$ROOT/scripts/signing.env" ]; then
    # shellcheck disable=SC1091
    . "$ROOT/scripts/signing.env"
fi

SIGN_IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
    echo "错误：未设置 SIGN_IDENTITY" >&2
    echo "请复制 scripts/signing.env.example 为 scripts/signing.env，并填写本机 Developer ID Application 证书名称。" >&2
    exit 1
fi

swift build -c release

APP_DIR="dist/PackingProofViewer.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp .build/release/PackingProofViewer "$APP_DIR/Contents/MacOS/PackingProofViewer"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

codesign --force \
  --options runtime \
  --timestamp \
  --sign "$SIGN_IDENTITY" \
  "$APP_DIR"

echo "已生成: $APP_DIR"
echo "运行: open $APP_DIR"
