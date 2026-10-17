import XCTest
import Foundation

/// Post-recording, the user must be able to choose per step (or session)
/// between animated GIF and static image. Currently FAILS: Review UI only
/// shows the static screenshot with no GIF/static toggle.
final class PostRecordingMediaChoiceTests: XCTestCase {
    func testReviewAllowsGifOrStaticChoice() {
        let pane = readSource("platform/macos/Sources/StepIt/UI/ReviewStepsPane.swift")
        let model = readSource("platform/macos/Sources/StepItIR/Model/StepSession.swift")
        let web = readSource("platform/macos/Sources/StepItPublishing/WebDocSections.swift")
        XCTAssertFalse(pane.isEmpty, "could not locate Review panes")
        // Cosmetic picker is not enough — the choice must persist and switch
        // the preview + exports.
        XCTAssertTrue(
            pane.contains("preferredMedia") && pane.contains("Picker") && pane.contains("wantsGIF"),
            "review must persist GIF/static choice to step.preferredMedia and switch the preview"
        )
        XCTAssertTrue(
            model.contains("preferredMedia"),
            "Step model must carry preferredMedia so the choice survives save/export"
        )
        XCTAssertTrue(
            web.contains("preferredMedia"),
            "web export must honor the per-step preferredMedia choice"
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
