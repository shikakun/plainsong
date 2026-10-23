#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCHEME="${SCHEME:-plainsong}"
CONFIGURATION="${CONFIGURATION:-Release}"
ARCHIVE_PATH="${ARCHIVE_PATH:-build/plainsong.xcarchive}"
APP_PATH="${APP_PATH:-build/Release/Plainsong.app}"
DMG_PATH="${DMG_PATH:-build/plainsong.dmg}"
STAGING_DIR="${STAGING_DIR:-build/dmg-staging}"

echo "==> Generating Xcode project"
mise run macos:generate

echo "==> Building ${SCHEME} (${CONFIGURATION})"
xcodebuild \
  -scheme "$SCHEME" \
  -project plainsong.xcodeproj \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}" \
  CONFIGURATION_BUILD_DIR="$ROOT/build/$CONFIGURATION" \
  build

mkdir -p "$(dirname "$APP_PATH")"
if [[ ! -d "$APP_PATH" ]]; then
  APP_PATH="$ROOT/build/$CONFIGURATION/Plainsong.app"
fi

if [[ "${CODE_SIGNING_ALLOWED:-NO}" == "YES" ]]; then
  echo "==> Signing (requires Developer ID certificate in keychain)"
  codesign --force --deep --options runtime --sign "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY}" "$APP_PATH"

  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "==> Notarizing"
    ditto -c -k --keepParent "$APP_PATH" build/plainsong-notarize.zip
    xcrun notarytool submit build/plainsong-notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP_PATH"
  fi
fi

echo "==> Creating DMG"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname Plainsong -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

echo "==> Done: $DMG_PATH"
