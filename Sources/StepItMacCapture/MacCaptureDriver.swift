import Foundation
import StepItIR
import StepItPipeline
import StepItCaptureAPI
import StepItCore
import AppKit

/// macOS implementation of the `CaptureDriver` SPI.
///
/// Single owner and single wiring point for `NSEvent` monitors, AX inspection,
/// screen capture, micro-clips, gestures, hotkey recognition, drag detection,
/// app-switch observation, terminal introspection and OCR redaction. Every
/// collaborator is injected — no hidden `.shared` lookups.
///
/// Lifecycle is app-scoped: `start()` runs once at bootstrap, so the `⌥Space`
/// toggle hotkey and smart gestures work in **all** recording states (fix F1).
/// Recording start/stop only toggles the clip ring-buffer.
public final class MacCaptureDriver: CaptureDriver, GestureSettingsSink, HotkeySettingsSink,
    VisualObscuring, VisualRedactionProviding, TerminalContextProviding, @unchecked Sendable {

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

    /// Stashed mouse-down so release can classify click vs. drag (T8).
    private struct PendingClick {
        var button: MouseButton
        var clickCount: Int
        var point: CGPoint
    }

    // MARK: - Collaborators

    private let eventMonitor: EventMonitor
    private let inspector: AccessibilityInspector
    private let screenRecorder: ScreenRecorder
    private let clipRecorder: MicroClipRecorder
    private let gestureDetector: SmartGestureDetector
    private let dragDetector: MouseDragDetector
    private let appSwitchMonitor: AppSwitchMonitor
    private let terminalInspector: TerminalContextInspector
    private let ocrScanner: VisionOCRScanner
    private let config: Configuration

    // MARK: - Event stream

    private let continuation: AsyncStream<RawInputEvent>.Continuation
    public let eventStream: AsyncStream<RawInputEvent>

    // MARK: - State

    private let lock = NSLock()
    private var wantsClipBuffering = false
    private var pendingClick: PendingClick?

    // MARK: - Init

    public init(
        eventMonitor: EventMonitor,
        inspector: AccessibilityInspector,
        screenRecorder: ScreenRecorder,
        clipRecorder: MicroClipRecorder,
        gestureDetector: SmartGestureDetector,
        dragDetector: MouseDragDetector = MouseDragDetector(),
        appSwitchMonitor: AppSwitchMonitor = AppSwitchMonitor(),
        terminalInspector: TerminalContextInspector = TerminalContextInspector(),
        ocrScanner: VisionOCRScanner = VisionOCRScanner(),
        config: Configuration = Configuration()
    ) {
        self.eventMonitor = eventMonitor
        self.inspector = inspector
        self.screenRecorder = screenRecorder
        self.clipRecorder = clipRecorder
        self.gestureDetector = gestureDetector
        self.dragDetector = dragDetector
        self.appSwitchMonitor = appSwitchMonitor
        self.terminalInspector = terminalInspector
        self.ocrScanner = ocrScanner
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
            // Parity: only left/right presses become click/drag steps.
            guard button == .left || button == .right else { return }
            // Defer the click until release so a drag is not double-recorded
            // as click + drag (T8).
            self.lock.withLock {
                self.pendingClick = PendingClick(button: button, clickCount: clickCount, point: point)
            }
            self.dragDetector.handleMouseDown(at: point)
        }

        eventMonitor.onMouseMove = { [weak self] point in
            guard let self = self, self.config.enableGestures else { return }
            self.gestureDetector.handleMouseMoved(to: point)
        }

        eventMonitor.onMouseUp = { [weak self] button, clickCount, point in
            guard let self = self else { return }
            if self.config.enableGestures {
                self.gestureDetector.handleMouseUp()
            }
            let pending: PendingClick? = self.lock.withLock {
                let pending = self.pendingClick
                self.pendingClick = nil
                return pending
            }
            guard let pending = pending else { return }
            _ = button

            if let drag = self.dragDetector.handleMouseUp(at: point), drag.isDrag {
                self.emit(.mouseDrag(start: Point2D(drag.start), end: Point2D(drag.end)), at: drag.end)
            } else {
                self.emit(
                    .mouseClick(button: pending.button, clickCount: max(pending.clickCount, clickCount)),
                    at: pending.point
                )
            }
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

        appSwitchMonitor.onAppActivated = { [weak self] bundleId, appName, _ in
            self?.continuation.yield(RawInputEvent(
                kind: .appSwitch(bundleId: bundleId, appName: appName, windowTitle: "")
            ))
        }

        eventMonitor.start()
        appSwitchMonitor.start()
    }

    public func stop() async {
        eventMonitor.stop()
        appSwitchMonitor.stop()
        eventMonitor.onMouseDown = nil
        eventMonitor.onMouseMove = nil
        eventMonitor.onMouseUp = nil
        eventMonitor.onKeyStroke = nil
        eventMonitor.onHotkeyCombo = nil
        gestureDetector.onGestureDetected = nil
        appSwitchMonitor.onAppActivated = nil
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

    // MARK: - HotkeySettingsSink

    /// The single sanctioned way hotkey-capture policy reaches the monitor's
    /// recognizer (R3: the toggle combo is centralized in `HotkeyRecognizer`).
    public func updateHotkeySettings(_ settings: HotkeyCaptureSettings, toggleCombo: String) async {
        eventMonitor.recognizer.settings = settings
        eventMonitor.recognizer.toggleCombo = toggleCombo
    }

    // MARK: - TerminalContextProviding

    public func inspectTerminalWorkingDirectory(bundleId: String?, pid: Int32?, windowTitle: String?) async -> String? {
        await terminalInspector.inspectCurrentDirectory(forApp: bundleId, pid: pid, windowTitle: windowTitle)
    }

    // MARK: - VisualObscuring

    /// Solid-blackout over secure-field regions. Coordinates are screen-space
    /// points (Cocoa, bottom-left origin), matching the captured image's
    /// bottom-left CoreImage space after subtracting the screen origin.
    public func obscureSensitiveRegions(
        in snapshot: FrameSnapshot,
        regions: [ElementRect],
        anchor: Point2D?
    ) async -> FrameSnapshot {
        guard !regions.isEmpty else { return snapshot }

        let anchorPoint = anchor.map { CGPoint($0) } ?? CGPoint(
            x: regions[0].x + regions[0].width / 2,
            y: regions[0].y + regions[0].height / 2
        )
        let screenFrame = NSScreen.screens.first(where: { $0.frame.contains(anchorPoint) })?.frame
            ?? NSScreen.main?.frame
        guard let screenFrame = screenFrame else { return snapshot }

        let scale = snapshot.scale
        let pixelRegions = regions.map { region in
            CGRect(
                x: (region.x - screenFrame.minX) * scale,
                y: (region.y - screenFrame.minY) * scale,
                width: region.width * scale,
                height: region.height * scale
            )
        }

        let compositor = BlurCompositor(configuration: .init(style: .blackout, radius: 0))
        guard let obscured = compositor.apply(to: snapshot.pngData, pixelRegions: pixelRegions, scale: scale) else {
            return snapshot
        }
        return FrameSnapshot(pngData: obscured, scale: snapshot.scale)
    }

    // MARK: - VisualRedactionProviding

    /// Offline pipeline: Vision OCR → `SensitiveDataDetector` (core) →
    /// CoreImage blur. Runs entirely on the scanner's utility queue.
    public func redactSensitiveContent(in snapshot: FrameSnapshot, settings: PrivacySettings) async -> RedactionOutcome {
        guard settings.enableOfflineOCRRedaction else {
            return RedactionOutcome(snapshot: snapshot, isRedacted: false)
        }

        let items = await ocrScanner.scanText(in: snapshot.pngData)
        guard !items.isEmpty else {
            return RedactionOutcome(snapshot: snapshot, isRedacted: false)
        }

        let plan = PrivacyRedactionEngine(settings: settings).plan(for: items)
        guard plan.isRedacted else {
            return RedactionOutcome(snapshot: snapshot, isRedacted: false)
        }

        let compositor = BlurCompositor(configuration: .init(style: settings.blurStyle, radius: settings.blurRadius))
        guard let redacted = compositor.apply(to: snapshot.pngData, normalizedRegions: plan.regions, scale: snapshot.scale) else {
            return RedactionOutcome(snapshot: snapshot, isRedacted: false)
        }
        return RedactionOutcome(snapshot: FrameSnapshot(pngData: redacted, scale: snapshot.scale), isRedacted: true)
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
