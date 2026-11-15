#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Uncomew"
BUILD_CONFIG="release"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
bash "$ROOT_DIR/scripts/compatibility_check.sh"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: Uncomew is a macOS app and must be built on macOS."
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift compiler not found."
  echo "Install Apple's Command Line Tools with:"
  echo "  xcode-select --install"
  exit 1
fi

if ! xcrun --show-sdk-path >/dev/null 2>&1; then
  echo "macOS SDK not found."
  echo "Install Apple's Command Line Tools with:"
  echo "  xcode-select --install"
  exit 1
fi

echo "[1/4] Building Uncomew with Swift Package Manager..."
cd "$ROOT_DIR"
xcrun swift build -c "$BUILD_CONFIG" --product "$APP_NAME"

BIN_DIR="$(xcrun swift build -c "$BUILD_CONFIG" --show-bin-path)"
EXECUTABLE="$BIN_DIR/$APP_NAME"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Error: built executable was not found at:"
  echo "  $EXECUTABLE"
  exit 1
fi

echo "[2/4] Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$EXECUTABLE" "$MACOS_DIR/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
chmod +x "$MACOS_DIR/$APP_NAME"

# Ad-hoc signing gives the locally built bundle a coherent code signature.
echo "[3/4] Ad-hoc signing..."
codesign --force --deep --sign - "$APP_DIR" >/dev/null
bash "$ROOT_DIR/scripts/validate_app.sh" "$APP_DIR"

echo "[4/4] Finished."
echo
echo "App created at:"
echo "  $APP_DIR"
echo
echo "Launch with:"
echo "  open \"$APP_DIR\""
echo
echo "To install with previous-version recovery, run: bash setup.sh"
