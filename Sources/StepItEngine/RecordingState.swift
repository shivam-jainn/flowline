import Foundation
import StepItCaptureAPI
import StepItIR
import StepItPipeline

/// Recording state machine states. Moved out of the pre-Phase-1 coordinator file
/// unchanged (same 3 cases, same public name) so no call site churns.
public enum RecordingState: Equatable, Sendable {
    case idle
    case recording
    case paused
}
