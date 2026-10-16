import AppKit
import SwiftUI
import StepItCore

public final class SettingsWindowController: @unchecked Sendable {
    public static let shared = SettingsWindowController()
    
    private var window: NSWindow?
    
    public init() {}
    
    @MainActor
    public func show() {
        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 620, height: 500),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            win.center()
            win.title = "StepIt Settings"
            win.contentView = NSHostingView(rootView: SettingsView())
            win.isReleasedWhenClosed = false
            self.window = win
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
