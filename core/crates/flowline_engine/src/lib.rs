//! `flowline_engine` — deterministic synchronous port of Swift
//! `Sources/FlowlineEngine/` (R/M2-03).
//!
//! The Swift engine is an actor consuming `RawInputEvent`s and producing
//! `StepSession`s. This port is a synchronous state machine over recorded
//! streams: async/driver/store become injected traits, and time is injected
//! millis threaded from the caller (`now_millis`). No tokio dependency, no
//! I/O/clock/RNG inside core functions — rebuild ⇒ byte-identical.
//!
//! Module split mirrors the M1-03 reducer split 1:1:
//! - [`state`]: `RecordingState`, `EngineConfig`, `RecorderSnapshot`.
//! - [`reducer`]: `Engine::process_event` dispatch (`EventReducer.swift`).
//! - [`step_gate`]: gated step production + `ProducedStep` (engine-shaped
//!   `make_*` builders; pure `StepFactory` logic delegates to
//!   `flowline_pipeline::step_factory`).
//! - [`enrichment`]: terminal/pwd + app-context fill + privacy hooks
//!   (classification, hotkey policy, and batch-context normalization delegate
//!   to `flowline_pipeline`).
//! - [`clips`]: clip orchestration + media persistence naming.

pub mod clips;
pub mod enrichment;
pub mod postpass;
pub mod reducer;
pub mod segmentation;
pub mod state;
pub mod step_gate;
pub mod testing;

pub use clips::ClipOrchestrator;
pub use enrichment::PrivacyRedactor;
pub use reducer::{Engine, InputEvent};
pub use state::{EngineConfig, RecorderSnapshot, RecordingState};

use thiserror::Error;

/// Engine failure surface (infallible core today; kept for trait fallibility).
#[derive(Debug, Error)]
pub enum Error {
    /// Malformed `YYYY-MM-DDTHH:MM:SS[.mmm]Z` timestamp.
    #[error("bad timestamp: {0}")]
    BadTimestamp(String),
}

/// Pull-model accessibility + pixels the engine needs (`CaptureDriver` SPI,
/// sync port of `FlowlineCaptureAPI.CaptureDriver`).
pub trait CaptureDriver {
    /// Called on click/drag to build the step's target description.
    fn inspect_element(&mut self, x: f64, y: f64) -> Option<flowline_ir::RawElementContext>;
    /// Called at typing-batch finalization and for keypress/terminal context.
    fn inspect_focused(&mut self) -> Option<flowline_ir::RawElementContext>;
    /// Terminal `pwd` resolution (`TerminalContextProviding` facet).
    fn terminal_working_dir(
        &mut self,
        bundle_id: Option<&str>,
        window_title: Option<&str>,
    ) -> Option<String>;
    /// Pixel snapshots available (`CaptureCapabilities.snapshots`).
    fn snapshots_enabled(&self) -> bool {
        false
    }
    /// Micro-clips available (`CaptureCapabilities.microClips`).
    fn micro_clips_enabled(&self) -> bool {
        false
    }
    /// Still capture with click highlight; `None` skips persistence.
    fn capture_snapshot(&mut self, _x: f64, _y: f64, _step_index: i64) -> Option<Vec<u8>> {
        None
    }
}

/// Abstract session persistence (sync port of `SessionStoreProtocol`'s
/// engine-used subset: save session + media).
pub trait SessionStore {
    fn save_session(&mut self, session: &flowline_ir::StepSession);
    /// Persists media bytes, returning the session-relative path.
    fn save_media(&mut self, session_id: &str, filename: &str, bytes: &[u8]) -> String;
}

// MARK: - Injected millisecond clock

const MILLIS_PER_DAY: i64 = 86_400_000;

/// Parse `YYYY-MM-DDTHH:MM:SS[.mmm]Z` to epoch millis (Howard Hinnant's
/// `days_from_civil`; no chrono dependency).
pub fn parse_timestamp_millis(timestamp: &str) -> Result<u64, Error> {
    if timestamp.len() < 20 || !timestamp.ends_with('Z') {
        return Err(Error::BadTimestamp(timestamp.to_string()));
    }
    let num = |range: std::ops::Range<usize>| {
        timestamp
            .get(range)
            .and_then(|s| s.parse::<i64>().ok())
            .ok_or_else(|| Error::BadTimestamp(timestamp.to_string()))
    };
    if &timestamp[4..5] != "-" || &timestamp[7..8] != "-" || &timestamp[10..11] != "T" {
        return Err(Error::BadTimestamp(timestamp.to_string()));
    }
    let year = num(0..4)?;
    let month = num(5..7)?;
    let day = num(8..10)?;
    let hour = num(11..13)?;
    let minute = num(14..16)?;
    let second = num(17..19)?;
    let millis = if timestamp.len() > 21 && &timestamp[19..20] == "." {
        let frac = timestamp
            .get(20..timestamp.len() - 1)
            .and_then(|s| s.parse::<i64>().ok())
            .ok_or_else(|| Error::BadTimestamp(timestamp.to_string()))?;
        let width = (timestamp.len() - 21) as u32;
        if width > 3 {
            frac / 10_i64.pow(width - 3)
        } else {
            frac * 10_i64.pow(3 - width)
        }
    } else if timestamp.len() != 20 {
        return Err(Error::BadTimestamp(timestamp.to_string()));
    } else {
        0
    };

    let y = if month <= 2 { year - 1 } else { year };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (month + 9) % 12;
    let doy = (153 * mp + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146097 + doe - 719468;
    let total = days * MILLIS_PER_DAY + hour * 3_600_000 + minute * 60_000 + second * 1000 + millis;
    u64::try_from(total).map_err(|_| Error::BadTimestamp(timestamp.to_string()))
}

/// Format epoch millis as `YYYY-MM-DDTHH:MM:SSZ` (or `.mmmZ` when sub-second).
pub fn format_millis(millis: u64) -> String {
    let days = (millis / MILLIS_PER_DAY as u64) as i64;
    let rem = (millis % MILLIS_PER_DAY as u64) as i64;
    let z = days + 719468;
    let era = z.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = if m <= 2 { y + 1 } else { y };
    let hour = rem / 3_600_000;
    let minute = (rem % 3_600_000) / 60_000;
    let second = (rem % 60_000) / 1000;
    let ms = rem % 1000;
    if ms == 0 {
        format!("{year:04}-{m:02}-{d:02}T{hour:02}:{minute:02}:{second:02}Z")
    } else {
        format!("{year:04}-{m:02}-{d:02}T{hour:02}:{minute:02}:{second:02}.{ms:03}Z")
    }
}
