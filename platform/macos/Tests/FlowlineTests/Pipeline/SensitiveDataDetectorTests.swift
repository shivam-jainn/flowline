import XCTest
import FlowlineStorage
import FlowlineCaptureAPI
import FlowlineMacCapture
import FlowlinePublishing
import FlowlineAIGateway
import FlowlinePermissions
import FlowlineIR
import FlowlinePipeline
import FlowlineEngine
@testable import FlowlineFixtures

final class SensitiveDataDetectorTests: XCTestCase {

    private let defaultDetector = SensitiveDataDetector()

    // MARK: - API keys & tokens

    func testOpenAIAPIKeyIsDetected() {
        let text = "OPENAI_API_KEY=sk-1234567890abcdef1234567890abcdef12"
        let matches = defaultDetector.matches(in: text)

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.kind, .openAIAPIKey)
        XCTAssertEqual(matches.first?.matchedText, "sk-1234567890abcdef1234567890abcdef12")
    }

    func testShortLookalikeIsNotDetected() {
        XCTAssertFalse(defaultDetector.containsSensitiveData("sk-abc")) // too short
        XCTAssertFalse(defaultDetector.containsSensitiveData("ask-me-anything")) // no boundary match
    }

    func testAWSAccessKeyIsDetected() {
        let matches = defaultDetector.matches(in: "aws_access_key_id = AKIAIOSFODNN7EXAMPLE")
        XCTAssertEqual(matches.map(\.kind), [.awsAccessKey])
    }

    func testGitHubTokenIsDetected() {
        let token = "ghp_" + String(repeating: "A", count: 36)
        XCTAssertEqual(defaultDetector.matches(in: "token: \(token)").map(\.kind), [.githubToken])
    }

    func testBearerTokenAndJWTAreDetected() {
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

        XCTAssertEqual(defaultDetector.matches(in: "Authorization: \(jwt)").map(\.kind), [.jsonWebToken])
        XCTAssertTrue(defaultDetector.containsSensitiveData("Authorization: Bearer \(jwt)"))
    }

    func testBearerAndJWTOnOneLineDeduplicate() {
        // The widest match wins — never two regions for the same token.
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.signature"
        let matches = defaultDetector.matches(in: "Authorization: Bearer \(jwt)")
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.kind, .bearerToken)
    }

    // MARK: - Credit cards (Luhn-validated)

    func testKnownTestCardsAreDetected() {
        let corpus = [
            "4111 1111 1111 1111", // Visa test
            "4242-4242-4242-4242", // Stripe test
            "5555555555554444"     // Mastercard test
        ]

        for card in corpus {
            let matches = defaultDetector.matches(in: "Card number: \(card)")
            XCTAssertEqual(matches.map(\.kind), [.creditCard], "\(card) should be detected")
        }
    }

    func testRandomNumberWithBadLuhnChecksumIsNotDetected() {
        XCTAssertFalse(defaultDetector.containsSensitiveData("Order 1234 5678 9012 3456"))
    }

    func testLuhnValidatorItself() {
        XCTAssertTrue(SensitiveDataDetector.passesLuhn("4111111111111111"))
        XCTAssertTrue(SensitiveDataDetector.passesLuhn("4111 1111 1111 1111"))
        XCTAssertFalse(SensitiveDataDetector.passesLuhn("1234567890123456"))
        XCTAssertFalse(SensitiveDataDetector.passesLuhn("1234"))
    }

    // MARK: - Configuration gates

    func testEmailsAreOffByDefaultAndConfigurable() {
        XCTAssertFalse(defaultDetector.containsSensitiveData("reach me at shivam@example.com"))

        var configuration = SensitiveDataDetector.Configuration()
        configuration.detectEmails = true
        let emailDetector = SensitiveDataDetector(configuration: configuration)
        XCTAssertEqual(emailDetector.matches(in: "reach me at shivam@example.com").map(\.kind), [.email])
    }

    func testAPIKeyDetectionCanBeDisabled() {
        var configuration = SensitiveDataDetector.Configuration()
        configuration.detectAPIKeys = false
        let detector = SensitiveDataDetector(configuration: configuration)
        XCTAssertFalse(detector.containsSensitiveData("sk-1234567890abcdef1234567890abcdef12"))
    }

    func testPrivacySettingsBridge() {
        var privacy = PrivacySettings()
        privacy.autoRedactAPIKeys = false
        privacy.autoRedactEmails = true

        let detector = SensitiveDataDetector(privacy: privacy)
        XCTAssertTrue(detector.containsSensitiveData("shivam@example.com"))
        XCTAssertFalse(detector.containsSensitiveData("sk-1234567890abcdef1234567890abcdef12"))
    }

    func testCustomRegexPatterns() {
        var privacy = PrivacySettings()
        privacy.customRegexPatterns = ["INTERNAL-[0-9]{4}"]

        let detector = SensitiveDataDetector(privacy: privacy)
        XCTAssertEqual(detector.matches(in: "ref INTERNAL-4242 ok").map(\.kind), [.custom])
    }

    func testInvalidCustomRegexIsIgnoredNotFatal() {
        var privacy = PrivacySettings()
        privacy.customRegexPatterns = ["([unclosed"]

        let detector = SensitiveDataDetector(privacy: privacy)
        XCTAssertFalse(detector.containsSensitiveData("nothing to see"))
    }

    // MARK: - Clean text

    func testOrdinaryDocumentationTextIsNotFlagged() {
        let clean = """
        # Release checklist
        Run swift test and open the Review Window.
        Commit branch feature/flowline-phase-2 and push to origin.
        Updated 2026-10-17 at 10:30.
        """
        XCTAssertFalse(defaultDetector.containsSensitiveData(clean))
    }

    func testMatchesAreOrderedAndNonOverlapping() {
        let text = "first 4111 1111 1111 1111 then AKIAIOSFODNN7EXAMPLE"
        let matches = defaultDetector.matches(in: text)

        XCTAssertEqual(matches.map(\.kind), [.creditCard, .awsAccessKey])
        XCTAssertLessThan(matches[0].range.upperBound, matches[1].range.lowerBound)
    }
}
