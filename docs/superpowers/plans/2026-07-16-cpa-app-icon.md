# CPA App and DMG Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reuse the CPA Usage Keeper icon as a reproducible macOS `AppIcon.icns` and apply it to the CPA Usage app bundle and mounted DMG volume.

**Architecture:** Store the pinned upstream PNG and attribution in `Resources/AppIcon`, generate and commit a standard ICNS with a focused system-tool script, copy the ICNS into every app build, and let the DMG packager reuse it as `.VolumeIcon.icns`. Shell regression tests verify the plist declaration, app resource, ICNS structure, and mounted DMG contents.

**Tech Stack:** zsh, `curl`, `sips`, `iconutil`, `SetFile`, Swift Package Manager, `hdiutil`, macOS bundle metadata, GitHub Actions.

## Global Constraints

- Reuse the approved icon from `Willxup/cpa-usage-keeper` commit `e40cdad46c5b72c55b098f4a343a45cf783faa6e`.
- The upstream source path is `web/src/assets/cli-proxy-api-favicon.png` and its SHA-256 is `8e0eb56b647e20b27efc315acc1300ac85ac880a1b80fd86c9f259acc57ee925`.
- The upstream repository uses the MIT License.
- Builds must not download the icon from the network.
- `CFBundleIconFile` must equal `AppIcon.icns`.
- The app icon must be present at `Contents/Resources/AppIcon.icns` before signing.
- The mounted DMG volume must contain `.VolumeIcon.icns` and retain the `/Applications` symbolic link.
- Existing Developer ID signing, notarization, staple, Gatekeeper, bundle identifier, and dual-architecture behavior must remain unchanged.
- Do not create a public version tag without separate user approval.

---

### Task 1: Define the app and DMG icon contract

**Files:**
- Modify: `scripts/test-build-app.sh`
- Modify: `scripts/test-package-dmg.sh`
- Test: `scripts/test-build-app.sh`
- Test: `scripts/test-package-dmg.sh`

**Interfaces:**
- Consumes: a built `dist/CPA Usage.app` and a mounted test DMG.
- Produces: failing assertions for `CFBundleIconFile`, the bundled ICNS, a valid iconset conversion, and `.VolumeIcon.icns` inside the mounted DMG.

- [ ] **Step 1: Add failing app-icon assertions**

Append to `scripts/test-build-app.sh` before the final code-signature check:

```zsh
icon_name="$(plutil -extract CFBundleIconFile raw 'dist/CPA Usage.app/Contents/Info.plist')"
[[ "$icon_name" == "AppIcon.icns" ]]

app_icon="dist/CPA Usage.app/Contents/Resources/AppIcon.icns"
[[ -f "$app_icon" ]]

icon_test_dir="$(mktemp -d)"
cleanup_icon_test() { rm -rf "$icon_test_dir" }
trap cleanup_icon_test EXIT
iconutil -c iconset "$app_icon" -o "$icon_test_dir/AppIcon.iconset"
[[ -f "$icon_test_dir/AppIcon.iconset/icon_512x512@2x.png" ]]
```

- [ ] **Step 2: Add failing mounted-volume assertions**

Append to `scripts/test-package-dmg.sh` after the `/Applications` link checks:

```zsh
[[ -f "$mount_dir/.VolumeIcon.icns" ]]
cmp "$mount_dir/.VolumeIcon.icns" "$mount_dir/CPA Usage.app/Contents/Resources/AppIcon.icns"
```

- [ ] **Step 3: Run both tests and verify they fail for the missing icon**

Run:

```bash
./scripts/test-build-app.sh
./scripts/test-package-dmg.sh
```

Expected: both commands exit non-zero because `CFBundleIconFile`, `AppIcon.icns`, and `.VolumeIcon.icns` do not exist yet.

- [ ] **Step 4: Commit the failing contract**

```bash
git add scripts/test-build-app.sh scripts/test-package-dmg.sh
git commit -m "test: define CPA app and DMG icon contract"
```

### Task 2: Pin the upstream source and generate the macOS ICNS

**Files:**
- Create: `Resources/AppIcon/cpa-usage-keeper.png`
- Create: `Resources/AppIcon/AppIcon.icns`
- Create: `Resources/AppIcon/SOURCE.md`
- Create: `scripts/generate-app-icon.sh`
- Test: `scripts/generate-app-icon.sh`

**Interfaces:**
- Consumes: `SOURCE_ICON` and `OUTPUT_ICNS`, defaulting to the pinned files under `Resources/AppIcon`.
- Produces: a center-cropped square macOS ICNS with 16, 32, 128, 256, 512, and 1024 pixel representations.

