#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${AWAYO_REPO_URL:-https://github.com/brysonkbarney/awayo.git}"
REF="${AWAYO_REF:-main}"
INSTALL_DIR="${AWAYO_INSTALL_DIR:-$HOME/Applications}"
OPEN_APP="${AWAYO_OPEN:-1}"
WORK_DIR=""
CLONED_WORK_DIR=""

usage() {
  cat <<'USAGE'
Install Awayo from source.

Usage:
  Scripts/install.sh [options]

Options:
  --dir PATH      Install Awayo.app into PATH. Default: ~/Applications
  --ref NAME      Git branch, tag, or commit to install. Default: main
  --repo URL      Git repository URL to install from.
  --no-open       Install without opening Awayo.
  -h, --help      Show this help.

Environment:
  AWAYO_INSTALL_DIR  Install directory. Default: ~/Applications
  AWAYO_REF          Git branch, tag, or commit. Default: main
  AWAYO_REPO_URL     Git repository URL.
  AWAYO_OPEN         Set to 0 to skip opening the app.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --dir)
    INSTALL_DIR="${2:-}"
    shift 2
    ;;
  --ref)
    REF="${2:-}"
    shift 2
    ;;
  --repo)
    REPO_URL="${2:-}"
    shift 2
    ;;
  --no-open)
    OPEN_APP="0"
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown option: $1" >&2
    usage >&2
    exit 1
    ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Awayo is a macOS app. Run this installer on macOS." >&2
  exit 1
fi

if [[ -z "$INSTALL_DIR" ]]; then
  echo "Install directory cannot be empty." >&2
  exit 1
fi

for command in git swift; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing required command: $command" >&2
    echo "Install Xcode Command Line Tools with: xcode-select --install" >&2
    exit 1
  fi
done

cleanup() {
  if [[ -n "$CLONED_WORK_DIR" ]]; then
    rm -rf "$CLONED_WORK_DIR"
  fi
}
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd || true)"
if [[ -n "$SCRIPT_DIR" && -x "$SCRIPT_DIR/package_app.sh" ]]; then
  WORK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  CLONED_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/awayo-install.XXXXXX")"
  WORK_DIR="$CLONED_WORK_DIR/awayo"
  echo "Fetching Awayo from $REPO_URL ($REF)..."
  if ! git clone --depth 1 --branch "$REF" "$REPO_URL" "$WORK_DIR"; then
    rm -rf "$WORK_DIR"
    git clone --filter=blob:none "$REPO_URL" "$WORK_DIR"
    git -C "$WORK_DIR" checkout "$REF"
  fi
fi

echo "Building Awayo..."
APP_PATH="$("$WORK_DIR/Scripts/package_app.sh" | tail -n 1)"

DEST_PATH="$INSTALL_DIR/Awayo.app"
mkdir -p "$INSTALL_DIR"

if [[ -d "$DEST_PATH" ]]; then
  existing_pids="$(pgrep -f "$DEST_PATH/Contents/MacOS/Awayo" || true)"
  if [[ -n "$existing_pids" ]]; then
    echo "Stopping existing Awayo from $DEST_PATH..."
    while IFS= read -r pid; do
      [[ -z "$pid" ]] && continue
      kill "$pid" >/dev/null 2>&1 || true
    done <<< "$existing_pids"
  fi
fi

rm -rf "$DEST_PATH"
ditto "$APP_PATH" "$DEST_PATH"

if command -v codesign >/dev/null 2>&1; then
  codesign --verify --deep --strict "$DEST_PATH"
fi

if [[ "$OPEN_APP" != "0" ]]; then
  open -n "$DEST_PATH"
fi

echo "Awayo installed at $DEST_PATH"
