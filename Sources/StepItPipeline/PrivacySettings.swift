import Foundation

// MARK: - Phase 2: Privacy Configuration (owns: StepItPipeline)
// Moved here from StepItCore/Model/Settings.swift during R/M1-02 so the
// pipeline stays Foundation+IR-only. StepItCore re-exports via typealias
// until R/M1-07 deletes the source shim.

/// Visual treatment applied over detected sensitive regions.
public enum RedactionBlurStyle: String, Codable, CaseIterable, Sendable {
    case frostedGlass = "frosted_glass"
    case blackout = "blackout"

    public var displayName: String {
        switch self {
        case .frostedGlass: return "Frosted Glass (Gaussian Blur)"
        case .blackout: return "Solid Blackout"
        }
    }
}

/// Pre-capture (secure field masking) and post-capture (offline OCR redaction)
/// privacy rules. Everything runs 100% on-device — no network, no cloud.
public struct PrivacySettings: Codable, Sendable, Equatable {
    /// Mask keystrokes typed into `isSecure` fields as `••••` instead of
    /// dropping the batch entirely. Raw characters are never buffered either way.
    public var maskSecureInputFields: Bool = true
    /// Run the offline Apple Vision OCR pipeline over captured screenshots and
    /// blur detected sensitive tokens before they are written to disk.
    public var enableOfflineOCRRedaction: Bool = true
    /// OpenAI `sk-…`, AWS `AKIA…`, GitHub `ghp_…`, JWTs and bearer tokens.
    public var autoRedactAPIKeys: Bool = true
    public var autoRedactCreditCards: Bool = true
    public var autoRedactEmails: Bool = false
    /// Blur radius (in screen points) for `.frostedGlass` redaction.
    public var blurRadius: Double = 12.0
    /// Frosted glass blur vs. solid blackout.
    public var blurStyle: RedactionBlurStyle = .frostedGlass
    /// Extra user-supplied regex patterns, matched case-insensitively.
    public var customRegexPatterns: [String] = []

    public init() {}
}
