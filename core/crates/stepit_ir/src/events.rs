//! Port of `Events/RawInputEvent.swift`, `Events/RawElementContext.swift`,
//! `Events/CaptureArtifacts.swift`, and `GestureAction.swift`.
//!
//! # Swift-encoding notes (verified against `swiftc`, not guessed)
//! - `KeyModifiers` (`OptionSet`) encodes as a **bare int** (its `rawValue`),
//!   not `{"rawValue": N}` — hence the transparent newtype below.
//! - `RawInputEvent.Kind` (enum with associated values) encodes externally
//!   tagged: `{"mouseClick": {"button": ..., "clickCount": ...}}` — serde's
//!   default enum representation with `camelCase` renames.
//! - `nil` optionals are omitted by Swift; every `Option` field carries
//!   `skip_serializing_if = "Option::is_none"`.

use serde::{Deserialize, Serialize};

use crate::session::ElementRect;

/// Platform-neutral 2D point used by every core API.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Point2D {
    /// x coordinate.
#[serde(serialize_with = "crate::numbers::serialize_f64")]
    pub x: f64,
    /// y coordinate.
#[serde(serialize_with = "crate::numbers::serialize_f64")]
    pub y: f64,
}

impl Point2D {
    /// The origin point.
    pub const ZERO: Point2D = Point2D { x: 0.0, y: 0.0 };

    /// Build a point.
    pub fn new(x: f64, y: f64) -> Self {
        Self { x, y }
    }
}

impl Default for Point2D {
    fn default() -> Self {
        Self::ZERO
    }
}

/// IR identity of a mouse button.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MouseButton {
    /// Left button (platform button number 0).
    Left,
    /// Right button (platform button number 1).
    Right,
    /// Middle button (platform button number 2).
    Middle,
}

impl MouseButton {
    /// Maps a platform button number (0 = left, 1 = right, 2 = middle).
    pub fn from_button_number(n: i64) -> Option<Self> {
        match n {
            0 => Some(Self::Left),
            1 => Some(Self::Right),
            2 => Some(Self::Middle),
            _ => None,
        }
    }
}

/// Canonical keyboard modifier set.
///
/// Swift `OptionSet` with `Codable` synthesizing to a bare-int `rawValue`;
/// mirrored here as a transparent bitflag newtype.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct KeyModifiers(pub i64);

impl KeyModifiers {
    /// Empty modifier set.
    pub const EMPTY: KeyModifiers = KeyModifiers(0);
    /// Command modifier (bit 0).
    pub const COMMAND: KeyModifiers = KeyModifiers(1 << 0);
    /// Option modifier (bit 1).
    pub const OPTION: KeyModifiers = KeyModifiers(1 << 1);
    /// Control modifier (bit 2).
    pub const CONTROL: KeyModifiers = KeyModifiers(1 << 2);
    /// Shift modifier (bit 3).
    pub const SHIFT: KeyModifiers = KeyModifiers(1 << 3);
    /// Function modifier (bit 4).
    pub const FUNCTION: KeyModifiers = KeyModifiers(1 << 4);

    /// Empty modifier set (mirrors Swift `KeyModifiers()`).
    pub fn empty() -> Self {
        KeyModifiers(0)
    }

    /// `true` when no modifier bits are set.
    pub fn is_empty(self) -> bool {
        self.0 == 0
    }

    /// `true` when `other`'s bits are all set in `self`.
    pub fn contains(self, other: KeyModifiers) -> bool {
        self.0 & other.0 == other.0
    }

    /// Bits in `self` minus `other` (mirrors Swift `OptionSet.subtracting`).
    pub fn subtracting(self, other: KeyModifiers) -> KeyModifiers {
        KeyModifiers(self.0 & !other.0)
    }

