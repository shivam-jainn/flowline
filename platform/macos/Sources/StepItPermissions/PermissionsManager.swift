import Foundation
import ApplicationServices
import CoreGraphics

public enum PermissionStatus: String, Sendable {
    case granted
    case denied
    case notDetermined
}

public final class PermissionsManager: Permissions, @unchecked Sendable {
    public static let shared = PermissionsManager()
    
    public init() {}
    
    // MARK: - Permissions protocol
    
    public func status(for kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .screenRecording:
            return hasScreenRecordingPermission ? .granted : .denied
        case .accessibility:
            return hasAccessibilityPermission ? .granted : .denied
        }
    }
    
    // MARK: - Screen Recording
    
    public var hasScreenRecordingPermission: Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }
    
    @discardableResult
    public func requestScreenRecordingPermission() -> Bool {
        if #available(macOS 10.15, *) {
            return CGRequestScreenCaptureAccess()
        }
        return true
    }
    
    public func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            openSystemURL(url)
        }
    }
    
    // MARK: - Accessibility
    
    public var hasAccessibilityPermission: Bool {
        return AXIsProcessTrusted()
    }
    
    @discardableResult
    public func requestAccessibilityPermission() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options)
    }
    
    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            openSystemURL(url)
        }
    }
    
    // MARK: - Combined Status
    
    public var allPermissionsGranted: Bool {
        return hasScreenRecordingPermission && hasAccessibilityPermission
    }
    
    // MARK: - Private
    
    /// AppKit-free equivalent of the shared-workspace open-URL call (R/M1-06:
    /// zero AppKit in this target). Opens the same URL via `/usr/bin/open`.
    private func openSystemURL(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        try? process.run()
    }
}
