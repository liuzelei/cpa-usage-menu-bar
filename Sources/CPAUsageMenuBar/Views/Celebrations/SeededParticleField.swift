import CoreGraphics
import Foundation

struct SeededParticle: Equatable, Sendable {
    let origin: CGPoint
    let velocity: CGVector
    let colorIndex: Int
    let size: CGFloat
    let delay: TimeInterval
    let lifetime: TimeInterval
    let phase: Double
}

enum SeededParticleField {
    static func particles(seed: UInt64, count: Int, bounds: CGSize) -> [SeededParticle] {
        guard count > 0 else { return [] }
        var generator = SeededGenerator(seed: seed)
        return (0..<count).map { _ in
            let angle = unit(&generator) * Double.pi * 2
            let speed = 36 + unit(&generator) * 180
            return SeededParticle(
                origin: CGPoint(x: unit(&generator) * bounds.width, y: unit(&generator) * bounds.height),
                velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                colorIndex: Int(generator.next() % 6),
                size: 2 + unit(&generator) * 6,
                delay: unit(&generator) * 1.4,
                lifetime: 1.2 + unit(&generator) * 1.8,
                phase: unit(&generator) * Double.pi * 2
            )
        }
    }

    private static func unit(_ generator: inout SeededGenerator) -> CGFloat {
        CGFloat(Double(generator.next()) / Double(UInt64.max))
    }
}