    /// Rendered in canonical order: `⌘⌥⌃⇧` (+ `fn`).
    pub fn symbol_string(self) -> String {
        let mut symbols = String::new();
        if self.contains(Self::COMMAND) {
            symbols.push('⌘');
        }
        if self.contains(Self::OPTION) {
            symbols.push('⌥');
        }
        if self.contains(Self::CONTROL) {
            symbols.push('⌃');
        }
        if self.contains(Self::SHIFT) {
            symbols.push('⇧');
        }
        if self.contains(Self::FUNCTION) {
            symbols.push_str("fn");
        }
        symbols
    }
}

impl Default for KeyModifiers {
    fn default() -> Self {
        Self::EMPTY
    }
}

impl std::ops::BitOr for KeyModifiers {
    type Output = Self;
    fn bitor(self, rhs: Self) -> Self {
        Self(self.0 | rhs.0)
    }
}

impl<const N: usize> From<[KeyModifiers; N]> for KeyModifiers {
    fn from(parts: [KeyModifiers; N]) -> Self {
        let mut acc = KeyModifiers::EMPTY;
        for part in parts {
            acc = acc | part;
        }
        acc
    }
}

/// The complete vocabulary of user actions across all future drivers.
///
/// Externally tagged (`{"mouseClick": {...}}`), `camelCase`, matching Swift.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum RawInputKind {
    /// Mouse click capture.
    MouseClick {
        /// Button pressed.
        button: MouseButton,
        /// Consecutive click count.
        #[serde(rename = "clickCount")]
        click_count: i64,
    },
    /// Keystroke capture.
    KeyStroke {
        /// W3C key name.
        key: String,
        /// Platform key code when known.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        code: Option<i64>,
        /// Active modifiers.
        modifiers: KeyModifiers,
    },
    /// Decoded hotkey combo.
    HotkeyCombo {
        /// Rendered combo, e.g. `⌘S`.
        combo: String,
    },
    /// Smart gesture notice.
    UserGesture {
        /// Gesture name.
        name: String,
        /// Gesture action.
        action: GestureAction,
    },
    /// Drag selection capture.
    MouseDrag {
        /// Drag start point.
        start: Point2D,
        /// Drag end point.
        end: Point2D,
    },
    /// App focus switch.
    AppSwitch {
        /// Bundle identifier when known.
        #[serde(default, rename = "bundleId", skip_serializing_if = "Option::is_none")]
        bundle_id: Option<String>,
        /// Application name.
        #[serde(rename = "appName")]
        app_name: String,
        /// Window title.
        #[serde(rename = "windowTitle")]
        window_title: String,
    },
    /// Terminal command introspection.
    TerminalCommand {
        /// Command text.
        command: String,
        /// Working directory when known.
        #[serde(default, rename = "workingDir", skip_serializing_if = "Option::is_none")]
        working_dir: Option<String>,
        /// Exit code when known.
        #[serde(default, rename = "exitCode", skip_serializing_if = "Option::is_none")]
        exit_code: Option<i32>,
    },
    /// Web page navigation step.
    PageNavigation {
        /// Page URL.
        url: String,
        /// Page title when known.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        title: Option<String>,
    },
}

/// The single event envelope every driver emits and the engine consumes.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RawInputEvent {
    /// Event identifier (UUID string).
    pub id: String,
    /// ISO-8601 timestamp string.
    pub timestamp: String,
    /// Event payload.
    pub kind: RawInputKind,
    /// Event location when known.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub location: Option<Point2D>,
    /// Pre-filled element context when the driver could inspect cheaply.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub target_context: Option<RawElementContext>,
}

impl RawInputEvent {
    /// Build an event with no location or target context.
    pub fn new(id: String, timestamp: String, kind: RawInputKind) -> Self {
        Self {
            id,
            timestamp,
            kind,
            location: None,
            target_context: None,
        }
    }
}

/// Presentation-side notice for a detected smart gesture.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RawGestureNotice {
    /// Gesture name.
    pub name: String,
    /// Gesture action.
    pub action: GestureAction,
    /// Gesture location.
    pub location: Point2D,
    /// ISO-8601 timestamp string.
    pub timestamp: String,
}

