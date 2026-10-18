//! Engine parity tests (R/M2-03).
//!
//! Strategy (the two goldens cover different layers):
//! - `steps.factory.json` pins per-step *content* (`StepFactory` output with
//!   random UUIDs). The engine reproduces each entry through a scripted
//!   scenario and asserts canonical equality with only `id` normalized to the
//!   deterministic `step-NNNN` scheme (`session.sample.json` proves that
//!   scheme: `step-0001…`). Entry 6 (terminal command over a stale Safari
//!   context) is not deterministically reproducible — see the test.
//! - `session.sample.json` pins the assembled *session envelope*. The
//!   full-stream run asserts every envelope field byte-identically, with
//!   `steps` equal to exactly what the engine produced (internal consistency).
//! - Phase-2 paths present in the goldens are all exercised: hotkey combo
//!   (toggle + drop), terminal command (+ `pwd` enrichment), app-switch,
//!   drag, typing batches, gesture notices, privacy hooks, clips.

use serde_json::{Value, from_str, to_string, to_value};
use flowline_engine::enrichment::HotkeyRecognizer;
use flowline_ir::{
    ActionType, GestureAction, KeyModifiers, MediaMode, MouseButton, Point2D, RawInputEvent,
    RawInputKind, ThemeName,
};
use flowline_engine::reducer::InputEvent;
use flowline_engine::state::{EngineConfig, EventDebouncer, RecordingState};
use flowline_engine::step_gate::action_type_for;
use flowline_engine::testing::{FlagRedactor, InMemoryStore, MockDriver, RecordingClips};
use flowline_engine::{Engine, format_millis, parse_timestamp_millis};

fn ms(ts: &str) -> u64 {
    parse_timestamp_millis(ts).expect("golden timestamp")
}

const T0: &str = "2026-03-01T10:00:00Z";
const T1: &str = "2026-03-01T10:00:01Z";
const T2: &str = "2026-03-01T10:00:02Z";

fn input(event: &RawInputEvent) -> InputEvent {
    InputEvent::new(
        ms(&event.timestamp),
        event.kind.clone(),
        event.location,
        event.target_context.clone(),
    )
}

fn golden_events() -> Vec<RawInputEvent> {
    let raw = parity_harness::load_golden("events.sample.json");
    from_str(&raw).expect("golden events parse")
}

fn factory_steps() -> Vec<Value> {
    let raw = parity_harness::load_golden("steps.factory.json");
    from_str(&raw).expect("factory golden parses")
}

fn keystroke(key: &str, modifiers: KeyModifiers, at: Point2D, ts: &str) -> InputEvent {
    InputEvent::new(
        ms(ts),
        RawInputKind::KeyStroke {
            key: key.to_string(),
            code: None,
            modifiers,
        },
        Some(at),
        None,
    )
}

fn engine_with_safari_click() -> Engine<MockDriver, InMemoryStore> {
    let mut driver = MockDriver::new();
    driver.element_at_point = Some(MockDriver::safari_save_button());
    driver.focused = Some(MockDriver::safari_focused());
    Engine::new(driver, InMemoryStore::new(), EngineConfig::default())
}

/// Assert an engine-produced step equals a factory golden entry modulo the
/// deterministic `step-NNNN` id scheme.
#[track_caller]
fn assert_factory_entry(step: &impl serde::Serialize, entry_index: usize) {
    let entries = factory_steps();
    let golden = &entries[entry_index];
    let mut candidate: Value = to_value(step).expect("step serializes");
    candidate["id"] = golden["id"].clone();
    assert_eq!(
        parity_harness::canonical(&to_string(&candidate).expect("json")),
        parity_harness::canonical(&to_string(golden).expect("json")),
        "parity mismatch vs steps.factory.json entry {entry_index}",
    );
}

// MARK: - Full golden stream → session envelope

