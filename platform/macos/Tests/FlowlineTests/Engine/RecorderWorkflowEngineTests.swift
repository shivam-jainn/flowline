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

final class RecorderWorkflowEngineTests: XCTestCase {

    private var tempDirectory: URL!
    private var store: SessionStore!
    private var driver: MockCaptureDriver!
    private var clock: TestClock!
    private var engine: RecorderWorkflowEngine!
    private var probe: SnapshotProbe!

    private let clickPoint = Point2D(x: 100, y: 100)

    override func setUp() async throws {
        try await super.setUp()

        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FlowlineEngineTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        store = SessionStore(customBaseDirectory: tempDirectory)
        driver = MockCaptureDriver()
        clock = TestClock()
        engine = RecorderWorkflowEngine(
            driver: driver,
            store: store,
            time: clock,
            config: RecorderWorkflowEngine.EngineConfig(typingDebounceInterval: 0.05, gestureNoticeDuration: 2.5)
        )
        try await engine.start()

        probe = SnapshotProbe()
        await probe.attach(to: engine)
    }

    override func tearDown() async throws {
        probe?.cancel()
        await engine?.shutdown()
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    // MARK: - Awaiting helpers (XCTest autoclosures cannot take `await`)

    @discardableResult
    private func startRecording(
        title: String = "Workflow Recording",
        theme: ThemeName = .modernMinimal,
        mediaMode: MediaMode = .hybrid
    ) async throws -> StepSession {
        let session = try await engine.startRecording(title: title, theme: theme, mediaMode: mediaMode)
        return try XCTUnwrap(session)
    }

    private func waitForSession(
        timeout: TimeInterval = 2.0,
        _ predicate: (StepSession?) -> Bool
    ) async -> StepSession? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let session = await engine.currentSnapshot().currentSession
            if predicate(session) { return session }
            if Date() >= deadline { return nil }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    /// Waits for an exact step count and fails the test if it never arrives.
    @discardableResult
    private func expectSteps(
        _ count: Int,
        timeout: TimeInterval = 2.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> StepSession? {
        let session = await waitForSession(timeout: timeout) { ($0?.steps.count ?? 0) == count }
        XCTAssertNotNil(session, "Expected \(count) step(s) within \(timeout)s", file: file, line: line)
        return session
    }

    private func expectState(
        _ state: RecordingState,
        timeout: TimeInterval = 2.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let reached = await waitForState(state, timeout: timeout)
        XCTAssertTrue(reached, "Expected state \(state) within \(timeout)s", file: file, line: line)
    }

    private func waitForState(_ state: RecordingState, timeout: TimeInterval = 2.0) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if await engine.currentSnapshot().state == state { return true }
            if Date() >= deadline { return false }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func currentState() async -> RecordingState {
        await engine.currentSnapshot().state
    }

    private func currentSnapshot() async -> RecorderSnapshot {
        await engine.currentSnapshot()
    }

    // MARK: - Engine lifecycle

    func testStartRecordingCreatesSessionAndStartsDriver() async throws {
        driver.contextProvider = { _ in RawEventFixtures.ctx(app: "Safari") }

        let session = try await startRecording(title: "First Session", theme: .developerDark)

        XCTAssertTrue(driver.started)
        await expectState(.recording)

        // Clip buffering starts with the settings-driven config.
        XCTAssertTrue(driver.isBuffering)
        let defaults = CaptureSettings()
        XCTAssertEqual(driver.bufferingConfig, ClipBufferConfig(fps: defaults.gifFps, maxBufferSeconds: defaults.clipDurationPreClickSec))

        // Session is persisted immediately.
        let loaded = try store.loadSession(id: session.id)
        XCTAssertEqual(loaded.title, "First Session")
        XCTAssertEqual(loaded.theme, .developerDark)
        XCTAssertTrue(loaded.steps.isEmpty)

        // Gesture settings are applied to the driver at start (single owner).
        XCTAssertFalse(driver.appliedGestureSettings.isEmpty)

        // Snapshot stream delivers the recording state.
        let streamDelivered = await probe.waitUntilState(.recording)
        XCTAssertTrue(streamDelivered)
    }

    func testStartRecordingIsIdempotentWhileRecording() async throws {
        _ = try await startRecording(title: "One")
        let second = try await engine.startRecording(title: "Two")
        XCTAssertNil(second)
        let title = await currentSnapshot().currentSession?.title
        XCTAssertEqual(title, "One")
    }

    func testStopFlushesPendingTypingAndPersists() async throws {
        driver.focusedContextProvider = { RawEventFixtures.ctx(app: "Ghostty", bundleId: "com.mitchellh.ghostty") }
        _ = try await startRecording()

        // Drive the engine directly so the keystrokes are guaranteed to be in
        // the aggregator before stop (deterministic flush).
        for event in RawEventFixtures.typing("ls -la", at: clickPoint) {
            await engine.processEvent(event)
        }

        let stopped = await engine.stopRecording()
        let session = try XCTUnwrap(stopped)

        XCTAssertEqual(session.steps.count, 1)
        XCTAssertEqual(session.steps.first?.textBlob, "ls -la")
        XCTAssertEqual(session.steps.first?.actionDescription, "Run \"ls -la\" in Ghostty")
        XCTAssertNotNil(session.endedAt)
        await expectState(.idle)
        XCTAssertEqual(driver.stoppedCount, 0, "Driver monitors must survive stopRecording (F1)")

        // JSON reload is equal.
        let reloaded = try store.loadSession(id: session.id)
        XCTAssertEqual(reloaded.steps.count, 1)
        XCTAssertEqual(reloaded.endedAt, session.endedAt)
        XCTAssertEqual(reloaded.steps.first?.textBlob, "ls -la")
    }

    func testStopWithoutRecordingReturnsNil() async {
        let session = await engine.stopRecording()
        XCTAssertNil(session)
    }

    // MARK: - Click reduction

    func testClickEmitsStepWithSnapshotAndContext() async throws {
        driver.contextProvider = { _ in
            RawEventFixtures.ctx(app: "Safari", windowTitle: "GitHub", role: "AXButton", title: "Submit Order")
        }
        _ = try await startRecording()

        driver.emitClick(at: clickPoint)

        let waited = await expectSteps(1)
        let session = try XCTUnwrap(waited)
        let step = try XCTUnwrap(session.steps.first)

        XCTAssertEqual(step.index, 1)
        XCTAssertEqual(step.action, .click)
        XCTAssertEqual(step.actionDescription, "Click \"Submit Order\" in GitHub")
        XCTAssertEqual(step.assets.screenshot, "media/step_01.png")
        XCTAssertEqual(step.coordinates, ScreenCoordinates(x: 100, y: 100))
        XCTAssertEqual(driver.inspectedPoints, [clickPoint])
        XCTAssertEqual(driver.snapshotStepIndices, [1])

        // The micro-clip is patched onto the step by id with the legacy names.
        let patched = await waitForSession { $0?.steps.first?.assets.gif != nil }
        XCTAssertNotNil(patched, "Micro-clip should be patched onto step 1")
        XCTAssertEqual(patched?.steps.first?.assets.gif, "media/step_01.gif")
        XCTAssertEqual(patched?.steps.first?.assets.webm, "media/step_01.mp4")

        let reloaded = try store.loadSession(id: session.id)
        XCTAssertEqual(reloaded.steps.first?.assets.screenshot, "media/step_01.png")
    }

    func testDoubleClickMapsToDoubleClickAction() async throws {
        driver.contextProvider = { _ in RawEventFixtures.ctx(app: "Notes", windowTitle: "Draft", title: "Title") }
        _ = try await startRecording()

        driver.emitClick(at: clickPoint, clickCount: 2)

        let waited = await expectSteps(1)
        let session = try XCTUnwrap(waited)
        XCTAssertEqual(session.steps.first?.action, .doubleClick)
        XCTAssertEqual(session.steps.first?.actionDescription, "Double-click \"Title\" in Draft")
    }

    func testRightClickMapsToRightClickAction() async throws {
        driver.contextProvider = { _ in RawEventFixtures.ctx(app: "Finder", bundleId: "com.apple.finder", role: "AXMenuItem") }
        _ = try await startRecording()

        driver.emitClick(at: clickPoint, button: .right)

        let waited = await expectSteps(1)
        let session = try XCTUnwrap(waited)
        XCTAssertEqual(session.steps.first?.action, .rightClick)
    }

    // MARK: - Debounce

    func testRapidClicksWithin200msAreDropped() async throws {
        driver.contextProvider = { _ in RawEventFixtures.ctx() }
        _ = try await startRecording()
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

        // Close + fast: contact bounce inside the 6pt radius, suppressed and
        // holding the window.
        driver.emitClick(at: Point2D(x: 10, y: 10), timestamp: start)
        driver.emitClick(at: Point2D(x: 12, y: 11), timestamp: start.addingTimeInterval(0.1))

        _ = await expectSteps(1)
        // Give the second event time to (incorrectly) land before asserting.
        try? await Task.sleep(nanoseconds: 80_000_000)
        let count = await currentSnapshot().stepCount
        XCTAssertEqual(count, 1)
        XCTAssertEqual(driver.snapshotStepIndices, [1])
    }

    func testFarFastRelocationIsDistinctNotBounce() async throws {
        driver.contextProvider = { _ in RawEventFixtures.ctx() }
        _ = try await startRecording()
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

        // 14pt in 100ms: a fast relocation across the 6pt radius is a
        // distinct click even though it lands inside the time window.
        driver.emitClick(at: Point2D(x: 10, y: 10), timestamp: start)
        driver.emitClick(at: Point2D(x: 20, y: 20), timestamp: start.addingTimeInterval(0.1))

        let waited = await expectSteps(2)
        let session = try XCTUnwrap(waited)
        XCTAssertEqual(session.steps.map(\.index), [1, 2])
    }

    func testOSDoubleClickIsAcceptedAsDouble() async throws {
        driver.contextProvider = { _ in RawEventFixtures.ctx() }
        _ = try await startRecording()
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

        driver.emitClick(at: Point2D(x: 10, y: 10), clickCount: 1, timestamp: start)
        driver.emitClick(at: Point2D(x: 10, y: 10), clickCount: 2, timestamp: start.addingTimeInterval(0.25))

        let waited = await expectSteps(2)
        let session = try XCTUnwrap(waited)
        // The second press surfaces as the double — not suppressed as
        // bounce, not mapped to a second single.
        XCTAssertEqual(session.steps.map(\.action), [.click, .doubleClick])
    }

    func testClicksAfterIntervalAreAccepted() async throws {
        driver.contextProvider = { _ in RawEventFixtures.ctx() }
        _ = try await startRecording()
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

        driver.emitClick(at: Point2D(x: 10, y: 10), timestamp: start)
        driver.emitClick(at: Point2D(x: 20, y: 20), timestamp: start.addingTimeInterval(0.25))

        let waited = await expectSteps(2)
        let session = try XCTUnwrap(waited)
        XCTAssertEqual(session.steps.map(\.index), [1, 2])
        XCTAssertEqual(driver.snapshotStepIndices, [1, 2])
    }

    // MARK: - Typing aggregation (headless)

    func testTypingBatchCoalescesIntoOneStepAfterDebounce() async throws {
        driver.focusedContextProvider = { RawEventFixtures.ctx(app: "Notes", windowTitle: "Draft", role: "AXTextField") }
        _ = try await startRecording()

        for event in RawEventFixtures.typing("hello", at: clickPoint) {
            driver.emit(event)
        }

        let waited = await expectSteps(1)
        let session = try XCTUnwrap(waited)
        let step = try XCTUnwrap(session.steps.first)

        XCTAssertEqual(step.textBlob, "hello")
        XCTAssertEqual(step.action, .typing)
        // Typing descriptions name the application (legacy parity), not the window.
        XCTAssertEqual(step.actionDescription, "Type \"hello\" in Notes")
        XCTAssertEqual(step.assets.screenshot, "media/step_01.png")
        XCTAssertEqual(driver.snapshotStepIndices, [1])
    }

    func testReturnFinalizesTerminalCommandAsWriteCode() async throws {
        driver.focusedContextProvider = { RawEventFixtures.ctx(app: "Ghostty", bundleId: "com.mitchellh.ghostty") }
        _ = try await startRecording()

        for event in RawEventFixtures.typing("git status", at: clickPoint) {
            driver.emit(event)
        }
        driver.emitKey("Return", code: 36)

        let waited = await expectSteps(1)
        let session = try XCTUnwrap(waited)
        let step = try XCTUnwrap(session.steps.first)

        XCTAssertEqual(step.actionDescription, "Run \"git status\" in Ghostty")
        XCTAssertEqual(step.action, .writeCode)
        XCTAssertEqual(step.codeLanguage, "bash")
        XCTAssertEqual(step.elementRole, "AXTerminal")
        XCTAssertTrue(step.isCode)

        // Fast-forward GIF patch.
        let patched = await waitForSession { $0?.steps.first?.assets.gif != nil }
        XCTAssertEqual(patched?.steps.first?.assets.gif, "media/step_01.gif")
    }

    func testControlCProducesInterruptStep() async throws {
        driver.focusedContextProvider = { RawEventFixtures.ctx(app: "Ghostty", bundleId: "com.mitchellh.ghostty") }
        _ = try await startRecording()

        for event in RawEventFixtures.typing("npm x", at: clickPoint) {
            driver.emit(event)
        }
        driver.emitKey("Backspace", code: 51)
        driver.emitKey("c", code: 8, modifiers: [.control])

        let waited = await expectSteps(1)
        let session = try XCTUnwrap(waited)
        XCTAssertEqual(session.steps.first?.textBlob, "npm  ^C")
        XCTAssertEqual(session.steps.first?.action, .writeCode)
    }

    func testBackspaceEditsBuffer() async throws {
        driver.focusedContextProvider = { RawEventFixtures.ctx(app: "Notes", windowTitle: "Draft") }
        _ = try await startRecording()

        for event in RawEventFixtures.typing("abc", at: clickPoint) {
            driver.emit(event)
        }
        driver.emitKey("Backspace", code: 51)
        driver.emitKey("Return", code: 36)

        let waited = await expectSteps(1)
        let session = try XCTUnwrap(waited)
        XCTAssertEqual(session.steps.first?.textBlob, "ab")
    }

    func testTabEmitsDiscreteKeyPressStepAndFlushesPendingTyping() async throws {
        driver.focusedContextProvider = { RawEventFixtures.ctx(app: "Ghostty", bundleId: "com.mitchellh.ghostty") }
        _ = try await startRecording()

        for event in RawEventFixtures.typing("ls", at: clickPoint) {
            driver.emit(event)
        }
        driver.emitKey("Tab", code: 48)
        driver.emitKey("Return", code: 36)

        let waited = await expectSteps(2)
        let session = try XCTUnwrap(waited)

        // Phase 2 (T3): the pending command is flushed *before* the Tab step.
        XCTAssertEqual(session.steps.first?.action, .writeCode)
        XCTAssertEqual(session.steps.first?.textBlob, "ls")

        let tabStep = try XCTUnwrap(session.steps.last)
        XCTAssertEqual(tabStep.action, .keyPress)
        XCTAssertEqual(tabStep.actionDescription, "Press Tab in Ghostty")
        XCTAssertNil(tabStep.hotkeyCombo, "Plain navigation keys carry no modifier combo")
    }

    func testClickFlushesPendingTypingFirst() async throws {
        driver.focusedContextProvider = { RawEventFixtures.ctx(app: "Ghostty", bundleId: "com.mitchellh.ghostty") }
        driver.contextProvider = { _ in RawEventFixtures.ctx(app: "Safari", title: "Link") }
        _ = try await startRecording()

        for event in RawEventFixtures.typing("git status", at: clickPoint) {
            driver.emit(event)
        }
        // Click immediately (before the 1 s debounce would fire).
        driver.emitClick(at: Point2D(x: 500, y: 500), timestamp: Date(timeIntervalSinceReferenceDate: 900_000_000))

        let waited = await expectSteps(2)
        let session = try XCTUnwrap(waited)
        // Order guarantee: the typing step lands before the click step.
        XCTAssertEqual(session.steps.first?.action, .writeCode)
        XCTAssertEqual(session.steps.first?.textBlob, "git status")
        XCTAssertEqual(session.steps.last?.action, .click)
        XCTAssertEqual(session.steps.map(\.index), [1, 2])
    }

    // MARK: - Gestures & hotkey (F1/F2/F3 regressions)

    func testHotkeyTogglesRecordingWhenIdleAndRecording() async throws {
        let initial = await currentState()
        XCTAssertEqual(initial, .idle)

        driver.emitHotkey("⌥Space")
        await expectState(.recording)

        // HotkeySettings-style string (with a space) matches too.
        driver.emitHotkey("⌥ Space")
        await expectState(.idle)

        // F1 regression: the hotkey still works after a stop — no manual menu
        // start needed, and the driver was never taken down.
        driver.emitHotkey("⌥Space")
        await expectState(.recording)
        XCTAssertEqual(driver.stoppedCount, 0)
    }

    func testGesturePauseResumeWhilePausedKeepsEventsFlowing() async throws {
        driver.contextProvider = { _ in RawEventFixtures.ctx() }
        _ = try await startRecording()

        driver.emitGesture(name: "Mouse Shake 🔀 (620 px/s)", action: .pauseResume)
        await expectState(.paused)
        XCTAssertTrue(driver.paused)
        let pauseNotice = await currentSnapshot().lastGestureNotice
        XCTAssertEqual(pauseNotice, "⏸️ Mouse Shake 🔀 (620 px/s) → Paused")

        // Clicks while paused are dropped, but the stream keeps flowing.
        driver.emitClick(at: clickPoint)
        try? await Task.sleep(nanoseconds: 80_000_000)
        let pausedCount = await currentSnapshot().stepCount
        XCTAssertEqual(pausedCount, 0)

        driver.emitGesture(name: "Mouse Shake 🔀 (620 px/s)", action: .pauseResume)
        await expectState(.recording)
        XCTAssertFalse(driver.paused)
        let resumeNotice = await currentSnapshot().lastGestureNotice
        XCTAssertEqual(resumeNotice, "▶️ Mouse Shake 🔀 (620 px/s) → Resumed")

        driver.emitClick(at: clickPoint)
        _ = await expectSteps(1)
    }

    func testGestureNoticeDismissesAfterConfiguredDuration() async throws {
        _ = try await startRecording()

        driver.emitGesture(name: "Middle-Click 🖱️", action: .addCheckpoint)

        try await waitFor { await self.currentSnapshot().lastGestureNotice != nil }
        // Walk the (test) clock past the 2.5 s notice duration.
        clock.advance(by: 2.6)
        try await waitFor { await self.currentSnapshot().lastGestureNotice == nil }
    }

    func testGestureStopAndReviewInvokesCallback() async throws {
        _ = try await startRecording()

        let expectation = expectation(description: "Review callback fires")
        let received = SessionBox()
        engine.onSessionReadyForReview = { session in
            received.session = session
            expectation.fulfill()
        }

        driver.emitGesture(name: "Bottom-Right Corner ↘️", action: .stopAndReview)

        await fulfillment(of: [expectation], timeout: 2.0)
        await expectState(.idle)
        XCTAssertNotNil(received.session?.endedAt)
        let notice = await currentSnapshot().lastGestureNotice
        XCTAssertEqual(notice, "🛑 Bottom-Right Corner ↘️ → Stopping & Reviewing")
    }

    func testGestureDiscardAndCheckpoint() async throws {
        driver.contextProvider = { _ in RawEventFixtures.ctx(app: "Safari", title: "Item") }
        _ = try await startRecording()

        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        driver.emitClick(at: Point2D(x: 10, y: 10), timestamp: start)
        _ = await expectSteps(1)

        driver.emitGesture(name: "Double Right-Click ⚡️", action: .discardLastStep)
        _ = await expectSteps(0)

        driver.emitClick(at: Point2D(x: 20, y: 20), timestamp: start.addingTimeInterval(0.3))
        _ = await expectSteps(1)

        driver.emitGesture(name: "Middle-Click 🖱️", action: .addCheckpoint)
        let marked = await waitForSession { $0?.steps.last?.userNotes?.contains("⭐") == true }
        XCTAssertNotNil(marked)
        XCTAssertEqual(marked?.steps.last?.userNotes, "⭐ Key Milestone / Checkpoint")
    }

    func testGestureCaptureSnapshotAddsManualStep() async throws {
        driver.contextProvider = { _ in RawEventFixtures.ctx(app: "Safari", title: "Grabbed") }
        _ = try await startRecording()

        driver.emitGesture(name: "Long Press (0.8s) ⏱️", action: .captureSnapshot, location: Point2D(x: 77, y: 88))

        let waited = await expectSteps(1)
        let session = try XCTUnwrap(waited)
        XCTAssertEqual(session.steps.first?.action, .manual)
        XCTAssertEqual(session.steps.first?.coordinates, ScreenCoordinates(x: 77, y: 88))
        let notice = await currentSnapshot().lastGestureNotice
        XCTAssertEqual(notice, "📸 Long Press (0.8s) ⏱️ → Captured Snapshot")
    }

    func testGestureSettingsFlowToDriver() async throws {
        _ = try await startRecording()

        var custom = GestureSettings()
        custom.shakeAction = .captureSnapshot
        await engine.applyGestureSettings(custom)

        XCTAssertEqual(driver.appliedGestureSettings.last?.shakeAction, .captureSnapshot)
    }

    func testGesturesWhileIdleAreSurfacedButInactive() async throws {
        let initial = await currentState()
        XCTAssertEqual(initial, .idle)

        driver.emitGesture(name: "Mouse Shake 🔀", action: .pauseResume, location: Point2D(x: 5, y: 5))

        try await waitFor { await self.currentSnapshot().lastGestureEvent != nil }
        let snapshot = await currentSnapshot()
        XCTAssertEqual(snapshot.lastGestureEvent?.name, "Mouse Shake 🔀")
        XCTAssertNil(snapshot.lastGestureNotice, "Idle gestures must not produce HUD notices or actions")
        XCTAssertEqual(snapshot.state, .idle)
    }

    // MARK: - Session operations

    func testDiscardLastStep() async throws {
        driver.contextProvider = { _ in RawEventFixtures.ctx() }
        _ = try await startRecording()
        driver.emitClick(at: clickPoint)
        let waited = await expectSteps(1)
        let session = try XCTUnwrap(waited)

        await engine.discardLastStep()
        _ = await expectSteps(0)

        let reloaded = try store.loadSession(id: session.id)
        XCTAssertTrue(reloaded.steps.isEmpty)
    }

    func testMarkLastStepCheckpointWritesStar() async throws {
        driver.contextProvider = { _ in RawEventFixtures.ctx() }
        _ = try await startRecording()
        driver.emitClick(at: clickPoint)
        let waited = await expectSteps(1)
        let session = try XCTUnwrap(waited)

        await engine.markLastStepAsCheckpoint()

        let reloaded = try store.loadSession(id: session.id)
        XCTAssertEqual(reloaded.steps.first?.userNotes, "⭐ Key Milestone / Checkpoint")

        // Idempotent: an existing star is not duplicated.
        await engine.markLastStepAsCheckpoint()
        let reloadedAgain = try store.loadSession(id: session.id)
        XCTAssertEqual(reloadedAgain.steps.first?.userNotes, "⭐ Key Milestone / Checkpoint")
    }

    func testAddManualStepOnlyWhileRecording() async throws {
        await engine.addManualStep(title: "Should be dropped")
        try? await Task.sleep(nanoseconds: 40_000_000)
        let idleCount = await currentSnapshot().stepCount
        XCTAssertEqual(idleCount, 0)

        _ = try await startRecording()
        await engine.addManualStep(title: "Deploy to production", notes: "Coordinate with SRE")

        let waited = await expectSteps(1)
        let session = try XCTUnwrap(waited)
        XCTAssertEqual(session.steps.first?.action, .manual)
        XCTAssertEqual(session.steps.first?.appName, "Manual Action")
        XCTAssertEqual(session.steps.first?.actionDescription, "Deploy to production")
        XCTAssertEqual(session.steps.first?.userNotes, "Coordinate with SRE")
    }

    func testCaptureInstantSnapshotCreatesStep() async throws {
        driver.contextProvider = { _ in
            RawEventFixtures.ctx(app: "System Settings", windowTitle: "Privacy", role: "AXButton", title: "Advanced...")
        }
        _ = try await startRecording()

        await engine.captureInstantSnapshot(at: Point2D(x: 42, y: 24))

        let waited = await expectSteps(1)
        let session = try XCTUnwrap(waited)
        let step = try XCTUnwrap(session.steps.first)
        XCTAssertEqual(step.action, .manual)
        XCTAssertEqual(step.actionDescription, "Perform step in \"Advanced...\" in Privacy")
        XCTAssertEqual(step.assets.screenshot, "media/step_01.png")
    }

    // MARK: - Persistence

    func testSessionSurvivesStoreRoundTrip() async throws {
        driver.focusedContextProvider = { RawEventFixtures.ctx(app: "Ghostty", bundleId: "com.mitchellh.ghostty") }
        driver.contextProvider = { _ in RawEventFixtures.ctx(app: "Safari", windowTitle: "GitHub", role: "AXButton", title: "Merge pull request") }
        let session = try await startRecording(title: "PR Merge Procedure", theme: .enterpriseSop)

        driver.emitClick(at: clickPoint, timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000))
        _ = await expectSteps(1)

        for event in RawEventFixtures.typing("git push", at: clickPoint) {
            driver.emit(event)
        }
        driver.emitKey("Return", code: 36)
        _ = await expectSteps(2)

        let stopped = await engine.stopRecording()
        let ended = try XCTUnwrap(stopped)
        XCTAssertEqual(ended.id, session.id)

        let reloaded = try store.loadSession(id: session.id)
        XCTAssertEqual(reloaded.title, "PR Merge Procedure")
        XCTAssertEqual(reloaded.theme, .enterpriseSop)
        XCTAssertEqual(reloaded.steps.count, 2)
        XCTAssertEqual(reloaded.steps.map(\.index), [1, 2])
        XCTAssertEqual(reloaded.steps.map(\.actionDescription), ended.steps.map(\.actionDescription))
        XCTAssertEqual(reloaded.steps[0].assets.screenshot, "media/step_01.png")
        XCTAssertEqual(reloaded.endedAt, ended.endedAt)
    }

    // MARK: - Static-only mode

    func testStaticOnlySessionNeverStartsClipBuffering() async throws {
        driver.contextProvider = { _ in RawEventFixtures.ctx() }
        _ = try await startRecording(mediaMode: .staticOnly)

        XCTAssertFalse(driver.isBuffering)
        XCTAssertNil(driver.bufferingConfig)

        driver.emitClick(at: clickPoint)
        let waited = await expectSteps(1)
        let session = try XCTUnwrap(waited)

        XCTAssertEqual(session.mediaMode, .staticOnly)
        XCTAssertEqual(session.steps.first?.assets.screenshot, "media/step_01.png")
        XCTAssertNil(session.steps.first?.assets.gif)
        XCTAssertTrue(driver.clipRequests.isEmpty, "Static-only sessions must never request micro-clips")
    }

    func testAnimatedOnlySessionStartsClipBuffering() async throws {
        _ = try await startRecording(mediaMode: .animatedOnly)
        XCTAssertTrue(driver.isBuffering)
    }

    // MARK: - Reserved event kinds

    func testPageNavigationRemainsReserved() async throws {
        _ = try await startRecording()

        // Phase 4 owns page navigation; Phase 2 handles the other reserved kinds.
        driver.emit(RawInputEvent(kind: .pageNavigation(url: "https://example.com", title: nil)))

        try? await Task.sleep(nanoseconds: 80_000_000)
        let count = await currentSnapshot().stepCount
        XCTAssertEqual(count, 0)
        await expectState(.recording)
    }

    // MARK: - Snapshot stream

    func testSnapshotStreamDeliversEveryMutationAndSeedsCurrentState() async throws {
        let freshDriver = MockCaptureDriver()
        let freshEngine = RecorderWorkflowEngine(driver: freshDriver, store: store, time: clock)
        try await freshEngine.start()
        let freshProbe = SnapshotProbe()
        await freshProbe.attach(to: freshEngine)

        // Seeded with the current (idle) snapshot on subscription.
        let seeded = await freshProbe.waitUntil { $0?.state == .idle }
        XCTAssertTrue(seeded)

        try await freshEngine.startRecording()
        let delivered = await freshProbe.waitUntilState(.recording)
        XCTAssertTrue(delivered)

        let session = try XCTUnwrap(freshProbe.last?.currentSession)
        await freshEngine.addManualStep(title: "Note")
        let stepDelivered = await freshProbe.waitForStepCount(1)
        XCTAssertTrue(stepDelivered)
        XCTAssertEqual(freshProbe.last?.currentSession?.id, session.id)

        freshProbe.cancel()
        await freshEngine.shutdown()
    }

    func testShutdownFinishesTheStream() async throws {
        let freshDriver = MockCaptureDriver()
        let freshEngine = RecorderWorkflowEngine(driver: freshDriver, store: store, time: clock)
        try await freshEngine.start()

        let stream = await freshEngine.snapshotStream()
        await freshEngine.shutdown()

        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next() // seeded snapshot
        let end = await iterator.next()
        XCTAssertNil(end)
        XCTAssertEqual(freshDriver.stoppedCount, 1)
    }

    // MARK: - Small async test utility

    private func waitFor(timeout: TimeInterval = 2.0, _ predicate: @escaping () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await predicate() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Condition not met within \(timeout)s")
    }
}

/// Thread-safe session box for callback assertions.
private final class SessionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _session: StepSession?

    var session: StepSession? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _session
        }
        set {
            lock.lock()
            _session = newValue
            lock.unlock()
        }
    }
}
