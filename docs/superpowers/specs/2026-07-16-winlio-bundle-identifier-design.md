# Winlio Bundle Identifier Design

## Goal

Replace the temporary application identifier with an identifier based on the
company-controlled `winlio.cn` domain before the app is distributed externally.

## Identifier

Use `cn.winlio.cpausage` as the canonical identifier for the macOS app.

The identifier is specific to the CPA Usage application while leaving the
`cn.winlio` namespace available for future Winlio applications.

## Scope

- Change `CFBundleIdentifier` in `Resources/Info.plist` from
  `com.cpausage.menubar` to `cn.winlio.cpausage`.
- Change the Keychain service identifier in `CredentialStore.swift` from
  `com.cpausage.menubar` to `cn.winlio.cpausage`.
- Update current documentation and tests that assert or describe the old
  identifier.
- Keep the Swift package name, executable name, application display name, and
  file-system paths unchanged.

## Credential Compatibility

No credential migration will be implemented because the app has not been
distributed to external users. Existing development installations may need to
enter their Keeper password or API key again after the identifier changes.

## Verification

- Search the active source, resources, tests, and user-facing documentation to
  confirm the old identifier is no longer used.
- Run the complete Swift test suite.
- Build the release `.app` and verify that its packaged `Info.plist` contains
  `cn.winlio.cpausage`.

