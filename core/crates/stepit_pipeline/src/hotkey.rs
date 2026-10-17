//! `HotkeyRecognizer` + `KeyCodeMap` port
//! (`Sources/StepItPipeline/HotkeyRecognizer.swift`,
//! `KeyCodeMap.swift`).
//!
//! IR-level chord policy plus the macOS virtual-keycode table, verbatim.

use std::collections::HashSet;

use stepit_ir::{HotkeyChord, KeyModifiers};

#[derive(Debug, Clone, PartialEq)]
pub struct HotkeyCaptureSettings {
    pub capture_modifier_shortcuts: bool,
    pub capture_navigation_keys: bool,
    pub ignored_combos: HashSet<String>,
}

impl Default for HotkeyCaptureSettings {
    fn default() -> Self {
        Self {
            capture_modifier_shortcuts: true,
            capture_navigation_keys: true,
            ignored_combos: HashSet::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum HotkeyDecision {
    ToggleRecording { combo: String },
    SystemConsumed { combo: String },
    WorkflowShortcut(HotkeyChord),
    NavigationKey(HotkeyChord),
    TextInput { key: String, modifiers: KeyModifiers },
    Ignored,
}

pub fn builtin_system_combos() -> HashSet<String> {
    [
        "⌘Tab",
        "⌘⇧Tab",
        "⌘Space",
        "⌘⇧Space",
        "⌃⌘Space",
        "⌘`",
    ]
    .iter()
    .map(|s| s.to_string())
    .collect()
}

pub fn navigation_keys() -> HashSet<String> {
    [
        "Escape", "Tab", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Home",
        "End", "PageUp", "PageDown", "Delete", "F1", "F2", "F3", "F4", "F5", "F6",
        "F7", "F8", "F9", "F10", "F11", "F12",
    ]
    .iter()
    .map(|s| s.to_string())
    .collect()
}

#[derive(Debug, Clone)]
pub struct HotkeyRecognizer {
    pub settings: HotkeyCaptureSettings,
    pub toggle_combo: String,
}

impl Default for HotkeyRecognizer {
    fn default() -> Self {
        Self {
            settings: HotkeyCaptureSettings::default(),
            toggle_combo: "⌥Space".to_string(),
        }
    }
}

impl HotkeyRecognizer {
    pub fn new(settings: HotkeyCaptureSettings, toggle_combo: &str) -> Self {
        Self {
            settings,
            toggle_combo: toggle_combo.to_string(),
        }
    }

    /// Driver entry point (raw key fields): modifier key presses are dropped,
    /// `⌘`/`⌃` chords use the modifier-independent character.
    pub fn evaluate_raw(
        &self,
        key_code: u16,
        characters: Option<&str>,
        characters_ignoring_modifiers: Option<&str>,
        modifiers: KeyModifiers,
    ) -> HotkeyDecision {
        if KeyCodeMap::is_modifier_key(key_code) {
            return HotkeyDecision::Ignored;
        }
        let chord_modifiers = Self::chord_modifiers(modifiers);
        let uses_chord_char = chord_modifiers.contains(KeyModifiers::COMMAND)
            || chord_modifiers.contains(KeyModifiers::CONTROL);
        let typed = if uses_chord_char {
            characters_ignoring_modifiers
        } else {
            characters
        };
        let key = KeyCodeMap::w3c_key_name(key_code, typed).or_else(|| {
            characters_ignoring_modifiers
                .and_then(|c| KeyCodeMap::w3c_key_name(key_code, Some(c)))
        });
        match key {
            Some(k) => self.evaluate(&k, Some(i32::from(key_code)), chord_modifiers),
            None => HotkeyDecision::Ignored,
        }
    }

    /// IR entry point (already-decoded chords).
    pub fn evaluate(
        &self,
        key: &str,
        code: Option<i32>,
        modifiers: KeyModifiers,
    ) -> HotkeyDecision {
        let modifiers = Self::chord_modifiers(modifiers);
        let chord = HotkeyChord::new(key.to_string(), None, code.map(i64::from), modifiers);
        let combo = chord.combo();

        // 1. Recorder control shortcut — strictly consumed (R3).
        if Self::normalize_combo(&combo) == Self::normalize_combo(&self.toggle_combo) {
            return HotkeyDecision::ToggleRecording { combo };
        }

        // 2. System-reserved combos the recorder must never turn into steps.
        if builtin_system_combos().contains(&combo)
            || self.settings.ignored_combos.contains(&combo)
        {
            return HotkeyDecision::SystemConsumed { combo };
        }

        // 3. Command / Control chords are workflow shortcuts. ⌃C is exempt
        //    from the capture gate (terminal SIGINT parity).
        let is_control_interrupt = modifiers.contains(KeyModifiers::CONTROL)
            && !modifiers.contains(KeyModifiers::COMMAND)
            && key.to_lowercase() == "c";
        if modifiers.contains(KeyModifiers::COMMAND) || modifiers.contains(KeyModifiers::CONTROL) {
            if !self.settings.capture_modifier_shortcuts && !is_control_interrupt {
                return HotkeyDecision::Ignored;
            }
            return HotkeyDecision::WorkflowShortcut(chord);
        }

        // 4. Navigation / special keys.
        if navigation_keys().contains(key) {
            if !self.settings.capture_navigation_keys {
                return HotkeyDecision::Ignored;
            }
            return HotkeyDecision::NavigationKey(chord);
        }

        // 5. Everything else is regular text input.
        HotkeyDecision::TextInput {
            key: key.to_string(),
            modifiers,
        }
    }

    /// macOS sets `.function` on arrow / F-key events even when the user never
    /// touched `fn`; it is not a real modifier for combo rendering.
    pub fn chord_modifiers(modifiers: KeyModifiers) -> KeyModifiers {
        modifiers.subtracting(KeyModifiers::FUNCTION)
    }

    /// Whitespace-insensitive combo comparison (`"⌥ Space"` == `"⌥Space"`).
    pub fn normalize_combo(combo: &str) -> String {
        combo.replace(' ', "").to_lowercase()
    }
}

/// macOS virtual key code → W3C `KeyboardEvent.key` vocabulary.
pub struct KeyCodeMap;

impl KeyCodeMap {
    pub fn w3c_key_name(key_code: u16, characters: Option<&str>) -> Option<String> {
        match key_code {
            36 | 76 => return Some("Return".to_string()),
            51 => return Some("Backspace".to_string()),
            48 => return Some("Tab".to_string()),
            49 => return Some(" ".to_string()),
            53 => return Some("Escape".to_string()),
            117 => return Some("Delete".to_string()),
            123 => return Some("ArrowLeft".to_string()),
            124 => return Some("ArrowRight".to_string()),
            125 => return Some("ArrowDown".to_string()),
            126 => return Some("ArrowUp".to_string()),
            115 => return Some("Home".to_string()),
            116 => return Some("PageUp".to_string()),
            119 => return Some("End".to_string()),
            121 => return Some("PageDown".to_string()),
            122 => return Some("F1".to_string()),
            120 => return Some("F2".to_string()),
            99 => return Some("F3".to_string()),
            118 => return Some("F4".to_string()),
            96 => return Some("F5".to_string()),
            97 => return Some("F6".to_string()),
            98 => return Some("F7".to_string()),
            100 => return Some("F8".to_string()),
            101 => return Some("F9".to_string()),
            109 => return Some("F10".to_string()),
            103 => return Some("F11".to_string()),
            111 => return Some("F12".to_string()),
            _ => {}
        }
        let characters = characters?;
        if characters.is_empty() {
            return None;
        }
        if let Some(first) = characters.chars().next() {
            // Printable check mirrors `unicodeScalars.first >= 32 && != 127`
            // on the ASCII corpus (multibyte scalars are all >= 128).
            let v = first as u32;
            if v >= 32 && v != 127 {
                return Some(characters.to_string());
            }
        }
        None
    }

    /// Virtual key codes that denote a modifier key press.
    pub fn is_modifier_key(key_code: u16) -> bool {
        matches!(key_code, 54..=63)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use stepit_ir::KeyModifiers as Mod;

    fn rec() -> HotkeyRecognizer {
        HotkeyRecognizer::default()
    }

    fn shortcut(dec: &HotkeyDecision) -> &HotkeyChord {
        match dec {
            HotkeyDecision::WorkflowShortcut(c) => c,
            other => panic!("expected workflow shortcut, got {other:?}"),
        }
    }

    fn nav(dec: &HotkeyDecision) -> &HotkeyChord {
        match dec {
            HotkeyDecision::NavigationKey(c) => c,
            other => panic!("expected navigation key, got {other:?}"),
        }
    }

    #[test]
    fn command_chord_combo() {
        let d = rec().evaluate("s", Some(1), Mod::COMMAND);
        let c = shortcut(&d);
        assert_eq!(c.key, "s");
        assert_eq!(c.display_key, "S");
        assert_eq!(c.combo(), "⌘S");
        assert_eq!(c.code, Some(1));
        assert!(c.is_shortcut());
    }

    #[test]
    fn command_shift_p() {
        let d = rec().evaluate("P", Some(35), Mod(Mod::COMMAND.0 | Mod::SHIFT.0));
        assert_eq!(shortcut(&d).combo(), "⌘⇧P");
    }

    #[test]
    fn canonical_modifier_order() {
        let cases = [
            (Mod(Mod::COMMAND.0 | Mod::OPTION.0), "⌘⌥I"),
            (Mod(Mod::COMMAND.0 | Mod::OPTION.0 | Mod::CONTROL.0), "⌘⌥⌃I"),
            (Mod(Mod::COMMAND.0 | Mod::SHIFT.0 | Mod::OPTION.0), "⌘⌥⇧I"),
            (Mod::CONTROL, "⌃I"),
        ];
        for (mods, expected) in cases {
            let d = rec().evaluate("i", Some(34), mods);
            assert_eq!(shortcut(&d).combo(), expected);
        }
    }

    #[test]
    fn control_c_is_workflow_shortcut() {
        let d = rec().evaluate("c", Some(8), Mod::CONTROL);
        assert_eq!(shortcut(&d).combo(), "⌃C");
    }

    #[test]
    fn navigation_keys() {
        let cases = [
            ("Escape", 53, "Escape"),
            ("Tab", 48, "Tab"),
            ("ArrowLeft", 123, "ArrowLeft"),
            ("ArrowRight", 124, "ArrowRight"),
            ("ArrowUp", 126, "ArrowUp"),
            ("ArrowDown", 125, "ArrowDown"),
            ("F1", 122, "F1"),
            ("F12", 111, "F12"),
            ("Delete", 117, "Delete"),
        ];
        for (key, code, combo) in cases {
            let d = rec().evaluate(key, Some(code), Mod::empty());
            let c = nav(&d);
            assert_eq!(c.combo(), combo);
            assert!(!c.is_shortcut());
        }
    }

    #[test]
    fn shift_tab_and_function_flag() {
        let d = rec().evaluate("Tab", Some(48), Mod::SHIFT);
        assert_eq!(nav(&d).combo(), "⇧Tab");
        let d = rec().evaluate("ArrowDown", Some(125), Mod::FUNCTION);
        let c = nav(&d);
        assert_eq!(c.combo(), "ArrowDown");
        assert_eq!(c.modifiers, Mod::empty());
    }

    #[test]
    fn toggle_immunity() {
        assert_eq!(
            rec().evaluate(" ", Some(49), Mod::OPTION),
            HotkeyDecision::ToggleRecording { combo: "⌥Space".to_string() }
        );
        let r = HotkeyRecognizer::new(HotkeyCaptureSettings::default(), "⌥ Space");
        assert_eq!(
            r.evaluate(" ", Some(49), Mod::OPTION),
            HotkeyDecision::ToggleRecording { combo: "⌥Space".to_string() }
        );
    }

    #[test]
    fn system_combos_consumed() {
        assert_eq!(
            rec().evaluate("Tab", Some(48), Mod::COMMAND),
            HotkeyDecision::SystemConsumed { combo: "⌘Tab".to_string() }
        );
        assert_eq!(
            rec().evaluate(" ", Some(49), Mod::COMMAND),
            HotkeyDecision::SystemConsumed { combo: "⌘Space".to_string() }
        );
        assert_eq!(
            rec().evaluate("Tab", Some(48), Mod(Mod::COMMAND.0 | Mod::SHIFT.0)),
            HotkeyDecision::SystemConsumed { combo: "⌘⇧Tab".to_string() }
        );
    }

    #[test]
    fn user_ignored_combos_consumed() {
        let s = HotkeyCaptureSettings {
            ignored_combos: std::collections::HashSet::from(["⌘⇧K".to_string()]),
            ..HotkeyCaptureSettings::default()
        };
        let r = HotkeyRecognizer::new(s, "⌥Space");
        assert_eq!(
            r.evaluate("K", Some(40), Mod(Mod::COMMAND.0 | Mod::SHIFT.0)),
            HotkeyDecision::SystemConsumed { combo: "⌘⇧K".to_string() }
        );
    }

    #[test]
    fn capture_gates() {
        let s = HotkeyCaptureSettings {
            capture_modifier_shortcuts: false,
            ..HotkeyCaptureSettings::default()
        };
        let r = HotkeyRecognizer::new(s, "⌥Space");
        assert_eq!(r.evaluate("s", Some(1), Mod::COMMAND), HotkeyDecision::Ignored);
        // ⌃C survives.
        let d = r.evaluate("c", Some(8), Mod::CONTROL);
        assert_eq!(shortcut(&d).combo(), "⌃C");

        let s2 = HotkeyCaptureSettings {
            capture_navigation_keys: false,
            ..HotkeyCaptureSettings::default()
        };
        let r2 = HotkeyRecognizer::new(s2, "⌥Space");
        assert_eq!(r2.evaluate("Escape", Some(53), Mod::empty()), HotkeyDecision::Ignored);
        assert_eq!(
            r2.evaluate("a", Some(0), Mod::empty()),
            HotkeyDecision::TextInput { key: "a".to_string(), modifiers: Mod::empty() }
        );
    }

    #[test]
    fn plain_text_and_composed() {
        assert_eq!(
            rec().evaluate("a", Some(0), Mod::empty()),
            HotkeyDecision::TextInput { key: "a".to_string(), modifiers: Mod::empty() }
        );
        assert_eq!(
            rec().evaluate("A", Some(0), Mod::SHIFT),
            HotkeyDecision::TextInput { key: "A".to_string(), modifiers: Mod::SHIFT }
        );
        assert_eq!(
            rec().evaluate("™", Some(19), Mod::OPTION),
            HotkeyDecision::TextInput { key: "™".to_string(), modifiers: Mod::OPTION }
        );
    }

    #[test]
    fn modifier_keycodes_ignored() {
        for code in 54u16..=63u16 {
            assert_eq!(
                rec().evaluate_raw(code, None, None, Mod::SHIFT),
                HotkeyDecision::Ignored,
                "keyCode {code}"
            );
        }
    }

    #[test]
    fn driver_chord_uses_ignoring_modifiers() {
        let d = rec().evaluate_raw(
            1,
            Some("s"),
            Some("S"),
            Mod(Mod::COMMAND.0 | Mod::SHIFT.0),
        );
        assert_eq!(shortcut(&d).combo(), "⌘⇧S");
    }

    #[test]
    fn driver_keeps_composed_characters() {
        assert_eq!(
            rec().evaluate_raw(19, Some("™"), Some("2"), Mod::OPTION),
            HotkeyDecision::TextInput { key: "™".to_string(), modifiers: Mod::OPTION }
        );
    }

    #[test]
    fn driver_decodes_function_keys() {
        let d = rec().evaluate_raw(122, None, None, Mod::FUNCTION);
        assert_eq!(nav(&d).combo(), "F1");
    }

    #[test]
    fn keycode_table() {
        assert_eq!(KeyCodeMap::w3c_key_name(36, None), Some("Return".to_string()));
        assert_eq!(KeyCodeMap::w3c_key_name(49, None), Some(" ".to_string()));
        assert_eq!(KeyCodeMap::w3c_key_name(0, Some("a")), Some("a".to_string()));
        assert_eq!(KeyCodeMap::w3c_key_name(0, Some("")), None);
        assert_eq!(KeyCodeMap::w3c_key_name(0, Some("\u{1}")), None);
        assert!(KeyCodeMap::is_modifier_key(55));
        assert!(!KeyCodeMap::is_modifier_key(0));
    }
}
