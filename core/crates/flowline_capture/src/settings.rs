//! Portable capture configuration (sync port of Swift
//! `Sources/FlowlineCaptureAPI/CaptureSettings.swift`,
//! `GestureSettings.swift`, `HotkeySettings.swift`, plus the
//! pipeline-owned `HotkeyCaptureSettings.swift` / `PrivacySettings.swift`
//! shapes the driver facets consume).
//!
//! All types are pure `serde` data: identical JSON keys/casing to the Swift
//! `Codable` twins so settings files stay interchangeable. Decoding is
//! lenient (every field has a Swift-matching default) so settings written
//! before a newer key existed still load.

use std::collections::BTreeSet;

use serde::{Deserialize, Serialize};

use flowline_ir::MediaMode;

// MARK: - CaptureMode

/// Still-capture framing: a tight per-window shot or the full display.
///
/// Port of Swift `FlowlineIR.CaptureMode` (which lives in IR to break the
/// `ClipBufferConfig` ↔ `CaptureSettings` ↔ driver dependency cycle). It is
/// defined here — not in `flowline_ir` — because the Rust IR crate predates
/// it; hosts map `CaptureSettings.capture_mode` into the driver when
/// building the IR `ClipBufferConfig`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum CaptureMode {
    /// Per-window shot (ScreenCaptureKit window filter on macOS).
    #[default]
    Window,
    /// Full-display framing (legacy).
    Display,
}

impl CaptureMode {
    /// Human-readable display name (mirrors Swift `displayName`).
    pub fn display_name(self) -> &'static str {
        match self {
            Self::Window => "Window",
            Self::Display => "Display",
        }
    }
}

// MARK: - CaptureSettings

fn default_gif_fps() -> i64 {
    15
}
fn default_pre_click_secs() -> f64 {
    0.5
}
fn default_post_click_secs() -> f64 {
    1.5
}
fn default_highlight_clicks() -> bool {
    true
}
fn default_highlight_color_hex() -> String {
    "#EF4444".to_string()
}
fn default_highlight_radius() -> f64 {
    28.0
}
fn default_record_app_switches() -> bool {
    false
}

/// Capture behaviour configuration.
///
/// Port of Swift `FlowlineCaptureAPI.CaptureSettings`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CaptureSettings {
    /// Screenshots + GIFs policy.
    #[serde(default = "default_media_mode")]
    pub media_mode: MediaMode,
    /// GIF frames per second.
    #[serde(default = "default_gif_fps")]
    pub gif_fps: i64,
    /// Pre-click ring-buffer window, in seconds.
    #[serde(
        default = "default_pre_click_secs",
        serialize_with = "flowline_ir_serialize_f64"
    )]
    pub clip_duration_pre_click_sec: f64,
    /// Post-click capture window, in seconds.
    #[serde(
        default = "default_post_click_secs",
        serialize_with = "flowline_ir_serialize_f64"
    )]
    pub clip_duration_post_click_sec: f64,
    /// Paint the click highlight into snapshots.
    #[serde(default = "default_highlight_clicks")]
    pub highlight_clicks: bool,
    /// Highlight color as `#RRGGBB`.
    #[serde(default = "default_highlight_color_hex")]
    pub highlight_color_hex: String,
    /// Highlight radius in screen points.
    #[serde(
        default = "default_highlight_radius",
        serialize_with = "flowline_ir_serialize_f64"
    )]
    pub highlight_radius: f64,
    /// Emit discrete `.appSwitch` steps when the frontmost app changes.
    #[serde(default = "default_record_app_switches")]
    pub record_app_switches: bool,
    /// Window vs. display framing for stills + micro-clips.
    #[serde(default)]
    pub capture_mode: CaptureMode,
}

fn default_media_mode() -> MediaMode {
    MediaMode::Hybrid
}

// `flowline_ir::numbers::serialize_f64` is private to the IR crate, so the
// Swift-compatible whole-double encoding is repeated here (integral doubles
// encode without a decimal point, matching Swift `JSONEncoder`).
fn flowline_ir_serialize_f64<S: serde::Serializer>(
    value: &f64,
    serializer: S,
) -> Result<S::Ok, S::Error> {
    if value.is_finite()
        && value.fract() == 0.0
        && *value >= i64::MIN as f64
        && *value <= i64::MAX as f64
    {
        serializer.serialize_i64(*value as i64)
    } else {
        serializer.serialize_f64(*value)
    }
}

