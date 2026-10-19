//! `flowline_settings` — portable home for the settings vocabulary.
//!
//! Rust port of the settings types that today live only in Swift:
//! `Sources/FlowlineEngine/FlowlineSettings.swift`,
//! `Sources/FlowlineEngine/EngineSettings.swift`,
//! `Sources/FlowlineCaptureAPI/CaptureSettings.swift`,
//! `Sources/FlowlineCaptureAPI/GestureSettings.swift`,
//! `Sources/FlowlineCaptureAPI/HotkeySettings.swift`,
//! `Sources/FlowlinePublishing/PublishingSettings.swift`,
//! `Sources/FlowlinePipeline/PrivacySettings.swift`,
//! `Sources/FlowlinePipeline/HotkeyCaptureSettings.swift`,
//! `Sources/FlowlineAIGateway/GatewaySettings.swift`
//! (plus the IR enums they reference: `MediaMode`, `ThemeName`,
//! `GestureAction`, `CaptureMode`).
//!
//! Own canonical structs (not re-exports): every JSON key and enum raw
//! value is byte-identical to Swift `JSONEncoder` output, `Default`
//! matches each Swift `init` default, and [`FlowlineSettings`] decodes
//! leniently (`decodeIfPresent` → default) so settings files written
//! before Phase 1/2 still load. No I/O, no `unsafe`, no Foundation.

use std::collections::BTreeSet;

use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// Swift-compatible `Double` encoding
// ---------------------------------------------------------------------------
// Mirrors `flowline_ir::numbers::serialize_f64` locally so this crate stays
// a leaf with no IR dependency: Swift's `JSONEncoder` emits integral
// doubles without a decimal point (`12`, not `12.0`).

fn serialize_f64<S: serde::Serializer>(value: &f64, serializer: S) -> Result<S::Ok, S::Error> {
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

// ---------------------------------------------------------------------------
// Small serde default fns (Swift `init` defaults that differ from the Rust
// type default, so partial JSON still decodes like Swift `decodeIfPresent`).
// ---------------------------------------------------------------------------

fn default_true() -> bool {
    true
}

fn default_gif_fps() -> i64 {
    15
}

fn default_pre_click_secs() -> f64 {
    0.5
}

fn default_post_click_secs() -> f64 {
    1.5
}

fn default_highlight_color() -> String {
    "#EF4444".to_string()
}

fn default_highlight_radius() -> f64 {
    28.0
}

fn default_toggle_recording() -> String {
    "⌥ Space".to_string()
}

fn default_company_name() -> String {
    "Flowline Docs".to_string()
}

fn default_paper_size() -> String {
    "A4".to_string()
}

fn default_blur_radius() -> f64 {
    12.0
}

fn default_gateway_base_url() -> String {
    GatewayProviderType::OpenRouter.default_base_url().to_string()
}

fn default_gateway_model() -> String {
    GatewayProviderType::OpenRouter.default_model().to_string()
}

fn default_temperature() -> f64 {
    0.2
}

fn default_long_press_secs() -> f64 {
    0.8
}

fn default_discard_last_step() -> GestureAction {
    GestureAction::DiscardLastStep
}

fn default_pause_resume() -> GestureAction {
    GestureAction::PauseResume
}

fn default_no_action() -> GestureAction {
    GestureAction::None
}

fn default_stop_and_review() -> GestureAction {
    GestureAction::StopAndReview
}

fn default_add_checkpoint() -> GestureAction {
    GestureAction::AddCheckpoint
}

fn default_capture_snapshot() -> GestureAction {
    GestureAction::CaptureSnapshot
}

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/// Decode failures for settings JSON.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    /// `serde_json` parse or type error.
    #[error("settings json error: {0}")]
    Json(#[from] serde_json::Error),
}

/// Decode settings JSON into `T` (usually [`FlowlineSettings`]).
pub fn from_json<T: serde::de::DeserializeOwned>(json: &str) -> Result<T, Error> {
    Ok(serde_json::from_str(json)?)
}

/// Encode settings to compact JSON.
pub fn to_json<T: serde::Serialize>(value: &T) -> Result<String, Error> {
    Ok(serde_json::to_string(value)?)
}

// ---------------------------------------------------------------------------
// Shared vocabularies (Swift twins in `Sources/FlowlineIR/`)
// ---------------------------------------------------------------------------

/// Capture media mode (`Model/StepSession.swift MediaMode`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
pub enum MediaMode {
    /// Hybrid (screenshots + GIFs).
    #[serde(rename = "hybrid")]
    #[default]
    Hybrid,
    /// Static screenshots only.
    #[serde(rename = "static")]
    StaticOnly,
    /// Animated GIFs only.
    #[serde(rename = "animated")]
    AnimatedOnly,
}

impl MediaMode {
    /// Human-readable display name (mirrors Swift `displayName`).
    pub fn display_name(self) -> &'static str {
        match self {
            Self::Hybrid => "Hybrid (Screenshots + GIFs)",
            Self::StaticOnly => "Static Screenshots Only",
            Self::AnimatedOnly => "Animated GIFs Only",
        }
    }
}