/// A decoded keyboard chord in platform-neutral IR terms.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HotkeyChord {
    /// W3C `KeyboardEvent.key` name, e.g. `"s"`, `"Escape"`, `"ArrowDown"`.
    pub key: String,
    /// Human-readable key label used in combo rendering, e.g. `"S"`, `"Space"`.
    pub display_key: String,
    /// Platform virtual key code when provided.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub code: Option<i64>,
    /// Active modifiers.
    pub modifiers: KeyModifiers,
}

impl HotkeyChord {
    /// Build a chord, deriving `displayKey` when omitted.
    pub fn new(
        key: String,
        display_key: Option<String>,
        code: Option<i64>,
        modifiers: KeyModifiers,
    ) -> Self {
        let display_key = display_key.unwrap_or_else(|| Self::default_display_key(&key));
        Self {
            key,
            display_key,
            code,
            modifiers,
        }
    }

    /// Rendered combo in canonical macOS order, e.g. `⌘⇧P`, `Escape`, `⌥Space`.
    pub fn combo(&self) -> String {
        format!("{}{}", self.modifiers.symbol_string(), self.display_key)
    }

    /// `true` when the chord involves at least one non-modifier modifier.
    pub fn is_shortcut(&self) -> bool {
        !self.modifiers.is_empty()
    }

    /// `"S"` for letters, `"Space"` for the space key, W3C name otherwise.
    pub fn default_display_key(key: &str) -> String {
        if key == " " {
            return "Space".to_string();
        }
        let mut chars = key.chars();
        if let (Some(c), None) = (chars.next(), chars.next()) {
            if c.is_alphanumeric() {
                return key.to_uppercase();
            }
        }
        key.to_string()
    }
}

/// Gesture action vocabulary.
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
    /// Human-readable title.
    pub fn title(self) -> &'static str {
        match self {
            Self::None => "Disabled",
            Self::PauseResume => "Pause / Resume Recording",
            Self::StopAndReview => "Stop & Open Review Window",
            Self::DiscardLastStep => "Discard / Undo Last Step",
            Self::AddCheckpoint => "Mark Step as Key Milestone ⭐",
            Self::CaptureSnapshot => "Capture Instant Snapshot 📸",
        }
    }

    /// SF Symbol name.
    pub fn icon(self) -> &'static str {
        match self {
            Self::None => "slash.circle",
            Self::PauseResume => "pause.circle.fill",
            Self::StopAndReview => "stop.circle.fill",
            Self::DiscardLastStep => "arrow.uturn.backward.circle.fill",
            Self::AddCheckpoint => "star.circle.fill",
            Self::CaptureSnapshot => "camera.circle.fill",
        }
    }
}

/// Normalized, platform-neutral description of *what the user acted on*.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RawElementContext {
    /// Localized application name, e.g. `"Safari"`.
    pub app_name: String,
    /// Bundle identifier when known.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub bundle_identifier: Option<String>,
    /// Title of the containing window.
    #[serde(default)]
    pub window_title: String,
    /// Accessibility role, e.g. `"AXButton"`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub role: Option<String>,
    /// Accessibility subrole.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub subrole: Option<String>,
    /// Best available label for the element.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    /// Element value.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub value: Option<String>,
    /// Placeholder text when the platform exposes one.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub placeholder: Option<String>,
    /// Accessibility role description, e.g. `"button"`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub role_description: Option<String>,
    /// `true` when the element is a password / secure field.
    #[serde(default)]
    pub is_secure: bool,
    /// Element frame in screen points.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub bounding_box: Option<ElementRect>,
    /// Containing window frame in screen points.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub window_bounds: Option<ElementRect>,
    /// Ordered selector fallbacks for the Phase 3 automation compilers.
    #[serde(default)]
    pub selectors: Vec<ElementSelector>,
}

