# Token Milestone Celebrations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add opt-in Token milestone celebrations with three visual styles, multi-display playback, meme copy, optional sound, and a settings preview that never changes real milestone state.

**Architecture:** A pure `MilestoneTracker` observes successful Today snapshots and persists non-secret daily state. A `CelebrationCoordinator` converts milestone events or synthetic previews into one synchronized session, then a window controller creates mouse-transparent overlay windows for every display and hosts one of three SwiftUI Canvas-based views.

**Tech Stack:** Swift 6.3, macOS 13+, SwiftUI Canvas and TimelineView, AppKit `NSPanel`/`NSScreen`/`NSSound`, Foundation `UserDefaults`, Swift Package Manager, Swift Testing.

## Global Constraints

- Celebrations default to Off for new and existing installations.
- Fixed milestones are 10M, 50M, and 100M Tokens; after 100M, trigger every additional 100M.
- Never backfill milestones at startup, after sleep, after a day change, or after an identity change.
- If one refresh crosses multiple milestones, celebrate only the highest.
- Show one synchronized style and meme on every connected display.
- Overlay windows must not activate the app, take focus, or intercept mouse input.
- Sound defaults to off and plays only once per celebration.
- Preview uses a synthetic 50M milestone and never reads or mutates real tracker state.
- Repeated preview clicks and simultaneous milestone events never stack overlays.
- Do not add third-party dependencies.

---

## File Map

- `Sources/CPAUsageMenuBar/Models/AppConfiguration.swift`: celebration style and sound settings with backward-compatible decoding.
- `Sources/CPAUsageMenuBar/Milestones/TokenMilestone.swift`: milestone and persisted state value types.
- `Sources/CPAUsageMenuBar/Milestones/MilestoneTracker.swift`: pure daily threshold state machine.
- `Sources/CPAUsageMenuBar/Milestones/MilestoneStateStore.swift`: non-secret state persistence.
- `Sources/CPAUsageMenuBar/Celebrations/CelebrationSession.swift`: immutable style/text/seed/timing session shared by all displays.
- `Sources/CPAUsageMenuBar/Celebrations/MemeCopyProvider.swift`: deterministic meme selection and milestone formatting.
- `Sources/CPAUsageMenuBar/Celebrations/CelebrationCoordinator.swift`: real-event and preview orchestration.
- `Sources/CPAUsageMenuBar/Celebrations/CelebrationWindowController.swift`: transparent multi-display window lifecycle.
- `Sources/CPAUsageMenuBar/Celebrations/CelebrationSoundPlayer.swift`: one system sound per session.
- `Sources/CPAUsageMenuBar/Views/Celebrations/CinematicFireworksView.swift`: full-screen Canvas fireworks.
- `Sources/CPAUsageMenuBar/Views/Celebrations/AchievementToastView.swift`: top achievement card and confetti.
- `Sources/CPAUsageMenuBar/Views/Celebrations/RetroAchievementView.swift`: pixel achievement panel and particles.
- `Sources/CPAUsageMenuBar/Views/Celebrations/CelebrationRootView.swift`: style router and shared timing.
- `Sources/CPAUsageMenuBar/Views/SettingsView.swift`: celebration settings and preview button.
- `Sources/CPAUsageMenuBar/Refresh/UsageRefreshModel.swift`: Today snapshot tracking and preview API.
- `Sources/CPAUsageMenuBar/App/AppDelegate.swift`: dependency construction and sleep/wake baseline reset.
- `Tests/CPAUsageMenuBarTests/*`: focused tracker, persistence, copy, coordinator, window configuration, settings compatibility, and integration tests.

### Task 1: Add Backward-Compatible Celebration Settings

**Files:**
- Modify: `Sources/CPAUsageMenuBar/Models/AppConfiguration.swift`
- Modify: `Tests/CPAUsageMenuBarTests/ConfigurationTests.swift`
- Modify: `Tests/CPAUsageMenuBarTests/PreferencesStoreTests.swift`

**Interfaces:**
- Produces: `enum CelebrationStyle: String, Codable, CaseIterable, Sendable { case off, cinematic, achievementToast, retro, random }`.
- Extends: `AppConfiguration` with `celebrationStyle: CelebrationStyle` and `celebrationSoundEnabled: Bool`.
- Preserves: decoding existing saved configurations that lack both new keys, defaulting to `.off` and `false`.