- [ ] **Step 1: Download the exact approved upstream PNG**

```bash
mkdir -p Resources/AppIcon
curl -fsSL \
  'https://raw.githubusercontent.com/Willxup/cpa-usage-keeper/e40cdad46c5b72c55b098f4a343a45cf783faa6e/web/src/assets/cli-proxy-api-favicon.png' \
  -o Resources/AppIcon/cpa-usage-keeper.png
echo '8e0eb56b647e20b27efc315acc1300ac85ac880a1b80fd86c9f259acc57ee925  Resources/AppIcon/cpa-usage-keeper.png' | shasum -a 256 -c -
```

Expected: checksum output ends with `OK`.

- [ ] **Step 2: Record source attribution**

Create `Resources/AppIcon/SOURCE.md`:

```markdown
# CPA Usage Icon Source

- Repository: https://github.com/Willxup/cpa-usage-keeper
- Commit: `e40cdad46c5b72c55b098f4a343a45cf783faa6e`
- Source path: `web/src/assets/cli-proxy-api-favicon.png`
- License: MIT License
- Source SHA-256: `8e0eb56b647e20b27efc315acc1300ac85ac880a1b80fd86c9f259acc57ee925`

The original 825×677 image is center-cropped to a square before generating
the macOS icon representations. It is not stretched.
```

- [ ] **Step 3: Implement the icon-generation script**

Create `scripts/generate-app-icon.sh`:

```zsh
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
```

Make it executable:

```bash
chmod +x scripts/generate-app-icon.sh
```

- [ ] **Step 4: Generate and validate the committed ICNS**

```bash
./scripts/generate-app-icon.sh
test_dir="$(mktemp -d)"
iconutil -c iconset Resources/AppIcon/AppIcon.icns -o "$test_dir/AppIcon.iconset"
test -f "$test_dir/AppIcon.iconset/icon_512x512@2x.png"
```

Expected: `AppIcon.icns` is created and converts back to a complete iconset.

- [ ] **Step 5: Commit the source, attribution, generator, and ICNS**

```bash
git add Resources/AppIcon scripts/generate-app-icon.sh
git commit -m "assets: add CPA macOS application icon"
```

### Task 3: Integrate the icon into the app bundle

**Files:**
- Modify: `Resources/Info.plist`
- Modify: `scripts/build-app.sh`
- Test: `scripts/test-build-app.sh`

**Interfaces:**
- Consumes: `Resources/AppIcon/AppIcon.icns`.
- Produces: every assembled app bundle with `CFBundleIconFile=AppIcon.icns` and a matching resource under `Contents/Resources`.

- [ ] **Step 1: Declare the icon in `Info.plist`**

Add after `CFBundleIdentifier`:

```xml
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
```

- [ ] **Step 2: Copy the icon before signing**

In `scripts/build-app.sh`, define and validate the resource near `app_dir`:

```zsh
icon="$root_dir/Resources/AppIcon/AppIcon.icns"
if [[ ! -f "$icon" ]]; then
    print -u2 "Application icon not found: $icon"
    exit 1
fi
```

After copying `Info.plist`, add:

```zsh
cp "$icon" "$app_dir/Contents/Resources/AppIcon.icns"
```

- [ ] **Step 3: Run the app build test and verify it passes**

```bash
./scripts/test-build-app.sh
```

Expected: exit 0; plist, ICNS structure, Universal architecture, and signature checks all pass.

- [ ] **Step 4: Commit the app integration**

```bash
git add Resources/Info.plist scripts/build-app.sh scripts/test-build-app.sh
git commit -m "build: bundle CPA application icon"
```

### Task 4: Integrate the icon into the mounted DMG volume

**Files:**
- Modify: `scripts/package-dmg.sh`
- Test: `scripts/test-package-dmg.sh`

**Interfaces:**
- Consumes: optional `VOLUME_ICON`, defaulting to `Resources/AppIcon/AppIcon.icns`.
- Produces: a DMG staging root with `.VolumeIcon.icns`, Finder custom-icon metadata, the app, and `/Applications` link.

- [ ] **Step 1: Validate and install the DMG volume icon**

Near the existing packaging variables in `scripts/package-dmg.sh`, add:

```zsh
volume_icon="${VOLUME_ICON:-$root_dir/Resources/AppIcon/AppIcon.icns}"
```

After validating `app_path`, add:

```zsh
if [[ ! -f "$volume_icon" ]]; then
    print -u2 "Volume icon not found: $volume_icon"
    exit 1
fi
```

After copying the app into the staging directory, add:

