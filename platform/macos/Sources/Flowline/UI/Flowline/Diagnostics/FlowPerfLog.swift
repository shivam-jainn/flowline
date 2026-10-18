import Foundation
import os

/// Lightweight `os_log` + `os_signpost` wrapper for Flowline drag-and-drop
/// animation debugging. macOS 14 APIs only, no dependencies.
///
/// Subsystem `com.flowline.app`, categories: `dnd`, `proximity`,
/// `scroll`, `haptics`. Intervals appear in Instruments' Points of Interest
/// track; details go to the unified log (`log stream --predicate
/// 'subsystem == "com.flowline.app"'`).
///
/// Zero-cost when disabled: every entry point returns before touching its
/// arguments, and all message payloads are `@autoclosure`, so string
/// interpolation never runs on the hot path (NSTrackingArea `mouseMoved`,
/// `dropUpdated` pumps).
public enum FlowPerfLog {
    public static let subsystem = "com.flowline.app"

    /// Runtime toggle. DEBUG builds default ON; Release builds default OFF
    /// (still toggleable for release-candidate profiling).
    public static let toggleKey = "FlowlinePerfLogging"

    public enum Category: String, CaseIterable, Sendable {
        case dnd, proximity, scroll, haptics
        var log: OSLog { FlowPerfLog.log(for: self) }
    }

    /// Canonical interval/event names — keep these stable so Instruments
    /// lanes stay comparable across recordings.
    public enum Interval {
        public static let dragSession: StaticString = "DragSession"
        public static let proximityResolve: StaticString = "ProximityResolve"
        public static let scrollNudge: StaticString = "ScrollNudge"
        public static let dropApply: StaticString = "DropApply"
    }

    private static let dndLog = OSLog(subsystem: subsystem, category: "dnd")
    private static let proximityLog = OSLog(subsystem: subsystem, category: "proximity")
    private static let scrollLog = OSLog(subsystem: subsystem, category: "scroll")
    private static let hapticsLog = OSLog(subsystem: subsystem, category: "haptics")

    private static func log(for category: Category) -> OSLog {
        switch category {
        case .dnd: dndLog
        case .proximity: proximityLog
        case .scroll: scrollLog
        case .haptics: hapticsLog
        }
    }

    /// Compile-time kill switch (DEBUG-only default) + runtime override.
    /// Launch-arg `-FlowlinePerfLogging NO` (or YES on Release) beats the default.
    public static var isEnabled: Bool {
#if DEBUG
        if UserDefaults.standard.object(forKey: toggleKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: toggleKey)
#else
        return UserDefaults.standard.bool(forKey: toggleKey)
#endif
    }

    public static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: toggleKey)
    }

    // MARK: - Raw signposts

    /// Begin an interval; pass the returned ID to `signpostEnd` to pair it.
    @discardableResult
    public static func signpostBegin(_ name: StaticString, _ category: Category) -> OSSignpostID {
        guard isEnabled else { return .invalid }
        let id = OSSignpostID(log: category.log)
        os_signpost(.begin, log: category.log, name: name, signpostID: id)
        return id
    }

    /// End an interval. Pass the ID from `signpostBegin` for pairing;
    /// the default is for fire-and-forget ends.
    public static func signpostEnd(_ name: StaticString, _ category: Category, id: OSSignpostID = .exclusive) {
        guard isEnabled else { return }
        os_signpost(.end, log: category.log, name: name, signpostID: id)
    }

    /// One-shot point event. `values` is never evaluated when disabled.
    public static func event(
        _ name: StaticString,
        values: @autoclosure () -> [String],
        category: Category = .dnd
    ) {
        guard isEnabled else { return }
        os_signpost(.event, log: category.log, name: name)
        let text = "\(String(describing: name)): \(values().joined(separator: " "))"
        os_log(.debug, log: category.log, "%{public}@", text as NSString)
    }

    // MARK: - Drag-session helpers (all main-thread; gutter calls are)

    private static var activeDragSignpost: OSSignpostID?
    private static var dragFlips = 0

    /// Open a `DragSession` interval. Returns its signpost ID (also stored
    /// internally so `endDrag` pairs without the caller threading state).
    @discardableResult
    public static func beginDrag(id: @autoclosure () -> String) -> OSSignpostID {
        guard isEnabled else { return .invalid }
        dragFlips = 0
        let sid = signpostBegin(Interval.dragSession, .dnd)
        activeDragSignpost = sid
        let text = "begin id=\(id())"
        os_log(.debug, log: Category.dnd.log, "%{public}@", text as NSString)
        return sid
    }

    /// Record a drop-target change. Feeds the probe's flips/sec counter.
    public static func updateTarget(from: @autoclosure () -> String?, to: @autoclosure () -> String?) {
        guard isEnabled else { return }
        dragFlips += 1
        let text = "target from=\(from() ?? "-") to=\(to() ?? "-") flips=\(dragFlips)"
        os_signpost(.event, log: Category.dnd.log, name: "TargetFlip")
        os_log(.debug, log: Category.dnd.log, "%{public}@", text as NSString)
        GutterProbeStats.shared.recordTargetFlip()
    }

    /// Close the `DragSession` interval. `frames` defaults to the internally
    /// counted target flips, so callers can omit it: `endDrag(id: id, dropped: true)`.
    public static func endDrag(id: @autoclosure () -> String, frames: Int = -1, dropped: Bool) {
        guard isEnabled else { return }
        let total = frames >= 0 ? frames : dragFlips
        if let sid = activeDragSignpost {
            os_signpost(.end, log: Category.dnd.log, name: Interval.dragSession, signpostID: sid)
            activeDragSignpost = nil
        }
        let text = "end id=\(id()) flips=\(total) dropped=\(dropped)"
        os_log(.debug, log: Category.dnd.log, "%{public}@", text as NSString)
        dragFlips = 0
    }

    /// Timed proximity-resolve sample. Feeds the probe's resolves/sec + last-ms.
    public static func proximityResolve(durationMs: Double, gapCount: Int) {
        guard isEnabled else { return }
        let text = String(format: "resolve %.2fms gaps=%d", durationMs, gapCount)
        os_signpost(.event, log: Category.proximity.log, name: Interval.proximityResolve)
        os_log(.debug, log: Category.proximity.log, "%{public}@", text as NSString)
        GutterProbeStats.shared.recordProximityResolve(durationMs: durationMs)
    }

    /// Zero-overhead timed wrapper: runs `body` untimed when disabled.
    public static func measureProximityResolve<T>(gapCount: Int, _ body: () -> T) -> T {
        guard isEnabled else { return body() }
        let start = ContinuousClock().now
        let result = body()
        let el = ContinuousClock().now - start
        let ms = Double(el.components.seconds) * 1_000 + Double(el.components.attoseconds) / 1e15
        proximityResolve(durationMs: ms, gapCount: gapCount)
        return result
    }

    /// Edge-nudge sample (call at the `dx != 0` site in `nudge(index:)`).
    public static func scrollNudge(dx: CGFloat) {
        guard isEnabled else { return }
        let text = String(format: "nudge dx=%.1f", Double(dx))
        os_signpost(.event, log: Category.scroll.log, name: Interval.scrollNudge)
        os_log(.debug, log: Category.scroll.log, "%{public}@", text as NSString)
    }

    /// Haptic tick sample (haptics always play; this only observes).
    public static func haptic(_ pattern: @autoclosure () -> String) {
        guard isEnabled else { return }
        let text = "haptic \(pattern())"
        os_signpost(.event, log: Category.haptics.log, name: "Haptic")
        os_log(.debug, log: Category.haptics.log, "%{public}@", text as NSString)
    }
}
