import XCTest
import AppKit

/// Regression: when recording starts and the user performs a step,
/// the target application screen must remain visible in the recording.
/// StepIt-owned UI (floating HUD) must never occlude/photobomb the
/// screenshot. Currently FAILS: HUD panel keeps default sharing and
/// `ScreenRecorder` captures `.optionOnScreenOnly` (includes our windows).
final class RecordingScreenVisibilityTests: XCTestCase {

    func testHUDWindowIsExcludedFromScreenCapture() {
        let source = readSource("platform/macos/Sources/StepIt/UI/FloatingHUDWindowController.swift")
        XCTAssertFalse(source.isEmpty, "could not locate FloatingHUDWindowController.swift")
        XCTAssertTrue(
            source.contains("sharingType = .none"),
            "HUD window must set sharingType=.none so the application screen stays visible in recordings"
        )
    }

    func testScreenRecorderExcludesStepItWindows() {
        let source = readSource("platform/macos/Sources/StepItMacCapture/ScreenRecorder.swift")
        XCTAssertFalse(source.isEmpty, "could not locate ScreenRecorder.swift")
        // BelowWindow under the backmost StepIt window in z-order: wallpaper
        // safe, excludes every StepIt window above. Plus a permission preflight
        // so denied captures return nil instead of pill-on-black frames.
        XCTAssertTrue(
            source.contains("optionOnScreenBelowWindow")
            && source.contains("backmostStepItWindowIDInZOrder"),
            "ScreenRecorder must capture below the backmost StepIt window in z-order"
        )
        XCTAssertTrue(
            source.contains("CGPreflightScreenCaptureAccess")
            || source.contains("hasScreenRecordingPermission"),
            "ScreenRecorder must preflight Screen Recording permission (no pill-on-black frames)"
        )
    }

    /// The recording pill (FloatingHUD capsule) must never appear in the
    /// captured screenshot: the capture path has to hide/exclude it for the
    /// duration of the snapshot.
    func testRecordingPillIsNotVisibleInCapture() {
        let hud = readSource("platform/macos/Sources/StepIt/UI/FloatingHUDWindowController.swift")
        let driver = readSource("platform/macos/Sources/StepItMacCapture/MacCaptureDriver.swift")
        let recorder = readSource("platform/macos/Sources/StepItMacCapture/ScreenRecorder.swift")
        let micro = readSource("platform/macos/Sources/StepItMacCapture/MicroClipRecorder.swift")
        XCTAssertFalse(hud.isEmpty && driver.isEmpty && recorder.isEmpty, "could not locate sources")
        let pillExcluded =
            recorder.contains("optionOnScreenBelowWindow")
            && recorder.contains("backmostStepItWindowIDInZOrder")
            && micro.contains("createScreenImageExcludingStepItWindows")
        XCTAssertTrue(
            pillExcluded,
            "recording pill must be excluded via BelowWindow in both screenshot and micro-clip paths"
        )
    }

    private func readSource(_ relative: String) -> String {
        // Derive repo root from this file's path (…/platform/macos/Tests/…).
        let thisFile = URL(fileURLWithPath: #filePath)
        var dir: URL? = thisFile.deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir?.appendingPathComponent(relative).path ?? ""
            if let text = try? String(contentsOfFile: candidate, encoding: .utf8) { return text }
            dir = dir?.deletingLastPathComponent()
        }
        // Fallback: repo root two levels above package dir.
        for base in [FileManager.default.currentDirectoryPath] {
            let full = (base as NSString).appendingPathComponent(relative)
            if relative.hasPrefix("platform/") {
                let trimmed = String(relative.dropFirst("platform/macos/".count))
                let alt = (base as NSString).appendingPathComponent(trimmed)
                if let text = try? String(contentsOfFile: alt, encoding: .utf8) { return text }
            }
            if let text = try? String(contentsOfFile: full, encoding: .utf8) { return text }
        }
        return ""
    }
}
