//! Gated step production (`StepProductionGate.swift`).
//!
//! Swift serializes producers through the step gate because privacy passes and
//! the debounce path can interleave them on the actor. The sync port applies
//! every producer directly and sequentially, so gate order holds by
//! construction.
//!
//! Pure `StepFactory` logic (`actionType` mapping, default-description
//! synthesis, terminal-command rendering) delegates to
//! `stepit_pipeline::step_factory` (single implementation). The `make_*`
//! builders below stay engine-owned: they shape engine-domain inputs
//! (`String` ids, `i64` indexes, `StepMedia`, engine `InputClassification`)
//! at reducer call sites, while the pipeline builders shape aggregator-domain
//! inputs (`&TypingBatchResult`, `i32` indexes). Unifying the input types is
//! tracked follow-up work; no description/table logic is duplicated.

use crate::clips::StepMedia;
use crate::enrichment::{InputClassification, enriched, terminal_command_description};
use stepit_ir::{
    ActionType, HotkeyChord, MediaAssets, MouseButton, Point2D, RawElementContext,
    ScreenCoordinates, Step,
};

/// Result of a gated step production — the id lets the post-gate micro-clip
/// pass patch assets without holding the gate.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProducedStep {
    pub id: String,
    pub capture_micro_clip: bool,
}

/// Click mapping (`StepFactory.actionType(for:clickCount:)`, verbatim):
/// right → `.rightClick`, count ≥ 2 → `.doubleClick`, else `.click`.
/// Delegates to `stepit_pipeline::step_factory` (single implementation).
pub fn action_type_for(button: MouseButton, click_count: i64) -> ActionType {
    stepit_pipeline::step_factory::action_type_for(button, click_count as i32)
}

/// `Step.synthesizeDefaultDescription` (click + typing/writeCode branches,
/// verbatim — including the 40-char preview and command-prefix table).
/// Delegates to `stepit_pipeline::step_factory` (single implementation).
pub fn synthesize_default_description(
    action: ActionType,
    element_title: Option<&str>,
    element_role: Option<&str>,
    app_name: &str,
    window_title: &str,
    text_blob: Option<&str>,
    is_code: bool,
) -> String {
    stepit_pipeline::step_factory::synthesize_default_description(
        action,
        element_title,
        element_role,
        app_name,
        window_title,
        text_blob,
        is_code,
    )
}

fn redacted(is_redacted: bool) -> Option<bool> {
    if is_redacted {
        Some(true)
    } else {
        None
    }
}

/// `StepFactory.makeClickStep` (engine-called shape).
#[allow(clippy::too_many_arguments)]
pub fn make_click_step(
    id: String,
    index: i64,
    timestamp: String,
    action: ActionType,
    location: Point2D,
    context: &RawElementContext,
    assets: MediaAssets,
    is_redacted: bool,
) -> Step {
    let description = synthesize_default_description(
        action,
        context.title.as_deref(),
        context.role.as_deref(),
        &context.app_name,
        &context.window_title,
        None,
        false,
    );
    Step {
        id,
        index,
        timestamp,
        action,
        app_name: context.app_name.clone(),
        bundle_identifier: context.bundle_identifier.clone(),
        window_title: context.window_title.clone(),
        element_role: context.role.clone(),
        element_title: context.title.clone(),
        element_value: if context.is_secure { None } else { context.value.clone() },
        coordinates: Some(ScreenCoordinates::new(location.x, location.y)),
        window_bounds: context.window_bounds,
        element_bounds: context.bounding_box,
        action_description: description,
        user_notes: None,
        text_blob: None,
        is_code: false,
        code_language: None,
        assets,
        working_directory: None,
        hotkey_combo: None,
        is_redacted: redacted(is_redacted),
    }
}

