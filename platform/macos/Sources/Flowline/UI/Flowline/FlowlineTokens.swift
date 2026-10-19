import SwiftUI

// MARK: - Hex helper (tokens file ONLY — never use in components)

extension NSColor {
    convenience init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt64(h, radix: 16) else { return nil }
        self.init(
            calibratedRed: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
        )
    }
}

private func c(_ hex: String, fallback: NSColor) -> Color {
    Color(nsColor: NSColor(hex: hex) ?? fallback)
}

// ─────────────────────────────────────────────────────────────
// LAYER 1 — Primitive tokens (raw palette; never referenced by components)
// ─────────────────────────────────────────────────────────────

/// Primitive palette — §29.1. Only `FlowSemantic` may read these.
public enum FlowPrimitive {
    public enum Neutral {
        public static let n0   = c("#FFFFFF", fallback: .white)
        public static let n50  = c("#FAFAF8", fallback: .windowBackgroundColor)
        public static let n100 = c("#F7F7F5", fallback: .windowBackgroundColor)
        public static let n150 = c("#F1F1EF", fallback: .controlBackgroundColor)
        public static let n200 = c("#EBEBE8", fallback: .controlBackgroundColor)
        public static let n300 = c("#E5E5E2", fallback: .separatorColor)
        public static let n400 = c("#D6D6D2", fallback: .separatorColor)
        public static let n500 = c("#A1A1A6", fallback: .secondaryLabelColor)
        public static let n600 = c("#6E6E73", fallback: .secondaryLabelColor)
        public static let n700 = c("#48484D", fallback: .labelColor)
        public static let n800 = c("#303035", fallback: .labelColor)
        public static let n900 = c("#202023", fallback: .windowBackgroundColor)
        public static let n950 = c("#18181A", fallback: .windowBackgroundColor)
        public static let ink  = c("#1D1D1F", fallback: .labelColor)
        public static let paperInk = c("#F5F5F7", fallback: .labelColor)
        public static let disabledLight = c("#C7C7CC", fallback: .tertiaryLabelColor)
        public static let disabledDark  = c("#545459", fallback: .tertiaryLabelColor)
        public static let surfaceActiveLight = c("#E7E7E4", fallback: .controlBackgroundColor)
        public static let surfaceActiveDark  = c("#35353A", fallback: .controlBackgroundColor)
        public static let surfaceSubtleDark  = c("#28282C", fallback: .controlBackgroundColor)
        public static let elevatedDark = c("#2A2A2E", fallback: .controlBackgroundColor)
        public static let inverseDark  = c("#F5F5F7", fallback: .labelColor)
    }
    public enum Blue {
        public static let b400 = c("#70A8FF", fallback: .controlAccentColor)
        public static let b500 = c("#5E9BFF", fallback: .controlAccentColor)
        public static let b600 = c("#3478F6", fallback: .controlAccentColor)
        public static let b700 = c("#2869DE", fallback: .controlAccentColor)
        public static let b800 = c("#1F5FCC", fallback: .controlAccentColor)
        public static let subtleLight = c("#F0F5FF", fallback: .controlAccentColor)
        public static let subtleDark  = c("#202D43", fallback: .controlAccentColor)
        public static let borderLight = c("#BFD4FF", fallback: .controlAccentColor)
        public static let borderDark  = c("#31558C", fallback: .controlAccentColor)
        public static let activeDark  = c("#4A8EFF", fallback: .controlAccentColor)
        public static let selectedStepLight = c("#F3F7FF", fallback: .controlAccentColor)
    }
    public enum Amber {
        public static let a400 = c("#FFB84D", fallback: .systemOrange)
        public static let a500 = c("#FFB340", fallback: .systemOrange)
        public static let a600 = c("#E8A32D", fallback: .systemOrange)
        public static let softLight = c("#FFF6E5", fallback: .systemOrange)
        public static let softDark  = c("#332817", fallback: .windowBackgroundColor)
    }
    public enum System {
        public static let greenLight = c("#34C759", fallback: .systemGreen)
        public static let greenDark  = c("#30D158", fallback: .systemGreen)
        public static let greenBgLight = c("#EFFAF2", fallback: .systemGreen)
        public static let greenBgDark  = c("#193523", fallback: .windowBackgroundColor)
        public static let greenBdLight = c("#A7E6B8", fallback: .systemGreen)
        public static let greenBdDark  = c("#326B43", fallback: .systemGreen)
        public static let red       = c("#FF453A", fallback: .systemRed)
        public static let redBgLight = c("#FFF2F1", fallback: .systemRed)
        public static let redBgDark  = c("#3A1E1C", fallback: .windowBackgroundColor)
        public static let redBdLight = c("#F2B0AB", fallback: .systemRed)
        public static let redBdDark  = c("#7A3833", fallback: .systemRed)
        public static let orangeLight = c("#FF9F0A", fallback: .systemOrange)
        public static let orangeDark  = c("#FFB340", fallback: .systemOrange)
        public static let warnBgLight = c("#FFF7E8", fallback: .systemOrange)
        public static let warnBgDark  = c("#3A2D18", fallback: .windowBackgroundColor)
        public static let warnBdLight = c("#F2C16B", fallback: .systemOrange)
        public static let warnBdDark  = c("#8A672B", fallback: .systemBrown)
        public static let violet    = c("#8B7CF6", fallback: .systemPurple)
        public static let violetFgDark = c("#9B8CFF", fallback: .systemPurple)
        public static let violetBgLight = c("#F1EEFF", fallback: .systemPurple)
        public static let violetBgDark  = c("#29253D", fallback: .windowBackgroundColor)
        public static let violetBdLight = c("#D4CCFF", fallback: .systemPurple)
        public static let violetBdDark  = c("#554A82", fallback: .systemPurple)
    }
    /// User-assigned accent choices (style panel swatches, §17). These are
    /// NOT semantic families — they exist only where the user explicitly
    /// assigns them. Hex approximations of the original `Color(red:…)`
    /// values so no raw constructors live outside this file.
    public enum AccentChoice {
        public static let forestLight   = c("#3B806B", fallback: .systemGreen)
        public static let forestDark    = c("#599E85", fallback: .systemGreen)
        public static let clayLight     = c("#B0632B", fallback: .systemBrown)
        public static let clayDark      = c("#D99E61", fallback: .systemOrange)
        public static let plumLight     = c("#7A59A8", fallback: .systemPurple)
        public static let plumDark      = c("#9E8CD9", fallback: .systemPurple)
        public static let graphiteLight = c("#47474D", fallback: .secondaryLabelColor)
        public static let graphiteDark  = c("#A1A1A6", fallback: .secondaryLabelColor)
    }
    /// User-assigned folder palette (§17). Persisted folders store one of
    /// these hex strings; views cycle/read via `paletteHex` only — never a
    /// bare hex array in a view file.
    public enum UserFolder {
        public static let defaultHex = "#6B84A8"
        public static let paletteHex = ["#6B84A8", "#6E9471", "#B08A5A", "#8A7BB0", "#9C7A72", "#7E8A93"]
        /// Pre-resolved palette colors, allocated once (no per-frame parsing).
        public static let palette: [Color] = [
            c("#6B84A8", fallback: .secondaryLabelColor),
            c("#6E9471", fallback: .secondaryLabelColor),
            c("#B08A5A", fallback: .systemBrown),
            c("#8A7BB0", fallback: .systemPurple),
            c("#9C7A72", fallback: .systemBrown),
            c("#7E8A93", fallback: .secondaryLabelColor),
        ]
        /// Resolve a persisted hex to its palette color (nil = unknown hex).
        public static func color(hex: String) -> Color? {
            guard let i = paletteHex.firstIndex(of: hex), i < palette.count else { return nil }
            return palette[i]
        }
    }
}

