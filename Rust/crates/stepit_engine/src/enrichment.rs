//! Terminal working-directory enrichment, app-context fill, keystroke
//! classification, and privacy gating hooks. Swift twins:
//! `TerminalEnrichment.swift`, `PrivacyEnrichment.swift` (`enriched`),
//! `KeystrokeClassifier.swift` and the secure/blackout halves of
//! `ClipOrchestrator.captureStepMedia` (image ops stay driver-side).
//!
//! Classification, hotkey policy, and batch-context normalization delegate to
//! `stepit_pipeline` (single implementation; R/M2 hardcoded-dedup close-out).
//! Engine-owned: `enriched` (app-switch fill), `terminal_command_description`
//! (`StepFactory` rendering), `PrivacyRedactor`, and the millis-domain
//! `EventDebouncer`/`TypingBuffer` in [`crate::state`] (integer-millis
//! precision; the pipeline debouncer/aggregator run on float seconds /
//! timer-driven batching — wrapping them would trade integer exactness for
//! float rounding at the accept boundary).

use stepit_ir::{HotkeyChord, KeyModifiers, RawElementContext};

/// What & where the user was typing (`KeystrokeClassifier.InputClassification`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InputClassification {
    Text,
    Code { language: Option<String> },
    Terminal,
}

impl From<stepit_pipeline::classify::InputClassification> for InputClassification {
    fn from(other: stepit_pipeline::classify::InputClassification) -> Self {
        match other {
            stepit_pipeline::classify::InputClassification::Text => Self::Text,
            stepit_pipeline::classify::InputClassification::Terminal => Self::Terminal,
            stepit_pipeline::classify::InputClassification::Code(lang) => Self::Code {
                language: Some(lang),
            },
        }
    }
}

/// Pure port of `KeystrokeClassifier` (verbatim app lists / predicates).
/// Delegates to `stepit_pipeline::classify` — the lists live in one place.
#[derive(Debug, Clone, Copy, Default)]
pub struct KeystrokeClassifier;

impl KeystrokeClassifier {
    pub fn is_terminal_environment(
        &self,
        app_name: &str,
        bundle_id: Option<&str>,
        window_title: &str,
    ) -> bool {
        stepit_pipeline::classify::is_terminal(app_name, bundle_id, window_title)
    }

    pub fn is_code_environment(
        &self,
        app_name: &str,
        bundle_id: Option<&str>,
        window_title: &str,
    ) -> bool {
        stepit_pipeline::classify::is_code(app_name, bundle_id, window_title)
    }

    /// Port of `detectLanguage`, including the legacy `"text"` fallback.
    pub fn detect_language(&self, app_name: &str, window_title: &str, text: &str) -> String {
        stepit_pipeline::classify::detect_language(app_name, window_title, text)
    }

    pub fn classify(&self, text: &str, context: &RawElementContext) -> InputClassification {
        stepit_pipeline::classify::classify(text, Some(context)).into()
    }
}

/// Fill missing app context from the last observed app switch
/// (`RecorderWorkflowEngine.enriched`, verbatim semantics).
pub fn enriched(
    mut context: RawElementContext,
    last_app: Option<&RawElementContext>,
) -> RawElementContext {
    if context.is_unknown() {
        if let Some(last) = last_app {
            context.app_name = last.app_name.clone();
            if context.bundle_identifier.is_none() {
                context.bundle_identifier = last.bundle_identifier.clone();
            }
            if context.window_title.is_empty() {
                context.window_title = last.window_title.clone();
            }
        }
    }
    context
}

/// Apply the typing-batch context fallbacks (`TypingBatchAggregator.makeResult`):
/// unknown/empty app becomes `"Terminal"`, empty window title becomes the app
/// name, and secure values never ride along. Delegates to
/// `stepit_pipeline::aggregate` (single implementation).
pub fn normalize_batch_context(context: RawElementContext) -> RawElementContext {
    stepit_pipeline::aggregate::normalize_batch_context(context)
}

/// Render `Run "git status" in ~/Code/stepit (Ghostty)`; legacy
/// `Run "git status" in Ghostty` when the `pwd` is unknown
/// (`StepFactory.terminalCommandDescription`, verbatim). Delegates to
/// `stepit_pipeline::step_factory`, preserving this function's trim contract.
pub fn terminal_command_description(
    command: &str,
    working_directory: Option<&str>,
    app_name: &str,
) -> String {
    stepit_pipeline::step_factory::terminal_command_description(
        command.trim(),
        working_directory,
        app_name,
    )
}

/// Decision produced for one keyboard event (`HotkeyRecognizer.HotkeyDecision`).
/// Same shape as `stepit_pipeline::hotkey::HotkeyDecision`; kept as a distinct
/// type so the reducer never depends on pipeline item paths directly.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HotkeyDecision {
    ToggleRecording { combo: String },
    SystemConsumed { combo: String },
    WorkflowShortcut(HotkeyChord),
    NavigationKey(HotkeyChord),
    TextInput { key: String, modifiers: KeyModifiers },
    Ignored,
}

