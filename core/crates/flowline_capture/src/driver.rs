//! Capture-driver service provider interface (sync port of Swift
//! `Sources/FlowlineCaptureAPI/CaptureDriver.swift`, `OCRScanning.swift`,
//! and `TerminalInspector.swift`).
//!
//! The Swift engine consumes these protocols through `async` methods and an
//! `AsyncStream<RawInputEvent>` push channel. This crate is runtime-free
//! (`no tokio`, no I/O, no AppKit/AX/ScreenCaptureKit), so every seam is a
//! synchronous trait instead:
//!
//! - `async` methods become plain `&mut self` methods returning owned IR.
//!   Async hosts run the blocking work on their own executor and bridge the
//!   results (e.g. wrap `poll_event` in a task that feeds their channel).
//! - The push-model `eventStream` becomes [`InputEventSource::poll_event`],
//!   a pull-model drain: hosts buffer platform callbacks and the engine
//!   drains them once per pump. Tests push fixtures directly.
//! - `pid_t` stays the portable `Option<i32>` (mirrors the Swift SPI note).
//!
//! Bridge note (`flowline_engine`): the engine's `CaptureDriver` trait is the
//! sync subset it actually calls (`inspect_element` / `inspect_focused` /
//! `terminal_working_dir` / `snapshots_enabled` / `micro_clips_enabled` /
//! `capture_snapshot`). A host adapts the traits below onto it; nothing here
//! depends on the engine crate.

use serde::{Deserialize, Serialize};
use thiserror::Error;

use flowline_ir::{
    ClipAsset, ClipBufferConfig, ElementRect, FrameSnapshot, OcrTextItem, Point2D,
    RawElementContext, RawInputEvent, RedactionOutcome,
};

use crate::settings::{CaptureMode, GestureSettings, HotkeyCaptureSettings, PrivacySettings};

// MARK: - Capabilities

/// Feature flags the engine queries to degrade gracefully (port of Swift
/// `CaptureCapabilities`).
///
/// JSON keys match Swift exactly (`snapshots`, `microClips`,
/// `accessibilityTree`, `secureFieldDetection`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CaptureCapabilities {
    pub snapshots: bool,
    pub micro_clips: bool,
    pub accessibility_tree: bool,
    pub secure_field_detection: bool,
}

impl CaptureCapabilities {
    /// Full macOS-native driver (mirrors Swift `.macNative`).
    pub fn mac_native() -> Self {
        Self {
            snapshots: true,
            micro_clips: true,
            accessibility_tree: true,
            secure_field_detection: true,
        }
    }

    /// Deterministic headless driver (mirrors Swift `.mockFull`).
    pub fn mock_full() -> Self {
        Self::mac_native()
    }

    /// No capabilities (safe default for unknown/future drivers).
    pub fn none() -> Self {
        Self {
            snapshots: false,
            micro_clips: false,
            accessibility_tree: false,
            secure_field_detection: false,
        }
    }
}

impl Default for CaptureCapabilities {
    fn default() -> Self {
        Self::none()
    }
}

// MARK: - Errors + permissions

/// Maps to the platform permission checks without leaking AX constants into
/// core (port of Swift `PermissionKind`: `accessibility`,
/// `screenRecording`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum PermissionKind {
    Accessibility,
    ScreenRecording,
}

/// Typed failure surface (port of Swift `CaptureDriverError`).
#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum CaptureDriverError {
    /// A required OS permission is missing.
    #[error("permission denied: {0:?}")]
    PermissionDenied(PermissionKind),
    /// Lifecycle misuse (e.g. capture before `start`).
    #[error("driver not running")]
    NotRunning,
    /// Platform capture failure with details.
    #[error("capture failed: {0}")]
    CaptureFailed(String),
    /// Operation the driver does not implement.
    #[error("unsupported: {0}")]
    Unsupported(String),
}

// MARK: - Core driver traits

/// Everything that *produces* input events plus its lifecycle.
///
/// Sync port of Swift `InputEventSource`. The Swift `eventStream`
/// (`AsyncStream<RawInputEvent>`, single consumer = the engine) is replaced
/// by [`InputEventSource::poll_event`]: async hosts buffer platform callbacks
/// and expose them here; the engine drains once per pump.
pub trait InputEventSource {
    /// `"macos-native"` / `"mock"` / `"windows"` — telemetry and selection.
    fn platform_identifier(&self) -> &str;

    /// Feature flags the engine uses to degrade gracefully.
    fn capabilities(&self) -> CaptureCapabilities;

    /// Boots platform hooks. Called once per driver lifetime (not per
    /// recording); monitors stay alive across recordings so gestures and the
    /// toggle hotkey work in every state.
    fn start(&mut self) -> Result<(), CaptureDriverError>;

    /// Driver-level hint (e.g. stop the clip ring-buffer to save CPU).
    /// Contract (mirrors Swift): must NOT stop event acquisition — the
    /// engine still needs gestures/hotkeys while paused.
    fn pause(&mut self);

    /// Undo a previous `pause()`.
    fn resume(&mut self);

    /// Tears down hooks. The engine drops the driver afterwards.
    fn stop(&mut self);