- [ ] **Step 1: Write failing compatibility tests**

```swift
@Test
func oldConfigurationDecodesWithCelebrationsOff() throws {
    let data = Data(#"{"baseURL":"http:\/\/keeper.local:8080","authenticationType":"administratorPassword","refreshInterval":60,"menuBarMetric":"tokens","launchAtLogin":false}"#.utf8)
    let configuration = try JSONDecoder().decode(AppConfiguration.self, from: data)
    #expect(configuration.celebrationStyle == .off)
    #expect(configuration.celebrationSoundEnabled == false)
}

@Test
func celebrationConfigurationRoundTrips() throws {
    let configuration = AppConfiguration(
        baseURL: URL(string: "http://keeper.local:8080")!,
        authenticationType: .administratorPassword,
        refreshInterval: 60,
        menuBarMetric: .tokens,
        launchAtLogin: false,
        celebrationStyle: .random,
        celebrationSoundEnabled: true
    )
    let decoded = try JSONDecoder().decode(AppConfiguration.self, from: JSONEncoder().encode(configuration))
    #expect(decoded == configuration)
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `swift test --filter 'oldConfigurationDecodesWithCelebrationsOff|celebrationConfigurationRoundTrips'`

Expected: compile failure because `CelebrationStyle` and the new properties do not exist.

- [ ] **Step 3: Implement custom Codable compatibility**

Add the enum with Chinese `title` values and implement `init(from:)` using `decodeIfPresent`:

```swift
celebrationStyle = try container.decodeIfPresent(CelebrationStyle.self, forKey: .celebrationStyle) ?? .off
celebrationSoundEnabled = try container.decodeIfPresent(Bool.self, forKey: .celebrationSoundEnabled) ?? false
```

Retain the memberwise initializer with default arguments `.off` and `false` so existing call sites compile unchanged.

- [ ] **Step 4: Run the configuration suite**

Run: `swift test --filter 'ConfigurationTests|PreferencesStoreTests'`

Expected: test target builds with all compatibility assertions passing on a full Swift Testing toolchain.

- [ ] **Step 5: Commit**

```bash
git add Sources/CPAUsageMenuBar/Models/AppConfiguration.swift Tests/CPAUsageMenuBarTests/ConfigurationTests.swift Tests/CPAUsageMenuBarTests/PreferencesStoreTests.swift
git commit -m "feat: add celebration preferences"
```

### Task 2: Implement the Daily Milestone State Machine

**Files:**
- Create: `Sources/CPAUsageMenuBar/Milestones/TokenMilestone.swift`
- Create: `Sources/CPAUsageMenuBar/Milestones/MilestoneTracker.swift`
- Create: `Sources/CPAUsageMenuBar/Milestones/MilestoneStateStore.swift`
- Create: `Tests/CPAUsageMenuBarTests/MilestoneTrackerTests.swift`
- Create: `Tests/CPAUsageMenuBarTests/MilestoneStateStoreTests.swift`

**Interfaces:**
- Produces: `struct TokenMilestone: Equatable, Hashable, Codable, Sendable { let tokens: Int64 }`.
- Produces: `struct MilestoneIdentity: Equatable, Codable, Sendable { let baseURL: String; let authenticationType: AuthenticationType }`.
- Produces: `struct MilestoneTrackerState: Equatable, Codable, Sendable` with date key, identity, last observed Tokens, celebrated milestone set, and `requiresBaseline`.
- Produces: `protocol MilestoneTracking` with `observe(tokens:date:identity:calendar:)`, `requireBaseline()`, and a readable `state`.
- Produces: `struct MilestoneTracker: MilestoneTracking` with `mutating func observe(tokens: Int64, date: Date, identity: MilestoneIdentity, calendar: Calendar) -> TokenMilestone?` and `mutating func requireBaseline()`.
- Produces: `protocol MilestoneStateStoring` with `load()`, `save(_:)`, and `clear()`.

- [ ] **Step 1: Write failing threshold tests**

Cover the required transitions with explicit values:

```swift
@Test
func firstSnapshotOnlyEstablishesBaseline() {
    var tracker = MilestoneTracker()
    #expect(tracker.observe(tokens: 9_000_000, date: day, identity: identity, calendar: calendar) == nil)
}

