import Foundation

@MainActor
protocol CelebrationPresenting: AnyObject {
    var isPresenting: Bool { get }
    func present(_ session: CelebrationSession)
    func dismiss()
}

@MainActor
protocol CelebrationCoordinating: AnyObject {
    var isPresenting: Bool { get }
    func celebrate(_ milestone: TokenMilestone, configuration: AppConfiguration)
    func preview(style: CelebrationStyle, soundEnabled: Bool)
    func dismiss()
}

@MainActor
final class CelebrationCoordinator: CelebrationCoordinating {
    private let presenter: any CelebrationPresenting
    private let soundPlayer: any CelebrationSoundPlaying
    private let copyProvider: any MemeCopyProviding
    private let seedProvider: () -> UInt64
    private let now: () -> Date
    private var dismissalTask: Task<Void, Never>?

    var isPresenting: Bool { presenter.isPresenting }

    init(
        presenter: any CelebrationPresenting,
        soundPlayer: (any CelebrationSoundPlaying)? = nil,
        copyProvider: any MemeCopyProviding = MemeCopyProvider(),
        seedProvider: @escaping () -> UInt64 = { UInt64.random(in: .min ... .max) },
        now: @escaping () -> Date = Date.init
    ) {
        self.presenter = presenter
        self.soundPlayer = soundPlayer ?? CelebrationSoundPlayer()
        self.copyProvider = copyProvider
        self.seedProvider = seedProvider
        self.now = now
    }

    func celebrate(_ milestone: TokenMilestone, configuration: AppConfiguration) {
        start(milestone: milestone, style: configuration.celebrationStyle, soundEnabled: configuration.celebrationSoundEnabled)
    }

    func preview(style: CelebrationStyle, soundEnabled: Bool) {
        start(milestone: TokenMilestone(tokens: 50_000_000), style: style, soundEnabled: soundEnabled)
    }

    func dismiss() {
        dismissalTask?.cancel()
        dismissalTask = nil
        presenter.dismiss()
    }

    private func start(milestone: TokenMilestone, style: CelebrationStyle, soundEnabled: Bool) {
        guard style != .off, !presenter.isPresenting else { return }
        let seed = seedProvider()
        let resolvedStyle = resolve(style, seed: seed)
        let duration = duration(for: resolvedStyle)
        let session = CelebrationSession(
            id: UUID(),
            milestone: milestone,
            style: resolvedStyle,
            copy: copyProvider.copy(for: milestone, style: resolvedStyle, seed: seed),
            seed: seed,
            startTime: now(),
            duration: duration
        )
        presenter.present(session)
        if soundEnabled { soundPlayer.play() }

        dismissalTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func resolve(_ style: CelebrationStyle, seed: UInt64) -> CelebrationStyle {
        guard style == .random else { return style }
        return [CelebrationStyle.cinematic, .achievementToast, .retro][Int(seed % 3)]
    }

    private func duration(for style: CelebrationStyle) -> TimeInterval {
        switch style {
        case .cinematic: 4.5
        case .achievementToast: 5
        case .retro: 4
        case .off, .random: 4
        }
    }
}
