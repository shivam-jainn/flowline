import Foundation
import FlowlineIR

/// AI provider plugin contract (Phase R §2). Pure request/response models;
/// transport is injected (see NetworkTransport.swift).
public struct GatewayRequest: Sendable, Equatable {
    public var prompt: String
    public var model: String
    public var payload: Data?
    public init(prompt: String, model: String, payload: Data? = nil) {
        self.prompt = prompt
        self.model = model
        self.payload = payload
    }
}

public struct GatewayResponse: Sendable, Equatable {
    public var text: String
    public init(text: String) { self.text = text }
}

public protocol GatewayProvider: AnyObject, Sendable {
    var providerID: String { get }
    func complete(request: GatewayRequest) async throws -> GatewayResponse
}
