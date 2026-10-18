import XCTest
import Foundation

/// Review window layout: step cards must fit the available column width.
/// Regression for the clipped-titles / overflowing-previews screenshot:
/// wide screenshots and NSImageView intrinsic sizes pushed cards wider than
/// the timeline column, clipping leading text ("ouTube…", "up in person…").
final class ReviewLayoutTests: XCTestCase {
    func testWindowDoesNotOverlayContentUnderTitlebar() {
        let controller = readSource("platform/macos/Sources/Flowline/UI/ReviewWindowController.swift")
        XCTAssertFalse(controller.isEmpty, "could not locate ReviewWindowController")
        XCTAssertFalse(
            controller.contains("fullSizeContentView"),
            "review window must not use .fullSizeContentView — it slides content under the toolbar/traffic lights and clips the timeline column"
        )
    }

    func testPreviewsAreConstrainedToCardWidth() {
        let pane = readSource("platform/macos/Sources/Flowline/UI/ReviewStepsPane.swift")
        XCTAssertFalse(pane.isEmpty, "could not locate ReviewStepsPane")
        XCTAssertTrue(
            pane.contains("maxWidth: .infinity, maxHeight: 180")
                || pane.contains("maxWidth:.infinity, maxHeight:180"),
            "GIF + screenshot previews must constrain BOTH width and height to the card (frame maxWidth+maxHeight + clipped), else wide captures overflow the column"
        )
        XCTAssertTrue(
            pane.contains(".clipped()"),
            "previews must clip overflow so oversized captures cannot push the card wider than the column"
        )
    }

    func testStepCardsFillColumnWithoutOverflow() {
        let pane = readSource("platform/macos/Sources/Flowline/UI/ReviewStepsPane.swift")
        XCTAssertFalse(pane.isEmpty, "could not locate ReviewStepsPane")
        XCTAssertTrue(
            pane.contains(".lineLimit(1)") || pane.contains(".truncationMode"),
            "step titles/metadata must truncate gracefully instead of pushing the card wider than the column"
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
        let full = (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(relative)
        if let text = try? String(contentsOfFile: full, encoding: .utf8) { return text }
        return ""
    }
}
