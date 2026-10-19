// NOTE: import-free on purpose — pure timeline math (same-module struct).
// This file is also compiled standalone by a verification harness, so it must
// not import SwiftUI or the app target.

/// Exact CSS cubic-bezier solver (WebKit `UnitBezier` algorithm:
/// Newton–Raphson with a bisection fallback). This is the same math every
/// browser uses to evaluate `transition-timing-function`, so easing evaluated
/// here matches `intro-prototype/styles.css` bit-for-bit — something
/// `CubicKeyframe` cannot do (fixed curve, no timing parameter).
public struct UnitBezier {
    private let x1: Double
    private let y1: Double
    private let x2: Double
    private let y2: Double

    public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
    }

    // Cubic Bernstein coefficients for one axis.
    private func coeff(_ a1: Double, _ a2: Double) -> (a: Double, b: Double, c: Double) {
        (1 - 3 * a2 + 3 * a1, 3 * a2 - 6 * a1, 3 * a1)
    }

    private func sample(_ t: Double, _ a: Double, _ b: Double, _ c: Double) -> Double {
        ((a * t + b) * t + c) * t
    }

    private func sampleDX(_ t: Double, _ a: Double, _ b: Double, _ c: Double) -> Double {
        (3 * a * t + 2 * b) * t + c
    }

    /// Given horizontal progress `x` in [0,1], return eased progress `y`.
    public func solve(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        let (ax, bx, cx) = coeff(x1, x2)
        let (ay, by, cy) = coeff(y1, y2)
        var t = x
        for _ in 0..<8 {
            let err = sample(t, ax, bx, cx) - x
            if abs(err) < 1e-7 { return sample(t, ay, by, cy) }
            let d = sampleDX(t, ax, bx, cx)
            if abs(d) < 1e-7 { break }
            t -= err / d
        }
        var lo = 0.0
        var hi = 1.0
        t = x
        while hi - lo > 1e-7 {
            let v = sample(t, ax, bx, cx)
            if abs(v - x) < 1e-7 { break }
            if v < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return sample(t, ay, by, cy)
    }
}

/// Prototype motion tokens (`styles.css` `:root`) as exact curves.
public enum IntroEase {
    /// Holds / constant-rate segments.
    case linear
    /// CSS `ease` (0.25, 0.1, 0.25, 1) — fades, morph.
    case ease
    /// `--spring` (0.32, 0.72, 0, 1) — all travel on the 9.6s clock.
    case spring
    /// `--spring-soft` (0.34, 1.06, 0.44, 1) — halo pop (slight overshoot,
    /// exactly like the browser renders it).
    case springSoft

    public func solve(_ p: Double) -> Double {
        switch self {
        case .linear: return min(1, max(0, p))
        case .ease: return UnitBezier(0.25, 0.1, 0.25, 1).solve(p)
        case .spring: return UnitBezier(0.32, 0.72, 0, 1).solve(p)
        case .springSoft: return UnitBezier(0.34, 1.06, 0.44, 1).solve(p)
        }
    }
}

/// One eased span of a channel: `from` → `to` over `[start, end]` (seconds).
public struct IntroSeg {
    public let start: Double
    public let end: Double
    public let from: Double
    public let to: Double
    public let ease: IntroEase

    public init(_ start: Double, _ end: Double, _ from: Double, _ to: Double, _ ease: IntroEase = .linear) {
        self.start = start
        self.end = end
        self.from = from
        self.to = to
        self.ease = ease
    }
}

/// The whole intro as a pure function of time. The SwiftUI view runs ONE
/// linear master clock (`keyframeAnimator` only needs to be linear) and maps
/// `t` → every channel here, so every travel uses the prototype's exact
/// bezier instead of `CubicKeyframe`'s fixed curve.
///
/// Segment tables below are 1:1 with the prototype beats
/// (intro.js `at(...)` times ÷ 1000). Boundaries are shared between coupled
/// channels (e.g. sNx/cardW) so edges stay glued — same invariant the old
/// per-track durations had, now checkable by `value(at: 9.6) == .final`.
public enum IntroTimeline {
    public static let total: Double = 9.6

    public static func clampT(_ t: Double) -> Double { min(total, max(0, t)) }

    /// Evaluate a channel's segment chain at time `t`.
    public static func chain(_ t: Double, _ segs: [IntroSeg]) -> Double {
        let time = clampT(t)
        for s in segs {
            if time < s.end || s.end >= total {
                if time < s.start { return s.from }
                let span = s.end - s.start
                guard span > 0 else { return s.to }
                let p = (time - s.start) / span
                return s.from + (s.to - s.from) * s.ease.solve(p)
            }
        }
        return segs.last?.to ?? 0
    }

