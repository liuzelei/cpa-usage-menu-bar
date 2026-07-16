import Testing
@testable import CPAUsageMenuBar

@Test
func popoverWidthKeepsPaddingOutsideContent() {
    #expect(PopoverLayout.contentWidth == 360)
    #expect(PopoverLayout.padding == 16)
    #expect(PopoverLayout.totalWidth == 392)
}
