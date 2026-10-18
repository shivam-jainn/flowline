//! Clip orchestration and snapshot/media persistence. Swift twins: the media
//! halves of `ClipOrchestrator.swift` (`captureStepMedia`, `patchAssets`) with
//! image capture itself behind the injected [`crate::CaptureDriver`] facets.
//!
//! The sync port keeps the `step_%02d.png` / `.gif` / `.mp4` naming and the
//! gate-then-clip ordering (micro-clip capture never blocks step production).

use flowline_ir::MediaAssets;

/// Micro-clip bytes captured after a step (GIF and/or video).
#[derive(Debug, Clone, PartialEq, Default)]
pub struct MicroClip {
    pub gif_data: Option<Vec<u8>>,
    pub video_data: Option<Vec<u8>>,
}

impl MicroClip {
    pub fn with_gif(data: Vec<u8>) -> Self {
        Self {
            gif_data: Some(data),
            video_data: None,
        }
    }
}

/// Micro-clip capture as an injectable trait. The test double records calls
/// (step id, point, post duration) instead of touching ScreenCaptureKit.
pub trait ClipOrchestrator {
    fn capture_micro_clip(
        &mut self,
        step_id: &str,
        x: f64,
        y: f64,
        post_duration_secs: f64,
    ) -> Option<MicroClip>;
}

/// No-op orchestrator: clips disabled (default engine wiring).
#[derive(Debug, Clone, Copy, Default)]
pub struct MicroClipless;

impl ClipOrchestrator for MicroClipless {
    fn capture_micro_clip(
        &mut self,
        _step_id: &str,
        _x: f64,
        _y: f64,
        _post_duration_secs: f64,
    ) -> Option<MicroClip> {
        None
    }
}

/// What `capture_step_media` produced for one step.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct StepMedia {
    pub assets: MediaAssets,
    pub is_redacted: bool,
}

/// Legacy media filenames (`step_%02d.png` / `.gif` / `.mp4`).
pub fn screenshot_filename(step_index: i64) -> String {
    format!("step_{step_index:02}.png")
}

pub fn original_filename(step_index: i64) -> String {
    format!("step_{step_index:02}.original.png")
}

pub fn gif_filename(step_index: i64) -> String {
    format!("step_{step_index:02}.gif")
}

pub fn video_filename(step_index: i64) -> String {
    format!("step_{step_index:02}.mp4")
}

pub fn filename_base(step_index: i64) -> String {
    format!("step_{step_index:02}")
}
