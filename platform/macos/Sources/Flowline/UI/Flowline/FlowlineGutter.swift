import SwiftUI
import AppKit
import FlowlineIR
import FlowlineStorage

/// Preview gutter — horizontal step navigator with proximity insert,
/// selection ring, halo/auto flags, drag-to-reorder. Port of `#gutter`
/// (`Step Recorder Guide Studio` prototype).
///
/// Motion: border/background 150ms standard, shadow/opacity 220ms standard,
/// transform 220ms ease-out for non-gesture flips (hover/select). All
/// drag-driven motion uses springs so pointer velocity is preserved on
/// retarget (WWDC23 "Animate with springs"): lift/drop-target/sibling shift
/// run on `FlowMotion.spring`/`FlowMotion.shift`. Dragging shows a lifted
/// preview (1.04, elevated shadow, accent edge); the drop target keeps its
/// 2.5px leading bar plus a sprung leading gap so siblings glide aside;
/// Force Touch haptics tick on target change (.alignment) and drop
/// (.generic). Scale/offset/overshoot are Reduce-Motion-gated (opacity-only
/// fallback); haptics are not motion and always play.
public struct FlowlineGutter: View {
    @Binding var session: StepSession
    var store: SessionStore
    var selection: Set<String>
    var onSelect: (String, Bool, Bool) -> Void  // id, cmd, shift
    var onInsert: (Int) -> Void
    var onMove: (Int, Int) -> Void
    var numbering: FlowNumbering = .numeric

