#!/bin/zsh
set -euo pipefail

root_dir="${0:A:h:h}"
cd "$root_dir"

arch="$(uname -m)"
APP_ARCHS="$arch" ./scripts/build-app.sh

test_dir="$(mktemp -d)"
dmg="$test_dir/CPA-Usage-test-$arch.dmg"
mount_dir="$test_dir/mount"
mkdir -p "$mount_dir"

cleanup() {
    hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
    rm -rf "$test_dir"
}
trap cleanup EXIT

APP_PATH="$root_dir/dist/CPA Usage.app" \
OUTPUT_DMG="$dmg" \
VOLUME_NAME="CPA Usage Test" \
./scripts/package-dmg.sh

[[ -f "$dmg" ]]
hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$dmg" >/dev/null
[[ -d "$mount_dir/CPA Usage.app" ]]
[[ -L "$mount_dir/Applications" ]]
[[ "$(readlink "$mount_dir/Applications")" == "/Applications" ]]
[[ -f "$mount_dir/.VolumeIcon.icns" ]]
cmp "$mount_dir/.VolumeIcon.icns" "$mount_dir/CPA Usage.app/Contents/Resources/AppIcon.icns"
volume_attributes="$(GetFileInfo -a "$mount_dir")"
[[ "$volume_attributes" == *C* ]]

binary="$mount_dir/CPA Usage.app/Contents/MacOS/CPAUsageMenuBar"
[[ "$(lipo -archs "$binary")" == "$arch" ]]
[[ "$(plutil -extract CFBundleIdentifier raw "$mount_dir/CPA Usage.app/Contents/Info.plist")" == "cn.winlio.cpausage" ]]
codesign --verify --deep --strict --verbose=2 "$mount_dir/CPA Usage.app"
