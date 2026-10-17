import Foundation
import StepItIR
import StepItPipeline

/// Tracks press → release geometry and classifies click vs. deliberate drag
/// (Phase 2, T8 / B6).
///
/// Pure value-in/value-out logic (no AppKit), so the distance and duration
/// thresholds are unit-testable with synthetic coordinates and timestamps.
public final class MouseDragDetector: @unchecked Sendable {

    public struct Configuration: Sendable {
        /// Euclidean distance (in screen points) beyond which a drag is recorded.
        public var minimumDistance: Double
        /// Minimum press-to-release duration. Filters accidental micro-movement
        /// during ordinary clicks.
        public var minimumDuration: TimeInterval

        public init(minimumDistance: Double = 15.0, minimumDuration: TimeInterval = 0.15) {
            self.minimumDistance = minimumDistance
            self.minimumDuration = minimumDuration
        }
    }

    /// Result of a completed press → release gesture.
    public struct DragGesture: Sendable, Equatable {
        public var start: CGPoint
        public var end: CGPoint
        public var distance: Double
        public var duration: TimeInterval
        /// `true` when both thresholds were exceeded — emit `.mouseDrag`.
        public var isDrag: Bool
    }

    public let configuration: Configuration

    private let lock = NSLock()
    private var downPoint: CGPoint?
    private var downTimestamp: Date?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public func handleMouseDown(at point: CGPoint, timestamp: Date = Date()) {
        lock.withLock {
            downPoint = point
            downTimestamp = timestamp
        }
    }

    /// Classifies the completed gesture. Returns `nil` when no press was
    /// tracked (e.g. the app started mid-drag).
    public func handleMouseUp(at point: CGPoint, timestamp: Date = Date()) -> DragGesture? {
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
            isDrag: distance > configuration.minimumDistance && duration > configuration.minimumDuration
        )
    }

    /// True when any press is currently being tracked.
    public var isTracking: Bool {
        lock.withLock { downPoint != nil }
    }
}
