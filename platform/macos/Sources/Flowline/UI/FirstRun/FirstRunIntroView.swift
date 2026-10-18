import SwiftUI

// MARK: - First-run intro: keyframe-driven product story
//
// Native SwiftUI port of the `intro-prototype` web timeline
// (interaction → capture → steps → guide → halo → AI refine →
// reader → brand). The whole scene is ONE keyframe timeline:
// `FirstRunIntroValues` holds every animatable channel, advanced on
// a single 9.6s clock. No timers, no JS — pure `keyframeAnimator`.
// Reduce Motion collapses to the end state.
//
// Geometry note: every rect below is derived from the actual subview
// sizes in this file (window 600×310 at (140,64), cards 220×128 in
// the gutter, guide paper, thumbs), not eyeballed — so the halo,
// cursor and flying capture land on real pixels.

/// Every animatable channel of the intro scene.
/// All `Double` so each gets its own `KeyframeTrack`.
public struct FirstRunIntroValues: Equatable {
    // cursor
    var cursorX: Double
    var cursorY: Double
    var cursorOpacity: Double
    var press: Double // 0 rest → 1 pressed (drives scale)
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
    // flying capture (uniform-scale card hand-off)
    var capOpacity: Double
    var capX: Double
    var capY: Double
    var capW: Double
    var capH: Double
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
    var guideScale: Double
    // AI panel
    var aiOpacity: Double
    var aiX: Double // slide offset (24 → 0)
    // text morph (old → new label on step 01)
    var morph: Double // 0/1 crossfade driver
    // brand end-card
    var brandOpacity: Double
    var brandY: Double
    // scene dimming for brand moment
    var sceneOpacity: Double // 1 → 0 as brand arrives

    static let canvasW: CGFloat = 880
    static let canvasH: CGFloat = 600
    static let guideH: CGFloat = 560

    /// Gutter slots (scene 4), canvas coords. Cards are 220×128.
    static let gutterY: Double = 442
    static let slotX: [Double] = [90, 330, 570]
    static let gutterW: Double = 220
    /// Guide rows (scenes 5–8), canvas coords. Same rows for doc and
    /// reader — only x/width animate after the guide forms.
    static let docX: Double = 230
    static let docAiX: Double = 180
    static let rowY: [Double] = [104, 250, 396]
    static let docW: Double = 420
    /// Reader: wider paper + wider cards, same rows.
    static let readerGuideX: Double = 160
    static let readerGuideW: Double = 560
    static let readerX: Double = 205
    static let readerW: Double = 470

    static var initial: Self {
        Self(
            cursorX: 940, cursorY: 540, cursorOpacity: 0, press: 0,
            winOpacity: 0, winY: 10, winScale: 0.985,
            haloOpacity: 0, haloX: 300, haloY: 250, haloW: 170, haloH: 60,
            capOpacity: 0, capX: 270, capY: 120, capW: 400, capH: 233,
            s1o: 0, s2o: 0, s3o: 0,
            s1x: slotX[0], s1y: gutterY,
            s2x: slotX[1], s2y: gutterY,
            s3x: slotX[2], s3y: gutterY,
            cardW: gutterW, selected: 0,
            guideOpacity: 0, guideX: 190, guideY: 32, guideW: 500, guideScale: 0.975,
            aiOpacity: 0, aiX: 24,
            morph: 0,
            brandOpacity: 0, brandY: 8,
            sceneOpacity: 1
        )
    }

    /// Reduce Motion / final state: reader composed, brand up.
    static var final: Self {
        var v = initial
        v.cursorOpacity = 0
        v.winOpacity = 0
        v.haloOpacity = 0
        v.capOpacity = 0
        v.s1o = 0; v.s2o = 0; v.s3o = 0
        v.guideOpacity = 0
        v.aiOpacity = 0
        v.morph = 1
        v.brandOpacity = 1; v.brandY = 0
        v.sceneOpacity = 0
        v.selected = 0
        return v
    }
}

// MARK: - Keyframe timeline (9.6s, mirrors prototype beats)

/// Total timeline length. EVERY track below sums to this — a track that
/// ends early freezes its channel, one that overruns stretches the whole
/// scene, so keep them in sync when editing.
private let introTotal: TimeInterval = 9.6

// Keyframe tracks are inlined in FirstRunIntroView.keyframes below (inference requires inline context).

