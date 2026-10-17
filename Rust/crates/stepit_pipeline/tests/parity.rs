//! Golden parity vs `Rust/goldens/` (R/M2-02).

use stepit_pipeline::aggregate::{TypingBatchAggregator, TypingBatchResult};
use stepit_pipeline::classify::{InputClassification, classify_parts};
use stepit_pipeline::debounce::EventDebouncer;
use stepit_pipeline::hotkey::{HotkeyDecision, HotkeyRecognizer};
use stepit_ir::{
    ActionType, HotkeyChord, KeyModifiers, MediaAssets, Point2D, RawElementContext,
};
use stepit_pipeline::redact::SensitiveDataDetector;
use stepit_pipeline::step_factory;

fn ctx(app: &str, bundle: Option<&str>, window: &str) -> RawElementContext {
    RawElementContext {
        app_name: app.to_string(),
        bundle_identifier: bundle.map(str::to_string),
        window_title: window.to_string(),
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

#[test]
fn debounce_replay_matches_golden() {
    let raw = parity_harness::load_golden("debounce.sequence.json");
    let v: serde_json::Value = serde_json::from_str(&raw).expect("golden json");
    let offsets: Vec<f64> = v["offsets"]
        .as_array()
        .expect("offsets")
        .iter()
        .map(|x| x.as_f64().expect("f64"))
        .collect();
    let expected: Vec<bool> = v["accepted"]
        .as_array()
        .expect("accepted")
        .iter()
        .map(|x| x.as_bool().expect("bool"))
        .collect();
    let mut debouncer = EventDebouncer::new(0.20);
    let got: Vec<bool> = offsets.iter().map(|o| debouncer.should_accept(*o)).collect();
    assert_eq!(got, expected, "debounce replay from t=0");
}

#[test]
fn classify_labels_match_golden() {
    let raw = parity_harness::load_golden("classify.cases.json");
    let cases: Vec<serde_json::Value> = serde_json::from_str(&raw).expect("golden json");
    assert!(!cases.is_empty());
    for case in &cases {
        let text = case["text"].as_str().expect("text");
        let app = case["appName"].as_str().expect("appName");
        let window = case["windowTitle"].as_str().expect("windowTitle");
        let label = case["label"].as_str().expect("label");
        assert_eq!(classify_parts(text, app, None, window).label(), label);
    }
}

#[test]
fn step_factory_outputs_match_golden() {
    let t0 = "2026-03-01T10:00:00Z";
    let t1 = "2026-03-01T10:00:01Z";
    let t2 = "2026-03-01T10:00:02Z";

    // 1. click
    let mut click_ctx = ctx("Safari", Some("com.apple.Safari"), "Docs — Safari");
    click_ctx.role = Some("AXButton".to_string());
    click_ctx.title = Some("Save".to_string());
    let click = step_factory::make_click_step(
        1,
        "C1BECF47-9DC2-4D06-A159-A90EDAEE3DB4",
        t0,
        ActionType::Click,
        Point2D::new(100.0, 200.0),
        Some(&click_ctx),
        MediaAssets::default(),
        None,
    );

    // 2. terminal typing with pwd
    let term_ctx = ctx("Terminal", Some("com.apple.Terminal"), "zsh");
    let typing_result = TypingBatchResult {
        text_blob: "git status".to_string(),
        context: Some(term_ctx),
        classification: InputClassification::Terminal,
        location: Point2D::new(50.0, 50.0),
    };
    let typing = step_factory::make_typing_step(
        2,
        "F4CD6E4C-5AF6-4D5A-B5A3-1604F96B7569",
        t1,
        &typing_result,
        MediaAssets::default(),
        Some("~/Code"),
        None,
    );

    // 3. ⌘S key press
    let chord = HotkeyChord::new("s".to_string(), None, None, KeyModifiers::COMMAND);
    let key = step_factory::make_key_press_step(
        3,
        "98573AF4-4DD0-4008-A620-05C3D2156A0E",
        t1,
        &chord,
        Some(&click_ctx),
        MediaAssets::default(),
        None,
    );

    // 4. drag
    let drag = step_factory::make_drag_step(
        4,
        "F58DA1A7-FCDB-467A-A4DE-D8AFF78A7C43",
        t2,
        Point2D::new(10.0, 10.0),
        Point2D::new(60.0, 40.0),
        Some(&click_ctx),
        MediaAssets::default(),
        None,
    );

    // 5. app switch
    let switch = step_factory::make_app_switch_step(
        5,
        "33B2AEF0-AAF7-4FD2-9743-A0E4BEDB3E98",
        t2,
        Some("com.apple.Terminal"),
        "Terminal",
        "zsh",
    );

    // 6. direct terminal command
    let term_cmd_ctx = ctx("Terminal", Some("com.apple.Safari"), "Docs — Safari");
    let term_cmd = step_factory::make_terminal_command_step(
        6,
        "2754B321-0D62-448A-9904-7480998EBCA2",
        t2,
        "git status",
        Some("~/Code"),
        Some(&term_cmd_ctx),
        MediaAssets::default(),
        None,
    );

    // 7. manual
    let manual = step_factory::make_manual_step(
        7,
        "C3750D3B-10B7-4565-A3C7-05B8E4FA062A",
        t2,
        "Verify",
        Some("check it"),
    );

    let steps = vec![click, typing, key, drag, switch, term_cmd, manual];
    parity_harness::assert_value_parity(&steps, "steps.factory.json");
}

#[test]
fn redaction_kinds_match_golden() {
    let raw = parity_harness::load_golden("redaction.matches.json");
    let cases: Vec<serde_json::Value> = serde_json::from_str(&raw).expect("golden json");
    assert!(!cases.is_empty());
    let detector = SensitiveDataDetector::default();
    for case in &cases {
        let text = case["text"].as_str().expect("text");
        let expected: Vec<&str> = case["kinds"]
            .as_array()
            .expect("kinds")
            .iter()
            .map(|k| k.as_str().expect("kind"))
            .collect();
        let mut got: Vec<&str> = detector
            .matches(text)
            .iter()
            .map(|m| m.kind.swift_name())
            .collect();
        got.sort_unstable();
        assert_eq!(got, expected, "kinds for {text:?}");
    }
}

#[test]
fn aggregator_end_to_end_smoke() {
    // Typing → timeout cut → return, mirroring the Swift callback tests.
    let c = ctx("Ghostty", Some("com.mitchellh.ghostty"), "ghostty");
    let mut agg = TypingBatchAggregator::new(50);
    for ch in "git sta".chars() {
        agg.append(&ch.to_string(), Point2D::ZERO, &c, 0);
    }
    for ch in "tus".chars() {
        agg.append(&ch.to_string(), Point2D::ZERO, &c, 1);
    }
    let cut = agg.poll_timeout(100).expect("timeout batch");
    assert_eq!(cut.text_blob, "git status");
    assert_eq!(cut.classification, InputClassification::Terminal);
}

#[test]
fn hotkey_toggle_smoke() {
    let rec = HotkeyRecognizer::default();
    assert_eq!(
        rec.evaluate(" ", Some(49), KeyModifiers::OPTION),
        HotkeyDecision::ToggleRecording { combo: "⌥Space".to_string() }
    );
    assert_eq!(
        rec.evaluate("s", Some(1), KeyModifiers::COMMAND),
        HotkeyDecision::WorkflowShortcut(HotkeyChord::new("s".to_string(), None, Some(1), KeyModifiers::COMMAND))
    );
}
