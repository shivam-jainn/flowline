//! Parity tests (R/M2-05): markdown golden byte-parity + redaction contract.

use stepit_projections::{
    assert_no_raw_secrets, js, markdown, mcp, python, redact_placeholders, shell, SecretSpan,
    ScriptStep,
};
use stepit_ir::StepSession;

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
        "markdown export diverged from Rust/goldens/markdown.sample.md"
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
