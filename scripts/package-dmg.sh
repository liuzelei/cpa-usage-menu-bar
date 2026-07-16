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
work_dir="$(mktemp -d)"
staging_dir="$work_dir/staging"
mount_dir="$work_dir/mount"
read_write_dmg="$work_dir/CPA-Usage-read-write.dmg"
mounted=0
mkdir -p "$staging_dir" "$mount_dir"

cleanup() {
    if (( mounted )); then
        hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
    fi
    rm -rf "$work_dir"
}
trap cleanup EXIT

ditto "$app_path" "$staging_dir/${app_path:t}"
cp "$volume_icon" "$staging_dir/.VolumeIcon.icns"
ln -s /Applications "$staging_dir/Applications"
rm -f "$output_dmg"
hdiutil create \
    -volname "$volume_name" \
    -srcfolder "$staging_dir" \
    -ov \
    -format UDRW \
    "$read_write_dmg"

hdiutil attach -readwrite -nobrowse -mountpoint "$mount_dir" "$read_write_dmg" >/dev/null
mounted=1
SetFile -a C "$mount_dir"
hdiutil detach "$mount_dir" >/dev/null
mounted=0

hdiutil convert "$read_write_dmg" -format UDZO -o "$output_dmg" >/dev/null

print "Created $output_dmg"
