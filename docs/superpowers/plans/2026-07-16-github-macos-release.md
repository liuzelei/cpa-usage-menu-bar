# GitHub macOS Release Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish CPA Usage from `v*` Git tags as a universal, Developer ID-signed, Apple-notarized GitHub Release.

**Architecture:** Extend the existing app assembly script to produce a universal executable, then add one GitHub Actions workflow that versions, signs, notarizes, validates, packages, and publishes the app. Generate a dedicated Developer ID key pair locally, store only the password-protected certificate and notarization credentials in GitHub Actions secrets, and leave existing Apple certificates untouched.

**Tech Stack:** Swift 6, Swift Package Manager, zsh, GitHub Actions, macOS `codesign`, `security`, `notarytool`, `stapler`, `spctl`, `lipo`, GitHub CLI

## Global Constraints

- The bundle identifier remains exactly `cn.winlio.cpausage`.
- Tags matching `v*` create releases; manual workflow runs validate without creating releases.
- Release builds contain both `arm64` and `x86_64` architectures.
- Existing Apple certificates and App Store Connect applications must not be revoked, replaced, or modified.
- Private keys, certificate archives, and passwords must never be committed, printed, or uploaded as workflow artifacts.
- The workflow distributes outside the Mac App Store.

---

### Task 1: Add Universal Application Builds

**Files:**
- Create: `scripts/test-build-app.sh`
- Modify: `scripts/build-app.sh`

**Interfaces:**
- Consumes: optional `APP_ARCHS` environment variable containing a space-separated architecture list.
- Produces: `dist/CPA Usage.app` whose executable contains every architecture requested by `APP_ARCHS`; defaults to `uname -m` when unset.

- [ ] **Step 1: Write the failing universal-build test**

Create `scripts/test-build-app.sh`:

```zsh
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
```

Make it executable:

```bash
chmod +x scripts/test-build-app.sh
```

- [ ] **Step 2: Run the test and verify the current script fails**

Run:

```bash
./scripts/test-build-app.sh
```

Expected: FAIL because the existing script ignores `APP_ARCHS` and produces only the host architecture.

- [ ] **Step 3: Implement architecture-aware builds**

Replace `scripts/build-app.sh` with:

```zsh
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
```

- [ ] **Step 4: Verify native and universal builds**

Run:

```bash
APP_ARCHS="$(uname -m)" ./scripts/build-app.sh
./scripts/test-build-app.sh
```

Expected: both commands succeed; the second reports both `arm64` and `x86_64`.

- [ ] **Step 5: Commit the universal build support**

```bash
git add scripts/build-app.sh scripts/test-build-app.sh
git commit -m "build: support universal macOS app bundles"
```

---

### Task 2: Add the Signed and Notarized Release Workflow

**Files:**
- Create: `.github/workflows/release.yml`
- Create: `scripts/test-release-workflow.sh`

**Interfaces:**
- Consumes: Git tag or manual `version` input plus the five Apple Actions secrets named in the design.
- Produces: a signed and notarized ZIP and checksum; tag runs additionally produce a GitHub Release.

- [ ] **Step 1: Write the failing workflow contract test**

Create `scripts/test-release-workflow.sh`:

```zsh
#!/bin/zsh
set -euo pipefail

root_dir="${0:A:h:h}"
workflow="$root_dir/.github/workflows/release.yml"

[[ -f "$workflow" ]]
rg -q 'tags:' "$workflow"
rg -q 'workflow_dispatch:' "$workflow"
rg -q 'APP_ARCHS: "arm64 x86_64"' "$workflow"
rg -q 'APPLE_CERTIFICATE_BASE64' "$workflow"
rg -q 'APPLE_APP_SPECIFIC_PASSWORD' "$workflow"
rg -q 'codesign' "$workflow"
rg -q 'notarytool submit' "$workflow"
rg -q 'stapler staple' "$workflow"
rg -q 'spctl --assess' "$workflow"
rg -q 'gh release create' "$workflow"

ruby -e 'require "yaml"; YAML.safe_load(File.read(ARGV[0]), aliases: true)' "$workflow"
```

Make it executable and run it:

```bash
chmod +x scripts/test-release-workflow.sh
./scripts/test-release-workflow.sh
```

Expected: FAIL because `.github/workflows/release.yml` does not exist.

- [ ] **Step 2: Create the release workflow**

Create `.github/workflows/release.yml`:

