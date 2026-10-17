import SwiftUI
import StepItFixtures
import StepItCaptureAPI
import StepItEngine
import StepItIR
import StepItPermissions

/// Settings shell (R/M1-07 split).
/// State flows from the injected settings snapshot + controller; persistence
/// goes through the injected `SettingsFileStore`. Composes the
/// gateway/capture/privacy presenter panes with the remaining tabs.
public struct SettingsView: View {
    @ObservedObject private var controller: WorkflowController
    @State private var settings: StepItSettings
    private let settingsStore: SettingsFileStore
    private let permissions: PermissionsManager

    @State private var showSavedAlert = false
    @State private var liveTestFeedback: String?
    @State private var liveTestFeedbackAction: GestureAction?

    public init(
        controller: WorkflowController,
        settings: StepItSettings,
        settingsStore: SettingsFileStore,
        permissions: PermissionsManager
    ) {
        self.controller = controller
        self._settings = State(initialValue: settings)
        self.settingsStore = settingsStore
        self.permissions = permissions
    }

    public var body: some View {
        TabView {
            SettingsGatewayPane(settings: $settings)
                .tabItem {
                    Label("AI Gateway", systemImage: "cpu.fill")
                }

            SettingsCapturePane(settings: $settings)
                .tabItem {
                    Label("Capture", systemImage: "camera.viewfinder")
                }

            gesturesTab
                .tabItem {
                    Label("Smart Gestures", systemImage: "hand.tap.fill")
                }

            SettingsPrivacyPane(settings: $settings)
                .tabItem {
                    Label("Privacy", systemImage: "hand.raised.fill")
                }

            shortcutsTab
                .tabItem {
                    Label("Shortcuts", systemImage: "command")
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
        .frame(width: 620, height: 560)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save Settings") {
                    try? settingsStore.save(settings)
                    // Single-owner routing (fix F2 / Phase 2 T9): settings reach
                    // the engine + driver through the controller, never by
                    // writing detectors or recognizers directly.
                    Task { await controller.applySettings(settings) }
                    showSavedAlert = true
                }
                .buttonStyle(BorderedProminentButtonStyle())
            }
        }
        .alert("Settings Saved", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: - Shortcuts Tab (Phase 2, T2/T9)

    private var shortcutsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox(label: Label("Keyboard Capture", systemImage: "command")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Capture Modifier Shortcuts (⌘S, ⌘⇧P, ⌃C…)", isOn: $settings.hotkeyCapture.captureModifierShortcuts)
                            .help("Each shortcut becomes a discrete 'key_press' step with a screenshot.")
                        Toggle("Capture Navigation Keys (Esc, Tab, Arrows, F-Keys)", isOn: $settings.hotkeyCapture.captureNavigationKeys)
                    }
                    .padding(10)
                }

                GroupBox(label: Label("Always-Ignored Combos", systemImage: "nosign")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("One combo per line (e.g. ⌘Tab, ⌘Space). These are consumed and never recorded.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: ignoredCombosBinding)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 60)
                            .border(Color.secondary.opacity(0.2))
                            .cornerRadius(4)
                    }
                    .padding(10)
                }

                GroupBox(label: Label("Recording Toggle", systemImage: "record.circle")) {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Toggle Shortcut", text: $settings.hotkeys.toggleRecording)
                            .help("Default ⌥ Space. The recorder consumes this combo and never records it as a step.")
                    }
                    .padding(10)
                }
            }
            .padding()
        }
    }

    private var ignoredCombosBinding: Binding<String> {
        Binding(
            get: { settings.hotkeyCapture.ignoredCombos.sorted().joined(separator: "\n") },
            set: { newValue in
                settings.hotkeyCapture.ignoredCombos = Set(
                    newValue
                        .components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                )
            }
        )
    }

    // MARK: - Publishing Tab

    private var publishingTab: some View {        ScrollView {
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
            Task { await controller.applyGestureSettings(settings.gestures) }
        }
        .onChange(of: controller.lastGestureEvent) { _, event in
            guard let event = event else { return }
            liveTestFeedback = event.name
            liveTestFeedbackAction = event.action
        }
    }

    private func simulateGesture(_ name: String, action: GestureAction) {
        liveTestFeedback = name
        liveTestFeedbackAction = action
    }

    // MARK: - Permissions Tab

    private var permissionsTab: some View {
        VStack {
            PermissionsBannerView(manager: permissions)
            Spacer()
        }
        .padding()
    }
}
