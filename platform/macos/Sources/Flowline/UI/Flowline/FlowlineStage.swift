import SwiftUI
import FlowlineIR
import FlowlinePublishing
import FlowlineStorage

/// Stage: main preview (screenshot + amber halo + tag) and the
/// step-information panel. Port of prototype `.stage`.
/// Colors come from component/semantic tokens only; the captured visual
/// provides the color (§2). Halo fades in/out, preview crossfades per step.
public struct FlowlineStage: View {
    @Binding var session: StepSession
    var store: SessionStore
    var selectedID: String?
    var haloKind: FlowlineHaloKind?
    var autoHalo: Bool
    var onEditTitle: (String, String) -> Void
    var onEditDesc: (String, String) -> Void
    var onSelectHaloKind: (FlowlineHaloKind) -> Void
    var meta: FlowlineMetaStore

    @Environment(\.colorScheme) private var scheme
    @State private var confirmRevealStepID: String? = nil
    @State private var previewTagExpanded = false

    public init(
        session: Binding<StepSession>, store: SessionStore, selectedID: String?,
        haloKind: FlowlineHaloKind? = nil, autoHalo: Bool = true,
        onEditTitle: @escaping (String, String) -> Void,
        onEditDesc: @escaping (String, String) -> Void,
        onSelectHaloKind: @escaping (FlowlineHaloKind) -> Void = { _ in },
        meta: FlowlineMetaStore = FlowlineMetaStore()
    ) {
        self._session = session
        self.store = store
        self.selectedID = selectedID
        self.haloKind = haloKind
        self.autoHalo = autoHalo
        self.onEditTitle = onEditTitle
        self.onEditDesc = onEditDesc
        self.onSelectHaloKind = onSelectHaloKind
        self.meta = meta
    }

    /// Effective halo kind: applied per-step override → panel pending kind →
    /// auto-derived from the interaction target.
    /// NOTE: the pending `haloKind` is global editor state but this func is
    /// only consulted for the currently selected step's preview, so the
    /// live preview never leaks onto other steps. The editor clears pending
    /// on `selectedID` / `session.id` change and after `applyHalo`.
    private func effectiveHaloKind(for s: Step) -> FlowlineHaloKind? {
        if let applied = meta.haloKind(for: s, sessionID: session.id, fallback: nil) { return applied }
        if haloKind != nil { return haloKind }
        return FlowlineHaloResolver.halo(for: s).map { $0.kind }
    }

    private var selectedIndex: Int? {
        guard let id = selectedID else { return session.steps.first.map { _ in 0 } }
        return session.steps.firstIndex(where: { $0.id == id })
    }
    /// Reader-copy H1 for a step: humanized resolver output
    /// (verb -> target plus app context). Never the raw resolver string, so
    /// template syntax such as {{base}} and raw role tokens (scrollarea,
    /// drkmtr) can never appear in the H1. Raw strings live in Details >
    /// Technical disclosure; the raw actionDescription stays editable as the
    /// subtitle below the H1.
    private func readerTitle(for s: Step) -> String {
        let verb = FlowlineHaloResolver.verb(for: s)
        var target = FlowlineHaloResolver.target(for: s)
        let app = s.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        target = target.replacingOccurrences(of: "{{base}}", with: app.isEmpty ? "target" : app)
        while let r = target.range(of: #"\{\{[^}]*\}\}"#, options: .regularExpression) {
            target = target.replacingCharacters(in: r, with: app.isEmpty ? "target" : app)
        }
        target = target.trimmingCharacters(in: .whitespacesAndNewlines)
        if target.isEmpty { target = app.isEmpty ? "target" : app }
        if !app.isEmpty, !target.localizedCaseInsensitiveContains(app) {
            return "\(verb) \u{201C}\(target)\u{201D} in \(app)"
        }
        return "\(verb) \u{201C}\(target)\u{201D}"
    }

    /// Tooltip/help copy: truncated reader title, never raw IDs
    /// (step/session ids, trigger keys) and never template syntax.
    private func tooltipText(for s: Step) -> String {
        let r = readerTitle(for: s)
        guard r.count > 140 else { return r }
        return String(r.prefix(140)) + "\u{2026}"
    }

