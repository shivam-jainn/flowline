import SwiftUI
import FlowlineEngine
import FlowlineIR
import FlowlineStorage

/// Review & publish shell (R/M1-07 split).
/// Composes `FlowlineEditor` over the injected collaborators (store,
/// synthesis, publishing, settings opener) — no singletons.
public struct ReviewWindow: View {
    @State public var session: StepSession
    @State private var settings: FlowlineSettings

    private let store: SessionStore
    private let synthesis: any StepSynthesisService
    private let publisher: any ReviewPublishingService
    private let onOpenSettings: () -> Void

    public init(
        session: StepSession,
        settings: FlowlineSettings,
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
        // Flowline workspace: sidebar | editor (header/toolbar/stage/gutter) | AI.
        // The editor is the default surface and reuses the same store/services.
        FlowlineEditor(
            session: $session,
            settings: settings,
            store: store,
            synthesis: synthesis,
            publisher: publisher,
            onOpenSettings: onOpenSettings,
            allSessions: store.listSessions().isEmpty ? [session] : store.listSessions(),
            onSelectSession: { selected in
                try? store.saveSession(session)
                if let loaded = try? store.loadSession(id: selected.id) {
                    session = loaded
                } else {
                    session = selected
                }
            }
        )
        .frame(minWidth: 1180, maxWidth: .infinity, minHeight: 720, maxHeight: .infinity)
        // NOTE (theme single-source-of-truth): no `.preferredColorScheme`
        // from `session.theme` here. The document theme drives export CSS
        // only; live editor chrome follows the system appearance plus the
        // FlowlineEditor appearance picker (`resolvedScheme` +
        // `.preferredColorScheme(appearance.scheme)`). A second override
        // here fought the inner one and caused scheme-split flicker.
        .onChange(of: session.theme) { _, _ in
            try? store.saveSession(session)
        }
    }
}
