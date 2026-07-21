# Admin API Key Usage Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Let Keeper administrators select one CPA API key in the existing popover and view its usage while keeping menu bar metrics and milestone celebrations based on aggregate daily usage.

**Architecture:** Extend the authenticated Keeper client with a safe Key-options request and an optional api_key_id overview filter. Keep aggregate Today state separate from page-filtered snapshots in UsageRefreshModel, then expose deterministic presentation data to a SwiftUI picker. Unsupported older Keeper endpoints return an empty capability result so aggregate usage remains unaffected.

**Tech Stack:** Swift 6, SwiftUI, Combine, Foundation URLSession, Swift Testing, macOS 13+

## Global Constraints

- The Key filter is available only with AuthenticationType.administratorPassword.
- Never call /api/v1/usage/api-keys/settings or decode, log, display, or persist a complete CPA API key.
- Use only id and label from /api/v1/usage/api-keys/options.
- The filter changes only popover metrics; todaySnapshot and milestone tracking always use aggregate Today usage.
- Do not persist selectedAPIKeyID; initialization and configuration identity changes default to aggregate usage.
- Treat Key-options HTTP 404 and 501 as unsupported and hide the filter without an app-wide error.
- A filtered overview HTTP 404 resets to aggregate usage and retries that page range once.
- Preserve the last successful snapshot during transient failures.
- Update both README.md and README.zh-CN.md.

---

### Task 1: Add safe API key option and filtered overview requests

**Files:**
- Create: Sources/CPAUsageMenuBar/Models/CPAAPIKeyOption.swift
- Modify: Sources/CPAUsageMenuBar/Networking/KeeperAPIClient.swift
- Modify: Tests/CPAUsageMenuBarTests/KeeperAPIClientTests.swift

**Interfaces:**
- Produces: CPAAPIKeyOption with id and label.
- Produces: fetchAPIKeyOptions(configuration:credential:) async throws -> [CPAAPIKeyOption].
- Changes: fetchOverview(configuration:credential:range:apiKeyID:) async throws -> UsageSnapshot.
- Preserves: a convenience overload of fetchOverview without apiKeyID for existing callers.

- [ ] **Step 1: Write failing tests for option decoding and old-Keeper compatibility**

Add to KeeperAPIClientTests:

~~~swift
@Test
func administratorFetchesSafeAPIKeyOptions() async throws {
    let body = Data("""
    {"options":[{"id":"42","label":"Primary Key"},{"id":"84","label":"sk-*********abcd"}]}
    """.utf8)
    StubURLProtocol.reset([
        .init(status: 204, headers: [:], body: Data()),
        .init(status: 200, headers: [:], body: body)
    ])

    let options = try await makeClient().fetchAPIKeyOptions(
        configuration: configuration(.administratorPassword),
        credential: "secret"
    )

    #expect(options == [
        CPAAPIKeyOption(id: "42", label: "Primary Key"),
        CPAAPIKeyOption(id: "84", label: "sk-*********abcd")
    ])
    #expect(StubURLProtocol.requests.map { $0.url!.path } == [
        "/api/v1/auth/login",
        "/api/v1/usage/api-keys/options"
    ])
    #expect(StubURLProtocol.requests[1].httpBody == nil)
}

@Test
func unsupportedAPIKeyOptionsReturnEmptyList() async throws {
    for status in [404, 501] {
        StubURLProtocol.reset([
            .init(status: 204, headers: [:], body: Data()),
            .init(status: status, headers: [:], body: Data())
        ])

        let options = try await makeClient().fetchAPIKeyOptions(
            configuration: configuration(.administratorPassword),
            credential: "secret"
        )

        #expect(options.isEmpty)
    }
}
~~~

- [ ] **Step 2: Run the first option test and verify RED**

Run:

~~~bash
swift test --filter KeeperAPIClientTests.administratorFetchesSafeAPIKeyOptions
~~~

Expected: compilation fails because CPAAPIKeyOption and fetchAPIKeyOptions do not exist.

- [ ] **Step 3: Write failing tests for filtered administrator requests and viewer isolation**

~~~swift
@Test
func administratorOverviewIncludesSelectedAPIKeyID() async throws {
    StubURLProtocol.reset([
        .init(status: 204, headers: [:], body: Data()),
        .init(status: 200, headers: [:], body: overviewJSON)
    ])

    _ = try await makeClient().fetchOverview(
        configuration: configuration(.administratorPassword),
        credential: "secret",
        range: .last7Days,
        apiKeyID: "42"
    )

    let components = try #require(
        URLComponents(url: StubURLProtocol.requests[1].url!, resolvingAgainstBaseURL: false)
    )
    #expect(Set(components.queryItems ?? []) == Set([
        URLQueryItem(name: "range", value: "7d"),
        URLQueryItem(name: "api_key_id", value: "42")
    ]))
}

