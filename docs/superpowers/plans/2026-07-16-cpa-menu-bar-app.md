# CPA Menu Bar App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a lightweight native macOS menu bar application that authenticates to one CPA Usage Keeper instance and displays configurable usage metrics without a persistent browser tab.

**Architecture:** A Swift Package produces an AppKit accessory application with SwiftUI popover/settings views. Focused stores own preferences and Keychain access, an actor-based API client owns Cookie Session authentication, and a main-actor refresh model publishes normalized snapshots to the status item and views.

**Tech Stack:** Swift 6.3, macOS 13+, AppKit, SwiftUI, Foundation `URLSession`, Security framework, ServiceManagement, Swift Package Manager, XCTest.

## Global Constraints

- Support one CPA Usage Keeper instance and one active identity only.
- Support Administrator Password and CPA API Key authentication as distinct modes.
- Store credentials only in macOS Keychain; never log credentials, cookies, or authentication bodies.
- Permit `http` URLs for LAN deployments while warning that credentials are not transport-encrypted.
- Keep the application out of the Dock during normal operation.
- Default refresh interval: 60 seconds; choices: 30 seconds, 60 seconds, 5 minutes, 15 minutes.
- Default menu bar metric: today's Token count.
- Popover ranges: Today, Last 24 Hours, Last 7 Days, Last 30 Days.
- Keep last-known-good usage visible during transient failures.
- Do not add third-party runtime dependencies.

---

## File Map

- `Package.swift`: Swift package definition and macOS platform floor.
- `Sources/CPAUsageMenuBar/App/CPAUsageMenuBarApp.swift`: executable entry point and accessory activation.
- `Sources/CPAUsageMenuBar/App/AppDelegate.swift`: status item, popover, settings window, and app lifecycle.
- `Sources/CPAUsageMenuBar/Models/AppConfiguration.swift`: authentication, range, refresh, and display settings types.
- `Sources/CPAUsageMenuBar/Models/UsageSnapshot.swift`: normalized Keeper usage model.
- `Sources/CPAUsageMenuBar/Models/AppError.swift`: user-facing error classification.
- `Sources/CPAUsageMenuBar/Formatting/UsageFormatter.swift`: compact status item and card formatting.
- `Sources/CPAUsageMenuBar/Storage/PreferencesStore.swift`: non-secret settings persistence.
- `Sources/CPAUsageMenuBar/Storage/CredentialStore.swift`: Keychain credential persistence.
- `Sources/CPAUsageMenuBar/Networking/KeeperAPIClient.swift`: login, cookies, overview calls, retry, decoding.
- `Sources/CPAUsageMenuBar/Refresh/UsageRefreshModel.swift`: timer, range state, last-known-good data, refresh coordination.
- `Sources/CPAUsageMenuBar/Views/UsagePopoverView.swift`: summary/setup popover.
- `Sources/CPAUsageMenuBar/Views/SettingsView.swift`: validated settings editor.
- `Sources/CPAUsageMenuBar/Views/MetricCard.swift`: reusable summary metric.
- `Sources/CPAUsageMenuBar/System/LaunchAtLoginController.swift`: ServiceManagement wrapper.
- `Tests/CPAUsageMenuBarTests/*`: focused XCTest suites.
- `scripts/build-app.sh`: release build and `.app` assembly.
- `Resources/Info.plist`: accessory app metadata.
- `README.md`: build, install, and usage instructions.

### Task 1: Create the Buildable Native Application Skeleton

**Files:**
- Create: `Package.swift`
- Create: `Sources/CPAUsageMenuBar/App/CPAUsageMenuBarApp.swift`
- Create: `Sources/CPAUsageMenuBar/App/AppDelegate.swift`
- Create: `Tests/CPAUsageMenuBarTests/SmokeTests.swift`

**Interfaces:**
- Produces: executable target `CPAUsageMenuBar` and test target `CPAUsageMenuBarTests`.
- Produces: `@main struct CPAUsageMenuBarApp` and `final class AppDelegate: NSObject, NSApplicationDelegate`.

- [ ] **Step 1: Write the package and failing smoke test**

```swift
// Tests/CPAUsageMenuBarTests/SmokeTests.swift
import XCTest
@testable import CPAUsageMenuBar

final class SmokeTests: XCTestCase {
    func testApplicationNameIsStable() {
        XCTAssertEqual(AppDelegate.applicationName, "CPA Usage")
    }
}
```

