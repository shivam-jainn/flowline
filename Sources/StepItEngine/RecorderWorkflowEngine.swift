import Foundation
import StepItCaptureAPI
import StepItStorage
import StepItIR
import StepItPipeline
import StepItCore

/// Pure domain state machine of StepIt's recording pipeline.
///
/// - Serializes all event reduction and session mutation through the actor; no
///   locks and no `DispatchQueue` pyramids.
/// - Consumes a normalized `AsyncStream<RawInputEvent>` from a pluggable
///   `CaptureDriver`; never touches AppKit, AX, ScreenCaptureKit, Vision or
///   CoreImage.
/// - Callers: `WorkflowController` (app) and tests (with
///   `MockCaptureDriver` + `TestClock`).
///
/// ## Concurrency rules
/// - One consumption task per engine; handlers are serialized by the actor.
/// - Every mutation re-asserts `state == .recording` (plus `isFinalizing`)
///   **after** every `await`, so a click whose snapshot resolves after
///   `stopRecording()` is dropped instead of appended.
/// - `stopRecording()` flushes pending typing first, then sets `isFinalizing`
///   while it finalizes.
///
/// ## Phase 2 additions
/// - Discrete `.keyPress` steps for workflow shortcuts and navigation keys (T2/T3).
/// - Terminal `pwd` enrichment for `.writeCode` command steps (T4/T5).
/// - Pre-capture secure-field suppression + snapshot blackout (T6).
/// - Offline OCR redaction of captured screenshots (T7).
/// - `.mouseDrag` and `.appSwitch` reduction (T8).
public actor RecorderWorkflowEngine {

    // MARK: - Configuration

    public struct EngineConfig: Sendable {
        /// Minimum spacing between accepted click/action steps.
        public var minStepInterval: TimeInterval
        /// Inactivity window that finalizes a typing batch.
        public var typingDebounceInterval: TimeInterval
        /// How long a gesture notice stays visible in the HUD.
        public var gestureNoticeDuration: TimeInterval
        /// Hotkey combo that toggles recording (matched against
        /// `HotkeySettings.toggleRecording`, whitespace-insensitive).
        public var toggleHotkeyCombo: String
        /// Post-click window collected for micro-clips.
        public var clickClipPostDuration: TimeInterval
        /// Post-click window collected for typing fast-forward clips.
        public var typingClipPostDuration: TimeInterval

        public init(
            minStepInterval: TimeInterval = 0.20,
            typingDebounceInterval: TimeInterval = 1.0,
            gestureNoticeDuration: TimeInterval = 2.5,
            toggleHotkeyCombo: String = "⌥Space",
            clickClipPostDuration: TimeInterval = 1.2,
            typingClipPostDuration: TimeInterval = 0.6
        ) {
            self.minStepInterval = minStepInterval
            self.typingDebounceInterval = typingDebounceInterval
            self.gestureNoticeDuration = gestureNoticeDuration
            self.toggleHotkeyCombo = toggleHotkeyCombo
            self.clickClipPostDuration = clickClipPostDuration
            self.typingClipPostDuration = typingClipPostDuration
        }
    }

    // MARK: - Dependencies

    internal let driver: any CaptureDriver
    internal let store: SessionStore
    internal let time: TimeProvider
    internal let config: EngineConfig
    internal let aggregator: TypingBatchAggregator

    // MARK: - State

    internal var state: RecordingState = .idle
    internal var currentSession: StepSession?
    internal var lastGestureNotice: String?
    internal var lastGestureEvent: RawGestureNotice?
    internal var gestureNoticeTask: Task<Void, Never>?
    internal var debouncer: EventDebouncer
    internal var consumptionTask: Task<Void, Never>?
    internal var isFinalizing = false
    internal var lastKnownLocation: Point2D?
    internal var streamContinuations: [UUID: AsyncStream<RecorderSnapshot>.Continuation] = [:]

    // Phase 2 state — settings snapshot for the active recording.
    internal var privacySettings = PrivacySettings()
    internal var hotkeySettings = HotkeyCaptureSettings()
    internal var captureSettings = CaptureSettings()
    internal var recognizer = HotkeyRecognizer()
    internal var toggleCombo: String
    /// Latest frontmost app (seeded at recording start, updated by `.appSwitch`).
    internal var lastAppContext: RawElementContext?

    // Step-production gate: privacy passes (OCR, secure blackout) can suspend a
    // handler for hundreds of milliseconds, and the debounce path can deliver a
    // typing batch out-of-band. Serializing production keeps step indices,
    // media filenames and append order exact.
    internal var stepGateContinuations: [CheckedContinuation<Void, Never>] = []
    internal var isStepGateHeld = false

    /// Replaces the dead `StepItShowReviewWindow` notification (fix F3).
    private let reviewCallback = ReviewCallbackBox()
    public nonisolated var onSessionReadyForReview: (@MainActor (StepSession) -> Void)? {
        get { reviewCallback.handler }
        set { reviewCallback.handler = newValue }
    }

    private final class ReviewCallbackBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _handler: (@MainActor (StepSession) -> Void)?

        var handler: (@MainActor (StepSession) -> Void)? {
            get {
                lock.lock()
                defer { lock.unlock() }
                return _handler
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                _handler = newValue
            }
        }
    }

    // MARK: - Init

    public init(
        driver: any CaptureDriver,
        store: SessionStore,
        time: TimeProvider = SystemTimeProvider(),
        config: EngineConfig = EngineConfig()
    ) {
        self.driver = driver
        self.store = store
        self.time = time
        self.config = config
        self.toggleCombo = config.toggleHotkeyCombo
        self.debouncer = EventDebouncer(minInterval: config.minStepInterval)
        self.aggregator = TypingBatchAggregator(
            configuration: TypingBatchAggregator.Configuration(debounceInterval: config.typingDebounceInterval),
            contextProvider: { [driver] in
                await driver.inspectFocusedElement()
            }
        )

        self.aggregator.onBatchCompleted = { [weak self] result in
            Task { await self?.handleTypingBatch(result) }
        }
    }

    // MARK: - Lifecycle

    /// Binds the driver **once** (app bootstrap), spawns the single consumption
    /// task and emits the initial snapshot. Replaces the `EventMonitor.start()`
    /// side effect that used to live in `AppDelegate`.
    public func start() async throws {
        guard consumptionTask == nil else { return }
        try await driver.start()

        let driver = self.driver
        consumptionTask = Task { [weak self] in
            for await event in driver.eventStream {
                await self?.processEvent(event)
            }
        }

        emitSnapshot()
    }

    public func shutdown() async {
        await driver.stop()
        consumptionTask?.cancel()
        consumptionTask = nil
        gestureNoticeTask?.cancel()
        gestureNoticeTask = nil

        for continuation in streamContinuations.values {
            continuation.finish()
        }
        streamContinuations.removeAll()
    }

    // MARK: - Recording intents

    @discardableResult
    public func startRecording(
        title: String = "Workflow Recording",
        theme: ThemeName = .modernMinimal,
        mediaMode: MediaMode = .hybrid
    ) async throws -> StepSession? {
        guard state == .idle, !isFinalizing else { return nil }

        let session = StepSession(
            title: title,
            theme: theme,
            mediaMode: mediaMode,
            steps: []
        )

        currentSession = session
        state = .recording
        debouncer.reset()

        let settings = store.loadSettings()
        applyLocalSettings(settings)
        await applyHotkeyPolicyToDriver(settings)

        // Seed the app-switch baseline so the first real switch is detectable.
        lastAppContext = await driver.inspectFocusedElement()

        // Start micro-clip buffering if needed (parity: hybrid/animated only).
        if mediaMode != .staticOnly, driver.capabilities.microClips {
            await driver.startClipBuffering(config: ClipBufferConfig(
                fps: settings.capture.gifFps,
                maxBufferSeconds: settings.capture.clipDurationPreClickSec
            ))
        }

        // Sync gesture detector settings (single-owner routing, fix F2).
        await applyGestureSettings(settings.gestures)

        try? store.saveSession(session)
        emitSnapshot()
        return session
    }

    public func pauseRecording() async {
        guard state == .recording else { return }
        state = .paused
        await driver.pause()
        emitSnapshot()
    }

    public func resumeRecording() async {
        guard state == .paused else { return }
        state = .recording
        await driver.resume()
        emitSnapshot()
    }

    /// Parity with the pre-Phase-1 coordinator's stopRecording: flush pending typing
    /// into a final step, stop clip buffering, stamp `endedAt`, persist and
    /// emit. Driver monitors stay alive (fix F1).
    public func stopRecording() async -> StepSession? {
        guard state != .idle, var session = currentSession else { return nil }

        // Synchronously flush any pending keystrokes before finalizing
        // (through the aggregator's async flush API — never queue.sync).
        if aggregator.hasPendingText, let batch = await aggregator.flushPending() {
            await handleTypingBatch(batch)
        }

        isFinalizing = true
        await driver.stopClipBuffering()

        session = currentSession ?? session
        session.endedAt = time.now
        currentSession = session
        state = .idle
        isFinalizing = false

        try? store.saveSession(session)
        emitSnapshot()
        return session
    }

    public func toggleRecording() async {
        switch state {
        case .idle:
            _ = try? await startRecording()
        case .recording, .paused:
            _ = await stopRecording()
        }
    }


    // MARK: - Settings


    // MARK: - Session operations

    // MARK: - Snapshots

    public func currentSnapshot() -> RecorderSnapshot {
        RecorderSnapshot(
            state: state,
            currentSession: currentSession,
            stepCount: currentSession?.steps.count ?? 0,
            lastGestureNotice: lastGestureNotice,
            lastGestureEvent: lastGestureEvent
        )
    }

    /// The controller's subscription. Yields the current snapshot immediately
    /// on subscription, then every state/step/gesture mutation.
    public func snapshotStream() -> AsyncStream<RecorderSnapshot> {
        let id = UUID()
        var continuation: AsyncStream<RecorderSnapshot>.Continuation!
        let stream = AsyncStream<RecorderSnapshot>(bufferingPolicy: .unbounded) { cont in
            continuation = cont
            cont.onTermination = { [weak self] _ in
                Task { await self?.removeSnapshotStream(id) }
            }
        }
        streamContinuations[id] = continuation
        continuation.yield(currentSnapshot())
        return stream
    }

    internal func removeSnapshotStream(_ id: UUID) {
        streamContinuations.removeValue(forKey: id)
    }

    internal func emitSnapshot() {
        let snapshot = currentSnapshot()
        for continuation in streamContinuations.values {
            continuation.yield(snapshot)
        }
    }

}
