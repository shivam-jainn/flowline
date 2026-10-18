import SwiftUI
import AppKit
import FlowlineIR
import FlowlineStorage
import FlowlineTemplates

/// Seam for track 1 (`FlowlineTemplates` + `templates/` folder): per-mode
/// step-body rendering for the live preview.
///
/// `GuideTextPreview` renders through this protocol instead of switching on
/// `FlowlineGuideMode` itself, so track 1 can plug a template-driven
/// provider in without touching call sites:
///
///     struct TemplatePreviewProvider: GuidePreviewProvider {
///         func body(for step: Step, index: Int, mode: FlowlineGuideMode,
///                   checked: Bool, onToggleCheck: @escaping () -> Void,
///                   displayTitle: String) -> AnyView { … }
///     }
///     GuideTextPreview(session:…, provider: TemplatePreviewProvider(), …)
///
/// Until then `FlowlineGuidePreviewProvider` renders directly from
/// `FlowlineGuideMode`, so the workspace compiles standalone.
public protocol GuidePreviewProvider {
    /// Render one step exactly as readers will see it in `mode`.
    /// `checked` / `onToggleCheck` back the checklist checkbox row;
    /// non-checklist modes ignore them. `displayTitle` is the list-level
    /// humanized title (verb → target with ·suffix de-dupe); the raw
    /// `actionDescription` renders as subtitle only, never as the title.
    func body(
        for step: Step, index: Int, mode: FlowlineGuideMode,
        checked: Bool, onToggleCheck: @escaping () -> Void,
        displayTitle: String
    ) -> AnyView
}

public extension GuidePreviewProvider {
    /// Back-compat: callers without list context fall back to the
    /// humanized verb → target title.
    func body(
        for step: Step, index: Int, mode: FlowlineGuideMode,
        checked: Bool, onToggleCheck: @escaping () -> Void
    ) -> AnyView {
        body(
            for: step, index: index, mode: mode,
            checked: checked, onToggleCheck: onToggleCheck,
            displayTitle: FlowlineStepText.readerTitle(for: step)
        )
    }
}

// MARK: - Shared step text (preview + gutter)

/// Human reader copy for steps. Centralizes the PREVIEW + FILMSTRIP
/// rules so the side preview, the gutter and tooltips never disagree:
/// humanized verb → target titles, placeholder detection, duplicate-run
/// grouping, collision de-dupe.
enum FlowlineStepText {
    /// Raw recorder placeholder written by `insertStep` — never rendered
    /// as reader-facing content.
    static let placeholderTitle = "Enter step instructions"

    static func isPlaceholder(_ step: Step) -> Bool {
        let t = step.actionDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t == placeholderTitle
    }

    static func placeholderCount(in steps: [Step]) -> Int {
        steps.filter(isPlaceholder).count
    }

    /// Reader title: human verb → target · app. Never the raw recorder
    /// string. `.manual` reads "Manual step" here; "Do" stays reserved
    /// for the automation export.
    static func readerTitle(for step: Step) -> String {
        if step.action == .manual { return "Manual step" }
        let verb = FlowlineHaloResolver.verb(for: step)
        let target = FlowlineHaloResolver.target(for: step)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let app = step.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return app.isEmpty ? verb : "\(verb) in \(app)" }
        guard !app.isEmpty, target != app else {
            return app.isEmpty ? "\(verb) \(target)" : "\(verb) in \(app)"
        }
        return "\(verb) → \(target) · \(app)"
    }

    /// Full untruncated text for tooltips / accessibility labels.
    static func fullText(step: Step, index: Int) -> String {
        if isPlaceholder(step) { return "Step \(index + 1) — needs instructions" }
        let title = readerTitle(for: step)
        let raw = step.actionDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty || raw == title { return "Step \(index + 1): \(title)" }
        return "Step \(index + 1): \(title) — \(raw)"
    }

    /// Per-step display titles with a ·suffix on collision (window title,
    /// else element title, else Step N). Keyed by step id.
    static func displayTitles(for steps: [Step]) -> [String: String] {
        let base = steps.map { readerTitle(for: $0) }
        var seen: [String: Int] = [:]
        for b in base { seen[b, default: 0] += 1 }
        var out: [String: String] = [:]
        for (i, s) in steps.enumerated() {
            var title = base[i]
            if (seen[base[i]] ?? 0) > 1 {
                let extra: String = {
                    if !s.windowTitle.isEmpty, s.windowTitle != s.appName { return s.windowTitle }
                    if let e = s.elementTitle, !e.isEmpty,
                       e != FlowlineHaloResolver.target(for: s) { return e }
                    return ""
                }()
                title += extra.isEmpty ? " · Step \(i + 1)" : " · \(extra)"
            }
            out[s.id] = title
        }
        return out
    }

    /// Runs of ≥2 consecutive steps sharing verb + target (duplicate
    /// bursts). Returns index groups; the preview renders an inline
    /// "N similar — Merge / Keep all" affordance per run.
    static func similarRuns(in steps: [Step]) -> [[Int]] {
        var runs: [[Int]] = []
        var cur: [Int] = []
        func key(_ s: Step) -> String {
            "\(FlowlineHaloResolver.verb(for: s))|\(FlowlineHaloResolver.target(for: s))"
        }
        for (i, s) in steps.enumerated() {
            if let last = cur.last, last == i - 1, key(steps[last]) == key(s) {
                cur.append(i)
            } else {
                if cur.count >= 2 { runs.append(cur) }
                cur = [i]
            }
        }
        if cur.count >= 2 { runs.append(cur) }
        return runs
    }
}