// ─────────────────────────────────────────────────────────────
// LAYER 2 — Semantic tokens (§29.2–29.15). Values switch on scheme;
// components never branch on scheme themselves.
// ─────────────────────────────────────────────────────────────

/// Semantic token bundle for one appearance. Obtain via
/// `FlowSemantic.for(scheme)` — components must not read `FlowPrimitive`.
public struct FlowSemantic {
    public let scheme: ColorScheme
    public static func `for`(_ scheme: ColorScheme) -> FlowSemantic { FlowSemantic(scheme: scheme) }

    // Background (§29.2)
    public var bgCanvas: Color { scheme == .dark ? FlowPrimitive.Neutral.n950 : FlowPrimitive.Neutral.n100 }
    public var bgSurface: Color { scheme == .dark ? FlowPrimitive.Neutral.n900 : FlowPrimitive.Neutral.n0 }
    public var bgSubtle: Color { scheme == .dark ? FlowPrimitive.Neutral.surfaceSubtleDark : FlowPrimitive.Neutral.n150 }
    public var bgHover: Color { scheme == .dark ? c("#303035", fallback: .controlBackgroundColor) : FlowPrimitive.Neutral.n200 }
    public var bgActive: Color { scheme == .dark ? FlowPrimitive.Neutral.surfaceActiveDark : FlowPrimitive.Neutral.surfaceActiveLight }
    public var bgElevated: Color { scheme == .dark ? FlowPrimitive.Neutral.elevatedDark : FlowPrimitive.Neutral.n0 }
    public var bgInverse: Color { scheme == .dark ? FlowPrimitive.Neutral.inverseDark : FlowPrimitive.Neutral.ink }

