import Foundation
import Testing
@testable import CPAUsageMenuBar

@MainActor
private final class RecordingCelebrationPresenter: CelebrationPresenting {
    private(set) var sessions: [CelebrationSession] = []
    private(set) var dismissCount = 0
    var isPresenting: Bool { !sessions.isEmpty && dismissCount == 0 }

    func present(_ session: CelebrationSession) {
        sessions.append(session)
    }

    func dismiss() {
        dismissCount += 1
    }
}

@MainActor
private final class RecordingSoundPlayer: CelebrationSoundPlaying {
    private(set) var playCount = 0
    func play() { playCount += 1 }
}

@MainActor
private func makeCoordinator() -> (CelebrationCoordinator, RecordingCelebrationPresenter, RecordingSoundPlayer) {
    let presenter = RecordingCelebrationPresenter()
    let sound = RecordingSoundPlayer()
    let coordinator = CelebrationCoordinator(
        presenter: presenter,
        soundPlayer: sound,
        seedProvider: { 42 },
        now: { Date(timeIntervalSince1970: 100) }
    )
    return (coordinator, presenter, sound)
}

@MainActor
@Test
func previewUsesSyntheticFiftyMillionWithoutTracker() {
    let (coordinator, presenter, _) = makeCoordinator()
    coordinator.preview(style: .retro, soundEnabled: false)
    #expect(presenter.sessions.first?.milestone.tokens == 50_000_000)
    #expect(presenter.sessions.first?.style == .retro)
}

@MainActor
@Test
func soundPlaysOnceForPresentation() {
    let (coordinator, _, sound) = makeCoordinator()
    let configuration = AppConfiguration(
        baseURL: URL(string: "http://keeper.local:8080")!,
        authenticationType: .administratorPassword,
        refreshInterval: 60,
        menuBarMetric: .tokens,
        launchAtLogin: false,
        celebrationStyle: .cinematic,
        celebrationSoundEnabled: true
    )
    coordinator.celebrate(.init(tokens: 100_000_000), configuration: configuration)
    #expect(sound.playCount == 1)
}

@MainActor
@Test
func activePresentationIgnoresSecondRequest() {
    let (coordinator, presenter, _) = makeCoordinator()
    coordinator.preview(style: .cinematic, soundEnabled: false)
    coordinator.preview(style: .retro, soundEnabled: false)
    #expect(presenter.sessions.count == 1)
}

@MainActor
@Test
func offStyleDoesNotPresent() {
    let (coordinator, presenter, _) = makeCoordinator()
    coordinator.preview(style: .off, soundEnabled: true)
    #expect(presenter.sessions.isEmpty)
}

@MainActor
@Test
func randomStyleResolvesBeforePresentation() {
    let (coordinator, presenter, _) = makeCoordinator()
    coordinator.preview(style: .random, soundEnabled: false)
    #expect([CelebrationStyle.cinematic, .achievementToast, .retro].contains(presenter.sessions.first?.style))
}
