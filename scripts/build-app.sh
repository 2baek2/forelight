#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT_DIR/.build/Forelight.app"
EXECUTABLE="$ROOT_DIR/.build/out/Products/Debug/Forelight"
SIGNING_IDENTITY="${FORELIGHT_SIGNING_IDENTITY:-Local Self-Signed}"

if ! security find-identity -v -p codesigning | grep -Fq "\"$SIGNING_IDENTITY\""; then
    echo "Signing identity not found: $SIGNING_IDENTITY" >&2
    echo "Set FORELIGHT_SIGNING_IDENTITY to an installed signing identity." >&2
    exit 1
fi

swift build --package-path "$ROOT_DIR"

mkdir -p "$APP_PATH/Contents/MacOS"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$EXECUTABLE" "$APP_PATH/Contents/MacOS/Forelight"

codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

echo "Built and signed $APP_PATH"
echo "Signing identity: $SIGNING_IDENTITY"

# Replace any running instance so the rebuilt binary is what actually launches.
if pgrep -x Forelight >/dev/null; then
    osascript -e 'tell application "Forelight" to quit' >/dev/null 2>&1 || pkill -x Forelight 2>/dev/null || true
    for _ in {1..20}; do
        pgrep -x Forelight >/dev/null || break
        sleep 0.1
    done
    pkill -x Forelight 2>/dev/null || true
fi

open "$APP_PATH"
