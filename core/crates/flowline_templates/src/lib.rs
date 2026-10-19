//! `flowline_templates` — Rust port of Swift `Sources/FlowlineTemplates/`.
//!
//! Plugin-based guide-template core: one [`GuideTemplate`] per guide mode
//! (data mirror of `templates/<id>/manifest.json`, validated by
//! `shared/contracts/template.schema.json`) plus the pure preview-text
//! renderer ([`render_step`]/[`render_guide`], "how text will look").
//!
//! The renderer is branch-for-branch identical to Swift
//! `TemplateRenderer`: unknown template ids fall back to standard, title
//! uppercasing is locale-independent on both sides (Swift pins
//! `en_US_POSIX`; Rust `to_uppercase` is locale-independent), and render
//! parity is pinned by `shared/goldens/templates.sample.json`.

use flowline_ir::session::{ActionType, Step, StepSession};
use serde::{Deserialize, Serialize};

/// One guide-mode template. Field shapes mirror Swift
/// `FlowlineTemplates.GuideTemplate` (serde camelCase, like the IR).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GuideTemplate {
    /// Guide mode id (`standard`, `checklist`, `sop`, `tutorial`,
    /// `runbook`, `presentation`, `reference`).
    pub id: String,
    /// Display label.
    pub label: String,
    /// One-line mode description.
    pub copy: String,
    /// `FlowlineIR.ThemeName` raw value.
    pub theme: String,
    /// `FlowlineAIGateway.DocumentationStyle` raw value.
    pub synthesis_style: String,
    /// Render quirks (`checklist-markers`, `numbered-steps`,
    /// `guidance-notes`, `code-fence`, `uppercase-titles`, `target-line`).
    #[serde(default)]
    pub quirks: Vec<String>,
    /// Whether the mode renders tickable boxes.
    #[serde(default)]
    pub supports_checklist: bool,
    /// Whether the mode renders code fences.
    #[serde(default)]
    pub shows_code: bool,
    /// Whether the mode renders `verb → target · app` lines.
    #[serde(default)]
    pub shows_target_line: bool,
    /// Whether the mode renders large (uppercased) titles.
    #[serde(default)]
    pub large_titles: bool,
}

impl GuideTemplate {
    /// Build a template with all capability flags cleared.
    pub fn new(id: &str, label: &str, copy: &str, theme: &str, synthesis_style: &str) -> Self {
        Self {
            id: id.to_string(),
            label: label.to_string(),
            copy: copy.to_string(),
            theme: theme.to_string(),
            synthesis_style: synthesis_style.to_string(),
            quirks: Vec::new(),
            supports_checklist: false,
            shows_code: false,
            shows_target_line: false,
            large_titles: false,
        }
    }

    /// The 7 built-in guide modes. Labels, copy, themes and synthesis styles
    /// mirror Swift `GuideTemplate.all` (which mirrors `FlowlineGuideMode`).
    pub fn all() -> Vec<GuideTemplate> {
        vec![
            GuideTemplate::new(
                "standard",
                "Standard guide",
                "Visual and explanation for every Step.",
                "modern-minimal",
                "sop_guide",
            ),
            GuideTemplate {
                quirks: vec!["checklist-markers".to_string()],
                supports_checklist: true,
                ..GuideTemplate::new(
                    "checklist",
                    "Checklist",
                    "A tickable list of everything to do.",
                    "modern-minimal",
                    "sop_guide",
                )
            },
            GuideTemplate {
                quirks: vec!["numbered-steps".to_string()],
                ..GuideTemplate::new(
                    "sop",
                    "SOP",
                    "Action-oriented structured instructions.",
                    "enterprise-sop",
                    "sop_guide",
                )
            },
            GuideTemplate {
                quirks: vec!["guidance-notes".to_string()],
                ..GuideTemplate::new(
                    "tutorial",
                    "Tutorial",
                    "More explanatory, written for a first run.",
                    "modern-minimal",
                    "sop_guide",
                )
            },
            GuideTemplate {
                quirks: vec!["code-fence".to_string()],
                shows_code: true,
                ..GuideTemplate::new(
                    "runbook",
                    "Runbook",
                    "Step, command, expected result, verification.",
                    "enterprise-sop",
                    "bug_report",
                )
            },
            GuideTemplate {
                quirks: vec!["uppercase-titles".to_string()],
                large_titles: true,
                ..GuideTemplate::new(
                    "presentation",
                    "Presentation",
                    "Large visuals with minimal text.",
                    "developer-dark",
                    "executive_summary",
                )
            },
            GuideTemplate {
                quirks: vec!["target-line".to_string()],
                shows_target_line: true,
                ..GuideTemplate::new(
                    "reference",
                    "Reference",
                    "Compact, searchable summary.",
                    "modern-minimal",
                    "automation_script",
                )
            },
        ]
    }

