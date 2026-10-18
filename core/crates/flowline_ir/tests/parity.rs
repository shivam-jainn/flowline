//! IR parity suite (R/M2-01): Swift goldens <-> `flowline_ir` round-trips.

use parity_harness::{assert_parity, assert_value_parity, load_golden};
use flowline_ir::{
    ActionType, HotkeyChord, KeyModifiers, PluginManifest, RawInputEvent, Step,
    StepSession,
};

#[test]
fn events_round_trip_byte_identical() {
    let raw = load_golden("events.sample.json");
    let events: Vec<RawInputEvent> =
        serde_json::from_str(&raw).expect("events golden must decode");
    assert_eq!(events.len(), 8);
    assert_parity(
        &serde_json::to_string(&events).expect("serializable"),
        "events.sample.json",
    );
}

#[test]
fn events_jsonl_lines_decode() {
    let raw = load_golden("events.sample.jsonl");
    let mut count = 0;
    for line in raw.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let event: RawInputEvent =
            serde_json::from_str(line).expect("jsonl line must decode");
        // Re-encoding a single line must reproduce that line canonically.
        assert_eq!(
            parity_harness::canonical(
                &serde_json::to_string(&event).expect("serializable")
            ),
            parity_harness::canonical(line),
            "jsonl round-trip mismatch",
        );
        count += 1;
    }
    assert!(count > 0, "jsonl golden must be non-empty");
}

#[test]
fn session_round_trip_byte_identical() {
    let raw = load_golden("session.sample.json");
    let session: StepSession =
        serde_json::from_str(&raw).expect("session golden must decode");
    assert_eq!(session.steps.len(), 3);
    assert_value_parity(&session, "session.sample.json");
}

#[test]
fn manifest_round_trip_byte_identical() {
    let raw = load_golden("manifest.sample.json");
    let manifest: PluginManifest =
        serde_json::from_str(&raw).expect("manifest golden must decode");
    assert_value_parity(&manifest, "manifest.sample.json");
}

#[test]
fn synthesize_default_description_matches_goldens() {
    // steps.factory.json step 1: plain click with title + window context.
    let factory: Vec<Step> = serde_json::from_str(&load_golden("steps.factory.json"))
        .expect("factory golden must decode");
    let click = &factory[0];
    assert_eq!(
        Step::synthesize_default_description(
            click.action,
            click.element_title.as_deref(),
            click.element_role.as_deref(),
            &click.app_name,
            &click.window_title,
            click.text_blob.as_deref(),
            click.is_code,
        ),
        "Click \"Save\" in Docs — Safari",
    );
    assert_eq!(click.action_description, "Click \"Save\" in Docs — Safari");

    // session.sample.json steps 1-2 are pure-function outputs.
    let session: StepSession = serde_json::from_str(&load_golden("session.sample.json"))
        .expect("session golden must decode");
    for step in &session.steps[..2] {
        assert_eq!(
            Step::synthesize_default_description(
                step.action,
                step.element_title.as_deref(),
                step.element_role.as_deref(),
                &step.app_name,
                &step.window_title,
                step.text_blob.as_deref(),
                step.is_code,
            ),
            step.action_description,
            "step {} description must be the pure-function output",
            step.index,
        );
    }
}

#[test]
fn synthesize_default_description_branches() {
    use ActionType as A;
    // Typing / code branches.
    assert_eq!(
        Step::synthesize_default_description(
            A::Typing, None, None, "Safari", "", Some("hello world"), false
        ),
        "Type \"hello world\" in Safari",
    );
    assert_eq!(
        Step::synthesize_default_description(
            A::WriteCode, None, None, "Terminal", "", Some("git status"), true
        ),
        "Run \"git status\" in Terminal",
    );
    assert_eq!(
        Step::synthesize_default_description(A::Typing, None, None, "Terminal", "", None, false),
        "Execute command in Terminal",
    );
    assert_eq!(
        Step::synthesize_default_description(A::WriteCode, None, None, "Xcode", "", None, true),
        "Write code in Xcode",
    );
    assert_eq!(
        Step::synthesize_default_description(A::Typing, None, None, "", "", None, false),
        "Type text in editor",
    );
    // 40-char truncation.
    let long = "a".repeat(50);
    assert_eq!(
        Step::synthesize_default_description(
            A::Typing, None, None, "Safari", "", Some(&long), false
        ),
        format!("Type \"{}...\" in Safari", "a".repeat(40)),
    );
    // Notification branch.
    assert_eq!(
        Step::synthesize_default_description(
            A::Click, Some("Build done"), None, "UserNotificationCenter", "", None, false
        ),
        "Click notification \"Build done\"",
    );
    assert_eq!(
        Step::synthesize_default_description(A::Click, None, None, "NotificationCenter", "", None, false),
        "Click system notification",
    );
    // Role fallback strips AX and lowercases.
    assert_eq!(
        Step::synthesize_default_description(
            A::Click, None, Some("AXCheckBox"), "Safari", "", None, false
        ),
        "Click checkbox in Safari",
    );
    // Empty target falls back to bare action + context.
    assert_eq!(
        Step::synthesize_default_description(A::Click, None, None, "Safari", "", None, false),
        "Click in Safari",
    );
}

