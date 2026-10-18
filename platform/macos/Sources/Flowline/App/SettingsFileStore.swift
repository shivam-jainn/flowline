import Foundation
import FlowlineEngine
import FlowlineStorage

/// JSON settings persistence owned by the composition layer (R/M1-07).
///
/// Reuses `SessionStore.settingsURL` so the on-disk location never drifts
/// from the store's layout; the store itself stays a pure session/media
/// gateway with no settings API.
public struct SettingsFileStore: Sendable {
    public var url: URL

    public init(url: URL) {
        self.url = url
    }

    public init(store: SessionStore) {
        self.url = store.settingsURL
    }

    /// Loads persisted settings, falling back to environment-aware defaults
    /// (and writing them back) when no file exists or decoding fails.
    public func load() -> FlowlineSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(FlowlineSettings.self, from: data) else {
            let defaults = FlowlineSettings.defaultSettings
            try? save(defaults)
            return defaults
        }
        return settings
    }

    public func save(_ settings: FlowlineSettings) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(settings)
        try data.write(to: url, options: .atomic)
    }
}
