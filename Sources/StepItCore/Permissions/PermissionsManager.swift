import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

public enum PermissionStatus: String, Sendable {
    case granted
    case denied
    case notDetermined
}

public final class PermissionsManager: @unchecked Sendable {
    public static let shared = PermissionsManager()
    
    public init() {}
    
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
            NSWorkspace.shared.open(url)
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
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Combined Status
    
    public var allPermissionsGranted: Bool {
        return hasScreenRecordingPermission && hasAccessibilityPermission
    }
}
