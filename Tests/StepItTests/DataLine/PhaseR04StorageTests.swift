import XCTest
import StepItPipeline
import StepItEngine
import StepItCaptureAPI
import StepItMacCapture
import StepItPublishing
import StepItAIGateway
import StepItPermissions
import Foundation
import StepItIR
import StepItCore
import StepItStorage

/// R/M1-04: storage protocol + gateway proof. The fake gateway round-trips
/// byte-identical payloads to the live disk gateway.
final class PhaseR04StorageTests: XCTestCase {
    private func sampleSession() -> StepSession {
        StepSession(title: "storage parity")
    }

    func testFakeGatewayRoundTripMatchesDisk() throws {
        let session = sampleSession()

        let fake = InMemoryFilesystemGateway()
        let memStore = SessionStore(
            customBaseDirectory: URL(fileURLWithPath: "/mem/StepIt", isDirectory: true),
            gateway: fake)
        try memStore.saveSession(session)
        let memBytes = try fake.readData(
            at: memStore.sessionDirectory(for: session.id).appendingPathComponent("session.json"))

        let diskBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhaseR04-\(UUID().uuidString)", isDirectory: true)
        let diskStore = SessionStore(customBaseDirectory: diskBase)
        try diskStore.saveSession(session)
        let diskBytes = try Data(
            contentsOf: diskStore.sessionDirectory(for: session.id).appendingPathComponent("session.json"))
        try? FileManager.default.removeItem(at: diskBase)

        XCTAssertEqual(memBytes, diskBytes)
        let roundTripDecoder = JSONDecoder()
        roundTripDecoder.dateDecodingStrategy = .iso8601
        let back = try roundTripDecoder.decode(StepSession.self, from: memBytes)
        XCTAssertEqual(back.title, "storage parity")
    }

    func testStoreIsSubstitutableViaProtocol() throws {
        let fake = InMemoryFilesystemGateway()
        let store: any SessionStoreProtocol = SessionStore(
            customBaseDirectory: URL(fileURLWithPath: "/mem/proto", isDirectory: true),
            gateway: fake)
        let session = sampleSession()
        try store.saveSession(session)
        XCTAssertEqual(try store.loadSession(id: session.id).id, session.id)
        XCTAssertEqual(store.listSessions().count, 1)
        let rel = try store.saveMedia(data: Data([0x1, 0x2]), sessionID: session.id, filename: "a.png")
        XCTAssertEqual(rel, "media/a.png")
        try store.deleteSession(id: session.id)
        XCTAssertEqual(store.listSessions().count, 0)
    }
}
