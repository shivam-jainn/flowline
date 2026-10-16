import Foundation
import AppKit

/// macOS global/local `NSEvent` monitors.
///
/// Phase 1: this class is a **pure event producer**. All gesture routing and
/// typing aggregation moved out — `MacCaptureDriver` wires the raw callbacks
/// and normalizes them into IR events. The class is owned by the driver, never
/// a hidden singleton.
///
/// Callbacks fire on the thread AppKit delivers the event on; the engine
/// serializes everything through its actor.
public final class EventMonitor: @unchecked Sendable {

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalKeyMonitor: Any?

    // MARK: - Raw callback surface (IR-agnostic, AppKit-typed)

    /// Mouse button pressed: (button, clickCount, point).
    /// Unknown/exotic buttons (> #2) are intentionally not reported — Phase 1
    /// parity keeps left/right/middle only.
    public var onMouseDown: ((MouseButton, Int, CGPoint) -> Void)?
    /// Mouse moved or dragged: point.
    public var onMouseMove: ((CGPoint) -> Void)?
    /// Any mouse button released.
    public var onMouseUp: (() -> Void)?
    /// Decoded keystroke: (W3C key name, virtual key code, modifiers).
    /// Only keys the pre-Phase-1 monitor fed into typing aggregation are
    /// emitted (`Return`, `Backspace`, `Tab`, `Ctrl+C`, printables).
    public var onKeyStroke: ((String, Int?, KeyModifiers) -> Void)?
    /// Toggle-recording hotkey (`⌥Space`) was pressed.
    public var onHotkeyCombo: ((String) -> Void)?

    private(set) public var isMonitoring = false

    public init() {}

    public func start() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Global mouse monitor for clicks & gestures outside StepIt windows
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [
                .leftMouseDown, .rightMouseDown, .otherMouseDown,
                .leftMouseUp, .rightMouseUp,
                .mouseMoved, .leftMouseDragged, .rightMouseDragged
            ]
        ) { [weak self] event in
            self?.handleMouseEvent(event)
        }

        // Global key monitor for shortcuts (Option + Space) & text input
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown]
        ) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // Local monitor so keystrokes / clicks within StepIt / Playground are also captured
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { [weak self] event in
            if event.type == .keyDown {
                self?.handleKeyEvent(event)
            } else {
                self?.handleMouseEvent(event)
            }
            return event
        }
    }

    public func stop() {
        guard isMonitoring else { return }
        isMonitoring = false

        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
    }

    // MARK: - Decoding (parity with pre-Phase-1 semantics)

    private func handleMouseEvent(_ event: NSEvent) {
        // AppKit coordinates: origin is at bottom-left of primary screen
        // NSEvent.mouseLocation gives global screen coordinate in Cocoa points
        let mouseLocation = NSEvent.mouseLocation

        switch event.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            onMouseMove?(mouseLocation)

        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            onMouseUp?()

        case .otherMouseDown, .leftMouseDown, .rightMouseDown:
            guard let button = MouseButton(buttonNumber: event.buttonNumber) else { return }
            onMouseDown?(button, event.clickCount, mouseLocation)

        default:
            break
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Option + Space check:
        // keyCode 49 is Space in US ANSI keyboard
        if event.keyCode == 49 && event.modifierFlags.contains(.option) {
            onHotkeyCombo?(KeyModifiers.option.symbolString + "Space")
            return
        }

        let modifiers = KeyModifiers(event.modifierFlags)

        // Control + C (Terminal Interrupt SIGINT)
        if event.modifierFlags.contains(.control) && (event.keyCode == 8 || event.charactersIgnoringModifiers?.lowercased() == "c") {
            onKeyStroke?("c", 8, modifiers)
            return
        }

        // Command chords stay out of typing aggregation (Phase 2 owns discrete
        // hotkey steps — parity: the old monitor dropped them here).
        guard !event.modifierFlags.contains(.command) else { return }

        // Decode to the W3C `KeyboardEvent.key` vocabulary: Return(36/76),
        // Backspace(51), Tab(48), Space(49), printable characters.
        guard let key = KeyCodeMap.w3cKeyName(for: event.keyCode, characters: event.characters) else { return }
        onKeyStroke?(key, Int(event.keyCode), modifiers)
    }
}
