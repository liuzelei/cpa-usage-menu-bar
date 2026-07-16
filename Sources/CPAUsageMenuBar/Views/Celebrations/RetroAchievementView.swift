import SwiftUI

struct RetroAchievementView: View {
    let session: CelebrationSession
    let elapsed: TimeInterval

    var body: some View {
        GeometryReader { proxy in
            let particles = SeededParticleField.particles(seed: session.seed, count: 48, bounds: proxy.size)
            ZStack {
                Color.black.opacity(0.2 * celebrationEnvelope(elapsed: elapsed, duration: session.duration))

                Canvas { context, size in
                    for y in stride(from: CGFloat.zero, through: size.height, by: 5) {
                        context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.12)))
                    }
                    for particle in particles {
                        let local = elapsed - particle.delay
                        guard local >= 0, local <= particle.lifetime else { continue }
                        let progress = local / particle.lifetime
                        let point = CGPoint(
                            x: particle.origin.x + particle.velocity.dx * local * 0.35,
                            y: particle.origin.y + particle.velocity.dy * local * 0.35
                        )
                        let side = max(2, particle.size.rounded())
                        let color: Color = particle.colorIndex.isMultiple(of: 2) ? .green : .yellow
                        context.fill(Path(CGRect(x: point.x, y: point.y, width: side, height: side)), with: .color(color.opacity((1 - progress) * 0.8)))
                    }
                }

                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        Text("★ ACHIEVEMENT UNLOCKED")
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.yellow)
                        Spacer()
                        Text(session.copy.eyebrow)
                            .foregroundStyle(.green)
                    }
                    .font(.system(size: 12, weight: .black, design: .monospaced))

                    Text(session.copy.headline.uppercased())
                        .font(.system(size: 31, weight: .black, design: .monospaced))
                        .minimumScaleFactor(0.55)
                        .lineLimit(2)
                        .foregroundStyle(.white)
                    Text(session.copy.detail)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .minimumScaleFactor(0.65)
                        .lineLimit(3)
                        .foregroundStyle(.green)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("AI NATIVE")
                            Spacer()
                            Text("99%?")
                        }
                        GeometryReader { bar in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(.white.opacity(0.14))
                                Rectangle()
                                    .fill(.green)
                                    .frame(width: bar.size.width * min(0.99, 0.18 + elapsed / session.duration * 0.81))
                            }
                        }
                        .frame(height: 13)
                    }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green.opacity(0.78))

                    if let badge = session.copy.badge {
                        Text("[ \(badge) ]")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.yellow)
                    }
                }
                .padding(24)
                .frame(maxWidth: min(620, proxy.size.width - 48))
                .background(Color(red: 0.025, green: 0.045, blue: 0.035))
                .overlay(Rectangle().stroke(.green, lineWidth: 3))
                .background(Rectangle().fill(.black).offset(x: 10, y: 10))
                .opacity(celebrationEnvelope(elapsed: elapsed, duration: session.duration))
                .scaleEffect(0.88 + min(1, elapsed / 0.35) * 0.12)
            }
        }
    }
}
