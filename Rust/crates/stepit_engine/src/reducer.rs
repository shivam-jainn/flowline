//! Deterministic synchronous port of `RecorderWorkflowEngine`'s event
//! reduction (`EventReducer.swift` + lifecycle intents).
//!
//! The Swift actor's async serialization becomes direct sequential
//! application: `process_event` runs to completion before the next event, so
//! the step-gate ordering Swift enforces with continuations holds by
//! construction. Time is injected millis; drivers/stores are injected traits.

use crate::clips::{ClipOrchestrator, MicroClipless, StepMedia};
use crate::enrichment::{
    HotkeyDecision, InputClassification, KeystrokeClassifier, PrivacyRedactor, enriched,
    normalize_batch_context,
};
use stepit_ir::{
    ActionType, ExportPaths, GestureAction, KeyModifiers, MediaMode, Point2D, RawElementContext,
    RawGestureNotice, RawInputKind, StepSession, ThemeName,
};
use crate::state::{EngineConfig, EventDebouncer, RecorderSnapshot, RecordingState, TypingBuffer};
use crate::step_gate::ProducedStep;

/// Event with an injected millisecond clock (`RawInputEvent` + `now_millis`).
#[derive(Debug, Clone)]
pub struct InputEvent {
    pub millis: u64,
    pub kind: RawInputKind,
    pub location: Option<Point2D>,
    pub target_context: Option<RawElementContext>,
}

impl InputEvent {
    pub fn new(
        millis: u64,
        kind: RawInputKind,
        location: Option<Point2D>,
        target_context: Option<RawElementContext>,
    ) -> Self {
        Self {
            millis,
            kind,
            location,
            target_context,
        }
    }
}

/// The engine: deterministic state machine over recorded streams.
pub struct Engine<D: crate::CaptureDriver, S: crate::SessionStore> {
    pub(crate) config: EngineConfig,
    pub(crate) state: RecordingState,
    pub(crate) session: Option<StepSession>,
    pub(crate) driver: D,
    pub(crate) store: S,
    pub(crate) clip: Box<dyn ClipOrchestrator>,
    pub(crate) redactor: Box<dyn PrivacyRedactor>,
    pub(crate) recognizer: crate::enrichment::HotkeyRecognizer,
    pub(crate) debouncer: EventDebouncer,
    pub(crate) typing: TypingBuffer,
    pub(crate) last_location: Point2D,
    pub(crate) last_app: Option<RawElementContext>,
    pub(crate) next_step: i64,
    pub(crate) session_seq: u64,
    pub(crate) gesture_notice: Option<String>,
    pub(crate) gesture_event: Option<RawGestureNotice>,
    pub(crate) classifier: KeystrokeClassifier,
}

impl<D: crate::CaptureDriver, S: crate::SessionStore> Engine<D, S> {
    pub fn new(driver: D, store: S, config: EngineConfig) -> Self {
        let recognizer = crate::enrichment::HotkeyRecognizer {
            toggle_combo: config.toggle_hotkey_combo.clone(),
            ignored_combos: Vec::new(),
            capture_modifier_shortcuts: config.capture_modifier_shortcuts,
            capture_navigation_keys: config.capture_navigation_keys,
        };
        Self {
            debouncer: EventDebouncer::new(config.min_step_interval_millis()),
            recognizer,
            config,
            state: RecordingState::Idle,
            session: None,
            driver,
            store,
            clip: Box::new(MicroClipless),
            redactor: Box::new(crate::enrichment::PassThroughRedactor),
            typing: TypingBuffer::default(),
            last_location: Point2D::ZERO,
            last_app: None,
            next_step: 1,
            session_seq: 0,
            gesture_notice: None,
            gesture_event: None,
            classifier: KeystrokeClassifier,
        }
    }

    pub fn set_clip_orchestrator(&mut self, clip: Box<dyn ClipOrchestrator>) {
        self.clip = clip;
    }

    pub fn set_privacy_redactor(&mut self, redactor: Box<dyn PrivacyRedactor>) {
        self.redactor = redactor;
    }

    pub fn state(&self) -> RecordingState {
        self.state
    }

    pub fn session(&self) -> Option<&StepSession> {
        self.session.as_ref()
    }

    pub fn store(&self) -> &S {
        &self.store
    }

    pub fn store_mut(&mut self) -> &mut S {
        &mut self.store
    }

    pub fn driver_mut(&mut self) -> &mut D {
        &mut self.driver
    }

