# CPA App and DMG Icon Design

## Goal

Give CPA Usage a recognizable macOS application icon and reuse the same visual
identity for the mounted DMG volume. The icon must appear correctly in Finder,
the Applications folder, macOS security dialogs, and the drag-to-install disk
image.

## Source Asset

Reuse `web/src/assets/cli-proxy-api-favicon.png` from the upstream
[`Willxup/cpa-usage-keeper`](https://github.com/Willxup/cpa-usage-keeper)
repository. The upstream repository is distributed under the MIT License, and
the user explicitly approved reusing its existing CPA icon.

Store the source PNG in this repository so builds are reproducible and do not
depend on GitHub network access. Record the upstream repository, source path,
commit SHA, and MIT license in a small attribution file next to the asset.

## macOS Icon Format

Generate a standard `AppIcon.icns` containing the macOS icon representations
for 16, 32, 128, 256, 512, and 1024 pixel rendering. Keep the original PNG as
the canonical source and commit the generated ICNS so local and CI builds do
not require image-processing dependencies beyond the macOS system tools.

The generated ICNS must be referenced by `CFBundleIconFile` in
`Resources/Info.plist` and copied into `CPA Usage.app/Contents/Resources` by
`scripts/build-app.sh` before code signing.

## DMG Integration

The app bundle inside the DMG receives its icon through `CFBundleIconFile`.
For the mounted volume, `scripts/package-dmg.sh` copies the same ICNS file to
the staging directory as `.VolumeIcon.icns` and applies the Finder custom-icon
attribute before creating the compressed DMG. The existing `/Applications`
symbolic link remains unchanged.

The DMG file itself continues to use the standard macOS disk-image document
icon; the custom CPA icon applies to the mounted volume and the enclosed app.

## Build Flow

1. The source PNG and generated `AppIcon.icns` live under `Resources/AppIcon`.
2. `scripts/build-app.sh` copies `AppIcon.icns` beside `Info.plist` in the app
   bundle before signing.
3. `Resources/Info.plist` declares `CFBundleIconFile` as `AppIcon.icns`.
4. `scripts/package-dmg.sh` reads the ICNS path from `VOLUME_ICON`, defaulting
   to the repository AppIcon, and installs it as `.VolumeIcon.icns` in the DMG
   staging directory.
5. The current Developer ID signing, DMG signing, notarization, staple, and
   Gatekeeper workflow remains unchanged apart from packaging the icon files.

## Failure Handling

- App builds fail immediately when the configured ICNS file is missing.
- DMG packaging fails when `VOLUME_ICON` points to a missing file.
- The icon-generation script validates the source image before producing an
  iconset and fails when a required representation cannot be created.
- No workflow downloads the upstream image dynamically.

## Verification

- A shell test checks that `CFBundleIconFile` equals `AppIcon.icns`, the built
  app contains `Contents/Resources/AppIcon.icns`, and the ICNS file is valid.
- The DMG test mounts the image and checks both the enclosed app icon and the
  `.VolumeIcon.icns` file.
- `iconutil` validates the generated ICNS by converting it back to an iconset.
- The normal build, DMG, release workflow contract, signing, notarization, and
  Gatekeeper tests continue to pass.
- A manual GitHub Actions run produces both architecture-specific DMGs for
  visual inspection before the next public tag is created.
