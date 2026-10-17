import Foundation

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

    // Phase 2 state — settings snapshot for the active recording.
    private var privacySettings = PrivacySettings()
    private var hotkeySettings = HotkeyCaptureSettings()
    private var captureSettings = CaptureSettings()
    private var recognizer = HotkeyRecognizer()
    private var toggleCombo: String
    /// Latest frontmost app (seeded at recording start, updated by `.appSwitch`).
    private var lastAppContext: RawElementContext?

    // Step-production gate: privacy passes (OCR, secure blackout) can suspend a
    // handler for hundreds of milliseconds, and the debounce path can deliver a
    // typing batch out-of-band. Serializing production keeps step indices,
    // media filenames and append order exact.
    private var stepGateContinuations: [CheckedContinuation<Void, Never>] = []
    private var isStepGateHeld = false

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

    // MARK: - Step-production gate

    /// Runs `body` with exclusive access to step production. Actor reentrancy
    /// plus long privacy passes would otherwise interleave producers; callers
    /// inside an already-gated body use the `produce*` variants directly.
    private func withStepGate<T>(_ body: () async -> T) async -> T {
        await acquireStepGate()
        defer { releaseStepGate() }
        return await body()
    }

    private func acquireStepGate() async {
        if isStepGateHeld {
            await withCheckedContinuation { stepGateContinuations.append($0) }
        } else {
            isStepGateHeld = true
        }
    }

    private func releaseStepGate() {
        if stepGateContinuations.isEmpty {
            isStepGateHeld = false
        } else {
            stepGateContinuations.removeFirst().resume()
        }
    }

    // MARK: - Settings

    /// Applies the full settings snapshot: privacy/hotkey policy locally, then
    /// the driver-owned facets (gestures + hotkey recognizer). Called by
    /// `WorkflowController` on save so changes take effect immediately (T9).
    public func applySettings(_ settings: StepItSettings) async {
        applyLocalSettings(settings)
        await applyGestureSettings(settings.gestures)
        await applyHotkeyPolicyToDriver(settings)
        emitSnapshot()
    }

    private func applyLocalSettings(_ settings: StepItSettings) {
        privacySettings = settings.privacy
        hotkeySettings = settings.hotkeyCapture
        captureSettings = settings.capture
        toggleCombo = settings.hotkeys.toggleRecording.isEmpty ? config.toggleHotkeyCombo : settings.hotkeys.toggleRecording
        recognizer.settings = settings.hotkeyCapture
        recognizer.toggleCombo = toggleCombo
        aggregator.privacySettings = settings.privacy
    }

    private func applyHotkeyPolicyToDriver(_ settings: StepItSettings) async {
        guard let sink = driver as? HotkeySettingsSink else { return }
        await sink.updateHotkeySettings(settings.hotkeyCapture, toggleCombo: toggleCombo)
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

        case .keyStroke(let key, let code, let modifiers):
            await handleKeystroke(key: key, code: code, modifiers: modifiers, at: event.location ?? lastKnownLocation)

        case .hotkeyCombo(let combo):
            if matchesToggleHotkey(combo) {
                await toggleRecording()
            }

        case .mouseDrag(let start, let end):
            await handleMouseDrag(start: start, end: end, timestamp: event.timestamp)

        case .appSwitch(let bundleId, let appName, let windowTitle):
            await handleAppSwitch(bundleId: bundleId, appName: appName, windowTitle: windowTitle)

        case .terminalCommand(let command, let workingDir, _):
            await handleTerminalCommand(command: command, workingDirectory: workingDir)

        case .userGesture(let name, let action):
            await handleGesture(name: name, action: action, location: event.location ?? .zero)

        case .pageNavigation:
            // Reserved for Phase 4; ignored by the engine.
            break
        }
    }

    /// Routes an IR keystroke through the shared `HotkeyRecognizer` policy so
    /// the engine and the macOS driver agree on every classification (T2).
    private func handleKeystroke(key: String, code: Int?, modifiers: KeyModifiers, at location: Point2D?) async {
        let decision = recognizer.evaluate(key: key, code: code, modifiers: modifiers)

        // The toggle must fire in every state (F1 parity with `.hotkeyCombo`).
        if case .toggleRecording = decision {
            await toggleRecording()
            return
        }

        guard state == .recording, !isFinalizing else { return }
        let location = location ?? .zero

        // ⌃C is the terminal SIGINT batch terminator (Phase 1 parity) and must
        // work even when modifier-shortcut capture is disabled.
        if modifiers.contains(.control), !modifiers.contains(.command),
           key.lowercased() == "c" {
            await aggregator.handleControlC(at: location)
            return
        }

        switch decision {
        case .toggleRecording:
            break

        case .systemConsumed, .ignored:
            return

        case .workflowShortcut(let chord):
            await handleKeyPressStep(chord, at: location)

        case .navigationKey(let chord):
            await handleKeyPressStep(chord, at: location)

        case .textInput(let key, _):
            await handleTextInput(key: key, at: location)
        }
    }

    /// Return / Backspace / printable characters feed the typing aggregator.
    /// Named keys never reach this path (navigation is classified above), which
    /// fixes the pre-Phase-2 hole where `"Escape"` was buffered as text.
    private func handleTextInput(key: String, at location: Point2D) async {
        switch key {
        case "Return", "\r", "\n":
            await aggregator.handleReturn(at: location)
        case "Backspace", "\u{7f}":
            await aggregator.handleBackspace(at: location)
        default:
            guard key.count == 1,
                  let first = key.unicodeScalars.first,
                  first.value >= 32, first.value != 127 else { return }
            await aggregator.append(char: key, at: location)
        }
    }

    // MARK: - Discrete key press steps (T3)

    private func handleKeyPressStep(_ chord: HotkeyChord, at location: Point2D) async {
        await withStepGate {
            await produceKeyPressStep(chord, at: location)
        }
    }

    private func produceKeyPressStep(_ chord: HotkeyChord, at location: Point2D) async {
        // Ordering guarantee (T3): a pending command must precede "Press ⌘S".
        if aggregator.hasPendingText, let batch = await aggregator.flushPending() {
            await produceTypingStep(batch)
        }

        guard state == .recording, !isFinalizing, var session = currentSession else { return }

        let nextIndex = session.steps.count + 1
        let timestamp = time.now
        let context = enriched(await driver.inspectFocusedElement() ?? .unknown)
        let media = await captureStepMedia(context: context, at: location, stepIndex: nextIndex, sessionID: session.id)

        // Post-await re-check: drop the step if the recording already stopped.
        guard state == .recording, !isFinalizing, let freshSession = currentSession else { return }
        session = freshSession

        let step = StepFactory.makeKeyPressStep(
            index: nextIndex,
            timestamp: timestamp,
            chord: chord,
            context: context,
            assets: media.assets,
            isRedacted: media.isRedacted ? true : nil
        )

        session.steps.append(step)
        currentSession = session
        try? store.saveSession(session)
        emitSnapshot()
    }

    // MARK: - Click / action handling

    /// Parity with `handleAction`: flush the aggregator first (order
    /// guarantee), debounce, pull element context, capture a highlighted
    /// snapshot, append + persist + emit, then collect the micro-clip and patch
    /// assets by step id.
    private func handleAction(action: ActionType, at point: Point2D, timestamp: Date) async {
        // The step gate covers context/media/privacy + append; the micro-clip
        // capture (up to ~1.5 s) runs after release so typing batches never
        // wait behind it.
        let produced = await withStepGate {
            await produceActionStep(action: action, at: point, timestamp: timestamp)
        }
        guard let produced = produced, produced.captureMicroClip else { return }
        guard driver.capabilities.microClips else { return }

        if let clip = await driver.captureMicroClip(around: point, postDuration: config.clickClipPostDuration) {
            patchAssets(stepID: produced.id, gif: clip.gifData, video: clip.videoData)
        }
    }

    private func produceActionStep(action: ActionType, at point: Point2D, timestamp: Date) async -> ProducedStep? {
        // Flush any pending typed text/commands before recording the subsequent action
        if aggregator.hasPendingText, let batch = await aggregator.flushPending() {
            await produceTypingStep(batch)
        }

        guard state == .recording, !isFinalizing else { return nil }
        guard debouncer.shouldAccept(at: timestamp) else { return nil }
        guard var session = currentSession else { return nil }

        let nextIndex = session.steps.count + 1

        // 1. Accessibility element inspection (fallback: .unknown placeholder)
        let context = enriched(await driver.inspectElement(at: point) ?? .unknown)

        // 2. High-res snapshot capture with highlight + privacy passes
        let media = await captureStepMedia(context: context, at: point, stepIndex: nextIndex, sessionID: session.id)

        // Post-await re-check: drop the step if the recording already stopped.
        guard state == .recording, !isFinalizing, let freshSession = currentSession else { return nil }
        session = freshSession

        let step = StepFactory.makeClickStep(
            index: nextIndex,
            timestamp: timestamp,
            action: action,
            location: point,
            context: context,
            assets: media.assets,
            isRedacted: media.isRedacted ? true : nil
        )

        session.steps.append(step)
        currentSession = session
        try? store.saveSession(session)
        emitSnapshot()

        return ProducedStep(
            id: step.id,
            captureMicroClip: session.mediaMode != .staticOnly && driver.capabilities.microClips
        )
    }

    // MARK: - Typing handling

    /// Parity with `handleTyping`: snapshot, build the typing step, append +
    /// persist + emit, then fast-forward GIF patch.
    ///
    /// Phase 2: terminal batches resolve the shell's `pwd` through the driver's
    /// `TerminalContextProviding` facet (T4/T5) and secure fields blackout the
    /// snapshot (T6).
    private func handleTypingBatch(_ result: TypingBatchResult) async {
        let produced = await withStepGate {
            await produceTypingStep(result)
        }
        guard let produced = produced, produced.captureMicroClip, driver.capabilities.microClips else { return }

        if let clip = await driver.captureMicroClip(around: result.location, postDuration: config.typingClipPostDuration),
           let gif = clip.gifData {
            patchAssets(stepID: produced.id, gif: gif, video: nil)
        }
    }

    /// Produces the typing step inside the gate. Returns the step id when a
    /// fast-forward clip should follow.
    @discardableResult
    private func produceTypingStep(_ result: TypingBatchResult) async -> ProducedStep? {
        guard state == .recording, !isFinalizing else { return nil }
        guard var session = currentSession else { return nil }

        let nextIndex = session.steps.count + 1
        let timestamp = time.now

        // 1. Terminal `pwd` resolution (never blocks non-terminal batches).
        var workingDirectory: String?
        if result.classification == .terminal {
            workingDirectory = await resolveWorkingDirectory(for: result.context)
        }

        // 2. Snapshot capture of the editor / terminal + privacy passes
        let media = await captureStepMedia(context: result.context, at: result.location, stepIndex: nextIndex, sessionID: session.id)

        guard state == .recording, !isFinalizing, let freshSession = currentSession else { return nil }
        session = freshSession

        let step = StepFactory.makeTypingStep(
            index: nextIndex,
            timestamp: timestamp,
            result: result,
            assets: media.assets,
            workingDirectory: workingDirectory,
            isRedacted: media.isRedacted ? true : nil
        )

        session.steps.append(step)
        currentSession = session
        try? store.saveSession(session)
        emitSnapshot()

        return ProducedStep(
            id: step.id,
            captureMicroClip: session.mediaMode != .staticOnly && driver.capabilities.microClips
        )
    }

    // MARK: - Terminal commands (T4/T5)

    private func resolveWorkingDirectory(for context: RawElementContext?) async -> String? {
        guard let provider = driver as? TerminalContextProviding else { return nil }
        return await provider.inspectTerminalWorkingDirectory(
            bundleId: context?.bundleIdentifier,
            pid: nil,
            windowTitle: context?.windowTitle
        )
    }

    private func handleTerminalCommand(command: String, workingDirectory: String?) async {
        await withStepGate {
            await produceTerminalCommandStep(command: command, workingDirectory: workingDirectory)
        }
    }

    private func produceTerminalCommandStep(command: String, workingDirectory: String?) async {
        if aggregator.hasPendingText, let batch = await aggregator.flushPending() {
            await produceTypingStep(batch)
        }

        guard state == .recording, !isFinalizing, var session = currentSession else { return }

        let nextIndex = session.steps.count + 1
        let context = enriched(await driver.inspectFocusedElement() ?? .unknown)
        var directory = workingDirectory
        if directory == nil {
            directory = await resolveWorkingDirectory(for: context)
        }
        let media = await captureStepMedia(context: context, at: lastKnownLocation ?? .zero, stepIndex: nextIndex, sessionID: session.id)

        guard state == .recording, !isFinalizing, let freshSession = currentSession else { return }
        session = freshSession

        let step = StepFactory.makeTerminalCommandStep(
            index: nextIndex,
            timestamp: time.now,
            command: command,
            workingDirectory: directory,
            context: context,
            assets: media.assets,
            isRedacted: media.isRedacted ? true : nil
        )

        session.steps.append(step)
        currentSession = session
        try? store.saveSession(session)
        emitSnapshot()
    }

    // MARK: - Drag & app-switch handling (T8)

    private func handleMouseDrag(start: Point2D, end: Point2D, timestamp: Date) async {
        await withStepGate {
            await produceDragStep(start: start, end: end, timestamp: timestamp)
        }
    }

    private func produceDragStep(start: Point2D, end: Point2D, timestamp: Date) async {
        if aggregator.hasPendingText, let batch = await aggregator.flushPending() {
            await produceTypingStep(batch)
        }

        guard state == .recording, !isFinalizing, var session = currentSession else { return }

        let nextIndex = session.steps.count + 1
        let context = enriched(await driver.inspectElement(at: end) ?? .unknown)
        let media = await captureStepMedia(context: context, at: end, stepIndex: nextIndex, sessionID: session.id)

        guard state == .recording, !isFinalizing, let freshSession = currentSession else { return }
        session = freshSession

        let step = StepFactory.makeDragStep(
            index: nextIndex,
            timestamp: timestamp,
            start: start,
            end: end,
            context: context,
            assets: media.assets,
            isRedacted: media.isRedacted ? true : nil
        )

        session.steps.append(step)
        currentSession = session
        try? store.saveSession(session)
        emitSnapshot()
    }

    private func handleAppSwitch(bundleId: String?, appName: String, windowTitle: String) async {
        let previous = lastAppContext
        lastAppContext = RawElementContext(appName: appName, bundleIdentifier: bundleId, windowTitle: windowTitle)

        guard state == .recording, !isFinalizing, captureSettings.recordAppSwitches else { return }
        guard appName != previous?.appName else { return }
        guard var session = currentSession else { return }

        let step = StepFactory.makeAppSwitchStep(
            index: session.steps.count + 1,
            timestamp: time.now,
            bundleId: bundleId,
            appName: appName,
            windowTitle: windowTitle
        )

        session.steps.append(step)
        currentSession = session
        try? store.saveSession(session)
        emitSnapshot()
    }

    // MARK: - Snapshot privacy pipeline (T6/T7)

    private struct StepMedia {
        var assets = MediaAssets()
        var isRedacted = false
    }

    /// Result of a gated step production — the id lets the post-gate micro-clip
    /// pass patch assets without holding the gate.
    private struct ProducedStep {
        var id: String
        var captureMicroClip: Bool
    }

    /// Capture → secure-field blackout → offline OCR redaction → persist.
    /// Shared by every step kind so privacy runs identically everywhere.
    private func captureStepMedia(
        context: RawElementContext?,
        at location: Point2D,
        stepIndex: Int,
        sessionID: String
    ) async -> StepMedia {
        var media = StepMedia()
        guard driver.capabilities.snapshots else { return media }
        guard var snapshot = await driver.captureSnapshot(highlightAt: location, stepIndex: stepIndex) else {
            return media
        }

        // 1. Pre-capture privacy (T6): blackout the secure field before the
        //    image is ever persisted.
        if context?.isSecure == true, let region = context?.boundingBox ?? context?.windowBounds,
           let obscuring = driver as? VisualObscuring {
            snapshot = await obscuring.obscureSensitiveRegions(in: snapshot, regions: [region], anchor: location)
        }

        // 2. Post-capture privacy (T7): offline OCR → sensitive regions → blur.
        if privacySettings.enableOfflineOCRRedaction, let redactor = driver as? VisualRedactionProviding {
            let preRedaction = snapshot
            let outcome = await redactor.redactSensitiveContent(in: snapshot, settings: privacySettings)
            if outcome.isRedacted {
                snapshot = outcome.snapshot
                media.isRedacted = true
                // Non-destructive redaction: keep the unblurred source so the
                // Review Window can toggle it.
                let originalName = String(format: "step_%02d.original.png", stepIndex)
                media.assets.screenshotOriginal = try? store.saveMedia(
                    data: preRedaction.pngData,
                    sessionID: sessionID,
                    filename: originalName
                )
            }
        }

        // 3. Persist the (possibly redacted) frame.
        let pngName = String(format: "step_%02d.png", stepIndex)
        if let relPath = try? store.saveMedia(data: snapshot.pngData, sessionID: sessionID, filename: pngName) {
            media.assets.screenshot = relPath
        }
        return media
    }

    /// Fills missing app context from the last observed app switch.
    private func enriched(_ context: RawElementContext) -> RawElementContext {
        var context = context
        if context.appName.isEmpty || context.appName == RawElementContext.unknown.appName,
           let last = lastAppContext {
            context.appName = last.appName
            context.bundleIdentifier = context.bundleIdentifier ?? last.bundleIdentifier
            if context.windowTitle.isEmpty {
                context.windowTitle = last.windowTitle
            }
        }
        return context
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
        Self.normalizeHotkey(combo) == Self.normalizeHotkey(toggleCombo)
            || Self.normalizeHotkey(combo) == Self.normalizeHotkey(config.toggleHotkeyCombo)
    }

    private static func normalizeHotkey(_ combo: String) -> String {
        combo.replacingOccurrences(of: " ", with: "").lowercased()
    }
}
