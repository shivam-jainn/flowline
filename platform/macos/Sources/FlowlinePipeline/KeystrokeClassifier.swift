import Foundation
import FlowlineIR

/// Result of classifying what & where the user was typing.
public enum InputClassification: Sendable, Equatable {
    /// Plain text input in a non-code field.
    case text
    /// Code editor typing, optionally with a detected language. `"text"` is
    /// used when the environment is a code editor but no language is known
    /// (byte parity with the pre-Phase-1 aggregator).
    case code(language: String?)
    /// Terminal command entry.
    case terminal
}

/// Pure, platform-free port of the app/editor/terminal predicates that used to
/// live inside the legacy macOS typing aggregator (Phase 1 audit A8).
///
/// Everything here is a pure function of a `RawElementContext` + text, so it is
/// fully unit-testable without hardware.
public struct KeystrokeClassifier: Sendable {
    public init() {}

    // MARK: - Terminal detection

    public func isTerminalEnvironment(_ context: RawElementContext?) -> Bool {
        isTerminalEnvironment(
            appName: context?.appName ?? "",
            bundleId: context?.bundleIdentifier,
            windowTitle: context?.windowTitle ?? ""
        )
    }

    /// Port of the legacy aggregator's `isTerminalEnvironment` (verbatim app list).
    public func isTerminalEnvironment(appName: String, bundleId: String?, windowTitle: String) -> Bool {
        let name = appName.lowercased()
        let bId = (bundleId ?? "").lowercased()
        let title = windowTitle.lowercased()

        if name.contains("terminal") || name.contains("iterm") || name.contains("alacritty") ||
           name.contains("kitty") || name.contains("warp") || name.contains("ghostty") ||
           name.contains("hyper") || bId.contains("terminal") || bId.contains("iterm") ||
           bId.contains("warp") || bId.contains("alacritty") || bId.contains("kitty") {
            return true
        }

        // Embedded IDE terminals or shells in window title
        if title.contains("— zsh") || title.contains("— bash") || title.contains("terminal") || title.contains("console") {
            return true
        }

        return false
    }

    // MARK: - Code-environment detection

    public func isCodeEnvironment(_ context: RawElementContext?) -> Bool {
        isCodeEnvironment(
            appName: context?.appName ?? "",
            bundleId: context?.bundleIdentifier,
            windowTitle: context?.windowTitle ?? ""
        )
    }

    /// Port of the legacy aggregator's `isCodeEnvironment` (verbatim app list and
    /// file-extension table).
    public func isCodeEnvironment(appName: String, bundleId: String?, windowTitle: String) -> Bool {
        let name = appName.lowercased()
        let bId = (bundleId ?? "").lowercased()
        let title = windowTitle.lowercased()

        if isTerminalEnvironment(appName: appName, bundleId: bundleId, windowTitle: windowTitle) {
            return true
        }

        if name.contains("code") || name.contains("xcode") || name.contains("sublime") ||
           name.contains("cursor") || name.contains("intellij") || name.contains("pycharm") ||
           name.contains("webstorm") || name.contains("antigravity") ||
           bId.contains("vscode") || bId.contains("antigravity") {
            return true
        }

        // Check file extension in window title
        let extensions = [".swift", ".ts", ".tsx", ".js", ".jsx", ".py", ".rs", ".go", ".cpp", ".c", ".h", ".json", ".yaml", ".yml", ".sh", ".bash", ".sql", ".html", ".css"]
        for ext in extensions {
            if title.contains(ext) { return true }
        }

        return false
    }

    // MARK: - Language detection

    public func detectLanguage(_ context: RawElementContext?, text: String) -> String {
        detectLanguage(
            appName: context?.appName ?? "",
            windowTitle: context?.windowTitle ?? "",
            text: text
        )
    }

