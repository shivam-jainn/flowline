import Foundation
import StepItIR

/// Decision produced by `HotkeyRecognizer` for one keyboard event.
///
/// The driver (`EventMonitor`) routes on this; the engine re-evaluates incoming
/// `.keyStroke` IR events with the same rules so out-of-process and mock
/// drivers behave identically.
public enum HotkeyDecision: Sendable, Equatable {
    /// The configured recorder-control shortcut (default `⌥Space`) — consumed
    /// by the recorder and **never** recorded as a workflow step (fix R3).
    case toggleRecording(combo: String)
    /// A system-reserved combo (`⌘Tab`, `⌘Space`, user `ignoredCombos`) —
    /// consumed, never recorded.
    case systemConsumed(combo: String)
    /// A discrete workflow shortcut (`⌘S`, `⌘⇧P`, `⌃A`, …) → `.keyPress` step.
    case workflowShortcut(HotkeyChord)
    /// A navigation / special key (`Esc`, `Tab`, arrows, F-keys) → `.keyPress` step.
    case navigationKey(HotkeyChord)
    /// Regular text input — routed to the typing aggregator.
    case textInput(key: String, modifiers: KeyModifiers)
    /// Drop entirely (modifier key press, unmapped non-text key).
    case ignored
}

/// Centralized hotkey resolution for the macOS driver and the engine (T2).
///
/// Foundation-only on purpose: it classifies IR-level chords so unit tests can
/// cover every modifier combination without hardware (`HotkeyRecognizerTests`).
/// `KeyCodeMap` owns the virtual-keycode decoding; this type owns the policy.
public struct HotkeyRecognizer: Sendable {

    /// Recorder control shortcut when settings are unavailable.
    public static let defaultToggleCombo = "⌥Space"

    /// Combos the OS/Mission Control consume before any app sees them.
    /// Always consumed, regardless of `HotkeyCaptureSettings.ignoredCombos`.
    public static let builtInSystemCombos: Set<String> = [
        "⌘Tab", "⌘⇧Tab",   // app switcher (both directions)
        "⌘Space", "⌘⇧Space", "⌃⌘Space", // Spotlight / input sources
        "⌘`"               // cycle app windows
    ]

    /// Named keys that are navigation / special keys rather than text.
    public static let navigationKeys: Set<String> = [
        "Escape", "Tab",
        "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight",
        "Home", "End", "PageUp", "PageDown", "Delete",
        "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"
    ]

    public var settings: HotkeyCaptureSettings
    /// The recorder toggle combo (`HotkeySettings.toggleRecording`).
    public var toggleCombo: String

    public init(
        settings: HotkeyCaptureSettings = HotkeyCaptureSettings(),
        toggleCombo: String = HotkeyRecognizer.defaultToggleCombo
    ) {
        self.settings = settings
        self.toggleCombo = toggleCombo
    }

    // MARK: - Driver entry point (raw NSEvent fields)

    /// Classifies a decoded `NSEvent` key-down.
    ///
    /// - Parameters:
    ///   - keyCode: macOS virtual key code.
    ///   - characters: `event.characters` (what the user actually typed).
    ///   - charactersIgnoringModifiers: `event.charactersIgnoringModifiers`
    ///     (stable letters for ⌘/⌃ chords; keeps Shift semantics).
    public func evaluate(
        keyCode: UInt16,
        characters: String?,
        charactersIgnoringModifiers: String?,
        modifiers: KeyModifiers
    ) -> HotkeyDecision {
        guard !KeyCodeMap.isModifierKey(keyCode) else { return .ignored }

        // ⌘/⌃ chords use the modifier-independent character ("s" for ⌘⇧S);
        // plain typing keeps the composed character ("™" for ⌥2).
        let chordModifiers = Self.chordModifiers(from: modifiers)
        let usesChordCharacter = chordModifiers.contains(.command) || chordModifiers.contains(.control)
        let typed = usesChordCharacter ? charactersIgnoringModifiers : characters
        guard let key = KeyCodeMap.w3cKeyName(for: keyCode, characters: typed) ?? charactersIgnoringModifiers.flatMap({ KeyCodeMap.w3cKeyName(for: keyCode, characters: $0) }) else {
            return .ignored
        }
        return evaluate(key: key, code: Int(keyCode), modifiers: chordModifiers)
    }

    // MARK: - IR entry point (already-decoded chords)

    /// Classifies an IR-level keystroke (`key` = W3C `KeyboardEvent.key`).
    public func evaluate(key: String, code: Int?, modifiers: KeyModifiers) -> HotkeyDecision {
        let modifiers = Self.chordModifiers(from: modifiers)
        let chord = HotkeyChord(key: key, code: code, modifiers: modifiers)
        let combo = chord.combo

        // 1. Recorder control shortcut — strictly consumed (R3).
        if Self.normalizeCombo(combo) == Self.normalizeCombo(toggleCombo) {
            return .toggleRecording(combo: combo)
        }

        // 2. System-reserved combos the recorder must never turn into steps.
        if Self.builtInSystemCombos.contains(combo) || settings.ignoredCombos.contains(combo) {
            return .systemConsumed(combo: combo)
        }

        // 3. Command / Control chords are workflow shortcuts (`⌘S`, `⌃A`, …).
        //    ⌃C is exempt from the capture gate: the engine maps it to the
        //    terminal SIGINT batch terminator in every configuration (Phase 1
        //    parity), so the driver must keep delivering the keystroke.
        let isControlInterruptChord = modifiers.contains(.control)
            && !modifiers.contains(.command)
            && key.lowercased() == "c"
        if modifiers.contains(.command) || modifiers.contains(.control) {
            guard settings.captureModifierShortcuts || isControlInterruptChord else { return .ignored }
            return .workflowShortcut(chord)
        }

        // 4. Navigation / special keys (`Esc`, `Tab`, arrows, F-keys).
        if Self.navigationKeys.contains(key) {
            guard settings.captureNavigationKeys else { return .ignored }
            return .navigationKey(chord)
        }

        // 5. Everything else is regular text input.
        return .textInput(key: key, modifiers: modifiers)
    }

    // MARK: - Helpers

    /// macOS sets `.function` on arrow / F-key events even when the user never
    /// touched `fn`; it is not a real modifier for combo rendering.
    static func chordModifiers(from modifiers: KeyModifiers) -> KeyModifiers {
        modifiers.subtracting(.function)
    }

    /// Whitespace-insensitive combo comparison (`"⌥ Space"` == `"⌥Space"`).
    static func normalizeCombo(_ combo: String) -> String {
        combo.replacingOccurrences(of: " ", with: "").lowercased()
    }
}
