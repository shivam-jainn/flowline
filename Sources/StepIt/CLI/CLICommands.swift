import Foundation
import AppKit
import SwiftUI

/// CLI dispatch (R/M1-07 split).
/// Builds the composition once per invocation and delegates to the
/// app/demo/sync slices — no duplicate wiring, no singletons.
public struct CLICommands {
    @MainActor
    public static func handle(arguments: [String]) async {
        let args = Array(arguments.dropFirst()) // drop executable name
        let command = args.first ?? "app"
        let composition = AppComposition.make()

        switch command {
        case "automate":
            await CLIDemoCommands.runAutomatedTour(composition: composition)

        case "serve":
            let port = args.count > 1 ? (Int(args[1]) ?? 8080) : 8080
            CLIAppCommands.servePlayground(port: port)

        case "record":
            await CLIAppCommands.runInteractiveTerminalRecorder(composition: composition)

        case "gateway":
            let prompt = args.count > 1 ? args[1] : "Provide a 3-step guide for testing an API gateway."
            await CLISyncCommands.testGatewayStream(composition: composition, prompt: prompt)

        case "demo":
            await CLIDemoCommands.runDemo(composition: composition)

        case "list":
            CLISyncCommands.listSessions(composition: composition)

        case "status":
            CLISyncCommands.showStatus(composition: composition)

        case "export":
            let sessionId = args.count > 1 ? args[1] : ""
            await CLISyncCommands.exportSession(composition: composition, id: sessionId)

        case "app-calculator":
            CLIAppCommands.runMiniApp(title: "StepIt MiniApp: Calculator", rootView: AnyView(CalculatorAppView()))

        case "app-kanban":
            CLIAppCommands.runMiniApp(title: "StepIt MiniApp: Kanban Board", rootView: AnyView(KanbanAppView()))

        case "app-monitor":
            CLIAppCommands.runMiniApp(title: "StepIt MiniApp: System Monitor", rootView: AnyView(SystemMonitorAppView()))

        case "cli-task":
            let taskArgs = Array(args.dropFirst())
            CLIAppCommands.runScript(relativeScript: "Scripts/dev/taskctl.py", arguments: taskArgs)

        case "cli-pulse":
            let pulseArgs = Array(args.dropFirst())
            CLIAppCommands.runScript(relativeScript: "Scripts/dev/devpulse.sh", arguments: pulseArgs)

        case "cli-fetch":
            let fetchArgs = Array(args.dropFirst())
            CLIAppCommands.runScript(relativeScript: "Scripts/dev/fetch_cli.sh", arguments: fetchArgs)

        case "cli-tour":
            await CLIDemoCommands.runCLITour(composition: composition)

        case "help", "--help", "-h":
            printHelp()

        case "app":
            CLIAppCommands.runGUIApp(composition: composition)

        default:
            print("Unknown command: \(command)")
            printHelp()
            exit(1)
        }
    }

    public static func printHelp() {
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
}