#[test]
fn full_stream_produces_golden_session_envelope() {
    let config = EngineConfig {
        record_app_switches: true,
        ..EngineConfig::default()
    };
    let mut driver = MockDriver::new();
    driver.element_at_point = Some(MockDriver::safari_save_button());
    driver.focused = Some(MockDriver::safari_focused());
    let mut engine = Engine::new(driver, InMemoryStore::new(), config);

    let events = golden_events();
    assert_eq!(events.len(), 8, "golden stream covers all Phase-2 paths");
    engine.start_recording("Golden Session", ThemeName::ModernMinimal, MediaMode::Hybrid, ms(T0));

    // Event 1: click → step-0001.
    engine.process_event(&input(&events[0]), ms(T0));
    assert_eq!(engine.snapshot().step_count, 1);

    // Event 2: keystroke buffers typing; event 3 (⌘S, non-toggle) is dropped.
    engine.process_event(&input(&events[1]), ms(T1));
    engine.process_event(&input(&events[2]), ms(T1));
    assert_eq!(engine.snapshot().step_count, 1, "non-toggle combo drops");

    // Event 4 arrives 1.0 s after the keystroke: the inactivity window
    // finalizes the buffered "a" first (Swift's debounce timer would have
    // fired here too), then shake pauses the recording.
    engine.process_event(&input(&events[3]), ms(T2));
    assert_eq!(engine.state(), RecordingState::Paused);
    assert_eq!(engine.snapshot().step_count, 2);
    assert_eq!(
        engine.snapshot().last_gesture_notice.as_deref(),
        Some("⏸️ shake → Paused")
    );

    // Events 5–7 land while paused: drag/app-switch/terminal produce nothing
    // (app-switch still tracks context), page nav is ignored.
    engine.process_event(&input(&events[4]), ms(T2));
    engine.process_event(&input(&events[5]), ms(T2));
    engine.process_event(&input(&events[6]), ms(T2));
    engine.process_event(&input(&events[7]), ms(T2));
    assert_eq!(engine.snapshot().step_count, 2);

    let session = engine.stop_recording(ms(T2)).expect("session");
    assert_eq!(session.steps.len(), 2);
    assert_eq!(session.steps[0].id, "step-0001");
    assert_eq!(session.steps[1].id, "step-0002");
    assert_factory_entry(&session.steps[0], 0);
    assert_eq!(session.steps[1].text_blob.as_deref(), Some("a"));
    assert_eq!(session.steps[1].timestamp, T2);

    // Envelope byte parity with session.sample.json; steps are exactly what
    // the engine produced (same-steps-content clause).
    let golden: Value = from_str(&parity_harness::load_golden("session.sample.json")).unwrap();
    assert_eq!(golden["id"], "sess_00000001");
    assert_eq!(session.id, "sess_00000001");
    assert_eq!(session.title, "Golden Session");
    assert_eq!(session.started_at, T0);
    assert_eq!(session.ended_at.as_deref(), Some(T2));

    let mut expected = golden.clone();
    expected["steps"] = to_value(&session.steps).unwrap();
    let candidate = to_value(&session).unwrap();
    assert_eq!(
        parity_harness::canonical(&to_string(&candidate).unwrap()),
        parity_harness::canonical(&to_string(&expected).unwrap()),
        "session envelope must match session.sample.json",
    );

    // Store saw the final session.
    let last = engine.store().last_session().expect("saved");
    assert_eq!(last.steps.len(), 2);
}

// MARK: - Factory content parity, one scripted run (indices 1–7)

