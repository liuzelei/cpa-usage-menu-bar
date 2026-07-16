# Winlio Bundle Identifier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the temporary macOS application and Keychain identifiers with `cn.winlio.cpausage`.

**Architecture:** Keep the existing Swift Package and app-bundle assembly unchanged. Update the identifier at its two runtime sources, lock the Keychain value with a focused unit test, and align the existing project documentation.

**Tech Stack:** Swift 6, Swift Testing, macOS `Info.plist`, Swift Package Manager

## Global Constraints

- The canonical application identifier is exactly `cn.winlio.cpausage`.
- Do not migrate credentials stored under `com.cpausage.menubar`.
- Keep the Swift package name, executable name, application display name, and file-system paths unchanged.

---

### Task 1: Replace and Verify the Application Identifier

**Files:**
- Modify: `Tests/CPAUsageMenuBarTests/CredentialStoreTests.swift`
- Modify: `Sources/CPAUsageMenuBar/Storage/CredentialStore.swift:16`
- Modify: `Resources/Info.plist:10`
- Modify: `docs/superpowers/plans/2026-07-16-cpa-menu-bar-app.md:214`
- Modify: `docs/superpowers/plans/2026-07-16-cpa-menu-bar-app.md:509`

**Interfaces:**
- Consumes: `KeychainCredentialStore.service: String` and the app bundle's `CFBundleIdentifier` value.
- Produces: matching source and packaged identifiers with the exact value `cn.winlio.cpausage`.

- [ ] **Step 1: Add a failing Keychain service identifier test**

Add this test to `Tests/CPAUsageMenuBarTests/CredentialStoreTests.swift`:

```swift
@Test
func credentialStoreUsesWinlioServiceIdentifier() {
    #expect(KeychainCredentialStore.service == "cn.winlio.cpausage")
}
```

- [ ] **Step 2: Run the focused test and verify the old identifier fails it**

Run:

```bash
swift test --filter credentialStoreUsesWinlioServiceIdentifier
```

Expected: FAIL because `KeychainCredentialStore.service` is still `com.cpausage.menubar`.

- [ ] **Step 3: Replace both active identifiers**

In `Sources/CPAUsageMenuBar/Storage/CredentialStore.swift`, set:

```swift
static let service = "cn.winlio.cpausage"
```

In `Resources/Info.plist`, set:

```xml
<key>CFBundleIdentifier</key>
<string>cn.winlio.cpausage</string>
```

Update the two references in `docs/superpowers/plans/2026-07-16-cpa-menu-bar-app.md` to describe `cn.winlio.cpausage`.

- [ ] **Step 4: Run the focused test and complete test suite**

Run:

```bash
swift test --filter credentialStoreUsesWinlioServiceIdentifier
swift test
```

Expected: the focused test and the complete suite both pass.

- [ ] **Step 5: Build and inspect the release application**

Run:

```bash
./scripts/build-app.sh
plutil -extract CFBundleIdentifier raw "dist/CPA Usage.app/Contents/Info.plist"
rg -n "com\.cpausage\.menubar" Resources Sources Tests README.md
```

Expected:

- Build succeeds.
- `plutil` prints `cn.winlio.cpausage`.
- The search returns no matches in active source, resources, tests, or user-facing documentation.

- [ ] **Step 6: Commit the implementation**

```bash
git add Resources/Info.plist \
  Sources/CPAUsageMenuBar/Storage/CredentialStore.swift \
  Tests/CPAUsageMenuBarTests/CredentialStoreTests.swift \
  docs/superpowers/plans/2026-07-16-cpa-menu-bar-app.md \
  docs/superpowers/plans/2026-07-16-winlio-bundle-identifier.md
git commit -m "chore: adopt Winlio bundle identifier"
```

