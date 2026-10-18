import Foundation
import FlowlineCaptureAPI
import FlowlineIR
import FlowlinePipeline

// MARK: - Clip and gesture orchestration (gesture half) (R/M1-03 reducer split; verbatim logic from RecorderWorkflowEngine)

extension RecorderWorkflowEngine {
    // MARK: - Gestures

    public func applyGestureSettings(_ settings: GestureSettings) async {
        if let sink = driver as? GestureSettingsSink {
            await sink.updateGestureSettings(settings)
        }
    }

    internal func handleGesture(name: String, action: GestureAction, location: Point2D) async {
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
                showGestureNotice("\(name) → Paused", event: event)
            } else if state == .paused {
                await resumeRecording()
                showGestureNotice("\(name) → Resumed", event: event)
            }

        case .stopAndReview:
            showGestureNotice("\(name) → Stopping & Reviewing", event: event)
            if let session = await stopRecording() {
                notifySessionReadyForReview(session)
            }

        case .discardLastStep:
            await discardLastStep()
            showGestureNotice("\(name) → Undone Last Step", event: event)

        case .addCheckpoint:
            await markLastStepAsCheckpoint()
            showGestureNotice("\(name) → Marked Checkpoint", event: event)

        case .captureSnapshot:
            await captureInstantSnapshot(at: location)
            showGestureNotice("\(name) → Captured Snapshot", event: event)
        }
    }

    internal func notifySessionReadyForReview(_ session: StepSession) {
        guard let handler = onSessionReadyForReview else { return }
        Task { @MainActor in
            handler(session)
        }
    }

    internal func showGestureNotice(_ message: String, event: RawGestureNotice) {
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
        if !notes.contains("[Checkpoint]") {
            notes = notes.isEmpty ? "Key Milestone / Checkpoint" : "[Checkpoint] \(notes)"
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
}
