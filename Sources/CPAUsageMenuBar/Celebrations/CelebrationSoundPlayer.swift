import AppKit

@MainActor
protocol CelebrationSoundPlaying {
    func play()
}

struct CelebrationSoundPlayer: CelebrationSoundPlaying {
    func play() {
        NSSound(named: NSSound.Name("Glass"))?.play()
    }
}