    @State private var dropTargetID: String?
    @State private var draggingID: String?
    /// Gap the pointer is inside right now (immediate) — drives the blue
    /// hint wash. Distinct from `armedInsert` below so the wash can lead.
    @State private var nearInsert: Int?
    /// Gap that survived the dwell (deliberate pause) — drives the `+`.
    @State private var armedInsert: Int?
    /// Pending deliberate-arm work item (see `requestArm`). Re-pushed on
    /// every pointer move while unarmed (sliding dwell), cancelled on
    /// leave and on drag start — disarm is always immediate, only arming
    /// waits out the dwell.
    @State private var armWork: DispatchWorkItem?
    @State private var insertMids: [Int: CGFloat] = [:]
    @State private var cardFrames: [Int: CGRect] = [:]
    @State private var lastMouseX: CGFloat?
    @State private var lastResolve = Date.distantPast
    @State private var settleID: String?
    @StateObject private var companion = GutterDragCompanion()
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        session: Binding<StepSession>, store: SessionStore, selection: Set<String>,
        onSelect: @escaping (String, Bool, Bool) -> Void,
        onInsert: @escaping (Int) -> Void,
        onMove: @escaping (Int, Int) -> Void,
        numbering: FlowNumbering = .numeric
    ) {
        self._session = session
        self.store = store
        self.selection = selection
        self.onSelect = onSelect
        self.onInsert = onInsert
        self.onMove = onMove
        self.numbering = numbering
    }

    public var body: some View {
        let t = FlowComponent.for(scheme)
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(session.steps, id: \.id) { step in
                        if let i = session.steps.firstIndex(where: { $0.id == step.id }) {
                            HStack(alignment: .center, spacing: 12) {
                                insertSlot(at: i)
                                card(step, at: i)
                            }
                            .id("slot-\(step.id)")
                        }
                    }
                    insertSlot(at: session.steps.count)
                    Spacer(minLength: 12)
                }
                .padding(12)
                .coordinateSpace(name: "gutter")
                .background(
                    GutterMouseTracker(
                        onMove: { updateProximity(x: $0) },
                        onExit: {
                            lastMouseX = nil
                            cancelArm()
                            nearInsert = nil
                            armedInsert = nil
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                )
                // Weak NSScrollView handle for 16pt edge-nudge steps; the
                // ScrollViewReader proxy below stays the scroll-follow path.
                .background(GutterScrollFinder(companion: companion))
                .onPreferenceChange(InsertMidXKey.self) {
                    // Skip PreferenceKey writes when unchanged — avoids a
                    // layout + re-resolve loop on every mouse event.
                    if $0 != insertMids {
                        insertMids = $0
                        companion.insertMids = $0
                    }
                }
                .onPreferenceChange(CardFrameKey.self) {
                    if $0 != cardFrames { cardFrames = $0 }
                }
            }
            .background(Color.clear)
            .overlay(RoundedRectangle(cornerRadius: FlowComponent.radiusLG).stroke(t.border, lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            // Prototype `scroll-behavior: smooth` — follow selection and drag.
            .onChange(of: selection) { _, new in
                guard let id = new.first else { return }
                withAnimation(FlowMotion.standard) {
                    proxy.scrollTo("slot-\(id)", anchor: .center)
                }
            }
            .onChange(of: dropTargetID) { _, id in
                guard let id else { return }
                // Scroll peace: while dragging, the 16pt edge-nudge owns
                // near-edge following. Only scrollTo on jumps (>1 card away
                // from the last scrolled target) so per-event target flips
                // don't fight the nudge pixel-scroll. Nudge remains the only
                // near-edge mechanism: suppress follow for ~300ms after any
                // nudge fired.
                if draggingID != nil,
                   Date().timeIntervalSince(companion.lastNudgeFired) < 0.3 {
                    return
                }
                if draggingID != nil,
                   let last = companion.lastScrolledID,
                   let li = session.steps.firstIndex(where: { $0.id == last }),
                   let ni = session.steps.firstIndex(where: { $0.id == id }),
                   abs(ni - li) <= 1,
                   Date().timeIntervalSince(companion.lastScroll) < 1.0 {
                    return
                }
                companion.lastScrolledID = id
                companion.lastScroll = Date()
                // Drag-driven follow — spring so retargets inherit velocity.
                withAnimation(FlowMotion.shift) {
                    proxy.scrollTo("slot-\(id)", anchor: .center)
                }
            }
            .onChange(of: session.steps.count) { _, _ in
                draggingID = nil
                dropTargetID = nil
                cancelArm()
                nearInsert = nil
                armedInsert = nil
                settleID = nil
                companion.lastTarget = nil
                companion.lastScrolledID = nil
            }
            .onChange(of: draggingID) { _, id in
                // Prototype clears every `.near` while a drag is in flight.
                if id != nil {
                    cancelArm()
                    nearInsert = nil
                    armedInsert = nil
                }
            }
        }
        .animation(FlowMotion.standard, value: session.steps.count)
    }

    // MARK: - Proximity (dynamic edge-20% + gap zones)

    /// Trigger zone for gap `i`, derived live from the measured card
    /// frames — never a fixed pixel radius:
    ///   * interior gap: trailing 20% of card `i-1` + the open space
    ///     between the cards + leading 20% of card `i`;
    ///   * end gaps: 20% of the single adjacent card + `endPad` of
    ///     padding space outside it.
    /// The middle 60% of a card never arms an insert, and because the
    /// zone is anchored to card edges (not the expanding slot's center)
    /// the 0→30px slot growth lands inside the already-armed zone
    /// instead of pushing the trigger away (no flicker loop).
    /// A small stickiness bias toward the currently-armed gap kills
    /// border dithering without delaying switches.
    private static let edgeFraction: CGFloat = 0.2
    private static let endPad: CGFloat = 36
    private static let legacyFallbackRadius: CGFloat = 24

    private func updateProximity(x: CGFloat) {
        // Throttle: sub-point moves can't change the armed gap; ~8ms
        // debounce caps PreferenceKey churn at ~120Hz of pointer events.
        if let last = lastMouseX, abs(x - last) < FlowMotion.proximityStep { return }
        let now = Date()
        guard now.timeIntervalSince(lastResolve) >= FlowMotion.proximityDebounce else { return }
        lastResolve = now
        lastMouseX = x
        let __t0 = ContinuousClock().now
        defer {
            let el = ContinuousClock().now - __t0
            let ms = Double(el.components.seconds) * 1_000
                + Double(el.components.attoseconds) / 1e15
            FlowPerfLog.proximityResolve(durationMs: ms,
                gapCount: session.steps.count + 1)
        }
        guard draggingID == nil else {
            if nearInsert != nil || armedInsert != nil {
                cancelArm()
                nearInsert = nil
                armedInsert = nil
            }
            return
        }
        let n = session.steps.count
        var best: Int?
        var bestScore: CGFloat = .greatestFiniteMagnitude
        for i in 0...n {
            let prev = i > 0 ? cardFrames[i - 1] : nil
            let next = i < n ? cardFrames[i] : nil
            if prev == nil && next == nil {
                // Card geometry not measured yet — tight center fallback
                // so the control still works on the very first frame.
                if let mid = insertMids[i] {
                    let d = abs(mid - x)
                    if d <= Self.legacyFallbackRadius && d < bestScore {
                        bestScore = d
                        best = i
                    }
                }
                continue
            }
            let refW = prev?.width ?? next?.width ?? FlowComponent.cardWidth
            let edge = Self.edgeFraction * refW
            let gapLo: CGFloat
            let gapHi: CGFloat
            let zoneLo: CGFloat
            let zoneHi: CGFloat
            switch (prev, next) {
            case let (p?, n?):
                gapLo = p.maxX
                gapHi = n.minX
                zoneLo = p.maxX - edge
                zoneHi = n.minX + edge
            case let (p?, nil):
                gapLo = p.maxX
                gapHi = p.maxX + Self.endPad
                zoneLo = p.maxX - edge
                zoneHi = p.maxX + Self.endPad
            case let (nil, n?):
                gapLo = n.minX - Self.endPad
                gapHi = n.minX
                zoneLo = n.minX - Self.endPad
                zoneHi = n.minX + edge
            default:
                continue
            }
            guard x >= zoneLo, x <= zoneHi else { continue }
            let dist: CGFloat = x < gapLo ? gapLo - x : (x > gapHi ? x - gapHi : 0)
            let score = dist + (nearInsert == i ? -2 : 0)
            if score < bestScore {
                bestScore = score
                best = i
            }
        }
        if best != nearInsert {
            // Zone leads immediately (hint line); the `+` follows only
            // after the dwell (deliberate pause) via requestArm.
            nearInsert = best
        }
        if best != armedInsert {
            // Sliding dwell: every move while unarmed re-pushes the timer,
            // so the `+` fires 0.18s after the pointer actually rests.
            // (Previously requestArm ran only on zone *entry*, so any
            // micro-adjust while aiming permanently killed the one pending
            // arm and the `+` never appeared until leave + re-enter.)
            requestArm(best)
        }
    }

    /// Deliberate-arm: a new gap only opens the `+` slot after the pointer
    /// has rested `insertDwell` without moving on. Leaving every zone (or
    /// starting a drag) disarms immediately — only arming waits.
    private func requestArm(_ gap: Int?) {
        armWork?.cancel()
        armWork = nil
        guard gap != armedInsert else { return }
        guard let gap else {
            armedInsert = nil
            return
        }
        // Fire only if the pointer hasn't moved on: any newer pointer event
        // targeting elsewhere cancels this item first, and a moved-on pointer
        // fails the stillness check.
        let x = lastMouseX
        let item = DispatchWorkItem {
            if lastMouseX == x { armedInsert = gap }
        }
        armWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + FlowMotion.insertDwell, execute: item)
    }

    private func cancelArm() {
        armWork?.cancel()
        armWork = nil
    }

    private func insertSlot(at index: Int) -> some View {
        ProximityInsert(index: index, zone: nearInsert == index, armed: armedInsert == index) {
            onInsert(index)
        }
        .background(InsertMidReader(index: index))
    }

    // MARK: - Cards

    /// Filmstrip card: NN + thumb + halo dot only. Titles live in the
    /// preview list (no duplication here); full text ships via
    /// help/accessibilityLabel. Placeholder steps render the shared
    /// dashed placeholder card instead.
    private func card(_ s: Step, at index: Int) -> some View {
        let selected = selection.contains(s.id)
        return cardContent(s, at: index, selected: selected)
            .id(s.id)
            .background(CardFrameReader(index: index))
    }

    private func cardContent(_ s: Step, at index: Int, selected: Bool) -> some View {
        let t = FlowComponent.for(scheme)
        let sem = FlowSemantic.for(scheme)
        return Group {
            if FlowlineStepText.isPlaceholder(s) {
            FlowlinePlaceholderCard(
                step: s, index: index, compact: true,
                onAddText: {
                    withAnimation(FlowMotion.standardFast) { onSelect(s.id, false, false) }
                },
                onCapture: {
                    withAnimation(FlowMotion.standardFast) { onSelect(s.id, false, false) }
                }
            )
            .frame(width: FlowComponent.cardWidth)
            .overlay(
                RoundedRectangle(cornerRadius: FlowComponent.radiusMD)
                    .stroke(selected ? FlowlineSelection.ring(for: scheme) : Color.clear,
                            lineWidth: selected ? 2 : 0)
            )
        } else {
            GutterCard(
                selected: selected,
                isDropTarget: dropTargetID == s.id,
                isDragging: draggingID == s.id,
                isAnyDragging: draggingID != nil,
                isSettled: settleID == s.id
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    ZStack(alignment: .topTrailing) {
                        thumb(for: s)
                            .frame(width: FlowComponent.cardWidth - 8, height: 64)
                            .background(t.surfaceSubtle)
                            .cornerRadius(FlowComponent.radiusSM)
                            .overlay(
                                RoundedRectangle(cornerRadius: FlowComponent.radiusSM)
                                    .stroke(selected ? FlowlineSelection.ring(for: scheme) : t.stepBorder,
                                            lineWidth: selected ? 2 : 1)
                            )
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(sem.accentDefault)
                                .background(t.textInverse.clipShape(Circle()))
                                .offset(x: 4, y: -4)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    HStack(spacing: 4) {
                        switch numbering {
                        case .numeric:
                            Text(String(format: "%02d", index + 1))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(t.stepNumber)
                        case .checkbox:
                            Image(systemName: selected ? "checkmark.square.fill" : "square")
                                .font(.system(size: 11))
                                .foregroundColor(selected ? sem.accentDefault : t.textTertiary)
                        case .none:
                            EmptyView()
                        }
                        if FlowlineHaloResolver.halo(for: s) != nil {
                            Circle()
                                .fill(sem.haloIcon)
                                .frame(width: 6, height: 6)
                                .help("Halo · \(FlowlineHaloResolver.kind(for: s).label)")
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(width: FlowComponent.cardWidth - 8, alignment: .leading)
                }
            }
        }
        }
        // Layout-stable gap: a visual offset, NOT animated padding. Padding
        // changes the HStack's measured width mid-drag (container-width
        // oscillation → jitter); offset never affects layout, so the 2.5px
        // overlay bar + this shift read as a gap with zero re-measurement.
        // Reduce Motion: no gap. Animated by the explicit withAnimation at
        // the dropTargetID mutation site — no .animation(value:) here.
        .offset(x: dropTargetID == s.id && !reduceMotion ? GutterDragCompanion.gapWidth / 2 : 0)
        // Prototype `.step-card.removing`: fade + scale to .9.
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .onTapGesture {
            // Pass live modifier flags so Cmd-click toggles and
            // Shift-click ranges via selectStep (bulk bar reachable).
            let flags = NSEvent.modifierFlags
            withAnimation(FlowMotion.standardFast) {
                onSelect(s.id, flags.contains(.command), flags.contains(.shift))
            }
        }
        .onDrag {
            // Lift is gesture-driven: spring preserves any pointer velocity.
            withAnimation(FlowMotion.spring) { draggingID = s.id }
            FlowPerfLog.beginDrag(id: s.id)
            return NSItemProvider(object: s.id as NSString)
        } preview: {
            GutterDragPreview(number: index + 1, title: FlowlineStepText.readerTitle(for: s), lifted: !reduceMotion)
        }
        .onDrop(of: [.text], delegate: StepDropDelegate(
            stepID: s.id,
            onHover: { over in
                if over {
                    // Tick once per target (dropUpdated re-fires while the
                    // pointer rests); haptics are not motion — always play.
                    if companion.lastTarget != s.id {
                        FlowPerfLog.updateTarget(from: companion.lastTarget, to: s.id)
                        companion.lastTarget = s.id
                        GutterHaptics.play(.alignment)
                    }
                    withAnimation(FlowMotion.shift) { dropTargetID = s.id }
                    // Per-event pump: nudge near the visible edge (throttled).
                    companion.nudge(index: index)
                } else {
                    // Sticky lastTarget for the drag lifetime: exiting to
                    // empty space clears the visual (dropTargetID nil) but
                    // remembers the last card so card-to-card re-entry
                    // doesn't re-tick haptics or re-animate. Cleared only at
                    // drag end (onMove) + steps-count reset.
                    withAnimation(FlowMotion.standardFast) {
                        if dropTargetID == s.id { dropTargetID = nil }
                    }
                }
            },
            onMove: { fromID, after in
                guard let from = session.steps.firstIndex(where: { $0.id == fromID }),
                      let to0 = session.steps.firstIndex(where: { $0.id == s.id }) else { return }
                // Prototype midline rule: `splice(dropAfter ? to+1 : to)`,
                // adjusted for the removal shift, clamped post-removal.
                var to = after ? to0 + 1 : to0
                if from < to { to -= 1 }
                to = min(max(to, 0), max(session.steps.count - 1, 0))
                // Settle is gesture-driven: spring the reorder…
                let __drop = FlowPerfLog.signpostBegin("DropApply", .dnd)
                withAnimation(FlowMotion.shift) { onMove(from, to) }
                FlowPerfLog.signpostEnd("DropApply", .dnd, id: __drop)
                FlowPerfLog.endDrag(id: fromID, dropped: true)
                GutterHaptics.play(.generic)
                // …then breathe the placed card 1.0→1.03→1.0 (view-gated).
                // Explicit animation (no .animation(value:) in GutterCard).
                withAnimation(FlowMotion.spring) { settleID = fromID }
                companion.lastTarget = nil
                dropTargetID = nil
                draggingID = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    if settleID == fromID {
                        withAnimation(FlowMotion.spring) { settleID = nil }
                    }
                }
            }
        ))
        .focusable()
        .onKeyPress(.return) {
            withAnimation(FlowMotion.standardFast) { onSelect(s.id, false, false) }
            return .handled
        }
        .onKeyPress(.space) {
            withAnimation(FlowMotion.standardFast) { onSelect(s.id, false, false) }
            return .handled
        }
        .help(FlowlineStepText.fullText(step: s, index: index))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(FlowlineStepText.fullText(step: s, index: index))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func thumb(for s: Step) -> some View {
        // Cache-keyed async thumbs: body never touches disk (no
        // NSImage(contentsOf:) in the body path), so drag hover frames stay
        // at a cache lookup + frame fill.
        if let gif = s.assets.gif, s.preferredMedia?.lowercased() == "gif" {
            let url = store.resolveMediaPath(sessionID: session.id, relativePath: gif)
            GutterThumb(url: url, cacheKey: "gif:\(s.id)/\(gif)")
        } else if let shot = s.assets.screenshot {
            let url = store.resolveMediaPath(sessionID: session.id, relativePath: shot)
            GutterThumb(url: url, cacheKey: "shot:\(s.id)/\(shot)")
        } else {
            Image(systemName: "photo.badge.plus")
                .foregroundColor(FlowComponent.for(scheme).textTertiary)
                .help("No capture")
        }
    }
}

/// Cached thumbnail view: synchronous NSCache hit in body, one
/// utility-queue disk load per asset lifetime. Static layout — no
/// GeometryReader/PreferenceKey/onHover.
private struct GutterThumb: View {
    var url: URL
    var cacheKey: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.clear
            }
        }
        .task(id: cacheKey) {
            if let hit = GutterThumbCache.shared.image(forKey: cacheKey) {
                image = hit
            } else {
                image = await GutterThumbCache.shared.load(url: url, key: cacheKey)
            }
        }
    }
}

