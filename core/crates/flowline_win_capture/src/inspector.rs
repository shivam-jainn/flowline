//! UIA tree inspector mapping (UI Automation properties → IR).
//!
//! Pure mapping over already-read UIA property values. Live traversal lives
//! in `plugin::win32` (`cfg(windows)`); the mapping below runs anywhere.
//!
//! Design note: Windows `Ctrl` is the workflow-modifier twin of macOS `Cmd`,
//! so [`super::hooks::modifiers_from_key_state`] maps physical Ctrl to the
//! logical `COMMAND` bit — `Ctrl+C` classifies exactly like `⌘C`.

use flowline_ir::{ElementRect, RawElementContext};

// ---- UIA control-type ids (UIA_ControlTypeIds) --------------------------------

pub const UIA_BUTTON: i32 = 50000;
pub const UIA_CHECKBOX: i32 = 50002;
pub const UIA_COMBOBOX: i32 = 50003;
pub const UIA_EDIT: i32 = 50004;
pub const UIA_HYPERLINK: i32 = 50005;
pub const UIA_LISTITEM: i32 = 50007;
pub const UIA_MENUITEM: i32 = 50009;
pub const UIA_TABITEM: i32 = 50019;
pub const UIA_DOCUMENT: i32 = 50030;
pub const UIA_WINDOW: i32 = 50032;
pub const UIA_PANE: i32 = 50033;

/// UIA control type → accessibility role vocabulary (shared with the macOS
/// driver's `AX*` roles so downstream steps render identically).
pub fn control_type_to_role(control_type: i32) -> &'static str {
    match control_type {
        UIA_BUTTON => "AXButton",
        UIA_CHECKBOX => "AXCheckBox",
        UIA_COMBOBOX => "AXComboBox",
        UIA_EDIT => "AXTextField",
        UIA_HYPERLINK => "AXLink",
        UIA_LISTITEM => "AXRow",
        UIA_MENUITEM => "AXMenuItem",
        UIA_TABITEM => "AXRadioButton",
        UIA_DOCUMENT => "AXTextArea",
        UIA_WINDOW => "AXWindow",
        UIA_PANE => "AXGroup",
        _ => "AXUnknown",
    }
}

/// UIA element snapshot (already-read properties) → [`RawElementContext`].
///
/// `is_password` covers `IsPassword` / `IsProtected` — secure fields take
/// the same pre-capture suppression path as macOS `isSecure` elements.
#[allow(clippy::too_many_arguments)]
pub fn inspect_element(
    app_name: &str,
    bundle_id: Option<&str>,
    window_title: &str,
    control_type: i32,
    name: Option<&str>,
    value: Option<&str>,
    is_password: bool,
    bounding_rect: Option<ElementRect>,
) -> RawElementContext {
    RawElementContext {
        app_name: app_name.to_string(),
        bundle_identifier: bundle_id.map(str::to_string),
        window_title: window_title.to_string(),
        role: Some(control_type_to_role(control_type).to_string()),
        subrole: None,
        title: name.map(str::to_string),
        value: if is_password {
            None
        } else {
            value.map(str::to_string)
        },
        placeholder: None,
        role_description: None,
        is_secure: is_password,
        bounding_box: bounding_rect,
        window_bounds: None,
        selectors: Vec::new(),
    }
}
