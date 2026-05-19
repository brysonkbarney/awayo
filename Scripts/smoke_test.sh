#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$("$ROOT_DIR/Scripts/package_app.sh" | tail -n 1)"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/Awayo"

codesign --verify --deep --strict "$APP_PATH"

existing_pids="$(pgrep -f "$EXECUTABLE_PATH" || true)"
open -n "$APP_PATH"

pid=""
for _ in {1..30}; do
  current_pids="$(pgrep -f "$EXECUTABLE_PATH" || true)"

  while IFS= read -r current_pid; do
    [[ -z "$current_pid" ]] && continue

    already_running=false
    while IFS= read -r existing_pid; do
      [[ -z "$existing_pid" ]] && continue

      if [[ "$current_pid" == "$existing_pid" ]]; then
        already_running=true
        break
      fi
    done <<< "$existing_pids"

    if [[ "$already_running" == false ]]; then
      pid="$current_pid"
      break 2
    fi
  done <<< "$current_pids"

  sleep 0.25
done

if [[ -z "$pid" ]]; then
  echo "Awayo did not launch from $APP_PATH" >&2
  exit 1
fi

kill "$pid" >/dev/null 2>&1 || true
echo "Smoke test passed: $APP_PATH launched as process $pid"
