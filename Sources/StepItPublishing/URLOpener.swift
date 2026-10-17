import Foundation

/// URL-opening capability (Phase R §4). Replaces `NSWorkspace.open` in
/// `PublishingCoordinator` (m1-06 removes the AppKit import).
public protocol URLOpener: Sendable {
    func open(_ url: URL)
    func revealInFinder(_ url: URL)
}

public struct DefaultURLOpener: URLOpener {
    public init() {}
    public func open(_ url: URL) {}
    public func revealInFinder(_ url: URL) {}
}
