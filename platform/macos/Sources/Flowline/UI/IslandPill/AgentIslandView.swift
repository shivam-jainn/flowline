import AppKit
import SwiftUI
import FlowlineIR

/// UI1.md §4.1 — Agent island. The capture HUD identity: one black pill.
///
/// Faithful port of `proto/src/stories/AgentIsland.{tsx,css}`:
/// collapsed shows a live timer + two-line agent narration (finished step
/// above in grey, current activity below in semibold white) beside the
/// frontmost app's icon + an action badge, plus a pixel grid that reshuffles
/// while working. Tap the header expands to full activity (elapsed / steps /
/// pause-capture-done); tap collapses back.
///
/// Motion numbers mirror `proto/src/tokens.ts` via `FlowMotion` (never
/// literals): line swap `fast` (`LINE_SWAP 0.15`), finished line follows
/// `0.09` late (`SWAP_FOLLOW`), icon swap `easeOutFast` (proto `0.16`),
/// expand `standardSlow`, entrance `easeOutSlow` (proto `0.32`), grid tick
/// `0.6s`. Reduced motion collapses everything to opacity with zero travel
/// and freezes the grid.
///
/// Click handling: the toggle button wraps the header's status/narration
/// area ONLY — the right-side transport buttons and the expanded action
/// buttons are siblings, never nested buttons (nested buttons double-fire
/// in SwiftUI). Press feedback is instant on mouse-down via
/// `IslandPressStyle`, so clicks feel immediate even though the
/// expand/collapse itself runs 0.32s.
///
/// Transport (pause/stop) lives on the right edge of the collapsed pill so
/// it is always visible — the expanded panel only carries the secondary
/// Capture-step action, never duplicates.
///
/// This replaces the generic recording pill — no parallel implementations.
public struct AgentIslandView: View {
    public var finishedStep: String?
    public var currentStep: String
    public var working: Bool
    /// Pause-correct elapsed time, driven by the controller's duration tick
    /// (frozen while paused — never wall-clock, so pause/resume stays exact).
    public var elapsed: TimeInterval
    public var stepCount: Int
    public var appName: String?
    public var appBundleID: String?
    public var action: ActionType
    public var onPauseResume: () -> Void
    public var onCaptureStep: () -> Void
    public var onStop: () -> Void
    public var onExpandedChange: (Bool) -> Void

