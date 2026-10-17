import Foundation
import StepItIR
import StepItPipeline
import StepItCaptureAPI
import AppKit

/// Extract a working-directory path from a terminal window/tab title.
///
/// Modern terminals encode the shell's `cwd` in the title:
/// - Ghostty:      `user@hostname: ~/Code/stepit`
/// - iTerm2:       `1. zsh (stepit) — /codebases/stepit`
/// - Warp:         `~/Code/stepit`
/// - Apple Terminal usually carries no path (`user — -zsh — 80x24`) and
///   falls through to the AppleScript / process tiers.
///
/// Pure Foundation so it is fully unit-testable (`TerminalContextInspectorTests`).
public enum TerminalTitlePathParser {

    /// Edge characters to strip when isolating a path token.
    private static let edgeTrimSet = CharacterSet(charactersIn:
        " \t\n\r—–-:|•·\"'()[]{}<>,;"
    )

    /// Returns the last `~`-prefixed or absolute path token in the title, or
    /// `nil` when the title carries no path.
    public static func extractPath(from title: String) -> String? {
        guard !title.isEmpty else { return nil }

        let candidates = title
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .compactMap { token -> String? in
                let trimmed = String(token).trimmingCharacters(in: edgeTrimSet)
                if isPathToken(trimmed) { return trimmed }
                // Shell titles like `user@host:~/dir` glue the prompt to the path.
                if let colon = trimmed.lastIndex(of: ":"), colon < trimmed.index(before: trimmed.endIndex) {
                    let suffix = String(trimmed[trimmed.index(after: colon)...])
                    if isPathToken(suffix) { return suffix }
                }
                return nil
            }

        // Prefer the last path: terminals update the title as the user cd's.
        return candidates.last
    }

    /// Matches `~/…`, `~`, `/abs/path`. Rejects separators, flags and empty
    /// fragments so root-ish chrome text never produces a false positive.
    static func isPathToken(_ token: String) -> Bool {
        if token == "~" { return true }

        if token.hasPrefix("~/") {
            let rest = token.dropFirst(2)
            return !rest.isEmpty && !rest.contains("~")
        }

        guard token.hasPrefix("/"), token.count > 1 else { return false }
        let rest = token.dropFirst()
        // Require a path-ish character after the slash; reject `/--flag` and
        // `/ ` fragments that appear in prompt decorations.
        guard let first = rest.first, (first.isLetter || first.isNumber || first == "." || first == "_") else {
            return false
        }
        return true
    }
}

/// macOS implementation of `TerminalInspectorProtocol` with a three-tier
/// resolution strategy (T4):
///
/// 1. **Title extraction** — zero permissions, instant (pure parser above).
/// 2. **AppleScript** — `Terminal.app` / iTerm2 fallback when the title has no
///    path. Only attempted when Tier 1 fails (avoids Automation prompts when
///    the title already answers, mitigation R2).
/// 3. **Process tree** — `pgrep`/`lsof` on the shell child of the terminal pid.
///
/// All tiers are injectable so headless tests exercise the strategy without
/// Apple Events or spawned processes.
public final class TerminalContextInspector: TerminalInspectorProtocol, @unchecked Sendable {

    public typealias AppleScriptRunner = @Sendable (String) -> String?
    public typealias ProcessDirectoryResolver = @Sendable (Int32) -> String?
    public typealias PidResolver = @Sendable (String?) -> Int32?

    private let appleScriptRunner: AppleScriptRunner
    private let processDirectoryResolver: ProcessDirectoryResolver
    private let pidResolver: PidResolver

    public init(
        appleScriptRunner: @escaping AppleScriptRunner = TerminalContextInspector.runAppleScript,
        processDirectoryResolver: @escaping ProcessDirectoryResolver = TerminalContextInspector.shellWorkingDirectory,
        pidResolver: @escaping PidResolver = TerminalContextInspector.frontmostPid
    ) {
        self.appleScriptRunner = appleScriptRunner
        self.processDirectoryResolver = processDirectoryResolver
        self.pidResolver = pidResolver
    }

    // MARK: - TerminalInspectorProtocol

    public func inspectCurrentDirectory(forApp bundleId: String?, pid: Int32?, windowTitle: String?) async -> String? {
        // Tier 1 — window / tab title (zero permissions).
        if let title = windowTitle, let path = TerminalTitlePathParser.extractPath(from: title) {
            return path
        }

        let resolvedPid = pid ?? pidResolver(bundleId)

        // Tier 2 — AppleScript (Terminal.app / iTerm2 only).
        if let script = Self.appleScript(for: bundleId),
           let output = appleScriptRunner(script)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !output.isEmpty {
            // Scripts return a path directly; run it through the same parser.
            if let path = TerminalTitlePathParser.extractPath(from: output) {
                return path
            }
        }

        // Tier 3 — process tree (`pgrep` child shells + `lsof` cwd).
        if let pid = resolvedPid, let path = processDirectoryResolver(pid) {
            return path
        }

        return nil
    }

    // MARK: - Tier 2: AppleScript

    public static func appleScript(for bundleId: String?) -> String? {
        switch bundleId {
        case "com.apple.Terminal":
            return #"tell application "Terminal" to get custom title of selected tab of front window"#
        case "com.googlecode.iterm2":
            return #"tell application "iTerm2" to tell current window to tell current session to get variable named "path""#
        default:
            return nil
        }
    }

    /// Runs `/usr/bin/osascript` off the main thread. Returns stdout or `nil`.
    public static let runAppleScript: AppleScriptRunner = { script in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Tier 3: Process tree

    /// Finds a shell child of the terminal process and asks `lsof` for its cwd.
    public static let shellWorkingDirectory: ProcessDirectoryResolver = { terminalPid in
        let shellNames: Set<String> = ["zsh", "bash", "fish", "sh", "nu", "elvish", "pwsh", "xonsh", "tcsh", "ksh"]

        // `pgrep -P <pid> -l` → "<childpid> <processname>" per line.
        guard let listing = runCommand("/usr/bin/pgrep", ["-P", String(terminalPid), "-l"]) else { return nil }

        var candidates: [(pid: Int32, name: String)] = []
        for line in listing.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            guard let pid = Int32(parts.first ?? "") else { continue }
            candidates.append((pid, parts.count > 1 ? parts[1] : ""))
        }

        guard !candidates.isEmpty else { return nil }
        let shell = candidates.first(where: { shellNames.contains($0.name.lowercased()) })
            ?? candidates.first

        guard let shell = shell else { return nil }

        // `lsof -a -d cwd -Fn -p <pid>` → "p<pid>\nfcwd\nn/path/to/dir".
        guard let lsof = runCommand("/usr/sbin/lsof", ["-a", "-d", "cwd", "-Fn", "-p", String(shell.pid)]) else {
            return nil
        }
        for line in lsof.split(separator: "\n") where line.hasPrefix("n") {
            return String(line.dropFirst())
        }
        return nil
    }

    // MARK: - PID resolution

    /// Resolves the pid of the frontmost running instance of a terminal app
    /// when the caller did not supply one.
    public static let frontmostPid: PidResolver = { bundleId in
        guard let bundleId = bundleId else {
            return NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        let active = running.first(where: { $0.isActive }) ?? running.first
        return active?.processIdentifier
    }

    static func runCommand(_ launchPath: String, _ arguments: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: launchPath) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
