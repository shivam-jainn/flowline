import XCTest
import StepItEngine
import StepItStorage
import StepItMacCapture
import StepItPublishing
import StepItAIGateway
import StepItPermissions
import Foundation
import StepItIR
import StepItPipeline
import StepItCaptureAPI

/// R/M1-05: native quarantine. The capture SPI + mocks live in
/// `StepItCaptureAPI` and macOS drivers in `StepItMacCapture`; these tests
/// prove the headless surface works without AppKit/Vision.
final class PhaseR05NativeTests: XCTestCase {

    // (a) The mock driver produces events headless (no CGEvent, no AX, no screen).
    func testMockDriverProducesEventsHeadless() async {
        let driver = MockCaptureDriver()
        try? await driver.start()
        var iterator = driver.eventStream.makeAsyncIterator()

        driver.emitClick(at: Point2D(x: 7, y: 9), clickCount: 1)
        let event = await iterator.next()
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.kind, .mouseClick(button: .left, clickCount: 1))
        XCTAssertEqual(event?.location, Point2D(x: 7, y: 9))

        await driver.stop()
        XCTAssertTrue(driver.started)
        XCTAssertEqual(driver.stoppedCount, 1)
        let tail = await iterator.next()
        XCTAssertNil(tail)
    }

    // (b) OCRScanning has a stub conformance usable without Vision.
    func testOCRScanningStubNeedsNoVision() async {
        struct StubOCRScanner: OCRScanning {
            let items: [OCRTextItem]
            func scanText(in pngData: Data) async -> [OCRTextItem] { items }
        }
        let fixture = OCRTextItem(
            text: "sk-test-key",
            boundingBox: ElementRect(x: 0, y: 0, width: 1, height: 1))
        let scanner: any OCRScanning = StubOCRScanner(items: [fixture])
        let items = await scanner.scanText(in: MockAssets.onePixelPNG)
        XCTAssertEqual(items, [fixture])
    }

    // (c) Moved driver suites work unmodified via the CaptureAPI surface.
    func testMovedDriverSuitesUnmodified() async {
        let driver = MockCaptureDriver()
        XCTAssertEqual(driver.platformIdentifier, "mock")
        XCTAssertEqual(driver.capabilities, .mockFull)

        // Terminal facet: no inspector → nil pwd, request still recorded.
        let pwd = await driver.inspectTerminalWorkingDirectory(
            bundleId: "com.apple.Terminal", pid: nil, windowTitle: "user — -zsh — 80x24")
        XCTAssertNil(pwd)
        XCTAssertEqual(driver.terminalRequests.count, 1)

        // Redaction facet default: no provider → snapshot passes through unredacted.
        let snapshot = FrameSnapshot(pngData: MockAssets.onePixelPNG, scale: 2.0)
        let outcome = await driver.redactSensitiveContent(in: snapshot, settings: PrivacySettings())
        XCTAssertFalse(outcome.isRedacted)
        XCTAssertEqual(outcome.snapshot, snapshot)

        // Gesture settings sink records without touching AppKit detectors.
        await driver.updateGestureSettings(GestureSettings())
        XCTAssertEqual(driver.appliedGestureSettings.count, 1)
    }
}
