import Foundation

/// Single seam for timestamps and timing (debounce / gesture-notice dismissal)
/// so engine tests can drive time deterministically.
public protocol TimeProvider: Sendable {
    var now: Date { get }
    /// Suspends for `interval` seconds. Cancellable via task cancellation.
    func sleep(for interval: TimeInterval) async throws
}

/// Production implementation: wall clock + `Task.sleep`.
public struct SystemTimeProvider: TimeProvider {
    public init() {}

    public var now: Date { Date() }

    public func sleep(for interval: TimeInterval) async throws {
        let nanoseconds = UInt64(max(0, interval) * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}
