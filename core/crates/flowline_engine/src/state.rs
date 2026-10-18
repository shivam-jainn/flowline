//! Recording state, engine configuration, snapshots, and the two small
//! value types that gate step production (`Sources/FlowlineEngine/` twins:
//! `RecordingState.swift`, `RecorderWorkflowEngine.EngineConfig`,
//! `RecorderSnapshot.swift`, `EventDebouncer` from `FlowlinePipeline`).

use flowline_ir::{Point2D, RawElementContext, RawGestureNotice};

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
///
/// [`EventDebouncer::should_accept_click`] adds pointer disambiguation:
/// the window adapts to inter-click pointer velocity
/// (`clamp(base * (1.5 - min(vel / 10, 0.8)), 80, 400)ms`), close + fast
/// repeats are bounced, and OS-reported doubles inside 500 ms are accepted
/// as the double (never suppressed, never split into two singles).
#[derive(Debug, Clone)]
pub struct EventDebouncer {
    min_interval_millis: u64,
    last_accepted_millis: Option<u64>,
    last_point: Option<Point2D>,
}

/// Distance below which a fast repeat is contact bounce, not intent.
pub const BOUNCE_RADIUS_PX: f64 = 6.0;
/// OS double-click coalescing window.
pub const DOUBLE_CLICK_WINDOW_MILLIS: u64 = 500;

/// Velocity-aware window in millis. `None` velocity (unknown previous
/// point) falls back to `base_millis` for legacy fixed-window parity.
pub fn adaptive_interval_millis(base_millis: u64, velocity_px_per_sec: Option<f64>) -> u64 {
    match velocity_px_per_sec {
        None => base_millis,
        Some(v) => {
            let v = v.max(0.0);
            let scaled = base_millis as f64 * (1.5 - (v / 10.0).min(0.8));
            scaled.clamp(80.0, 400.0).round() as u64
        }
    }
}

impl EventDebouncer {
    pub fn new(min_interval_millis: u64) -> Self {
        Self {
            min_interval_millis,
            last_accepted_millis: None,
            last_point: None,
        }
    }

    /// Legacy fixed-window gate (strict `>`). Click steps should prefer
    /// [`Self::should_accept_click`].
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

    /// Velocity-aware click gate (see struct docs). Rejected bounces hold
    /// the window: `last_accepted_millis`/`last_point` only move on accept.
    pub fn should_accept_click(
        &mut self,
        at_millis: u64,
        point: Option<Point2D>,
        os_click_count: i64,
    ) -> bool {
        let Some(last) = self.last_accepted_millis else {
            self.last_accepted_millis = Some(at_millis);
            self.last_point = point;
            return true;
        };
        // `saturating_sub` keeps out-of-order clocks from underflowing; a
        // timestamp at/before the last accepted event is never a bounce.
        if at_millis < last {
            return true;
        }
        let dt_millis = at_millis.saturating_sub(last);
        let dt_secs = dt_millis as f64 / 1000.0;
        if os_click_count >= 2 && dt_millis < DOUBLE_CLICK_WINDOW_MILLIS {
            self.last_accepted_millis = Some(at_millis);
            self.last_point = point;
            return true;
        }
        match (self.last_point, point) {
            (Some(prev), Some(cur)) => {
                let dx = cur.x - prev.x;
                let dy = cur.y - prev.y;
                let dist = (dx * dx + dy * dy).sqrt();
                let vel = if dt_secs > 0.0 {
                    flowline_pipeline::drag::pointer_velocity(dist, dt_secs)
                } else {
                    f64::INFINITY
                };
                let window = adaptive_interval_millis(self.min_interval_millis, Some(vel));
                if dist < BOUNCE_RADIUS_PX && dt_millis <= window {
                    return false;
                }
                self.last_accepted_millis = Some(at_millis);
                self.last_point = point;
                true
            }
            _ => {
                let window = adaptive_interval_millis(self.min_interval_millis, None);
                if dt_millis <= window {
                    return false;
                }
                self.last_accepted_millis = Some(at_millis);
                self.last_point = point;
                true
            }
        }
    }

    pub fn reset(&mut self) {
        self.last_accepted_millis = None;
        self.last_point = None;
    }
}

/// Pending keystroke buffer (sync port of `TypingBatchAggregator`'s buffer).
///
/// Timer-driven debounce becomes gap-driven: `Engine::process_event` finalizes
/// the buffer first whenever the incoming event lands at/after
/// `last_key_millis + typing_debounce`. Smart segmentation adds hysteresis
/// (`T_LOW` JOIN / `T_HIGH` CUT per app profile + adaptive p95), focus-cut
/// tracking, burst/IME guards, word-undo and atomic-paste entry points so the
/// sync port mirrors `TypingBatchAggregator` + `classify` without timers.
#[derive(Debug, Clone, Default)]
pub struct TypingBuffer {
    text: String,
    location: Point2D,
    last_millis: u64,
    has_keys: bool,
    focus: Option<RawElementContext>,
    iki_history: Vec<u64>,
    composing: bool,
    clipboard_hash: Option<u64>,
}

