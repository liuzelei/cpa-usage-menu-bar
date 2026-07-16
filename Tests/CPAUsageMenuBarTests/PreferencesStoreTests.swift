import Foundation
import Testing
@testable import CPAUsageMenuBar

@Test
func preferencesRoundTrip() throws {
    let suiteName = "PreferencesStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = PreferencesStore(defaults: defaults)
    let configuration = AppConfiguration(
        baseURL: URL(string: "http://localhost:8318")!,
        authenticationType: .administratorPassword,
        refreshInterval: 60,
        menuBarMetric: .tokens,
        launchAtLogin: false
    )

    try store.save(configuration)

    #expect(try store.load() == configuration)
}

@Test
func clearingPreferencesRemovesConfiguration() throws {
    let suiteName = "PreferencesStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = PreferencesStore(defaults: defaults)
    try store.save(.init(baseURL: URL(string: "https://keeper.local")!, authenticationType: .cpaAPIKey, refreshInterval: 300, menuBarMetric: .cost, launchAtLogin: true))

    store.clear()

    #expect(try store.load() == nil)
}
