import Foundation

/// Recording-toggle hotkey configuration (R/M1-07: moved from StepItCore).
/// Owned by the capture SPI target; matched against
/// `RecorderWorkflowEngine.EngineConfig.toggleHotkeyCombo`.
public struct HotkeySettings: Codable, Sendable, Equatable {
    public var toggleRecording: String

    public init(toggleRecording: String = "⌥ Space") {
        self.toggleRecording = toggleRecording
    }
}