/// Thumbnail disk cache keyed by asset path. Unbounded NSCache (system
/// evicts under pressure); one disk read per asset per session.
private final class GutterThumbCache {
    static let shared = GutterThumbCache()
    private let cache = NSCache<NSString, NSImage>()

    func image(forKey key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func load(url: URL, key: String) async -> NSImage? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                guard let img = NSImage(contentsOf: url) else {
                    cont.resume(returning: nil)
                    return
                }
                self.cache.setObject(img, forKey: key as NSString)
                cont.resume(returning: img)
            }
        }
    }
}

// MARK: - Gap geometry (live rects, like `getBoundingClientRect`)

private struct InsertMidXKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] { [:] }
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct InsertMidReader: View {
    var index: Int
    var body: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: InsertMidXKey.self,
                value: [index: geo.frame(in: .named("gutter")).midX]
            )
        }
    }
}

/// Live card boxes in gutter space. Proximity zones anchor to these
/// edges so the trigger follows the real layout (card width, spacing,
/// scroll position) instead of a fixed pixel radius.
private struct CardFrameKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] { [:] }
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct CardFrameReader: View {
    var index: Int
    var body: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: CardFrameKey.self,
                value: [index: geo.frame(in: .named("gutter"))]
            )
        }
    }
}

// MARK: - Container pointer tracking (`pointermove` / `pointerleave`)

