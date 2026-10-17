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
@testable import StepItFixtures

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
}
