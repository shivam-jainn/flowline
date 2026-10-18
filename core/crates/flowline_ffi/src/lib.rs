//! Versioned FFI surface over the six core crates (R/M2-07).
//!
//! One API surface (`API_VERSION`) re-exporting every core crate behind
//! JSON-string boundaries: hosts pass JSON in, get JSON (or strings) out.
//! This keeps the boundary expressible as data + capability calls (§4).
//!
//! Bindings: `uniffi::export` on the six boundary functions +
//! `setup_scaffolding!`; Swift bindings are generated with
//! `Scripts/build-rust-ffi.sh` into `Generated/FlowlineFFI/` and linked via the
//! `FlowlineFFI` target in `Package.swift` (proven by
//! `Tests/FlowlineTests/DataLine/PhaseR09FFITests.swift`). Web: `web.rs`
//! (`#[wasm_bindgen]`) packaged with `wasm-pack build` (proven by
//! `wasm-pack test --node`).
//!
//! The C ABI exposes a single smoke symbol (`flowline_api_version`); richer
//! UniFFI scaffolding binds to the `api::*` functions below.

pub use flowline_ai_gateway as ai_gateway;
pub use flowline_engine as engine;
pub use flowline_ir as ir;
pub use flowline_pipeline as pipeline;
pub use flowline_projections as projections;
pub use flowline_storage as storage;

pub mod web;

use thiserror::Error;

uniffi::setup_scaffolding!("flowline_ffi");

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
pub extern "C" fn flowline_api_version() -> *const std::os::raw::c_char {
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

/// Typing thresholds for a focused element → JSON
/// `{"lowMs":600,"highMs":1800,"profile":"editor"|"terminal"|"url"}`.
///
/// Rust core is the source of truth; the Swift twins call this instead of
/// forking the per-app table.
#[uniffi::export]
pub fn typing_thresholds(
    app_name: String,
    bundle_id: Option<String>,
    window_title: String,
    role: Option<String>,
    placeholder: Option<String>,
) -> String {
    let ctx = ir::RawElementContext {
        app_name,
        bundle_identifier: bundle_id,
        window_title,
        role,
        subrole: None,
        title: None,
        value: None,
        placeholder,
        role_description: None,
        is_secure: false,
        bounding_box: None,
        window_bounds: None,
        selectors: Vec::new(),
    };
    let (low, high) = pipeline::classify::thresholds_for_context(&ctx);
    let profile = match pipeline::classify::typing_profile(&ctx) {
        pipeline::classify::TypingProfile::Terminal => "terminal",
        pipeline::classify::TypingProfile::Editor => "editor",
        pipeline::classify::TypingProfile::Url => "url",
    };
    format!("{{\"lowMs\":{low},\"highMs\":{high},\"profile\":\"{profile}\"}}")
}

/// Hysteresis cut decision: JOIN below `low_ms`, CUT at/above `high_ms`,
/// otherwise HOLD unless `corroborated`.
#[uniffi::export]
pub fn typing_should_cut(gap_ms: u64, low_ms: u64, high_ms: u64, corroborated: bool) -> bool {
    pipeline::classify::should_cut_by_hysteresis(gap_ms, low_ms, high_ms, corroborated)
}

/// Burst-rate probe: `true` above 15 Hz (paste/IME injection cadence).
#[uniffi::export]
pub fn typing_is_burst(gap_ms: u64) -> bool {
    pipeline::classify::is_burst_gap(gap_ms)
}

/// 95th percentile of recent inter-key intervals, if any.
#[uniffi::export]
pub fn typing_p95_iki(gaps: Vec<u64>) -> Option<u64> {
    pipeline::classify::p95_iki(&gaps)
}

/// Adaptive personalization `T_user = 0.8*T_app + 0.2*p95` → `[low, high]`.
#[uniffi::export]
pub fn typing_adaptive_thresholds(
    base_low_ms: u64,
    base_high_ms: u64,
    p95_iki_ms: Option<u64>,
) -> Vec<u64> {
    let (low, high) =
        pipeline::classify::adaptive_thresholds(base_low_ms, base_high_ms, p95_iki_ms);
    vec![low, high]
}

/// Focus-change cut probe over two context JSONs → `true` when the
/// bundle/window/AX-role identity changed (`AXUnknown` popups never cut).
#[uniffi::export]
pub fn typing_focus_changed(prev_json: String, next_json: String) -> Result<bool, Error> {
    let prev: ir::RawElementContext =
        decode(&prev_json, "RawElementContext").map_err(|_| Error::BadInput("prev_json".to_string()))?;
    let next: ir::RawElementContext =
        decode(&next_json, "RawElementContext").map_err(|_| Error::BadInput("next_json".to_string()))?;
    Ok(pipeline::classify::focus_identity_changed(Some(&prev), &next))
}

/// Return semantics → `"cut"` or `"join"` (multiline plain Return joins).
#[uniffi::export]
pub fn typing_classify_return(
    app_name: String,
    bundle_id: Option<String>,
    window_title: String,
    role: Option<String>,
    command_held: bool,
) -> String {
    let ctx = ir::RawElementContext {
        app_name,
        bundle_identifier: bundle_id,
        window_title,
        role,
        subrole: None,
        title: None,
        value: None,
        placeholder: None,
        role_description: None,
        is_secure: false,
        bounding_box: None,
        window_bounds: None,
        selectors: Vec::new(),
    };
    match pipeline::classify::classify_return(&ctx, command_held) {
        pipeline::classify::ReturnAction::Cut => "cut".to_string(),
        pipeline::classify::ReturnAction::JoinNewline => "join".to_string(),
    }
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
