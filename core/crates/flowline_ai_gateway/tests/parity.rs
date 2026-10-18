//! Parity tests (R/M2-06): golden payload + prompt/provider unit tests.

use flowline_ai_gateway::{
    GatewayProviderType, payload, prompts,
    prompts::DocumentationStyle, settings_for_provider,
};
use flowline_ir::{ActionType, MediaAssets, MediaMode, Step, StepSession, ThemeName};

/// The Swift `Date.formatted()` rendering embedded in the golden payload.
/// NOTE: the space before `PM` is U+202F NARROW NO-BREAK SPACE (that is what
/// Foundation emits); it is an input to the pure builder, not logic.
const GOLDEN_RECORDED_AT: &str = "1/3/2026, 3:30\u{202f}PM";

/// Text-only session mirroring the `gateway.payload.json` dump: id
/// `sess_00000002`, title `Text Session`, one TextEdit typing step.
///
/// DIVERGENCE NOTE (task text says "2-step"; the golden dump has
/// `Total Steps: 1` with a single step — this test mirrors the GOLDEN, which
/// is the parity authority).
fn golden_text_session() -> StepSession {
    StepSession {
        id: "sess_00000002".to_owned(),
        started_at: "2026-03-01T10:00:00Z".to_owned(),
        ended_at: Some("2026-03-01T10:00:01Z".to_owned()),
        title: "Text Session".to_owned(),
        summary: None,
        theme: ThemeName::ModernMinimal,
        media_mode: MediaMode::Hybrid,
        steps: vec![Step {
            id: "step-0101".to_owned(),
            index: 1,
            timestamp: "2026-03-01T10:00:00Z".to_owned(),
            action: ActionType::Typing,
            app_name: "TextEdit".to_owned(),
            bundle_identifier: None,
            window_title: "Untitled".to_owned(),
            element_role: None,
            element_title: None,
            element_value: None,
            coordinates: None,
            window_bounds: None,
            element_bounds: None,
            action_description: "Type text in TextEdit".to_owned(),
            user_notes: None,
            text_blob: Some("hello world".to_owned()),
            is_code: false,
            code_language: None,
            assets: MediaAssets::default(),
            working_directory: None,
            hotkey_combo: None,
            is_redacted: None,
        }],
        exports: Default::default(),
        synthesized_markdown: None,
    }
}

#[test]
fn text_only_request_matches_golden_payload() {
    let session = golden_text_session();
    let mut settings = settings_for_provider(GatewayProviderType::OpenRouter);
    settings.vision_enabled = false; // golden was built text-only, vision off
    let req = payload::build_request(
        &session,
        &settings,
        DocumentationStyle::SopGuide,
        None,
        GOLDEN_RECORDED_AT,
        &[],
    );
    assert_eq!(req.model, "anthropic/claude-3.5-sonnet");
    assert_eq!(req.temperature, 0.2);
    assert!(req.stream);
    parity_harness::assert_value_parity(&req, "gateway.payload.json");
}

#[test]
fn each_style_renders_non_empty_with_session_title() {
    let session = golden_text_session();
    let styles = [
        DocumentationStyle::SopGuide,
        DocumentationStyle::BugReport,
        DocumentationStyle::AutomationScript,
        DocumentationStyle::ExecutiveSummary,
    ];
    let mut systems = Vec::new();
    for style in styles {
        let system = prompts::system_prompt(style);
        assert!(!system.is_empty(), "{style:?} system prompt is empty");
        assert!(
            system.starts_with(prompts::BASE_SYSTEM_PROMPT),
            "{style:?} system prompt must extend the base prompt"
        );
        let user = prompts::user_prompt(&session, style, None, GOLDEN_RECORDED_AT);
        assert!(
            user.contains("Text Session"),
            "{style:?} user prompt must contain the session title"
        );
        systems.push(system);
    }
    // All four style suffixes must differ.
    for i in 0..systems.len() {
        for j in (i + 1)..systems.len() {
            assert_ne!(systems[i], systems[j], "styles {i} and {j} collide");
        }
    }
}

#[test]
fn style_raw_values_match_swift() {
    assert_eq!(DocumentationStyle::SopGuide.raw_value(), "sop_guide");
    assert_eq!(DocumentationStyle::BugReport.raw_value(), "bug_report");
    assert_eq!(
        DocumentationStyle::AutomationScript.raw_value(),
        "automation_script"
    );
    assert_eq!(
        DocumentationStyle::ExecutiveSummary.raw_value(),
        "executive_summary"
    );
}

#[test]
fn custom_instructions_branching_matches_swift() {
    let session = golden_text_session();
    let with = prompts::user_prompt(&session, DocumentationStyle::SopGuide, Some("Answer in French."), GOLDEN_RECORDED_AT);
    assert!(with.contains("Special User Instructions:\nAnswer in French.\n"));

    // Whitespaces-only custom is suppressed (Swift `CharacterSet.whitespaces`).
    let suppressed = prompts::user_prompt(&session, DocumentationStyle::SopGuide, Some("   \t  "), GOLDEN_RECORDED_AT);
    assert!(!suppressed.contains("Special User Instructions"));

    // Newlines-only custom is NOT suppressed (Swift `.whitespaces` excludes `\n`).
    let newlines = prompts::user_prompt(&session, DocumentationStyle::SopGuide, Some("\n"), GOLDEN_RECORDED_AT);
    assert!(newlines.contains("Special User Instructions"));
}

