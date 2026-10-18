//! Windows driver parity (R/M3-01): recorded Windows fixture session flows
//! through the UNMODIFIED core (`flowline_engine` + `flowline_ir`) end to end.

use flowline_engine::state::EngineConfig;
use flowline_engine::testing::{InMemoryStore, MockDriver};
use flowline_engine::{Engine, InputEvent};
use flowline_ir::{KeyModifiers, MediaMode, MouseButton, Point2D, RawInputKind, ThemeName};
use flowline_win_capture::{hooks, inspector, register};

#[test]
fn mouse_hook_codes_normalize_to_clicks() {
    assert_eq!(
        hooks::normalize_mouse_event(hooks::WM_LBUTTONDOWN, 100, 200, 1),
        Some(RawInputKind::MouseClick {
            button: MouseButton::Left,
            click_count: 1,
        })
    );
    assert_eq!(
        hooks::normalize_mouse_event(hooks::WM_RBUTTONDOWN, 0, 0, 1),
        Some(RawInputKind::MouseClick {
            button: MouseButton::Right,
            click_count: 1,
        })
    );
    // Button-up / wheel traffic is ignored by the step producer.
    assert_eq!(hooks::normalize_mouse_event(hooks::WM_LBUTTONUP, 0, 0, 1), None);
    assert_eq!(hooks::normalize_mouse_event(hooks::WM_MOUSEWHEEL, 0, 0, 0), None);
}

#[test]
fn keyboard_hook_codes_normalize_to_keystrokes() {
    let mods = hooks::modifiers_from_key_state(false, true, false);
    assert!(mods.contains(KeyModifiers::COMMAND)); // Ctrl ≡ Cmd for shortcuts
    let (key, code, _) =
        hooks::normalize_keyboard_event(hooks::WM_KEYDOWN, 0x43, Some('c'), mods)
            .expect("keydown normalizes");
    assert_eq!(key, "c");
    assert_eq!(code, Some(0x43));
    // Key-up is ignored; modifiers alone produce no text.
    assert_eq!(
        hooks::normalize_keyboard_event(hooks::WM_KEYUP, 0x43, Some('c'), mods),
        None
    );
    assert_eq!(
        hooks::normalize_keyboard_event(hooks::WM_KEYDOWN, hooks::VK_SHIFT, None, mods),
        None
    );
    // Special keys map to W3C names.
    let (esc, _, _) = hooks::normalize_keyboard_event(
        hooks::WM_KEYDOWN,
        hooks::VK_ESCAPE,
        None,
        KeyModifiers::empty(),
    )
    .expect("escape normalizes");
    assert_eq!(esc, "Escape");
}

#[test]
fn uia_properties_map_to_ir_context() {
    let ctx = inspector::inspect_element(
        "Notepad",
        Some("Microsoft.Notepad"),
        "Untitled — Notepad",
        inspector::UIA_EDIT,
        Some("Document"),
        Some("secret"),
        false,
        None,
    );
    assert_eq!(ctx.role.as_deref(), Some("AXTextField"));
    assert_eq!(ctx.app_name, "Notepad");

    let secure = inspector::inspect_element(
        "Login",
        None,
        "Sign in",
        inspector::UIA_EDIT,
        Some("Password"),
        Some("hunter2"),
        true,
        None,
    );
    assert!(secure.is_secure);
    assert_eq!(secure.value, None); // values never leave secure fields
    assert_eq!(
        inspector::control_type_to_role(inspector::UIA_BUTTON),
        "AXButton"
    );
}

#[test]
fn windows_plugin_registers_alongside_mac_mock_noop() {
    let plugin = register();
    assert_eq!(plugin.manifest.id, "windows");
    assert!(plugin.manifest.validate_host("r-m1"));
    assert!(plugin.supports_streaming());
    assert!(plugin.needs_screen_access());
    // Same capability surface as the mac native: the core cannot tell them apart.
    for cap in ["snapshots", "micro-clips", "accessibility-tree", "secure-field-detection"] {
        assert!(plugin.manifest.supports(cap), "missing {cap}");
    }
}

#[test]
fn windows_fixture_session_flows_through_unmodified_core() {
    // Recorded Windows fixture: click on a Save button, then Ctrl+S.
    let click = InputEvent::new(
        1_000,
        hooks::normalize_mouse_event(hooks::WM_LBUTTONDOWN, 100, 200, 1).unwrap(),
        Some(Point2D::new(100.0, 200.0)),
        Some(inspector::inspect_element(
            "Contoso",
            Some("Contoso.App"),
            "Document",
            inspector::UIA_BUTTON,
            Some("Save"),
            None,
            false,
            None,
        )),
    );
    let mods = hooks::modifiers_from_key_state(false, true, false);
    let key_kind =
        hooks::keyboard_to_kind(hooks::WM_KEYDOWN, 0x53, Some('s'), mods, Point2D::new(100.0, 200.0))
            .unwrap();
    let key = InputEvent::new(1_500, key_kind, None, None);

    let mut engine_driver = MockDriver::new();
    engine_driver.element_at_point = Some(inspector::inspect_element(
        "Contoso",
        Some("Contoso.App"),
        "Document",
        inspector::UIA_BUTTON,
        Some("Save"),
        None,
        false,
        None,
    ));
    let mut engine = Engine::new(
        engine_driver,
        InMemoryStore::new(),
        EngineConfig::default(),
    );
    engine.start_recording(
        "Windows Fixture",
        ThemeName::ModernMinimal,
        MediaMode::Hybrid,
        0,
    );
    engine.process_event(&click, 1_000);
    engine.process_event(&key, 1_500);
    let session = engine.session().expect("session").clone();

    assert_eq!(session.id, "sess_00000001");
    assert!(!session.steps.is_empty(), "windows events must produce steps");
    assert!(session.steps.iter().any(|s| s.action_description.contains("Save")));
    // Ctrl+S is consumed as the recorder toggle (parity with macOS ⌘ handling).
    assert!(session.steps.iter().all(|s| s.action_description != "⌘S"));
}
