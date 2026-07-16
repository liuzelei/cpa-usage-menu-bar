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
