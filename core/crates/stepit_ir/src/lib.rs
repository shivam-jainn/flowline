//! `stepit_ir` — Rust port of Swift `Sources/StepItIR/` (R/M2-01).
//!
//! Mirrors every `Codable` type with identical JSON keys/casing so output is
//! byte-identical (canonical) to Swift `JSONEncoder(sortedKeys:)` goldens.
//! Dates and UUIDs are plain `String`s (no chrono/uuid dependency).
//!
//! Layout follows the Swift twin (`Events/` and `Model/` under
//! `Sources/StepItIR/`, plus `GestureAction.swift` and `PluginManifest.swift`).

pub mod base64_data;
pub mod events;
pub mod manifest;
pub mod numbers;
pub mod session;

pub use events::{
    ClipAsset, ClipBufferConfig, ElementSelector, FrameSnapshot, GestureAction,
    HotkeyChord, KeyModifiers, MouseButton, OcrTextItem, Point2D, RawElementContext,
    RawGestureNotice, RawInputEvent, RawInputKind, RedactionOutcome,
};
pub use manifest::PluginManifest;
pub use session::{
    ActionType, ElementRect, ExportPaths, MediaAssets, MediaMode, ScreenCoordinates,
    Step, StepSession, ThemeName,
};

use thiserror::Error;

/// Decode/encode failures for IR JSON.
#[derive(Debug, Error)]
pub enum Error {
    /// `serde_json` parse or type error.
    #[error("ir json error: {0}")]
    Json(#[from] serde_json::Error),
    /// Malformed base64 in a `Data` field.
    #[error("ir base64 error: {0}")]
    Base64(String),
}

/// Decode IR JSON into `T` (e.g. `Vec<RawInputEvent>`, `StepSession`).
pub fn from_json<T: serde::de::DeserializeOwned>(json: &str) -> Result<T, Error> {
    Ok(serde_json::from_str(json)?)
}

/// Encode IR to compact JSON.
pub fn to_json<T: serde::Serialize>(value: &T) -> Result<String, Error> {
    Ok(serde_json::to_string(value)?)
}
