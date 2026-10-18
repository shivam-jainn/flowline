import AppKit
import Foundation

let arguments = CommandLine.arguments

if arguments.count > 1 && arguments[1] != "app" {
    // Headless / CLI Subcommands (composition is built inside CLICommands).
    nonisolated(unsafe) var isDone = false
    Task { @MainActor in
        await CLICommands.handle(arguments: arguments)
        isDone = true
    }

    while !isDone {
        RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }
} else {
    // Native macOS Dock App + HUD (top-level main runs on the main thread)
    print("[Flowline] Running as Dock app — look for the Flowline icon in the Dock (plus the menu-bar extra).")
    print("   Press ⌥ Space to start/stop recording, or use File → Start Recording. This terminal stays attached until you quit (⌘Q, Dock → Quit, or menu bar → Quit Flowline).")
    MainActor.assumeIsolated {
        CLIAppCommands.runGUIApp(composition: AppComposition.make())
    }
}