    // Text (§29.3)
    public var textPrimary: Color { scheme == .dark ? FlowPrimitive.Neutral.paperInk : FlowPrimitive.Neutral.ink }
    public var textSecondary: Color { scheme == .dark ? FlowPrimitive.Neutral.n500 : FlowPrimitive.Neutral.n600 }
    public var textTertiary: Color { scheme == .dark ? FlowPrimitive.Neutral.n600 : FlowPrimitive.Neutral.n500 }
    public var textDisabled: Color { scheme == .dark ? FlowPrimitive.Neutral.disabledDark : FlowPrimitive.Neutral.disabledLight }
    public var textInverse: Color { scheme == .dark ? FlowPrimitive.Neutral.n950 : FlowPrimitive.Neutral.n0 }

    // Border (§29.4)
    public var borderSubtle: Color { scheme == .dark ? c("#303035", fallback: .separatorColor) : c("#EDEDEA", fallback: .separatorColor) }
    public var borderDefault: Color { scheme == .dark ? c("#38383D", fallback: .separatorColor) : FlowPrimitive.Neutral.n300 }
    public var borderStrong: Color { scheme == .dark ? FlowPrimitive.Neutral.n700 : FlowPrimitive.Neutral.n400 }

    // Accent (§29.5) — the ONE primary accent family
    public var accentDefault: Color { scheme == .dark ? FlowPrimitive.Blue.b500 : FlowPrimitive.Blue.b600 }
    public var accentHover: Color { scheme == .dark ? FlowPrimitive.Blue.b400 : FlowPrimitive.Blue.b700 }
    public var accentActive: Color { scheme == .dark ? FlowPrimitive.Blue.activeDark : FlowPrimitive.Blue.b800 }
    public var accentSubtle: Color { scheme == .dark ? FlowPrimitive.Blue.subtleDark : FlowPrimitive.Blue.subtleLight }
    public var accentBorder: Color { scheme == .dark ? FlowPrimitive.Blue.borderDark : FlowPrimitive.Blue.borderLight }
    public var accentContrast: Color { scheme == .dark ? FlowPrimitive.Neutral.n950 : FlowPrimitive.Neutral.n0 }

