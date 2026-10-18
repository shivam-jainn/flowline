import Foundation
import FlowlineCaptureAPI
import FlowlineIR
import FlowlinePipeline

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
        // Delayed commit: provisional emit immediately, confirm at +400 ms default.
        noteProvisional(stepID: step.id, confirmAfter: FocusSegmentation.confirmDefault)
    }

    /// Click/action production with pointer disambiguation.
    ///
    /// - `clickCount` is the platform-reported press count: an OS double
    ///   inside 500 ms is accepted as the double (not suppressed as bounce,
    ///   not split into two singles). Rejected bounces hold the window.
    ///   Non-click actions (manual snapshots) pass `1`.
    internal func produceActionStep(
        action: ActionType,
        at point: Point2D,
        timestamp: Date,
        clickCount: Int = 1
    ) async -> ProducedStep? {
        // Flush any pending typed text/commands before recording the subsequent action
        if aggregator.hasPendingText, let batch = await aggregator.flushPending() {
            await produceTypingStep(batch)
        }

        guard state == .recording, !isFinalizing else { return nil }
        guard debouncer.shouldAcceptClick(at: timestamp, location: point, osClickCount: clickCount) else { return nil }
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
        // Delayed commit: clicks confirm at +150 ms.
        noteProvisional(stepID: step.id, confirmAfter: FocusSegmentation.confirmClick)

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
        // Delayed commit: typing confirms at +500 ms (slow path).
        noteProvisional(stepID: step.id, confirmAfter: FocusSegmentation.confirmTyping)

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
        // Boundary check: inspect source and target so a drag that crosses
        // elements is never misattributed to one side. The step keeps the
        // target (end) context.
        _ = enriched(await driver.inspectElement(at: start) ?? .unknown)
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
        // Delayed commit: drag confirms at +400 ms default.
        noteProvisional(stepID: step.id, confirmAfter: FocusSegmentation.confirmDefault)
    }

    /// Gate producer for app-switch steps (shared by the immediate `.emit`
    /// path and the limbo-settle path in `Segmentation.swift`). Mirrors the
    /// `.emit` branch: append, provisional (confirm at the default window),
    /// persist, emit.
    internal func produceAppSwitchStep(bundleId: String?, appName: String, windowTitle: String) async {
        guard state == .recording, !isFinalizing, var session = currentSession else { return }

        let step = StepFactory.makeAppSwitchStep(
            index: session.steps.count + 1,
            timestamp: time.now,
            bundleId: bundleId,
            appName: appName,
            windowTitle: windowTitle
        )

        session.steps.append(step)
        // Post-await state==recording re-check preserved.
        guard state == .recording, !isFinalizing else { return }
        noteProvisional(stepID: step.id, confirmAfter: FocusSegmentation.confirmDefault)
        currentSession = session
        try? store.saveSession(session)
        emitSnapshot()
    }

    internal func produceTerminalCommandStep(command: String, workingDirectory: String?) async {
        // Ordering: flush_typing_before_step preserved — pending text precedes
        // the terminal command.
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

        // Post-await state==recording re-check preserved.
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
        // Delayed commit: terminal commands confirm at +400 ms default.
        noteProvisional(stepID: step.id, confirmAfter: FocusSegmentation.confirmDefault)
    }
}