```yaml
name: Release macOS App

on:
  push:
    tags:
      - "v*"
  workflow_dispatch:
    inputs:
      version:
        description: Version used for a validation build
        required: true
        default: "1.0.0"

permissions:
  contents: write

concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false

jobs:
  release:
    runs-on: macos-15
    env:
      APP_PATH: dist/CPA Usage.app
      APP_ARCHS: "arm64 x86_64"
      APPLE_CERTIFICATE_BASE64: ${{ secrets.APPLE_CERTIFICATE_BASE64 }}
      APPLE_CERTIFICATE_PASSWORD: ${{ secrets.APPLE_CERTIFICATE_PASSWORD }}
      APPLE_ID: ${{ secrets.APPLE_ID }}
      APPLE_APP_SPECIFIC_PASSWORD: ${{ secrets.APPLE_APP_SPECIFIC_PASSWORD }}
      APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}

    steps:
      - name: Check out source
        uses: actions/checkout@v4

      - name: Run tests
        run: swift test

      - name: Resolve version
        id: version
        shell: zsh
        run: |
          set -euo pipefail
          if [[ "$GITHUB_REF_TYPE" == "tag" ]]; then
            version="${GITHUB_REF_NAME#v}"
          else
            version="${{ inputs.version }}"
          fi
          if ! print -rn -- "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$'; then
            print -u2 "Invalid version: $version"
            exit 1
          fi
          print "version=$version" >> "$GITHUB_OUTPUT"
          print "archive=CPA-Usage-$version.zip" >> "$GITHUB_OUTPUT"

      - name: Apply version metadata
        shell: zsh
        run: |
          plutil -replace CFBundleShortVersionString -string "${{ steps.version.outputs.version }}" Resources/Info.plist
          plutil -replace CFBundleVersion -string "$GITHUB_RUN_NUMBER" Resources/Info.plist

      - name: Build universal app
        run: ./scripts/build-app.sh

      - name: Import Developer ID certificate
        id: signing
        shell: zsh
        run: |
          set -euo pipefail
          keychain="$RUNNER_TEMP/release-signing.keychain-db"
          certificate="$RUNNER_TEMP/developer-id.p12"
          keychain_password="$(uuidgen)$(uuidgen)"

          print -rn -- "$APPLE_CERTIFICATE_BASE64" | base64 --decode > "$certificate"
          security create-keychain -p "$keychain_password" "$keychain"
          security set-keychain-settings -lut 21600 "$keychain"
          security unlock-keychain -p "$keychain_password" "$keychain"
          security import "$certificate" -k "$keychain" -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
          security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain"
          security list-keychains -d user -s "$keychain" login.keychain-db

          identity="$(security find-identity -v -p codesigning "$keychain" | awk '/Developer ID Application/ {print $2; exit}')"
          if [[ -z "$identity" ]]; then
            print -u2 "Developer ID Application identity not found"
            exit 1
          fi

          print "keychain=$keychain" >> "$GITHUB_OUTPUT"
          print "identity=$identity" >> "$GITHUB_OUTPUT"

      - name: Sign application
        shell: zsh
        run: |
          codesign --force --deep --strict --options runtime --timestamp \
            --keychain "${{ steps.signing.outputs.keychain }}" \
            --sign "${{ steps.signing.outputs.identity }}" \
            "$APP_PATH"
          codesign --verify --deep --strict --verbose=2 "$APP_PATH"

      - name: Submit for notarization
        shell: zsh
        run: |
          notarization_archive="$RUNNER_TEMP/CPA-Usage-notarization.zip"
          ditto -c -k --keepParent "$APP_PATH" "$notarization_archive"
          xcrun notarytool submit "$notarization_archive" \
            --apple-id "$APPLE_ID" \
            --password "$APPLE_APP_SPECIFIC_PASSWORD" \
            --team-id "$APPLE_TEAM_ID" \
            --wait

      - name: Staple and validate notarization
        shell: zsh
        run: |
          xcrun stapler staple "$APP_PATH"
          xcrun stapler validate "$APP_PATH"
          codesign --verify --deep --strict --verbose=2 "$APP_PATH"
          spctl --assess --type execute --verbose=4 "$APP_PATH"

          [[ "$(plutil -extract CFBundleIdentifier raw "$APP_PATH/Contents/Info.plist")" == "cn.winlio.cpausage" ]]
          archs="$(lipo -archs "$APP_PATH/Contents/MacOS/CPAUsageMenuBar")"
          [[ " $archs " == *" arm64 "* ]]
          [[ " $archs " == *" x86_64 "* ]]

      - name: Package release
        id: package
        shell: zsh
        run: |
          archive="dist/${{ steps.version.outputs.archive }}"
          rm -f "$archive" "$archive.sha256"
          ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$archive"
          shasum -a 256 "$archive" > "$archive.sha256"
          print "archive=$archive" >> "$GITHUB_OUTPUT"

      - name: Upload validation artifact
        uses: actions/upload-artifact@v4
        with:
          name: CPA-Usage-${{ steps.version.outputs.version }}
          path: |
            ${{ steps.package.outputs.archive }}
            ${{ steps.package.outputs.archive }}.sha256
          if-no-files-found: error

      - name: Create GitHub Release
        if: github.ref_type == 'tag'
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh release create "$GITHUB_REF_NAME" \
            "${{ steps.package.outputs.archive }}" \
            "${{ steps.package.outputs.archive }}.sha256" \
            --verify-tag \
            --generate-notes \
            --title "CPA Usage $GITHUB_REF_NAME"

      - name: Remove temporary credentials
        if: always()
        shell: zsh
        run: |
          keychain="${{ steps.signing.outputs.keychain }}"
          if [[ -n "$keychain" && -f "$keychain" ]]; then
            security delete-keychain "$keychain" || true
          fi
          rm -f "$RUNNER_TEMP/developer-id.p12" "$RUNNER_TEMP/CPA-Usage-notarization.zip"
```

