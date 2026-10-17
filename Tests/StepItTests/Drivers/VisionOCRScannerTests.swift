import XCTest
import StepItStorage
import StepItCaptureAPI
import StepItMacCapture
import StepItPublishing
import StepItAIGateway
import StepItPermissions
import StepItIR
import StepItPipeline
import StepItEngine
import AppKit
import CoreGraphics
@testable import StepItCore

/// End-to-end offline OCR checks on synthesized images (T7 DoD:
/// "`VisionOCRScanner` blurs synthetic test images on macOS").
final class VisionOCRScannerTests: XCTestCase {

    /// Renders `text` into a white 1024×220 PNG wide enough for long tokens.
    private func renderTextImage(_ text: String) throws -> Data {
        let size = NSSize(width: 1024, height: 220)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 26, weight: .medium),
            .foregroundColor: NSColor.black
        ]
        text.draw(at: NSPoint(x: 24, y: 95), withAttributes: attributes)
        image.unlockFocus()

        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    func testVisionFindsRenderedText() async throws {
        let scanner = VisionOCRScanner(configuration: .init(recognitionLevel: .accurate))
        let pngData = try renderTextImage("DEPLOY TOKEN sk-1234567890abcdef1234567890abcdef12")

        let items = await scanner.scanText(in: pngData)

        XCTAssertFalse(items.isEmpty, "Vision should recognize the rendered text line")
        let joined = items.map(\.text).joined(separator: " ")
        XCTAssertTrue(joined.contains("sk-"), "OCR result should contain the token: \(joined)")
    }

    func testFullRedactionPipelineBlursSensitiveLines() async throws {
        let pngData = try renderTextImage("API KEY sk-1234567890abcdef1234567890abcdef12")
        let scanner = VisionOCRScanner()
        let settings = PrivacySettings()

        let items = await scanner.scanText(in: pngData)
        let plan = PrivacyRedactionEngine(settings: settings).plan(for: items)
        XCTAssertTrue(plan.isRedacted, "The OCR line should be flagged as sensitive")

        let compositor = BlurCompositor(configuration: .init(style: settings.blurStyle, radius: settings.blurRadius))
        let redacted = try XCTUnwrap(compositor.apply(to: pngData, normalizedRegions: plan.regions))

        XCTAssertNotEqual(redacted, pngData, "The persisted frame must differ from the raw capture")
    }

    func testMacCaptureDriverFacetRunsThePipelineInProcess() async throws {
        let pngData = try renderTextImage("OPENAI_API_KEY=sk-1234567890abcdef1234567890abcdef12")
        let driver = MacCaptureDriver()
        let settings = PrivacySettings()

        let outcome = await driver.redactSensitiveContent(
            in: FrameSnapshot(pngData: pngData, scale: 1.0),
            settings: settings
        )

        XCTAssertTrue(outcome.isRedacted)
        XCTAssertNotEqual(outcome.snapshot.pngData, pngData)
    }

    func testDriverFacetLeavesCleanFramesUntouched() async throws {
        let pngData = try renderTextImage("Release checklist: run swift test")
        let driver = MacCaptureDriver()

        let outcome = await driver.redactSensitiveContent(
            in: FrameSnapshot(pngData: pngData, scale: 1.0),
            settings: PrivacySettings()
        )

        XCTAssertFalse(outcome.isRedacted)
        XCTAssertEqual(outcome.snapshot.pngData, pngData)
    }

    func testDownsamplingKeepsLargeFramesScannable() async throws {
        let scanner = VisionOCRScanner(configuration: .init(maximumDimension: 400))
        let pngData = try renderTextImage("HELLO STEPIT")

        let items = await scanner.scanText(in: pngData)
        XCTAssertFalse(items.isEmpty)
    }

    func testUndecodableDataYieldsNoItems() async {
        let scanner = VisionOCRScanner()
        let items = await scanner.scanText(in: Data([0x00, 0x01, 0x02]))
        XCTAssertTrue(items.isEmpty)
    }
}
