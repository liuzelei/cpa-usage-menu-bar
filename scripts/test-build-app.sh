#!/bin/zsh
set -euo pipefail

root_dir="${0:A:h:h}"
cd "$root_dir"

APP_ARCHS="arm64 x86_64" ./scripts/build-app.sh

binary="dist/CPA Usage.app/Contents/MacOS/CPAUsageMenuBar"
archs="$(lipo -archs "$binary")"

[[ " $archs " == *" arm64 "* ]]
[[ " $archs " == *" x86_64 "* ]]

bundle_id="$(plutil -extract CFBundleIdentifier raw 'dist/CPA Usage.app/Contents/Info.plist')"
[[ "$bundle_id" == "cn.winlio.cpausage" ]]

codesign --verify --deep --strict --verbose=2 "dist/CPA Usage.app"