/// Still-capture framing (`Events/CaptureArtifacts.swift CaptureMode`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum CaptureMode {
    /// Tight per-window shot.
    #[default]
    Window,
    /// Full display.
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

/// Gesture action vocabulary (`GestureAction.swift`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GestureAction {
    /// Disabled.
    None,
    /// Pause / resume recording.
    PauseResume,
    /// Stop and open review window.
    StopAndReview,
    /// Discard / undo last step.
    DiscardLastStep,
    /// Mark step as key milestone.
    AddCheckpoint,
    /// Capture instant snapshot.
    CaptureSnapshot,
}

impl GestureAction {
    /// Human-readable title (mirrors Swift `title`).
    pub fn title(self) -> &'static str {
        match self {
            Self::None => "Disabled",
            Self::PauseResume => "Pause / Resume Recording",
            Self::StopAndReview => "Stop & Open Review Window",
            Self::DiscardLastStep => "Discard / Undo Last Step",
            Self::AddCheckpoint => "Mark Step as Key Milestone",
            Self::CaptureSnapshot => "Capture Instant Snapshot",
        }
    }
}

/// Export theme name (`Model/StepSession.swift ThemeName`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
pub enum ThemeName {
    /// Modern minimalist theme.
    #[serde(rename = "modern-minimal")]
    #[default]
    ModernMinimal,
    /// Developer dark theme.
    #[serde(rename = "developer-dark")]
    DeveloperDark,
    /// Enterprise SOP theme.
    #[serde(rename = "enterprise-sop")]
    EnterpriseSop,
}

impl ThemeName {
    /// Human-readable display name (mirrors Swift `displayName`).
    pub fn display_name(self) -> &'static str {
        match self {
            Self::ModernMinimal => "Modern Minimalist",
            Self::DeveloperDark => "Developer Dark",
            Self::EnterpriseSop => "Enterprise SOP",
        }
    }
}

/// Selectable keystroke visual style (`Publishing/KeyVisualStyle.swift`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
pub enum KeycapStyle {
    /// Flat Magic-Keyboard matte caps.
    #[serde(rename = "mac2D")]
    Mac2D,
    /// Apple bezel: gradient + bottom edge + shadow.
    #[serde(rename = "mac3D")]
    #[default]
    Mac3D,
    /// Skeuomorphic mechanical caps.
    #[serde(rename = "mechanical3D")]
    Mechanical3D,
}

/// Selectable mouse-pointer halo style (`Publishing/KeyVisualStyle.swift`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
pub enum MouseStyle {
    /// Thin ring + dot.
    #[serde(rename = "flat")]
    Flat,
    /// Native pointer in a flat badge.
    #[serde(rename = "mac2D")]
    Mac2D,
    /// Double ring + glow + drop shadow.
    #[serde(rename = "mac3D")]
    #[default]
    Mac3D,
}

/// Smart-gesture sensitivity (`CaptureAPI/GestureSettings.swift`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum GestureSensitivity {
    /// Vigorous motion.
    Low,
    /// Balanced.
    #[default]
    Medium,
    /// Quick response.
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

    /// Shake velocity threshold in px/s (mirrors Swift `thresholdVelocity`).
    pub fn threshold_velocity(self) -> f64 {
        match self {
            Self::Low => 850.0,
            Self::Medium => 550.0,
            Self::High => 380.0,
        }
    }
}

