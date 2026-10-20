#!/bin/bash
# Installs VGAGlitch from the latest GitHub release:
#   curl -fsSL https://raw.githubusercontent.com/deaddls/newPresenter/main/install.sh | bash
set -euo pipefail

REPO=deaddls/newPresenter
DEST=${VGAGLITCH_DEST:-/Applications}
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

install_app() {   # <name> <bundle id>
    local name=$1 id=$2
    echo "Lade $name …"
    curl -fsSL "https://github.com/$REPO/releases/latest/download/$name.zip" -o "$TMP/$name.zip"
    if [ -e "$DEST/$name.app" ]; then
        pkill -x "$name" 2>/dev/null || true
        rm -rf "$DEST/$name.app"
        # A new build has a new ad-hoc signature, macOS would silently ignore the old permission.
        tccutil reset ScreenCapture "$id" >/dev/null 2>&1 || true
    fi
    ditto -x -k "$TMP/$name.zip" "$DEST"
    # curl sets no quarantine flag, but clear it anyway so Gatekeeper never blocks the first start.
    xattr -dr com.apple.quarantine "$DEST/$name.app" 2>/dev/null || true
}

install_app VGAGlitch local.vgaglitch

# VGAGlitch2 was merged into VGAGlitch; the old copy would grab the same hotkey.
if [ -e "$DEST/VGAGlitch2.app" ]; then
    pkill -x VGAGlitch2 2>/dev/null || true
    rm -rf "$DEST/VGAGlitch2.app"
    echo "Altes VGAGlitch2 entfernt (steckt jetzt in VGAGlitch)."
fi

echo
echo "Fertig: VGAGlitch liegt in $DEST."
echo "Starten: open -a VGAGlitch   (oder per Launchpad / Spotlight)"