@Test
func crossingTenMillionTriggersOnce() {
    var tracker = trackerWithBaseline(9_000_000)
    #expect(tracker.observe(tokens: 10_000_000, date: day, identity: identity, calendar: calendar) == TokenMilestone(tokens: 10_000_000))
    #expect(tracker.observe(tokens: 11_000_000, date: day, identity: identity, calendar: calendar) == nil)
}

@Test
func crossingMultipleMilestonesUsesHighest() {
    var tracker = trackerWithBaseline(9_000_000)
    #expect(tracker.observe(tokens: 120_000_000, date: day, identity: identity, calendar: calendar) == TokenMilestone(tokens: 100_000_000))
}

@Test
func repeatingMilestonesContinueEveryHundredMillion() {
    var tracker = trackerWithBaseline(190_000_000)
    #expect(tracker.observe(tokens: 205_000_000, date: day, identity: identity, calendar: calendar) == TokenMilestone(tokens: 200_000_000))
}
```

Also test 50M, exact 100M, 300M, rollback, day change, identity change, `requireBaseline()`, restart from saved state, and highest-crossed deduplication.

- [ ] **Step 2: Run tracker tests and verify RED**

Run: `swift test --filter MilestoneTrackerTests`

Expected: compile failure because milestone types do not exist.

- [ ] **Step 3: Implement threshold calculation**

Use one helper that returns ordered thresholds between two values:

```swift
static func thresholds(upTo tokens: Int64) -> [Int64] {
    var values: [Int64] = [10_000_000, 50_000_000, 100_000_000]
    if tokens >= 200_000_000 {
        for value in stride(from: Int64(200_000_000), through: tokens, by: Int64(100_000_000)) {
            values.append(value)
        }
    }
    return values
}
```

Filter values where `previous < threshold && threshold <= current`, remove celebrated thresholds, and return the maximum. Always persist the new observed value. A date or identity mismatch clears celebrated values and sets a baseline without emitting.

- [ ] **Step 4: Implement isolated persistence and tests**

Store JSON under `token-milestone-state-v1` in injected `UserDefaults`. Invalid data returns `nil` and removes the corrupt value rather than breaking refresh.

- [ ] **Step 5: Run milestone tests**

Run: `swift test --filter 'MilestoneTrackerTests|MilestoneStateStoreTests'`

Expected: milestone and persistence test target builds successfully.

- [ ] **Step 6: Commit**

```bash
git add Sources/CPAUsageMenuBar/Milestones Tests/CPAUsageMenuBarTests/MilestoneTrackerTests.swift Tests/CPAUsageMenuBarTests/MilestoneStateStoreTests.swift
git commit -m "feat: track daily token milestones"
```

### Task 3: Build Celebration Sessions and Meme Copy

**Files:**
- Create: `Sources/CPAUsageMenuBar/Celebrations/CelebrationSession.swift`
- Create: `Sources/CPAUsageMenuBar/Celebrations/MemeCopyProvider.swift`
- Create: `Tests/CPAUsageMenuBarTests/MemeCopyProviderTests.swift`

**Interfaces:**
- Produces: `struct CelebrationCopy: Equatable, Sendable { let eyebrow: String; let headline: String; let detail: String; let badge: String? }`.
- Produces: `struct CelebrationSession: Equatable, Sendable` with ID, milestone, resolved non-random style, copy, seed, start time, and duration.
- Produces: `protocol MemeCopyProviding { func copy(for: TokenMilestone, style: CelebrationStyle, seed: UInt64) -> CelebrationCopy }`.
- Produces: `MemeCopyProvider.compactMilestone(_:)`.

- [ ] **Step 1: Write failing copy tests**

```swift
@Test
func milestoneFormattingUsesCompactValues() {
    #expect(MemeCopyProvider.compactMilestone(10_000_000) == "10M")
    #expect(MemeCopyProvider.compactMilestone(100_000_000) == "100M")
    #expect(MemeCopyProvider.compactMilestone(1_200_000_000) == "1.2B")
}

