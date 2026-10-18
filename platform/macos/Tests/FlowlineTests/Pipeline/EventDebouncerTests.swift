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

final class EventDebouncerTests: XCTestCase {

    func testFirstEventIsAlwaysAccepted() {
        var debouncer = EventDebouncer(minInterval: 0.20)
        XCTAssertTrue(debouncer.shouldAccept(at: Date(timeIntervalSinceReferenceDate: 100)))
    }

    func testRapidClicksWithin200msAreDropped() {
        var debouncer = EventDebouncer(minInterval: 0.20)
        let start = Date(timeIntervalSinceReferenceDate: 100)

        XCTAssertTrue(debouncer.shouldAccept(at: start))
        XCTAssertFalse(debouncer.shouldAccept(at: start.addingTimeInterval(0.05)))
        XCTAssertFalse(debouncer.shouldAccept(at: start.addingTimeInterval(0.19)))
    }

    func testClicksAfterIntervalAreAccepted() {
        var debouncer = EventDebouncer(minInterval: 0.20)
        let start = Date(timeIntervalSinceReferenceDate: 100)

        XCTAssertTrue(debouncer.shouldAccept(at: start))
        XCTAssertTrue(debouncer.shouldAccept(at: start.addingTimeInterval(0.21)))
        XCTAssertTrue(debouncer.shouldAccept(at: start.addingTimeInterval(0.42)))
    }

    func testRejectedEventDoesNotMoveTheWindow() {
        var debouncer = EventDebouncer(minInterval: 0.20)
        let start = Date(timeIntervalSinceReferenceDate: 100)

        XCTAssertTrue(debouncer.shouldAccept(at: start))
        XCTAssertFalse(debouncer.shouldAccept(at: start.addingTimeInterval(0.15)))
        // 0.21 after the last *accepted* event → accepted (the rejected event
        // must not have shifted the window).
        XCTAssertTrue(debouncer.shouldAccept(at: start.addingTimeInterval(0.21)))
    }

    func testResetAllowsImmediateAcceptance() {
        var debouncer = EventDebouncer(minInterval: 0.20)
        let start = Date(timeIntervalSinceReferenceDate: 100)

        XCTAssertTrue(debouncer.shouldAccept(at: start))
        debouncer.reset()
        XCTAssertTrue(debouncer.shouldAccept(at: start.addingTimeInterval(0.01)))
    }

    // MARK: - Velocity-aware click gate

    func testAdaptiveIntervalClamps() {
        // Stationary pointer: 200 * 1.5 = 300ms.
        XCTAssertEqual(EventDebouncer.adaptiveInterval(base: 0.2, velocityPxPerSec: 0), 0.30, accuracy: 1e-9)
        // Fast pointer: 200 * (1.5 - 0.8) = 140ms.
        XCTAssertEqual(EventDebouncer.adaptiveInterval(base: 0.2, velocityPxPerSec: 100), 0.14, accuracy: 1e-9)
        // Unknown velocity: base window (legacy replay parity).
        XCTAssertEqual(EventDebouncer.adaptiveInterval(base: 0.2, velocityPxPerSec: nil), 0.20, accuracy: 1e-9)
    }

    func testCloseFastRepeatIsBounceAndHoldsWindow() {
        var debouncer = EventDebouncer(minInterval: 0.20)
        let start = Date(timeIntervalSinceReferenceDate: 100)
        let point = Point2D(x: 100, y: 200)

        XCTAssertTrue(debouncer.shouldAcceptClick(at: start, location: point, osClickCount: 1))
        // 3pt away after 100ms: bounce, window unmoved.
        XCTAssertFalse(debouncer.shouldAcceptClick(
            at: start.addingTimeInterval(0.1),
            location: Point2D(x: 103, y: 200),
            osClickCount: 1
        ))
        // 350ms after the *accepted* click: outside the ~300ms stationary
        // window, so a distinct click.
        XCTAssertTrue(debouncer.shouldAcceptClick(
            at: start.addingTimeInterval(0.35),
            location: point,
            osClickCount: 1
        ))
    }

    func testFarFastRelocationIsDistinct() {
        var debouncer = EventDebouncer(minInterval: 0.20)
        let start = Date(timeIntervalSinceReferenceDate: 100)

        XCTAssertTrue(debouncer.shouldAcceptClick(
            at: start, location: Point2D(x: 0, y: 0), osClickCount: 1
        ))
        // 100pt in 100ms: fast relocation, distinct even though quick.
        XCTAssertTrue(debouncer.shouldAcceptClick(
            at: start.addingTimeInterval(0.1),
            location: Point2D(x: 100, y: 0),
            osClickCount: 1
        ))
    }

    func testOSDoubleIsAcceptedNotSuppressed() {
        var debouncer = EventDebouncer(minInterval: 0.20)
        let start = Date(timeIntervalSinceReferenceDate: 100)
        let point = Point2D(x: 50, y: 50)

        XCTAssertTrue(debouncer.shouldAcceptClick(at: start, location: point, osClickCount: 1))
        // Second press of an OS double lands inside the bounce window but
        // must still surface as the double — not a suppressed bounce, not a
        // second single.
        XCTAssertTrue(debouncer.shouldAcceptClick(
            at: start.addingTimeInterval(0.25),
            location: point,
            osClickCount: 2
        ))
    }

    func testRejectedBounceHoldsWindowForLaterClicks() {
        var debouncer = EventDebouncer(minInterval: 0.20)
        let start = Date(timeIntervalSinceReferenceDate: 100)
        let point = Point2D(x: 7, y: 7)

        XCTAssertTrue(debouncer.shouldAcceptClick(at: start, location: point, osClickCount: 1))
        XCTAssertFalse(debouncer.shouldAcceptClick(
            at: start.addingTimeInterval(0.1), location: point, osClickCount: 1
        ))
        XCTAssertTrue(debouncer.shouldAcceptClick(
            at: start.addingTimeInterval(0.35), location: point, osClickCount: 1
        ))
    }
}
