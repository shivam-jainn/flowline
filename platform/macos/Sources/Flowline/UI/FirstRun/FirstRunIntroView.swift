import SwiftUI

// MARK: - First-run intro: keyframe-driven product story
//
// Native SwiftUI port of the `intro-prototype` web timeline
// (OpenDesign project "Step Recorder Guide Studio" → intro-prototype/index.html,
// intro.js, styles.css). Nine beats on ONE 9.6s clock:
// idle → interaction (0.8s) → stepCaptured (2.0s) → stepsCollected (3.0s) →
// guideFormed (4.5s) → halo (6.0s) → aiEdit (6.8s, morph 7.35s) →
// reader (7.8s) → brand (9.0s).
//
// `FirstRunIntroValues` holds every animatable channel. The view runs ONE
// linear master clock (`IntroClock` 0 → 9.6) through `keyframeAnimator` and
// maps it to channels in `IntroTimeline.value(at:)` — because
// `CubicKeyframe` has a fixed curve (verified in SwiftUICore: no timing
// parameter), the exact prototype beziers (--spring (0.32,0.72,0,1),
// --spring-soft, ease) are evaluated in code by `UnitBezier`, the same
// Newton+bisection math browsers use. No timers, no JS.
//
// Prototype → SwiftUI mapping notes (canvas differs: web 1120×800, here 880×600,
// so positions are re-derived from the SwiftUI subview sizes, but BEATS,
// DURATIONS and EASING SHAPES mirror the prototype):
// - web --spring (0.32,0.72,0,1) / --spring-soft (0.34,1.06,0.44,1) / ease /
//   t-micro 180ms / t-ui 520ms / t-major 900ms.
// - web halo geometry jumps instantly (no transition on left/top/width/height)
//   while invisible, then fades/scales in → mirrored here as constant
//   segments that step at 6.0.
// - web capture flight is left/top/width/height 780ms spring + fade 260/200ms.
// - web brand is opacity 700ms ease + rise 900ms spring; it ends at 9.7s, past
//   our 9.6s total, so brand segments start 8.7–8.9 (invisible until 8.9) and
//   land exactly at 9.6 — verified by value(at: 9.6) == .final.
// - The cursor's first leg is INTERRUPTED at 0.8s (prototype retargets
//   mid-flight): leg 2 starts from the eased mid-flight position, which only
//   a function of time can express — sequential keyframes force a false stop
//   at the (560,330) waypoint.
//
// Geometry note: every rect below is derived from the actual subview
// sizes in this file (window 600×310 at (140,64), cards 220×128 in
// the gutter, guide paper, thumbs), not eyeballed — so the halo,
// cursor and flying capture land on real pixels.

/// Every animatable channel of the intro scene.
/// All `Double`, mapped from the master clock by `IntroTimeline.value(at:)`.
public struct FirstRunIntroValues: Equatable {
    // cursor
    var cursorX: Double
    var cursorY: Double
    var cursorOpacity: Double
    var press: Double // 0 rest → 1 pressed (drives scale CONTINUOUSLY)
    // mock app window
    var winOpacity: Double
    var winY: Double // offset from rest (0 = rest)
    var winScale: Double
    // amber halo (CTA, then in-guide)
    var haloOpacity: Double
    var haloX: Double
    var haloY: Double
    var haloW: Double
    var haloH: Double
    var haloScale: Double // 0.9 → 1 pop (prototype transform 260ms spring-soft)
    // flying capture (uniform-scale card hand-off)
    var capOpacity: Double
    var capX: Double
    var capY: Double
    var capW: Double
    var capH: Double
    var capR: Double // corner radius 10 → 8 (prototype)
    // steps (opacity + slot position + shared width)
    var s1o: Double
    var s2o: Double
    var s3o: Double
    var s1x: Double
    var s1y: Double
    var s2x: Double
    var s2y: Double
    var s3x: Double
    var s3y: Double
    var cardW: Double
    var selected: Double // 0/1 step-01 selection ring
    // guide paper
    var guideOpacity: Double
    var guideX: Double
    var guideY: Double // top edge
    var guideW: Double
    var guideH: Double // animatable: 560 → 582 for the reader beat
    var guideScale: Double
    var readerT: Double // 0 doc → 1 reader (drives type/padding/thumb, 7.8–8.7)
    // AI panel
    var aiOpacity: Double
    var aiX: Double // slide offset (24 → 0, back to 24 on exit)
    // text morph (old → new label on step 01), driven CONTINUOUSLY (no Bool step)
    var morph: Double // 0 → 1 crossfade driver
    // brand end-card
    var brandOpacity: Double
    var brandY: Double
    // scene dimming for brand moment
    var sceneOpacity: Double // 1 → 0 as brand arrives (recede = 1 - sceneOpacity)