@Test
func sameSeedProducesSameCopy() {
    let provider = MemeCopyProvider()
    #expect(provider.copy(for: .init(tokens: 50_000_000), style: .cinematic, seed: 42) == provider.copy(for: .init(tokens: 50_000_000), style: .cinematic, seed: 42))
}
```

Assert every fixed style produces non-empty headline/detail and includes the formatted milestone in either eyebrow or headline.

- [ ] **Step 2: Run copy tests and verify RED**

Run: `swift test --filter MemeCopyProviderTests`

Expected: compile failure because session and copy types do not exist.

- [ ] **Step 3: Implement seeded copy pools**

Create separate headline/detail/badge pools for cinematic, achievement, and retro styles. Select indices from a local deterministic generator initialized with the session seed. Do not use global randomness inside views.

- [ ] **Step 4: Run copy tests**

Run: `swift test --filter MemeCopyProviderTests`

Expected: copy and formatting assertions build successfully.

- [ ] **Step 5: Commit**

```bash
git add Sources/CPAUsageMenuBar/Celebrations/CelebrationSession.swift Sources/CPAUsageMenuBar/Celebrations/MemeCopyProvider.swift Tests/CPAUsageMenuBarTests/MemeCopyProviderTests.swift
git commit -m "feat: add milestone meme sessions"
```

### Task 4: Create Multi-Display Window and Coordination Infrastructure

**Files:**
- Create: `Sources/CPAUsageMenuBar/Celebrations/CelebrationWindowController.swift`
- Create: `Sources/CPAUsageMenuBar/Celebrations/CelebrationCoordinator.swift`
- Create: `Sources/CPAUsageMenuBar/Celebrations/CelebrationSoundPlayer.swift`
- Create: `Tests/CPAUsageMenuBarTests/CelebrationCoordinatorTests.swift`
- Create: `Tests/CPAUsageMenuBarTests/CelebrationWindowConfigurationTests.swift`

**Interfaces:**
- Produces: `protocol CelebrationPresenting { var isPresenting: Bool { get }; func present(_ session: CelebrationSession); func dismiss() }`.
- Produces: `protocol CelebrationSoundPlaying { func play() }`.
- Produces: `@MainActor final class CelebrationCoordinator` with `celebrate(_:configuration:)`, `preview(style:soundEnabled:)`, and `dismiss()`.
- Produces: `CelebrationPanelConfiguration` pure value describing level, opacity, mouse behavior, activation behavior, and screen frame for testability.

- [ ] **Step 1: Write failing coordinator tests**

Use fake presenter, sound player, copy provider, and clock:

```swift
@MainActor
@Test
func previewUsesSyntheticFiftyMillionWithoutTracker() {
    coordinator.preview(style: .retro, soundEnabled: false)
    #expect(presenter.sessions.single?.milestone.tokens == 50_000_000)
}

@MainActor
@Test
func soundPlaysOnceForMultiDisplayPresentation() {
    coordinator.celebrate(.init(tokens: 100_000_000), configuration: configuration(style: .cinematic, sound: true))
    #expect(soundPlayer.playCount == 1)
}

@MainActor
@Test
func activePresentationIgnoresSecondRequest() {
    coordinator.preview(style: .cinematic, soundEnabled: false)
    coordinator.preview(style: .retro, soundEnabled: false)
    #expect(presenter.sessions.count == 1)
}
```

- [ ] **Step 2: Run coordinator tests and verify RED**

Run: `swift test --filter CelebrationCoordinatorTests`

Expected: compile failure because coordinator interfaces do not exist.

- [ ] **Step 3: Implement coordinator and system sound**

Resolve `.random` once with the session seed. Use style durations 4.5, 5.0, and 4.0 seconds. Use `NSSound(named: "Glass")?.play()` in the production sound player. Schedule one dismissal task owned by the coordinator.

- [ ] **Step 4: Implement window configuration tests**

Assert each screen creates one panel with:

```swift
panel.styleMask = [.borderless, .nonactivatingPanel]
panel.backgroundColor = .clear
panel.isOpaque = false
panel.hasShadow = false
panel.ignoresMouseEvents = true
panel.level = .statusBar
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
```

The window controller uses an injected screen-frame provider in tests and `NSScreen.screens.map(\.frame)` in production.

- [ ] **Step 5: Run coordinator/window tests**

Run: `swift test --filter 'CelebrationCoordinatorTests|CelebrationWindowConfigurationTests'`

Expected: coordination and panel configuration tests build successfully.

- [ ] **Step 6: Commit**

```bash
git add Sources/CPAUsageMenuBar/Celebrations Tests/CPAUsageMenuBarTests/CelebrationCoordinatorTests.swift Tests/CPAUsageMenuBarTests/CelebrationWindowConfigurationTests.swift
git commit -m "feat: coordinate multi-display celebrations"
```

### Task 5: Implement Three Canvas-Based Visual Styles

**Files:**
- Create: `Sources/CPAUsageMenuBar/Views/Celebrations/CelebrationRootView.swift`
- Create: `Sources/CPAUsageMenuBar/Views/Celebrations/CinematicFireworksView.swift`
- Create: `Sources/CPAUsageMenuBar/Views/Celebrations/AchievementToastView.swift`
- Create: `Sources/CPAUsageMenuBar/Views/Celebrations/RetroAchievementView.swift`
- Create: `Sources/CPAUsageMenuBar/Views/Celebrations/SeededParticleField.swift`
- Create: `Tests/CPAUsageMenuBarTests/SeededParticleFieldTests.swift`

**Interfaces:**
- Produces: `struct SeededParticle: Equatable, Sendable` and `SeededParticleField.particles(seed:count:bounds:)`.
- Produces: `CelebrationRootView(session:)` routing only resolved `.cinematic`, `.achievementToast`, or `.retro` styles.

- [ ] **Step 1: Write failing deterministic particle tests**

```swift
@Test
func sameSeedCreatesSameParticles() {
    let first = SeededParticleField.particles(seed: 42, count: 40, bounds: CGSize(width: 800, height: 600))
    let second = SeededParticleField.particles(seed: 42, count: 40, bounds: CGSize(width: 800, height: 600))
    #expect(first == second)
}