/// Scripts click → typing → keypress → drag → app-switch → terminal →
/// manual in a single recording so indices/timestamps line up with
/// `steps.factory.json` entries 1–7 (entry 6 asserted as a subset — the
/// golden blends a Terminal command with a stale Safari context, which no
/// deterministic context pipeline can reproduce; see below).
#[test]
fn scripted_run_matches_factory_entries() {
    let config = EngineConfig {
        record_app_switches: true,
        ..EngineConfig::default()
    };
    let mut driver = MockDriver::new();
    driver.element_at_point = Some(MockDriver::safari_save_button());
    driver.focused = Some(MockDriver::safari_focused());
    driver.working_dir = Some("~/Code".to_string());
    let mut engine = Engine::new(driver, InMemoryStore::new(), config);
    engine.start_recording("Factory Run", ThemeName::ModernMinimal, MediaMode::Hybrid, ms(T0));

    // Entry 1: click.
    engine.process_event(
        &InputEvent::new(
            ms(T0),
            RawInputKind::MouseClick {
                button: MouseButton::Left,
                click_count: 1,
            },
            Some(Point2D::new(100.0, 200.0)),
            None,
        ),
        ms(T0),
    );

    // Entry 2: terminal typing batch ("git status" + Return).
    engine.driver_mut().focused = Some(MockDriver::terminal_focused());
    for ch in ["g", "i", "t", " ", "s", "t", "a", "t", "u", "s"] {
        engine.process_event(
            &keystroke(ch, KeyModifiers::EMPTY, Point2D::new(50.0, 50.0), T1),
            ms(T1),
        );
    }
    engine.process_event(
        &keystroke("Return", KeyModifiers::EMPTY, Point2D::new(50.0, 50.0), T1),
        ms(T1),
    );

    // Entry 3: ⌘S workflow shortcut → keypress.
    engine.driver_mut().focused = Some(MockDriver::safari_focused());
    engine.process_event(
        &InputEvent::new(
            ms(T1),
            RawInputKind::KeyStroke {
                key: "s".to_string(),
                code: None,
                modifiers: KeyModifiers(KeyModifiers::COMMAND.0),
            },
            None,
            None,
        ),
        ms(T1),
    );

    // Entry 4: drag.
    engine.process_event(
        &InputEvent::new(
            ms(T2),
            RawInputKind::MouseDrag {
                start: Point2D::new(10.0, 10.0),
                end: Point2D::new(60.0, 40.0),
            },
            None,
            None,
        ),
        ms(T2),
    );

    // Entry 5: app switch (baseline seeded from Safari at start).
    engine.process_event(
        &InputEvent::new(
            ms(T2),
            RawInputKind::AppSwitch {
                bundle_id: Some("com.apple.Terminal".to_string()),
                app_name: "Terminal".to_string(),
                window_title: "zsh".to_string(),
            },
            None,
            None,
        ),
        ms(T2),
    );

    // Entry 6: terminal command. Golden entry 6 blends `appName: Terminal`
    // + `Run … in ~/Code (Terminal)` with a *stale Safari* bundle id, window
    // title, and missing coordinates — no deterministic `enriched()` pipeline
    // produces that mix, so it is asserted as a content subset here.
    engine.driver_mut().focused = Some(MockDriver::terminal_focused());
    engine.process_event(
        &InputEvent::new(
            ms(T1),
            RawInputKind::TerminalCommand {
                command: "git status".to_string(),
                working_dir: Some("~/Code".to_string()),
                exit_code: Some(0),
            },
            None,
            None,
        ),
        ms(T1),
    );

    // Entry 7: manual step.
    engine.add_manual_step("Verify", Some("check it"), ms(T2));

    let session = engine.stop_recording(ms(T2)).expect("session");
    assert_eq!(session.steps.len(), 7);
    for (i, step) in session.steps.iter().enumerate() {
        assert_eq!(step.id, format!("step-{:04}", i + 1));
        assert_eq!(step.index, (i + 1) as i64);
    }

    assert_factory_entry(&session.steps[0], 0);
    assert_factory_entry(&session.steps[1], 1);
    assert_factory_entry(&session.steps[2], 2);
    assert_factory_entry(&session.steps[3], 3);
    assert_factory_entry(&session.steps[4], 4);
    assert_factory_entry(&session.steps[6], 6);

    let cmd = &session.steps[5];
    assert_eq!(cmd.action, ActionType::WriteCode);
    assert_eq!(cmd.text_blob.as_deref(), Some("git status"));
    assert_eq!(cmd.working_directory.as_deref(), Some("~/Code"));
    assert_eq!(
        cmd.action_description,
        "Run \"git status\" in ~/Code (Terminal)"
    );
}

// MARK: - Reduction semantics units

#[test]
fn click_debounce_drops_rapid_second_click() {
    let mut engine = engine_with_safari_click();
    engine.start_recording("t", ThemeName::ModernMinimal, MediaMode::Hybrid, ms(T0));
    let click = |millis| {
        InputEvent::new(
            millis,
            RawInputKind::MouseClick {
                button: MouseButton::Left,
                click_count: 1,
            },
            Some(Point2D::new(1.0, 1.0)),
            None,
        )
    };
    let t0 = ms(T0);
    engine.process_event(&click(t0), t0);
    // +100 ms: inside the window → dropped, window not moved.
    engine.process_event(&click(t0 + 100), t0 + 100);
    // +400 ms after the *accepted* click: outside both the legacy 200 ms
    // window and the pointer-aware stationary window (~300 ms) → accepted.
    engine.process_event(&click(t0 + 400), t0 + 400);
    assert_eq!(engine.snapshot().step_count, 2);
}

