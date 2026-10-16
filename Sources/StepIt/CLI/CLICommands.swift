import Foundation
import AppKit
import SwiftUI
import StepItCore

public struct CLICommands {
    @MainActor
    public static func handle(arguments: [String]) async {
        let args = Array(arguments.dropFirst()) // drop executable name
        let command = args.first ?? "app"
        
        switch command {
        case "automate":
            do {
                _ = try await AutomatedWorkflowRecorder.shared.recordPlaygroundWorkflow(openInBrowserAfter: true)
            } catch {
                print("❌ Automation failed: \(error.localizedDescription)")
            }
            
        case "serve":
            let port = args.count > 1 ? (Int(args[1]) ?? 8080) : 8080
            servePlayground(port: port)
            
        case "record":
            await runInteractiveTerminalRecorder()
            
        case "gateway":
            let prompt = args.count > 1 ? args[1] : "Provide a 3-step guide for testing an API gateway."
            await testGatewayStream(prompt: prompt)
            
        case "demo":
            await runDemo()
            
        case "list":
            listSessions()
            
        case "status":
            showStatus()
            
        case "export":
            let sessionId = args.count > 1 ? args[1] : ""
            await exportSession(id: sessionId)
            
        case "app-calculator":
            runMiniApp(title: "StepIt MiniApp: Calculator", rootView: AnyView(CalculatorAppView()))
            
        case "app-kanban":
            runMiniApp(title: "StepIt MiniApp: Kanban Board", rootView: AnyView(KanbanAppView()))
            
        case "app-monitor":
            runMiniApp(title: "StepIt MiniApp: System Monitor", rootView: AnyView(SystemMonitorAppView()))
            
        case "help", "--help", "-h":
            printHelp()
            
        case "app":
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
          automate         Run automated multi-page recording tour across the 10-page playground
          serve [port]     Start local HTTP server serving the 10-page interactive playground
          record           Start an interactive CLI recording session (captures desktop clicks)
          gateway [prompt] Test AI Gateway streaming response directly in terminal
          demo             Generate an end-to-end sample guide, export Web/PDF/MD, and open in browser
          list             List all saved recording sessions
          export <id>      Export a saved session by ID (e.g. stepit export sess_123456)
          status           Check macOS permissions (Screen Recording, Accessibility) & Gateway settings
          app-calculator   Launch native Calculator & Currency Converter mini app
          app-kanban       Launch native Sprint Kanban Board mini app
          app-monitor      Launch native Hardware & Resource Monitor mini app
          app              Launch the native StepIt Menu Bar & Floating HUD app (default)
          help             Show this help message

        Hotkeys (when app is running):
          ⌥ Space          Start / Stop recording workflow
        """)
    }
    
    private static func servePlayground(port: Int) {
        let currentDir = FileManager.default.currentDirectoryPath
        let playgroundDir = URL(fileURLWithPath: currentDir).appendingPathComponent("Playground/web")
        
        print("⚡️ Serving 10-page StepIt UI Playground at http://localhost:\(port)/")
        print("📁 Root directory: \(playgroundDir.path)")
        print("Press Ctrl+C to stop server.\n")
        
        // Use python3 built-in http.server
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-m", "http.server", "\(port)", "--directory", playgroundDir.path]
        try? process.run()
        process.waitUntilExit()
    }
    
    @MainActor
    private static func runInteractiveTerminalRecorder() async {
        print("⚡️ [StepIt CLI Recorder] Initializing recording session...")
        print("👉 Click anywhere on your screen to capture steps.")
        print("🛑 Press Ctrl+C in this terminal when finished to synthesize and export.\n")
        
        CaptureCoordinator.shared.startRecording(
            title: "Terminal CLI Recording",
            theme: .developerDark,
            mediaMode: .hybrid
        )
        
        // Listen to Coordinator updates
        var lastStepCount = 0
        _ = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            let count = CaptureCoordinator.shared.stepCount
            if count > lastStepCount {
                print("  📸 Captured Step \(count): recorded snapshot & GIF at cursor coordinates.")
                lastStepCount = count
            }
        }
        
        // Setup SIGINT handler to finish
        signal(SIGINT) { _ in
            print("\n⚡️ Stopping recording and publishing documentation...")
            Task { @MainActor in
                if let session = CaptureCoordinator.shared.stopRecording() {
                    let settings = SessionStore.shared.loadSettings()
                    if let (web, pdf, md) = try? await PublishingCoordinator.shared.exportAll(session: session, settings: settings) {
                        print("\n🎉 Recording Synthesized & Published!")
                        print("  🌐 Web Documentation: \(web.path)")
                        if let p = pdf { print("  📄 Print-Ready PDF:   \(p.path)") }
                        print("  📝 Markdown README:   \(md.path)")
                        PublishingCoordinator.shared.openInBrowser(url: web)
                    }
                }
                exit(0)
            }
        }
        
        // Keep task alive
        while true {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    
    private static func testGatewayStream(prompt: String) async {
        print("⚡️ Testing AI Gateway Streaming (OpenAI-compatible protocol)...")
        let settings = SessionStore.shared.loadSettings()
        print("  • Provider: \(settings.gateway.provider.displayName)")
        print("  • Base URL: \(settings.gateway.baseURL)")
        print("  • Model:    \(settings.gateway.model)\n")
        
        let dummySession = StepSession(
            title: "Gateway Test",
            steps: [
                Step(index: 1, action: .click, appName: "Browser", actionDescription: "Open API Gateway")
            ]
        )
        
        do {
            let stream = AIGatewayClient.shared.generateStream(
                session: dummySession,
                settings: settings.gateway,
                style: .sopGuide,
                customInstructions: prompt
            )
            
            print("--- Streaming Output ---")
            for try await token in stream {
                print(token, terminator: "")
                fflush(stdout)
            }
            print("\n--- End of Stream ---")
        } catch {
            print("\n❌ Gateway error: \(error.localizedDescription)")
            print("Tip: Check API Key or endpoint URL in Settings.")
        }
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
    
    @MainActor
    private static func runMiniApp(title: String, rootView: AnyView) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        
        let window = NSWindow(
            contentRect: NSRect(x: 150, y: 150, width: 680, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.center()
        window.contentView = NSHostingView(rootView: rootView)
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        app.run()
    }
    
    private static func runGUIApp() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
