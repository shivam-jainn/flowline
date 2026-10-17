import Foundation
import StepItIR
import StepItCore

// MARK: - Session store protocol (owns: StepItStorage, R/M1-04)
//
// Every public method of `SessionStore`, so the engine and surfaces can depend
// on the abstraction. `StepItSettings` still lives in StepItCore (m1-07 moves
// it next to its owning modules); the protocol references it transitionally.

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

    func loadSettings() -> StepItSettings
    func saveSettings(_ settings: StepItSettings) throws
}
