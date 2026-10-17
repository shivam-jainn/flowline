import AppKit
import StepItFixtures
import StepItEngine
import StepItPermissions
import SwiftUI

/// Settings window owned by the composition root (R/M1-07).
/// The controller, settings persistence and permissions arrive by injection.
public final class SettingsWindowController: @unchecked Sendable {
    private let controller: WorkflowController
    private let settingsStore: SettingsFileStore
    private let permissions: PermissionsManager

    private var window: NSWindow?

    public init(
        controller: WorkflowController,
        settingsStore: SettingsFileStore,
        permissions: PermissionsManager
    ) {
        self.controller = controller
        self.settingsStore = settingsStore
        self.permissions = permissions
    }

    @MainActor
    public func show() {
        let view = SettingsView(
            controller: controller,
            settings: settingsStore.load(),
            settingsStore: settingsStore,
            permissions: permissions
        )
        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 620, height: 500),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            win.center()
            win.title = "StepIt Settings"
            win.contentView = NSHostingView(rootView: view)
            win.isReleasedWhenClosed = false
            self.window = win
        } else {
            window?.contentView = NSHostingView(rootView: view)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