impl Default for CaptureSettings {
    fn default() -> Self {
        Self {
            media_mode: default_media_mode(),
            gif_fps: default_gif_fps(),
            clip_duration_pre_click_sec: default_pre_click_secs(),
            clip_duration_post_click_sec: default_post_click_secs(),
            highlight_clicks: default_highlight_clicks(),
            highlight_color_hex: default_highlight_color_hex(),
            highlight_radius: default_highlight_radius(),
            record_app_switches: default_record_app_switches(),
            capture_mode: CaptureMode::default(),
        }
    }
}

// MARK: - Gesture settings

/// Shake-detection sensitivity tiers (port of Swift `GestureSensitivity`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum GestureSensitivity {
    Low,
    #[default]
    Medium,
    High,
}

impl GestureSensitivity {
    /// Human-readable title (mirrors Swift `title`).
    pub fn title(self) -> &'static str {
        match self {
            Self::Low => "Low (Vigorous Motion)",
            Self::Medium => "Medium (Balanced)",
            Self::High => "High (Quick Response)",
        }
    }

    /// Shake velocity threshold (mirrors Swift `thresholdVelocity`).
    pub fn threshold_velocity(self) -> f64 {
        match self {
            Self::Low => 850.0,
            Self::Medium => 550.0,
            Self::High => 380.0,
        }
    }
}

// Swift `GestureAction` lives in `flowline_ir`; re-exported at the crate root.
use flowline_ir::GestureAction;

/// Hot-corner bindings (port of Swift `HotCornerSettings`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HotCornerSettings {
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default = "default_top_left")]
    pub top_left: GestureAction,
    #[serde(default = "default_top_right")]
    pub top_right: GestureAction,
    #[serde(default = "default_gesture_none")]
    pub bottom_left: GestureAction,
    #[serde(default = "default_bottom_right")]
    pub bottom_right: GestureAction,
}

fn default_true() -> bool {
    true
}
fn default_top_left() -> GestureAction {
    GestureAction::DiscardLastStep
}
fn default_top_right() -> GestureAction {
    GestureAction::PauseResume
}
fn default_gesture_none() -> GestureAction {
    GestureAction::None
}
fn default_bottom_right() -> GestureAction {
    GestureAction::StopAndReview
}

impl Default for HotCornerSettings {
    fn default() -> Self {
        Self {
            enabled: true,
            top_left: GestureAction::DiscardLastStep,
            top_right: GestureAction::PauseResume,
            bottom_left: GestureAction::None,
            bottom_right: GestureAction::StopAndReview,
        }
    }
}

/// Smart-gesture configuration (port of Swift `GestureSettings`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GestureSettings {
    #[serde(default = "default_true")]
    pub shake_to_pause_enabled: bool,
    #[serde(default)]
    pub shake_sensitivity: GestureSensitivity,
    #[serde(default = "default_top_right")]
    pub shake_action: GestureAction,
    #[serde(default)]
    pub hot_corners: HotCornerSettings,
    #[serde(default = "default_middle_click")]
    pub middle_click_action: GestureAction,
    #[serde(default = "default_top_left")]
    pub double_right_click_action: GestureAction,
    #[serde(default = "default_long_press")]
    pub long_press_action: GestureAction,
    #[serde(
        default = "default_long_press_secs",
        serialize_with = "flowline_ir_serialize_f64"
    )]
    pub long_press_duration_sec: f64,
}

fn default_middle_click() -> GestureAction {
    GestureAction::AddCheckpoint
}
fn default_long_press() -> GestureAction {
    GestureAction::CaptureSnapshot
}
fn default_long_press_secs() -> f64 {
    0.8
}

impl Default for GestureSettings {
    fn default() -> Self {
        Self {
            shake_to_pause_enabled: true,
            shake_sensitivity: GestureSensitivity::Medium,
            shake_action: GestureAction::PauseResume,
            hot_corners: HotCornerSettings::default(),
            middle_click_action: GestureAction::AddCheckpoint,
            double_right_click_action: GestureAction::DiscardLastStep,
            long_press_action: GestureAction::CaptureSnapshot,
            long_press_duration_sec: 0.8,
        }
    }
}

