import SwiftUI
import FlowlineIR
import FlowlineAIGateway

/// Collapsible right AI panel: provider status, thread, 3 quick actions,
/// auto scope pill, compose box. Port of prototype `<aside class="ai-sidebar">`.
/// Streams through the injected `StepSynthesisService`-shaped closure so the
/// surface never names a singleton.
public struct FlowlineAISidebar: View {
    var session: StepSession
    var gateway: GatewaySettings
    var collapsed: Bool
    var accent: FlowAccentChoice = .blue
    /// Currently selected step — used when the prompt scopes with `@step`.
    var scopeStep: Step?
    var onToggle: () -> Void
    /// Deep-link to the AI gateway settings pane. Optional so existing
    /// call sites keep compiling; the setup card / Connect button no-op
    /// gracefully when unset.
    var onOpenSettings: () -> Void = {}
    var onSynthesized: (String) -> Void
    var synthesize: (
        _ session: StepSession,
        _ settings: GatewaySettings,
        _ style: DocumentationStyle,
        _ instructions: String?
    ) -> AsyncThrowingStream<String, Error>

    @State private var style: DocumentationStyle = .sopGuide
    @State private var instructions: String = ""
    @State private var isWorking = false
    @State private var errorCard: AIErrorCard?
    @State private var pendingVia: String?
    @State private var pendingPrompt: String?
    @State private var lastPrompt: (text: String, via: String?)?
    @State private var mentionHighlight = 0
    @State private var mentionHidden = false
    @FocusState private var composeFocused: Bool
    @State private var thread: [AIMessage] = [
        AIMessage(role: .assistant, text: "I can tidy, explain, or turn this guide into checklist or script. Just ask below.")
    ]

    @Environment(\.colorScheme) private var scheme

    struct AIMessage: Identifiable {
        enum Role { case user, assistant }
        var id = UUID()
        var role: Role
        var text: String
        /// Quick-action that produced this prompt (shown as a small caption).
        var via: String?
    }

    /// Actionable error card — setup errors deep-link to Settings instead of
    /// dumping a raw `LocalizedError` string.
    struct AIErrorCard {
        var message: String
        /// Missing-key / not-configured: show the setup card, no Retry.
        var isSetup: Bool
    }

    /// Three quick actions — chip tap fills the compose box (editable),
    /// it does not fire immediately. Convert==Automation and
    /// Cleanup==Rewrite==Structure are merged; the rest is natural language.
    static let quick: [(String, String)] = [
        ("Tidy up", "Tidy up this guide: remove filler steps, tighten titles, and rewrite in a clearer voice."),
        ("Explain", "Explain what this guide does and why each step matters."),
        ("Automate", "Draft Playwright/Bash automation for these steps."),
    ]

    /// Overflow for the remaining action that didn't fit the 3-chip row.
    static let moreActions: [(String, String)] = [
        ("Suggest callouts", "Suggest Halo callouts and warnings for risky steps."),
    ]

    public init(
        session: StepSession, gateway: GatewaySettings, collapsed: Bool,
        accent: FlowAccentChoice = .blue, scopeStep: Step? = nil,
        onToggle: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void = {},
        onSynthesized: @escaping (String) -> Void,
        synthesize: @escaping (StepSession, GatewaySettings, DocumentationStyle, String?) -> AsyncThrowingStream<String, Error>
    ) {
        self.session = session
        self.gateway = gateway
        self.collapsed = collapsed
        self.accent = accent
        self.scopeStep = scopeStep
        self.onToggle = onToggle
        self.onOpenSettings = onOpenSettings
        self.onSynthesized = onSynthesized
        self.synthesize = synthesize
    }

    /// Whether the panel may send: cloud needs a non-empty API key, local
    /// models (`ollama` / `lmStudio`) need no key.
    private var canRun: Bool { gateway.canRun }

    /// Derived header status — never a hardcoded "Connected".
    private var statusLabel: String {
        if isWorking { return "Working" }
        return canRun ? "Ready" : "Needs setup"
    }

