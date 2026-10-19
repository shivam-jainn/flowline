//! Settings parity suite: Swift goldens <-> `flowline_settings` round-trips.
//!
//! Asserts the exact Swift `JSONEncoder` keys / enum raw values, the
//! `decodeIfPresent` backwards compatibility, Swift-style `Double`
//! encoding, the env-aware `defaultSettings`, and the engine projection.

use std::collections::BTreeSet;

use flowline_settings::{
    EngineTuning, FlowlineSettings, GatewayProviderType, GestureAction, GestureSensitivity,
};
use parity_harness::{canonical, to_canonical};

#[test]
fn default_round_trip_is_stable() {
    let settings = FlowlineSettings::default();
    let json = serde_json::to_string(&settings).expect("serializable");
    let back: FlowlineSettings = serde_json::from_str(&json).expect("decodable");
    assert_eq!(back, settings);
    // Canonical form is stable across the round-trip.
    assert_eq!(to_canonical(&settings), canonical(&json));
}

#[test]
fn swift_keys_and_raw_values_verbatim() {
    let value = serde_json::to_value(FlowlineSettings::default()).expect("to value");
    let get = |ptr: &str| value.pointer(ptr).unwrap_or_else(|| panic!("missing {ptr}"));

    // Sections.
    for section in [
        "/capture",
        "/publishing",
        "/gateway",
        "/hotkeys",
        "/gestures",
        "/privacy",
        "/hotkeyCapture",
    ] {
        assert!(value.pointer(section).is_some(), "missing {section}");
    }
    // Capture keys.
    for key in [
        "/capture/mediaMode",
        "/capture/gifFps",
        "/capture/clipDurationPreClickSec",
        "/capture/clipDurationPostClickSec",
        "/capture/highlightClicks",
        "/capture/highlightColorHex",
        "/capture/highlightRadius",
        "/capture/recordAppSwitches",
        "/capture/captureMode",
    ] {
        assert!(value.pointer(key).is_some(), "missing {key}");
    }
    assert_eq!(get("/capture/mediaMode"), "hybrid");
    assert_eq!(get("/capture/captureMode"), "window");
    // Gateway keys keep their Swift capitals.
    assert_eq!(get("/gateway/provider"), "openrouter");
    assert_eq!(get("/gateway/baseURL"), "https://openrouter.ai/api/v1");
    assert_eq!(get("/gateway/apiKey"), "");
    assert_eq!(get("/gateway/model"), "anthropic/claude-3.5-sonnet");
    assert_eq!(get("/gateway/visionEnabled"), true);
    // Hotkey / gesture keys.
    assert_eq!(get("/hotkeys/toggleRecording"), "⌥ Space");
    assert_eq!(get("/gestures/shakeSensitivity"), "medium");
    assert_eq!(get("/gestures/shakeAction"), "pause_resume");
    assert_eq!(get("/gestures/hotCorners/topLeft"), "discard_last_step");
    assert_eq!(get("/gestures/hotCorners/topRight"), "pause_resume");
    assert_eq!(get("/gestures/hotCorners/bottomLeft"), "none");
    assert_eq!(get("/gestures/hotCorners/bottomRight"), "stop_and_review");
    assert_eq!(get("/gestures/middleClickAction"), "add_checkpoint");
    // Privacy keys.
    assert_eq!(get("/privacy/maskSecureInputFields"), true);
    assert_eq!(get("/privacy/enableOfflineOCRRedaction"), true);
    assert_eq!(get("/privacy/autoRedactAPIKeys"), true);
    assert_eq!(get("/privacy/autoRedactEmails"), false);
    assert_eq!(get("/privacy/blurStyle"), "frosted_glass");
    assert_eq!(get("/privacy/customRegexPatterns"), &serde_json::json!([]));
    // Publishing keys.
    assert_eq!(get("/publishing/defaultTheme"), "modern-minimal");
    assert_eq!(get("/publishing/companyName"), "Flowline Docs");
    assert_eq!(get("/publishing/pdfPaperSize"), "A4");
    assert_eq!(get("/publishing/keycapStyle"), "mac3D");
    assert_eq!(get("/publishing/mouseStyle"), "mac3D");
    // Hotkey-capture keys.
    assert_eq!(get("/hotkeyCapture/captureModifierShortcuts"), true);
    assert_eq!(get("/hotkeyCapture/captureNavigationKeys"), true);
    assert_eq!(get("/hotkeyCapture/ignoredCombos"), &serde_json::json!([]));
}

#[test]
fn swift_double_encoding() {
    // Integral doubles encode without a decimal point, like Swift.
    let json = serde_json::to_string(&FlowlineSettings::default()).expect("serializable");
    let canon = canonical(&json);
    assert!(canon.contains("\"blurRadius\":12"), "{canon}");
    assert!(canon.contains("\"highlightRadius\":28"), "{canon}");
    assert!(canon.contains("\"temperature\":0.2"), "{canon}");
    assert!(canon.contains("\"longPressDurationSec\":0.8"), "{canon}");
}

