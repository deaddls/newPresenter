#!/bin/bash
# Builds build/VGAGlitch.app. Optional: SIGN_IDENTITY="Apple Development: …" ./build.sh
# (a stable signature keeps the screen recording permission across rebuilds).
set -euo pipefail
cd "$(dirname "$0")"

APP=build/VGAGlitch.app
ARCH=$(uname -m)
mkdir -p build/module-cache
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"

swiftc -O -swift-version 5 \
    -target "$ARCH-apple-macos13.0" \
    -module-cache-path build/module-cache \
    Sources/*.swift \
    -o "$APP/Contents/MacOS/VGAGlitch"

codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Fertig: $APP"
