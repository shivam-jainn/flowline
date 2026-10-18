import SwiftUI
import FlowlinePublishing

// MARK: - Selectable keystroke + pointer visuals
//
// Three ramps shared by the native stage and the web/PDF export
// (see FlowlinePublishing.KeyVisualStyle for the Foundation-only source):
// - Mac 2D: flat Magic-Keyboard matte caps, 1px border, no depth.
// - Mac 3D: Apple bezel — gradient face, top highlight, bottom edge, shadow.
// - 3D Keys (mechanical): base wall + raised cap + contact shadow;
//   modifier caps tinted like Show KeyPress / Remocn indigo mods.
// Mouse mirrors the ramp: flat ring → native pointer badge → glowing
// double ring with drop shadow. All colors come from component/semantic
// tokens only; depth is black/white opacity, never a new palette family.

/// Single keycap. `isModifier` tints mechanical mods + bolds Mac-3D mods.
public struct KeycapChip: View {
    public var token: String
    public var isModifier: Bool
    public var style: KeycapStyle
    @Environment(\.colorScheme) private var scheme

    public init(_ token: String, isModifier: Bool = false, style: KeycapStyle = .mac3D) {
        self.token = token
        self.isModifier = isModifier
        self.style = style
    }

    public var body: some View {
        switch style {
        case .mac2D: flatCap
        case .mac3D: mac3DCap
        case .mechanical3D: mechCap
        }
    }

    // MARK: Mac 2D — flat matte, 1px border, no shadow

    private var flatCap: some View {
        let t = FlowComponent.for(scheme)
        return Text(token)
            .font(.system(size: 11, weight: isModifier ? .semibold : .medium, design: .monospaced))
            .foregroundColor(t.textPrimary)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(t.surface)
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(t.border, lineWidth: 1))
    }

    // MARK: Mac 3D — gradient face + top highlight + bottom edge + shadow

    private var mac3DCap: some View {
        let t = FlowComponent.for(scheme)
        let sem = FlowSemantic.for(scheme)
        return Text(token)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(isModifier ? sem.haloIcon : t.textPrimary)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(
                ZStack {
                    // Bottom edge (the keywell lip).
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.black.opacity(scheme == .dark ? 0.55 : 0.28))
                        .offset(y: 1.5)
                    // Gradient face.
                    RoundedRectangle(cornerRadius: 7)
                        .fill(LinearGradient(
                            colors: [t.surface, t.surfaceSubtle],
                            startPoint: .top, endPoint: .bottom
                        ))
                    // Top highlight.
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.white.opacity(scheme == .dark ? 0.16 : 0.9), lineWidth: 1)
                        .padding(.top, 0.5)
                }
            )
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(t.border, lineWidth: 1))
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.45 : 0.22), radius: 3, y: 2)
    }

    // MARK: 3D Keys — base wall + raised cap + contact shadow

    private var mechCap: some View {
        let t = FlowComponent.for(scheme)
        let sem = FlowSemantic.for(scheme)
        let face: LinearGradient = isModifier
            ? LinearGradient(colors: [sem.accentSubtle, sem.accentSubtle], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [t.surface, t.surfaceSubtle], startPoint: .top, endPoint: .bottom)
        return Text(token)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(isModifier ? sem.accentDefault : t.textPrimary)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(
                ZStack {
                    // Side wall + contact shadow.
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(scheme == .dark ? 0.6 : 0.32))
                        .offset(y: 3)
                        .shadow(color: Color.black.opacity(scheme == .dark ? 0.5 : 0.25), radius: 5, y: 3)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(face)
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(scheme == .dark ? 0.14 : 0.85), lineWidth: 1)
                        .padding(.top, 0.5)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isModifier ? sem.accentDefault.opacity(0.45) : t.border, lineWidth: 1)
            )
            .padding(.bottom, 3) // room for the wall
    }
}

/// A recorded combo (`"⌘⇧P"`) as a row of caps joined by `+`.
/// Also renders bare keys (`["esc"]`) and typed characters (`["^"]`).
public struct KeyComboCaps: View {
    public var toks: [String]
    public var style: KeycapStyle
    @Environment(\.colorScheme) private var scheme

    public init(_ combo: String, style: KeycapStyle = .mac3D) {
        self.toks = KeyComboTokens.tokens(from: combo)
        self.style = style
    }

    public init(tokens: [String], style: KeycapStyle = .mac3D) {
        self.toks = tokens
        self.style = style
    }

    public var body: some View {
        let t = FlowComponent.for(scheme)
        HStack(spacing: 4) {
            ForEach(Array(toks.enumerated()), id: \.offset) { i, tok in
                if i > 0 {
                    Text("+")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(t.textTertiary)
                }
                KeycapChip(tok, isModifier: KeyComboTokens.isModifier(tok), style: style)
            }
        }
    }
}

// MARK: - Pointer halos (same depth ramp as caps)

/// Click halo: ring + centered dot + offset pointer glyph.
/// The halo frame stretches to the interaction rect (often huge), so this
/// is stroke + translucent wash ONLY — never an opaque fill, which would
/// read as a solid disc over the screenshot.
public struct MouseClickHalo: View {
    public var style: MouseStyle
    @Environment(\.colorScheme) private var scheme

    public init(style: MouseStyle = .mac3D) { self.style = style }

