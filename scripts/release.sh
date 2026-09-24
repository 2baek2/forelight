#!/bin/zsh
# Builds a distributable Forelight.app plus a DMG and a zip.
#
# Without an Apple Developer ID the app cannot be notarized, so it is signed
# ad-hoc (or with FORELIGHT_SIGNING_IDENTITY when provided). Users install it by
# clearing the quarantine flag or using "Open" from the context menu.
#
# Usage:
#   ./scripts/release.sh [version]
#
#   FORELIGHT_SIGNING_IDENTITY="Developer ID Application: ..." ./scripts/release.sh 0.2.0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Forelight"
APP_PATH="$ROOT_DIR/.build/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/dist"

if [[ -n "${1:-}" ]]; then
    VERSION="$1"
else
    VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT_DIR/Resources/Info.plist")"
fi

echo "Building $APP_NAME $VERSION (release)…"
swift build --package-path "$ROOT_DIR" -c release
BIN_PATH="$(swift build --package-path "$ROOT_DIR" -c release --show-bin-path)"
EXECUTABLE="$BIN_PATH/$APP_NAME"

if [[ ! -x "$EXECUTABLE" ]]; then
    echo "Release binary not found at $EXECUTABLE" >&2
    exit 1
fi

echo "Assembling $APP_PATH…"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
cp "$EXECUTABLE" "$APP_PATH/Contents/MacOS/$APP_NAME"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP_PATH/Contents/Info.plist"

DEFAULT_IDENTITY="Local Self-Signed"
IDENTITY="${FORELIGHT_SIGNING_IDENTITY:-$DEFAULT_IDENTITY}"
AVAILABLE_IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"

if [[ -n "$IDENTITY" ]] && [[ "$AVAILABLE_IDENTITIES" == *"\"$IDENTITY\""* ]]; then
    echo "Signing with: $IDENTITY"
    codesign --force --sign "$IDENTITY" "$APP_PATH"
else
    echo "Signing identity \"$IDENTITY\" not found; signing ad-hoc."
    echo "Tip: a stable certificate keeps the Accessibility grant across updates."
    codesign --force --sign - "$APP_PATH"
fi
codesign --verify --strict "$APP_PATH"

mkdir -p "$DIST_DIR"
STAGE="$(mktemp -d)"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"
ZIP="$DIST_DIR/$APP_NAME-$VERSION.zip"
rm -f "$DMG" "$ZIP"
echo "Creating $DMG…"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "Creating $ZIP…"
ditto -c -k --keepParent "$APP_PATH" "$ZIP"
rm -rf "$STAGE"

echo
echo "Built:"
echo "  $DMG"
echo "  $ZIP"
echo
echo "Install (no Developer ID, so Gatekeeper will warn on first launch):"
echo "  1. Open the DMG and drag $APP_NAME to Applications."
echo "  2. Right-click the app and choose Open, then Open again."
echo "     Or run: xattr -dr com.apple.quarantine /Applications/$APP_NAME.app"
echo "  3. Grant Accessibility permission when Forelight asks."
