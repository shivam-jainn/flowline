import AppKit
import FlowlineFixtures
import Foundation
import FlowlineIR
import FlowlinePipeline
import FlowlineEngine
import FlowlineStorage
import FlowlineCaptureAPI
import FlowlineMacCapture
import FlowlinePublishing
import FlowlineAIGateway
import FlowlinePermissions

/// Single wiring point for the whole app (R/M1-07 composition root).
///
/// Builds every injectable graph exactly once: registries (drivers with
/// versioned `PluginManifest`s, exporters, AI providers), the store, engine,
/// controller, publisher, gateway client and window controllers. No concrete
/// is named anywhere else — surfaces and CLI slices take their pieces from
/// here.
///
/// GUI (`main.swift` → `AppDelegate`) and headless (`CLICommands.handle`)
/// share this path: `AppComposition.make(...)`.
@MainActor
public final class AppComposition {
    public let store: SessionStore
    public let settingsStore: SettingsFileStore
    public let driverRegistry: DriverRegistry
    public let exporterRegistry: ExporterRegistry
    public let providerRegistry: ProviderRegistry
    public let urlOpener: any URLOpener
    public let permissions: PermissionsManager
    public let gatewayClient: AIGatewayClient
    public let publisher: PublishingCoordinator
    public let engine: RecorderWorkflowEngine
    public let controller: WorkflowController
    public let reviewWindows: ReviewWindowController
    public let settingsWindows: SettingsWindowController
    public let hud: FloatingHUDWindowController
    public let firstRun: FirstRunWindowController

    public init(driverID: String = "mac", baseDirectory: URL? = nil) {
        let store = SessionStore(customBaseDirectory: baseDirectory)
        let urlOpener = DefaultURLOpener()
        let permissions = PermissionsManager()
        let gatewayClient = AIGatewayClient(store: store)

        // Registries: every plugin registers a factory + versioned manifest.
        let drivers = DriverRegistry()
        drivers.register(
            manifest: PluginManifest(
                id: "mac",
                version: "1.0.0",
                capabilities: ["snapshots", "micro-clips", "accessibility", "gestures"],
                minimumHostVersion: "r-m1"
            ),
            factory: { MacCaptureDriver() }
        )
        drivers.register(
            manifest: PluginManifest(
                id: "mock",
                version: "1.0.0",
                capabilities: ["snapshots", "micro-clips"],
                minimumHostVersion: "r-m1"
            ),
            factory: { MockCaptureDriver() }
        )
        drivers.register(
            manifest: PluginManifest(id: "noop", version: "1.0.0", minimumHostVersion: "r-m1"),
            factory: { FlowlineNoopDriver() }
        )
        // R/M3-01: the Windows native driver. Manifest mirrors
        // `flowline_win_capture::plugin::windows_manifest()` 1:1; on macOS the
        // factory is a Mock-backed placeholder (no Win32 hooks here) so the
        // registry resolves `windows` alongside mac/mock/noop and sessions
        // flow through the untouched core. On Windows the real Win32-hook
        // driver binary backs this same manifest id.
        drivers.register(
            manifest: PluginManifest(
                id: "windows",
                version: "1.0.0",
                capabilities: ["snapshots", "micro-clips", "accessibility-tree", "secure-field-detection"],
                minimumHostVersion: "r-m1"
            ),
            factory: { MockCaptureDriver() }
        )

        let exporters = ExporterRegistry()
        exporters.register(
            manifest: PluginManifest(id: "markdown", version: "1.0.0", minimumHostVersion: "r-m1"),
            factory: { MarkdownSessionExporter() }
        )
        exporters.register(
            manifest: PluginManifest(id: "webdoc", version: "1.0.0", minimumHostVersion: "r-m1"),
            factory: { WebDocSessionExporter() }
        )
        exporters.register(
            manifest: PluginManifest(id: "pdf-meta", version: "1.0.0", minimumHostVersion: "r-m1"),
            factory: { PDFMetaSessionExporter() }
        )

        let providers = ProviderRegistry()
        let openAISettings = GatewaySettings(
            provider: .customOpenAI,
            baseURL: GatewayProviderType.customOpenAI.defaultBaseURL,
            model: GatewayProviderType.customOpenAI.defaultModel
        )
        let anthropicSettings = GatewaySettings(
            provider: .openRouter,
            baseURL: GatewayProviderType.openRouter.defaultBaseURL,
            model: GatewayProviderType.openRouter.defaultModel
        )
        let ollamaSettings = GatewaySettings(
            provider: .ollama,
            baseURL: GatewayProviderType.ollama.defaultBaseURL,
            model: GatewayProviderType.ollama.defaultModel
        )
        for (id, settings) in [
            ("openai", openAISettings),
            ("anthropic", anthropicSettings),
            ("ollama", ollamaSettings),
        ] {
            let manifest = PluginManifest(id: id, version: "1.0.0", minimumHostVersion: "r-m1")
            let client = gatewayClient
            providers.register(manifest: manifest) {
                ClientBackedGatewayProvider(providerID: id, client: client, settings: settings)
            }
        }

        // Resolve the selected driver (falls back to the mock when unknown).
        let driver: any CaptureDriver = (drivers.resolve(id: driverID) as? any CaptureDriver)
            ?? MockCaptureDriver()

        let publisher = PublishingCoordinator(store: store, urlOpener: urlOpener)
        let engine = RecorderWorkflowEngine(driver: driver, store: store)

        let reviewWindows = ReviewWindowController(
            synthesis: gatewayClient,
            publisher: publisher,
            store: store,
            settingsStore: SettingsFileStore(store: store)
        )
        let controller = WorkflowController(engine: engine, onReview: { session in
            reviewWindows.show(for: session)
        })
        let firstRun = FirstRunWindowController()
        let settingsWindows = SettingsWindowController(
            controller: controller,
            settingsStore: SettingsFileStore(store: store),
            permissions: permissions,
            firstRun: firstRun
        )
        let hud = FloatingHUDWindowController(controller: controller)

        self.store = store
        self.settingsStore = SettingsFileStore(store: store)
        self.driverRegistry = drivers
        self.exporterRegistry = exporters
        self.providerRegistry = providers
        self.urlOpener = urlOpener
        self.permissions = permissions
        self.gatewayClient = gatewayClient
        self.publisher = publisher
        self.engine = engine
        self.controller = controller
        self.reviewWindows = reviewWindows
        self.settingsWindows = settingsWindows
        self.hud = hud
        self.firstRun = firstRun

        reviewWindows.onOpenSettings = { [weak settingsWindows] in
            settingsWindows?.show()
        }
    }

    /// Shared factory for the GUI app and headless CLI: one wiring point.
    public static func make(driverID: String = "mac", baseDirectory: URL? = nil) -> AppComposition {
        AppComposition(driverID: driverID, baseDirectory: baseDirectory)
    }

    /// Seeds the engine from persisted settings, then starts the driver so
    /// the ⌥Space hotkey works in every state (fix F1). Called once at app
    /// launch and on the CLI `record` path.
    public func boot() async {
        await engine.applySettings(settingsStore.load().engineSettings)
        await controller.bootstrap()
    }
}
