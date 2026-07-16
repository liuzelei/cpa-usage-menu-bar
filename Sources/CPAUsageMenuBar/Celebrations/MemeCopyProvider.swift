import Foundation

protocol MemeCopyProviding {
    func copy(for milestone: TokenMilestone, style: CelebrationStyle, seed: UInt64) -> CelebrationCopy
}

struct MemeCopyProvider: MemeCopyProviding {
    func copy(for milestone: TokenMilestone, style: CelebrationStyle, seed: UInt64) -> CelebrationCopy {
        let amount = Self.compactMilestone(milestone.tokens)
        var generator = SeededGenerator(seed: seed)
        let pool = pool(for: style)
        return CelebrationCopy(
            eyebrow: "TOKEN BURN · \(amount)",
            headline: pool.headlines.pick(using: &generator),
            detail: pool.details.pick(using: &generator),
            badge: pool.badges.pick(using: &generator)
        )
    }

    static func compactMilestone(_ tokens: Int64) -> String {
        if tokens >= 1_000_000_000 {
            let value = Double(tokens) / 1_000_000_000
            return value.rounded() == value ? "\(Int(value))B" : String(format: "%.1fB", value)
        }
        if tokens >= 1_000_000 {
            let value = Double(tokens) / 1_000_000
            return value.rounded() == value ? "\(Int(value))M" : String(format: "%.1fM", value)
        }
        return "\(tokens)"
    }

    private func pool(for style: CelebrationStyle) -> CopyPool {
        switch style {
        case .cinematic:
            CopyPool(
                headlines: [
                    "恭喜，算力已为你点亮夜空",
                    "今天的 Token，烧得很有艺术感",
                    "AI Native 进度 +1"
                ],
                details: [
                    "Token 没有消失，只是转化成了智能。",
                    "GPU 看见你已经开始冒汗。",
                    "这一刻，硅谷的风都带着账单味。"
                ],
                badges: ["算力烟花", "PROMPT POWERED", "烧得漂亮"]
            )
        case .retro:
            CopyPool(
                headlines: [
                    "成就解锁：人形吞吐机",
                    "TOKEN COMBO!",
                    "AI 原住民经验值上涨"
                ],
                details: [
                    "钱包已进入只读模式。",
                    "Prompt 很短，账单很长。",
                    "预算条 -100，生产力是否 +100 有待观察。"
                ],
                badges: ["ACHIEVEMENT", "LEVEL UP", "NO REFUND"]
            )
        case .achievementToast, .off, .random:
            CopyPool(
                headlines: [
                    "今日烧 Token KPI 已达成",
                    "恭喜你离 AI Native 更近一步",
                    "这波不是消费，是认知升级"
                ],
                details: [
                    "AI Native 进度 +1，预算条 -100。",
                    "你的上下文窗口，今天很有存在感。",
                    "领导问产出，你可以先展示这个成就。"
                ],
                badges: ["里程碑达成", "效率玄学", "含金量待定"]
            )
        }
    }
}

private struct CopyPool {
    let headlines: [String]
    let details: [String]
    let badges: [String]
}

struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E3779B97F4A7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}

private extension Array {
    func pick(using generator: inout SeededGenerator) -> Element {
        self[Int(generator.next() % UInt64(count))]
    }
}