Define `Package.swift` with `.macOS(.v13)`, one executable target linking `AppKit`, `SwiftUI`, `Security`, and `ServiceManagement`, and one test target.

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter SmokeTests`

Expected: compile failure because `AppDelegate.applicationName` does not exist.

- [ ] **Step 3: Add the minimal accessory app entry point**

```swift
// Sources/CPAUsageMenuBar/App/CPAUsageMenuBarApp.swift
import AppKit

@main
enum CPAUsageMenuBarApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
```

```swift
// Sources/CPAUsageMenuBar/App/AppDelegate.swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let applicationName = "CPA Usage"

    func applicationDidFinishLaunching(_ notification: Notification) {}
}
```

- [ ] **Step 4: Run tests and build**

Run: `swift test --filter SmokeTests && swift build`

Expected: one passing test and a successful debug executable build.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "build: scaffold native menu bar app"
```

### Task 2: Define Configuration, Snapshot, Errors, and Formatting

**Files:**
- Create: `Sources/CPAUsageMenuBar/Models/AppConfiguration.swift`
- Create: `Sources/CPAUsageMenuBar/Models/UsageSnapshot.swift`
- Create: `Sources/CPAUsageMenuBar/Models/AppError.swift`
- Create: `Sources/CPAUsageMenuBar/Formatting/UsageFormatter.swift`
- Create: `Tests/CPAUsageMenuBarTests/ConfigurationTests.swift`
- Create: `Tests/CPAUsageMenuBarTests/UsageFormatterTests.swift`

**Interfaces:**
- Produces: `enum AuthenticationType: String, Codable, CaseIterable { case administratorPassword, cpaAPIKey }`.
- Produces: `enum UsageRange: String, Codable, CaseIterable { case today, last24Hours = "24h", last7Days = "7d", last30Days = "30d" }`.
- Produces: `enum MenuBarMetric: String, Codable, CaseIterable { case iconOnly, tokens, cost, requests }`.
- Produces: `struct AppConfiguration: Codable, Equatable` with `baseURL`, `authenticationType`, `refreshInterval`, `menuBarMetric`, and `launchAtLogin`.
- Produces: `struct UsageSnapshot: Equatable, Sendable` with requests, successes, failures, tokens, optional cost, range, timezone, and refreshedAt.
- Produces: `enum AppError: LocalizedError, Equatable`.
- Produces: `UsageFormatter.compactNumber(_:)`, `statusText(metric:snapshot:)`, `successRate(_:)`, and `cost(_:)`.

- [ ] **Step 1: Write failing configuration and formatter tests**

```swift
func testBaseURLNormalizationRemovesTrailingSlash() throws {
    let url = try AppConfiguration.normalizedBaseURL(" http://keeper.local:8318/ ")
    XCTAssertEqual(url.absoluteString, "http://keeper.local:8318")
}

func testBaseURLRejectsUnsupportedScheme() {
    XCTAssertThrowsError(try AppConfiguration.normalizedBaseURL("ftp://keeper.local"))
}

func testCompactNumbers() {
    XCTAssertEqual(UsageFormatter.compactNumber(999), "999")
    XCTAssertEqual(UsageFormatter.compactNumber(1_200), "1.2K")
    XCTAssertEqual(UsageFormatter.compactNumber(2_340_000), "2.3M")
    XCTAssertEqual(UsageFormatter.compactNumber(3_600_000_000), "3.6B")
}

func testSuccessRateUsesSuccessAndFailureCounts() {
    let snapshot = UsageSnapshot(requests: 4, successes: 3, failures: 1, tokens: 10, cost: 0.5, range: .today, timezone: nil, refreshedAt: .distantPast)
    XCTAssertEqual(UsageFormatter.successRate(snapshot), "75.0%")
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ConfigurationTests && swift test --filter UsageFormatterTests`

Expected: compile failure because the model and formatter types do not exist.

- [ ] **Step 3: Implement the focused model types and formatters**

Use `URLComponents` to require `http` or `https`, a non-empty host, and no query or fragment. Map `UsageRange` raw values directly to Keeper API values. Return `nil` cost when Keeper reports `cost_available: false`. Make zero total requests format as `0.0%`.

