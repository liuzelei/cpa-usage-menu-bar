#!/bin/zsh
set -euo pipefail

root_dir="${0:A:h:h}"
source_icon="${SOURCE_ICON:-$root_dir/Resources/AppIcon/cpa-usage-keeper.png}"
output_icns="${OUTPUT_ICNS:-$root_dir/Resources/AppIcon/AppIcon.icns}"

if [[ ! -f "$source_icon" ]]; then
    print -u2 "Source icon not found: $source_icon"
    exit 1
fi

width="$(sips -g pixelWidth "$source_icon" | awk '/pixelWidth/ {print $2}')"
height="$(sips -g pixelHeight "$source_icon" | awk '/pixelHeight/ {print $2}')"
if [[ -z "$width" || -z "$height" || "$width" -le 0 || "$height" -le 0 ]]; then
    print -u2 "Invalid source icon dimensions"
    exit 1
fi

side="$width"
if (( height < width )); then side="$height"; fi

work_dir="$(mktemp -d)"
iconset="$work_dir/AppIcon.iconset"
square="$work_dir/square.png"
mkdir -p "$iconset" "${output_icns:h}"

cleanup() { rm -rf "$work_dir" }
trap cleanup EXIT

sips --cropToHeightWidth "$side" "$side" "$source_icon" --out "$square" >/dev/null

for spec in \
    '16 icon_16x16.png' \
    '32 icon_16x16@2x.png' \
    '32 icon_32x32.png' \
    '64 icon_32x32@2x.png' \
    '128 icon_128x128.png' \
    '256 icon_128x128@2x.png' \
    '256 icon_256x256.png' \
    '512 icon_256x256@2x.png' \
    '512 icon_512x512.png' \
    '1024 icon_512x512@2x.png'; do
    parts=(${=spec})
    sips -z "${parts[1]}" "${parts[1]}" "$square" --out "$iconset/${parts[2]}" >/dev/null
done

rm -f "$output_icns"
iconutil -c icns "$iconset" -o "$output_icns"
print "Generated $output_icns"
