import Foundation

public final class MarkdownExporter: @unchecked Sendable {
    public static let shared = MarkdownExporter()
    
    public init() {}
    
    public func exportMarkdown(session: StepSession, relativeAssetPrefix: String = "") -> String {
        // If an AI synthesized markdown exists, use it or format it with standard headers
        if let synth = session.synthesizedMarkdown, !synth.trimmingCharacters(in: .whitespaces).isEmpty {
            return synth
        }
        
        // Default clean structured markdown generation
        var md = "# \(session.title)\n\n"
        
        if let summary = session.summary, !summary.isEmpty {
            md += "> \(summary)\n\n"
        }
        
        md += "| Recorded | Steps | Theme | Mode |\n"
        md += "| :--- | :--- | :--- | :--- |\n"
        md += "| \(session.startedAt.formatted()) | \(session.steps.count) | \(session.theme.displayName) | \(session.mediaMode.displayName) |\n\n"
        md += "---\n\n"
        
        md += "## Table of Contents\n\n"
        for step in session.steps {
            let anchor = step.actionDescription
                .lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "'", with: "")
            md += "- [Step \(step.index): \(step.actionDescription)](#step-\(step.index)-\(anchor))\n"
        }
        md += "\n---\n\n"
        
        md += "## Workflow Steps\n\n"
        for step in session.steps {
            md += "### Step \(step.index): \(step.actionDescription)\n\n"
            
            if !step.appName.isEmpty {
                md += "- **Application**: `\(step.appName)`\n"
            }
            if !step.windowTitle.isEmpty {
                md += "- **Window**: *\(step.windowTitle)*\n"
            }
            if let role = step.elementRole {
                let titleDesc = step.elementTitle != nil ? " (`\(step.elementTitle!)`)" : ""
                md += "- **Target Element**: \(role)\(titleDesc)\n"
            }
            if let combo = step.hotkeyCombo {
                md += "- **Shortcut**: `\(combo)`\n"
            }
            if let directory = step.workingDirectory {
                md += "- **Working Directory**: `\(directory)`\n"
            }
            if step.isRedacted == true {
                md += "- **Redacted**: 🛡️ sensitive data blurred offline\n"
            }
            if let coords = step.coordinates {
                md += "- **Coordinates**: (\(Int(coords.x)), \(Int(coords.y)))\n"
            }
            if let notes = step.userNotes, !notes.isEmpty {
                md += "\n> **Note**: \(notes)\n"
            }
            
            if let text = step.textBlob, !text.isEmpty {
                let lang = step.codeLanguage ?? (step.isCode ? "bash" : "")
                md += "\n```\(lang)\n\(text)\n```\n"
            }
            
            md += "\n"
            
            let prefix = relativeAssetPrefix.isEmpty ? "" : (relativeAssetPrefix.hasSuffix("/") ? relativeAssetPrefix : "\(relativeAssetPrefix)/")
            
            // Prefer GIF if animated, or screenshot
            if let gif = step.assets.gif {
                md += "![\(step.actionDescription)](\(prefix)\(gif))\n\n"
            } else if let screenshot = step.assets.screenshot {
                md += "![\(step.actionDescription)](\(prefix)\(screenshot))\n\n"
            }
            if let zoomCrop = step.assets.zoomCrop {
                md += "🔍 *[View 2.4× Focused DOM Zoom Crop](\(prefix)\(zoomCrop))*\n\n"
            }
        }
        
        md += "---\n\n"
        md += "_Documented with [step·it](https://github.com/stepit/stepit) for macOS._\n"
        return md
    }
}
