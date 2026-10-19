//! `flowline_capture` — portable capture-driver SPI (traits + pure config).
//!
//! Sync, runtime-free port of Swift `platform/macos/Sources/FlowlineCaptureAPI/`
//! (`CaptureDriver.swift`, `CaptureSettings.swift`, `GestureSettings.swift`,
//! `HotkeySettings.swift`, `DriverRegistry.swift`, `OCRScanning.swift`,
//! `TerminalInspector.swift`).
//!
//! - [`driver`]: `CaptureDriver` composition + facets (`InputEventSource`,
//!   `ElementInspector`, `VisualCapture`, settings sinks, redaction facets),
//!   `CaptureCapabilities`, `CaptureDriverError`, `PermissionKind`, and the
//!   `OcrScanning` / `TerminalInspector` seams.
//! - [`settings`]: pure `serde` config (`CaptureSettings`,
//!   `GestureSettings`, `HotkeySettings`, `HotkeyCaptureSettings`,
//!   `PrivacySettings`, `CaptureMode`) with Swift-matching JSON keys and
//!   lenient defaults.
//! - [`registry`]: type-erased [`DriverRegistry`](registry::DriverRegistry)
//!   (factory + `PluginManifest`, version-gated `resolve`).
//!
//! No AppKit/AX/ScreenCaptureKit, no `unsafe`, no I/O. Async hosts bridge
//! the sync methods onto their executor (see [`driver`] docs).

pub mod driver;
pub mod registry;
pub mod settings;

pub use driver::{
    CaptureCapabilities, CaptureDriver, CaptureDriverError, CaptureModeSink, ElementInspector,
    GestureSettingsSink, HotkeySettingsSink, InputEventSource, OcrScanning, PermissionKind,
    TerminalContextProviding, TerminalInspector, VisualCapture, VisualObscuring,
    VisualRedactionProviding,
};
pub use registry::{DriverRegistry, DEFAULT_HOST_VERSION};
pub use settings::{
    CaptureMode, CaptureSettings, GestureSensitivity, GestureSettings, HotCornerSettings,
    HotkeyCaptureSettings, HotkeySettings, PrivacySettings, RedactionBlurStyle,
};

// `ClipBufferConfig` is owned by the IR crate (Swift `CaptureArtifacts.swift`);
// re-exported here so driver hosts have a single SPI import.
pub use flowline_ir::ClipBufferConfig;
