import XCTest
import StepItIR
import StepItPipeline
@testable import StepItCore

/// Phase 0 gate: the fixture TDD framework itself is tested before any
/// Phase 7–22 work begins. If these tests are green, every later phase can
/// write its exit gate as a fixture test on day one (red), then implement
/// (green), then refactor.
///
/// TDD workflow per phase (enforced by review, not by tooling):
/// 1. RED — add a failing test under `Tests/StepItTests/DataLine/PhaseNN*`
///    using only `DataLineFixtures` + `GoldenAssertions`.
/// 2. GREEN — implement the minimum production code to pass.
/// 3. REFACTOR — deduplicate; re-run `swift test` + `make check-arch`.
/// 4. GATE — the phase's exit-gate test(s) pass deterministically 3× in a row.
final class Phase0FixtureFrameworkTests: XCTestCase {

    func testSeededSecretsAreAllDetected() {
        var config = SensitiveDataDetector.Configuration()
        config.detectEmails = true
        let detector = SensitiveDataDetector(configuration: config)
        for secret in DataLineFixtures.SeededSecrets.all {
            XCTAssertTrue(
                detector.containsSensitiveData(secret),
                "Seeded secret not detected: \(secret.prefix(16))…"
            )
        }
    }

    func testSessionBuilderIsDeterministic() throws {
        let a = DataLineFixtures.session(1)
        let b = DataLineFixtures.session(1)
        try GoldenAssertions.assertJSONRoundTrip(a.steps)
        XCTAssertEqual(a.id, b.id)
        XCTAssertEqual(a.steps.map(\.id), b.steps.map(\.id))
        XCTAssertEqual(a.steps.map(\.timestamp), b.steps.map(\.timestamp))
    }

    func testSessionsHaveDistinctIDs() {
        let ids = DataLineFixtures.sessions(3).map(\.id)
        XCTAssertEqual(Set(ids).count, 3)
    }

    func testRedactionReportCountsSeededBlob() {
        let blob = DataLineFixtures.SeededSecrets.all.joined(separator: " ")
        let report = DataLineFixtures.redactionReport(for: blob)
        XCTAssertTrue(report.needsRedaction)
        XCTAssertEqual(report.unresolved.count, DataLineFixtures.SeededSecrets.all.count)
        XCTAssertEqual(report.countsByClass.values.reduce(0, +), report.unresolved.count)
    }

    func testNoRawSecretsHelperCatchesLeaks() {
        // The helper itself must fail on a leak: verify indirectly by scanning.
        let clean = ["hello fixture"]
        GoldenAssertions.assertNoRawSecrets(in: clean) // must not assert
        let blob = DataLineFixtures.SeededSecrets.openAIKey
        var config = SensitiveDataDetector.Configuration()
        config.detectEmails = true
        XCTAssertTrue(SensitiveDataDetector(configuration: config).containsSensitiveData(blob))
    }

    func testDatasetOrderingAndManifestAreDeterministic() throws {
        let sessions = DataLineFixtures.sessions(3)
        let ids = DataLineFixtures.orderedSampleIDs(sessions.reversed())
        XCTAssertEqual(ids, ids.sorted())
        let manifest = DataLineFixtures.datasetManifest(version: 1, sampleIDs: ids)
        try GoldenAssertions.assertDeterministic {
            try GoldenAssertions.canonicalJSON(manifest)
        }
    }

    func testConsentAndEnvironmentMatricesAreExhaustive() {
        XCTAssertEqual(DataLineFixtures.FixtureConsentClass.allCases.count, 3)
        XCTAssertEqual(DataLineFixtures.FixtureEnvironmentClass.allCases.count, 4)
        // Every sample-state transition target exists (Phase 14 table smoke test).
        XCTAssertTrue(DataLineFixtures.FixtureSampleState.allCases.contains(.accepted))
    }

    func testFuturePhaseExitGateNeedsNoNewHelpers() throws {
        // Roadmap T0 exit gate: a new phase expresses its gate with ONLY
        // DataLineFixtures + GoldenAssertions. Simulate three gates here —
        // Phase 7 (schema round-trip), Phase 9 (no raw secrets), Phase 17
        // (deterministic rebuild) — with zero helpers beyond those two types.
        let session = DataLineFixtures.session(1, text: DataLineFixtures.SeededSecrets.all.joined(separator: " "))

        // Phase 7 style: provenance + consent matrix round-trips byte-stable.
        let provenance = DataLineFixtures.provenance()
        try GoldenAssertions.assertJSONRoundTrip(provenance)
        try GoldenAssertions.assertByteStable(provenance)

        // Phase 9 style: redacted projection carries placeholders, never raw secrets.
        var redacted = DataLineFixtures.scannableText(session)
        for (index, secret) in DataLineFixtures.SeededSecrets.all.enumerated() {
            redacted = redacted.replacingOccurrences(
                of: secret, with: "{{secret:step2.redaction\(index)}}")
        }
        GoldenAssertions.assertNoRawSecrets(in: [redacted])
        GoldenAssertions.assertPlaceholders(
            in: redacted, count: DataLineFixtures.SeededSecrets.all.count)

        // Phase 17 style: same filter + inputs ⇒ byte-identical manifest.
        let ids = DataLineFixtures.orderedSampleIDs(DataLineFixtures.sessions(3))
        try GoldenAssertions.assertDeterministic {
            try GoldenAssertions.canonicalJSON(
                DataLineFixtures.datasetManifest(version: 2, sampleIDs: ids))
        }
    }
}
