import XCTest
import StepItIR
import StepItPipeline
@testable import StepItCore

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

    func testFastFlickBelowDurationThresholdIsNotADrag() {
        // The documented Phase 2 rule: distance > 15pt **and** duration > 0.15s.
        let detector = MouseDragDetector()

        detector.handleMouseDown(at: CGPoint(x: 0, y: 0), timestamp: start)
        let gesture = detector.handleMouseUp(at: CGPoint(x: 200, y: 0), timestamp: start.addingTimeInterval(0.05))

        XCTAssertFalse(gesture?.isDrag ?? true)
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
}
