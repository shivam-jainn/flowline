//! Terminal working-directory enrichment, app-context fill, keystroke
//! classification, and privacy gating hooks. Swift twins:
//! `TerminalEnrichment.swift`, `PrivacyEnrichment.swift` (`enriched`),
//! `KeystrokeClassifier.swift` and the secure/blackout halves of
//! `ClipOrchestrator.captureStepMedia` (image ops stay driver-side).

use stepit_ir::{HotkeyChord, KeyModifiers, RawElementContext};

/// What & where the user was typing (`KeystrokeClassifier.InputClassification`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InputClassification {
    Text,
    Code { language: Option<String> },
    Terminal,
}

/// Pure port of `KeystrokeClassifier` (verbatim app lists / predicates).
#[derive(Debug, Clone, Copy, Default)]
pub struct KeystrokeClassifier;

impl KeystrokeClassifier {
    pub fn is_terminal_environment(
        &self,
        app_name: &str,
        bundle_id: Option<&str>,
        window_title: &str,
    ) -> bool {
        let name = app_name.to_lowercase();
        let bid = bundle_id.unwrap_or("").to_lowercase();
        let title = window_title.to_lowercase();

        if name.contains("terminal")
            || name.contains("iterm")
            || name.contains("alacritty")
            || name.contains("kitty")
            || name.contains("warp")
            || name.contains("ghostty")
            || name.contains("hyper")
            || bid.contains("terminal")
            || bid.contains("iterm")
            || bid.contains("warp")
            || bid.contains("alacritty")
            || bid.contains("kitty")
        {
            return true;
        }

        if title.contains("— zsh")
            || title.contains("— bash")
            || title.contains("terminal")
            || title.contains("console")
        {
            return true;
        }

        false
    }

    pub fn is_code_environment(
        &self,
        app_name: &str,
        bundle_id: Option<&str>,
        window_title: &str,
    ) -> bool {
        if self.is_terminal_environment(app_name, bundle_id, window_title) {
            return true;
        }
        let name = app_name.to_lowercase();
        let bid = bundle_id.unwrap_or("").to_lowercase();
        let title = window_title.to_lowercase();

        if name.contains("code")
            || name.contains("xcode")
            || name.contains("sublime")
            || name.contains("cursor")
            || name.contains("intellij")
            || name.contains("pycharm")
            || name.contains("webstorm")
            || name.contains("antigravity")
            || bid.contains("vscode")
            || bid.contains("antigravity")
        {
            return true;
        }

        const EXTS: [&str; 19] = [
            ".swift", ".ts", ".tsx", ".js", ".jsx", ".py", ".rs", ".go", ".cpp", ".c", ".h",
            ".json", ".yaml", ".yml", ".sh", ".bash", ".sql", ".html", ".css",
        ];
        EXTS.iter().any(|ext| title.contains(ext))
    }

    /// Port of `detectLanguage`, including the legacy `"text"` fallback.
    pub fn detect_language(&self, app_name: &str, window_title: &str, text: &str) -> String {
        let name = app_name.to_lowercase();
        let title = window_title.to_lowercase();

        if self.is_terminal_environment(app_name, None, window_title) {
            return "bash".to_string();
        }

        if title.contains(".swift") {
            return "swift".to_string();
        }
        if title.contains(".ts") || title.contains(".tsx") {
            return "typescript".to_string();
        }
        if title.contains(".json") {
            return "json".to_string();
        }
        if title.contains(".jsx") || title.contains(".js") {
            return "javascript".to_string();
        }
        if title.contains(".py") {
            return "python".to_string();
        }
        if title.contains(".rs") {
            return "rust".to_string();
        }
        if title.contains(".go") {
            return "go".to_string();
        }
        if title.contains(".yaml") || title.contains(".yml") {
            return "yaml".to_string();
        }
        if title.contains(".sql") {
            return "sql".to_string();
        }
        if title.contains(".sh")
            || title.contains(".bash")
            || name.contains("terminal")
            || name.contains("iterm")
        {
            return "bash".to_string();
        }
        if title.contains(".html") {
            return "html".to_string();
        }
        if title.contains(".css") {
            return "css".to_string();
        }

        let trimmed = text.trim();
        if trimmed.starts_with('{') || trimmed.starts_with('[') {
            return "json".to_string();
        }
        if trimmed.starts_with("import ")
            || trimmed.starts_with("func ")
            || trimmed.starts_with("struct ")
        {
            return "swift".to_string();
        }
        if trimmed.starts_with("def ") || trimmed.starts_with("class ") {
            return "python".to_string();
        }
        if trimmed.starts_with("npm ")
            || trimmed.starts_with("git ")
            || trimmed.starts_with("cd ")
            || trimmed.starts_with("curl ")
            || trimmed.starts_with("swift ")
            || trimmed.starts_with("docker ")
        {
            return "bash".to_string();
        }

        "text".to_string()
    }

