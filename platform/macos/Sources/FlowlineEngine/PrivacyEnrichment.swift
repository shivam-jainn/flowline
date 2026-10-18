import Foundation
import FlowlineCaptureAPI
import FlowlineIR
import FlowlinePipeline

// MARK: - Privacy and terminal enrichment (privacy half) (R/M1-03 reducer split; verbatim logic from RecorderWorkflowEngine)

extension RecorderWorkflowEngine {
    /// Fills missing app context from the last observed app switch.
    /// Swift parity anchor (`PrivacyEnrichment.swift:12-13`): fill when the
    /// app name is empty **or** the `"Unknown App"` placeholder — the Rust
    /// port mirrors this exact predicate to stay drift-proof.
    internal func enriched(_ context: RawElementContext) -> RawElementContext {
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
    /// Applies the full settings snapshot: privacy/hotkey policy locally, then
    /// the driver-owned facets (gestures + hotkey recognizer). Called by
    /// `WorkflowController` on save so changes take effect immediately (T9).
    /// Narrow-shape entry point (R/M1-07); the engine never reads publishing
    /// or gateway sections.
    public func applySettings(_ settings: EngineSettings) async {
        engineSettings = settings
        applyLocalSettings(settings)
        await applyGestureSettings(settings.gestures)
        await applyHotkeyPolicyToDriver(settings)
        emitSnapshot()
    }

    /// Compatibility overload: projects the engine-consumed subset out of the
    /// full aggregate. Existing callers (tests, controller) keep compiling.
    public func applySettings(_ settings: FlowlineSettings) async {
        await applySettings(settings.engineSettings)
    }

    internal func applyLocalSettings(_ settings: EngineSettings) {
        privacySettings = settings.privacy
        hotkeySettings = settings.hotkeyCapture
        captureSettings = settings.capture
        toggleCombo = settings.hotkeys.toggleRecording.isEmpty ? config.toggleHotkeyCombo : settings.hotkeys.toggleRecording
        recognizer.settings = settings.hotkeyCapture
        recognizer.toggleCombo = toggleCombo
        aggregator.privacySettings = settings.privacy
    }

    internal func applyHotkeyPolicyToDriver(_ settings: EngineSettings) async {
        guard let sink = driver as? HotkeySettingsSink else { return }
        await sink.updateHotkeySettings(settings.hotkeyCapture, toggleCombo: toggleCombo)
    }
}