    pub fn snapshot(&self) -> RecorderSnapshot {
        RecorderSnapshot {
            state: self.state,
            session_id: self.session.as_ref().map(|s| s.id.clone()),
            step_count: self.session.as_ref().map(|s| s.steps.len()).unwrap_or(0),
            last_gesture_notice: self.gesture_notice.clone(),
            last_gesture_event: self.gesture_event.clone(),
        }
    }

    // MARK: - Recording intents

    pub fn start_recording(
        &mut self,
        title: &str,
        theme: ThemeName,
        media_mode: MediaMode,
        now_millis: u64,
    ) -> Option<StepSession> {
        if self.state != RecordingState::Idle {
            return None;
        }
        self.session_seq += 1;
        let session = StepSession {
            id: format!("sess_{:08}", self.session_seq),
            started_at: crate::format_millis(now_millis),
            ended_at: None,
            title: title.to_string(),
            summary: None,
            theme,
            media_mode,
            steps: Vec::new(),
            exports: ExportPaths::default(),
            synthesized_markdown: None,
        };
        self.session = Some(session);
        self.state = RecordingState::Recording;
        self.debouncer.reset();
        self.typing.clear();
        self.next_step = 1;
        self.last_app = self.driver.inspect_focused();
        if let Some(session) = &self.session {
            self.store.save_session(session);
        }
        self.session.clone()
    }

    pub fn pause_recording(&mut self) {
        if self.state != RecordingState::Recording {
            return;
        }
        self.state = RecordingState::Paused;
    }

    pub fn resume_recording(&mut self) {
        if self.state != RecordingState::Paused {
            return;
        }
        self.state = RecordingState::Recording;
    }

    /// Flush pending typing, stamp `endedAt`, persist. Driver monitors stay
    /// alive (fix F1) — there is nothing to stop in the sync port.
    pub fn stop_recording(&mut self, now_millis: u64) -> Option<StepSession> {
        if self.state == RecordingState::Idle {
            return None;
        }
        if self.typing.has_pending() {
            self.finalize_typing(now_millis);
        }
        if let Some(session) = self.session.as_mut() {
            session.ended_at = Some(crate::format_millis(now_millis));
            let snapshot = session.clone();
            self.store.save_session(&snapshot);
        }
        self.state = RecordingState::Idle;
        self.session.clone()
    }

    pub fn toggle_recording(&mut self, now_millis: u64) {
        match self.state {
            RecordingState::Idle => {
                self.start_recording(
                    "Workflow Recording",
                    ThemeName::ModernMinimal,
                    MediaMode::Hybrid,
                    now_millis,
                );
            }
            RecordingState::Recording | RecordingState::Paused => {
                self.stop_recording(now_millis);
            }
        }
    }

    pub fn discard_last_step(&mut self) {
        if let Some(session) = self.session.as_mut() {
            if session.steps.pop().is_some() {
                let snapshot = session.clone();
                self.store.save_session(&snapshot);
            }
        }
    }

    pub fn mark_last_step_as_checkpoint(&mut self) {
        if let Some(session) = self.session.as_mut() {
            if let Some(last) = session.steps.last_mut() {
                let mut notes = last.user_notes.clone().unwrap_or_default();
                if !notes.contains('⭐') {
                    notes = if notes.is_empty() {
                        "⭐ Key Milestone / Checkpoint".to_string()
                    } else {
                        format!("⭐ [Checkpoint] {notes}")
                    };
                }
                last.user_notes = Some(notes);
                let snapshot = session.clone();
                self.store.save_session(&snapshot);
            }
        }
    }

    pub fn add_manual_step(
        &mut self,
        title: &str,
        notes: Option<&str>,
        now_millis: u64,
    ) {
        if self.state != RecordingState::Recording {
            return;
        }
        self.produce_manual_step(title, notes, now_millis);
    }

    pub fn capture_instant_snapshot(&mut self, at: Option<Point2D>, now_millis: u64) {
        let location = at.or(self.last_location()).unwrap_or(Point2D::ZERO);
        self.produce_action(ActionType::Manual, location, now_millis);
    }

    fn last_location(&self) -> Option<Point2D> {
        Some(self.last_location)
    }

    // MARK: - Event reduction (`EventReducer.processEvent`)

