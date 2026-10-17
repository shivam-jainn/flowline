import Foundation
import StepItPipeline
import StepItCaptureAPI

/// Narrow settings shape the recording engine consumes (R/M1-07).
///
/// The full `StepItSettings` aggregate also carries publishing + gateway
/// sections the engine never reads; this struct is the engine-facing subset
/// (capture, privacy, hotkey policy, gestures). Surfaces project via
/// `StepItSettings.engineSettings`; `RecorderWorkflowEngine.applySettings`
/// accepts both shapes.
public struct EngineSettings: Sendable, Equatable {
    public var capture: CaptureSettings
    public var privacy: PrivacySettings
    public var hotkeyCapture: HotkeyCaptureSettings
    public var hotkeys: HotkeySettings
    public var gestures: GestureSettings

    public init(
        capture: CaptureSettings = CaptureSettings(),
        privacy: PrivacySettings = PrivacySettings(),
        hotkeyCapture: HotkeyCaptureSettings = HotkeyCaptureSettings(),
        hotkeys: HotkeySettings = HotkeySettings(),
        gestures: GestureSettings = GestureSettings()
    ) {
        self.capture = capture
        self.privacy = privacy
        self.hotkeyCapture = hotkeyCapture
        self.hotkeys = hotkeys
        self.gestures = gestures
    }
}

extension StepItSettings {
    /// Projects the engine-consumed subset out of the full aggregate.
    public var engineSettings: EngineSettings {
        EngineSettings(
            capture: capture,
            privacy: privacy,
            hotkeyCapture: hotkeyCapture,
            hotkeys: hotkeys,
            gestures: gestures
        )
    }
}