```zsh
cp "$volume_icon" "$staging_dir/.VolumeIcon.icns"
SetFile -a C "$staging_dir"
```

- [ ] **Step 2: Run the mounted-DMG test and verify it passes**

```bash
./scripts/test-package-dmg.sh
```

Expected: exit 0; `.VolumeIcon.icns` exists, matches the app ICNS, and the existing app, architecture, bundle ID, signature, and `/Applications` link checks pass.

- [ ] **Step 3: Commit the DMG integration**

```bash
git add scripts/package-dmg.sh scripts/test-package-dmg.sh
git commit -m "build: add CPA icon to DMG volume"
```

### Task 5: Run full local and GitHub verification

**Files:**
- Verify: `Resources/AppIcon/AppIcon.icns`
- Verify: `Resources/Info.plist`
- Verify: `scripts/generate-app-icon.sh`
- Verify: `scripts/build-app.sh`
- Verify: `scripts/package-dmg.sh`
- Verify: `scripts/test-build-app.sh`
- Verify: `scripts/test-package-dmg.sh`
- Verify: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: all icon implementation commits.
- Produces: local verification and two signed/notarized CI DMGs containing the icon without creating a public Release.

- [ ] **Step 1: Run all local verification commands**

```bash
swift test
./scripts/generate-app-icon.sh
./scripts/test-build-app.sh
./scripts/test-package-dmg.sh
./scripts/test-release-workflow.sh
git diff --check
```

Expected: every command exits 0.

- [ ] **Step 2: Push the implementation to remote `main` through SSH**

```bash
git push git@github.com:liuzelei/cpa-usage-menu-bar.git HEAD:main
```

Expected: remote `main` advances to the icon integration commit.

- [ ] **Step 3: Trigger the manual dual-DMG workflow**

```bash
gh workflow run release.yml \
  --repo liuzelei/cpa-usage-menu-bar \
  --ref main \
  -f version=1.0.2
```

Expected: a workflow run starts; no public GitHub Release is created.

- [ ] **Step 4: Watch and download both artifacts**

```bash
head_sha="$(git rev-parse HEAD)"
run_id="$(gh run list \
  --repo liuzelei/cpa-usage-menu-bar \
  --workflow release.yml \
  --event workflow_dispatch \
  --limit 10 \
  --json databaseId,headSha \
  --jq ".[] | select(.headSha == \"$head_sha\") | .databaseId" | head -1)"
test -n "$run_id"
gh run watch "$run_id" --repo liuzelei/cpa-usage-menu-bar --exit-status
verification_dir="$(mktemp -d)"
gh run download "$run_id" --repo liuzelei/cpa-usage-menu-bar --dir "$verification_dir"
```

Expected: tests, both architecture jobs, signing, DMG signing, notarization, staple, Gatekeeper, and uploads succeed.

- [ ] **Step 5: Mount both DMGs and verify icon resources**

```zsh
for arch in arm64 x86_64; do
    artifact_dir="$verification_dir/CPA-Usage-1.0.2-$arch"
    dmg="$artifact_dir/CPA-Usage-1.0.2-$arch.dmg"
    (cd "$artifact_dir" && shasum -a 256 -c "${dmg:t}.sha256")
    codesign --verify --verbose=2 "$dmg"
    xcrun stapler validate "$dmg"

    assessment="$(spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg" 2>&1)"
    print -r -- "$assessment" | grep -q ': accepted$'

    mount_dir="$(mktemp -d)"
    hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$dmg" >/dev/null
    app="$mount_dir/CPA Usage.app"
    [[ "$(lipo -archs "$app/Contents/MacOS/CPAUsageMenuBar")" == "$arch" ]]
    [[ "$(plutil -extract CFBundleIconFile raw "$app/Contents/Info.plist")" == "AppIcon.icns" ]]
    [[ -f "$app/Contents/Resources/AppIcon.icns" ]]
    [[ -f "$mount_dir/.VolumeIcon.icns" ]]
    cmp "$mount_dir/.VolumeIcon.icns" "$app/Contents/Resources/AppIcon.icns"

    preview_dir="$(mktemp -d)"
    iconutil -c iconset "$app/Contents/Resources/AppIcon.icns" -o "$preview_dir/AppIcon.iconset"
    [[ -f "$preview_dir/AppIcon.iconset/icon_512x512@2x.png" ]]
    hdiutil detach "$mount_dir" >/dev/null
done
```

Expected: both DMGs pass all checks, and the generated
`icon_512x512@2x.png` is available for visual inspection.

- [ ] **Step 6: Report results without creating a tag**

Report the manual run URL and verification evidence. Ask for separate approval before creating the next public version tag.
