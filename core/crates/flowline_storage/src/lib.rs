//! `flowline_storage` — session bundle persistence (R/M2-04).
//!
//! Ports `Sources/FlowlineStorage/SessionStore.swift` (+ protocol/gateway):
//! `session.json` encoding stays byte-identical to Swift (canonical-JSON
//! parity), media files live under `media/<name>`, exports under `exports/`.
//! New in Rust (Swift has no such machinery): the append-only `events.jsonl`
//! log, the bundle [`Manifest`](schema::Manifest), and v0→v1
//! [`migration`](migrate).

pub mod migrate;
pub mod schema;
pub mod serialize;

pub use flowline_ir::{RawInputEvent, StepSession};
pub use schema::Manifest;
pub use serialize::{Error, Filesystem, MemFs, Result, SessionStore, StdFs};
