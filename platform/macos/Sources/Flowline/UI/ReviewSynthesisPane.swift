import SwiftUI
import FlowlineAIGateway
import FlowlineEngine
import FlowlineIR

/// AI synthesis pane of the review window (R/M1-07 split).
/// Streams documentation through the injected synthesis service; the finished
/// text is handed back to the shell for persistence via `onSynthesized`.
public struct ReviewSynthesisPane: View {
    public var session: StepSession
    public var gateway: GatewaySettings
    public var synthesis: any StepSynthesisService
    public var onSynthesized: (String) -> Void
    public var onOpenSettings: () -> Void

    @State private var selectedStyle: DocumentationStyle = .sopGuide
    @State private var customInstructions: String = ""
    @State private var isSynthesizing = false
    @State private var synthesizedText: String
    @State private var synthesisError: String?

    public init(
        session: StepSession,
        gateway: GatewaySettings,
        synthesis: any StepSynthesisService,
        onSynthesized: @escaping (String) -> Void = { _ in },
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.session = session
        self.gateway = gateway
        self.synthesis = synthesis
        self.onSynthesized = onSynthesized
        self.onOpenSettings = onOpenSettings
        self._synthesizedText = State(initialValue: session.synthesizedMarkdown ?? "")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.md) {
            HStack {
                Label("AI Synthesis Gateway", systemImage: FlowSymbols.ai)
                    .font(.headline)
                    .foregroundColor(.accentColor)
                Spacer()
                // Provider settings — leading icon only, even spacing
                Button(action: onOpenSettings) {
                    Label(gateway.provider.displayName, systemImage: FlowSymbols.settings)
                        .font(.system(size: 11))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Configure AI Provider & API Keys in Settings")
                .accessibilityLabel("Configure AI provider settings")
            }

            HStack {
                Text("Documentation Style:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $selectedStyle) {
                    ForEach(DocumentationStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(maxWidth: 240)
            }

            TextField("Custom Instructions (e.g. 'Use concise bullet points', 'Target macOS Sequoia')", text: $customInstructions)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.system(size: 12))

            HStack {
                Button(action: startAISynthesis) {
                    // Leading icon + label, even 6pt gap
                    HStack(spacing: 6) {
                        if isSynthesizing {
                            ProgressView()
                                .controlSize(.small)
                            Text("Synthesizing Stream...")
                        } else {
                            Image(systemName: FlowSymbols.generate)
                                .font(.system(size: 12, weight: .semibold))
                            Text("Generate Documentation with AI")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .disabled(isSynthesizing || session.steps.isEmpty)
            }

            if let err = synthesisError {
                HStack(spacing: FlowSpacing.sm) {
                    Image(systemName: FlowSymbols.warning)
                        .foregroundColor(.red)
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            // Output Markdown Preview
            if !synthesizedText.isEmpty {
                VStack(alignment: .leading, spacing: FlowSpacing.sm) {
                    HStack {
                        Text("Synthesized Output")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(synthesizedText, forType: .string)
                        }) {
                            Label("Copy Markdown", systemImage: FlowSymbols.copy)
                        }
                        .controlSize(.small)
                    }

                    TextEditor(text: $synthesizedText)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(height: 200)
                        .padding(FlowSpacing.xs)
                        .border(Color.secondary.opacity(0.2), width: 1)
                        .cornerRadius(FlowComponent.radiusXS)
                }
            }
        }
        .padding(FlowSpacing.lg)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(FlowComponent.radiusMD)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func startAISynthesis() {
        isSynthesizing = true
        synthesisError = nil
        synthesizedText = ""

        Task {
            do {
                let stream = synthesis.generateStream(
                    session: session,
                    settings: gateway,
                    style: selectedStyle,
                    customInstructions: customInstructions
                )

                for try await token in stream {
                    await MainActor.run {
                        self.synthesizedText += token
                    }
                }

                await MainActor.run {
                    self.onSynthesized(self.synthesizedText)
                    self.isSynthesizing = false
                }
            } catch {
                await MainActor.run {
                    self.synthesisError = error.localizedDescription
                    self.isSynthesizing = false
                }
            }
        }
    }
}