    /// The reduction switch. Deterministic: callers thread `now_millis`.
    pub fn process_event(&mut self, event: &InputEvent, now_millis: u64) {
        if let Some(location) = event.location {
            self.last_location = location;
        }

        // Gap-driven typing debounce (sync stand-in for the aggregator timer):
        // an event landing at/past the inactivity window finalizes the batch
        // before the event itself is reduced.
        if self
            .typing
            .is_due(event.millis, self.config.typing_debounce_millis())
        {
            self.finalize_typing(event.millis);
        }

        match &event.kind {
            RawInputKind::MouseClick {
                button,
                click_count,
            } => {
                let action = crate::step_gate::action_type_for(*button, *click_count);
                let at = event.location.unwrap_or(self.last_location);
                self.produce_action(action, at, event.millis);
            }
            RawInputKind::KeyStroke {
                key,
                code,
                modifiers,
            } => {
                let at = event.location.or(Some(self.last_location));
                self.handle_keystroke(key, *code, *modifiers, at, event.millis);
            }
            RawInputKind::HotkeyCombo { combo } => {
                if self.matches_toggle_hotkey(combo) {
                    self.toggle_recording(now_millis);
                }
            }
            RawInputKind::MouseDrag { start, end } => {
                self.produce_drag(*start, *end, event.millis);
            }
            RawInputKind::AppSwitch {
                bundle_id,
                app_name,
                window_title,
            } => {
                self.handle_app_switch(bundle_id.clone(), app_name.clone(), window_title.clone(), now_millis);
            }
            RawInputKind::TerminalCommand {
                command,
                working_dir,
                ..
            } => {
                self.produce_terminal_command(command.clone(), working_dir.clone(), now_millis);
            }
            RawInputKind::UserGesture { name, action } => {
                let at = event.location.unwrap_or(Point2D::ZERO);
                self.handle_gesture(name.clone(), *action, at, now_millis);
            }
            RawInputKind::PageNavigation { .. } => {
                // Reserved for Phase 4; ignored by the engine.
            }
        }
    }

    /// Routes an IR keystroke through the shared recognizer policy
    /// (`handleKeystroke`, verbatim order).
    fn handle_keystroke(
        &mut self,
        key: &str,
        code: Option<i64>,
        modifiers: KeyModifiers,
        at: Option<Point2D>,
        now_millis: u64,
    ) {
        let decision = self.recognizer.evaluate(key, code, modifiers);

        // The toggle must fire in every state (F1 parity with `.hotkeyCombo`).
        if let HotkeyDecision::ToggleRecording { .. } = decision {
            self.toggle_recording(now_millis);
            return;
        }

        if self.state != RecordingState::Recording {
            return;
        }
        let location = at.unwrap_or(Point2D::ZERO);

        // ⌃C is the terminal SIGINT batch terminator (Phase 1 parity) and must
        // work even when modifier-shortcut capture is disabled.
        if modifiers.contains(KeyModifiers::CONTROL)
            && !modifiers.contains(KeyModifiers::COMMAND)
            && key.to_lowercase() == "c"
        {
            self.handle_control_c(location, now_millis);
            return;
        }

        match decision {
            HotkeyDecision::ToggleRecording { .. } => {}
            HotkeyDecision::SystemConsumed { .. } | HotkeyDecision::Ignored => {}
            HotkeyDecision::WorkflowShortcut(chord) | HotkeyDecision::NavigationKey(chord) => {
                self.produce_key_press(&chord, location, now_millis);
            }
            HotkeyDecision::TextInput { key, .. } => {
                self.handle_text_input(&key, location, now_millis);
            }
        }
    }

    /// Return / Backspace / printable characters feed the typing buffer. Named
    /// keys never reach this path (classified above), closing the pre-Phase-2
    /// hole where `"Escape"` was buffered as text.
    fn handle_text_input(&mut self, key: &str, at: Point2D, now_millis: u64) {
        match key {
            "Return" | "\r" | "\n" => {
                self.finalize_typing(now_millis);
            }
            "Backspace" | "\u{7f}" => {
                self.typing.pop(at, now_millis);
            }
            _ => {
                let mut chars = key.chars();
                let printable = match (chars.next(), chars.next()) {
                    (Some(c), None) => (c as u32) >= 32 && (c as u32) != 127,
                    _ => false,
                };
                if !printable {
                    return;
                }
                // Per-keystroke secure probe (T6): raw characters never enter
                // the buffer for secure fields — only masks (or nothing) do.
                let secure = self.driver.inspect_focused().map(|c| c.is_secure).unwrap_or(false);
                if secure {
                    if self.config.mask_secure_input {
                        let mask: String = key.chars().map(|_| '•').collect();
                        self.typing.push(&mask, at, now_millis);
                    } else {
                        self.typing.touch(at, now_millis);
                    }
                } else {
                    self.typing.push(key, at, now_millis);
                }
            }
        }
    }

