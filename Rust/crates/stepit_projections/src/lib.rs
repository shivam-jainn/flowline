//! Projections: markdown / python / js / shell / mcp string generators (R/M2-05).
//!
//! NOTE: `stepit_ir` does not exist as a Rust crate yet (M2-01 has not
//! landed), so the minimal `Session`/`Step` model needed for projection is
//! defined locally here (serde-compatible with the Swift `StepSession` JSON).
//! When `stepit_ir` lands, this model should be replaced with a dependency on
//! it. Field shapes mirror `Sources/StepItIR/Model/StepSession.swift`.
//!
//! Redaction contract (shared by all generators): secret values NEVER appear
//! in output. Callers supply pre-classified char-offset spans
//! ([`SecretSpan`], matching Swift `Range<Int>` character semantics); each
//! covered range is replaced with `{{secret:<kind>}}` by
//! [`redact_placeholders`].

pub mod js;
pub mod markdown;
pub mod mcp;
pub mod python;
pub mod shell;

use serde::{Deserialize, Serialize};

/// A pre-classified secret range inside a text value.
///
/// Offsets are **char** offsets (NOT byte offsets), matching Swift
/// `Range<Int>` / `String.Index` semantics over extended grapheme clusters
/// (approximated by Rust `char`s). Generators must go through
/// [`redact_placeholders`] so multibyte text (emoji/CJK) is sliced on char
/// boundaries and never panics or leaks partial bytes.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SecretSpan {
    /// Start offset in `char`s from the beginning of the text.
    pub start: usize,
    /// Length in `char`s.
    pub len: usize,
    /// Secret category, emitted verbatim as `{{secret:<kind>}}`.
    pub kind: String,
}

impl SecretSpan {
    pub fn new(start: usize, len: usize, kind: &str) -> Self {
        Self {
            start,
            len,
            kind: kind.to_string(),
        }
    }
}

/// Replace every [`SecretSpan`] range in `text` with `{{secret:<kind>}}`.
///
/// * Spans are interpreted as char offsets; out-of-range tails are clamped.
/// * Spans are sorted by start; a span overlapping an already-emitted range
///   is skipped (first span wins), so output never contains a raw secret even
///   with hostile span input.
/// * Text outside spans is passed through untouched.
pub fn redact_placeholders(text: &str, spans: &[SecretSpan]) -> String {
    if spans.is_empty() {
        return text.to_string();
    }
    let chars: Vec<char> = text.chars().collect();
    let mut ordered: Vec<&SecretSpan> = spans.iter().collect();
    ordered.sort_by_key(|s| (s.start, s.len));
    let mut out = String::with_capacity(text.len() + spans.len() * 16);
    let mut cursor = 0usize;
    for span in ordered {
        if span.len == 0 {
            continue;
        }
        let end = span.start.saturating_add(span.len).min(chars.len());
        let start = span.start.min(chars.len());
        if start < cursor {
            continue; // overlaps an already-redacted range: skip
        }
        for &c in &chars[cursor..start] {
            out.push(c);
        }
        out.push_str("{{secret:");
        out.push_str(&span.kind);
        out.push_str("}}");
        cursor = end.max(cursor);
    }
    for &c in &chars[cursor..] {
        out.push(c);
    }
    out
}

/// Test helper: fail if any non-empty secret appears verbatim in `output`.
#[track_caller]
pub fn assert_no_raw_secrets(output: &str, secrets: &[&str]) {
    for secret in secrets {
        if secret.is_empty() {
            continue;
        }
        assert!(
            !output.contains(secret),
            "raw secret leaked into output: {secret:?}"
        );
    }
}

/// Minimal input step for the script/tool-call generators.
///
/// `text` holds the typed literal or terminal command; `secrets` classifies
/// the sensitive ranges inside it. Non-text steps (clicks, hotkeys) leave
/// `text` empty and describe themselves via `action`/`description`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ScriptStep {
    /// Action id, e.g. `"click"`, `"typing"`, `"terminal"`, `"key_press"`.
    pub action: String,
    /// Human-readable description (emitted as comments, never executed).
    pub description: String,
    /// Typed text or shell command (may be empty).
    #[serde(default)]
    pub text: String,
    /// Pre-classified secret spans over `text` (char offsets).
    #[serde(default)]
    pub secrets: Vec<SecretSpan>,
}

impl ScriptStep {
    pub fn new(action: &str, description: &str, text: &str, secrets: Vec<SecretSpan>) -> Self {
        Self {
            action: action.to_string(),
            description: description.to_string(),
            text: text.to_string(),
            secrets,
        }
    }

    /// `text` with secrets replaced by `{{secret:<kind>}}` placeholders.
    pub fn redacted_text(&self) -> String {
        redact_placeholders(&self.text, &self.secrets)
    }
}

pub use stepit_ir::{MediaAssets, ScreenCoordinates, Step, StepSession};
