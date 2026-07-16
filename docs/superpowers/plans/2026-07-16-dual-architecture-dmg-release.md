# Dual-Architecture DMG Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Universal ZIP release with independently built, signed, notarized, and checksummed `arm64` and `x86_64` DMG assets.

**Architecture:** A focused packaging script creates a drag-to-install DMG from one signed app. GitHub Actions runs tests once, executes two architecture-specific packaging jobs through a matrix, then uses one aggregate job to create the GitHub Release after both DMGs pass validation.

**Tech Stack:** Swift Package Manager, zsh, `hdiutil`, `codesign`, `notarytool`, `stapler`, `spctl`, GitHub Actions matrix jobs, GitHub CLI.

## Global Constraints

- The deployment target remains macOS 13.0.
- The bundle identifier remains exactly `cn.winlio.cpausage`.
- The `arm64` DMG contains only an `arm64` executable.
- The `x86_64` DMG contains only an `x86_64` executable.
- The Universal ZIP and its checksum are removed from future releases.
- Existing Apple secrets and certificates remain unchanged.
- Manual workflow runs validate both DMGs but do not create a GitHub Release.
- The already published `v1.0.0` Release is not rewritten.

---

### Task 1: Define the dual-DMG workflow contract

**Files:**
- Modify: `scripts/test-release-workflow.sh`
- Test: `scripts/test-release-workflow.sh`

**Interfaces:**
- Consumes: `.github/workflows/release.yml` as plain YAML text.
- Produces: a shell contract requiring the architecture matrix, DMG tooling, four exact asset patterns, aggregate release dependency, and removal of Universal ZIP packaging.

- [ ] **Step 1: Replace the Universal ZIP assertions with failing dual-DMG assertions**

Add these checks after the existing trigger assertions and remove the assertion for `APP_ARCHS: "arm64 x86_64"`:

```zsh
rg -q 'matrix:' "$workflow"
rg -q 'arch: \[arm64, x86_64\]' "$workflow"
rg -Fq 'APP_ARCHS: ${{ matrix.arch }}' "$workflow"
rg -q './scripts/package-dmg.sh' "$workflow"
rg -q 'notarytool submit .*\.dmg|notarytool submit "\$dmg"' "$workflow"
rg -q 'stapler staple "\$dmg"' "$workflow"
rg -q 'spctl --assess --type open' "$workflow"
rg -q 'CPA-Usage-.*-arm64\.dmg' "$workflow"
rg -q 'CPA-Usage-.*-x86_64\.dmg' "$workflow"
rg -q 'needs: package' "$workflow"

if rg -q 'CPA-Usage-.*\.zip|ditto -c -k' "$workflow"; then
    print -u2 'Release workflow must not package a Universal ZIP'
    exit 1
fi
```

- [ ] **Step 2: Run the contract test and verify the new requirements fail**

Run:

```bash
./scripts/test-release-workflow.sh
```

Expected: non-zero exit because `.github/workflows/release.yml` has no `matrix.arch` DMG workflow yet.

- [ ] **Step 3: Commit the failing contract**

```bash
git add scripts/test-release-workflow.sh
git commit -m "test: define dual-architecture DMG release contract"
```

### Task 2: Add a locally testable DMG packager

**Files:**
- Create: `scripts/package-dmg.sh`
- Create: `scripts/test-package-dmg.sh`
- Test: `scripts/test-package-dmg.sh`

**Interfaces:**
- Consumes: `APP_PATH`, `OUTPUT_DMG`, and optional `VOLUME_NAME` environment variables.
- Produces: one compressed read-only DMG containing the app bundle and an `/Applications` symbolic link.

- [ ] **Step 1: Write the failing DMG packaging test**

Create `scripts/test-package-dmg.sh`:

```zsh
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

binary="$mount_dir/CPA Usage.app/Contents/MacOS/CPAUsageMenuBar"
[[ "$(lipo -archs "$binary")" == "$arch" ]]
[[ "$(plutil -extract CFBundleIdentifier raw "$mount_dir/CPA Usage.app/Contents/Info.plist")" == "cn.winlio.cpausage" ]]
codesign --verify --deep --strict --verbose=2 "$mount_dir/CPA Usage.app"
```

Make it executable:

```bash
chmod +x scripts/test-package-dmg.sh
```

- [ ] **Step 2: Run the test and verify it fails because the packager is missing**

Run:

```bash
./scripts/test-package-dmg.sh
```

Expected: non-zero exit with `no such file or directory: ./scripts/package-dmg.sh`.

- [ ] **Step 3: Implement the minimal DMG packager**

Create `scripts/package-dmg.sh`:

```zsh
#!/bin/zsh
set -euo pipefail

root_dir="${0:A:h:h}"
app_path="${APP_PATH:-$root_dir/dist/CPA Usage.app}"
output_dmg="${OUTPUT_DMG:-$root_dir/dist/CPA-Usage.dmg}"
volume_name="${VOLUME_NAME:-CPA Usage}"

if [[ ! -d "$app_path" ]]; then
    print -u2 "Application bundle not found: $app_path"
    exit 1
fi

mkdir -p "${output_dmg:h}"
staging_dir="$(mktemp -d)"

cleanup() {
    rm -rf "$staging_dir"
}
trap cleanup EXIT

ditto "$app_path" "$staging_dir/${app_path:t}"
ln -s /Applications "$staging_dir/Applications"
rm -f "$output_dmg"
hdiutil create \
    -volname "$volume_name" \
    -srcfolder "$staging_dir" \
    -ov \
    -format UDZO \
    "$output_dmg"

print "Created $output_dmg"
```

Make it executable:

```bash
chmod +x scripts/package-dmg.sh
```

- [ ] **Step 4: Run the DMG test and verify it passes**

Run:

```bash
./scripts/test-package-dmg.sh
```

Expected: exit 0; the mounted image contains `CPA Usage.app`, an `/Applications` link, the host-only executable, the Winlio bundle ID, and a valid ad-hoc local signature.

- [ ] **Step 5: Commit the packager and test**

```bash
git add scripts/package-dmg.sh scripts/test-package-dmg.sh
git commit -m "build: add macOS DMG packager"
```

### Task 3: Convert the release workflow to architecture-specific matrix jobs

**Files:**
- Modify: `.github/workflows/release.yml`
- Test: `scripts/test-release-workflow.sh`

**Interfaces:**
- Consumes: `scripts/build-app.sh`, `scripts/package-dmg.sh`, the five existing Apple GitHub Secrets, a tag or manual version input.
- Produces: two validated workflow artifacts and, for tags, one GitHub Release containing four exact files.

- [ ] **Step 1: Split the workflow into `test`, `package`, and `release` jobs**

Use this job structure:

```yaml
jobs:
  test:
    runs-on: macos-15
    steps:
      - name: Check out source
        uses: actions/checkout@v4
      - name: Run tests
        run: swift test

  package:
    needs: test
    runs-on: macos-15
    strategy:
      fail-fast: false
      matrix:
        arch: [arm64, x86_64]
    env:
      APP_PATH: dist/CPA Usage.app
      APP_ARCHS: ${{ matrix.arch }}
```

Retain the existing Apple secret environment variables in `package`. Keep the current version validation expression, and emit these outputs from its version step:

```zsh
dmg="CPA-Usage-$version-${{ matrix.arch }}.dmg"
print "version=$version" >> "$GITHUB_OUTPUT"
print "dmg=$dmg" >> "$GITHUB_OUTPUT"
```

- [ ] **Step 2: Build and sign one native app per matrix entry**

Use the existing metadata, certificate import, and signing steps. Rename the build step and keep the target architecture explicit:

```yaml
      - name: Build native app
        run: ./scripts/build-app.sh
```

After signing, require one exact architecture:

```zsh
archs="$(lipo -archs "$APP_PATH/Contents/MacOS/CPAUsageMenuBar")"
[[ "$archs" == "${{ matrix.arch }}" ]]
```

- [ ] **Step 3: Create, notarize, staple, and validate the DMG**

Replace ZIP notarization and packaging with:

```yaml
      - name: Create disk image
        id: package
        shell: zsh {0}
        run: |
          dmg="dist/${{ steps.version.outputs.dmg }}"
          APP_PATH="$APP_PATH" OUTPUT_DMG="$dmg" VOLUME_NAME="CPA Usage" \
            ./scripts/package-dmg.sh
          print "dmg=$dmg" >> "$GITHUB_OUTPUT"

      - name: Submit disk image for notarization
        shell: zsh {0}
        run: |
          dmg="${{ steps.package.outputs.dmg }}"
          xcrun notarytool submit "$dmg" \
            --apple-id "$APPLE_ID" \
            --password "$APPLE_APP_SPECIFIC_PASSWORD" \
            --team-id "$APPLE_TEAM_ID" \
            --wait

      - name: Staple and validate disk image
        shell: zsh {0}
        run: |
          dmg="${{ steps.package.outputs.dmg }}"
          xcrun stapler staple "$dmg"
          xcrun stapler validate "$dmg"
          spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg"

          mount_dir="$RUNNER_TEMP/mount-${{ matrix.arch }}"
          mkdir -p "$mount_dir"
          cleanup_mount() { hdiutil detach "$mount_dir" >/dev/null 2>&1 || true }
          trap cleanup_mount EXIT
          hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$dmg" >/dev/null

          mounted_app="$mount_dir/CPA Usage.app"
          codesign --verify --deep --strict --verbose=2 "$mounted_app"
          [[ "$(plutil -extract CFBundleIdentifier raw "$mounted_app/Contents/Info.plist")" == "cn.winlio.cpausage" ]]
          [[ "$(plutil -extract CFBundleShortVersionString raw "$mounted_app/Contents/Info.plist")" == "${{ steps.version.outputs.version }}" ]]
          [[ "$(lipo -archs "$mounted_app/Contents/MacOS/CPAUsageMenuBar")" == "${{ matrix.arch }}" ]]
          [[ -L "$mount_dir/Applications" ]]

          cleanup_mount
          trap - EXIT
          shasum -a 256 "$dmg" > "$dmg.sha256"
```

- [ ] **Step 4: Upload one artifact per architecture and keep cleanup unconditional**

```yaml
      - name: Upload validation artifact
        uses: actions/upload-artifact@v4
        with:
          name: CPA-Usage-${{ steps.version.outputs.version }}-${{ matrix.arch }}
          path: |
            ${{ steps.package.outputs.dmg }}
            ${{ steps.package.outputs.dmg }}.sha256
          if-no-files-found: error
```

Keep the temporary keychain deletion under `if: always()` and remove the obsolete notarization ZIP cleanup path.

- [ ] **Step 5: Add the aggregate release job**

```yaml
  release:
    needs: package
    if: github.ref_type == 'tag'
    runs-on: macos-15
    steps:
      - name: Download release assets
        uses: actions/download-artifact@v4
        with:
          pattern: CPA-Usage-*
          path: dist
          merge-multiple: true

      - name: Validate release assets
        shell: zsh {0}
        run: |
          version="${GITHUB_REF_NAME#v}"
          for arch in arm64 x86_64; do
            dmg="dist/CPA-Usage-$version-$arch.dmg"
            [[ -f "$dmg" ]]
            [[ -f "$dmg.sha256" ]]
            expected="$(awk '{print $1}' "$dmg.sha256")"
            actual="$(shasum -a 256 "$dmg" | awk '{print $1}')"
            [[ "$actual" == "$expected" ]]
          done

      - name: Create GitHub Release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh release create "$GITHUB_REF_NAME" \
            dist/CPA-Usage-*.dmg \
            dist/CPA-Usage-*.dmg.sha256 \
            --verify-tag \
            --generate-notes \
            --title "CPA Usage $GITHUB_REF_NAME"
```