    @State private var expanded = false
    @State private var appeared = false
    @State private var isPulsing = false
    @StateObject private var iconLoader = AppIconLoader()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        finishedStep: String? = nil,
        currentStep: String,
        working: Bool = true,
        elapsed: TimeInterval = 0,
        stepCount: Int = 0,
        appName: String? = nil,
        appBundleID: String? = nil,
        action: ActionType = .click,
        onPauseResume: @escaping () -> Void = {},
        onCaptureStep: @escaping () -> Void = {},
        onStop: @escaping () -> Void = {},
        onExpandedChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.finishedStep = finishedStep
        self.currentStep = currentStep
        self.working = working
        self.elapsed = elapsed
        self.stepCount = stepCount
        self.appName = appName
        self.appBundleID = appBundleID
        self.action = action
        self.onPauseResume = onPauseResume
        self.onCaptureStep = onCaptureStep
        self.onStop = onStop
        self.onExpandedChange = onExpandedChange
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(action: toggleExpanded) {
                    HStack(spacing: 10) {
                        statusCluster
                        appIconWithBadge
                        narrationStack
                        PixelGridView(working: working)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(IslandPressStyle(reduceMotion: reduceMotion))
                .accessibilityLabel(working ? "Recording. \(currentStep)." : "Paused. \(currentStep).")
                .accessibilityHint(expanded ? "Collapses the activity detail." : "Expands the full activity.")
                transportButtons
            }
            if expanded {
                expandedDetail
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: expanded ? 18 : 22))
        .shadow(color: Color.black.opacity(0.28), radius: 16, x: 0, y: 10)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : -14)
        .onAppear {
            iconLoader.load(bundleID: appBundleID, appName: appName)
            isPulsing = true
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(FlowMotion.easeOutSlow) { appeared = true }
            }
        }
        .onChange(of: iconLoaderKey) { _, _ in
            iconLoader.load(bundleID: appBundleID, appName: appName)
        }
    }

    // MARK: - Collapsed row

    /// Live dot + monospaced timer (proto has no timer; UI1.md adds it to
    /// the collapsed pill — dot red while recording, orange while paused).
    private var statusCluster: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(working ? Color.red : Color.orange)
                .frame(width: 8, height: 8)
                .scaleEffect(working && isPulsing && !reduceMotion ? 1.25 : 1.0)
                .opacity(working && isPulsing && !reduceMotion ? 0.6 : 1.0)
                .animation(
                    working && !reduceMotion
                        ? Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                        : .default,
                    value: isPulsing
                )
            Text(formatted(elapsed))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
    }

    /// Real frontmost-app icon (proto/README pipeline: `NSWorkspace`
    /// art, nearest-neighbour crush, `pixelated` display). Resolved off the
    /// main thread by `AppIconLoader` so app switches never hitch the pill.
    /// Falls back to nothing before the first step lands — the status dot
    /// carries state until then.
    private var appIconWithBadge: some View {
        Group {
            if let icon = iconLoader.image {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .id(iconLoaderKey)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .scale(scale: 0.7).combined(with: .opacity)
                    )
                    .animation(reduceMotion ? nil : FlowMotion.easeOutFast, value: iconLoaderKey)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: symbol(for: action))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 14, height: 14)
                            .background(Color.black.opacity(0.85))
                            .clipShape(Circle())
                            .offset(x: 4, y: 4)
                            .accessibilityHidden(true)
                    }
            }
        }
        .accessibilityHidden(true)
    }

    /// Two-line hierarchy from the reference frames: finished step (12px
    /// grey) above, current activity (semibold white) below. Each line
    /// swaps with a short vertical travel; the finished line follows 0.09s
    /// late, exactly like proto `SWAP_FOLLOW`.
    private var narrationStack: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let finishedStep {
                Text(finishedStep)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .id("finished-\(finishedStep)")
                    .transition(lineTransition)
                    .animation(
                        reduceMotion ? nil : FlowMotion.standardFast.delay(0.09),
                        value: finishedStep
                    )
            }
            Text(currentStep)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .id("current-\(currentStep)")
                .transition(lineTransition)
                .animation(reduceMotion ? nil : FlowMotion.standardFast, value: currentStep)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lineTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            )
    }

    // MARK: - Right-side transport (always visible)

    /// Pause/resume + stop, pinned to the pill's right edge. Stop is a
    /// solid red circle so it reads instantly; pause is a quiet glass
    /// circle that flips to play while paused. Siblings of the toggle —
    /// tapping them never expands/collapses.
    private var transportButtons: some View {
        HStack(spacing: 8) {
            Button(action: onPauseResume) {
                Image(systemName: working ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.14))
                    .clipShape(Circle())
            }
            .buttonStyle(IslandPressStyle(reduceMotion: reduceMotion))
            .help(working ? "Pause recording" : "Resume recording")
            .accessibilityLabel(working ? "Pause recording" : "Resume recording")
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.red)
                    .clipShape(Circle())
            }
            .buttonStyle(IslandPressStyle(reduceMotion: reduceMotion))
            .help("Stop recording and review")
            .accessibilityLabel("Stop recording and review")
        }
    }

    // MARK: - Expanded detail (sibling of the toggle — never nested buttons)

    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(formatted(elapsed)) elapsed · \(stepCount) \(stepCount == 1 ? "step" : "steps") captured")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
            HStack(spacing: 8) {
                Button("Capture step", action: onCaptureStep)
                    .tint(.white)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .transition(
            reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
        )
    }

    // MARK: - Behavior

    private func toggleExpanded() {
        let next = !expanded
        withAnimation(reduceMotion ? nil : FlowMotion.standardSlow) { expanded = next }
        onExpandedChange(next)
    }

    private func formatted(_ interval: TimeInterval) -> String {
        let mins = Int(interval) / 60
        let secs = Int(interval) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private var iconLoaderKey: String {
        "\(appBundleID ?? "")|\(appName ?? "")"
    }

    private func symbol(for action: ActionType) -> String {
        switch action {
        case .click, .rightClick, .doubleClick:
            return "cursorarrow.click.fill"
        case .keyPress, .typing, .writeCode:
            return "keyboard.fill"
        case .appSwitch:
            return "rectangle.stack.fill"
        case .mouseDrag:
            return "hand.draw.fill"
        case .manual:
            return "plus.circle.fill"
        }
    }
}