impl From<stepit_pipeline::hotkey::HotkeyDecision> for HotkeyDecision {
    fn from(other: stepit_pipeline::hotkey::HotkeyDecision) -> Self {
        match other {
            stepit_pipeline::hotkey::HotkeyDecision::ToggleRecording { combo } => {
                Self::ToggleRecording { combo }
            }
            stepit_pipeline::hotkey::HotkeyDecision::SystemConsumed { combo } => {
                Self::SystemConsumed { combo }
            }
            stepit_pipeline::hotkey::HotkeyDecision::WorkflowShortcut(chord) => {
                Self::WorkflowShortcut(chord)
            }
            stepit_pipeline::hotkey::HotkeyDecision::NavigationKey(chord) => {
                Self::NavigationKey(chord)
            }
            stepit_pipeline::hotkey::HotkeyDecision::TextInput { key, modifiers } => {
                Self::TextInput { key, modifiers }
            }
            stepit_pipeline::hotkey::HotkeyDecision::Ignored => Self::Ignored,
        }
    }
}

/// Centralized hotkey resolution (`HotkeyRecognizer`, IR entry point verbatim).
/// Delegates to `stepit_pipeline::hotkey` — the toggle/system/shortcut/
/// navigation policy lives in one place. (Note: this also drops a deviation
/// the engine copy had: it normalized `ignored_combos` before comparing,
/// while Swift compares exactly. Delegation restores verbatim Swift parity.)
#[derive(Debug, Clone)]
pub struct HotkeyRecognizer {
    pub toggle_combo: String,
    pub ignored_combos: Vec<String>,
    pub capture_modifier_shortcuts: bool,
    pub capture_navigation_keys: bool,
}

impl HotkeyRecognizer {
    pub fn new(toggle_combo: &str) -> Self {
        Self {
            toggle_combo: toggle_combo.to_string(),
            ignored_combos: Vec::new(),
            capture_modifier_shortcuts: true,
            capture_navigation_keys: true,
        }
    }

    pub fn built_in_system_combos() -> &'static [&'static str] {
        &[
            "⌘Tab",
            "⌘⇧Tab",
            "⌘Space",
            "⌘⇧Space",
            "⌃⌘Space",
            "⌘`",
        ]
    }

    pub fn navigation_keys() -> &'static [&'static str] {
        &[
            "Escape", "Tab", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Home", "End",
            "PageUp", "PageDown", "Delete", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8",
            "F9", "F10", "F11", "F12",
        ]
    }

    /// Whitespace-insensitive combo comparison (`"⌥ Space"` == `"⌥Space"`).
    /// Toggle matching keeps Swift's normalization (pipeline parity).
    pub fn normalize_combo(combo: &str) -> String {
        stepit_pipeline::hotkey::HotkeyRecognizer::normalize_combo(combo)
    }

    /// macOS sets `.function` on arrow / F-key events without a real `fn`
    /// press; it is not a modifier for combo rendering.
    pub fn chord_modifiers(modifiers: KeyModifiers) -> KeyModifiers {
        stepit_pipeline::hotkey::HotkeyRecognizer::chord_modifiers(modifiers)
    }

    fn pipeline_recognizer(&self) -> stepit_pipeline::hotkey::HotkeyRecognizer {
        stepit_pipeline::hotkey::HotkeyRecognizer::new(
            stepit_pipeline::hotkey::HotkeyCaptureSettings {
                capture_modifier_shortcuts: self.capture_modifier_shortcuts,
                capture_navigation_keys: self.capture_navigation_keys,
                ignored_combos: self.ignored_combos.iter().cloned().collect(),
            },
            &self.toggle_combo,
        )
    }

    /// Classifies an IR-level keystroke (`key` = W3C `KeyboardEvent.key`).
    pub fn evaluate(
        &self,
        key: &str,
        code: Option<i64>,
        modifiers: KeyModifiers,
    ) -> HotkeyDecision {
        self.pipeline_recognizer()
            .evaluate(key, code.map(|c| c as i32), modifiers)
            .into()
    }
}

/// Privacy gating hook: offline OCR redaction as an injectable trait returning
/// whether the step's media was redacted. The default (no hook installed) is
/// pass-through. Vision/CoreImage never enter core — same boundary as Swift's
/// `VisualRedactionProviding` facet.
pub trait PrivacyRedactor {
    /// `true` when the step's media was redacted (→ `isRedacted: true`).
    fn redact(&mut self, step_index: i64) -> bool;
}

/// Pass-through redactor used when no privacy hook is installed.
#[derive(Debug, Clone, Copy, Default)]
pub struct PassThroughRedactor;

impl PrivacyRedactor for PassThroughRedactor {
    fn redact(&mut self, _step_index: i64) -> bool {
        false
    }
}