impl RawElementContext {
    /// Explicit placeholder for denied/unavailable element inspection.
    pub fn unknown() -> Self {
        Self {
            app_name: "Unknown App".to_string(),
            bundle_identifier: None,
            window_title: String::new(),
            role: None,
            subrole: None,
            title: None,
            value: None,
            placeholder: None,
            role_description: None,
            is_secure: false,
            bounding_box: None,
            window_bounds: None,
            selectors: Vec::new(),
        }
    }

    /// `true` when no usable app context is present (mirrors Swift
    /// `enriched`: empty app name or the unknown placeholder).
    pub fn is_unknown(&self) -> bool {
        self.app_name.is_empty() || self.app_name == Self::unknown().app_name
    }
}

/// One entry in the ordered selector fallback list.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ElementSelector {
    /// Selector kind.
    pub kind: ElementSelectorKind,
    /// Selector value.
    pub value: String,
    /// Lower values are tried first.
    pub priority: i64,
}

impl ElementSelector {
    /// Build a selector entry.
    pub fn new(kind: ElementSelectorKind, value: String, priority: i64) -> Self {
        Self {
            kind,
            value,
            priority,
        }
    }
}

/// Selector fallback kinds.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ElementSelectorKind {
    /// Accessibility selector.
    #[serde(rename = "accessibility")]
    Accessibility,
    /// DOM test id.
    #[serde(rename = "domTestID")]
    DomTestId,
    /// ARIA label.
    #[serde(rename = "ariaLabel")]
    AriaLabel,
    /// XPath.
    #[serde(rename = "xpath")]
    Xpath,
    /// CSS selector.
    #[serde(rename = "css")]
    Css,
    /// Screen coordinates.
    #[serde(rename = "coordinates")]
    Coordinates,
}

/// IR for a still capture.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FrameSnapshot {
    /// PNG bytes (Swift `Data` — base64 string on the wire).
    #[serde(with = "crate::base64_data")]
    pub png_data: Vec<u8>,
    /// Backing scale factor of the captured screen.
#[serde(serialize_with = "crate::numbers::serialize_f64")]
    pub scale: f64,
}

impl FrameSnapshot {
    /// Build a snapshot.
    pub fn new(png_data: Vec<u8>, scale: f64) -> Self {
        Self { png_data, scale }
    }
}

/// IR for micro-clips.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClipAsset {
    /// GIF bytes when captured.
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        with = "crate::base64_data::opt"
    )]
    pub gif_data: Option<Vec<u8>>,
    /// Video bytes when captured.
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        with = "crate::base64_data::opt"
    )]
    pub video_data: Option<Vec<u8>>,
    /// Length of the captured post-click window, in seconds.
#[serde(serialize_with = "crate::numbers::serialize_f64")]
    pub duration: f64,
}

/// Capture settings passed across the SPI without reading `SessionStore`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClipBufferConfig {
    /// Capture frames per second.
    pub fps: i64,
    /// Maximum buffered seconds.
#[serde(serialize_with = "crate::numbers::serialize_f64")]
    pub max_buffer_seconds: f64,
}

/// One text region returned by an offline OCR scan.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OcrTextItem {
    /// Recognized text.
    pub text: String,
    /// Normalized bounding box (`0…1`, Vision bottom-left origin).
    pub bounding_box: ElementRect,
}

impl OcrTextItem {
    /// Build an OCR text item (mirrors the Swift memberwise init).
    pub fn new(text: &str, bounding_box: ElementRect) -> Self {
        Self {
            text: text.to_string(),
            bounding_box,
        }
    }
}

/// Outcome of a post-capture redaction pass.
///
/// (Swift twin is not `Codable`; serde here is a strict superset used for
/// debugging and future `.stepit` bundle payloads.)
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RedactionOutcome {
    /// Snapshot to persist — blurred when `is_redacted` is `true`.
    pub snapshot: FrameSnapshot,
    /// Whether redaction was applied.
    pub is_redacted: bool,
}
