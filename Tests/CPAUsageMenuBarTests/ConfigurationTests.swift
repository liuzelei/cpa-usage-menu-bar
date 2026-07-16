import Foundation
import Testing
@testable import CPAUsageMenuBar

@Test
func baseURLNormalizationRemovesTrailingSlash() throws {
    let url = try AppConfiguration.normalizedBaseURL(" http://keeper.local:8318/ ")
    #expect(url.absoluteString == "http://keeper.local:8318")
}

@Test
func baseURLRejectsUnsupportedScheme() {
    #expect(throws: AppError.self) {
        try AppConfiguration.normalizedBaseURL("ftp://keeper.local")
    }
}

@Test
func rangeUsesKeeperAPIValues() {
    #expect(UsageRange.today.rawValue == "today")
    #expect(UsageRange.last24Hours.rawValue == "24h")
    #expect(UsageRange.last7Days.rawValue == "7d")
    #expect(UsageRange.last30Days.rawValue == "30d")
}

@Test
func oldConfigurationDecodesWithCelebrationsOff() throws {
    let data = Data(#"{"baseURL":"http:\/\/keeper.local:8080","authenticationType":"administratorPassword","refreshInterval":60,"menuBarMetric":"tokens","launchAtLogin":false}"#.utf8)
    let configuration = try JSONDecoder().decode(AppConfiguration.self, from: data)
    #expect(configuration.celebrationStyle == .off)
    #expect(configuration.celebrationSoundEnabled == false)
}

@Test
func celebrationConfigurationRoundTrips() throws {
    let configuration = AppConfiguration(
        baseURL: URL(string: "http://keeper.local:8080")!,
        authenticationType: .administratorPassword,
        refreshInterval: 60,
        menuBarMetric: .tokens,
        launchAtLogin: false,
        celebrationStyle: .random,
        celebrationSoundEnabled: true
    )
    let decoded = try JSONDecoder().decode(AppConfiguration.self, from: JSONEncoder().encode(configuration))
    #expect(decoded == configuration)
}
