import Foundation
import AppKit
import StepItCore

public struct CLICommands {
    public static func handle(arguments: [String]) async {
        let args = Array(arguments.dropFirst()) // drop executable name
        let command = args.first ?? "app"
        
        switch command {
        case "demo":
            await runDemo()
            
        case "list":
            listSessions()
            
        case "status":
            showStatus()
            
        case "export":
            let sessionId = args.count > 1 ? args[1] : ""
            await exportSession(id: sessionId)
            
        case "help", "--help", "-h":
            printHelp()
            
        case "app":
            // Run native GUI app
            runGUIApp()
            
        default:
            print("Unknown command: \(command)")
            printHelp()
            exit(1)
        }
    }
    
    private static func printHelp() {
        print("""
        ⚡️ StepIt — Effortless step-by-step workflow capture & AI synthesis for macOS.

        Usage:
          stepit [command]

        Available Commands:
          app        Launch the native StepIt Menu Bar & Floating HUD app (default)
          demo       Generate an end-to-end sample guide, export Web/PDF/MD, and open in browser
          list       List all saved recording sessions
          export     Export a saved session by ID (e.g. stepit export sess_123456)
          status     Check macOS permissions (Screen Recording, Accessibility) & Gateway settings
          help       Show this help message

        Hotkeys (when app is running):
          ⌥ Space    Start / Stop recording workflow
        """)
    }
    
    private static func showStatus() {
        print("⚡️ StepIt Status & Permissions:\n")
        
        let screen = PermissionsManager.shared.hasScreenRecordingPermission
        let ax = PermissionsManager.shared.hasAccessibilityPermission
        
        print("  • Screen Recording:  \(screen ? "✅ Granted" : "❌ Denied / Not Determined")")
        print("  • Accessibility:     \(ax ? "✅ Granted" : "❌ Denied / Not Determined")")
        
        let settings = SessionStore.shared.loadSettings()
        print("\n⚙️ Gateway Configuration:")
        print("  • Provider: \(settings.gateway.provider.displayName)")
        print("  • Base URL: \(settings.gateway.baseURL)")
        print("  • Model:    \(settings.gateway.model)")
        print("  • Vision:   \(settings.gateway.visionEnabled ? "Enabled" : "Disabled")")
        
        print("\n📁 Storage Root:")
        print("  • \(SessionStore.shared.baseDirectory.path)")
    }
    
    private static func listSessions() {
        let sessions = SessionStore.shared.listSessions()
        if sessions.isEmpty {
            print("No saved sessions found in \(SessionStore.shared.sessionsDirectory.path)")
            return
        }
        
        print("⚡️ Saved StepIt Sessions (\(sessions.count)):\n")
        for s in sessions {
            print("  • [\(s.id)] \(s.title)")
            print("    Started: \(s.startedAt.formatted()) | Steps: \(s.steps.count) | Theme: \(s.theme.displayName)")
            if let web = s.exports.web {
                print("    Web: \(web)")
            }
            print("")
        }
    }
    
    private static func exportSession(id: String) async {
        guard !id.isEmpty else {
            print("Error: Missing session ID. Run `stepit list` to find session IDs.")
            return
        }
        
        do {
            let session = try SessionStore.shared.loadSession(id: id)
            let settings = SessionStore.shared.loadSettings()
            print("Exporting session '\(session.title)'...")
            let (webURL, pdfURL, mdURL) = try await PublishingCoordinator.shared.exportAll(session: session, settings: settings)
            print("✅ Web Documentation: \(webURL.path)")
            if let pdf = pdfURL {
                print("✅ Styled PDF Guide:   \(pdf.path)")
            }
            print("✅ Markdown README:    \(mdURL.path)")
            
            PublishingCoordinator.shared.openInBrowser(url: webURL)
        } catch {
            print("❌ Failed to export session: \(error.localizedDescription)")
        }
    }
    
    private static func runDemo() async {
        print("⚡️ Building rich StepIt demonstration session...")
        
        let session = DemoSessionGenerator.generateDemoSession()
        let settings = SessionStore.shared.loadSettings()
        
        do {
            try SessionStore.shared.saveSession(session)
            print("Saved demo session: \(session.id)")
            
            print("Generating 1-Click Multi-Format Exports (Interactive Web Doc, Print-Ready PDF, Markdown)...")
            let (webURL, pdfURL, mdURL) = try await PublishingCoordinator.shared.exportAll(session: session, settings: settings)
            
            print("\n🎉 Demo Successfully Built!")
            print("  🌐 Interactive Web Site: \(webURL.path)")
            if let pdf = pdfURL {
                print("  📄 Print-Ready PDF:      \(pdf.path)")
            }
            print("  📝 Markdown Guide:       \(mdURL.path)")
            
            print("\nOpening Interactive Web Documentation in your browser...")
            PublishingCoordinator.shared.openInBrowser(url: webURL)
        } catch {
            print("Error generating demo: \(error.localizedDescription)")
        }
    }
    
    private static func runGUIApp() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
