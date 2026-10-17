import Foundation
import StepItIR

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
    public func classify(text: String, context: RawElementContext?) -> InputClassification {
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
}
