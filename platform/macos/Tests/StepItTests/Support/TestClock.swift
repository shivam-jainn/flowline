import Foundation
import StepItStorage
import StepItCaptureAPI
import StepItMacCapture
import StepItPublishing
import StepItAIGateway
import StepItPermissions
import StepItIR
import StepItPipeline
import StepItEngine
import XCTest
@testable import StepItFixtures

/// Advanceable `TimeProvider` for debounce / gesture-notice tests.
///
/// `sleep(for:)` suspends until `advance(by:)` pushes the clock past the
/// deadline (or the surrounding task is cancelled) — no real sleeps.
final class TestClock: TimeProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    private var sleepers: [UUID: (deadline: Date, continuation: CheckedContinuation<Void, Never>)] = [:]

    init(start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.current = start
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    /// Moves the clock forward and wakes every sleeper whose deadline passed.
    func advance(by interval: TimeInterval) {
        var due: [CheckedContinuation<Void, Never>] = []
        lock.lock()
        current = current.addingTimeInterval(interval)
        let now = current
        for (id, sleeper) in sleepers where sleeper.deadline <= now {
            due.append(sleeper.continuation)
            sleepers.removeValue(forKey: id)
        }
        lock.unlock()
        due.forEach { $0.resume() }
    }

    func sleep(for interval: TimeInterval) async throws {
        guard interval > 0 else { return }
        let deadline = now.addingTimeInterval(interval)
        let id = UUID()

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                if current >= deadline {
                    lock.unlock()
                    continuation.resume()
                } else {
                    sleepers[id] = (deadline, continuation)
                    lock.unlock()
                }
            }
        } onCancel: {
            resumeSleeper(id)
        }
    }

    private func resumeSleeper(_ id: UUID) {
        lock.lock()
        let sleeper = sleepers.removeValue(forKey: id)
        lock.unlock()
        sleeper?.continuation.resume()
    }
}
