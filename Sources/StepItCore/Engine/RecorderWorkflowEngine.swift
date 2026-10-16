import Foundation

/// Pure domain state machine of StepIt's recording pipeline.
///
/// - Serializes all event reduction and session mutation through the actor; no
///   locks and no `DispatchQueue` pyramids.
/// - Consumes a normalized `AsyncStream<RawInputEvent>` from a pluggable
///   `CaptureDriver`; never touches AppKit, AX, ScreenCaptureKit or Combine.
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

    private let driver: any CaptureDriver
    private let store: SessionStore
    private let time: TimeProvider
    private let config: EngineConfig
    private let aggregator: TypingBatchAggregator

    // MARK: - State

    private var state: RecordingState = .idle
    private var currentSession: StepSession?
    private var lastGestureNotice: String?
    private var lastGestureEvent: RawGestureNotice?
    private var gestureNoticeTask: Task<Void, Never>?
    private var debouncer: EventDebouncer
    private var consumptionTask: Task<Void, Never>?
    private var isFinalizing = false
    private var lastKnownLocation: Point2D?
    private var streamContinuations: [UUID: AsyncStream<RecorderSnapshot>.Continuation] = [:]

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

    // MARK: - Event reduction

    /// The reduction switch. Public so tests can drive the engine
    /// deterministically without a stream.
    public func processEvent(_ event: RawInputEvent) async {
        if let location = event.location {
            lastKnownLocation = location
        }

        switch event.kind {
        case .mouseClick(let button, let clickCount):
            let action = StepFactory.actionType(for: button, clickCount: clickCount)
            await handleAction(action: action, at: event.location ?? lastKnownLocation ?? .zero, timestamp: event.timestamp)

        case .keyStroke(let key, _, let modifiers):
            handleKeystroke(key: key, modifiers: modifiers, at: event.location ?? lastKnownLocation)

        case .hotkeyCombo(let combo):
            if matchesToggleHotkey(combo) {
                await toggleRecording()
            }

        case .userGesture(let name, let action):
            await handleGesture(name: name, action: action, location: event.location ?? .zero)

        case .mouseDrag, .appSwitch, .terminalCommand, .pageNavigation:
            // Reserved for later phases: declared in the IR, never emitted in
            // Phase 1, ignored by the engine.
            break
        }
    }

    private func handleKeystroke(key: String, modifiers: KeyModifiers, at location: Point2D?) {
        guard state == .recording, !isFinalizing else { return }
        let location = location ?? .zero

        if modifiers.contains(.control) && key.lowercased() == "c" {
            aggregator.handleControlC(at: location)
            return
        }

        switch key {
        case "Return", "\r", "\n":
            aggregator.handleReturn(at: location)
        case "Backspace", "\u{7f}":
            aggregator.handleBackspace(at: location)
        case "Tab":
            aggregator.append(char: "\t", at: location)
        default:
            guard let first = key.unicodeScalars.first, first.value >= 32, first.value != 127 else { return }
            aggregator.append(char: key, at: location)
        }
    }

    // MARK: - Click / action handling

    /// Parity with `handleAction`: flush the aggregator first (order
    /// guarantee), debounce, pull element context, capture a highlighted
    /// snapshot, append + persist + emit, then collect the micro-clip and patch
    /// assets by step id.
    private func handleAction(action: ActionType, at point: Point2D, timestamp: Date) async {
        // Flush any pending typed text/commands before recording the subsequent action
        if aggregator.hasPendingText, let batch = await aggregator.flushPending() {
            await handleTypingBatch(batch)
        }

        guard state == .recording, !isFinalizing else { return }
        guard debouncer.shouldAccept(at: timestamp) else { return }
        guard var session = currentSession else { return }

        let nextIndex = session.steps.count + 1

        // 1. Accessibility element inspection (fallback: .unknown placeholder)
        let context = await driver.inspectElement(at: point) ?? .unknown

        // 2. High-res snapshot capture with highlight
        let snapshot = await driver.captureSnapshot(highlightAt: point, stepIndex: nextIndex)

        // Post-await re-check: drop the step if the recording already stopped.
        guard state == .recording, !isFinalizing, let freshSession = currentSession else { return }
        session = freshSession

        var assets = MediaAssets()
        let filenameBase = String(format: "step_%02d", nextIndex)

        if let snapshot = snapshot, driver.capabilities.snapshots {
            let pngName = "\(filenameBase).png"
            if let relPath = try? store.saveMedia(data: snapshot.pngData, sessionID: session.id, filename: pngName) {
                assets.screenshot = relPath
            }
        }

        let step = StepFactory.makeClickStep(
            index: nextIndex,
            timestamp: timestamp,
            action: action,
            location: point,
            context: context,
            assets: assets
        )

        session.steps.append(step)
        currentSession = session
        try? store.saveSession(session)
        emitSnapshot()

        // 3. Capture animated micro-clip if hybrid or animated
        if session.mediaMode != .staticOnly, driver.capabilities.microClips {
            if let clip = await driver.captureMicroClip(around: point, postDuration: config.clickClipPostDuration) {
                patchAssets(stepID: step.id, gif: clip.gifData, video: clip.videoData)
            }
        }
    }

    // MARK: - Typing handling

    /// Parity with `handleTyping`: snapshot, build the typing step, append +
    /// persist + emit, then fast-forward GIF patch.
    private func handleTypingBatch(_ result: TypingBatchResult) async {
        guard state == .recording, !isFinalizing else { return }
        guard var session = currentSession else { return }

        let nextIndex = session.steps.count + 1
        let timestamp = time.now

        // 1. Snapshot capture of the editor / terminal
        let snapshot = await driver.captureSnapshot(highlightAt: result.location, stepIndex: nextIndex)

        guard state == .recording, !isFinalizing, let freshSession = currentSession else { return }
        session = freshSession

        var assets = MediaAssets()
        let filenameBase = String(format: "step_%02d", nextIndex)

        if let snapshot = snapshot, driver.capabilities.snapshots {
            let pngName = "\(filenameBase).png"
            if let relPath = try? store.saveMedia(data: snapshot.pngData, sessionID: session.id, filename: pngName) {
                assets.screenshot = relPath
            }
        }

        let step = StepFactory.makeTypingStep(
            index: nextIndex,
            timestamp: timestamp,
            result: result,
            assets: assets
        )

        session.steps.append(step)
        currentSession = session
        try? store.saveSession(session)
        emitSnapshot()

        // 2. Generate fast-forward GIF from the rolling buffer
        if session.mediaMode != .staticOnly, driver.capabilities.microClips {
            if let clip = await driver.captureMicroClip(around: result.location, postDuration: config.typingClipPostDuration),
               let gif = clip.gifData {
                patchAssets(stepID: step.id, gif: gif, video: nil)
            }
        }
    }

    /// Patches a step's assets (by id) once a micro-clip resolves, with the
    /// legacy `step_%02d.gif` / `step_%02d.mp4` naming.
    private func patchAssets(stepID: String, gif: Data?, video: Data?) {
        guard var session = currentSession,
              let index = session.steps.firstIndex(where: { $0.id == stepID }) else { return }

        let filenameBase = String(format: "step_%02d", session.steps[index].index)
        var assets = session.steps[index].assets

        if let gif = gif {
            let gifName = "\(filenameBase).gif"
            if let relPath = try? store.saveMedia(data: gif, sessionID: session.id, filename: gifName) {
                assets.gif = relPath
            }
        }

        if let video = video {
            let mp4Name = "\(filenameBase).mp4"
            if let relPath = try? store.saveMedia(data: video, sessionID: session.id, filename: mp4Name) {
                assets.webm = relPath
            }
        }

        session.steps[index].assets = assets
        currentSession = session
        try? store.saveSession(session)
    }

    // MARK: - Session operations

    public func discardLastStep() async {
        guard var session = currentSession, !session.steps.isEmpty else { return }
        _ = session.steps.removeLast()
        currentSession = session
        try? store.saveSession(session)
        emitSnapshot()
    }

    public func markLastStepAsCheckpoint() async {
        guard var session = currentSession, !session.steps.isEmpty else { return }
        let lastIndex = session.steps.count - 1
        var notes = session.steps[lastIndex].userNotes ?? ""
        if !notes.contains("⭐") {
            notes = notes.isEmpty ? "⭐ Key Milestone / Checkpoint" : "⭐ [Checkpoint] \(notes)"
        }
        session.steps[lastIndex].userNotes = notes
        currentSession = session
        try? store.saveSession(session)
        emitSnapshot()
    }

    public func addManualStep(title: String, notes: String? = nil) async {
        guard state == .recording, !isFinalizing, var session = currentSession else { return }

        let step = StepFactory.makeManualStep(
            index: session.steps.count + 1,
            timestamp: time.now,
            title: title,
            notes: notes
        )

        session.steps.append(step)
        currentSession = session
        try? store.saveSession(session)
        emitSnapshot()
    }

    public func captureInstantSnapshot(at point: Point2D? = nil) async {
        let location = point ?? lastKnownLocation ?? .zero
        await handleAction(action: .manual, at: location, timestamp: time.now)
    }

    // MARK: - Gestures

    public func applyGestureSettings(_ settings: GestureSettings) async {
        if let sink = driver as? GestureSettingsSink {
            await sink.updateGestureSettings(settings)
        }
    }

    private func handleGesture(name: String, action: GestureAction, location: Point2D) async {
        // Presentation layers (Settings live-test) see every gesture; recording
        // actions only fire while a recording is active.
        let event = RawGestureNotice(name: name, action: action, location: location, timestamp: time.now)
        lastGestureEvent = event
        guard state != .idle else {
            emitSnapshot()
            return
        }

        switch action {
        case .none:
            break

        case .pauseResume:
            if state == .recording {
                await pauseRecording()
                showGestureNotice("⏸️ \(name) → Paused", event: event)
            } else if state == .paused {
                await resumeRecording()
                showGestureNotice("▶️ \(name) → Resumed", event: event)
            }

        case .stopAndReview:
            showGestureNotice("🛑 \(name) → Stopping & Reviewing", event: event)
            if let session = await stopRecording() {
                notifySessionReadyForReview(session)
            }

        case .discardLastStep:
            await discardLastStep()
            showGestureNotice("🗑️ \(name) → Undone Last Step", event: event)

        case .addCheckpoint:
            await markLastStepAsCheckpoint()
            showGestureNotice("⭐ \(name) → Marked Checkpoint", event: event)

        case .captureSnapshot:
            await captureInstantSnapshot(at: location)
            showGestureNotice("📸 \(name) → Captured Snapshot", event: event)
        }
    }

    private func notifySessionReadyForReview(_ session: StepSession) {
        guard let handler = onSessionReadyForReview else { return }
        Task { @MainActor in
            handler(session)
        }
    }

    private func showGestureNotice(_ message: String, event: RawGestureNotice) {
        lastGestureNotice = message
        lastGestureEvent = event
        emitSnapshot()

        gestureNoticeTask?.cancel()
        gestureNoticeTask = Task { [time, config] in
            do {
                try await time.sleep(for: config.gestureNoticeDuration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.lastGestureNotice = nil
            self.emitSnapshot()
        }
    }

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

    private func removeSnapshotStream(_ id: UUID) {
        streamContinuations.removeValue(forKey: id)
    }

    private func emitSnapshot() {
        let snapshot = currentSnapshot()
        for continuation in streamContinuations.values {
            continuation.yield(snapshot)
        }
    }

    // MARK: - Helpers

    private func matchesToggleHotkey(_ combo: String) -> Bool {
        Self.normalizeHotkey(combo) == Self.normalizeHotkey(config.toggleHotkeyCombo)
    }

    private static func normalizeHotkey(_ combo: String) -> String {
        combo.replacingOccurrences(of: " ", with: "").lowercased()
    }
}
