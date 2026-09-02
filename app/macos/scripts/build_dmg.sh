#!/usr/bin/env bash
#
# Builds a distributable, professional Aika.dmg from an already-built
# Aika.app (release build). Run this on macOS, after:
#
#   flutter build macos --release
#
# Usage:
#   ./macos/scripts/build_dmg.sh [path/to/Aika.app] [output/dir]
#
# Defaults:
#   APP_PATH   = build/macos/Build/Products/Release/Aika.app
#   OUTPUT_DIR = dist
#
# Requires `create-dmg` (https://github.com/create-dmg/create-dmg):
#   brew install create-dmg
#
# This script does NOT sign or notarize anything — run it AFTER the .app
# has already been codesigned (and ideally notarized/stapled). See
# docs/macos-release.md for the full, ordered procedure.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

APP_PATH="${1:-$ROOT_DIR/build/macos/Build/Products/Release/Aika.app}"
OUTPUT_DIR="${2:-$ROOT_DIR/dist}"
APP_NAME="Aika"
VOLUME_NAME="Aika"
DMG_PATH="$OUTPUT_DIR/${APP_NAME}.dmg"
BACKGROUND_IMAGE="$ROOT_DIR/macos/scripts/dmg_background.png"

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "error: create-dmg is not installed. Install it with: brew install create-dmg" >&2
  exit 1
fi

if [ ! -d "$APP_PATH" ]; then
  echo "error: $APP_PATH not found. Run 'flutter build macos --release' first." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
rm -f "$DMG_PATH"

create-dmg \
  --volname "$VOLUME_NAME" \
  --background "$BACKGROUND_IMAGE" \
  --window-pos 200 120 \
  --window-size 660 420 \
  --icon-size 128 \
  --icon "${APP_NAME}.app" 180 170 \
  --hide-extension "${APP_NAME}.app" \
  --app-drop-link 480 170 \
  --no-internet-enable \
  "$DMG_PATH" \
  "$APP_PATH"

echo ""
echo "Created: $DMG_PATH"
echo ""
echo "SHA-256 checksum (for the GitHub Release notes):"
shasum -a 256 "$DMG_PATH"
