import XCTest
import StepItIR
import StepItPipeline
import StepItEngine
import CoreGraphics
import ImageIO
@testable import StepItCore

final class PrivacyRedactionTests: XCTestCase {

    private func item(_ text: String, x: Double = 0.1, y: Double = 0.1, w: Double = 0.6, h: Double = 0.05) -> OCRTextItem {
        OCRTextItem(text: text, boundingBox: ElementRect(x: x, y: y, width: w, height: h))
    }

    // MARK: - Planning

    func testSensitiveLineProducesABlurredRegion() {
        let engine = PrivacyRedactionEngine(settings: PrivacySettings())
        let apiKeyLine = item("OPENAI_API_KEY=sk-1234567890abcdef1234567890abcdef12")

        let plan = engine.plan(for: [apiKeyLine])

        XCTAssertTrue(plan.isRedacted)
        XCTAssertEqual(plan.matches.map(\.kind), [.openAIAPIKey])
        XCTAssertEqual(plan.regions.count, 1)
        // Region covers the OCR box (plus small padding).
        let region = plan.regions[0]
        XCTAssertLessThanOrEqual(region.x, apiKeyLine.boundingBox.x)
        XCTAssertGreaterThanOrEqual(region.width, apiKeyLine.boundingBox.width)
        XCTAssertGreaterThanOrEqual(region.height, apiKeyLine.boundingBox.height)
    }

    func testCleanLinesProduceNoRegions() {
        let engine = PrivacyRedactionEngine(settings: PrivacySettings())
        let plan = engine.plan(for: [
            item("Run swift test before pushing"),
            item("Open the Review Window and export the guide")
        ])

        XCTAssertFalse(plan.isRedacted)
        XCTAssertTrue(plan.regions.isEmpty)
        XCTAssertTrue(plan.matches.isEmpty)
    }

    func testMixedFrameRedactsOnlySensitiveLines() {
        let engine = PrivacyRedactionEngine(settings: PrivacySettings())
        let clean = item("Deploy notes", y: 0.8)
        let secret = item("Card: 4111 1111 1111 1111", y: 0.4)

        let plan = engine.plan(for: [clean, secret])

        XCTAssertEqual(plan.regions.count, 1)
        XCTAssertEqual(plan.regions[0].y, secret.boundingBox.y, accuracy: secret.boundingBox.height * 0.1)
    }

    func testDisabledOCRRedactionPlansNothing() {
        var privacy = PrivacySettings()
        privacy.enableOfflineOCRRedaction = false

        let engine = PrivacyRedactionEngine(settings: privacy)
        let plan = engine.plan(for: [item("sk-1234567890abcdef1234567890abcdef12")])

        XCTAssertFalse(plan.isRedacted)
    }

    func testEmailRedactionFollowsSettings() {
        var privacy = PrivacySettings()
        privacy.autoRedactEmails = true
        let engine = PrivacyRedactionEngine(settings: privacy)

        XCTAssertTrue(engine.plan(for: [item("shivam@example.com")]).isRedacted)
        XCTAssertFalse(PrivacyRedactionEngine(settings: PrivacySettings()).plan(for: [item("shivam@example.com")]).isRedacted)
    }

    func testPaddingIsClampedToNormalizedBounds() {
        let engine = PrivacyRedactionEngine(settings: PrivacySettings())
        let corner = item("ghp_" + String(repeating: "A", count: 36), x: 0.99, y: 0.0, w: 0.01, h: 0.01)

        let plan = engine.plan(for: [corner])

        XCTAssertEqual(plan.regions.count, 1)
        let region = plan.regions[0]
        XCTAssertGreaterThanOrEqual(region.x, 0)
        XCTAssertGreaterThanOrEqual(region.y, 0)
        XCTAssertLessThanOrEqual(region.x + region.width, 1.0 + 0.0001)
        XCTAssertLessThanOrEqual(region.y + region.height, 1.0 + 0.0001)
    }

    // MARK: - Compositor

    func testBlurCompositorChangesPixelsForFrostedGlass() throws {
        // A quadrant texture is required: blurring a solid fill is a no-op.
        let pngData = try XCTUnwrap(TestImages.quadrantsPNG(width: 128, height: 128))
        let compositor = BlurCompositor(configuration: .init(style: .frostedGlass, radius: 16))

        let redacted = try XCTUnwrap(compositor.apply(
            to: pngData,
            normalizedRegions: [ElementRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)]
        ))

        XCTAssertNotEqual(redacted, pngData)
        XCTAssertEqual([UInt8](redacted.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    func testBlurCompositorBlackoutProducesBlackPixels() throws {
        let pngData = try XCTUnwrap(TestImages.solidPNG(width: 64, height: 64, color: (0.2, 0.4, 0.9)))
        let compositor = BlurCompositor(configuration: .init(style: .blackout, radius: 0))

        let redacted = try XCTUnwrap(compositor.apply(
            to: pngData,
            normalizedRegions: [ElementRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)]
        ))

        let centerPixel = try XCTUnwrap(TestImages.centerPixel(of: redacted))
        XCTAssertLessThan(centerPixel.red, 0.05)
        XCTAssertLessThan(centerPixel.green, 0.05)
        XCTAssertLessThan(centerPixel.blue, 0.05)
    }

    func testEmptyRegionsReturnTheOriginalData() throws {
        let pngData = try XCTUnwrap(TestImages.solidPNG(width: 16, height: 16, color: (1, 1, 1)))
        let compositor = BlurCompositor()
        XCTAssertEqual(compositor.apply(to: pngData, normalizedRegions: []), pngData)
    }
}

// MARK: - Test image helpers

enum TestImages {
    static func solidPNG(width: Int, height: Int, color: (Double, Double, Double)) -> Data? {
        renderPNG(width: width, height: height) { context in
            context.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1.0)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// Four sharply different quadrants — blurring across the seams changes pixels.
    static func quadrantsPNG(width: Int, height: Int) -> Data? {
        renderPNG(width: width, height: height) { context in
            let half = CGRect(x: 0, y: 0, width: width / 2, height: height / 2)
            let colors: [(CGFloat, CGFloat, CGFloat)] = [(0.1, 0.1, 0.9), (0.9, 0.1, 0.1), (0.1, 0.9, 0.2), (0.95, 0.85, 0.1)]
            var index = 0
            for x in [0, width / 2] {
                for y in [0, height / 2] {
                    let color = colors[index]
                    context.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1.0)
                    context.fill(CGRect(x: CGFloat(x), y: CGFloat(y), width: half.width, height: half.height))
                    index += 1
                }
            }
        }
    }

    private static func renderPNG(width: Int, height: Int, draw: (CGContext) -> Void) -> Data? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        draw(context)
        guard let image = context.makeImage() else { return nil }
        return BlurCompositor.encodePNG(image)
    }

    /// Reads the very center pixel back as normalized RGB.
    static func centerPixel(of pngData: Data) -> (red: Double, green: Double, blue: Double)? {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        let width = image.width
        let height = image.height
        var pixel = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        return (Double(pixel[0]) / 255.0, Double(pixel[1]) / 255.0, Double(pixel[2]) / 255.0)
    }
}