#[test]
fn os_double_click_is_accepted_not_suppressed() {
    let mut engine = engine_with_safari_click();
    engine.start_recording("t", ThemeName::ModernMinimal, MediaMode::Hybrid, ms(T0));
    let at = Some(Point2D::new(1.0, 1.0));
    let t0 = ms(T0);
    // First press surfaces as the single …
    engine.process_event(
        &InputEvent::new(
            t0,
            RawInputKind::MouseClick {
                button: MouseButton::Left,
                click_count: 1,
            },
            at,
            None,
        ),
        t0,
    );
    // … the OS-reported second press lands inside the bounce window but
    // must still surface as the double (not suppressed, not a 2nd single).
    engine.process_event(
        &InputEvent::new(
            t0 + 250,
            RawInputKind::MouseClick {
                button: MouseButton::Left,
                click_count: 2,
            },
            at,
            None,
        ),
        t0 + 250,
    );
    let session = engine.session().expect("session").clone();
    assert_eq!(session.steps.len(), 2);
    assert_eq!(
        session.steps.iter().map(|s| s.action).collect::<Vec<_>>(),
        vec![ActionType::Click, ActionType::DoubleClick]
    );
}

#[test]
fn far_fast_relocation_is_distinct_not_bounce() {
    let mut engine = engine_with_safari_click();
    engine.start_recording("t", ThemeName::ModernMinimal, MediaMode::Hybrid, ms(T0));
    let t0 = ms(T0);
    let click_at = |millis, x: f64, y: f64| {
        InputEvent::new(
            millis,
            RawInputKind::MouseClick {
                button: MouseButton::Left,
                click_count: 1,
            },
            Some(Point2D::new(x, y)),
            None,
        )
    };
    // 100 px in 100 ms: crosses the 6 px bounce radius → distinct click.
    engine.process_event(&click_at(t0, 0.0, 0.0), t0);
    engine.process_event(&click_at(t0 + 100, 100.0, 0.0), t0 + 100);
    assert_eq!(engine.snapshot().step_count, 2);
}

#[test]
fn drag_inspects_source_and_target_boundary() {
    let mut engine = engine_with_safari_click();
    engine.start_recording("t", ThemeName::ModernMinimal, MediaMode::Hybrid, ms(T0));
    let t0 = ms(T0);
    engine.process_event(
        &InputEvent::new(
            t0,
            RawInputKind::MouseDrag {
                start: Point2D::new(10.0, 10.0),
                end: Point2D::new(60.0, 40.0),
            },
            None,
            None,
        ),
        t0,
    );
    // Boundary check: both ends probed (step keeps the target context).
    assert_eq!(
        engine.driver_mut().inspect_element_calls,
        vec![(10.0, 10.0), (60.0, 40.0)]
    );
    assert_eq!(engine.snapshot().step_count, 1);
}

#[test]
fn action_type_mapping_matches_factory() {
    assert_eq!(action_type_for(MouseButton::Left, 1), ActionType::Click);
    assert_eq!(action_type_for(MouseButton::Left, 2), ActionType::DoubleClick);
    assert_eq!(action_type_for(MouseButton::Left, 5), ActionType::DoubleClick);
    assert_eq!(action_type_for(MouseButton::Right, 1), ActionType::RightClick);
    // Debouncer parity: exactly at the window edge is still rejected.
    let mut d = EventDebouncer::new(200);
    assert!(d.should_accept(1_000));
    assert!(!d.should_accept(1_200));
    assert!(d.should_accept(1_201));
}

#[test]
fn toggle_combo_fires_in_every_state_others_drop() {
    let mut engine = engine_with_safari_click();
    // Idle + toggle → starts.
    engine.process_event(
        &InputEvent::new(
            ms(T0),
            RawInputKind::HotkeyCombo {
                combo: "⌥Space".to_string(),
            },
            None,
            None,
        ),
        ms(T0),
    );
    assert_eq!(engine.state(), RecordingState::Recording);
    // Non-toggle combo while recording → dropped, no step.
    engine.process_event(
        &InputEvent::new(
            ms(T1),
            RawInputKind::HotkeyCombo {
                combo: "⌘S".to_string(),
            },
            None,
            None,
        ),
        ms(T1),
    );
    assert_eq!(engine.snapshot().step_count, 0);
    // Whitespace-insensitive toggle → stops.
    engine.process_event(
        &InputEvent::new(
            ms(T2),
            RawInputKind::HotkeyCombo {
                combo: "⌥ Space".to_string(),
            },
            None,
            None,
        ),
        ms(T2),
    );
    assert_eq!(engine.state(), RecordingState::Idle);
    // Keystroke toggle path agrees (HotkeySettings default is "⌥ Space").
    assert!(
        HotkeyRecognizer::normalize_combo("⌥ Space")
            == HotkeyRecognizer::normalize_combo("⌥Space")
    );
}

