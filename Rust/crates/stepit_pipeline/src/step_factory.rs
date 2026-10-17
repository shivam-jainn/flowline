//! `StepFactory` port (`Sources/StepItPipeline/StepFactory.swift`).
//!
//! All `make*` constructors plus helpers, producing the local IR `Step`
//! mirror with fixed timestamp strings flowing through verbatim.

use crate::aggregate::TypingBatchResult;
use crate::classify::InputClassification;
use stepit_ir::{
    ActionType, HotkeyChord, MediaAssets, MouseButton, Point2D, RawElementContext,
    ScreenCoordinates, Step,
};

pub fn action_type_for(button: MouseButton, click_count: i32) -> ActionType {
    if button == MouseButton::Right {
        return ActionType::RightClick;
    }
    if click_count >= 2 {
        return ActionType::DoubleClick;
    }
    ActionType::Click
}

#[allow(clippy::too_many_arguments)]
pub fn make_click_step(
    index: i32,
    id: &str,
    timestamp: &str,
    action: ActionType,
    location: Point2D,
    context: Option<&RawElementContext>,
    assets: MediaAssets,
    is_redacted: Option<bool>,
) -> Step {
    let context = context.cloned().unwrap_or_else(RawElementContext::unknown);
    with_synthesized_description(Step {
        id: id.to_string(),
        index: index as i64,
        timestamp: timestamp.to_string(),
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
        action_description: default_action_placeholder(),
        user_notes: None,
        text_blob: None,
        is_code: false,
        code_language: None,
        assets,
        working_directory: None,
        hotkey_combo: None,
        is_redacted,
    })
    
}

