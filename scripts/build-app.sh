#!/bin/sh
# Builds dist/Rowboat.app from the SwiftPM release binary and ad-hoc signs it.
# Usage: scripts/build-app.sh [--sign "Developer ID Application: ..."]
set -eu
cd "$(dirname "$0")/.."
SIGN="-"
if [ "${1:-}" = "--sign" ]; then SIGN="$2"; fi

VERSION=$(cat VERSION 2>/dev/null || echo 0.1.0)
swift build -c release 2>&1 | grep -E "error|warning: var|Compiling|Build complete" | grep -v '^\[' || true
BIN=$(swift build -c release --show-bin-path)/Rowboat
test -x "$BIN"

APP=dist/Rowboat.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Rowboat"
sed "s/__VERSION__/$VERSION/" scripts/Info.plist > "$APP/Contents/Info.plist"
if [ -f scripts/AppIcon.icns ]; then cp scripts/AppIcon.icns "$APP/Contents/Resources/"; fi
codesign --force --sign "$SIGN" --options runtime --entitlements scripts/Rowboat.entitlements "$APP" 2>/dev/null \
  || codesign --force --sign "$SIGN" "$APP"
echo "built $APP ($VERSION), signed with: $SIGN"