    /// Control+C appends the `^C` marker and finalizes immediately.
    fn handle_control_c(&mut self, at: Point2D, now_millis: u64) {
        if self.typing.has_pending() {
            if let Some((text, loc, _)) = self.typing.take() {
                let marked = format!("{text} ^C");
                self.produce_typing(&marked, loc, now_millis);
                return;
            }
        }
        self.typing.clear();
        self.produce_typing("^C", at, now_millis);
    }

    fn handle_app_switch(
        &mut self,
        bundle_id: Option<String>,
        app_name: String,
        window_title: String,
        now_millis: u64,
    ) {
        let previous = self.last_app.clone();
        self.last_app = Some(RawElementContext {
            app_name: app_name.clone(),
            bundle_identifier: bundle_id.clone(),
            window_title: window_title.clone(),
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
        });

        if self.state != RecordingState::Recording || !self.config.record_app_switches {
            return;
        }
        if previous.as_ref().map(|p| p.app_name.as_str()) == Some(app_name.as_str()) {
            return;
        }
        self.produce_app_switch(bundle_id, &app_name, &window_title, now_millis);
    }

    // MARK: - Gestures (`GestureNotices.swift`)

    fn handle_gesture(
        &mut self,
        name: String,
        action: GestureAction,
        location: Point2D,
        now_millis: u64,
    ) {
        // Presentation layers see every gesture; recording actions only fire
        // while a recording is active.
        let event = RawGestureNotice {
            name: name.clone(),
            action,
            location,
            timestamp: crate::format_millis(now_millis),
        };
        self.gesture_event = Some(event.clone());
        if self.state == RecordingState::Idle {
            return;
        }

        match action {
            GestureAction::None => {}
            GestureAction::PauseResume => {
                if self.state == RecordingState::Recording {
                    self.pause_recording();
                    self.show_gesture_notice(format!("⏸️ {name} → Paused"), event);
                } else if self.state == RecordingState::Paused {
                    self.resume_recording();
                    self.show_gesture_notice(format!("▶️ {name} → Resumed"), event);
                }
            }
            GestureAction::StopAndReview => {
                self.show_gesture_notice(format!("🛑 {name} → Stopping & Reviewing"), event);
                self.stop_recording(now_millis);
            }
            GestureAction::DiscardLastStep => {
                self.discard_last_step();
                self.show_gesture_notice(format!("🗑️ {name} → Undone Last Step"), event);
            }
            GestureAction::AddCheckpoint => {
                self.mark_last_step_as_checkpoint();
                self.show_gesture_notice(format!("⭐ {name} → Marked Checkpoint"), event);
            }
            GestureAction::CaptureSnapshot => {
                self.capture_instant_snapshot(Some(location), now_millis);
                self.show_gesture_notice(format!("📸 {name} → Captured Snapshot"), event);
            }
        }
    }

    fn show_gesture_notice(&mut self, message: String, event: RawGestureNotice) {
        self.gesture_notice = Some(message);
        self.gesture_event = Some(event);
        // Sync port: notices are sticky (no Task.sleep dismissal); the next
        // notice replaces them. `gesture_notice_secs` documents the HUD span.
    }

    // MARK: - Typing finalization

    /// Flush-then-produce used before every competing step kind (order
    /// guarantee: pending text precedes the action/keypress/drag/command).
    pub(crate) fn flush_typing_before_step(&mut self, now_millis: u64) {
        if self.typing.has_pending() {
            self.finalize_typing(now_millis);
        }
    }

    fn finalize_typing(&mut self, now_millis: u64) {
        let Some((text, location, _)) = self.typing.take() else {
            return;
        };
        self.produce_typing(&text, location, now_millis);
    }

    pub(crate) fn produce_typing(&mut self, text: &str, location: Point2D, now_millis: u64) {
        if self.state != RecordingState::Recording {
            return;
        }
        // Resolve context + classification exactly like the aggregator's
        // `makeResult` (fallbacks before the terminal/code predicates).
        let raw = self.driver.inspect_focused().unwrap_or_else(RawElementContext::unknown);
        let context = normalize_batch_context(enriched(raw, self.last_app.as_ref()));
        let classification = self.classifier.classify(text, &context);

        let mut effective = location;
        if let Some(bounds) = context.window_bounds {
            if bounds.width > 50.0 && bounds.height > 50.0 {
                effective = bounds.center();
            }
        }

        let working_directory = match classification {
            InputClassification::Terminal => self
                .driver
                .terminal_working_dir(
                    context.bundle_identifier.as_deref(),
                    Some(context.window_title.as_str()),
                ),
            _ => None,
        };
        let media = self.capture_step_media(&context, effective, self.next_step);
        let step = crate::step_gate::make_typing_step(
            self.next_id(),
            self.next_step,
            crate::format_millis(now_millis),
            text,
            &context,
            classification,
            effective,
            working_directory,
            media,
        );
        self.push_step(step, Some((effective, self.config.typing_clip_post_secs)));
    }

