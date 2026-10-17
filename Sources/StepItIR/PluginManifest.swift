import Foundation

/// Shared plugin manifest (Phase R §2). Every capture driver, exporter and
/// AI provider ships one; hosts assert minimum versions at startup.
public struct PluginManifest: Codable, Sendable, Equatable {
    public var id: String
    public var version: String
    public var capabilities: [String]
    public var minimumHostVersion: String

    public init(id: String, version: String, capabilities: [String] = [], minimumHostVersion: String = "r-m1") {
        self.id = id
        self.version = version
        self.capabilities = capabilities
        self.minimumHostVersion = minimumHostVersion
    }

    public func validateHost(version hostVersion: String) -> Bool {
        hostVersion.compare(minimumHostVersion, options: .numeric) != .orderedAscending
    }

    public func supports(_ capability: String) -> Bool {
        capabilities.contains(capability)
    }
}
