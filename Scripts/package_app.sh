#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Awayo"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"

swift build -c release --product "$APP_NAME"
BIN_DIR="$(swift build -c release --show-bin-path | tail -n 1)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "$ROOT_DIR/App/Info.plist" "$CONTENTS_DIR/Info.plist"
swift "$ROOT_DIR/Scripts/generate_icon.swift" "$RESOURCES_DIR/AppIcon.icns"
chmod 755 "$MACOS_DIR/$APP_NAME"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - --timestamp=none "$APP_DIR" >/dev/null
fi

echo "$APP_DIR"
