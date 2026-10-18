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

    private func append(_ text: String, to aggregator: TypingBatchAggregator, at location: Point2D = .zero) async {
        for character in text {
            await aggregator.append(char: String(character), at: location)
        }
    }

    func testAppendAndFlushPendingCoalesces() async {
        let aggregator = makeAggregator(context: RawEventFixtures.ctx(app: "Notes"))
        XCTAssertFalse(aggregator.hasPendingText)

        await append("hello", to: aggregator, at: Point2D(x: 1, y: 1))

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
        await aggregator.append(char: " ", at: .zero)
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

        await append("git status", to: aggregator, at: Point2D(x: 100, y: 100))
        await aggregator.handleReturn(at: Point2D(x: 100, y: 100))

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

        await append("hi", to: aggregator)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(box.last?.textBlob, "hi")
    }

    func testBackspaceEditsBuffer() async {
        let aggregator = makeAggregator(context: RawEventFixtures.ctx(app: "Notes"))

        await append("abc", to: aggregator)
        await aggregator.handleBackspace(at: .zero)
        await aggregator.handleBackspace(at: .zero)

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

        await append("npm x", to: aggregator)
        await aggregator.handleBackspace(at: .zero)
        await aggregator.handleControlC(at: .zero)

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

        await aggregator.handleControlC(at: .zero)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(box.last?.textBlob, "^C")
    }

    func testContextProviderDrivesClassificationAndNormalization() async {
        let aggregator = makeAggregator(context: RawEventFixtures.ctx(app: "", windowTitle: "", role: "AXTextField"))
        await aggregator.append(char: "l", at: .zero)
        await aggregator.append(char: "s", at: .zero)

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

        await aggregator.append(char: "x", at: Point2D(x: 1, y: 2))

        let result = await aggregator.flushPending()
        XCTAssertEqual(result?.location, Point2D(x: 300, y: 300))
    }

    func testTinyWindowBoundsKeepTheRecordedLocation() async {
        let bounds = ElementRect(x: 0, y: 0, width: 10, height: 10)
        let aggregator = makeAggregator(context: RawEventFixtures.ctx(app: "Notes", windowBounds: bounds))

        await aggregator.append(char: "x", at: Point2D(x: 1, y: 2))

        let result = await aggregator.flushPending()
        XCTAssertEqual(result?.location, Point2D(x: 1, y: 2))
    }

    // MARK: - Phase 2 (T6): secure field suppression

    private var secureContext: RawElementContext {
        RawEventFixtures.ctx(
            app: "Safari",
            windowTitle: "Sign In",
            role: "AXTextField",
            subrole: "AXSecureTextField",
            value: "hunter2",
            isSecure: true,
            bounds: ElementRect(x: 10, y: 10, width: 200, height: 30)
        )
    }

    func testTypingIntoSecureFieldSuppressesPlaintext() async {
        let aggregator = makeAggregator(context: secureContext)

        await append("SecretPassword123", to: aggregator)
        let result = await aggregator.flushPending()

        // Raw keystrokes never reach the buffer — only bullets do.
        XCTAssertEqual(result?.textBlob, String(repeating: "•", count: "SecretPassword123".count))
        XCTAssertFalse(result?.textBlob.contains("Secret") ?? true)
        // The secure verdict survives into the result + value is stripped.
        XCTAssertEqual(result?.context?.isSecure, true)
        XCTAssertNil(result?.context?.value)
    }

    func testSecureFieldWithMaskingDisabledDropsCharactersEntirely() async {
        let aggregator = makeAggregator(context: secureContext)
        var privacy = PrivacySettings()
        privacy.maskSecureInputFields = false
        aggregator.privacySettings = privacy

        await append("hunter2", to: aggregator)

        XCTAssertFalse(aggregator.hasPendingText)
        let result = await aggregator.flushPending()
        XCTAssertNil(result)
    }

    func testSecureBackspaceEditsMaskedBufferWithoutRevealing() async {
        let aggregator = makeAggregator(context: secureContext)

        await append("•••••", to: aggregator)
        await aggregator.handleBackspace(at: .zero)

        let result = await aggregator.flushPending()
        XCTAssertEqual(result?.textBlob, "••••")
    }

    func testNonSecureTypingIsBufferedRaw() async {
        let aggregator = makeAggregator(context: RawEventFixtures.ctx(app: "Notes", isSecure: false))

        await append("hello", to: aggregator)
        let result = await aggregator.flushPending()

        XCTAssertEqual(result?.textBlob, "hello")
    }

    func testSecureVerdictIsRecheckedWhenFocusChangesMidBatch() async {
        // Email field → password field without a debounce boundary: the second
        // half of the batch must be masked, never buffered raw.
        let flag = SecureFlag()
        let aggregator = TypingBatchAggregator(
            configuration: .init(debounceInterval: 5.0),
            contextProvider: {
                flag.isSecure
                    ? RawEventFixtures.ctx(app: "Safari", role: "AXSecureTextField", isSecure: true)
                    : RawEventFixtures.ctx(app: "Safari", role: "AXTextField")
            }
        )

        await append("ab", to: aggregator)
        flag.isSecure = true
        await append("cd", to: aggregator)

        let result = await aggregator.flushPending()
        XCTAssertEqual(result?.textBlob, "ab••")
    }
}

/// Thread-safe mutable secure flag for the mid-batch flip test.
private final class SecureFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSecure: Bool {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}