@Test
func viewerOverviewNeverIncludesSelectedAPIKeyID() async throws {
    StubURLProtocol.reset([
        .init(status: 204, headers: [:], body: Data()),
        .init(status: 200, headers: [:], body: overviewJSON)
    ])

    _ = try await makeClient().fetchOverview(
        configuration: configuration(.cpaAPIKey),
        credential: "key",
        range: .last7Days,
        apiKeyID: "42"
    )

    #expect(StubURLProtocol.requests[1].url?.path == "/api/v1/key-overview")
    #expect(StubURLProtocol.requests[1].url?.query == "range=7d")
}
~~~

- [ ] **Step 4: Run the administrator filter test and verify RED**

Run:

~~~bash
swift test --filter KeeperAPIClientTests.administratorOverviewIncludesSelectedAPIKeyID
~~~

Expected: compilation fails because fetchOverview does not accept apiKeyID.

- [ ] **Step 5: Implement the model and protocol contract**

Create CPAAPIKeyOption.swift:

~~~swift
struct CPAAPIKeyOption: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let label: String
}
~~~

Update KeeperAPIClientProtocol:

~~~swift
protocol KeeperAPIClientProtocol: Sendable {
    func fetchOverview(
        configuration: AppConfiguration,
        credential: String,
        range: UsageRange,
        apiKeyID: String?
    ) async throws -> UsageSnapshot

    func fetchAPIKeyOptions(
        configuration: AppConfiguration,
        credential: String
    ) async throws -> [CPAAPIKeyOption]
}

extension KeeperAPIClientProtocol {
    func fetchOverview(
        configuration: AppConfiguration,
        credential: String,
        range: UsageRange
    ) async throws -> UsageSnapshot {
        try await fetchOverview(
            configuration: configuration,
            credential: credential,
            range: range,
            apiKeyID: nil
        )
    }
}
~~~

Add the private response envelope:

~~~swift
private struct APIKeyOptionsResponse: Decodable {
    let options: [CPAAPIKeyOption]
}
~~~

Change overviewResponse to accept apiKeyID. Build query items as follows:

~~~swift
var queryItems = [URLQueryItem(name: "range", value: range.rawValue)]
if configuration.authenticationType == .administratorPassword,
   let apiKeyID,
   !apiKeyID.isEmpty {
    queryItems.append(URLQueryItem(name: "api_key_id", value: apiKeyID))
}
components.queryItems = queryItems
~~~

Thread apiKeyID through both the first request and the one-time 401 retry. Add the option request and decoder:

~~~swift
func fetchAPIKeyOptions(
    configuration: AppConfiguration,
    credential: String
) async throws -> [CPAAPIKeyOption] {
    guard configuration.authenticationType == .administratorPassword else { return [] }
    let context = AuthContext(
        baseURL: configuration.baseURL,
        authenticationType: configuration.authenticationType
    )
    if authenticatedContext != context {
        sessionCookieHeader = nil
        try await login(configuration: configuration, credential: credential)
        authenticatedContext = context
    }

    let first = try await apiKeyOptionsResponse(configuration: configuration)
    if first.response.statusCode == 401 {
        authenticatedContext = nil
        sessionCookieHeader = nil
        try await login(configuration: configuration, credential: credential)
        authenticatedContext = context
        let retried = try await apiKeyOptionsResponse(configuration: configuration)
        guard retried.response.statusCode != 401 else {
            authenticatedContext = nil
            throw AppError.authenticationFailed
        }
        return try decodeAPIKeyOptions(retried.data, response: retried.response)
    }
    return try decodeAPIKeyOptions(first.data, response: first.response)
}

private func apiKeyOptionsResponse(
    configuration: AppConfiguration
) async throws -> (data: Data, response: HTTPURLResponse) {
    var request = URLRequest(
        url: configuration.baseURL.appendingPathComponent("api/v1/usage/api-keys/options")
    )
    request.timeoutInterval = 15
    if let sessionCookieHeader {
        request.setValue(sessionCookieHeader, forHTTPHeaderField: "Cookie")
    }
    return try await perform(request)
}