impl TypingBuffer {
    fn record_gap(&mut self, now_millis: u64) {
        let gap = now_millis.saturating_sub(self.last_millis);
        // First keystroke has no interval; skip the zero baseline.
        if self.has_keys {
            self.iki_history.push(gap);
            if self.iki_history.len() > 200 {
                let excess = self.iki_history.len() - 200;
                self.iki_history.drain(..excess);
            }
        }
    }

    pub fn push(&mut self, ch: &str, at: Point2D, now_millis: u64) {
        self.record_gap(now_millis);
        self.text.push_str(ch);
        self.location = at;
        self.last_millis = now_millis;
        self.has_keys = true;
    }

    /// Atomic-paste insert: buffers the whole payload as one unit.
    pub fn push_paste(&mut self, text: &str, at: Point2D, now_millis: u64) {
        self.record_gap(now_millis);
        self.text.push_str(text);
        self.location = at;
        self.last_millis = now_millis;
        if !text.is_empty() {
            self.has_keys = true;
        }
    }

    pub fn pop(&mut self, at: Point2D, now_millis: u64) {
        self.text.pop();
        self.location = at;
        self.last_millis = now_millis;
    }

    /// Option/Command+Backspace word-undo: drops the trailing word + spaces.
    pub fn pop_word(&mut self, at: Point2D, now_millis: u64) {
        let mut chars: Vec<char> = self.text.chars().collect();
        while chars.last().is_some_and(|c| c.is_whitespace()) {
            chars.pop();
        }
        while chars.last().is_some_and(|c| !c.is_whitespace()) {
            chars.pop();
        }
        while chars.last().is_some_and(|c| c.is_whitespace()) {
            chars.pop();
        }
        self.text = chars.into_iter().collect();
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
        if self.composing {
            return false;
        }
        self.has_keys && now_millis.saturating_sub(self.last_millis) >= debounce_millis
    }

    /// Hysteresis cut probe for typing continuations.
    pub fn should_cut(
        &self,
        now_millis: u64,
        ctx: Option<&RawElementContext>,
        corroborated: bool,
    ) -> bool {
        if self.composing || !self.has_keys {
            return false;
        }
        let gap = now_millis.saturating_sub(self.last_millis);
        if flowline_pipeline::classify::is_burst_gap(gap) {
            return false;
        }
        let (low, high) = match ctx {
            Some(c) => {
                let (bl, bh) = flowline_pipeline::classify::thresholds_for_context(c);
                flowline_pipeline::classify::adaptive_thresholds(
                    bl,
                    bh,
                    flowline_pipeline::classify::p95_iki(&self.iki_history),
                )
            }
            None => {
                let p95 = flowline_pipeline::classify::p95_iki(&self.iki_history);
                flowline_pipeline::classify::adaptive_thresholds(600, 1800, p95)
            }
        };
        flowline_pipeline::classify::should_cut_by_hysteresis(gap, low, high, corroborated)
    }

    /// Focus-cut probe: bundle/window/AX-role identity changed.
    /// Popups (`AXUnknown` + menu/popover chrome) never cut.
    pub fn focus_changed(&self, next: &RawElementContext) -> bool {
        let Some(prev) = self.focus.as_ref() else {
            return false;
        };
        if crate::segmentation::is_popup_context(next)
            || next.role.as_deref() == Some("AXUnknown")
        {
            return false;
        }
        if flowline_pipeline::classify::focus_identity_changed(Some(prev), next) {
            return true;
        }
        crate::segmentation::should_cut_on_focus(crate::segmentation::focus_cut_score(
            prev, next,
        ))
    }

    /// Focus-cut score for the confidence gate (0.0 when no baseline).
    pub fn focus_score(&self, next: &RawElementContext) -> f64 {
        let Some(prev) = self.focus.as_ref() else {
            return 0.0;
        };
        crate::segmentation::focus_cut_score(prev, next)
    }

    pub fn note_focus(&mut self, ctx: RawElementContext) {
        self.focus = Some(ctx);
    }

    pub fn clear_focus(&mut self) {
        self.focus = None;
    }

    pub fn set_composing(&mut self, composing: bool) {
        self.composing = composing;
    }

    pub fn is_composing(&self) -> bool {
        self.composing
    }

    pub fn clipboard_hash(&self) -> Option<u64> {
        self.clipboard_hash
    }

    pub fn set_clipboard_hash(&mut self, hash: Option<u64>) {
        self.clipboard_hash = hash;
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
        self.focus = None;
    }
}
