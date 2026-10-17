import XCTest
import Foundation

/// Startup must verify system permissions (screen recording + accessibility)
/// and notify the user when anything is missing. Currently FAILS: launch
/// just boots the engine with no permission check or user notice.
final class StartupPermissionChecksTests: XCTestCase {
    func testLaunchChecksPermissions() {
        let delegate = readSource("platform/macos/Sources/StepIt/App/AppDelegate.swift")
        let composition = readSource("platform/macos/Sources/StepIt/App/AppComposition.swift")
        XCTAssertFalse(delegate.isEmpty && composition.isEmpty, "could not locate startup sources")
        let checksPermissions =
            delegate.contains("allPermissionsGranted")
            || delegate.contains("status(for:")
            || delegate.contains("hasScreenRecordingPermission")
            || delegate.contains("hasAccessibilityPermission")
            || composition.contains("allPermissionsGranted")
            || composition.contains("missingPermissions")
            || composition.contains("PermissionKind")
        XCTAssertTrue(checksPermissions, "startup must check screen-recording + accessibility permission status")
    }

    func testMissingPermissionsNotifyUser() {
        let delegate = readSource("platform/macos/Sources/StepIt/App/AppDelegate.swift")
        XCTAssertFalse(delegate.isEmpty, "could not locate AppDelegate.swift")
        // Must be wired to the launch path, not just the manual Settings menu.
        // Extract the launch method body and require the notice there.
        let launchBody: String = {
            guard let range = delegate.range(of: "applicationDidFinishLaunching") else { return "" }
            let tail = String(delegate[range.lowerBound...])
            // next 3 method boundaries ≈ launch body + helpers
            return String(tail.prefix(3000))
        }()
        let launchNotifies =
            launchBody.contains("showPermissionsIfNeeded")
            || launchBody.contains("notifyMissingPermissions")
            || launchBody.contains("NSAlert")
            || (launchBody.contains("allPermissionsGranted") && launchBody.contains("permissionsWindow"))
            || (launchBody.contains("PermissionsBanner") && launchBody.contains("allPermissionsGranted"))
        XCTAssertTrue(launchNotifies, "startup must surface a banner/alert/notification when permissions are missing")
    }

    func testRecordingBlockedWhenPermissionsMissing() {
        let delegate = readSource("platform/macos/Sources/StepIt/App/AppDelegate.swift")
        XCTAssertFalse(delegate.isEmpty, "could not locate AppDelegate.swift")
        XCTAssertTrue(
            delegate.contains("ensurePermissionsForRecording"),
            "recording must be gated on permissions (else black pill-only frames + no clicks)"
        )
    }

    /// Heisenbug support: the window verdict must be observable without a
    /// debugger, so Refresh logs the live screen/ax verdicts to unified log.
    func testPermissionVerdictsAreLogged() {
        let banner = readSource("platform/macos/Sources/StepIt/UI/PermissionsBannerView.swift")
        XCTAssertFalse(banner.isEmpty, "could not locate PermissionsBannerView.swift")
        XCTAssertTrue(
            banner.contains("NSLog") && banner.contains("hasScreenRecordingPermission"),
            "permission checks must NSLog the live verdicts (else GUI-vs-CLI mismatches are undebuggable)"
        )
    }

    /// Green ticks must lead somewhere: when both permissions are granted the
    /// window has to offer an onward action (close + start recording),
    /// otherwise the user is stuck on a fully-checked list.
    func testGrantedPermissionsOfferWayForward() {
        let banner = readSource("platform/macos/Sources/StepIt/UI/PermissionsBannerView.swift")
        let delegate = readSource("platform/macos/Sources/StepIt/App/AppDelegate.swift")
        XCTAssertFalse(banner.isEmpty, "could not locate PermissionsBannerView.swift")
        XCTAssertFalse(delegate.isEmpty, "could not locate AppDelegate.swift")
        XCTAssertTrue(
            banner.contains("onContinue") && banner.contains("Start Recording"),
            "banner must expose an onContinue action with a Start Recording button for the all-granted state"
        )
        XCTAssertTrue(
            delegate.contains("onContinue"),
            "AppDelegate must wire the banner continue action (close window + start recording)"
        )
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
