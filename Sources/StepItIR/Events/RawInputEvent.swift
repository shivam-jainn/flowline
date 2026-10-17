import Foundation
import StepItIR

/// Platform-neutral 2D point used by every core API.
///
/// macOS ↔ CoreGraphics bridging lives in the driver layer (`IRBridging.swift`),
/// never in `Events/`, `Engine/` or `Pipeline/`.
public struct Point2D: Codable, Sendable, Equatable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Point2D(x: 0, y: 0)
}

/// IR identity of a mouse button. `NSEvent` decoding stays driver-side.
public enum MouseButton: String, Codable, Sendable, CaseIterable {
    case left
    case right
    case middle

    /// Maps a platform button number (0 = left, 1 = right, 2 = middle).
    public init?(buttonNumber: Int) {
        switch buttonNumber {
        case 0: self = .left
        case 1: self = .right
        case 2: self = .middle
        default: return nil
        }
    }
}

/// Canonical keyboard modifier set. `symbolString` feeds hotkey combo
/// rendering, e.g. `⌥Space` for `[.option]`.
public struct KeyModifiers: OptionSet, Codable, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let option = KeyModifiers(rawValue: 1 << 1)
    public static let control = KeyModifiers(rawValue: 1 << 2)
    public static let shift = KeyModifiers(rawValue: 1 << 3)
    public static let function = KeyModifiers(rawValue: 1 << 4)

    /// Rendered in canonical order: `⌘⌥⌃⇧` (+ `fn`).
    public var symbolString: String {
        var symbols = ""
        if contains(.command) { symbols += "⌘" }
        if contains(.option) { symbols += "⌥" }
        if contains(.control) { symbols += "⌃" }
        if contains(.shift) { symbols += "⇧" }
        if contains(.function) { symbols += "fn" }
        return symbols
    }
}

/// The single event envelope every driver emits and the engine consumes.
///
/// `targetContext` is pre-filled when the driver can inspect cheaply at event
/// time; otherwise the engine pulls it via `ElementInspector`.
public struct RawInputEvent: Identifiable, Codable, Sendable, Equatable {
    /// The complete vocabulary of user actions across all future drivers.
    public enum Kind: Codable, Sendable, Equatable {
        // MARK: Emitted in Phase 1
        case mouseClick(button: MouseButton, clickCount: Int)
        case keyStroke(key: String, code: Int?, modifiers: KeyModifiers)
        case hotkeyCombo(combo: String)
        case userGesture(name: String, action: GestureAction)

        // MARK: Emitted since Phase 2
        /// Drag selection capture (distance/duration thresholds applied driver-side).
        case mouseDrag(start: Point2D, end: Point2D)
        /// App focus switches as intermediate representations.
        case appSwitch(bundleId: String?, appName: String, windowTitle: String)
        /// Terminal `pwd`/command introspection.
        case terminalCommand(command: String, workingDir: String?, exitCode: Int32?)
        /// Phase 4 — web page navigation steps.
        case pageNavigation(url: String, title: String?)
    }

    public var id: UUID
    public var timestamp: Date
    public var kind: Kind
    public var location: Point2D?
    public var targetContext: RawElementContext?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: Kind,
        location: Point2D? = nil,
        targetContext: RawElementContext? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.location = location
        self.targetContext = targetContext
    }
}

/// Presentation-side notice for a detected smart gesture.
///
/// Built by the engine from `.userGesture` events so `WorkflowController`
/// (HUD notice, Settings live-test) never has to touch a driver.
public struct RawGestureNotice: Codable, Sendable, Equatable {
    public var name: String
    public var action: GestureAction
    public var location: Point2D
    public var timestamp: Date

    public init(name: String, action: GestureAction, location: Point2D = .zero, timestamp: Date = Date()) {
        self.name = name
        self.action = action
        self.location = location
        self.timestamp = timestamp
    }
}

/// A decoded keyboard chord in platform-neutral IR terms.
///
/// Produced by `HotkeyRecognizer` (macOS driver layer) and consumed by the
/// engine / `StepFactory` to synthesize `.keyPress` documentation steps.
/// Living in `Events/` keeps the recognizer's output Foundation-only IR, so
/// `Pipeline/` never has to see an `NSEvent`.
public struct HotkeyChord: Codable, Sendable, Equatable {
    /// W3C `KeyboardEvent.key` name, e.g. `"s"`, `"Escape"`, `"ArrowDown"`.
    public var key: String
    /// Human-readable key label used in combo rendering, e.g. `"S"`, `"Space"`.
    public var displayKey: String
    /// macOS virtual key code when the platform provided one.
    public var code: Int?
    public var modifiers: KeyModifiers

    public init(key: String, displayKey: String? = nil, code: Int? = nil, modifiers: KeyModifiers = []) {
        self.key = key
        self.displayKey = displayKey ?? HotkeyChord.defaultDisplayKey(for: key)
        self.code = code
        self.modifiers = modifiers
    }

    /// Rendered combo in canonical macOS order, e.g. `⌘⇧P`, `Escape`, `⌥Space`.
    public var combo: String {
        modifiers.symbolString + displayKey
    }

    /// `true` when the chord involves at least one non-modifier modifier.
    public var isShortcut: Bool {
        !modifiers.isEmpty
    }

    /// `"S"` for letters, `"Space"` for the space key, W3C name otherwise.
    public static func defaultDisplayKey(for key: String) -> String {
        if key == " " { return "Space" }
        if key.count == 1, let scalar = key.unicodeScalars.first,
           CharacterSet.alphanumerics.contains(scalar) {
            return key.uppercased()
        }
        return key
    }
}
