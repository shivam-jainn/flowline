import XCTest
import FlowlineStorage
import FlowlineCaptureAPI
import FlowlinePublishing
import FlowlineAIGateway
import FlowlineIR
import FlowlinePipeline
import FlowlineEngine
import FlowlineFixtures

/// R/M1-07: surface composition proof.
///
/// The executable target (`Flowline`: WorkflowController call sites, CLI
/// slices, `AppComposition`) cannot be imported by SwiftPM test targets, so
/// this suite exercises the exact module seams the composition root wires:
/// injected engine/controller assembly over mock + noop doubles, the three
/// registries, store-injected publishing, the gateway client and the split
/// settings homes. `swift build` separately proves the app target compiles
/// against the same constructors.
final class PhaseR07SurfaceTests: XCTestCase {

    private var tempDirectory: URL!
    private var store: SessionStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FlowlinePhaseR07_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        store = SessionStore(customBaseDirectory: tempDirectory)
    }

    override func tearDown() async throws {
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    // MARK: - Controller assembles over injected doubles (no concretes)

    @MainActor
    func testWorkflowControllerAssemblesOverMockDriver() async throws {
        let driver = MockCaptureDriver()
        let engine = RecorderWorkflowEngine(driver: driver, store: store)
        let controller = WorkflowController(engine: engine)

        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(controller.stepCount, 0)
        XCTAssertNil(controller.currentSession)

        await controller.bootstrap()
        await controller.startRecording(title: "R07 probe")
        XCTAssertEqual(controller.stepCount, 0)
        let session = await controller.stopRecording()
        XCTAssertNotNil(session)
        await controller.shutdown()
    }

    @MainActor
    func testWorkflowControllerAssemblesOverNoopDriver() async {
        let engine = RecorderWorkflowEngine(driver: NoopDriver(), store: store)
        let controller = WorkflowController(engine: engine)
        XCTAssertEqual(controller.state, .idle)

        var reviewed: StepSession?
        let reviewing = WorkflowController(engine: engine, onReview: { reviewed = $0 })
        XCTAssertNil(reviewed)
        _ = reviewing
        await controller.shutdown()
    }

    func testEngineAcceptsAnySessionStoreProtocol() async throws {
        let storeBox: any SessionStoreProtocol = store
        let engine = RecorderWorkflowEngine(driver: MockCaptureDriver(), store: storeBox)
        try await engine.start()
        let session = try await engine.startRecording(title: "protocol probe")
        XCTAssertNotNil(session)
        _ = await engine.stopRecording()
        await engine.shutdown()
    }

    // MARK: - Narrow + compat settings reach the driver

    func testNarrowEngineSettingsReachTheDriver() async throws {
        let driver = MockCaptureDriver()
        let engine = RecorderWorkflowEngine(driver: driver, store: store)
        try await engine.start()

        var narrow = EngineSettings()
        narrow.hotkeyCapture.captureNavigationKeys = false
        narrow.hotkeys.toggleRecording = "⌥ Space"
        await engine.applySettings(narrow)

        XCTAssertEqual(driver.appliedHotkeySettings.last?.settings.captureNavigationKeys, false)
        XCTAssertEqual(driver.appliedHotkeySettings.last?.toggleCombo, "⌥ Space")
        await engine.shutdown()
    }

    func testFullAggregateProjectsToEngineSettings() async throws {
        let driver = MockCaptureDriver()
        let engine = RecorderWorkflowEngine(driver: driver, store: store)
        try await engine.start()

        var full = FlowlineSettings()
        full.hotkeyCapture.captureModifierShortcuts = false
        await engine.applySettings(full) // compat overload → narrow projection

        XCTAssertEqual(driver.appliedHotkeySettings.last?.settings.captureModifierShortcuts, false)
        XCTAssertEqual(full.engineSettings.hotkeyCapture.captureModifierShortcuts, false)
        await engine.shutdown()
    }

    // MARK: - Registries register + resolve with versioned manifests

    func testDriverRegistryResolvesMockAndNoop() {
        let registry = DriverRegistry()
        registry.register(
            manifest: PluginManifest(id: "mock", version: "1.0.0", minimumHostVersion: "r-m1"),
            factory: { MockCaptureDriver() }
        )
        registry.register(
            manifest: PluginManifest(id: "noop", version: "1.0.0", minimumHostVersion: "r-m1"),
            factory: { NoopDriver() }
        )

        XCTAssertEqual(registry.registeredIDs, ["mock", "noop"])
        XCTAssertEqual(registry.manifest(id: "mock")?.version, "1.0.0")

        let mock = registry.resolve(id: "mock") as? any CaptureDriver
        XCTAssertEqual(mock?.platformIdentifier, "mock")
        let noop = registry.resolve(id: "noop") as? any CaptureDriver
        XCTAssertEqual(noop?.platformIdentifier, "noop")
        XCTAssertNil(registry.resolve(id: "mac"), "Nothing registered under mac here")
    }

    func testExporterRegistryRoundTripsStubExporter() throws {
        let registry = ExporterRegistry()
        registry.register(
            manifest: PluginManifest(id: "stub-md", version: "1.0.0", minimumHostVersion: "r-m1"),
            factory: { StubSessionExporter() }
        )
        let exporter = registry.resolve(id: "stub-md") as? any SessionExporter
        XCTAssertEqual(exporter?.exporterID, "stub-md")

        let outDir = tempDirectory.appendingPathComponent("stub-export", isDirectory: true)
        let session = StepSession(title: "Stub Export", steps: [])
        let artifact = try exporter?.export(session: session, to: outDir)
        XCTAssertEqual(artifact?.mimeType, "text/plain")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outDir.appendingPathComponent("stub.txt").path))
    }

    func testProviderRegistryRoundTripsStubProvider() async throws {
        let registry = ProviderRegistry()
        registry.register(
            manifest: PluginManifest(id: "stub-ai", version: "1.0.0", minimumHostVersion: "r-m1"),
            factory: { StubGatewayProvider() }
        )
        let provider = registry.resolve(id: "stub-ai") as? any GatewayProvider
        XCTAssertEqual(provider?.providerID, "stub-ai")

        let response = try await provider?.complete(request: GatewayRequest(prompt: "hi", model: "stub"))
        XCTAssertEqual(response?.text, "stub:hi")
    }

    // MARK: - Store-injected publishing works with doubles

    func testPublishingCoordinatorExportsWithInjectedStoreAndOpener() throws {
        let opener = StubURLOpener()
        let coordinator = PublishingCoordinator(store: store, urlOpener: opener)

        let session = StepSession(title: "R07 Export", steps: [])
        try store.saveSession(session)

        let webURL = try coordinator.exportWeb(session: session, publishing: PublishingSettings())
        XCTAssertTrue(FileManager.default.fileExists(atPath: webURL.path))

        let mdURL = try coordinator.exportMarkdown(session: session)
        XCTAssertTrue(FileManager.default.fileExists(atPath: mdURL.path))

        coordinator.openInBrowser(url: webURL)
        coordinator.revealInFinder(url: mdURL)
        XCTAssertEqual(opener.opened, [webURL])
        XCTAssertEqual(opener.revealed, [mdURL])
    }

    func testGatewayClientConstructsWithInjectedSession() {
        let client = AIGatewayClient(urlSession: .shared)
        XCTAssertNotNil(client)
    }

    // MARK: - Settings defaults (opt-in flags stay off)

    func testOptInCaptureDefaultsStayOff() {
        // No donation/telemetry flag exists anywhere in the settings surface;
        // the tracked opt-in default is `recordAppSwitches == false`.
        XCTAssertFalse(
            FlowlineSettings().capture.recordAppSwitches,
            "App-switch steps are opt-in and must stay off by default"
        )
        XCTAssertFalse(CaptureSettings().recordAppSwitches)
        XCTAssertEqual(FlowlineSettings().gateway.provider, .openRouter)
        XCTAssertTrue(FlowlineSettings().gateway.visionEnabled)
        XCTAssertTrue(FlowlineSettings().privacy.maskSecureInputFields)
        XCTAssertEqual(FlowlineSettings().gestures.shakeSensitivity, .medium)
    }
}

// MARK: - Test doubles (registry seams)

private final class StubSessionExporter: SessionExporter, @unchecked Sendable {
    let exporterID = "stub-md"

    func export(session: Any, to directory: URL) throws -> ExportArtifact {
        guard session is StepSession else {
            throw NSError(domain: "StubSessionExporter", code: 400)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("stub.txt")
        try "stub".write(to: url, atomically: true, encoding: .utf8)
        return ExportArtifact(url: url, relativePath: "stub.txt", mimeType: "text/plain")
    }
}

private final class StubGatewayProvider: GatewayProvider, @unchecked Sendable {
    let providerID = "stub-ai"

    func complete(request: GatewayRequest) async throws -> GatewayResponse {
        GatewayResponse(text: "stub:\(request.prompt)")
    }
}

private final class StubURLOpener: URLOpener, @unchecked Sendable {
    private let lock = NSLock()
    private var _opened: [URL] = []
    private var _revealed: [URL] = []

    var opened: [URL] { lock.withLock { _opened } }
    var revealed: [URL] { lock.withLock { _revealed } }

    func open(_ url: URL) { lock.withLock { _opened.append(url) } }
    func revealInFinder(_ url: URL) { lock.withLock { _revealed.append(url) } }
}
