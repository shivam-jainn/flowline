//! Cross-crate shared suite (R/M2-07): one fixture corpus through the FFI
//! surface — Swift, Rust crates, and (when the toolchain lands) WASM run the
//! same goldens. Runs under `cargo test -p stepit_ffi`.

use stepit_ffi as ffi;

#[test]
fn api_version_is_pinned() {
    assert_eq!(ffi::API_VERSION, "r-m2.1");
    let ptr = ffi::stepit_api_version();
    assert!(!ptr.is_null());
}

#[test]
fn session_round_trip_matches_golden() {
    let golden = parity_harness::load_golden("session.sample.json");
    let out = ffi::session_round_trip(&golden).expect("round-trip");
    parity_harness::assert_parity(&out, "session.sample.json");
}

#[test]
fn classify_and_redact_share_pipeline() {
    assert_eq!(ffi::classify_text("git status", "Terminal", "zsh"), "terminal");
    assert_eq!(ffi::classify_text("hello world", "TextEdit", "Untitled"), "text");
    let hits = ffi::detect_secrets("key sk-1234567890abcdef1234567890abcdef12 end");
    assert!(hits.contains("openAIAPIKey"), "got: {hits}");
    assert!(hits.contains("sk-1234567890abcdef1234567890abcdef12"), "got: {hits}");
}

#[test]
fn markdown_end_to_end_matches_golden() {
    let session = parity_harness::load_golden("session.sample.json");
    let expected = parity_harness::load_golden("markdown.sample.md");
    assert_eq!(
        ffi::export_markdown(&session, "../").expect("markdown"),
        expected
    );
}

#[test]
fn gateway_end_to_end_matches_golden() {
    // The payload golden was built from a text-only session; rebuild the same
    // input shape here (mirrors stepit_ai_gateway's parity test).
    let session = serde_json::json!({
        "id": "sess_00000002",
        "startedAt": "2026-03-01T10:00:00Z",
        "endedAt": "2026-03-01T10:00:01Z",
        "title": "Text Session",
        "theme": "modern-minimal",
        "mediaMode": "hybrid",
        "steps": [{
            "id": "step-0101", "index": 1,
            "timestamp": "2026-03-01T10:00:00Z",
            "action": "typing", "appName": "TextEdit",
            "windowTitle": "Untitled",
            "actionDescription": "Type text in TextEdit",
            "isCode": false,
            "assets": {},
            "textBlob": "hello world",
        }],
        "exports": {},
    });
    let settings = serde_json::json!({
        "provider": "openrouter",
        "baseURL": "https://openrouter.ai/api/v1",
        "apiKey": "",
        "model": "anthropic/claude-3.5-sonnet",
        "visionEnabled": false,
        "temperature": 0.2,
    });
    let out = ffi::gateway_build_request(
        &session.to_string(),
        &settings.to_string(),
        "sop_guide",
        None,
        "1/3/2026, 3:30\u{202f}PM",
    )
    .expect("payload");
    parity_harness::assert_parity(&out, "gateway.payload.json");
}

#[test]
fn unknown_style_fails_fast() {
    let session = parity_harness::load_golden("session.sample.json");
    let settings = serde_json::json!({
        "provider": "ollama",
        "baseURL": "http://localhost:11434/v1",
        "apiKey": "",
        "model": "llama3.2-vision",
        "visionEnabled": false,
        "temperature": 0.2,
    });
    assert!(ffi::gateway_build_request(
        &session,
        &settings.to_string(),
        "nope",
        None,
        "x"
    )
    .is_err());
}

#[test]
fn manifest_validation_end_to_end() {
    let manifest = parity_harness::load_golden("manifest.sample.json");
    assert!(ffi::manifest_valid_for_host(&manifest, "r-m1"));
    assert!(!ffi::manifest_valid_for_host(&manifest, "r-m0"));
    assert!(!ffi::manifest_valid_for_host("not json", "r-m1"));
}
