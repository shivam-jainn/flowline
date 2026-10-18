import Foundation
import FlowlineIR

/// One pickable `@` reference for the AI compose box.
///
/// Tokens are what gets inserted into the prompt text:
/// `@guide` / `@recording` / `@automation` keep the full session,
/// `@step` scopes to the currently selected step,
/// `@step-N` scopes to a specific step by its 1-based index.
public struct AIMentionOption: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable, Equatable {
        case guide
        case selectedStep
        case recording
        case automation
        case step
    }

    public var id: String { token }
    public var token: String
    public var title: String
    public var subtitle: String
    public var kind: Kind
    /// 1-based step index for `.step` options, nil otherwise.
    public var stepIndex: Int?

    public init(token: String, title: String, subtitle: String, kind: Kind, stepIndex: Int? = nil) {
        self.token = token
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.stepIndex = stepIndex
    }
}

public enum AIMentions {
    private static let allowedQueryChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))

    /// Finds the in-progress `@query` at the end of `text`.
    ///
    /// Assumes the caret is at the end (the compose box is a single-line
    /// `TextField`). Returns nil when there is no trailing `@token`:
    /// no `@`, `@` preceded by a non-whitespace char (emails), or the user
    /// already typed a space / punctuation after the token.
    public static func activeQuery(in text: String) -> (query: String, range: Range<String.Index>)? {
        guard let lastAt = text.lastIndex(of: "@") else { return nil }
        if lastAt != text.startIndex {
            let prev = text[text.index(before: lastAt)]
            if !prev.isWhitespace { return nil }
        }
        let afterAt = text.index(after: lastAt)
        let query = String(text[afterAt...])
        // A space / newline after the token means the mention is finished.
        if query.contains(where: { $0.isWhitespace }) { return nil }
        if query.unicodeScalars.contains(where: { !allowedQueryChars.contains($0) }) { return nil }
        return (query, lastAt..<text.endIndex)
    }

    /// Every referenceable target (specials + one row per current step),
    /// filtered by `query` (the text after `@`, case-insensitive).
    public static func options(
        session: StepSession,
        scopeStep: Step?,
        query: String
    ) -> [AIMentionOption] {
        var all: [AIMentionOption] = [
            AIMentionOption(
                token: "@guide",
                title: "Guide",
                subtitle: "\(session.steps.count) steps · full guide",
                kind: .guide
            ),
        ]
        if let s = scopeStep {
            all.append(AIMentionOption(
                token: "@step",
                title: "Selected step",
                subtitle: "Step \(s.index): \(s.actionDescription.prefix(60))",
                kind: .selectedStep
            ))
        }
        all.append(AIMentionOption(
            token: "@recording",
            title: "Recording",
            subtitle: "Full capture + media",
            kind: .recording
        ))
        all.append(AIMentionOption(
            token: "@automation",
            title: "Automation",
            subtitle: "Full guide as script outline",
            kind: .automation
        ))
        for step in session.steps.sorted(by: { $0.index < $1.index }) {
            let app = step.appName.isEmpty ? "" : " · \(step.appName)"
            all.append(AIMentionOption(
                token: "@step-\(step.index)",
                title: "Step \(step.index)",
                subtitle: "\(step.actionDescription.prefix(60))\(app)",
                kind: .step,
                stepIndex: step.index
            ))
        }

        let q = query.lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { opt in
            let tokenBare = opt.token.dropFirst().lowercased()
            if tokenBare.contains(q) { return true }
            if opt.title.lowercased().contains(q) { return true }
            if opt.subtitle.lowercased().contains(q) { return true }
            // `@step3` without the dash still finds step 3.
            if opt.kind == .step, let idx = opt.stepIndex {
                if "step\(idx)".contains(q) { return true }
                if "\(idx)" == q { return true }
            }
            return false
        }
    }

    /// Replaces the trailing `@query` with the picked token plus a space.
    /// When there is no active query (e.g. the `@step` shortcut buttons),
    /// appends the token instead.
    public static func applying(option: AIMentionOption, to text: String) -> String {
        if let active = activeQuery(in: text) {
            var out = text
            out.replaceSubrange(active.range, with: option.token + " ")
            return out
        }
        if text.isEmpty || text.last?.isWhitespace == true {
            return text + option.token + " "
        }
        return text + " " + option.token + " "
    }

    /// Narrows `session` to the referenced steps:
    /// explicit `@step-N` / `@stepN` tokens win, else bare `@step` uses the
    /// selected step, else the full session (`@guide` / `@recording` /
    /// `@automation` / no mention).
    public static func scopedSession(
        session: StepSession,
        scopeStep: Step?,
        instructions: String
    ) -> StepSession {
        let lower = instructions.lowercased()
        var wanted = Set<Int>()
        var i = lower.startIndex
        while let at = lower[i...].firstIndex(of: "@") {
            let after = lower.index(after: at)
            var j = after
            while j < lower.endIndex, lower[j].isLetter { j = lower.index(after: j) }
            let word = String(lower[after..<j])
            if word == "step" {
                // Optional `-N` / `N` suffix directly attached.
                var k = j
                if k < lower.endIndex, lower[k] == "-" { k = lower.index(after: k) }
                var num = ""
                while k < lower.endIndex, lower[k].isNumber {
                    num.append(lower[k])
                    k = lower.index(after: k)
                }
                if let n = Int(num) { wanted.insert(n) }
            }
            i = lower.index(after: at)
        }
        if !wanted.isEmpty {
            let matched = session.steps.filter { wanted.contains($0.index) }
            // Fall back to positional lookup when stored indices are stale
            // (e.g. after deletes before a renumber).
            let resolved: [Step]
            if matched.isEmpty {
                resolved = wanted.compactMap { n in
                    session.steps.indices.contains(n - 1) ? session.steps[n - 1] : nil
                }
            } else {
                resolved = matched
            }
            if !resolved.isEmpty {
                var scoped = session
                scoped.steps = resolved
                return scoped
            }
        }
        if lower.contains("@step"), let s = scopeStep {
            var scoped = session
            scoped.steps = [s]
            return scoped
        }
        return session
    }
}
