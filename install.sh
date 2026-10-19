#!/bin/bash
# Installs VGAGlitch and VGAGlitch2 from the latest GitHub release:
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
install_app VGAGlitch2 local.vgaglitch2

echo
echo "Fertig: VGAGlitch und VGAGlitch2 liegen in $DEST."
echo "Starten: open -a VGAGlitch2   (oder per Launchpad / Spotlight)"
