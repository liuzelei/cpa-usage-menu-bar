import CoreGraphics
import Testing
@testable import CPAUsageMenuBar

@Test
func sameSeedCreatesSameParticles() {
    let first = SeededParticleField.particles(seed: 42, count: 40, bounds: CGSize(width: 800, height: 600))
    let second = SeededParticleField.particles(seed: 42, count: 40, bounds: CGSize(width: 800, height: 600))
    #expect(first == second)
}

@Test
func particlesStayWithinInitialBounds() {
    let particles = SeededParticleField.particles(seed: 7, count: 100, bounds: CGSize(width: 400, height: 300))
    #expect(particles.allSatisfy { (0...400).contains($0.origin.x) && (0...300).contains($0.origin.y) })
}

@Test
func requestedParticleCountIsRespected() {
    #expect(SeededParticleField.particles(seed: 1, count: 128, bounds: CGSize(width: 10, height: 10)).count == 128)
}