#[test]
fn manifest_validate_and_supports() {
    let manifest: PluginManifest = serde_json::from_str(&load_golden("manifest.sample.json"))
        .expect("manifest golden must decode");
    assert!(manifest.supports("snapshots"));
    assert!(manifest.supports("clips"));
    assert!(!manifest.supports("exports"));

    assert!(manifest.validate_host("r-m1"));
    assert!(manifest.validate_host("r-m2"));
    assert!(!manifest.validate_host("r-m0"));
    // Numeric (not lexicographic): r-m10 > r-m9.
    let newer = PluginManifest::new(
        "x".to_string(),
        "1.0.0".to_string(),
        vec![],
        "r-m9".to_string(),
    );
    assert!(newer.validate_host("r-m10"));
    assert!(!newer.validate_host("r-m8"));
}

#[test]
fn key_modifiers_bare_int_and_symbols() {
    // Golden encodes modifiers as a bare int (Swift OptionSet behavior).
    let mods: KeyModifiers =
        serde_json::from_str("9").expect("bare int must decode");
    assert!(mods.contains(KeyModifiers::COMMAND));
    assert!(mods.contains(KeyModifiers::SHIFT));
    assert!(!mods.contains(KeyModifiers::OPTION));
    assert_eq!(mods.symbol_string(), "⌘⇧");
    assert_eq!(serde_json::to_string(&mods).unwrap(), "9");

    assert_eq!(KeyModifiers::EMPTY.symbol_string(), "");
    assert_eq!(
        (KeyModifiers::COMMAND | KeyModifiers::OPTION | KeyModifiers::CONTROL | KeyModifiers::SHIFT)
            .symbol_string(),
        "⌘⌥⌃⇧",
    );
    assert_eq!(
        (KeyModifiers::COMMAND | KeyModifiers::FUNCTION).symbol_string(),
        "⌘fn",
    );
}

#[test]
fn hotkey_chord_rendering() {
    assert_eq!(
        HotkeyChord::new("s".to_string(), None, Some(1), KeyModifiers::COMMAND).combo(),
        "⌘S",
    );
    assert_eq!(
        HotkeyChord::new(
            "P".to_string(),
            None,
            Some(35),
            KeyModifiers::COMMAND | KeyModifiers::SHIFT,
        )
        .combo(),
        "⌘⇧P",
    );
    assert_eq!(
        HotkeyChord::new(" ".to_string(), None, Some(49), KeyModifiers::OPTION).combo(),
        "⌥Space",
    );
    assert!(!HotkeyChord::new("Escape".to_string(), None, Some(53), KeyModifiers::EMPTY)
        .is_shortcut());
    assert!(HotkeyChord::new("s".to_string(), None, Some(1), KeyModifiers::COMMAND).is_shortcut());
}

#[test]
fn action_type_raw_values() {
    for (action, raw) in [
        (ActionType::Click, "\"click\""),
        (ActionType::RightClick, "\"right_click\""),
        (ActionType::DoubleClick, "\"double_click\""),
        (ActionType::KeyPress, "\"key_press\""),
        (ActionType::Typing, "\"typing\""),
        (ActionType::WriteCode, "\"write_code\""),
        (ActionType::AppSwitch, "\"app_switch\""),
        (ActionType::MouseDrag, "\"mouse_drag\""),
        (ActionType::Manual, "\"manual\""),
    ] {
        assert_eq!(serde_json::to_string(&action).unwrap(), raw);
    }
}

#[test]
fn frame_snapshot_data_is_base64_like_swift() {
    // Swift `Data` encodes as a base64 string, not a number array.
    let snapshot = flowline_ir::FrameSnapshot::new(vec![0x89, 0x50, 0x4E, 0x47], 2.0);
    let json = serde_json::to_string(&snapshot).unwrap();
    assert!(
        json.contains("\"pngData\":\"iVBORw==\""),
        "unexpected snapshot json: {json}",
    );
    let decoded: flowline_ir::FrameSnapshot = serde_json::from_str(&json).unwrap();
    assert_eq!(decoded, snapshot);
}
