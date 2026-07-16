#!/bin/zsh
set -euo pipefail

root_dir="${0:A:h:h}"
app_path="${APP_PATH:-$root_dir/dist/CPA Usage.app}"
output_dmg="${OUTPUT_DMG:-$root_dir/dist/CPA-Usage.dmg}"
volume_name="${VOLUME_NAME:-CPA Usage}"
volume_icon="${VOLUME_ICON:-$root_dir/Resources/AppIcon/AppIcon.icns}"

if [[ ! -d "$app_path" ]]; then
    print -u2 "Application bundle not found: $app_path"
    exit 1
fi

if [[ ! -f "$volume_icon" ]]; then
    print -u2 "Volume icon not found: $volume_icon"
    exit 1
fi

mkdir -p "${output_dmg:h}"
staging_dir="$(mktemp -d)"

cleanup() {
    rm -rf "$staging_dir"
}
trap cleanup EXIT

ditto "$app_path" "$staging_dir/${app_path:t}"
cp "$volume_icon" "$staging_dir/.VolumeIcon.icns"
SetFile -a C "$staging_dir"
ln -s /Applications "$staging_dir/Applications"
rm -f "$output_dmg"
hdiutil create \
    -volname "$volume_name" \
    -srcfolder "$staging_dir" \
    -ov \
    -format UDZO \
    "$output_dmg"

print "Created $output_dmg"
