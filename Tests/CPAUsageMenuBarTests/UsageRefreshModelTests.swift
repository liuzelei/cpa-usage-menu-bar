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
        return try results.removeFirst().get()
    }
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
