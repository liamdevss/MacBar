#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swift build --disable-sandbox -c release
BIN_DIR="$(swift build --disable-sandbox -c release --show-bin-path)"
APP="$PWD/build/MacBar.app"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp Sources/MacBar/Assets/DefaultBackground.jpg "$APP/Contents/Resources/DefaultBackground.jpg"
cp Sources/MacBar/Assets/ProfilePhoto.jpg "$APP/Contents/Resources/ProfilePhoto.jpg"
cp "$BIN_DIR/MacBar" "$APP/Contents/MacOS/MacBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
printf 'Built %s\n' "$APP"
