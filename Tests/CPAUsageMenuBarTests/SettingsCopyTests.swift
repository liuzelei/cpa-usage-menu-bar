import Testing
@testable import CPAUsageMenuBar

@Test
func keeperURLCopyIsExplicit() {
    #expect(SettingsCopy.keeperURLLabel == "Keeper 服务地址")
    #expect(SettingsCopy.keeperURLPlaceholder == "例如：http://192.168.1.10:8080")
    #expect(SettingsCopy.keeperURLHelp == "CPA Usage Keeper 仪表盘的访问地址")
}
