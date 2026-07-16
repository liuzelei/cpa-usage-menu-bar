#!/bin/zsh
set -euo pipefail

root_dir="${0:A:h:h}"
cd "$root_dir"

swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
app_dir="$root_dir/dist/CPA Usage.app"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/CPAUsageMenuBar" "$app_dir/Contents/MacOS/CPAUsageMenuBar"
cp "$root_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$app_dir"
fi

print "Built $app_dir"
