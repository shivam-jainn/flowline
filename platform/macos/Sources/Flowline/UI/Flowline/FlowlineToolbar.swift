import SwiftUI

/// Editor toolbar: Undo Redo | Split Duplicate Delete | Highlight Style |
/// Preview | Publish | More. Port of prototype `.toolbar`.
/// Consumes component toolbar tokens only (§18); monochrome + accent-active.
public struct FlowlineToolbar: View {
    var canUndo: Bool
    var canRedo: Bool
    var publishState: FlowlinePublishState
    /// Effective share URL string (file:// after publish, or persisted
    /// relative export path). Nil = never published — share rows stay disabled.
    var shareURL: String? = nil
    var currentVisibility: FlowlineVisibility = .unlisted
    var onSplit: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onHalo: () -> Void
    var onStyle: () -> Void
    var onAutomation: () -> Void
    var onMore: (FlowMoreAction) -> Void
    var onPreview: () -> Void
    var onPublish: (FlowlinePublishAction) -> Void
    var accent: FlowAccentChoice = .blue
    var showPreview: Bool = false
    var onTogglePreview: () -> Void = {}

    @Environment(\.colorScheme) private var scheme

    public init(
        canUndo: Bool, canRedo: Bool, publishState: FlowlinePublishState,
        onSplit: @escaping () -> Void, onDuplicate: @escaping () -> Void, onDelete: @escaping () -> Void,
        onUndo: @escaping () -> Void, onRedo: @escaping () -> Void,
        onHalo: @escaping () -> Void, onStyle: @escaping () -> Void,
        onAutomation: @escaping () -> Void, onMore: @escaping (FlowMoreAction) -> Void,
        onPreview: @escaping () -> Void, onPublish: @escaping (FlowlinePublishAction) -> Void,
        accent: FlowAccentChoice = .blue,
        showPreview: Bool = false, onTogglePreview: @escaping () -> Void = {},
        shareURL: String? = nil, currentVisibility: FlowlineVisibility = .unlisted
    ) {
        self.canUndo = canUndo; self.canRedo = canRedo; self.publishState = publishState
        self.onSplit = onSplit; self.onDuplicate = onDuplicate; self.onDelete = onDelete
        self.onUndo = onUndo; self.onRedo = onRedo
        self.onHalo = onHalo; self.onStyle = onStyle
        self.onAutomation = onAutomation; self.onMore = onMore
        self.onPreview = onPreview; self.onPublish = onPublish
        self.accent = accent
        self.showPreview = showPreview; self.onTogglePreview = onTogglePreview
        self.shareURL = shareURL; self.currentVisibility = currentVisibility
    }