    public var body: some View {
        let sem = FlowSemantic.for(scheme)
        switch style {
        case .flat:
            Circle()
                .stroke(sem.haloBorder, lineWidth: 1.5)
                .background(Circle().fill(sem.haloFill))
                .overlay(
                    Image(systemName: "cursorarrow")
                        .font(.system(size: 11))
                        .foregroundColor(sem.haloIcon)
                        .offset(x: 13, y: 13)
                )
        case .mac2D:
            ZStack {
                Circle().fill(sem.haloFill.opacity(0.6))
                Circle().stroke(sem.haloBorder, lineWidth: 1.5)
                Circle().fill(sem.haloIcon).frame(width: 5, height: 5)
                Image(systemName: "cursorarrow")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(sem.haloIcon)
                    .offset(x: 12, y: 12)
            }
        case .mac3D:
            ZStack {
                Circle().fill(sem.haloFill)
                Circle()
                    .stroke(sem.haloBorder, lineWidth: 2)
                    .shadow(color: Color.black.opacity(scheme == .dark ? 0.5 : 0.3), radius: 5, y: 3)
                Circle().stroke(Color.white.opacity(scheme == .dark ? 0.14 : 0.7), lineWidth: 1)
                Circle().fill(sem.haloIcon).frame(width: 6, height: 6)
                Image(systemName: "cursorarrow.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(sem.haloIcon)
                    .shadow(color: Color.black.opacity(0.3), radius: 2, y: 1)
                    .offset(x: 14, y: 14)
            }
        }
    }
}

/// Cursor halo: centered pointer badge (no large click ring).
public struct MouseCursorHalo: View {
    public var style: MouseStyle
    @Environment(\.colorScheme) private var scheme

    public init(style: MouseStyle = .mac3D) { self.style = style }

    public var body: some View {
        let sem = FlowSemantic.for(scheme)
        let t = FlowComponent.for(scheme)
        switch style {
        case .flat:
            Image(systemName: "cursorarrow")
                .font(.system(size: 16))
                .foregroundColor(sem.haloIcon)
                .frame(width: 28, height: 28)
                .background(Circle().fill(sem.haloFill))
                .overlay(Circle().stroke(sem.haloBorder, lineWidth: 1.5))
        case .mac2D:
            Image(systemName: "cursorarrow")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(t.textPrimary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(t.surface))
                .overlay(Circle().stroke(t.border, lineWidth: 1.5))
        case .mac3D:
            // Fixed-size badge: centered in the (possibly huge) halo rect,
            // never stretched. Opaque fill is fine at this size.
            ZStack {
                Circle().fill(sem.haloFill).frame(width: 46, height: 46)
                Image(systemName: "cursorarrow.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(t.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(LinearGradient(
                            colors: [t.surface, t.surfaceSubtle],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .shadow(color: Color.black.opacity(scheme == .dark ? 0.5 : 0.3), radius: 5, y: 3)
                    )
                    .overlay(Circle().stroke(sem.haloBorder, lineWidth: 1.5))
            }
        }
    }
}

/// Drag halo: dashed rect + arrow, depth from the mouse style.
public struct MouseDragHalo: View {
    public var style: MouseStyle
    @Environment(\.colorScheme) private var scheme

    public init(style: MouseStyle = .mac3D) { self.style = style }

    public var body: some View {
        let sem = FlowSemantic.for(scheme)
        ZStack {
            RoundedRectangle(cornerRadius: FlowComponent.radiusSM)
                .stroke(sem.haloBorder, style: StrokeStyle(lineWidth: style == .flat ? 1.5 : 2, dash: [5, 4]))
                .background(RoundedRectangle(cornerRadius: FlowComponent.radiusSM).fill(sem.haloFill))
                .shadow(color: style == .flat ? .clear : Color.black.opacity(scheme == .dark ? 0.4 : 0.2),
                        radius: style == .flat ? 0 : 5, y: style == .flat ? 0 : 3)
            Image(systemName: "arrow.up.right")
                .foregroundColor(sem.haloIcon)
                .offset(x: -14, y: -14)
        }
    }
}

// MARK: - Style-panel thumbnails

/// Mini `⌘ ⇧ K` preview for the key-style picker.
public struct KeyStyleThumbnail: View {
    public var style: KeycapStyle
    public init(_ style: KeycapStyle) { self.style = style }
    public var body: some View {
        HStack(spacing: 3) {
            KeycapChip("⌘", isModifier: true, style: style)
            KeycapChip("⇧", isModifier: true, style: style)
            KeycapChip("K", style: style)
        }
        .scaleEffect(0.82)
        .frame(height: 30)
    }
}

/// Mini pointer preview for the mouse-style picker.
public struct MouseStyleThumbnail: View {
    public var style: MouseStyle
    @Environment(\.colorScheme) private var scheme
    public init(_ style: MouseStyle) { self.style = style }
    public var body: some View {
        let t = FlowComponent.for(scheme)
        let sem = FlowSemantic.for(scheme)
        ZStack {
            if style == .mac3D {
                Circle().fill(sem.haloFill).frame(width: 30, height: 30)
            }
            switch style {
            case .flat:
                Circle().stroke(sem.haloBorder, lineWidth: 1.5)
                    .frame(width: 22, height: 22)
            case .mac2D:
                Circle().fill(t.surface)
                    .overlay(Circle().stroke(t.border, lineWidth: 1.5))
                    .frame(width: 22, height: 22)
                    .overlay(Image(systemName: "cursorarrow").font(.system(size: 9)).foregroundColor(t.textPrimary))
            case .mac3D:
                Circle().fill(t.surface)
                    .overlay(Circle().stroke(sem.haloBorder, lineWidth: 2))
                    .frame(width: 22, height: 22)
                    .shadow(color: sem.shadowSubtle, radius: 4, y: 2)
                    .overlay(Image(systemName: "cursorarrow.fill").font(.system(size: 9)).foregroundColor(sem.haloIcon))
            }
        }
        .frame(width: 44, height: 30)
    }
}