/// Shared selection tokens — preview rows and gutter cards resolve the
/// same ring + wash so selection reads as one state in both panes.
enum FlowlineSelection {
    static func ring(for scheme: ColorScheme) -> Color {
        FlowSemantic.for(scheme).accentDefault.opacity(0.35)
    }
    static func wash(for scheme: ColorScheme) -> Color {
        FlowSemantic.for(scheme).accentSubtle.opacity(0.4)
    }
}

/// Shared placeholder: dashed card shown instead of any step content
/// while the step still carries the recorder placeholder (or an empty
/// title). Used by the preview list and the gutter so neither ships a
/// bare photo icon as content.
struct FlowlinePlaceholderCard: View {
    var step: Step
    var index: Int
    var compact: Bool = false
    var onAddText: () -> Void
    var onCapture: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = FlowComponent.for(scheme)
        let sem = FlowSemantic.for(scheme)
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            Text("Step \(index + 1) — needs instructions")
                .font(.system(size: compact ? 10 : 12, weight: .semibold))
                .foregroundColor(t.textSecondary)
            HStack(spacing: compact ? 6 : 8) {
                Button("Add text", action: onAddText)
                    .font(.system(size: compact ? 10 : 11, weight: .medium))
                    .foregroundColor(sem.accentDefault)
                    .buttonStyle(FlowPressStyle())
                    .help("Select step \(index + 1) to edit its text on the canvas")
                Button("Capture", action: onCapture)
                    .font(.system(size: compact ? 10 : 11))
                    .foregroundColor(t.textSecondary)
                    .buttonStyle(FlowPressStyle())
                    .help("Select step \(index + 1) to capture its visual on the canvas")
            }
        }
        .padding(compact ? 6 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surfaceSubtle.opacity(0.55))
        .cornerRadius(FlowComponent.radiusSM)
        .overlay(
            RoundedRectangle(cornerRadius: FlowComponent.radiusSM)
                .stroke(t.textTertiary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
        .help("Step \(index + 1) needs instructions — add text or capture a visual")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(index + 1) needs instructions")
    }
}

/// Plugin-backed provider: resolves per-mode quirks from
/// `TemplateRegistry` (built from `templates/<id>/manifest.json` via
/// `GuideTemplate.all`) and renders through the shared step body, so the
/// side preview and the fullscreen Preview never disagree. Unknown mode ids
/// fall back to standard rendering (same rule as `TemplateRenderer`).
public struct TemplatePreviewProvider: GuidePreviewProvider {
    public var registry: TemplateRegistry

    public init(registry: TemplateRegistry = .withDefaults()) {
        self.registry = registry
    }

    /// Plugin template for a guide mode id (`mode.rawValue`).
    public func template(for mode: FlowlineGuideMode) -> GuideTemplate? {
        registry.resolve(id: mode.rawValue)
    }

    public func body(
        for step: Step, index: Int, mode: FlowlineGuideMode,
        checked: Bool, onToggleCheck: @escaping () -> Void,
        displayTitle: String
    ) -> AnyView {
        AnyView(FlowlinePreviewStepBody(
            step: step, index: index, mode: mode,
            checked: checked, onToggleCheck: onToggleCheck,
            displayTitle: displayTitle
        ))
    }
}

