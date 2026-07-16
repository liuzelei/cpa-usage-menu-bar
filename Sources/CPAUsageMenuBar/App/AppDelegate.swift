import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated static let applicationName = "CPA Usage"

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var model: UsageRefreshModel!
    private var cancellables = Set<AnyCancellable>()
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = UsageRefreshModel(
            preferences: PreferencesStore(),
            credentials: KeychainCredentialStore(),
            api: KeeperAPIClient()
        )
        configureStatusItem()
        configurePopover()
        observeModel()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.requireMilestoneBaseline() }
        }
        model.start()
        if model.configuration == nil {
            DispatchQueue.main.async { [weak self] in self?.openSettings() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatusItem()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: UsagePopoverView(
            model: model,
            openSettings: { [weak self] in self?.openSettings() },
            quit: { NSApplication.shared.terminate(nil) }
        ))
    }

    private func observeModel() {
        Publishers.CombineLatest3(model.$todaySnapshot, model.$error, model.$configuration)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in self?.updateStatusItem() }
            .store(in: &cancellables)
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let metric = model?.configuration?.menuBarMetric ?? .iconOnly
        button.title = StatusItemPresentation.title(metric: metric, snapshot: model?.todaySnapshot)
        button.image = NSImage(systemSymbolName: StatusItemPresentation.imageName(hasError: model?.error != nil), accessibilityDescription: "CPA Usage")
        button.image?.isTemplate = true
        button.imagePosition = button.title.isEmpty ? .imageOnly : .imageLeading
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApplication.shared.activate(ignoringOtherApps: true)
            Task { await model.refresh(force: false) }
        }
    }

    private func openSettings() {
        popover.performClose(nil)
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 560), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "CPA Usage 设置"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView(model: model) { [weak window] in
            window?.close()
        })
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
