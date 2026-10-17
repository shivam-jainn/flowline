import Foundation
import StepItIR
import StepItPipeline
import StepItEngine
@testable import StepItCore

/// One-liners for readable engine tests.
enum RawEventFixtures {

    static func ctx(
        app: String = "Safari",
        bundleId: String? = "com.apple.Safari",
        windowTitle: String = "",
        role: String? = nil,
        subrole: String? = nil,
        title: String? = nil,
        value: String? = nil,
        isSecure: Bool = false,
        bounds: ElementRect? = nil,
        windowBounds: ElementRect? = nil
    ) -> RawElementContext {
        RawElementContext(
            appName: app,
            bundleIdentifier: bundleId,
            windowTitle: windowTitle,
            role: role,
            subrole: subrole,
            title: title,
            value: value,
            isSecure: isSecure,
            boundingBox: bounds,
            windowBounds: windowBounds
        )
    }

    static func click(
        at point: Point2D = Point2D(x: 100, y: 100),
        button: MouseButton = .left,
        clickCount: Int = 1,
        timestamp: Date = Date(),
        context: RawElementContext? = nil
    ) -> RawInputEvent {
        RawInputEvent(
            timestamp: timestamp,
            kind: .mouseClick(button: button, clickCount: clickCount),
            location: point,
            targetContext: context
        )
    }

    static func hotkey(_ combo: String = "⌥Space", timestamp: Date = Date()) -> RawInputEvent {
        RawInputEvent(timestamp: timestamp, kind: .hotkeyCombo(combo: combo))
    }

    static func gesture(
        _ name: String = "Mouse Shake",
        action: GestureAction,
        location: Point2D = Point2D(x: 200, y: 200),
        timestamp: Date = Date()
    ) -> RawInputEvent {
        RawInputEvent(
            timestamp: timestamp,
            kind: .userGesture(name: name, action: action),
            location: location
        )
    }

    /// Builds a keystroke sequence: one `.keyStroke` per character, in order.
    static func typing(
        _ text: String,
        at point: Point2D = Point2D(x: 100, y: 100),
        timestamp: Date = Date()
    ) -> [RawInputEvent] {
        text.map { character in
            RawInputEvent(
                timestamp: timestamp,
                kind: .keyStroke(key: String(character), code: nil, modifiers: []),
                location: point
            )
        }
    }

    static func key(
        _ key: String,
        modifiers: KeyModifiers = [],
        at point: Point2D = Point2D(x: 100, y: 100),
        timestamp: Date = Date()
    ) -> RawInputEvent {
        RawInputEvent(
            timestamp: timestamp,
            kind: .keyStroke(key: key, code: nil, modifiers: modifiers),
            location: point
        )
    }
}
