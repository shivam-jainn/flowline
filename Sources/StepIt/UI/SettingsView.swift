import SwiftUI
import StepItCore

public struct SettingsView: View {
    @State private var settings: StepItSettings = SessionStore.shared.loadSettings()
    @State private var showSavedAlert = false
    @State private var isShowingApiKey = false
    @State private var liveTestFeedback: String?
    @State private var liveTestFeedbackAction: GestureAction?
    
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
            
            gesturesTab
                .tabItem {
                    Label("Smart Gestures", systemImage: "hand.tap.fill")
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
        .frame(width: 620, height: 500)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save Settings") {
                    try? SessionStore.shared.saveSettings(settings)
                    SmartGestureDetector.shared.settings = settings.gestures
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
    
    // MARK: - Smart Gestures Tab
    
    private var gesturesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Section 1: Mouse Shake
                GroupBox(label: Label("Shake to Action", systemImage: "waveform.path.ecg")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Enable Mouse Shake Detection", isOn: $settings.gestures.shakeToPauseEnabled)
                            .fontWeight(.medium)
                        
                        if settings.gestures.shakeToPauseEnabled {
                            Picker("Trigger Action", selection: $settings.gestures.shakeAction) {
                                ForEach(GestureAction.allCases, id: \.self) { act in
                                    Text(act.title).tag(act)
                                }
                            }
                            
                            Picker("Motion Sensitivity", selection: $settings.gestures.shakeSensitivity) {
                                ForEach(GestureSensitivity.allCases, id: \.self) { sens in
                                    Text(sens.title).tag(sens)
                                }
                            }
                            
                            Text("Vigorously shake mouse pointer horizontally to trigger action instantly without pressing hotkeys.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(10)
                }
                
                // Section 2: Hot Corners
                GroupBox(label: Label("Screen Hot Corners", systemImage: "macwindow.on.rectangle")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Enable Screen Hot Corners", isOn: $settings.gestures.hotCorners.enabled)
                            .fontWeight(.medium)
                        
                        if settings.gestures.hotCorners.enabled {
                            VStack(spacing: 10) {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("↖️ Top-Left Corner").font(.caption).fontWeight(.semibold)
                                        Picker("", selection: $settings.gestures.hotCorners.topLeft) {
                                            ForEach(GestureAction.allCases, id: \.self) { act in
                                                Text(act.title).tag(act)
                                            }
                                        }
                                        .labelsHidden()
                                    }
                                    .frame(maxWidth: .infinity)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("↗️ Top-Right Corner").font(.caption).fontWeight(.semibold)
                                        Picker("", selection: $settings.gestures.hotCorners.topRight) {
                                            ForEach(GestureAction.allCases, id: \.self) { act in
                                                Text(act.title).tag(act)
                                            }
                                        }
                                        .labelsHidden()
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("↙️ Bottom-Left Corner").font(.caption).fontWeight(.semibold)
                                        Picker("", selection: $settings.gestures.hotCorners.bottomLeft) {
                                            ForEach(GestureAction.allCases, id: \.self) { act in
                                                Text(act.title).tag(act)
                                            }
                                        }
                                        .labelsHidden()
                                    }
                                    .frame(maxWidth: .infinity)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("↘️ Bottom-Right Corner").font(.caption).fontWeight(.semibold)
                                        Picker("", selection: $settings.gestures.hotCorners.bottomRight) {
                                            ForEach(GestureAction.allCases, id: \.self) { act in
                                                Text(act.title).tag(act)
                                            }
                                        }
                                        .labelsHidden()
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            
                            Text("Slam cursor into screen corners for 0.2s dwell to trigger rapid workflow actions.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(10)
                }
                
                // Section 3: Click & Hold Gestures
                GroupBox(label: Label("Mouse Click & Hold Gestures", systemImage: "hand.tap")) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Middle-Click (Scroll Wheel):")
                            Spacer()
                            Picker("", selection: $settings.gestures.middleClickAction) {
                                ForEach(GestureAction.allCases, id: \.self) { act in
                                    Text(act.title).tag(act)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 230)
                        }
                        
                        HStack {
                            Text("Double Right-Click:")
                            Spacer()
                            Picker("", selection: $settings.gestures.doubleRightClickAction) {
                                ForEach(GestureAction.allCases, id: \.self) { act in
                                    Text(act.title).tag(act)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 230)
                        }
                        
                        HStack {
                            Text("Long Press (Click & Hold):")
                            Spacer()
                            Picker("", selection: $settings.gestures.longPressAction) {
                                ForEach(GestureAction.allCases, id: \.self) { act in
                                    Text(act.title).tag(act)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 230)
                        }
                        
                        if settings.gestures.longPressAction != .none {
                            Slider(value: $settings.gestures.longPressDurationSec, in: 0.5...1.5, step: 0.1) {
                                Text("Long Press Duration: \(String(format: "%.1f", settings.gestures.longPressDurationSec))s")
                            }
                        }
                    }
                    .padding(10)
                }
                
                // Section 4: Live Gesture Test Playground
                GroupBox(label: Label("Live Gesture Test Playground", systemImage: "bolt.fill")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Try shaking your mouse, moving to screen corners, middle-clicking, or holding to test detection:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            if let feedback = liveTestFeedback, let action = liveTestFeedbackAction {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Detected: \(feedback)")
                                            .font(.system(size: 12, weight: .bold))
                                        Text("Mapped to: \(action.title)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(8)
                                .background(Color.green.opacity(0.12))
                                .cornerRadius(8)
                            } else {
                                HStack(spacing: 6) {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.secondary)
                                    Text("Ready — Perform any gesture to test detection sensitivity.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(8)
                            }
                            
                            Spacer()
                            
                            // Simulator buttons
                            Button("Simulate Shake") {
                                simulateGesture("Mouse Shake (Simulated 620 px/s)", action: settings.gestures.shakeAction)
                            }
                            .font(.caption)
                            
                            Button("Simulate Corner") {
                                simulateGesture("Top-Right Corner (Simulated)", action: settings.gestures.hotCorners.topRight)
                            }
                            .font(.caption)
                        }
                    }
                    .padding(10)
                }
            }
            .padding()
        }
        .onAppear {
            SmartGestureDetector.shared.settings = settings.gestures
            SmartGestureDetector.shared.onGestureDetected = { notice in
                liveTestFeedback = notice.gestureName
                liveTestFeedbackAction = notice.action
            }
        }
    }
    
    private func simulateGesture(_ name: String, action: GestureAction) {
        liveTestFeedback = name
        liveTestFeedbackAction = action
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

