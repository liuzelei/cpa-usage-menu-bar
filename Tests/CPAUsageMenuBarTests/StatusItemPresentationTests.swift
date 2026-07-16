import Foundation
import Testing
@testable import CPAUsageMenuBar

private func statusSnapshot(tokens: Int64 = 2_340_000) -> UsageSnapshot {
    .init(requests: 42, successes: 40, failures: 2, tokens: tokens, cost: 1.25, range: .today, timezone: nil, refreshedAt: .distantPast)
}

@Test
func tokenMetricUsesCompactTodayValue() {
    #expect(StatusItemPresentation.title(metric: .tokens, snapshot: statusSnapshot()) == "2.3M")
}

@Test
func iconOnlyHasNoTitle() {
    #expect(StatusItemPresentation.title(metric: .iconOnly, snapshot: nil) == "")
}

@Test
func errorUsesWarningSymbol() {
    #expect(StatusItemPresentation.imageName(hasError: true) == "exclamationmark.circle")
}
