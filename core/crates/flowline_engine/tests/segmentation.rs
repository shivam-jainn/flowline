//! Focus-aware segmentation acceptance tests: flap revert, enriched
//! empty-fill, confidence thresholds + delayed-commit revision window.

use flowline_engine::enrichment::enriched;
use flowline_engine::segmentation::{
    CommitKind, PendingCommit, SegmentDecision, app_switch_key, confidence_score,
    decide_confidence, focus_cut_score,
};
use flowline_engine::state::EngineConfig;
use flowline_engine::testing::{InMemoryStore, MockDriver};
use flowline_engine::{Engine, parse_timestamp_millis};
use flowline_ir::{KeyModifiers, MediaMode, Point2D, RawElementContext, RawInputKind, ThemeName};
use flowline_engine::reducer::InputEvent;

fn ms(ts: &str) -> u64 {
    parse_timestamp_millis(ts).expect("ts")
}

const T0: &str = "2026-03-01T10:00:00Z";

fn ctx(app: &str, bundle: Option<&str>, window: &str, role: Option<&str>) -> RawElementContext {
    RawElementContext {
        app_name: app.to_string(),
        bundle_identifier: bundle.map(|s| s.to_string()),
        window_title: window.to_string(),
        role: role.map(|s| s.to_string()),
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

fn engine_safari() -> Engine<MockDriver, InMemoryStore> {
    let mut driver = MockDriver::new();
    driver.focused = Some(MockDriver::safari_focused());
    driver.element_at_point = Some(MockDriver::safari_save_button());
    let config = EngineConfig {
        record_app_switches: true,
        ..EngineConfig::default()
    };
    Engine::new(driver, InMemoryStore::new(), config)
}

fn app_switch(millis: u64, app: &str, bundle: &str, window: &str) -> InputEvent {
    InputEvent::new(
        millis,
        RawInputKind::AppSwitch {
            bundle_id: Some(bundle.to_string()),
            app_name: app.to_string(),
            window_title: window.to_string(),
        },
        None,
        None,
    )
}

#[test]
fn flap_revert_drops_bounce_switch() {
    let mut engine = engine_safari();
    let t0 = ms(T0);
    engine.start_recording("t", ThemeName::ModernMinimal, MediaMode::Hybrid, t0);
    assert_eq!(engine.snapshot().step_count, 0);

    // Baseline Safari (seeded) → Terminal CUT.
    engine.process_event(
        &app_switch(t0 + 100, "Terminal", "com.apple.Terminal", "zsh"),
        t0 + 100,
    );
    assert_eq!(engine.snapshot().step_count, 1);

    // Fast return to Safari within 800 ms with 0 middle events → revert.
    engine.process_event(
        &app_switch(t0 + 500, "Safari", "com.apple.Safari", "Docs — Safari"),
        t0 + 500,
    );
    assert_eq!(
        engine.snapshot().step_count,
        0,
        "flap A→B→A inside 800ms with <3 events must revert the B CUT"
    );
    assert!(
        engine
            .revision_log()
            .iter()
            .any(|l| l.contains("revert")),
        "revision log must record the revert"
    );
}

#[test]
fn flap_dedup_key_includes_window_not_just_app() {
    // Same app, new window must still CUT (over-join fix).
    assert_ne!(
        app_switch_key("Safari", Some("com.apple.Safari"), "Tab A"),
        app_switch_key("Safari", Some("com.apple.Safari"), "Tab B")
    );
    let mut engine = engine_safari();
    let t0 = ms(T0);
    engine.start_recording("t", ThemeName::ModernMinimal, MediaMode::Hybrid, t0);
    engine.process_event(
        &app_switch(t0 + 100, "Safari", "com.apple.Safari", "Other Tab"),
        t0 + 100,
    );
    assert_eq!(engine.snapshot().step_count, 1);
    // Identical key → dedup, no new step.
    engine.process_event(
        &app_switch(t0 + 200, "Safari", "com.apple.Safari", "Other Tab"),
        t0 + 200,
    );
    assert_eq!(engine.snapshot().step_count, 1);
}

#[test]
fn record_app_switches_false_default_produces_no_steps() {
    let mut driver = MockDriver::new();
    driver.focused = Some(MockDriver::safari_focused());
    let mut engine = Engine::new(
        driver,
        InMemoryStore::new(),
        EngineConfig::default(), // record_app_switches == false
    );
    let t0 = ms(T0);
    engine.start_recording("t", ThemeName::ModernMinimal, MediaMode::Hybrid, t0);
    engine.process_event(
        &app_switch(t0 + 100, "Terminal", "com.apple.Terminal", "zsh"),
        t0 + 100,
    );
    assert_eq!(engine.snapshot().step_count, 0);
}

#[test]
fn enriched_fills_empty_and_unknown_app_names() {
    let last = ctx("Safari", Some("com.apple.Safari"), "Docs", None);
    // Empty app name fills (Swift PrivacyEnrichment.swift:12 parity).
    let empty = ctx("", None, "", None);
    let filled = enriched(empty, Some(&last));
    assert_eq!(filled.app_name, "Safari");
    assert_eq!(
        filled.bundle_identifier.as_deref(),
        Some("com.apple.Safari")
    );
    assert_eq!(filled.window_title, "Docs");
    // "Unknown App" placeholder fills identically.
    let unknown = RawElementContext::unknown();
    let filled2 = enriched(unknown, Some(&last));
    assert_eq!(filled2.app_name, "Safari");
    // Bundle already present is never overwritten.
    let keep = ctx("", Some("com.other.App"), "", None);
    let filled3 = enriched(keep, Some(&last));
    assert_eq!(filled3.bundle_identifier.as_deref(), Some("com.other.App"));
}

#[test]
fn focus_scores_match_spec_and_gate_popup() {
    let a = ctx("Safari", Some("com.apple.Safari"), "Docs", Some("AXButton"));
    let b = ctx("Terminal", Some("com.apple.Terminal"), "zsh", Some("AXButton"));
    assert_eq!(focus_cut_score(&a, &b), 0.95);
    let w2 = ctx("Safari", Some("com.apple.Safari"), "Other", Some("AXButton"));
    assert_eq!(focus_cut_score(&a, &w2), 0.85);
    let r2 = ctx("Safari", Some("com.apple.Safari"), "Docs", Some("AXTextField"));
    assert_eq!(focus_cut_score(&a, &r2), 0.70);
    let popup = ctx("Safari", Some("com.apple.Safari"), "Docs", Some("AXMenu"));
    assert_eq!(focus_cut_score(&a, &popup), 0.0);
}

#[test]
fn confidence_thresholds_gate_cut_join_provisional() {
    let cut = confidence_score(0.95, 1.0, 0.0, 0.5, 0.2);
    assert!(cut > 0.6);
    assert_eq!(decide_confidence(cut), SegmentDecision::Cut);
    let join = confidence_score(0.0, 0.1, 0.0, 0.0, 0.2);
    assert!(join < 0.4);
    assert_eq!(decide_confidence(join), SegmentDecision::Join);
    assert_eq!(decide_confidence(0.5), SegmentDecision::Provisional);
    assert_eq!(decide_confidence(0.6), SegmentDecision::Provisional);
}

#[test]
fn delayed_commit_provisional_then_confirmed_with_log() {
    let mut c = PendingCommit::new("step-0001".into(), CommitKind::Click, 1000);
    assert_eq!(c.confirm_at_millis, 1150);
    assert!(c.extend_on_contradiction());
    assert!(c.extend_on_contradiction());
    assert!(!c.extend_on_contradiction());
    assert_eq!(c.extensions, 2);

    // Engine-level: click emits provisionally, confirms after +150 ms.
    let mut engine = engine_safari();
    let t0 = ms(T0);
    engine.start_recording("t", ThemeName::ModernMinimal, MediaMode::Hybrid, t0);
    engine.process_event(
        &InputEvent::new(
            t0,
            RawInputKind::MouseClick {
                button: flowline_ir::MouseButton::Left,
                click_count: 1,
            },
            Some(Point2D::new(100.0, 200.0)),
            None,
        ),
        t0,
    );
    assert_eq!(engine.pending_commit_count(), 1);
    assert!(
        engine
            .revision_log()
            .iter()
            .any(|l| l.contains("v1 provisional"))
    );
    // A later event past the window confirms.
    engine.process_event(
        &InputEvent::new(
            t0 + 500,
            RawInputKind::MouseClick {
                button: flowline_ir::MouseButton::Left,
                click_count: 1,
            },
            Some(Point2D::new(10.0, 10.0)),
            None,
        ),
        t0 + 500,
    );
    assert!(
        engine
            .revision_log()
            .iter()
            .any(|l| l.contains("v2 confirmed"))
    );
}

#[test]
fn terminal_return_cut_and_ctrl_c_bypass_preserved() {
    let mut engine = engine_safari();
    let t0 = ms(T0);
    engine.start_recording("t", ThemeName::ModernMinimal, MediaMode::Hybrid, t0);
    let key = |k: &str, mods: KeyModifiers, millis: u64| {
        InputEvent::new(
            millis,
            RawInputKind::KeyStroke {
                key: k.to_string(),
                code: None,
                modifiers: mods,
            },
            Some(Point2D::ZERO),
            None,
        )
    };
    engine.process_event(&key("g", KeyModifiers::EMPTY, t0), t0);
    engine.process_event(&key("i", KeyModifiers::EMPTY, t0), t0);
    // Return always CUTs the batch.
    engine.process_event(&key("Return", KeyModifiers::EMPTY, t0), t0);
    assert_eq!(engine.snapshot().step_count, 1);
    // Ctrl+C SIGINT bypass works even with typing pending.
    engine.process_event(&key("x", KeyModifiers::EMPTY, t0), t0);
    engine.process_event(
        &key(
            "c",
            KeyModifiers(KeyModifiers::CONTROL.0),
            t0,
        ),
        t0,
    );
    let session = engine.session().expect("session").clone();
    assert!(session.steps.iter().any(|s| s.text_blob.as_deref() == Some("x ^C") || s.text_blob.as_deref() == Some("^C")));
}
