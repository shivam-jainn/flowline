import Foundation

/// Extracts the inline 200 ms click guard into a testable value type driven by
/// event timestamps.
///
/// Parity with the pre-Phase-1 coordinator's handleAction: a rejected event does **not**
/// move the window forward; only accepted events do.
public struct EventDebouncer: Sendable {
    public let minInterval: TimeInterval
    private var lastAcceptedAt: Date

    public init(minInterval: TimeInterval = 0.20, start: Date = .distantPast) {
        self.minInterval = minInterval
        self.lastAcceptedAt = start
    }

    /// Returns `true` when this timestamp is outside the debounce window.
    public mutating func shouldAccept(at date: Date) -> Bool {
        guard date.timeIntervalSince(lastAcceptedAt) > minInterval else {
            return false
        }
        lastAcceptedAt = date
        return true
    }

    public mutating func reset() {
        lastAcceptedAt = .distantPast
    }
}