    public var body: some View {
        let t = FlowComponent.for(scheme)
        let sem = FlowSemantic.for(scheme)
        HStack(spacing: 4) {
            // Undo / Redo lead: the safest actions come first.
            TBtn("arrow.uturn.backward", nil, disabled: !canUndo, shortcut: ("z", .command), tip: "Undo", action: onUndo)
            TBtn("arrow.uturn.forward", nil, disabled: !canRedo, shortcut: ("z", [.command, .shift]), tip: "Redo", action: onRedo)
            Divider().frame(height: 18)
            TBtn("scissors", "Split", tip: "Split this step into two at the sentence", action: onSplit)
            TBtn("doc.on.doc", "Duplicate", shortcut: ("d", .command), tip: "Duplicate the selected steps", action: onDuplicate)
            Divider().frame(height: 18)
            // Delete stands apart from the editing tools: destructive.
            TBtn("trash", nil, danger: true, tip: "Delete the selected steps", action: onDelete)
            Divider().frame(height: 18)
            TBtn("cursorarrow.rays", "Highlight", active: false, tip: "Highlight the reader's interaction — amber mark, never editor state", action: onHalo)
            TBtn("paintbrush", "Style", tip: "Guide styling: image treatment, numbering, accent", action: onStyle)
            Divider().frame(height: 18)
            TBtn("sidebar.right", "Preview", active: showPreview, tip: "Toggle the live preview — what readers will see", action: onTogglePreview)
            Spacer(minLength: 4)
            // Publish split-button: primary action on the left, chevron menu
            // on the RIGHT edge only. The chevron never leads the label.
            HStack(spacing: 0) {
                Button(action: primaryPublishAction) {
                    HStack(spacing: 6) {
                        Text(publishLabel)
                            .font(.system(size: 12, weight: .semibold))
                        // Amber dot = the live guide has unpublished changes.
                        if publishState == .updated {
                            Circle()
                                .fill(sem.warningFg)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.leading, FlowSpacing.md)
                    .padding(.trailing, 6)
                    .padding(.vertical, FlowSpacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(publishHelp)
                .accessibilityLabel(publishHelp)
                Divider().frame(height: 16).padding(.horizontal, 2)
                Menu {
                    Section("Share") {
                        if let url = shareURL, !url.isEmpty {
                            Button(action: { onPublish(.shareLink) }) {
                                Label {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Copy link")
                                        Text(shortLink(url))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "link")
                                }
                            }
                            .keyboardShortcut("l", modifiers: .command)
                            Button(action: { onPublish(.openLink) }) {
                                Label("Open link in browser", systemImage: "safari")
                            }
                            Button(action: { onPublish(.shareEmail) }) {
                                Label("Share via Email…", systemImage: "envelope")
                            }
                        } else {
                            Text("Publish first to enable sharing")
                        }
                    }
                    Section("Publish") {
                        if publishState == .published {
                            Button(action: { onPublish(.publishChanges) }) {
                                Label("Published — up to date", systemImage: "checkmark.circle.fill")
                            }
                            .disabled(true)
                        } else {
                            Button(action: { onPublish(.publishChanges) }) {
                                Label(
                                    publishState == .updated ? "Publish changes" : "Publish guide",
                                    systemImage: "arrow.up.circle.fill"
                                )
                            }
                            .keyboardShortcut("p", modifiers: [.command, .shift])
                        }
                        Menu {
                            ForEach([FlowlineVisibility.public, .unlisted, .private], id: \.label) { v in
                                Button(action: { onPublish(.visibility(v)) }) {
                                    Label {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(v.label)
                                            Text(v.blurb)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    } icon: {
                                        if v.label == currentVisibility.label {
                                            Image(systemName: "checkmark")
                                        } else {
                                            Image(systemName: v.systemImage)
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label("Visibility: \(currentVisibility.label)", systemImage: currentVisibility.systemImage)
                        }
                    }
                    Section("Export") {
                        Button(action: { onPublish(.pdf) }) {
                            Label("Export PDF…", systemImage: "doc.richtext")
                        }
                        Button(action: { onPublish(.html) }) {
                            Label("Export HTML page…", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                        Button(action: { onPublish(.markdown) }) {
                            Label("Export Markdown…", systemImage: "doc.plaintext")
                        }
                    }
                } label: {
                    // Trailing chevron: the ONLY dropdown indicator here.
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.leading, 2)
                        .padding(.trailing, FlowSpacing.md)
                        .padding(.vertical, FlowSpacing.sm)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help(publishHelp)
                .accessibilityLabel("Publish options")
            }
            .background(publishState == .draft ? t.surfaceSubtle : sem.publishSuccess)
            .foregroundColor(publishState == .draft ? t.textPrimary : t.primaryFg)
            .cornerRadius(FlowComponent.radiusSM)
            .shadow(color: sem.shadowSubtle, radius: 4, y: 1)
            // Overflow is a plain icon button — it must NOT show its own
            // chevron. The missing `.menuIndicator(.hidden)` here was the
            // "…∨" bug: macOS renders a default indicator for borderless
            // menus unless explicitly hidden.
            Menu {
                Button("Merge with next step") { onMore(.mergeNext) }
                Button("Set default Highlight for guide") { onMore(.defaultHalo) }
                Divider()
                // Automation lives here now, not in the toolbar row — the
                // sheet (script, dry run, export) is unchanged.
                Button("Automation…") { onAutomation() }
                Divider()
                Button("Delete guide", role: .destructive) { onMore(.deleteGuide) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "ellipsis").font(.system(size: 12))
                }
                .foregroundColor(FlowComponent.for(scheme).textSecondary)
                .padding(.horizontal, FlowSpacing.sm).padding(.vertical, FlowSpacing.sm)
                .background(Color.clear)
                .cornerRadius(FlowComponent.radiusXS)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("More actions")
            .accessibilityLabel("More actions")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(t.surface)
        .cornerRadius(FlowComponent.radiusMD)
        .overlay(RoundedRectangle(cornerRadius: FlowComponent.radiusMD).stroke(t.border, lineWidth: 1))
        .shadow(color: sem.shadowSubtle, radius: 6, y: 1)
        .padding(.horizontal, 16)
    }

    /// Tooltip for the stateful Publish button. The `publishState` → label
    /// logic lives here, next to the dot + color states above.
    private var publishHelp: String {
        switch publishState {
        case .draft: return "Publish this guide — share link or export"
        case .published: return "Published — share link or export"
        case .updated: return "Unpublished changes — publish, share, or export"
        }
    }

    /// Main-button label: "Publish" until first publish, "Published" after.
    private var publishLabel: String {
        publishState == .published ? "Published" : "Publish"
    }

    /// Primary click: publish when dirty/draft, copy the link when clean.
    private func primaryPublishAction() {
        if publishState == .published {
            onPublish(.shareLink)
        } else {
            onPublish(.publishChanges)
        }
    }

    /// Middle-truncated link preview for the Copy-link row.
    private func shortLink(_ url: String) -> String {
        let maxLen = 44
        guard url.count > maxLen else { return url }
        // Prefer the most meaningful tail (host + last path component).
        if let parsed = URL(string: url), let host = parsed.host {
            let tail = parsed.lastPathComponent
            let short = tail.isEmpty ? host : "\(host)/…/\(tail)"
            if short.count <= maxLen { return short }
            return String(short.prefix(maxLen - 1)) + "…"
        }
        return String(url.prefix(maxLen - 1)) + "…"
    }

    private func TBtn(
        _ sys: String, _ label: String?,
        danger: Bool = false, disabled: Bool = false, active: Bool = false,
        shortcut: (String, EventModifiers)? = nil, tip: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        // Even buttons: labeled = 12×8, icon-only = 8×8, leading icon + 6pt gap
        return ToolbarHoverButton(danger: danger, disabled: disabled, active: active, shortcut: shortcut, action: action) {
            HStack(spacing: 6) {
                Image(systemName: sys).font(.system(size: 12))
                if let label { Text(label).font(.system(size: 12)) }
            }
            .padding(.horizontal, label == nil ? FlowSpacing.sm : FlowSpacing.md)
            .padding(.vertical, FlowSpacing.sm)
        }
        .help(tip ?? label ?? sys)
        .accessibilityLabel(label ?? sys)
    }
}

/// Toolbar button: transparent → surfaceSubtle on hover, accentSubtle+accent
/// when active, danger foreground for destructive. Animated via motion tokens.
private struct ToolbarHoverButton<Label: View>: View {
    var danger: Bool
    var disabled: Bool
    var active: Bool
    var shortcut: (String, EventModifiers)? = nil
    var action: () -> Void
    var label: () -> Label
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = FlowComponent.for(scheme)
        Button(action: { withAnimation(FlowMotion.standardFast) { action() } }) {
            label()
                .foregroundColor(danger ? t.dangerFg : (active ? t.toolbarFgActive : (hovering ? t.toolbarFgHover : t.toolbarFg)))
                .background(active ? t.toolbarBgActive : (hovering ? t.toolbarBgHover : t.toolbarBg))
                .cornerRadius(FlowComponent.radiusXS)
                .opacity(disabled ? 0.35 : 1)
                .scaleEffect(hovering && !disabled ? 1.03 : 1.0)
                .animation(FlowMotion.standardFast, value: hovering)
        }
        .buttonStyle(FlowPressStyle())
        .disabled(disabled)
        .onHover { hovering = $0 }
        .ifLet(shortcut) { view, sc in view.keyboardShortcut(KeyEquivalent(Character(sc.0)), modifiers: sc.1) }
    }
}

private extension View {
    /// Applies `transform` only when `value` is non-nil (keyboard shortcuts).
    @ViewBuilder
    func ifLet<V, T: View>(_ value: V?, transform: (Self, V) -> T) -> some View {
        if let value { transform(self, value) } else { self }
    }
}

public enum FlowlineVisibility { case `public`, unlisted, `private`
    public var label: String {
        switch self {
        case .public: return "Public"
        case .unlisted: return "Unlisted"
        case .private: return "Private"
        }
    }
    public var systemImage: String {
        switch self {
        case .public: return "globe"
        case .unlisted: return "link"
        case .private: return "lock.fill"
        }
    }
    public var blurb: String {
        switch self {
        case .public: return "Anyone can find and view"
        case .unlisted: return "Only people with the link"
        case .private: return "Only you"
        }
    }
}
public enum FlowlinePublishAction {
    case shareLink, openLink, shareEmail, publishChanges, visibility(FlowlineVisibility), pdf, html, markdown
}