/// Default mode-based rendering. Mirrors the fullscreen `previewSheet`
/// row-for-row (media, title, STEP nn, notes, per-mode quirks) so the side
/// preview and the Preview never disagree.
public struct FlowlineGuidePreviewProvider: GuidePreviewProvider {
    public init() {}
    public func body(
        for step: Step, index: Int, mode: FlowlineGuideMode,
        checked: Bool, onToggleCheck: @escaping () -> Void,
        displayTitle: String
    ) -> AnyView {
        AnyView(FlowlinePreviewStepBody(
            step: step, index: index, mode: mode,
            checked: checked, onToggleCheck: onToggleCheck,
            displayTitle: displayTitle
        ))
    }
}

/// One preview-style step block: Step N + humanized verb → target title +
/// raw actionDescription subtitle + userNotes + per-mode quirks (checklist
/// checkbox row, runbook code block, presentation larger title).
/// Placeholder steps never reach here — the list renders
/// `FlowlinePlaceholderCard` instead.
struct FlowlinePreviewStepBody: View {
    var step: Step
    var index: Int
    var mode: FlowlineGuideMode
    var checked: Bool
    var onToggleCheck: () -> Void
    /// List-level display title (verb → target with ·suffix de-dupe).
    var displayTitle: String

    @Environment(\.colorScheme) private var scheme

    /// Raw recorder string as secondary subtitle only — never the title.
    private var subtitle: String? {
        let raw = step.actionDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw != displayTitle else { return nil }
        return step.actionDescription
    }