#[allow(clippy::too_many_arguments)]
pub fn make_typing_step(
    index: i32,
    id: &str,
    timestamp: &str,
    result: &TypingBatchResult,
    assets: MediaAssets,
    working_directory: Option<&str>,
    is_redacted: Option<bool>,
) -> Step {
    let context = result.context.clone().unwrap_or_else(RawElementContext::unknown);
    let clean: String = result.text_blob.trim().to_string();

    let (action, description, role, lang_tag): (ActionType, String, &str, Option<String>) =
        match &result.classification {
            InputClassification::Terminal => (
                ActionType::WriteCode,
                terminal_command_description(&clean, working_directory, &context.app_name),
                "AXTerminal",
                Some("bash".to_string()),
            ),
            InputClassification::Code(language) => (
                ActionType::WriteCode,
                format!("Write code in {}", context.app_name),
                "AXCodeEditor",
                Some(language.clone()),
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

    with_synthesized_description(Step {
        id: id.to_string(),
        index: index as i64,
        timestamp: timestamp.to_string(),
        action,
        app_name: context.app_name.clone(),
        bundle_identifier: context.bundle_identifier.clone(),
        window_title: context.window_title.clone(),
        element_role: Some(role.to_string()),
        element_title: lang_tag.as_ref().map(|l| format!("({l})")),
        element_value: None,
        coordinates: Some(ScreenCoordinates::new(result.location.x, result.location.y)),
        window_bounds: None,
        element_bounds: None,
        action_description: description,
        user_notes: None,
        text_blob: Some(result.text_blob.clone()),
        is_code: action == ActionType::WriteCode,
        code_language: lang_tag,
        assets,
        working_directory: if result.classification == InputClassification::Terminal {
            working_directory.map(str::to_string)
        } else {
            None
        },
        hotkey_combo: None,
        is_redacted,
    })
}

/// Step for a directly-emitted terminal command (T5).
#[allow(clippy::too_many_arguments)]
pub fn make_terminal_command_step(
    index: i32,
    id: &str,
    timestamp: &str,
    command: &str,
    working_directory: Option<&str>,
    context: Option<&RawElementContext>,
    assets: MediaAssets,
    is_redacted: Option<bool>,
) -> Step {
    let context = context.cloned().unwrap_or_else(RawElementContext::unknown);
    let clean = command.trim().to_string();
    with_synthesized_description(Step {
        id: id.to_string(),
        index: index as i64,
        timestamp: timestamp.to_string(),
        action: ActionType::WriteCode,
        app_name: context.app_name.clone(),
        bundle_identifier: context.bundle_identifier.clone(),
        window_title: context.window_title.clone(),
        element_role: Some("AXTerminal".to_string()),
        element_title: Some("(bash)".to_string()),
        element_value: None,
        coordinates: context
            .window_bounds
            .map(|b| ScreenCoordinates::new(b.center().x, b.center().y)),
        window_bounds: None,
        element_bounds: None,
        action_description: terminal_command_description(
            &clean,
            working_directory,
            &context.app_name,
        ),
        user_notes: None,
        text_blob: Some(command.to_string()),
        is_code: true,
        code_language: Some("bash".to_string()),
        assets,
        working_directory: working_directory.map(str::to_string),
        hotkey_combo: None,
        is_redacted,
    })
}

/// `Run "git status" in ~/Code/stepit (Ghostty)` when `pwd` is known;
/// legacy `Run "git status" in Ghostty` otherwise (E2).
pub fn terminal_command_description(
    command: &str,
    working_directory: Option<&str>,
    app_name: &str,
) -> String {
    match working_directory {
        Some(dir) if !dir.is_empty() => format!("Run \"{command}\" in {dir} ({app_name})"),
        _ => format!("Run \"{command}\" in {app_name}"),
    }
}

pub fn make_key_press_step(
    index: i32,
    id: &str,
    timestamp: &str,
    chord: &HotkeyChord,
    context: Option<&RawElementContext>,
    assets: MediaAssets,
    is_redacted: Option<bool>,
) -> Step {
    let context = context.cloned().unwrap_or_else(RawElementContext::unknown);
    let combo = chord.combo();
    let app_name = if context.app_name.is_empty() {
        RawElementContext::unknown().app_name
    } else {
        context.app_name.clone()
    };

    let description = if combo == "⌘S" {
        format!("Press ⌘S to save in {app_name}")
    } else {
        format!("Press {combo} in {app_name}")
    };

    with_synthesized_description(Step {
        id: id.to_string(),
        index: index as i64,
        timestamp: timestamp.to_string(),
        action: ActionType::KeyPress,
        app_name: context.app_name.clone(),
        bundle_identifier: context.bundle_identifier.clone(),
        window_title: context.window_title.clone(),
        element_role: Some("AXKeyboard".to_string()),
        element_title: Some(chord.key.clone()),
        element_value: None,
        coordinates: context
            .bounding_box
            .map(|b| ScreenCoordinates::new(b.center().x, b.center().y)),
        window_bounds: context.window_bounds,
        element_bounds: context.bounding_box,
        action_description: description,
        user_notes: None,
        text_blob: None,
        is_code: false,
        code_language: None,
        assets,
        working_directory: None,
        hotkey_combo: if chord.is_shortcut() { Some(combo) } else { None },
        is_redacted,
    })
}

#[allow(clippy::too_many_arguments)]
pub fn make_drag_step(
    index: i32,
    id: &str,
    timestamp: &str,
    start: Point2D,
    end: Point2D,
    context: Option<&RawElementContext>,
    assets: MediaAssets,
    is_redacted: Option<bool>,
) -> Step {
    let context = context.cloned().unwrap_or_else(RawElementContext::unknown);
    let description = format!(
        "Drag from ({}, {}) to ({}, {}) in {}",
        start.x.round() as i64,
        start.y.round() as i64,
        end.x.round() as i64,
        end.y.round() as i64,
        context.app_name
    );
    with_synthesized_description(Step {
        id: id.to_string(),
        index: index as i64,
        timestamp: timestamp.to_string(),
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
        assets,
        working_directory: None,
        hotkey_combo: None,
        is_redacted,
    })
}

pub fn make_app_switch_step(
    index: i32,
    id: &str,
    timestamp: &str,
    bundle_id: Option<&str>,
    app_name: &str,
    window_title: &str,
) -> Step {
    with_synthesized_description(Step {
        id: id.to_string(),
        index: index as i64,
        timestamp: timestamp.to_string(),
        action: ActionType::AppSwitch,
        app_name: app_name.to_string(),
        bundle_identifier: bundle_id.map(str::to_string),
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
    })
}

pub fn make_manual_step(index: i32, id: &str, timestamp: &str, title: &str, notes: Option<&str>) -> Step {
    with_synthesized_description(Step {
        id: id.to_string(),
        index: index as i64,
        timestamp: timestamp.to_string(),
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
        user_notes: notes.map(str::to_string),
        text_blob: None,
        is_code: false,
        code_language: None,
        assets: MediaAssets::default(),
        working_directory: None,
        hotkey_combo: None,
        is_redacted: None,
    })
}

/// `Step.synthesizeDefaultDescription` port (owns: StepItIR in Swift;
/// mirrored here so click steps render byte-identical descriptions).
pub fn synthesize_default_description(
    action: ActionType,
    element_title: Option<&str>,
    element_role: Option<&str>,
    app_name: &str,
    window_title: &str,
    text_blob: Option<&str>,
    is_code: bool,
) -> String {
    if action == ActionType::Typing || action == ActionType::WriteCode {
        let target = if app_name.is_empty() { "editor" } else { app_name };
        let lower = target.to_lowercase();
        let is_terminal_app = ["terminal", "iterm", "warp", "ghostty", "kitty", "alacritty"]
            .iter()
            .any(|t| lower.contains(t));

        if let Some(blob) = text_blob {
            if !blob.is_empty() {
                let clean = blob.trim().to_string();
                let preview: String = clean.chars().take(40).collect();
                let ellipsis = if clean.chars().count() > 40 { "..." } else { "" };
                if is_terminal_app || is_code && is_command_like(&clean) {
                    return format!("Run \"{preview}{ellipsis}\" in {target}");
                } else if is_code {
                    return format!("Write code in {target}");
                } else {
                    return format!("Type \"{preview}{ellipsis}\" in {target}");
                }
            }
        }
        if is_terminal_app {
            return format!("Execute command in {target}");
        } else if is_code {
            return format!("Write code in {target}");
        }
        return format!("Type text in {target}");
    }

    if app_name.contains("UserNotificationCenter") || app_name.contains("Notification") {
        if let Some(title) = element_title {
            if !title.trim().is_empty() {
                return format!("Click notification \"{title}\"");
            }
        }
        return "Click system notification".to_string();
    }

    let action_word = match action {
        ActionType::Click => "Click",
        ActionType::RightClick => "Right-click",
        ActionType::DoubleClick => "Double-click",
        ActionType::KeyPress => "Press",
        ActionType::Typing => "Type in",
        ActionType::WriteCode => "Write code in",
        ActionType::AppSwitch => "Switch to",
        ActionType::MouseDrag => "Drag in",
        ActionType::Manual => "Perform step in",
    };

    let mut target_desc = String::new();
    if let Some(title) = element_title {
        if !title.trim().is_empty() {
            target_desc = format!("\"{title}\"");
        }
    }
    if target_desc.is_empty() {
        if let Some(role) = element_role {
            target_desc = role.replace("AX", "").to_lowercase();
        }
    }

    let context = if !window_title.is_empty() {
        format!(" in {window_title}")
    } else if !app_name.is_empty() {
        format!(" in {app_name}")
    } else {
        String::new()
    };

    if target_desc.is_empty() {
        format!("{action_word}{context}")
    } else {
        format!("{action_word} {target_desc}{context}")
    }
}

fn is_command_like(clean: &str) -> bool {
    ["npm ", "git ", "swift ", "cd ", "cat ", "ls", "curl", "docker"]
        .iter()
        .any(|p| clean.starts_with(p))
}

fn default_action_placeholder() -> String {
    String::new()
}

fn with_synthesized_description(mut step: Step) -> Step {
    if step.action_description.is_empty() {
        step.action_description = synthesize_default_description(
            step.action,
            step.element_title.as_deref(),
            step.element_role.as_deref(),
            &step.app_name,
            &step.window_title,
            step.text_blob.as_deref(),
            step.is_code,
        );
    }
    step
}

#[cfg(test)]
mod tests {
    use super::*;
    fn ctx(app: &str) -> RawElementContext {
        RawElementContext {
            app_name: app.to_string(),
            bundle_identifier: None,
            window_title: String::new(),
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

    use stepit_ir::HotkeyChord;
    use stepit_ir::KeyModifiers as Mod;

    fn safari_docs() -> RawElementContext {
        let mut c = ctx("Safari");
        c.bundle_identifier = Some("com.apple.Safari".to_string());
        c.window_title = "Docs — Safari".to_string();
        c.role = Some("AXButton".to_string());
        c.title = Some("Save".to_string());
        c
    }

    #[test]
    fn click_mapping() {
        assert_eq!(action_type_for(MouseButton::Right, 1), ActionType::RightClick);
        assert_eq!(action_type_for(MouseButton::Right, 2), ActionType::RightClick);
        assert_eq!(action_type_for(MouseButton::Left, 1), ActionType::Click);
        assert_eq!(action_type_for(MouseButton::Left, 2), ActionType::DoubleClick);
        assert_eq!(action_type_for(MouseButton::Middle, 3), ActionType::DoubleClick);
    }

    #[test]
    fn click_synthesizes_description() {
        let ctx = safari_docs();
        let s = make_click_step(
            1, "id", "2026-03-01T10:00:00Z", ActionType::Click,
            Point2D::new(100.0, 200.0), Some(&ctx), MediaAssets::default(), None,
        );
        assert_eq!(s.action_description, "Click \"Save\" in Docs — Safari");
    }

    #[test]
    fn typing_branches() {
        let mk = |blob: &str, class: InputClassification, app: &str| TypingBatchResult {
            text_blob: blob.to_string(),
            context: Some({
                let mut c = ctx(app);
                c.window_title = app.to_string();
                c
            }),
            classification: class,
            location: Point2D::ZERO,
        };
        let t = make_typing_step(
            1, "id", "ts",
            &mk("git status", InputClassification::Terminal, "Ghostty"),
            MediaAssets::default(), None, None,
        );
        assert_eq!(t.action_description, "Run \"git status\" in Ghostty");
        assert_eq!(t.element_role.as_deref(), Some("AXTerminal"));
        assert_eq!(t.code_language.as_deref(), Some("bash"));

        let c = make_typing_step(
            1, "id", "ts",
            &mk("let x = 1", InputClassification::Code("swift".into()), "VS Code"),
            MediaAssets::default(), None, None,
        );
        assert_eq!(c.action_description, "Write code in VS Code");

        let long = "Hello team, here is a longer note that exceeds 32 characters";
        let p = make_typing_step(
            1, "id", "ts",
            &mk(long, InputClassification::Text, "Notes"),
            MediaAssets::default(), Some("~/x"), None,
        );
        assert_eq!(p.action_description, "Type \"Hello team, here is a longer not...\" in Notes");
        assert_eq!(p.working_directory, None);
    }

    #[test]
    fn keypress_save_special_case() {
        let ctx = safari_docs();
        let chord = HotkeyChord::new("s".to_string(), None, Some(1), Mod::COMMAND);
        let s = make_key_press_step(3, "id", "ts", &chord, Some(&ctx), MediaAssets::default(), None);
        assert_eq!(s.action_description, "Press ⌘S to save in Safari");
        assert_eq!(s.hotkey_combo.as_deref(), Some("⌘S"));
        let nav = HotkeyChord::new("Escape".to_string(), None, Some(53), Mod::empty());
        let e = make_key_press_step(1, "id", "ts", &nav, Some(&ctx), MediaAssets::default(), None);
        assert_eq!(e.hotkey_combo, None);
    }

    #[test]
    fn drag_rounds() {
        let ctx = safari_docs();
        let s = make_drag_step(
            4, "id", "ts",
            Point2D::new(10.0, 10.0), Point2D::new(300.4, 200.6),
            Some(&ctx), MediaAssets::default(), None,
        );
        assert_eq!(s.action_description, "Drag from (10, 10) to (300, 201) in Safari");
    }

    #[test]
    fn terminal_pwd_and_manual() {
        assert_eq!(
            terminal_command_description("git status", Some("~/Code"), "Terminal"),
            "Run \"git status\" in ~/Code (Terminal)"
        );
        assert_eq!(
            terminal_command_description("git status", None, "Ghostty"),
            "Run \"git status\" in Ghostty"
        );
        let m = make_manual_step(7, "id", "ts", "Verify", Some("check it"));
        assert_eq!(m.app_name, "Manual Action");
        assert_eq!(m.action_description, "Verify");
    }

    #[test]
    fn notification_parity() {
        let mut ctx = ctx("UserNotificationCenter");
        ctx.role = Some("AXNotificationCenter".to_string());
        ctx.title = Some("Claude Code Prototype".to_string());
        let s = make_click_step(
            1, "id", "ts", ActionType::Click, Point2D::ZERO,
            Some(&ctx), MediaAssets::default(), None,
        );
        assert_eq!(s.action_description, "Click notification \"Claude Code Prototype\"");
    }
}