/// Visual treatment over detected sensitive regions
/// (`Pipeline/PrivacySettings.swift RedactionBlurStyle`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum RedactionBlurStyle {
    /// Frosted glass (Gaussian blur).
    #[default]
    FrostedGlass,
    /// Solid blackout.
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

/// AI gateway provider (`AIGateway/GatewaySettings.swift`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
pub enum GatewayProviderType {
    /// OpenRouter cloud gateway.
    #[serde(rename = "openrouter")]
    #[default]
    OpenRouter,
    /// OpenAI / Portkey / LiteLLM.
    #[serde(rename = "custom_openai")]
    CustomOpenAI,
    /// Ollama (local offline).
    #[serde(rename = "ollama")]
    Ollama,
    /// LM Studio (local offline).
    #[serde(rename = "lm_studio")]
    LmStudio,
    /// Local CLI pipeline.
    #[serde(rename = "cli")]
    Cli,
}

impl GatewayProviderType {
    /// Human-readable display name (mirrors Swift `displayName`).
    pub fn display_name(self) -> &'static str {
        match self {
            Self::OpenRouter => "OpenRouter (Cloud Gateway)",
            Self::CustomOpenAI => "OpenAI / Portkey / LiteLLM",
            Self::Ollama => "Ollama (Local Offline)",
            Self::LmStudio => "LM Studio (Local Offline)",
            Self::Cli => "Local CLI Pipeline",
        }
    }

    /// Provider default base URL (mirrors Swift `defaultBaseURL`).
    pub fn default_base_url(self) -> &'static str {
        match self {
            Self::OpenRouter => "https://openrouter.ai/api/v1",
            Self::CustomOpenAI => "https://api.openai.com/v1",
            Self::Ollama => "http://localhost:11434/v1",
            Self::LmStudio => "http://localhost:1234/v1",
            Self::Cli => "",
        }
    }

    /// Provider default model (mirrors Swift `defaultModel`).
    pub fn default_model(self) -> &'static str {
        match self {
            Self::OpenRouter => "anthropic/claude-3.5-sonnet",
            Self::CustomOpenAI => "gpt-4o",
            Self::Ollama => "llama3.2-vision",
            Self::LmStudio => "meta-llama-3.2-11b-vision-instruct",
            Self::Cli => "ollama run llama3.2-vision",
        }
    }
}

// ---------------------------------------------------------------------------
// Capture
// ---------------------------------------------------------------------------

/// Capture behaviour configuration
/// (`CaptureAPI/CaptureSettings.swift`; JSON keys verbatim).
///
/// Every field carries a Swift-matching serde default, mirroring the
/// custom `init(from:)` (`decodeIfPresent` per key) so pre-Phase-2 files
/// without `recordAppSwitches` / `captureMode` still load.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CaptureSettings {
    #[serde(default)]
    pub media_mode: MediaMode,
    #[serde(default = "default_gif_fps")]
    pub gif_fps: i64,
    #[serde(default = "default_pre_click_secs", serialize_with = "serialize_f64")]
    pub clip_duration_pre_click_sec: f64,
    #[serde(default = "default_post_click_secs", serialize_with = "serialize_f64")]
    pub clip_duration_post_click_sec: f64,
    #[serde(default = "default_true")]
    pub highlight_clicks: bool,
    #[serde(default = "default_highlight_color")]
    pub highlight_color_hex: String,
    #[serde(default = "default_highlight_radius", serialize_with = "serialize_f64")]
    pub highlight_radius: f64,
    /// Emit discrete `.appSwitch` steps on frontmost-app change.
    #[serde(default)]
    pub record_app_switches: bool,
    /// Window vs. display framing for stills + micro-clips.
    #[serde(default)]
    pub capture_mode: CaptureMode,
}