private struct GutterMouseTracker: NSViewRepresentable {
    var onMove: (CGFloat) -> Void
    var onExit: () -> Void

    func makeNSView(context: Context) -> TrackingNSView {
        let v = TrackingNSView()
        v.onMove = onMove
        v.onExit = onExit
        return v
    }

    func updateNSView(_ nsView: TrackingNSView, context: Context) {
        nsView.onMove = onMove
        nsView.onExit = onExit
        nsView.updateTrackingAreas()
    }

    final class TrackingNSView: NSView {
        var onMove: ((CGFloat) -> Void)?
        var onExit: (() -> Void)?

        override func layout() {
            super.layout()
            updateTrackingAreas()
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for t in trackingAreas { removeTrackingArea(t) }
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                owner: self,
                userInfo: nil
            ))
        }

        override func mouseMoved(with event: NSEvent) {
            onMove?(convert(event.locationInWindow, from: nil).x)
        }

        override func mouseExited(with event: NSEvent) {
            onExit?()
        }
    }
}

/// Proximity insert (`gut-insert` + `insert-btn`), two-stage:
/// the blue grain wash appears the instant the pointer enters the gap
/// (zone — "something can happen here"), the 24px circle `+` expands
/// 0→30px only after the dwell (armed — deliberate pause). Leaving the
/// zone clears both immediately. The wash is a fixed-frame background so
/// it never takes layout space; only the armed expansion shifts siblings.
private struct ProximityInsert: View {
    var index: Int
    var zone: Bool
    var armed: Bool
    var action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let sem = FlowSemantic.for(scheme)
        let t = FlowComponent.for(scheme)
        Button(action: { withAnimation(FlowMotion.standard) { action() } }) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(hovering ? t.textInverse : t.textSecondary)
                .frame(width: 24, height: 24)
                .background(hovering ? sem.accentDefault : t.surfaceElevated, in: Circle())
                .overlay(Circle().stroke(t.border, lineWidth: hovering ? 0 : 1))
                .shadow(color: sem.shadowSubtle, radius: 2, y: 1)
                .scaleEffect(hovering && !reduceMotion ? 1.12 : 1.0)
                .animation(FlowMotion.easeOutFast, value: hovering)
        }
        .buttonStyle(FlowPressStyle())
        .opacity(armed ? 1 : 0)
        .scaleEffect(armed && !reduceMotion ? 1.0 : 0.9)
        .frame(width: armed ? 30 : 0, height: 64)
        .background(InsertHint(visible: zone))
        .animation(FlowMotion.easeOut, value: armed)
        .onHover { hovering = $0 }
        .allowsHitTesting(armed)
        .help("Insert step at position \(index + 1)")
        .accessibilityLabel("Insert step at position \(index + 1)")
    }
}

