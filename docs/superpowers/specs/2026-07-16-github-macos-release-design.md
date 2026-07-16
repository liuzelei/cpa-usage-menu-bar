# GitHub macOS Release Automation Design

## Goal

Publish CPA Usage from GitHub tags as a universal macOS application that is
signed with the Winlio Apple Developer identity, notarized by Apple, and
attached to a GitHub Release.

## Release Contract

- Tags matching `v*` trigger a release; `workflow_dispatch` allows a manual
  verification run.
- The tag without its leading `v` becomes `CFBundleShortVersionString`.
- `GITHUB_RUN_NUMBER` becomes the monotonically increasing `CFBundleVersion`.
- The packaged bundle identifier remains exactly `cn.winlio.cpausage`.
- The release contains a ZIP archive and its SHA-256 checksum.
- This workflow distributes outside the Mac App Store and does not modify any
  existing App Store Connect application.

## Build Architecture

Update `scripts/build-app.sh` so CI can request both `arm64` and `x86_64`
builds while local development can continue to build the host architecture.
The two release executables are combined with `lipo` into a universal binary
before the standard `.app` bundle is assembled.

The workflow runs on a GitHub-hosted macOS runner and performs these stages:

1. Check out the tag and run the Swift test command.
2. Derive and validate the version from the tag or manual input.
3. Write the release version and build number into `Resources/Info.plist`.
4. Build an `arm64` and `x86_64` universal application.
5. Import the Developer ID certificate into a temporary keychain.
6. Sign with Hardened Runtime and a trusted Apple timestamp.
7. Submit the archive to Apple notarization and wait for the result.
8. Staple the notarization ticket and validate the app with `codesign`,
   `stapler`, `spctl`, `plutil`, and `lipo`.
9. Recreate the final ZIP, produce a SHA-256 checksum, and create the GitHub
   Release for tag-triggered runs.
10. Delete temporary keychains and credential files even when the job fails.

## Apple Credentials

Create one new `Developer ID Application` certificate in the currently
selected Apple Developer team. Creating it must not revoke or modify any
existing development, distribution, or push certificate.

Generate a new private key and CSR locally. Upload only the CSR to Apple,
download the issued certificate, and combine it with the private key into a
password-protected PKCS#12 (`.p12`) bundle. After its contents and password are
stored in GitHub Actions secrets, remove the temporary private-key material
from disk.

Use an Apple ID app-specific password for notarization because App Store
Connect API access is not currently enabled for the team. The workflow can be
migrated to an App Store Connect `.p8` API key later without changing the build
or release stages.

## GitHub Secrets

Configure these repository Actions secrets:

- `APPLE_CERTIFICATE_BASE64`: Base64 representation of the `.p12` bundle.
- `APPLE_CERTIFICATE_PASSWORD`: Random password protecting the `.p12` bundle.
- `APPLE_ID`: Apple ID used for notarization.
- `APPLE_APP_SPECIFIC_PASSWORD`: Dedicated app-specific password for CI.
- `APPLE_TEAM_ID`: Apple Developer team identifier used by `notarytool`.

The temporary CI keychain password is generated inside each workflow run and
is not stored as a repository secret.

## Security Boundaries

- Private keys, certificate archives, Apple passwords, and GitHub secret
  values must never be committed, printed, or attached to workflow artifacts.
- Secret values are sent only to GitHub Actions secrets and to Apple's
  notarization service for the requested release process.
- Shell tracing must remain disabled for credential-handling steps.
- Existing Apple certificates must not be revoked.
- The temporary certificate workspace and CI keychain are removed after use.

## Failure Handling

- A test, build, signing, notarization, validation, or packaging failure stops
  the release before GitHub Release creation.
- Notarization uses `--wait` so the workflow exposes Apple's final acceptance
  or rejection directly in the job result.
- The release step uses GitHub's automatically scoped token with
  `contents: write`; no personal GitHub token is stored.
- Manual workflow runs build and validate the app but do not create a release
  unless they are associated with a release tag.

## Verification

- Run local source and build-script tests before pushing.
- Run a GitHub Actions manual build after secrets are installed.
- Push a test release tag only after the manual build succeeds.
- Confirm the final archive contains a universal executable, the expected
  bundle identifier and version, a valid Developer ID signature, a stapled
  notarization ticket, and a Gatekeeper acceptance result.

