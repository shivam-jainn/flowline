import AppKit
import FlowlineIR
import FlowlineEngine
import FlowlineStorage
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
                contentRect: NSRect(x: 100, y: 100, width: 1320, height: 840),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )

            win.center()
            win.titleVisibility = .visible
            win.minSize = NSSize(width: 1180, height: 720)
            win.collectionBehavior = [.fullScreenPrimary, .managed]
            win.contentView = NSHostingView(rootView: reviewView)
            win.isReleasedWhenClosed = false

            self.window = win
        } else {
            window?.contentView = NSHostingView(rootView: reviewView)
        }

        // Close-safe: isReleasedWhenClosed=false keeps the window reusable
        // after the user closes it, and per-session title identifies it.
        // No activate here: the automatic post-stop show must not steal
        // focus — explicit menu/Dock actions activate before calling show.
        window?.title = "Flowline — \(session.title)"
        window?.makeKeyAndOrderFront(nil)
    }
}
