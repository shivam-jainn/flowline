//! Versioned FFI surface over the six core crates (R/M2-07).
//!
//! One API surface (`API_VERSION`) re-exporting every core crate behind
//! JSON-string boundaries: hosts pass JSON in, get JSON (or strings) out.
//! This keeps the boundary expressible as data + capability calls (§4) and
//! makes `uniffi-rs` codegen mechanical when the toolchain is available
//! (see `docs/roadmap/phase-r/m2-07-bindings-wasm.md` for the deferred
//! UniFFI + `wasm-pack` steps — neither `uniffi-bindgen` nor the
//! `wasm32-unknown-unknown` target exists on this machine).
//!
//! The C ABI exposes a single smoke symbol (`stepit_api_version`); richer
//! UniFFI scaffolding binds to the `api::*` functions below.

pub use stepit_ai_gateway as ai_gateway;
pub use stepit_engine as engine;
pub use stepit_ir as ir;
pub use stepit_pipeline as pipeline;
pub use stepit_projections as projections;
pub use stepit_storage as storage;

pub mod web;

use thiserror::Error;

uniffi::setup_scaffolding!("stepit_ffi");

/// Versioned FFI surface. Hosts assert this before calling anything else.
pub const API_VERSION: &str = "r-m2.1";

#[derive(Debug, Error, uniffi::Error)]
#[uniffi(flat_error)]
pub enum Error {
    #[error("bad input JSON: {0}")]
    BadInput(String),
    #[error("pipeline: {0}")]
    Pipeline(String),
    #[error("unknown documentation style: {0}")]
    UnknownStyle(String),
}

/// C ABI smoke symbol: NUL-terminated `API_VERSION`.
///
/// (Plain `extern "C"` without `#[no_mangle]` — the workspace forbids
/// `unsafe_code`, so the symbol is exported mangled; UniFFI codegen replaces
/// this with proper scaffolding when the toolchain lands.)
pub extern "C" fn stepit_api_version() -> *const std::os::raw::c_char {
    static VERSION: &[u8] = b"r-m2.1\0";
    VERSION.as_ptr() as *const std::os::raw::c_char
}

fn decode<T: serde::de::DeserializeOwned>(json: &str, what: &str) -> Result<T, Error> {
    serde_json::from_str(json).map_err(|e| Error::BadInput(format!("{what}: {e}")))
}

/// Parse + re-emit a session (proves the IR codec across the boundary).
#[uniffi::export]
pub fn session_round_trip(session_json: String) -> Result<String, Error> {
    let session: ir::StepSession = decode(&session_json, "StepSession")?;
    serde_json::to_string(&session).map_err(|e| Error::BadInput(e.to_string()))
}

/// Classify a typing context → golden label (`text`/`code:<lang>`/`terminal`).
#[uniffi::export]
pub fn classify_text(text: String, app_name: String, window_title: String) -> String {
    pipeline::classify::classify_parts(&text, &app_name, None, &window_title).label()
}

/// Detect secrets → `[[kind, matched_text], …]` JSON array (Swift raw values).
#[uniffi::export]
pub fn detect_secrets(text: String) -> String {
    let detector =
        pipeline::redact::SensitiveDataDetector::new(pipeline::redact::DetectorConfig::default());
    let hits: Vec<(String, String)> = detector
        .matches(&text)
        .iter()
        .map(|m| {
            (
                m.kind.swift_name().to_string(),
                m.matched_text.clone(),
            )
        })
        .collect();
    serde_json::to_string(&hits).expect("pairs serialize")
}

/// Render markdown for a session JSON + asset prefix.
#[uniffi::export]
pub fn export_markdown(session_json: String, relative_asset_prefix: String) -> Result<String, Error> {
    let session: ir::StepSession = decode(&session_json, "StepSession")?;
    Ok(projections::markdown::export_markdown(&session, &relative_asset_prefix))
}

/// Parse a documentation style name (`sop_guide`, …).
fn parse_style(style: &str) -> Result<ai_gateway::prompts::DocumentationStyle, Error> {
    use ai_gateway::prompts::DocumentationStyle::*;
    match style {
        "sop_guide" => Ok(SopGuide),
        "bug_report" => Ok(BugReport),
        "automation_script" => Ok(AutomationScript),
        "executive_summary" => Ok(ExecutiveSummary),
        other => Err(Error::UnknownStyle(other.to_string())),
    }
}

/// Build a gateway payload for a session/settings JSON pair.
#[uniffi::export]
pub fn gateway_build_request(
    session_json: String,
    settings_json: String,
    style: String,
    custom_instructions: Option<String>,
    recorded_at_display: String,
) -> Result<String, Error> {
    let session: ir::StepSession = decode(&session_json, "StepSession")?;
    let settings: ai_gateway::GatewaySettings = decode(&settings_json, "GatewaySettings")?;
    let req = ai_gateway::payload::build_request(
        &session,
        &settings,
        parse_style(&style)?,
        custom_instructions.as_deref(),
        &recorded_at_display,
        &[],
    );
    serde_json::to_string(&req).map_err(|e| Error::BadInput(e.to_string()))
}

/// Validate a plugin manifest JSON against a host version.
#[uniffi::export]
pub fn manifest_valid_for_host(manifest_json: String, host_version: String) -> bool {
    let Ok(manifest): Result<ir::PluginManifest, _> = serde_json::from_str(&manifest_json) else {
        return false;
    };
    manifest.validate_host(&host_version)
}
