import SwiftUI

struct CelebrationRootView: View {
    let session: CelebrationSession

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(session.startTime))
            Group {
                switch session.style {
                case .cinematic:
                    CinematicFireworksView(session: session, elapsed: elapsed)
                case .achievementToast:
                    AchievementToastView(session: session, elapsed: elapsed)
                case .retro:
                    RetroAchievementView(session: session, elapsed: elapsed)
                case .off, .random:
                    EmptyView()
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

func celebrationEnvelope(elapsed: TimeInterval, duration: TimeInterval) -> Double {
    let fadeIn = min(1, max(0, elapsed / 0.35))
    let fadeOut = min(1, max(0, (duration - elapsed) / 0.5))
    return fadeIn * fadeOut
}
