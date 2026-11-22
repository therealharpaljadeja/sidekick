#!/usr/bin/env bash
# Builds build/Sidekick.app. Pass --install to copy it to /Applications and launch it.
# UNIVERSAL=1 builds for both Apple Silicon and Intel.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
ARCH_FLAGS=()
[[ "${UNIVERSAL:-}" == "1" ]] && ARCH_FLAGS=(--arch arm64 --arch x86_64)
swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/Sidekick"

APP="build/Sidekick.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts"
cp "$BIN" "$APP/Contents/MacOS/Sidekick"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Fonts/*.ttf Resources/Fonts/OFL.txt "$APP/Contents/Resources/Fonts/"

SIGN_FLAGS=(--force --sign "${SIGN_IDENTITY:--}")
[[ -n "${SIGN_IDENTITY:-}" ]] && SIGN_FLAGS+=(--options runtime --timestamp)
codesign "${SIGN_FLAGS[@]}" "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Sidekick 2>/dev/null || true
  rm -rf /Applications/Sidekick.app
  cp -R "$APP" /Applications/Sidekick.app
  open /Applications/Sidekick.app
  echo "Installed to /Applications/Sidekick.app"
fi
