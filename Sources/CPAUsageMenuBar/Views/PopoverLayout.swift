import SwiftUI

enum PopoverLayout {
    static let contentWidth: CGFloat = 360
    static let padding: CGFloat = 16
    static let hostWidth = contentWidth + padding * 2
    static let totalWidth = hostWidth
    static let hostingSizingOptions: NSHostingSizingOptions = [.preferredContentSize]
}