    /// Look up a built-in template by mode id. Returns `None` for unknown
    /// ids so callers can fall back to standard rendering.
    pub fn make(id: &str) -> Option<GuideTemplate> {
        Self::all().into_iter().find(|t| t.id == id)
    }
}

/// Error parsing or validating a `templates/<id>/manifest.json` file.
///
/// Minimal validation mirror of `shared/contracts/template.schema.json`:
/// required `id` / `version` / `label` / `copy` / `theme` /
/// `synthesisStyle` (all non-empty strings), `theme` / `synthesisStyle`
/// restricted to their schema enums, and `quirks` (when present) a string
/// array. Pure `&str` in, no file I/O, no unsafe.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ManifestError {
    /// The input was not valid JSON (or not a JSON object).
    #[error("invalid JSON: {0}")]
    InvalidJson(String),
    /// A required field is absent.
    #[error("missing required field `{0}`")]
    MissingField(&'static str),
    /// A field is present but has the wrong type/value.
    #[error("invalid field `{field}`: {reason}")]
    InvalidField { field: &'static str, reason: String },
}

/// Allowed `theme` values (`$defs/ThemeName` in the schema).
const KNOWN_THEMES: &[&str] = &["modern-minimal", "developer-dark", "enterprise-sop"];

/// Allowed `synthesisStyle` values (`$defs/DocumentationStyle`).
const KNOWN_SYNTHESIS_STYLES: &[&str] = &[
    "sop_guide",
    "bug_report",
    "automation_script",
    "executive_summary",
];

fn required_string<'a>(
    obj: &'a serde_json::Map<String, serde_json::Value>,
    field: &'static str,
) -> Result<&'a str, ManifestError> {
    let value = obj.get(field).ok_or(ManifestError::MissingField(field))?;
    let s = value.as_str().ok_or_else(|| ManifestError::InvalidField {
        field,
        reason: "expected a string".to_string(),
    })?;
    if s.is_empty() {
        return Err(ManifestError::InvalidField {
            field,
            reason: "must not be empty".to_string(),
        });
    }
    Ok(s)
}

/// Validate a `manifest.json` document (as a string) against the minimal
/// schema subset. Returns `Ok(())` when the document has all required
/// string fields plus valid `theme` / `synthesisStyle` enums.
///
/// Takes `&str` only — callers do the file I/O (e.g. via `include_str!` or
/// `CARGO_MANIFEST_DIR`-relative reads).
pub fn validate_manifest(json: &str) -> Result<(), ManifestError> {
    let value: serde_json::Value =
        serde_json::from_str(json).map_err(|e| ManifestError::InvalidJson(e.to_string()))?;
    let obj = value
        .as_object()
        .ok_or_else(|| ManifestError::InvalidJson("expected a JSON object".to_string()))?;
    let _ = required_string(obj, "id")?;
    let _ = required_string(obj, "version")?;
    let _ = required_string(obj, "label")?;
    let _ = required_string(obj, "copy")?;
    let theme = required_string(obj, "theme")?;
    if !KNOWN_THEMES.contains(&theme) {
        return Err(ManifestError::InvalidField {
            field: "theme",
            reason: format!("unknown theme `{theme}`"),
        });
    }
    let style = required_string(obj, "synthesisStyle")?;
    if !KNOWN_SYNTHESIS_STYLES.contains(&style) {
        return Err(ManifestError::InvalidField {
            field: "synthesisStyle",
            reason: format!("unknown synthesisStyle `{style}`"),
        });
    }
    if let Some(quirks) = obj.get("quirks") {
        let arr = quirks
            .as_array()
            .ok_or_else(|| ManifestError::InvalidField {
                field: "quirks",
                reason: "expected an array of strings".to_string(),
            })?;
        for entry in arr {
            if entry.as_str().is_none() {
                return Err(ManifestError::InvalidField {
                    field: "quirks",
                    reason: "expected an array of strings".to_string(),
                });
            }
        }
    }
    Ok(())
}

/// Parse a `manifest.json` document (as a string) into a [`GuideTemplate`],
/// validating per [`validate_manifest`] first.
///
/// Capability flags are derived from `quirks` so file-loaded templates
/// equal the [`GuideTemplate::all`] catalogue entries (`checklist-markers`
/// → `supports_checklist`, `code-fence` → `shows_code`, `target-line` →
/// `shows_target_line`, `uppercase-titles` → `large_titles`).
///
/// Takes `&str` only — callers do the file I/O (e.g. via `include_str!` or
/// `CARGO_MANIFEST_DIR`-relative reads).
pub fn load_manifest_json(json: &str) -> Result<GuideTemplate, ManifestError> {
    validate_manifest(json)?;
    let mut template: GuideTemplate =
        serde_json::from_str(json).map_err(|e| ManifestError::InvalidJson(e.to_string()))?;
    template.supports_checklist = template.quirks.iter().any(|q| q == "checklist-markers");
    template.shows_code = template.quirks.iter().any(|q| q == "code-fence");
    template.shows_target_line = template.quirks.iter().any(|q| q == "target-line");
    template.large_titles = template.quirks.iter().any(|q| q == "uppercase-titles");
    Ok(template)
}

