import Foundation
import StepItIR

public final class SessionStore: SessionStoreProtocol, @unchecked Sendable {
    public static let shared = SessionStore()

    public let baseDirectory: URL
    private let gateway: any FilesystemGateway
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        customBaseDirectory: URL? = nil,
        gateway: any FilesystemGateway = LiveFilesystemGateway()
    ) {
        if let custom = customBaseDirectory {
            self.baseDirectory = custom
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.baseDirectory = appSupport.appendingPathComponent("StepIt", isDirectory: true)
        }
        self.gateway = gateway

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
        try gateway.createDirectory(at: url)
    }

    // MARK: - Sessions

    public func saveSession(_ session: StepSession) throws {
        let dir = sessionDirectory(for: session.id)
        try ensureDirectoryExists(dir)
        try ensureDirectoryExists(mediaDirectory(for: session.id))
        try ensureDirectoryExists(exportsDirectory(for: session.id))

        let jsonURL = dir.appendingPathComponent("session.json")
        let data = try encoder.encode(session)
        try gateway.writeData(data, to: jsonURL)
    }

    public func loadSession(id: String) throws -> StepSession {
        let jsonURL = sessionDirectory(for: id).appendingPathComponent("session.json")
        let data = try gateway.readData(at: jsonURL)
        return try decoder.decode(StepSession.self, from: data)
    }

    public func listSessions() -> [StepSession] {
        guard let items = try? gateway.contentsOfDirectory(at: sessionsDirectory) else {
            return []
        }

        var sessions: [StepSession] = []
        for item in items {
            let jsonURL = item.appendingPathComponent("session.json")
            if let data = try? gateway.readData(at: jsonURL),
               let session = try? decoder.decode(StepSession.self, from: data) {
                sessions.append(session)
            }
        }

        return sessions.sorted { $0.startedAt > $1.startedAt }
    }

    public func deleteSession(id: String) throws {
        let dir = sessionDirectory(for: id)
        if gateway.fileExists(at: dir) {
            try gateway.removeItem(at: dir)
        }
    }

    // MARK: - Media Storage

    public func saveMedia(data: Data, sessionID: String, filename: String) throws -> String {
        let mediaDir = mediaDirectory(for: sessionID)
        try ensureDirectoryExists(mediaDir)
        let fileURL = mediaDir.appendingPathComponent(filename)
        try gateway.writeData(data, to: fileURL)
        return "media/\(filename)"
    }

    public func resolveMediaPath(sessionID: String, relativePath: String) -> URL {
        sessionDirectory(for: sessionID).appendingPathComponent(relativePath)
    }
}
