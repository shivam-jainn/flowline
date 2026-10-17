import Foundation
import StepItCaptureAPI
import StepItIR
import StepItPipeline
import StepItCore

// MARK: - Event reduction (R/M1-03 reducer split; verbatim logic from RecorderWorkflowEngine)

extension RecorderWorkflowEngine {
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
    internal func handleKeystroke(key: String, code: Int?, modifiers: KeyModifiers, at location: Point2D?) async {
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
    internal func handleTextInput(key: String, at location: Point2D) async {
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

    internal func handleKeyPressStep(_ chord: HotkeyChord, at location: Point2D) async {
        await withStepGate {
            await produceKeyPressStep(chord, at: location)
        }
    }


    // MARK: - Click / action handling

    /// Parity with `handleAction`: flush the aggregator first (order
    /// guarantee), debounce, pull element context, capture a highlighted
    /// snapshot, append + persist + emit, then collect the micro-clip and patch
    /// assets by step id.
    internal func handleAction(action: ActionType, at point: Point2D, timestamp: Date) async {
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


    // MARK: - Typing handling

    /// Parity with `handleTyping`: snapshot, build the typing step, append +
    /// persist + emit, then fast-forward GIF patch.
    ///
    /// Phase 2: terminal batches resolve the shell's `pwd` through the driver's
    /// `TerminalContextProviding` facet (T4/T5) and secure fields blackout the
    /// snapshot (T6).
    internal func handleTypingBatch(_ result: TypingBatchResult) async {
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

    // MARK: - Drag & app-switch handling (T8)

    internal func handleMouseDrag(start: Point2D, end: Point2D, timestamp: Date) async {
        await withStepGate {
            await produceDragStep(start: start, end: end, timestamp: timestamp)
        }
    }

    internal func handleAppSwitch(bundleId: String?, appName: String, windowTitle: String) async {
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


    // MARK: - Helpers

    internal func matchesToggleHotkey(_ combo: String) -> Bool {
        Self.normalizeHotkey(combo) == Self.normalizeHotkey(toggleCombo)
            || Self.normalizeHotkey(combo) == Self.normalizeHotkey(config.toggleHotkeyCombo)
    }

    internal static func normalizeHotkey(_ combo: String) -> String {
        combo.replacingOccurrences(of: " ", with: "").lowercased()
    }
}
