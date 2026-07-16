import SwiftUI

struct AchievementToastView: View {
    let session: CelebrationSession
    let elapsed: TimeInterval

    private let colors: [Color] = [.yellow, .pink, .cyan, .orange, .mint, .purple]

    var body: some View {
        GeometryReader { proxy in
            let confettiBounds = CGSize(width: proxy.size.width, height: min(360, proxy.size.height * 0.55))
            let particles = SeededParticleField.particles(seed: session.seed, count: 72, bounds: confettiBounds)
            ZStack(alignment: .top) {
                Canvas { context, _ in
                    for particle in particles {
                        let local = elapsed - particle.delay * 0.55
                        guard local >= 0, local <= particle.lifetime + 1 else { continue }
                        let x = particle.origin.x + sin(local * 3 + particle.phase) * 26
                        let y = particle.origin.y + local * (70 + abs(particle.velocity.dy) * 0.35)
                        let alpha = max(0, 1 - local / (particle.lifetime + 1)) * celebrationEnvelope(elapsed: elapsed, duration: session.duration)
                        let rect = CGRect(x: x, y: y, width: particle.size * 1.6, height: particle.size * 0.75)
                        context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(colors[particle.colorIndex % colors.count].opacity(alpha)))
                    }
                }

                HStack(spacing: 18) {
                    ZStack {
                        Circle().fill(.yellow.gradient)
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.black.opacity(0.78))
                    }
                    .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(session.copy.eyebrow)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let badge = session.copy.badge {
                                Text(badge)
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.yellow.opacity(0.22), in: Capsule())
                            }
                        }
                        Text(session.copy.headline)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.65)
                            .lineLimit(2)
                        Text(session.copy.detail)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .minimumScaleFactor(0.7)
                            .lineLimit(2)
                    }
                }
                .padding(20)
                .frame(maxWidth: min(620, proxy.size.width - 40))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.32)))
                .shadow(color: .black.opacity(0.28), radius: 30, y: 14)
                .padding(.top, max(24, proxy.safeAreaInsets.top + 16))
                .offset(y: toastOffset)
                .opacity(celebrationEnvelope(elapsed: elapsed, duration: session.duration))
            }
        }
    }

    private var toastOffset: CGFloat {
        let progress = min(1, max(0, elapsed / 0.55))
        let eased = 1 - pow(1 - progress, 3)
        return -150 + 150 * eased
    }
}
