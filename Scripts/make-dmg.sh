#!/usr/bin/env bash
# Builds a universal build/Sidekick.dmg with a drag-to-Applications layout.
# Optional: SIGN_IDENTITY="Developer ID Application: ..." to sign, and
# NOTARY_PROFILE=<notarytool keychain profile> (or APPLE_ID, APPLE_TEAM_ID and
# APPLE_APP_PASSWORD) to notarize and staple.
set -euo pipefail
cd "$(dirname "$0")/.."

UNIVERSAL=1 ./Scripts/build-app.sh

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
DMG="build/Sidekick-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R build/Sidekick.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname Sidekick -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi
NOTARY_AUTH=()
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "${SIGN_IDENTITY:-}" && -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
  NOTARY_AUTH=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
fi
if (( ${#NOTARY_AUTH[@]} )); then
  xcrun notarytool submit "$DMG" "${NOTARY_AUTH[@]}" --wait
  xcrun stapler staple "$DMG"
fi
echo "Built $DMG"
