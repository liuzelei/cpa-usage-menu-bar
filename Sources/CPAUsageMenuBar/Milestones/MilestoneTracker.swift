import Foundation

protocol MilestoneTracking {
    var state: MilestoneTrackerState? { get }
    mutating func observe(tokens: Int64, date: Date, identity: MilestoneIdentity, calendar: Calendar) -> TokenMilestone?
    mutating func requireBaseline()
}

struct MilestoneTracker: MilestoneTracking {
    private(set) var state: MilestoneTrackerState?

    init(state: MilestoneTrackerState? = nil) {
        self.state = state
    }

    mutating func observe(
        tokens: Int64,
        date: Date,
        identity: MilestoneIdentity,
        calendar: Calendar
    ) -> TokenMilestone? {
        let dateKey = Self.dateKey(for: date, calendar: calendar)
        guard var currentState = state,
              currentState.dateKey == dateKey,
              currentState.identity == identity else {
            state = MilestoneTrackerState(
                dateKey: dateKey,
                identity: identity,
                lastObservedTokens: tokens,
                celebratedMilestones: [],
                requiresBaseline: false
            )
            return nil
        }

        if currentState.requiresBaseline || tokens < currentState.lastObservedTokens {
            currentState.lastObservedTokens = tokens
            currentState.requiresBaseline = false
            state = currentState
            return nil
        }

        let crossed = Self.thresholds(upTo: tokens).filter {
            currentState.lastObservedTokens < $0
                && $0 <= tokens
                && !currentState.celebratedMilestones.contains($0)
        }
        currentState.lastObservedTokens = tokens
        guard let highest = crossed.max() else {
            state = currentState
            return nil
        }
        currentState.celebratedMilestones.insert(highest)
        state = currentState
        return TokenMilestone(tokens: highest)
    }

    mutating func requireBaseline() {
        state?.requiresBaseline = true
    }

    static func thresholds(upTo tokens: Int64) -> [Int64] {
        guard tokens >= 10_000_000 else { return [] }
        var values: [Int64] = [10_000_000, 50_000_000, 100_000_000]
        if tokens >= 200_000_000 {
            values.append(contentsOf: stride(from: Int64(200_000_000), through: tokens, by: 100_000_000))
        }
        return values.filter { $0 <= tokens }
    }

    private static func dateKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
