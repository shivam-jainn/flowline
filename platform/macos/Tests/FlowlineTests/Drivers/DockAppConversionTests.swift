import XCTest
import Foundation

/// Menu-bar → Dock conversion: regular activation policy, native main menu,
/// close-safe lifecycle, quit guard, Dock-ready bundle metadata.
/// Source-assertion style (matches StartupPermissionChecksTests): the GUI
/// itself needs TCC + a display, so tests pin the wiring in source.
final class DockAppConversionTests: XCTestCase {
    func testActivationPolicyIsRegular() {
        let delegate = readSource("platform/macos/Sources/Flowline/App/AppDelegate.swift")
        XCTAssertFalse(delegate.isEmpty, "could not locate AppDelegate.swift")
        XCTAssertTrue(
            delegate.contains("setActivationPolicy(.regular)"),
            "Dock app must set .regular activation policy"
        )
        XCTAssertFalse(
            delegate.contains("setActivationPolicy(.accessory)"),
            "must not hide the Dock icon with .accessory"
        )
    }

    func testActivationPolicySetEarlyAtLaunch() {
        let delegate = readSource("platform/macos/Sources/Flowline/App/AppDelegate.swift")
        let launchBody = body(of: "applicationDidFinishLaunching", in: delegate)
        XCTAssertTrue(
            launchBody.contains("setActivationPolicy(.regular)"),
            ".regular must be set early in applicationDidFinishLaunching, before windows/menus"
        )
        XCTAssertTrue(
            launchBody.contains("MainMenuBuilder"),
            "main menu must be installed during launch"
        )
    }

    func testMainMenuHasAppFileWindowHelp() {
        let builder = readSource("platform/macos/Sources/Flowline/UI/MainMenuBuilder.swift")
        XCTAssertFalse(builder.isEmpty, "could not locate MainMenuBuilder.swift")
        for menu in ["\"Flowline\"", "\"File\"", "\"Window\"", "\"Help\""] {
            XCTAssertTrue(builder.contains(menu), "main menu must include \(menu)")
        }
        XCTAssertTrue(builder.contains("Settings") && builder.contains("\",\""),
            "App menu must have Settings… (⌘,)")
        XCTAssertTrue(builder.contains("Quit Flowline") && builder.contains("\"q\""),
            "App menu must have Quit Flowline (⌘Q)")
        XCTAssertTrue(builder.contains("Start Recording"), "File menu must have Start Recording")
        XCTAssertTrue(builder.contains("Stop Recording"), "File menu must have Stop Recording")
        XCTAssertTrue(builder.contains("Open Recent"), "File menu must have Open Recent (reuses store.listSessions())")
        XCTAssertTrue(builder.contains("Minimize") && builder.contains("Bring All to Front"),
            "Window menu must have Minimize / Bring All to Front")
    }

    func testMainMenuSharesDelegateActions() {
        let builder = readSource("platform/macos/Sources/Flowline/UI/MainMenuBuilder.swift")
        XCTAssertFalse(builder.isEmpty, "could not locate MainMenuBuilder.swift")
        // Both menus must run the same code: every command targets the
        // shared AppDelegate selectors (no duplicated implementations).
        for selector in [
            "startRecording", "stopRecording", "cancelRecording",
            "openSettings", "openPermissions", "triggerDemo",
            "openRecentSession", "quitApp",
        ] {
            XCTAssertTrue(
                builder.contains(selector),
                "main menu must target the shared AppDelegate.\(selector) action"
            )
        }
    }

    func testLaunchShowsLastSession() {
        let delegate = readSource("platform/macos/Sources/Flowline/App/AppDelegate.swift")
        XCTAssertTrue(
            delegate.contains("showLastSessionAtLaunch"),
            "launch must restore a main window (last session)"
        )
        XCTAssertTrue(
            delegate.contains("reviewWindows.show(for:"),
            "last-session restore must present via ReviewWindowController.show"
        )
        XCTAssertTrue(
            delegate.contains("listSessions().first"),
            "restore must pick the most recent session (listSessions is newest-first)"
        )
    }

    func testCloseSafeLifecycle() {
        let delegate = readSource("platform/macos/Sources/Flowline/App/AppDelegate.swift")
        XCTAssertTrue(
            delegate.contains("applicationShouldTerminateAfterLastWindowClosed")
                && delegate.contains("-> Bool { false }"),
            "closing the last window must not quit (recording/HUD survive)"
        )
        XCTAssertTrue(
            delegate.contains("applicationShouldHandleReopen")
                && delegate.contains("hasVisibleWindows"),
            "Dock-icon reopen must re-show the review window (or HUD if recording)"
        )
    }

