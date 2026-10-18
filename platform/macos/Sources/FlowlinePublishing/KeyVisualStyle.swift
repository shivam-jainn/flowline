import Foundation

/// Selectable keystroke / mouse visual styles.
///
/// Surveyed 2026-10 (KeyCastr Classic vs Svelte, `show-keystrokes`
/// Modern vs Mechanical, Keypress Magic-Keyboard, Remocn physical caps):
/// - `mac2D` — flat Magic-Keyboard matte caps, 1px border, no depth.
/// - `mac3D` — Apple bezel: gradient face + top highlight + bottom edge +
///   drop shadow (Great-Docs `kbd`, KeyCastr Classic, Magic Keyboard 3D).
/// - `mechanical3D` — skeuomorphic mechanical: base wall + raised top cap +
///   contact shadow; modifiers tinted (Show KeyPress Mechanical, Remocn).
///
/// Foundation-only so FlowlinePublishing (web/PDF CSS + HTML) and the
/// SwiftUI stage share one source of truth. Never import SwiftUI/AppKit here.
public enum KeycapStyle: String, Codable, CaseIterable, Sendable {
    case mac2D = "mac2D"
    case mac3D = "mac3D"
    case mechanical3D = "mechanical3D"

    public var label: String {
        switch self {
        case .mac2D: return "Mac 2D"
        case .mac3D: return "Mac 3D"
        case .mechanical3D: return "3D Keys"
        }
    }

    public var blurb: String {
        switch self {
        case .mac2D: return "Flat Magic Keyboard — matte, 1px border"
        case .mac3D: return "Apple bezel — gradient + bottom edge + shadow"
        case .mechanical3D: return "Mechanical — deep dish, side wall, tinted mods"
        }
    }

    /// CSS class suffix used by the web doc (`keycap-mac2d` …).
    public var cssClass: String {
        switch self {
        case .mac2D: return "keycap-mac2d"
        case .mac3D: return "keycap-mac3d"
        case .mechanical3D: return "keycap-mech"
        }
    }

    /// `data-keycap` value on `<html>`.
    public var htmlValue: String {
        switch self {
        case .mac2D: return "mac2d"
        case .mac3D: return "mac3d"
        case .mechanical3D: return "mech"
        }
    }
}

/// Selectable mouse-pointer halo styles. Mirrors `KeycapStyle` depth ramp:
/// flat ring → native Mac cursor → deep double-ring + glow.
public enum MouseStyle: String, Codable, CaseIterable, Sendable {
    case flat = "flat"
    case mac2D = "mac2D"
    case mac3D = "mac3D"

    public var label: String {
        switch self {
        case .flat: return "Flat"
        case .mac2D: return "Mac 2D"
        case .mac3D: return "Mac 3D"
        }
    }

    public var blurb: String {
        switch self {
        case .flat: return "Thin ring + dot, no shadow"
        case .mac2D: return "Native pointer in a flat badge"
        case .mac3D: return "Double ring + glow + drop shadow"
        }
    }

    public var cssClass: String {
        switch self {
        case .flat: return "mouse-flat"
        case .mac2D: return "mouse-mac2d"
        case .mac3D: return "mouse-mac3d"
        }
    }

    public var htmlValue: String {
        switch self {
        case .flat: return "flat"
        case .mac2D: return "mac2d"
        case .mac3D: return "mac3d"
        }
    }
}

/// Tokenizes a recorded `hotkeyCombo` (e.g. `"⌘⇧P"`, `"⌘S"`, `"⌥Space"`,
/// `"Ctrl+Shift+P"`) into per-keycap tokens.
///
/// - `"+"`-joined strings split on `"+"` (Windows-style `Ctrl+Shift+P`).
/// - Otherwise each modifier symbol is its own token and the remainder is
///   grouped into words/single characters, so `"⌥Space"` → `["⌥", "Space"]`.
public enum KeyComboTokens {
    /// Single-char modifier / navigation symbols that always stand alone.
    /// Includes ASCII `^` (caret notation for Control from external
    /// drivers) so it never fuses into a neighboring token and vanishes.
    public static let standalone: Set<Character> = [
        "⌘", "⌥", "⇧", "⌃", "⇥", "⎋", "⏎", "⌫", "⌦",
        "↑", "↓", "←", "→", "␣", "⇪", "🌐︎", "⊞", "❖", "^",
    ]

