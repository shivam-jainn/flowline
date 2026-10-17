//! Port of `Model/StepSession.swift`.
//!
//! Includes the pure `Step::synthesize_default_description` logic, ported
//! branch-for-branch from Swift (terminal/code/notification/role-fallback).

use serde::{Deserialize, Serialize};

use crate::events::Point2D;

/// Capture media mode.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum MediaMode {
    /// Hybrid (screenshots + GIFs).
    #[serde(rename = "hybrid")]
    Hybrid,
    /// Static screenshots only.
    #[serde(rename = "static")]
    StaticOnly,
    /// Animated GIFs only.
    #[serde(rename = "animated")]
    AnimatedOnly,
}

impl MediaMode {
    /// Human-readable display name.
    pub fn display_name(self) -> &'static str {
        match self {
            Self::Hybrid => "Hybrid (Screenshots + GIFs)",
            Self::StaticOnly => "Static Screenshots Only",
            Self::AnimatedOnly => "Animated GIFs Only",
        }
    }
}

/// Export theme name.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ThemeName {
    /// Modern minimalist theme.
    #[serde(rename = "modern-minimal")]
    ModernMinimal,
    /// Developer dark theme.
    #[serde(rename = "developer-dark")]
    DeveloperDark,
    /// Enterprise SOP theme.
    #[serde(rename = "enterprise-sop")]
    EnterpriseSop,
}

impl ThemeName {
    /// Human-readable display name.
    pub fn display_name(self) -> &'static str {
        match self {
            Self::ModernMinimal => "Modern Minimalist",
            Self::DeveloperDark => "Developer Dark",
            Self::EnterpriseSop => "Enterprise SOP",
        }
    }
}

/// Screen coordinates in points.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ScreenCoordinates {
    /// x coordinate.
#[serde(serialize_with = "crate::numbers::serialize_f64")]
    pub x: f64,
    /// y coordinate.
#[serde(serialize_with = "crate::numbers::serialize_f64")]
    pub y: f64,
}

impl ScreenCoordinates {
    /// Build coordinates (mirrors Swift `init(x:y:)`).
    pub fn new(x: f64, y: f64) -> Self {
        Self { x, y }
    }
}

/// Rectangular frame in screen points.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ElementRect {
    /// Origin x.
#[serde(serialize_with = "crate::numbers::serialize_f64")]
    pub x: f64,
    /// Origin y.
#[serde(serialize_with = "crate::numbers::serialize_f64")]
    pub y: f64,
    /// Width.
#[serde(serialize_with = "crate::numbers::serialize_f64")]
    pub width: f64,
    /// Height.
#[serde(serialize_with = "crate::numbers::serialize_f64")]
    pub height: f64,
}

impl ElementRect {
    /// Build a rect.
    pub fn new(x: f64, y: f64, width: f64, height: f64) -> Self {
        Self {
            x,
            y,
            width,
            height,
        }
    }

    /// Geometric center in the same (screen-point) coordinate space.
    pub fn center(self) -> Point2D {
        Point2D::new(self.x + self.width / 2.0, self.y + self.height / 2.0)
    }
}

/// Media assets attached to a step.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct MediaAssets {
    /// Screenshot path.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub screenshot: Option<String>,
    /// GIF path.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub gif: Option<String>,
    /// WebM path.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub webm: Option<String>,
    /// Zoom-crop path.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub zoom_crop: Option<String>,
    /// Pre-redaction screenshot kept for non-destructive redaction toggle.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub screenshot_original: Option<String>,
}

/// Documented user action vocabulary.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ActionType {
    /// Single click.
    Click,
    /// Right click.
    RightClick,
    /// Double click.
    DoubleClick,
    /// Hotkey press.
    KeyPress,
    /// Freeform typing.
    Typing,
    /// Code authoring / terminal command.
    WriteCode,
    /// Application switch.
    AppSwitch,
    /// Mouse drag.
    MouseDrag,
    /// Manually added step.
    Manual,
}

