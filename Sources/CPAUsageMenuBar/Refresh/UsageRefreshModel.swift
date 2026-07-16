import Combine
import Foundation

@MainActor
final class UsageRefreshModel: ObservableObject {
    @Published private(set) var configuration: AppConfiguration?
    @Published var selectedRange: UsageRange = .today
    @Published private(set) var selectedSnapshot: UsageSnapshot?
    @Published private(set) var todaySnapshot: UsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var error: AppError?

    private let preferences: PreferencesStoring
    private let credentials: CredentialStoring
    private let api: any KeeperAPIClientProtocol
    private let launchAtLogin: LaunchAtLoginControlling
    private var milestoneTracker: any MilestoneTracking
    private let milestoneStateStore: any MilestoneStateStoring
    private let celebrationCoordinator: any CelebrationCoordinating
    private var timer: Timer?
    private var celebrationStateRefreshTask: Task<Void, Never>?
    private var snapshots: [UsageRange: UsageSnapshot] = [:]
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
            let today = try await api.fetchOverview(configuration: configuration, credential: credential, range: .today)
            snapshots[.today] = today
            todaySnapshot = today
            observeMilestone(tokens: today.tokens, configuration: configuration)
            if selectedRange == .today {
                selectedSnapshot = today
            } else {
                let selected = try await api.fetchOverview(configuration: configuration, credential: credential, range: selectedRange)
                snapshots[selectedRange] = selected
                selectedSnapshot = selected
            }
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
        selectedSnapshot = snapshots[range]
        await refresh(force: true)
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
        snapshots = [.today: validated]
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