impl Default for CaptureSettings {
    /// Mirrors Swift `CaptureSettings.init` defaults.
    fn default() -> Self {
        Self {
            media_mode: MediaMode::Hybrid,
            gif_fps: 15,
            clip_duration_pre_click_sec: 0.5,
            clip_duration_post_click_sec: 1.5,
            highlight_clicks: true,
            highlight_color_hex: "#EF4444".to_string(),
            highlight_radius: 28.0,
            record_app_switches: false,
            capture_mode: CaptureMode::Window,
        }
    }
}

// ---------------------------------------------------------------------------
// Gestures
// ---------------------------------------------------------------------------

/// Hot-corner bindings (`CaptureAPI/GestureSettings.swift`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HotCornerSettings {
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default = "default_discard_last_step")]
    pub top_left: GestureAction,
    #[serde(default = "default_pause_resume")]
    pub top_right: GestureAction,
    #[serde(default = "default_no_action")]
    pub bottom_left: GestureAction,
    #[serde(default = "default_stop_and_review")]
    pub bottom_right: GestureAction,
}

impl Default for HotCornerSettings {
    /// Mirrors Swift `HotCornerSettings.init` defaults.
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

/// Smart-gestures configuration (`CaptureAPI/GestureSettings.swift`).
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GestureSettings {
    #[serde(default = "default_true")]
    pub shake_to_pause_enabled: bool,
    #[serde(default)]
    pub shake_sensitivity: GestureSensitivity,
    #[serde(default = "default_pause_resume")]
    pub shake_action: GestureAction,
    #[serde(default)]
    pub hot_corners: HotCornerSettings,
    #[serde(default = "default_add_checkpoint")]
    pub middle_click_action: GestureAction,
    #[serde(default = "default_discard_last_step")]
    pub double_right_click_action: GestureAction,
    #[serde(default = "default_capture_snapshot")]
    pub long_press_action: GestureAction,
    #[serde(default = "default_long_press_secs", serialize_with = "serialize_f64")]
    pub long_press_duration_sec: f64,
}

impl Default for GestureSettings {
    /// Mirrors Swift `GestureSettings.init` defaults.
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

// ---------------------------------------------------------------------------
// Hotkeys
// ---------------------------------------------------------------------------

/// Recording-toggle hotkey (`CaptureAPI/HotkeySettings.swift`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HotkeySettings {
    #[serde(default = "default_toggle_recording")]
    pub toggle_recording: String,
}

impl Default for HotkeySettings {
    /// Mirrors Swift `HotkeySettings.init` (`"⌥ Space"`).
    fn default() -> Self {
        Self {
            toggle_recording: "⌥ Space".to_string(),
        }
    }
}

/// Which keyboard chords become discrete documentation steps
/// (`Pipeline/HotkeyCaptureSettings.swift`).
///
/// `ignored_combos` is a `BTreeSet` (Swift `Set<String>` encodes as an
/// array; sorted order keeps canonical JSON deterministic).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HotkeyCaptureSettings {
    /// Record `⌘`/`⌃` chords as `.keyPress` steps.
    #[serde(default = "default_true")]
    pub capture_modifier_shortcuts: bool,
    /// Record navigation keys as `.keyPress` steps.
    #[serde(default = "default_true")]
    pub capture_navigation_keys: bool,
    /// Extra chords the recorder consumes and never records.
    #[serde(default)]
    pub ignored_combos: BTreeSet<String>,
}

impl Default for HotkeyCaptureSettings {
    /// Mirrors Swift `HotkeyCaptureSettings.init` defaults.
    fn default() -> Self {
        Self {
            capture_modifier_shortcuts: true,
            capture_navigation_keys: true,
            ignored_combos: BTreeSet::new(),
        }
    }
}

// ---------------------------------------------------------------------------
// Publishing
// ---------------------------------------------------------------------------

/// Documentation output configuration
/// (`Publishing/PublishingSettings.swift`; tolerant decode mirrors Swift's
/// custom `init(from:)` for pre-style payloads).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PublishingSettings {
    #[serde(default)]
    pub default_theme: ThemeName,
    #[serde(default)]
    pub author_name: String,
    #[serde(default = "default_company_name")]
    pub company_name: String,
    #[serde(default = "default_true")]
    pub enable_interactive_checklists: bool,
    #[serde(default = "default_paper_size")]
    pub pdf_paper_size: String,
    #[serde(default = "default_true")]
    pub include_timestamp: bool,
    #[serde(default)]
    pub keycap_style: KeycapStyle,
    #[serde(default)]
    pub mouse_style: MouseStyle,
}

