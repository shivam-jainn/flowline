//! Recording state, engine configuration, snapshots, and the two small
//! value types that gate step production (`Sources/StepItEngine/` twins:
//! `RecordingState.swift`, `RecorderWorkflowEngine.EngineConfig`,
//! `RecorderSnapshot.swift`, `EventDebouncer` from `StepItPipeline`).

use stepit_ir::{Point2D, RawGestureNotice};

/// Recording state machine states (`RecordingState.swift`, unchanged 3 cases).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecordingState {
    Idle,
    Recording,
    Paused,
}

/// Engine configuration (`RecorderWorkflowEngine.EngineConfig` + the
/// engine-owned settings defaults it folds in).
#[derive(Debug, Clone)]
pub struct EngineConfig {
    /// Minimum spacing between accepted click/action steps (Swift: 0.20).
    pub min_step_interval_secs: f64,
    /// Inactivity window that finalizes a typing batch (Swift: 1.0).
    pub typing_debounce_secs: f64,
    /// How long a gesture notice stays visible in the HUD (Swift: 2.5).
    /// Sync engine: notices are sticky until replaced; callers clear them.
    pub gesture_notice_secs: f64,
    /// Hotkey combo that toggles recording (Swift: `"⌥Space"`).
    pub toggle_hotkey_combo: String,
    /// Post-click window collected for micro-clips (Swift: 1.2).
    pub click_clip_post_secs: f64,
    /// Post-typing window collected for fast-forward clips (Swift: 0.6).
    pub typing_clip_post_secs: f64,
    /// Emit discrete `.appSwitch` steps on frontmost-app change
    /// (Swift `CaptureSettings.recordAppSwitches`, default `false`).
    pub record_app_switches: bool,
    /// Capture `⌘/⌃` chords as `.keyPress` steps
    /// (Swift `HotkeyCaptureSettings.captureModifierShortcuts`, default `true`).
    pub capture_modifier_shortcuts: bool,
    /// Capture navigation keys as `.keyPress` steps
    /// (Swift `HotkeyCaptureSettings.captureNavigationKeys`, default `true`).
    pub capture_navigation_keys: bool,
    /// Mask secure-field keystrokes with `•` instead of buffering plaintext
    /// (Swift `PrivacySettings.maskSecureInputFields`, default `true`).
    pub mask_secure_input: bool,
}

impl Default for EngineConfig {
    fn default() -> Self {
        Self {
            min_step_interval_secs: 0.20,
            typing_debounce_secs: 1.0,
            gesture_notice_secs: 2.5,
            toggle_hotkey_combo: "⌥Space".to_string(),
            click_clip_post_secs: 1.2,
            typing_clip_post_secs: 0.6,
            record_app_switches: false,
            capture_modifier_shortcuts: true,
            capture_navigation_keys: true,
            mask_secure_input: true,
        }
    }
}

impl EngineConfig {
    pub fn typing_debounce_millis(&self) -> u64 {
        (self.typing_debounce_secs * 1000.0).round() as u64
    }

    pub fn min_step_interval_millis(&self) -> u64 {
        (self.min_step_interval_secs * 1000.0).round() as u64
    }
}

/// One atomic value the controller mirrors (`RecorderSnapshot.swift`).
#[derive(Debug, Clone)]
pub struct RecorderSnapshot {
    pub state: RecordingState,
    /// Id of the live session, if any.
    pub session_id: Option<String>,
    pub step_count: usize,
    pub last_gesture_notice: Option<String>,
    pub last_gesture_event: Option<RawGestureNotice>,
}

/// Inline click guard driven by event timestamps (`EventDebouncer`).
///
/// Parity rule: a rejected event does **not** move the window forward; only
/// accepted events do. Swift uses strict `>` against `minInterval`.
#[derive(Debug, Clone)]
pub struct EventDebouncer {
    min_interval_millis: u64,
    last_accepted_millis: Option<u64>,
}

impl EventDebouncer {
    pub fn new(min_interval_millis: u64) -> Self {
        Self {
            min_interval_millis,
            last_accepted_millis: None,
        }
    }

    pub fn should_accept(&mut self, at_millis: u64) -> bool {
        match self.last_accepted_millis {
            None => {
                self.last_accepted_millis = Some(at_millis);
                true
            }
            Some(last) => {
                if at_millis.saturating_sub(last) > self.min_interval_millis {
                    self.last_accepted_millis = Some(at_millis);
                    true
                } else {
                    false
                }
            }
        }
    }

    pub fn reset(&mut self) {
        self.last_accepted_millis = None;
    }
}

/// Pending keystroke buffer (sync port of `TypingBatchAggregator`'s buffer).
///
/// Timer-driven debounce becomes gap-driven: `Engine::process_event` finalizes
/// the buffer first whenever the incoming event lands at/after
/// `last_key_millis + typing_debounce`.
#[derive(Debug, Clone, Default)]
pub struct TypingBuffer {
    text: String,
    location: Point2D,
    last_millis: u64,
    has_keys: bool,
}

impl TypingBuffer {
    pub fn push(&mut self, ch: &str, at: Point2D, now_millis: u64) {
        self.text.push_str(ch);
        self.location = at;
        self.last_millis = now_millis;
        self.has_keys = true;
    }

    pub fn pop(&mut self, at: Point2D, now_millis: u64) {
        self.text.pop();
        self.location = at;
        self.last_millis = now_millis;
    }

    pub fn touch(&mut self, at: Point2D, now_millis: u64) {
        self.location = at;
        self.last_millis = now_millis;
    }

    /// Mirrors `hasPendingText`: whitespace-only buffers do not produce steps.
    pub fn has_pending(&self) -> bool {
        self.has_keys && !self.text.trim().is_empty()
    }

    pub fn is_due(&self, now_millis: u64, debounce_millis: u64) -> bool {
        self.has_keys && now_millis.saturating_sub(self.last_millis) >= debounce_millis
    }

    pub fn take(&mut self) -> Option<(String, Point2D, u64)> {
        if !self.has_pending() {
            self.clear();
            return None;
        }
        let text = std::mem::take(&mut self.text);
        let out = (text, self.location, self.last_millis);
        self.clear();
        Some(out)
    }

    pub fn clear(&mut self) {
        self.text.clear();
        self.location = Point2D::ZERO;
        self.last_millis = 0;
        self.has_keys = false;
    }
}
