#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$("$ROOT_DIR/Scripts/package_app.sh" | tail -n 1)"

open -n "$APP_PATH"
echo "Opened $APP_PATH"
