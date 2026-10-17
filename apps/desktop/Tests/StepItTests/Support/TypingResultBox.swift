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
@testable import StepItFixtures

/// Thread-safe collector for async callback results (typing batches).
final class TypingResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [TypingBatchResult] = []

    var results: [TypingBatchResult] {
        lock.lock()
        defer { lock.unlock() }
        return collected
    }

    var last: TypingBatchResult? { results.last }

    func append(_ result: TypingBatchResult) {
        lock.lock()
        collected.append(result)
        lock.unlock()
    }
}
