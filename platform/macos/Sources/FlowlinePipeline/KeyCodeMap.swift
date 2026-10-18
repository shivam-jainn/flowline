import Foundation
import FlowlineIR

/// macOS virtual key code → W3C `KeyboardEvent.key` vocabulary.
///
/// Keeps the IR platform-neutral while the mapping stays in the macOS driver
/// layer. The future `WebCaptureDriver` maps 1:1 to browser events with no
/// translation needed.
public enum KeyCodeMap {

    /// Returns the W3C key name for a virtual key code, falling back to the
    /// typed characters for printables. `nil` for keys with no IR representation
    /// (modifier keys, non-printable control characters).
    public static func w3cKeyName(for keyCode: UInt16, characters: String?) -> String? {
        switch keyCode {
        case 36, 76: return "Return"
        case 51: return "Backspace"
        case 48: return "Tab"
        case 49: return " "
        case 53: return "Escape"
        case 117: return "Delete"
        case 123: return "ArrowLeft"
        case 124: return "ArrowRight"
        case 125: return "ArrowDown"
        case 126: return "ArrowUp"
        case 115: return "Home"
        case 116: return "PageUp"
        case 119: return "End"
        case 121: return "PageDown"
        // Function keys (Phase 2, T2).
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default:
            break
        }

        guard let characters = characters, !characters.isEmpty else { return nil }
        // Check for printable characters
        if let first = characters.unicodeScalars.first, first.value >= 32 && first.value != 127 {
            return characters
        }
        return nil
    }

    /// Virtual key codes that denote a modifier key press (`⇧⌃⌥⌘fn`).
    ///
    /// Modifier key-down events carry no typed character and must never be fed
    /// into text aggregation or hotkey recognition.
    public static func isModifierKey(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 54, 55, 56, 57, 58, 59, 60, 61, 62, 63: return true
        default: return false
        }
    }
}