@Test
func particlesStayWithinInitialBounds() {
    let particles = SeededParticleField.particles(seed: 7, count: 100, bounds: CGSize(width: 400, height: 300))
    #expect(particles.allSatisfy { (0...400).contains($0.origin.x) && (0...300).contains($0.origin.y) })
}
```

- [ ] **Step 2: Run particle tests and verify RED**

Run: `swift test --filter SeededParticleFieldTests`

Expected: compile failure because particle types do not exist.

- [ ] **Step 3: Implement shared particle generation**

Generate origin, velocity, color index, size, delay, and lifetime from the deterministic generator. Views animate particles by elapsed time from the shared session start timestamp.

- [ ] **Step 4: Implement the three views**

- Cinematic: full-screen subtle dark veil, 100–140 particles, large centered headline/detail/badge, fade in/out.
- Achievement toast: top-center material card, slide/spring entrance, localized confetti field, automatic fade.
- Retro: pixel-styled bordered panel, monospaced typography, block-shadow offset, scan lines, pixel particles, humorous progress bar.

Use `ViewThatFits` and minimum scale factors so copy remains visible on small or scaled displays. Apply safe-area padding to every text container.

- [ ] **Step 5: Run particle tests and compile views**

Run: `swift test --filter SeededParticleFieldTests && swift build`

Expected: deterministic tests build and the application compiles.

- [ ] **Step 6: Commit**

```bash
git add Sources/CPAUsageMenuBar/Views/Celebrations Tests/CPAUsageMenuBarTests/SeededParticleFieldTests.swift
git commit -m "feat: add milestone celebration visuals"
```

### Task 6: Integrate Tracking, Sleep/Wake, Settings, and Preview

**Files:**
- Modify: `Sources/CPAUsageMenuBar/Refresh/UsageRefreshModel.swift`
- Modify: `Sources/CPAUsageMenuBar/Views/SettingsView.swift`
- Modify: `Sources/CPAUsageMenuBar/App/AppDelegate.swift`
- Modify: `Tests/CPAUsageMenuBarTests/UsageRefreshModelTests.swift`
- Create: `Tests/CPAUsageMenuBarTests/CelebrationSettingsTests.swift`

**Interfaces:**
- Extends: `UsageRefreshModel` initializer with `MilestoneTracker`, `MilestoneStateStoring`, and `CelebrationCoordinator` dependencies.
- Produces: `previewCelebration(style:soundEnabled:)` and `requireMilestoneBaseline()`.
- Settings preview consumes unsaved form values and never calls `validateAndSave`.

- [ ] **Step 1: Write failing refresh integration tests**

```swift
@MainActor
@Test
func successfulTodayRefreshForwardsMilestone() async {
    let tracker = FakeMilestoneTracker(events: [.init(tokens: 50_000_000)])
    await model.refresh(force: true)
    #expect(coordinator.milestones == [.init(tokens: 50_000_000)])
}

@MainActor
@Test
func failedRefreshDoesNotAdvanceTracker() async {
    await model.refresh(force: true)
    #expect(tracker.observations.isEmpty)
}

