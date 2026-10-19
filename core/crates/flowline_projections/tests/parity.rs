//! Parity tests (R/M2-05): markdown golden byte-parity + redaction contract.

use flowline_projections::{
    assert_no_raw_secrets, js, key_visual, markdown, mcp, python, redact_placeholders, shell,
    webdoc, SecretSpan, ScriptStep,
};
use flowline_ir::StepSession;

fn load_session() -> StepSession {
    let raw = parity_harness::load_golden("session.sample.json");
    serde_json::from_str(&raw).expect("session.sample.json must deserialize")
}

/// Markdown export of the golden session == golden markdown byte-for-byte.
#[test]
fn markdown_matches_golden_byte_for_byte() {
    let session = load_session();
    let expected = parity_harness::load_golden("markdown.sample.md");
    assert_eq!(
        markdown::export_markdown(&session, ""),
        expected,
        "markdown export diverged from shared/goldens/markdown.sample.md"
    );
}

/// Asset-prefix handling mirrors Swift (`""` / trailing-`/` / bare prefix).
#[test]
fn markdown_asset_prefix_variants() {
    let mut session = load_session();
    session.steps[0].assets.gif = Some("step-1.gif".to_string());
    session.steps[0].assets.screenshot = Some("step-1.png".to_string()); // gif wins
    session.steps[1].assets.screenshot = Some("step-2.png".to_string());

    let bare = markdown::export_markdown(&session, "assets");
    assert!(bare.contains("(assets/step-1.gif)"), "bare prefix + gif");
    assert!(bare.contains("(assets/step-2.png)"), "bare prefix + png");

    let slashed = markdown::export_markdown(&session, "assets/");
    assert!(slashed.contains("(assets/step-1.gif)"), "slashed prefix");

    let empty = markdown::export_markdown(&session, "");
    assert!(empty.contains("](step-1.gif)"), "empty prefix");
    assert!(!empty.contains("gifscreenshot"), "no concatenation bugs");
}

/// Build a char-offset span for the first occurrence of `needle` in `text`.
fn char_span(text: &str, needle: &str, kind: &str) -> SecretSpan {
    let byte_idx = text.find(needle).unwrap_or_else(|| panic!("needle {needle:?} missing"));
    SecretSpan::new(text[..byte_idx].chars().count(), needle.chars().count(), kind)
}

/// Fixed 3-step session: click, typing-with-secret, terminal-with-secret.
fn three_steps() -> (Vec<ScriptStep>, Vec<&'static str>) {
    let typing_text = "login hunter2 🔑 welcome秘密";
    let typing = ScriptStep::new(
        "typing",
        "Type password in Safari",
        typing_text,
        vec![
            char_span(typing_text, "hunter2", "password"),
            char_span(typing_text, "秘密", "token"),
        ],
    );
    let cmd_text = "curl -H 'Authorization: Bearer ABC123' https://api.example.com";
    let terminal = ScriptStep::new(
        "terminal",
        "Call API in Terminal",
        cmd_text,
        vec![char_span(cmd_text, "ABC123", "token")],
    );
    let steps = vec![
        ScriptStep::new("click", "Click Save in Docs", "", vec![]),
        typing,
        terminal,
    ];
    (steps, vec!["hunter2", "秘密", "ABC123"])
}

#[test]
fn python_redacts_secrets() {
    let (steps, secrets) = three_steps();
    let out = python::render(&steps);
    assert!(out.contains("{{secret:password}}"), "password placeholder:\n{out}");
    assert!(out.contains("{{secret:token}}"), "token placeholder:\n{out}");
    assert_no_raw_secrets(&out, &secrets);
}

#[test]
fn js_redacts_secrets() {
    let (steps, secrets) = three_steps();
    let out = js::render(&steps);
    assert!(out.contains("{{secret:password}}"), "password placeholder:\n{out}");
    assert!(out.contains("{{secret:token}}"), "token placeholder:\n{out}");
    assert_no_raw_secrets(&out, &secrets);
}

#[test]
fn shell_redacts_secrets() {
    let (steps, secrets) = three_steps();
    let out = shell::render(&steps);
    assert!(out.contains("{{secret:password}}"), "password placeholder:\n{out}");
    assert!(out.contains("{{secret:token}}"), "token placeholder:\n{out}");
    assert_no_raw_secrets(&out, &secrets);
}

