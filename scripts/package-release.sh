#!/bin/sh
# Builds a universal OpenVader.app and vaderctl and zips them into ./dist for a GitHub release.
set -eu
cd "$(dirname "$0")/.."
VERSION="$(sed -n 's/.*string = "\(.*\)"/\1/p' Sources/VaderKit/Device/DeviceBackup.swift)"
UNIVERSAL=1 scripts/build-app.sh release
rm -rf dist
mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent build/OpenVader.app "dist/OpenVader-$VERSION.zip"
(cd build && ditto -c -k vaderctl "../dist/vaderctl-$VERSION.zip")
(cd dist && shasum -a 256 ./*.zip > SHA256SUMS.txt)
ls -l dist
