import XCTest
import FlowlineStorage
import FlowlineCaptureAPI
import FlowlineMacCapture
import FlowlinePublishing
import FlowlineAIGateway
import FlowlinePermissions
import FlowlineIR
import FlowlinePipeline
import FlowlineEngine
@testable import FlowlineFixtures

final class MouseDragDetectorTests: XCTestCase {

    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testSmallJitterIsTreatedAsAClick() {
        let detector = MouseDragDetector()

        detector.handleMouseDown(at: CGPoint(x: 100, y: 100), timestamp: start)
        let gesture = detector.handleMouseUp(at: CGPoint(x: 108, y: 105), timestamp: start.addingTimeInterval(0.3))

        XCTAssertNotNil(gesture)
        XCTAssertFalse(gesture?.isDrag ?? true, "8pt / 300ms jitter must stay a click")
        XCTAssertEqual(gesture?.start, CGPoint(x: 100, y: 100))
        XCTAssertEqual(gesture?.end, CGPoint(x: 108, y: 105))
        XCTAssertEqual(gesture?.distance ?? 0, (8.0 * 8.0 + 5.0 * 5.0).squareRoot(), accuracy: 0.0001)
    }

    func testDeliberateDragExceedsBothThresholds() {
        let detector = MouseDragDetector()

        detector.handleMouseDown(at: CGPoint(x: 10, y: 10), timestamp: start)
        let gesture = detector.handleMouseUp(at: CGPoint(x: 310, y: 210), timestamp: start.addingTimeInterval(0.5))

        XCTAssertTrue(gesture?.isDrag ?? false)
        XCTAssertEqual(gesture?.distance ?? 0, (300.0 * 300.0 + 200.0 * 200.0).squareRoot(), accuracy: 0.01)
        XCTAssertEqual(gesture?.duration ?? 0, 0.5, accuracy: 0.0001)
    }

    func testFastFlickWithLargeDisplacementIsADrag() {
        // Pointer-disambiguation rule: distance > 10pt is always a drag —
        // press → release velocity replaces the old minimum-duration gate,
        // so a 200pt flick in 50ms (4000pt/s) must not collapse to a click.
        let detector = MouseDragDetector()

        detector.handleMouseDown(at: CGPoint(x: 0, y: 0), timestamp: start)
        let gesture = detector.handleMouseUp(at: CGPoint(x: 200, y: 0), timestamp: start.addingTimeInterval(0.05))

        XCTAssertTrue(gesture?.isDrag ?? false)
    }

    func testLongPressWithoutMovementIsNotADrag() {
        let detector = MouseDragDetector()

        detector.handleMouseDown(at: CGPoint(x: 50, y: 50), timestamp: start)
        let gesture = detector.handleMouseUp(at: CGPoint(x: 50, y: 50), timestamp: start.addingTimeInterval(1.2))

        XCTAssertFalse(gesture?.isDrag ?? true)
    }

    func testThresholdsAreConfigurable() {
        let detector = MouseDragDetector(configuration: .init(minimumDistance: 5, minimumDuration: 0.01))

        detector.handleMouseDown(at: CGPoint(x: 0, y: 0), timestamp: start)
        let gesture = detector.handleMouseUp(at: CGPoint(x: 10, y: 0), timestamp: start.addingTimeInterval(0.02))

        XCTAssertTrue(gesture?.isDrag ?? false)
    }

    func testMouseUpWithoutTrackedDownReturnsNil() {
        let detector = MouseDragDetector()
        XCTAssertNil(detector.handleMouseUp(at: CGPoint(x: 1, y: 1)))
        XCTAssertFalse(detector.isTracking)
    }

    func testTrackingStateResetsAfterRelease() {
        let detector = MouseDragDetector()
        XCTAssertFalse(detector.isTracking)

        detector.handleMouseDown(at: .zero)
        XCTAssertTrue(detector.isTracking)

        _ = detector.handleMouseUp(at: CGPoint(x: 1, y: 1))
        XCTAssertFalse(detector.isTracking)
    }

    // MARK: - Pointer-disambiguation bands

    func testSubClickRadiusIgnoresMoves() {
        // < 4pt stays a click however slow the hold.
        XCTAssertEqual(MouseDragDetector.classify(distance: 3.9, duration: 0.05), .click)
        XCTAssertEqual(MouseDragDetector.classify(distance: 0.0, duration: 1.20), .click)
    }

    func testMidBandSlowIsJitterNotDrag() {
        // 8.9pt in 300ms ≈ 30pt/s — hand tremor. Jitter surfaces as a click.
        let distance = (8.0 * 8.0 + 5.0 * 5.0).squareRoot()
        XCTAssertEqual(MouseDragDetector.classify(distance: distance, duration: 0.30), .jitter)

        let detector = MouseDragDetector()
        detector.handleMouseDown(at: CGPoint(x: 100, y: 100), timestamp: start)
        let gesture = detector.handleMouseUp(
            at: CGPoint(x: 108, y: 105),
            timestamp: start.addingTimeInterval(0.3)
        )
        XCTAssertEqual(gesture?.isDrag, false)
    }

    func testMidBandFastIsDrag() {
        // Same displacement flicked in 20ms ≈ 447pt/s.
        let distance = (8.0 * 8.0 + 5.0 * 5.0).squareRoot()
        XCTAssertEqual(MouseDragDetector.classify(distance: distance, duration: 0.02), .drag)
    }

    func testHeldPastClickRadiusIsDrag() {
        XCTAssertEqual(MouseDragDetector.classify(distance: 5.0, duration: 0.31), .drag)
        // Exactly on the hold boundary stays in the velocity gate.
        XCTAssertEqual(MouseDragDetector.classify(distance: 5.0, duration: 0.30), .jitter)
    }

    func testTrackpadDeadzoneIsWider() {
        // 5pt: a click on trackpad, velocity-gated on a mouse.
        XCTAssertEqual(MouseDragDetector.classify(distance: 5.0, duration: 0.05, isTrackpad: true), .click)
        XCTAssertEqual(MouseDragDetector.classify(distance: 5.0, duration: 0.05, isTrackpad: false), .drag)
        // Trackpad rim: the velocity gate still applies.
        XCTAssertEqual(MouseDragDetector.classify(distance: 6.0, duration: 1.00, isTrackpad: true), .drag)
        XCTAssertEqual(MouseDragDetector.classify(distance: 6.0, duration: 0.30, isTrackpad: true), .jitter)

        let detector = MouseDragDetector()
        detector.handleMouseDown(at: .zero, timestamp: start)
        let gesture = detector.handleMouseUp(
            at: CGPoint(x: 5, y: 0),
            timestamp: start.addingTimeInterval(0.05),
            isTrackpad: true
        )
        XCTAssertEqual(gesture?.isDrag, false)
    }

    func testLegacyMinimumDistanceAliasStillMaps() {
        // The T8-era initializer keeps compiling and still drags past it.
        var config = MouseDragDetector.Configuration(minimumDistance: 5, minimumDuration: 0.01)
        XCTAssertEqual(config.dragRadius, 5)
        XCTAssertEqual(config.longHoldDuration, 0.01, accuracy: 0.0001)
        config.minimumDistance = 12
        XCTAssertEqual(config.dragRadius, 12)
    }
}
