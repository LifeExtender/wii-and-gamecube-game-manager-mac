#!/bin/sh
# Builds the self-contained, universal app and zips it for distribution.
set -eu

cd "$(dirname "$0")/.."
[ -x Helpers/wit ] && [ -x Helpers/wwt ] || scripts/fetch-tools.sh

xcodegen generate --quiet
xcodebuild -project WiiGameManager.xcodeproj -scheme WiiGameManager -configuration Release \
    -derivedDataPath build -destination 'generic/platform=macOS' \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= -quiet build

mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent \
    "build/Build/Products/Release/Wii and GameCube Game Manager.app" "dist/Wii-and-GameCube-Game-Manager.zip"
echo "Built dist/Wii-and-GameCube-Game-Manager.zip"
