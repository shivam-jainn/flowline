import SwiftUI

// MARK: - Native microinteraction toolkit (no third-party dependency)
//
// Surveyed 2026-10: Lottie 4.6 (SPM, macOS + SwiftUI LottieView) and Rive 6.x
// (SPM, macOS 13.1+, interactive state machines) are the good libs — but both
// exist to play rich vector character/illustration animation from asset files.
// This product's system (§26–28) forbids decorative animation: chrome stays
// monochrome, content provides the color, motion communicates state only.
// A binary/asset animation runtime would buy nothing while adding fetch,
// size, and a designer-asset pipeline. Everything below is native SwiftUI on
// macOS 14 (springs, phase/keyframe animators, numeric transitions) and
// respects Reduce Motion.

/// Press physics for borderless buttons: 0.96 squash + slight dim, spring
/// release. Replaces `.buttonStyle(.plain)` wherever a press should be felt.
public struct FlowPressStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.82 : 1.0)
            .animation(FlowMotion.standardFast, value: configuration.isPressed)
    }
}

/// Three-dot thinking indicator for AI work (prototype `aiThinking`).
/// Phase-animates opacity + offset; static when Reduce Motion is on.
public struct ThinkingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    public init() {}
    public var body: some View {
        if reduceMotion {
            Text("…").font(.system(size: 14, weight: .bold))
                .foregroundColor(FlowSemantic.for(scheme).textTertiary)
        } else {
            PhaseAnimator([0, 1, 2], content: { phase in
                HStack(spacing: 4) {
                    ForEach(0..<3) { i in
                        Circle()
                            .frame(width: 6, height: 6)
                            .opacity(phase == i ? 1.0 : 0.25)
                            .offset(y: phase == i ? -2 : 0)
                            .animation(FlowMotion.standardFast, value: phase)
                    }
                }
            }, animation: { _ in .easeInOut(duration: 0.4) })
        }
    }
}

/// Shimmer sweep for in-flight work (automation run, AI streaming).
public struct FlowShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var sweep = false
    public func body(content: Content) -> some View {
        if reduceMotion { content }
        else {
            content
                .overlay(
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, FlowSemantic.for(scheme).shimmerHighlight, .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.4)
                        .offset(x: sweep ? geo.size.width : -geo.size.width * 0.4)
                    }
                )
                .clipped()
                .onAppear {
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                        sweep = true
                    }
                }
        }
    }
}

public extension View {
    func flowShimmer() -> some View { modifier(FlowShimmer()) }
}

/// One-shot halo pop: 1.0 → 1.05 → 1.0 when the mark appears (§13: no glow,
/// no loop — a single breath so the eye lands on the interaction target).
public struct HaloAppear: ViewModifier {
    var trigger: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public func body(content: Content) -> some View {
        if reduceMotion { content }
        else {
            content.keyframeAnimator(initialValue: 1.0, trigger: trigger) { view, v in
                view.scaleEffect(v)
            } keyframes: { _ in
                CubicKeyframe(1.05, duration: 0.16)
                CubicKeyframe(1.0, duration: 0.24)
            }
        }
    }
}
