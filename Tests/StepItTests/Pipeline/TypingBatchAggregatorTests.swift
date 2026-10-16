import XCTest
@testable import StepItCore

final class TypingBatchAggregatorTests: XCTestCase {

    private func makeAggregator(
        debounceInterval: TimeInterval = 0.05,
        context: RawElementContext? = nil
    ) -> TypingBatchAggregator {
        TypingBatchAggregator(
            configuration: TypingBatchAggregator.Configuration(debounceInterval: debounceInterval),
            contextProvider: { context }
        )
    }

    func testAppendAndFlushPendingCoalesces() async {
        let aggregator = makeAggregator(context: RawEventFixtures.ctx(app: "Notes"))
        XCTAssertFalse(aggregator.hasPendingText)

        for character in "hello" {
            aggregator.append(char: String(character), at: Point2D(x: 1, y: 1))
        }

        XCTAssertTrue(aggregator.hasPendingText)
        let result = await aggregator.flushPending()

        XCTAssertEqual(result?.textBlob, "hello")
        XCTAssertEqual(result?.classification, .text)
        XCTAssertFalse(aggregator.hasPendingText)
        let flushed = await aggregator.flushPending()
        XCTAssertNil(flushed)
    }

    func testFlushWithoutPendingTextReturnsNil() async {
        let aggregator = makeAggregator()
        let empty = await aggregator.flushPending()
        XCTAssertNil(empty)

        // Whitespace-only buffers also produce nothing.
        aggregator.append(char: " ", at: .zero)
        let whitespace = await aggregator.flushPending()
        XCTAssertNil(whitespace)
    }

    func testReturnFinalizesImmediatelyThroughCallback() async {
        let aggregator = makeAggregator(context: RawEventFixtures.ctx(app: "Ghostty", bundleId: "com.mitchellh.ghostty"))
        let box = TypingResultBox()
        let expectation = expectation(description: "Return finalizes the command")

        aggregator.onBatchCompleted = { result in
            box.append(result)
            expectation.fulfill()
        }

        for character in "git status" {
            aggregator.append(char: String(character), at: Point2D(x: 100, y: 100))
        }
        aggregator.handleReturn(at: Point2D(x: 100, y: 100))

        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertEqual(box.last?.textBlob, "git status")
        XCTAssertEqual(box.last?.classification, .terminal)
        XCTAssertFalse(aggregator.hasPendingText)
    }

    func testDebounceFinalizesOnInactivity() async {
        let aggregator = makeAggregator(debounceInterval: 0.05, context: RawEventFixtures.ctx(app: "Notes"))
        let box = TypingResultBox()
        let expectation = expectation(description: "Debounce fires")

        aggregator.onBatchCompleted = { result in
            box.append(result)
            expectation.fulfill()
        }

        for character in "hi" {
            aggregator.append(char: String(character), at: .zero)
        }

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(box.last?.textBlob, "hi")
    }

    func testBackspaceEditsBuffer() async {
        let aggregator = makeAggregator(context: RawEventFixtures.ctx(app: "Notes"))

        for character in "abc" {
            aggregator.append(char: String(character), at: .zero)
        }
        aggregator.handleBackspace(at: .zero)
        aggregator.handleBackspace(at: .zero)

        let result = await aggregator.flushPending()
        XCTAssertEqual(result?.textBlob, "a")
    }

    func testControlCAppendsInterruptMarkerAndFinalizes() async {
        let aggregator = makeAggregator(context: RawEventFixtures.ctx(app: "Ghostty", bundleId: "com.mitchellh.ghostty"))
        let box = TypingResultBox()
        let expectation = expectation(description: "Ctrl+C finalizes the batch")

        aggregator.onBatchCompleted = { result in
            box.append(result)
            expectation.fulfill()
        }

        for character in "npm x" {
            aggregator.append(char: String(character), at: .zero)
        }
        aggregator.handleBackspace(at: .zero)
        aggregator.handleControlC(at: .zero)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(box.last?.textBlob, "npm  ^C")
        XCTAssertEqual(box.last?.classification, .terminal)
    }

    func testControlCOnEmptyBufferProducesMarker() async {
        let aggregator = makeAggregator(context: RawEventFixtures.ctx(app: "Ghostty"))
        let box = TypingResultBox()
        let expectation = expectation(description: "Ctrl+C on an empty buffer finalizes ^C")

        aggregator.onBatchCompleted = { result in
            box.append(result)
            expectation.fulfill()
        }

        aggregator.handleControlC(at: .zero)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(box.last?.textBlob, "^C")
    }

    func testContextProviderDrivesClassificationAndNormalization() async {
        let aggregator = makeAggregator(context: RawEventFixtures.ctx(app: "", windowTitle: "", role: "AXTextField"))
        aggregator.append(char: "l", at: .zero)
        aggregator.append(char: "s", at: .zero)

        let result = await aggregator.flushPending()

        // Empty app name falls back to the legacy "Terminal" default and the
        // window title falls back to the app name (old aggregator parity).
        XCTAssertEqual(result?.context?.appName, "Terminal")
        XCTAssertEqual(result?.context?.windowTitle, "Terminal")
        XCTAssertEqual(result?.classification, .terminal)
    }

    func testWindowBoundsProduceCenterLocation() async {
        let bounds = ElementRect(x: 100, y: 200, width: 400, height: 200)
        let aggregator = makeAggregator(context: RawEventFixtures.ctx(app: "Notes", windowBounds: bounds))

        aggregator.append(char: "x", at: Point2D(x: 1, y: 2))

        let result = await aggregator.flushPending()
        XCTAssertEqual(result?.location, Point2D(x: 300, y: 300))
    }

    func testTinyWindowBoundsKeepTheRecordedLocation() async {
        let bounds = ElementRect(x: 0, y: 0, width: 10, height: 10)
        let aggregator = makeAggregator(context: RawEventFixtures.ctx(app: "Notes", windowBounds: bounds))

        aggregator.append(char: "x", at: Point2D(x: 1, y: 2))

        let result = await aggregator.flushPending()
        XCTAssertEqual(result?.location, Point2D(x: 1, y: 2))
    }
}