- [ ] **Step 3: Verify the workflow contract and local build**

Run:

```bash
./scripts/test-release-workflow.sh
./scripts/test-build-app.sh
git diff --check
```

Expected: all commands succeed.

- [ ] **Step 4: Commit the workflow**

```bash
git add .github/workflows/release.yml scripts/test-release-workflow.sh
git commit -m "ci: add signed notarized macOS releases"
```

---

### Task 3: Create and Store Apple Release Credentials

**Files:**
- Create temporarily outside the repository: `/tmp/cpa-release-credentials/developer-id.key`
- Create temporarily outside the repository: `/tmp/cpa-release-credentials/developer-id.csr`
- Create temporarily outside the repository: `/tmp/cpa-release-credentials/developer-id.cer`
- Create temporarily outside the repository: `/tmp/cpa-release-credentials/developer-id.p12`
- Create temporarily outside the repository: `/tmp/cpa-release-credentials/p12-password`

**Interfaces:**
- Consumes: the currently selected Apple Developer team and the user's authenticated Apple account.
- Produces: repository Actions secrets required by `.github/workflows/release.yml`.

- [ ] **Step 1: Generate the private key, CSR, and PKCS#12 password locally**

Run without shell tracing:

```bash
rm -rf /tmp/cpa-release-credentials
mkdir -m 700 /tmp/cpa-release-credentials
openssl genrsa -out /tmp/cpa-release-credentials/developer-id.key 2048
chmod 600 /tmp/cpa-release-credentials/developer-id.key
openssl req -new -sha256 \
  -key /tmp/cpa-release-credentials/developer-id.key \
  -out /tmp/cpa-release-credentials/developer-id.csr \
  -subj '/CN=CPA Usage GitHub Actions/C=CN'
openssl rand -base64 36 > /tmp/cpa-release-credentials/p12-password
chmod 600 /tmp/cpa-release-credentials/p12-password
openssl req -in /tmp/cpa-release-credentials/developer-id.csr -noout -verify
```

Expected: CSR verification reports `verify OK`.

- [ ] **Step 2: Create the Developer ID Application certificate in Apple Developer**

In the already authenticated Apple Developer certificate page:

1. Select `Add new certificate`.
2. Select `Developer ID Application` under Software.
3. Continue without changing or revoking any existing certificate.
4. Upload `/tmp/cpa-release-credentials/developer-id.csr`.
5. Create the certificate and download the resulting `.cer` file.
6. Copy the downloaded file to `/tmp/cpa-release-credentials/developer-id.cer`.

- [ ] **Step 3: Build and validate the password-protected `.p12`**

Run:

```bash
openssl x509 -inform DER \
  -in /tmp/cpa-release-credentials/developer-id.cer \
  -out /tmp/cpa-release-credentials/developer-id.pem
openssl x509 -in /tmp/cpa-release-credentials/developer-id.pem -noout -subject -issuer -dates
openssl pkcs12 -export -legacy \
  -inkey /tmp/cpa-release-credentials/developer-id.key \
  -in /tmp/cpa-release-credentials/developer-id.pem \
  -out /tmp/cpa-release-credentials/developer-id.p12 \
  -passout file:/tmp/cpa-release-credentials/p12-password \
  -name 'CPA Usage GitHub Actions'
chmod 600 /tmp/cpa-release-credentials/developer-id.p12
```

Validate importability using a disposable local keychain, then delete that keychain:

```bash
keychain=/tmp/cpa-release-credentials/validation.keychain-db
keychain_password="$(uuidgen)$(uuidgen)"
security create-keychain -p "$keychain_password" "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import /tmp/cpa-release-credentials/developer-id.p12 \
  -k "$keychain" \
  -P "$(< /tmp/cpa-release-credentials/p12-password)" \
  -T /usr/bin/codesign
security find-identity -v -p codesigning "$keychain" | rg 'Developer ID Application'
security delete-keychain "$keychain"
```

Expected: exactly one valid Developer ID Application identity appears.

- [ ] **Step 4: Create a dedicated Apple app-specific password**

In the authenticated Apple Account security page, create one app-specific
password named `CPA Usage GitHub CI`. If Apple requests password, 2FA, or other
account verification, pause for the user to complete it. Save the one-time
password directly to `/tmp/cpa-release-credentials/apple-app-password` with
mode `600` without printing it.

- [ ] **Step 5: Store all five values in GitHub Actions secrets**

Run without printing the values:

```bash
base64 -i /tmp/cpa-release-credentials/developer-id.p12 | gh secret set APPLE_CERTIFICATE_BASE64
gh secret set APPLE_CERTIFICATE_PASSWORD < /tmp/cpa-release-credentials/p12-password
gh secret set APPLE_APP_SPECIFIC_PASSWORD < /tmp/cpa-release-credentials/apple-app-password
```

Set `APPLE_ID` and `APPLE_TEAM_ID` from the currently authenticated account by
passing their values to `gh secret set` through standard input, not command-line
arguments. Verify only the secret names:

```bash
gh secret list | rg 'APPLE_(CERTIFICATE_BASE64|CERTIFICATE_PASSWORD|ID|APP_SPECIFIC_PASSWORD|TEAM_ID)'
```

Expected: all five names are listed; their values are not displayed.

- [ ] **Step 6: Remove local credential material**

Only after GitHub lists all five secrets:

```bash
rm -rf /tmp/cpa-release-credentials
test ! -e /tmp/cpa-release-credentials
```

---

### Task 4: Push, Validate, and Publish Version 1.0.0

**Files:**
- No new files.

**Interfaces:**
- Consumes: committed workflow, configured repository secrets, and the remote default branch `main`.
- Produces: a successful manual validation run followed by GitHub Release `v1.0.0`.

- [ ] **Step 1: Run final local verification**

Run:

```bash
./scripts/test-build-app.sh
./scripts/test-release-workflow.sh
swift test
git diff --check
git status --short
```

Expected: script validations and build succeed, `swift test` exits successfully,
and the worktree is clean.

- [ ] **Step 2: Push the local commits to the remote default branch**

Run:

```bash
git fetch origin main
git merge-base --is-ancestor origin/main HEAD
git push origin HEAD:main
```

Expected: the remote `main` branch advances without a force push.

- [ ] **Step 3: Run and watch the manual validation build**

Run:

```bash
gh workflow run release.yml --ref main -f version=1.0.0
run_id="$(gh run list --workflow release.yml --branch main --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "$run_id" --exit-status
```

Expected: the workflow completes successfully and uploads the signed,
notarized validation artifact without creating a GitHub Release.

- [ ] **Step 4: Create and push the first release tag**

First verify that the tag and release do not already exist:

```bash
test -z "$(git tag --list v1.0.0)"
! gh release view v1.0.0 >/dev/null 2>&1
```

Then create and push the tag:

```bash
git tag -a v1.0.0 -m 'CPA Usage v1.0.0'
git push origin v1.0.0
```

- [ ] **Step 5: Watch the release run and verify published assets**

Run:

```bash
run_id="$(gh run list --workflow release.yml --branch v1.0.0 --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "$run_id" --exit-status
gh release view v1.0.0 --json url,name,tagName,assets
```

Expected: release `v1.0.0` exists with one CPA Usage ZIP and one `.sha256`
asset, and the GitHub Actions run is successful.