    static let canvasW: CGFloat = 880
    static let canvasH: CGFloat = 600

    /// Gutter slots (scene 4), canvas coords. Cards are 220×128.
    static let gutterY: Double = 442
    static let slotX: [Double] = [90, 330, 570]
    static let gutterW: Double = 220
    /// Guide rows (scenes 5–8), canvas coords. Same rows for doc and
    /// reader — only x/width animate after the guide forms.
    static let docX: Double = 230
    static let docAiX: Double = 180
    static let rowY: [Double] = [104, 250, 396]
    /// Reader rows: prototype READER sits ~30px above DOC with more air
    /// (web READER−DOC = −37/−30/−23 on an 800px canvas → ≈ −28/−22/−17 here).
    static let readerRowY: [Double] = [76, 228, 379]
    static let docW: Double = 420
    /// Reader: wider paper + wider cards, same rows.
    static let readerGuideX: Double = 160
    static let readerGuideW: Double = 560
    static let readerGuideH: Double = 582
    static let readerX: Double = 205
    static let readerW: Double = 470

    static var initial: Self {
        Self(
            cursorX: 940, cursorY: 510, cursorOpacity: 0, press: 0,
            winOpacity: 0, winY: 10, winScale: 0.985,
            haloOpacity: 0, haloX: 300, haloY: 250, haloW: 170, haloH: 60, haloScale: 0.9,
            capOpacity: 0, capX: 300, capY: 114, capW: 430, capH: 250.2, capR: 10,
            s1o: 0, s2o: 0, s3o: 0,
            s1x: slotX[0], s1y: gutterY,
            s2x: slotX[1], s2y: gutterY,
            s3x: slotX[2], s3y: gutterY,
            cardW: gutterW, selected: 0,
            guideOpacity: 0, guideX: 190, guideY: 32, guideW: 500, guideH: 560, guideScale: 0.975, readerT: 0,
            aiOpacity: 0, aiX: 24,
            morph: 0,
            brandOpacity: 0, brandY: 8,
            sceneOpacity: 1
        )
    }

    /// Reduce Motion / final state: MUST equal the timeline end exactly
    /// (reader composed, brand up, scene receded) so the static snapshot
    /// and the played-out frame agree.
    static var final: Self {
        Self(
            cursorX: 385, cursorY: 283, cursorOpacity: 0, press: 0,
            winOpacity: 0, winY: -6, winScale: 0.97,
            haloOpacity: 0, haloX: 564, haloY: 144, haloW: 72, haloH: 38, haloScale: 0.9,
            capOpacity: 0, capX: 90, capY: 442, capW: 220, capH: 128, capR: 8,
            s1o: 1, s2o: 1, s3o: 1,
            s1x: readerX, s1y: readerRowY[0],
            s2x: readerX, s2y: readerRowY[1],
            s3x: readerX, s3y: readerRowY[2],
            cardW: readerW, selected: 0,
            guideOpacity: 0, guideX: readerGuideX, guideY: 18, guideW: readerGuideW, guideH: readerGuideH, guideScale: 1.0, readerT: 1,
            aiOpacity: 0, aiX: 24,
            morph: 1,
            brandOpacity: 1, brandY: 0,
            sceneOpacity: 0
        )
    }
}

// MARK: - Keyframe timeline (9.6s, mirrors prototype beats)

/// Total timeline length, mirrored by `IntroTimeline.total`. The animator's
/// single linear track spans exactly this; every segment table in
/// `IntroTimeline` is bounded by it (`value(at: 9.6) == .final` locks it).
private let introTotal: TimeInterval = 9.6