    // Interaction (§29.6)
    public var interactHover: Color { bgHover }
    public var interactPressed: Color { bgActive }
    public var interactSelected: Color { accentSubtle }
    public var interactFocus: Color { accentDefault }
    public var interactDrag: Color { accentDefault }
    public var interactDropTarget: Color { accentDefault }

    // Step (§29.7)
    public var stepBg: Color { scheme == .dark ? FlowPrimitive.Neutral.n900 : FlowPrimitive.Neutral.n0 }
    public var stepBgHover: Color { scheme == .dark ? c("#252529", fallback: .controlBackgroundColor) : FlowPrimitive.Neutral.n50 }
    public var stepBgSelected: Color { scheme == .dark ? FlowPrimitive.Blue.subtleDark : FlowPrimitive.Blue.selectedStepLight }
    public var stepBorder: Color { scheme == .dark ? c("#38383D", fallback: .separatorColor) : FlowPrimitive.Neutral.n300 }
    public var stepBorderSelected: Color { accentBorder }
    public var stepText: Color { textPrimary }
    public var stepTextSecondary: Color { textSecondary }
    public var stepNumber: Color { scheme == .dark ? FlowPrimitive.Neutral.n500 : FlowPrimitive.Neutral.n600 }
    public var stepInsertion: Color { accentDefault }

    // Halo (§29.8) — amber = user interaction, never warnings
    public var haloFill: Color { FlowPrimitive.Amber.a500.opacity(scheme == .dark ? 0.14 : 0.16) }
    public var haloBorder: Color {
        scheme == .dark ? FlowPrimitive.Amber.a400.opacity(0.80) : FlowPrimitive.Amber.a600.opacity(0.85)
    }
    public var haloIcon: Color { scheme == .dark ? FlowPrimitive.Amber.a400 : FlowPrimitive.Amber.a600 }
    public var haloSoft: Color { scheme == .dark ? FlowPrimitive.Amber.softDark : FlowPrimitive.Amber.softLight }

    // State (§29.9)
    public var successFg: Color { scheme == .dark ? FlowPrimitive.System.greenDark : FlowPrimitive.System.greenLight }
    public var successBg: Color { scheme == .dark ? FlowPrimitive.System.greenBgDark : FlowPrimitive.System.greenBgLight }
    public var successBd: Color { scheme == .dark ? FlowPrimitive.System.greenBdDark : FlowPrimitive.System.greenBdLight }
    public var warningFg: Color { scheme == .dark ? FlowPrimitive.System.orangeDark : FlowPrimitive.System.orangeLight }
    public var warningBg: Color { scheme == .dark ? FlowPrimitive.System.warnBgDark : FlowPrimitive.System.warnBgLight }
    public var warningBd: Color { scheme == .dark ? FlowPrimitive.System.warnBdDark : FlowPrimitive.System.warnBdLight }
    public var dangerFg: Color { FlowPrimitive.System.red }
    public var dangerBg: Color { scheme == .dark ? FlowPrimitive.System.redBgDark : FlowPrimitive.System.redBgLight }
    public var dangerBd: Color { scheme == .dark ? FlowPrimitive.System.redBdDark : FlowPrimitive.System.redBdLight }

    // AI (§29.10) — tiny indicators only, never panel chrome
    public var aiFg: Color { scheme == .dark ? FlowPrimitive.System.violetFgDark : FlowPrimitive.System.violet }
    public var aiBg: Color { scheme == .dark ? FlowPrimitive.System.violetBgDark : FlowPrimitive.System.violetBgLight }
    public var aiBd: Color { scheme == .dark ? FlowPrimitive.System.violetBdDark : FlowPrimitive.System.violetBdLight }

    // Recording (§29.11) — localized to the recording pill
    public var recordingActive: Color { FlowPrimitive.System.red }
    public var recordingBg: Color { FlowPrimitive.System.red.opacity(0.10) }
    public var recordingFg: Color { FlowPrimitive.System.red }

