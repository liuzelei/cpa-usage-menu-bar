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
    struct OverviewCall: Equatable {
        let range: UsageRange
        let apiKeyID: String?
    }

    var results: [Result<UsageSnapshot, AppError>]
    var optionResults: [Result<[CPAAPIKeyOption], AppError>]
    private(set) var overviewCalls: [OverviewCall] = []
    private(set) var optionCallCount = 0

    init(
        results: [Result<UsageSnapshot, AppError>],
        optionResults: [Result<[CPAAPIKeyOption], AppError>] = []
    ) {
        self.results = results
        self.optionResults = optionResults
    }

    func fetchOverview(
        configuration: AppConfiguration,
        credential: String,
        range: UsageRange,
        apiKeyID: String?
    ) async throws -> UsageSnapshot {
        overviewCalls.append(.init(range: range, apiKeyID: apiKeyID))
        guard !results.isEmpty else { throw AppError.serviceUnavailable }
        return try results.removeFirst().get()
    }

    func fetchAPIKeyOptions(
        configuration: AppConfiguration,
        credential: String
    ) async throws -> [CPAAPIKeyOption] {
        optionCallCount += 1
        guard !optionResults.isEmpty else { return [] }
        return try optionResults.removeFirst().get()
    }

    func recordedOverviewCalls() -> [OverviewCall] { overviewCalls }
    func recordedOptionCallCount() -> Int { optionCallCount }
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

private func snapshot(tokens: Int64, range: UsageRange) -> UsageSnapshot {
    .init(
        requests: 1,
        successes: 1,
        failures: 0,
        tokens: tokens,
        cost: nil,
        range: range,
        timezone: nil,
        refreshedAt: .now
    )
}

@MainActor
@Test
func administratorLoadsOptionsAndDefaultsToAggregateUsage() async {
    let preferences = FakePreferencesStore(); preferences.value = refreshConfiguration
    let credentials = FakeCredentialStore(); credentials.value = "secret"
    let api = FakeKeeperAPI(
        results: [.success(refreshSnapshot)],
        optionResults: [.success([.init(id: "42", label: "Primary Key")])]
    )
    let model = UsageRefreshModel(preferences: preferences, credentials: credentials, api: api)

    await model.refresh(force: true)

    #expect(model.apiKeyOptions == [.init(id: "42", label: "Primary Key")])
    #expect(model.selectedAPIKeyID == nil)
    #expect(model.isAPIKeyFilterAvailable)
    #expect(await api.recordedOverviewCalls() == [.init(range: .today, apiKeyID: nil)])
}

@MainActor
@Test
func apiKeyViewerNeverLoadsAdministratorOptions() async {
    let viewer = AppConfiguration(
        baseURL: refreshConfiguration.baseURL,
        authenticationType: .cpaAPIKey,
        refreshInterval: 60,
        menuBarMetric: .tokens,
        launchAtLogin: false
    )
    let preferences = FakePreferencesStore(); preferences.value = viewer
    let credentials = FakeCredentialStore(); credentials.value = "viewer-key"
    let api = FakeKeeperAPI(results: [.success(refreshSnapshot)])
    let model = UsageRefreshModel(preferences: preferences, credentials: credentials, api: api)

    await model.refresh(force: true)

    #expect(await api.recordedOptionCallCount() == 0)
    #expect(!model.isAPIKeyFilterAvailable)
}

@MainActor
@Test
func selectedKeyChangesOnlyPageSnapshotWhileMilestoneUsesAggregateToday() async {
    let preferences = FakePreferencesStore(); preferences.value = refreshConfiguration
    let credentials = FakeCredentialStore(); credentials.value = "secret"
    let tracker = FakeMilestoneTracker()
    let api = FakeKeeperAPI(
        results: [
            .success(snapshot(tokens: 100_000_000, range: .today)),
            .success(snapshot(tokens: 2_000_000, range: .today))
        ],
        optionResults: [.success([.init(id: "42", label: "Primary Key")])]
    )
    let model = UsageRefreshModel(
        preferences: preferences,
        credentials: credentials,
        api: api,
        milestoneTracker: tracker,
        milestoneStateStore: FakeMilestoneStateStore(),
        celebrationCoordinator: FakeCelebrationCoordinator()
    )

    await model.refresh(force: true)
    await model.selectAPIKey("42")

    #expect(model.todaySnapshot?.tokens == 100_000_000)
    #expect(model.selectedSnapshot?.tokens == 2_000_000)
    #expect(tracker.observations.map(\.tokens) == [100_000_000])
    #expect(await api.recordedOverviewCalls() == [
        .init(range: .today, apiKeyID: nil),
        .init(range: .today, apiKeyID: "42")
    ])
}

@MainActor
@Test
func missingSelectedKeyFallsBackToAggregateOnce() async {
    let preferences = FakePreferencesStore(); preferences.value = refreshConfiguration
    let credentials = FakeCredentialStore(); credentials.value = "secret"
    let api = FakeKeeperAPI(
        results: [
            .success(refreshSnapshot),
            .success(refreshSnapshot),
            .success(snapshot(tokens: 8_000, range: .last7Days)),
            .failure(.server(status: 404)),
            .success(snapshot(tokens: 9_000, range: .last7Days))
        ],
        optionResults: [
            .success([.init(id: "42", label: "Primary Key")]),
            .success([.init(id: "42", label: "Primary Key")])
        ]
    )
    let model = UsageRefreshModel(preferences: preferences, credentials: credentials, api: api)

    await model.refresh(force: true)
    await model.selectRange(.last7Days)
    await model.selectAPIKey("42")

    #expect(model.selectedAPIKeyID == nil)
    #expect(model.selectedSnapshot?.tokens == 9_000)
    #expect(await api.recordedOverviewCalls().suffix(2) == [
        .init(range: .last7Days, apiKeyID: "42"),
        .init(range: .last7Days, apiKeyID: nil)
    ])
}

@MainActor
@Test
func savingChangedIdentityResetsKeySelection() async throws {
    let preferences = FakePreferencesStore(); preferences.value = refreshConfiguration
    let credentials = FakeCredentialStore(); credentials.value = "secret"
    let api = FakeKeeperAPI(
        results: [
            .success(refreshSnapshot),
            .success(refreshSnapshot),
            .success(refreshSnapshot)
        ],
        optionResults: [.success([.init(id: "42", label: "Primary Key")])]
    )
    let model = UsageRefreshModel(preferences: preferences, credentials: credentials, api: api)

    await model.refresh(force: true)
    await model.selectAPIKey("42")
    let changed = AppConfiguration(
        baseURL: URL(string: "https://other-keeper.example")!,
        authenticationType: .administratorPassword,
        refreshInterval: 60,
        menuBarMetric: .tokens,
        launchAtLogin: false
    )
    try await model.validateAndSave(configuration: changed, credential: "new-secret")

    #expect(model.selectedAPIKeyID == nil)
    #expect(model.apiKeyOptions.isEmpty)
}

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
