#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="WhatsLive"
DISPLAY_NAME="What's Live"
INSTALL_DIR="${WHATSLIVE_INSTALL_DIR:-$HOME/Applications}"

BUILD_CONFIGURATION=release "$ROOT_DIR/script/build_and_run.sh" --verify
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$DISPLAY_NAME.app"
cp -R "$ROOT_DIR/dist/$APP_NAME.app" "$INSTALL_DIR/$DISPLAY_NAME.app"

/usr/bin/mdimport "$INSTALL_DIR/$DISPLAY_NAME.app" >/dev/null 2>&1 || true

echo "Installed $DISPLAY_NAME to $INSTALL_DIR/$DISPLAY_NAME.app"
echo "Spotlight name: $DISPLAY_NAME"
