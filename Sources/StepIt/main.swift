import Foundation
import AppKit

let arguments = CommandLine.arguments

if arguments.count > 1 && arguments[1] != "app" {
    // Headless / CLI Subcommands
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
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
