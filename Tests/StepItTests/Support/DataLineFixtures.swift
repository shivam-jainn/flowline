import Foundation
import StepItIR
import StepItPipeline
@testable import StepItCore

/// Phase 0 — deterministic builders for every data-line phase (7–22).
///
/// Why this exists: Phases 7–22 are 16 one-domain phases. Without shared
/// fixtures each phase invents its own sessions, secrets, policies, and
/// golden files, and exit gates become untestable. This file is the single
/// source of deterministic test data.
///
/// Rules:
/// - Every builder is deterministic: fixed UUIDs + fixed clock
///   (`TestClock` default start). No `UUID()` / `Date()` inside builders.
/// - Seeded secrets ALWAYS match `SensitiveDataDetector` so hygiene tests
///   (Phase 9) are meaningful, but are obviously fake (`…TEST…`, `example.com`).
/// - Test-local enums (`FixtureConsentClass`, …) mirror the planned Phase 7+
///   schema. When the real types land in `StepItCore`, delete the mirror and
///   typealias to the real thing — call sites must not change shape.
///
enum DataLineFixtures {

    // MARK: - Deterministic ids & time

    /// Fixed session/step ids: `sess_fix_001`, `step_fix_001_01`, …
    static func sessionID(_ n: Int) -> String { String(format: "sess_fix_%03d", n) }
    static func stepID(session n: Int, step s: Int) -> String {
        String(format: "step_fix_%03d_%02d", n, s)
    }

    static var fixedDate: Date { Date(timeIntervalSince1970: 1_700_000_000) }

    // MARK: - Seeded secrets (Phase 9 hygiene corpus)

    /// Every value here MUST be detected by `SensitiveDataDetector` with default
    /// config + emails on. If you add one, add its kind below and a test.
    enum SeededSecrets {
        static let openAIKey = "sk-testOPENAIKEY0123456789ABCDEF12345678"
        static let awsKey = "AKIATESTEXAMPLE12345"
        static let githubToken = "ghp_test0123456789abcdefghij1234567890AB"
        static let bearer = "Bearer test-bearer-token-abc123XYZ"
        static let email = "contractor.test@example.com"
        /// Passes Luhn; recognised as `creditCard`.
        static let card = "4242 4242 4242 4242"

        static var all: [String] {
            [openAIKey, awsKey, githubToken, bearer, email, card]
        }
    }

    // MARK: - Session builder (substrate for Phases 7–17)

    /// A 2-app, 3-step session with fixed ids, timestamps, and coordinates.
    /// `text:` injects raw text into step 2's blob (hygiene tests pass a secret).
    static func session(
        _ n: Int = 1,
        title: String = "Fixture workflow",
        text: String? = nil
    ) -> StepSession {
        let base = fixedDate
        let steps = [
            Step(
                id: stepID(session: n, step: 1),
                index: 1,
                timestamp: base,
                action: .click,
                appName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                windowTitle: "Checkout",
                elementRole: "AXButton",
                elementTitle: "Submit Order",
                coordinates: ScreenCoordinates(x: 100, y: 100),
                actionDescription: "Click \"Submit Order\" in Checkout"
            ),
            Step(
                id: stepID(session: n, step: 2),
                index: 2,
                timestamp: base.addingTimeInterval(5),
                action: .typing,
                appName: "Notes",
                bundleIdentifier: "com.apple.Notes",
                windowTitle: "Draft",
                elementRole: "AXTextField",
                actionDescription: "Type text in Notes",
                textBlob: text ?? "hello fixture"
            ),
            Step(
                id: stepID(session: n, step: 3),
                index: 3,
                timestamp: base.addingTimeInterval(10),
                action: .click,
                appName: "Terminal",
                bundleIdentifier: "com.apple.Terminal",
                windowTitle: "zsh",
                elementRole: "AXButton",
                elementTitle: "Run",
                coordinates: ScreenCoordinates(x: 200, y: 200),
                actionDescription: "Click \"Run\" in zsh"
            ),
        ]
        return StepSession(
            id: sessionID(n),
            startedAt: base,
            endedAt: base.addingTimeInterval(60),
            title: title,
            steps: steps
        )
    }

    /// `count` sessions with distinct deterministic ids (`sess_fix_001…`).
    static func sessions(_ count: Int, text: String? = nil) -> [StepSession] {
        (1...count).map { session($0, text: text) }
    }

