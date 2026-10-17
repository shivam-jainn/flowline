import Foundation

/// Injected network transport (Phase R §4). Core builds prompts/payloads;
/// Native (or tests) provides the socket. `URLSession` conforms at the
/// composition root / in tests — never inside Core logic.
public protocol NetworkTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}