    /// Port of the legacy aggregator's `detectLanguage`, including the legacy
    /// `"text"` fallback (byte-parity with pre-Phase-1 step JSON).
    public func detectLanguage(appName: String, windowTitle: String, text: String) -> String {
        let name = appName.lowercased()
        let title = windowTitle.lowercased()

        if isTerminalEnvironment(appName: appName, bundleId: nil, windowTitle: windowTitle) {
            return "bash"
        }

        if title.contains(".swift") { return "swift" }
        if title.contains(".ts") || title.contains(".tsx") { return "typescript" }
        if title.contains(".json") { return "json" }
        if title.contains(".jsx") || title.contains(".js") { return "javascript" }
        if title.contains(".py") { return "python" }
        if title.contains(".rs") { return "rust" }
        if title.contains(".go") { return "go" }
        if title.contains(".yaml") || title.contains(".yml") { return "yaml" }
        if title.contains(".sql") { return "sql" }
        if title.contains(".sh") || title.contains(".bash") || name.contains("terminal") || name.contains("iterm") { return "bash" }
        if title.contains(".html") { return "html" }
        if title.contains(".css") { return "css" }

        // Fallback checks on text structure
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return "json" }
        if trimmed.hasPrefix("import ") || trimmed.hasPrefix("func ") || trimmed.hasPrefix("struct ") { return "swift" }
        if trimmed.hasPrefix("def ") || trimmed.hasPrefix("class ") { return "python" }
        if trimmed.hasPrefix("npm ") || trimmed.hasPrefix("git ") || trimmed.hasPrefix("cd ") || trimmed.hasPrefix("curl ") || trimmed.hasPrefix("swift ") || trimmed.hasPrefix("docker ") { return "bash" }