// Segments live in IntroTimeline.swift (one table per channel).

// MARK: - Public first-run view (canvas + footer)

/// Linear master-clock value. The animator interpolates ONLY this (exact
/// linear 0 → 9.6); `IntroTimeline.value(at:)` maps it to every channel.
private struct IntroClock: Equatable {
    var t: Double
}

/// Explicit two-step first run: intro tour, then the onboarding
/// phase where visual defaults are picked.
public enum FirstRunPhase {
    case intro, setup
}

public struct FirstRunIntroView: View {
    var onDone: () -> Void = {}
    var onSkip: (() -> Void)? = nil
    var startingAt: FirstRunPhase = .intro

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playID = 0
    @State private var finished = false
    @State private var phase: FirstRunPhase = .intro

    public init(
        onDone: @escaping () -> Void = {},
        onSkip: (() -> Void)? = nil,
        startingAt: FirstRunPhase = .intro
    ) {
        self.onDone = onDone
        self.onSkip = onSkip
        self.startingAt = startingAt
        _phase = State(initialValue: startingAt)
    }

    public var body: some View {
        if phase == .setup {
            setupBody
        } else {
            introBody
        }
    }

    private var introBody: some View {
        VStack(spacing: 0) {
            header
            if reduceMotion {
                // Static end-state: same story beats as text, no motion.
                IntroCanvas(value: .final)
                    .onAppear { finished = true }
            } else {
                Color.clear
                    .keyframeAnimator(initialValue: IntroClock(t: 0), trigger: playID) { _, c in
                        IntroCanvas(value: IntroTimeline.value(at: c.t))
                    } keyframes: { _ in
                    // ONE linear master clock. Every channel is mapped from t
                    // inside IntroTimeline (exact CSS cubic-beziers via
                    // UnitBezier) — the animator itself only needs to be
                    // linear. See IntroTimeline.swift.
                    KeyframeTrack(\.t) {
                        LinearKeyframe(introTotal, duration: introTotal)
                    }
                    }
                    .onAppear { if playID == 0 { playID = 1 } }
                    .onChange(of: playID) { _, _ in finished = false }
                    .onChange(of: phase) { _, new in
                        // Returning from Setup re-inserts this view with the
                        // SAME trigger value → keyframeAnimator would sit
                        // frozen on its first frame. Bump to replay.
                        if new == .intro { playID += 1 }
                    }
                    .task(id: playID) {
                        guard playID != 0 else { return }
                        try? await Task.sleep(for: .seconds(introTotal + 0.6))
                        if !Task.isCancelled { finished = true }
                    }
            }
            footer
        }
        .background(FlowComponent.for(scheme).canvas)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome to Flowline. Watch how an interaction becomes a step, steps become a guide, and the guide becomes a readable document.")
    }

