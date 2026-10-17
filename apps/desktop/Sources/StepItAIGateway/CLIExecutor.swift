import Foundation

public final class CLIExecutor: @unchecked Sendable {
    public static let shared = CLIExecutor()
    
    public init() {}
    
    public func executeStream(
        command: String,
        arguments: [String],
        standardInput: String? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stdinPipe = Pipe()
            
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
            process.standardOutput = stdoutPipe
            process.standardError = stdoutPipe
            
            if standardInput != nil {
                process.standardInput = stdinPipe
            }
            
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                continuation.yield(text)
            }
            
            process.terminationHandler = { _ in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                continuation.finish()
            }
            
            do {
                try process.run()
                
                if let input = standardInput, let inData = input.data(using: .utf8) {
                    stdinPipe.fileHandleForWriting.write(inData)
                    try? stdinPipe.fileHandleForWriting.close()
                }
            } catch {
                continuation.finish(throwing: error)
            }
            
            continuation.onTermination = { @Sendable _ in
                if process.isRunning {
                    process.terminate()
                }
            }
        }
    }
}
