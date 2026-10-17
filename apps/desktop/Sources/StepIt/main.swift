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
    // Native macOS Menu Bar & HUD App (top-level main runs on the main thread)
    print("⚡️ StepIt is running as a menu bar app — look for the ⚡ icon in the menu bar.")
    print("   Press ⌥ Space to start/stop recording. This terminal stays attached until you quit (menu bar → Quit StepIt, or Ctrl+C).")
    MainActor.assumeIsolated {
        CLIAppCommands.runGUIApp(composition: AppComposition.make())
    }
}