    /// Session text blobs joined for scanning (what Phase 9 runs over).
    static func scannableText(_ session: StepSession) -> String {
        session.steps.compactMap(\.textBlob).joined(separator: "\n")
            + "\n"
            + session.steps.map(\.actionDescription).joined(separator: "\n")
    }

    // MARK: - Phase 7 mirrors (delete when real schema lands)

    enum FixtureConsentClass: String, Codable, CaseIterable {
        case `private`
        case contractCampaign = "contract-campaign"
        case consumerDonation = "consumer-donation"
    }

    enum FixtureEnvironmentClass: String, Codable, CaseIterable {
        case local, cleanVM = "clean-vm", trialAccount = "trial-account"
        case syntheticAccount = "synthetic-account"
    }

    struct FixtureProvenance: Codable, Equatable {
        var appName: String = "StepIt"
        var appVersion: String = "0.0.0-test"
        var environmentClass: FixtureEnvironmentClass = .syntheticAccount
        var licenseNotes: String = "fixture-only"
    }

    static func provenance(
        environment: FixtureEnvironmentClass = .syntheticAccount
    ) -> FixtureProvenance {
        FixtureProvenance(environmentClass: environment)
    }

    // MARK: - Phase 8 mirrors (capture policy)

    enum FixturePolicyStatus: String, Codable {
        case clean, violations
    }

    struct FixtureRecordingPolicy: Codable, Equatable {
        var allowedBundleIDs: [String]
        var bannedBundleIDs: [String]
        var requiredEnvironment: FixtureEnvironmentClass?
        var requiredAttestations: [String]

        static var safariOnly: FixtureRecordingPolicy {
            FixtureRecordingPolicy(
                allowedBundleIDs: ["com.apple.Safari"],
                bannedBundleIDs: ["com.evil.keylogger"],
                requiredEnvironment: .syntheticAccount,
                requiredAttestations: ["I am using a synthetic account"]
            )
        }
    }

    // MARK: - Phase 9 mirrors (hygiene report)

    struct FixtureRedactionReport: Codable, Equatable {
        var countsByClass: [String: Int]
        var unresolved: [String]
        var needsRedaction: Bool { !unresolved.isEmpty }
    }

    /// Report for a blob scanned with emails enabled: deterministic key order.
    static func redactionReport(for text: String) -> FixtureRedactionReport {
        var config = SensitiveDataDetector.Configuration()
        config.detectEmails = true
        let kinds = SensitiveDataDetector(configuration: config)
            .matches(in: text).map(\.kind.rawValue).sorted()
        var counts: [String: Int] = [:]
        kinds.forEach { counts[$0, default: 0] += 1 }
        return FixtureRedactionReport(countsByClass: counts, unresolved: kinds)
    }

    // MARK: - Phase 12–14 mirrors (campaign / task / review)

    struct FixtureTask: Codable, Equatable {
        var id: String
        var campaignID: String
        var title: String
        var policy: FixtureRecordingPolicy?
        var isHiddenValidation: Bool = false

        static func task(_ n: Int, hidden: Bool = false) -> FixtureTask {
            FixtureTask(
                id: String(format: "task_fix_%03d", n),
                campaignID: "camp_fix_001",
                title: "Fixture task \(n)",
                policy: .safariOnly,
                isHiddenValidation: hidden
            )
        }
    }

    enum FixtureSampleState: String, Codable, CaseIterable {
        case submitted, verifying, verified, inReview = "in_review"
        case accepted, fixRequested = "fix_requested", rejected, superseded
    }

    enum FixtureStepLabel: String, Codable { case fresh, stale, broken }
    enum FixtureReplayLabel: String, Codable { case success, failed, partial }

    // MARK: - Phase 16–19 mirrors (dataset / delivery)

    struct FixtureDatasetFilter: Codable, Equatable {
        var campaignID: String = "camp_fix_001"
        var requireState: FixtureSampleState = .accepted
        var excludeHiddenTasks: Bool = true
    }

    /// Stable dataset ordering: sort by session id. Phase 17 must use this.
    static func orderedSampleIDs(_ sessions: [StepSession]) -> [String] {
        sessions.map(\.id).sorted()
    }

    static func datasetManifest(
        version: Int,
        sampleIDs: [String],
        consent: FixtureConsentClass = .contractCampaign
    ) -> [String: String] {
        [
            "version": "v\(version)",
            "samples": sampleIDs.sorted().joined(separator: ","),
            "consent": consent.rawValue,
        ]
    }
}
