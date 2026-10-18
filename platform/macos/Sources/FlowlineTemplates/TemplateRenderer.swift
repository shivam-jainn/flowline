import Foundation
import FlowlineIR

/// Pure preview-text renderer: "how text will look" for each guide mode.
///
/// Deterministic and Foundation-only. Unknown template ids fall back to
/// standard rendering. Title uppercasing uses a fixed POSIX locale so
/// output never depends on the user's locale.
public enum TemplateRenderer {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    /// Render one step for the "how text will look" preview. `index` is the
    /// 1-based display number (callers enumerating a session pass position).
    public static func renderStep(step: Step, index: Int, template: GuideTemplate) -> String {
        let description = step.actionDescription
        let title = "Step \(index): \(description)"
        switch template.id {
        case "checklist":
            return "- [ ] \(title)"
        case "sop":
            return "\(index). \(description)"
        case "tutorial":
            var lines = [title]
            if let notes = step.userNotes, !notes.isEmpty {
                lines.append("  Tip: \(notes)")
            }
            let context: String
            if !step.appName.isEmpty, !step.windowTitle.isEmpty {
                context = "  (\(step.appName) · \(step.windowTitle))"
            } else if !step.appName.isEmpty {
                context = "  (\(step.appName))"
            } else if !step.windowTitle.isEmpty {
                context = "  (\(step.windowTitle))"
            } else {
                context = ""
            }
            if !context.isEmpty {
                lines.append(context)
            }
            return lines.joined(separator: "\n")
        case "runbook":
            var lines = [title]
            if let blob = step.textBlob, !blob.isEmpty {
                let language: String
                if let codeLanguage = step.codeLanguage, !codeLanguage.isEmpty {
                    language = codeLanguage
                } else if step.isCode {
                    language = "bash"
                } else {
                    language = ""
                }
                lines.append("```\(language)\n\(blob)\n```")
            }
            if let combo = step.hotkeyCombo, !combo.isEmpty {
                lines.append("  Keys: \(combo)")
            }
            return lines.joined(separator: "\n")
        case "presentation":
            return title.uppercased(with: posixLocale)
        case "reference":
            let appSuffix = step.appName.isEmpty ? "" : " · \(step.appName)"
            return "\(title)\n\(verb(for: step)) → \(target(for: step))\(appSuffix)"
        default:
            return title
        }
    }

    /// Render a whole session preview: title header, template byline, then
    /// one `renderStep` block per step in session order (numbered 1-based).
    public static func renderGuide(session: StepSession, template: GuideTemplate) -> String {
        var blocks = ["# \(session.title)", "_\(template.label)_ — \(template.copy)"]
        for (offset, step) in session.steps.enumerated() {
            blocks.append(renderStep(step: step, index: offset + 1, template: template))
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    /// Action verb for the reference target line. Mirrors
    /// `FlowlineHaloResolver.verb(for:)` (kept local so this target imports
    /// only Foundation + FlowlineIR).
    public static func verb(for step: Step) -> String {
        switch step.action {
        case .click: return "Click"
        case .rightClick: return "Right-click"
        case .doubleClick: return "Double-click"
        case .keyPress: return step.hotkeyCombo ?? "Press"
        case .typing: return "Type"
        case .writeCode: return "Write"
        case .appSwitch: return "Open"
        case .mouseDrag: return "Drag"
        case .manual: return "Do"
        }
    }

    /// Target noun for the reference target line. Mirrors
    /// `FlowlineHaloResolver.target(for:)`.
    public static func target(for step: Step) -> String {
        if let elementTitle = step.elementTitle, !elementTitle.isEmpty {
            return elementTitle
        }
        if !step.windowTitle.isEmpty {
            return step.windowTitle
        }
        if !step.appName.isEmpty {
            return step.appName
        }
        return "target"
    }
}
