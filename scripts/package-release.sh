#!/bin/zsh
set -euo pipefail

VERSION="${1:?用法: scripts/package-release.sh <版本号>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

./scripts/build-app.sh >/dev/null
APP="dist/PackingProofViewer.app"
ZIP="dist/PackingProofViewer_v${VERSION}_macOS.zip"

ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
echo "已生成: $ZIP"
