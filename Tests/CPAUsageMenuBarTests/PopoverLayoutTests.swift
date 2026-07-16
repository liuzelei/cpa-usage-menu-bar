import Testing
import SwiftUI
@testable import CPAUsageMenuBar

@Test
func popoverWidthKeepsPaddingOutsideContent() {
    #expect(PopoverLayout.contentWidth == 360)
    #expect(PopoverLayout.padding == 16)
    #expect(PopoverLayout.totalWidth == 392)
}

@Test
func popoverHostOwnsTheFullPaddedWidth() {
    #expect(PopoverLayout.hostWidth == 392)
    #expect(PopoverLayout.hostWidth - PopoverLayout.padding * 2 == PopoverLayout.contentWidth)
}

@Test
func popoverHostingUsesPreferredContentSizeOnly() {
    #expect(PopoverLayout.hostingSizingOptions == [.preferredContentSize])
}
