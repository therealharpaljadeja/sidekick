#!/usr/bin/env bash
# Builds build/Sidekick.app. Pass --install to copy it to /Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Sidekick"

APP="build/Sidekick.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts"
cp "$BIN" "$APP/Contents/MacOS/Sidekick"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Fonts/*.ttf Resources/Fonts/OFL.txt "$APP/Contents/Resources/Fonts/"

codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Sidekick 2>/dev/null || true
  rm -rf /Applications/Sidekick.app
  cp -R "$APP" /Applications/Sidekick.app
  open /Applications/Sidekick.app
  echo "Installed to /Applications/Sidekick.app"
fi
