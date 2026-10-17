import AppKit
import StepItEngine
import StepItFixtures
import StepItIR
import SwiftUI
import Combine

/// Menu-bar app delegate (R/M1-07: composition-owned).
/// Every collaborator comes from the injected `AppComposition` — no singletons.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    private let composition: AppComposition
    private var statusItem: NSStatusItem!
    private var permissionsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    public init(composition: AppComposition) {
        self.composition = composition
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Identity line for support: proves which copy launched (rules out
        // stale duplicates / translocation when permissions misbehave).
        NSLog(
            "StepIt launch: id=%s path=%s",
            Bundle.main.bundleIdentifier ?? "none",
            Bundle.main.bundleURL.path
        )
        // Configure menu bar extra
        setupStatusItem()

        // Setup Floating HUD stop callback
        composition.hud.onStopRequested = { [weak self] in
            Task { @MainActor in
                self?.stopRecording()
            }
        }

        // Observe controller state changes
        composition.controller.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateStatusItemIcon(for: state)
                if state == .recording {
                    self?.composition.hud.show()
                } else if state == .idle {
                    self?.composition.hud.hide()
                }
            }
            .store(in: &cancellables)

        // Boot the recording engine once: driver monitors stay alive for the
        // whole app session, so the ⌥Space hotkey works in every state (fix F1).
        Task { @MainActor in
            await composition.boot()
        }

        // Startup permission gate: check screen-recording + accessibility and
        // notify the user immediately if anything is missing.
        showPermissionsIfNeeded()

        // Hide dock icon if desired for menu bar utility, or keep accessory
        NSApp.setActivationPolicy(.accessory)
    }

    /// Shows the permissions window when screen-recording or accessibility
    /// is missing, so the user is notified at startup rather than hitting a
    /// silent empty recording later. Also triggers the OS prompts so the
    /// user gets the system dialog, not just our window.
    private func showPermissionsIfNeeded() {
        let missingScreen = !composition.permissions.hasScreenRecordingPermission
        let missingAX = !composition.permissions.hasAccessibilityPermission
        guard missingScreen || missingAX else { return }
        // Trigger the OS-level prompts first (these post the system dialog).
        if missingScreen {
            _ = composition.permissions.requestScreenRecordingPermission()
        }
        if missingAX {
            _ = composition.permissions.requestAccessibilityPermission()
        }
        // Then open our window listing exactly what is missing.
        openPermissions()
    }

    /// Recording-time gate: refuse to start when permissions are missing and
    /// tell the user exactly what to enable. Without this, recording produces
    /// black pill-only frames (no Screen Recording) and no click events at
    /// all (no Accessibility) — the "screen not showing for anything" bug.
    private func ensurePermissionsForRecording() -> Bool {
        let missingScreen = !composition.permissions.hasScreenRecordingPermission
        let missingAX = !composition.permissions.hasAccessibilityPermission
        guard missingScreen || missingAX else { return true }
        var parts: [String] = []
        if missingScreen { parts.append("Screen Recording (else captures are black)") }
        if missingAX { parts.append("Accessibility (else clicks are never seen)") }
        let alert = NSAlert()
        alert.messageText = "StepIt needs system permissions"
        alert.informativeText = "Missing: " + parts.joined(separator: " + ")
            + ". Grant them in System Settings, then start recording again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Permissions")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openPermissions()
        }
        return false
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "StepIt")
            button.action = #selector(statusItemClicked)
            button.target = self
        }
        buildMenu()
    }

    private func updateStatusItemIcon(for state: RecordingState) {
        guard let button = statusItem.button else { return }
        switch state {
        case .recording:
            button.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")
            button.contentTintColor = .systemRed
        case .paused:
            button.image = NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: "Paused")
            button.contentTintColor = .systemOrange
        case .idle:
            button.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "StepIt")
            button.contentTintColor = nil
        }
        buildMenu()
    }

    @objc private func statusItemClicked() {
        buildMenu()
        statusItem.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func buildMenu() {
        let menu = NSMenu()
        let isRecording = composition.controller.state != .idle

        if isRecording {
            let stopItem = NSMenuItem(title: "Stop Recording & Synthesize", action: #selector(stopRecording), keyEquivalent: "")
            stopItem.target = self
            menu.addItem(stopItem)

            let cancelItem = NSMenuItem(title: "Cancel Recording", action: #selector(cancelRecording), keyEquivalent: "")
            cancelItem.target = self
            menu.addItem(cancelItem)
        } else {
            let startItem = NSMenuItem(title: "Start Recording (⌥ Space)", action: #selector(startRecording), keyEquivalent: "")
            startItem.target = self
            menu.addItem(startItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Recent Sessions Submenu
        let recentMenu = NSMenu()
        let recentSessions = composition.store.listSessions().prefix(6)
        if recentSessions.isEmpty {
            let emptyItem = NSMenuItem(title: "No Recent Sessions", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            recentMenu.addItem(emptyItem)
        } else {
            for session in recentSessions {
                let item = NSMenuItem(title: "\(session.title) (\(session.steps.count) steps)", action: #selector(openRecentSession(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = session.id
                recentMenu.addItem(item)
            }
        }
        let recentItem = NSMenuItem(title: "Recent Sessions", action: nil, keyEquivalent: "")
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)

        // Quick Demo
        let demoItem = NSMenuItem(title: "Build Demo Session...", action: #selector(triggerDemo), keyEquivalent: "")
        demoItem.target = self
        menu.addItem(demoItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let permissionsItem = NSMenuItem(title: "macOS Permissions...", action: #selector(openPermissions), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit StepIt", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @MainActor
    @objc public func toggleRecording() {
        guard ensurePermissionsForRecording() else { return }
        Task { @MainActor in
            await composition.controller.toggleRecording()
        }
    }

    @MainActor
    @objc public func startRecording() {
        guard ensurePermissionsForRecording() else { return }
        Task { @MainActor in
            await composition.controller.startRecording()
        }
    }

    @MainActor
    @objc public func stopRecording() {
        Task { @MainActor in
            if let session = await composition.controller.stopRecording() {
                composition.reviewWindows.show(for: session)
            }
        }
    }

    @MainActor
    @objc public func cancelRecording() {
        Task { @MainActor in
            _ = await composition.controller.stopRecording()
        }
    }

    @objc private func openRecentSession(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let session = try? composition.store.loadSession(id: id) else { return }
        Task { @MainActor in
            composition.reviewWindows.show(for: session)
        }
    }

    @objc private func triggerDemo() {
        Task {
            let settings = composition.settingsStore.load()
            let generator = DemoSessionGenerator(store: composition.store)
            guard let session = try? await generator.generate() else { return }
            try? composition.store.saveSession(session)
            if let (web, _, _) = try? await composition.publisher.exportAll(
                session: session,
                publishing: settings.publishing
            ) {
                composition.publisher.openInBrowser(url: web)
            }
            await MainActor.run {
                composition.reviewWindows.show(for: session)
            }
        }
    }

    @MainActor
    @objc public func openSettings() {
        composition.settingsWindows.show()
    }

    @objc private func openPermissions() {
        if permissionsWindow == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 480, height: 320),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            win.center()
            win.title = "StepIt System Permissions"
            win.contentView = NSHostingView(
                rootView: PermissionsBannerView(
                    manager: composition.permissions,
                    onContinue: { [weak self] in
                        self?.permissionsWindow?.close()
                        self?.startRecording()
                    }
                ).padding()
            )
            win.isReleasedWhenClosed = false
            self.permissionsWindow = win
        }
        permissionsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
