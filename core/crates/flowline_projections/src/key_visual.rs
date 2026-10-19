//! Key-visual styles — port of `KeyVisualStyle.swift` (`KeycapStyle`,
//! `MouseStyle`, `KeyComboTokens`).
//!
//! Pure string/token logic only: splits recorded `hotkeyCombo` strings into
//! per-keycap tokens, renders `<kbd>` rows for the web doc, and maps W3C
//! `KeyboardEvent.key` names to cap legends. No native imports.

use serde::{Deserialize, Serialize};

/// Selectable keystroke visual style.
///
/// Mirrors `KeycapStyle` raw values / labels / CSS classes / `data-keycap`
/// values branch-for-branch.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
pub enum KeycapStyle {
    /// Flat Magic Keyboard — matte, 1px border.
    #[serde(rename = "mac2D")]
    Mac2D,
    /// Apple bezel — gradient + bottom edge + shadow.
    #[serde(rename = "mac3D")]
    #[default]
    Mac3D,
    /// Mechanical — deep dish, side wall, tinted mods.
    #[serde(rename = "mechanical3D")]
    Mechanical3D,
}

impl KeycapStyle {
    /// Human-readable label (`KeycapStyle.label`).
    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            Self::Mac2D => "Mac 2D",
            Self::Mac3D => "Mac 3D",
            Self::Mechanical3D => "3D Keys",
        }
    }

    /// Blurb (`KeycapStyle.blurb`).
    #[must_use]
    pub const fn blurb(self) -> &'static str {
        match self {
            Self::Mac2D => "Flat Magic Keyboard — matte, 1px border",
            Self::Mac3D => "Apple bezel — gradient + bottom edge + shadow",
            Self::Mechanical3D => "Mechanical — deep dish, side wall, tinted mods",
        }
    }

    /// CSS class suffix (`keycap-mac2d` …).
    #[must_use]
    pub const fn css_class(self) -> &'static str {
        match self {
            Self::Mac2D => "keycap-mac2d",
            Self::Mac3D => "keycap-mac3d",
            Self::Mechanical3D => "keycap-mech",
        }
    }

    /// `data-keycap` value on `<html>`.
    #[must_use]
    pub const fn html_value(self) -> &'static str {
        match self {
            Self::Mac2D => "mac2d",
            Self::Mac3D => "mac3d",
            Self::Mechanical3D => "mech",
        }
    }
}

/// Selectable mouse-pointer halo style. Mirrors `MouseStyle`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
pub enum MouseStyle {
    /// Thin ring + dot, no shadow.
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

impl MouseStyle {
    /// Human-readable label.
    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            Self::Flat => "Flat",
            Self::Mac2D => "Mac 2D",
            Self::Mac3D => "Mac 3D",
        }
    }

    /// Blurb.
    #[must_use]
    pub const fn blurb(self) -> &'static str {
        match self {
            Self::Flat => "Thin ring + dot, no shadow",
            Self::Mac2D => "Native pointer in a flat badge",
            Self::Mac3D => "Double ring + glow + drop shadow",
        }
    }

    /// CSS class.
    #[must_use]
    pub const fn css_class(self) -> &'static str {
        match self {
            Self::Flat => "mouse-flat",
            Self::Mac2D => "mouse-mac2d",
            Self::Mac3D => "mouse-mac3d",
        }
    }

    /// `data-mouse` value on `<html>`.
    #[must_use]
    pub const fn html_value(self) -> &'static str {
        match self {
            Self::Flat => "flat",
            Self::Mac2D => "mac2d",
            Self::Mac3D => "mac3d",
        }
    }
}

/// Single-char modifier / navigation symbols that always stand alone.
///
/// Mirrors `KeyComboTokens.standalone`. Includes ASCII `^` (caret notation
/// for Control) so it never fuses into a neighboring token.
///
/// DIVERGENCE: Swift's set holds `"🌐︎"` (U+1F310 + U+FE0E variation
/// selector) as one `Character` (grapheme cluster). Rust matches on `char`s,
/// so only the base `'🌐'` (U+1F310) is listed here; a trailing VS16 falls
/// into the word buffer. Combos never contain this symbol in practice.
pub fn is_standalone(ch: char) -> bool {
    matches!(
        ch,
        '⌘' | '⌥'
            | '⇧'
            | '⌃'
            | '⇥'
            | '⎋'
            | '⏎'
            | '⌫'
            | '⌦'
            | '↑'
            | '↓'
            | '←'
            | '→'
            | '␣'
            | '⇪'
            | '🌐'
            | '⊞'
            | '❖'
            | '^'
    )
}

/// Swift `.whitespaces` (WITHOUT newlines) trim, mirroring
/// `trimmingCharacters(in: .whitespaces)`. Same helper as `markdown.rs`.
fn trim_swift_ws(s: &str) -> &str {
    s.trim_matches(|c: char| c.is_whitespace() && c != '\n' && c != '\r')
}

