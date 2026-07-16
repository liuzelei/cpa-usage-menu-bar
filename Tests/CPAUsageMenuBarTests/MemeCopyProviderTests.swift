import Testing
@testable import CPAUsageMenuBar

@Test
func milestoneFormattingUsesCompactValues() {
    #expect(MemeCopyProvider.compactMilestone(10_000_000) == "10M")
    #expect(MemeCopyProvider.compactMilestone(100_000_000) == "100M")
    #expect(MemeCopyProvider.compactMilestone(1_200_000_000) == "1.2B")
}

@Test
func sameSeedProducesSameCopy() {
    let provider = MemeCopyProvider()
    let milestone = TokenMilestone(tokens: 50_000_000)
    #expect(provider.copy(for: milestone, style: .cinematic, seed: 42) == provider.copy(for: milestone, style: .cinematic, seed: 42))
}

@Test(arguments: [CelebrationStyle.cinematic, .achievementToast, .retro])
func fixedStylesProduceCompleteMilestoneCopy(style: CelebrationStyle) {
    let provider = MemeCopyProvider()
    let copy = provider.copy(for: .init(tokens: 100_000_000), style: style, seed: 7)
    #expect(!copy.headline.isEmpty)
    #expect(!copy.detail.isEmpty)
    #expect(copy.eyebrow.contains("100M") || copy.headline.contains("100M"))
}