@MainActor
@Test
func previewDoesNotCallTrackerOrStateStore() {
    model.previewCelebration(style: .retro, soundEnabled: true)
    #expect(tracker.observations.isEmpty)
    #expect(stateStore.saveCount == 0)
}
```

- [ ] **Step 2: Run integration tests and verify RED**

Run: `swift test --filter 'UsageRefreshModelTests|CelebrationSettingsTests'`

Expected: compile failure because milestone and preview dependencies are not integrated.

- [ ] **Step 3: Integrate successful Today snapshots**

After the Today API request succeeds, build `MilestoneIdentity` from normalized base URL and authentication type, call tracker, save resulting state, and call coordinator only when style is not Off. Milestone tracking errors are swallowed after retaining the successful usage snapshot.

When settings validate successfully and identity changes, call `requireMilestoneBaseline()` before starting the next refresh.

- [ ] **Step 4: Add sleep/wake baseline reset**

In `AppDelegate`, observe `NSWorkspace.didWakeNotification` and call `model.requireMilestoneBaseline()`. Remove the observer at termination.

- [ ] **Step 5: Add settings controls and preview**

Add a “Token 里程碑彩蛋” section with style picker, sound toggle, and preview button. Preview is disabled for Off or while the coordinator reports an active presentation. Pass the current unsaved style and sound values to `model.previewCelebration`.

Do not close the settings window for preview. Display preview errors inline without changing validation state.

- [ ] **Step 6: Run integration tests and build**

Run: `swift test --filter 'UsageRefreshModelTests|CelebrationSettingsTests' && swift build`

Expected: test target and application compile successfully.

- [ ] **Step 7: Commit**

```bash
git add Sources/CPAUsageMenuBar/Refresh/UsageRefreshModel.swift Sources/CPAUsageMenuBar/Views/SettingsView.swift Sources/CPAUsageMenuBar/App/AppDelegate.swift Tests/CPAUsageMenuBarTests/UsageRefreshModelTests.swift Tests/CPAUsageMenuBarTests/CelebrationSettingsTests.swift
git commit -m "feat: integrate milestone celebrations"
```

### Task 7: Document, Manually Verify, Build, and Publish

**Files:**
- Modify: `README.md`
- Modify only if verification reveals a defect: celebration implementation or tests.

**Interfaces:**
- Produces: public documentation for enabling, previewing, disabling, and understanding milestone behavior.

- [ ] **Step 1: Update README**

Document that celebrations are disabled by default, list all styles and thresholds, explain no-backfill behavior, explain all-display playback, and describe the preview and sound controls.

- [ ] **Step 2: Run complete automated verification**

Run:

```bash
swift test
./scripts/build-app.sh
plutil -lint "dist/CPA Usage.app/Contents/Info.plist"
codesign --verify --deep --strict "dist/CPA Usage.app"
git diff --check
```

Expected: all commands exit 0. On the standalone Command Line Tools environment, record that Swift Testing sources compile even if the runner does not enumerate them.

- [ ] **Step 3: Run manual preview matrix**

Using the built application:

- Preview Cinematic with sound off and on.
- Preview Achievement Toast.
- Preview Retro Achievement.
- Preview Random twice and confirm one synchronized style per session.
- Confirm every connected display receives an overlay.
- Confirm mouse clicks pass through and focus stays in the active app.
- Confirm repeated preview clicks do not stack.
- Confirm animations auto-dismiss.

- [ ] **Step 4: Verify tracker behavior without consuming real usage**

Use injected test snapshots or a local debug harness to exercise 9M→10M, 49M→50M, 99M→100M, 190M→200M, restart, day change, sleep baseline, and identity change. Never modify Keeper data.

- [ ] **Step 5: Scan repository safety**

Run:

```bash
git grep -nE 'cpa_usage_keeper_session=|active-credential.*(password|api.?key)' -- . || true
git diff --cached --check
```

Expected: no supplied credential appears.

- [ ] **Step 6: Commit documentation and publish**

```bash
git add README.md Sources Tests
git commit -m "docs: explain token milestone celebrations"
git push origin HEAD:main
```

- [ ] **Step 7: Rebuild and relaunch the current app**

Run:

```bash
pkill -x CPAUsageMenuBar || true
open "$PWD/dist/CPA Usage.app"
```

Expected: the application runs with the existing Keeper configuration and celebrations remain Off until explicitly enabled.
