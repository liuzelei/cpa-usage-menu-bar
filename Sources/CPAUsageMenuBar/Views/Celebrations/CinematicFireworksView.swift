import SwiftUI

struct CinematicFireworksView: View {
    let session: CelebrationSession
    let elapsed: TimeInterval

    private let colors: [Color] = [.yellow, .orange, .pink, .cyan, .mint, .white]

    var body: some View {
        GeometryReader { proxy in
            let particles = SeededParticleField.particles(seed: session.seed, count: 132, bounds: proxy.size)
            ZStack {
                LinearGradient(
                    colors: [.black.opacity(0.76), Color(red: 0.08, green: 0.03, blue: 0.16).opacity(0.68), .black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Canvas { context, _ in
                    for particle in particles {
                        let local = elapsed - particle.delay
                        guard local >= 0, local <= particle.lifetime else { continue }
                        let progress = local / particle.lifetime
                        let gravity = 54 * local * local
                        let point = CGPoint(
                            x: particle.origin.x + particle.velocity.dx * local,
                            y: particle.origin.y + particle.velocity.dy * local + gravity
                        )
                        let alpha = sin(progress * .pi) * celebrationEnvelope(elapsed: elapsed, duration: session.duration)
                        let radius = particle.size * (1 - progress * 0.45)
                        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                        let color = colors[particle.colorIndex % colors.count]
                        context.fill(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)), with: .color(color.opacity(alpha * 0.16)))
                        context.fill(Path(ellipseIn: rect), with: .color(color.opacity(alpha)))
                    }
                }

                VStack(spacing: 16) {
                    Text(session.copy.eyebrow)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .tracking(3)
                        .foregroundStyle(.yellow)
                    Text(session.copy.headline)
                        .font(.system(size: 46, weight: .black, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .shadow(color: .pink.opacity(0.7), radius: 20)
                    Text(session.copy.detail)
                        .font(.system(size: 19, weight: .medium, design: .rounded))
                        .minimumScaleFactor(0.65)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.82))
                    if let badge = session.copy.badge {
                        Text(badge)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(.white.opacity(0.12), in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.24)))
                    }
                }
                .frame(maxWidth: min(760, proxy.size.width - 64))
                .padding(32)
                .opacity(celebrationEnvelope(elapsed: elapsed, duration: session.duration))
                .scaleEffect(0.94 + 0.06 * min(1, elapsed / 0.6))
            }
        }
    }
}