/// Clean insertion hint shown the instant the pointer enters a gap zone.
/// A 4px lateral gradient bar reaching ~40% into each neighboring card
/// toward its center (spec §11: thin, clean, understated).
/// Lateral color blend (accent → hover) + transparent tips so the overhang
/// melts into the cards. Painted as an overlay so the overhang
/// never takes layout space; only the armed `+` expansion shifts siblings.
/// Opacity + scaleX only; Reduce-Motion safe via the parent's gating.
private struct InsertHint: View {
    var visible: Bool
    @Environment(\.colorScheme) private var scheme

    /// Slot (30) + 40% of one card width on each side.
    private static var lineWidth: CGFloat { 30 + FlowComponent.cardWidth * 0.8 }

    var body: some View {
        let sem = FlowSemantic.for(scheme)
        Capsule()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: sem.accentDefault.opacity(0), location: 0),
                        .init(color: sem.accentDefault, location: 0.22),
                        .init(color: sem.aiFg, location: 0.78),
                        .init(color: sem.aiFg.opacity(0), location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: Self.lineWidth, height: 6)
            .shadow(color: sem.stepInsertion.opacity(0.35), radius: 4, y: 0)
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : 0.7, anchor: .center)
            .animation(FlowMotion.standardFast, value: visible)
    }
}

