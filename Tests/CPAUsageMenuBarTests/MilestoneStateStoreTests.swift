import Foundation
import Testing
@testable import CPAUsageMenuBar

@Test
func milestoneStateRoundTrips() throws {
    let suiteName = "MilestoneStateStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = MilestoneStateStore(defaults: defaults)
    let state = MilestoneTrackerState(
        dateKey: "2026-07-16",
        identity: .init(baseURL: "http://keeper.local:8080", authenticationType: .administratorPassword),
        lastObservedTokens: 50_000_000,
        celebratedMilestones: [10_000_000, 50_000_000],
        requiresBaseline: false
    )

    try store.save(state)

    #expect(store.load() == state)
}

@Test
func corruptMilestoneStateIsDiscarded() {
    let suiteName = "MilestoneStateStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(Data("not-json".utf8), forKey: MilestoneStateStore.storageKey)
    let store = MilestoneStateStore(defaults: defaults)

    #expect(store.load() == nil)
    #expect(defaults.data(forKey: MilestoneStateStore.storageKey) == nil)
}

@Test
func clearingMilestoneStateRemovesIt() throws {
    let suiteName = "MilestoneStateStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = MilestoneStateStore(defaults: defaults)
    try store.save(.init(dateKey: "2026-07-16", identity: .init(baseURL: "x", authenticationType: .cpaAPIKey), lastObservedTokens: 1, celebratedMilestones: [], requiresBaseline: true))

    store.clear()

    #expect(store.load() == nil)
}
