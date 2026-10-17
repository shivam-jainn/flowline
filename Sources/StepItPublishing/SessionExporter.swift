import Foundation

/// Exported artifact descriptor. Pure data — rendering happens in Native.
public struct ExportArtifact: Sendable, Equatable {
    public var url: URL?
    public var relativePath: String
    public var mimeType: String
    public init(url: URL? = nil, relativePath: String, mimeType: String) {
        self.url = url
        self.relativePath = relativePath
        self.mimeType = mimeType
    }
}

/// Session exporter plugin contract (Phase R §2).
/// Uses a type-erased session (`Any`) until m1-02 moves `StepSession` into
/// StepItIR; m1-06 binds the concrete type without changing call-site shape.
public protocol SessionExporter: AnyObject, Sendable {
    var exporterID: String { get }
    func export(session: Any, to directory: URL) throws -> ExportArtifact
}
