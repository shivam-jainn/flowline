import Foundation

/// URL-opening capability (Phase R §4). Replaces `NSWorkspace.open` in
/// `PublishingCoordinator` (m1-06 removes the AppKit import).
public protocol URLOpener: Sendable {
    func open(_ url: URL)
    func revealInFinder(_ url: URL)
}

/// Live opener without AppKit: shells out to `/usr/bin/open`
/// (`open <url>`, `open -R <path>` reveals in Finder).
public struct DefaultURLOpener: URLOpener {
    public init() {}

    public func open(_ url: URL) {
        runOpen(arguments: [url.absoluteString])
    }

    public func revealInFinder(_ url: URL) {
        if url.isFileURL {
            runOpen(arguments: ["-R", url.path])
        } else {
            runOpen(arguments: [url.absoluteString])
        }
    }

    private func runOpen(arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        try? process.run()
    }
}
