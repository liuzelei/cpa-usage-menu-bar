import AppKit
import Testing
@testable import CPAUsageMenuBar

@Test
func overlayPanelConfigurationDoesNotCaptureInputOrActivation() {
    let frame = CGRect(x: 100, y: 200, width: 800, height: 600)
    let configuration = CelebrationPanelConfiguration(frame: frame)
    #expect(configuration.frame == frame)
    #expect(configuration.isOpaque == false)
    #expect(configuration.hasShadow == false)
    #expect(configuration.ignoresMouseEvents)
    #expect(configuration.level == .statusBar)
    #expect(configuration.styleMask.contains(.borderless))
    #expect(configuration.styleMask.contains(.nonactivatingPanel))
    #expect(configuration.collectionBehavior.contains(.canJoinAllSpaces))
    #expect(configuration.collectionBehavior.contains(.fullScreenAuxiliary))
    #expect(configuration.collectionBehavior.contains(.stationary))
}

@MainActor
@Test
func windowControllerCreatesOnePanelPerDisplay() {
    let frames = [
        CGRect(x: 0, y: 0, width: 800, height: 600),
        CGRect(x: 800, y: 0, width: 1024, height: 768)
    ]
    let controller = CelebrationWindowController(screenFrames: { frames })
    let session = CelebrationSession(
        id: UUID(),
        milestone: .init(tokens: 50_000_000),
        style: .retro,
        copy: .init(eyebrow: "50M", headline: "测试", detail: "测试", badge: nil),
        seed: 1,
        startTime: .now,
        duration: 4
    )

    controller.present(session)

    #expect(controller.panelCount == 2)
    controller.dismiss()
}