    // MARK: - Helpers shared with `step_gate`

    pub(crate) fn next_id(&self) -> String {
        format!("step-{:04}", self.next_step)
    }

    pub(crate) fn push_step(&mut self, step: stepit_ir::Step, clip: Option<(Point2D, f64)>) {
        let step_id = step.id.clone();
        let step_index = step.index;
        if let Some(session) = self.session.as_mut() {
            session.steps.push(step);
            let snapshot = session.clone();
            self.store.save_session(&snapshot);
        }
        self.next_step += 1;

        // Post-gate micro-clip pass (never blocks production).
        if let Some((at, post_secs)) = clip {
            let should_capture = match &self.session {
                Some(session) => {
                    session.media_mode != MediaMode::StaticOnly
                        && self.driver.micro_clips_enabled()
                }
                None => false,
            };
            if should_capture {
                let produced = ProducedStep {
                    id: step_id,
                    capture_micro_clip: true,
                };
                self.collect_micro_clip(&produced, at, post_secs, step_index);
            }
        }
    }

    pub(crate) fn capture_step_media(
        &mut self,
        context: &RawElementContext,
        at: Point2D,
        step_index: i64,
    ) -> StepMedia {
        let mut media = StepMedia::default();
        if !self.driver.snapshots_enabled() {
            return media;
        }
        let session_id = match &self.session {
            Some(s) => s.id.clone(),
            None => return media,
        };
        // Secure-field blackout + OCR blur are driver pixel ops; the sync
        // port records the redaction verdict via the injectable hook.
        let redacted = self.redactor.redact(step_index);
        media.is_redacted = redacted;
        if self
            .driver
            .capture_snapshot(at.x, at.y, step_index)
            .is_some()
        {
            let name = crate::clips::screenshot_filename(step_index);
            media.assets.screenshot = Some(self.store.save_media(&session_id, &name, &[]));
        }
        let _ = context;
        media
    }

    pub(crate) fn collect_micro_clip(
        &mut self,
        produced: &ProducedStep,
        at: Point2D,
        post_secs: f64,
        step_index: i64,
    ) {
        if !produced.capture_micro_clip {
            return;
        }
        if !self.driver.micro_clips_enabled() {
            return;
        }
        let session_id = match &self.session {
            Some(s) => s.id.clone(),
            None => return,
        };
        if let Some(clip) = self.clip.capture_micro_clip(&produced.id, at.x, at.y, post_secs) {
            if let Some(gif) = clip.gif_data {
                let name = crate::clips::gif_filename(step_index);
                let rel = self.store.save_media(&session_id, &name, &gif);
                self.patch_step_assets(&produced.id, Some(rel), None);
            }
            if let Some(video) = clip.video_data {
                let name = crate::clips::video_filename(step_index);
                let rel = self.store.save_media(&session_id, &name, &video);
                self.patch_step_assets(&produced.id, None, Some(rel));
            }
        }
    }

    pub(crate) fn patch_step_assets(
        &mut self,
        step_id: &str,
        gif: Option<String>,
        video: Option<String>,
    ) {
        if let Some(session) = self.session.as_mut() {
            if let Some(step) = session.steps.iter_mut().find(|s| s.id == step_id) {
                if gif.is_some() {
                    step.assets.gif = gif;
                }
                if video.is_some() {
                    step.assets.webm = video;
                }
            }
            let snapshot = session.clone();
            self.store.save_session(&snapshot);
        }
    }

    pub(crate) fn matches_toggle_hotkey(&self, combo: &str) -> bool {
        crate::enrichment::HotkeyRecognizer::normalize_combo(combo)
            == crate::enrichment::HotkeyRecognizer::normalize_combo(&self.recognizer.toggle_combo)
            || crate::enrichment::HotkeyRecognizer::normalize_combo(combo)
                == crate::enrichment::HotkeyRecognizer::normalize_combo(
                    &self.config.toggle_hotkey_combo,
                )
    }
}
