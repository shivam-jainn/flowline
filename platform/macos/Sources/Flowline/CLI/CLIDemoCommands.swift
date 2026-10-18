import Foundation
import FlowlineEngine
import FlowlineFixtures
import FlowlineIR

/// Demo/content-generation CLI slice (R/M1-07 split): showcase demo, the
/// 10-page automated tour and the terminal toolchain tour.
/// Fixture builders and the publisher arrive via the shared `AppComposition`.
public struct CLIDemoCommands {
    @MainActor
    public static func runAutomatedTour(composition: AppComposition) async {
        do {
            let settings = composition.settingsStore.load()
            let recorder = AutomatedWorkflowRecorder(
                store: composition.store,
                publisher: composition.publisher,
                publishing: settings.publishing
            )
            _ = try await recorder.recordPlaygroundWorkflow(openInBrowserAfter: true)
        } catch {
            print("[ERROR] Automation failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    public static func runDemo(composition: AppComposition) async {
        print("[Flowline] Building rich Flowline demonstration session from real Web Playground...")

        do {
            let generator = DemoSessionGenerator(store: composition.store)
            let session = try await generator.generate()
            let settings = composition.settingsStore.load()

            try composition.store.saveSession(session)
            print("Saved demo session: \(session.id)")

            print("Generating 1-Click Multi-Format Exports (Interactive Web Doc, Print-Ready PDF, Markdown)...")
            let (webURL, pdfURL, mdURL) = try await composition.publisher.exportAll(
                session: session,
                publishing: settings.publishing
            )

            print("\n[DONE] Demo Successfully Built!")
            print("  Web: \(webURL.path)")
            if let pdf = pdfURL {
                print("  PDF:      \(pdf.path)")
            }
            print("  Markdown:       \(mdURL.path)")

            print("\nOpening Interactive Web Documentation in your browser...")
            composition.publisher.openInBrowser(url: webURL)
        } catch {
            print("Error generating demo: \(error.localizedDescription)")
        }
    }

    @MainActor
    public static func runCLITour(composition: AppComposition) async {
        print("[Flowline] [CLI Tour] Running terminal workflow tour across developer CLI tools...")
        let currentDir = FileManager.default.currentDirectoryPath
        let taskctlURL = URL(fileURLWithPath: currentDir).appendingPathComponent("Scripts/dev/taskctl.py")
        let devpulseURL = URL(fileURLWithPath: currentDir).appendingPathComponent("Scripts/dev/devpulse.sh")

        guard FileManager.default.fileExists(atPath: taskctlURL.path),
              FileManager.default.fileExists(atPath: devpulseURL.path) else {
            print("[ERROR] CLI scripts not found in Scripts/dev/ directory.")
            return
        }

        print("  > [1/3] Executing taskctl list & sprint progress inspection...")
        let step1 = Step(
            id: UUID().uuidString,
            index: 1,
            action: .typing,
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            windowTitle: "taskctl — zsh",
            elementRole: "AXTextField",
            elementTitle: "./Scripts/dev/taskctl.py list",
            actionDescription: "Inspect sprint backlog via taskctl CLI",
            userNotes: "Review open and completed sprint backlog tickets directly in terminal.",
            textBlob: """
            ./Scripts/dev/taskctl.py list
            ./Scripts/dev/taskctl.py stats
            """,
            isCode: true,
            codeLanguage: "bash"
        )

        print("  > [2/3] Executing taskctl add new automation ticket...")
        let step2 = Step(
            id: UUID().uuidString,
            index: 2,
            action: .writeCode,
            appName: "Visual Studio Code",
            bundleIdentifier: "com.microsoft.VSCode",
            windowTitle: "taskctl.py",
            elementRole: "AXCodeEditor",
            elementTitle: "taskctl.py",
            actionDescription: "Add automated playground verification ticket",
            userNotes: "Append high-priority automated testing ticket to the backlog queue.",
            textBlob: """
            ./Scripts/dev/taskctl.py add "Automate end-to-end 10-page playground tour" --priority high --tag testing
            """,
            isCode: true,
            codeLanguage: "bash"
        )

        print("  > [3/3] Executing devpulse system & pipeline benchmark...")
        let step3 = Step(
            id: UUID().uuidString,
            index: 3,
            action: .typing,
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            windowTitle: "devpulse — zsh",
            elementRole: "AXTextField",
            elementTitle: "./Scripts/dev/devpulse.sh doctor",
            actionDescription: "Run developer environment health diagnostics",
            userNotes: "Verify macOS Darwin kernel, Swift compiler toolchain, and Git working tree.",
            textBlob: """
            ./Scripts/dev/devpulse.sh doctor
            ./Scripts/dev/devpulse.sh bench 5
            """,
            isCode: true,
            codeLanguage: "bash"
        )

        let session = StepSession(
            id: "sess_cli_tour_\(Int(Date().timeIntervalSince1970))",
            title: "Terminal CLI & Developer Toolchain Guide",
            theme: .developerDark,
            mediaMode: .hybrid,
            steps: [step1, step2, step3]
        )

        do {
            try composition.store.saveSession(session)
            let settings = composition.settingsStore.load()
            let (webURL, pdfURL, mdURL) = try await composition.publisher.exportAll(
                session: session,
                publishing: settings.publishing
            )
            print("\n[DONE] Terminal CLI Guide Successfully Published!")
            print("  Web: \(webURL.path)")
            if let pdf = pdfURL {
                print("  PDF:      \(pdf.path)")
            }
            print("  Markdown:       \(mdURL.path)")
            composition.publisher.openInBrowser(url: webURL)
        } catch {
            print("[ERROR] CLI tour generation failed: \(error.localizedDescription)")
        }
    }
}