```swift
static func compactNumber(_ value: Int64) -> String {
    let thresholds: [(Double, String)] = [(1_000_000_000, "B"), (1_000_000, "M"), (1_000, "K")]
    for (threshold, suffix) in thresholds where Double(value) >= threshold {
        let scaled = Double(value) / threshold
        return String(format: scaled >= 10 ? "%.0f%@" : "%.1f%@", scaled, suffix)
    }
    return String(value)
}
```

- [ ] **Step 4: Run the model tests**

Run: `swift test --filter ConfigurationTests && swift test --filter UsageFormatterTests`

Expected: all configuration and formatting tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/CPAUsageMenuBar/Models Sources/CPAUsageMenuBar/Formatting Tests/CPAUsageMenuBarTests
git commit -m "feat: add usage models and formatting"
```

### Task 3: Persist Preferences and Credentials Safely

**Files:**
- Create: `Sources/CPAUsageMenuBar/Storage/PreferencesStore.swift`
- Create: `Sources/CPAUsageMenuBar/Storage/CredentialStore.swift`
- Create: `Tests/CPAUsageMenuBarTests/PreferencesStoreTests.swift`
- Create: `Tests/CPAUsageMenuBarTests/CredentialStoreTests.swift`

**Interfaces:**
- Produces: `protocol PreferencesStoring` with `load()`, `save(_:)`, and `clear()`.
- Produces: `final class PreferencesStore` backed by injected `UserDefaults`.
- Produces: `protocol CredentialStoring` with `read()`, `replace(with:)`, and `delete()`.
- Produces: `final class KeychainCredentialStore` using service `cn.winlio.cpausage` and account `active-credential`.

- [ ] **Step 1: Write failing isolated storage tests**

```swift
func testPreferencesRoundTrip() throws {
    let suiteName = "PreferencesStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = PreferencesStore(defaults: defaults)
    let configuration = AppConfiguration(baseURL: URL(string: "http://localhost:8318")!, authenticationType: .administratorPassword, refreshInterval: 60, menuBarMetric: .tokens, launchAtLogin: false)
    try store.save(configuration)
    XCTAssertEqual(try store.load(), configuration)
}
```

For Keychain tests, inject a `SecurityClient` closure bundle and assert the exact add, copy, update, and delete query dictionaries without touching the user's real Keychain.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PreferencesStoreTests && swift test --filter CredentialStoreTests`

Expected: compile failure because storage protocols and implementations do not exist.

- [ ] **Step 3: Implement preferences and Keychain adapters**

Encode configuration as JSON under `active-configuration`. For replacement, call `SecItemUpdate`; if it returns `errSecItemNotFound`, call `SecItemAdd`. Convert any other non-success `OSStatus` to `AppError.keychain(status:)` without including credential data.

- [ ] **Step 4: Run storage tests**

Run: `swift test --filter PreferencesStoreTests && swift test --filter CredentialStoreTests`

Expected: all storage tests pass and no real Keychain prompt appears.

- [ ] **Step 5: Commit**

```bash
git add Sources/CPAUsageMenuBar/Storage Tests/CPAUsageMenuBarTests
git commit -m "feat: persist settings and keychain credential"
```

### Task 4: Implement Keeper Authentication and Overview Loading

**Files:**
- Create: `Sources/CPAUsageMenuBar/Networking/KeeperAPIClient.swift`
- Create: `Tests/CPAUsageMenuBarTests/KeeperAPIClientTests.swift`

**Interfaces:**
- Consumes: `AppConfiguration`, `UsageRange`, `UsageSnapshot`, `AppError`.
- Produces: `protocol KeeperAPIClientProtocol: Sendable { func fetchOverview(configuration: AppConfiguration, credential: String, range: UsageRange) async throws -> UsageSnapshot }`.
- Produces: `actor KeeperAPIClient` using an ephemeral `URLSessionConfiguration` with an in-memory `HTTPCookieStorage`.

- [ ] **Step 1: Write failing URLProtocol-based API tests**

Test exact request behavior:

```swift
func testAdministratorUsesPasswordLoginAndAdminOverview() async throws {
    StubURLProtocol.enqueue(status: 204, headers: ["Set-Cookie": "cpa_usage_keeper_session=session; Path=/; HttpOnly"], body: Data())
    StubURLProtocol.enqueue(status: 200, body: overviewJSON)
    let snapshot = try await client.fetchOverview(configuration: adminConfiguration, credential: "secret", range: .today)
    XCTAssertEqual(StubURLProtocol.requests[0].url?.path, "/api/v1/auth/login")
    XCTAssertEqual(try requestJSON(0)["password"] as? String, "secret")
    XCTAssertEqual(StubURLProtocol.requests[1].url?.path, "/api/v1/usage/overview")
    XCTAssertEqual(snapshot.tokens, 1234)
}

func testAPIKeyUsesScopedEndpoints() async throws {
    // Assert /auth/api-key-login body key "apiKey" and /key-overview.
}

func testUnauthorizedOverviewReauthenticatesOnlyOnce() async throws {
    // Enqueue login 204, overview 401, login 204, overview 200; assert four requests.
}

func testRepeatedUnauthorizedStopsAfterOneRetry() async {
    // Enqueue login 204, overview 401, login 204, overview 401; assert AppError.authenticationFailed.
}
```

Also test `403`, timeout, malformed JSON, empty usage, unavailable cost, and cookie retention.

- [ ] **Step 2: Run API tests to verify they fail**

Run: `swift test --filter KeeperAPIClientTests`

Expected: compile failure because `KeeperAPIClient` and its protocol do not exist.

- [ ] **Step 3: Implement login, overview decoding, and one retry**

Define private Codable payloads matching Keeper fields:

```swift
private struct OverviewResponse: Decodable {
    let usage: Usage
    let summary: Summary?
    let timezone: String?
}

private struct Usage: Decodable {
    let totalRequests: Int64
    let successCount: Int64
    let failureCount: Int64
    let totalTokens: Int64
    enum CodingKeys: String, CodingKey {
        case totalRequests = "total_requests", successCount = "success_count"
        case failureCount = "failure_count", totalTokens = "total_tokens"
    }
}

private struct Summary: Decodable {
    let totalCost: Double
    let costAvailable: Bool
    enum CodingKeys: String, CodingKey {
        case totalCost = "total_cost", costAvailable = "cost_available"
    }
}
```

Set `Content-Type: application/json` and `X-CPA-Usage-Keeper-Request: fetch` on login POST requests. Use a 15-second request timeout. Never interpolate a credential or body into error text.

- [ ] **Step 4: Run API tests**

Run: `swift test --filter KeeperAPIClientTests`

Expected: all authentication, retry, decoding, and error tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/CPAUsageMenuBar/Networking Tests/CPAUsageMenuBarTests/KeeperAPIClientTests.swift
git commit -m "feat: add keeper authentication client"
```

### Task 5: Coordinate Refreshes and Preserve Last-Known-Good Data

**Files:**
- Create: `Sources/CPAUsageMenuBar/Refresh/UsageRefreshModel.swift`
- Create: `Tests/CPAUsageMenuBarTests/UsageRefreshModelTests.swift`

**Interfaces:**
- Consumes: `PreferencesStoring`, `CredentialStoring`, `KeeperAPIClientProtocol`.
- Produces: `@MainActor final class UsageRefreshModel: ObservableObject`.
- Publishes: `configuration`, `selectedRange`, `selectedSnapshot`, `todaySnapshot`, `isRefreshing`, and `error`.
- Produces: `start()`, `stop()`, `refresh(force:) async`, `selectRange(_:) async`, `validateAndSave(configuration:credential:) async throws`, and `retryAuthentication() async`.

- [ ] **Step 1: Write failing async refresh tests with fakes**

```swift
@MainActor
func testTransientFailureKeepsLastKnownGoodSnapshot() async {
    api.results = [.success(todaySnapshot), .failure(AppError.serviceUnavailable)]
    await model.refresh(force: true)
    await model.refresh(force: true)
    XCTAssertEqual(model.todaySnapshot, todaySnapshot)
    XCTAssertEqual(model.error, .serviceUnavailable)
}

@MainActor
func testTodayRangeSharesOneRequestForPopoverAndStatusItem() async {
    model.selectedRange = .today
    await model.refresh(force: true)
    XCTAssertEqual(api.requestedRanges, [.today])
}

