import Foundation

/// macOS virtual key code → W3C `KeyboardEvent.key` vocabulary.
///
/// Keeps the IR platform-neutral while the mapping stays in the macOS driver
/// layer. The future `WebCaptureDriver` maps 1:1 to browser events with no
/// translation needed.
public enum KeyCodeMap {

    /// Returns the W3C key name for a virtual key code, falling back to the
    /// typed characters for printables. `nil` for keys Phase 1 does not emit
    /// (function keys, modifiers, non-printable control characters).
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
}