- [ ] **Step 6: Run the workflow contract and YAML parser**

Run:

```bash
./scripts/test-release-workflow.sh
ruby -e 'require "yaml"; YAML.safe_load(File.read(ARGV[0]), aliases: true)' .github/workflows/release.yml
```

Expected: both commands exit 0.

- [ ] **Step 7: Commit the workflow**

```bash
git add .github/workflows/release.yml scripts/test-release-workflow.sh
git commit -m "ci: publish native arm64 and Intel DMGs"
```

### Task 4: Run full local verification

**Files:**
- Verify: `scripts/build-app.sh`
- Verify: `scripts/package-dmg.sh`
- Verify: `scripts/test-build-app.sh`
- Verify: `scripts/test-package-dmg.sh`
- Verify: `scripts/test-release-workflow.sh`
- Verify: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: all implementation outputs from Tasks 1-3.
- Produces: fresh local evidence that source compilation, Universal build compatibility, native DMG packaging, workflow contracts, and YAML syntax remain valid.

- [ ] **Step 1: Run all local verification commands**

```bash
swift test
./scripts/test-build-app.sh
./scripts/test-package-dmg.sh
./scripts/test-release-workflow.sh
git diff --check
```

Expected: every command exits 0. On machines with Command Line Tools only, `swift test` may compile Swift Testing targets without executing them; GitHub's full Xcode runner performs the authoritative test execution.

- [ ] **Step 2: Inspect the final diff and repository status**

```bash
git diff HEAD~3 --stat
git status --short --branch
```

Expected: only the design/plan, DMG scripts, workflow, and contract-test changes are present; no credentials or generated DMGs are staged.

### Task 5: Push and validate both architectures in GitHub Actions

**Files:**
- Remote workflow: `.github/workflows/release.yml`
- Remote artifacts: `CPA-Usage-<version>-arm64` and `CPA-Usage-<version>-x86_64`

**Interfaces:**
- Consumes: the committed implementation and existing GitHub Actions Apple secrets.
- Produces: a successful manual workflow run with two signed and notarized downloadable DMGs; it does not create or rewrite a Release.

- [ ] **Step 1: Push the current branch through SSH**

```bash
git push git@github.com:liuzelei/cpa-usage-menu-bar.git HEAD:main
```

Expected: remote `main` advances to the implementation commit.

- [ ] **Step 2: Trigger a manual validation build**

```bash
gh workflow run release.yml \
  --repo liuzelei/cpa-usage-menu-bar \
  --ref main \
  -f version=1.0.1
```

Expected: GitHub returns a new workflow run URL.

- [ ] **Step 3: Watch the run to completion**

```bash
gh run watch <run-id> --repo liuzelei/cpa-usage-menu-bar --exit-status
```

Expected: the test job passes; both `package (arm64)` and `package (x86_64)` pass signing, DMG notarization, staple, Gatekeeper, mounted-content, and artifact-upload checks; the release job is skipped because this is a manual run.

- [ ] **Step 4: Download and independently verify both workflow artifacts**

```bash
verification_dir="$(mktemp -d)"
gh run download <run-id> --repo liuzelei/cpa-usage-menu-bar --dir "$verification_dir"
find "$verification_dir" -type f -name '*.dmg' -o -name '*.dmg.sha256'
```

Expected: exactly two DMGs and two checksum files exist. Mount each DMG, verify its checksum, `cn.winlio.cpausage`, version `1.0.1`, Developer ID signature, stapled notarization, Gatekeeper acceptance, `/Applications` link, and exact expected architecture.

- [ ] **Step 5: Report validation and request version-tag authorization**

Do not create `v1.0.1` automatically. Report the successful manual validation and ask for explicit approval before creating the next public release tag.