impl Default for PublishingSettings {
    /// Mirrors Swift `PublishingSettings.init` defaults.
    fn default() -> Self {
        Self {
            default_theme: ThemeName::ModernMinimal,
            author_name: String::new(),
            company_name: "Flowline Docs".to_string(),
            enable_interactive_checklists: true,
            pdf_paper_size: "A4".to_string(),
            include_timestamp: true,
            keycap_style: KeycapStyle::Mac3D,
            mouse_style: MouseStyle::Mac3D,
        }
    }
}

// ---------------------------------------------------------------------------
// Privacy
// ---------------------------------------------------------------------------

/// Pre-capture masking + post-capture redaction rules
/// (`Pipeline/PrivacySettings.swift`). Everything runs on-device.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PrivacySettings {
    /// Mask keystrokes in `isSecure` fields instead of dropping the batch.
    #[serde(default = "default_true")]
    pub mask_secure_input_fields: bool,
    /// Blur sensitive tokens in screenshots before writing to disk.
    #[serde(default = "default_true", rename = "enableOfflineOCRRedaction")]
    pub enable_offline_ocr_redaction: bool,
    /// Redact API keys / bearer tokens / JWTs.
    #[serde(default = "default_true", rename = "autoRedactAPIKeys")]
    pub auto_redact_api_keys: bool,
    #[serde(default = "default_true")]
    pub auto_redact_credit_cards: bool,
    #[serde(default)]
    pub auto_redact_emails: bool,
    /// Blur radius in screen points for `.frostedGlass`.
    #[serde(default = "default_blur_radius", serialize_with = "serialize_f64")]
    pub blur_radius: f64,
    /// Frosted glass blur vs. solid blackout.
    #[serde(default)]
    pub blur_style: RedactionBlurStyle,
    /// Extra user-supplied regex patterns (case-insensitive).
    #[serde(default)]
    pub custom_regex_patterns: Vec<String>,
}

impl Default for PrivacySettings {
    /// Mirrors Swift memberwise defaults.
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

// ---------------------------------------------------------------------------
// Gateway
// ---------------------------------------------------------------------------

/// AI gateway configuration (`AIGateway/GatewaySettings.swift`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GatewaySettings {
    #[serde(default)]
    pub provider: GatewayProviderType,
    #[serde(default = "default_gateway_base_url", rename = "baseURL")]
    pub base_url: String,
    #[serde(default, rename = "apiKey")]
    pub api_key: String,
    #[serde(default = "default_gateway_model")]
    pub model: String,
    #[serde(default = "default_true", rename = "visionEnabled")]
    pub vision_enabled: bool,
    #[serde(default = "default_temperature", serialize_with = "serialize_f64")]
    pub temperature: f64,
}

impl Default for GatewaySettings {
    /// Mirrors Swift `GatewaySettings.init` defaults (openRouter).
    fn default() -> Self {
        Self::for_provider(GatewayProviderType::OpenRouter)
    }
}

impl GatewaySettings {
    /// Defaults for a provider: per-provider base URL + model, empty key,
    /// `visionEnabled true`, `temperature 0.2`.
    pub fn for_provider(provider: GatewayProviderType) -> Self {
        Self {
            base_url: provider.default_base_url().to_string(),
            model: provider.default_model().to_string(),
            provider,
            api_key: String::new(),
            vision_enabled: true,
            temperature: 0.2,
        }
    }

    /// Local providers run on this Mac — no API key needed.
    pub fn is_local(&self) -> bool {
        matches!(
            self.provider,
            GatewayProviderType::Ollama | GatewayProviderType::LmStudio | GatewayProviderType::Cli
        )
    }

    /// Cloud providers require an API key before synthesis can run.
    pub fn needs_api_key(&self) -> bool {
        matches!(
            self.provider,
            GatewayProviderType::OpenRouter | GatewayProviderType::CustomOpenAI
        )
    }

