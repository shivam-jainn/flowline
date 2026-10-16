import Foundation

public enum DocumentationStyle: String, Codable, CaseIterable, Sendable {
    case sopGuide = "sop_guide"
    case bugReport = "bug_report"
    case automationScript = "automation_script"
    case executiveSummary = "executive_summary"
    
    public var displayName: String {
        switch self {
        case .sopGuide: return "SOP / How-To Guide"
        case .bugReport: return "Bug Reproduction Report"
        case .automationScript: return "Automation Script (Bash / Python)"
        case .executiveSummary: return "Executive Summary"
        }
    }
}

public struct PromptTemplates {
    public static let baseSystemPrompt = """
You are StepIt AI, a world-class technical writer and systems documentation expert.
Your job is to transform raw user workflow interaction steps (containing app names, window titles, element titles/roles, coordinates, and screenshots) into crystal-clear, professional documentation.

Formatting Guidelines:
- Use clean GitHub-flavored Markdown.
- Provide a clear, actionable title and brief overview.
- Include prerequisites or environment requirements if relevant.
- Group steps logically with sequential numbered headings (e.g. `### Step 1: Open Settings`).
- Highlight important UI targets in **bold** or inline code `like this`.
- Reference captured assets cleanly using standard markdown images: `![Step X Description](<asset_path>)`.
- Include pro-tips, warnings, or callout notes where user mistakes are common.
- Keep tone concise, professional, and easy to follow.
"""

    public static func systemPrompt(for style: DocumentationStyle) -> String {
        switch style {
        case .sopGuide:
            return baseSystemPrompt + "\n\nGoal: Create a step-by-step Standard Operating Procedure (SOP) or How-To tutorial."
        case .bugReport:
            return baseSystemPrompt + """
\n\nGoal: Create a formal QA / Bug Reproduction Report.
Include:
1. Summary & Environment info.
2. Steps to Reproduce (numbered, precise).
3. Expected Behavior vs. Actual Behavior observed in the flow.
4. UI element state at each step and relevant error states.
"""
        case .automationScript:
            return baseSystemPrompt + """
\n\nGoal: Generate executable automation scripts (such as Bash, Python with pyautogui or Playwright, or AppleScript/osascript) that replicate the recorded user workflow.
Provide complete, well-commented code blocks with explanations.
"""
        case .executiveSummary:
            return baseSystemPrompt + "\n\nGoal: Create a high-level executive overview summarizing the business workflow, tools touched, and process efficiency."
        }
    }
    
    public static func userPrompt(for session: StepSession, style: DocumentationStyle, customInstructions: String? = nil) -> String {
        var buffer = "Synthesize the following recorded user workflow into documentation.\n"
        buffer += "Workflow Title: \(session.title)\n"
        buffer += "Recorded At: \(session.startedAt.formatted())\n"
        buffer += "Total Steps: \(session.steps.count)\n"
        
        if let custom = customInstructions, !custom.trimmingCharacters(in: .whitespaces).isEmpty {
            buffer += "\nSpecial User Instructions:\n\(custom)\n"
        }
        
        buffer += "\nCaptured Steps Metadata:\n"
        for step in session.steps {
            buffer += """
---
Step \(step.index):
- Action: \(step.action.rawValue)
- App: \(step.appName) \(step.bundleIdentifier != nil ? "(\(step.bundleIdentifier!))" : "")
- Window: "\(step.windowTitle)"
- Target Element: \(step.elementRole ?? "Unknown") \(step.elementTitle != nil ? "\"\(step.elementTitle!)\"" : "")
- Coordinates: \(step.coordinates != nil ? "(\(Int(step.coordinates!.x)), \(Int(step.coordinates!.y)))" : "N/A")
- Auto Description: \(step.actionDescription)
"""
            if let notes = step.userNotes, !notes.isEmpty {
                buffer += "\n- User Notes: \(notes)"
            }
            if let screenshot = step.assets.screenshot {
                buffer += "\n- Screenshot Asset: \(screenshot)"
            }
            if let gif = step.assets.gif {
                buffer += "\n- Animated GIF Asset: \(gif)"
            }
            buffer += "\n"
        }
        
        return buffer
    }
}
