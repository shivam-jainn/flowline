import Foundation
import StepItIR
import StepItPipeline
import StepItCore

// MARK: - Privacy and terminal enrichment (privacy half) (R/M1-03 reducer split; verbatim logic from RecorderWorkflowEngine)

extension RecorderWorkflowEngine {
    /// Fills missing app context from the last observed app switch.
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
    public func applySettings(_ settings: StepItSettings) async {
        applyLocalSettings(settings)
        await applyGestureSettings(settings.gestures)
        await applyHotkeyPolicyToDriver(settings)
        emitSnapshot()
    }

    internal func applyLocalSettings(_ settings: StepItSettings) {
        privacySettings = settings.privacy
        hotkeySettings = settings.hotkeyCapture
        captureSettings = settings.capture
        toggleCombo = settings.hotkeys.toggleRecording.isEmpty ? config.toggleHotkeyCombo : settings.hotkeys.toggleRecording
        recognizer.settings = settings.hotkeyCapture
        recognizer.toggleCombo = toggleCombo
        aggregator.privacySettings = settings.privacy
    }

    internal func applyHotkeyPolicyToDriver(_ settings: StepItSettings) async {
        guard let sink = driver as? HotkeySettingsSink else { return }
        await sink.updateHotkeySettings(settings.hotkeyCapture, toggleCombo: toggleCombo)
    }
}