/// `StepFactory.makeTypingStep` (three description branches verbatim).
#[allow(clippy::too_many_arguments)]
pub fn make_typing_step(
    id: String,
    index: i64,
    timestamp: String,
    text: &str,
    context: &RawElementContext,
    classification: InputClassification,
    location: Point2D,
    working_directory: Option<String>,
    media: StepMedia,
) -> Step {
    let clean = text.trim();
    let (action, description, role, lang_tag): (ActionType, String, &str, Option<String>) =
        match &classification {
            InputClassification::Terminal => (
                ActionType::WriteCode,
                terminal_command_description(clean, working_directory.as_deref(), &context.app_name),
                "AXTerminal",
                Some("bash".to_string()),
            ),
            InputClassification::Code { language } => (
                ActionType::WriteCode,
                format!("Write code in {}", context.app_name),
                "AXCodeEditor",
                language.clone(),
            ),
            InputClassification::Text => {
                let preview: String = clean.chars().take(32).collect();
                let ellipsis = if clean.chars().count() > 32 { "..." } else { "" };
                (
                    ActionType::Typing,
                    format!("Type \"{preview}{ellipsis}\" in {}", context.app_name),
                    "AXTextField",
                    None,
                )
            }
        };
    let is_code = action == ActionType::WriteCode;
    Step {
        id,
        index,
        timestamp,
        action,
        app_name: context.app_name.clone(),
        bundle_identifier: context.bundle_identifier.clone(),
        window_title: context.window_title.clone(),
        element_role: Some(role.to_string()),
        element_title: lang_tag.as_ref().map(|l| format!("({l})")),
        element_value: None,
        coordinates: Some(ScreenCoordinates::new(location.x, location.y)),
        window_bounds: None,
        element_bounds: None,
        action_description: description,
        user_notes: None,
        text_blob: Some(text.to_string()),
        is_code,
        code_language: lang_tag,
        assets: media.assets,
        working_directory: if classification == InputClassification::Terminal {
            working_directory
        } else {
            None
        },
        hotkey_combo: None,
        is_redacted: redacted(media.is_redacted),
    }
}

/// `StepFactory.makeTerminalCommandStep` (direct `.terminalCommand` events).
pub fn make_terminal_command_step(
    id: String,
    index: i64,
    timestamp: String,
    command: &str,
    working_directory: Option<String>,
    context: &RawElementContext,
    media: StepMedia,
) -> Step {
    let clean = command.trim();
    Step {
        id,
        index,
        timestamp,
        action: ActionType::WriteCode,
        app_name: context.app_name.clone(),
        bundle_identifier: context.bundle_identifier.clone(),
        window_title: context.window_title.clone(),
        element_role: Some("AXTerminal".to_string()),
        element_title: Some("(bash)".to_string()),
        element_value: None,
        coordinates: context.window_bounds.map(|b| {
            let c = b.center();
            ScreenCoordinates::new(c.x, c.y)
        }),
        window_bounds: None,
        element_bounds: None,
        action_description: terminal_command_description(
            clean,
            working_directory.as_deref(),
            &context.app_name,
        ),
        user_notes: None,
        text_blob: Some(command.to_string()),
        is_code: true,
        code_language: Some("bash".to_string()),
        assets: media.assets,
        working_directory,
        hotkey_combo: None,
        is_redacted: redacted(media.is_redacted),
    }
}

/// `StepFactory.makeKeyPressStep` (`⌘S` keeps its `to save` rendering).
pub fn make_key_press_step(
    id: String,
    index: i64,
    timestamp: String,
    chord: &HotkeyChord,
    context: &RawElementContext,
    media: StepMedia,
) -> Step {
    let combo = chord.combo();
    let app_name = if context.app_name.is_empty() {
        "Unknown App".to_string()
    } else {
        context.app_name.clone()
    };
    let description = if combo == "⌘S" {
        format!("Press ⌘S to save in {app_name}")
    } else {
        format!("Press {combo} in {app_name}")
    };
    Step {
        id,
        index,
        timestamp,
        action: ActionType::KeyPress,
        app_name: context.app_name.clone(),
        bundle_identifier: context.bundle_identifier.clone(),
        window_title: context.window_title.clone(),
        element_role: Some("AXKeyboard".to_string()),
        element_title: Some(chord.key.clone()),
        element_value: None,
        coordinates: context.bounding_box.map(|b| {
            let c = b.center();
            ScreenCoordinates::new(c.x, c.y)
        }),
        window_bounds: context.window_bounds,
        element_bounds: context.bounding_box,
        action_description: description,
        user_notes: None,
        text_blob: None,
        is_code: false,
        code_language: None,
        assets: media.assets,
        working_directory: None,
        hotkey_combo: if chord.is_shortcut() { Some(combo) } else { None },
        is_redacted: redacted(media.is_redacted),
    }
}

