import SwiftUI
import StepItCore

public struct SettingsView: View {
    @State private var settings: StepItSettings = SessionStore.shared.loadSettings()
    @State private var showSavedAlert = false
    @State private var isShowingApiKey = false
    
    public init() {}
    
    public var body: some View {
        TabView {
            gatewayTab
                .tabItem {
                    Label("AI Gateway", systemImage: "cpu.fill")
                }
            
            captureTab
                .tabItem {
                    Label("Capture", systemImage: "camera.viewfinder")
                }
            
            publishingTab
                .tabItem {
                    Label("Publishing", systemImage: "doc.text.fill")
                }
            
            permissionsTab
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield.fill")
                }
        }
        .padding()
        .frame(width: 580, height: 460)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save Settings") {
                    try? SessionStore.shared.saveSettings(settings)
                    showSavedAlert = true
                }
                .buttonStyle(BorderedProminentButtonStyle())
            }
        }
        .alert("Settings Saved", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) {}
        }
    }
    
    // MARK: - Gateway Tab
    
    private var gatewayTab: some View {
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
    
    // MARK: - Capture Tab
    
    private var captureTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox(label: Label("Media Capture Engine", systemImage: "camera.fill")) {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Capture Mode", selection: $settings.capture.mediaMode) {
                            ForEach(MediaMode.allCases, id: \.self) { (m: MediaMode) in
                                Text(m.displayName).tag(m)
                            }
                        }
                        
                        Stepper("Animated GIF Frame Rate: \(settings.capture.gifFps) fps", value: $settings.capture.gifFps, in: 10...30)
                        
                        Toggle("Highlight Clicks with Indicator Marker", isOn: $settings.capture.highlightClicks)
                        
                        Slider(value: $settings.capture.highlightRadius, in: 16...48, step: 2) {
                            Text("Highlight Marker Radius: \(Int(settings.capture.highlightRadius)) pt")
                        }
                    }
                    .padding(10)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Publishing Tab
    
    private var publishingTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox(label: Label("Documentation Output & Themes", systemImage: "doc.text.fill")) {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Default Web Theme", selection: $settings.publishing.defaultTheme) {
                            ForEach(ThemeName.allCases, id: \.self) { (t: ThemeName) in
                                Text(t.displayName).tag(t)
                            }
                        }
                        
                        TextField("Author / Technical Writer", text: $settings.publishing.authorName)
                        TextField("Company / Team Name", text: $settings.publishing.companyName)
                        
                        Picker("PDF Paper Size", selection: $settings.publishing.pdfPaperSize) {
                            Text("A4").tag("A4")
                            Text("US Letter").tag("Letter")
                        }
                        
                        Toggle("Include Interactive Checklist Mode", isOn: $settings.publishing.enableInteractiveChecklists)
                    }
                    .padding(10)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Permissions Tab
    
    private var permissionsTab: some View {
        VStack {
            PermissionsBannerView()
            Spacer()
        }
        .padding()
    }
}
