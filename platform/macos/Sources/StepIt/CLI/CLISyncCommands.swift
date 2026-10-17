import Foundation
import StepItAIGateway
import StepItIR

/// Store/state-query CLI slice (R/M1-07 split): gateway probe, session list,
/// status and export. Reads store, settings, permissions, gateway client and
/// publisher from the shared `AppComposition`.
public struct CLISyncCommands {
    public static func testGatewayStream(composition: AppComposition, prompt: String) async {
        print("⚡️ Testing AI Gateway Streaming (OpenAI-compatible protocol)...")
        let settings = composition.settingsStore.load()
        print("  • Provider: \(settings.gateway.provider.displayName)")
        print("  • Base URL: \(settings.gateway.baseURL)")
        print("  • Model:    \(settings.gateway.model)\n")

        let dummySession = StepSession(
            title: "Gateway Test",
            steps: [
                Step(index: 1, action: .click, appName: "Browser", actionDescription: "Open API Gateway")
            ]
        )

        do {
            let stream = composition.gatewayClient.generateStream(
                session: dummySession,
                settings: settings.gateway,
                style: .sopGuide,
                customInstructions: prompt
            )

            print("--- Streaming Output ---")
            for try await token in stream {
                print(token, terminator: "")
                fflush(stdout)
            }
            print("\n--- End of Stream ---")
        } catch {
            print("\n❌ Gateway error: \(error.localizedDescription)")
            print("Tip: Check API Key or endpoint URL in Settings.")
        }
    }

    public static func showStatus(composition: AppComposition) {
        print("⚡️ StepIt Status & Permissions:\n")

        let screen = composition.permissions.hasScreenRecordingPermission
        let ax = composition.permissions.hasAccessibilityPermission

        print("  • Screen Recording:  \(screen ? "✅ Granted" : "❌ Denied / Not Determined")")
        print("  • Accessibility:     \(ax ? "✅ Granted" : "❌ Denied / Not Determined")")
        print("\n  NOTE: run outside the .app bundle (e.g. `swift run`), these reflect")
        print("  the terminal context, not StepIt.app itself — the in-app window")
        print("  (menu bar → macOS Permissions…) is the verdict that matters.")

        let settings = composition.settingsStore.load()
        print("\n⚙️ Gateway Configuration:")
        print("  • Provider: \(settings.gateway.provider.displayName)")
        print("  • Base URL: \(settings.gateway.baseURL)")
        print("  • Model:    \(settings.gateway.model)")
        print("  • Vision:   \(settings.gateway.visionEnabled ? "Enabled" : "Disabled")")

        print("\n📁 Storage Root:")
        print("  • \(composition.store.baseDirectory.path)")
    }

    public static func listSessions(composition: AppComposition) {
        let sessions = composition.store.listSessions()
        if sessions.isEmpty {
            print("No saved sessions found in \(composition.store.sessionsDirectory.path)")
            return
        }

        print("⚡️ Saved StepIt Sessions (\(sessions.count)):\n")
        for s in sessions {
            print("  • [\(s.id)] \(s.title)")
            print("    Started: \(s.startedAt.formatted()) | Steps: \(s.steps.count) | Theme: \(s.theme.displayName)")
            if let web = s.exports.web {
                print("    Web: \(web)")
            }
            print("")
        }
    }

    @MainActor
    public static func exportSession(composition: AppComposition, id: String) async {
        guard !id.isEmpty else {
            print("Error: Missing session ID. Run `stepit list` to find session IDs.")
            return
        }

        do {
            let session = try composition.store.loadSession(id: id)
            let settings = composition.settingsStore.load()
            print("Exporting session '\(session.title)'...")
            let (webURL, pdfURL, mdURL) = try await composition.publisher.exportAll(
                session: session,
                publishing: settings.publishing
            )
            print("✅ Web Documentation: \(webURL.path)")
            if let pdf = pdfURL {
                print("✅ Styled PDF Guide:   \(pdf.path)")
            }
            print("✅ Markdown README:    \(mdURL.path)")

            composition.publisher.openInBrowser(url: webURL)
        } catch {
            print("❌ Failed to export session: \(error.localizedDescription)")
        }
    }
}