private func decodeAPIKeyOptions(
    _ data: Data,
    response: HTTPURLResponse
) throws -> [CPAAPIKeyOption] {
    switch response.statusCode {
    case 200..<300:
        do { return try JSONDecoder().decode(APIKeyOptionsResponse.self, from: data).options }
        catch { throw AppError.incompatibleResponse }
    case 404, 501: return []
    case 401: throw AppError.authenticationFailed
    case 403: throw AppError.forbidden
    default: throw AppError.server(status: response.statusCode)
    }
}
~~~

- [ ] **Step 6: Run focused client tests and verify GREEN**

Run:

~~~bash
swift test --filter KeeperAPIClientTests
~~~

Expected: every KeeperAPIClientTests test passes with no warnings.

- [ ] **Step 7: Commit the API client task**

~~~bash
git add Sources/CPAUsageMenuBar/Models/CPAAPIKeyOption.swift Sources/CPAUsageMenuBar/Networking/KeeperAPIClient.swift Tests/CPAUsageMenuBarTests/KeeperAPIClientTests.swift
git commit -m "feat: fetch admin API key usage options"
~~~

---

### Task 2: Separate aggregate Today usage from filtered page usage

**Files:**
- Modify: Sources/CPAUsageMenuBar/Refresh/UsageRefreshModel.swift
- Modify: Tests/CPAUsageMenuBarTests/UsageRefreshModelTests.swift

**Interfaces:**
- Consumes: Task 1 client APIs.
- Produces: published apiKeyOptions and selectedAPIKeyID.
- Produces: isAPIKeyFilterAvailable and selectAPIKey(_:).
- Replaces: range-only cache with a cache keyed by range and optional Key ID.

- [ ] **Step 1: Upgrade the fake API before adding model tests**

Replace FakeKeeperAPI with:

~~~swift
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
~~~

- [ ] **Step 2: Write failing administrator and viewer option-state tests**

~~~swift
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
~~~

- [ ] **Step 3: Run the administrator state test and verify RED**

Run:

~~~bash
swift test --filter administratorLoadsOptionsAndDefaultsToAggregateUsage
~~~

Expected: compilation fails because the model does not expose Key filter state.

- [ ] **Step 4: Write the failing global-versus-filtered isolation test**

Add this helper:

~~~swift
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
~~~

Add the test:

~~~swift
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
~~~

- [ ] **Step 5: Run the isolation test and verify RED**

Run:

~~~bash
swift test --filter selectedKeyChangesOnlyPageSnapshotWhileMilestoneUsesAggregateToday
~~~

Expected: compilation fails because selectAPIKey and selectedAPIKeyID do not exist.

- [ ] **Step 6: Implement filter state and isolated caching**

Add:

~~~swift
private struct SnapshotKey: Hashable {
    let range: UsageRange
    let apiKeyID: String?
}

@Published private(set) var apiKeyOptions: [CPAAPIKeyOption] = []
@Published private(set) var selectedAPIKeyID: String?

private var snapshots: [SnapshotKey: UsageSnapshot] = [:]

var isAPIKeyFilterAvailable: Bool {
    configuration?.authenticationType == .administratorPassword && !apiKeyOptions.isEmpty
}
~~~

Implement selection:

~~~swift
func selectAPIKey(_ id: String?) async {
    guard !isRefreshing else { return }
    selectedAPIKeyID = id.flatMap { candidate in
        apiKeyOptions.contains(where: { $0.id == candidate }) ? candidate : nil
    }
    selectedSnapshot = snapshots[
        SnapshotKey(range: selectedRange, apiKeyID: selectedAPIKeyID)
    ]
    guard let configuration,
          let credential = try? credentials.read(),
          !credential.isEmpty else { return }

    isRefreshing = true
    defer { isRefreshing = false }
    do {
        try await refreshSelectedSnapshot(
            configuration: configuration,
            credential: credential,
            aggregateToday: todaySnapshot
        )
        error = nil
    } catch let appError as AppError {
        error = appError
        if appError == .authenticationFailed { authenticationSuspended = true }
    } catch {
        self.error = .serviceUnavailable
    }
}
~~~

Add these helpers:

~~~swift
private func refreshAPIKeyOptions(
    configuration: AppConfiguration,
    credential: String
) async throws {
    guard configuration.authenticationType == .administratorPassword else {
        apiKeyOptions = []
        selectedAPIKeyID = nil
        return
    }
    let options = try await api.fetchAPIKeyOptions(
        configuration: configuration,
        credential: credential
    )
    apiKeyOptions = options
    if let selectedAPIKeyID,
       !options.contains(where: { $0.id == selectedAPIKeyID }) {
        self.selectedAPIKeyID = nil
    }
}

