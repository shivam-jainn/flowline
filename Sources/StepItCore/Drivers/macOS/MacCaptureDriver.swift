import Foundation
import AppKit

/// macOS implementation of the `CaptureDriver` SPI.
///
/// Single owner and single wiring point for `NSEvent` monitors, AX inspection,
/// screen capture, micro-clips and gestures. Every collaborator is injected —
/// no hidden `.shared` lookups.
///
/// Lifecycle is app-scoped: `start()` runs once at bootstrap, so the `⌥Space`
/// toggle hotkey and smart gestures work in **all** recording states (fix F1).
/// Recording start/stop only toggles the clip ring-buffer.
public final class MacCaptureDriver: CaptureDriver, GestureSettingsSink, @unchecked Sendable {

    public struct Configuration: Sendable {
        /// Enables forwarding mouse motion / buttons to the gesture detector.
        public var enableGestures: Bool
        /// The toggle-recording hotkey the macOS monitor listens for.
        /// (Phase 1 supports `⌥Space` in `EventMonitor`; the value here is
        /// carried for telemetry and future hotkey tables.)
        public var toggleHotkeyCombo: String

        public init(enableGestures: Bool = true, toggleHotkeyCombo: String = "⌥Space") {
            self.enableGestures = enableGestures
            self.toggleHotkeyCombo = toggleHotkeyCombo
        }
    }

    // MARK: - Collaborators

    private let eventMonitor: EventMonitor
    private let inspector: AccessibilityInspector
    private let screenRecorder: ScreenRecorder
    private let clipRecorder: MicroClipRecorder
    private let gestureDetector: SmartGestureDetector
    private let config: Configuration

    // MARK: - Event stream

    private let continuation: AsyncStream<RawInputEvent>.Continuation
    public let eventStream: AsyncStream<RawInputEvent>

    // MARK: - State

    private let lock = NSLock()
    private var wantsClipBuffering = false

    // MARK: - Init

    public init(
        eventMonitor: EventMonitor,
        inspector: AccessibilityInspector,
        screenRecorder: ScreenRecorder,
        clipRecorder: MicroClipRecorder,
        gestureDetector: SmartGestureDetector,
        config: Configuration = Configuration()
    ) {
        self.eventMonitor = eventMonitor
        self.inspector = inspector
        self.screenRecorder = screenRecorder
        self.clipRecorder = clipRecorder
        self.gestureDetector = gestureDetector
        self.config = config

        var cont: AsyncStream<RawInputEvent>.Continuation!
        self.eventStream = AsyncStream<RawInputEvent>(bufferingPolicy: .unbounded) { cont = $0 }
        self.continuation = cont
    }

    /// Default wiring used by the app: one instance of each platform hook.
    public convenience init(config: Configuration = Configuration()) {
        self.init(
            eventMonitor: EventMonitor(),
            inspector: AccessibilityInspector(),
            screenRecorder: ScreenRecorder(),
            clipRecorder: MicroClipRecorder(),
            gestureDetector: SmartGestureDetector(),
            config: config
        )
    }

    // MARK: - InputEventSource

    public var platformIdentifier: String { "macos-native" }

    public var capabilities: CaptureCapabilities { .macNative }

    /// Boots the platform hooks and wires each raw callback to exactly one IR
    /// event. Permissions stay advisory (parity with `PermissionsBannerView`).
    public func start() async throws {
        eventMonitor.onMouseDown = { [weak self] button, clickCount, point in
            guard let self = self else { return }
            if self.config.enableGestures {
                self.gestureDetector.handleMouseDown(button: button, at: point)
            }
            // Parity: only left/right presses become click steps.
            guard button == .left || button == .right else { return }
            self.emit(.mouseClick(button: button, clickCount: clickCount), at: point)
        }

        eventMonitor.onMouseMove = { [weak self] point in
            guard let self = self, self.config.enableGestures else { return }
            self.gestureDetector.handleMouseMoved(to: point)
        }

        eventMonitor.onMouseUp = { [weak self] in
            guard let self = self, self.config.enableGestures else { return }
            self.gestureDetector.handleMouseUp()
        }

        eventMonitor.onKeyStroke = { [weak self] key, code, modifiers in
            self?.emit(.keyStroke(key: key, code: code, modifiers: modifiers), at: NSEvent.mouseLocation)
        }

        eventMonitor.onHotkeyCombo = { [weak self] combo in
            self?.continuation.yield(RawInputEvent(kind: .hotkeyCombo(combo: combo)))
        }

        gestureDetector.onGestureDetected = { [weak self] notice in
            self?.continuation.yield(.userGesture(notice))
        }

        eventMonitor.start()
    }

