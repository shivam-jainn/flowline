import Foundation

// MARK: - Capture Driver SPI
//
// This is the pluggable capture boundary of StepIt. The workflow engine depends
// only on these protocols — never on `NSEvent`, `AXUIElement` or
// `ScreenCaptureKit`. Future drivers (Web Extension, Windows) implement the
// same contracts.
//
// ## Threading
// Every protocol here is `AnyObject + Sendable`. Callbacks and async methods
// may be invoked from any thread; the engine serializes all event reduction
// through its actor. Implementations must be safe to call from any context.
//
// ## Lifecycle
// - `start()` is called **once per driver lifetime** by the engine (app
//   bootstrap), *not* per recording. Monitors stay alive across recordings so
//   gestures and the toggle hotkey work in every state (fix F1).
// - Recording start/stop only toggles engine state plus the clip ring-buffer.
// - `stop()` tears down hooks and finishes `eventStream` so the engine's
//   consumer task terminates cleanly (no leaked continuations).

/// Everything that *produces* input events plus its lifecycle.
public protocol InputEventSource: AnyObject, Sendable {
    /// `"macos-native"` / `"mock"` — telemetry, debugging, future driver selection.
    var platformIdentifier: String { get }

    /// Feature flags the engine uses to degrade gracefully
    /// (no clips → skip `startClipBuffering`; no AX → skip `inspectElement`).
    var capabilities: CaptureCapabilities { get }

    /// The push channel. Single consumer (the engine). Chosen over callbacks so
    /// tests can deterministically `yield` and the engine consumes with one
    /// `for await` loop.
    var eventStream: AsyncStream<RawInputEvent> { get }

    /// Boots platform hooks. Called once per driver lifetime by the engine.
    func start() async throws

    /// Driver-level hint (e.g. stop the clip ring-buffer to save CPU).
    /// **Contract: must NOT stop event acquisition** — the engine still needs
    /// gestures/hotkeys while paused; the engine drops step events itself.
    func pause() async

    /// Undo a previous `pause()`.
    func resume() async

    /// Tears down hooks and finishes the stream so the engine's consumer task
    /// terminates cleanly.
    func stop() async
}

/// Pull-model accessibility semantics.
public protocol ElementInspector: AnyObject, Sendable {
    /// Called by the engine on click to build the step's target description.
    /// Returns `nil` / `.unknown` without AX permission (parity with today's
    /// placeholder behavior).
    func inspectElement(at point: Point2D) async -> RawElementContext?

    /// Called at typing-batch finalization to classify terminal vs code vs
    /// text and label the step.
    func inspectFocusedElement() async -> RawElementContext?
}

/// Pull-model pixels.
public protocol VisualCapture: AnyObject, Sendable {
    /// Ring-buffer lifecycle — must start *before* the first click so pre-click
    /// frames exist.
    func startClipBuffering(config: ClipBufferConfig) async
    func stopClipBuffering() async

    /// Still capture with the existing click-highlight rendering; `stepIndex`
    /// keeps the `step_%02d` naming path intact.
    func captureSnapshot(highlightAt point: Point2D?, stepIndex: Int) async -> FrameSnapshot?

    /// Async wrapper over the callback-based micro-clip recorder so the engine
    /// can `await` the clip and patch step assets without callback pyramids.
    func captureMicroClip(around point: Point2D, postDuration: TimeInterval) async -> ClipAsset?
}

/// Composition type for concrete drivers and factories.
public protocol CaptureDriver: InputEventSource, ElementInspector, VisualCapture {}

/// Optional facet: drivers that own a gesture detector can accept settings
/// updates through this. Kept off `CaptureDriver` so non-macOS drivers can
/// ignore it while the engine routes settings generically.
public protocol GestureSettingsSink: AnyObject, Sendable {
    func updateGestureSettings(_ settings: GestureSettings) async
}

/// One flag set the engine and controllers can query; keeps feature detection
/// out of `#if os()` in core.
public struct CaptureCapabilities: Codable, Sendable, Equatable {
    public var snapshots: Bool
    public var microClips: Bool
    public var accessibilityTree: Bool
    public var secureFieldDetection: Bool

    public init(
        snapshots: Bool,
        microClips: Bool,
        accessibilityTree: Bool,
        secureFieldDetection: Bool
    ) {
        self.snapshots = snapshots
        self.microClips = microClips
        self.accessibilityTree = accessibilityTree
        self.secureFieldDetection = secureFieldDetection
    }

    public static let macNative = CaptureCapabilities(
        snapshots: true,
        microClips: true,
        accessibilityTree: true,
        secureFieldDetection: true
    )

    public static let mockFull = CaptureCapabilities.macNative
}

/// Typed failure surface; `start()` throws it and the engine surfaces
/// `.permissionDenied` to the controller.
public enum CaptureDriverError: Error, Sendable, Equatable {
    case permissionDenied(PermissionKind)
    case notRunning
    case captureFailed(String)
    case unsupported(String)
}

/// Maps to `PermissionsManager` checks without leaking AX constants into core.
public enum PermissionKind: String, Codable, Sendable, CaseIterable {
    case accessibility
    case screenRecording
}
