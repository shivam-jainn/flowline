import AppKit
import SwiftUI

// MARK: - First-run persistence (fresh install → show once)

/// Tracks whether the first-run intro has been shown. UserDefaults-backed
/// so a fresh install (no defaults) shows the tour exactly once.
public struct FirstRunStore: @unchecked Sendable {
    private static let key = "com.flowline.firstRun.completed"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var hasCompleted: Bool {
        defaults.bool(forKey: Self.key)
    }

    public func markCompleted() {
        defaults.set(true, forKey: Self.key)
    }

    public func resetForTesting() {
        defaults.removeObject(forKey: Self.key)
    }

    /// Fresh install shows the tour: never completed before. Callers pass
    /// `hasSessions` so upgrades with an existing library skip the tour
    /// even if the flag was somehow cleared.
    public func shouldShow(hasSessions: Bool) -> Bool {
        !hasCompleted && !hasSessions
    }
}

// MARK: - First-run window (composition-owned, like Settings/Review)

/// Centered welcome window shown once on first launch. Owns no state
/// besides presentation; completion is recorded on any dismiss path.
public final class FirstRunWindowController: @unchecked Sendable {
    private let store: FirstRunStore
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    public init(store: FirstRunStore = FirstRunStore()) {
        self.store = store
    }

    /// Shows the tour when this is a true first run. Returns whether it showed.
    @MainActor
    @discardableResult
    public func showIfNeeded(hasSessions: Bool, onGetStarted: (() -> Void)? = nil) -> Bool {
        guard store.shouldShow(hasSessions: hasSessions) else { return false }
        show(onGetStarted: onGetStarted)
        return true
    }

    @MainActor
    public func show(onGetStarted: (() -> Void)? = nil, startingAt: FirstRunPhase = .intro) {
        let view = FirstRunIntroView(
            onDone: { [weak self] in
                self?.dismiss()
                onGetStarted?()
            },
            onSkip: { [weak self] in
                self?.dismiss()
                onGetStarted?()
            },
            startingAt: startingAt
        )
        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 960, height: 780),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            win.center()
            win.title = "Welcome to Flowline"
            win.minSize = NSSize(width: 900, height: 740)
            win.isReleasedWhenClosed = false
            win.contentView = NSHostingView(rootView: view)
            self.window = win
            // Red X also completes the tour — any dismiss path records it.
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: win,
                queue: .main
            ) { [weak self] _ in self?.store.markCompleted() }
        } else {
            window?.contentView = NSHostingView(rootView: view)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Dev / Settings retrigger: jump straight to the onboarding setup
    /// phase (defaults picker) without replaying the tour.
    @MainActor
    public func showSetup() {
        show(startingAt: .setup)
    }

    /// Clears tour + defaults state so the next launch replays first-run.
    /// Dev escape hatch, also surfaced in Settings → Onboarding.
    public func resetForRelaunch() {
        store.resetForTesting()
        OnboardingDefaultsStore.reset()
    }

    @MainActor
    public func dismiss() {
        store.markCompleted()
        window?.close()
    }
}
