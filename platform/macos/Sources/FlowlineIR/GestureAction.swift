import Foundation

/// Gesture action vocabulary (owns: FlowlineIR). Moved from
/// FlowlineCore/Model/Settings.swift during R/M1-02: `RawInputEvent.Kind`
/// carries it, so it must live in IR. FlowlineCore re-exports via typealias
/// until R/M1-07.
public enum GestureAction: String, Codable, CaseIterable, Sendable {
    case none = "none"
    case pauseResume = "pause_resume"
    case stopAndReview = "stop_and_review"
    case discardLastStep = "discard_last_step"
    case addCheckpoint = "add_checkpoint"
    case captureSnapshot = "capture_snapshot"

    public var title: String {
        switch self {
        case .none: return "Disabled"
        case .pauseResume: return "Pause / Resume Recording"
        case .stopAndReview: return "Stop & Open Review Window"
        case .discardLastStep: return "Discard / Undo Last Step"
        case .addCheckpoint: return "Mark Step as Key Milestone"
        case .captureSnapshot: return "Capture Instant Snapshot"
        }
    }

    public var icon: String {
        switch self {
        case .none: return "slash.circle"
        case .pauseResume: return "pause.circle.fill"
        case .stopAndReview: return "stop.circle.fill"
        case .discardLastStep: return "arrow.uturn.backward.circle.fill"
        case .addCheckpoint: return "star.circle.fill"
        case .captureSnapshot: return "camera.circle.fill"
        }
    }
}
