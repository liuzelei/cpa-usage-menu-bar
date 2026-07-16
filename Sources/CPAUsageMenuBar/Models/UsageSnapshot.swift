import Foundation

struct UsageSnapshot: Equatable, Sendable {
    let requests: Int64
    let successes: Int64
    let failures: Int64
    let tokens: Int64
    let cost: Double?
    let range: UsageRange
    let timezone: String?
    let refreshedAt: Date
}
