import Foundation
import Testing
@testable import CPAUsageMenuBar

@Test
func compactNumbersUseShortSuffixes() {
    #expect(UsageFormatter.compactNumber(999) == "999")
    #expect(UsageFormatter.compactNumber(1_200) == "1.2K")
    #expect(UsageFormatter.compactNumber(2_340_000) == "2.3M")
    #expect(UsageFormatter.compactNumber(3_600_000_000) == "3.6B")
}

@Test
func successRateUsesSuccessAndFailureCounts() {
    let snapshot = UsageSnapshot(
        requests: 4,
        successes: 3,
        failures: 1,
        tokens: 10,
        cost: 0.5,
        range: .today,
        timezone: nil,
        refreshedAt: .distantPast
    )
    #expect(UsageFormatter.successRate(snapshot) == "75.0%")
}

@Test
func unavailableSnapshotUsesPlaceholderStatusText() {
    #expect(UsageFormatter.statusText(metric: .tokens, snapshot: nil) == "--")
    #expect(UsageFormatter.statusText(metric: .iconOnly, snapshot: nil) == "")
}
