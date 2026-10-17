//! Prompt templates — byte-identical port of `PromptTemplates.swift`.
//!
//! Whitespace/newlines mirror the Swift multiline literals exactly; see the
//! parity test against `shared/goldens/gateway.payload.json`.

use stepit_ir::StepSession;

/// Mirror of Swift `DocumentationStyle` (raw values identical).
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum DocumentationStyle {
    #[serde(rename = "sop_guide")]
    SopGuide,
    #[serde(rename = "bug_report")]
    BugReport,
    #[serde(rename = "automation_script")]
    AutomationScript,
    #[serde(rename = "executive_summary")]
    ExecutiveSummary,
}

impl DocumentationStyle {
    /// Mirror of Swift `displayName`.
    #[must_use]
    pub const fn display_name(self) -> &'static str {
        match self {
            Self::SopGuide => "SOP / How-To Guide",
            Self::BugReport => "Bug Reproduction Report",
            Self::AutomationScript => "Automation Script (Bash / Python)",
            Self::ExecutiveSummary => "Executive Summary",
        }
    }

    /// Mirror of Swift `rawValue`.
    #[must_use]
    pub const fn raw_value(self) -> &'static str {
        match self {
            Self::SopGuide => "sop_guide",
            Self::BugReport => "bug_report",
            Self::AutomationScript => "automation_script",
            Self::ExecutiveSummary => "executive_summary",
        }
    }
}

/// Mirror of Swift `PromptTemplates.baseSystemPrompt` (verbatim, no trailing newline).
pub const BASE_SYSTEM_PROMPT: &str = "You are StepIt AI, a world-class technical writer and systems documentation expert.\nYour job is to transform raw user workflow interaction steps (containing app names, window titles, element titles/roles, coordinates, and screenshots) into crystal-clear, professional documentation.\n\nFormatting Guidelines:\n- Use clean GitHub-flavored Markdown.\n- Provide a clear, actionable title and brief overview.\n- Include prerequisites or environment requirements if relevant.\n- Group steps logically with sequential numbered headings (e.g. `### Step 1: Open Settings`).\n- Highlight important UI targets in **bold** or inline code `like this`.\n- Reference captured assets cleanly using standard markdown images: `![Step X Description](<asset_path>)`.\n- Include pro-tips, warnings, or callout notes where user mistakes are common.\n- Keep tone concise, professional, and easy to follow.";

/// Mirror of `PromptTemplates.systemPrompt(for:)`.
#[must_use]
pub fn system_prompt(style: DocumentationStyle) -> String {
    match style {
        DocumentationStyle::SopGuide => {
            format!(
                "{BASE_SYSTEM_PROMPT}\n\nGoal: Create a step-by-step Standard Operating Procedure (SOP) or How-To tutorial."
            )
        }
        DocumentationStyle::BugReport => {
            format!(
                "{BASE_SYSTEM_PROMPT}\n\nGoal: Create a formal QA / Bug Reproduction Report.\nInclude:\n1. Summary & Environment info.\n2. Steps to Reproduce (numbered, precise).\n3. Expected Behavior vs. Actual Behavior observed in the flow.\n4. UI element state at each step and relevant error states."
            )
        }
        DocumentationStyle::AutomationScript => {
            format!(
                "{BASE_SYSTEM_PROMPT}\n\nGoal: Generate executable automation scripts (such as Bash, Python with pyautogui or Playwright, or AppleScript/osascript) that replicate the recorded user workflow.\nProvide complete, well-commented code blocks with explanations."
            )
        }
        DocumentationStyle::ExecutiveSummary => {
            format!(
                "{BASE_SYSTEM_PROMPT}\n\nGoal: Create a high-level executive overview summarizing the business workflow, tools touched, and process efficiency."
            )
        }
    }
}