    private var statusColor: Color {
        if isWorking { return accent.color(for: scheme) }
        return canRun ? FlowSemantic.for(scheme).successFg : FlowSemantic.for(scheme).warningFg
    }

    /// Short style names so the Output picker fits the narrow panel.
    private func shortStyleName(_ s: DocumentationStyle) -> String {
        switch s {
        case .sopGuide: return "How-to guide"
        case .bugReport: return "Bug report"
        case .automationScript: return "Automation script"
        case .executiveSummary: return "Summary"
        }
    }

    public var body: some View {
        Group {
            if collapsed {
                VStack(spacing: 10) {
                    Button(action: onToggle) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14))
                            .foregroundColor(FlowSemantic.for(scheme).accentDefault)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(FlowPressStyle())
                    .help("Open AI sidebar")
                    Button(action: onToggle) {
                        Image(systemName: "at")
                            .font(.system(size: 13))
                            .foregroundColor(FlowComponent.for(scheme).textSecondary)
                    }
                    .buttonStyle(FlowPressStyle())
                    .help("Context references")
                    Spacer()
                }
                .padding(.vertical, 12)
                .frame(width: FlowComponent.aiRailWidth)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .foregroundColor(FlowSemantic.for(scheme).accentDefault)
                        Text("Guide AI")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        HStack(spacing: 4) {
                            Circle().fill(statusColor).frame(width: 7, height: 7)
                                .opacity(isWorking ? 0.35 : 1)
                                .animation(isWorking ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .default, value: isWorking)
                            Text(statusLabel)
                                .font(.system(size: 10))
                                .foregroundColor(FlowComponent.for(scheme).textSecondary)
                        }
                        .help(canRun ? "AI provider is configured" : "Add an API key in Settings, or switch to a local model")
                        Button(action: onToggle) {
                            Image(systemName: "sidebar.trailing")
                                .foregroundColor(FlowComponent.for(scheme).textSecondary)
                        }
                        .buttonStyle(FlowPressStyle())
                        .help("Collapse")
                    }

