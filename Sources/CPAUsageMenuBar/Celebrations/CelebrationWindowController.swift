import AppKit
import SwiftUI

struct CelebrationPanelConfiguration {
    let frame: CGRect
    let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
    let isOpaque = false
    let hasShadow = false
    let ignoresMouseEvents = true
    let level: NSWindow.Level = .statusBar
    let collectionBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
}

@MainActor
final class CelebrationWindowController: CelebrationPresenting {
    private let screenFrames: () -> [CGRect]
    private var panels: [NSPanel] = []

    var isPresenting: Bool { !panels.isEmpty }
    var panelCount: Int { panels.count }

    init(screenFrames: @escaping () -> [CGRect] = { NSScreen.screens.map(\.frame) }) {
        self.screenFrames = screenFrames
    }

    func present(_ session: CelebrationSession) {
        guard panels.isEmpty else { return }
        panels = screenFrames().map { frame in
            let configuration = CelebrationPanelConfiguration(frame: frame)
            let panel = NSPanel(
                contentRect: configuration.frame,
                styleMask: configuration.styleMask,
                backing: .buffered,
                defer: false
            )
            panel.backgroundColor = .clear
            panel.isOpaque = configuration.isOpaque
            panel.hasShadow = configuration.hasShadow
            panel.ignoresMouseEvents = configuration.ignoresMouseEvents
            panel.level = configuration.level
            panel.collectionBehavior = configuration.collectionBehavior
            panel.hidesOnDeactivate = false
            panel.contentView = NSHostingView(rootView: AnyView(Color.clear))
            panel.orderFrontRegardless()
            return panel
        }
    }

    func dismiss() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }
}