/// `StepFactory.makeDragStep`.
pub fn make_drag_step(
    id: String,
    index: i64,
    timestamp: String,
    start: Point2D,
    end: Point2D,
    context: &RawElementContext,
    media: StepMedia,
) -> Step {
    let description = format!(
        "Drag from ({}, {}) to ({}, {}) in {}",
        start.x.round() as i64,
        start.y.round() as i64,
        end.x.round() as i64,
        end.y.round() as i64,
        context.app_name
    );
    Step {
        id,
        index,
        timestamp,
        action: ActionType::MouseDrag,
        app_name: context.app_name.clone(),
        bundle_identifier: context.bundle_identifier.clone(),
        window_title: context.window_title.clone(),
        element_role: Some("AXDrag".to_string()),
        element_title: None,
        element_value: None,
        coordinates: Some(ScreenCoordinates::new(end.x, end.y)),
        window_bounds: context.window_bounds,
        element_bounds: context.bounding_box,
        action_description: description,
        user_notes: None,
        text_blob: None,
        is_code: false,
        code_language: None,
        assets: media.assets,
        working_directory: None,
        hotkey_combo: None,
        is_redacted: redacted(media.is_redacted),
    }
}

/// `StepFactory.makeAppSwitchStep`.
pub fn make_app_switch_step(
    id: String,
    index: i64,
    timestamp: String,
    bundle_id: Option<String>,
    app_name: &str,
    window_title: &str,
) -> Step {
    Step {
        id,
        index,
        timestamp,
        action: ActionType::AppSwitch,
        app_name: app_name.to_string(),
        bundle_identifier: bundle_id,
        window_title: window_title.to_string(),
        element_role: None,
        element_title: None,
        element_value: None,
        coordinates: None,
        window_bounds: None,
        element_bounds: None,
        action_description: format!("Switch to {app_name}"),
        user_notes: None,
        text_blob: None,
        is_code: false,
        code_language: None,
        assets: MediaAssets::default(),
        working_directory: None,
        hotkey_combo: None,
        is_redacted: None,
    }
}

/// `StepFactory.makeManualStep`.
pub fn make_manual_step(id: String, index: i64, timestamp: String, title: &str, notes: Option<&str>) -> Step {
    Step {
        id,
        index,
        timestamp,
        action: ActionType::Manual,
        app_name: "Manual Action".to_string(),
        bundle_identifier: None,
        window_title: String::new(),
        element_role: None,
        element_title: None,
        element_value: None,
        coordinates: None,
        window_bounds: None,
        element_bounds: None,
        action_description: title.to_string(),
        user_notes: notes.map(|n| n.to_string()),
        text_blob: None,
        is_code: false,
        code_language: None,
        assets: MediaAssets::default(),
        working_directory: None,
        hotkey_combo: None,
        is_redacted: None,
    }
}

// MARK: - Engine producers (gate bodies; sequential by construction)