// MARK: - Hotkey settings

fn default_toggle_recording() -> String {
    "⌥ Space".to_string()
}

/// Recording-toggle hotkey configuration (port of Swift `HotkeySettings`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HotkeySettings {
    #[serde(default = "default_toggle_recording")]
    pub toggle_recording: String,
}

impl Default for HotkeySettings {
    fn default() -> Self {
        Self {
            toggle_recording: default_toggle_recording(),
        }
    }
}

/// Which keyboard chords become discrete documentation steps.
///
/// Port of Swift `FlowlinePipeline.HotkeyCaptureSettings` (consumed by the
/// `HotkeySettingsSink` driver facet). Defined here so the capture SPI stays
/// independent of `flowline_pipeline`; the pipeline crate owns a policy twin
/// with the same defaults.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct HotkeyCaptureSettings {
    /// Record `⌘`/`⌃` chords (`⌘S`, `⌘⇧P`, …) as `.keyPress` steps.
    #[serde(default = "default_true")]
    pub capture_modifier_shortcuts: bool,
    /// Record navigation keys (Esc, Tab, arrows, F-keys) as `.keyPress` steps.
    #[serde(default = "default_true")]
    pub capture_navigation_keys: bool,
    /// Extra chords the recorder consumes and never records. System combos
    /// like `⌘Tab` / `⌘Space` are always consumed regardless.
    #[serde(default)]
    pub ignored_combos: BTreeSet<String>,
}

// MARK: - Privacy settings

/// Visual treatment applied over detected sensitive regions.
///
/// Port of Swift `FlowlinePipeline.RedactionBlurStyle`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum RedactionBlurStyle {
    #[serde(rename = "frosted_glass")]
    #[default]
    FrostedGlass,
    #[serde(rename = "blackout")]
    Blackout,
}

impl RedactionBlurStyle {
    /// Human-readable display name (mirrors Swift `displayName`).
    pub fn display_name(self) -> &'static str {
        match self {
            Self::FrostedGlass => "Frosted Glass (Gaussian Blur)",
            Self::Blackout => "Solid Blackout",
        }
    }
}

fn default_blur_radius() -> f64 {
    12.0
}

/// Pre-capture (secure field masking) and post-capture (offline OCR
/// redaction) privacy rules.
///
/// Port of Swift `FlowlinePipeline.PrivacySettings`. Defined here (serde)
/// so the `VisualRedactionProviding` facet stays portable; the pipeline
/// crate owns a policy twin with the same defaults.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PrivacySettings {
    /// Mask keystrokes typed into `isSecure` fields as `••••`.
    #[serde(default = "default_true")]
    pub mask_secure_input_fields: bool,
    /// Run the offline OCR pipeline over screenshots and blur sensitive
    /// tokens before they are written to disk.
    #[serde(rename = "enableOfflineOCRRedaction", default = "default_true")]
    pub enable_offline_ocr_redaction: bool,
    /// OpenAI `sk-…`, AWS `AKIA…`, GitHub `ghp_…`, JWTs and bearer tokens.
    #[serde(rename = "autoRedactAPIKeys", default = "default_true")]
    pub auto_redact_api_keys: bool,
    #[serde(default = "default_true")]
    pub auto_redact_credit_cards: bool,
    #[serde(default)]
    pub auto_redact_emails: bool,
    /// Blur radius (in screen points) for `.frostedGlass` redaction.
    #[serde(
        default = "default_blur_radius",
        serialize_with = "flowline_ir_serialize_f64"
    )]
    pub blur_radius: f64,
    /// Frosted glass blur vs. solid blackout.
    #[serde(default)]
    pub blur_style: RedactionBlurStyle,
    /// Extra user-supplied regex patterns, matched case-insensitively.
    #[serde(default)]
    pub custom_regex_patterns: Vec<String>,
}

impl Default for PrivacySettings {
    fn default() -> Self {
        Self {
            mask_secure_input_fields: true,
            enable_offline_ocr_redaction: true,
            auto_redact_api_keys: true,
            auto_redact_credit_cards: true,
            auto_redact_emails: false,
            blur_radius: 12.0,
            blur_style: RedactionBlurStyle::FrostedGlass,
            custom_regex_patterns: Vec::new(),
        }
    }
}