impl ActionType {
    /// Swift `ActionType.rawValue` (identical to the serde encoding).
    #[must_use]
    pub const fn raw_value(self) -> &'static str {
        match self {
            Self::Click => "click",
            Self::RightClick => "right_click",
            Self::DoubleClick => "double_click",
            Self::KeyPress => "key_press",
            Self::Typing => "typing",
            Self::WriteCode => "write_code",
            Self::AppSwitch => "app_switch",
            Self::MouseDrag => "mouse_drag",
            Self::Manual => "manual",
        }
    }
}

/// One documented workflow step.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Step {
    /// Step identifier.
    pub id: String,
    /// 1-based position in the session.
    pub index: i64,
    /// ISO-8601 timestamp string.
    pub timestamp: String,
    /// Documented action.
    pub action: ActionType,
    /// Application name.
    #[serde(default)]
    pub app_name: String,
    /// Bundle identifier when known.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub bundle_identifier: Option<String>,
    /// Window title.
    #[serde(default)]
    pub window_title: String,
    /// Element role when known.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub element_role: Option<String>,
    /// Element title when known.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub element_title: Option<String>,
    /// Element value when known.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub element_value: Option<String>,
    /// Click/drag coordinates when known.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub coordinates: Option<ScreenCoordinates>,
    /// Window bounds when known.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub window_bounds: Option<ElementRect>,
    /// Element bounds when known.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub element_bounds: Option<ElementRect>,
    /// Rendered step description.
    #[serde(default)]
    pub action_description: String,
    /// User-authored notes.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub user_notes: Option<String>,
    /// Typed/command text blob.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text_blob: Option<String>,
    /// Whether the blob is code.
    #[serde(default)]
    pub is_code: bool,
    /// Code language tag when known.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub code_language: Option<String>,
    /// Attached media.
    #[serde(default)]
    pub assets: MediaAssets,
    /// Terminal working directory when known.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub working_directory: Option<String>,
    /// Rendered hotkey combo for `.keyPress` steps.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hotkey_combo: Option<String>,
    /// Whether OCR redaction blurred this step's media.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub is_redacted: Option<bool>,
}

impl Step {
    /// Synthesize the default description, mirroring Swift's
    /// `Step.synthesizeDefaultDescription` branch-for-branch.
    #[allow(clippy::too_many_arguments)]
    pub fn synthesize_default_description(
        action: ActionType,
        element_title: Option<&str>,
        element_role: Option<&str>,
        app_name: &str,
        window_title: &str,
        text_blob: Option<&str>,
        is_code: bool,
    ) -> String {
        if action == ActionType::Typing || action == ActionType::WriteCode {
            let target_app = if app_name.is_empty() {
                "editor".to_string()
            } else {
                app_name.to_string()
            };
            let lower = target_app.to_lowercase();
            let is_terminal_app = lower.contains("terminal")
                || lower.contains("iterm")
                || lower.contains("warp")
                || lower.contains("ghostty")
                || lower.contains("kitty")
                || lower.contains("alacritty");

            if let Some(blob) = text_blob {
                if !blob.is_empty() {
                    let clean = blob
                        .trim_matches(|c: char| c.is_whitespace())
                        .to_string();
                    let preview: String = clean.chars().take(40).collect();
                    let suffix = if clean.chars().count() > 40 {
                        "..."
                    } else {
                        ""
                    };
                    let looks_like_command = clean.starts_with("npm ")
                        || clean.starts_with("git ")
                        || clean.starts_with("swift ")
                        || clean.starts_with("cd ")
                        || clean.starts_with("cat ")
                        || clean.starts_with("ls")
                        || clean.starts_with("curl")
                        || clean.starts_with("docker");
                    if is_terminal_app || is_code && looks_like_command {
                        return format!("Run \"{preview}{suffix}\" in {target_app}");
                    } else if is_code {
                        return format!("Write code in {target_app}");
                    } else {
                        return format!("Type \"{preview}{suffix}\" in {target_app}");
                    }
                }
            }
            if is_terminal_app {
                return format!("Execute command in {target_app}");
            } else if is_code {
                return format!("Write code in {target_app}");
            } else {
                return format!("Type text in {target_app}");
            }
        }

        // Notification Center interactions.
        // Note: Swift trims `.whitespaces` here (vs `.whitespacesAndNewlines`
        // above); Rust `trim` covers both, diverging only for titles made
        // solely of newlines.
        if app_name.contains("UserNotificationCenter") || app_name.contains("Notification") {
            if let Some(title) = element_title {
                if !title.trim().is_empty() {
                    return format!("Click notification \"{title}\"");
                }
            }
            return "Click system notification".to_string();
        }

        let action_word = match action {
            ActionType::Click => "Click",
            ActionType::RightClick => "Right-click",
            ActionType::DoubleClick => "Double-click",
            ActionType::KeyPress => "Press",
            ActionType::Typing => "Type in",
            ActionType::WriteCode => "Write code in",
            ActionType::AppSwitch => "Switch to",
            ActionType::MouseDrag => "Drag in",
            ActionType::Manual => "Perform step in",
        };

        let mut target_desc = String::new();
        if let Some(title) = element_title {
            if !title.trim().is_empty() {
                target_desc = format!("\"{title}\"");
            }
        }
        if target_desc.is_empty() {
            if let Some(role) = element_role {
                target_desc = role.replace("AX", "").to_lowercase();
            }
        }

        let context = if !window_title.is_empty() {
            format!(" in {window_title}")
        } else if !app_name.is_empty() {
            format!(" in {app_name}")
        } else {
            String::new()
        };

        if target_desc.is_empty() {
            format!("{action_word}{context}")
        } else {
            format!("{action_word} {target_desc}{context}")
        }
    }