#[test]
fn system_combos_never_become_steps() {
    let mut engine = engine_with_safari_click();
    engine.start_recording("t", ThemeName::ModernMinimal, MediaMode::Hybrid, ms(T0));
    // ⌘Tab is system-consumed.
    engine.process_event(
        &InputEvent::new(
            ms(T1),
            RawInputKind::KeyStroke {
                key: "Tab".to_string(),
                code: None,
                modifiers: KeyModifiers(KeyModifiers::COMMAND.0),
            },
            None,
            None,
        ),
        ms(T1),
    );
    assert_eq!(engine.snapshot().step_count, 0);
}

#[test]
fn gap_debounce_finalizes_typing_before_next_event() {
    let mut engine = engine_with_safari_click();
    engine.start_recording("t", ThemeName::ModernMinimal, MediaMode::Hybrid, ms(T0));
    let t0 = ms(T0);
    engine.process_event(&keystroke("a", KeyModifiers::EMPTY, Point2D::ZERO, T0), t0);
    engine.process_event(&keystroke("b", KeyModifiers::EMPTY, Point2D::ZERO, T0), t0);
    // Next event 1.5 s later: typing finalizes first (typing ts), then click.
    let click = InputEvent::new(
        t0 + 1500,
        RawInputKind::MouseClick {
            button: MouseButton::Left,
            click_count: 1,
        },
        Some(Point2D::new(100.0, 200.0)),
        None,
    );
    engine.process_event(&click, t0 + 1500);
    let session = engine.session().expect("session").clone();
    assert_eq!(session.steps.len(), 2);
    assert_eq!(session.steps[0].action, ActionType::Typing);
    assert_eq!(session.steps[0].text_blob.as_deref(), Some("ab"));
    assert_eq!(session.steps[1].action, ActionType::Click);
}

#[test]
fn control_c_terminates_batch_with_marker() {
    let mut engine = engine_with_safari_click();
    engine.start_recording("t", ThemeName::ModernMinimal, MediaMode::Hybrid, ms(T0));
    engine.process_event(&keystroke("g", KeyModifiers::EMPTY, Point2D::ZERO, T1), ms(T1));
    engine.process_event(&keystroke("i", KeyModifiers::EMPTY, Point2D::ZERO, T1), ms(T1));
    engine.process_event(
        &keystroke("c", KeyModifiers(KeyModifiers::CONTROL.0), Point2D::ZERO, T1),
        ms(T1),
    );
    let session = engine.session().expect("session").clone();
    assert_eq!(session.steps.len(), 1);
    assert_eq!(session.steps[0].text_blob.as_deref(), Some("gi ^C"));
    // Bare ⌃C with an empty buffer still records the marker.
    engine.process_event(
        &keystroke("C", KeyModifiers(KeyModifiers::CONTROL.0), Point2D::ZERO, T1),
        ms(T1),
    );
    let session = engine.session().expect("session").clone();
    assert_eq!(session.steps[1].text_blob.as_deref(), Some("^C"));
}

#[test]
fn stop_flushes_pending_typing() {
    let mut engine = engine_with_safari_click();
    engine.start_recording("t", ThemeName::ModernMinimal, MediaMode::Hybrid, ms(T0));
    engine.process_event(&keystroke("a", KeyModifiers::EMPTY, Point2D::ZERO, T1), ms(T1));
    let session = engine.stop_recording(ms(T2)).expect("session");
    assert_eq!(session.steps.len(), 1);
    assert_eq!(session.steps[0].text_blob.as_deref(), Some("a"));
    assert_eq!(session.ended_at.as_deref(), Some(T2));
}

