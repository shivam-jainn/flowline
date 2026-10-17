import Foundation
import StepItCaptureAPI
import StepItIR
import StepItPipeline
import StepItCore

/// One atomic value the controller mirrors into `@Published` vars — no torn
/// reads across `async` hops.
///
/// `StepSession` is not `Equatable`, so snapshots compare via `stepCount` /
/// `state` where needed rather than value equality.
public struct RecorderSnapshot: Sendable {
    public var state: RecordingState
    public var currentSession: StepSession?
    public var stepCount: Int
    public var lastGestureNotice: String?
    /// Full gesture notice for presentation layers that need the name + mapped
    /// action (Settings live-test playground), not just the HUD string.
    public var lastGestureEvent: RawGestureNotice?

    public init(
        state: RecordingState,
        currentSession: StepSession?,
        stepCount: Int,
        lastGestureNotice: String?,
        lastGestureEvent: RawGestureNotice? = nil
    ) {
        self.state = state
        self.currentSession = currentSession
        self.stepCount = stepCount
        self.lastGestureNotice = lastGestureNotice
        self.lastGestureEvent = lastGestureEvent
    }
}
