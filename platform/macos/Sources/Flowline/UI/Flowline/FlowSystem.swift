import SwiftUI

// MARK: - Flow Design System: Spacing / Buttons / Icons (single source of truth)
//
// Research synthesis (Apple HIG + 3 parallel audits):
// - One 4pt base scale, even buttons, leading-icon-only, one meaning one mark.
// - All components must use these tokens — no hardcoded 5/7/9/11/13 paddings.

/// 4pt base spacing scale. Use only these values.
public enum FlowSpacing {
    public static let xs: CGFloat = 4   // icon↔icon, icon↔label compact
    public static let sm: CGFloat = 8   // icon→label, button→button, card inner V
    public static let md: CGFloat = 12  // card padding, header→content
    public static let lg: CGFloat = 16  // group gap, canvas padding
    public static let xl: CGFloat = 20  // section gap
    public static let xxl: CGFloat = 24 // between cards / sections
    public static let xxxl: CGFloat = 32// page margins, footer separation
}

/// Canonical icon sizes. Icon always leads label, never trails.
public enum FlowIconSize {
    public static let badge: CGFloat = 10   // pills, chips, badges (10–11 semibold)
    public static let toolbar: CGFloat = 12 // toolbar / secondary buttons
    public static let regular: CGFloat = 13 // primary / dialog
    public static let tile: CGFloat = 15    // icon-only tile max
}

/// Central SF Symbol catalog — one meaning, one mark.
/// Do not invent ad-hoc symbols elsewhere; reuse these.
public enum FlowSymbols {
    public static let add = "plus"
    public static let addCircle = "plus.circle"
    public static let copy = "doc.on.doc"
    public static let share = "square.and.arrow.up"
    public static let trash = "trash"
    public static let settings = "gearshape" // canonical (not gearshape.fill)
    public static let pause = "pause.fill"
    public static let play = "play.fill"
    public static let stop = "stop.fill"
    public static let send = "paperplane.fill"
    public static let ai = "sparkles"
    public static let generate = "bolt.badge.automatic.fill"
    public static let warning = "exclamationmark.triangle.fill"
    public static let shield = "shield.lefthalf.filled"
    public static let shieldSlash = "shield.slash"
    public static let check = "checkmark.circle.fill"
    public static let globe = "globe"
    public static let doc = "doc.richtext.fill"
    public static let markdown = "text.alignleft"
    public static let open = "arrow.up.right.square"
    public static let reveal = "folder"
    public static let search = "magnifyingglass"
    public static let close = "xmark"
}

/// Button variants. Hierarchy by style, never by ad-hoc size.
public enum FlowButtonVariant {
    case primary      // one per view, prominent
    case secondary    // bordered, default action row
    case tertiary     // toolbar / plain + FlowPressStyle
    case destructive  // never .borderedProminent + destructive
    case iconOnly     // toolbar / HUD transport, always + tooltip
}

public enum FlowButtonSize {
    case compact  // toolbar / badge: H12 V8
    case regular  // secondary: H12 V7-8, primary: H16 V8

    var hPad: CGFloat {
        switch self {
        case .compact: return 8
        case .regular: return 12
        }
    }
    var vPad: CGFloat {
        switch self {
        case .compact: return 8
        case .regular: return 8
        }
    }
}

/// Unified button: leading icon only, even padding, correct hit targets.
public struct FlowButton: View {
    let title: String
    let icon: String?
    let variant: FlowButtonVariant
    let size: FlowButtonSize
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    public init(
        _ title: String,
        icon: String? = nil,
        variant: FlowButtonVariant = .secondary,
        size: FlowButtonSize = .regular,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.variant = variant
        self.size = size
        self.action = action
    }

    public var body: some View {
        let t = FlowComponent.for(scheme)
        let sem = FlowSemantic.for(scheme)
        Button(action: { withAnimation(FlowMotion.standardFast) { action() } }) {
            HStack(spacing: FlowSpacing.xs + 2) { // 6pt icon→label
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: .semibold))
                        .accessibilityHidden(true)
                }
                if variant != .iconOnly {
                    Text(title)
                        .font(.system(size: labelSize, weight: variant == .primary ? .semibold : .medium))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, size.hPad)
            .padding(.vertical, size.vPad)
            .background(background(t, sem))
            .foregroundColor(foreground(t, sem))
            .cornerRadius(corner(t))
        }
        .buttonStyle(FlowPressStyle())
        .help(title)
        .accessibilityLabel(title)
    }

    private var iconSize: CGFloat {
        switch size {
        case .compact: return FlowIconSize.badge
        case .regular: return FlowIconSize.toolbar
        }
    }
    private var labelSize: CGFloat {
        variant == .primary ? 13 : 12
    }
    private func background(_ t: FlowComponent, _ sem: FlowSemantic) -> Color {
        switch variant {
        case .primary: return t.primaryBg
        case .secondary: return t.surfaceSubtle
        case .tertiary: return .clear
        case .destructive: return .clear
        case .iconOnly: return .clear
        }
    }
    private func foreground(_ t: FlowComponent, _ sem: FlowSemantic) -> Color {
        switch variant {
        case .primary: return t.primaryFg
        case .destructive: return t.dangerFg
        default: return t.textPrimary
        }
    }
    private func corner(_ t: FlowComponent) -> CGFloat {
        FlowComponent.radiusSM
    }
}

public extension View {
    /// Even icon-only hit target: 28pt visual, 44pt accessible.
    func flowIconHitTarget(min: CGFloat = 44) -> some View {
        self
            .frame(minWidth: min, minHeight: min)
            .contentShape(Rectangle())
    }

    /// Standard card padding (12) + MD corner. Replaces ad-hoc 10/14/16/18/20.
    func flowCard(padding: CGFloat = FlowSpacing.md, radius: CGFloat? = nil) -> some View {
        self
            .padding(padding)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(radius ?? FlowComponent.radiusMD)
    }
}
