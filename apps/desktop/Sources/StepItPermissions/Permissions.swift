import Foundation

/// Capability gated by a macOS system permission prompt.
public enum PermissionKind: String, Sendable, CaseIterable {
    case screenRecording
    case accessibility
}

/// Prompt-free decision derived from a raw permission status.
public enum PermissionDecision: String, Sendable, Equatable {
    case granted
    case denied
    case promptRequired
}

/// Pure decision function: status → decision. No prompts, no side effects.
public func permissionDecision(for status: PermissionStatus) -> PermissionDecision {
    switch status {
    case .granted:
        return .granted
    case .denied:
        return .denied
    case .notDetermined:
        return .promptRequired
    }
}

/// Permission-checking contract (R/M1-06). The macOS implementation lives in
/// `PermissionsManager`; callers depend on this protocol, never on AppKit.
public protocol Permissions: Sendable {
    func status(for kind: PermissionKind) -> PermissionStatus
    var allPermissionsGranted: Bool { get }
}
