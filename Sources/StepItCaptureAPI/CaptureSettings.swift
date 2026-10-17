import Foundation
import StepItIR

/// Capture behaviour configuration (R/M1-07: moved from StepItCore).
/// Portable config owned by the capture SPI target.
public struct CaptureSettings: Codable, Sendable, Equatable {
    public var mediaMode: MediaMode
    public var gifFps: Int
    public var clipDurationPreClickSec: Double
    public var clipDurationPostClickSec: Double
    public var highlightClicks: Bool
    public var highlightColorHex: String
    public var highlightRadius: Double
    /// Phase 2: emit discrete `.appSwitch` steps when the frontmost app changes
    /// during a recording (opt-in; context tracking is always updated).
    public var recordAppSwitches: Bool

    public init(
        mediaMode: MediaMode = .hybrid,
        gifFps: Int = 15,
        clipDurationPreClickSec: Double = 0.5,
        clipDurationPostClickSec: Double = 1.5,
        highlightClicks: Bool = true,
        highlightColorHex: String = "#EF4444",
        highlightRadius: Double = 28.0,
        recordAppSwitches: Bool = false
    ) {
        self.mediaMode = mediaMode
        self.gifFps = gifFps
        self.clipDurationPreClickSec = clipDurationPreClickSec
        self.clipDurationPostClickSec = clipDurationPostClickSec
        self.highlightClicks = highlightClicks
        self.highlightColorHex = highlightColorHex
        self.highlightRadius = highlightRadius
        self.recordAppSwitches = recordAppSwitches
    }

    // Lenient decoding so Settings.json written before Phase 2 (without
    // `recordAppSwitches`) still loads instead of resetting user settings.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.mediaMode = try container.decodeIfPresent(MediaMode.self, forKey: .mediaMode) ?? .hybrid
        self.gifFps = try container.decodeIfPresent(Int.self, forKey: .gifFps) ?? 15
        self.clipDurationPreClickSec = try container.decodeIfPresent(Double.self, forKey: .clipDurationPreClickSec) ?? 0.5
        self.clipDurationPostClickSec = try container.decodeIfPresent(Double.self, forKey: .clipDurationPostClickSec) ?? 1.5
        self.highlightClicks = try container.decodeIfPresent(Bool.self, forKey: .highlightClicks) ?? true
        self.highlightColorHex = try container.decodeIfPresent(String.self, forKey: .highlightColorHex) ?? "#EF4444"
        self.highlightRadius = try container.decodeIfPresent(Double.self, forKey: .highlightRadius) ?? 28.0
        self.recordAppSwitches = try container.decodeIfPresent(Bool.self, forKey: .recordAppSwitches) ?? false
    }
}