/// Instant press feedback for the island header: reacts on mouse-down
/// (SwiftUI `isPressed`), not on release, so clicks feel immediate while
/// the 0.32s expand/collapse runs underneath.
private struct IslandPressStyle: ButtonStyle {
    var reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1.0)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .animation(reduceMotion ? nil : FlowMotion.easeOutFast, value: configuration.isPressed)
    }
}

/// Resolves the frontmost app's icon off the main thread: bundle lookup +
/// icns decode can hit disk, which used to hitch the pill exactly when the
/// user switched apps mid-recording. Only the 32px nearest-neighbour crush
/// (main-thread-only drawing) and the publish hop back to `@Published`.
private final class AppIconLoader: ObservableObject {
    @Published var image: NSImage?
    private var key: String?

    func load(bundleID: String?, appName: String?) {
        let nextKey = "\(bundleID ?? "")|\(appName ?? "")"
        guard nextKey != key else { return }
        key = nextKey
        image = nil
        guard nextKey != "|" else { return }
        Task.detached(priority: .userInitiated) {
            var raw: NSImage?
            if let id = bundleID, !id.isEmpty,
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            {
                raw = NSWorkspace.shared.icon(forFile: url.path)
            }
            if raw == nil, let name = appName, !name.isEmpty {
                let path = "/Applications/\(name).app"
                if FileManager.default.fileExists(atPath: path) {
                    raw = NSWorkspace.shared.icon(forFile: path)
                }
            }
            guard let found = raw else { return }
            let small = await MainActor.run { Self.pixelated(found, edge: 32) }
            await MainActor.run {
                guard self.key == nextKey else { return }
                self.image = small
            }
        }
    }

    /// Nearest-neighbour crush to a tiny square (the honest-pixel-art trick
    /// from `proto/README.md`); `.interpolation(.none)` keeps the crunch on
    /// upscale. Main thread only (NSImage focus locking).
    @MainActor
    private static func pixelated(_ image: NSImage, edge: CGFloat) -> NSImage {
        let out = NSImage(size: NSSize(width: edge, height: edge))
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        image.draw(
            in: NSRect(x: 0, y: 0, width: edge, height: edge),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )
        out.unlockFocus()
        return out
    }
}

/// Pixel grid that reshuffles while working (proto idle life). Frozen under
/// reduced motion or while paused.
private struct PixelGridView: View {
    var working: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: reduceMotion || !working ? 3600 : 0.6)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate / 0.6)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(5), spacing: 2), count: 6), spacing: 2) {
                ForEach(0..<24, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(FlowPrimitive.System.violet)
                        .frame(width: 5, height: 5)
                        .opacity(working && !reduceMotion ? [0.25, 0.9, 0.5][(i + tick) % 3] : 0.25)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Agent island — collapsed") {
    AgentIslandView(
        finishedStep: "Grouped 3 events into Step 4",
        currentStep: "Typing terminal command",
        working: true,
        elapsed: 187,
        stepCount: 4,
        appName: "Terminal",
        action: .typing
    )
    .padding()
}

#Preview("Agent island — paused") {
    AgentIslandView(
        finishedStep: "Clicked Save in Figma",
        currentStep: "Paused",
        working: false,
        elapsed: 305,
        stepCount: 7,
        appName: "Figma",
        action: .click
    )
    .padding()
}

#Preview("Agent island — listening") {
    AgentIslandView(
        currentStep: "Listening for activity",
        working: true,
        elapsed: 4,
        stepCount: 0
    )
    .padding()
}
