import SwiftUI

/// Applies a keyboard shortcut only when one is provided (keeps the
/// call-site's view type stable so both branches type-check as one).
private struct OptionalShortcut: ViewModifier {
    let shortcut: (KeyEquivalent, EventModifiers)?

    func body(content: Content) -> some View {
        if let (key, modifiers) = shortcut {
            content.keyboardShortcut(key, modifiers: modifiers)
        } else {
            content
        }
    }
}

/// Run status for the live log console.
private enum AutomationStatus {
    case idle
    case running
    case passed
    case failed

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .running: return "Running"
        case .passed: return "Passed"
        case .failed: return "Failed"
        }
    }
}

/// Automation sheet — generated Playwright script + steps JSON preview,
/// editor handoff menu, Run/Copy/Export toolbar, collapsible log footer.
///
/// UX (HIG + dev-tool audit of the previous 5-box layout):
/// - One primary zone (code), one action row, one status footer. The old
///   `Open in…` 6-button card is gone — it truncated labels ("VS Co…",
///   "Sublim…"), forced a 660pt width, and duplicated the toolbar. It is
///   now a single `OpenInMenu` (progressive disclosure).
/// - Run is the sole primary (trailing). Copy/Export are secondary.
///   The duplicate Copy in the code header is icon-only.
/// - The old "Step N" pill described the *selected* step while the script
///   covers the whole guide — now "N steps" (total).
/// - Logs collapse to a one-line status bar when idle; the tall console
///   appears only while running or once lines exist.
public struct AutomationSheet: View {
    private let script: String
    private let stepsJSON: String
    private let stepNumber: Int
    private let totalSteps: Int?
    private let isRunning: Bool
    private let logs: [String]
    private let onRun: () -> Void
    private let onCopy: () -> Void
    private let onExport: () -> Void
    private let onOpen: (EditorTarget) -> Void
    private let onClose: () -> Void
    private let onFileChange: (FlowCodeFile) -> Void