    // Publish (§29.12) — reuse accent/state, no new family
    public var publishPrimary: Color { accentDefault }
    public var publishSuccess: Color { successFg }
    public var publishPending: Color { accentDefault }

    // Focus (§29.13)
    public var focusRing: Color {
        scheme == .dark ? FlowPrimitive.Blue.b500.opacity(0.38) : FlowPrimitive.Blue.b600.opacity(0.32)
    }
    public var focusRingSubtle: Color {
        scheme == .dark ? FlowPrimitive.Blue.b500.opacity(0.22) : FlowPrimitive.Blue.b600.opacity(0.18)
    }

    // Overlay (§29.14)
    public var overlayScrim: Color { Color.black.opacity(0.20) }
    public var overlayLight: Color { Color.black.opacity(0.06) }
    public var overlayHeavy: Color { Color.black.opacity(0.45) }

    // Shadow (§29.15) — opacity only, never colored
    public var shadowSubtle: Color { Color.black.opacity(scheme == .dark ? 0.16 : 0.04) }
    public var shadowDefault: Color { Color.black.opacity(scheme == .dark ? 0.25 : 0.07) }
    public var shadowElevated: Color { Color.black.opacity(scheme == .dark ? 0.35 : 0.11) }

    // Selection wash (§8)
    public var selectedRing: Color {
        scheme == .dark ? FlowPrimitive.Blue.b500.opacity(0.22) : FlowPrimitive.Blue.b600.opacity(0.18)
    }

    // User-assigned (§17) — folders the user colors explicitly. Unknown hex
    // (legacy data) falls back to secondary text, matching prior behavior.
    public func folderColor(hex: String) -> Color {
        FlowPrimitive.UserFolder.color(hex: hex) ?? textSecondary
    }

    // Shimmer sweep for in-flight work (FlowShimmer). White highlight, single
    // value in both schemes; resolved once from the primitive (no per-frame
    // allocation — static let).
    public var shimmerHighlight: Color { FlowPrimitive.Neutral.n0.opacity(0.35) }

    // Code workspace (§22) — restrained dark developer surface, fixed in
    // both appearances. Never a neon syntax theme.
    public var codeBg: Color { FlowPrimitive.Neutral.n950 }
    public var codeSurface: Color { FlowPrimitive.Neutral.n900 }
    public var codeBorder: Color { c("#38383D", fallback: .separatorColor) }
    public var codeText: Color { FlowPrimitive.Neutral.paperInk }
    public var codeSecondary: Color { FlowPrimitive.Neutral.n500 }
}

// ─────────────────────────────────────────────────────────────
// LAYER 3 — Component tokens (§29.16). Components consume ONLY these.
// ─────────────────────────────────────────────────────────────

/// Component tokens — resolved from one `FlowSemantic`. This is the only
/// token type views may reference.
public struct FlowComponent {
    public let s: FlowSemantic
    public static func `for`(_ scheme: ColorScheme) -> FlowComponent { FlowComponent(s: .for(scheme)) }

    // Geometry (unchanged)
    public static let radiusXS: CGFloat = 6
    public static let radiusSM: CGFloat = 8
    public static let radiusMD: CGFloat = 12
    public static let radiusLG: CGFloat = 16
    public static let sidebarWidth: CGFloat = 236
    public static let aiWidth: CGFloat = 300
    public static let aiRailWidth: CGFloat = 44
    public static let cardWidth: CGFloat = 148

    // Step card → color.step.*
    public var stepBg: Color { s.stepBg }
    public var stepBgHover: Color { s.stepBgHover }
    public var stepBgSelected: Color { s.stepBgSelected }
    public var stepBorder: Color { s.stepBorder }
    public var stepBorderSelected: Color { s.stepBorderSelected }
    public var stepText: Color { s.stepText }
    public var stepTextSecondary: Color { s.stepTextSecondary }
    public var stepNumber: Color { s.stepNumber }