    func testQuitGuardBlocksDuringRecording() {
        let delegate = readSource("platform/macos/Sources/Flowline/App/AppDelegate.swift")
        XCTAssertTrue(
            delegate.contains("func applicationShouldTerminate("),
            "⌘Q/quit must be guarded while a session is live"
        )
        XCTAssertTrue(
            delegate.contains(".recording") && delegate.contains(".paused"),
            "quit guard must cover both recording and paused states"
        )
        XCTAssertTrue(
            delegate.contains("Stop & Synthesize")
                && delegate.contains("Cancel Recording")
                && delegate.contains("Don't Quit"),
            "quit guard must offer Stop & Synthesize / Cancel Recording / Don't Quit"
        )
        XCTAssertTrue(
            delegate.contains("reply(toApplicationShouldTerminate:"),
            "async stop-then-quit must reply to the termination request"
        )
    }

    func testReviewWindowTitleAndNoFocusSteal() {
        let controller = readSource("platform/macos/Sources/Flowline/UI/ReviewWindowController.swift")
        XCTAssertFalse(controller.isEmpty, "could not locate ReviewWindowController.swift")
        XCTAssertTrue(
            controller.contains("session.title"),
            "review window title must identify the session"
        )
        XCTAssertFalse(
            controller.contains("activate(ignoringOtherApps"),
            "automatic post-stop review show must not steal focus (explicit menu/Dock actions activate)"
        )
        XCTAssertTrue(
            controller.contains("isReleasedWhenClosed = false"),
            "review window must stay close-safe (reusable after close)"
        )
    }

    func testStatusItemStillWorks() {
        let delegate = readSource("platform/macos/Sources/Flowline/App/AppDelegate.swift")
        XCTAssertTrue(
            delegate.contains("NSStatusBar.system") && delegate.contains("setupStatusItem"),
            "menu-bar status item must keep working alongside the Dock icon"
        )
    }

    func testRunGUIAppIsDockReady() {
        let cli = readSource("platform/macos/Sources/Flowline/CLI/CLIAppCommands.swift")
        XCTAssertFalse(cli.isEmpty, "could not locate CLIAppCommands.swift")
        let guiBody = body(of: "runGUIApp", in: cli)
        XCTAssertTrue(
            guiBody.contains("setActivationPolicy(.regular)"),
            "runGUIApp must set .regular (mirrors runMiniApp)"
        )
        XCTAssertTrue(
            guiBody.contains("activate(ignoringOtherApps: true)"),
            "runGUIApp must activate (mirrors runMiniApp)"
        )
    }

    func testLaunchCopyIsDockApp() {
        let main = readSource("platform/macos/Sources/Flowline/main.swift")
        XCTAssertFalse(main.isEmpty, "could not locate main.swift")
        XCTAssertTrue(main.contains("Dock"), "launch copy must describe the Dock app")
        XCTAssertFalse(main.contains("menu bar app"), "launch copy must not call it a menu-bar app")
    }

    func testBundlePlistIsDockReady() {
        let script = readSource("tooling/release/bundle_app.sh")
        XCTAssertFalse(script.isEmpty, "could not locate bundle_app.sh")
        XCTAssertTrue(script.contains("com.flowline.macos"), "bundle id must stay unchanged (TCC!)")
        XCTAssertTrue(script.contains("CFBundleDisplayName"), "plist must set CFBundleDisplayName")
        XCTAssertTrue(
            script.contains("NSSupportsAutomaticTermination") && script.contains("NSSupportsSuddenTermination"),
            "plist must opt out of automatic/sudden termination (recording must not be killed)"
        )
        XCTAssertTrue(
            script.contains("LSUIElement") && script.contains("<false/>"),
            "LSUIElement must stay false (Dock icon visible)"
        )
        XCTAssertTrue(
            script.contains("AppIcon.icns") && script.contains("CFBundleIcon"),
            "icon copy + icon plist keys must stay wired"
        )
    }

    // MARK: - Helpers (same shape as StartupPermissionChecksTests)

    private func body(of method: String, in source: String) -> String {
        guard let range = source.range(of: method) else { return "" }
        let tail = String(source[range.lowerBound...])
        return String(tail.prefix(2500))
    }

    private func readSource(_ relative: String) -> String {
        let thisFile = URL(fileURLWithPath: #filePath)
        var dir: URL? = thisFile.deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir?.appendingPathComponent(relative).path ?? ""
            if let text = try? String(contentsOfFile: candidate, encoding: .utf8) { return text }
            dir = dir?.deletingLastPathComponent()
        }
        for base in [FileManager.default.currentDirectoryPath] {
            if relative.hasPrefix("platform/") {
                let trimmed = String(relative.dropFirst("platform/macos/".count))
                let alt = (base as NSString).appendingPathComponent(trimmed)
                if let text = try? String(contentsOfFile: alt, encoding: .utf8) { return text }
            }
            let full = (base as NSString).appendingPathComponent(relative)
            if let text = try? String(contentsOfFile: full, encoding: .utf8) { return text }
        }
        return ""
    }
}