        return "text"
    }

    // MARK: - Classification

    /// Single entry point used by `TypingBatchAggregator`: mirrors the old
    /// coordinator's `isCode`/`isTerminal`/`language` derivation exactly.
    ///
    /// Rust core is the source of truth: when the `FlowlineFFI` bindings are
    /// present (rebuilt via `make ffi`), classification delegates to
    /// `flowline_ffi.classify_text` so Swift never forks the table.
    public func classify(text: String, context: RawElementContext?) -> InputClassification {
        #if canImport(FlowlineFFI)
        if let bridged = FFIBridge.classify(text: text, context: context) {
            return bridged
        }
        #endif
        if isTerminalEnvironment(context) {
            return .terminal
        }
        if isCodeEnvironment(context) {
            return .code(language: detectLanguage(context, text: text))
        }
        return .text
    }

    // MARK: - Command prefixes

    /// Command-prefix vocabulary used by `Step.synthesizeDefaultDescription`
    /// and the Phase 3 automation compilers.
    public func commandPrefix(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let prefixes = ["git ", "npm ", "swift ", "cd ", "cat ", "ls", "curl", "docker"]
        for prefix in prefixes where trimmed.hasPrefix(prefix) {
            return prefix.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    // MARK: - Smart typing segmentation (mirrors `flowline_pipeline::classify`)

    /// Typing environment profile driving per-app hysteresis thresholds.
    /// Rust core (`TypingProfile`) is the source of truth; this is the
    /// verbatim Swift twin for use when `FlowlineFFI` is unavailable.
    public enum TypingProfile: Sendable, Equatable {
        case terminal
        case editor
        case url
    }

    /// Canonical hysteresis bounds (millis): editor 600/1800, terminal
    /// 900/2500, URL 400/1200.
    public static let tLowEditor: Double = 600
    public static let tHighEditor: Double = 1800
    public static let tLowTerminal: Double = 900
    public static let tHighTerminal: Double = 2500
    public static let tLowURL: Double = 400
    public static let tHighURL: Double = 1200

    /// Burst rate marking paste/IME injection: >15 Hz ⇒ gap ≤ 66 ms.
    public static let burstGapMaxMillis: Double = 66

    public static func profileThresholds(_ profile: TypingProfile) -> (low: Double, high: Double) {
        switch profile {
        case .terminal: return (tLowTerminal, tHighTerminal)
        case .editor: return (tLowEditor, tHighEditor)
        case .url: return (tLowURL, tHighURL)
        }
    }

    /// `true` when the focused element is a URL/address field.
    public func isURLField(_ context: RawElementContext?) -> Bool {
        guard let context else { return false }
        let placeholder = (context.placeholder ?? "").lowercased()
        let title = (context.title ?? "").lowercased()
        let window = context.windowTitle.lowercased()
        let app = context.appName.lowercased()
        let bid = (context.bundleIdentifier ?? "").lowercased()
        let fieldHint = placeholder.contains("url") || placeholder.contains("address")
            || placeholder.contains("search") || placeholder.contains("omnibox")
            || title.contains("address bar") || title.contains("omnibox")
            || title.contains("url")
        if fieldHint { return true }
        let browser = app.contains("safari") || app.contains("chrome")
            || app.contains("chromium") || app.contains("firefox")
            || app.contains("edge") || app.contains("arc")
            || app.contains("brave") || app.contains("orion")
            || bid.contains("safari") || bid.contains("chrome")
            || bid.contains("firefox") || bid.contains("edge")
            || bid.contains("arc") || bid.contains("brave")
        return browser && (window.contains("http://") || window.contains("https://") || window.contains("www."))
    }

    public func typingProfile(_ context: RawElementContext?) -> TypingProfile {
        if isTerminalEnvironment(context) { return .terminal }
        if isURLField(context) { return .url }
        return .editor
    }

    /// Base (non-adaptive) thresholds for a concrete context.
    public func thresholds(for context: RawElementContext?) -> (low: Double, high: Double) {
        #if canImport(FlowlineFFI)
        if let bridged = FFIBridge.thresholds(context: context) {
            return bridged
        }
        #endif
        return Self.profileThresholds(typingProfile(context))
    }

    /// Adaptive personalization: `T_user = 0.8 * T_app + 0.2 * p95_IKI`.
    public static func adaptiveThresholds(baseLow: Double, baseHigh: Double, p95: Double?) -> (low: Double, high: Double) {
        #if canImport(FlowlineFFI)
        if let bridged = FFIBridge.adaptiveThresholds(baseLow: baseLow, baseHigh: baseHigh, p95: p95) {
            return bridged
        }
        #endif
        guard let p95 else { return (baseLow, baseHigh) }
        let low = max(100, (8 * baseLow + 2 * p95) / 10)
        let high = max(low + 100, (8 * baseHigh + 2 * p95) / 10)
        return (low, high)
    }

    /// 95th percentile of recent inter-key intervals (millis). `nil` when empty.
    public static func p95(_ gaps: [Double]) -> Double? {
        #if canImport(FlowlineFFI)
        if let bridged = FFIBridge.p95(gaps: gaps) {
            return bridged
        }
        #endif
        guard !gaps.isEmpty else { return nil }
        let sorted = gaps.sorted()
        let n = sorted.count
        let rank = (95 * n + 99) / 100
        return sorted[max(0, min(rank - 1, n - 1))]
    }

    /// Hysteresis cut decision: JOIN below low, CUT at/above high, HOLD in
    /// the ambiguous band unless `corroborated`.
    public static func shouldCut(gap: Double, low: Double, high: Double, corroborated: Bool) -> Bool {
        #if canImport(FlowlineFFI)
        if let bridged = FFIBridge.shouldCut(gap: gap, low: low, high: high, corroborated: corroborated) {
            return bridged
        }
        #endif
        if gap < low { return false }
        if gap >= high { return true }
        return corroborated
    }

    /// `true` when `gap` marks burst/paste-rate traffic (>15 Hz).
    public static func isBurstGap(_ gap: Double) -> Bool {
        #if canImport(FlowlineFFI)
        if let bridged = FFIBridge.isBurst(gap: gap) {
            return bridged
        }
        #endif
        return gap <= burstGapMaxMillis
    }

    /// `true` for the `Cmd+V` paste chord.
    public static func isCmdPaste(key: String, commandHeld: Bool) -> Bool {
        commandHeld && key.lowercased() == "v"
    }

    /// Return-key outcome after the Return classifier.
    public enum ReturnAction: Sendable, Equatable {
        case cut
        case joinNewline
    }

    /// Terminal / single-line / `Cmd+Return` CUT; multiline plain Return JOINs.
    public func classifyReturn(_ context: RawElementContext?, commandHeld: Bool) -> ReturnAction {
        #if canImport(FlowlineFFI)
        if let bridged = FFIBridge.classifyReturn(context: context, commandHeld: commandHeld) {
            return bridged
        }
        #endif
        if commandHeld { return .cut }
        if isTerminalEnvironment(context) { return .cut }
        let role = context?.role ?? ""
        if role.contains("TextArea") { return .joinNewline }
        if role.contains("TextField") { return .cut }
        return .cut
    }

    /// `true` when the focused element identity changed enough to force a cut
    /// (bundle/app/window/AX-role; `AXUnknown` successors never cut).
    public static func focusChanged(from prev: RawElementContext?, to next: RawElementContext?) -> Bool {
        #if canImport(FlowlineFFI)
        if let bridged = FFIBridge.focusChanged(from: prev, to: next) {
            return bridged
        }
        #endif
        guard let prev, let next else { return false }
        if next.role == "AXUnknown" { return false }
        if prev.bundleIdentifier != next.bundleIdentifier { return true }
        if prev.appName != next.appName { return true }
        if prev.windowTitle != next.windowTitle { return true }
        if prev.role != next.role { return true }
        return false
    }
}

#if canImport(FlowlineFFI)
import FlowlineFFI

/// Isolates every Rust-core call so UniFFI signature drift stays in one spot.
/// Each helper returns `nil` when the bridge is unreachable, letting the pure
/// Swift twin above serve as the fallback.
private enum FFIBridge {
    static func classify(text: String, context: RawElementContext?) -> InputClassification? {
        let label = classifyText(
            text: text,
            appName: context?.appName ?? "",
            windowTitle: context?.windowTitle ?? ""
        )
        switch label {
        case "terminal": return .terminal
        case "text": return .text
        default:
            if label.hasPrefix("code:") {
                return .code(language: String(label.dropFirst(5)))
            }
            return nil
        }
    }

    static func thresholds(context: RawElementContext?) -> (low: Double, high: Double)? {
        guard let context else { return nil }
        let raw = typingThresholds(
            appName: context.appName,
            bundleId: context.bundleIdentifier,
            windowTitle: context.windowTitle,
            role: context.role,
            placeholder: context.placeholder
        )
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let low = json["lowMs"] as? Double,
              let high = json["highMs"] as? Double
        else { return nil }
        return (low, high)
    }

    static func adaptiveThresholds(baseLow: Double, baseHigh: Double, p95: Double?) -> (low: Double, high: Double)? {
        let p95u: UInt64? = p95.map { UInt64($0) }
        let out = typingAdaptiveThresholds(
            baseLowMs: UInt64(baseLow),
            baseHighMs: UInt64(baseHigh),
            p95IkiMs: p95u
        )
        guard out.count == 2 else { return nil }
        return (Double(out[0]), Double(out[1]))
    }

    static func p95(gaps: [Double]) -> Double? {
        typingP95Iki(gaps: gaps.map { UInt64($0) }).map { Double($0) }
    }

    static func shouldCut(gap: Double, low: Double, high: Double, corroborated: Bool) -> Bool? {
        typingShouldCut(gapMs: UInt64(gap), lowMs: UInt64(low), highMs: UInt64(high), corroborated: corroborated)
    }

    static func isBurst(gap: Double) -> Bool? {
        typingIsBurst(gapMs: UInt64(gap))
    }

    static func classifyReturn(context: RawElementContext?, commandHeld: Bool) -> KeystrokeClassifier.ReturnAction? {
        guard let context else { return nil }
        let raw = typingClassifyReturn(
            appName: context.appName,
            bundleId: context.bundleIdentifier,
            windowTitle: context.windowTitle,
            role: context.role,
            commandHeld: commandHeld
        )
        switch raw {
        case "cut": return .cut
        case "join": return .joinNewline
        default: return nil
        }
    }

    static func focusChanged(from prev: RawElementContext?, to next: RawElementContext?) -> Bool? {
        guard let prev, let next,
              let prevData = try? JSONEncoder().encode(prev),
              let nextData = try? JSONEncoder().encode(next),
              let prevJSON = String(data: prevData, encoding: .utf8),
              let nextJSON = String(data: nextData, encoding: .utf8),
              let result = try? typingFocusChanged(prevJson: prevJSON, nextJson: nextJSON)
        else { return nil }
        return result
    }
}
#endif