impl<D: crate::CaptureDriver, S: crate::SessionStore> crate::reducer::Engine<D, S> {
    pub(crate) fn produce_action(
        &mut self,
        action: ActionType,
        at: Point2D,
        event_millis: u64,
    ) -> Option<ProducedStep> {
        // Flush any pending typed text before the subsequent action (order).
        self.flush_typing_before_step(event_millis);

        if self.state != crate::state::RecordingState::Recording {
            return None;
        }
        if !self.debouncer.should_accept(event_millis) {
            return None;
        }
        let context = self
            .driver
            .inspect_element(at.x, at.y)
            .unwrap_or_else(RawElementContext::unknown);
        let context = enriched(context, self.last_app.as_ref());
        let index = self.next_step;
        let media = self.capture_step_media(&context, at, index);
        let step = make_click_step(
            self.next_id(),
            index,
            crate::format_millis(event_millis),
            action,
            at,
            &context,
            media.assets,
            media.is_redacted,
        );
        let id = step.id.clone();
        let should_clip = self.session.as_ref().is_some_and(|s| {
            s.media_mode != stepit_ir::MediaMode::StaticOnly && self.driver.micro_clips_enabled()
        });
        self.push_step(step, None);
        let produced = ProducedStep {
            id,
            capture_micro_clip: should_clip,
        };
        if produced.capture_micro_clip {
            self.collect_micro_clip(&produced, at, self.config.click_clip_post_secs, index);
        }
        Some(produced)
    }

    pub(crate) fn produce_key_press(
        &mut self,
        chord: &HotkeyChord,
        at: Point2D,
        now_millis: u64,
    ) {
        // Ordering guarantee (T3): a pending command precedes "Press ⌘S".
        self.flush_typing_before_step(now_millis);

        if self.state != crate::state::RecordingState::Recording {
            return;
        }
        let context = self
            .driver
            .inspect_focused()
            .unwrap_or_else(RawElementContext::unknown);
        let context = enriched(context, self.last_app.as_ref());
        let index = self.next_step;
        let media = self.capture_step_media(&context, at, index);
        let step = make_key_press_step(
            self.next_id(),
            index,
            crate::format_millis(now_millis),
            chord,
            &context,
            media,
        );
        self.push_step(step, None);
    }

    pub(crate) fn produce_drag(&mut self, start: Point2D, end: Point2D, event_millis: u64) {
        self.flush_typing_before_step(event_millis);

        if self.state != crate::state::RecordingState::Recording {
            return;
        }
        let context = self
            .driver
            .inspect_element(end.x, end.y)
            .unwrap_or_else(RawElementContext::unknown);
        let context = enriched(context, self.last_app.as_ref());
        let index = self.next_step;
        let media = self.capture_step_media(&context, end, index);
        let step = make_drag_step(
            self.next_id(),
            index,
            crate::format_millis(event_millis),
            start,
            end,
            &context,
            media,
        );
        self.push_step(step, None);
    }

    pub(crate) fn produce_terminal_command(
        &mut self,
        command: String,
        working_directory: Option<String>,
        now_millis: u64,
    ) {
        self.flush_typing_before_step(now_millis);

        if self.state != crate::state::RecordingState::Recording {
            return;
        }
        let context = self
            .driver
            .inspect_focused()
            .unwrap_or_else(RawElementContext::unknown);
        let context = enriched(context, self.last_app.as_ref());
        let directory = match working_directory {
            Some(d) => Some(d),
            None => self.driver.terminal_working_dir(
                context.bundle_identifier.as_deref(),
                Some(context.window_title.as_str()),
            ),
        };
        let at = self.last_location;
        let index = self.next_step;
        let media = self.capture_step_media(&context, at, index);
        let step = make_terminal_command_step(
            self.next_id(),
            index,
            crate::format_millis(now_millis),
            &command,
            directory,
            &context,
            media,
        );
        self.push_step(step, None);
    }

    pub(crate) fn produce_app_switch(
        &mut self,
        bundle_id: Option<String>,
        app_name: &str,
        window_title: &str,
        now_millis: u64,
    ) {
        let step = make_app_switch_step(
            self.next_id(),
            self.next_step,
            crate::format_millis(now_millis),
            bundle_id,
            app_name,
            window_title,
        );
        self.push_step(step, None);
    }

    pub(crate) fn produce_manual_step(&mut self, title: &str, notes: Option<&str>, now_millis: u64) {
        let step = make_manual_step(
            self.next_id(),
            self.next_step,
            crate::format_millis(now_millis),
            title,
            notes,
        );
        self.push_step(step, None);
    }
}