/// Card shell — prototype `.step-card` states:
/// hover = wash + lift -2px + subtle shadow;
/// selected = selected wash + accent border + soft ring + lift;
/// dragging = lifted preview treatment (opacity .45 + scale .96, springs);
/// drop-target = accent border + 2.5px leading insertion bar (spring) +
/// layout-stable visual offset (no measured-width change);
/// settled = one spring breath to 1.03 after a drop (Reduce-Motion-gated).
///
/// Animation discipline: only hover/select (non-gesture flips) carry
/// `.animation(value:)` here. Everything gesture-driven (lift, drop-target,
/// settle) animates from the ONE explicit `withAnimation` at the mutation
/// site in `FlowlineGutter`. The `isAnyDragging` opt-out makes the
/// drag-wide shadow-diet switch instant instead of inheriting the lift
/// spring on every card.
private struct GutterCard<Content: View>: View {
    var selected: Bool
    var isDropTarget: Bool
    var isDragging: Bool
    var isAnyDragging: Bool = false
    var isSettled: Bool = false
    @ViewBuilder var content: () -> Content
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lifted: Bool { hovering || selected }

    var body: some View {
        let t = FlowComponent.for(scheme)
        let sem = FlowSemantic.for(scheme)
        let lift: CGFloat = (lifted && !isDragging && !reduceMotion) ? -2 : 0
        content()
            .padding(4)
            .frame(width: FlowComponent.cardWidth)
            .background(selected ? t.stepBgSelected : (hovering ? t.stepBgHover : t.stepBg))
            .cornerRadius(FlowComponent.radiusMD)
            .overlay(
                RoundedRectangle(cornerRadius: FlowComponent.radiusMD)
                    .stroke(isDropTarget ? sem.interactDropTarget : (selected ? FlowlineSelection.ring(for: scheme) : t.stepBorder),
                            lineWidth: (selected || isDropTarget) ? 2 : 1)
            )
            // Prototype `drop-target::before`: 2.5px blue bar, left -6px.
            .overlay(alignment: .leading) {
                if isDropTarget {
                    Capsule()
                        .fill(sem.stepInsertion)
                        .frame(width: 2.5)
                        .padding(.vertical, 8)
                        .offset(x: -6)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .modifier(GutterCardShadow(
                selected: selected, hovering: hovering,
                isDragging: isDragging, isAnyDragging: isAnyDragging,
                lift: lift, semantic: sem
            ))
            .offset(y: lift)
            .scaleEffect(scale)
            .opacity(isDragging ? 0.45 : 1.0)
            // Non-gesture flips only — gesture visuals ride the parent's
            // explicit withAnimation. The nil animation makes the drag-wide
            // shadow-diet switch instant (value-scoped opt-out; a
            // transaction() cannot key off a single value).
            .animation(FlowMotion.standardFast, value: hovering)
            .animation(FlowMotion.standardFast, value: selected)
            .animation(nil, value: isAnyDragging)
            .onHover { hovering = $0 }
    }

    /// Reduce Motion gates every scale: opacity-only fallback otherwise.
    private var scale: CGFloat {
        if reduceMotion { return 1.0 }
        if isDragging { return 0.96 }
        if isSettled { return 1.03 }
        return 1.0
    }
}

/// Shadow diet: a single shadow pass while ANY drag is in flight (one cheap
/// blur — or a no-op clear — per card instead of 3 layered blurs recomputed
/// per hover frame), full triple treatment restored after the drag. Colors
/// stay on FlowSemantic tokens.
private struct GutterCardShadow: ViewModifier {
    var selected: Bool
    var hovering: Bool
    var isDragging: Bool
    var isAnyDragging: Bool
    var lift: CGFloat
    var semantic: FlowSemantic

    func body(content: Content) -> some View {
        if isAnyDragging {
            content.shadow(
                color: isDragging ? semantic.shadowElevated : .clear,
                radius: isDragging ? 8 : 0,
                y: isDragging ? 3 : 0
            )
        } else {
            content
                .shadow(
                    color: selected ? semantic.shadowDefault : (hovering ? semantic.shadowSubtle : .clear),
                    radius: selected ? 6.0 : (hovering ? 5.0 : 0.0),
                    y: lift != 0 ? 2.0 : 0.0
                )
                .shadow(color: selected ? semantic.selectedRing : .clear, radius: 3, y: 0)
                .shadow(color: isDragging ? semantic.shadowElevated : .clear, radius: 8, y: 3)
        }
    }
}

struct StepDropDelegate: DropDelegate {
    var stepID: String
    var onHover: (Bool) -> Void = { _ in }
    var onMove: (String, Bool) -> Void
    func dropEntered(info: DropInfo) { onHover(true) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        onHover(true)
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) { onHover(false) }
    func performDrop(info: DropInfo) -> Bool {
        onHover(false)
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        // Prototype midline rule: insert after the card when the pointer
        // is past its horizontal midpoint.
        let after = info.location.x > FlowComponent.cardWidth / 2
        provider.loadObject(ofClass: NSString.self) { obj, _ in
            if let id = obj as? String, id != stepID {
                DispatchQueue.main.async { onMove(id, after) }
            }
        }
        return true
    }
}

// MARK: - Tactile drag support (springs + haptics + edge scroll)

// AppKit Force Touch haptics. `perform` is a silent no-op where no Force
// Touch trackpad exists. Haptics are not motion: never Reduce-Motion-gated.
// Observed only via FlowPerfLog.haptic (zero-cost when disabled).
private enum GutterHaptics {
    static var lastHaptic = Date.distantPast
    static func play(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        // Rate-gate the alignment tick so card-to-card flips can't stack
        // ticks closer than hapticMinInterval; drop .generic always plays.
        // Haptics are not motion: never Reduce-Motion-gated.
        if pattern == .alignment {
            let now = Date()
            guard now.timeIntervalSince(lastHaptic) >= FlowMotion.hapticMinInterval else { return }
            lastHaptic = now
        }
        FlowPerfLog.haptic("\(pattern)")
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}

/// Live drag state shared by every card's drop closures. A reference type so
/// per-event `dropUpdated` pumps read live gap geometry instead of the stale
/// struct snapshot captured when the closure was built.
final class GutterDragCompanion: ObservableObject {
    /// Leading gap grown before the drop target so siblings glide aside.
    static let gapWidth: CGFloat = 14
    /// Prototype edge-scroll tuning: nudge while the hovered card sits
    /// within 72pt of the visible edge, 16pt per event.
    static let edgeInset: CGFloat = 72
    static let nudgeStep: CGFloat = 16
    static let nudgeInterval: TimeInterval = 0.09

    weak var scrollView: NSScrollView?
    var insertMids: [Int: CGFloat] = [:]
    var lastTarget: String?
    var lastNudge = Date.distantPast
    /// Last edge-nudge fire time: scroll-follow stays suppressed for ~300ms
    /// after any nudge so the pixel-pump owns near-edge following.
    var lastNudgeFired = Date.distantPast
    /// Scroll-follow arbitration: the dropTargetID scrollTo records here so
    /// per-event target flips within 1 card don't fight the edge nudge.
    var lastScrolledID: String?
    var lastScroll = Date.distantPast

    /// Locate the enclosing scroll view for pixel nudges.
    func attach(_ view: NSView) {
        var s = view.superview
        while let v = s {
            if let sv = v as? NSScrollView {
                scrollView = sv
                return
            }
            s = v.superview
        }
    }

    /// Pixel-nudge the scrolled content while a drag hovers near the visible
    /// leading/trailing edge. Geometry is content-space on both sides: gap
    /// mids are measured in the "gutter" coordinate space (the padded
    /// document view) and `contentView.bounds` is the visible rect in
    /// document coordinates, so no screen-space conversion is needed.
    /// Throttled to one 16pt step per interval; safely no-ops in previews.
    func nudge(index: Int) {
        guard let sv = scrollView else { return }
        let now = Date()
        guard now.timeIntervalSince(lastNudge) >= Self.nudgeInterval else { return }
        guard let lead = insertMids[index], let trail = insertMids[index + 1] else { return }
        let visible = sv.contentView.bounds
        let cardMin = lead + 3
        let cardMax = trail - 3
        var dx: CGFloat = 0
        if cardMin - visible.minX < Self.edgeInset {
            dx = -Self.nudgeStep
        } else if visible.maxX - cardMax < Self.edgeInset {
            dx = Self.nudgeStep
        }
        guard dx != 0 else { return }
        FlowPerfLog.scrollNudge(dx: dx)
        lastNudgeFired = now
        let docWidth = sv.documentView?.frame.width ?? visible.width
        let maxX = max(docWidth - visible.width, 0)
        var origin = visible.origin
        origin.x = min(max(origin.x + dx, 0), maxX)
        sv.contentView.scroll(to: origin)
        sv.reflectScrolledClipView(sv.contentView)
        lastNudge = now
    }
}

/// Introspection hook that hands the companion its weak NSScrollView.
private struct GutterScrollFinder: NSViewRepresentable {
    var companion: GutterDragCompanion

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async { companion.attach(v) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        companion.attach(nsView)
    }
}

/// Lifted drag preview (macOS 14 `onDrag` preview API): slight scale-up,
/// elevated shadow, accent edge. Reduce Motion renders it flat.
/// Static by contract: no GeometryReader/PreferenceKey/onHover — the system
/// snapshots it outside the layout pass, so any of those would cost per
/// drag without benefit.
private struct GutterDragPreview: View {
    var number: Int
    var title: String
    var lifted: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = FlowComponent.for(scheme)
        let sem = FlowSemantic.for(scheme)
        VStack(alignment: .leading, spacing: 4) {
            Text(String(format: "%02d", number))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(t.stepNumber)
            Text(title)
                .font(.system(size: 11))
                .lineLimit(2)
                .foregroundColor(t.stepText)
        }
        .frame(width: FlowComponent.cardWidth - 10, alignment: .leading)
        .padding(8)
        .background(t.stepBgSelected)
        .cornerRadius(FlowComponent.radiusMD)
        .overlay(
            RoundedRectangle(cornerRadius: FlowComponent.radiusMD)
                .stroke(sem.interactDropTarget, lineWidth: 2)
        )
        .shadow(color: sem.shadowElevated, radius: lifted ? 12 : 0, y: lifted ? 4 : 0)
        .scaleEffect(lifted ? 1.04 : 1.0)
    }
}
