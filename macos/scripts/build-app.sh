#!/bin/bash
# Builds the SwiftPM executable and wraps it into a menu bar .app bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP_NAME="DeepSeekBalanceIndicator"
APP="$ROOT/build/$APP_NAME.app"

cd "$ROOT"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Menu bar artwork is read straight from Contents/Resources by MenuBarIcon.
ICON="$ROOT/Sources/$APP_NAME/Resources/icon.png"
if [ ! -f "$ICON" ]; then
  echo "!! missing $ICON (run scripts/make-icon.sh)" >&2
  exit 1
fi
cp "$ICON" "$APP/Contents/Resources/icon.png"

# Ad-hoc signature keeps macOS from quarantining the freshly built binary.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
  echo "!! ad-hoc codesign failed (the app still runs locally)"

echo "==> done: $APP"
echo "    open \"$APP\"    # launch"
echo "    $APP/Contents/MacOS/$APP_NAME --check-resources"