    private var header: some View {
        let t = FlowComponent.for(scheme)
        return VStack(spacing: 6) {
            Text("Turn what you do into guides")
                .font(.system(size: 22, weight: .semibold, design: .default))
                .foregroundColor(t.textPrimary)
            Text("Flowline captures your workflow and drafts the how-to for you.")
                .font(.system(size: 13))
                .foregroundColor(t.textSecondary)
        }
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    private var footer: some View {
        let t = FlowComponent.for(scheme)
        return HStack(spacing: 12) {
            // Always live (like the prototype's replay + Space): replaying
            // mid-tour cancels the in-flight .task via its id and restarts.
            Button("Replay") { playID += 1 }
                .buttonStyle(FlowPressStyle())
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(t.textSecondary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(t.surfaceSubtle)
                .cornerRadius(FlowComponent.radiusSM)

            Spacer()

            if onSkip != nil {
                Button("Skip tour") { phase = .setup }
                    .buttonStyle(FlowPressStyle())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(t.textSecondary)
            }
            Button("Continue") { phase = .setup }
                .buttonStyle(FlowPressStyle())
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(t.primaryFg)
                .padding(.horizontal, 18).padding(.vertical, 8)
                .background(t.primaryBg)
                .cornerRadius(FlowComponent.radiusSM)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var setupBody: some View {
        let t = FlowComponent.for(scheme)
        return VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Make it yours")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(t.textPrimary)
                Text("New guides start from these. You can change them later in Settings → Onboarding.")
                    .font(.system(size: 13))
                    .foregroundColor(t.textSecondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 8)
            OnboardingSetupView(
                onSave: { _ in onDone() },
                onBack: { phase = .intro }
            )
            HStack(spacing: 12) {
                Spacer()
                Button("Skip for now") {
                    if let onSkip { onSkip() } else { onDone() }
                }
                    .buttonStyle(FlowPressStyle())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(t.textSecondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 14)
        }
        .background(FlowComponent.for(scheme).canvas)
    }
}

// MARK: - Canvas (pure function of IntroValues — no local state, no nested animations)

private func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }

struct IntroCanvas: View {
    var value: FirstRunIntroValues

    @Environment(\.colorScheme) private var scheme

    /// Beat caption. Order mirrors the prototype phases; the reader beat is
    /// keyed off readerT (morph stays 1 through it, so morph must NOT win).
    private var caption: String {
        if value.brandOpacity > 0.4 { return "Your workflow, ready to share" }
        if value.readerT > 0.5 { return "A readable document, ready to share" }
        if value.aiOpacity > 0.3 { return "Refine wording — screenshots untouched" }
        if value.morph > 0.5 { return "Refine wording — screenshots untouched" }
        if value.guideOpacity > 0.4 { return "Steps collect into a guide" }
        if value.s2o > 0.5 { return "Every action becomes a step" }
        if value.capOpacity > 0.3 { return "Flowline captures the moment" }
        if value.winOpacity > 0.5 { return "Do your work as usual" }
        return "Watch what Flowline sees"
    }

    var body: some View {
        let t = FlowComponent.for(scheme)
        // Card chrome dissolves with the paper (prototype: border/shadow fade
        // fast, padding glides slow — here one continuous mix over the 0.6s
        // guide ramp, firing from ~4.53 instead of a late 0.4 snap).
        let docMix = clamp01(value.guideOpacity)
        // Brand recede drift (prototype: Y −8, scale .985 over the fade).
        let recede = 1 - value.sceneOpacity
        let cardH = 128.0 + 6 * value.readerT
        // Head reveal lags the paper (prototype: 350ms delay).
        let headMix = clamp01((value.guideOpacity - 0.35) / 0.65)
        ZStack {
            // guide paper (behind steps)
            GuidePaper(headMix: headMix, footMix: value.readerT)
                .frame(width: CGFloat(value.guideW), height: CGFloat(value.guideH))
                .position(
                    x: CGFloat(value.guideX + value.guideW / 2),
                    y: CGFloat(value.guideY + value.guideH / 2)
                )
                .opacity(value.guideOpacity * value.sceneOpacity)
                .scaleEffect(CGFloat(value.guideScale))
                .scaleEffect(1 - 0.015 * CGFloat(recede))
                .offset(y: -8 * CGFloat(recede))

            // mock app window
            MockAppWindow(press: value.press)
                .frame(width: 600, height: 310)
                .position(x: 440, y: CGFloat(219 + value.winY))
                .opacity(value.winOpacity * value.sceneOpacity)
                .scaleEffect(CGFloat(value.winScale))

            // three step cards. Entrance rise/de-zoom derive from the opacity
            // channel itself (12px → 0, 0.96 → 1) so they can never desync.
            // position.x = left + width/2 every frame keeps the LEFT edge
            // glued to sNx even while cardW animates (web `left` semantics).
            StepCard(
                num: "01",
                oldTitle: "Click “Create project”", newTitle: "Create a new project",
                morph: value.morph,
                isFirst: true,
                selected: value.selected > 0.5, showThumbButton: true,
                docMix: docMix, readerT: value.readerT
            )
            .frame(width: CGFloat(value.cardW), height: CGFloat(cardH))
            .position(x: CGFloat(value.s1x + value.cardW / 2), y: CGFloat(value.s1y + cardH / 2))
            .scaleEffect(0.96 + 0.04 * CGFloat(value.s1o))
            .offset(y: CGFloat(12 * (1 - value.s1o) - 8 * recede))
            .scaleEffect(1 - 0.015 * CGFloat(recede))
            .opacity(value.s1o * value.sceneOpacity)

            StepCard(num: "02", title: "Name the project", morph: 0, isFirst: false, selected: false, showThumbButton: false, thumbKind: .field, docMix: docMix, readerT: value.readerT)
                .frame(width: CGFloat(value.cardW), height: CGFloat(cardH))
                .position(x: CGFloat(value.s2x + value.cardW / 2), y: CGFloat(value.s2y + cardH / 2))
                .scaleEffect(0.96 + 0.04 * CGFloat(value.s2o))
                .offset(y: CGFloat(12 * (1 - value.s2o) - 8 * recede))
                .scaleEffect(1 - 0.015 * CGFloat(recede))
                .opacity(value.s2o * value.sceneOpacity)

            StepCard(num: "03", title: "Choose a template", morph: 0, isFirst: false, selected: false, showThumbButton: false, thumbKind: .rows, docMix: docMix, readerT: value.readerT)
                .frame(width: CGFloat(value.cardW), height: CGFloat(cardH))
                .position(x: CGFloat(value.s3x + value.cardW / 2), y: CGFloat(value.s3y + cardH / 2))
                .scaleEffect(0.96 + 0.04 * CGFloat(value.s3o))
                .offset(y: CGFloat(12 * (1 - value.s3o) - 8 * recede))
                .scaleEffect(1 - 0.015 * CGFloat(recede))
                .opacity(value.s3o * value.sceneOpacity)

            // flying capture: the step-01 card, uniform-scaled onto its slot.
            // alignment MUST be .topLeading: the inner card scales about its
            // own top-left, which then coincides with the outer frame's
            // top-left (a center-aligned ZStack offsets it by half the
            // size delta — the old 90px detach bug). Outer clips to the
            // animated radius; shadow keeps a constant radius and fades by
            // alpha (no per-tick shadow re-render).
            ZStack(alignment: .topLeading) {
                StepCard(
                    num: "01",
                    oldTitle: "Click “Create project”", newTitle: "Create a new project",
                    morph: 0,
                    isFirst: true, selected: false, showThumbButton: true,
                    docMix: 0, readerT: 0
                )
                .frame(width: 220, height: 128)
                .scaleEffect(
                    CGFloat(min(value.capW / 220, value.capH / 128)),
                    anchor: .topLeading
                )
            }
            .frame(width: CGFloat(value.capW), height: CGFloat(value.capH))
            .clipShape(RoundedRectangle(cornerRadius: CGFloat(value.capR)))
            .position(x: CGFloat(value.capX + value.capW / 2), y: CGFloat(value.capY + value.capH / 2))
            .opacity(value.capOpacity * value.sceneOpacity)
            .shadow(color: .black.opacity(0.18 * value.capOpacity), radius: 28, y: 10)

            // amber halo (interaction, then in-guide). Pops 0.9 → 1 via
            // haloScale; the outer pulse ring approximates the prototype's
            // one-shot halo-pulse (inset −4, 0.7 → 0 over 900ms) as a static
            // ring riding the same opacity — no extra clock needed.
            ZStack {
                RoundedRectangle(cornerRadius: value.haloW < 100 ? 12 : 10)
                    .stroke(FlowSemantic.for(scheme).haloBorder, lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: value.haloW < 100 ? 12 : 10)
                            .fill(FlowSemantic.for(scheme).haloFill)
                    )
                    .frame(width: CGFloat(value.haloW), height: CGFloat(value.haloH))
                    .scaleEffect(CGFloat(value.haloScale))
                RoundedRectangle(cornerRadius: (value.haloW < 100 ? 12 : 10) + 4)
                    .stroke(FlowSemantic.for(scheme).haloBorder, lineWidth: 1.5)
                    .frame(width: CGFloat(value.haloW + 8), height: CGFloat(value.haloH + 8))
                    .scaleEffect(CGFloat(value.haloScale * 1.04))
                    .opacity(value.haloOpacity * 0.5)
            }
            .position(x: CGFloat(value.haloX + value.haloW / 2), y: CGFloat(value.haloY + value.haloH / 2))
            .opacity(value.haloOpacity * value.sceneOpacity)

            // AI refinement panel (slides back +24 while fading on exit).
            AIRefinePanel()
                .frame(width: 180)
                .position(x: CGFloat(736 + value.aiX), y: 240)
                .offset(y: -8 * CGFloat(recede))
                .opacity(value.aiOpacity * value.sceneOpacity)

            // cursor (continuous press scale — never a Bool snap).
            CursorView(press: value.press)
                .position(x: CGFloat(value.cursorX), y: CGFloat(value.cursorY))
                .opacity(value.cursorOpacity * value.sceneOpacity)

            // beat caption (fades in with the scene instead of popping).
            Text(caption)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(t.textSecondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(t.surface)
                .cornerRadius(FlowComponent.radiusSM)
                .overlay(RoundedRectangle(cornerRadius: FlowComponent.radiusSM).stroke(t.border, lineWidth: 1))
                .position(x: FirstRunIntroValues.canvasW / 2, y: FirstRunIntroValues.canvasH - 14)
                .opacity(value.sceneOpacity * CGFloat(clamp01(max(value.winOpacity, value.s1o) * 2.5)))

            // brand end-card (hit-test gated: invisible overlay must not
            // swallow clicks for 9s).
            VStack(spacing: 10) {
                Text("Flowline")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(t.textPrimary)
                Text("Turn what you do into guides.")
                    .font(.system(size: 15))
                    .foregroundColor(t.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(value.brandOpacity)
            .offset(y: CGFloat(value.brandY))
            .allowsHitTesting(value.brandOpacity > 0.5)
        }
        .frame(width: FirstRunIntroValues.canvasW, height: FirstRunIntroValues.canvasH)
        .clipped()
    }
}

// MARK: - Scene pieces (tokens only, no hard-coded palette)

private struct MockAppWindow: View {
    /// Continuous 0 → 1 press (prototype: 130ms down/up + CTA bg darken).
    var press: Double
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let t = FlowComponent.for(scheme)
        let sem = FlowSemantic.for(scheme)
        // #3478F6 → #2C6BE0 lerped by press (prototype 160ms bg ease).
        let cta = Color(
            red: (52 - 8 * press) / 255,
            green: (120 - 13 * press) / 255,
            blue: (246 - 22 * press) / 255
        )
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                ForEach(0..<3) { _ in Circle().fill(t.border).frame(width: 11, height: 11) }
                Spacer()
                Text("Projects").font(.system(size: 12, weight: .medium)).foregroundColor(t.textSecondary)
                Spacer()
                Color.clear.frame(width: 44)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(t.surfaceSubtle.opacity(0.6))
            Divider().background(t.borderSubtle)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WORKSPACE").font(.system(size: 10, weight: .semibold)).foregroundColor(t.textTertiary).padding(.bottom, 4)
                    Text("Projects").font(.system(size: 12.5, weight: .medium)).foregroundColor(sem.accentDefault)
                        .padding(.horizontal, 8).padding(.vertical, 5).background(sem.accentSubtle).cornerRadius(6)
                    Text("Templates").font(.system(size: 12.5)).foregroundColor(t.textSecondary).padding(.horizontal, 8)
                    Text("Archive").font(.system(size: 12.5)).foregroundColor(t.textSecondary).padding(.horizontal, 8)
                    Spacer()
                }
                .frame(width: 150).padding(12)
                Divider().background(t.borderSubtle)
                VStack(alignment: .leading, spacing: 0) {
                    Text("New project").font(.system(size: 19, weight: .semibold)).foregroundColor(t.textPrimary)
                    Text("Name it now — you can change it later.").font(.system(size: 12.5)).foregroundColor(t.textSecondary).padding(.top, 5).padding(.bottom, 16)
                    Text("Project name").font(.system(size: 11, weight: .medium)).foregroundColor(t.textSecondary).padding(.bottom, 6)
                    Text("Website refresh").font(.system(size: 13)).foregroundColor(t.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(t.surface).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(t.border, lineWidth: 1))
                    Text("Create project").font(.system(size: 13, weight: .medium)).foregroundColor(.white)
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(cta).cornerRadius(8)
                        .scaleEffect(1 - 0.035 * CGFloat(press))
                        .padding(.top, 16)
                    Spacer()
                }
                .padding(26)
            }
        }
        .background(t.surface)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(t.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.14), radius: 30, y: 12)
    }
}

