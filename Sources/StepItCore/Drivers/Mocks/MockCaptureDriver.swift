import Foundation

/// In-memory `CaptureDriver` for headless tests: no `CGEvent`, no AX
/// permission, no display. Behaving like a non-macOS driver also proves the SPI
/// is implementable off-Apple.
public final class MockCaptureDriver: CaptureDriver, GestureSettingsSink, @unchecked Sendable {

    // MARK: - Identity

    public let platformIdentifier = "mock"
    public let capabilities: CaptureCapabilities

    // MARK: - Event stream

    private let continuation: AsyncStream<RawInputEvent>.Continuation
    public let eventStream: AsyncStream<RawInputEvent>

    // MARK: - Scripted providers

    /// Scripts the element under a click point.
    public var contextProvider: (@Sendable (Point2D) -> RawElementContext?)?
    /// Scripts the focused element context used at typing finalization.
    /// Falls back to `contextProvider?(.zero)` when unset.
    public var focusedContextProvider: (@Sendable () -> RawElementContext?)?
    /// Scripts still captures. Defaults to a 1×1 PNG.
    public var snapshotProvider: (@Sendable (Point2D?) -> FrameSnapshot?)?
    /// Scripts micro-clips. Defaults to a GIF+MP4 stub pair.
    public var clipProvider: (@Sendable (Point2D) -> ClipAsset?)?

    // MARK: - Spy state

    private let lock = NSLock()
    private var _started = false
    private var _stoppedCount = 0
    private var _isStreamFinished = false
    private var _paused = false
    private var _isBuffering = false
    private var _bufferingConfig: ClipBufferConfig?
    private var _inspectedPoints: [Point2D] = []
    private var _focusedInspectionCount = 0
    private var _snapshotStepIndices: [Int] = []
    private var _lastHighlightPoint: Point2D?
    private var _clipRequests: [Point2D] = []
    private var _appliedGestureSettings: [GestureSettings] = []

    public var started: Bool { lock.withLock { _started } }
    public var stoppedCount: Int { lock.withLock { _stoppedCount } }
    public var isStreamFinished: Bool { lock.withLock { _isStreamFinished } }
    public var paused: Bool { lock.withLock { _paused } }
    public var isBuffering: Bool { lock.withLock { _isBuffering } }
    public var bufferingConfig: ClipBufferConfig? { lock.withLock { _bufferingConfig } }
    public var inspectedPoints: [Point2D] { lock.withLock { _inspectedPoints } }
    public var focusedInspectionCount: Int { lock.withLock { _focusedInspectionCount } }
    public var snapshotStepIndices: [Int] { lock.withLock { _snapshotStepIndices } }
    public var lastHighlightPoint: Point2D? { lock.withLock { _lastHighlightPoint } }
    public var clipRequests: [Point2D] { lock.withLock { _clipRequests } }
    public var appliedGestureSettings: [GestureSettings] { lock.withLock { _appliedGestureSettings } }

    // MARK: - Init

    public init(
        capabilities: CaptureCapabilities = .mockFull,
        contextProvider: (@Sendable (Point2D) -> RawElementContext?)? = nil,
        focusedContextProvider: (@Sendable () -> RawElementContext?)? = nil,
        snapshotProvider: (@Sendable (Point2D?) -> FrameSnapshot?)? = nil,
        clipProvider: (@Sendable (Point2D) -> ClipAsset?)? = nil
    ) {
        self.capabilities = capabilities
        self.contextProvider = contextProvider
        self.focusedContextProvider = focusedContextProvider
        self.snapshotProvider = snapshotProvider ?? { _ in FrameSnapshot(pngData: MockAssets.onePixelPNG, scale: 2.0) }
        self.clipProvider = clipProvider ?? { _ in
            ClipAsset(gifData: MockAssets.gifStub, videoData: MockAssets.mp4Stub, duration: 0.5)
        }

        var cont: AsyncStream<RawInputEvent>.Continuation!
        self.eventStream = AsyncStream<RawInputEvent>(bufferingPolicy: .unbounded) { cont = $0 }
        self.continuation = cont
    }

    // MARK: - Emission helpers

    public func emit(_ event: RawInputEvent) {
        continuation.yield(event)
    }

    @discardableResult
    public func emitClick(
        at point: Point2D,
        button: MouseButton = .left,
        clickCount: Int = 1,
        timestamp: Date = Date(),
        context: RawElementContext? = nil
    ) -> UUID {
        let event = RawInputEvent(
            timestamp: timestamp,
            kind: .mouseClick(button: button, clickCount: clickCount),
            location: point,
            targetContext: context
        )
        emit(event)
        return event.id
    }

    public func emitKey(
        _ key: String,
        code: Int? = nil,
        modifiers: KeyModifiers = [],
        timestamp: Date = Date(),
        location: Point2D? = nil
    ) {
        emit(RawInputEvent(
            timestamp: timestamp,
            kind: .keyStroke(key: key, code: code, modifiers: modifiers),
            location: location
        ))
    }

    public func emitHotkey(_ combo: String, timestamp: Date = Date()) {
        emit(RawInputEvent(timestamp: timestamp, kind: .hotkeyCombo(combo: combo)))
    }

    public func emitGesture(name: String, action: GestureAction, location: Point2D = .zero, timestamp: Date = Date()) {
        emit(RawInputEvent(
            timestamp: timestamp,
            kind: .userGesture(name: name, action: action),
            location: location
        ))
    }

    // MARK: - InputEventSource

    public func start() async throws {
        lock.withLock { _started = true }
    }

    public func pause() async {
        lock.withLock { _paused = true }
    }

    public func resume() async {
        lock.withLock { _paused = false }
    }

    public func stop() async {
        lock.withLock {
            _stoppedCount += 1
            _isStreamFinished = true
        }
        continuation.finish()
    }

    // MARK: - ElementInspector

    public func inspectElement(at point: Point2D) async -> RawElementContext? {
        lock.withLock { _inspectedPoints.append(point) }
        return contextProvider?(point)
    }

    public func inspectFocusedElement() async -> RawElementContext? {
        lock.withLock { _focusedInspectionCount += 1 }
        if let focusedContextProvider = focusedContextProvider {
            return focusedContextProvider()
        }
        return contextProvider?(.zero)
    }

    // MARK: - VisualCapture

    public func startClipBuffering(config: ClipBufferConfig) async {
        lock.withLock {
            _isBuffering = true
            _bufferingConfig = config
        }
    }

    public func stopClipBuffering() async {
        lock.withLock { _isBuffering = false }
    }

    public func captureSnapshot(highlightAt point: Point2D?, stepIndex: Int) async -> FrameSnapshot? {
        lock.withLock {
            _snapshotStepIndices.append(stepIndex)
            _lastHighlightPoint = point
        }
        return snapshotProvider?(point)
    }

    public func captureMicroClip(around point: Point2D, postDuration: TimeInterval) async -> ClipAsset? {
        lock.withLock { _clipRequests.append(point) }
        return clipProvider?(point)
    }

    // MARK: - GestureSettingsSink

    public func updateGestureSettings(_ settings: GestureSettings) async {
        lock.withLock { _appliedGestureSettings.append(settings) }
    }
}
