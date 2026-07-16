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

icon_name="$(plutil -extract CFBundleIconFile raw 'dist/CPA Usage.app/Contents/Info.plist')"
[[ "$icon_name" == "AppIcon.icns" ]]

app_icon="dist/CPA Usage.app/Contents/Resources/AppIcon.icns"
[[ -f "$app_icon" ]]

icon_test_dir="$(mktemp -d)"
cleanup_icon_test() { rm -rf "$icon_test_dir" }
trap cleanup_icon_test EXIT
iconutil -c iconset "$app_icon" -o "$icon_test_dir/AppIcon.iconset"
[[ -f "$icon_test_dir/AppIcon.iconset/icon_512x512@2x.png" ]]

codesign --verify --deep --strict --verbose=2 "dist/CPA Usage.app"
