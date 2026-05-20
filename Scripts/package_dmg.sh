#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Awayo"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
DIST_DIR="$ROOT_DIR/dist"
DMG_STAGING_DIR="$DIST_DIR/dmg"
VERSIONED_DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
LATEST_DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
VOLUME_NAME="$APP_NAME $VERSION"

APP_PATH="$("$ROOT_DIR/Scripts/package_app.sh" | tail -n 1)"

rm -rf "$DMG_STAGING_DIR" "$VERSIONED_DMG_PATH" "$LATEST_DMG_PATH"
mkdir -p "$DMG_STAGING_DIR"

ditto "$APP_PATH" "$DMG_STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$DMG_STAGING_DIR/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$VERSIONED_DMG_PATH" >/dev/null

cp "$VERSIONED_DMG_PATH" "$LATEST_DMG_PATH"
rm -rf "$DMG_STAGING_DIR"

echo "$VERSIONED_DMG_PATH"