#[test]
fn mcp_redacts_secrets() {
    let (steps, secrets) = three_steps();
    let out = mcp::render(&steps);
    assert!(out.contains("{{secret:password}}"), "password placeholder:\n{out}");
    assert!(out.contains("{{secret:token}}"), "token placeholder:\n{out}");
    assert_no_raw_secrets(&out, &secrets);
    // Still valid JSON shaped as tool calls.
    let parsed: serde_json::Value = serde_json::from_str(&out).expect("mcp output is JSON");
    assert_eq!(parsed.as_array().expect("array").len(), 3);
}

/// Char (not byte) offsets: `🔑` is 4 bytes/1 char; CJK are 3 bytes/1 char.
/// A byte-offset implementation would slice mid-codepoint and corrupt output.
#[test]
fn placeholders_use_char_offsets_for_multibyte_text() {
    let text = "ab🔑cd密码ef"; // chars: a0 b1 🔑2 c3 d4 密5 码6 e7 f8
    let out = redact_placeholders(text, &[SecretSpan::new(5, 2, "cjk")]);
    assert_eq!(out, "ab🔑cd{{secret:cjk}}ef");

    let out2 = redact_placeholders(text, &[SecretSpan::new(2, 1, "emoji")]);
    assert_eq!(out2, "ab{{secret:emoji}}cd密码ef");

    // Overlapping spans: first wins, no raw leak, no panic.
    // chars 4..8 = d,密,码,e -> "ab🔑c" + placeholder + "f".
    let out3 = redact_placeholders(
        text,
        &[SecretSpan::new(4, 4, "a"), SecretSpan::new(5, 2, "b")],
    );
    assert_eq!(out3, "ab🔑c{{secret:a}}f");
    assert_no_raw_secrets(&out3, &["密码"]);
}

// ---------------------------------------------------------------------------
// webdoc (R/M2-05 follow-up): WebDocGenerator/Sections/Media/Theme/Icons port
// ---------------------------------------------------------------------------

/// Smoke test: generated HTML contains the session title, step cards, the
/// embedded theme stylesheet, and the interactive script.
#[test]
fn webdoc_contains_title_steps_and_chrome() {
    let session = load_session();
    let html = webdoc::generate_html(&session);
    assert!(html.starts_with("<!DOCTYPE html>"), "doctype");
    assert!(
        html.contains(&session.title),
        "session title present:\n{}",
        &html[..html.len().min(400)]
    );
    for step in &session.steps {
        assert!(
            html.contains(&format!("step-card-{}", step.index)),
            "card for step {}",
            step.index
        );
        assert!(
            html.contains(&webdoc::escape_html(&step.action_description)),
            "escaped description for step {}",
            step.index
        );
    }
    // Theme CSS embedded (design tokens), keycap/mouse attributes, script.
    assert!(html.contains("--font-sans"), "theme CSS embedded");
    assert!(html.contains("data-theme=\"modern-minimal\""), "theme attr");
    assert!(html.contains("data-keycap=\"mac3d\""), "keycap attr");
    assert!(html.contains("data-mouse=\"mac3d\""), "mouse attr");
    assert!(
        html.contains(&format!("const sessionId = \"{}\";", session.id)),
        "session id spliced into script"
    );
    assert!(html.contains("switchMediaView"), "media switcher script");
    // Header metadata: pinned IST recorded cell + format display name.
    assert!(html.contains("RECORDED"), "recorded cell");
    assert!(html.contains("Hybrid (Screenshots + GIFs)"), "format cell");
}

/// Escapes mirror Swift order (`&` first) and JS escaping drops CR.
#[test]
fn webdoc_escape_helpers_match_swift() {
    assert_eq!(
        webdoc::escape_html("<a href=\"x\">'&'"),
        "&lt;a href=&quot;x&quot;&gt;&#39;&amp;&#39;"
    );
    assert_eq!(webdoc::escape_js("a\\b'c\nd\re"), "a\\\\b\\'c\\nde");
    assert_eq!(webdoc::asset_prefix(""), "");
    assert_eq!(webdoc::asset_prefix("media"), "media/");
    assert_eq!(webdoc::asset_prefix("media/"), "media/");
}

/// Asset prefix flows into media `src` attributes.
#[test]
fn webdoc_asset_prefix_applies_to_media() {
    let mut session = load_session();
    session.steps[0].assets.screenshot = Some("step-1.png".to_string());
    let bare = webdoc::generate_html_with_settings(
        &session,
        &webdoc::WebPublishSettings::default(),
        "assets",
    );
    assert!(bare.contains("src=\"assets/step-1.png\""), "bare prefix");
    let empty = webdoc::generate_html(&session);
    assert!(empty.contains("src=\"step-1.png\""), "empty prefix");
}

