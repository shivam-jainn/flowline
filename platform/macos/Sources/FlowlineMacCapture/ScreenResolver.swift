import AppKit
import CoreGraphics
import Foundation

/// Multi-display screen resolution.
///
/// Every capture / overlay / gesture call site used to reach for the primary
/// display, so anything on a secondary monitor captured the wrong display
/// (or missed gestures entirely). This is the single place that maps a
/// global Cocoa point to its display.
///
/// Pure geometry (`frameContaining`, `nearestFrame`) is `NSScreen`-free so
/// unit tests can feed synthetic frames without displays attached.
///
/// Threading: `NSScreen.screens` is main-thread-only, but capture timers run
/// on background queues at 12 Hz. Display frames + scales are cached and
/// refreshed on screen-parameter changes, so hot paths never hop to main.
/// Only the `NSScreen`-object accessors (`screenContaining`,
/// `screenForMouse`) require the main thread (the HUD calls them from
/// `@MainActor`).
public enum ScreenResolver {

    // MARK: - Pure geometry (testable, no AppKit state)

    /// Exact hit: first frame containing the point.
    public static func frameContaining(_ point: CGPoint, in frames: [CGRect]) -> CGRect? {
        frames.first { $0.contains(point) }
    }

    /// Distance from a point to a rect (0 when inside).
    public static func distanceFromPoint(_ point: CGPoint, to rect: CGRect) -> CGFloat {
        guard !rect.isNull && !rect.isEmpty else { return .greatestFiniteMagnitude }
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    /// Closest frame by edge distance. Used when the point sits in a gap
    /// between displays (bezel dead-zone) or outside all frames.
    public static func nearestFrame(to point: CGPoint, in frames: [CGRect]) -> CGRect? {
        let valid = frames.filter { !$0.isNull && !$0.isEmpty }
        guard !valid.isEmpty else { return nil }
        return valid.min { distanceFromPoint(point, to: $0) < distanceFromPoint(point, to: $1) }
    }

    /// Containing frame, else nearest, else nil.
    public static func resolveFrame(for point: CGPoint, in frames: [CGRect]) -> CGRect? {
        frameContaining(point, in: frames) ?? nearestFrame(to: point, in: frames)
    }

    // MARK: - Cached display snapshot (main-thread reads, lock-free hits)

    private struct DisplayInfo: Equatable {
        var frame: CGRect
        var scale: CGFloat
    }

    private static let cacheLock = NSLock()
    private static var cached: [DisplayInfo]?
    private static var observing = false

    private static func ensureObserving() {
        let install: Bool = cacheLock.withLock {
            if observing { return false }
            observing = true
            return true
        }
        guard install else { return }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            cacheLock.withLock { cached = nil }
            // Pre-warm on main so background callers rarely pay for a hop.
            if Thread.isMainThread {
                _ = refresh()
            } else {
                DispatchQueue.main.async { _ = refresh() }
            }
        }
    }

    /// Reads `NSScreen.screens` on main and caches frames + scales.
    @discardableResult
    private static func refresh() -> [DisplayInfo] {
        let displays: [DisplayInfo]
        if Thread.isMainThread {
            displays = NSScreen.screens.map { DisplayInfo(frame: $0.frame, scale: $0.backingScaleFactor) }
        } else {
            displays = DispatchQueue.main.sync {
                NSScreen.screens.map { DisplayInfo(frame: $0.frame, scale: $0.backingScaleFactor) }
            }
        }
        cacheLock.withLock { cached = displays }
        return displays
    }

    private static func displaysSnapshot() -> [DisplayInfo] {
        ensureObserving()
        if let hit = cacheLock.withLock({ cached }) { return hit }
        return refresh()
    }

    // MARK: - Frame / scale resolution (safe from any thread)

    /// Capture rect for a click point. Nil when headless (callers bail out).
    public static func captureFrame(at point: CGPoint) -> CGRect? {
        let displays = displaysSnapshot()
        guard !displays.isEmpty else { return nil }
        return resolveFrame(for: point, in: displays.map(\.frame))
    }

    /// Capture rect when there is no point (buffer ticks): the display under
    /// the cursor.
    public static func captureFrameForMouse() -> CGRect? {
        captureFrame(at: NSEvent.mouseLocation)
    }

    /// Backing scale for a point's display, else the first display, else 1.
    public static func scaleFactor(for point: CGPoint?) -> CGFloat {
        let displays = displaysSnapshot()
        guard !displays.isEmpty else { return 1 }
        if let point, let frame = resolveFrame(for: point, in: displays.map(\.frame)),
           let match = displays.first(where: { $0.frame == frame }) {
            return match.scale
        }
        return displays[0].scale
    }

    // MARK: - NSScreen objects (main thread only; HUD use)

    /// Display containing the point, else the nearest (gap / bezel), else
    /// main. Nil when headless or off-main.
    @MainActor
    public static func screenContaining(_ point: CGPoint) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        if let exact = screens.first(where: { $0.frame.contains(point) }) {
            return exact
        }
        let frames = screens.map(\.frame)
        guard let target = nearestFrame(to: point, in: frames) else { return nil }
        return screens.first { $0.frame == target } ?? NSScreen.main
    }

    /// Display under the cursor right now (main thread only).
    @MainActor
    public static func screenForMouse() -> NSScreen? {
        screenContaining(NSEvent.mouseLocation)
    }
}
