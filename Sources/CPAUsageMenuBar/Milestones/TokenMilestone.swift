import Foundation

struct TokenMilestone: Equatable, Hashable, Codable, Sendable {
    let tokens: Int64
}

struct MilestoneIdentity: Equatable, Codable, Sendable {
    let baseURL: String
    let authenticationType: AuthenticationType
}

struct MilestoneTrackerState: Equatable, Codable, Sendable {
    let dateKey: String
    let identity: MilestoneIdentity
    var lastObservedTokens: Int64
    var celebratedMilestones: Set<Int64>
    var requiresBaseline: Bool
}