#[test]
fn secure_fields_mask_plaintext() {
    let mut driver = MockDriver::new();
    let mut secure = MockDriver::safari_focused();
    secure.is_secure = true;
    driver.focused = Some(secure);
    let mut engine = Engine::new(driver, InMemoryStore::new(), EngineConfig::default());
    engine.start_recording("t", ThemeName::ModernMinimal, MediaMode::Hybrid, ms(T0));
    engine.process_event(&keystroke("p", KeyModifiers::EMPTY, Point2D::ZERO, T1), ms(T1));
    engine.process_event(&keystroke("w", KeyModifiers::EMPTY, Point2D::ZERO, T1), ms(T1));
    let session = engine.stop_recording(ms(T2)).expect("session");
    assert_eq!(session.steps.len(), 1);
    assert_eq!(session.steps[0].text_blob.as_deref(), Some("••"));
}

#[test]
fn gestures_drive_pause_resume_checkpoint_and_discard() {
    let mut engine = engine_with_safari_click();
    engine.start_recording("t", ThemeName::ModernMinimal, MediaMode::Hybrid, ms(T0));
    let gesture = |name: &str, action: GestureAction| {
        InputEvent::new(
            ms(T2),
            RawInputKind::UserGesture {
                name: name.to_string(),
                action,
            },
            Some(Point2D::new(5.0, 5.0)),
            None,
        )
    };
    engine.process_event(&gesture("shake", GestureAction::PauseResume), ms(T2));
    assert_eq!(engine.state(), RecordingState::Paused);
    engine.process_event(&gesture("shake", GestureAction::PauseResume), ms(T2));
    assert_eq!(engine.state(), RecordingState::Recording);
    assert_eq!(
        engine.snapshot().last_gesture_notice.as_deref(),
        Some("▶️ shake → Resumed")
    );

    engine.add_manual_step("Checkpoint me", None, ms(T2));
    engine.process_event(&gesture("star", GestureAction::AddCheckpoint), ms(T2));
    assert_eq!(
        engine
            .session()
            .unwrap()
            .steps
            .last()
            .unwrap()
            .user_notes
            .as_deref(),
        Some("⭐ Key Milestone / Checkpoint")
    );
    engine.process_event(&gesture("undo", GestureAction::DiscardLastStep), ms(T2));
    assert_eq!(engine.snapshot().step_count, 0);
    // Idle engines still record the notice for presentation layers.
    engine.stop_recording(ms(T2));
    engine.process_event(&gesture("shake", GestureAction::PauseResume), ms(T2));
    assert!(engine.snapshot().last_gesture_event.is_some());
}

#[test]
fn privacy_hook_flags_redacted_steps() {
    let mut driver = MockDriver::new();
    driver.element_at_point = Some(MockDriver::safari_save_button());
    driver.focused = Some(MockDriver::safari_focused());
    driver.snapshots = true;
    driver.snapshot_bytes = Some(vec![1, 2, 3]);
    let mut engine = Engine::new(driver, InMemoryStore::new(), EngineConfig::default());
    engine.set_privacy_redactor(Box::new(FlagRedactor::redact_index(1)));
    engine.start_recording("t", ThemeName::ModernMinimal, MediaMode::Hybrid, ms(T0));
    engine.process_event(
        &InputEvent::new(
            ms(T0),
            RawInputKind::MouseClick {
                button: MouseButton::Left,
                click_count: 1,
            },
            Some(Point2D::new(100.0, 200.0)),
            None,
        ),
        ms(T0),
    );
    let session = engine.session().expect("session").clone();
    assert_eq!(session.steps[0].is_redacted, Some(true));
    assert_eq!(
        session.steps[0].assets.screenshot.as_deref(),
        Some("step_01.png")
    );
    assert!(engine.store().media.contains_key("sess_00000001/step_01.png"));
}

#[test]
fn micro_clips_record_calls_and_patch_assets() {
    let mut driver = MockDriver::new();
    driver.element_at_point = Some(MockDriver::safari_save_button());
    driver.focused = Some(MockDriver::safari_focused());
    driver.micro_clips = true;
    let mut clips = RecordingClips::new();
    clips.gif_bytes = Some(vec![9, 9]);
    let mut engine = Engine::new(driver, InMemoryStore::new(), EngineConfig::default());
    engine.set_clip_orchestrator(Box::new(clips));
    engine.start_recording("t", ThemeName::ModernMinimal, MediaMode::Hybrid, ms(T0));
    engine.process_event(
        &InputEvent::new(
            ms(T0),
            RawInputKind::MouseClick {
                button: MouseButton::Left,
                click_count: 1,
            },
            Some(Point2D::new(100.0, 200.0)),
            None,
        ),
        ms(T0),
    );
    let session = engine.session().expect("session").clone();
    // Click post window is 1.2 s; gif patched by step id with legacy naming.
    assert_eq!(session.steps[0].assets.gif.as_deref(), Some("step_01.gif"));

    // Typing fast-forward window is 0.6 s.
    engine.process_event(&keystroke("a", KeyModifiers::EMPTY, Point2D::ZERO, T1), ms(T1));
    engine.process_event(&keystroke("Return", KeyModifiers::EMPTY, Point2D::ZERO, T1), ms(T1));
    let session = engine.session().expect("session").clone();
    assert_eq!(session.steps[1].assets.gif.as_deref(), Some("step_02.gif"));
}

