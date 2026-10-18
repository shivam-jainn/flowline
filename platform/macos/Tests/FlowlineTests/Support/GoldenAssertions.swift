import Foundation
import FlowlineStorage
import FlowlineCaptureAPI
import FlowlineMacCapture
import FlowlinePublishing
import FlowlineAIGateway
import FlowlinePermissions
import FlowlineIR
import FlowlinePipeline
import FlowlineEngine
import XCTest

/// Phase 0 — golden / determinism / leak assertions shared by all data-line tests.
///
/// Every Phase 7–22 exit gate that says "byte-identical", "round-trips", or
/// "no raw secret survives" maps to exactly one helper here, so gates stay
/// comparable across phases.
enum GoldenAssertions {

    /// Canonical JSON: sorted keys, no whitespace, fixed date encoding.
    /// Byte-compare THIS, never `JSONEncoder()` defaults (key order is unstable).
    static func canonicalJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(value)
    }

    static func assertByteStable<T: Encodable>(
        _ value: T,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let once = try canonicalJSON(value)
        let twice = try canonicalJSON(value)
        XCTAssertEqual(once, twice, "Encoding is not byte-stable", file: file, line: line)
    }

    static func assertJSONRoundTrip<T: Codable & Equatable>(
        _ value: T,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let data = try canonicalJSON(value)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(T.self, from: data)
        XCTAssertEqual(decoded, value, "Round-trip changed the value", file: file, line: line)
    }

    /// Fails if any seeded secret (or its payload) appears verbatim in `artifacts`.
    /// Pass `artifacts` = every generated string/file content (projections,
    /// manifests, reports, logs). This is the Phase 9 / cross-cutting
    /// "no raw secrets" invariant as a one-liner.
    static func assertNoRawSecrets(
        in artifacts: [String],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for secret in DataLineFixtures.SeededSecrets.all {
            for artifact in artifacts {
                XCTAssertFalse(
                    artifact.contains(secret),
                    "Raw secret leaked into artifact: \(secret.prefix(12))…",
                    file: file, line: line
                )
            }
        }
    }

    /// Redacted placeholder that MUST appear instead of the secret.
    static let redactionPlaceholderPrefix = "{{secret:"

    static func assertPlaceholders(
        in text: String,
        count expected: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let found = text.components(separatedBy: redactionPlaceholderPrefix).count - 1
        XCTAssertEqual(found, expected, "Expected \(expected) redaction placeholders", file: file, line: line)
    }

    /// Determinism: run `build` twice, byte-compare. Phase 17's
    /// "same filter + inputs ⇒ byte-identical dataset" is this helper.
    static func assertDeterministic(
        _ build: () throws -> Data,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertEqual(try build(), try build(), "Rebuild was not byte-identical", file: file, line: line)
    }
}