private func refreshSelectedSnapshot(
    configuration: AppConfiguration,
    credential: String,
    aggregateToday: UsageSnapshot?
) async throws {
    let selectedID = selectedAPIKeyID
    let key = SnapshotKey(range: selectedRange, apiKeyID: selectedID)
    if selectedRange == .today, selectedID == nil, let aggregateToday {
        snapshots[key] = aggregateToday
        selectedSnapshot = aggregateToday
        return
    }
    do {
        let value = try await api.fetchOverview(
            configuration: configuration,
            credential: credential,
            range: selectedRange,
            apiKeyID: selectedID
        )
        snapshots[key] = value
        selectedSnapshot = value
    } catch AppError.server(status: 404) where selectedID != nil {
        selectedAPIKeyID = nil
        let fallbackKey = SnapshotKey(range: selectedRange, apiKeyID: nil)
        if selectedRange == .today, let aggregateToday {
            snapshots[fallbackKey] = aggregateToday
            selectedSnapshot = aggregateToday
            return
        }
        let fallback = try await api.fetchOverview(
            configuration: configuration,
            credential: credential,
            range: selectedRange,
            apiKeyID: nil
        )
        snapshots[fallbackKey] = fallback
        selectedSnapshot = fallback
    }
}
~~~

Refactor refresh(force:) to call the helpers in this order:

~~~swift
let today = try await api.fetchOverview(
    configuration: configuration,
    credential: credential,
    range: .today,
    apiKeyID: nil
)
let aggregateKey = SnapshotKey(range: .today, apiKeyID: nil)
snapshots[aggregateKey] = today
todaySnapshot = today
observeMilestone(tokens: today.tokens, configuration: configuration)
try await refreshAPIKeyOptions(configuration: configuration, credential: credential)
try await refreshSelectedSnapshot(
    configuration: configuration,
    credential: credential,
    aggregateToday: today
)
error = nil
authenticationSuspended = false
~~~

Update selectRange(_:) to load SnapshotKey(range:apiKeyID:) before calling refresh(force: true):

~~~swift
func selectRange(_ range: UsageRange) async {
    selectedRange = range
    selectedSnapshot = snapshots[
        SnapshotKey(range: range, apiKeyID: selectedAPIKeyID)
    ]
    await refresh(force: true)
}
~~~

In validateAndSave, reset and seed state with:

~~~swift
apiKeyOptions = []
selectedAPIKeyID = nil
let aggregateKey = SnapshotKey(range: .today, apiKeyID: nil)
snapshots = [aggregateKey: validated]
todaySnapshot = validated
selectedRange = .today
selectedSnapshot = validated
~~~

- [ ] **Step 7: Write failing deleted-Key and identity-reset tests**

~~~swift
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
~~~

- [ ] **Step 8: Run all tests and make the model GREEN**

Run:

~~~bash
swift test
~~~

Expected: the complete suite passes with no failures or warnings.

- [ ] **Step 9: Commit the refresh model task**

~~~bash
git add Sources/CPAUsageMenuBar/Refresh/UsageRefreshModel.swift Tests/CPAUsageMenuBarTests/UsageRefreshModelTests.swift
git commit -m "feat: isolate filtered key usage from global usage"
~~~

---

### Task 3: Add the administrator Key picker

**Files:**
- Create: Sources/CPAUsageMenuBar/Views/APIKeyFilterPresentation.swift
- Modify: Sources/CPAUsageMenuBar/Views/UsagePopoverView.swift
- Create: Tests/CPAUsageMenuBarTests/APIKeyFilterPresentationTests.swift

**Interfaces:**
- Consumes: Task 2 model filter state and selection method.
- Produces: APIKeyFilterItem and APIKeyFilterPresentation.items(authenticationType:options:).

- [ ] **Step 1: Write failing presentation tests**

~~~swift
import Testing
@testable import CPAUsageMenuBar

@Test
func administratorFilterStartsWithAggregateThenKeeperOptions() {
    let items = APIKeyFilterPresentation.items(
        authenticationType: .administratorPassword,
        options: [
            .init(id: "42", label: "Primary Key"),
            .init(id: "84", label: "sk-*********abcd")
        ]
    )

    #expect(items.map(\.apiKeyID) == [nil, "42", "84"])
    #expect(items.map(\.title) == ["全部用量", "Primary Key", "sk-*********abcd"])
}

