import Foundation
import StepItIR
import StepItPipeline
@testable import StepItCore

/// Collects `RecorderSnapshot`s from the engine's stream and lets tests await
/// a predicate instead of racing.
final class SnapshotProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [RecorderSnapshot] = []
    private var task: Task<Void, Never>?

    func attach(to engine: RecorderWorkflowEngine) async {
        let stream = await engine.snapshotStream()
        task = Task { [weak self] in
            for await snapshot in stream {
                self?.append(snapshot)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    var snapshots: [RecorderSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return collected
    }

    var last: RecorderSnapshot? { snapshots.last }

    private func append(_ snapshot: RecorderSnapshot) {
        lock.lock()
        collected.append(snapshot)
        lock.unlock()
    }

    @discardableResult
    func waitUntil(
        timeout: TimeInterval = 2.0,
        _ predicate: @escaping (RecorderSnapshot?) -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate(last) { return true }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return predicate(last)
    }

    @discardableResult
    func waitUntilState(_ state: RecordingState, timeout: TimeInterval = 2.0) async -> Bool {
        await waitUntil(timeout: timeout) { $0?.state == state }
    }

    @discardableResult
    func waitForStepCount(_ count: Int, timeout: TimeInterval = 2.0) async -> Bool {
        await waitUntil(timeout: timeout) { $0?.stepCount == count }
    }
}