    /// Pull-model stand-in for `eventStream`. Returns the next buffered
    /// [`RawInputEvent`], or `None` when the buffer is empty. Default: no
    /// buffered events (drivers without an event source keep it).
    fn poll_event(&mut self) -> Option<RawInputEvent> {
        None
    }
}

/// Pull-model accessibility semantics (sync port of Swift `ElementInspector`).
pub trait ElementInspector {
    /// Called by the engine on click to build the step's target description.
    /// Returns `None` without AX permission (parity with today's placeholder
    /// behavior).
    fn inspect_element(&mut self, x: f64, y: f64) -> Option<RawElementContext>;

    /// Called at typing-batch finalization to classify terminal vs code vs
    /// text and label the step.
    fn inspect_focused(&mut self) -> Option<RawElementContext>;
}

/// Pull-model pixels (sync port of Swift `VisualCapture`).
pub trait VisualCapture {
    /// Ring-buffer lifecycle — must start *before* the first click so
    /// pre-click frames exist.
    fn start_clip_buffering(&mut self, config: ClipBufferConfig);
    fn stop_clip_buffering(&mut self);

    /// Still capture with click highlight; `step_index` keeps the
    /// `step_%02d` naming path intact. Returns `None` to skip persistence.
    fn capture_snapshot(
        &mut self,
        highlight_at: Option<Point2D>,
        step_index: i64,
    ) -> Option<FrameSnapshot>;

    /// Micro-clip around a point; `post_duration_secs` mirrors Swift's
    /// `postDuration: TimeInterval`. Returns `None` to skip persistence.
    fn capture_micro_clip(
        &mut self,
        around: Point2D,
        post_duration_secs: f64,
    ) -> Option<ClipAsset>;
}

/// Composition type for concrete drivers (sync port of Swift
/// `CaptureDriver: InputEventSource + ElementInspector + VisualCapture`).
///
/// Blanket-implemented: implement the three facet traits and this follows.
pub trait CaptureDriver: InputEventSource + ElementInspector + VisualCapture {}

impl<T> CaptureDriver for T where T: InputEventSource + ElementInspector + VisualCapture {}

// MARK: - Optional facets

/// Optional facet: drivers that own a gesture detector accept settings
/// updates through this (sync port of Swift `GestureSettingsSink`).
pub trait GestureSettingsSink {
    fn update_gesture_settings(&mut self, settings: GestureSettings);
}

/// Optional facet: drivers that route raw key events through a hotkey
/// recognizer accept capture-policy updates through this (sync port of
/// Swift `HotkeySettingsSink`).
pub trait HotkeySettingsSink {
    fn update_hotkey_settings(
        &mut self,
        settings: HotkeyCaptureSettings,
        toggle_combo: String,
    );
}

/// Optional facet: drivers that can frame stills + clips per-window accept
/// the window/display mode through this (sync port of Swift
/// `CaptureModeSink`).
pub trait CaptureModeSink {
    fn update_capture_mode(&mut self, mode: CaptureMode);
}

/// Optional facet: paints solid blackouts over secure-field regions in a
/// snapshot **before** it is persisted (sync port of Swift
/// `VisualObscuring`). Drivers without image processing return the input
/// unchanged (the engine fallback drops the media).
pub trait VisualObscuring {
    fn obscure_sensitive_regions(
        &mut self,
        snapshot: FrameSnapshot,
        regions: Vec<ElementRect>,
        anchor: Option<Point2D>,
    ) -> FrameSnapshot;
}

/// Optional facet: runs the offline OCR + blur pipeline over a captured
/// frame (sync port of Swift `VisualRedactionProviding`).
pub trait VisualRedactionProviding {
    fn redact_sensitive_content(
        &mut self,
        snapshot: FrameSnapshot,
        settings: PrivacySettings,
    ) -> RedactionOutcome;
}

/// Optional driver facet mirroring `GestureSettingsSink`: drivers that own a
/// terminal inspector expose it through this so the engine can enrich
/// terminal steps with `pwd` (sync port of Swift
/// `TerminalContextProviding`).
pub trait TerminalContextProviding {
    fn inspect_terminal_working_directory(
        &mut self,
        bundle_id: Option<&str>,
        pid: Option<i32>,
        window_title: Option<&str>,
    ) -> Option<String>;
}

// MARK: - OCR scanning

/// OCR seam: extracts text + normalized regions from a captured PNG.
///
/// Sync port of Swift `OCRScanning` (`scanText(in:)`). Never fails — an
/// unreadable frame simply yields no regions. Async hosts run Vision on
/// their executor and return the buffered items here.
pub trait OcrScanning {
    /// Runs offline text recognition over `png_data`.
    fn scan_text(&self, png_data: &[u8]) -> Vec<OcrTextItem>;
}

// MARK: - Terminal inspection

/// Platform-neutral terminal introspection boundary (sync port of Swift
/// `TerminalInspectorProtocol`).
///
/// `pid` is the portable `Option<i32>` (mirrors the Swift SPI note about
/// avoiding Darwin's `pid_t`).
pub trait TerminalInspector {
    /// Best-effort working directory for the terminal app described by the
    /// inputs. Returns `None` when the directory cannot be resolved.
    fn inspect_current_directory(
        &self,
        bundle_id: Option<&str>,
        pid: Option<i32>,
        window_title: Option<&str>,
    ) -> Option<String>;
}
