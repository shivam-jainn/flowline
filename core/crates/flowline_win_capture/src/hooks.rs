//! Win32 low-level hook normalization (`WH_MOUSE_LL`, `WH_KEYBOARD_LL` → IR).
//!
//! Pure functions over the raw hook payloads. The live pump lives in
//! `plugin::win32` (`cfg(windows)`); everything here runs on any host.

use flowline_ir::{KeyModifiers, MouseButton, Point2D, RawInputKind};

// ---- Win32 message codes (Winuser.h) ---------------------------------------

pub const WM_LBUTTONDOWN: u32 = 0x0201;
pub const WM_LBUTTONUP: u32 = 0x0202;
pub const WM_RBUTTONDOWN: u32 = 0x0204;
pub const WM_RBUTTONUP: u32 = 0x0205;
pub const WM_MBUTTONDOWN: u32 = 0x0207;
pub const WM_MBUTTONUP: u32 = 0x0208;
pub const WM_MOUSEWHEEL: u32 = 0x020A;
pub const WM_KEYDOWN: u32 = 0x0100;
pub const WM_SYSKEYDOWN: u32 = 0x0104;
pub const WM_KEYUP: u32 = 0x0101;

pub const VK_SHIFT: u32 = 0x10;
pub const VK_CONTROL: u32 = 0x11;
pub const VK_MENU: u32 = 0x12; // Alt
pub const VK_LWIN: u32 = 0x5B;
pub const VK_RWIN: u32 = 0x5C;
pub const VK_ESCAPE: u32 = 0x1B;
pub const VK_RETURN: u32 = 0x0D;
pub const VK_TAB: u32 = 0x09;
pub const VK_BACK: u32 = 0x08;
pub const VK_SPACE: u32 = 0x20;

// ---- Mouse ------------------------------------------------------------------

/// Normalized mouse action from a low-level mouse message. `None` for
/// button-up / wheel traffic the step producer ignores (presses only).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MouseAction {
    Click(MouseButton),
    DoubleClick,
}

pub fn mouse_message_to_action(w_param: u32) -> Option<MouseAction> {
    match w_param {
        WM_LBUTTONDOWN => Some(MouseAction::Click(MouseButton::Left)),
        WM_RBUTTONDOWN => Some(MouseAction::Click(MouseButton::Right)),
        WM_MBUTTONDOWN => Some(MouseAction::Click(MouseButton::Middle)),
        _ => None,
    }
}

/// `WH_MOUSE_LL` payload → click IR (position in screen pixels).
pub fn normalize_mouse_event(
    w_param: u32,
    x: i32,
    y: i32,
    click_count: u32,
) -> Option<RawInputKind> {
    let action = mouse_message_to_action(w_param)?;
    let button = match action {
        MouseAction::Click(b) => b,
        MouseAction::DoubleClick => MouseButton::Left,
    };
    let _ = (x, y);
    Some(RawInputKind::MouseClick {
        button,
        click_count: click_count as i64,
    })
}

// ---- Keyboard ---------------------------------------------------------------

/// Modifier snapshot from async key state: each flag mirrors
/// `GetAsyncKeyState(VK_*) & 0x8000 != 0`.
pub fn modifiers_from_key_state(shift_down: bool, ctrl_down: bool, alt_down: bool) -> KeyModifiers {
    let mut mods = KeyModifiers::empty();
    if shift_down {
        mods = KeyModifiers(mods.0 | KeyModifiers::SHIFT.0);
    }
    if ctrl_down {
        mods = KeyModifiers(mods.0 | KeyModifiers::COMMAND.0);
    }
    if alt_down {
        mods = KeyModifiers(mods.0 | KeyModifiers::OPTION.0);
    }
    mods
}

/// Virtual-key code → W3C `KeyboardEvent.key` vocabulary (printables fall
/// back to the provided char; matches `KeyCodeMap` semantics on macOS).
pub fn virtual_key_to_text(vk: u32, printable: Option<char>) -> Option<String> {
    match vk {
        VK_ESCAPE => Some("Escape".to_string()),
        VK_RETURN => Some("Enter".to_string()),
        VK_TAB => Some("Tab".to_string()),
        VK_BACK => Some("Backspace".to_string()),
        VK_SPACE => Some(" ".to_string()),
        VK_SHIFT | VK_CONTROL | VK_MENU | VK_LWIN | VK_RWIN => None,
        _ => printable.map(|c| c.to_string()),
    }
}

/// `WH_KEYBOARD_LL` payload → keystroke IR. `None` for key-up traffic and
/// pure-modifier presses (same policy as the macOS `HotkeyRecognizer` entry).
pub fn normalize_keyboard_event(
    w_param: u32,
    vk: u32,
    printable: Option<char>,
    modifiers: KeyModifiers,
) -> Option<(String, Option<i64>, KeyModifiers)> {
    match w_param {
        WM_KEYDOWN | WM_SYSKEYDOWN => {}
        _ => return None,
    }
    let key = virtual_key_to_text(vk, printable)?;
    Some((key, Some(vk as i64), modifiers))
}

/// Convenience: full keyboard normalization to a positioned IR kind.
pub fn keyboard_to_kind(
    w_param: u32,
    vk: u32,
    printable: Option<char>,
    modifiers: KeyModifiers,
    _at: Point2D,
) -> Option<RawInputKind> {
    let (key, code, mods) = normalize_keyboard_event(w_param, vk, printable, modifiers)?;
    Some(RawInputKind::KeyStroke {
        key,
        code,
        modifiers: mods,
    })
}
