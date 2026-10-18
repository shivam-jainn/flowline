import Foundation
import FlowlineIR
import FlowlineStorage

public enum AIGatewayError: LocalizedError, Sendable {
    case invalidURL(String)
    case httpError(statusCode: Int, message: String)
    case decodingError(String)
    case emptyResponse
    case missingAPIKey
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid Gateway URL: \(url)"
        case .httpError(let code, let msg):
            return "AI Gateway returned HTTP \(code): \(msg)"
        case .decodingError(let msg):
            return "Failed to decode AI response: \(msg)"
        case .emptyResponse:
            return "AI Gateway returned an empty response."
        case .missingAPIKey:
            return "An API key is required for cloud AI. Add one in Settings, or switch to a local model — local models need no key."
        }
    }
}

public final class AIGatewayClient: @unchecked Sendable {
    public static let shared = AIGatewayClient()
    
    private let urlSession: URLSession
    private let payloadBuilder: MultimodalPayloadBuilder

    public init(urlSession: URLSession = .shared, store: any SessionStoreProtocol = SessionStore()) {
        self.urlSession = urlSession
        self.payloadBuilder = MultimodalPayloadBuilder(store: store)
    }
    
    public func generateStream(
        session: StepSession,
        settings: GatewaySettings,
        style: DocumentationStyle = .sopGuide,
        customInstructions: String? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var endpointStr = settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    if endpointStr.hasSuffix("/") {
                        endpointStr.removeLast()
                    }
                    if !endpointStr.hasSuffix("/chat/completions") {
                        endpointStr += "/chat/completions"
                    }
                    
                    guard let url = URL(string: endpointStr) else {
                        continuation.finish(throwing: AIGatewayError.invalidURL(endpointStr))
                        return
                    }
                    
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    
                    if !settings.apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
                        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
                    } else if settings.needsAPIKey {
                        // Cloud providers (OpenRouter, OpenAI-compatible) fail
                        // here with an actionable error; local providers
                        // (Ollama / LM Studio / CLI) need no key.
                        continuation.finish(throwing: AIGatewayError.missingAPIKey)
                        return
                    }
                    
                    // Gateway identification headers for OpenRouter / Portkey
                    request.setValue("https://github.com/flowline/flowline", forHTTPHeaderField: "HTTP-Referer")
                    request.setValue("Flowline macOS", forHTTPHeaderField: "X-Title")
                    
                    let chatPayload = payloadBuilder.buildRequest(
                        session: session,
                        settings: settings,
                        style: style,
                        customInstructions: customInstructions
                    )
                    
                    let jsonData = try JSONEncoder().encode(chatPayload)
                    request.httpBody = jsonData
                    
                    let (asyncBytes, response) = try await urlSession.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: AIGatewayError.emptyResponse)
                        return
                    }
                    
                    if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                        var errBody = ""
                        for try await line in asyncBytes.lines {
                            errBody += line
                        }
                        continuation.finish(throwing: AIGatewayError.httpError(statusCode: httpResponse.statusCode, message: errBody))
                        return
                    }
                    
                    // Process SSE stream
                    for try await line in asyncBytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        guard trimmed.hasPrefix("data:") else { continue }
                        
                        let dataContent = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if dataContent == "[DONE]" {
                            break
                        }
                        
                        guard let data = dataContent.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let first = choices.first else {
                            continue
                        }
                        
                        // Extract delta content
                        if let delta = first["delta"] as? [String: Any],
                           let content = delta["content"] as? String {
                            continuation.yield(content)
                        } else if let message = first["message"] as? [String: Any],
                                  let content = message["content"] as? String {
                            continuation.yield(content)
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
