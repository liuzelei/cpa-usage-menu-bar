import Foundation

protocol PreferencesStoring {
    func load() throws -> AppConfiguration?
    func save(_ configuration: AppConfiguration) throws
    func clear()
}

final class PreferencesStore: PreferencesStoring {
    private let defaults: UserDefaults
    private let key = "active-configuration"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() throws -> AppConfiguration? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do { return try JSONDecoder().decode(AppConfiguration.self, from: data) }
        catch { throw AppError.incompatibleResponse }
    }

    func save(_ configuration: AppConfiguration) throws {
        defaults.set(try JSONEncoder().encode(configuration), forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