                    // Provider status — a single Settings affordance. Cloud vs
                    // local readiness only; provider name, endpoint, model and
                    // temperature live in Settings.
                    Button(action: onOpenSettings) {
                        HStack(spacing: 6) {
                            Image(systemName: gateway.isLocal ? "desktopcomputer" : "cloud")
                                .font(.system(size: 11))
                                .foregroundColor(FlowComponent.for(scheme).textSecondary)
                            Text(canRun ? (gateway.isLocal ? "Local · Ready" : "Cloud · Ready") : "AI · Not set up")
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text("Settings")
                                .font(.system(size: 11))
                                .foregroundColor(FlowSemantic.for(scheme).accentDefault)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(FlowComponent.for(scheme).textTertiary)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(FlowComponent.for(scheme).surfaceSubtle)
                        .cornerRadius(FlowComponent.radiusSM)
                    }
                    .buttonStyle(FlowPressStyle())
                    .help("Open AI settings")

                    // Output style — full-width row so names never truncate.
                    HStack(spacing: 6) {
                        Text("Output:")
                            .font(.system(size: 11))
                            .foregroundColor(FlowComponent.for(scheme).textSecondary)
                        Picker("Output", selection: $style) {
                            ForEach(DocumentationStyle.allCases, id: \.self) { s in
                                Text(shortStyleName(s)).tag(s)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(FlowComponent.for(scheme).surfaceSubtle)
                    .cornerRadius(FlowComponent.radiusSM)

                    // Thread — AI panel stays neutral (§15, §19); only a tiny
                    // violet marker indicates AI-generated content (§29.10).
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(thread) { m in
                                if m.role == .assistant {
                                    HStack(alignment: .top, spacing: 6) {
                                        Circle()
                                            .fill(FlowSemantic.for(scheme).aiFg)
                                            .frame(width: 6, height: 6)
                                            .padding(.top, 5)
                                        Text(m.text)
                                            .font(.system(size: 12))
                                            .padding(8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(FlowComponent.for(scheme).surfaceSubtle)
                                            .cornerRadius(FlowComponent.radiusSM)
                                    }
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                                } else {
                                    // Normal user bubble — no `[Label]` pill prefix;
                                    // the quick action shows as a small caption.
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(m.text)
                                            .font(.system(size: 12))
                                            .padding(8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(FlowSemantic.for(scheme).accentSubtle)
                                            .cornerRadius(FlowComponent.radiusSM)
                                        if let via = m.via {
                                            Text("via \(via)")
                                                .font(.system(size: 10))
                                                .foregroundColor(FlowComponent.for(scheme).textTertiary)
                                        }
                                    }
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                                }
                            }
                            if isWorking {
                                ThinkingDots()
                                    .transition(.opacity)
                            }
                            if let card = errorCard {
                                aiErrorCard(card)
                            }
                        }
                        .animation(FlowMotion.standard, value: thread.count)
                        .animation(FlowMotion.standardFast, value: isWorking)
                    }

                    if canRun {
                        // Quick chips — tap fills the compose box for editing,
                        // it does not fire immediately.
                        FlowLayout(spacing: 6) {
                            ForEach(Self.quick, id: \.0) { name, prompt in
                                Button(name) { stagePrompt(prompt: prompt, via: name) }
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 8).padding(.vertical, 5)
                                    .background(FlowComponent.for(scheme).surfaceSubtle)
                                    .clipShape(Capsule())
                                    .buttonStyle(FlowPressStyle())
                            }
                            Menu {
                                ForEach(Self.moreActions, id: \.0) { name, prompt in
                                    Button(name) { stagePrompt(prompt: prompt, via: name) }
                                }
                            } label: {
                                Text("···")
                                    .font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 8).padding(.vertical, 5)
                                    .background(FlowComponent.for(scheme).surfaceSubtle)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(FlowPressStyle())
                            .help("More actions")
                        }

                        // Scope is automatic: an explicit @-mention wins,
                        // otherwise the selected step scopes the prompt.
                        // @ autocomplete lives in the compose box only.
                        HStack(spacing: 6) {
                            Image(systemName: scopeStep != nil ? "scope" : "book")
                                .font(.system(size: 10))
                                .foregroundColor(FlowSemantic.for(scheme).accentDefault)
                            if let step = scopeStep {
                                Text("Scoped to Step \(step.index)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(FlowComponent.for(scheme).textPrimary)
                                Button(action: { useWholeGuide() }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(FlowComponent.for(scheme).textTertiary)
                                }
                                .buttonStyle(FlowPressStyle())
                                .help("Ask about the whole guide instead")
                            } else {
                                Text("Whole guide")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(FlowComponent.for(scheme).textPrimary)
                            }
                            Spacer(minLength: 4)
                            Text(session.steps.isEmpty ? "No steps yet" : "\(session.steps.count) steps")
                                .font(.system(size: 10))
                                .foregroundColor(FlowComponent.for(scheme).textTertiary)
                                .lineLimit(1)
                        }
                    } else {
                        // Setup card — replaces chips + scope until AI can run.
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Connect AI to ask about this guide")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(FlowComponent.for(scheme).textPrimary)
                            Text("Add an API key for cloud, or pick a local model — local models need no key.")
                                .font(.system(size: 11))
                                .foregroundColor(FlowComponent.for(scheme).textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Open Settings", action: onOpenSettings)
                                .font(.system(size: 11, weight: .medium))
                                .buttonStyle(FlowPressStyle())
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(FlowComponent.for(scheme).surfaceSubtle)
                        .cornerRadius(FlowComponent.radiusSM)
                    }
                    VStack(spacing: 6) {
                        if showMentionList {
                            mentionPopup
                        }
                        HStack(spacing: 6) {
                            TextField(
                                canRun ? "Ask about this guide… (@ to reference steps)" : "Connect AI to ask about this guide",
                                text: $instructions
                            )
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(.system(size: 12))
                                .focused($composeFocused)
                                .disabled(!canRun)
                                .onChange(of: instructions) { _, _ in
                                    mentionHighlight = 0
                                    mentionHidden = false
                                    // Manual edits detach the staged quick action.
                                    if instructions != pendingPrompt {
                                        pendingVia = nil
                                        pendingPrompt = nil
                                    }
                                }
                                .onSubmit {
                                    if showMentionList, mentionCandidates.indices.contains(mentionHighlight) {
                                        applyMention(mentionCandidates[mentionHighlight])
                                    } else {
                                        run(prompt: instructions, label: pendingVia)
                                    }
                                }
                                .onKeyPress(.upArrow) {
                                    guard showMentionList, !mentionCandidates.isEmpty else { return .ignored }
                                    mentionHighlight = (mentionHighlight - 1 + mentionCandidates.count) % mentionCandidates.count
                                    return .handled
                                }
                                .onKeyPress(.downArrow) {
                                    guard showMentionList, !mentionCandidates.isEmpty else { return .ignored }
                                    mentionHighlight = (mentionHighlight + 1) % mentionCandidates.count
                                    return .handled
                                }
                                .onKeyPress(.tab) {
                                    guard showMentionList, mentionCandidates.indices.contains(mentionHighlight) else { return .ignored }
                                    applyMention(mentionCandidates[mentionHighlight])
                                    return .handled
                                }
                                .onExitCommand {
                                    if showMentionList { mentionHidden = true }
                                }
                            Button(action: {
                                if canRun {
                                    run(prompt: instructions, label: pendingVia)
                                } else {
                                    onOpenSettings()
                                }
                            }) {
                                if canRun {
                                    Image(systemName: "paperplane.fill")
                                        .foregroundColor(FlowComponent.for(scheme).primaryFg)
                                        .padding(7)
                                        .background(accent.color(for: scheme))
                                        .clipShape(Circle())
                                } else {
                                    Text("Connect")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(FlowComponent.for(scheme).primaryFg)
                                        .padding(.horizontal, 10).padding(.vertical, 7)
                                        .background(accent.color(for: scheme))
                                        .clipShape(Capsule())
                                }
                            }
                            .buttonStyle(FlowPressStyle())
                            .disabled(canRun ? (isWorking || instructions.trimmingCharacters(in: .whitespaces).isEmpty) : isWorking)
                            .help(canRun ? "Send" : "Connect AI in Settings")
                        }
                    }
                }
                .padding(12)
                .frame(width: FlowComponent.aiWidth)
            }
        }
        .background(FlowComponent.for(scheme).surface)
        .overlay(Rectangle().fill(FlowComponent.for(scheme).border).frame(width: 1), alignment: .leading)
    }

