import SwiftUI
import FlowlineIR
import FlowlineEngine
import FlowlineStorage
import FlowlineAIGateway
import FlowlinePublishing
import FlowlineTemplates

/// Halo apply scope (prototype `haloThis/haloSelected/haloAll`).
public enum FlowHaloScope: String, CaseIterable {
    case thisStep, selected, wholeGuide
    public var label: String {
        switch self { case .thisStep: return "This step"; case .selected: return "Selected steps"; case .wholeGuide: return "Whole guide" }
    }
}

/// Appearance override for the editor chrome (prototype `themeToggle`).
public enum FlowAppearance: String, CaseIterable {
    case system, light, dark
    public var scheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
    public var icon: String {
        switch self { case .system: return "circle.lefthalf.filled"; case .light: return "sun.max"; case .dark: return "moon" }
    }
}

/// One code-workspace tab (prototype `cwTabs`).
public enum FlowCodeFile: String, CaseIterable {
    case script, steps
    public var label: String {
        switch self { case .script: return "guide.spec.ts"; case .steps: return "steps.json" }
    }
}

/// The `…` toolbar menu (prototype `moreMenu`).
public enum FlowMoreAction {
    case mergeNext, defaultHalo, deleteGuide
}

/// Flowline editor — full port of the `Step Recorder Guide Studio` prototype
/// workspace: header + toolbar + bulk bar + stage + gutter, with the AI
/// sidebar on the right and the Library home as the pre-recording view.
///
/// The `StepSession` stays the single model (one guide = one session);
/// guide modes, halo scope, publish state and AI collapse are UI-only.
/// Every mutation persists through the injected `SessionStore`.
public struct FlowlineEditor: View {
    @Binding var session: StepSession
    var settings: FlowlineSettings
    var store: SessionStore
    var synthesis: any StepSynthesisService
    var publisher: any ReviewPublishingService
    var onOpenSettings: () -> Void
    var onSelectSession: (StepSession) -> Void

    // View + selection state (mirrors prototype `state`)
    @State private var view: FlowlineEditorView = .editor
    @State private var selectedID: String?
    @State private var selection: Set<String> = []
    @State private var anchorID: String?
    @State private var history = FlowlineHistory()
    // Parallel undo stack for FlowlineMetaStore.steps: FlowlineHistory only
    // snapshots [Step], so meta would otherwise diverge on undo/redo.
    // TODO: fold meta into FlowlineHistory (store [String:FlowStepMeta]
    // per checkpoint) instead of two parallel stacks.
    @State private var metaUndo: [[String: FlowStepMeta]] = []
    @State private var metaRedo: [[String: FlowStepMeta]] = []
    @State private var mode: FlowlineGuideMode = .standard
    @State private var publishState: FlowlinePublishState = .draft
    @State private var aiCollapsed = true
    @State private var haloKind: FlowlineHaloKind? = nil
    @StateObject private var meta = FlowlineMetaStore()
    @State private var sessions: [StepSession]
    @State private var appearance: FlowAppearance = .system
    @State private var showHalo = false
    @State private var showStyle = false
    @State private var showFullPreview = false
    @State private var previewChecked: Set<String> = []
    @State private var showAutomation = false
    @State private var toast: String?
    @State private var toastCanUndo = false
    @State private var lastShareURL: String?
    @State private var visibility: FlowlineVisibility = .unlisted
    @State private var confirmDelete = false
    @State private var confirmDeleteGuide = false
    @State private var cwFile: FlowCodeFile = .script
    @State private var cwRunning = false
    @State private var cwLogs: [String] = []
    /// Plugin template catalogue (`templates/<id>/manifest.json` via
    /// `GuideTemplate.all`). Drives the live preview's quirks caption;
    /// step rendering stays in `TemplatePreviewProvider` so the side
    /// preview and fullscreen Preview never disagree.
    private let templateRegistry = TemplateRegistry.withDefaults()
    /// Live preview pane collapse — persisted across launches. (Track 2:
    /// workspace WYSIWYG. Meta-store persistence was left out deliberately
    /// so guide style snapshots stay untouched.)
    @AppStorage("flowline.showPreview") private var showPreview = true

    @Environment(\.colorScheme) private var scheme

    /// Effective scheme for this editor's own chrome.
    /// `.preferredColorScheme` only re-resolves `@Environment(\.colorScheme)`
    /// for *descendant* views — `scheme` above still reports the parent
    /// (system / ReviewWindow session-theme) value. Inline builders in this
    /// file (canvas background, header, popovers, sheets) capture that stale
    /// value, so they must resolve tokens from `resolvedScheme` instead.
    /// Children keep working via `.preferredColorScheme(appearance.scheme)`.
    private var resolvedScheme: ColorScheme { appearance.scheme ?? scheme }

    public init(
        session: Binding<StepSession>, settings: FlowlineSettings, store: SessionStore,
        synthesis: any StepSynthesisService, publisher: any ReviewPublishingService,
        onOpenSettings: @escaping () -> Void = {},
        allSessions: [StepSession] = [], onSelectSession: @escaping (StepSession) -> Void = { _ in }
    ) {
        self._session = session
        self.settings = settings
        self.store = store
        self.synthesis = synthesis
        self.publisher = publisher
        self.onOpenSettings = onOpenSettings
        self.onSelectSession = onSelectSession
        self._sessions = State(initialValue: allSessions)
    }

