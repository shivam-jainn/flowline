import SwiftUI
import StepItAIGateway
import StepItEngine

/// AI gateway pane of Settings (R/M1-07 split).
/// Edits the gateway section through a binding; persistence stays with the shell.
public struct SettingsGatewayPane: View {
    @Binding public var settings: StepItSettings

    @State private var isShowingApiKey = false

    public init(settings: Binding<StepItSettings>) {
        self._settings = settings
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox(label: Label("AI Gateway Configuration", systemImage: "sparkles")) {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Provider Preset", selection: $settings.gateway.provider) {
                            ForEach(GatewayProviderType.allCases, id: \.self) { (p: GatewayProviderType) in
                                Text(p.displayName).tag(p)
                            }
                        }
                        .onChange(of: settings.gateway.provider) { _, newProvider in
                            if settings.gateway.baseURL.isEmpty ||
                                settings.gateway.baseURL == GatewayProviderType.openRouter.defaultBaseURL ||
                                settings.gateway.baseURL == GatewayProviderType.ollama.defaultBaseURL {
                                settings.gateway.baseURL = newProvider.defaultBaseURL
                                settings.gateway.model = newProvider.defaultModel
                            }
                        }

                        TextField("Base URL", text: $settings.gateway.baseURL)
                            .help("OpenAI-compatible /v1 endpoint (e.g. OpenRouter, Portkey, LiteLLM, Ollama, LM Studio)")

                        HStack {
                            if isShowingApiKey {
                                TextField("API Key", text: $settings.gateway.apiKey)
                            } else {
                                SecureField("API Key", text: $settings.gateway.apiKey)
                            }
                            Button(action: { isShowingApiKey.toggle() }) {
                                Image(systemName: isShowingApiKey ? "eye.slash" : "eye")
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        TextField("Model Identifier", text: $settings.gateway.model)
                            .help("e.g. anthropic/claude-3.5-sonnet, gpt-4o, llama3.2-vision")

                        Toggle("Enable Multimodal Vision (Send Screenshots)", isOn: $settings.gateway.visionEnabled)
                            .help("Transmits captured step screenshots to vision-capable models for higher accuracy synthesis.")

                        Slider(value: $settings.gateway.temperature, in: 0.0...1.0, step: 0.05) {
                            Text("Temperature: \(String(format: "%.2f", settings.gateway.temperature))")
                        }
                    }
                    .padding(10)
                }
            }
            .padding()
        }
    }
}
