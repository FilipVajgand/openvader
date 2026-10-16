#!/bin/sh
# Builds OpenVader.app into ./build. Usage: scripts/build-app.sh [debug|release]
set -eu
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
VERSION="$(sed -n 's/.*string = "\(.*\)"/\1/p' Sources/VaderKit/Device/DeviceBackup.swift)"

swift build -c "$CONFIG" --product OpenVader
swift build -c "$CONFIG" --product vaderctl
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

APP=build/OpenVader.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/OpenVader" "$APP/Contents/MacOS/OpenVader"
cp "$BIN/vaderctl" build/vaderctl

if [ ! -f build/AppIcon.icns ]; then
    rm -rf build/AppIcon.iconset
    swift scripts/make-icon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$APP"
echo "Built $APP ($VERSION) and build/vaderctl"
