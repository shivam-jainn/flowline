import AppKit
import Foundation
import FlowlineEngine
import FlowlineFixtures
import FlowlineIR
import SwiftUI

/// App/tooling CLI slice (R/M1-07 split): GUI launch, mini-apps, playground
/// server, interactive recording and dev-script execution.
/// Every entry point takes the shared `AppComposition` — never singletons.
public struct CLIAppCommands {
    @MainActor
    public static func runGUIApp(composition: AppComposition) {
        let app = NSApplication.shared
        // Dock app (mirrors runMiniApp): regular policy + activation so the
        // app appears in the Dock and comes forward with its main window.
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate(composition: composition)
        app.delegate = delegate
        app.activate(ignoringOtherApps: true)
        app.run()
    }

    public static func servePlayground(port: Int) {
        guard let playgroundDir = FixtureLocator.playgroundWebDirectory() else {
            print("[ERROR] shared/fixtures/playground-web was not found. Run from the repository root or set FLOWLINE_FIXTURES_DIR.")
            exit(1)
        }

        print("[Flowline] Serving the 10-page Flowline fixture web app at http://localhost:\(port)/")
        print("Root directory: \(playgroundDir.path)")
        print("Press Ctrl+C to stop server.\n")

        // Use python3 built-in http.server
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-m", "http.server", "\(port)", "--directory", playgroundDir.path]
        try? process.run()
        process.waitUntilExit()
    }

    @MainActor
    public static func runInteractiveTerminalRecorder(composition: AppComposition) async {
        print("[Flowline] [CLI Recorder] Initializing recording session...")
        print("> Click anywhere on your screen to capture steps.")
        print("[STOP] Press Ctrl+C in this terminal when finished to synthesize and export.\n")

        let controller = composition.controller
        let publisher = composition.publisher
        let settings = composition.settingsStore.load()
        await composition.boot()
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
                    print("  [CAPTURE] Captured Step \(count): recorded snapshot & GIF at cursor coordinates.")
                    lastStepCount = count
                }
            }
        }

        // Setup SIGINT handler to finish (dispatch source: the handler closure
        // may capture composition pieces, unlike a raw C signal handler).
        signal(SIGINT, SIG_IGN)
        let sigint = DispatchSource.makeSignalSource(signal: SIGINT)
        sigint.setEventHandler {
            print("\n[Flowline] Stopping recording and publishing documentation...")
            Task { @MainActor in
                if let session = await controller.stopRecording() {
                    if let (web, pdf, md) = try? await publisher.exportAll(session: session, publishing: settings.publishing) {
                        print("\n[DONE] Recording Synthesized & Published!")
                        print("  Web: \(web.path)")
                        if let p = pdf { print("  PDF:   \(p.path)") }
                        print("  Markdown:   \(md.path)")
                        publisher.openInBrowser(url: web)
                    }
                }
                exit(0)
            }
        }
        sigint.resume()

        // Keep task alive
        while true {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    @MainActor
    public static func runMiniApp(title: String, rootView: AnyView) {
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

    public static func runScript(relativeScript: String, arguments: [String]) {
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
            print("[ERROR] Failed to execute script at \(scriptURL.path): \(error.localizedDescription)")
            exit(1)
        }
    }
}