    // Toolbar button → §18 (monochrome; active = accent-soft/accent)
    public var toolbarBg: Color { .clear }
    public var toolbarBgHover: Color { s.bgSubtle }
    public var toolbarBgActive: Color { s.accentSubtle }
    public var toolbarFg: Color { s.textSecondary }
    public var toolbarFgActive: Color { s.accentDefault }
    public var toolbarFgHover: Color { s.textPrimary }

    // Primary button → accent
    public var primaryBg: Color { s.accentDefault }
    public var primaryBgHover: Color { s.accentHover }
    public var primaryBgPressed: Color { s.accentActive }
    public var primaryFg: Color { s.accentContrast }

    // Danger button → state.danger
    public var dangerFg: Color { s.dangerFg }
    public var dangerBgHover: Color { s.dangerBg }

    // Sidebar rows → §17
    public var sideBg: Color { .clear }
    public var sideBgHover: Color { s.bgSubtle }
    public var sideBgSelected: Color { s.accentSubtle }
    public var sideFg: Color { s.textSecondary }
    public var sideFgSelected: Color { s.accentDefault }

    // Surfaces / chrome
    public var canvas: Color { s.bgCanvas }
    public var surface: Color { s.bgSurface }
    public var surfaceSubtle: Color { s.bgSubtle }
    public var surfaceElevated: Color { s.bgElevated }
    public var border: Color { s.borderDefault }
    public var borderSubtle: Color { s.borderSubtle }
    public var textPrimary: Color { s.textPrimary }
    public var textSecondary: Color { s.textSecondary }
    public var textTertiary: Color { s.textTertiary }
    public var textDisabled: Color { s.textDisabled }
    public var textInverse: Color { s.textInverse }
}

// ─────────────────────────────────────────────────────────────
// Motion tokens — prototype @layer used --motion-fast/base/slow +
// --ease-standard/out. All Flowline animation goes through these.
// ─────────────────────────────────────────────────────────────

public enum FlowMotion {
    public static let fast: Double = 0.15
    public static let base: Double = 0.22
    public static let slow: Double = 0.32
    public static var standard: Animation { .timingCurve(0.28, 0, 0.22, 1, duration: base) }
    public static var standardFast: Animation { .timingCurve(0.28, 0, 0.22, 1, duration: fast) }
    /// Standard curve at the slow duration — agent-island expand/collapse
    /// (UI1.md §4.1: expand `slow` + `standard`; mirrors proto `0.32`).
    public static var standardSlow: Animation { .timingCurve(0.28, 0, 0.22, 1, duration: slow) }
    public static var easeOut: Animation { .timingCurve(0.16, 1, 0.3, 1, duration: base) }
    public static var easeOutFast: Animation { .timingCurve(0.16, 1, 0.3, 1, duration: fast) }
    /// Ease-out at the slow duration — agent-island entrance
    /// (proto `ai-island` enters over `0.32`).
    public static var easeOutSlow: Animation { .timingCurve(0.16, 1, 0.3, 1, duration: slow) }
    public static var spring: Animation { .spring(response: 0.32, dampingFraction: 0.82) }
    /// Sibling-shift spring — snappier than `spring` so cards glide aside
    /// during a drag without lagging the pointer. Drag-driven layout motion
    /// (drop-target shifts, reorder settle) uses springs so gesture velocity
    /// is preserved on retarget (WWDC23 "Animate with springs"); the 150 /
    /// 220ms curves stay for non-gesture flips (hover/select).
    public static var shift: Animation { .spring(response: 0.28, dampingFraction: 0.86) }
    /// Proximity-throttle tuning for gutter hover tracking: sub-point moves
    /// can't change the armed gap (`proximityStep`), and PreferenceKey
    /// re-resolves are debounced to `proximityDebounce` (~120Hz cap).
    public static let proximityStep: CGFloat = 1
    public static let proximityDebounce: TimeInterval = 0.008
    /// Haptic rate gate: at most one alignment tick per interval while the
    /// drop target flips card-to-card (drop `.generic` always plays).
    public static let hapticMinInterval: TimeInterval = 0.15
    /// Insert-arm dwell: the `+` slot only expands after the pointer has
    /// rested in (or near) the gap this long. Sliding across gaps never
    /// arms — inserting reads as a deliberate pause, not a flyby.
    /// Disarm (leaving the zone) is always immediate.
    public static let insertDwell: TimeInterval = 0.18
}

