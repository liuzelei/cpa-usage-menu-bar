import Foundation
import Testing
@testable import CPAUsageMenuBar

private final class FakePreferencesStore: PreferencesStoring {
    var value: AppConfiguration?
    func load() throws -> AppConfiguration? { value }
    func save(_ configuration: AppConfiguration) throws { value = configuration }
    func clear() { value = nil }
}

private final class FakeCredentialStore: CredentialStoring {
    var value: String?
    func read() throws -> String? { value }
    func replace(with credential: String) throws { value = credential }
    func delete() throws { value = nil }
}

private actor FakeKeeperAPI: KeeperAPIClientProtocol {
    var results: [Result<UsageSnapshot, AppError>]
    var ranges: [UsageRange] = []

    init(results: [Result<UsageSnapshot, AppError>]) { self.results = results }

    func fetchOverview(configuration: AppConfiguration, credential: String, range: UsageRange) async throws -> UsageSnapshot {
        ranges.append(range)
        guard !results.isEmpty else { throw AppError.serviceUnavailable }
        return try results.removeFirst().get()
    }
}

private final class FakeMilestoneTracker: MilestoneTracking {
    struct Observation: Equatable {
        let tokens: Int64
        let identity: MilestoneIdentity
    }

    var state: MilestoneTrackerState?
    var events: [TokenMilestone?]
    var observations: [Observation] = []
    var baselineResetCount = 0

    init(events: [TokenMilestone?] = []) {
        self.events = events
    }

    func observe(tokens: Int64, date: Date, identity: MilestoneIdentity, calendar: Calendar) -> TokenMilestone? {
        observations.append(.init(tokens: tokens, identity: identity))
        state = .init(dateKey: "2026-07-16", identity: identity, lastObservedTokens: tokens, celebratedMilestones: [], requiresBaseline: false)
        return events.isEmpty ? nil : events.removeFirst()
    }

    func requireBaseline() {
        baselineResetCount += 1
    }
}

private final class FakeMilestoneStateStore: MilestoneStateStoring {
    var value: MilestoneTrackerState?
    var saveCount = 0
    func load() -> MilestoneTrackerState? { value }
    func save(_ state: MilestoneTrackerState) throws { value = state; saveCount += 1 }
    func clear() { value = nil }
}

@MainActor
private final class FakeCelebrationCoordinator: CelebrationCoordinating {
    var isPresenting = false
    var milestones: [TokenMilestone] = []
    var previews: [(CelebrationStyle, Bool)] = []

    func celebrate(_ milestone: TokenMilestone, configuration: AppConfiguration) {
        milestones.append(milestone)
    }

    func preview(style: CelebrationStyle, soundEnabled: Bool) {
        previews.append((style, soundEnabled))
    }

    func dismiss() {}
}

private let refreshConfiguration = AppConfiguration(
    baseURL: URL(string: "http://keeper.local:8318")!,
    authenticationType: .administratorPassword,
    refreshInterval: 60,
    menuBarMetric: .tokens,
    launchAtLogin: false
)

private let refreshSnapshot = UsageSnapshot(
    requests: 4,
    successes: 3,
    failures: 1,
    tokens: 1234,
    cost: 0.42,
    range: .today,
    timezone: "Asia/Shanghai",
    refreshedAt: Date(timeIntervalSince1970: 100)
)

@MainActor
@Test
func transientFailureKeepsLastKnownGoodSnapshot() async {
    let preferences = FakePreferencesStore(); preferences.value = refreshConfiguration
    let credentials = FakeCredentialStore(); credentials.value = "secret"
    let api = FakeKeeperAPI(results: [.success(refreshSnapshot), .failure(.serviceUnavailable)])
    let model = UsageRefreshModel(preferences: preferences, credentials: credentials, api: api)

    await model.refresh(force: true)
    await model.refresh(force: true)

    #expect(model.todaySnapshot == refreshSnapshot)
    #expect(model.error == .serviceUnavailable)
}

@MainActor
@Test
func candidateConfigurationIsPersistedOnlyAfterValidation() async throws {
    let preferences = FakePreferencesStore()
    let credentials = FakeCredentialStore()
    let api = FakeKeeperAPI(results: [.success(refreshSnapshot)])
    let model = UsageRefreshModel(preferences: preferences, credentials: credentials, api: api)

    try await model.validateAndSave(configuration: refreshConfiguration, credential: "new-secret")

    #expect(preferences.value == refreshConfiguration)
    #expect(credentials.value == "new-secret")
}

@MainActor
@Test
func successfulTodayRefreshForwardsMilestone() async {
    let preferences = FakePreferencesStore(); preferences.value = refreshConfiguration
    let credentials = FakeCredentialStore(); credentials.value = "secret"
    let tracker = FakeMilestoneTracker(events: [.init(tokens: 50_000_000)])
    let stateStore = FakeMilestoneStateStore()
    let coordinator = FakeCelebrationCoordinator()
    let snapshot = UsageSnapshot(requests: 1, successes: 1, failures: 0, tokens: 50_000_000, cost: nil, range: .today, timezone: nil, refreshedAt: .now)
    let model = UsageRefreshModel(
        preferences: preferences,
        credentials: credentials,
        api: FakeKeeperAPI(results: [.success(snapshot)]),
        milestoneTracker: tracker,
        milestoneStateStore: stateStore,
        celebrationCoordinator: coordinator
    )

    await model.refresh(force: true)

    #expect(tracker.observations.count == 1)
    #expect(coordinator.milestones == [.init(tokens: 50_000_000)])
    #expect(stateStore.saveCount == 1)
}

@MainActor
@Test
func failedRefreshDoesNotAdvanceTracker() async {
    let preferences = FakePreferencesStore(); preferences.value = refreshConfiguration
    let credentials = FakeCredentialStore(); credentials.value = "secret"
    let tracker = FakeMilestoneTracker()
    let model = UsageRefreshModel(
        preferences: preferences,
        credentials: credentials,
        api: FakeKeeperAPI(results: [.failure(.serviceUnavailable)]),
        milestoneTracker: tracker,
        milestoneStateStore: FakeMilestoneStateStore(),
        celebrationCoordinator: FakeCelebrationCoordinator()
    )

    await model.refresh(force: true)

    #expect(tracker.observations.isEmpty)
}

@MainActor
@Test
func previewDoesNotCallTrackerOrStateStore() {
    let tracker = FakeMilestoneTracker()
    let stateStore = FakeMilestoneStateStore()
    let coordinator = FakeCelebrationCoordinator()
    let model = UsageRefreshModel(
        preferences: FakePreferencesStore(),
        credentials: FakeCredentialStore(),
        api: FakeKeeperAPI(results: []),
        milestoneTracker: tracker,
        milestoneStateStore: stateStore,
        celebrationCoordinator: coordinator
    )

    model.previewCelebration(style: .retro, soundEnabled: true)

    #expect(tracker.observations.isEmpty)
    #expect(stateStore.saveCount == 0)
    #expect(coordinator.previews.count == 1)
}
