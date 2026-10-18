import Foundation
import FlowlineIR
import FlowlinePipeline

/// Tracks press → release geometry and classifies click vs. jitter vs.
/// deliberate drag (Phase 2, T8; pointer-disambiguation bands).
///
/// Pure value-in/value-out logic (no AppKit), so the distance and duration
/// thresholds are unit-testable with synthetic coordinates and timestamps.
///
/// Bands:
/// - `< clickRadius` (4 pt mouse, 6 pt trackpad): click, moves ignored.
/// - 4–10 pt: velocity-gated — `> 50 pt/s` is a drag, else jitter (a click).
/// - `> 10 pt`, or held `> 300 ms` past the click radius: a drag.
/// - A stationary long-press stays a click (long-press ≠ drag).
///
/// Drag emission always forces a source-vs-target element boundary check at
/// the engine layer (`produceDragStep` inspects both ends).
public final class MouseDragDetector: @unchecked Sendable {

    /// Classification of a completed press → release gesture. `jitter` is
    /// hand tremor, not intent — callers treat it like `click` (never emit
    /// `.mouseDrag`); the distinct case exists so tests can pin the band.
    public enum PressRelease: Sendable, Equatable {
        case click
        case jitter
        case drag
    }

    public struct Configuration: Sendable {
        /// Euclidean distance below which any press → release is a click.
        public var clickRadius: Double
        /// Same, for trackpads (wider deadzone, 5–6 pt).
        public var trackpadClickRadius: Double
        /// Distance above which the gesture is always a drag.
        public var dragRadius: Double
        /// 4–10 pt band gate: above this press → release velocity is a drag.
        public var velocityThresholdPxPerSec: Double
        /// Held past the click radius longer than this is a drag.
        public var longHoldDuration: TimeInterval
        /// Legacy T8 alias for `dragRadius`.
        public var minimumDistance: Double {
            get { dragRadius }
            set { dragRadius = newValue }
        }
        /// Legacy T8 alias for `longHoldDuration`.
        public var minimumDuration: TimeInterval {
            get { longHoldDuration }
            set { longHoldDuration = newValue }
        }

        public init(
            clickRadius: Double = 4.0,
            trackpadClickRadius: Double = 6.0,
            dragRadius: Double = 10.0,
            velocityThresholdPxPerSec: Double = 50.0,
            longHoldDuration: TimeInterval = 0.30
        ) {
            self.clickRadius = clickRadius
            self.trackpadClickRadius = trackpadClickRadius
            self.dragRadius = dragRadius
            self.velocityThresholdPxPerSec = velocityThresholdPxPerSec
            self.longHoldDuration = longHoldDuration
        }

        /// Legacy T8 initializer (`minimumDistance`/`minimumDuration`).
        public init(minimumDistance: Double, minimumDuration: TimeInterval) {
            self.init(dragRadius: minimumDistance, longHoldDuration: minimumDuration)
        }
    }

    /// Result of a completed press → release gesture.
    public struct DragGesture: Sendable, Equatable {
        public var start: CGPoint
        public var end: CGPoint
        public var distance: Double
        public var duration: TimeInterval
        /// `true` when the gesture is a deliberate drag — emit `.mouseDrag`.
        public var isDrag: Bool
    }

    public let configuration: Configuration

    private let lock = NSLock()
    private var downPoint: CGPoint?
    private var downTimestamp: Date?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Mean press → release velocity in pt/s (single implementation in
    /// `EventDebouncer`; kept here for call-site compatibility).
    public static func pointerVelocity(distance: Double, duration: TimeInterval) -> Double {
        EventDebouncer.pointerVelocity(distance: distance, duration: duration)
    }

    /// Pure band classifier shared by `handleMouseUp` (mirrors
    /// `flowline_pipeline::drag::classify_with`).
    public static func classify(
        distance: Double,
        duration: TimeInterval,
        isTrackpad: Bool = false,
        configuration: Configuration = Configuration()
    ) -> PressRelease {
        let distance = distance.isFinite ? max(0, distance) : 0
        let clickRadius = isTrackpad ? configuration.trackpadClickRadius : configuration.clickRadius
        // Inside the deadzone movement is ignored: plain click.
        guard distance >= clickRadius else { return .click }
        // Unambiguous displacement: always a drag.
        if distance > configuration.dragRadius { return .drag }
        // Held past the click radius: deliberate even when slow. Strict `>`
        // keeps a release exactly on the boundary in the velocity gate.
        if duration > configuration.longHoldDuration { return .drag }
        // Mid-band: velocity-gated.
        if pointerVelocity(distance: distance, duration: duration) > configuration.velocityThresholdPxPerSec {
            return .drag
        }
        return .jitter
    }

    public func handleMouseDown(at point: CGPoint, timestamp: Date = Date()) {
        lock.withLock {
            downPoint = point
            downTimestamp = timestamp
        }
    }

    /// Classifies the completed gesture. Returns `nil` when no press was
    /// tracked (e.g. the app started mid-drag).
    public func handleMouseUp(
        at point: CGPoint,
        timestamp: Date = Date(),
        isTrackpad: Bool = false
    ) -> DragGesture? {
        let tracked: (point: CGPoint, timestamp: Date)? = lock.withLock {
            let tracked = downPoint.map { ($0, downTimestamp ?? timestamp) }
            downPoint = nil
            downTimestamp = nil
            return tracked
        }

        guard let tracked = tracked else { return nil }

        let dx = Double(point.x - tracked.point.x)
        let dy = Double(point.y - tracked.point.y)
        let distance = (dx * dx + dy * dy).squareRoot()
        let duration = timestamp.timeIntervalSince(tracked.timestamp)

        return DragGesture(
            start: tracked.point,
            end: point,
            distance: distance,
            duration: duration,
            isDrag: Self.classify(
                distance: distance,
                duration: duration,
                isTrackpad: isTrackpad,
                configuration: configuration
            ) == .drag
        )
    }

    /// True when any press is currently being tracked.
    public var isTracking: Bool {
        lock.withLock { downPoint != nil }
    }
}
