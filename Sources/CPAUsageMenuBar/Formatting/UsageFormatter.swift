import Foundation

enum UsageFormatter {
    static func compactNumber(_ value: Int64) -> String {
        let thresholds: [(Double, String)] = [
            (1_000_000_000, "B"),
            (1_000_000, "M"),
            (1_000, "K")
        ]
        for (threshold, suffix) in thresholds where Double(value) >= threshold {
            let scaled = Double(value) / threshold
            return String(format: scaled >= 10 ? "%.0f%@" : "%.1f%@", scaled, suffix)
        }
        return String(value)
    }

    static func statusText(metric: MenuBarMetric, snapshot: UsageSnapshot?) -> String {
        guard metric != .iconOnly else { return "" }
        guard let snapshot else { return "--" }
        switch metric {
        case .iconOnly: return ""
        case .tokens: return compactNumber(snapshot.tokens)
        case .requests: return compactNumber(snapshot.requests)
        case .cost: return snapshot.cost.map { cost($0) } ?? "--"
        }
    }

    static func successRate(_ snapshot: UsageSnapshot) -> String {
        let total = snapshot.successes + snapshot.failures
        guard total > 0 else { return "0.0%" }
        return String(format: "%.1f%%", Double(snapshot.successes) / Double(total) * 100)
    }

    static func cost(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}
