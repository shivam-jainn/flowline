import Foundation
import StepItIR
import StepItPipeline
import StepItCaptureAPI
import StepItPublishing
import StepItAIGateway

// MARK: - No-op capture driver (composition-local double)

/// Headless no-op driver registered as `"noop"`. Produces/consumes nothing;
/// used for dry runs, tests and environments without capture entitlements.
public final class StepItNoopDriver: CaptureDriver, @unchecked Sendable {
    public let platformIdentifier = "noop"
    public let capabilities: CaptureCapabilities = .mockFull
    public let eventStream: AsyncStream<RawInputEvent>
    private let continuation: AsyncStream<RawInputEvent>.Continuation

    public init() {
        var cont: AsyncStream<RawInputEvent>.Continuation!
        self.eventStream = AsyncStream<RawInputEvent> { cont = $0 }
        self.continuation = cont
    }

    public func start() async throws {}
    public func pause() async {}
    public func resume() async {}
    public func stop() async { continuation.finish() }

    public func inspectElement(at point: Point2D) async -> RawElementContext? { nil }
    public func inspectFocusedElement() async -> RawElementContext? { nil }

    public func startClipBuffering(config: ClipBufferConfig) async {}
    public func stopClipBuffering() async {}
    public func captureSnapshot(highlightAt point: Point2D?, stepIndex: Int) async -> FrameSnapshot? { nil }
    public func captureMicroClip(around point: Point2D, postDuration: TimeInterval) async -> ClipAsset? { nil }
}

// MARK: - SessionExporter adapters (module generators → registry entries)

/// Writes `MarkdownExporter` output as `README.md` under the given directory.
public final class MarkdownSessionExporter: SessionExporter, @unchecked Sendable {
    public let exporterID = "markdown"
    private let markdown = MarkdownExporter()
    public init() {}

    public func export(session: Any, to directory: URL) throws -> ExportArtifact {
        guard let session = session as? StepSession else {
            throw NSError(domain: "MarkdownSessionExporter", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Expected StepSession, got \(type(of: session))"
            ])
        }
        let md = markdown.exportMarkdown(session: session, relativeAssetPrefix: "../")
        let url = directory.appendingPathComponent("README.md")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try md.write(to: url, atomically: true, encoding: .utf8)
        return ExportArtifact(url: url, relativePath: "README.md", mimeType: "text/markdown")
    }
}

/// Writes `WebDocGenerator` output as `index.html` under the given directory.
public final class WebDocSessionExporter: SessionExporter, @unchecked Sendable {
    public let exporterID = "webdoc"
    private let webdoc = WebDocGenerator()
    public init() {}

    public func export(session: Any, to directory: URL) throws -> ExportArtifact {
        guard let session = session as? StepSession else {
            throw NSError(domain: "WebDocSessionExporter", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Expected StepSession, got \(type(of: session))"
            ])
        }
        let html = webdoc.generateHTML(session: session)
        let url = directory.appendingPathComponent("index.html")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try html.write(to: url, atomically: true, encoding: .utf8)
        return ExportArtifact(url: url, relativePath: "index.html", mimeType: "text/html")
    }
}

/// Writes a JSON sidecar describing the session for the (async, WebKit-backed)
/// PDF pipeline without rendering. Registered as `"pdf-meta"`.
public final class PDFMetaSessionExporter: SessionExporter, @unchecked Sendable {
    public let exporterID = "pdf-meta"
    public init() {}

    struct PDFMeta: Codable {
        var sessionID: String
        var title: String
        var stepCount: Int
        var theme: String
    }

    public func export(session: Any, to directory: URL) throws -> ExportArtifact {
        guard let session = session as? StepSession else {
            throw NSError(domain: "PDFMetaSessionExporter", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Expected StepSession, got \(type(of: session))"
            ])
        }
        let meta = PDFMeta(
            sessionID: session.id,
            title: session.title,
            stepCount: session.steps.count,
            theme: session.theme.rawValue
        )
        let data = try JSONEncoder().encode(meta)
        let url = directory.appendingPathComponent("guide-meta.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return ExportArtifact(url: url, relativePath: "guide-meta.json", mimeType: "application/json")
    }
}

// MARK: - GatewayProvider adapter (AIGatewayClient → registry entries)

/// `GatewayProvider` backed by the streaming `AIGatewayClient`: collects the
/// token stream into a single response over an ad-hoc session built from the
/// request prompt. Registered per provider id (`openai`/`anthropic`/`ollama`)
/// with matching `GatewaySettings`.
public final class ClientBackedGatewayProvider: GatewayProvider, @unchecked Sendable {
    public let providerID: String
    private let client: AIGatewayClient
    private let settings: GatewaySettings

    public init(providerID: String, client: AIGatewayClient, settings: GatewaySettings) {
        self.providerID = providerID
        self.client = client
        self.settings = settings
    }

    public func complete(request: GatewayRequest) async throws -> GatewayResponse {
        let session = StepSession(
            title: "Ad-hoc Gateway Request",
            steps: [
                Step(
                    index: 1,
                    action: .manual,
                    appName: "StepIt",
                    actionDescription: request.prompt
                )
            ]
        )
        var text = ""
        let stream = client.generateStream(
            session: session,
            settings: settings,
            style: .sopGuide,
            customInstructions: request.prompt
        )
        for try await token in stream {
            text += token
        }
        return GatewayResponse(text: text)
    }
}

// MARK: - Network transport (URLSession conformance at the composition root)

extension URLSession: NetworkTransport {
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request, delegate: nil)
    }
}
