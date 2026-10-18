//! Web (WASM) packaging surface (R/M2-07 item 3).
//!
//! The Phase 4 web driver consumes this WASM core, never a second
//! implementation. Same JSON-string boundaries as [`crate`] — data in,
//! data out — so Swift, Rust, and WASM run the identical goldens.
//! Built with `wasm-pack build core/crates/flowline_ffi --target web`;
//! verified headless with `wasm-pack test --node`.

use wasm_bindgen::prelude::*;

/// UniFFI surface version (mirrors [`crate::API_VERSION`]).
#[wasm_bindgen(js_name = "apiVersion")]
pub fn api_version() -> String {
    crate::API_VERSION.to_string()
}

/// Classify a typing context → golden label.
#[wasm_bindgen(js_name = "classifyText")]
pub fn classify_text(text: String, app_name: String, window_title: String) -> String {
    crate::classify_text(text, app_name, window_title)
}

/// Detect secrets → `[[kind, matched_text], …]` JSON array.
#[wasm_bindgen(js_name = "detectSecrets")]
pub fn detect_secrets(text: String) -> String {
    crate::detect_secrets(text)
}

/// Render markdown for a session JSON + asset prefix. Throws on bad input.
#[wasm_bindgen(js_name = "exportMarkdown")]
pub fn export_markdown(session_json: String, relative_asset_prefix: String) -> Result<String, JsValue> {
    crate::export_markdown(session_json, relative_asset_prefix)
        .map_err(|e| JsValue::from_str(&e.to_string()))
}

/// Session JSON round-trip (proves the IR codec across the boundary).
#[wasm_bindgen(js_name = "sessionRoundTrip")]
pub fn session_round_trip(session_json: String) -> Result<String, JsValue> {
    crate::session_round_trip(session_json).map_err(|e| JsValue::from_str(&e.to_string()))
}

/// Manifest validation against a host version.
#[wasm_bindgen(js_name = "manifestValidForHost")]
pub fn manifest_valid_for_host(manifest_json: String, host_version: String) -> bool {
    crate::manifest_valid_for_host(manifest_json, host_version)
}
