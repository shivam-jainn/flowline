import SwiftUI
import StepItEngine
import StepItIR
import StepItStorage

/// Review & publish shell (R/M1-07 split).
/// Composes `ReviewStepsPane` + `ReviewSynthesisPane` + `ReviewExportPane`;
/// every collaborator (store, synthesis, publishing, settings opener) is
/// injected by the composition root — no singletons.
public struct ReviewWindow: View {
    @State public var session: StepSession
    @State private var settings: StepItSettings

    private let store: SessionStore
    private let synthesis: any StepSynthesisService
    private let publisher: any ReviewPublishingService
    private let onOpenSettings: () -> Void

    public init(
        session: StepSession,
        settings: StepItSettings,
        store: SessionStore,
        synthesis: any StepSynthesisService,
        publisher: any ReviewPublishingService,
        onOpenSettings: @escaping () -> Void = {}
    ) {
        _session = State(initialValue: session)
        _settings = State(initialValue: settings)
        self.store = store
        self.synthesis = synthesis
        self.publisher = publisher
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        HSplitView {
            // Left Column: Steps Timeline & Inspector (primary workspace)
            ReviewStepsPane(session: $session, store: store, onOpenSettings: onOpenSettings)
                .frame(minWidth: 460, idealWidth: 640, maxWidth: .infinity)

            // Right Column: AI Synthesis & 1-Click Publishing Pane (action sidebar)
            rightActionPane
                .frame(minWidth: 380, idealWidth: 460, maxWidth: 600)
        }
        .frame(minWidth: 920, maxWidth: .infinity, minHeight: 620, maxHeight: .infinity)
        .preferredColorScheme(session.theme == .developerDark ? .dark : (session.theme == .enterpriseSop ? .light : nil))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    Image(systemName: "stairs")
                        .foregroundColor(.accentColor)
                    Text(session.title)
                        .font(.headline)
                    Text("• \(session.steps.count) steps")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            ToolbarItem(placement: .automatic) {
                HStack(spacing: 6) {
                    Text("Theme:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("Theme", selection: $session.theme) {
                        ForEach(ThemeName.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button(action: onOpenSettings) {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")
            }
        }
        .onChange(of: session.theme) { _, newTheme in
            try? store.saveSession(session)
            if session.exports.web != nil {
                exportWebDoc()
            }
        }
    }

    private var rightActionPane: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ReviewSynthesisPane(
                        session: session,
                        gateway: settings.gateway,
                        synthesis: synthesis,
                        onSynthesized: { text in
                            session.synthesizedMarkdown = text
                            try? store.saveSession(session)
                        },
                        onOpenSettings: onOpenSettings
                    )

                    Divider()

                    ReviewExportPane(
                        session: session,
                        publishing: settings.publishing,
                        publisher: publisher
                    )
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private func exportWebDoc() {
        do {
            _ = try publisher.exportWeb(session: session, publishing: settings.publishing)
        } catch {
            // Theme-change re-export is best-effort; the pane surfaces errors.
        }
    }
}