#[test]
fn timestamp_helpers_round_trip_goldens() {
    for ts in [T0, T1, T2] {
        assert_eq!(format_millis(ms(ts)), ts);
    }
    assert_eq!(format_millis(ms(T0) + 500), "2026-03-01T10:00:00.500Z");
}

// MARK: - Smart typing segmentation (hysteresis / focus / Return / paste)

fn textarea_focused() -> flowline_ir::RawElementContext {
    flowline_ir::RawElementContext {
        app_name: "Notes".to_string(),
        bundle_identifier: None,
        window_title: "Draft".to_string(),
        role: Some("AXTextArea".to_string()),
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

fn engine_with_focused(focused: flowline_ir::RawElementContext) -> Engine<MockDriver, InMemoryStore> {
    let mut driver = MockDriver::new();
    driver.element_at_point = Some(MockDriver::safari_save_button());
    driver.focused = Some(focused);
    Engine::new(driver, InMemoryStore::new(), EngineConfig::default())
}

#[test]
fn multiline_return_joins_newline_in_engine() {
    let mut engine = engine_with_focused(textarea_focused());
    engine.start_recording("t", ThemeName::ModernMinimal, MediaMode::Hybrid, ms(T0));
    for ch in ["l", "i", "n", "e", "1"] {
        engine.process_event(&keystroke(ch, KeyModifiers::EMPTY, Point2D::ZERO, T1), ms(T1));
    }
    // Plain Return in a multiline field joins; it must not cut.
    engine.process_event(
        &keystroke("Return", KeyModifiers::EMPTY, Point2D::ZERO, T1),
        ms(T1),
    );
    for ch in ["l", "i", "n", "e", "2"] {
        engine.process_event(&keystroke(ch, KeyModifiers::EMPTY, Point2D::ZERO, T1), ms(T1));
    }
    let session = engine.stop_recording(ms(T2)).expect("session");
    assert_eq!(session.steps.len(), 1);
    assert_eq!(session.steps[0].text_blob.as_deref(), Some("line1\nline2"));
}

#[test]
fn cmd_return_cuts_even_in_multiline_engine() {
    let mut engine = engine_with_focused(textarea_focused());
    engine.start_recording("t", ThemeName::ModernMinimal, MediaMode::Hybrid, ms(T0));
    for ch in ["a", "b"] {
        engine.process_event(&keystroke(ch, KeyModifiers::EMPTY, Point2D::ZERO, T1), ms(T1));
    }
    engine.process_event(
        &keystroke("Return", KeyModifiers::COMMAND, Point2D::ZERO, T1),
        ms(T1),
    );
    let session = engine.session().expect("session").clone();
    assert_eq!(session.steps.len(), 1);
    assert_eq!(session.steps[0].text_blob.as_deref(), Some("ab"));
}

#[test]
fn focus_change_cuts_typing_in_engine() {
    let mut engine = engine_with_safari_click();
    engine.start_recording("t", ThemeName::ModernMinimal, MediaMode::Hybrid, ms(T0));
    for ch in ["a", "b"] {
        engine.process_event(&keystroke(ch, KeyModifiers::EMPTY, Point2D::ZERO, T1), ms(T1));
    }
    // Window/bundle hop before the next char forces the boundary.
    engine.driver_mut().focused = Some(MockDriver::terminal_focused());
    for ch in ["c", "d"] {
        engine.process_event(&keystroke(ch, KeyModifiers::EMPTY, Point2D::ZERO, T1), ms(T1));
    }
    let session = engine.stop_recording(ms(T2)).expect("session");
    assert_eq!(session.steps.len(), 2);
    assert_eq!(session.steps[0].text_blob.as_deref(), Some("ab"));
    assert_eq!(session.steps[1].text_blob.as_deref(), Some("cd"));
}

#[test]
fn paste_burst_stays_atomic_in_engine() {
    let mut engine = engine_with_safari_click();
    engine.start_recording("t", ThemeName::ModernMinimal, MediaMode::Hybrid, ms(T0));
    for ch in ["a", "b"] {
        engine.process_event(&keystroke(ch, KeyModifiers::EMPTY, Point2D::ZERO, T1), ms(T1));
    }
    // Menu/long-press paste with the same focus joins the pending batch.
    engine.handle_paste("XYZ", Point2D::ZERO, ms(T1), Some(99));
    let session = engine.stop_recording(ms(T2)).expect("session");
    assert_eq!(session.steps.len(), 1);
    assert_eq!(session.steps[0].text_blob.as_deref(), Some("abXYZ"));

    // A focus hop forces the boundary BEFORE the paste.
    let mut engine = engine_with_safari_click();
    engine.start_recording("t", ThemeName::ModernMinimal, MediaMode::Hybrid, ms(T0));
    for ch in ["a", "b"] {
        engine.process_event(&keystroke(ch, KeyModifiers::EMPTY, Point2D::ZERO, T1), ms(T1));
    }
    engine.driver_mut().focused = Some(MockDriver::terminal_focused());
    engine.handle_paste("XYZ", Point2D::ZERO, ms(T1), Some(100));
    let session = engine.stop_recording(ms(T2)).expect("session");
    assert_eq!(session.steps.len(), 2);
    assert_eq!(session.steps[0].text_blob.as_deref(), Some("ab"));
    assert_eq!(session.steps[1].text_blob.as_deref(), Some("XYZ"));
}

#[test]
fn cmd_v_is_consumed_not_a_keypress_in_engine() {
    let mut engine = engine_with_safari_click();
    engine.start_recording("t", ThemeName::ModernMinimal, MediaMode::Hybrid, ms(T0));
    engine.process_event(&keystroke("a", KeyModifiers::EMPTY, Point2D::ZERO, T1), ms(T1));
    // Cmd+V never becomes a "Press ⌘V" step; the burst follow-ups join it.
    engine.process_event(
        &keystroke("v", KeyModifiers::COMMAND, Point2D::ZERO, T1),
        ms(T1),
    );
    engine.process_event(&keystroke("b", KeyModifiers::EMPTY, Point2D::ZERO, T1), ms(T1));
    let session = engine.stop_recording(ms(T2)).expect("session");
    assert_eq!(session.steps.len(), 1);
    assert_eq!(session.steps[0].text_blob.as_deref(), Some("ab"));
}

#[test]
fn backspace_word_undo_coalesces_in_engine() {
    let mut engine = engine_with_safari_click();
    engine.start_recording("t", ThemeName::ModernMinimal, MediaMode::Hybrid, ms(T0));
    for ch in ["h", "i", " ", "y", "o"] {
        engine.process_event(&keystroke(ch, KeyModifiers::EMPTY, Point2D::ZERO, T1), ms(T1));
    }
    engine.process_event(
        &keystroke("Backspace", KeyModifiers::OPTION, Point2D::ZERO, T1),
        ms(T1),
    );
    let session = engine.stop_recording(ms(T2)).expect("session");
    assert_eq!(session.steps.len(), 1);
    assert_eq!(session.steps[0].text_blob.as_deref(), Some("hi"));
}

#[test]
fn ime_composing_suspends_gap_cut_in_engine() {
    let mut engine = engine_with_safari_click();
    engine.start_recording("t", ThemeName::ModernMinimal, MediaMode::Hybrid, ms(T0));
    let t0 = ms(T0);
    engine.process_event(&keystroke("a", KeyModifiers::EMPTY, Point2D::ZERO, T0), t0);
    engine.set_ime_composing(true);
    // 5 s gap would cut (high 1800) — composition holds it.
    engine.process_event(
        &keystroke("b", KeyModifiers::EMPTY, Point2D::ZERO, T1),
        t0 + 5000,
    );
    engine.set_ime_composing(false);
    let session = engine.stop_recording(ms(T2)).expect("session");
    assert_eq!(session.steps.len(), 1);
    assert_eq!(session.steps[0].text_blob.as_deref(), Some("ab"));
}