// MARK: - Public first-run view (canvas + footer)

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
                IntroCanvas(value: .final, morphed: true)
                    .onAppear { finished = true }
            } else {
                Color.clear
                    .keyframeAnimator(initialValue: FirstRunIntroValues.initial, trigger: playID) { _, v in
                        IntroCanvas(value: v, morphed: v.morph > 0.5)
                    } keyframes: { _ in
        // — cursor: off-canvas → park → CTA centre (385,283), gone by 3.25
        KeyframeTrack(\.cursorX) {
            LinearKeyframe(940, duration: 0.12)
            CubicKeyframe(560, duration: 0.68)
            CubicKeyframe(385, duration: 0.66)
            LinearKeyframe(385, duration: 1.79)
            LinearKeyframe(385, duration: 6.35)
        }
        KeyframeTrack(\.cursorY) {
            LinearKeyframe(540, duration: 0.12)
            CubicKeyframe(330, duration: 0.68)
            CubicKeyframe(283, duration: 0.66)
            LinearKeyframe(283, duration: 1.79)
            LinearKeyframe(283, duration: 6.35)
        }
        KeyframeTrack(\.cursorOpacity) {
            LinearKeyframe(0, duration: 0.12)
            LinearKeyframe(1, duration: 0.2)
            LinearKeyframe(1, duration: 2.68)
            LinearKeyframe(0, duration: 0.25)
            LinearKeyframe(0, duration: 6.35)
        }
        KeyframeTrack(\.press) {
            LinearKeyframe(0, duration: 1.46)
            CubicKeyframe(1, duration: 0.12)
            CubicKeyframe(0, duration: 0.14)
            LinearKeyframe(0, duration: 7.88)
        }
        // — mock window: fades in, recedes as the capture fires (gone by 2.4)
        KeyframeTrack(\.winOpacity) {
            LinearKeyframe(0, duration: 0.1)
            LinearKeyframe(1, duration: 0.5)
            LinearKeyframe(1, duration: 1.4)
            LinearKeyframe(0, duration: 0.4)
            LinearKeyframe(0, duration: 7.2)
        }
        KeyframeTrack(\.winY) {
            LinearKeyframe(10, duration: 0.1)
            CubicKeyframe(0, duration: 0.7)
            CubicKeyframe(0, duration: 1.2)
            CubicKeyframe(-6, duration: 0.4)
            LinearKeyframe(-6, duration: 7.2)
        }
        KeyframeTrack(\.winScale) {
            LinearKeyframe(0.985, duration: 0.1)
            CubicKeyframe(1.0, duration: 0.7)
            CubicKeyframe(1.0, duration: 1.2)
            CubicKeyframe(0.97, duration: 0.4)
            LinearKeyframe(0.97, duration: 7.2)
        }
        // — halo: on CTA (1.46–2.0), then on the step-01 button (6.0–6.65)
        KeyframeTrack(\.haloOpacity) {
            LinearKeyframe(0, duration: 1.46)
            LinearKeyframe(1, duration: 0.12)
            LinearKeyframe(1, duration: 0.42)
            LinearKeyframe(0, duration: 0.2)
            LinearKeyframe(0, duration: 3.8)
            LinearKeyframe(1, duration: 0.15)
            LinearKeyframe(1, duration: 0.5)
            LinearKeyframe(0, duration: 0.2)
            LinearKeyframe(0, duration: 2.75)
        }
        // halo geometry: CTA box → step-01 button box. Holds are constant
        // while opacity is 0, so nothing visibly drifts.
        KeyframeTrack(\.haloX) {
            LinearKeyframe(300, duration: 6.0)
            CubicKeyframe(564, duration: 0.4)
            LinearKeyframe(564, duration: 3.2)
        }
        KeyframeTrack(\.haloY) {
            LinearKeyframe(250, duration: 6.0)
            CubicKeyframe(144, duration: 0.4)
            LinearKeyframe(144, duration: 3.2)
        }
        KeyframeTrack(\.haloW) {
            LinearKeyframe(170, duration: 6.0)
            CubicKeyframe(72, duration: 0.4)
            LinearKeyframe(72, duration: 3.2)
        }
        KeyframeTrack(\.haloH) {
            LinearKeyframe(60, duration: 6.0)
            CubicKeyframe(38, duration: 0.4)
            LinearKeyframe(38, duration: 3.2)
        }
        // — capture: a full step card flies window → step-01 slot (2.0–2.78,
        // uniform 0.55 scale), gone by 3.0 as the real card fades in
        KeyframeTrack(\.capOpacity) {
            LinearKeyframe(0, duration: 2.0)
            LinearKeyframe(1, duration: 0.1)
            LinearKeyframe(1, duration: 0.68)
            LinearKeyframe(0, duration: 0.2)
            LinearKeyframe(0, duration: 6.62)
        }
        KeyframeTrack(\.capX) {
            LinearKeyframe(270, duration: 2.0)
            CubicKeyframe(90, duration: 0.78)
            LinearKeyframe(90, duration: 6.82)
        }
        KeyframeTrack(\.capY) {
            LinearKeyframe(120, duration: 2.0)
            CubicKeyframe(442, duration: 0.78)
            LinearKeyframe(442, duration: 6.82)
        }
        KeyframeTrack(\.capW) {
            LinearKeyframe(400, duration: 2.0)
            CubicKeyframe(220, duration: 0.78)
            LinearKeyframe(220, duration: 6.82)
        }
        KeyframeTrack(\.capH) {
            LinearKeyframe(233, duration: 2.0)
            CubicKeyframe(128, duration: 0.78)
            LinearKeyframe(128, duration: 6.82)
        }
        // — steps: s1 lands with the capture (2.0); s2/s3 fade in at
        // their own slots (3.14 / 3.5) — no travel through each other
        KeyframeTrack(\.s1o) {
            LinearKeyframe(0, duration: 2.0)
            LinearKeyframe(1, duration: 0.3)
            LinearKeyframe(1, duration: 7.3)
        }
        KeyframeTrack(\.s2o) {
            LinearKeyframe(0, duration: 3.14)
            LinearKeyframe(1, duration: 0.3)
            LinearKeyframe(1, duration: 6.16)
        }
        KeyframeTrack(\.s3o) {
            LinearKeyframe(0, duration: 3.5)
            LinearKeyframe(1, duration: 0.3)
            LinearKeyframe(1, duration: 5.8)
        }
        // s1x: slot 0 → doc (4.5–5.4) → hold → doc-ai (6.8–7.4) →
        // hold → reader (7.8–8.4) → hold. s2x/s3x identical from slots.
        KeyframeTrack(\.s1x) {
            LinearKeyframe(FirstRunIntroValues.slotX[0], duration: 4.5)
            CubicKeyframe(FirstRunIntroValues.docX, duration: 0.9)
            LinearKeyframe(FirstRunIntroValues.docX, duration: 1.4)
            CubicKeyframe(FirstRunIntroValues.docAiX, duration: 0.6)
            LinearKeyframe(FirstRunIntroValues.docAiX, duration: 0.4)
            CubicKeyframe(FirstRunIntroValues.readerX, duration: 0.6)
            LinearKeyframe(FirstRunIntroValues.readerX, duration: 1.2)
        }
        KeyframeTrack(\.s1y) {
            LinearKeyframe(FirstRunIntroValues.gutterY, duration: 4.5)
            CubicKeyframe(FirstRunIntroValues.rowY[0], duration: 0.9)
            LinearKeyframe(FirstRunIntroValues.rowY[0], duration: 4.2)
        }
        KeyframeTrack(\.s2x) {
            LinearKeyframe(FirstRunIntroValues.slotX[1], duration: 4.5)
            CubicKeyframe(FirstRunIntroValues.docX, duration: 0.9)
            LinearKeyframe(FirstRunIntroValues.docX, duration: 1.4)
            CubicKeyframe(FirstRunIntroValues.docAiX, duration: 0.6)
            LinearKeyframe(FirstRunIntroValues.docAiX, duration: 0.4)
            CubicKeyframe(FirstRunIntroValues.readerX, duration: 0.6)
            LinearKeyframe(FirstRunIntroValues.readerX, duration: 1.2)
        }
        KeyframeTrack(\.s2y) {
            LinearKeyframe(FirstRunIntroValues.gutterY, duration: 4.5)
            CubicKeyframe(FirstRunIntroValues.rowY[1], duration: 0.9)
            LinearKeyframe(FirstRunIntroValues.rowY[1], duration: 4.2)
        }
        KeyframeTrack(\.s3x) {
            LinearKeyframe(FirstRunIntroValues.slotX[2], duration: 4.5)
            CubicKeyframe(FirstRunIntroValues.docX, duration: 0.9)
            LinearKeyframe(FirstRunIntroValues.docX, duration: 1.4)
            CubicKeyframe(FirstRunIntroValues.docAiX, duration: 0.6)
            LinearKeyframe(FirstRunIntroValues.docAiX, duration: 0.4)
            CubicKeyframe(FirstRunIntroValues.readerX, duration: 0.6)
            LinearKeyframe(FirstRunIntroValues.readerX, duration: 1.2)
        }
        KeyframeTrack(\.s3y) {
            LinearKeyframe(FirstRunIntroValues.gutterY, duration: 4.5)
            CubicKeyframe(FirstRunIntroValues.rowY[2], duration: 0.9)
            LinearKeyframe(FirstRunIntroValues.rowY[2], duration: 4.2)
        }
        // shared card width: gutter 220 → doc 420 (4.5–5.4) → hold →
        // reader 470 (7.8–8.4) → hold
        KeyframeTrack(\.cardW) {
            LinearKeyframe(220, duration: 4.5)
            CubicKeyframe(420, duration: 0.9)
            LinearKeyframe(420, duration: 2.4)
            CubicKeyframe(470, duration: 0.6)
            LinearKeyframe(470, duration: 1.2)
        }
        // step-01 selected ring (4.2 → 4.5, clears as the guide forms)
        KeyframeTrack(\.selected) {
            LinearKeyframe(0, duration: 4.2)
            LinearKeyframe(1, duration: 0.15)
            LinearKeyframe(1, duration: 0.15)
            LinearKeyframe(0, duration: 0.2)
            LinearKeyframe(0, duration: 4.9)
        }
        // — guide paper rises at 4.5, shifts for AI (6.8) / reader (7.8),
        // recedes at 9.0
        KeyframeTrack(\.guideOpacity) {
            LinearKeyframe(0, duration: 4.5)
            LinearKeyframe(1, duration: 0.4)
            LinearKeyframe(1, duration: 4.1)
            LinearKeyframe(0, duration: 0.55)
            LinearKeyframe(0, duration: 0.05)
        }
        KeyframeTrack(\.guideX) {
            LinearKeyframe(190, duration: 6.8)
            CubicKeyframe(140, duration: 0.6)
            LinearKeyframe(140, duration: 0.4)
            CubicKeyframe(160, duration: 0.6)
            LinearKeyframe(160, duration: 1.2)
        }
        KeyframeTrack(\.guideY) {
            LinearKeyframe(32, duration: 4.5)
            CubicKeyframe(20, duration: 0.7)
            LinearKeyframe(20, duration: 4.4)
        }
        KeyframeTrack(\.guideW) {
            LinearKeyframe(500, duration: 7.8)
            CubicKeyframe(560, duration: 0.6)
            LinearKeyframe(560, duration: 1.2)
        }
        KeyframeTrack(\.guideScale) {
            LinearKeyframe(0.975, duration: 4.5)
            CubicKeyframe(1.0, duration: 0.7)
            LinearKeyframe(1.0, duration: 4.4)
        }
        // — AI panel slides in at 6.8, leaves at 7.8
        KeyframeTrack(\.aiOpacity) {
            LinearKeyframe(0, duration: 6.8)
            LinearKeyframe(1, duration: 0.3)
            LinearKeyframe(1, duration: 0.7)
            LinearKeyframe(0, duration: 0.3)
            LinearKeyframe(0, duration: 1.5)
        }
        KeyframeTrack(\.aiX) {
            LinearKeyframe(24, duration: 6.8)
            CubicKeyframe(0, duration: 0.5)
            LinearKeyframe(0, duration: 2.3)
        }
        // — label morph at 7.35
        KeyframeTrack(\.morph) {
            LinearKeyframe(0, duration: 7.35)
            LinearKeyframe(1, duration: 0.3)
            LinearKeyframe(1, duration: 1.95)
        }
        // — brand end-card at 9.0, scene recedes with it
        KeyframeTrack(\.brandOpacity) {
            LinearKeyframe(0, duration: 9.0)
            LinearKeyframe(1, duration: 0.5)
            LinearKeyframe(1, duration: 0.1)
        }
        KeyframeTrack(\.brandY) {
            LinearKeyframe(8, duration: 9.0)
            CubicKeyframe(0, duration: 0.6)
        }
        KeyframeTrack(\.sceneOpacity) {
            LinearKeyframe(1, duration: 9.0)
            LinearKeyframe(0, duration: 0.55)
            LinearKeyframe(0, duration: 0.05)
        }
                    }
                    .onAppear { playID = 1 }
                    .onChange(of: playID) { _, _ in finished = false }
                    .task(id: playID) {
                        guard playID != 0 else { return }
                        try? await Task.sleep(for: .seconds(introTotal + 0.3))
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
            Button("Replay") { playID += 1 }
                .buttonStyle(FlowPressStyle())
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(t.textSecondary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(t.surfaceSubtle)
                .cornerRadius(FlowComponent.radiusSM)
                .disabled(!finished && !reduceMotion)
                .opacity((!finished && !reduceMotion) ? 0.5 : 1)

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

// MARK: - Canvas (pure function of IntroValues — no local state)

struct IntroCanvas: View {
    var value: FirstRunIntroValues
    var morphed: Bool

    @Environment(\.colorScheme) private var scheme

    /// Beat caption derived from the channels — no extra track needed.
    private var caption: String {
        if value.brandOpacity > 0.4 { return "Your workflow, ready to share" }
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
        let docMode = value.guideOpacity > 0.4
        ZStack {
            // guide paper (behind steps)
            GuidePaper()
                .frame(width: CGFloat(value.guideW), height: FirstRunIntroValues.guideH)
                .position(
                    x: CGFloat(value.guideX + value.guideW / 2),
                    y: CGFloat(value.guideY + Double(FirstRunIntroValues.guideH / 2))
                )
                .opacity(value.guideOpacity * value.sceneOpacity)
                .scaleEffect(CGFloat(value.guideScale))

            // mock app window
            MockAppWindow(pressed: value.press > 0.5)
                .frame(width: 600, height: 310)
                .position(x: 440, y: CGFloat(219 + value.winY))
                .opacity(value.winOpacity * value.sceneOpacity)
                .scaleEffect(CGFloat(value.winScale))

            // three step cards (chrome drops away once the guide forms)
            StepCard(
                num: "01", title: "Click “Create project”",
                oldTitle: "Click “Create project”", newTitle: "Create a new project",
                morphed: morphed, isFirst: true,
                selected: value.selected > 0.5, showThumbButton: true,
                docMode: docMode
            )
            .frame(width: CGFloat(value.cardW), height: 128)
            .position(x: CGFloat(value.s1x + value.cardW / 2), y: CGFloat(value.s1y + 64))
            .opacity(value.s1o * value.sceneOpacity)

            StepCard(num: "02", title: "Name the project", isFirst: false, selected: false, showThumbButton: false, thumbKind: .field, docMode: docMode)
                .frame(width: CGFloat(value.cardW), height: 128)
                .position(x: CGFloat(value.s2x + value.cardW / 2), y: CGFloat(value.s2y + 64))
                .opacity(value.s2o * value.sceneOpacity)

            StepCard(num: "03", title: "Choose a template", isFirst: false, selected: false, showThumbButton: false, thumbKind: .rows, docMode: docMode)
                .frame(width: CGFloat(value.cardW), height: 128)
                .position(x: CGFloat(value.s3x + value.cardW / 2), y: CGFloat(value.s3y + 64))
                .opacity(value.s3o * value.sceneOpacity)

            // flying capture: the step-01 card itself, uniform-scaled down
            // onto its slot (matches the card that fades in beneath it)
            ZStack {
                Color.clear
                StepCard(
                    num: "01", title: "Click “Create project”",
                    isFirst: true, selected: false, showThumbButton: true
                )
                .frame(width: 220, height: 128)
                .scaleEffect(CGFloat(value.capW / 220), anchor: .topLeading)
            }
            .frame(width: CGFloat(value.capW), height: CGFloat(value.capH))
            .position(x: CGFloat(value.capX + value.capW / 2), y: CGFloat(value.capY + value.capH / 2))
            .opacity(value.capOpacity * value.sceneOpacity)
            .shadow(color: .black.opacity(0.14 * value.capOpacity), radius: 18, y: 8)

            // amber halo (interaction, then in-guide)
            RoundedRectangle(cornerRadius: 10)
                .stroke(FlowSemantic.for(scheme).haloBorder, lineWidth: 2)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(FlowSemantic.for(scheme).haloFill)
                )
                .frame(width: CGFloat(value.haloW), height: CGFloat(value.haloH))
                .position(x: CGFloat(value.haloX + value.haloW / 2), y: CGFloat(value.haloY + value.haloH / 2))
                .opacity(value.haloOpacity * value.sceneOpacity)

            // AI refinement panel
            AIRefinePanel()
                .frame(width: 180)
                .position(x: CGFloat(736 + value.aiX), y: 240)
                .opacity(value.aiOpacity * value.sceneOpacity)

            // cursor
            CursorView(pressed: value.press > 0.5)
                .position(x: CGFloat(value.cursorX), y: CGFloat(value.cursorY))
                .opacity(value.cursorOpacity * value.sceneOpacity)

            // beat caption
            Text(caption)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(t.textSecondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(t.surface)
                .cornerRadius(FlowComponent.radiusSM)
                .overlay(RoundedRectangle(cornerRadius: FlowComponent.radiusSM).stroke(t.border, lineWidth: 1))
                .position(x: FirstRunIntroValues.canvasW / 2, y: FirstRunIntroValues.canvasH - 14)
                .opacity(value.sceneOpacity * (value.winOpacity > 0.05 || value.s1o > 0.05 ? 1 : 0))

            // brand end-card
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
        }
        .frame(width: FirstRunIntroValues.canvasW, height: FirstRunIntroValues.canvasH)
        .clipped()
    }
}

// MARK: - Scene pieces (tokens only, no hard-coded palette)

private struct MockAppWindow: View {
    var pressed: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let t = FlowComponent.for(scheme)
        let sem = FlowSemantic.for(scheme)
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
                        .background(sem.accentDefault).cornerRadius(8)
                        .scaleEffect(pressed ? 0.965 : 1.0)
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
    var title: String
    var oldTitle: String? = nil
    var newTitle: String? = nil
    var morphed: Bool = false
    var isFirst: Bool = false
    var selected: Bool = false
    var showThumbButton: Bool = false
    var thumbKind: ThumbKind = .create
    /// Once the guide forms, cards drop their chrome and read as
    /// document sections on the paper (like the prototype).
    var docMode: Bool = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let t = FlowComponent.for(scheme)
        let sem = FlowSemantic.for(scheme)
        let chrome = docMode ? 0 : 1
        VStack(alignment: .leading, spacing: 0) {
            Text(num)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(docMode ? sem.accentDefault : t.textTertiary)
                .padding(.bottom, 8)
            MiniThumb(kind: thumbKind, showButton: showThumbButton)
            ZStack(alignment: .topLeading) {
                if isFirst, let old = oldTitle, let new = newTitle {
                    Text(old).font(.system(size: 12.5)).foregroundColor(t.textPrimary)
                        .opacity(morphed ? 0 : 1).offset(y: morphed ? -5 : 0)
                    Text(new).font(.system(size: 12.5, weight: .medium)).foregroundColor(t.textPrimary)
                        .opacity(morphed ? 1 : 0).offset(y: morphed ? 0 : 5)
                } else {
                    Text(title).font(.system(size: 12.5)).foregroundColor(t.textPrimary)
                }
            }
            .padding(.top, 10)
            .animation(.easeInOut(duration: 0.3), value: morphed)
        }
        .padding(12)
        .background((docMode ? Color.clear : t.surface).opacity(1))
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
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let t = FlowComponent.for(scheme)
        let sem = FlowSemantic.for(scheme)
        RoundedRectangle(cornerRadius: 8)
            .fill(t.surfaceSubtle.opacity(0.7))
            .frame(height: 52)
            .overlay(thumbContent(t: t, sem: sem))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(t.borderSubtle, lineWidth: 1))
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
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let t = FlowComponent.for(scheme)
        VStack(alignment: .leading, spacing: 0) {
            Text("Create a Project").font(.system(size: 22, weight: .semibold)).foregroundColor(t.textPrimary).padding(.top, 30)
            Text("Guide · 3 steps · captured just now").font(.system(size: 11.5)).foregroundColor(t.textSecondary).padding(.top, 5)
            Spacer()
            Text("Published with Flowline").font(.system(size: 10.5)).foregroundColor(t.textTertiary).padding(.bottom, 20)
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
    var pressed: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let t = FlowComponent.for(scheme)
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
        .fill(t.textPrimary)
        .overlay(
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
            .stroke(t.textInverse, lineWidth: 1.4)
        )
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        .scaleEffect(pressed ? 0.86 : 1.0)
        .frame(width: 16, height: 24)
    }
}