/// Tokenizes a recorded `hotkeyCombo` (e.g. `"⌘⇧P"`, `"⌘S"`, `"⌥Space"`,
/// `"Ctrl+Shift+P"`) into per-keycap tokens.
///
/// Mirrors `KeyComboTokens.tokens(from:)` branch-for-branch:
/// - `"+"`-joined strings split on `"+"`.
/// - Otherwise each standalone symbol is its own token and the remainder is
///   grouped into words/single characters.
pub fn tokens_from(combo: &str) -> Vec<String> {
    let trimmed = combo.trim_matches(|c: char| c.is_whitespace());
    if trimmed.is_empty() {
        return Vec::new();
    }
    if trimmed.contains('+') {
        return trimmed
            .split('+')
            .map(trim_swift_ws)
            .filter(|t| !t.is_empty())
            .map(str::to_string)
            .collect();
    }
    let mut out: Vec<String> = Vec::new();
    let mut buf = String::new();
    let flush = |buf: &mut String, out: &mut Vec<String>| {
        let t = trim_swift_ws(buf).to_string();
        if !t.is_empty() {
            out.push(t);
        }
        buf.clear();
    };
    for ch in trimmed.chars() {
        if is_standalone(ch) {
            flush(&mut buf, &mut out);
            out.push(ch.to_string());
        } else if ch.is_whitespace() {
            flush(&mut buf, &mut out);
        } else {
            buf.push(ch);
        }
    }
    flush(&mut buf, &mut out);
    if out.is_empty() {
        return vec![trimmed.to_string()];
    }
    out
}

/// True for modifier caps (get the tinted/slate treatment in 3D styles).
/// Mirrors `KeyComboTokens.isModifier`.
pub fn is_modifier(token: &str) -> bool {
    if token.chars().count() == 1 {
        if let Some(ch) = token.chars().next() {
            return is_standalone(ch);
        }
    }
    matches!(
        token.to_lowercase().as_str(),
        "cmd" | "command"
            | "opt"
            | "option"
            | "alt"
            | "ctrl"
            | "control"
            | "shift"
            | "fn"
            | "meta"
            | "win"
            | "caps"
            | "capslock"
    )
}

/// Escaped HTML for one token. Mirrors `KeyComboTokens.escapeHTML`
/// (escapes `& < > "` only — NOT `'`).
pub fn escape_token_html(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

/// `<kbd>` row for the web doc. `style` picks the per-cap CSS class.
/// Mirrors `KeyComboTokens.webKeycapsHTML(combo:style:)`.
pub fn web_keycaps_html(combo: &str, style: KeycapStyle) -> String {
    web_caps_html(&tokens_from(combo), style)
}

/// `<kbd>` row from pre-split tokens. Mirrors `KeyComboTokens.webCapsHTML`.
pub fn web_caps_html(tokens: &[String], style: KeycapStyle) -> String {
    tokens
        .iter()
        .map(|t| {
            let modifier = if is_modifier(t) { " is-mod" } else { "" };
            format!(
                "<kbd class=\"keycap {}{modifier}\">{}</kbd>",
                style.css_class(),
                escape_token_html(t)
            )
        })
        .collect::<Vec<_>>()
        .join("<span class=\"key-plus\" aria-hidden=\"true\">+</span>")
}

/// Tokens for a step: the recorded combo when present, else the bare
/// pressed key (`element_title` carries the W3C key name for key presses).
/// Mirrors `KeyComboTokens.tokensForStep`.
pub fn tokens_for_step(combo: Option<&str>, element_title: Option<&str>) -> Vec<String> {
    if let Some(c) = combo {
        if !c.trim_matches(|ch: char| ch.is_whitespace()).is_empty() {
            return tokens_from(c);
        }
    }
    if let Some(t) = element_title {
        if !t.trim_matches(|ch: char| ch.is_whitespace()).is_empty() {
            return vec![glyph_for_w3c_key(t)];
        }
    }
    Vec::new()
}

/// W3C `KeyboardEvent.key` name → cap legend. Unknown names pass through
/// (truncated) so nothing silently disappears.
/// Mirrors `KeyComboTokens.glyph(forW3CKey:)`.
pub fn glyph_for_w3c_key(key: &str) -> String {
    match key {
        "ArrowUp" => "↑".to_string(),
        "ArrowDown" => "↓".to_string(),
        "ArrowLeft" => "←".to_string(),
        "ArrowRight" => "→".to_string(),
        "Enter" => "⏎".to_string(),
        "Backspace" => "⌫".to_string(),
        "Delete" | "Del" => "⌦".to_string(),
        "Escape" | "Esc" => "esc".to_string(),
        "Tab" => "⇥".to_string(),
        " " => "Space".to_string(),
        "Spacebar" => "Space".to_string(),
        _ => {
            if key.chars().count() <= 12 {
                key.to_string()
            } else {
                let head: String = key.chars().take(12).collect();
                format!("{head}…")
            }
        }
    }
}

/// Per-character caps for short typed text (`"^"` → `["^"]`), so typed
/// characters get a visual instead of vanishing. Returns `None` for empty
/// or long blobs (the code card already shows those).
/// Mirrors `KeyComboTokens.typedTokens(text:maxChars:)` (default 12).
pub fn typed_tokens(text: &str, max_chars: usize) -> Option<Vec<String>> {
    if text.is_empty() || text.chars().count() > max_chars {
        return None;
    }
    Some(
        text.chars()
            .map(|ch| match ch {
                ' ' => "Space".to_string(),
                '\n' => "⏎".to_string(),
                '\t' => "⇥".to_string(),
                _ => ch.to_string(),
            })
            .collect(),
    )
}

/// Mouse action → short web label. `None` for non-pointer steps.
/// Accepts both `ActionType.rawValue` (`"click"`, `"right_click"` …) and
/// camelCase (`"rightClick"`) so callers never have to convert.
/// Mirrors `KeyComboTokens.mouseLabel(action:)`.
pub fn mouse_label(action: &str) -> Option<&'static str> {
    match action {
        "click" => Some("Left click"),
        "rightClick" | "right_click" => Some("Right click"),
        "doubleClick" | "double_click" => Some("Double click"),
        "mouseDrag" | "mouse_drag" => Some("Drag"),
        _ => None,
    }
}
