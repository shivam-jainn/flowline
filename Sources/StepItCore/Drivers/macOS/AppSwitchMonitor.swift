import Foundation
import AppKit

/// Observes frontmost-application changes for the recording pipeline
/// (Phase 2, T8 / B7).
///
/// Emits `NSWorkspace.didActivateApplicationNotification` as raw
/// (bundleId, appName, pid) tuples; `MacCaptureDriver` normalizes them into
/// `.appSwitch` IR events. Owned by the driver, never a singleton.
public final class AppSwitchMonitor: @unchecked Sendable {

    /// (bundleId, localized app name, process identifier).
    public var onAppActivated: ((String?, String, Int32) -> Void)?

    private var observer: NSObjectProtocol?

    public init() {}

    public func start() {
        guard observer == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        observer = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            let bundleId = app.bundleIdentifier
            let name = app.localizedName ?? bundleId ?? "Unknown App"
            self?.onAppActivated?(bundleId, name, app.processIdentifier)
        }
    }

    public func stop() {
        guard let observer = observer else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(observer)
        self.observer = nil
    }

    deinit {
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
