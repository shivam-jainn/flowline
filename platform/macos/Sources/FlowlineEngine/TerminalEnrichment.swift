import Foundation
import FlowlineCaptureAPI
import FlowlineIR
import FlowlinePipeline

// MARK: - Privacy and terminal enrichment (terminal half) (R/M1-03 reducer split; verbatim logic from RecorderWorkflowEngine)

extension RecorderWorkflowEngine {
    // MARK: - Terminal commands (T4/T5)

    internal func resolveWorkingDirectory(for context: RawElementContext?) async -> String? {
        guard let provider = driver as? TerminalContextProviding else { return nil }
        return await provider.inspectTerminalWorkingDirectory(
            bundleId: context?.bundleIdentifier,
            pid: nil,
            windowTitle: context?.windowTitle
        )
    }

    internal func handleTerminalCommand(command: String, workingDirectory: String?) async {
        await withStepGate {
            await produceTerminalCommandStep(command: command, workingDirectory: workingDirectory)
        }
    }

}
