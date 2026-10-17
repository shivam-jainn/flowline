import Foundation
import StepItIR

/// Smart-gestures configuration (R/M1-07: moved from StepItCore).
/// Owned by the capture SPI target; consumed by gesture detectors via
/// `GestureSettingsSink` and by the engine's gesture routing.
public enum GestureSensitivity: String, Codable, CaseIterable, Sendable {
    case low = "low"
    case medium = "medium"
    case high = "high"

    public var title: String {
        switch self {
        case .low: return "Low (Vigorous Motion)"
        case .medium: return "Medium (Balanced)"
        case .high: return "High (Quick Response)"
        }
    }

    public var thresholdVelocity: Double {
        switch self {
        case .low: return 850.0
        case .medium: return 550.0
        case .high: return 380.0
        }
    }
}

public struct HotCornerSettings: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var topLeft: GestureAction
    public var topRight: GestureAction
    public var bottomLeft: GestureAction
    public var bottomRight: GestureAction

    public init(
        enabled: Bool = true,
        topLeft: GestureAction = .discardLastStep,
        topRight: GestureAction = .pauseResume,
        bottomLeft: GestureAction = .none,
        bottomRight: GestureAction = .stopAndReview
    ) {
        self.enabled = enabled
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
    }
}

public struct GestureSettings: Codable, Sendable, Equatable {
    public var shakeToPauseEnabled: Bool
    public var shakeSensitivity: GestureSensitivity
    public var shakeAction: GestureAction

    public var hotCorners: HotCornerSettings

    public var middleClickAction: GestureAction
    public var doubleRightClickAction: GestureAction
    public var longPressAction: GestureAction
    public var longPressDurationSec: Double

    public init(
        shakeToPauseEnabled: Bool = true,
        shakeSensitivity: GestureSensitivity = .medium,
        shakeAction: GestureAction = .pauseResume,
        hotCorners: HotCornerSettings = HotCornerSettings(),
        middleClickAction: GestureAction = .addCheckpoint,
        doubleRightClickAction: GestureAction = .discardLastStep,
        longPressAction: GestureAction = .captureSnapshot,
        longPressDurationSec: Double = 0.8
    ) {
        self.shakeToPauseEnabled = shakeToPauseEnabled
        self.shakeSensitivity = shakeSensitivity
        self.shakeAction = shakeAction
        self.hotCorners = hotCorners
        self.middleClickAction = middleClickAction
        self.doubleRightClickAction = doubleRightClickAction
        self.longPressAction = longPressAction
        self.longPressDurationSec = longPressDurationSec
    }
}
