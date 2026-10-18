import Combine
import Foundation
import FlowlineCaptureAPI
import FlowlineEngine
import FlowlineIR

/// The only object the UI talks to.
///
/// - Owns the app's `RecorderWorkflowEngine` (driver + store) and mirrors the
///   engine's `RecorderSnapshot` stream into `@Published` state on the main
///   actor — the same shape SwiftUI/Combine consumers used pre-Phase-1.
/// - Forwards user intents (`start`, `pause`, `stop`, gestures, settings) to
///   the engine; never touches drivers directly.
///
/// R/M1-07: lives in `FlowlineFixtures` (importable by tests; kept out of
/// `FlowlineEngine` so the portable core stays Combine-free for the Rust port) and takes all
/// dependencies by injection — the driver arrives inside the engine, and the
/// review presentation arrives as a callback from the composition root.
/// There is no `shared` singleton: the composition root owns the one instance.
@MainActor
public final class WorkflowController: ObservableObject {

    // MARK: - Published state (1:1 with the old coordinator surface)

    @Published public private(set) var state: RecordingState = .idle
    @Published public private(set) var currentSession: StepSession?
    @Published public private(set) var stepCount: Int = 0
    @Published public private(set) var recordingDuration: TimeInterval = 0
    @Published public private(set) var lastGestureNotice: String?
    /// Full gesture notice (name + mapped action) for presentation layers that
    /// need more than the HUD string — e.g. the Settings live-test playground.
    @Published public private(set) var lastGestureEvent: RawGestureNotice?

    // MARK: - Dependencies

    private let engine: RecorderWorkflowEngine
    private var snapshotTask: Task<Void, Never>?
    private var durationTimer: Timer?
    private var isBootstrapped = false

    /// - Parameter engine: fully-wired recording engine (driver + store).
    /// - Parameter onReview: presentation of a finished session, provided by
    ///   the composition root (replaces the hardwired review-window lookup).
    public init(
        engine: RecorderWorkflowEngine,
        onReview: (@MainActor (StepSession) -> Void)? = nil
    ) {
        self.engine = engine

        // Fix F3: gesture "Stop & Review" now opens the review window through a
        // real callback instead of a dead notification.
        if let onReview {
            engine.onSessionReadyForReview = onReview
        }

        bindEngine()
    }

    // MARK: - Lifecycle

    /// Called once from `applicationDidFinishLaunching`. Starts the engine
    /// (driver + single consumption task) so the `⌥Space` hotkey works in
    /// **all** states (fix F1).
    public func bootstrap() async {
        guard !isBootstrapped else { return }
        isBootstrapped = true
        do {
            try await engine.start()
        } catch {
            NSLog("Flowline: capture driver failed to start: \(String(describing: error))")
        }
    }

    public func shutdown() async {
        snapshotTask?.cancel()
        snapshotTask = nil
        stopDurationTimer()
        await engine.shutdown()
    }

    // MARK: - Intents

    public func toggleRecording() async {
        await engine.toggleRecording()
    }

    public func startRecording(
        title: String = "Workflow Recording",
        theme: ThemeName = .modernMinimal,
        mediaMode: MediaMode = .hybrid
    ) async {
        _ = try? await engine.startRecording(title: title, theme: theme, mediaMode: mediaMode)
    }

    public func pauseRecording() async {
        await engine.pauseRecording()
    }

    public func resumeRecording() async {
        await engine.resumeRecording()
    }

    public func stopRecording() async -> StepSession? {
        await engine.stopRecording()
    }

    public func discardLastStep() async {
        await engine.discardLastStep()
    }

    public func markLastStepAsCheckpoint() async {
        await engine.markLastStepAsCheckpoint()
    }

    public func addManualStep(title: String, notes: String? = nil) async {
        await engine.addManualStep(title: title, notes: notes)
    }

    public func captureInstantSnapshot(at point: Point2D? = nil) async {
        await engine.captureInstantSnapshot(at: point)
    }

    /// The only mutation path for gesture settings (fix F2): forwards to the
    /// engine, which routes to the driver's gesture detector.
    public func applyGestureSettings(_ settings: GestureSettings) async {
        await engine.applyGestureSettings(settings)
    }

    /// Phase 2 (T9): full settings snapshot — privacy, hotkey capture and
    /// gesture policy — applied live so changes affect the next event.
    /// Projects to the narrow engine shape (R/M1-07).
    public func applySettings(_ settings: FlowlineSettings) async {
        await engine.applySettings(settings.engineSettings)
    }

    // MARK: - Engine binding

    private func bindEngine() {
        snapshotTask?.cancel()
        snapshotTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            let stream = await self.engine.snapshotStream()
            for await snapshot in stream {
                self.apply(snapshot)
            }
        }
    }

    private func apply(_ snapshot: RecorderSnapshot) {
        let wasIdle = state == .idle

        state = snapshot.state
        currentSession = snapshot.currentSession
        stepCount = snapshot.stepCount
        lastGestureNotice = snapshot.lastGestureNotice
        lastGestureEvent = snapshot.lastGestureEvent

        // A new recording restarts the timer from zero.
        if wasIdle && snapshot.state == .recording {
            recordingDuration = 0
        }

        if snapshot.state == .recording {
            startDurationTimer()
        } else {
            stopDurationTimer()
        }
    }

    // MARK: - Duration ticking (presentation cadence, ported 1:1)

    private func startDurationTimer() {
        guard durationTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.state == .recording else { return }
                self.recordingDuration += 1.0
            }
        }
        durationTimer = timer
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
}