    /// Fill `action_description` with the synthesized default when empty,
    /// mirroring Swift's `Step.init` behavior.
    pub fn ensure_description(&mut self) {
        if self.action_description.is_empty() {
            self.action_description = Self::synthesize_default_description(
                self.action,
                self.element_title.as_deref(),
                self.element_role.as_deref(),
                &self.app_name.clone(),
                &self.window_title.clone(),
                self.text_blob.as_deref(),
                self.is_code,
            );
        }
    }
}

/// Export output paths.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ExportPaths {
    /// PDF export path.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pdf: Option<String>,
    /// Web export path.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub web: Option<String>,
    /// Markdown export path.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub markdown: Option<String>,
}

/// One recorded workflow session.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StepSession {
    /// Session identifier.
    pub id: String,
    /// ISO-8601 start timestamp.
    pub started_at: String,
    /// ISO-8601 end timestamp when finished.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ended_at: Option<String>,
    /// Session title.
    #[serde(default = "default_session_title")]
    pub title: String,
    /// Session summary when set.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub summary: Option<String>,
    /// Export theme.
    #[serde(default = "default_theme")]
    pub theme: ThemeName,
    /// Capture media mode.
    #[serde(default = "default_media_mode")]
    pub media_mode: MediaMode,
    /// Documented steps.
    #[serde(default)]
    pub steps: Vec<Step>,
    /// Export outputs.
    #[serde(default)]
    pub exports: ExportPaths,
    /// Synthesized markdown when generated.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub synthesized_markdown: Option<String>,
}

fn default_session_title() -> String {
    "Workflow Recording".to_string()
}

fn default_theme() -> ThemeName {
    ThemeName::ModernMinimal
}

fn default_media_mode() -> MediaMode {
    MediaMode::Hybrid
}

impl StepSession {
    /// Build a new empty session.
    pub fn new(id: String, started_at: String) -> Self {
        Self {
            id,
            started_at,
            ended_at: None,
            title: default_session_title(),
            summary: None,
            theme: ThemeName::ModernMinimal,
            media_mode: MediaMode::Hybrid,
            steps: Vec::new(),
            exports: ExportPaths::default(),
            synthesized_markdown: None,
        }
    }
}