@Test
func filterIsHiddenForViewerOrEmptyOptions() {
    #expect(APIKeyFilterPresentation.items(
        authenticationType: .cpaAPIKey,
        options: [.init(id: "42", label: "Primary Key")]
    ).isEmpty)
    #expect(APIKeyFilterPresentation.items(
        authenticationType: .administratorPassword,
        options: []
    ).isEmpty)
}
~~~

- [ ] **Step 2: Run the presentation tests and verify RED**

Run:

~~~bash
swift test --filter APIKeyFilterPresentation
~~~

Expected: compilation fails because APIKeyFilterPresentation does not exist.

- [ ] **Step 3: Implement presentation data**

Create APIKeyFilterPresentation.swift:

~~~swift
struct APIKeyFilterItem: Equatable, Identifiable {
    let apiKeyID: String?
    let title: String

    var id: String { apiKeyID ?? "all" }
}

enum APIKeyFilterPresentation {
    static func items(
        authenticationType: AuthenticationType,
        options: [CPAAPIKeyOption]
    ) -> [APIKeyFilterItem] {
        guard authenticationType == .administratorPassword, !options.isEmpty else { return [] }
        return [APIKeyFilterItem(apiKeyID: nil, title: "全部用量")]
            + options.map { APIKeyFilterItem(apiKeyID: $0.id, title: $0.label) }
    }
}
~~~

- [ ] **Step 4: Run presentation tests and verify GREEN**

Run:

~~~bash
swift test --filter APIKeyFilterPresentation
~~~

Expected: both presentation tests pass.

- [ ] **Step 5: Add the picker above the time range picker**

In UsagePopoverView.summary, derive items from the current configuration and model options. Insert this before the time range picker:

~~~swift
if let authenticationType = model.configuration?.authenticationType {
    let items = APIKeyFilterPresentation.items(
        authenticationType: authenticationType,
        options: model.apiKeyOptions
    )
    if !items.isEmpty {
        Picker("API Key", selection: Binding(
            get: { model.selectedAPIKeyID },
            set: { id in Task { await model.selectAPIKey(id) } }
        )) {
            ForEach(items) { item in
                Text(item.title).tag(item.apiKeyID)
            }
        }
        .pickerStyle(.menu)
    }
}
~~~

Keep the existing metric cards, progress indicator, footer, and popover width unchanged.

- [ ] **Step 6: Build and run all tests**

Run:

~~~bash
swift test
~~~

Expected: the package builds and all tests pass with no failures or warnings.

- [ ] **Step 7: Commit the popover task**

~~~bash
git add Sources/CPAUsageMenuBar/Views/APIKeyFilterPresentation.swift Sources/CPAUsageMenuBar/Views/UsagePopoverView.swift Tests/CPAUsageMenuBarTests/APIKeyFilterPresentationTests.swift
git commit -m "feat: add admin API key usage picker"
~~~

---

### Task 4: Document and verify the feature

**Files:**
- Modify: README.md
- Modify: README.zh-CN.md

**Interfaces:**
- Consumes: completed behavior from Tasks 1–3.
- Produces: matching English and Simplified Chinese user documentation.

- [ ] **Step 1: Update README.md**

Add this feature bullet after the time-range bullet:

~~~markdown
- Let administrators filter popover usage by a specific CPA API key while keeping menu bar metrics and milestone celebrations based on aggregate usage.
~~~

Add this Usage bullet:

~~~markdown
- When signed in with a Keeper admin key, select **All Usage** or a specific CPA API key from the Key picker. Older Keeper versions that do not support Key options simply hide this picker.
~~~

- [ ] **Step 2: Update README.zh-CN.md**

Add this feature bullet after the time-range bullet:

~~~markdown
- 管理员可在弹窗中按具体 CPA API Key 筛选用量，菜单栏指标和里程碑彩蛋仍使用全局用量。
~~~

Add this 使用 bullet:

~~~markdown
- 使用 Keeper 管理密钥登录时，可在 Key 下拉框中选择“全部用量”或具体 CPA API Key；不支持 Key 选项接口的旧版 Keeper 会自动隐藏该下拉框。
~~~

- [ ] **Step 3: Verify documentation and the complete package**

Run:

~~~bash
git diff --check
swift test
~~~

Expected: the diff check prints nothing and all Swift tests pass with no failures or warnings.

- [ ] **Step 4: Commit documentation**

~~~bash
git add README.md README.zh-CN.md
git commit -m "docs: explain admin API key usage filter"
~~~

- [ ] **Step 5: Perform final verification**

Run:

~~~bash
swift test
git diff --check HEAD^ HEAD
git status --short
~~~

Expected: all tests pass, the committed diff has no whitespace errors, and the working tree is clean.