private struct StepCard: View {
    enum ThumbKind { case create, field, rows }
    var num: String
    var title: String? = nil
    var oldTitle: String? = nil
    var newTitle: String? = nil
    /// Continuous morph driver 0 → 1 (prototype: 420ms crossfade, ∓6px).
    /// NEVER Bool-threshold this or add .animation — the keyframe clock owns it.
    var morph: Double = 0
    var isFirst: Bool = false
    var selected: Bool = false
    var showThumbButton: Bool = false
    var thumbKind: ThumbKind = .create
    /// 0 = card chrome, 1 = document section (prototype .is-guide: border/
    /// shadow/bg/padding dissolve). Continuous so the guide forms as a glide.
    var docMix: Double = 0
    /// 0 = doc, 1 = reader (prototype .is-reader: airier type + padding).
    var readerT: Double = 0
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let t = FlowComponent.for(scheme)
        let sem = FlowSemantic.for(scheme)
        let m = clamp01(morph)
        let chrome = 1 - clamp01(docMix)
        let pad = 12 * chrome + 14 * clamp01(readerT)
        VStack(alignment: .leading, spacing: 0) {
            Text(num)
                .font(.system(size: 10 + 1 * readerT, weight: .semibold, design: .monospaced))
                .foregroundColor(clamp01(docMix) > 0.5 ? sem.accentDefault : t.textTertiary)
                .padding(.bottom, 8)
            MiniThumb(kind: thumbKind, showButton: showThumbButton, readerT: readerT)
            ZStack(alignment: .topLeading) {
                if isFirst, let old = oldTitle, let new = newTitle {
                    // Pure function of m: old lifts −6 and fades, new rises
                    // from +6 — exactly the prototype lbl-a/lbl-b crossfade.
                    Text(old).font(.system(size: 12.5 + 1 * readerT)).foregroundColor(t.textPrimary)
                        .opacity(1 - m).offset(y: -6 * CGFloat(m))
                    Text(new).font(.system(size: 12.5 + 1 * readerT, weight: .medium)).foregroundColor(t.textPrimary)
                        .opacity(m).offset(y: 6 * CGFloat(1 - m))
                } else {
                    Text(title ?? "").font(.system(size: 12.5 + 1 * readerT)).foregroundColor(t.textPrimary)
                }
            }
            .padding(.top, 10)
        }
        .padding(pad)
        .background(t.surface.opacity(chrome))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    selected ? sem.accentDefault.opacity(0.55) : t.border.opacity(CGFloat(chrome)),
                    lineWidth: selected ? 1.5 : 1
                )
        )
        .shadow(color: .black.opacity(0.06 * Double(chrome)), radius: 10, y: 3)
    }
}

