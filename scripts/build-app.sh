#!/bin/zsh
set -euo pipefail

root_dir="${0:A:h:h}"
cd "$root_dir"

arch_list="${APP_ARCHS:-$(uname -m)}"
archs=(${=arch_list})

if (( ${#archs} == 0 )); then
    print -u2 "APP_ARCHS must contain at least one architecture"
    exit 1
fi

app_dir="$root_dir/dist/CPA Usage.app"
executable="$app_dir/Contents/MacOS/CPAUsageMenuBar"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"

binaries=()
for arch in "${archs[@]}"; do
    triple="${arch}-apple-macosx13.0"
    swift build -c release --triple "$triple"
    bin_dir="$(swift build -c release --triple "$triple" --show-bin-path)"
    binaries+=("$bin_dir/CPAUsageMenuBar")
done

if (( ${#binaries} == 1 )); then
    cp "${binaries[1]}" "$executable"
else
    lipo -create "${binaries[@]}" -output "$executable"
fi

cp "$root_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$app_dir"
fi

print "Built $app_dir for: $(lipo -archs "$executable")"