@MainActor
func testCandidateConfigurationIsPersistedOnlyAfterValidation() async throws {
    api.results = [.success(todaySnapshot)]
    try await model.validateAndSave(configuration: candidate, credential: "new-secret")
    XCTAssertEqual(try preferences.load(), candidate)
    XCTAssertEqual(try credentials.read(), "new-secret")
}
```

Also test failed validation leaves old configuration untouched, stale-on-open refresh behavior, duplicate refresh coalescing, and authentication retry suspension.

- [ ] **Step 2: Run refresh tests to verify they fail**

Run: `swift test --filter UsageRefreshModelTests`

Expected: compile failure because `UsageRefreshModel` does not exist.

- [ ] **Step 3: Implement the main-actor state model**

Use one in-flight `Task` per range, a repeating `Timer` scheduled from `start()`, and snapshot cache keyed by `UsageRange`. When the selected range is not Today, refresh Today and the selected range concurrently with `async let`. Update published properties only on the main actor.

For settings validation, call the candidate API first, then replace the credential, save preferences, rebuild timer state, and publish the validated snapshot. If credential persistence fails, do not save preferences.

- [ ] **Step 4: Run refresh tests**

Run: `swift test --filter UsageRefreshModelTests`

Expected: all refresh, caching, coalescing, and atomic-settings tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/CPAUsageMenuBar/Refresh Tests/CPAUsageMenuBarTests/UsageRefreshModelTests.swift
git commit -m "feat: coordinate usage refresh state"
```

### Task 6: Build the Native Popover, Settings, and Status Item

**Files:**
- Create: `Sources/CPAUsageMenuBar/Views/MetricCard.swift`
- Create: `Sources/CPAUsageMenuBar/Views/UsagePopoverView.swift`
- Create: `Sources/CPAUsageMenuBar/Views/SettingsView.swift`
- Modify: `Sources/CPAUsageMenuBar/App/AppDelegate.swift`
- Create: `Tests/CPAUsageMenuBarTests/StatusItemPresentationTests.swift`

**Interfaces:**
- Consumes: `UsageRefreshModel`, `UsageFormatter`, and storage/API implementations.
- Produces: `StatusItemPresentation.title(metric:snapshot:)` and `imageName(hasError:)` as pure functions.
- Produces: a 360-point-wide SwiftUI popover and a separate settings window.

- [ ] **Step 1: Write failing status presentation tests**

```swift
func testTokenMetricUsesCompactTodayValue() {
    XCTAssertEqual(StatusItemPresentation.title(metric: .tokens, snapshot: snapshot(tokens: 2_340_000)), "2.3M")
}

func testIconOnlyHasNoTitle() {
    XCTAssertEqual(StatusItemPresentation.title(metric: .iconOnly, snapshot: nil), "")
}

func testErrorUsesWarningSymbol() {
    XCTAssertEqual(StatusItemPresentation.imageName(hasError: true), "exclamationmark.circle")
}
```

- [ ] **Step 2: Run presentation tests to verify they fail**

Run: `swift test --filter StatusItemPresentationTests`

Expected: compile failure because `StatusItemPresentation` does not exist.

- [ ] **Step 3: Implement status item and AppKit lifecycle**

In `applicationDidFinishLaunching`, construct real stores/client/model, create `NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)`, assign an SF Symbol template image, attach the click action, and start the refresh model. Host `UsagePopoverView` in `NSPopover` using `NSHostingController`.

Observe model changes with Combine and update title/image on the main actor. Retain cancellables in `AppDelegate`.

- [ ] **Step 4: Implement the SwiftUI popover and settings view**

Use a segmented picker for the four ranges, four `MetricCard` views, concise inline errors, refresh/settings/browser buttons, and setup content when configuration is absent. Open the dashboard with `NSWorkspace.shared.open(configuration.baseURL)`.

The settings form uses `SecureField`, shows an HTTP warning, disables Save during validation, and displays validation failures without closing. It never pre-fills the stored credential; leaving the credential blank while editing non-auth settings means reuse the current stored credential.

- [ ] **Step 5: Run tests and compile the executable**

Run: `swift test --filter StatusItemPresentationTests && swift test && swift build`

Expected: all tests pass and the native executable compiles.

- [ ] **Step 6: Commit**

```bash
git add Sources/CPAUsageMenuBar/App Sources/CPAUsageMenuBar/Views Tests/CPAUsageMenuBarTests/StatusItemPresentationTests.swift
git commit -m "feat: add native menu bar interface"
```

### Task 7: Add Launch at Login and Build a Standard App Bundle

**Files:**
- Create: `Sources/CPAUsageMenuBar/System/LaunchAtLoginController.swift`
- Create: `Tests/CPAUsageMenuBarTests/LaunchAtLoginControllerTests.swift`
- Create: `Resources/Info.plist`
- Create: `scripts/build-app.sh`
- Create: `.gitignore`

