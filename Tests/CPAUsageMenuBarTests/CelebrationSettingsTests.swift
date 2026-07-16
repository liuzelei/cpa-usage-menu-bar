import Testing
@testable import CPAUsageMenuBar

@Test
func celebrationStyleTitlesAreUserFacing() {
    #expect(CelebrationStyle.off.title == "关闭")
    #expect(CelebrationStyle.cinematic.title == "电影烟花")
    #expect(CelebrationStyle.achievementToast.title == "顶部成就通知")
    #expect(CelebrationStyle.retro.title == "复古游戏成就")
    #expect(CelebrationStyle.random.title == "每次随机")
}