// ---------------------------------------------------------------------------
// key_visual: KeyComboTokens port
// ---------------------------------------------------------------------------

#[test]
fn key_tokens_split_modifiers_and_plus_forms() {
    use key_visual::{glyph_for_w3c_key, mouse_label, typed_tokens};
    assert_eq!(key_visual::tokens_from("⌘⇧P"), vec!["⌘", "⇧", "P"]);
    assert_eq!(key_visual::tokens_from("⌥Space"), vec!["⌥", "Space"]);
    assert_eq!(
        key_visual::tokens_from("Ctrl+Shift+P"),
        vec!["Ctrl", "Shift", "P"]
    );
    assert!(key_visual::tokens_from("   ").is_empty());
    // Web row: one <kbd> per token with the style class.
    let row = key_visual::web_keycaps_html("⌘S", key_visual::KeycapStyle::Mac3D);
    assert!(row.contains("<kbd class=\"keycap keycap-mac3d is-mod\">⌘</kbd>"));
    assert!(row.contains("<kbd class=\"keycap keycap-mac3d\">S</kbd>"));
    assert!(row.contains("key-plus"), "plus separator");
    // W3C glyphs + typed tokens + mouse labels.
    assert_eq!(glyph_for_w3c_key("ArrowLeft"), "←");
    assert_eq!(glyph_for_w3c_key("Escape"), "esc");
    assert_eq!(glyph_for_w3c_key(" "), "Space");
    assert_eq!(typed_tokens("^", 12), Some(vec!["^".to_string()]));
    assert_eq!(typed_tokens("", 12), None);
    assert!(typed_tokens(&"x".repeat(13), 12).is_none());
    assert_eq!(mouse_label("click"), Some("Left click"));
    assert_eq!(mouse_label("rightClick"), Some("Right click"));
    assert_eq!(mouse_label("right_click"), Some("Right click"));
    assert_eq!(mouse_label("typing"), None);
}

// ---------------------------------------------------------------------------
// open-in-editor deep links (OpenInEditorCore port)
// ---------------------------------------------------------------------------

#[test]
fn deep_links_match_swift_rules() {
    use webdoc::{deep_link_url, editor_launch_info, finder_fallback_toast, resolved_url_scheme};
    let vscode = editor_launch_info("vscode").expect("vscode known");
    assert_eq!(
        deep_link_url(vscode, "/tmp/a b.swift", Some(3), Some(7), None),
        Some("vscode://file/tmp/a%20b.swift:3:7".to_string())
    );
    // Column without line is dropped; non-positive values dropped.
    assert_eq!(
        deep_link_url(vscode, "/tmp/f.swift", None, Some(7), None),
        Some("vscode://file/tmp/f.swift".to_string())
    );
    assert_eq!(
        deep_link_url(vscode, "/tmp/f.swift", Some(0), Some(-2), None),
        Some("vscode://file/tmp/f.swift".to_string())
    );
    // Insiders install resolves the insiders scheme.
    assert_eq!(
        resolved_url_scheme(vscode, Some("com.microsoft.VSCodeInsiders")),
        Some("vscode-insiders")
    );
    assert_eq!(
        deep_link_url(
            vscode,
            "/tmp/f.swift",
            Some(1),
            None,
            Some("com.microsoft.VSCodeInsiders")
        ),
        Some("vscode-insiders://file/tmp/f.swift:1".to_string())
    );
    // Sublime query shape.
    let sublime = editor_launch_info("sublime").expect("sublime known");
    assert_eq!(
        deep_link_url(sublime, "/tmp/f.swift", Some(2), Some(4), None),
        Some("sublimetext://open?url=file:///tmp/f.swift&line=2&column=4".to_string())
    );
    // Xcode / Finder have no deep-link style; unknown targets are None.
    assert_eq!(
        deep_link_url(editor_launch_info("xcode").unwrap(), "/tmp/f.swift", None, None, None),
        None
    );
    assert!(editor_launch_info("nova").is_none());
    assert!(deep_link_url(vscode, "", None, None, None).is_none());
    assert_eq!(
        finder_fallback_toast("Cursor"),
        "Cursor isn't installed — revealed the file in Finder instead."
    );
}
