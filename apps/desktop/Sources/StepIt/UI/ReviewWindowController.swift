import AppKit
import StepItIR
import StepItEngine
import StepItStorage
import SwiftUI

/// Review window owned by the composition root (R/M1-07).
/// All collaborators are injected; the window is presented per session.
public final class ReviewWindowController: @unchecked Sendable {
    private let synthesis: any StepSynthesisService
    private let publisher: any ReviewPublishingService
    private let store: SessionStore
    private let settingsStore: SettingsFileStore

    /// Opens Settings; wired by the composition root to the settings window.
    public var onOpenSettings: (() -> Void)?

    private var window: NSWindow?

    public init(
        synthesis: any StepSynthesisService,
        publisher: any ReviewPublishingService,
        store: SessionStore,
        settingsStore: SettingsFileStore
    ) {
        self.synthesis = synthesis
        self.publisher = publisher
        self.store = store
        self.settingsStore = settingsStore
    }

    @MainActor
    public func show(for session: StepSession) {
        let reviewView = ReviewWindow(
            session: session,
            settings: settingsStore.load(),
            store: store,
            synthesis: synthesis,
            publisher: publisher,
            onOpenSettings: { [weak self] in self?.onOpenSettings?() }
        )
        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 1050, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )

            win.center()
            win.title = "StepIt — Review & Publish"
            win.titleVisibility = .visible
            win.minSize = NSSize(width: 960, height: 600)
            win.contentView = NSHostingView(rootView: reviewView)
            win.isReleasedWhenClosed = false

            self.window = win
        } else {
            window?.contentView = NSHostingView(rootView: reviewView)
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
