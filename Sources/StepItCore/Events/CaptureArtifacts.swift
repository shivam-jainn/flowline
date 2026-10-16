import Foundation

/// IR for a still capture (currently the bare `(image, pngData)` tuple returned
/// by `ScreenRecorder`). Lets `MockCaptureDriver` return a 1×1 PNG without any
/// rendering.
public struct FrameSnapshot: Codable, Sendable, Equatable {
    public var pngData: Data
    /// Backing scale factor of the captured screen (1.0 for non-Retina).
    public var scale: Double

    public init(pngData: Data, scale: Double = 1.0) {
        self.pngData = pngData
        self.scale = scale
    }
}

/// IR for micro-clips (today: a `(gifData, videoData)` callback tuple).
public struct ClipAsset: Codable, Sendable, Equatable {
    public var gifData: Data?
    public var videoData: Data?
    /// Length of the captured post-click window, in seconds.
    public var duration: TimeInterval

    public init(gifData: Data? = nil, videoData: Data? = nil, duration: TimeInterval = 0) {
        self.gifData = gifData
        self.videoData = videoData
        self.duration = duration
    }
}

/// Passes capture settings (`CaptureSettings.gifFps`,
/// `CaptureSettings.clipDurationPreClickSec`) across the SPI without the
/// driver ever reading `SessionStore`.
public struct ClipBufferConfig: Codable, Sendable, Equatable {
    public var fps: Int
    public var maxBufferSeconds: Double

    public init(fps: Int, maxBufferSeconds: Double) {
        self.fps = fps
        self.maxBufferSeconds = maxBufferSeconds
    }
}
