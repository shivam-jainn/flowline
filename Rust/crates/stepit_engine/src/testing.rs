//! Test doubles: mock driver, in-memory store, recording clip orchestrator.
//! Mirrors `MockCaptureDriver` + the store fakes Swift tests use.

use std::collections::HashMap;

use crate::clips::{ClipOrchestrator, MicroClip};
use crate::{CaptureDriver, SessionStore};

/// Scriptable driver double. Every facet returns a canned value; every call
/// is observable for assertions.
#[derive(Debug, Clone, Default)]
pub struct MockDriver {
    pub element_at_point: Option<stepit_ir::RawElementContext>,
    pub focused: Option<stepit_ir::RawElementContext>,
    pub working_dir: Option<String>,
    pub snapshots: bool,
    pub micro_clips: bool,
    pub snapshot_bytes: Option<Vec<u8>>,
    pub inspect_element_calls: Vec<(f64, f64)>,
    pub inspect_focused_calls: usize,
    pub terminal_dir_calls: Vec<(Option<String>, Option<String>)>,
}

impl MockDriver {
    pub fn new() -> Self {
        Self::default()
    }

    /// Safari "Save" button context behind the golden click (100, 200).
    pub fn safari_save_button() -> stepit_ir::RawElementContext {
        stepit_ir::RawElementContext {
            app_name: "Safari".to_string(),
            bundle_identifier: Some("com.apple.Safari".to_string()),
            window_title: "Docs — Safari".to_string(),
            role: Some("AXButton".to_string()),
            subrole: None,
            title: Some("Save".to_string()),
            value: None,
            placeholder: None,
            role_description: None,
            is_secure: false,
            bounding_box: None,
            window_bounds: None,
            selectors: Vec::new(),
        }
    }

    /// Focused Safari window behind the golden ⌘S keypress.
    pub fn safari_focused() -> stepit_ir::RawElementContext {
        stepit_ir::RawElementContext {
            app_name: "Safari".to_string(),
            bundle_identifier: Some("com.apple.Safari".to_string()),
            window_title: "Docs — Safari".to_string(),
            role: None,
            subrole: None,
            title: None,
            value: None,
            placeholder: None,
            role_description: None,
            is_secure: false,
            bounding_box: None,
            window_bounds: None,
            selectors: Vec::new(),
        }
    }

    /// Terminal window behind the golden `git status` steps (center 50, 50).
    pub fn terminal_focused() -> stepit_ir::RawElementContext {
        stepit_ir::RawElementContext {
            app_name: "Terminal".to_string(),
            bundle_identifier: Some("com.apple.Terminal".to_string()),
            window_title: "zsh".to_string(),
            role: None,
            subrole: None,
            title: None,
            value: None,
            placeholder: None,
            role_description: None,
            is_secure: false,
            bounding_box: None,
            window_bounds: Some(stepit_ir::ElementRect::new(0.0, 0.0, 100.0, 100.0)),
            selectors: Vec::new(),
        }
    }
}

impl CaptureDriver for MockDriver {
    fn inspect_element(&mut self, x: f64, y: f64) -> Option<stepit_ir::RawElementContext> {
        self.inspect_element_calls.push((x, y));
        self.element_at_point.clone()
    }

    fn inspect_focused(&mut self) -> Option<stepit_ir::RawElementContext> {
        self.inspect_focused_calls += 1;
        self.focused.clone()
    }

    fn terminal_working_dir(
        &mut self,
        bundle_id: Option<&str>,
        window_title: Option<&str>,
    ) -> Option<String> {
        self.terminal_dir_calls.push((
            bundle_id.map(|s| s.to_string()),
            window_title.map(|s| s.to_string()),
        ));
        self.working_dir.clone()
    }

    fn snapshots_enabled(&self) -> bool {
        self.snapshots
    }

    fn micro_clips_enabled(&self) -> bool {
        self.micro_clips
    }

    fn capture_snapshot(&mut self, _x: f64, _y: f64, _step_index: i64) -> Option<Vec<u8>> {
        self.snapshot_bytes.clone()
    }
}

/// In-memory session/media store: records every save for assertions.
#[derive(Debug, Clone, Default)]
pub struct InMemoryStore {
    pub sessions: Vec<stepit_ir::StepSession>,
    pub media: HashMap<String, Vec<u8>>,
}

impl InMemoryStore {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn last_session(&self) -> Option<&stepit_ir::StepSession> {
        self.sessions.last()
    }
}

impl SessionStore for InMemoryStore {
    fn save_session(&mut self, session: &stepit_ir::StepSession) {
        self.sessions.push(session.clone());
    }

    fn save_media(&mut self, session_id: &str, filename: &str, bytes: &[u8]) -> String {
        let rel = filename.to_string();
        self.media
            .insert(format!("{session_id}/{filename}"), bytes.to_vec());
        rel
    }
}

/// Clip double: records calls, returns canned bytes.
#[derive(Debug, Clone, Default)]
pub struct RecordingClips {
    pub calls: Vec<(String, f64, f64, f64)>,
    pub gif_bytes: Option<Vec<u8>>,
    pub video_bytes: Option<Vec<u8>>,
}

impl RecordingClips {
    pub fn new() -> Self {
        Self::default()
    }
}

impl ClipOrchestrator for RecordingClips {
    fn capture_micro_clip(
        &mut self,
        step_id: &str,
        x: f64,
        y: f64,
        post_duration_secs: f64,
    ) -> Option<MicroClip> {
        self.calls
            .push((step_id.to_string(), x, y, post_duration_secs));
        if self.gif_bytes.is_none() && self.video_bytes.is_none() {
            return None;
        }
        Some(MicroClip {
            gif_data: self.gif_bytes.clone(),
            video_data: self.video_bytes.clone(),
        })
    }
}

/// Redaction double: flags the configured step indices as redacted.
#[derive(Debug, Clone, Default)]
pub struct FlagRedactor {
    pub redacted_indices: Vec<i64>,
    pub calls: Vec<i64>,
}

impl FlagRedactor {
    pub fn redact_index(index: i64) -> Self {
        Self {
            redacted_indices: vec![index],
            calls: Vec::new(),
        }
    }
}

impl crate::PrivacyRedactor for FlagRedactor {
    fn redact(&mut self, step_index: i64) -> bool {
        self.calls.push(step_index);
        self.redacted_indices.contains(&step_index)
    }
}
