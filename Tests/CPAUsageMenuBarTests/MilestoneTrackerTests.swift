import Foundation
import Testing
@testable import CPAUsageMenuBar

private let milestoneCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()
private let milestoneDay = Date(timeIntervalSince1970: 1_752_624_000)
private let milestoneIdentity = MilestoneIdentity(
    baseURL: "http://keeper.local:8080",
    authenticationType: .administratorPassword
)

private func trackerWithBaseline(_ tokens: Int64) -> MilestoneTracker {
    var tracker = MilestoneTracker()
    _ = tracker.observe(tokens: tokens, date: milestoneDay, identity: milestoneIdentity, calendar: milestoneCalendar)
    return tracker
}

@Test
func firstSnapshotOnlyEstablishesBaseline() {
    var tracker = MilestoneTracker()
    #expect(tracker.observe(tokens: 9_000_000, date: milestoneDay, identity: milestoneIdentity, calendar: milestoneCalendar) == nil)
}

@Test
func crossingFixedMilestonesTriggersOnce() {
    var tracker = trackerWithBaseline(9_000_000)
    #expect(tracker.observe(tokens: 10_000_000, date: milestoneDay, identity: milestoneIdentity, calendar: milestoneCalendar) == TokenMilestone(tokens: 10_000_000))
    #expect(tracker.observe(tokens: 11_000_000, date: milestoneDay, identity: milestoneIdentity, calendar: milestoneCalendar) == nil)
    #expect(tracker.observe(tokens: 50_000_000, date: milestoneDay, identity: milestoneIdentity, calendar: milestoneCalendar) == TokenMilestone(tokens: 50_000_000))
    #expect(tracker.observe(tokens: 100_000_000, date: milestoneDay, identity: milestoneIdentity, calendar: milestoneCalendar) == TokenMilestone(tokens: 100_000_000))
}

@Test
func crossingMultipleMilestonesUsesHighest() {
    var tracker = trackerWithBaseline(9_000_000)
    #expect(tracker.observe(tokens: 120_000_000, date: milestoneDay, identity: milestoneIdentity, calendar: milestoneCalendar) == TokenMilestone(tokens: 100_000_000))
    #expect(tracker.state?.celebratedMilestones == [10_000_000, 50_000_000, 100_000_000])
}

@Test
func repeatingMilestonesContinueEveryHundredMillion() {
    var tracker = trackerWithBaseline(190_000_000)
    #expect(tracker.observe(tokens: 205_000_000, date: milestoneDay, identity: milestoneIdentity, calendar: milestoneCalendar) == TokenMilestone(tokens: 200_000_000))
    #expect(tracker.observe(tokens: 305_000_000, date: milestoneDay, identity: milestoneIdentity, calendar: milestoneCalendar) == TokenMilestone(tokens: 300_000_000))
}

@Test
func rollbackDoesNotCelebrate() {
    var tracker = trackerWithBaseline(120_000_000)
    #expect(tracker.observe(tokens: 80_000_000, date: milestoneDay, identity: milestoneIdentity, calendar: milestoneCalendar) == nil)
}

@Test
func dayAndIdentityChangesOnlyEstablishBaseline() {
    var tracker = trackerWithBaseline(9_000_000)
    let tomorrow = milestoneCalendar.date(byAdding: .day, value: 1, to: milestoneDay)!
    #expect(tracker.observe(tokens: 60_000_000, date: tomorrow, identity: milestoneIdentity, calendar: milestoneCalendar) == nil)

    let otherIdentity = MilestoneIdentity(baseURL: "http://other.local:8080", authenticationType: .administratorPassword)
    #expect(tracker.observe(tokens: 110_000_000, date: tomorrow, identity: otherIdentity, calendar: milestoneCalendar) == nil)
}

@Test
func explicitBaselineResetSuppressesNextCrossing() {
    var tracker = trackerWithBaseline(9_000_000)
    tracker.requireBaseline()
    #expect(tracker.observe(tokens: 60_000_000, date: milestoneDay, identity: milestoneIdentity, calendar: milestoneCalendar) == nil)
    #expect(tracker.observe(tokens: 100_000_000, date: milestoneDay, identity: milestoneIdentity, calendar: milestoneCalendar) == TokenMilestone(tokens: 100_000_000))
}

@Test
func savedStateRetainsDailyDeduplication() {
    var original = trackerWithBaseline(9_000_000)
    _ = original.observe(tokens: 10_000_000, date: milestoneDay, identity: milestoneIdentity, calendar: milestoneCalendar)
    var restored = MilestoneTracker(state: original.state)
    #expect(restored.observe(tokens: 11_000_000, date: milestoneDay, identity: milestoneIdentity, calendar: milestoneCalendar) == nil)
}
