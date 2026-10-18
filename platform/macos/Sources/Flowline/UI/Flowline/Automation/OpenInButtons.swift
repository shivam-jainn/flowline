import AppKit
import SwiftUI

/// Brand icon for one `EditorTarget`, probed by asset-catalog name.
///
/// Resolution order: `assetName`, then `alternateAssetName`, then the
/// SF-Symbol fallback in a token-styled tile. When the host app registers
/// `Cursor` / `VSCode` / `Xcode` / `Zed` / `SublimeText` / `Finder` image
/// assets, they light up here automatically — no code change needed.
public struct EditorIconView: View {
    public let target: EditorTarget

    @Environment(\.colorScheme) private var scheme

    public init(target: EditorTarget) {
        self.target = target
    }

    public var body: some View {
        let comp = FlowComponent.for(scheme)
        Group {
            if let image = resolvedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: FlowComponent.radiusXS)
                        .fill(comp.surfaceElevated)
                    RoundedRectangle(cornerRadius: FlowComponent.radiusXS)
                        .stroke(comp.border, lineWidth: 1)
                    Image(systemName: target.fallbackSystemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(comp.textSecondary)
                }
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }

    private var resolvedImage: NSImage? {
        if let direct = NSImage(named: target.assetName) { return direct }
        if let alias = target.alternateAssetName, let aliased = NSImage(named: alias) { return aliased }
        return nil
    }
}

/// One meticulously-designed "Open in <editor>" button.
///
/// Native `Button` (Tab-focusable, `⌘`-shortcut free so it never steals
/// global keys), press physics via `FlowPressStyle`, hover wash via
/// component tokens, a focus ring when keyboard-focused, and a tooltip
/// naming the current file + editor.
public struct OpenInButton: View {
    public let target: EditorTarget
    public let fileName: String
    public let onOpen: (EditorTarget) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @FocusState private var focused: Bool

    public init(target: EditorTarget, fileName: String, onOpen: @escaping (EditorTarget) -> Void) {
        self.target = target
        self.fileName = fileName
        self.onOpen = onOpen
    }

    public var body: some View {
        let comp = FlowComponent.for(scheme)
        let sem = FlowSemantic.for(scheme)
        Button {
            onOpen(target)
        } label: {
            HStack(spacing: 8) {
                EditorIconView(target: target)
                Text(target.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(comp.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(hovering ? sem.bgHover : comp.surfaceSubtle)
            .cornerRadius(FlowComponent.radiusSM)
            .overlay(
                RoundedRectangle(cornerRadius: FlowComponent.radiusSM)
                    .stroke(focused ? sem.focusRing : comp.border, lineWidth: focused ? 2 : 1)
            )
        }
        .buttonStyle(FlowPressStyle())
        .focusable()
        .focused($focused)
        .onHover { hovering = $0 }
        .help(target.tooltip(fileName: fileName))
        .accessibilityLabel(target.tooltip(fileName: fileName))
        .animation(reduceMotion ? nil : FlowMotion.standardFast, value: hovering)
        .animation(reduceMotion ? nil : FlowMotion.standardFast, value: focused)
    }
}

/// Compact "Open in" handoff: a single menu instead of the old 6-button
/// row. The row truncated labels ("VS Co…", "Sublim…") and forced a 660pt
/// sheet width; the menu shows full names with icons (progressive
/// disclosure, HIG §Menus) and keeps the toolbar to one line.
public struct OpenInMenu: View {
    public let fileName: String
    public let onOpen: (EditorTarget) -> Void

    @Environment(\.colorScheme) private var scheme

    public init(fileName: String, onOpen: @escaping (EditorTarget) -> Void) {
        self.fileName = fileName
        self.onOpen = onOpen
    }

    public var body: some View {
        let comp = FlowComponent.for(scheme)
        Menu {
            ForEach(EditorTarget.allCases) { target in
                Button(target.tooltip(fileName: fileName)) {
                    onOpen(target)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: FlowSymbols.open)
                    .font(.system(size: 11))
                Text("Open in…")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(comp.surfaceSubtle)
            .foregroundColor(comp.textPrimary)
            .cornerRadius(FlowComponent.radiusSM)
            .overlay(
                RoundedRectangle(cornerRadius: FlowComponent.radiusSM)
                    .stroke(comp.border, lineWidth: 1)
            )
        }
        .buttonStyle(FlowPressStyle())
        .help("Open \(fileName) in an external editor")
        .accessibilityLabel("Open \(fileName) in an external editor")
    }
}

/// Prominent "Open in…" handoff row: every supported editor plus the
/// Finder fallback, each an `OpenInButton` against the current file name.
/// - Note: Legacy layout — prefer `OpenInMenu` (single menu, no truncation).
///   Kept for previews/tests; `AutomationSheet` no longer uses this.
public struct OpenInRow: View {
    public let fileName: String
    public let onOpen: (EditorTarget) -> Void

    @Environment(\.colorScheme) private var scheme

    public init(fileName: String, onOpen: @escaping (EditorTarget) -> Void) {
        self.fileName = fileName
        self.onOpen = onOpen
    }

    public var body: some View {
        let comp = FlowComponent.for(scheme)
        VStack(alignment: .leading, spacing: 8) {
            Text("Open in…")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(comp.textTertiary)
                .accessibilityLabel("Open the generated file in an external editor")
            HStack(spacing: 8) {
                ForEach(EditorTarget.allCases) { target in
                    OpenInButton(target: target, fileName: fileName, onOpen: onOpen)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(comp.surface)
        .cornerRadius(FlowComponent.radiusMD)
        .overlay(
            RoundedRectangle(cornerRadius: FlowComponent.radiusMD)
                .stroke(comp.border, lineWidth: 1)
        )
    }
}