#[test]
fn provider_defaults_match_swift() {
    let cases = [
        (
            GatewayProviderType::OpenRouter,
            "https://openrouter.ai/api/v1",
            "anthropic/claude-3.5-sonnet",
        ),
        (
            GatewayProviderType::CustomOpenAI,
            "https://api.openai.com/v1",
            "gpt-4o",
        ),
        (
            GatewayProviderType::Ollama,
            "http://localhost:11434/v1",
            "llama3.2-vision",
        ),
        (
            GatewayProviderType::LmStudio,
            "http://localhost:1234/v1",
            "meta-llama-3.2-11b-vision-instruct",
        ),
        (
            GatewayProviderType::Cli,
            "",
            "ollama run llama3.2-vision",
        ),
    ];
    for (provider, base_url, model) in cases {
        assert_eq!(provider.default_base_url(), base_url, "{provider:?} base URL");
        assert_eq!(provider.default_model(), model, "{provider:?} model");
        let settings = settings_for_provider(provider);
        assert_eq!(settings.base_url, base_url);
        assert_eq!(settings.model, model);
        assert_eq!(settings.api_key, "");
        assert!(settings.vision_enabled);
        assert_eq!(settings.temperature, 0.2);
    }
}

fn vision_session() -> StepSession {
    let mut session = golden_text_session();
    session.steps[0].assets.screenshot = Some("media/shot-1.png".to_owned());
    session.steps.push(Step {
        id: "step-0102".to_owned(),
        index: 2,
        timestamp: "2026-03-01T10:00:01Z".to_owned(),
        action: ActionType::Click,
        app_name: "Safari".to_owned(),
        bundle_identifier: Some("com.apple.Safari".to_owned()),
        window_title: "Docs".to_owned(),
        element_role: Some("AXButton".to_owned()),
        element_title: Some("Save".to_owned()),
        element_value: None,
        coordinates: Some(flowline_ir::ScreenCoordinates { x: 100.7, y: 200.2 }),
        window_bounds: None,
        element_bounds: None,
        action_description: "Click \"Save\" in Docs".to_owned(),
        user_notes: Some("remember this".to_owned()),
        text_blob: None,
        is_code: false,
        code_language: None,
        assets: flowline_ir::MediaAssets {
            screenshot: None, // no screenshot asset -> image entry must be skipped
            gif: Some("media/anim-2.gif".to_owned()),
            ..Default::default()
        },
        working_directory: None,
        hotkey_combo: None,
        is_redacted: None,
    });
    session
}

#[test]
fn vision_path_appends_caption_and_data_url_in_order() {
    let session = vision_session();
    let settings = settings_for_provider(GatewayProviderType::OpenRouter); // vision on
    let req = payload::build_request(
        &session,
        &settings,
        DocumentationStyle::SopGuide,
        None,
        GOLDEN_RECORDED_AT,
        &[(1, "QUJD"), (2, "R0hJ")], // step 2 has no screenshot -> skipped
    );
    let user = &req.messages[1];
    assert_eq!(user.role, "user");
    assert_eq!(user.content.len(), 3, "text + caption + image, got {}", user.content.len());
    assert_eq!(user.content[1].text.as_deref(), Some("Screenshot for Step 1 (Type text in TextEdit):"));
    assert_eq!(
        user.content[2].image_url.as_ref().map(|u| u.url.as_str()),
        Some("data:image/png;base64,QUJD")
    );

    // Swift Codable keys: `image_url`, never camelCase; nil fields omitted.
    let raw = serde_json::to_string(&req).expect("serializable");
    assert!(raw.contains("\"image_url\""), "must use snake_case image_url key");
    assert!(!raw.contains("imageUrl"), "must not use camelCase keys");
}

#[test]
fn vision_disabled_or_missing_images_yield_text_only() {
    let session = vision_session();

    // Vision off: images supplied but ignored.
    let mut off = settings_for_provider(GatewayProviderType::Ollama);
    off.vision_enabled = false;
    let req = payload::build_request(
        &session,
        &off,
        DocumentationStyle::BugReport,
        None,
        GOLDEN_RECORDED_AT,
        &[(1, "QUJD")],
    );
    assert_eq!(req.messages[1].content.len(), 1);

    // Vision on but no images supplied: silent skip, like unreadable files.
    let on = settings_for_provider(GatewayProviderType::Ollama);
    let req = payload::build_request(&session, &on, DocumentationStyle::BugReport, None, GOLDEN_RECORDED_AT, &[]);
    assert_eq!(req.messages[1].content.len(), 1);
}

#[test]
fn step_rendering_covers_bundle_coords_notes_and_gif() {
    let session = vision_session();
    let user = prompts::user_prompt(&session, DocumentationStyle::SopGuide, None, GOLDEN_RECORDED_AT);
    assert!(user.contains("- App: Safari (com.apple.Safari)\n"));
    assert!(user.contains("- Target Element: AXButton \"Save\"\n"));
    assert!(user.contains("- Coordinates: (100, 200)\n")); // Swift Int() truncation
    assert!(user.contains("- User Notes: remember this\n"));
    assert!(user.contains("- Animated GIF Asset: media/anim-2.gif\n"));
    assert!(user.contains("- Screenshot Asset: media/shot-1.png\n"));
    assert!(user.contains("Total Steps: 2\n"));
}
