import Foundation
import FlowlineIR

// MARK: - Focus-aware semantic segmentation + delayed commit (Swift twin of
// `core/crates/flowline_engine/src/segmentation.rs`).
//
// Scoring contract:
// - bundle change → 0.95
// - windowID/title change → 0.85
// - AX element/role change → 0.70
// - only cut on role change or window/bundle; popups never cut.
//
// Confidence contract:
// `score = 0.35*focus + 0.25*gap + 0.15*ret + 0.15*clipboard + 0.10*velocity`
// CUT when `> 0.6`, JOIN when `< 0.4`, else provisional.
//
// Delayed commit: provisional emit immediately, confirm at +400 ms default
// (150 ms clicks, 500 ms typing), max 2 × +200 ms extensions on a
// contradicting event. Revision history logs `v1 provisional → v2 confirmed`.

public enum FocusSegmentation {
    public static let flapRevertMillis: TimeInterval = 0.8
    public static let flapMaxMiddleEvents = 3
    public static let oscillationWindow: TimeInterval = 2.0
    public static let limboSettle: TimeInterval = 0.4

    public static let confirmDefault: TimeInterval = 0.4
    public static let confirmClick: TimeInterval = 0.15
    public static let confirmTyping: TimeInterval = 0.5
    public static let extensionStep: TimeInterval = 0.2
    public static let maxExtensions = 2

    public static let cutThreshold = 0.6
    public static let joinThreshold = 0.4

    /// Window-aware dedup key: app identity *plus* window/title, never
    /// appName alone (over-join fix).
    public static func appSwitchKey(appName: String, bundleId: String?, windowTitle: String) -> String {
        "\(appName)|\(bundleId ?? "")|\(windowTitle)"
    }

    public static func isPopup(_ ctx: RawElementContext) -> Bool {
        if let role = ctx.role {
            switch role {
            case "AXMenu", "AXMenuBarItem", "AXMenuItem", "AXPopover", "AXSheet", "AXDrawer", "AXPopUpButton":
                return true
            default:
                break
            }
            let lower = role.lowercased()
            if lower.contains("popup") || lower.contains("popover") || lower.contains("menu") {
                return true
            }
        }
        if let desc = ctx.roleDescription?.lowercased(),
           desc.contains("popup") || desc.contains("popover") || desc.contains("menu") {
            return true
        }
        return false
    }

    /// Bundle 0.95 / window(title) 0.85 / AX role 0.70, else 0.0.
    /// Pure popup deltas never cut.
    public static func cutScore(prev: RawElementContext, curr: RawElementContext) -> Double {
        if prev.bundleIdentifier != curr.bundleIdentifier { return 0.95 }
        if prev.appName != curr.appName { return 0.95 }
        if prev.windowTitle != curr.windowTitle { return 0.85 }
        if prev.windowBounds != curr.windowBounds,
           prev.windowBounds != nil || curr.windowBounds != nil {
            return 0.85
        }
        if prev.role != curr.role || prev.subrole != curr.subrole {
            if isPopup(curr) || isPopup(prev) { return 0.0 }
            return 0.70
        }
        if isPopup(curr) && !isPopup(prev) { return 0.0 }
        return 0.0
    }

    public static func shouldCut(score: Double) -> Bool { score >= 0.70 }

    public enum Decision { case cut, join, provisional }

    public static func confidence(focus: Double, gap: Double, ret: Double, clipboard: Double, velocity: Double) -> Double {
        0.35 * focus + 0.25 * gap + 0.15 * ret + 0.15 * clipboard + 0.10 * velocity
    }

    public static func decide(_ score: Double) -> Decision {
        if score > cutThreshold { return .cut }
        if score < joinThreshold { return .join }
        return .provisional
    }

    public static func gapHysteresis(gap: TimeInterval, debounce: TimeInterval) -> Double {
        guard debounce > 0 else { return 1.0 }
        if gap >= 2 * debounce { return 1.0 }
        if gap >= debounce { return 0.7 }
        if gap >= debounce / 2 { return 0.4 }
        return 0.1
    }