    /// Whether the AI panel may send: cloud needs a non-empty key, local
    /// providers need none (mirrors Swift `canRun`).
    pub fn can_run(&self) -> bool {
        !self.needs_api_key() || !self.api_key.trim().is_empty()
    }
}

// ---------------------------------------------------------------------------
// Aggregate
// ---------------------------------------------------------------------------

/// Full application settings aggregate
/// (`Engine/FlowlineSettings.swift`).
///
/// Every section is `#[serde(default)]`, mirroring Swift's
/// `decodeIfPresent` decoder: settings files written before Phase 1
/// (no `gestures`) or Phase 2 (no `privacy` / `hotkeyCapture`) load with
/// defaults instead of failing.
#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FlowlineSettings {
    #[serde(default)]
    pub capture: CaptureSettings,
    #[serde(default)]
    pub publishing: PublishingSettings,
    #[serde(default)]
    pub gateway: GatewaySettings,
    #[serde(default)]
    pub hotkeys: HotkeySettings,
    #[serde(default)]
    pub gestures: GestureSettings,
    #[serde(default)]
    pub privacy: PrivacySettings,
    #[serde(default)]
    pub hotkey_capture: HotkeyCaptureSettings,
}

impl FlowlineSettings {
    /// Decode from JSON, tolerating missing sections / keys.
    pub fn from_json(json: &str) -> Result<Self, Error> {
        from_json(json)
    }

    /// Environment-aware defaults (mirrors Swift `defaultSettings`):
    /// `OPENROUTER_API_KEY` wins, else `OPENAI_API_KEY`; empty values
    /// are ignored.
    pub fn default_settings() -> Self {
        let mut s = Self::default();
        if let Ok(key) = std::env::var("OPENROUTER_API_KEY") {
            if !key.is_empty() {
                s.gateway.api_key = key;
                s.gateway.provider = GatewayProviderType::OpenRouter;
                s.gateway.base_url = GatewayProviderType::OpenRouter.default_base_url().to_string();
                return s;
            }
        }
        if let Ok(key) = std::env::var("OPENAI_API_KEY") {
            if !key.is_empty() {
                s.gateway.api_key = key;
                s.gateway.provider = GatewayProviderType::CustomOpenAI;
                s.gateway.base_url = GatewayProviderType::CustomOpenAI.default_base_url().to_string();
            }
        }
        s
    }

    /// Projects the engine-consumed subset (mirrors Swift `engineSettings`).
    pub fn engine_settings(&self) -> EngineSettings {
        EngineSettings {
            capture: self.capture.clone(),
            privacy: self.privacy.clone(),
            hotkey_capture: self.hotkey_capture.clone(),
            hotkeys: self.hotkeys.clone(),
            gestures: self.gestures,
        }
    }

    /// Scalar tuning consumed by `flowline_engine::EngineConfig`.
    ///
    /// The engine owns the timing constants (`minStepInterval`,
    /// `typingDebounce`, gesture-notice + clip windows); the rest is
    /// projected straight out of settings. Kept as a plain value (not a
    /// `flowline_engine` dependency) so this crate stays a leaf.
    pub fn engine_tuning(&self) -> EngineTuning {
        EngineTuning {
            min_step_interval_secs: 0.20,
            typing_debounce_secs: 1.0,
            gesture_notice_secs: 2.5,
            toggle_hotkey_combo: self.hotkeys.toggle_recording.clone(),
            click_clip_post_secs: 1.2,
            typing_clip_post_secs: 0.6,
            record_app_switches: self.capture.record_app_switches,
            capture_modifier_shortcuts: self.hotkey_capture.capture_modifier_shortcuts,
            capture_navigation_keys: self.hotkey_capture.capture_navigation_keys,
            mask_secure_input: self.privacy.mask_secure_input_fields,
        }
    }
}

/// Narrow settings shape the recording engine consumes
/// (`Engine/EngineSettings.swift`; not `Codable` in Swift either).
#[derive(Debug, Clone, PartialEq)]
pub struct EngineSettings {
    pub capture: CaptureSettings,
    pub privacy: PrivacySettings,
    pub hotkey_capture: HotkeyCaptureSettings,
    pub hotkeys: HotkeySettings,
    pub gestures: GestureSettings,
}

