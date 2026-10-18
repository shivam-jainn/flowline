import SwiftUI
import FlowlineFixtures
import FlowlineCaptureAPI
import FlowlineEngine
import FlowlineIR
import FlowlinePermissions

/// Settings shell — sidebar navigation + autosave.
///
/// Previous design: 7-tab `TabView`, manual "Save Settings" button swallowing
/// errors, clipped 620×500 non-resizable window, placeholder-as-label fields.
/// Now: `NavigationSplitView` sidebar, `Form`-based panes, every change
/// persists immediately and forwards to the engine. No Save button.
public struct SettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case ai = "AI Model"
        case capture = "Capture"
        case privacy = "Privacy"
        case shortcuts = "Shortcuts"
        case gestures = "Gestures"
        case publishing = "Publishing"
        case onboarding = "Onboarding"
        case permissions = "Permissions"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .ai: return "cpu.fill"
            case .capture: return "camera.viewfinder"
            case .privacy: return "hand.raised.fill"
            case .shortcuts: return "command"
            case .gestures: return "hand.tap.fill"
            case .publishing: return "doc.text.fill"
            case .onboarding: return "sparkles"
            case .permissions: return "lock.shield.fill"
            }
        }
    }

    @ObservedObject private var controller: WorkflowController
    @State private var settings: FlowlineSettings
    @State private var selection: Section = .ai
    @State private var saveState: SaveState = .saved
    @State private var saveError: String?
    @State private var saveTask: Task<Void, Never>?
    private let settingsStore: SettingsFileStore
    private let permissions: PermissionsManager
    private let firstRun: FirstRunWindowController?
    private let onClose: () -> Void

    enum SaveState: Equatable {
        case saved, saving, failed
    }

    public init(
        controller: WorkflowController,
        settings: FlowlineSettings,
        settingsStore: SettingsFileStore,
        permissions: PermissionsManager,
        firstRun: FirstRunWindowController? = nil,
        onClose: @escaping () -> Void = {}
    ) {
        self.controller = controller
        self._settings = State(initialValue: settings)
        self.settingsStore = settingsStore
        self.permissions = permissions
        self.firstRun = firstRun
        self.onClose = onClose
    }

    public var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("Settings")
            .frame(minWidth: 180)
        } detail: {
            VStack(spacing: 0) {
                detailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                statusBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .onExitCommand { onClose() }
        .onChange(of: settings) { _, newValue in
            autosave(newValue)
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        switch selection {
        case .ai:
            SettingsGatewayPane(settings: $settings)
                .navigationTitle("AI Model")
        case .capture:
            SettingsCapturePane(settings: $settings)
                .navigationTitle("Capture")
        case .privacy:
            SettingsPrivacyPane(settings: $settings)
                .navigationTitle("Privacy")
        case .shortcuts:
            SettingsShortcutsPane(settings: $settings)
                .navigationTitle("Shortcuts")
        case .gestures:
            SettingsGesturesPane(settings: $settings, controller: controller)
                .navigationTitle("Gestures")
        case .publishing:
            SettingsPublishingPane(settings: $settings)
                .navigationTitle("Publishing")
        case .onboarding:
            if let firstRun {
                SettingsOnboardingPane(firstRun: firstRun)
                    .navigationTitle("Onboarding")
            } else {
                Text("Onboarding unavailable in this context.")
                    .navigationTitle("Onboarding")
            }
        case .permissions:
            SettingsPermissionsPane(manager: permissions)
                .navigationTitle("Permissions")
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            switch saveState {
            case .saved:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("All changes saved automatically").font(.caption).foregroundStyle(.secondary)
            case .saving:
                ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
                Text("Saving…").font(.caption).foregroundStyle(.secondary)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text(saveError ?? "Save failed").font(.caption).foregroundStyle(.red)
            }
            Spacer()
            Text(sectionHint)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var sectionHint: String {
        switch selection {
        case .ai: return "Cloud = quality · Local = private"
        case .capture: return "Applies to the next recording"
        case .privacy: return "100% on-device redaction"
        case .shortcuts: return "Applies instantly"
        case .gestures: return "Live test below"
        case .publishing: return "Used on next export"
        case .onboarding: return "Tour + new-guide defaults"
        case .permissions: return "macOS system access"
        }
    }

    private func autosave(_ newValue: FlowlineSettings) {
        saveTask?.cancel()
        saveState = .saving
        saveError = nil
        // Debounce 350ms so slider drags don't hammer disk + engine.
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            do {
                try settingsStore.save(newValue)
                await controller.applySettings(newValue)
                saveState = .saved
            } catch {
                saveState = .failed
                saveError = error.localizedDescription
            }
        }
    }
}