    public static func tokens(from combo: String) -> [String] {
        let trimmed = combo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.contains("+") {
            return trimmed.components(separatedBy: "+")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        var out: [String] = []
        var buf = ""
        func flush() {
            let t = buf.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { out.append(t) }
            buf = ""
        }
        for ch in trimmed {
            if standalone.contains(ch) {
                flush()
                out.append(String(ch))
            } else if ch.isWhitespace {
                flush()
            } else {
                buf.append(ch)
            }
        }
        flush()
        // `"⌘⇧P"` arrives as one buffer `"P"` after symbols — already split.
        // `"Space"`-style words stay whole; single letters stay single.
        if out.isEmpty { return [trimmed] }
        return out
    }

    /// True for modifier caps (get the tinted/slate treatment in 3D styles).
    public static func isModifier(_ token: String) -> Bool {
        guard token.count == 1, let ch = token.first else {
            let lower = token.lowercased()
            return ["cmd", "command", "opt", "option", "alt", "ctrl", "control",
                    "shift", "fn", "meta", "win", "caps", "capslock"].contains(lower)
        }
        return standalone.contains(ch)
    }

    /// Escaped HTML for one token.
    public static func escapeHTML(_ s: String) -> String {
        var r = s
        r = r.replacingOccurrences(of: "&", with: "&amp;")
        r = r.replacingOccurrences(of: "<", with: "&lt;")
        r = r.replacingOccurrences(of: ">", with: "&gt;")
        r = r.replacingOccurrences(of: "\"", with: "&quot;")
        return r
    }

    /// `<kbd>` row for the web doc. `style` picks the per-cap CSS class.
    public static func webKeycapsHTML(combo: String, style: KeycapStyle) -> String {
        webCapsHTML(tokens: tokens(from: combo), style: style)
    }

    /// `<kbd>` row from pre-split tokens (combo, bare key, or typed chars).
    public static func webCapsHTML(tokens: [String], style: KeycapStyle) -> String {
        let caps = tokens.map { t -> String in
            let mod = isModifier(t) ? " is-mod" : ""
            return "<kbd class=\"keycap \(style.cssClass)\(mod)\">\(escapeHTML(t))</kbd>"
        }
        return caps.joined(separator: "<span class=\"key-plus\" aria-hidden=\"true\">+</span>")
    }

    /// Tokens for a step: the recorded combo when present, else the bare
    /// pressed key (`elementTitle` carries the W3C key name for key presses,
    /// e.g. `"Escape"`, `"ArrowLeft"`). Never falls back to the action
    /// sentence — that rendered whole words ("Press", "in") as caps.
    public static func tokensForStep(combo: String?, elementTitle: String?) -> [String] {
        if let combo, !combo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return tokens(from: combo)
        }
        if let t = elementTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return [glyph(forW3CKey: t)]
        }
        return []
    }

    /// W3C `KeyboardEvent.key` name → cap legend. Unknown names pass
    /// through (truncated) so nothing silently disappears.
    public static func glyph(forW3CKey key: String) -> String {
        switch key {
        case "ArrowUp": return "↑"
        case "ArrowDown": return "↓"
        case "ArrowLeft": return "←"
        case "ArrowRight": return "→"
        case "Enter": return "⏎"
        case "Backspace": return "⌫"
        case "Delete", "Del": return "⌦"
        case "Escape", "Esc": return "esc"
        case "Tab": return "⇥"
        case " ": return "Space"
        case "Spacebar": return "Space"
        default: return key.count <= 12 ? key : String(key.prefix(12)) + "…"
        }
    }

    /// Per-character caps for short typed text (`"^"` → `["^"]`), so typed
    /// characters get a visual instead of vanishing. Returns nil for empty
    /// or long blobs (the code card already shows those).
    public static func typedTokens(text: String, maxChars: Int = 12) -> [String]? {
        guard !text.isEmpty, text.count <= maxChars else { return nil }
        return text.map { ch -> String in
            switch ch {
            case " ": return "Space"
            case "\n": return "⏎"
            case "\t": return "⇥"
            default: return String(ch)
            }
        }
    }

    /// Mouse action → short web label. Nil for non-pointer steps.
    /// Accepts both `ActionType.rawValue` (`"click"`, `"right_click"` …)
    /// and camelCase (`"rightClick"`) so callers never have to convert.
    public static func mouseLabel(action: String) -> String? {
        switch action {
        case "click": return "Left click"
        case "rightClick", "right_click": return "Right click"
        case "doubleClick", "double_click": return "Double click"
        case "mouseDrag", "mouse_drag": return "Drag"
        default: return nil
        }
    }
}
