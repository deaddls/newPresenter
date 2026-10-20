#!/bin/bash
# Builds the app and publishes it as a new GitHub release: ./release.sh 1.1
# install.sh and the download links always fetch the latest release.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=${1:?Version angeben, z. B. ./release.sh 1.1}
./build.sh
mkdir -p build/dist
rm -f build/dist/VGAGlitch.zip
ditto -c -k --keepParent build/VGAGlitch.app build/dist/VGAGlitch.zip
gh release create "v$VERSION" build/dist/VGAGlitch.zip \
    --title "VGAGlitch $VERSION" \
    --notes "Installieren: \`curl -fsSL https://raw.githubusercontent.com/deaddls/newPresenter/main/install.sh | bash\` – oder VGAGlitch.zip laden, entpacken und nach Programme ziehen (siehe README)."
