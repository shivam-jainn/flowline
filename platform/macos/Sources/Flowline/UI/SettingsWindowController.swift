import AppKit
import FlowlineFixtures
import FlowlineEngine
import FlowlinePermissions
import SwiftUI

/// Settings window owned by the composition root (R/M1-07).
/// The controller, settings persistence and permissions arrive by injection.
public final class SettingsWindowController: @unchecked Sendable {
    private let controller: WorkflowController
    private let settingsStore: SettingsFileStore
    private let permissions: PermissionsManager
    private let firstRun: FirstRunWindowController?

    private var window: NSWindow?

    public init(
        controller: WorkflowController,
        settingsStore: SettingsFileStore,
        permissions: PermissionsManager,
        firstRun: FirstRunWindowController? = nil
    ) {
        self.controller = controller
        self.settingsStore = settingsStore
        self.permissions = permissions
        self.firstRun = firstRun
    }

    @MainActor
    public func show() {
        let view = SettingsView(
            controller: controller,
            settings: settingsStore.load(),
            settingsStore: settingsStore,
            permissions: permissions,
            firstRun: firstRun,
            onClose: { [weak self] in self?.window?.close() }
        )
        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 780, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            win.center()
            win.title = "Flowline Settings"
            win.minSize = NSSize(width: 720, height: 520)
            win.contentView = NSHostingView(rootView: view)
            win.isReleasedWhenClosed = false
            self.window = win
        } else {
            window?.contentView = NSHostingView(rootView: view)
        }
        window?.makeKeyAndOrderFront(nil)
        // No activate here: callers with an explicit user action behind them
        // (menu clicks) activate first; automatic shows must not steal focus.
    }
}
