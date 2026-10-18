import Foundation
import FlowlineIR

/// A sensitive token found in scanned text (Phase 2, T7).
public struct SensitiveDataMatch: Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case openAIAPIKey
        case awsAccessKey
        case githubToken
        case bearerToken
        case jsonWebToken
        case creditCard
        case email
        case custom
    }

    public var kind: Kind
    public var matchedText: String
    /// UTF-16 code-unit offsets (`NSRange` semantics) into the scanned string.
    public var range: Range<Int>

    public init(kind: Kind, matchedText: String, range: Range<Int>) {
        self.kind = kind
        self.matchedText = matchedText
        self.range = range
    }
}

/// Pure-Swift, offline sensitive-data matcher (Phase 2, T7).
///
/// Deliberately Foundation-only: the regex corpus runs on already-extracted OCR
/// text inside the core `Pipeline/`, never touching Vision or CoreImage. Strict
/// anchored patterns (`sk-…`, `AKIA…`, `ghp_…`, JWT triplets) plus a Luhn check
/// for card numbers keep false positives (and over-blurring, mitigation R4) low.
public struct SensitiveDataDetector: Sendable {

    public struct Configuration: Sendable, Equatable {
        /// OpenAI `sk-…`, AWS `AKIA…`, GitHub `ghp_…`, JWTs, bearer tokens.
        public var detectAPIKeys: Bool = true
        public var detectCreditCards: Bool = true
        public var detectEmails: Bool = false
        /// Extra user-supplied regex patterns (matched case-insensitively).
        public var customPatterns: [String] = []

        public init() {}
    }

    public let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Convenience bridge from persisted privacy settings.
    public init(privacy: PrivacySettings) {
        var configuration = Configuration()
        configuration.detectAPIKeys = privacy.autoRedactAPIKeys
        configuration.detectCreditCards = privacy.autoRedactCreditCards
        configuration.detectEmails = privacy.autoRedactEmails
        configuration.customPatterns = privacy.customRegexPatterns
        self.configuration = configuration
    }

    // MARK: - Matching

    /// All sensitive tokens in `text`, ordered by position and de-overlapped.
    public func matches(in text: String) -> [SensitiveDataMatch] {
        guard !text.isEmpty else { return [] }

        var found: [SensitiveDataMatch] = []
        for rule in rules {
            found.append(contentsOf: matches(for: rule, in: text))
        }

        let sorted = found.sorted { lhs, rhs in
            lhs.range.lowerBound == rhs.range.lowerBound
                ? lhs.range.upperBound > rhs.range.upperBound
                : lhs.range.lowerBound < rhs.range.lowerBound
        }

        // Keep the widest match at any overlapping span (a bearer token that
        // embeds an sk-… key should report once).
        var deduped: [SensitiveDataMatch] = []
        for match in sorted where !deduped.contains(where: { $0.range.overlaps(match.range) }) {
            deduped.append(match)
        }
        return deduped
    }

    /// `true` when at least one configured pattern matches.
    public func containsSensitiveData(_ text: String) -> Bool {
        !matches(in: text).isEmpty
    }

    // MARK: - Rules

    private struct Rule {
        var kind: SensitiveDataMatch.Kind
        var pattern: String
        var options: NSRegularExpression.Options
        /// Extra semantic validation (credit-card Luhn checksum).
        var validator: (@Sendable (String) -> Bool)?

        init(
            kind: SensitiveDataMatch.Kind,
            pattern: String,
            options: NSRegularExpression.Options = [],
            validator: (@Sendable (String) -> Bool)? = nil
        ) {
            self.kind = kind
            self.pattern = pattern
            self.options = options
            self.validator = validator
        }
    }

    private var rules: [Rule] {
        var rules: [Rule] = []

        if configuration.detectAPIKeys {
            rules.append(Rule(kind: .openAIAPIKey, pattern: #"\bsk-[a-zA-Z0-9]{32,}\b"#))
            rules.append(Rule(kind: .awsAccessKey, pattern: #"\bAKIA[0-9A-Z]{16}\b"#))
            rules.append(Rule(kind: .githubToken, pattern: #"\bgh[pousr]_[a-zA-Z0-9]{36}\b"#))
            rules.append(Rule(kind: .bearerToken, pattern: #"\bBearer\s+[a-zA-Z0-9\-\._~\+/]+=*"#, options: [.caseInsensitive]))
            rules.append(Rule(kind: .jsonWebToken, pattern: #"\beyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#))
        }

        if configuration.detectCreditCards {
            rules.append(Rule(
                kind: .creditCard,
                pattern: #"\b(?:\d{4}[ -]?){3}\d{4}\b"#,
                validator: SensitiveDataDetector.passesLuhn
            ))
        }

        if configuration.detectEmails {
            rules.append(Rule(kind: .email, pattern: #"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"#))
        }

        for pattern in configuration.customPatterns where !pattern.isEmpty {
            rules.append(Rule(kind: .custom, pattern: pattern, options: [.caseInsensitive]))
        }

        return rules
    }

    private func matches(for rule: Rule, in text: String) -> [SensitiveDataMatch] {
        guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else {
            return []
        }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: fullRange).compactMap { result in
            guard let range = Range(result.range, in: text) else { return nil }
            let matched = String(text[range])
            if let validator = rule.validator, !validator(matched) { return nil }
            return SensitiveDataMatch(
                kind: rule.kind,
                matchedText: matched,
                range: result.range.location..<(result.range.location + result.range.length)
            )
        }
    }

    // MARK: - Validators

    /// Standard Luhn checksum (used to reject arbitrary 16-digit numbers).
    public static let passesLuhn: @Sendable (String) -> Bool = { candidate in
        let digits = candidate.compactMap { $0.wholeNumberValue }
        guard digits.count >= 13 else { return false }

        var sum = 0
        for (offset, digit) in digits.reversed().enumerated() {
            if offset % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }
}
