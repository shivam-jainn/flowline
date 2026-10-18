import Foundation
import FlowlineIR

// MARK: - Session store protocol (owns: FlowlineStorage, R/M1-04)
//
// Every public method of `SessionStore`, so the engine and surfaces can depend
// on the abstraction. Settings persistence moved out in R/M1-07 (the
// aggregate lives in `FlowlineEngine`; JSON load/save is owned by the app
// composition layer via `SettingsFileStore`, reusing `settingsURL` below).

/// Abstract session persistence. Conformed to by `SessionStore`.
public protocol SessionStoreProtocol: Sendable {
    var baseDirectory: URL { get }
    var sessionsDirectory: URL { get }
    var settingsURL: URL { get }

    func sessionDirectory(for id: String) -> URL
    func mediaDirectory(for id: String) -> URL
    func exportsDirectory(for id: String) -> URL
    func webExportDirectory(for id: String) -> URL

    func saveSession(_ session: StepSession) throws
    func loadSession(id: String) throws -> StepSession
    func listSessions() -> [StepSession]
    func deleteSession(id: String) throws

    func saveMedia(data: Data, sessionID: String, filename: String) throws -> String
    func resolveMediaPath(sessionID: String, relativePath: String) -> URL
}