/// Screenshot thumbnail skeleton. Step 01 mirrors the mock window
/// (field + Create button) so the flying capture lands on its twin.
private struct MiniThumb: View {
    var kind: StepCard.ThumbKind
    var showButton: Bool
    /// 0 = doc, 1 = reader (prototype thumb 108 → 100, radius 8 → 10).
    var readerT: Double = 0
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let t = FlowComponent.for(scheme)
        let sem = FlowSemantic.for(scheme)
        RoundedRectangle(cornerRadius: 8 + 2 * CGFloat(readerT))
            .fill(t.surfaceSubtle.opacity(0.7))
            .frame(height: 52 - 4 * CGFloat(readerT))
            .overlay(thumbContent(t: t, sem: sem))
            .overlay(RoundedRectangle(cornerRadius: 8 + 2 * CGFloat(readerT)).stroke(t.borderSubtle, lineWidth: 1))
    }

    @ViewBuilder
    private func thumbContent(t: FlowComponent, sem: FlowSemantic) -> some View {
        switch kind {
        case .create:
            HStack {
                RoundedRectangle(cornerRadius: 4).fill(t.border).frame(width: 40, height: 8)
                Spacer()
                if showButton {
                    Text("Create").font(.system(size: 9, weight: .medium)).foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5).background(sem.accentDefault).cornerRadius(6)
                }
            }.padding(.horizontal, 10)
        case .field:
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(t.border, lineWidth: 1)
                    .frame(width: 72, height: 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2).fill(sem.accentDefault).frame(width: 1.5, height: 10),
                        alignment: .leading
                    )
                    .padding(.leading, 6)
                RoundedRectangle(cornerRadius: 3).fill(t.borderSubtle).frame(width: 44, height: 6)
                Spacer()
            }.padding(.horizontal, 4)
        case .rows:
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(t.surfaceSubtle).frame(width: 84, height: 12)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(t.border, lineWidth: 1))
                RoundedRectangle(cornerRadius: 4).fill(sem.accentSubtle).frame(width: 84, height: 12)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(sem.accentDefault.opacity(0.55), lineWidth: 1))
            }.padding(.horizontal, 10)
        }
    }
}