/// Action verb for the reference target line. Mirrors Swift
/// `TemplateRenderer.verb(for:)` (which mirrors
/// `FlowlineHaloResolver.verb(for:)`).
pub fn verb(step: &Step) -> String {
    match step.action {
        ActionType::Click => "Click".to_string(),
        ActionType::RightClick => "Right-click".to_string(),
        ActionType::DoubleClick => "Double-click".to_string(),
        ActionType::KeyPress => step
            .hotkey_combo
            .clone()
            .unwrap_or_else(|| "Press".to_string()),
        ActionType::Typing => "Type".to_string(),
        ActionType::WriteCode => "Write".to_string(),
        ActionType::AppSwitch => "Open".to_string(),
        ActionType::MouseDrag => "Drag".to_string(),
        ActionType::Manual => "Do".to_string(),
    }
}

/// Target noun for the reference target line. Mirrors Swift
/// `TemplateRenderer.target(for:)`.
pub fn target(step: &Step) -> String {
    if let Some(title) = step.element_title.as_deref() {
        if !title.is_empty() {
            return title.to_string();
        }
    }
    if !step.window_title.is_empty() {
        return step.window_title.clone();
    }
    if !step.app_name.is_empty() {
        return step.app_name.clone();
    }
    "target".to_string()
}

/// Step description, synthesizing the default when the stored one is empty
/// (mirrors Swift `Step.init`, which fills it at construction time).
fn description(step: &Step) -> String {
    if !step.action_description.is_empty() {
        return step.action_description.clone();
    }
    Step::synthesize_default_description(
        step.action,
        step.element_title.as_deref(),
        step.element_role.as_deref(),
        &step.app_name,
        &step.window_title,
        step.text_blob.as_deref(),
        step.is_code,
    )
}

/// Render one step for the "how text will look" preview. `index` is the
/// 1-based display number. Unknown template ids fall back to standard.
pub fn render_step(step: &Step, index: i64, template: &GuideTemplate) -> String {
    let desc = description(step);
    let title = format!("Step {index}: {desc}");
    match template.id.as_str() {
        "checklist" => format!("- [ ] {title}"),
        "sop" => format!("{index}. {desc}"),
        "tutorial" => {
            let mut lines = vec![title];
            if let Some(notes) = step.user_notes.as_deref() {
                if !notes.is_empty() {
                    lines.push(format!("  Tip: {notes}"));
                }
            }
            let context = if !step.app_name.is_empty() && !step.window_title.is_empty() {
                format!("  ({} · {})", step.app_name, step.window_title)
            } else if !step.app_name.is_empty() {
                format!("  ({})", step.app_name)
            } else if !step.window_title.is_empty() {
                format!("  ({})", step.window_title)
            } else {
                String::new()
            };
            if !context.is_empty() {
                lines.push(context);
            }
            lines.join("\n")
        }
        "runbook" => {
            let mut lines = vec![title];
            if let Some(blob) = step.text_blob.as_deref() {
                if !blob.is_empty() {
                    let language = match step.code_language.as_deref() {
                        Some(lang) if !lang.is_empty() => lang.to_string(),
                        _ if step.is_code => "bash".to_string(),
                        _ => String::new(),
                    };
                    lines.push(format!("```{language}\n{blob}\n```"));
                }
            }
            if let Some(combo) = step.hotkey_combo.as_deref() {
                if !combo.is_empty() {
                    lines.push(format!("  Keys: {combo}"));
                }
            }
            lines.join("\n")
        }
        "presentation" => title.to_uppercase(),
        "reference" => {
            let app_suffix = if step.app_name.is_empty() {
                String::new()
            } else {
                format!(" · {}", step.app_name)
            };
            format!("{title}\n{} → {}{app_suffix}", verb(step), target(step))
        }
        _ => title,
    }
}

/// Render a whole session preview: title header, template byline, then one
/// [`render_step`] block per step in session order (numbered 1-based).
pub fn render_guide(session: &StepSession, template: &GuideTemplate) -> String {
    let mut blocks = vec![
        format!("# {}", session.title),
        format!("_{}_ — {}", template.label, template.copy),
    ];
    for (offset, step) in session.steps.iter().enumerate() {
        blocks.push(render_step(step, offset as i64 + 1, template));
    }
    let mut out = blocks.join("\n\n");
    out.push('\n');
    out
}