    pub fn classify(&self, text: &str, context: &RawElementContext) -> InputClassification {
        if self.is_terminal_environment(
            &context.app_name,
            context.bundle_identifier.as_deref(),
            &context.window_title,
        ) {
            return InputClassification::Terminal;
        }
        if self.is_code_environment(
            &context.app_name,
            context.bundle_identifier.as_deref(),
            &context.window_title,
        ) {
            return InputClassification::Code {
                language: Some(self.detect_language(&context.app_name, &context.window_title, text)),
            };
        }
        InputClassification::Text
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
/// name, and secure values never ride along.
pub fn normalize_batch_context(mut context: RawElementContext) -> RawElementContext {
    if context.app_name.is_empty() || context.app_name == RawElementContext::unknown().app_name {
        context.app_name = "Terminal".to_string();
    }
    if context.window_title.is_empty() {
        context.window_title = context.app_name.clone();
    }
    if context.is_secure {
        context.value = None;
    }
    context
}

/// Render `Run "git status" in ~/Code/stepit (Ghostty)`; legacy
/// `Run "git status" in Ghostty` when the `pwd` is unknown
/// (`StepFactory.terminalCommandDescription`, verbatim).
pub fn terminal_command_description(
    command: &str,
    working_directory: Option<&str>,
    app_name: &str,
) -> String {
    let clean = command.trim();
    match working_directory {
        Some(dir) if !dir.is_empty() => format!("Run \"{clean}\" in {dir} ({app_name})"),
        _ => format!("Run \"{clean}\" in {app_name}"),
    }
}

/// Decision produced for one keyboard event (`HotkeyRecognizer.HotkeyDecision`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HotkeyDecision {
    ToggleRecording { combo: String },
    SystemConsumed { combo: String },
    WorkflowShortcut(HotkeyChord),
    NavigationKey(HotkeyChord),
    TextInput { key: String, modifiers: KeyModifiers },
    Ignored,
}

/// Centralized hotkey resolution (`HotkeyRecognizer`, IR entry point verbatim).
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
    pub fn normalize_combo(combo: &str) -> String {
        combo.replace(' ', "").to_lowercase()
    }

    /// macOS sets `.function` on arrow / F-key events without a real `fn`
    /// press; it is not a modifier for combo rendering.
    pub fn chord_modifiers(modifiers: KeyModifiers) -> KeyModifiers {
        modifiers.subtracting(KeyModifiers::FUNCTION)
    }

    /// Classifies an IR-level keystroke (`key` = W3C `KeyboardEvent.key`).
    pub fn evaluate(
        &self,
        key: &str,
        code: Option<i64>,
        modifiers: KeyModifiers,
    ) -> HotkeyDecision {
        let modifiers = Self::chord_modifiers(modifiers);
        let chord = HotkeyChord::new(key.to_string(), None, code, modifiers);
        let combo = chord.combo();

        if Self::normalize_combo(&combo) == Self::normalize_combo(&self.toggle_combo) {
            return HotkeyDecision::ToggleRecording { combo };
        }

        if Self::built_in_system_combos().contains(&combo.as_str())
            || self
                .ignored_combos
                .iter()
                .any(|c| Self::normalize_combo(c) == Self::normalize_combo(&combo))
        {
            return HotkeyDecision::SystemConsumed { combo };
        }

        let is_control_interrupt =
            modifiers.contains(KeyModifiers::CONTROL) && !modifiers.contains(KeyModifiers::COMMAND) && key.to_lowercase() == "c";
        if modifiers.contains(KeyModifiers::COMMAND) || modifiers.contains(KeyModifiers::CONTROL) {
            if !self.capture_modifier_shortcuts && !is_control_interrupt {
                return HotkeyDecision::Ignored;
            }
            return HotkeyDecision::WorkflowShortcut(chord);
        }

        if Self::navigation_keys().contains(&key) {
            if !self.capture_navigation_keys {
                return HotkeyDecision::Ignored;
            }
            return HotkeyDecision::NavigationKey(chord);
        }

        HotkeyDecision::TextInput { key: key.to_string(), modifiers }
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
