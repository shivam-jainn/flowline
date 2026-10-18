import AppKit

/// Native main menu for the Dock-app Flowline (menu-bar → Dock conversion).
///
/// Every item targets the shared `AppDelegate` action methods — the same
/// selectors the menu-bar status item uses — so there is exactly one code
/// path per command (start/stop/cancel recording, demo, settings,
/// permissions, recent sessions, quit). No duplicates, no singletons: the
/// delegate is injected by the caller (composition-owned, like everything
/// else behind `AppComposition`).
public enum MainMenuBuilder {
    /// Rendering-only snapshot of a recent session for File → Open Recent.
    public struct RecentSession: Sendable {
        public let id: String
        public let title: String
        public let stepCount: Int

        public init(id: String, title: String, stepCount: Int) {
            self.id = id
            self.title = title
            self.stepCount = stepCount
        }
    }

    /// Builds the full main menu (App, File, Window, Help).
    @MainActor
    public static func build(
        delegate: AppDelegate,
        recentSessions: [RecentSession],
        isRecording: Bool
    ) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(appMenu(delegate: delegate))
        menu.addItem(fileMenu(
            delegate: delegate,
            recentSessions: recentSessions,
            isRecording: isRecording
        ))
        menu.addItem(windowMenu())
        menu.addItem(helpMenu(delegate: delegate))
        return menu
    }

    // MARK: - App menu (About, Settings, Permissions, Quit)

    private static func appMenu(delegate: AppDelegate) -> NSMenuItem {
        let submenu = NSMenu()
        // Standard About panel via the responder chain (target nil → NSApp).
        submenu.addItem(NSMenuItem(
            title: "About Flowline",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        ))
        submenu.addItem(.separator())
        submenu.addItem(menuItem(
            "Settings…",
            action: #selector(AppDelegate.openSettings),
            target: delegate,
            key: ","
        ))
        submenu.addItem(menuItem(
            "macOS Permissions…",
            action: #selector(AppDelegate.openPermissions),
            target: delegate
        ))
        submenu.addItem(.separator())
        submenu.addItem(menuItem(
            "Quit Flowline",
            action: #selector(AppDelegate.quitApp),
            target: delegate,
            key: "q"
        ))
        let root = NSMenuItem(title: "Flowline", action: nil, keyEquivalent: "")
        root.submenu = submenu
        return root
    }

    // MARK: - File menu (recording commands shared with the status item)

    private static func fileMenu(
        delegate: AppDelegate,
        recentSessions: [RecentSession],
        isRecording: Bool
    ) -> NSMenuItem {
        let submenu = NSMenu(title: "File")
        let start = menuItem(
            "Start Recording",
            action: #selector(AppDelegate.startRecording),
            target: delegate,
            key: " ",
            modifiers: .option
        )
        start.isEnabled = !isRecording
        submenu.addItem(start)
        let stop = menuItem(
            "Stop Recording & Synthesize",
            action: #selector(AppDelegate.stopRecording),
            target: delegate
        )
        stop.isEnabled = isRecording
        submenu.addItem(stop)
        let cancel = menuItem(
            "Cancel Recording",
            action: #selector(AppDelegate.cancelRecording),
            target: delegate
        )
        cancel.isEnabled = isRecording
        submenu.addItem(cancel)
        submenu.addItem(.separator())
        submenu.addItem(menuItem(
            "Build Demo Session…",
            action: #selector(AppDelegate.triggerDemo),
            target: delegate
        ))
        submenu.addItem(openRecentMenuItem(delegate: delegate, sessions: recentSessions))
        let root = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        root.submenu = submenu
        return root
    }

    /// File → Open Recent, mirroring the status-item Recent Sessions list.
    /// Items reuse `openRecentSession:` so both menus run the same code.
    private static func openRecentMenuItem(
        delegate: AppDelegate,
        sessions: [RecentSession]
    ) -> NSMenuItem {
        let recent = NSMenu(title: "Open Recent")
        if sessions.isEmpty {
            let empty = NSMenuItem(title: "No Recent Sessions", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recent.addItem(empty)
        } else {
            for session in sessions {
                let item = NSMenuItem(
                    title: "\(session.title) (\(session.stepCount) steps)",
                    action: #selector(AppDelegate.openRecentSession(_:)),
                    keyEquivalent: ""
                )
                item.target = delegate
                item.representedObject = session.id
                recent.addItem(item)
            }
        }
        let root = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        root.submenu = recent
        return root
    }

    // MARK: - Window menu (standard items via the responder chain)

    private static func windowMenu() -> NSMenuItem {
        let submenu = NSMenu(title: "Window")
        submenu.addItem(NSMenuItem(
            title: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        ))
        submenu.addItem(NSMenuItem(
            title: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        ))
        submenu.addItem(.separator())
        submenu.addItem(NSMenuItem(
            title: "Close Window",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        ))
        submenu.addItem(.separator())
        submenu.addItem(NSMenuItem(
            title: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        ))
        // Gives the menu the standard window-list behavior.
        NSApp.windowsMenu = submenu
        let root = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        root.submenu = submenu
        return root
    }

    // MARK: - Help menu

    private static func helpMenu(delegate: AppDelegate) -> NSMenuItem {
        let submenu = NSMenu(title: "Help")
        submenu.addItem(menuItem(
            "Flowline Settings",
            action: #selector(AppDelegate.openSettings),
            target: delegate
        ))
        submenu.addItem(menuItem(
            "macOS Permissions Help",
            action: #selector(AppDelegate.openPermissions),
            target: delegate
        ))
        let root = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        root.submenu = submenu
        return root
    }

    // MARK: - Helper

    private static func menuItem(
        _ title: String,
        action: Selector?,
        target: AnyObject?,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        if !key.isEmpty {
            item.keyEquivalentModifierMask = modifiers
        }
        return item
    }
}
