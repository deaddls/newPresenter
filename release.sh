#!/bin/bash
# Builds both apps and publishes them as a new GitHub release: ./release.sh 1.1
# install.sh and the download links always fetch the latest release.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=${1:?Version angeben, z. B. ./release.sh 1.1}
./build.sh
mkdir -p build/dist
for app in VGAGlitch VGAGlitch2; do
    rm -f "build/dist/$app.zip"
    ditto -c -k --keepParent "build/$app.app" "build/dist/$app.zip"
done
gh release create "v$VERSION" build/dist/VGAGlitch.zip build/dist/VGAGlitch2.zip \
    --title "VGAGlitch $VERSION" \
    --notes "Installieren: \`curl -fsSL https://raw.githubusercontent.com/deaddls/newPresenter/main/install.sh | bash\` – oder die zip laden, entpacken und nach Programme ziehen (siehe README)."
