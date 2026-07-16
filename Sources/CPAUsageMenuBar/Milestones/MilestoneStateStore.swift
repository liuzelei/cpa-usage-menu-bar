import Foundation

protocol MilestoneStateStoring {
    func load() -> MilestoneTrackerState?
    func save(_ state: MilestoneTrackerState) throws
    func clear()
}

final class MilestoneStateStore: MilestoneStateStoring {
    static let storageKey = "token-milestone-state-v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> MilestoneTrackerState? {
        guard let data = defaults.data(forKey: Self.storageKey) else { return nil }
        do {
            return try JSONDecoder().decode(MilestoneTrackerState.self, from: data)
        } catch {
            defaults.removeObject(forKey: Self.storageKey)
            return nil
        }
    }

    func save(_ state: MilestoneTrackerState) throws {
        defaults.set(try JSONEncoder().encode(state), forKey: Self.storageKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}
