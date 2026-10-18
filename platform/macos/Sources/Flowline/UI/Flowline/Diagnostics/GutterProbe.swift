import SwiftUI

/// Shared counters backing the probe HUD. Fed by `FlowPerfLog` helpers
/// (`updateTarget`, `proximityResolve`); the HUD samples frames itself.
/// All recording is gated on `FlowPerfLog.isEnabled`, so Release builds
/// with the toggle off are inert.
public final class GutterProbeStats: ObservableObject {
    public static let shared = GutterProbeStats()

    public struct Snapshot: Equatable {
        public var fps: Double
        public var frameP95Ms: Double
        public var flipsPerSec: Double
        public var resolvesPerSec: Double
        public var lastResolveMs: Double
        public static let zero = Snapshot(
            fps: 0, frameP95Ms: 0, flipsPerSec: 0,
            resolvesPerSec: 0, lastResolveMs: 0
        )
    }

    private let lock = NSLock()
    private var frames: [Date] = []     // trailing display-link ticks
    private var flips: [Date] = []      // drop-target changes
    private var resolves: [Date] = []   // proximity resolves
    private var lastResolveMs: Double = 0

    public func recordFrame(at date: Date = Date()) {
        guard FlowPerfLog.isEnabled else { return }
        lock.lock(); defer { lock.unlock() }
        frames.append(date)
        if frames.count > 480 { frames.removeFirst(frames.count - 480) }
    }

    public func recordTargetFlip(at date: Date = Date()) {
        guard FlowPerfLog.isEnabled else { return }
        lock.lock(); defer { lock.unlock() }
        flips.append(date)
        if flips.count > 120 { flips.removeFirst(flips.count - 120) }
    }

    public func recordProximityResolve(durationMs: Double, at date: Date = Date()) {
        guard FlowPerfLog.isEnabled else { return }
        lock.lock(); defer { lock.unlock() }
        resolves.append(date)
        if resolves.count > 240 { resolves.removeFirst(resolves.count - 240) }
        lastResolveMs = durationMs
    }

    public func snapshot(now: Date = Date()) -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        let window: TimeInterval = 1.0
        let recent = frames.filter { now.timeIntervalSince($0) <= window }
        var gaps: [Double] = []
        for i in 1 ..< recent.count {
            gaps.append(recent[i].timeIntervalSince(recent[i - 1]) * 1_000)
        }
        gaps.sort()
        let p95 = gaps.isEmpty ? 0 : gaps[min(Int((Double(gaps.count) * 0.95).rounded(.up)) - 1, gaps.count - 1)]
        let span = recent.count >= 2 ? recent.last!.timeIntervalSince(recent.first!) : 0
        return Snapshot(
            fps: span > 0 ? Double(recent.count - 1) / span : 0,
            frameP95Ms: p95,
            flipsPerSec: Double(flips.filter { now.timeIntervalSince($0) <= window }.count),
            resolvesPerSec: Double(resolves.filter { now.timeIntervalSince($0) <= window }.count),
            lastResolveMs: lastResolveMs
        )
    }
}

#if DEBUG
/// Debug-only HUD: FPS + frame-p95, target flips/sec, resolves/sec.
/// Never instantiated in Release.
private struct GutterProbeHUD: View {
    @State private var snap = GutterProbeStats.Snapshot.zero

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("FLOWLINE PROBE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
            Text(String(format: "fps %4.0f  p95 %5.1fms", snap.fps, snap.frameP95Ms))
                .foregroundColor(fpsColor)
            Text(String(format: "flips/s %.0f  resolves/s %.0f", snap.flipsPerSec, snap.resolvesPerSec))
            Text(String(format: "last resolve %5.2fms", snap.lastResolveMs))
                .foregroundColor(snap.lastResolveMs > 8 ? .red : .green)
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundColor(.white)
        .padding(6)
        .background(Color.black.opacity(0.72))
        .cornerRadius(6)
        .padding(8)
        // Per-frame sampler: TimelineView ticks at display rate.
        .background(
            TimelineView(.animation) { context in
                Color.clear.onChange(of: context.date, initial: true) { _, new in
                    GutterProbeStats.shared.recordFrame(at: new)
                }
            }
        )
        // Cheap 2Hz text refresh so the HUD itself doesn't churn layout.
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            snap = GutterProbeStats.shared.snapshot()
        }
    }

    private var fpsColor: Color {
        if snap.fps >= 55 { return .green }
        if snap.fps >= 30 { return .yellow }
        return .red
    }
}
#endif

/// Opt-in diagnostics overlay. No-op in Release (content passes through
/// untouched); in DEBUG it shows the HUD only when `enabled` is true.
///
/// Attach at the gutter root, e.g. `FlowlineGutter` body:
/// `.gutterProbe()`. Disable before capturing final Instruments numbers.
public struct GutterProbe: ViewModifier {
    private let enabled: Bool

    public init(enabled: Bool = true) {
        self.enabled = enabled
    }

    public func body(content: Content) -> some View {
#if DEBUG
        if enabled {
            content.overlay(alignment: .topTrailing) { GutterProbeHUD() }
        } else {
            content
        }
#else
        content
#endif
    }
}

public extension View {
    /// Show the gutter perf HUD (DEBUG only; Release = passthrough).
    func gutterProbe(enabled: Bool = true) -> some View {
        modifier(GutterProbe(enabled: enabled))
    }
}
