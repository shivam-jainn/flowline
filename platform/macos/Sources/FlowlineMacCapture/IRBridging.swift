import Foundation
import FlowlineIR
import FlowlinePipeline
import AppKit

// MARK: - macOS ↔ IR bridging
//
// Every conversion between platform-native types (`CGPoint`, `CGRect`,
// `NSEvent`, `ElementInspectionResult`) and the platform-neutral IR lives here,
// inside `Drivers/macOS/`. `Events/`, `Engine/` and `Pipeline/` never see an
// AppKit type.

extension Point2D {
    /// From a Cocoa screen point (origin bottom-left of the primary screen).
    public init(_ point: CGPoint) {
        self.init(x: Double(point.x), y: Double(point.y))
    }
}

extension CGPoint {
    public init(_ point: Point2D) {
        self.init(x: point.x, y: point.y)
    }
}

extension ElementRect {
    public init(_ rect: CGRect) {
        self.init(x: Double(rect.origin.x), y: Double(rect.origin.y), width: Double(rect.width), height: Double(rect.height))
    }
}

extension MouseButton {
    /// Decodes a mouse-down `NSEvent` into an IR button.
    public init?(event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            self = .left
        case .rightMouseDown:
            self = .right
        case .otherMouseDown:
            guard let button = MouseButton(buttonNumber: event.buttonNumber) else { return nil }
            self = button
        default:
            return nil
        }
    }
}

extension KeyModifiers {
    public init(_ flags: NSEvent.ModifierFlags) {
        var modifiers: KeyModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.function) { modifiers.insert(.function) }
        self = modifiers
    }
}

extension RawElementContext {
    /// Converts an AX inspection result into the IR, filling the Phase 1
    /// selector fallbacks (`.accessibility`, then `.coordinates`).
    public init(_ result: ElementInspectionResult) {
        var selectors: [ElementSelector] = []

        if let query = Self.accessibilityQuery(for: result) {
            selectors.append(ElementSelector(kind: .accessibility, value: query, priority: 0))
        }
        if let bounds = result.elementBounds {
            selectors.append(ElementSelector(
                kind: .coordinates,
                value: "\(bounds.x),\(bounds.y)",
                priority: 1
            ))
        }

        self.init(
            appName: result.appName,
            bundleIdentifier: result.bundleIdentifier,
            windowTitle: result.windowTitle,
            role: result.role,
            subrole: result.subrole,
            title: result.title,
            value: result.value,
            roleDescription: result.roleDescription,
            isSecure: result.isSecure,
            boundingBox: result.elementBounds,
            windowBounds: result.windowBounds,
            selectors: selectors
        )
    }

    /// Best-effort AX selector string for the Phase 3 automation compilers.
    static func accessibilityQuery(for result: ElementInspectionResult) -> String? {
        var parts: [String] = []
        if let role = result.role, !role.isEmpty {
            parts.append("role=\"\(role)\"")
        }
        if let title = result.title, !title.isEmpty {
            parts.append("title=\"\(title)\"")
        } else if let value = result.value, !value.isEmpty {
            parts.append("value=\"\(value)\"")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }
}

extension RawInputEvent {
    /// Converts a gesture notice into a `.userGesture` IR event.
    public static func userGesture(_ notice: GestureEventNotice) -> RawInputEvent {
        RawInputEvent(
            timestamp: notice.timestamp,
            kind: .userGesture(name: notice.gestureName, action: notice.action),
            location: Point2D(notice.location)
        )
    }
}
