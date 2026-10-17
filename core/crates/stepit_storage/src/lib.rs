//! `stepit_storage` — session bundle persistence (R/M2-04).
//!
//! Ports `Sources/StepItStorage/SessionStore.swift` (+ protocol/gateway):
//! `session.json` encoding stays byte-identical to Swift (canonical-JSON
//! parity), media files live under `media/<name>`, exports under `exports/`.
//! New in Rust (Swift has no such machinery): the append-only `events.jsonl`
//! log, the bundle [`Manifest`](schema::Manifest), and v0→v1
//! [`migration`](migrate).
//!
//! NOTE: `ir` is a temporary local shim for the `stepit_ir` crate (ported in
//! parallel; absent at the time of writing). When it lands, delete `ir.rs`
//! and re-export from `stepit_ir` instead — see the module docs.

pub mod migrate;
pub mod schema;
pub mod serialize;

pub use stepit_ir::{RawInputEvent, StepSession};
pub use schema::Manifest;
pub use serialize::{Error, Filesystem, MemFs, Result, SessionStore, StdFs};
