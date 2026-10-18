import SwiftUI
import FlowlineAIGateway
import FlowlineEngine

/// AI gateway pane — clean Form layout.
///
/// Sections: Provider → Endpoint → Authentication → Model → Generation.
/// - Provider cards explain Cloud vs Local so the choice is obvious.
/// - Endpoint + API key validate inline instead of failing at synthesis time.
/// - CLI provider hides irrelevant URL/key fields and shows the command.
/// - Temperature uses Slider + Stepper + Reset for precise control.
public struct SettingsGatewayPane: View {
    @Binding public var settings: FlowlineSettings

    @State private var isShowingApiKey = false

    public init(settings: Binding<FlowlineSettings>) {
        self._settings = settings
    }

    private var isLocal: Bool {
        settings.gateway.provider == .ollama
            || settings.gateway.provider == .lmStudio
            || settings.gateway.provider == .cli
    }

    private var endpointError: String? {
        if settings.gateway.provider == .cli { return nil }
        return SettingsValidation.gatewayEndpointError(
            baseURL: settings.gateway.baseURL,
            providerIsLocal: isLocal
        )
    }

    private var needsAPIKey: Bool {
        settings.gateway.provider == .openRouter
            || settings.gateway.provider == .customOpenAI
    }

    public var body: some View {
        Form {
            // MARK: Provider
            Section {
                Picker("Provider", selection: $settings.gateway.provider) {
                    ForEach(GatewayProviderType.allCases, id: \.self) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: settings.gateway.provider) { _, newProvider in
                    resetEndpointIfStillDefault(for: newProvider)
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: isLocal ? "desktopcomputer" : "cloud.fill")
                        .foregroundStyle(isLocal ? .green : .blue)
                    Text(providerBlurb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            } header: {
                Text("AI Provider")
            } footer: {
                Text("Cloud = best quality, screenshots leave this Mac. Local = private & offline, needs Ollama / LM Studio running.")
            }

            // MARK: Connection (CLI only — other providers keep their
            // endpoint under Advanced below)
            if settings.gateway.provider == .cli {
                Section("Connection") {
                    LabeledContent("Command") {
                        TextField("ollama run llama3.2-vision", text: $settings.gateway.model)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 340)
                            .font(.system(.body, design: .monospaced))
                    }
                    Text("Runs locally via the CLI pipeline — no URL or API key needed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: Authentication
            if settings.gateway.provider != .cli {
                Section {
                    LabeledContent("API Key") {
                        HStack(spacing: 6) {
                            if isShowingApiKey {
                                TextField("sk-…", text: $settings.gateway.apiKey)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField(needsAPIKey ? "Required for cloud" : "Optional", text: $settings.gateway.apiKey)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Button(action: { isShowingApiKey.toggle() }) {
                                Image(systemName: isShowingApiKey ? "eye.slash" : "eye")
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                            .help(isShowingApiKey ? "Hide API key" : "Show API key")
                            .accessibilityLabel(isShowingApiKey ? "Hide API key" : "Show API key")
                        }
                        .frame(maxWidth: 340)
                    }

                    if settings.gateway.apiKey.trimmingCharacters(in: .whitespaces).isEmpty && needsAPIKey {
                        Label("Not connected — paste an API key above to connect, or switch to a local provider. Local models need no key.", systemImage: "key.slash.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Stored in Settings.json. Cloud providers send it as Bearer auth.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Authentication")
                }
            }

            // MARK: Generation
            Section {
                Toggle("Send screenshots to the model", isOn: $settings.gateway.visionEnabled)
                Text(isLocal
                     ? "Screenshots stay on this Mac with local providers."
                     : "Screenshots are uploaded to the cloud gateway for higher accuracy. Turn off for text-only synthesis.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Generation")
            }

            // MARK: Advanced — endpoint, model, creativity. The provider
            // picker stays top-level so the Cloud/Local choice is always
            // visible; these fields rarely change after setup.
            DisclosureGroup("Advanced") {
                if settings.gateway.provider != .cli {
                    LabeledContent("Endpoint") {
                        TextField("https://…/api/v1", text: $settings.gateway.baseURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 340)
                            .autocorrectionDisabled()
#if os(macOS)
                            .textSelection(.enabled)
#endif
                    }
                    if let endpointError {
                        Label(endpointError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text("OpenAI-compatible /v1 endpoint. /chat/completions is appended automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Model") {
                        TextField("e.g. anthropic/claude-3.5-sonnet", text: $settings.gateway.model)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 340)
                            .autocorrectionDisabled()
                    }
                    // Quick-pick known-good models per provider
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(suggestedModels, id: \.self) { m in
                                Button(m) { settings.gateway.model = m }
                                    .buttonStyle(.link)
                                    .font(.caption)
                            }
                        }
                    }
                }

                LabeledContent("Creativity") {
                    HStack {
                        Slider(value: $settings.gateway.temperature, in: 0...1, step: 0.05)
                            .frame(maxWidth: 220)
                        Text(String(format: "%.2f", settings.gateway.temperature))
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 40, alignment: .trailing)
                        Stepper("", value: $settings.gateway.temperature, in: 0...1, step: 0.05)
                            .labelsHidden()
                        Button("Reset") { settings.gateway.temperature = 0.2 }
                            .buttonStyle(.link)
                            .font(.caption)
                            .disabled(abs(settings.gateway.temperature - 0.2) < 0.001)
                    }
                }
                Text("0.00 = deterministic, 1.00 = most creative. 0.20 is the recommended default for guides.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Helpers

    private var providerBlurb: String {
        switch settings.gateway.provider {
        case .openRouter:
            return "Cloud gateway — access Claude, GPT and more through one key. Best quality."
        case .customOpenAI:
            return "OpenAI, Portkey or LiteLLM — any OpenAI-compatible endpoint."
        case .ollama:
            return "Local & private via Ollama at localhost:11434. No data leaves this Mac."
        case .lmStudio:
            return "Local & private via LM Studio at localhost:1234. Load a vision model first."
        case .cli:
            return "Local pipeline — runs a shell command per synthesis. Fully offline."
        }
    }

    private var suggestedModels: [String] {
        switch settings.gateway.provider {
        case .openRouter:
            return ["anthropic/claude-3.5-sonnet", "openai/gpt-4o", "google/gemini-2.0-flash-001"]
        case .customOpenAI:
            return ["gpt-4o", "gpt-4o-mini"]
        case .ollama:
            return ["llama3.2-vision", "llava:13b", "minicpm-v"]
        case .lmStudio:
            return ["meta-llama-3.2-11b-vision-instruct", "qwen2-vl-7b-instruct"]
        case .cli:
            return []
        }
    }

    /// Only auto-fill URL+model when the user hasn't customized them —
    /// fixes the stale-URL bug where switching presets kept the old endpoint.
    private func resetEndpointIfStillDefault(for newProvider: GatewayProviderType) {
        let allDefaults = Set(GatewayProviderType.allCases.map { $0.defaultBaseURL })
        let current = settings.gateway.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty || allDefaults.contains(current) {
            settings.gateway.baseURL = newProvider.defaultBaseURL
            // Don't clobber a custom CLI command with a model id
            if settings.gateway.provider != .cli || settings.gateway.model.isEmpty {
                settings.gateway.model = newProvider.defaultModel
            } else if newProvider != .cli {
                settings.gateway.model = newProvider.defaultModel
            }
        } else if newProvider == .cli {
            // CLI needs no URL — clear it so validation stays green
            settings.gateway.baseURL = ""
        }
    }
}