    private static func lerp(_ a: Double, _ b: Double, _ p: Double) -> Double {
        a + (b - a) * p
    }

    /// Cursor with the prototype's INTERRUPTED first leg: the 0.12s glide is
    /// retargeted mid-flight at 0.8s, so leg 2 starts from the eased
    /// mid-flight position — not from the (560,330) waypoint. Sequential
    /// keyframes cannot express this; a function can.
    static func cursor(at t: Double) -> (x: Double, y: Double) {
        let time = clampT(t)
        let park = (x: 940.0, y: 510.0)
        let mid = (x: 560.0, y: 330.0)
        let cta = (x: 385.0, y: 283.0)
        if time <= 0.12 { return park }
        if time <= 0.8 {
            let p = IntroEase.spring.solve((time - 0.12) / 0.9)
            return (lerp(park.x, mid.x, p), lerp(park.y, mid.y, p))
        }
        let pCut = IntroEase.spring.solve((0.8 - 0.12) / 0.9)
        let cut = (x: lerp(park.x, mid.x, pCut), y: lerp(park.y, mid.y, pCut))
        if time <= 1.46 {
            let p = IntroEase.spring.solve((time - 0.8) / 0.66)
            return (lerp(cut.x, cta.x, p), lerp(cut.y, cta.y, p))
        }
        return cta
    }

