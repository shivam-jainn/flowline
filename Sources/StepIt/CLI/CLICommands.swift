import Foundation
import StepItPermissions
import StepItStorage
import StepItMacCapture
import StepItCaptureAPI
import StepItPublishing
import StepItAIGateway
import StepItPipeline
import StepItEngine
import StepItIR
import AppKit
import SwiftUI
import StepItCore
import StepItFixtures

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
            
        case "cli-task":
            let taskArgs = Array(args.dropFirst())
            runScript(relativeScript: "Scripts/dev/taskctl.py", arguments: taskArgs)
            
        case "cli-pulse":
            let pulseArgs = Array(args.dropFirst())
            runScript(relativeScript: "Scripts/dev/devpulse.sh", arguments: pulseArgs)
            
        case "cli-fetch":
            let fetchArgs = Array(args.dropFirst())
            runScript(relativeScript: "Scripts/dev/fetch_cli.sh", arguments: fetchArgs)
            
        case "cli-tour":
            await runCLITour()
            
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
          automate         Run automated multi-page recording tour across the 10-page fixture web app
          serve [port]     Start local HTTP server serving the 10-page fixture web app (Fixtures/playground-web)
          record           Start an interactive CLI recording session (captures desktop clicks)
          gateway [prompt] Test AI Gateway streaming response directly in terminal
          demo             Generate an end-to-end sample guide, export Web/PDF/MD, and open in browser
          list             List all saved recording sessions
          export <id>      Export a saved session by ID (e.g. stepit export sess_123456)
          status           Check macOS permissions (Screen Recording, Accessibility) & Gateway settings
          app-calculator   Launch native Calculator & Currency Converter mini app
          app-kanban       Launch native Sprint Kanban Board mini app
          app-monitor      Launch native Hardware & Resource Monitor mini app
          cli-task [args]  Execute taskctl task & sprint management CLI
          cli-pulse [args] Execute devpulse diagnostics & benchmark CLI
          cli-fetch [url]  Fetch/clone lightweight CLI tools from GitHub
          cli-tour         Automated end-to-end terminal recording tour with copyable code blobs
          app              Launch the native StepIt Menu Bar & Floating HUD app (default)
          help             Show this help message

        Hotkeys (when app is running):
          ⌥ Space          Start / Stop recording workflow
        """)
    }
    
    private static func servePlayground(port: Int) {
        guard let playgroundDir = FixtureLocator.playgroundWebDirectory() else {
            print("❌ Fixtures/playground-web was not found. Run from the repository root or set STEPIT_FIXTURES_DIR.")
            exit(1)
        }
        
        print("⚡️ Serving the 10-page StepIt fixture web app at http://localhost:\(port)/")
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
        
        let controller = WorkflowController.shared
        await controller.bootstrap()
        await controller.startRecording(
            title: "Terminal CLI Recording",
            theme: .developerDark,
            mediaMode: .hybrid
        )
        
        // Listen to controller updates
        Task { @MainActor in
            var lastStepCount = 0
            while true {
                try? await Task.sleep(nanoseconds: 500_000_000)
                let count = controller.stepCount
                if count > lastStepCount {
                    print("  📸 Captured Step \(count): recorded snapshot & GIF at cursor coordinates.")
                    lastStepCount = count
                }
            }
        }
        
        // Setup SIGINT handler to finish
        signal(SIGINT) { _ in
            print("\n⚡️ Stopping recording and publishing documentation...")
            Task { @MainActor in
                if let session = await WorkflowController.shared.stopRecording() {
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
        print("⚡️ Building rich StepIt demonstration session from real Web Playground...")
        
        do {
            let session = try await DemoSessionGenerator.generateDemoSession()
            let settings = SessionStore.shared.loadSettings()
            
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
    
    private static func runScript(relativeScript: String, arguments: [String]) {
        let currentDir = FileManager.default.currentDirectoryPath
        var scriptURL = URL(fileURLWithPath: currentDir).appendingPathComponent(relativeScript)
        
        if !FileManager.default.fileExists(atPath: scriptURL.path) {
            // Check bundle / parent dirs
            var current = URL(fileURLWithPath: currentDir)
            for _ in 0..<4 {
                let candidate = current.appendingPathComponent(relativeScript)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    scriptURL = candidate
                    break
                }
                current = current.deletingLastPathComponent()
            }
        }
        
        let process = Process()
        process.executableURL = scriptURL
        process.arguments = arguments
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        
        do {
            try process.run()
            process.waitUntilExit()
            exit(process.terminationStatus)
        } catch {
            print("❌ Failed to execute script at \(scriptURL.path): \(error.localizedDescription)")
            exit(1)
        }
    }
    
    private static func runCLITour() async {
        print("⚡️ [StepIt CLI Tour] Running terminal workflow tour across developer CLI tools...")
        let currentDir = FileManager.default.currentDirectoryPath
        let taskctlURL = URL(fileURLWithPath: currentDir).appendingPathComponent("Scripts/dev/taskctl.py")
        let devpulseURL = URL(fileURLWithPath: currentDir).appendingPathComponent("Scripts/dev/devpulse.sh")
        
        guard FileManager.default.fileExists(atPath: taskctlURL.path),
              FileManager.default.fileExists(atPath: devpulseURL.path) else {
            print("❌ CLI scripts not found in Scripts/dev/ directory.")
            return
        }
        
        print("  ▶ [1/3] Executing taskctl list & sprint progress inspection...")
        let step1 = Step(
            id: UUID().uuidString,
            index: 1,
            action: .typing,
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            windowTitle: "taskctl — zsh",
            elementRole: "AXTextField",
            elementTitle: "./Scripts/dev/taskctl.py list",
            actionDescription: "Inspect sprint backlog via taskctl CLI",
            userNotes: "Review open and completed sprint backlog tickets directly in terminal.",
            textBlob: """
            ./Scripts/dev/taskctl.py list
            ./Scripts/dev/taskctl.py stats
            """,
            isCode: true,
            codeLanguage: "bash"
        )
        
        print("  ▶ [2/3] Executing taskctl add new automation ticket...")
        let step2 = Step(
            id: UUID().uuidString,
            index: 2,
            action: .writeCode,
            appName: "Visual Studio Code",
            bundleIdentifier: "com.microsoft.VSCode",
            windowTitle: "taskctl.py",
            elementRole: "AXCodeEditor",
            elementTitle: "taskctl.py",
            actionDescription: "Add automated playground verification ticket",
            userNotes: "Append high-priority automated testing ticket to the backlog queue.",
            textBlob: """
            ./Scripts/dev/taskctl.py add "Automate end-to-end 10-page playground tour" --priority high --tag testing
            """,
            isCode: true,
            codeLanguage: "bash"
        )
        
        print("  ▶ [3/3] Executing devpulse system & pipeline benchmark...")
        let step3 = Step(
            id: UUID().uuidString,
            index: 3,
            action: .typing,
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            windowTitle: "devpulse — zsh",
            elementRole: "AXTextField",
            elementTitle: "./Scripts/dev/devpulse.sh doctor",
            actionDescription: "Run developer environment health diagnostics",
            userNotes: "Verify macOS Darwin kernel, Swift compiler toolchain, and Git working tree.",
            textBlob: """
            ./Scripts/dev/devpulse.sh doctor
            ./Scripts/dev/devpulse.sh bench 5
            """,
            isCode: true,
            codeLanguage: "bash"
        )
        
        let session = StepSession(
            id: "sess_cli_tour_\(Int(Date().timeIntervalSince1970))",
            title: "Terminal CLI & Developer Toolchain Guide",
            theme: .developerDark,
            mediaMode: .hybrid,
            steps: [step1, step2, step3]
        )
        
        do {
            try SessionStore.shared.saveSession(session)
            let settings = SessionStore.shared.loadSettings()
            let (webURL, pdfURL, mdURL) = try await PublishingCoordinator.shared.exportAll(session: session, settings: settings)
            print("\n🎉 Terminal CLI Guide Successfully Published!")
            print("  🌐 Interactive Web Site: \(webURL.path)")
            if let pdf = pdfURL {
                print("  📄 Print-Ready PDF:      \(pdf.path)")
            }
            print("  📝 Markdown Guide:       \(mdURL.path)")
            PublishingCoordinator.shared.openInBrowser(url: webURL)
        } catch {
            print("❌ CLI tour generation failed: \(error.localizedDescription)")
        }
    }
    
    @MainActor
    private static func runGUIApp() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
