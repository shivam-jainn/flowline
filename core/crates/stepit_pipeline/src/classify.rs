//! `KeystrokeClassifier` port (`Sources/StepItPipeline/KeystrokeClassifier.swift`).
//!
//! App/editor/terminal predicates plus the language table, verbatim —
//! including order of checks, word lists, and the `"text"` fallback.

use stepit_ir::RawElementContext;

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
}