    public static func value(at t: Double) -> FirstRunIntroValues {
        var v = FirstRunIntroValues.initial
        let c = cursor(at: t)
        v.cursorX = c.x
        v.cursorY = c.y
        v.cursorOpacity = chain(t, [
            IntroSeg(0, 0.12, 0, 0),
            IntroSeg(0.12, 0.42, 0, 1, .ease),
            IntroSeg(0.42, 3.0, 1, 1),
            IntroSeg(3.0, 3.3, 1, 0, .ease),
            IntroSeg(3.3, 9.6, 0, 0),
        ])
        v.press = chain(t, [
            IntroSeg(0, 1.46, 0, 0),
            IntroSeg(1.46, 1.59, 0, 1, .spring),
            IntroSeg(1.59, 1.72, 1, 0, .spring),
            IntroSeg(1.72, 9.6, 0, 0),
        ])
        v.winOpacity = chain(t, [
            IntroSeg(0, 0.5, 0, 1, .ease),
            IntroSeg(0.5, 2.0, 1, 1),
            IntroSeg(2.0, 2.5, 1, 0, .ease),
            IntroSeg(2.5, 9.6, 0, 0),
        ])
        v.winY = chain(t, [
            IntroSeg(0, 0.7, 10, 0, .spring),
            IntroSeg(0.7, 2.0, 0, 0),
            IntroSeg(2.0, 2.7, 0, -6, .spring),
            IntroSeg(2.7, 9.6, -6, -6),
        ])
        v.winScale = chain(t, [
            IntroSeg(0, 0.7, 0.985, 1.0, .spring),
            IntroSeg(0.7, 2.0, 1.0, 1.0),
            IntroSeg(2.0, 2.7, 1.0, 0.97, .spring),
            IntroSeg(2.7, 9.6, 0.97, 0.97),
        ])
        v.haloOpacity = chain(t, [
            IntroSeg(0, 1.46, 0, 0),
            IntroSeg(1.46, 1.64, 0, 1, .ease),
            IntroSeg(1.64, 2.0, 1, 1),
            IntroSeg(2.0, 2.18, 1, 0, .ease),
            IntroSeg(2.18, 6.0, 0, 0),
            IntroSeg(6.0, 6.15, 0, 1, .ease),
            IntroSeg(6.15, 6.65, 1, 1),
            IntroSeg(6.65, 6.85, 1, 0, .ease),
            IntroSeg(6.85, 9.6, 0, 0),
        ])
        // Geometry jumps instantly at 6.0 while invisible (prototype sets
        // left/top/width/height with no transition, then fades back in).
        v.haloX = chain(t, [IntroSeg(0, 6.0, 300, 300), IntroSeg(6.0, 9.6, 564, 564)])
        v.haloY = chain(t, [IntroSeg(0, 6.0, 250, 250), IntroSeg(6.0, 9.6, 144, 144)])
        v.haloW = chain(t, [IntroSeg(0, 6.0, 170, 170), IntroSeg(6.0, 9.6, 72, 72)])
        v.haloH = chain(t, [IntroSeg(0, 6.0, 60, 60), IntroSeg(6.0, 9.6, 38, 38)])
        v.haloScale = chain(t, [
            IntroSeg(0, 1.46, 0.9, 0.9),
            IntroSeg(1.46, 1.72, 0.9, 1.0, .springSoft),
            IntroSeg(1.72, 2.0, 1.0, 1.0),
            IntroSeg(2.0, 2.26, 1.0, 0.9, .springSoft),
            IntroSeg(2.26, 6.0, 0.9, 0.9),
            IntroSeg(6.0, 6.26, 0.9, 1.0, .springSoft),
            IntroSeg(6.26, 6.65, 1.0, 1.0),
            IntroSeg(6.65, 6.91, 1.0, 0.9, .springSoft),
            IntroSeg(6.91, 9.6, 0.9, 0.9),
        ])
        v.capOpacity = chain(t, [
            IntroSeg(0, 2.0, 0, 0),
            IntroSeg(2.0, 2.26, 0, 1, .ease),
            IntroSeg(2.26, 2.78, 1, 1),
            IntroSeg(2.78, 2.98, 1, 0, .ease),
            IntroSeg(2.98, 9.6, 0, 0),
        ])
        v.capX = chain(t, [IntroSeg(0, 2.0, 300, 300), IntroSeg(2.0, 2.78, 300, 90, .spring), IntroSeg(2.78, 9.6, 90, 90)])
        v.capY = chain(t, [IntroSeg(0, 2.0, 114, 114), IntroSeg(2.0, 2.78, 114, 442, .spring), IntroSeg(2.78, 9.6, 442, 442)])
        v.capW = chain(t, [IntroSeg(0, 2.0, 430, 430), IntroSeg(2.0, 2.78, 430, 220, .spring), IntroSeg(2.78, 9.6, 220, 220)])
        v.capH = chain(t, [IntroSeg(0, 2.0, 250.2, 250.2), IntroSeg(2.0, 2.78, 250.2, 128, .spring), IntroSeg(2.78, 9.6, 128, 128)])
        v.capR = chain(t, [IntroSeg(0, 2.0, 10, 10), IntroSeg(2.0, 2.78, 10, 8, .spring), IntroSeg(2.78, 9.6, 8, 8)])
        v.s1o = chain(t, [IntroSeg(0, 2.0, 0, 0), IntroSeg(2.0, 2.52, 0, 1, .ease), IntroSeg(2.52, 9.6, 1, 1)])
        v.s2o = chain(t, [IntroSeg(0, 3.14, 0, 0), IntroSeg(3.14, 3.66, 0, 1, .ease), IntroSeg(3.66, 9.6, 1, 1)])
        v.s3o = chain(t, [IntroSeg(0, 3.5, 0, 0), IntroSeg(3.5, 4.02, 0, 1, .ease), IntroSeg(4.02, 9.6, 1, 1)])
        let sx = FirstRunIntroValues.self
        v.s1x = chain(t, xTrack(slot: sx.slotX[0]))
        v.s2x = chain(t, xTrack(slot: sx.slotX[1]))
        v.s3x = chain(t, xTrack(slot: sx.slotX[2]))
        v.s1y = chain(t, yTrack(row: sx.rowY[0], readerRow: sx.readerRowY[0]))
        v.s2y = chain(t, yTrack(row: sx.rowY[1], readerRow: sx.readerRowY[1]))
        v.s3y = chain(t, yTrack(row: sx.rowY[2], readerRow: sx.readerRowY[2]))
        v.cardW = chain(t, [
            IntroSeg(0, 4.5, 220, 220),
            IntroSeg(4.5, 5.4, 220, 420, .spring),
            IntroSeg(5.4, 7.8, 420, 420),
            IntroSeg(7.8, 8.7, 420, 470, .spring),
            IntroSeg(8.7, 9.6, 470, 470),
        ])
        v.selected = chain(t, [
            IntroSeg(0, 4.2, 0, 0),
            IntroSeg(4.2, 4.35, 0, 1),
            IntroSeg(4.35, 4.5, 1, 0),
            IntroSeg(4.5, 9.6, 0, 0),
        ])
        v.guideOpacity = chain(t, [
            IntroSeg(0, 4.5, 0, 0),
            IntroSeg(4.5, 5.1, 0, 1, .ease),
            IntroSeg(5.1, 9.0, 1, 1),
            IntroSeg(9.0, 9.55, 1, 0, .ease),
            IntroSeg(9.55, 9.6, 0, 0),
        ])
        v.guideX = chain(t, [
            IntroSeg(0, 6.8, 190, 190),
            IntroSeg(6.8, 7.7, 190, 140, .spring),
            IntroSeg(7.7, 7.8, 140, 140),
            IntroSeg(7.8, 8.7, 140, 160, .spring),
            IntroSeg(8.7, 9.6, 160, 160),
        ])
        v.guideY = chain(t, [
            IntroSeg(0, 4.5, 32, 32),
            IntroSeg(4.5, 5.4, 32, 20, .spring),
            IntroSeg(5.4, 7.8, 20, 20),
            IntroSeg(7.8, 8.7, 20, 18, .spring),
            IntroSeg(8.7, 9.6, 18, 18),
        ])
        v.guideW = chain(t, [
            IntroSeg(0, 7.8, 500, 500),
            IntroSeg(7.8, 8.7, 500, 560, .spring),
            IntroSeg(8.7, 9.6, 560, 560),
        ])
        v.guideH = chain(t, [
            IntroSeg(0, 7.8, 560, 560),
            IntroSeg(7.8, 8.7, 560, 582, .spring),
            IntroSeg(8.7, 9.6, 582, 582),
        ])
        v.guideScale = chain(t, [
            IntroSeg(0, 4.5, 0.975, 0.975),
            IntroSeg(4.5, 5.4, 0.975, 1.0, .spring),
            IntroSeg(5.4, 9.6, 1.0, 1.0),
        ])
        v.readerT = chain(t, [
            IntroSeg(0, 7.8, 0, 0),
            IntroSeg(7.8, 8.7, 0, 1, .spring),
            IntroSeg(8.7, 9.6, 1, 1),
        ])
        v.aiOpacity = chain(t, [
            IntroSeg(0, 6.8, 0, 0),
            IntroSeg(6.8, 7.26, 0, 1, .ease),
            IntroSeg(7.26, 7.8, 1, 1),
            IntroSeg(7.8, 8.1, 1, 0, .ease),
            IntroSeg(8.1, 9.6, 0, 0),
        ])
        v.aiX = chain(t, [
            IntroSeg(0, 6.8, 24, 24),
            IntroSeg(6.8, 7.42, 24, 0, .spring),
            IntroSeg(7.42, 7.8, 0, 0),
            IntroSeg(7.8, 8.3, 0, 24, .spring),
            IntroSeg(8.3, 9.6, 24, 24),
        ])
        v.morph = chain(t, [
            IntroSeg(0, 7.35, 0, 0),
            IntroSeg(7.35, 7.77, 0, 1, .ease),
            IntroSeg(7.77, 9.6, 1, 1),
        ])
        v.brandOpacity = chain(t, [
            IntroSeg(0, 8.9, 0, 0),
            IntroSeg(8.9, 9.6, 0, 1, .ease),
        ])
        v.brandY = chain(t, [
            IntroSeg(0, 8.7, 8, 8),
            IntroSeg(8.7, 9.6, 8, 0, .spring),
        ])
        v.sceneOpacity = chain(t, [
            IntroSeg(0, 9.0, 1, 1),
            IntroSeg(9.0, 9.55, 1, 0, .ease),
            IntroSeg(9.55, 9.6, 0, 0),
        ])
        return v
    }

    private static func xTrack(slot: Double) -> [IntroSeg] {
        let sx = FirstRunIntroValues.self
        return [
            IntroSeg(0, 4.5, slot, slot),
            IntroSeg(4.5, 5.4, slot, sx.docX, .spring),
            IntroSeg(5.4, 6.8, sx.docX, sx.docX),
            IntroSeg(6.8, 7.7, sx.docX, sx.docAiX, .spring),
            IntroSeg(7.7, 7.8, sx.docAiX, sx.docAiX),
            IntroSeg(7.8, 8.7, sx.docAiX, sx.readerX, .spring),
            IntroSeg(8.7, 9.6, sx.readerX, sx.readerX),
        ]
    }

    private static func yTrack(row: Double, readerRow: Double) -> [IntroSeg] {
        let gutterY = FirstRunIntroValues.gutterY
        return [
            IntroSeg(0, 4.5, gutterY, gutterY),
            IntroSeg(4.5, 5.4, gutterY, row, .spring),
            IntroSeg(5.4, 7.8, row, row),
            IntroSeg(7.8, 8.7, row, readerRow, .spring),
            IntroSeg(8.7, 9.6, readerRow, readerRow),
        ]
    }
}