    @State private var file: FlowCodeFile = .script
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        script: String,
        stepsJSON: String,
        stepNumber: Int,
        totalSteps: Int? = nil,
        isRunning: Bool,
        logs: [String],
        onRun: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onExport: @escaping () -> Void,
        onOpen: @escaping (EditorTarget) -> Void,
        onClose: @escaping () -> Void,
        onFileChange: @escaping (FlowCodeFile) -> Void = { _ in }
    ) {
        self.script = script
        self.stepsJSON = stepsJSON
        self.stepNumber = stepNumber
        self.totalSteps = totalSteps
        self.isRunning = isRunning
        self.logs = logs
        self.onRun = onRun
        self.onCopy = onCopy
        self.onExport = onExport
        self.onOpen = onOpen
        self.onClose = onClose
        self.onFileChange = onFileChange
    }

    public var body: some View {
        let comp = FlowComponent.for(scheme)
        VStack(alignment: .leading, spacing: FlowSpacing.md) {
            header(comp: comp)
            toolbarRow(comp: comp)
            codePane()
            logFooter(comp: comp)
        }
        .padding(FlowSpacing.lg)
        .frame(minWidth: 600, minHeight: 520)
        .background(comp.canvas)
    }

    // MARK: - Header: title + scope, status + close

    private func header(comp: FlowComponent) -> some View {
        HStack(alignment: .center, spacing: FlowSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Automation")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(comp.textPrimary)
                Text("Playwright script from this guide — selectors use recorded accessibility targets.")
                    .font(.system(size: 12))
                    .foregroundColor(comp.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            FlowPill(stepsLabel, kind: .neutral)
            statusBadge(comp: comp)
            Button(action: onClose) {
                Image(systemName: FlowSymbols.close)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(comp.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(comp.surfaceSubtle)
                    .cornerRadius(FlowComponent.radiusSM)
            }
            .buttonStyle(FlowPressStyle())
            .keyboardShortcut(.cancelAction)
            .help("Close (Esc)")
            .accessibilityLabel("Close automation")
        }
    }

    private var stepsLabel: String {
        if let totalSteps { return "\(totalSteps) steps" }
        return "Step \(stepNumber)"
    }

    // MARK: - Single action row: file switcher + handoff + Run

    private func toolbarRow(comp: FlowComponent) -> some View {
        HStack(spacing: FlowSpacing.sm) {
            Picker("", selection: $file) {
                ForEach(FlowCodeFile.allCases, id: \.self) { f in
                    Text(f.label).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .help("Choose the generated file to preview")
            .accessibilityLabel("Generated file")
            .onChange(of: file) { _, new in onFileChange(new) }
            Spacer()
            OpenInMenu(fileName: activeFileName, onOpen: onOpen)
            FlowButton("Copy", icon: FlowSymbols.copy, variant: .secondary, size: .regular, action: onCopy)
                .help("Copy \(activeFileName) to the clipboard (⇧⌘C)")
                .modifier(OptionalShortcut(shortcut: ("C", [.command, .shift])))
            FlowButton("Export", icon: FlowSymbols.share, variant: .secondary, size: .regular, action: onExport)
                .help("Save \(activeFileName) to disk")
            FlowButton(
                isRunning ? "Running…" : "Run",
                icon: isRunning ? nil : FlowSymbols.play,
                variant: .primary, size: .regular,
                action: onRun
            )
            .disabled(isRunning)
            .help("Run the generated Playwright script (⌘R)")
            .keyboardShortcut("r", modifiers: .command)
            .accessibilityLabel("Run the generated Playwright script")
        }
    }

    // MARK: - Code pane (sole primary zone)

    private var activeText: String { file == .script ? script : stepsJSON }

    private var activeFileName: String { file.label }

    private var activeLines: [String] {
        activeText.components(separatedBy: "\n")
    }

    private func codePane() -> some View {
        let sem = FlowSemantic.for(scheme)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: FlowSpacing.sm) {
                Image(systemName: file == .script ? "chevron.left.forwardslash.chevron.right" : "curlybraces")
                    .font(.system(size: 11))
                    .foregroundColor(sem.codeSecondary)
                Text(activeFileName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(sem.codeText)
                Text("\(activeLines.count) lines")
                    .font(.system(size: 11))
                    .foregroundColor(sem.codeSecondary)
                Spacer()
                Button(action: onCopy) {
                    Image(systemName: FlowSymbols.copy)
                        .font(.system(size: 11))
                        .foregroundColor(sem.codeSecondary)
                        .padding(4)
                }
                .buttonStyle(FlowPressStyle())
                .help("Copy \(activeFileName) (⇧⌘C)")
                .accessibilityLabel("Copy \(activeFileName)")
            }
            .padding(.horizontal, FlowSpacing.md)
            .padding(.vertical, FlowSpacing.sm)
            Rectangle()
                .fill(sem.codeBorder)
                .frame(height: 1)
            ScrollView([.vertical, .horizontal]) {
                HStack(alignment: .top, spacing: FlowSpacing.md) {
                    VStack(alignment: .trailing, spacing: 2) {
                        ForEach(activeLines.indices, id: \.self) { i in
                            Text("\(i + 1)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(sem.codeSecondary)
                        }
                    }
                    .frame(minWidth: 28)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(activeLines.indices, id: \.self) { i in
                            let line = activeLines[i]
                            let trimmed = line.trimmingCharacters(in: .whitespaces)
                            Text(line.isEmpty ? " " : line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(trimmed.hasPrefix("//") ? sem.codeSecondary : sem.codeText)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(FlowSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(sem.codeBg)
        .cornerRadius(FlowComponent.radiusSM)
        .overlay(
            RoundedRectangle(cornerRadius: FlowComponent.radiusSM)
                .stroke(sem.codeBorder, lineWidth: 1)
        )
    }

    // MARK: - Collapsible log footer

    private var status: AutomationStatus {
        if isRunning { return .running }
        guard !logs.isEmpty else { return .idle }
        let joined = logs.joined(separator: "\n").lowercased()
        if joined.contains("fail") || joined.contains("✗") || joined.contains("error") { return .failed }
        return .passed
    }

    private var statusHint: String {
        switch status {
        case .idle: return "Press Run to execute the script"
        case .running: return "Running…"
        case .passed: return "Finished — \(logs.count) lines"
        case .failed: return "Finished with failures"
        }
    }

    private func statusBadge(comp: FlowComponent) -> some View {
        let sem = FlowSemantic.for(scheme)
        let (bg, fg): (Color, Color) = {
            switch status {
            case .idle: return (comp.surfaceSubtle, comp.textSecondary)
            case .running: return (sem.accentSubtle, sem.accentDefault)
            case .passed: return (sem.successBg, sem.successFg)
            case .failed: return (sem.dangerBg, sem.dangerFg)
            }
        }()
        return HStack(spacing: 6) {
            if status == .running {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Circle()
                    .fill(status == .idle ? comp.textTertiary : fg)
                    .frame(width: 8, height: 8)
            }
            Text(status.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(fg)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(bg)
        .clipShape(Capsule())
        .help(statusHint)
    }

    private func logLineColor(_ line: String, sem: FlowSemantic) -> Color {
        let lower = line.lowercased()
        if lower.contains("fail") || lower.contains("✗") || lower.contains("error") { return sem.dangerFg }
        if lower.contains("✓") || lower.contains("pass") || lower.contains("done") { return sem.successFg }
        return sem.codeText
    }

    private func logFooter(comp: FlowComponent) -> some View {
        let sem = FlowSemantic.for(scheme)
        return VStack(alignment: .leading, spacing: FlowSpacing.sm) {
            HStack(spacing: FlowSpacing.sm) {
                Text("Logs")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(comp.textTertiary)
                Spacer()
                Text(statusHint)
                    .font(.system(size: 11))
                    .foregroundColor(comp.textTertiary)
                    .lineLimit(1)
            }
            if logs.isEmpty && !isRunning {
                Text("No runs yet — logs stream here while the script runs.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(sem.codeSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(sem.codeBg)
                    .cornerRadius(FlowComponent.radiusSM)
                    .overlay(
                        RoundedRectangle(cornerRadius: FlowComponent.radiusSM)
                            .stroke(sem.codeBorder, lineWidth: 1)
                    )
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(logs.indices, id: \.self) { i in
                                Text(logs[i])
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(logLineColor(logs[i], sem: sem))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(i)
                                    .transition(.opacity)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 112)
                    .background(sem.codeBg)
                    .cornerRadius(FlowComponent.radiusSM)
                    .overlay(
                        RoundedRectangle(cornerRadius: FlowComponent.radiusSM)
                            .stroke(sem.codeBorder, lineWidth: 1)
                    )
                    .onChange(of: logs.count) { _, _ in
                        guard let last = logs.indices.last else { return }
                        if reduceMotion {
                            proxy.scrollTo(last, anchor: .bottom)
                        } else {
                            withAnimation(FlowMotion.easeOutFast) {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : FlowMotion.standard, value: logs.count)
    }
}
