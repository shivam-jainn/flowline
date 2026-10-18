//! Windows native capture driver (R/M3-01) — the second real native behind
//! `FlowlineCaptureAPI`, proving the plugin contract is portable.
//!
//! Layout mirrors the driver boundary: [`hooks`] normalizes Win32 low-level
//! hook data (`WH_MOUSE_LL` / `WH_KEYBOARD_LL`) into core IR events,
//! [`inspector`] maps UI Automation (UIA) element properties into
//! `RawElementContext`, and [`plugin`] publishes the `windows` manifest +
//! registration. No engine or core changes were needed — the driver feeds the
//! UNMODIFIED `flowline_engine` (see `tests/parity.rs` end to end).
//!
//! Verification note: the live hook pumping (`plugin::win32`, `cfg(windows)`
//! only) compiles where the Windows SDK exists; every normalization function
//! in this crate is pure, host-testable, and covered on all platforms.

pub mod hooks;
pub mod inspector;
pub mod plugin;

pub use plugin::{windows_manifest, DriverPlugin, register};
