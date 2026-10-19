#!/bin/bash
# Builds build/VGAGlitch.app and build/VGAGlitch2.app (glitches plus the Bargeld poll).
# Optional: SIGN_IDENTITY="Apple Development: …" ./build.sh
# (a stable signature keeps the screen recording permission across rebuilds).
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build/module-cache

# build_app <name> <bundle id> [swiftc flags …]
build_app() {
    local name=$1 id=$2
    shift 2
    local app=build/$name.app
    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp Info.plist "$app/Contents/Info.plist"
    for key in CFBundleExecutable CFBundleName CFBundleDisplayName; do
        plutil -replace "$key" -string "$name" "$app/Contents/Info.plist"
    done
    plutil -replace CFBundleIdentifier -string "$id" "$app/Contents/Info.plist"

    # Universal binary, so the app runs natively on Intel and Apple Silicon.
    for arch in x86_64 arm64; do
        swiftc -O -swift-version 5 \
            -target "$arch-apple-macos13.0" \
            -module-cache-path build/module-cache \
            "$@" \
            Sources/*.swift \
            -o "build/$name-$arch"
    done
    lipo -create "build/$name-x86_64" "build/$name-arm64" -output "$app/Contents/MacOS/$name"
    rm "build/$name-x86_64" "build/$name-arm64"
}

build_app VGAGlitch local.vgaglitch
build_app VGAGlitch2 local.vgaglitch2 -D VGAGLITCH2
cp Resources/stuetzle.png build/VGAGlitch2.app/Contents/Resources/

for app in build/VGAGlitch.app build/VGAGlitch2.app; do
    codesign --force --sign "${SIGN_IDENTITY:--}" "$app"
done
echo "Fertig: build/VGAGlitch.app, build/VGAGlitch2.app"
