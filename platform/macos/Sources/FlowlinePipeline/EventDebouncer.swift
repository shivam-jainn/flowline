import Foundation
import FlowlineIR

/// Extracts the inline 200 ms click guard into a testable value type driven by
/// event timestamps.
///
/// Parity with the pre-Phase-1 coordinator's handleAction: a rejected event does **not**
/// move the window forward; only accepted events do.
///
/// `shouldAcceptClick` adds pointer disambiguation for click steps: the
/// window adapts to inter-click pointer velocity
/// (`clamp(200 * (1.5 - min(vel / 10, 0.8)), 80, 400)ms`), close + fast
/// repeats are bounced, and OS-reported doubles inside 500 ms are accepted
/// as the double (never suppressed as bounce, never split into two singles).
/// Rejected bounces still hold the window.
public struct EventDebouncer: Sendable {
    public let minInterval: TimeInterval
    private var lastAcceptedAt: Date
    private var lastAcceptedLocation: Point2D?

    /// Distance below which a fast repeat is contact bounce, not intent.
    public static let bounceRadius: Double = 6.0
    /// OS double-click coalescing window.
    public static let doubleClickWindow: TimeInterval = 0.5

    public init(minInterval: TimeInterval = 0.20, start: Date = .distantPast) {
        self.minInterval = minInterval
        self.lastAcceptedAt = start
    }

    /// Mean press → release velocity in pt/s. Non-positive durations yield
    /// `.infinity` for a real displacement (an instant teleport is fast, not
    /// still) and `0` for a true no-move. Single implementation shared with
    /// `MouseDragDetector` (which lives downstream in `FlowlineMacCapture`).
    public static func pointerVelocity(distance: Double, duration: TimeInterval) -> Double {
        guard distance > 0 else { return 0 }
        guard duration > 0 else { return .infinity }
        return distance / duration
    }

    /// Velocity-aware window. A `nil` velocity (unknown previous point)
    /// falls back to `base` so location-less replays keep the legacy window.
    public static func adaptiveInterval(base: TimeInterval, velocityPxPerSec: Double?) -> TimeInterval {
        guard let velocity = velocityPxPerSec else { return base }
        let clamped = min(max(velocity, 0) / 10.0, 0.8)
        return min(max(base * (1.5 - clamped), 0.08), 0.40)
    }

    /// Returns `true` when this timestamp is outside the debounce window.
    ///
    /// Legacy fixed-window path. Click steps should prefer
    /// `shouldAcceptClick`.
    public mutating func shouldAccept(at date: Date) -> Bool {
        guard date.timeIntervalSince(lastAcceptedAt) > minInterval else {
            return false
        }
        lastAcceptedAt = date
        return true
    }

    /// Velocity-aware click gate.
    ///
    /// - First click: always accepted.
    /// - OS double (`osClickCount >= 2`) within 500 ms of the accepted
    ///   click: accepted as the double — not suppressed, not a second single.
    /// - Location within 6 pt and `dt <= adaptiveWindow`: bounce — rejected,
    ///   and the window does **not** move.
    /// - Otherwise: distinct click, accepted.
    /// - Locations unknown: falls back to the legacy time-only window.
    public mutating func shouldAcceptClick(
        at date: Date,
        location: Point2D?,
        osClickCount: Int
    ) -> Bool {
        let dt = date.timeIntervalSince(lastAcceptedAt)
        // First click (or reset state): always accepted.
        guard lastAcceptedAt != .distantPast else {
            lastAcceptedAt = date
            lastAcceptedLocation = location
            return true
        }
        // Out-of-order clock: never suppress, never move the window back.
        guard dt >= 0 else { return true }
        // OS-reported double inside the system window is the double — accept
        // even when it lands inside the bounce window.
        if osClickCount >= 2 && dt < Self.doubleClickWindow {
            lastAcceptedAt = date
            lastAcceptedLocation = location
            return true
        }
        switch (lastAcceptedLocation, location) {
        case let (.some(previous), .some(current)):
            let dx = current.x - previous.x
            let dy = current.y - previous.y
            let distance = (dx * dx + dy * dy).squareRoot()
            let velocity: Double? = Self.pointerVelocity(distance: distance, duration: dt)
            let window = Self.adaptiveInterval(base: minInterval, velocityPxPerSec: velocity)
            guard distance >= Self.bounceRadius || dt > window else { return false }
            lastAcceptedAt = date
            lastAcceptedLocation = location
            return true
        case _:
            let window = Self.adaptiveInterval(base: minInterval, velocityPxPerSec: nil)
            guard dt > window else { return false }
            lastAcceptedAt = date
            lastAcceptedLocation = location
            return true
        }
    }

    public mutating func reset() {
        lastAcceptedAt = .distantPast
        lastAcceptedLocation = nil
    }
}