// MARK: - User-assigned accent choices (style panel + folder colors, §17)
//
// The product accent stays blue by default. These alternatives exist only
// where the user explicitly assigns them (style panel swatch, folder color),
// mirroring the prototype's swatch row — they are not new semantic families.

public enum FlowAccentChoice: String, Codable, CaseIterable, Hashable {
    case blue, forest, clay, plum, graphite
    public var label: String {
        switch self {
        case .blue: return "Blue"
        case .forest: return "Forest"
        case .clay: return "Clay"
        case .plum: return "Plum"
        case .graphite: return "Graphite"
        }
    }
    public func color(for scheme: ColorScheme) -> Color {
        let sem = FlowSemantic.for(scheme)
        switch self {
        case .blue: return sem.accentDefault
        // User-assigned exception (style panel swatch): values live in
        // FlowPrimitive.AccentChoice, never raw constructors in views.
        case .forest: return scheme == .dark ? FlowPrimitive.AccentChoice.forestDark : FlowPrimitive.AccentChoice.forestLight
        case .clay: return scheme == .dark ? FlowPrimitive.AccentChoice.clayDark : FlowPrimitive.AccentChoice.clayLight
        case .plum: return scheme == .dark ? FlowPrimitive.AccentChoice.plumDark : FlowPrimitive.AccentChoice.plumLight
        case .graphite: return scheme == .dark ? FlowPrimitive.AccentChoice.graphiteDark : FlowPrimitive.AccentChoice.graphiteLight
        }
    }
}

// MARK: - Shared modifiers

/// Elegant focus ring driven by `color.focus.ring` (§25).
public struct FlowFocusRing: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    public func body(content: Content) -> some View {
        content.shadow(color: FlowSemantic.for(scheme).focusRing, radius: 3)
    }
}

public extension View {
    /// Subtle hover elevation: background shift + shadow, no color invention.
    func flowHoverLift(_ hovering: Bool, semantic: FlowSemantic) -> some View {
        self.shadow(color: hovering ? semantic.shadowDefault : .clear, radius: hovering ? 6 : 0, y: hovering ? 2 : 0)
    }
}

/// Single-line pill badge — consumes component tokens only.
public struct FlowPill: View {
    public var text: String
    public var kind: Kind
    @Environment(\.colorScheme) private var scheme

    public enum Kind { case neutral, success, halo, accent }

    public init(_ text: String, kind: Kind = .neutral) {
        self.text = text
        self.kind = kind
    }

    public var body: some View {
        let t = FlowComponent.for(scheme)
        let sem = FlowSemantic.for(scheme)
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 2.5)
            .background(bg(t, sem))
            .foregroundColor(fg(t, sem))
            .clipShape(Capsule())
            .lineLimit(1)
            .contentTransition(.numericText())
    }

    private func bg(_ t: FlowComponent, _ sem: FlowSemantic) -> Color {
        switch kind {
        case .neutral: return t.surfaceSubtle
        case .success: return sem.successBg
        case .halo: return sem.haloFill
        case .accent: return sem.accentSubtle
        }
    }
    private func fg(_ t: FlowComponent, _ sem: FlowSemantic) -> Color {
        switch kind {
        case .neutral: return t.textSecondary
        case .success: return sem.successFg
        case .halo: return sem.haloIcon
        case .accent: return sem.accentDefault
        }
    }
}