private struct GuidePaper: View {
    /// 0 → 1 delayed head reveal (prototype: title/meta lag the paper 350ms).
    var headMix: Double = 1
    /// 0 → 1 published-foot reveal (prototype: foot appears in reader).
    var footMix: Double = 1
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let t = FlowComponent.for(scheme)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Create a Project").font(.system(size: 22, weight: .semibold)).foregroundColor(t.textPrimary).padding(.top, 30)
                Text("Guide · 3 steps · captured just now").font(.system(size: 11.5)).foregroundColor(t.textSecondary).padding(.top, 5)
            }
            .opacity(headMix)
            .offset(y: 8 * (1 - CGFloat(headMix)))
            Spacer()
            Text("Published with Flowline").font(.system(size: 10.5)).foregroundColor(t.textTertiary).padding(.bottom, 20)
                .opacity(footMix)
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(t.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(t.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.13), radius: 28, y: 10)
    }
}

private struct AIRefinePanel: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let t = FlowComponent.for(scheme)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle().fill(t.textTertiary).frame(width: 7, height: 7)
                Text("Refine").font(.system(size: 12, weight: .semibold)).foregroundColor(t.textPrimary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Click create project").font(.system(size: 10.5, design: .monospaced)).foregroundColor(t.textTertiary).strikethrough()
                Image(systemName: "arrow.down").font(.system(size: 10)).foregroundColor(t.textTertiary)
                Text("Create a new project").font(.system(size: 10.5, design: .monospaced)).foregroundColor(t.textPrimary)
            }
            .padding(11)
            .background(t.surfaceSubtle.opacity(0.7))
            .cornerRadius(9)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(t.borderSubtle, lineWidth: 1))
            Text("Reworded the step. Screenshot unchanged.").font(.system(size: 10.5)).foregroundColor(t.textSecondary).lineLimit(3)
        }
        .padding(15)
        .background(t.surface)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(t.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.09), radius: 14, y: 4)
    }
}

/// Real pointer shape (prototype SVG), not an SF Symbol.
private struct CursorView: View {
    /// Continuous 0 → 1 press (prototype: inner scale 1 → 0.86, 130ms).
    var press: Double
    @Environment(\.colorScheme) private var scheme
    private var pointer: Path {
        Path { p in
            p.move(to: CGPoint(x: 2, y: 0))
            p.addLine(to: CGPoint(x: 2, y: 20))
            p.addLine(to: CGPoint(x: 6.5, y: 15.5))
            p.addLine(to: CGPoint(x: 9, y: 22))
            p.addLine(to: CGPoint(x: 11.5, y: 20.8))
            p.addLine(to: CGPoint(x: 9, y: 14.5))
            p.addLine(to: CGPoint(x: 14, y: 14.5))
            p.closeSubpath()
        }
    }
    var body: some View {
        let t = FlowComponent.for(scheme)
        pointer
            .fill(t.textPrimary)
            .overlay(pointer.stroke(t.textInverse, lineWidth: 1.4))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .scaleEffect(1 - 0.14 * CGFloat(press))
            .frame(width: 16, height: 24)
    }
}
