import XCTest
import Foundation
import FlowlineFFI

/// R/M2-07: UniFFI binding proof — Swift calls the Rust core through the
/// generated bindings and gets byte-identical answers.
final class PhaseR09FFITests: XCTestCase {
    func testClassifyThroughFFI() {
        XCTAssertEqual(classifyText(text: "git status", appName: "Terminal", windowTitle: "zsh"), "terminal")
        XCTAssertEqual(classifyText(text: "hello", appName: "TextEdit", windowTitle: "Untitled"), "text")
    }

    func testSessionRoundTripThroughFFI() throws {
        let session = """
        {"id":"sess_ffi01","startedAt":"2026-03-01T10:00:00Z","title":"FFI",\
        "theme":"modern-minimal","mediaMode":"hybrid","steps":[],"exports":{}}
        """
        let back = try sessionRoundTrip(sessionJson: session)
        XCTAssertEqual(
            back.replacingOccurrences(of: " ", with: ""),
            session.replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "\n", with: "")
        )
        XCTAssertTrue(back.contains("sess_ffi01"))
    }

    func testManifestValidationThroughFFI() {
        let manifest = """
        {"id":"windows","version":"1.0.0","capabilities":["snapshots"],\
        "minimumHostVersion":"r-m1"}
        """
        XCTAssertTrue(manifestValidForHost(manifestJson: manifest, hostVersion: "r-m1"))
        XCTAssertFalse(manifestValidForHost(manifestJson: manifest, hostVersion: "r-m0"))
    }

    func testSecretsThroughFFI() {
        let hits = detectSecrets(text: "key sk-1234567890abcdef1234567890abcdef12 end")
        XCTAssertTrue(hits.contains("openAIAPIKey"), hits)
    }
}
