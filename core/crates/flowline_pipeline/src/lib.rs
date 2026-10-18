//! `flowline_pipeline` — Rust port of the Swift `FlowlinePipeline` module (R/M2-02).
//!
//! Pure functions only: errors as `Result` (thiserror), time only via
//! injected `f64` seconds / `u64` millis, no clock, no RNG.
//!
use thiserror::Error;

pub mod aggregate;
pub mod classify;
pub mod coalesce;
pub mod debounce;
pub mod drag;
pub mod hotkey;
pub mod postpass;
pub mod redact;
pub mod split;
pub mod step_factory;
pub mod time;

#[derive(Debug, Error)]
pub enum Error {
    #[error("invalid input: {0}")]
    InvalidInput(&'static str),
}

pub type Result<T> = std::result::Result<T, Error>;
