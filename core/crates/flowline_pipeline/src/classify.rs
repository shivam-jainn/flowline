//! `KeystrokeClassifier` port (`Sources/FlowlinePipeline/KeystrokeClassifier.swift`).
//!
//! App/editor/terminal predicates plus the language table, verbatim —
//! including order of checks, word lists, and the `"text"` fallback.

use flowline_ir::RawElementContext;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InputClassification {
    Text,
    Code(String),
    Terminal,
}

impl InputClassification {
    /// Golden label strings: `text`, `code:<lang>`, `terminal`.
    pub fn label(&self) -> String {
        match self {
            Self::Text => "text".to_string(),
            Self::Terminal => "terminal".to_string(),
            Self::Code(lang) => format!("code:{lang}"),
        }
    }
}

fn lower(s: &str) -> String {
    s.to_lowercase()
}

pub fn is_terminal(app_name: &str, bundle_id: Option<&str>, window_title: &str) -> bool {
    let name = lower(app_name);
    let bid = lower(bundle_id.unwrap_or(""));
    let title = lower(window_title);

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

pub fn is_code(app_name: &str, bundle_id: Option<&str>, window_title: &str) -> bool {
    let name = lower(app_name);
    let bid = lower(bundle_id.unwrap_or(""));
    let title = lower(window_title);

    if is_terminal(app_name, bundle_id, window_title) {
        return true;
    }

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

    const EXTENSIONS: &[&str] = &[
        ".swift", ".ts", ".tsx", ".js", ".jsx", ".py", ".rs", ".go", ".cpp", ".c", ".h",
        ".json", ".yaml", ".yml", ".sh", ".bash", ".sql", ".html", ".css",
    ];
    for ext in EXTENSIONS {
        if title.contains(ext) {
            return true;
        }
    }

    false
}

pub fn detect_language(app_name: &str, window_title: &str, text: &str) -> String {
    let name = lower(app_name);
    let title = lower(window_title);

    if is_terminal(app_name, None, window_title) {
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

    let trimmed = text.trim_matches(|c: char| c.is_whitespace());
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

pub fn classify(text: &str, context: Option<&RawElementContext>) -> InputClassification {
    let (app, bundle, title) = match context {
        Some(c) => (
            c.app_name.as_str(),
            c.bundle_identifier.as_deref(),
            c.window_title.as_str(),
        ),
        None => ("", None, ""),
    };
    classify_parts(text, app, bundle, title)
}

pub fn classify_parts(
    text: &str,
    app_name: &str,
    bundle_id: Option<&str>,
    window_title: &str,
) -> InputClassification {
    if is_terminal(app_name, bundle_id, window_title) {
        return InputClassification::Terminal;
    }
    if is_code(app_name, bundle_id, window_title) {
        return InputClassification::Code(detect_language(app_name, window_title, text));
    }
    InputClassification::Text
}

/// Command-prefix vocabulary used by `Step.synthesizeDefaultDescription`.
pub fn command_prefix(text: &str) -> Option<String> {
    let trimmed = text.trim_matches(|c: char| c.is_whitespace()).to_lowercase();
    const PREFIXES: &[&str] = &[
        "git ", "npm ", "swift ", "cd ", "cat ", "ls", "curl", "docker",
    ];
    for prefix in PREFIXES {
        if trimmed.starts_with(prefix) {
            return Some(prefix.trim().to_string());
        }
    }
    None
}

// MARK: - Smart typing segmentation (hysteresis / focus / Return / paste)

/// Typing environment profile driving per-app hysteresis thresholds.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TypingProfile {
    Terminal,
    Editor,
    Url,
}

/// Canonical hysteresis bounds (millis).
///
/// - Default/editor: `T_LOW 600` JOIN, `T_HIGH 1800` CUT.
/// - Terminal: `900 / 2500` (slower cadence, longer commands).
/// - URL bar: `400 / 1200` (short bursts, fast commits).
pub const T_LOW_EDITOR: u64 = 600;
pub const T_HIGH_EDITOR: u64 = 1800;
pub const T_LOW_TERMINAL: u64 = 900;
pub const T_HIGH_TERMINAL: u64 = 2500;
pub const T_LOW_URL: u64 = 400;
pub const T_HIGH_URL: u64 = 1200;

/// Burst rate that marks pasted/IME-injected traffic: >15 Hz => gap < 66.66 ms.
pub const BURST_GAP_MAX_MILLIS: u64 = 66;

pub fn profile_thresholds(profile: TypingProfile) -> (u64, u64) {
    match profile {
        TypingProfile::Terminal => (T_LOW_TERMINAL, T_HIGH_TERMINAL),
        TypingProfile::Editor => (T_LOW_EDITOR, T_HIGH_EDITOR),
        TypingProfile::Url => (T_LOW_URL, T_HIGH_URL),
    }
}

/// `true` when the focused element is a URL/address field.
pub fn is_url_field(context: &RawElementContext) -> bool {
    let placeholder = context.placeholder.as_deref().unwrap_or("").to_lowercase();
    let title = context.title.as_deref().unwrap_or("").to_lowercase();
    let window = context.window_title.to_lowercase();
    let app = context.app_name.to_lowercase();
    let bid = context
        .bundle_identifier
        .as_deref()
        .unwrap_or("")
        .to_lowercase();

    let field_hint = placeholder.contains("url")
        || placeholder.contains("address")
        || placeholder.contains("search")
        || placeholder.contains("omnibox")
        || title.contains("address bar")
        || title.contains("omnibox")
        || title.contains("url");

    let browser = app.contains("safari")
        || app.contains("chrome")
        || app.contains("chromium")
        || app.contains("firefox")
        || app.contains("edge")
        || app.contains("arc")
        || app.contains("brave")
        || app.contains("orion")
        || bid.contains("safari")
        || bid.contains("chrome")
        || bid.contains("firefox")
        || bid.contains("edge")
        || bid.contains("arc")
        || bid.contains("brave");

    if field_hint {
        return true;
    }
    if browser
        && (window.contains("http://")
            || window.contains("https://")
            || window.contains("www."))
    {
        return true;
    }
    false
}

pub fn typing_profile(context: &RawElementContext) -> TypingProfile {
    if is_terminal(
        &context.app_name,
        context.bundle_identifier.as_deref(),
        &context.window_title,
    ) {
        return TypingProfile::Terminal;
    }
    if is_url_field(context) {
        return TypingProfile::Url;
    }
    TypingProfile::Editor
}

/// Base (non-adaptive) thresholds for a concrete context.
pub fn thresholds_for_context(context: &RawElementContext) -> (u64, u64) {
    profile_thresholds(typing_profile(context))
}

/// Adaptive personalization: `T_user = 0.8 * T_app + 0.2 * p95_IKI`.
pub fn adaptive_thresholds(
    base_low: u64,
    base_high: u64,
    p95_iki_ms: Option<u64>,
) -> (u64, u64) {
    match p95_iki_ms {
        None => (base_low, base_high),
        Some(p95) => {
            let low = (8 * base_low + 2 * p95) / 10;
            let high = (8 * base_high + 2 * p95) / 10;
            (low.max(100), high.max(low.saturating_add(100)))
        }
    }
}

/// 95th percentile of recent inter-key intervals (millis). `None` when empty.
pub fn p95_iki(gaps: &[u64]) -> Option<u64> {
    if gaps.is_empty() {
        return None;
    }
    let mut sorted = gaps.to_vec();
    sorted.sort_unstable();
    let n = sorted.len() as u64;
    let rank = (95 * n).div_ceil(100);
    let idx = (rank.saturating_sub(1) as usize).min(sorted.len().saturating_sub(1));
    Some(sorted[idx])
}

/// Hysteresis cut decision for a gap.
pub fn should_cut_by_hysteresis(
    gap_ms: u64,
    low_ms: u64,
    high_ms: u64,
    corroborated: bool,
) -> bool {
    if gap_ms < low_ms {
        return false;
    }
    if gap_ms >= high_ms {
        return true;
    }
    corroborated
}

/// `true` when `gap` marks burst/paste-rate traffic (>15 Hz).
pub fn is_burst_gap(gap_ms: u64) -> bool {
    gap_ms <= BURST_GAP_MAX_MILLIS
}

/// `true` for the `Cmd+V` paste chord (case-insensitive `v`).
pub fn is_cmd_paste(key: &str, command_held: bool) -> bool {
    command_held && key.eq_ignore_ascii_case("v")
}

/// Return-key outcome after the Return classifier.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReturnAction {
    Cut,
    JoinNewline,
}

/// Return semantics: Cmd+Return and terminal always CUT; multiline
/// (`AXTextArea`) plain Return JOINs; single-line/unknown CUTs.
pub fn classify_return(context: &RawElementContext, command_held: bool) -> ReturnAction {
    if command_held {
        return ReturnAction::Cut;
    }
    if is_terminal(
        &context.app_name,
        context.bundle_identifier.as_deref(),
        &context.window_title,
    ) {
        return ReturnAction::Cut;
    }
    let role = context.role.as_deref().unwrap_or("");
    if role.contains("TextArea") {
        return ReturnAction::JoinNewline;
    }
    if role.contains("TextField") {
        return ReturnAction::Cut;
    }
    ReturnAction::Cut
}

/// `true` when the focused element identity changed enough to force a cut.
pub fn focus_identity_changed(
    prev: Option<&RawElementContext>,
    next: &RawElementContext,
) -> bool {
    let Some(prev) = prev else {
        return false;
    };
    if next.role.as_deref() == Some("AXUnknown") {
        return false;
    }
    if prev.bundle_identifier != next.bundle_identifier {
        return true;
    }
    if prev.app_name != next.app_name {
        return true;
    }
    if prev.window_title != next.window_title {
        return true;
    }
    if prev.role != next.role {
        return true;
    }
    if prev.subrole != next.subrole {
        return true;
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn golden_labels() {
        assert_eq!(classify_parts("hello world", "TextEdit", None, "Untitled").label(), "text");
        assert_eq!(classify_parts("git status", "Terminal", None, "zsh").label(), "terminal");
        assert_eq!(
            classify_parts("func main() {}", "Xcode", None, "main.swift").label(),
            "code:swift"
        );
    }

    #[test]
    fn terminal_by_bundle_and_title() {
        assert!(is_terminal("Ghostty", Some("com.mitchellh.ghostty"), "fish"));
        assert!(is_terminal("Terminal", None, "zsh"));
        assert!(is_terminal("Notes", None, "my — zsh session"));
        assert!(is_terminal("Notes", None, "debug console"));
        assert!(!is_terminal("Notes", None, "Draft"));
    }

    #[test]
    fn code_env_lists_and_extensions() {
        assert!(is_code("Visual Studio Code", Some("com.microsoft.VSCode"), ""));
        assert!(is_code("Cursor", None, ""));
        // Terminal counts as code environment too.
        assert!(is_code("Terminal", None, "zsh"));
        assert!(is_code("TextEdit", None, "app.py"));
        assert!(!is_code("TextEdit", None, "Untitled"));
    }

    #[test]
    fn language_table_order() {
        assert_eq!(detect_language("Terminal", "zsh", "ls"), "bash");
        assert_eq!(detect_language("App", "a.ts", "x"), "typescript");
        assert_eq!(detect_language("App", "a.json", "x"), "json");
        assert_eq!(detect_language("App", "a.js", "x"), "javascript");
        assert_eq!(detect_language("App", "a.py", "x"), "python");
        assert_eq!(detect_language("App", "a.rs", "x"), "rust");
        assert_eq!(detect_language("App", "a.go", "x"), "go");
        assert_eq!(detect_language("App", "a.yml", "x"), "yaml");
        assert_eq!(detect_language("App", "a.sql", "x"), "sql");
        assert_eq!(detect_language("App", "run.sh", "x"), "bash");
        assert_eq!(detect_language("App", "i.html", "x"), "html");
        assert_eq!(detect_language("App", "s.css", "x"), "css");
        // Text-structure fallbacks.
        assert_eq!(detect_language("Notes", "Draft", "{\"a\":1}"), "json");
        assert_eq!(detect_language("Notes", "Draft", "import Foundation"), "swift");
        assert_eq!(detect_language("Notes", "Draft", "def f():"), "python");
        assert_eq!(detect_language("Notes", "Draft", "git status"), "bash");
        assert_eq!(detect_language("Notes", "Draft", "hello"), "text");
    }

    #[test]
    fn prefixes() {
        assert_eq!(command_prefix("git status"), Some("git".to_string()));
        assert_eq!(command_prefix("ls -la"), Some("ls".to_string()));
        assert_eq!(command_prefix("hello"), None);
    }

    fn smart_ctx(app: &str, bundle: Option<&str>, window: &str) -> RawElementContext {
        RawElementContext {
            app_name: app.to_string(),
            bundle_identifier: bundle.map(str::to_string),
            window_title: window.to_string(),
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

    #[test]
    fn hysteresis_boundaries() {
        // Editor 600/1800: below low joins, at/above high cuts.
        assert!(!should_cut_by_hysteresis(599, 600, 1800, false));
        assert!(!should_cut_by_hysteresis(599, 600, 1800, true));
        assert!(!should_cut_by_hysteresis(600, 600, 1800, false));
        assert!(should_cut_by_hysteresis(600, 600, 1800, true));
        assert!(!should_cut_by_hysteresis(1799, 600, 1800, false));
        assert!(should_cut_by_hysteresis(1799, 600, 1800, true));
        assert!(should_cut_by_hysteresis(1800, 600, 1800, false));
        assert!(should_cut_by_hysteresis(2500, 600, 1800, false));
    }

    #[test]
    fn per_app_profiles() {
        let term = smart_ctx("Ghostty", Some("com.mitchellh.ghostty"), "ghostty");
        assert_eq!(typing_profile(&term), TypingProfile::Terminal);
        assert_eq!(thresholds_for_context(&term), (900, 2500));

        let editor = smart_ctx("Notes", None, "Draft");
        assert_eq!(typing_profile(&editor), TypingProfile::Editor);
        assert_eq!(thresholds_for_context(&editor), (600, 1800));

        let mut url = smart_ctx("Safari", Some("com.apple.Safari"), "https://example.com");
        url.placeholder = Some("Address".to_string());
        url.role = Some("AXTextField".to_string());
        assert!(is_url_field(&url));
        assert_eq!(typing_profile(&url), TypingProfile::Url);
        assert_eq!(thresholds_for_context(&url), (400, 1200));
    }

    #[test]
    fn adaptive_blends_toward_p95() {
        assert_eq!(adaptive_thresholds(600, 1800, None), (600, 1800));
        // T_user = 0.8*T_app + 0.2*p95.
        assert_eq!(adaptive_thresholds(600, 1800, Some(1200)), (720, 1680));
        assert_eq!(adaptive_thresholds(900, 2500, Some(500)), (820, 2100));
        // p95 of a skewed sample lands on the tail.
        let gaps = vec![100, 110, 120, 130, 140, 150, 160, 170, 180, 900];
        assert_eq!(p95_iki(&gaps), Some(900));
        assert_eq!(p95_iki(&[]), None);
    }

    #[test]
    fn focus_change_cuts_except_axunknown_popup() {
        let a = smart_ctx("Notes", None, "Draft");
        let mut b = a.clone();
        assert!(!focus_identity_changed(Some(&a), &b));
        b.window_title = "Other".to_string();
        assert!(focus_identity_changed(Some(&a), &b));
        let mut c = a.clone();
        c.role = Some("AXTextField".to_string());
        let mut d = c.clone();
        d.role = Some("AXTextArea".to_string());
        assert!(focus_identity_changed(Some(&c), &d));
        // AXUnknown popup is ignorable noise.
        let mut popup = c.clone();
        popup.role = Some("AXUnknown".to_string());
        assert!(!focus_identity_changed(Some(&c), &popup));
        assert!(!focus_identity_changed(None, &a));
    }

    #[test]
    fn return_classifier() {
        let mut term = smart_ctx("Ghostty", None, "zsh");
        assert_eq!(classify_return(&term, false), ReturnAction::Cut);
        assert_eq!(classify_return(&term, true), ReturnAction::Cut);

        let mut single = smart_ctx("Safari", None, "Form");
        single.role = Some("AXTextField".to_string());
        assert_eq!(classify_return(&single, false), ReturnAction::Cut);
        assert_eq!(classify_return(&single, true), ReturnAction::Cut);

        let mut multi = smart_ctx("Notes", None, "Draft");
        multi.role = Some("AXTextArea".to_string());
        assert_eq!(classify_return(&multi, false), ReturnAction::JoinNewline);
        assert_eq!(classify_return(&multi, true), ReturnAction::Cut);

        term.role = Some("AXTextArea".to_string());
        // Terminal wins over multiline.
        assert_eq!(classify_return(&term, false), ReturnAction::Cut);
    }

    #[test]
    fn burst_and_paste_chords() {
        assert!(is_burst_gap(0));
        assert!(is_burst_gap(66));
        assert!(!is_burst_gap(67));
        assert!(is_cmd_paste("v", true));
        assert!(is_cmd_paste("V", true));
        assert!(!is_cmd_paste("v", false));
        assert!(!is_cmd_paste("c", true));
    }
}
