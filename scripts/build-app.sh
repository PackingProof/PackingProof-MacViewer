#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release

APP_DIR="dist/PackingProofViewer.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp .build/release/PackingProofViewer "$APP_DIR/Contents/MacOS/PackingProofViewer"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
codesign --force --sign - "$APP_DIR"

echo "已生成: $APP_DIR"
echo "运行: open $APP_DIR"