impl Default for EngineSettings {
    fn default() -> Self {
        FlowlineSettings::default().engine_settings()
    }
}

/// Scalar tuning mirroring `flowline_engine::EngineConfig` fields.
///
/// Build an `EngineConfig` from this with a field-by-field copy; the
/// field names and types match intentionally.
#[derive(Debug, Clone, PartialEq)]
pub struct EngineTuning {
    /// Minimum spacing between accepted click/action steps (0.20).
    pub min_step_interval_secs: f64,
    /// Inactivity window finalizing a typing batch (1.0).
    pub typing_debounce_secs: f64,
    /// Gesture-notice HUD lifetime (2.5).
    pub gesture_notice_secs: f64,
    /// Hotkey combo toggling recording (from `hotkeys.toggleRecording`).
    pub toggle_hotkey_combo: String,
    /// Post-click window collected for micro-clips (1.2).
    pub click_clip_post_secs: f64,
    /// Post-typing window collected for fast-forward clips (0.6).
    pub typing_clip_post_secs: f64,
    /// Emit discrete `.appSwitch` steps.
    pub record_app_switches: bool,
    /// Capture `⌘/⌃` chords as `.keyPress` steps.
    pub capture_modifier_shortcuts: bool,
    /// Capture navigation keys as `.keyPress` steps.
    pub capture_navigation_keys: bool,
    /// Mask secure-field keystrokes instead of buffering plaintext.
    pub mask_secure_input: bool,
}

impl Default for EngineTuning {
    /// Mirrors `flowline_engine::EngineConfig::default`.
    fn default() -> Self {
        FlowlineSettings::default().engine_tuning()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn swift_init_defaults() {
        let c = CaptureSettings::default();
        assert_eq!(c.gif_fps, 15);
        assert_eq!(c.clip_duration_pre_click_sec, 0.5);
        assert_eq!(c.clip_duration_post_click_sec, 1.5);
        assert!(c.highlight_clicks);
        assert_eq!(c.highlight_color_hex, "#EF4444");
        assert_eq!(c.highlight_radius, 28.0);
        assert!(!c.record_app_switches);

        let g = GestureSettings::default();
        assert!(g.shake_to_pause_enabled);
        assert_eq!(g.shake_sensitivity, GestureSensitivity::Medium);
        assert_eq!(
            g.shake_sensitivity.threshold_velocity(),
            550.0
        );
        assert_eq!(g.long_press_duration_sec, 0.8);
        assert_eq!(g.hot_corners.top_left, GestureAction::DiscardLastStep);
        assert_eq!(g.hot_corners.top_right, GestureAction::PauseResume);
        assert_eq!(g.hot_corners.bottom_left, GestureAction::None);
        assert_eq!(g.hot_corners.bottom_right, GestureAction::StopAndReview);

        assert_eq!(HotkeySettings::default().toggle_recording, "⌥ Space");

        let p = PublishingSettings::default();
        assert_eq!(p.company_name, "Flowline Docs");
        assert_eq!(p.pdf_paper_size, "A4");
        assert!(p.enable_interactive_checklists);
        assert!(p.include_timestamp);

        let gw = GatewaySettings::default();
        assert_eq!(gw.provider, GatewayProviderType::OpenRouter);
        assert_eq!(gw.base_url, "https://openrouter.ai/api/v1");
        assert_eq!(gw.model, "anthropic/claude-3.5-sonnet");
        assert!(gw.vision_enabled);
        assert_eq!(gw.temperature, 0.2);
        assert!(!gw.can_run());
        assert!(gw.needs_api_key());
        assert!(!gw.is_local());

        let t = EngineTuning::default();
        assert_eq!(t.toggle_hotkey_combo, "⌥ Space");
        assert!(!t.record_app_switches);
        assert!(t.capture_modifier_shortcuts);
        assert!(t.capture_navigation_keys);
        assert!(t.mask_secure_input);
    }

    #[test]
    fn empty_object_decodes_to_defaults() {
        let s: FlowlineSettings = from_json("{}").unwrap();
        assert_eq!(s, FlowlineSettings::default());
    }
}
