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
@testable import StepItCore

final class MockCaptureDriverTests: XCTestCase {

    func testYieldDeliversToStream() async {
        let driver = MockCaptureDriver()
        var iterator = driver.eventStream.makeAsyncIterator()

        driver.emitClick(at: Point2D(x: 10, y: 20), clickCount: 2)

        let event = await iterator.next()
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.kind, .mouseClick(button: .left, clickCount: 2))
        XCTAssertEqual(event?.location, Point2D(x: 10, y: 20))
    }

    func testStopFinishesTheStream() async {
        let driver = MockCaptureDriver()
        try? await driver.start()
        var iterator = driver.eventStream.makeAsyncIterator()

        await driver.stop()

        let event = await iterator.next()
        XCTAssertNil(event)
        XCTAssertEqual(driver.stoppedCount, 1)
        XCTAssertTrue(driver.started)
    }

    func testCapabilityFlagsRoundTrip() {
        let limited = MockCaptureDriver(capabilities: CaptureCapabilities(
            snapshots: true,
            microClips: false,
            accessibilityTree: false,
            secureFieldDetection: true
        ))
        XCTAssertFalse(limited.capabilities.microClips)
        XCTAssertFalse(limited.capabilities.accessibilityTree)

        XCTAssertEqual(MockCaptureDriver().platformIdentifier, "mock")
        XCTAssertEqual(MockCaptureDriver().capabilities, .mockFull)
    }

    func testConvenienceEmittersProduceIRkinds() async {
        let driver = MockCaptureDriver()
        var iterator = driver.eventStream.makeAsyncIterator()
        let point = Point2D(x: 1, y: 2)

        driver.emitKey("a", code: 0, modifiers: [], location: point)
        driver.emitHotkey("⌥Space")
        driver.emitGesture(name: "Middle-Click 🖱️", action: .addCheckpoint, location: point)

        let first = await iterator.next()
        let second = await iterator.next()
        let third = await iterator.next()

        XCTAssertEqual(first?.kind, .keyStroke(key: "a", code: 0, modifiers: []))
        XCTAssertEqual(second?.kind, .hotkeyCombo(combo: "⌥Space"))
        XCTAssertEqual(third?.kind, .userGesture(name: "Middle-Click 🖱️", action: .addCheckpoint))
    }

    func testProviderScriptingAndSpies() async {
        let driver = MockCaptureDriver()
        driver.contextProvider = { point in
            RawEventFixtures.ctx(app: "Notes", title: "Clicked at \(Int(point.x))")
        }
        driver.focusedContextProvider = { RawEventFixtures.ctx(app: "Ghostty") }

        let context = await driver.inspectElement(at: Point2D(x: 42, y: 0))
        XCTAssertEqual(context?.appName, "Notes")
        XCTAssertEqual(context?.title, "Clicked at 42")

        let focused = await driver.inspectFocusedElement()
        XCTAssertEqual(focused?.appName, "Ghostty")

        let snapshot = await driver.captureSnapshot(highlightAt: Point2D(x: 5, y: 5), stepIndex: 3)
        XCTAssertNotNil(snapshot?.pngData)
        XCTAssertEqual(driver.snapshotStepIndices, [3])
        XCTAssertEqual(driver.lastHighlightPoint, Point2D(x: 5, y: 5))

        let clip = await driver.captureMicroClip(around: Point2D(x: 5, y: 5), postDuration: 0.6)
        XCTAssertNotNil(clip?.gifData)
        XCTAssertEqual(driver.clipRequests.count, 1)

        await driver.startClipBuffering(config: ClipBufferConfig(fps: 15, maxBufferSeconds: 0.5))
        XCTAssertTrue(driver.isBuffering)
        XCTAssertEqual(driver.bufferingConfig, ClipBufferConfig(fps: 15, maxBufferSeconds: 0.5))
        await driver.stopClipBuffering()
        XCTAssertFalse(driver.isBuffering)

        await driver.pause()
        XCTAssertTrue(driver.paused)
        await driver.resume()
        XCTAssertFalse(driver.paused)

        let settings = GestureSettings()
        await driver.updateGestureSettings(settings)
        XCTAssertEqual(driver.appliedGestureSettings.count, 1)
    }

    func testFocusedInspectionFallsBackToClickProvider() async {
        let driver = MockCaptureDriver(contextProvider: { _ in RawEventFixtures.ctx(app: "Finder") })
        let focused = await driver.inspectFocusedElement()
        XCTAssertEqual(focused?.appName, "Finder")
        XCTAssertEqual(driver.focusedInspectionCount, 1)
    }
}