    var body: some View {
        let t = FlowComponent.for(scheme)
        let sem = FlowSemantic.for(scheme)
        if mode == .checklist {
            Button(action: { withAnimation(FlowMotion.standardFast) { onToggleCheck() } }) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                        .font(.system(size: 16))
                        .foregroundColor(checked ? sem.accentDefault : t.textTertiary)
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Step \(index + 1)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(t.textTertiary)
                            .strikethrough(checked)
                        Text(displayTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(checked ? t.textSecondary : t.textPrimary)
                            .strikethrough(checked)
                            .multilineTextAlignment(.leading)
                        if let sub = subtitle {
                            Text(sub)
                                .font(.system(size: 12))
                                .foregroundColor(t.textSecondary)
                                .strikethrough(checked)
                                .multilineTextAlignment(.leading)
                        }
                        if let notes = step.userNotes, !notes.isEmpty {
                            Text(notes)
                                .font(.system(size: 12))
                                .foregroundColor(t.textSecondary)
                                .strikethrough(checked)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(checked ? sem.accentSubtle.opacity(0.5) : t.surfaceSubtle.opacity(0.55))
                .cornerRadius(FlowComponent.radiusMD)
                .overlay(
                    RoundedRectangle(cornerRadius: FlowComponent.radiusMD)
                        .stroke(checked ? sem.accentDefault.opacity(0.3) : t.borderSubtle, lineWidth: 1)
                )
                .opacity(checked ? 0.8 : 1)
            }
            .buttonStyle(FlowPressStyle())
            .help(checked ? "Mark step \(index + 1) not done" : "Mark step \(index + 1) done")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Step \(index + 1)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(t.textSecondary)
                Text(displayTitle)
                    .font(.system(size: mode == .presentation ? 20 : 15, weight: .semibold))
                    .foregroundColor(t.textPrimary)
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 13))
                        .foregroundColor(t.textSecondary)
                }
                if let notes = step.userNotes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 13))
                        .foregroundColor(t.textPrimary)
                }
                if mode == .runbook, let blob = step.textBlob {
                    Text(blob)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(sem.codeSurface)
                        .foregroundColor(sem.codeText)
                        .cornerRadius(FlowComponent.radiusXS)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Live "how it will look" pane: the full guide as it reads in `mode`.
/// Reads the same `session` value as the canvas, so every
/// editTitle/editDesc/selection change re-renders both panes together —
/// no persistence or undo changes. Checklist state is shared with the
/// fullscreen Preview via the `checked` binding. Selection is signaled by
/// the shared ring + scroll-follow (`FlowlineSelection`), not a hero card.
/// Each step shows its captured visual (screenshot / playing GIF) above
/// its text, exactly like the published guide. Runs of similar steps get
/// an inline "N similar — Merge / Keep all" affordance; placeholder steps
/// render `FlowlinePlaceholderCard`, never raw recorder text.
public struct GuideTextPreview<P: GuidePreviewProvider>: View {
    var session: StepSession
    var mode: FlowlineGuideMode
    var selectedID: String?
    @Binding var checked: Set<String>
    var provider: P
    var onSelect: (String) -> Void
    /// Plugin quirks caption (e.g. "code-fence" for runbook). Hidden from
    /// the default UI — Option-click the header to reveal (also NSLog'd).
    var quirksCaption: String?
    /// Injected store for resolving captured visuals. Nil → text-only
    /// (keeps the pane usable in tests without a store).
    var store: SessionStore?
    /// Merge a run of similar steps. The editor wires this to
    /// `mergeSelection` after selecting the run.
    var onMergeRun: ([String]) -> Void

    @State private var dismissedRuns: Set<String> = []
    @State private var showQuirks = false

    @Environment(\.colorScheme) private var scheme

    public init(
        session: StepSession, mode: FlowlineGuideMode, selectedID: String?,
        checked: Binding<Set<String>>, provider: P, onSelect: @escaping (String) -> Void = { _ in },
        quirksCaption: String? = nil, store: SessionStore? = nil,
        onMergeRun: @escaping ([String]) -> Void = { _ in }
    ) {
        self.session = session
        self.mode = mode
        self.selectedID = selectedID
        self._checked = checked
        self.provider = provider
        self.onSelect = onSelect
        self.quirksCaption = quirksCaption
        self.store = store
        self.onMergeRun = onMergeRun
    }

    private var doneCount: Int {
        session.steps.filter { checked.contains($0.id) }.count
    }

    private func toggleCheck(_ id: String) {
        if checked.contains(id) { checked.remove(id) } else { checked.insert(id) }
    }

    private func runKey(_ run: [Int]) -> String {
        run.map { session.steps[$0].id }.joined(separator: ",")
    }

    public var body: some View {
        let t = FlowComponent.for(scheme)
        VStack(alignment: .leading, spacing: 12) {
            header(t)
            Divider()
            if session.steps.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "text.rectangle")
                        .font(.system(size: 20))
                        .foregroundColor(t.textTertiary)
                    Text("Nothing to preview yet")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(t.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                if mode == .checklist {
                    progressRow(t)
                }
                // Single scroller: the ScrollViewReader owns the one
                // ScrollView. (Previously an outer ScrollView wrapped a
                // nested ScrollViewReader list, which cut off Step 5+ and
                // showed two scrollbars.)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            let titles = FlowlineStepText.displayTitles(for: session.steps)
                            let runEndMap = endMap(FlowlineStepText.similarRuns(in: session.steps))
                            ForEach(session.steps.indices, id: \.self) { i in
                                let s = session.steps[i]
                                stepRow(s, at: i, title: titles[s.id] ?? FlowlineStepText.readerTitle(for: s))
                                if let run = runEndMap[i], !dismissedRuns.contains(runKey(run)) {
                                    mergeRow(run: run)
                                } else if mode != .checklist, i < session.steps.count - 1 {
                                    Divider()
                                }
                            }
                        }
                        .onChange(of: selectedID) { _, id in
                            if let id {
                                withAnimation(FlowMotion.standardFast) {
                                    proxy.scrollTo(id, anchor: .center)
                                }
                            }
                        }
                        .onAppear {
                            if let id = selectedID {
                                DispatchQueue.main.async {
                                    proxy.scrollTo(id, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(t.surface)
        .cornerRadius(FlowComponent.radiusLG)
        .overlay(
            RoundedRectangle(cornerRadius: FlowComponent.radiusLG)
                .stroke(t.border, lineWidth: 1)
        )
    }

    private func endMap(_ runs: [[Int]]) -> [Int: [Int]] {
        var out: [Int: [Int]] = [:]
        for run in runs { if let last = run.last { out[last] = run } }
        return out
    }

    private func header(_ t: FlowComponent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Preview — \(mode.label)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(t.textPrimary)
                Spacer()
                FlowPill("\(session.steps.count) steps")
            }
            Text(mode.copy)
                .font(.system(size: 11))
                .foregroundColor(t.textSecondary)
            if showQuirks, let q = quirksCaption, !q.isEmpty {
                Text("Template quirks: \(q)")
                    .font(.system(size: 10))
                    .foregroundColor(t.textTertiary)
            }
            Text("WYSIWYG · updates as you edit")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(t.textTertiary)
        }
        .help("Option-click to show template quirks")
        .onTapGesture {
            guard NSEvent.modifierFlags.contains(.option) else { return }
            if let q = quirksCaption, !q.isEmpty {
                NSLog("[Flowline] template quirks for %@: %@", mode.rawValue, q)
            }
            withAnimation(FlowMotion.standardFast) { showQuirks.toggle() }
        }
    }

    private func progressRow(_ t: FlowComponent) -> some View {
        let sem = FlowSemantic.for(scheme)
        return HStack(spacing: 8) {
            ProgressView(value: Double(doneCount), total: Double(max(session.steps.count, 1)))
                .frame(maxWidth: 140)
                .tint(sem.accentDefault)
            Text(doneCount == session.steps.count ? "All done" : "\(doneCount) of \(session.steps.count) complete")
                .font(.system(size: 11))
                .foregroundColor(t.textSecondary)
            Spacer()
            if doneCount > 0 {
                Button("Reset") {
                    withAnimation(FlowMotion.standardFast) { checked.removeAll() }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(sem.accentDefault)
                .buttonStyle(FlowPressStyle())
            }
        }
        .padding(8)
        .background(t.surfaceSubtle)
        .cornerRadius(FlowComponent.radiusMD)
    }

    /// One list row: captured visual + humanized body (or the shared
    /// placeholder card). Selected rows carry the shared ring + wash so
    /// selection matches the gutter; scrolling follows `selectedID`.
    private func stepRow(_ s: Step, at i: Int, title: String) -> some View {
        let isSel = (s.id == selectedID)
        return VStack(alignment: .leading, spacing: 6) {
            if let store {
                PreviewMediaView(step: s, sessionID: session.id, store: store, maxHeight: 130)
            }
            if FlowlineStepText.isPlaceholder(s) {
                FlowlinePlaceholderCard(
                    step: s, index: i,
                    onAddText: { onSelect(s.id) },
                    onCapture: { onSelect(s.id) }
                )
            } else if mode == .checklist {
                // Tap toggles the check via the explicit checkbox (same as
                // Preview); selection still follows the canvas + gutter.
                provider.body(
                    for: s, index: i, mode: mode,
                    checked: checked.contains(s.id),
                    onToggleCheck: { toggleCheck(s.id) },
                    displayTitle: title
                )
            } else {
                Button(action: {
                    withAnimation(FlowMotion.standardFast) { onSelect(s.id) }
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
        .background(isSel ? FlowlineSelection.wash(for: scheme) : Color.clear)
        .cornerRadius(FlowComponent.radiusMD)
        .overlay(
            RoundedRectangle(cornerRadius: FlowComponent.radiusMD)
                .stroke(isSel ? FlowlineSelection.ring(for: scheme) : Color.clear, lineWidth: 1)
        )
        .id(s.id)
        .padding(.vertical, mode == .checklist ? 4 : 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(FlowlineStepText.fullText(step: s, index: i))
        .accessibilityAddTraits(isSel ? .isSelected : [])
    }

    /// Inline duplicate-run affordance: "N similar — Merge / Keep all".
    /// Merge hands the run's ids to `onMergeRun` (the editor selects the
    /// run and reuses `mergeSelection`); Keep all dismisses this run only.
    private func mergeRow(run: [Int]) -> some View {
        let t = FlowComponent.for(scheme)
        let sem = FlowSemantic.for(scheme)
        let ids = run.map { session.steps[$0].id }
        return HStack(spacing: 8) {
            Text("\(run.count) similar")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(t.textSecondary)
            Button("Merge") { onMergeRun(ids) }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(sem.accentDefault)
                .buttonStyle(FlowPressStyle())
                .help("Merge these \(run.count) steps into one")
                .accessibilityLabel("Merge these \(run.count) similar steps into one")
            Button("Keep all") { dismissedRuns.insert(runKey(run)) }
                .font(.system(size: 11))
                .foregroundColor(t.textSecondary)
                .buttonStyle(FlowPressStyle())
                .help("Keep these steps separate")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surfaceSubtle.opacity(0.6))
        .cornerRadius(FlowComponent.radiusSM)
        .padding(.vertical, 4)
    }
}
