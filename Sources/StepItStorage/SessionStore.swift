import Foundation

public final class SessionStore: @unchecked Sendable {
    public static let shared = SessionStore()
    
    public let baseDirectory: URL
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    public init(customBaseDirectory: URL? = nil) {
        if let custom = customBaseDirectory {
            self.baseDirectory = custom
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.baseDirectory = appSupport.appendingPathComponent("StepIt", isDirectory: true)
        }
        
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        
        try? ensureDirectoryExists(baseDirectory)
        try? ensureDirectoryExists(sessionsDirectory)
    }
    
    public var sessionsDirectory: URL {
        baseDirectory.appendingPathComponent("Sessions", isDirectory: true)
    }
    
    public var settingsURL: URL {
        baseDirectory.appendingPathComponent("Settings.json")
    }
    
    public func sessionDirectory(for id: String) -> URL {
        sessionsDirectory.appendingPathComponent(id, isDirectory: true)
    }
    
    public func mediaDirectory(for id: String) -> URL {
        sessionDirectory(for: id).appendingPathComponent("media", isDirectory: true)
    }
    
    public func exportsDirectory(for id: String) -> URL {
        sessionDirectory(for: id).appendingPathComponent("exports", isDirectory: true)
    }
    
    public func webExportDirectory(for id: String) -> URL {
        exportsDirectory(for: id).appendingPathComponent("web", isDirectory: true)
    }
    
    private func ensureDirectoryExists(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Sessions
    
    public func saveSession(_ session: StepSession) throws {
        let dir = sessionDirectory(for: session.id)
        try ensureDirectoryExists(dir)
        try ensureDirectoryExists(mediaDirectory(for: session.id))
        try ensureDirectoryExists(exportsDirectory(for: session.id))
        
        let jsonURL = dir.appendingPathComponent("session.json")
        let data = try encoder.encode(session)
        try data.write(to: jsonURL, options: .atomic)
    }
    
    public func loadSession(id: String) throws -> StepSession {
        let jsonURL = sessionDirectory(for: id).appendingPathComponent("session.json")
        let data = try Data(contentsOf: jsonURL)
        return try decoder.decode(StepSession.self, from: data)
    }
    
    public func listSessions() -> [StepSession] {
        guard let items = try? fileManager.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        
        var sessions: [StepSession] = []
        for item in items where item.hasDirectoryPath {
            let jsonURL = item.appendingPathComponent("session.json")
            if let data = try? Data(contentsOf: jsonURL),
               let session = try? decoder.decode(StepSession.self, from: data) {
                sessions.append(session)
            }
        }
        
        return sessions.sorted { $0.startedAt > $1.startedAt }
    }
    
    public func deleteSession(id: String) throws {
        let dir = sessionDirectory(for: id)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
    }
    
    // MARK: - Media Storage
    
    public func saveMedia(data: Data, sessionID: String, filename: String) throws -> String {
        let mediaDir = mediaDirectory(for: sessionID)
        try ensureDirectoryExists(mediaDir)
        let fileURL = mediaDir.appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)
        return "media/\(filename)"
    }
    
    public func resolveMediaPath(sessionID: String, relativePath: String) -> URL {
        sessionDirectory(for: sessionID).appendingPathComponent(relativePath)
    }
    
    // MARK: - Settings
    
    public func loadSettings() -> StepItSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? decoder.decode(StepItSettings.self, from: data) else {
            let defaultSettings = StepItSettings.defaultSettings
            try? saveSettings(defaultSettings)
            return defaultSettings
        }
        return settings
    }
    
    public func saveSettings(_ settings: StepItSettings) throws {
        try ensureDirectoryExists(baseDirectory)
        let data = try encoder.encode(settings)
        try data.write(to: settingsURL, options: .atomic)
    }
}