    // MARK: - @ mention picker (lists the current steps)

    private var activeMentionQuery: String? {
        guard !mentionHidden else { return nil }
        return AIMentions.activeQuery(in: instructions)?.query
    }

    private var mentionCandidates: [AIMentionOption] {
        guard let q = activeMentionQuery, !mentionHidden else { return [] }
        let opts = AIMentions.options(session: session, scopeStep: scopeStep, query: q)
        return opts
    }

    private var showMentionList: Bool {
        AIMentions.activeQuery(in: instructions) != nil && !mentionHidden && composeFocused
    }

    private var mentionPopup: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(session.steps.isEmpty ? "CONTEXT" : "STEPS IN THIS GUIDE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(FlowComponent.for(scheme).textTertiary)
                Spacer()
                Text("\(mentionCandidates.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(FlowComponent.for(scheme).textTertiary)
                Button(action: { mentionHidden = true }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(FlowComponent.for(scheme).textTertiary)
                }
                .buttonStyle(FlowPressStyle())
                .help("Dismiss (Esc)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            if mentionCandidates.isEmpty {
                Text(activeMentionQuery.map { "No matches for “@\($0)”" } ?? "No matches")
                    .font(.system(size: 11))
                    .foregroundColor(FlowComponent.for(scheme).textSecondary)
                    .padding(10)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(mentionCandidates.enumerated()), id: \.element.id) { idx, opt in
                            Button(action: { applyMention(opt) }) {
                                HStack(spacing: 8) {
                                    mentionBadge(for: opt)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(opt.title)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(FlowComponent.for(scheme).textPrimary)
                                            .lineLimit(1)
                                        Text(opt.subtitle)
                                            .font(.system(size: 11))
                                            .foregroundColor(FlowComponent.for(scheme).textSecondary)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }
                                    Spacer(minLength: 4)
                                    Text(opt.token)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(FlowSemantic.for(scheme).accentDefault)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(idx == mentionHighlight ? FlowSemantic.for(scheme).accentSubtle : Color.clear)
                                .cornerRadius(FlowComponent.radiusXS)
                            }
                            .buttonStyle(FlowPressStyle())
                            .help("Insert \(opt.token) — \(opt.subtitle)")
                            .accessibilityLabel("\(opt.title), \(opt.subtitle), \(opt.token)")
                            .onHover { hovering in
                                if hovering { mentionHighlight = idx }
                            }
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 220)
                Text("↑↓ navigate · Enter select · Esc dismiss")
                    .font(.system(size: 10))
                    .foregroundColor(FlowComponent.for(scheme).textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
        }
        .background(FlowComponent.for(scheme).surfaceElevated)
        .cornerRadius(FlowComponent.radiusSM)
        .overlay(RoundedRectangle(cornerRadius: FlowComponent.radiusSM).stroke(FlowComponent.for(scheme).border, lineWidth: 1))
        .shadow(color: FlowSemantic.for(scheme).shadowDefault, radius: 8, y: 2)
        .onChange(of: mentionCandidates.count) { _, count in
            if mentionHighlight >= count { mentionHighlight = 0 }
        }
    }

    @ViewBuilder
    private func mentionBadge(for opt: AIMentionOption) -> some View {
        switch opt.kind {
        case .guide:
            Image(systemName: "book")
                .font(.system(size: 11))
                .foregroundColor(FlowSemantic.for(scheme).accentDefault)
                .frame(width: 22, height: 22)
                .background(FlowSemantic.for(scheme).accentSubtle)
                .clipShape(Circle())
        case .selectedStep:
            Image(systemName: "cursorarrow.click")
                .font(.system(size: 11))
                .foregroundColor(FlowSemantic.for(scheme).accentDefault)
                .frame(width: 22, height: 22)
                .background(FlowSemantic.for(scheme).accentSubtle)
                .clipShape(Circle())
        case .recording:
            Image(systemName: "record.circle")
                .font(.system(size: 11))
                .foregroundColor(FlowSemantic.for(scheme).accentDefault)
                .frame(width: 22, height: 22)
                .background(FlowSemantic.for(scheme).accentSubtle)
                .clipShape(Circle())
        case .automation:
            Image(systemName: "gearshape")
                .font(.system(size: 11))
                .foregroundColor(FlowSemantic.for(scheme).accentDefault)
                .frame(width: 22, height: 22)
                .background(FlowSemantic.for(scheme).accentSubtle)
                .clipShape(Circle())
        case .step:
            Text("\(opt.stepIndex ?? 0)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(FlowSemantic.for(scheme).accentDefault)
                .frame(width: 22, height: 22)
                .background(FlowSemantic.for(scheme).accentSubtle)
                .clipShape(Circle())
        }
    }

    /// Error card with Retry + Open Settings — setup errors show the
    /// actionable setup copy instead of a raw error string.
    private func aiErrorCard(_ card: AIErrorCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.isSetup ? "AI isn't connected yet" : "Couldn't get an AI response")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(FlowComponent.for(scheme).textPrimary)
            Text(card.message)
                .font(.system(size: 11))
                .foregroundColor(FlowComponent.for(scheme).textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if !card.isSetup {
                    Button("Retry") {
                        if let last = lastPrompt {
                            run(prompt: last.text, label: last.via, appendUser: false)
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(FlowPressStyle())
                }
                Button("Open Settings", action: onOpenSettings)
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(FlowPressStyle())
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FlowComponent.for(scheme).surfaceSubtle)
        .cornerRadius(FlowComponent.radiusSM)
        .overlay(RoundedRectangle(cornerRadius: FlowComponent.radiusSM).stroke(FlowSemantic.for(scheme).warningBd, lineWidth: 1))
    }

    /// Chip tap stages the prompt in the compose box for editing —
    /// it does not fire immediately.
    private func stagePrompt(prompt: String, via: String) {
        instructions = prompt
        pendingPrompt = prompt
        pendingVia = via
        mentionHidden = true
        composeFocused = true
    }

    /// Scope-pill × — asks about the whole guide via an editable token
    /// (`@guide` keeps the full session in `scopedSession`).
    private func useWholeGuide() {
        if instructions.isEmpty || instructions.last?.isWhitespace == true {
            instructions += "@guide "
        } else {
            instructions += " @guide "
        }
        pendingPrompt = instructions
        composeFocused = true
    }

    /// Missing-key failures (thrown by `AIGatewayClient` or surfaced while
    /// the panel can't run) become the setup card, never a red raw string.
    private static func isSetupError(_ error: Error) -> Bool {
        if let gw = error as? AIGatewayError, case .missingAPIKey = gw {
            return true
        }
        return false
    }

    private static func friendlyErrorMessage(_ error: Error, canRun: Bool) -> String {
        if isSetupError(error) || !canRun {
            return "Add an API key in Settings, or switch to a local model — local models need no key."
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func applyMention(_ opt: AIMentionOption) {
        instructions = AIMentions.applying(option: opt, to: instructions)
        mentionHighlight = 0
        // The inserted token ends with a space, so `activeQuery` goes nil
        // and the popup closes on its own; keep focus for more typing.
        composeFocused = true
    }

    private func run(prompt: String, label: String?, appendUser: Bool = true) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canRun, !trimmed.isEmpty, !isWorking else { return }
        isWorking = true
        errorCard = nil
        mentionHidden = true
        lastPrompt = (trimmed, label)
        if appendUser {
            thread.append(AIMessage(role: .user, text: trimmed, via: label))
        }
        instructions = ""
        pendingVia = nil
        pendingPrompt = nil
        // @-mention scoping (prototype `targetsFromPrompt`): explicit
        // `@step-N` narrows to those steps, bare `@step` uses the selected
        // step; `@guide`/`@recording`/`@automation` keep the full session.
        let scoped = AIMentions.scopedSession(session: session, scopeStep: scopeStep, instructions: trimmed)
        Task { [scoped] in
            var acc = ""
            do {
                let stream = synthesize(scoped, gateway, style, trimmed)
                for try await tok in stream { acc += tok }
                await MainActor.run {
                    thread.append(AIMessage(role: .assistant, text: acc.isEmpty ? "(empty response)" : acc))
                    onSynthesized(acc)
                    isWorking = false
                }
            } catch {
                await MainActor.run {
                    self.errorCard = AIErrorCard(
                        message: Self.friendlyErrorMessage(error, canRun: self.canRun),
                        isSetup: Self.isSetupError(error) || !self.canRun
                    )
                    isWorking = false
                }
            }
        }
    }
}

/// Simple wrapping layout for quick-action chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        var h: CGFloat = 0
        for row in rows { h += row.height + spacing }
        return CGSize(width: proposal.width ?? 0, height: max(0, h - spacing))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(proposal: .init(width: bounds.width, height: nil), subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for (idx, size) in row.items {
                subviews[idx].place(at: CGPoint(x: x, y: y), proposal: .init(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }
    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [(items: [(Int, CGSize)], height: CGFloat)] {
        let maxW = proposal.width ?? .infinity
        var rows: [(items: [(Int, CGSize)], height: CGFloat)] = []
        var cur: [(Int, CGSize)] = []
        var curW: CGFloat = 0
        var curH: CGFloat = 0
        for (i, s) in subviews.enumerated() {
            let size = s.sizeThatFits(.unspecified)
            if curW + size.width > maxW, !cur.isEmpty {
                rows.append((cur, curH))
                cur = []; curW = 0; curH = 0
            }
            cur.append((i, size))
            curW += size.width + spacing
            curH = max(curH, size.height)
        }
        if !cur.isEmpty { rows.append((cur, curH)) }
        return rows
    }
}
