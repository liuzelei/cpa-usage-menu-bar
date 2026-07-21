import Combine
import Foundation

private struct SnapshotKey: Hashable {
    let range: UsageRange
    let apiKeyID: String?
}

@MainActor
final class UsageRefreshModel: ObservableObject {
    @Published private(set) var configuration: AppConfiguration?
    @Published var selectedRange: UsageRange = .today
    @Published private(set) var selectedSnapshot: UsageSnapshot?
    @Published private(set) var todaySnapshot: UsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var error: AppError?
    @Published private(set) var apiKeyOptions: [CPAAPIKeyOption] = []
    @Published private(set) var selectedAPIKeyID: String?

    private let preferences: PreferencesStoring
    private let credentials: CredentialStoring
    private let api: any KeeperAPIClientProtocol
    private let launchAtLogin: LaunchAtLoginControlling
    private var milestoneTracker: any MilestoneTracking
    private let milestoneStateStore: any MilestoneStateStoring
    private let celebrationCoordinator: any CelebrationCoordinating
    private var timer: Timer?
    private var celebrationStateRefreshTask: Task<Void, Never>?
    private var snapshots: [SnapshotKey: UsageSnapshot] = [:]
    private var authenticationSuspended = false

    init(
        preferences: PreferencesStoring,
        credentials: CredentialStoring,
        api: any KeeperAPIClientProtocol,
        launchAtLogin: LaunchAtLoginControlling = LaunchAtLoginController(),
        milestoneTracker: (any MilestoneTracking)? = nil,
        milestoneStateStore: any MilestoneStateStoring = MilestoneStateStore(),
        celebrationCoordinator: (any CelebrationCoordinating)? = nil
    ) {
        self.preferences = preferences
        self.credentials = credentials
        self.api = api
        self.launchAtLogin = launchAtLogin
        self.milestoneStateStore = milestoneStateStore
        if let milestoneTracker {
            self.milestoneTracker = milestoneTracker
        } else {
            var restoredTracker = MilestoneTracker(state: milestoneStateStore.load())
            restoredTracker.requireBaseline()
            self.milestoneTracker = restoredTracker
        }
        self.celebrationCoordinator = celebrationCoordinator
            ?? CelebrationCoordinator(presenter: CelebrationWindowController())
        self.configuration = try? preferences.load()
    }

    var isCelebrationPresenting: Bool { celebrationCoordinator.isPresenting }

    var isAPIKeyFilterAvailable: Bool {
        configuration?.authenticationType == .administratorPassword && !apiKeyOptions.isEmpty
    }

    func start() {
        stop()
        guard let configuration else { return }
        timer = Timer.scheduledTimer(withTimeInterval: configuration.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh(force: false) }
        }
        Task { await refresh(force: true) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh(force: Bool) async {
        guard !isRefreshing else { return }
        guard !authenticationSuspended || force else { return }
        guard let configuration else {
            error = .missingConfiguration
            return
        }
        guard let credential = try? credentials.read(), !credential.isEmpty else {
            error = .missingCredential
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }
        do {
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
        } catch let appError as AppError {
            error = appError
            if appError == .authenticationFailed { authenticationSuspended = true }
        } catch {
            self.error = .serviceUnavailable
        }
    }

    func selectRange(_ range: UsageRange) async {
        selectedRange = range
        if let snapshot = snapshots[
            SnapshotKey(range: range, apiKeyID: selectedAPIKeyID)
        ] {
            selectedSnapshot = snapshot
        }
        await refresh(force: true)
    }

    func selectAPIKey(_ id: String?) async {
        guard !isRefreshing else { return }
        let shouldRecoverAuthentication = authenticationSuspended
        selectedAPIKeyID = id.flatMap { candidate in
            apiKeyOptions.contains(where: { $0.id == candidate }) ? candidate : nil
        }
        if let snapshot = snapshots[
            SnapshotKey(range: selectedRange, apiKeyID: selectedAPIKeyID)
        ] {
            selectedSnapshot = snapshot
        }
        if shouldRecoverAuthentication {
            await refresh(force: true)
            return
        }
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

    func validateAndSave(configuration candidate: AppConfiguration, credential candidateCredential: String) async throws {
        let oldConfiguration = configuration
        let oldCredential = try credentials.read()
        let credential = candidateCredential.isEmpty ? oldCredential : candidateCredential
        guard let credential, !credential.isEmpty else { throw AppError.missingCredential }

        let validated = try await api.fetchOverview(configuration: candidate, credential: credential, range: .today)
        let oldLaunchAtLogin = launchAtLogin.isEnabled
        try launchAtLogin.setEnabled(candidate.launchAtLogin)
        do {
            try credentials.replace(with: credential)
            try preferences.save(candidate)
        } catch {
            try? launchAtLogin.setEnabled(oldLaunchAtLogin)
            if let oldCredential { try? credentials.replace(with: oldCredential) }
            else { try? credentials.delete() }
            throw error
        }

        configuration = candidate
        if oldConfiguration?.baseURL != candidate.baseURL
            || oldConfiguration?.authenticationType != candidate.authenticationType {
            requireMilestoneBaseline()
        }
        apiKeyOptions = []
        selectedAPIKeyID = nil
        let aggregateKey = SnapshotKey(range: .today, apiKeyID: nil)
        snapshots = [aggregateKey: validated]
        todaySnapshot = validated
        selectedRange = .today
        selectedSnapshot = validated
        error = nil
        authenticationSuspended = false
        stop()
        start()

    }

    func retryAuthentication() async {
        authenticationSuspended = false
        await refresh(force: true)
    }

    func previewCelebration(style: CelebrationStyle, soundEnabled: Bool) {
        celebrationCoordinator.preview(style: style, soundEnabled: soundEnabled)
        refreshCelebrationPresentationState(after: 5.1)
    }

    func requireMilestoneBaseline() {
        milestoneTracker.requireBaseline()
        if let state = milestoneTracker.state {
            try? milestoneStateStore.save(state)
        }
    }

    private func observeMilestone(tokens: Int64, configuration: AppConfiguration) {
        let identity = MilestoneIdentity(
            baseURL: configuration.baseURL.absoluteString,
            authenticationType: configuration.authenticationType
        )
        let milestone = milestoneTracker.observe(
            tokens: tokens,
            date: Date(),
            identity: identity,
            calendar: .current
        )
        if let state = milestoneTracker.state {
            try? milestoneStateStore.save(state)
        }
        if let milestone {
            celebrationCoordinator.celebrate(milestone, configuration: configuration)
            refreshCelebrationPresentationState(after: 5.1)
        }
    }

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

    private func refreshCelebrationPresentationState(after duration: TimeInterval) {
        objectWillChange.send()
        celebrationStateRefreshTask?.cancel()
        celebrationStateRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.objectWillChange.send()
        }
    }
}