    public func stop() async {
        eventMonitor.stop()
        eventMonitor.onMouseDown = nil
        eventMonitor.onMouseMove = nil
        eventMonitor.onMouseUp = nil
        eventMonitor.onKeyStroke = nil
        eventMonitor.onHotkeyCombo = nil
        gestureDetector.onGestureDetected = nil
        continuation.finish()
    }

    /// Pauses the clip ring-buffer only — monitors stay up so gestures and
    /// hotkeys keep flowing while the engine is paused.
    public func pause() async {
        if lock.withLock({ wantsClipBuffering }) {
            clipRecorder.stopBuffering()
        }
    }

    public func resume() async {
        if lock.withLock({ wantsClipBuffering }) {
            clipRecorder.startBuffering()
        }
    }

    // MARK: - ElementInspector

    public func inspectElement(at point: Point2D) async -> RawElementContext? {
        RawElementContext(inspector.inspectElement(at: CGPoint(point)))
    }

    public func inspectFocusedElement() async -> RawElementContext? {
        RawElementContext(inspector.inspectFocusedElement())
    }

    // MARK: - VisualCapture

    public func startClipBuffering(config: ClipBufferConfig) async {
        lock.withLock { wantsClipBuffering = true }
        clipRecorder.fps = config.fps
        clipRecorder.maxBufferSeconds = config.maxBufferSeconds
        clipRecorder.startBuffering()
    }

    public func stopClipBuffering() async {
        lock.withLock { wantsClipBuffering = false }
        clipRecorder.stopBuffering()
    }

    public func captureSnapshot(highlightAt point: Point2D?, stepIndex: Int) async -> FrameSnapshot? {
        let cgPoint = point.map { CGPoint($0) }
        guard let result = screenRecorder.captureScreen(highlightAt: cgPoint, stepIndex: stepIndex) else {
            return nil
        }
        return FrameSnapshot(pngData: result.pngData, scale: scaleFactor(for: cgPoint))
    }

    public func captureMicroClip(around point: Point2D, postDuration: TimeInterval) async -> ClipAsset? {
        let cgPoint = CGPoint(point)
        return await withCheckedContinuation { continuation in
            clipRecorder.recordClip(around: cgPoint, postDuration: postDuration) { gifData, videoData in
                if gifData == nil && videoData == nil {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: ClipAsset(
                        gifData: gifData,
                        videoData: videoData,
                        duration: postDuration
                    ))
                }
            }
        }
    }

    // MARK: - GestureSettingsSink

    /// The single sanctioned way gesture settings reach the detector
    /// (replaces the old competing gesture-detector writers).
    public func updateGestureSettings(_ settings: GestureSettings) async {
        gestureDetector.settings = settings
    }

    // MARK: - Helpers

    private func emit(_ kind: RawInputEvent.Kind, at point: CGPoint? = nil, timestamp: Date = Date()) {
        continuation.yield(RawInputEvent(
            timestamp: timestamp,
            kind: kind,
            location: point.map { Point2D($0) }
        ))
    }

    private func scaleFactor(for point: CGPoint?) -> Double {
        if let point = point, let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            return Double(screen.backingScaleFactor)
        }
        return Double(NSScreen.main?.backingScaleFactor ?? 1)
    }
}
