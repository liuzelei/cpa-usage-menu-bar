# Dual-Architecture DMG Release Design

## Goal

Publish CPA Usage as two independently built macOS disk images: one for Apple
Silicon (`arm64`) and one for Intel (`x86_64`). Each disk image must contain a
Developer ID-signed application, be notarized by Apple, pass Gatekeeper
validation, and be attached to the same GitHub Release.

## Release Contract

- Tags matching `v*` trigger a release; `workflow_dispatch` performs a manual
  validation build without creating a GitHub Release.
- The tag without its leading `v` becomes `CFBundleShortVersionString`.
- `GITHUB_RUN_NUMBER` becomes `CFBundleVersion` for both architectures.
- The bundle identifier remains exactly `cn.winlio.cpausage`.
- The existing Universal ZIP is replaced by these four assets:
  - `CPA-Usage-<version>-arm64.dmg`
  - `CPA-Usage-<version>-arm64.dmg.sha256`
  - `CPA-Usage-<version>-x86_64.dmg`
  - `CPA-Usage-<version>-x86_64.dmg.sha256`
- The `arm64` DMG contains only an `arm64` executable, and the `x86_64` DMG
  contains only an `x86_64` executable.

## Workflow Architecture

Keep one test job and use a two-entry GitHub Actions matrix for packaging.
The matrix entries are `arm64` and `x86_64`; each entry builds, signs,
packages, notarizes, staples, validates, and uploads one architecture-specific
artifact. A final release job downloads both matrix artifacts and creates one
GitHub Release only after both entries succeed.

This separation prevents parallel jobs from racing to create the same Release
and allows GitHub to rerun a failed architecture independently. The existing
Apple secrets remain unchanged and are imported into an isolated temporary
keychain in each matrix job.

## Per-Architecture Build and Packaging

For each matrix architecture:

1. Check out the source and apply identical version metadata.
2. Run `scripts/build-app.sh` with `APP_ARCHS` set to the single target
   architecture.
3. Import the Developer ID Application certificate into a temporary keychain.
4. Sign `CPA Usage.app` with Hardened Runtime and a trusted timestamp.
5. Verify the app signature and confirm the executable contains exactly the
   requested architecture.
6. Create a read-only compressed DMG containing `CPA Usage.app` and an
   `/Applications` symbolic link for drag-to-install behavior.
7. Submit the DMG to Apple with `notarytool --wait`.
8. Staple the notarization ticket to the DMG and validate it with `stapler` and
   Gatekeeper.
9. Mount the final DMG read-only, validate the enclosed app's bundle ID,
   version, signature, and architecture, then detach it even if validation
   fails.
10. Generate the DMG's SHA-256 checksum and upload both files as a workflow
    artifact.

The DMG creation logic belongs in a focused script so it can be tested locally
without duplicating shell logic in the workflow.

## GitHub Release Assembly

The release job depends on both matrix packaging jobs. It downloads their
artifacts into one directory and verifies that all four exact filenames exist.
For tag-triggered runs, it creates `CPA Usage <tag>` and attaches all four
files. For manual runs, it uploads the two architecture artifacts for
inspection but skips GitHub Release creation.

## Security and Cleanup

- No Apple credential or certificate content is added to the DMG or workflow
  artifacts.
- Shell tracing remains disabled around credential operations.
- Each matrix entry deletes its temporary keychain and decoded certificate in
  an `always()` cleanup step.
- DMG staging directories and mounted volumes are created under runner
  temporary storage and cleaned or detached after use.
- No existing Apple certificate is revoked or replaced.

## Failure Handling

- Tests must pass before either architecture is packaged.
- A build, signature, architecture, DMG creation, notarization, staple,
  Gatekeeper, mount, or checksum failure stops that matrix entry.
- The release job cannot run unless both architecture entries succeed.
- Exact asset-name checks prevent incomplete Releases.
- Mounted disk images are detached through a cleanup path even when content
  validation fails.

## Verification

- Extend the shell contract tests first so they fail until the workflow
  contains both matrix architectures, DMG notarization, four release assets,
  and no Universal ZIP packaging.
- Add a local DMG packaging test that builds a host-architecture app, creates a
  DMG, mounts it, and verifies the app and `/Applications` link.
- Run Swift compilation/tests, build-script tests, DMG tests, release workflow
  contract tests, and YAML parsing locally.
- Run a manual GitHub Actions validation build and inspect both downloadable
  DMG artifacts.
- Publish a new version tag only after manual validation succeeds; do not
  rewrite the already published `v1.0.0` Release.
