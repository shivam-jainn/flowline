import Foundation
import StepItIR
import StepItPipeline
import AppKit

/// macOS global/local `NSEvent` monitors.
///
/// Phase 1: this class is a **pure event producer**. All gesture routing and
/// typing aggregation moved out — `MacCaptureDriver` wires the raw callbacks
/// and normalizes them into IR events. The class is owned by the driver, never
/// a hidden singleton.
///
/// Phase 2: keyboard events are classified by `HotkeyRecognizer`:
/// - the recorder toggle combo is consumed as a control event;
/// - `⌘`/`⌃` workflow chords (once dropped by a blanket guard) and navigation
///   keys (`Esc`, `Tab`, arrows, F-keys) are emitted as keystrokes;
/// - system combos (`⌘Tab`, `⌘Space`) and key auto-repeats are consumed.
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
    /// Mouse button released: (button, clickCount, point). Phase 2 defers click
    /// emission to the release so `MouseDragDetector` can classify the gesture.
    public var onMouseUp: ((MouseButton?, Int, CGPoint) -> Void)?
    /// Decoded keystroke: (W3C key name, virtual key code, modifiers).
    /// Emitted for typing, workflow chords (`⌘S`) and navigation keys (`Esc`).
    public var onKeyStroke: ((String, Int?, KeyModifiers) -> Void)?
    /// Toggle-recording hotkey (`⌥Space`) was pressed — consumed, never recorded.
    public var onHotkeyCombo: ((String) -> Void)?
    /// Phase 2 policy table shared with the engine. Updated through
    /// `MacCaptureDriver.updateHotkeySettings` (single-owner routing).
    public var recognizer = HotkeyRecognizer()

    private(set) public var isMonitoring = false

    public init() {}

    public func start() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Global mouse monitor for clicks & gestures outside StepIt windows
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [
                .leftMouseDown, .rightMouseDown, .otherMouseDown,
                .leftMouseUp, .rightMouseUp, .otherMouseUp,
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
            matching: [
                .leftMouseDown, .rightMouseDown, .otherMouseDown,
                .leftMouseUp, .rightMouseUp, .otherMouseUp,
                .keyDown
            ]
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

    // MARK: - Decoding

    private func handleMouseEvent(_ event: NSEvent) {
        // AppKit coordinates: origin is at bottom-left of primary screen
        // NSEvent.mouseLocation gives global screen coordinate in Cocoa points
        let mouseLocation = NSEvent.mouseLocation

        switch event.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            onMouseMove?(mouseLocation)

        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            onMouseUp?(MouseButton(buttonNumber: event.buttonNumber), event.clickCount, mouseLocation)

        case .otherMouseDown, .leftMouseDown, .rightMouseDown:
            guard let button = MouseButton(buttonNumber: event.buttonNumber) else { return }
            onMouseDown?(button, event.clickCount, mouseLocation)

        default:
            break
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let modifiers = KeyModifiers(event.modifierFlags)

        let decision = recognizer.evaluate(
            keyCode: event.keyCode,
            characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifiers: modifiers
        )

        switch decision {
        case .toggleRecording(let combo):
            onHotkeyCombo?(combo)

        case .systemConsumed, .ignored:
            // ⌘Tab / ⌘Space / modifier keys / disabled capture classes.
            return

        case .workflowShortcut(let chord), .navigationKey(let chord):
            // One step per physical press — never one per auto-repeat frame.
            guard !event.isARepeat else { return }
            onKeyStroke?(chord.key, chord.code, chord.modifiers)

        case .textInput(let key, let modifiers):
            onKeyStroke?(key, Int(event.keyCode), modifiers)
        }
    }
}
