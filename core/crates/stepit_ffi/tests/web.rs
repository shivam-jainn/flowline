//! WASM headless tests (R/M2-07 item 3): same goldens, Node runtime.
//! Run with `wasm-pack test --node -p stepit_ffi` (needs Node; no browser).

use stepit_ffi::web;
use wasm_bindgen_test::wasm_bindgen_test;

#[wasm_bindgen_test]
fn wasm_classify_matches_golden_labels() {
    assert_eq!(
        web::classify_text(
            "git status".to_string(),
            "Terminal".to_string(),
            "zsh".to_string()
        ),
        "terminal"
    );
    assert_eq!(
        web::classify_text(
            "hello".to_string(),
            "TextEdit".to_string(),
            "Untitled".to_string()
        ),
        "text"
    );
}

#[wasm_bindgen_test]
fn wasm_session_round_trip_preserves_id() {
    let session = r#"{"id":"sess_wasm01","startedAt":"2026-03-01T10:00:00Z","title":"WASM","theme":"modern-minimal","mediaMode":"hybrid","steps":[],"exports":{}}"#;
    let back = web::session_round_trip(session.to_string()).expect("round-trip");
    assert!(back.contains("sess_wasm01"), "got: {back}");
}

#[wasm_bindgen_test]
fn wasm_secrets_detected() {
    let hits = web::detect_secrets("key sk-1234567890abcdef1234567890abcdef12 end".to_string());
    assert!(hits.contains("openAIAPIKey"), "got: {hits}");
}