/// Swift `CharacterSet.whitespaces` (space-ish, NOT newlines): U+0020, U+0009,
/// U+00A0, U+1680, U+2000–U+200A, U+202F, U+205F, U+3000.
fn is_swift_whitespace(c: char) -> bool {
    matches!(
        c,
        '\u{20}'
            | '\u{09}'
            | '\u{A0}'
            | '\u{1680}'
            | '\u{2000}'
            | '\u{2001}'
            | '\u{2002}'
            | '\u{2003}'
            | '\u{2004}'
            | '\u{2005}'
            | '\u{2006}'
            | '\u{2007}'
            | '\u{2008}'
            | '\u{2009}'
            | '\u{200A}'
            | '\u{202F}'
            | '\u{205F}'
            | '\u{3000}'
    )
}

/// Mirror of `PromptTemplates.userPrompt(for:style:customInstructions:)`.
///
/// `style` is unused by Swift (kept for signature parity). `custom` mirrors
/// the optional `customInstructions`, including the whitespaces-only (but not
/// newlines-only) suppression check.
#[must_use]
pub fn user_prompt(
    session: &StepSession,
    _style: DocumentationStyle,
    custom_instructions: Option<&str>,
    recorded_at_display: &str,
) -> String {
    let mut buffer =
        String::from("Synthesize the following recorded user workflow into documentation.\n");
    buffer.push_str(&format!("Workflow Title: {}\n", session.title));
    buffer.push_str(&format!("Recorded At: {recorded_at_display}\n"));
    buffer.push_str(&format!("Total Steps: {}\n", session.steps.len()));

    if let Some(custom) = custom_instructions {
        if !custom.is_empty() && !custom.chars().all(is_swift_whitespace) {
            buffer.push_str(&format!("\nSpecial User Instructions:\n{custom}\n"));
        }
    }

    buffer.push_str("\nCaptured Steps Metadata:\n");
    for step in &session.steps {
        buffer.push_str("---\n");
        buffer.push_str(&format!("Step {}:\n", step.index));
        buffer.push_str(&format!("- Action: {}\n", step.action.raw_value()));
        let bundle = step
            .bundle_identifier
            .as_deref()
            .map_or_else(String::new, |b| format!("({b})"));
        buffer.push_str(&format!("- App: {} {}\n", step.app_name, bundle));
        buffer.push_str(&format!("- Window: \"{}\"\n", step.window_title));
        let target = step
            .element_title
            .as_deref()
            .map_or_else(String::new, |t| format!("\"{t}\""));
        buffer.push_str(&format!(
            "- Target Element: {} {}\n",
            step.element_role.as_deref().unwrap_or("Unknown"),
            target
        ));
        let coords = step.coordinates.map_or_else(
            || "N/A".to_owned(),
            // Swift `Int(x)` truncates toward zero, same as `as i64` here.
            #[allow(clippy::cast_possible_truncation)]
            |c| format!("({}, {})", c.x as i64, c.y as i64),
        );
        buffer.push_str(&format!("- Coordinates: {coords}\n"));
        buffer.push_str(&format!("- Auto Description: {}", step.action_description));
        if let Some(blob) = step.text_blob.as_deref() {
            if !blob.is_empty() {
                buffer.push_str(&format!(
                    "\n- Captured Code / Text Blob ({}):\n```{}\n{blob}\n```",
                    step.code_language.as_deref().unwrap_or("text"),
                    step.code_language.as_deref().unwrap_or("")
                ));
            }
        }
        if let Some(notes) = step.user_notes.as_deref() {
            if !notes.is_empty() {
                buffer.push_str(&format!("\n- User Notes: {notes}"));
            }
        }
        if let Some(screenshot) = step.assets.screenshot.as_deref() {
            buffer.push_str(&format!("\n- Screenshot Asset: {screenshot}"));
        }
        if let Some(gif) = step.assets.gif.as_deref() {
            buffer.push_str(&format!("\n- Animated GIF Asset: {gif}"));
        }
        buffer.push('\n');
    }

    buffer
}