    public static func velocityScore(eventsPerSec: Double) -> Double {
        if eventsPerSec >= 5 { return 1.0 }
        if eventsPerSec >= 2 { return 0.6 }
        return 0.2
    }
}

/// One provisionally emitted step awaiting confirmation.
public struct PendingCommit: Equatable {
    public var stepID: String
    public var provisionalAt: Date
    public var confirmAt: Date
    public var extensions: Int = 0
    public var confirmed = false

    public mutating func extendOnContradiction() -> Bool {
        guard !confirmed, extensions < FocusSegmentation.maxExtensions else { return false }
        extensions += 1
        confirmAt = confirmAt.addingTimeInterval(FocusSegmentation.extensionStep)
        return true
    }
}

/// Flap-tracker verdict for an incoming switch.
public enum FlapAction { case emit, revert, holdLimbo }

extension RecorderWorkflowEngine {
    /// Provisional emit bookkeeping: visible immediately, confirmed later.
    /// Logs `v1 provisional → v2 confirmed` across the revision window.
    internal func noteProvisional(stepID: String, confirmAfter: TimeInterval) {
        let now = time.now
        let commit = PendingCommit(stepID: stepID, provisionalAt: now, confirmAt: now.addingTimeInterval(confirmAfter))
        revisionLog.append("v1 provisional \(stepID) @ \(now) (confirm @ \(commit.confirmAt))")
        pendingCommits.append(commit)
    }

    internal func settleDueCommits(now: Date) {
        for i in pendingCommits.indices where !pendingCommits[i].confirmed && now >= pendingCommits[i].confirmAt {
            pendingCommits[i].confirmed = true
            revisionLog.append("v2 confirmed \(pendingCommits[i].stepID) @ \(now)")
        }
        pendingCommits.removeAll { $0.confirmed }
    }

    internal func confirmAllCommits(now: Date) {
        for i in pendingCommits.indices where !pendingCommits[i].confirmed {
            pendingCommits[i].confirmed = true
            revisionLog.append("v2 confirmed \(pendingCommits[i].stepID) @ \(now) (stop flush)")
        }
        pendingCommits.removeAll()
    }

    internal func extendCommitsOnContradiction() {
        for i in pendingCommits.indices {
            if pendingCommits[i].extendOnContradiction() {
                revisionLog.append("extend \(pendingCommits[i].stepID) → confirm @ \(pendingCommits[i].confirmAt) (#\(pendingCommits[i].extensions))")
            }
        }
    }

    /// Emit a limbo-held oscillation switch once it settles.
    internal func settleLimboSwitch(now: Date) async {
        guard let limbo = limboSwitch, now >= limbo.confirmAt else { return }
        limboSwitch = nil
        guard state == .recording, !isFinalizing, captureSettings.recordAppSwitches else { return }
        // Post-await state==recording re-check preserved.
        guard state == .recording, !isFinalizing else { return }
        switchHistory.append((key: limbo.key, at: now))
        lastAppContext = RawElementContext(appName: limbo.appName, bundleIdentifier: limbo.bundleId, windowTitle: limbo.windowTitle)
        await produceAppSwitchStep(bundleId: limbo.bundleId, appName: limbo.appName, windowTitle: limbo.windowTitle)
    }

    internal func classifyAppSwitch(key: String, now: Date) -> FlapAction {
        guard let last = switchHistory.last, last.key != key else { return .emit }
        if switchHistory.count >= 2 {
            let original = switchHistory[switchHistory.count - 2]
            if original.key == key,
               now.timeIntervalSince(last.at) <= FocusSegmentation.flapRevertMillis,
               eventsSinceSwitch < FocusSegmentation.flapMaxMiddleEvents {
                return .revert
            }
        }
        if switchHistory.count >= 3 {
            let n = switchHistory.count
            let a = switchHistory[n - 3]; let b = switchHistory[n - 2]; let c = switchHistory[n - 1]
            if a.key == c.key && b.key != a.key && key == b.key,
               now.timeIntervalSince(a.at) <= FocusSegmentation.oscillationWindow {
                return .holdLimbo
            }
        }
        return .emit
    }
}