    /// Heuristic PII check for the reveal confirm. Redacted media itself
    /// counts as sensitive, so revealing a redacted step always confirms.
    private func containsPII(step s: Step) -> Bool {
        if s.isRedacted == true { return true }
        guard let b = s.textBlob?.lowercased(), !b.isEmpty else { return false }
        if b.contains("@") { return true }
        if b.range(of: #"\d{4,}"#, options: .regularExpression) != nil { return true }
        for kw in ["ssn", "password", "secret", "token", "api_key", "apikey", "credit", "card number", "dob", "address", "phone"] {
            if b.contains(kw) { return true }
        }
        return false
    }

    /// Scope count for the redaction toggle: redacted media + PII text blob.
    private func redactedFieldCount(step s: Step) -> Int {
        var n = 0
        if s.isRedacted == true { n += 1 }
        else if s.assets.screenshotOriginal != nil { n += 1 }
        if let b = s.textBlob, !b.isEmpty, containsPII(step: s) { n += 1 }
        return max(n, 1)
    }
    private var step: Step? {
        guard let i = selectedIndex, session.steps.indices.contains(i) else { return nil }
        return session.steps[i]
    }

    public var body: some View {
        VStack(spacing: 12) {
            preview
            stepInfo
        }
        .padding(.horizontal, 16)
        .animation(FlowMotion.standard, value: selectedID)
    }

    // MARK: - Preview

    private var preview: some View {
        let t = FlowComponent.for(scheme)
        let sem = FlowSemantic.for(scheme)
        let treatment = meta.style(sessionID: session.id).media
        let radius: CGFloat = treatment == .framed ? FlowComponent.radiusSM : (treatment == .full ? FlowComponent.radiusXS : FlowComponent.radiusLG)
        return ZStack {
            Checkerboard()
                .cornerRadius(radius)
            if let url = previewURL, let ns = NSImage(contentsOf: url) {
                Image(nsImage: ns)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(radius)
                    .padding(treatment == .framed ? 10 : 0)
                    .id(selectedID) // crossfade per step
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundColor(t.textTertiary)
                    Text("No captured visual for this step")
                        .font(.system(size: 12))
                        .foregroundColor(t.textSecondary)
                }
                .transition(.opacity)
            }
            // Halo overlay — amber = user interaction (§12–13), fades in/out.
            // Applied per-step overrides stay visible even when Auto Halo is
            // off; pending panel picks also preview for the selected step.
            if let s = step, let h = FlowlineHaloResolver.halo(for: s),
               let kind = effectiveHaloKind(for: s),
               (autoHalo || meta.appliedHaloKind(sessionID: session.id, stepID: s.id) != nil || haloKind != nil) {
                GeometryReader { geo in
                    FlowlineHaloView(
                        halo: h, overrideKind: kind, stepID: s.id, hotkeyLabel: s.hotkeyCombo,
                        elementTitle: s.elementTitle,
                        keyStyle: meta.style(sessionID: session.id).keycapStyle,
                        mouseStyle: meta.style(sessionID: session.id).mouseStyle
                    )
                        .position(
                            x: CGFloat(h.x + h.w / 2) * geo.size.width,
                            y: CGFloat(h.y + h.h / 2) * geo.size.height
                        )
                        .frame(width: CGFloat(h.w) * geo.size.width, height: CGFloat(h.h) * geo.size.height)
                }
                .padding(treatment == .framed ? 10 : 0)
                .allowsHitTesting(false)
                .clipped()
                .zIndex(1)
                .transition(.opacity)
            }
            // Preview tag (verb → target) — reader copy, 2-line cap with
            // click-to-expand; help carries the truncated reader title only,
            // never raw IDs or template syntax.
            if let s = step {
                VStack {
                    Spacer()
                    HStack {
                        Button(action: { withAnimation(FlowMotion.standardFast) { previewTagExpanded.toggle() } }) {
                            HStack(spacing: 8) {
                                Image(systemName: "cursorarrow")
                                    .font(.system(size: 11))
                                Text(readerTitle(for: s))
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(previewTagExpanded ? nil : 2)
                                    .truncationMode(.tail)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(t.surface)
                            .cornerRadius(FlowComponent.radiusSM)
                            .overlay(RoundedRectangle(cornerRadius: FlowComponent.radiusSM).stroke(t.border, lineWidth: 1))
                            .foregroundColor(t.textPrimary)
                        }
                        .buttonStyle(.plain)
                        .help(tooltipText(for: s))
                        .accessibilityLabel(readerTitle(for: s))
                        Spacer()
                    }
                    .padding(12)
                }
                .zIndex(2)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minHeight: 220, maxHeight: 420)
        .overlay(RoundedRectangle(cornerRadius: radius).stroke(t.border, lineWidth: 1))
        .shadow(color: sem.shadowSubtle, radius: 8, y: 2)
    }

    private var previewURL: URL? {
        guard let s = step else { return nil }
        let wantsGIF = (s.preferredMedia?.lowercased() == "gif") || (s.preferredMedia == nil && s.assets.gif != nil)
        if wantsGIF, let g = s.assets.gif { return store.resolveMediaPath(sessionID: session.id, relativePath: g) }
        if let p = s.assets.screenshot { return store.resolveMediaPath(sessionID: session.id, relativePath: p) }
        return nil
    }

    // MARK: - Step info

    private var stepInfo: some View {
        let t = FlowComponent.for(scheme)
        return Group {
            if let s = step, let idx = selectedIndex {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("Step \(idx + 1) of \(session.steps.count)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(t.textSecondary)
                            if FlowlineHaloResolver.halo(for: s) != nil {
                                autoDetectPill(step: s)
                            }
                        }
                        // H1 = reader copy from the humanized resolver.
                        // Raw resolver output never renders here.
                        Text(readerTitle(for: s))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(t.textPrimary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                        // Editable subtitle = raw actionDescription.
                        TextField("Step title", text: Binding(
                            get: { session.steps[idx].actionDescription },
                            set: { onEditTitle(s.id, $0) }
                        ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(t.textSecondary)
                        TextEditor(text: Binding(
                            get: { session.steps[idx].userNotes ?? "" },
                            set: { onEditDesc(s.id, $0) }
                        ))
                        .font(.system(size: 12))
                        .frame(height: 56)
                        .padding(8)
                        .background(t.surfaceSubtle)
                        .cornerRadius(FlowComponent.radiusSM)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        if let combo = s.hotkeyCombo {
                            HStack(alignment: .top, spacing: 8) {
                                Text("HOTKEY")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(t.textTertiary)
                                    .frame(width: 64, alignment: .leading)
                                    .padding(.top, 6)
                                KeyComboCaps(combo, style: meta.style(sessionID: session.id).keycapStyle)
                            }
                        } else if s.action == .keyPress {
                            // Shortcut-less presses (Esc, arrows) carry the W3C
                            // key name in `elementTitle` — one cap, never the
                            // action sentence split into word-caps.
                            let toks = KeyComboTokens.tokensForStep(combo: nil, elementTitle: s.elementTitle)
                            if !toks.isEmpty {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("KEY")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(t.textTertiary)
                                        .frame(width: 64, alignment: .leading)
                                        .padding(.top, 6)
                                    KeyComboCaps(tokens: toks, style: meta.style(sessionID: session.id).keycapStyle)
                                }
                            }
                        } else if s.action == .typing,
                                  let typed = KeyComboTokens.typedTokens(text: s.textBlob ?? "") {
                            // Short typed input (`^`, `~`) gets per-char caps
                            // so typed characters never vanish from the visual.
                            HStack(alignment: .top, spacing: 8) {
                                Text("TYPED")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(t.textTertiary)
                                    .frame(width: 64, alignment: .leading)
                                    .padding(.top, 6)
                                KeyComboCaps(tokens: typed, style: meta.style(sessionID: session.id).keycapStyle)
                            }
                        }
                        if let blob = s.textBlob, !blob.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("CAPTURED TEXT")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(t.textTertiary)
                                ExpandableText(text: blob)
                            }
                        }
                        redactionRow(step: s, index: idx)
                        redactionPlaceholder(step: s)
                        annotationsRow(step: s)
                        commentsRow(step: s)
                        annotateControl(step: s)
                        // Action + Source + raw resolver output live here,
                        // collapsed by default. Screenshot + reader sentence
                        // above stay the primary view.
                        DisclosureGroup("Details") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Technical disclosure")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(t.textTertiary)
                                infoRow("Action", "\(FlowlineHaloResolver.verb(for: s)) → \(FlowlineHaloResolver.target(for: s))", bold: true)
                                infoRow("Source", "\(s.appName)\(s.windowTitle.isEmpty ? "" : " → \(s.windowTitle)")")
                                if let role = s.elementRole, !role.isEmpty {
                                    infoRow("Element", role)
                                }
                                if let title = s.elementTitle, !title.isEmpty {
                                    ExpandableText(text: title, label: "Target")
                                }
                                if !s.actionDescription.isEmpty, s.actionDescription != readerTitle(for: s) {
                                    ExpandableText(text: s.actionDescription, label: "Raw")
                                }
                            }
                            .padding(.top, 4)
                        }
                        .font(.system(size: 12))
                        .foregroundColor(t.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .background(t.surface)
                .cornerRadius(FlowComponent.radiusLG)
                .overlay(RoundedRectangle(cornerRadius: FlowComponent.radiusLG).stroke(t.border, lineWidth: 1))
                .id(selectedID)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                Text("Select a step to inspect it")
                    .foregroundColor(t.textSecondary)
                    .padding()
            }
        }
    }

    /// Auto-detect pill (wand icon): shows the derived kind while auto,
    /// "Manual" once a per-step override is applied. Click toggles the
    /// Manual override for this step (set/clear the applied kind).
    @ViewBuilder
    private func autoDetectPill(step s: Step) -> some View {
        let sem = FlowSemantic.for(scheme)
        let kind = meta.appliedHaloKind(sessionID: session.id, stepID: s.id)
            ?? FlowlineHaloResolver.kind(for: s)
        let isManual = meta.appliedHaloKind(sessionID: session.id, stepID: s.id) != nil
        Button(action: {
            withAnimation(FlowMotion.standardFast) {
                meta.updateStep(sessionID: session.id, stepID: s.id) { m in
                    if m.haloKind != nil { m.haloKind = nil }
                    else { m.haloKind = FlowlineHaloResolver.kind(for: s) }
                }
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: isManual ? "pencil.circle" : "wand.and.stars")
                    .font(.system(size: 10))
                Text("\(isManual ? "Manual" : "Auto-detected") · \(kind.label)")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 2.5)
            .background(sem.haloFill)
            .foregroundColor(sem.haloIcon)
            .clipShape(Capsule())
        }
        .buttonStyle(FlowPressStyle())
        .help(isManual ? "Manual override. Click to return to Auto-detect." : "Auto-detected from the interaction. Click for Manual override.")
        .accessibilityLabel(isManual ? "Manual override \(kind.label). Activate to return to auto-detect." : "Auto-detected \(kind.label). Activate for manual override.")
    }

    private func infoRow(_ k: String, _ v: String, bold: Bool = false) -> some View {
        let t = FlowComponent.for(scheme)
        return HStack(alignment: .top, spacing: 8) {
            Text(k.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(t.textTertiary)
                .frame(width: 64, alignment: .leading)
            Text(v)
                .font(.system(size: 12, weight: bold ? .semibold : .regular))
                .foregroundColor(t.textPrimary)
        }
    }

    @ViewBuilder
    private func annotationsRow(step s: Step) -> some View {
        let t = FlowComponent.for(scheme)
        let sem = FlowSemantic.for(scheme)
        let annos = meta.meta(sessionID: session.id, stepID: s.id).annotations
        VStack(alignment: .leading, spacing: 8) {
            if !annos.isEmpty {
                Text("ANNOTATIONS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(t.textTertiary)
                FlowLayout(spacing: 8) {
                    ForEach(annos, id: \.self) { a in
                        Button(action: {
                            withAnimation(FlowMotion.standardFast) {
                                meta.updateStep(sessionID: session.id, stepID: s.id) { $0.annotations.removeAll(where: { $0 == a }) }
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "tag").font(.system(size: 9))
                                Text(a).font(.system(size: 11))
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                            }
                            .foregroundColor(sem.accentDefault)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(sem.accentSubtle)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(FlowPressStyle())
                        .help("Remove annotation")
                    }
                }
            }
        }
    }

    /// Single +Annotate split-button: click adds a callout (default),
    /// dropdown offers Warning / Comment. Replaces the old separate
    /// +Add and +Comment buttons; existing chips/comments above stay.
    @ViewBuilder
    private func annotateControl(step s: Step) -> some View {
        let t = FlowComponent.for(scheme)
        HStack(spacing: 0) {
            Button(action: {
                withAnimation(FlowMotion.standardFast) {
                    meta.updateStep(sessionID: session.id, stepID: s.id) {
                        $0.annotations.append("Callout: \(FlowlineHaloResolver.target(for: s))")
                    }
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 9, weight: .semibold))
                    Text("Annotate").font(.system(size: 11))
                }
                .foregroundColor(t.textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(t.surfaceSubtle)
                .clipShape(Capsule())
            }
            .buttonStyle(FlowPressStyle())
            .help("Add annotation. Click adds a callout; open the menu for Warning or Comment.")
            Menu {
                Button("Warning") {
                    withAnimation(FlowMotion.standardFast) {
                        meta.updateStep(sessionID: session.id, stepID: s.id) {
                            $0.annotations.append("Warning: \(FlowlineHaloResolver.target(for: s))")
                        }
                    }
                }
                Button("Comment") {
                    withAnimation(FlowMotion.standard) {
                        meta.updateStep(sessionID: session.id, stepID: s.id) {
                            $0.comments.append(FlowStepComment(who: "You", text: "Reviewed — ready to publish."))
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(t.textSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(t.surfaceSubtle)
                    .clipShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .help("More annotation types: Warning or Comment.")
        }
    }

    @ViewBuilder
    private func commentsRow(step s: Step) -> some View {
        let t = FlowComponent.for(scheme)
        let comments = meta.meta(sessionID: session.id, stepID: s.id).comments
        if !comments.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(comments.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(FlowSemantic.for(scheme).accentSubtle)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Text(comments[i].who.prefix(1))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(FlowSemantic.for(scheme).accentDefault)
                            )
                        Text("**\(comments[i].who)** — \(comments[i].text)")
                            .font(.system(size: 12))
                            .foregroundColor(t.textPrimary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(FlowMotion.standard, value: comments.count)
        }
    }

    /// Neutral redaction toggle (eye.slash): "Hidden · Show (N fields)".
    /// Scope count included; revealing a step that may hold PII asks for
    /// confirmation first. Non-destructive toggle logic is unchanged.
    @ViewBuilder
    private func redactionRow(step: Step, index: Int) -> some View {
        let t = FlowComponent.for(scheme)
        if step.isRedacted == true {
            let n = redactedFieldCount(step: step)
            let label = n == 1 ? "Hidden · Show (1 field)" : "Hidden · Show (\(n) fields)"
            Button(action: {
                if containsPII(step: step) { confirmRevealStepID = step.id }
                else { withAnimation(FlowMotion.standardFast) { toggleRedaction(at: index) } }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 10))
                    Text(label)
                        .font(.system(size: 11))
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                .foregroundColor(t.textSecondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(t.surfaceSubtle)
                .clipShape(Capsule())
            }
            .buttonStyle(FlowPressStyle())
            .help("Sensitive content hidden (\(n) \(n == 1 ? "field" : "fields")). Review before revealing.")
            .confirmationDialog(
                "Reveal hidden content?",
                isPresented: Binding(
                    get: { confirmRevealStepID == step.id },
                    set: { if !$0 { confirmRevealStepID = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Reveal") {
                    if let i = session.steps.firstIndex(where: { $0.id == step.id }) {
                        withAnimation(FlowMotion.standardFast) { toggleRedaction(at: i) }
                    }
                    confirmRevealStepID = nil
                }
                Button("Cancel", role: .cancel) { confirmRevealStepID = nil }
            } message: {
                Text("This step may contain sensitive info. Only reveal if it is safe to show.")
            }
        } else if step.assets.screenshotOriginal != nil {
            Button(action: { withAnimation(FlowMotion.standardFast) { toggleRedaction(at: index) } }) {
                HStack(spacing: 6) {
                    Image(systemName: "eye")
                        .font(.system(size: 10))
                    Text("Visible · Re-apply")
                        .font(.system(size: 11))
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                .foregroundColor(t.textSecondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(t.surfaceSubtle)
                .clipShape(Capsule())
            }
            .buttonStyle(FlowPressStyle())
            .help("Original visible. Click to re-apply hiding.")
        }
    }

    /// Hatched redaction placeholder (never a blank white box): striped fill
    /// + "sensitive hidden — drag to adjust" + handle affordance. Hidden
    /// entirely when the step has nothing redactable.
    @ViewBuilder
    private func redactionPlaceholder(step s: Step) -> some View {
        if s.isRedacted != true, s.assets.screenshotOriginal == nil {
            EmptyView()
        } else if s.isRedacted == true {
            let t = FlowComponent.for(scheme)
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: FlowComponent.radiusSM)
                    .fill(t.surfaceSubtle)
                HatchLines()
                    .stroke(t.textTertiary.opacity(0.45), lineWidth: 1)
                    .clipShape(RoundedRectangle(cornerRadius: FlowComponent.radiusSM))
                HStack(spacing: 6) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 10))
                    Text("sensitive hidden — drag to adjust")
                        .font(.system(size: 11))
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                .foregroundColor(t.textSecondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                RoundedRectangle(cornerRadius: 4)
                    .fill(t.surface)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                            .font(.system(size: 9))
                            .foregroundColor(t.textSecondary)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(t.border, lineWidth: 1))
                    .padding(6)
            }
            .frame(height: 64)
            .overlay(RoundedRectangle(cornerRadius: FlowComponent.radiusSM).stroke(t.border, lineWidth: 1))
            .help("Sensitive content hidden. Drag the handle to adjust the hidden area.")
            .accessibilityLabel("Sensitive content hidden. Drag the handle to adjust.")
        }
    }

    private func toggleRedaction(at index: Int) {
        var s = session.steps[index]
        guard let original = s.assets.screenshotOriginal, let current = s.assets.screenshot else { return }
        s.assets.screenshotOriginal = current
        s.assets.screenshot = original
        s.isRedacted = !(s.isRedacted ?? false)
        session.steps[index] = s
        try? store.saveSession(session)
    }
}

// MARK: - Halo overlay (amber = user interaction, §12–13)

struct FlowlineHaloView: View {
    var halo: FlowlineHalo
    var overrideKind: FlowlineHaloKind? = nil
    var stepID: String? = nil
    var hotkeyLabel: String? = nil
    var elementTitle: String? = nil
    var keyStyle: KeycapStyle = .mac3D
    var mouseStyle: MouseStyle = .mac3D
    @Environment(\.colorScheme) private var scheme

    /// Tooltip copy for the overlay: truncated label, never raw IDs
    /// (step/session ids, trigger keys) and never template syntax.
    /// Rendered labels cap at 2 lines with tail ellipsis; full text lives
    /// in Details > Technical disclosure (click-to-expand there).
    private func tooltipForHalo() -> String {
        var s = halo.label.replacingOccurrences(of: "{{base}}", with: "target")
        while let r = s.range(of: #"\{\{[^}]*\}\}"#, options: .regularExpression) {
            s = s.replacingCharacters(in: r, with: "target")
        }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > 140 else { return t }
        return String(t.prefix(140)) + "…"
    }

    var body: some View {
        let sem = FlowSemantic.for(scheme)
        let t = FlowComponent.for(scheme)
        let kind = overrideKind ?? halo.kind
        ZStack {
            switch kind {
            case .click:
                MouseClickHalo(style: mouseStyle)
            case .cursor:
                MouseCursorHalo(style: mouseStyle)
            case .spotlight:
                RoundedRectangle(cornerRadius: FlowComponent.radiusSM)
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundColor(sem.haloBorder)
                    .background(RoundedRectangle(cornerRadius: FlowComponent.radiusSM).fill(sem.haloFill))
                    .shadow(color: mouseStyle == .flat ? .clear : sem.shadowSubtle, radius: mouseStyle == .flat ? 0 : 4, y: 2)
            case .rect:
                RoundedRectangle(cornerRadius: FlowComponent.radiusSM)
                    .stroke(sem.haloBorder, lineWidth: 2)
                    .background(RoundedRectangle(cornerRadius: FlowComponent.radiusSM).fill(sem.haloFill))
                    .shadow(color: mouseStyle == .flat ? .clear : sem.shadowSubtle, radius: mouseStyle == .flat ? 0 : 4, y: 2)
            case .callout:
                RoundedRectangle(cornerRadius: FlowComponent.radiusSM)
                    .stroke(sem.haloBorder, lineWidth: 2)
                    .background(RoundedRectangle(cornerRadius: FlowComponent.radiusSM).fill(sem.haloFill))
                    .overlay(
                        Text(halo.shortLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(sem.haloIcon)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .padding(8)
                    )
                    .clipped()
            case .key:
                // Selectable keycap row — combo first, else the bare pressed
                // key. Never the action sentence as word-caps.
                let keyToks = KeyComboTokens.tokensForStep(combo: hotkeyLabel, elementTitle: elementTitle)
                Group {
                    if keyToks.isEmpty {
                        Text(halo.shortLabel)
                            .font(.system(size: 11))
                            .foregroundColor(sem.haloIcon)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .padding(.horizontal, 8)
                    } else {
                        KeyComboCaps(tokens: keyToks, style: keyStyle)
                            .padding(2)
                    }
                }
            case .arrow:
                MouseDragHalo(style: mouseStyle)
            }
        }
        // TODO(magnifier): offset the lens 24px down-right with a connector
        // line back to the target point. Non-trivial (needs lens + line
        // geometry in preview space), so left as a task; the amber overlay
        // legend above stays the source of truth for mark meaning.
        .help(tooltipForHalo())
        .modifier(HaloAppear(trigger: stepID.map { "\($0)-\(kind.rawValue)-\(keyStyle.rawValue)-\(mouseStyle.rawValue)" } ?? halo.triggerKey))
    }
}

struct Checkerboard: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        // Captured-visual well: subtle checker from surface/subtle tokens.
        let t = FlowComponent.for(scheme)
        t.surfaceSubtle
    }
}

/// 2-line truncated text with click-to-expand. Tooltips/labels cap at 2
/// lines with tail ellipsis; the toggle reveals the full string in place.
/// Never fed raw IDs — callers pass human-readable copy only.
private struct ExpandableText: View {
    var text: String
    var label: String? = nil
    @Environment(\.colorScheme) private var scheme
    @State private var expanded = false

    var body: some View {
        let t = FlowComponent.for(scheme)
        let sem = FlowSemantic.for(scheme)
        VStack(alignment: .leading, spacing: 4) {
            if let label {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(t.textTertiary)
            }
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(sem.codeSurface)
                .foregroundColor(sem.codeText)
                .cornerRadius(FlowComponent.radiusXS)
                .lineLimit(expanded ? nil : 2)
                .truncationMode(.tail)
            if text.count > 80 {
                Button(expanded ? "Less" : "More") {
                    withAnimation(FlowMotion.standardFast) { expanded.toggle() }
                }
                .font(.system(size: 11))
                .foregroundColor(sem.accentDefault)
                .buttonStyle(FlowPressStyle())
            }
        }
    }
}

/// Diagonal hatch fill for the redaction placeholder (never blank white).
private struct HatchLines: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let step: CGFloat = 8
        var x: CGFloat = -rect.height
        while x < rect.maxX + rect.height {
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += step
        }
        return p
    }
}