#[test]
fn backwards_compatible_decode() {
    // Empty file (or `{}`) loads full defaults.
    let empty: FlowlineSettings = serde_json::from_str("{}").expect("decodable");
    assert_eq!(empty, FlowlineSettings::default());

    // Pre-Phase-1 file: no gestures / privacy / hotkeyCapture sections.
    let legacy = serde_json::json!({
        "capture": { "gifFps": 30, "mediaMode": "static" },
        "gateway": { "provider": "ollama" },
        "hotkeys": { "toggleRecording": "⌥R" },
        "publishing": { "authorName": "Ada" },
    });
    let s: FlowlineSettings = serde_json::from_value(legacy).expect("decodable");
    assert_eq!(s.capture.gif_fps, 30);
    assert_eq!(s.capture.highlight_color_hex, "#EF4444");
    assert!(!s.capture.record_app_switches);
    assert_eq!(s.gateway.provider, GatewayProviderType::Ollama);
    // Untouched-in-Swift gateway keys fall back to openRouter-flavoured
    // struct defaults (mirrors `GatewaySettings.init`).
    assert_eq!(s.gateway.base_url, "https://openrouter.ai/api/v1");
    assert_eq!(s.hotkeys.toggle_recording, "⌥R");
    assert_eq!(s.publishing.author_name, "Ada");
    assert_eq!(s.publishing.company_name, "Flowline Docs");
    assert_eq!(s.gestures.shake_sensitivity, GestureSensitivity::Medium);
    assert!(s.privacy.mask_secure_input_fields);
    assert!(s.hotkey_capture.capture_modifier_shortcuts);

    // Pre-style publishing payload (no keycapStyle / mouseStyle).
    let pre_style = serde_json::json!({ "publishing": { "pdfPaperSize": "Letter" } });
    let s: FlowlineSettings = serde_json::from_value(pre_style).expect("decodable");
    assert_eq!(s.publishing.pdf_paper_size, "Letter");
    assert_eq!(s.publishing.company_name, "Flowline Docs");
}

#[test]
fn serializer_round_trip_of_custom_values() {
    let mut s = FlowlineSettings::default();
    s.capture.record_app_switches = true;
    s.hotkey_capture.ignored_combos = BTreeSet::from(["⌘⇧K".to_string()]);
    s.privacy.custom_regex_patterns = vec!["secret-\\d+".to_string()];
    s.privacy.blur_style = flowline_settings::RedactionBlurStyle::Blackout;
    s.gestures.shake_action = GestureAction::CaptureSnapshot;
    let json = serde_json::to_string(&s).expect("serializable");
    let back: FlowlineSettings = serde_json::from_str(&json).expect("decodable");
    assert_eq!(back, s);
}

#[test]
fn env_aware_default_settings() {
    // Single test owns these vars to avoid cross-test races.
    std::env::remove_var("OPENROUTER_API_KEY");
    std::env::remove_var("OPENAI_API_KEY");

    let plain = FlowlineSettings::default_settings();
    assert_eq!(plain.gateway.api_key, "");
    assert_eq!(plain.gateway.provider, GatewayProviderType::OpenRouter);

    std::env::set_var("OPENAI_API_KEY", "sk-test-openai");
    let s = FlowlineSettings::default_settings();
    assert_eq!(s.gateway.api_key, "sk-test-openai");
    assert_eq!(s.gateway.provider, GatewayProviderType::CustomOpenAI);
    assert_eq!(s.gateway.base_url, "https://api.openai.com/v1");

    // OpenRouter wins when both are set.
    std::env::set_var("OPENROUTER_API_KEY", "sk-or-test");
    let s = FlowlineSettings::default_settings();
    assert_eq!(s.gateway.api_key, "sk-or-test");
    assert_eq!(s.gateway.provider, GatewayProviderType::OpenRouter);
    assert_eq!(s.gateway.base_url, "https://openrouter.ai/api/v1");

    // Empty values are ignored.
    std::env::set_var("OPENROUTER_API_KEY", "");
    std::env::set_var("OPENAI_API_KEY", "");
    let s = FlowlineSettings::default_settings();
    assert_eq!(s.gateway.api_key, "");

    std::env::remove_var("OPENROUTER_API_KEY");
    std::env::remove_var("OPENAI_API_KEY");
}

#[test]
fn engine_projection_matches_engine_config_defaults() {
    let s = FlowlineSettings::default();
    let narrow = s.engine_settings();
    assert_eq!(narrow.capture, s.capture);
    assert_eq!(narrow.privacy, s.privacy);
    assert_eq!(narrow.hotkey_capture, s.hotkey_capture);
    assert_eq!(narrow.hotkeys, s.hotkeys);
    assert_eq!(narrow.gestures, s.gestures);

    // Field names/types mirror `flowline_engine::EngineConfig` so the
    // engine can copy them field-by-field.
    let t: EngineTuning = s.engine_tuning();
    assert_eq!(t.min_step_interval_secs, 0.20);
    assert_eq!(t.typing_debounce_secs, 1.0);
    assert_eq!(t.gesture_notice_secs, 2.5);
    assert_eq!(t.toggle_hotkey_combo, "⌥ Space");
    assert_eq!(t.click_clip_post_secs, 1.2);
    assert_eq!(t.typing_clip_post_secs, 0.6);
    assert!(!t.record_app_switches);
    assert!(t.capture_modifier_shortcuts);
    assert!(t.capture_navigation_keys);
    assert!(t.mask_secure_input);

    // Custom values flow through.
    let mut s = FlowlineSettings::default();
    s.hotkeys.toggle_recording = "⌃⌥R".to_string();
    s.capture.record_app_switches = true;
    s.privacy.mask_secure_input_fields = false;
    let t = s.engine_tuning();
    assert_eq!(t.toggle_hotkey_combo, "⌃⌥R");
    assert!(t.record_app_switches);
    assert!(!t.mask_secure_input);
}
