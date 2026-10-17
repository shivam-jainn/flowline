import Foundation
import StepItCaptureAPI
import StepItIR
import StepItPipeline
import StepItCore

// MARK: - Step-production gate (R/M1-03 reducer split; verbatim logic from RecorderWorkflowEngine)

extension RecorderWorkflowEngine {
    // MARK: - Step-production gate

    /// Runs `body` with exclusive access to step production. Actor reentrancy
    /// plus long privacy passes would otherwise interleave producers; callers
    /// inside an already-gated body use the `produce*` variants directly.
    internal func withStepGate<T>(_ body: () async -> T) async -> T {
        await acquireStepGate()
        defer { releaseStepGate() }
        return await body()
    }

    internal func acquireStepGate() async {
        if isStepGateHeld {
            await withCheckedContinuation { stepGateContinuations.append($0) }
        } else {
            isStepGateHeld = true
        }
    }

    internal func releaseStepGate() {
        if stepGateContinuations.isEmpty {
            isStepGateHeld = false
        } else {
            stepGateContinuations.removeFirst().resume()
        }
    }

    // MARK: - Snapshot privacy pipeline (T6/T7)

    internal struct StepMedia {
        var assets = MediaAssets()
        var isRedacted = false
    }

    /// Result of a gated step production — the id lets the post-gate micro-clip
    /// pass patch assets without holding the gate.
    internal struct ProducedStep {
        var id: String
        var captureMicroClip: Bool
    }
    internal func produceKeyPressStep(_ chord: HotkeyChord, at location: Point2D) async {
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

    internal func produceActionStep(action: ActionType, at point: Point2D, timestamp: Date) async -> ProducedStep? {
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

    internal func produceTypingStep(_ result: TypingBatchResult) async -> ProducedStep? {
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

    internal func produceDragStep(start: Point2D, end: Point2D, timestamp: Date) async {
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

    internal func produceTerminalCommandStep(command: String, workingDirectory: String?) async {
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
}