    public var body: some View {
        ZStack {
            HStack(spacing: 0) {
            FlowlineSidebar(
                session: $session, sessions: sessions.isEmpty ? [session] : sessions,
                view: view, meta: meta,
                onSelectView: { v in withAnimation(FlowMotion.standardFast) { view = v } },
                onSelectSession: { s in onSelectSession(s); withAnimation(FlowMotion.standardFast) { view = .editor } },
                onRenameSession: renameSession,
                onMoveSession: { meta.move(sessionID: $0, to: $1); refreshSessions() },
                onDeleteSession: deleteSession,
                onDuplicateSession: duplicateSession,
                onOpenSettings: onOpenSettings
            )
            Divider()
            Group {
                if view == .library { libraryHome.transition(.opacity) }
                else { editorColumn.transition(.opacity) }
            }
            .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
            .animation(FlowMotion.standard, value: view)
            Divider()
            FlowlineAISidebar(
                session: session, gateway: settings.gateway, collapsed: aiCollapsed,
                accent: meta.style(sessionID: session.id).accent,
                scopeStep: selectedStep,
                onToggle: { withAnimation(FlowMotion.standard) { aiCollapsed.toggle() } },
                onOpenSettings: onOpenSettings,
                onSynthesized: { text in
                    session.synthesizedMarkdown = text
                    try? store.saveSession(session)
                },
                synthesize: { sess, gw, style, custom in
                    synthesis.generateStream(session: sess, settings: gw, style: style, customInstructions: custom)
                }
            )
            }
            // Fullscreen WYSIWYG preview — macOS has no fullScreenCover, so the
            // preview takes over the whole window as an overlay instead of a
            // centered sheet.
            if showFullPreview {
                fullPreviewSheet
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .background(FlowComponent.for(resolvedScheme).canvas)
        .preferredColorScheme(appearance.scheme)
        .sheet(isPresented: $showAutomation) { automationSheet }
        .popover(isPresented: $showHalo) { haloPanel }
        .popover(isPresented: $showStyle) { stylePanel }
        .onChange(of: showHalo) { _, open in
            // Click-away dismiss drops the pending pick so previews revert
            // to each step's applied/auto halo. Apply paths nil it first,
            // so this is a no-op after a real apply.
            if !open { haloKind = nil }
        }
        .confirmationDialog("Delete \(deleteTargetCount) step\(deleteTargetCount == 1 ? "" : "s")?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { deleteSelection() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this guide? This removes its Steps.", isPresented: $confirmDeleteGuide) {
            Button("Delete guide", role: .destructive) {
                deleteSession(session.id)
            }
            Button("Cancel", role: .cancel) {}
        }
        .overlay(alignment: .bottom) {
            if let t = toast {
                HStack(spacing: 8) {
                    Text(t)
                        .font(.system(size: 12))
                        .foregroundColor(FlowComponent.for(resolvedScheme).textPrimary)
                    if toastCanUndo {
                        Button("Undo") {
                            withAnimation(FlowMotion.standardFast) { handleToastUndo() }
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(FlowSemantic.for(resolvedScheme).accentDefault)
                        .buttonStyle(FlowPressStyle())
                        .keyboardShortcut("z", modifiers: .command)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(FlowComponent.for(resolvedScheme).surfaceElevated)
                .cornerRadius(FlowComponent.radiusSM)
                .overlay(RoundedRectangle(cornerRadius: FlowComponent.radiusSM).stroke(FlowComponent.for(resolvedScheme).border, lineWidth: 1))
                .shadow(color: FlowSemantic.for(resolvedScheme).shadowDefault, radius: 8, y: 2)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    let canUndo = toastCanUndo
                    DispatchQueue.main.asyncAfter(deadline: .now() + (canUndo ? 5 : 2.4)) {
                        withAnimation(FlowMotion.easeOut) {
                            toast = nil; toastCanUndo = false
                            deletedGuideBackup = nil; deletedGuideFolder = nil; deletedGuideFavorite = false
                        }
                    }
                }
            }
        }
        .animation(FlowMotion.standard, value: toast != nil)
        .onAppear {
            refreshSessions()
            if selectedID == nil { selectedID = session.steps.first?.id }
            if selection.isEmpty, let id = selectedID { selection = [id] }
        }
        .onChange(of: session.id) { _, _ in
            refreshSessions()
            selectedID = session.steps.first?.id
            selection = selectedID.map { [$0] } ?? []
            // Global pending pick must not leak across guides.
            haloKind = nil
        }
        .onChange(of: selectedID) { _, _ in
            // Pending halo pick intentionally survives step changes: the
            // flow is pick-a-kind → click a step → APPLY TO. Nuking it here
            // silently replaced the pick with the guide default on apply.
            // (Panel dismiss still clears it — see showHalo below.)
        }
    }

    private var selectedStep: Step? {
        guard let id = selectedID else { return nil }
        return session.steps.first(where: { $0.id == id })
    }

    private func showToast(_ text: String, undoable: Bool = false) {
        withAnimation(FlowMotion.standard) {
            toast = text
            toastCanUndo = undoable
        }
    }

    private func refreshSessions() {
        sessions = store.listSessions()
    }

    // MARK: - Editor column

    private var editorColumn: some View {
        VStack(spacing: 12) {
            header
            FlowlineToolbar(
                canUndo: !history.undo.isEmpty, canRedo: !history.redo.isEmpty,
                publishState: publishState,
                onSplit: splitStep, onDuplicate: { duplicateSelection() },
                onDelete: { confirmDelete = true },
                onUndo: undo, onRedo: redo,
                onHalo: { haloKind = haloKind ?? meta.style(sessionID: session.id).defaultHalo; showHalo.toggle() },
                onStyle: { showStyle.toggle() },
                onAutomation: { showAutomation = true }, onMore: handleMore,
                onPreview: { showFullPreview = true },
                onPublish: handlePublish,
                accent: meta.style(sessionID: session.id).accent,
                showPreview: showPreview,
                onTogglePreview: { withAnimation(FlowMotion.standard) { showPreview.toggle() } },
                shareURL: lastShareURL ?? session.exports.web,
                currentVisibility: visibility
            )
            if selection.count > 1 {
                bulkBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            workspace
            gutterSection
        }
        .padding(.top, 12)
    }

    // MARK: - Live workspace (visual canvas + text preview)

    /// Two-column WYSIWYG workspace: the existing visual canvas on the
    /// left, the live "how text will look" preview on the right. Both read
    /// the same `session`/`mode`/selection, so every edit flows to both
    /// panes; persistence and undo are untouched.
    private var workspace: some View {
        HStack(alignment: .top, spacing: 12) {
            ScrollView {
                if session.steps.isEmpty {
                    guideEmptyView
                } else {
                    FlowlineStage(
                        session: $session, store: store, selectedID: selectedID,
                        haloKind: haloKind, autoHalo: meta.style(sessionID: session.id).autoHalo,
                        onEditTitle: editTitle, onEditDesc: editDesc,
                        onSelectHaloKind: { haloKind = $0 },
                        meta: meta
                    )
                }
            }
            .frame(minWidth: 320, maxWidth: .infinity)
            if showPreview {
                GuideTextPreview(
                    session: session, mode: mode, selectedID: selectedID,
                    checked: $previewChecked, provider: TemplatePreviewProvider(registry: templateRegistry),
                    onSelect: { selectStep($0, false, false) },
                    quirksCaption: templateRegistry.resolve(id: mode.rawValue)?.quirks.joined(separator: ", "),
                    store: store,
                    onMergeRun: { ids in
                        selection = Set(ids)
                        mergeSelection()
                    }
                )
                .frame(minWidth: 280, idealWidth: 340, maxWidth: 420, maxHeight: .infinity)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(FlowMotion.standard, value: showPreview)
    }

    /// Friendly empty state instead of a blank canvas.
    private var guideEmptyView: some View {
        let t = FlowComponent.for(resolvedScheme)
        return VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundColor(t.textTertiary)
            Text("No steps yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(t.textPrimary)
            Text("Record or add a manual step — it will appear here and in the preview.")
                .font(.system(size: 12))
                .foregroundColor(t.textSecondary)
                .multilineTextAlignment(.center)
            Button("Add manual step") {
                withAnimation(FlowMotion.standard) { insertStep(at: session.steps.count) }
            }
            .font(.system(size: 12, weight: .medium))
            .buttonStyle(FlowPressStyle())
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(.vertical, 24)
    }

    /// Gutter with a header row so its purpose is scannable.
    private var gutterSection: some View {
        let t = FlowComponent.for(resolvedScheme)
        let needsCount = FlowlineStepText.placeholderCount(in: session.steps)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Steps — click to preview")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(t.textSecondary)
                if needsCount > 0 {
                    Text("· \(needsCount) step\(needsCount == 1 ? "" : "s") need\(needsCount == 1 ? "s" : "") instructions")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(FlowSemantic.for(resolvedScheme).warningFg)
                        .help("Add instructions to every step before publishing")
                }
                Spacer()
                Text("\(session.steps.count) steps")
                    .font(.system(size: 11))
                    .foregroundColor(t.textTertiary)
            }
            .padding(.horizontal, 16)
            FlowlineGutter(
                session: $session, store: store, selection: selection,
                onSelect: selectStep,
                onInsert: { insertStep(at: $0) },
                onMove: moveStep,
                numbering: meta.style(sessionID: session.id).numbering
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Real breadcrumb: back to the library + the guide's location
            // (its folder, or the library root when ungrouped).
            HStack(spacing: 6) {
                Button(action: { withAnimation(FlowMotion.standardFast) { view = .library } }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(FlowComponent.for(resolvedScheme).textSecondary)
                }
                .buttonStyle(FlowPressStyle())
                .help("Back to library")
                .accessibilityLabel("Back to library")
                Text(meta.folder(for: session.id)?.name ?? "Library")
                    .font(.system(size: 11))
                    .foregroundColor(FlowComponent.for(resolvedScheme).textSecondary)
            }
            HStack(spacing: 8) {
                TextField("Guide title", text: $session.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundColor(FlowComponent.for(resolvedScheme).textPrimary)
                    .onSubmit { persist() }
                Spacer()
            }
            HStack(spacing: 8) {
                FlowPill(stepCounterText)
                Text(editedRelativeText)
                    .font(.system(size: 11))
                    .foregroundColor(FlowComponent.for(resolvedScheme).textTertiary)
                    .help(editedAbsoluteText)
                Spacer()
                // Appearance (prototype `themeToggle`): system / light / dark.
                Picker("", selection: $appearance) {
                    ForEach(FlowAppearance.allCases, id: \.self) { a in
                        Image(systemName: a.icon).tag(a)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 96)
                // Template switcher (presentation only — the step model never forks)
                HStack(spacing: 4) {
                    Text("Template:")
                        .font(.system(size: 12))
                        .foregroundColor(FlowComponent.for(resolvedScheme).textSecondary)
                    Picker("", selection: $mode) {
                        ForEach(FlowlineGuideMode.allCases) { m in Text(m.label).tag(m) }
                    }
                    .pickerStyle(.menu)
                    .help(mode.copy)
                }
                .frame(maxWidth: 220)
            }
        }
        .padding(.horizontal, 16)
    }

    /// Context-aware step count: position when a step is selected, else total.
    private var stepCounterText: String {
        if let id = selectedID,
           let i = session.steps.firstIndex(where: { $0.id == id }) {
            return "Step \(i + 1) of \(session.steps.count)"
        }
        return "\(session.steps.count) steps"
    }

    /// Relative edited stamp ("Edited 2m ago"); the absolute date lives in `.help`.
    private var editedRelativeText: String {
        let date = session.endedAt ?? session.startedAt
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return "Edited " + f.localizedString(for: date, relativeTo: Date())
    }

    private var editedAbsoluteText: String {
        "Edited \(session.endedAt?.formatted(date: .abbreviated, time: .shortened) ?? session.startedAt.formatted(date: .abbreviated, time: .omitted))"
    }

    private var bulkBar: some View {
        HStack(spacing: 8) {
            Text("\(selection.count) Steps selected")
                .font(.system(size: 12, weight: .semibold))
                .contentTransition(.numericText())
            Spacer()
            Button("Halo") { showHalo = true }.buttonStyle(FlowPressStyle()).font(.system(size: 12))
            Button("Merge") { mergeSelection() }.buttonStyle(FlowPressStyle()).font(.system(size: 12))
            Button("Duplicate") { duplicateSelection() }.buttonStyle(FlowPressStyle()).font(.system(size: 12))
            Button("Delete") { confirmDelete = true }.buttonStyle(FlowPressStyle()).font(.system(size: 12)).foregroundColor(FlowSemantic.for(resolvedScheme).dangerFg)
            Button("Clear") { clearSelection() }.buttonStyle(FlowPressStyle()).font(.system(size: 12))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(FlowSemantic.for(resolvedScheme).accentSubtle)
        .cornerRadius(FlowComponent.radiusMD)
        .padding(.horizontal, 16)
    }

    // MARK: - Library home (pre-recording view)

    private var libraryHome: some View {
        FlowlineLibraryView(
            sessions: sessions.isEmpty ? [session] : sessions,
            store: store,
            meta: meta,
            onOpen: { s in onSelectSession(s); view = .editor }
        )
    }

    // MARK: - Fullscreen Preview (all 7 modes render the same steps)

    private var fullPreviewSheet: some View {
        let sem = FlowSemantic.for(resolvedScheme)
        let t = FlowComponent.for(resolvedScheme)
        let doneCount = session.steps.filter { previewChecked.contains($0.id) }.count
        return NavigationStack {
            ScrollView {
                // Centered WYSIWYG page on a full-bleed canvas.
                VStack(alignment: .center, spacing: 0) {
                    VStack(alignment: .leading, spacing: 20) {
                        // Mode selector — wrapping pills.
                        VStack(alignment: .leading, spacing: 8) {
                            Text("MODE")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(t.textTertiary)
                            FlowLayout(spacing: 8) {
                                ForEach(FlowlineGuideMode.allCases) { m in
                                    let selected = (m == mode)
                                    Button(action: { withAnimation(FlowMotion.standardFast) { mode = m } }) {
                                        Text(m.label)
                                            .font(.system(size: 12, weight: selected ? .semibold : .medium))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background(selected ? sem.accentSubtle : t.surfaceSubtle)
                                            .foregroundColor(selected ? sem.accentDefault : t.textSecondary)
                                            .clipShape(Capsule())
                                            .overlay(
                                                Capsule()
                                                    .stroke(selected ? sem.accentDefault.opacity(0.35) : Color.clear, lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(FlowPressStyle())
                                    .help(m.copy)
                                }
                            }
                            Text(mode.copy)
                                .font(.system(size: 12))
                                .foregroundColor(t.textSecondary)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text(session.title)
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(t.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 8) {
                                FlowPill("\(session.steps.count) steps")
                                FlowPill(mode.label, kind: .accent)
                                FlowPill(publishState.pill, kind: publishState == .draft ? .neutral : .success)
                                if mode == .checklist, !session.steps.isEmpty {
                                    FlowPill("\(doneCount)/\(session.steps.count) done", kind: .success)
                                }
                            }
                        }
                        // Checklist progress row.
                        if mode == .checklist, !session.steps.isEmpty {
                            HStack(spacing: 10) {
                                ProgressView(value: Double(doneCount), total: Double(max(session.steps.count, 1)))
                                    .frame(maxWidth: 220)
                                    .tint(sem.accentDefault)
                                Text(doneCount == session.steps.count ? "All done" : "\(doneCount) of \(session.steps.count) complete")
                                    .font(.system(size: 12))
                                    .foregroundColor(t.textSecondary)
                                Spacer()
                                if doneCount > 0 {
                                    Button("Reset") {
                                        withAnimation(FlowMotion.standardFast) { previewChecked.removeAll() }
                                    }
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(sem.accentDefault)
                                    .buttonStyle(FlowPressStyle())
                                }
                            }
                            .padding(10)
                            .background(t.surfaceSubtle)
                            .cornerRadius(FlowComponent.radiusMD)
                        }
                        Divider()
                        LazyVStack(alignment: .leading, spacing: 0) {
                            let titles = FlowlineStepText.displayTitles(for: session.steps)
                            let provider = TemplatePreviewProvider(registry: templateRegistry)
                            ForEach(session.steps.indices, id: \.self) { i in
                                let s = session.steps[i]
                                fullscreenStepRow(
                                    s, at: i,
                                    title: titles[s.id] ?? FlowlineStepText.readerTitle(for: s),
                                    provider: provider
                                )
                                if mode != .checklist, i < session.steps.count - 1 {
                                    Divider()
                                }
                            }
                        }
                        Text("Published with Flowline")
                            .font(.system(size: 11))
                            .foregroundColor(t.textTertiary)
                            .padding(.top, 4)
                    }
                    .padding(36)
                    .frame(maxWidth: 780, alignment: .topLeading)
                    .background(t.surfaceElevated)
                    .cornerRadius(FlowComponent.radiusLG)
                    .shadow(color: sem.shadowElevated, radius: 24, y: 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: FlowComponent.radiusLG)
                            .stroke(t.borderSubtle, lineWidth: 1)
                    )
                    .padding(32)
                }
                .frame(maxWidth: .infinity)
            }
            .background(t.canvas)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { withAnimation(FlowMotion.standardFast) { showFullPreview = false } }
                        .keyboardShortcut(.escape)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Back to editor") { withAnimation(FlowMotion.standardFast) { showFullPreview = false } }
                }
            }
            .navigationTitle("Preview — \(mode.label)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FlowComponent.for(resolvedScheme).canvas)
        .onExitCommand { showFullPreview = false }
        .onChange(of: session.id) { _, _ in previewChecked.removeAll() }
    }

    /// One fullscreen Preview row: captured visual + shared preview body
    /// (or the shared placeholder card). Mirrors `GuideTextPreview.stepRow` —
    /// media via `PreviewMediaView` (badges included), titles via
    /// `FlowlineStepText.displayTitles`, selection via `FlowlineSelection` —
    /// so the Preview and the side preview never disagree. The raw recorder
    /// string renders as subtitle only, never as the title (no raw
    /// scrollarea/drkmtr/{{base}}); template quirks stay hidden.
    private func fullscreenStepRow(
        _ s: Step, at i: Int, title: String, provider: TemplatePreviewProvider
    ) -> some View {
        let isSel = (s.id == selectedID)
        return VStack(alignment: .leading, spacing: 6) {
            PreviewMediaView(step: s, sessionID: session.id, store: store, maxHeight: 340)
            if FlowlineStepText.isPlaceholder(s) {
                FlowlinePlaceholderCard(
                    step: s, index: i,
                    onAddText: {
                        withAnimation(FlowMotion.standardFast) {
                            selectStep(s.id, false, false)
                            showFullPreview = false
                        }
                    },
                    onCapture: {
                        withAnimation(FlowMotion.standardFast) {
                            selectStep(s.id, false, false)
                            showFullPreview = false
                        }
                    }
                )
            } else if mode == .checklist {
                provider.body(
                    for: s, index: i, mode: mode,
                    checked: previewChecked.contains(s.id),
                    onToggleCheck: {
                        withAnimation(FlowMotion.standardFast) {
                            if previewChecked.contains(s.id) { previewChecked.remove(s.id) }
                            else { previewChecked.insert(s.id) }
                        }
                    },
                    displayTitle: title
                )
            } else {
                Button(action: {
                    withAnimation(FlowMotion.standardFast) { selectStep(s.id, false, false) }
                }) {
                    provider.body(
                        for: s, index: i, mode: mode,
                        checked: false,
                        onToggleCheck: {},
                        displayTitle: title
                    )
                }
                .buttonStyle(FlowPressStyle())
                .help(FlowlineStepText.fullText(step: s, index: i))
            }
        }
        .padding(8)
        .background(isSel ? FlowlineSelection.wash(for: resolvedScheme) : Color.clear)
        .cornerRadius(FlowComponent.radiusMD)
        .overlay(
            RoundedRectangle(cornerRadius: FlowComponent.radiusMD)
                .stroke(isSel ? FlowlineSelection.ring(for: resolvedScheme) : Color.clear, lineWidth: 1)
        )
        .padding(.vertical, mode == .checklist ? 4 : 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(FlowlineStepText.fullText(step: s, index: i))
        .accessibilityAddTraits(isSel ? .isSelected : [])
    }

    // MARK: - Automation sheet (redesigned: script + Open in… + logs)

    private var automationSheet: some View {
        AutomationSheet(
            script: playwrightScript,
            stepsJSON: stepsJSON,
            stepNumber: selectedNumber,
            totalSteps: session.steps.count,
            isRunning: cwRunning,
            logs: cwLogs,
            onRun: runAutomation,
            onCopy: copyAutomation,
            onExport: exportAutomation,
            onOpen: openInEditor,
            onClose: { showAutomation = false },
            onFileChange: { cwFile = $0 }
        )
    }

    /// Writes the visible generated file to a temp path and hands it to the
    /// chosen editor (reveal-in-Finder fallback included, never silent).
    private func openInEditor(_ target: EditorTarget) {
        let name = cwFile.label
        let text = cwFile == .script ? playwrightScript : stepsJSON
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Flowline", isDirectory: true)
        let url = dir.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            showToast("Couldn't stage \(name) for \(target.label).")
            return
        }
        Task {
            let result = await OpenInEditors.open(target, fileURL: url)
            await MainActor.run {
                switch result {
                case .success(let outcome):
                    if let msg = outcome.toastMessage { showToast(msg) }
                    else { showToast("Opened in \(outcome.target.label)") }
                case .failure(let error):
                    showToast(error.humanMessage)
                }
            }
        }
    }

    private var selectedNumber: Int {
        guard let id = selectedID, let i = session.steps.firstIndex(where: { $0.id == id }) else { return 1 }
        return i + 1
    }

    private var playwrightScript: String {
        var out = "// Generated by Flowline — \(session.title)\nimport { test, expect } from '@playwright/test';\n\ntest('\(session.title)', async ({ page }) => {\n"
        for (i, s) in session.steps.enumerated() {
            let target = FlowlineHaloResolver.target(for: s).replacingOccurrences(of: "\"", with: "")
            switch s.action {
            case .click, .doubleClick, .rightClick:
                out += "  // Step \(i + 1): \(s.actionDescription)\n  await page.getByRole('\(s.elementRole?.lowercased() ?? "button")', { name: '\(target)' }).click();\n"
            case .keyPress:
                out += "  // Step \(i + 1): \(s.actionDescription)\n  await page.keyboard.press('\(s.hotkeyCombo ?? "Enter")');\n"
            case .typing, .writeCode:
                out += "  // Step \(i + 1): \(s.actionDescription)\n  await page.keyboard.type(\(swiftString(s.textBlob ?? "")));\n"
            default:
                out += "  // Step \(i + 1): \(s.actionDescription)\n  // halo: \(FlowlineHaloResolver.kind(for: s).rawValue)\n"
            }
        }
        out += "});\n"
        return out
    }

    private var stepsJSON: String {
        let dicts = session.steps.map { s -> [String: Any] in
            [
                "index": s.index,
                "action": s.action.rawValue,
                "app": s.appName,
                "description": s.actionDescription,
                "halo": FlowlineHaloResolver.kind(for: s).rawValue,
            ]
        }
        if let d = try? JSONSerialization.data(withJSONObject: dicts, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: d, encoding: .utf8) { return str }
        return "[]"
    }

    /// Simulated dry-run with streamed log lines (prototype `runCode`).
    /// Real execution happens in the exported script, not the editor.
    private func runAutomation() {
        guard !cwRunning else { return }
        cwRunning = true
        cwLogs = ["$ npx playwright test guide.spec.ts", "  running \(session.steps.count) steps (dry run) …"]
        Task {
            for (i, s) in session.steps.enumerated() {
                try? await Task.sleep(nanoseconds: 280_000_000)
                await MainActor.run {
                    withAnimation(FlowMotion.standardFast) {
                        cwLogs.append("  ✓ step \(i + 1)/\(session.steps.count): \(s.actionDescription.prefix(60))")
                    }
                }
            }
            await MainActor.run {
                withAnimation(FlowMotion.standard) {
                    cwLogs.append("  done — \(session.steps.count) passed, 0 failed")
                    cwRunning = false
                }
            }
        }
    }

    private func copyAutomation() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cwFile == .script ? playwrightScript : stepsJSON, forType: .string)
        showToast("Copied \(cwFile.label)")
    }

    private func swiftString(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "\\'").prefix(120) + "'"
    }

    private func exportAutomation() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "flowline-guide.spec.ts"
        if panel.runModal() == .OK, let url = panel.url {
            try? playwrightScript.write(to: url, atomically: true, encoding: .utf8)
            showToast("Automation exported")
        }
    }

    // MARK: - Halo + style panels

    private var haloPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Halo").font(.system(size: 14, weight: .bold))
            Text("Halo marks the user's interaction with the captured interface. Amber means interaction — never editor state.")
                .font(.system(size: 11))
                .foregroundColor(FlowComponent.for(resolvedScheme).textSecondary)
            Text("TYPE").font(.system(size: 10, weight: .semibold)).foregroundColor(FlowComponent.for(resolvedScheme).textTertiary)
            LazyVGrid(columns: [GridItem(.fixed(88)), GridItem(.fixed(88)), GridItem(.fixed(88))], spacing: 8) {
                ForEach(FlowlineHaloKind.allCases, id: \.self) { k in
                    Button(action: { haloKind = k }) {
                        VStack(spacing: 4) {
                            Image(systemName: k.systemImage)
                            Text(k.label).font(.system(size: 10))
                        }
                        .frame(width: 88, height: 56)
                        .background(haloKind == k ? FlowSemantic.for(resolvedScheme).accentSubtle : FlowComponent.for(resolvedScheme).surfaceSubtle)
                        .cornerRadius(FlowComponent.radiusSM)
                    }
                    .buttonStyle(FlowPressStyle())
                }
            }
            Toggle("Auto Halo — place marks from recorded interaction targets", isOn: Binding(
                get: { meta.style(sessionID: session.id).autoHalo },
                set: { v in meta.updateGuide(sessionID: session.id) { $0.autoHalo = v } }
            ))
                .font(.system(size: 12))
            Text("APPLY TO").font(.system(size: 10, weight: .semibold)).foregroundColor(FlowComponent.for(resolvedScheme).textTertiary)
            HStack(spacing: 8) {
                ForEach(FlowHaloScope.allCases, id: \.self) { scope in
                    Button(scope.label) { applyHalo(scope: scope) }
                        .font(.system(size: 11))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(FlowComponent.for(resolvedScheme).surfaceSubtle)
                        .clipShape(Capsule())
                        .buttonStyle(FlowPressStyle())
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private var stylePanel: some View {
        let style = meta.style(sessionID: session.id)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Guide styling").font(.system(size: 14, weight: .bold))
            styleRow("Image treatment", FlowMediaTreatment.allCases, style.media, labels: { $0.label }) { m in
                meta.updateGuide(sessionID: session.id) { $0.media = m }
            }
            styleRow("Step numbering", FlowNumbering.allCases, style.numbering, labels: { $0.label }) { n in
                meta.updateGuide(sessionID: session.id) { $0.numbering = n }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("KEYCAP STYLE").font(.system(size: 10, weight: .semibold)).foregroundColor(FlowComponent.for(resolvedScheme).textTertiary)
                ForEach(KeycapStyle.allCases, id: \.self) { ks in
                    Button(action: { withAnimation(FlowMotion.standardFast) {
                        meta.updateGuide(sessionID: session.id) { $0.keycapStyle = ks }
                    } }) {
                        HStack(spacing: 8) {
                            KeyStyleThumbnail(ks)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(ks.label).font(.system(size: 11, weight: style.keycapStyle == ks ? .semibold : .regular))
                                Text(ks.blurb).font(.system(size: 10)).foregroundColor(FlowComponent.for(resolvedScheme).textTertiary)
                            }
                            Spacer()
                            if style.keycapStyle == ks {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(FlowSemantic.for(resolvedScheme).accentDefault)
                            }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(style.keycapStyle == ks ? FlowSemantic.for(resolvedScheme).accentSubtle : FlowComponent.for(resolvedScheme).surfaceSubtle)
                        .cornerRadius(FlowComponent.radiusSM)
                    }
                    .buttonStyle(FlowPressStyle())
                    .help("\(ks.label) — \(ks.blurb)")
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("MOUSE STYLE").font(.system(size: 10, weight: .semibold)).foregroundColor(FlowComponent.for(resolvedScheme).textTertiary)
                ForEach(MouseStyle.allCases, id: \.self) { ms in
                    Button(action: { withAnimation(FlowMotion.standardFast) {
                        meta.updateGuide(sessionID: session.id) { $0.mouseStyle = ms }
                    } }) {
                        HStack(spacing: 8) {
                            MouseStyleThumbnail(ms)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(ms.label).font(.system(size: 11, weight: style.mouseStyle == ms ? .semibold : .regular))
                                Text(ms.blurb).font(.system(size: 10)).foregroundColor(FlowComponent.for(resolvedScheme).textTertiary)
                            }
                            Spacer()
                            if style.mouseStyle == ms {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(FlowSemantic.for(resolvedScheme).accentDefault)
                            }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(style.mouseStyle == ms ? FlowSemantic.for(resolvedScheme).accentSubtle : FlowComponent.for(resolvedScheme).surfaceSubtle)
                        .cornerRadius(FlowComponent.radiusSM)
                    }
                    .buttonStyle(FlowPressStyle())
                    .help("\(ms.label) — \(ms.blurb)")
                }
            }
            Text("ACCENT COLOR").font(.system(size: 10, weight: .semibold)).foregroundColor(FlowComponent.for(resolvedScheme).textTertiary)
            HStack(spacing: 8) {
                ForEach(FlowAccentChoice.allCases, id: \.self) { choice in
                    Button(action: { withAnimation(FlowMotion.standardFast) {
                        meta.updateGuide(sessionID: session.id) { $0.accent = choice }
                    } }) {
                        Circle()
                            .fill(choice.color(for: resolvedScheme))
                            .frame(width: 24, height: 24)
                            .overlay(Circle().stroke(FlowComponent.for(resolvedScheme).textInverse, lineWidth: style.accent == choice ? 2 : 0))
                            .scaleEffect(style.accent == choice ? 1.12 : 1.0)
                            .animation(FlowMotion.spring, value: style.accent)
                    }
                    .buttonStyle(FlowPressStyle())
                    .help(choice.label)
                }
            }
            Text("Navigation style").font(.system(size: 12, weight: .medium))
            Text("Steps · Chapters · Dots — Preview renders the same steps.")
                .font(.system(size: 11))
                .foregroundColor(FlowComponent.for(resolvedScheme).textSecondary)
        }
        .padding(16)
        .frame(width: 330)
    }

    private func styleRow<V: Hashable>(
        _ title: String, _ opts: [V], _ sel: V, labels: @escaping (V) -> String,
        action: @escaping (V) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundColor(FlowComponent.for(resolvedScheme).textTertiary)
            HStack(spacing: 8) {
                ForEach(opts, id: \.self) { o in
                    Button(action: { withAnimation(FlowMotion.standardFast) { action(o) } }) {
                        Text(labels(o)).font(.system(size: 11))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(o == sel ? FlowSemantic.for(resolvedScheme).accentSubtle : FlowComponent.for(resolvedScheme).surfaceSubtle)
                            .foregroundColor(o == sel ? FlowSemantic.for(resolvedScheme).accentDefault : FlowComponent.for(resolvedScheme).textPrimary)
                            .cornerRadius(FlowComponent.radiusSM)
                    }
                    .buttonStyle(FlowPressStyle())
                }
            }
        }
    }

    // MARK: - Halo apply (prototype `applyHalo` + `haloFor`)

    private func applyHalo(scope: FlowHaloScope) {
        let kind = haloKind ?? meta.style(sessionID: session.id).defaultHalo
        let ids: [String]
        switch scope {
        case .thisStep:
            ids = selectedID.map { [$0] } ?? []
        case .selected:
            ids = selection.isEmpty ? (selectedID.map { [$0] } ?? []) : Array(selection)
        case .wholeGuide:
            ids = session.steps.map { $0.id }
            meta.updateGuide(sessionID: session.id) { $0.defaultHalo = kind }
        }
        guard !ids.isEmpty else { showToast("Select a step first"); return }
        checkpointMeta()
        for id in ids {
            meta.updateStep(sessionID: session.id, stepID: id) { $0.haloKind = kind }
        }
        // Clear the pending pick so the next step previews its own
        // applied/auto halo instead of this stale selection.
        haloKind = nil
        showHalo = false
        // NOTE: wholeGuide also sets the guide default (toast scope label
        // already says "whole guide").
        showToast("Halo · \(kind.label) → \(scope.label.lowercased())")
    }

    // MARK: - More menu (prototype `moreMenu`)

    private func handleMore(_ action: FlowMoreAction) {
        switch action {
        case .mergeNext: mergeWithNext()
        case .defaultHalo:
            checkpointMeta()
            meta.updateGuide(sessionID: session.id) {
                $0.defaultHalo = haloKind ?? $0.defaultHalo
                $0.autoHalo = true
            }
            haloKind = nil
            showToast("Default Halo set — Auto Halo on")
        case .deleteGuide: confirmDeleteGuide = true
        }
    }

    private func mergeWithNext() {
        guard let id = selectedID,
              let i = session.steps.firstIndex(where: { $0.id == id }),
              session.steps.indices.contains(i + 1) else {
            showToast("No next step to merge with"); return
        }
        checkpoint()
        let next = session.steps[i + 1]
        let notes = session.steps[i].userNotes ?? ""
        session.steps[i].userNotes = (notes.isEmpty ? "" : notes + " ") + (next.userNotes ?? next.actionDescription)
        session.steps.remove(at: i + 1)
        meta.removeSteps(sessionID: session.id, ids: [next.id])
        renumber()
        persist()
        showToast("Merged with next step", undoable: true)
    }

    // MARK: - Sessions (rename / move / delete via sidebar + menus)

    private func renameSession(_ id: String, title: String) {
        if id == session.id {
            session.title = title
            persist()
        } else if var other = (try? store.loadSession(id: id)) {
            other.title = title
            try? store.saveSession(other)
        }
        refreshSessions()
    }

    @State private var deletedGuideBackup: StepSession?
    @State private var deletedGuideFolder: String?
    @State private var deletedGuideFavorite: Bool = false

    private func deleteSession(_ id: String) {
        // Backup for the undo toast (guide deletes are destructive on disk).
        if id == session.id {
            deletedGuideBackup = session
        } else if let other = try? store.loadSession(id: id) {
            deletedGuideBackup = other
        } else {
            deletedGuideBackup = nil
        }
        deletedGuideFolder = meta.sessionFolder[id]
        deletedGuideFavorite = meta.isFavorite(id)
        meta.move(sessionID: id, to: nil)
        meta.setFavorite(id, false)
        try? store.deleteSession(id: id)
        refreshSessions()
        if id == session.id {
            if let next = sessions.first {
                onSelectSession(next)
                view = .editor
            } else {
                let fresh = StepSession(title: "Untitled guide")
                try? store.saveSession(fresh)
                refreshSessions()
                onSelectSession(fresh)
                view = .editor
            }
        }
        showToast("Guide deleted", undoable: true)
    }

    /// Real duplicate backing the sidebar "Duplicate guide" item (replaces
    /// the old placeholder that just re-opened the source). The copy keeps
    /// its steps, folder assignment, guide style and per-step meta.
    private func duplicateSession(_ id: String) {
        guard let src = (id == session.id ? session : (try? store.loadSession(id: id))) else { return }
        var copy = src
        copy.id = "sess_\(UUID().uuidString.prefix(8).lowercased())"
        copy.title = src.title + " (copy)"
        copy.startedAt = Date()
        copy.endedAt = nil
        try? store.saveSession(copy)
        let srcStyle = meta.style(sessionID: src.id)
        meta.updateGuide(sessionID: copy.id) { $0 = srcStyle }
        for step in copy.steps {
            if let m = meta.steps["\(src.id)/\(step.id)"] {
                let captured = m
                meta.updateStep(sessionID: copy.id, stepID: step.id) { $0 = captured }
            }
        }
        if let fid = meta.sessionFolder[src.id] {
            meta.move(sessionID: copy.id, to: fid)
        }
        refreshSessions()
        onSelectSession(copy)
        view = .editor
        showToast("Guide duplicated")
    }

    /// Toast Undo branches: a pending guide-delete backup restores the
    /// session file + folder/favorite mapping, otherwise it is step undo.
    private func handleToastUndo() {
        if let backup = deletedGuideBackup {
            try? store.saveSession(backup)
            if let fid = deletedGuideFolder { meta.move(sessionID: backup.id, to: fid) }
            if deletedGuideFavorite { meta.setFavorite(backup.id, true) }
            deletedGuideBackup = nil; deletedGuideFolder = nil; deletedGuideFavorite = false
            refreshSessions()
            onSelectSession(backup)
            view = .editor
            toast = nil
            showToast("Guide restored")
        } else {
            undo()
            toast = nil
        }
    }

    // MARK: - Mutations (all push history + persist)

    private func persist() {
        try? store.saveSession(session)
        if publishState == .published { publishState = .updated }
    }

    private func checkpoint() {
        history.push(session.steps)
        pushMetaCheckpoint()
    }

    /// Push the meta dict onto the parallel undo stack (clears redo).
    /// Meta-only mutations (applyHalo, defaultHalo) pair the meta snapshot
    /// with an (unchanged) step snapshot so the two stacks stay 1:1 and
    /// undo/redo restores both together.
    private func pushMetaCheckpoint() {
        metaUndo.append(meta.stepsSnapshot())
        if metaUndo.count > 60 { metaUndo.removeFirst() }
        metaRedo.removeAll()
    }

    private func checkpointMeta() {
        history.push(session.steps)
        pushMetaCheckpoint()
    }

    private func undo() {
        if let prev = history.popUndo(current: session.steps) {
            session.steps = prev
            if let m = metaUndo.popLast() {
                metaRedo.append(meta.stepsSnapshot())
                meta.restoreSteps(m)
            }
            renumber()
            persist()
        }
    }
    private func redo() {
        if let next = history.popRedo(current: session.steps) {
            session.steps = next
            if let m = metaRedo.popLast() {
                metaUndo.append(meta.stepsSnapshot())
                meta.restoreSteps(m)
            }
            renumber()
            persist()
        }
    }

    private func selectStep(_ id: String, _ cmd: Bool, _ shift: Bool) {
        if shift, let anchor = anchorID,
           let a = session.steps.firstIndex(where: { $0.id == anchor }),
           let b = session.steps.firstIndex(where: { $0.id == id }) {
            let range = min(a, b)...max(a, b)
            selection = Set(range.map { session.steps[$0].id })
        } else if cmd {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            anchorID = id
        } else {
            selection = [id]
            anchorID = id
        }
        selectedID = id
    }

    private func clearSelection() {
        if let id = selectedID { selection = [id] }
    }

    private func renumber() {
        for i in session.steps.indices { session.steps[i].index = i + 1 }
    }

    private func insertStep(at index: Int) {
        checkpoint()
        let ref = session.steps.indices.contains(min(index, session.steps.count - 1)) ? session.steps[min(index, session.steps.count - 1)] : nil
        let clamped = max(0, min(index, session.steps.count))
        let s = Step(
            index: clamped + 1, timestamp: Date(), action: .manual,
            appName: ref?.appName ?? "Manual Step",
            actionDescription: "Enter step instructions"
        )
        session.steps.insert(s, at: clamped)
        renumber()
        selectedID = s.id
        selection = [s.id]
        persist()
        showToast("Step inserted at \(clamped + 1)", undoable: true)
    }

    private func duplicateSelection() {
        let ids = selection.isEmpty ? (selectedID.map { [$0] } ?? []) : Array(selection)
        guard !ids.isEmpty else { return }
        checkpoint()
        var added: [String] = []
        for id in ids.sorted(by: { a, b in
            (session.steps.firstIndex(where: { $0.id == a }) ?? 0) > (session.steps.firstIndex(where: { $0.id == b }) ?? 0)
        }) {
            guard let i = session.steps.firstIndex(where: { $0.id == id }) else { continue }
            var copy = session.steps[i]
            copy.id = UUID().uuidString
            copy.actionDescription += " (copy)"
            session.steps.insert(copy, at: i + 1)
            meta.copyStepMeta(sessionID: session.id, fromID: id, toID: copy.id)
            added.append(copy.id)
        }
        renumber()
        if let last = added.last { selectedID = last }
        selection = Set(added)
        persist()
        showToast("\(added.count) step\(added.count == 1 ? "" : "s") duplicated", undoable: true)
    }

    private func splitStep() {
        guard let id = selectedID,
              let i = session.steps.firstIndex(where: { $0.id == id }) else { return }
        let notes = session.steps[i].userNotes ?? ""
        let parts = notes.components(separatedBy: ". ")
        guard parts.count > 1 else {
            // Split the title sentence as a fallback.
            let t = session.steps[i].actionDescription.components(separatedBy: ". ")
            guard t.count > 1 else { toast = "Nothing to split — the description is one sentence"; return }
            checkpoint()
            session.steps[i].actionDescription = t[0]
            var next = session.steps[i]
            next.id = UUID().uuidString
            next.actionDescription = t[1...].joined(separator: ". ")
            session.steps.insert(next, at: i + 1)
            meta.copyStepMeta(sessionID: session.id, fromID: id, toID: next.id)
            renumber(); persist()
            showToast("Step split into two", undoable: true)
            return
        }
        checkpoint()
        session.steps[i].userNotes = parts[0]
        var next = session.steps[i]
        next.id = UUID().uuidString
        next.userNotes = parts[1...].joined(separator: ". ")
        session.steps.insert(next, at: i + 1)
        meta.copyStepMeta(sessionID: session.id, fromID: id, toID: next.id)
        renumber()
        selectedID = next.id
        selection = [next.id]
        persist()
        showToast("Step split into two", undoable: true)
    }

    /// Steps the pending delete confirm covers (mirrors `deleteSelection`).
    private var deleteTargetCount: Int {
        selection.isEmpty ? (selectedID == nil ? 0 : 1) : selection.count
    }

    private func deleteSelection() {
        let ids = selection.isEmpty ? (selectedID.map { [$0] } ?? []) : Array(selection)
        guard !ids.isEmpty else { return }
        checkpoint()
        session.steps.removeAll(where: { ids.contains($0.id) })
        meta.removeSteps(sessionID: session.id, ids: ids)
        renumber()
        selectedID = session.steps.last?.id
        selection = selectedID.map { [$0] } ?? []
        persist()
        showToast("\(ids.count) step\(ids.count == 1 ? "" : "s") deleted", undoable: true)
    }

    private func mergeSelection() {
        let idxs = selection.compactMap { id in session.steps.firstIndex(where: { $0.id == id }) }.sorted()
        guard idxs.count >= 2 else { toast = "Select at least two steps to merge"; return }
        checkpoint()
        let head = idxs[0]
        var mergedNotes = session.steps[head].userNotes ?? ""
        for i in idxs.dropFirst() {
            mergedNotes += (mergedNotes.isEmpty ? "" : " ") + (session.steps[i].userNotes ?? session.steps[i].actionDescription)
        }
        session.steps[head].userNotes = mergedNotes
        let removedIDs = idxs.dropFirst().map { session.steps[$0].id }
        for i in idxs.dropFirst().reversed() { session.steps.remove(at: i) }
        // Head keeps its id + halo override; drop orphans for removed steps.
        meta.removeSteps(sessionID: session.id, ids: removedIDs)
        renumber()
        selectedID = session.steps[head].id
        selection = [session.steps[head].id]
        persist()
        showToast("Merged \(idxs.count) steps into one", undoable: true)
    }

    private func moveStep(from: Int, to: Int) {
        guard session.steps.indices.contains(from), session.steps.indices.contains(to), from != to else { return }
        checkpoint()
        let m = session.steps.remove(at: from)
        session.steps.insert(m, at: to)
        renumber()
        selectedID = m.id
        selection = [m.id]
        persist()
        showToast("Step reordered", undoable: true)
    }

    private func editTitle(_ id: String, _ title: String) {
        guard let i = session.steps.firstIndex(where: { $0.id == id }) else { return }
        session.steps[i].actionDescription = title
        persist()
    }
    private func editDesc(_ id: String, _ desc: String) {
        guard let i = session.steps.firstIndex(where: { $0.id == id }) else { return }
        session.steps[i].userNotes = desc
        persist()
    }

    // MARK: - Publish

    private func handlePublish(_ action: FlowlinePublishAction) {
        switch action {
        case .shareLink:
            // Copyable link: copies the full URL string to the clipboard.
            let link = lastShareURL ?? session.exports.web
            if let link {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link, forType: .string)
                showToast("Link copied — paste it anywhere")
            } else {
                showToast("Publish first — then copy the link")
            }
        case .openLink:
            // Clickable URL: opens the published page in the default browser.
            if let str = lastShareURL ?? session.exports.web,
               let url = URL(string: str), url.scheme != nil {
                publisher.openInBrowser(url: url)
                showToast("Opened in browser")
            } else if session.exports.web != nil {
                showToast("Publish again to open the fresh link")
            } else {
                showToast("Publish first — then open the link")
            }
        case .shareEmail:
            // Email share: opens Mail with subject + link body.
            let link = lastShareURL ?? session.exports.web
            guard let link else {
                showToast("Publish first — then share by email")
                return
            }
            let subject = session.title.isEmpty ? "Guide" : session.title
            let body = "\(subject)\n\(link)"
            var comps = URLComponents()
            comps.scheme = "mailto"
            comps.queryItems = [
                URLQueryItem(name: "subject", value: subject),
                URLQueryItem(name: "body", value: body),
            ]
            if let url = comps.url {
                publisher.openInBrowser(url: url)
                showToast("Opened Mail with link")
            } else {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link, forType: .string)
                showToast("Link copied — paste it into email")
            }
        case .publishChanges:
            // Placeholder steps block publish: stay Draft and say why.
            let needs = FlowlineStepText.placeholderCount(in: session.steps)
            guard needs == 0 else {
                publishState = .draft
                showToast("\(needs) step\(needs == 1 ? "" : "s") need\(needs == 1 ? "s" : "") instructions")
                return
            }
            do {
                let url = try publisher.exportWeb(session: session, publishing: settings.publishing)
                publishState = .published
                lastShareURL = url.absoluteString
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                showToast("Changes published — link copied")
            } catch { showToast("Publish failed: \(error.localizedDescription)") }
        case .visibility(let v):
            visibility = v
            switch v {
            case .public: showToast("Visibility: Public — anyone can find and view")
            case .unlisted: showToast("Visibility: Unlisted — only people with the link")
            case .private: showToast("Visibility: Private — only you")
            }
        case .pdf:
            Task {
                do {
                    let url = try await publisher.exportPDF(session: session, publishing: settings.publishing)
                    await MainActor.run { showToast("PDF exported: \(url.lastPathComponent)") }
                } catch {
                    await MainActor.run { showToast("PDF failed: \(error.localizedDescription)") }
                }
            }
        case .html:
            do {
                let url = try publisher.exportWeb(session: session, publishing: settings.publishing)
                publishState = .published
                lastShareURL = url.absoluteString
                showToast("HTML exported: \(url.lastPathComponent)")
            } catch { showToast("HTML failed: \(error.localizedDescription)") }
        case .markdown:
            do {
                let url = try publisher.exportMarkdown(session: session)
                showToast("Markdown exported: \(url.lastPathComponent)")
            } catch { showToast("Markdown failed: \(error.localizedDescription)") }
        }
    }
}