**Interfaces:**
- Produces: `protocol LaunchAtLoginControlling` with `isEnabled` and `setEnabled(_:) throws`.
- Produces: `final class LaunchAtLoginController` wrapping `SMAppService.mainApp` on macOS 13+.
- Produces: `dist/CPA Usage.app` from `scripts/build-app.sh`.

- [ ] **Step 1: Write failing launch-at-login adapter tests**

Inject register/unregister/status closures and assert enabling calls register once, disabling calls unregister once, and service errors map to `AppError.launchAtLogin`.

- [ ] **Step 2: Run launch tests to verify they fail**

Run: `swift test --filter LaunchAtLoginControllerTests`

Expected: compile failure because the controller does not exist.

- [ ] **Step 3: Implement the ServiceManagement adapter**

Use `SMAppService.mainApp.register()` and `.unregister()`. Treat `.enabled` as enabled and all other statuses as disabled for the toggle. Surface registration failure in settings without altering the saved preference.

- [ ] **Step 4: Add bundle metadata and build script**

`Info.plist` must set:

```xml
<key>CFBundleIdentifier</key><string>cn.winlio.cpausage</string>
<key>CFBundleName</key><string>CPA Usage</string>
<key>CFBundleExecutable</key><string>CPAUsageMenuBar</string>
<key>LSUIElement</key><true/>
<key>NSHumanReadableCopyright</key><string>CPA Usage Menu Bar</string>
```

`scripts/build-app.sh` must run `swift build -c release`, recreate `dist/CPA Usage.app/Contents/MacOS`, copy the release executable and `Info.plist`, then ad-hoc sign with `codesign --force --deep --sign -` when `codesign` is available.

- [ ] **Step 5: Run tests and build the app bundle**

Run: `swift test --filter LaunchAtLoginControllerTests && ./scripts/build-app.sh && test -x 'dist/CPA Usage.app/Contents/MacOS/CPAUsageMenuBar'`

Expected: tests pass and the bundle executable exists.

- [ ] **Step 6: Commit**

```bash
git add Sources/CPAUsageMenuBar/System Tests/CPAUsageMenuBarTests/LaunchAtLoginControllerTests.swift Resources scripts .gitignore
git commit -m "build: package macOS menu bar application"
```

### Task 8: Document, Verify Against the Real Keeper, and Finish

**Files:**
- Create: `README.md`
- Modify only if verification reveals a defect: implementation or test files from earlier tasks.

**Interfaces:**
- Produces: clear build, installation, configuration, authentication, security, and troubleshooting instructions.

- [ ] **Step 1: Write README usage instructions**

Document:

- `swift test` and `./scripts/build-app.sh`.
- Moving `dist/CPA Usage.app` to `/Applications`.
- First-run URL and authentication-type configuration.
- Difference between Administrator Password and CPA API Key.
- Keychain storage behavior.
- HTTP LAN credential warning.
- Status metric and refresh settings.
- How to quit and disable launch at login.

- [ ] **Step 2: Run the complete automated verification**

Run: `swift test && ./scripts/build-app.sh && plutil -lint 'dist/CPA Usage.app/Contents/Info.plist' && codesign --verify --deep --strict 'dist/CPA Usage.app'`

Expected: all tests pass, bundle builds, plist is valid, and signature verifies.

- [ ] **Step 3: Verify authentication and overview calls against the configured LAN instance**

Launch the built application, enter the approved LAN URL and administrator password through the settings UI, and confirm:

- Validation succeeds.
- Today's Token count appears in the menu bar.
- Popover metrics match the Keeper dashboard for Today.
- 24 Hours, 7 Days, and 30 Days load.
- “Open Dashboard” opens the configured URL.
- The credential does not appear in Console output or repository files.

Do not commit or print the supplied administrator password.

- [ ] **Step 4: Run repository safety checks**

Run: `git status --short && git grep -n 'cpa_usage_keeper_session=' -- Sources Tests Resources scripts README.md || true`

Expected: only intentional README or fix changes are uncommitted; no session cookie is present in source-controlled application files. Separately inspect the staged diff before committing to ensure no credential supplied at runtime appears in it.

- [ ] **Step 5: Commit documentation and any verified fixes**

```bash
git add README.md Sources Tests scripts Resources Package.swift .gitignore
git commit -m "docs: add CPA menu bar setup guide"
```

- [ ] **Step 6: Record final evidence**

Run: `git status --short && git log --oneline -10 && swift test`

Expected: clean worktree and a final passing test suite.
