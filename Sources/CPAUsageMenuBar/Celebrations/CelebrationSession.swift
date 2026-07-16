import Foundation

struct CelebrationCopy: Equatable, Sendable {
    let eyebrow: String
    let headline: String
    let detail: String
    let badge: String?
}

struct CelebrationSession: Equatable, Sendable {
    let id: UUID
    let milestone: TokenMilestone
    let style: CelebrationStyle
    let copy: CelebrationCopy
    let seed: UInt64
    let startTime: Date
    let duration: TimeInterval
}
