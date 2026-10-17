import AppKit
import StepItIR
import SwiftUI
import Combine
import StepItCore
import StepItFixtures

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var permissionsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure menu bar extra
        setupStatusItem()
        
        // Setup Floating HUD stop callback
        FloatingHUDWindowController.shared.onStopRequested = { [weak self] in
            Task { @MainActor in
                self?.stopRecording()
            }
        }
        
        // Observe WorkflowController state changes
        WorkflowController.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateStatusItemIcon(for: state)
                if state == .recording {
                    FloatingHUDWindowController.shared.show()
                } else if state == .idle {
                    FloatingHUDWindowController.shared.hide()
                }
            }
            .store(in: &cancellables)
        
        // Boot the recording engine once: driver monitors stay alive for the
        // whole app session, so the ⌥Space hotkey works in every state (fix F1).
        Task { @MainActor in
            await WorkflowController.shared.bootstrap()
        }
        
        // Hide dock icon if desired for menu bar utility, or keep accessory
        NSApp.setActivationPolicy(.accessory)
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
        let isRecording = WorkflowController.shared.state != .idle
        
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
        let recentSessions = SessionStore.shared.listSessions().prefix(6)
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
        Task { @MainActor in
            await WorkflowController.shared.toggleRecording()
        }
    }
    
    @MainActor
    @objc public func startRecording() {
        Task { @MainActor in
            await WorkflowController.shared.startRecording()
        }
    }
    
    @MainActor
    @objc public func stopRecording() {
        Task { @MainActor in
            if let session = await WorkflowController.shared.stopRecording() {
                ReviewWindowController.shared.show(for: session)
            }
        }
    }
    
    @MainActor
    @objc public func cancelRecording() {
        Task { @MainActor in
            _ = await WorkflowController.shared.stopRecording()
        }
    }
    
    @objc private func openRecentSession(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let session = try? SessionStore.shared.loadSession(id: id) else { return }
        Task { @MainActor in
            ReviewWindowController.shared.show(for: session)
        }
    }
    
    @objc private func triggerDemo() {
        Task {
            guard let session = try? await DemoSessionGenerator.generateDemoSession() else { return }
            let settings = SessionStore.shared.loadSettings()
            try? SessionStore.shared.saveSession(session)
            if let (web, _, _) = try? await PublishingCoordinator.shared.exportAll(session: session, settings: settings) {
                PublishingCoordinator.shared.openInBrowser(url: web)
            }
            await MainActor.run {
                ReviewWindowController.shared.show(for: session)
            }
        }
    }
    
    @MainActor
    @objc public func openSettings() {
        SettingsWindowController.shared.show()
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
            win.contentView = NSHostingView(rootView: PermissionsBannerView().padding())
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
