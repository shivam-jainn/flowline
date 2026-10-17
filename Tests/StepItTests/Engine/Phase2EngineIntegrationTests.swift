import XCTest
import StepItStorage
import StepItCaptureAPI
import StepItMacCapture
import StepItPublishing
import StepItAIGateway
import StepItPermissions
import StepItIR
import StepItPipeline
import StepItEngine
@testable import StepItCore

/// Phase 2 end-to-end matrix (T10): hotkeys, terminal `pwd`, pre-capture
/// password suppression, OCR redaction, drags, app switches and backwards
/// compatibility — all through the headless engine + `MockCaptureDriver`.
final class Phase2EngineIntegrationTests: XCTestCase {

    private var tempDirectory: URL!
    private var store: SessionStore!
    private var driver: MockCaptureDriver!
    private var clock: TestClock!
    private var engine: RecorderWorkflowEngine!

    private let clickPoint = Point2D(x: 120, y: 240)

    override func setUp() async throws {
        try await super.setUp()

        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StepItPhase2Tests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        store = SessionStore(customBaseDirectory: tempDirectory)
        driver = MockCaptureDriver()
        clock = TestClock()
        engine = RecorderWorkflowEngine(
            driver: driver,
            store: store,
            time: clock,
            config: RecorderWorkflowEngine.EngineConfig(typingDebounceInterval: 0.05)
        )
        try await engine.start()
    }

    override func tearDown() async throws {
        await engine?.shutdown()
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    // MARK: - Helpers

    @discardableResult
    private func startRecording(settings: StepItSettings? = nil) async throws -> StepSession {
        if let settings = settings {
            try store.saveSettings(settings)
        }
        let session = try await engine.startRecording()
        return try XCTUnwrap(session)
    }

    private func waitForSession(
        timeout: TimeInterval = 2.0,
        _ predicate: (StepSession?) -> Bool
    ) async -> StepSession? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let session = await engine.currentSnapshot().currentSession
            if predicate(session) { return session }
            if Date() >= deadline { return nil }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    @discardableResult
    private func expectSteps(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async throws -> StepSession {
        let session = await waitForSession { ($0?.steps.count ?? 0) == count }
        return try XCTUnwrap(session, "Expected \(count) step(s)", file: file, line: line)
    }

    private func waitForState(_ state: RecordingState, timeout: TimeInterval = 2.0) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await engine.currentSnapshot().state == state { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Expected state \(state)")
    }

    // MARK: - Hotkeys (E1)

    func testCommandShortcutsBecomeDiscreteKeyPressSteps() async throws {
        driver.focusedContextProvider = { RawEventFixtures.ctx(app: "Visual Studio Code", windowTitle: "main.swift") }
        _ = try await startRecording()

        driver.emitKey("s", code: 1, modifiers: [.command])
        driver.emitKey("P", code: 35, modifiers: [.command, .shift])
        driver.emitKey("v", code: 9, modifiers: [.command])

        let session = try await expectSteps(3)

        let save = session.steps[0]
        XCTAssertEqual(save.action, .keyPress)
        XCTAssertEqual(save.actionDescription, "Press ⌘S to save in Visual Studio Code")
        XCTAssertEqual(save.hotkeyCombo, "⌘S")
        XCTAssertEqual(save.assets.screenshot, "media/step_01.png")
        XCTAssertEqual(save.appName, "Visual Studio Code")

        let palette = session.steps[1]
        XCTAssertEqual(palette.actionDescription, "Press ⌘⇧P in Visual Studio Code")
        XCTAssertEqual(palette.hotkeyCombo, "⌘⇧P")

        let paste = session.steps[2]
        XCTAssertEqual(paste.actionDescription, "Press ⌘V in Visual Studio Code")
        XCTAssertEqual(paste.hotkeyCombo, "⌘V")
        XCTAssertEqual(driver.snapshotStepIndices, [1, 2, 3])
    }

    func testNavigationKeysBecomeStepsWithAppContext() async throws {
        driver.focusedContextProvider = { RawEventFixtures.ctx(app: "Notes", windowTitle: "Draft") }
        _ = try await startRecording()

        driver.emitKey("Escape", code: 53)
        driver.emitKey("ArrowDown", code: 125)

        let session = try await expectSteps(2)
        XCTAssertEqual(session.steps.map(\.actionDescription), [
            "Press Escape in Notes",
            "Press ArrowDown in Notes"
        ])
        XCTAssertNil(session.steps[0].hotkeyCombo, "Plain navigation keys are not modifier combos")
    }

    func testCommandCParsesAsKeyPressWhileControlCStaysTerminalInterrupt() async throws {
        driver.focusedContextProvider = { RawEventFixtures.ctx(app: "Safari", windowTitle: "Docs") }
        _ = try await startRecording()

        // ⌘C → discrete key press step.
        driver.emitKey("c", code: 8, modifiers: [.command])
        let session = try await expectSteps(1)
        XCTAssertEqual(session.steps[0].actionDescription, "Press ⌘C in Safari")

        // ⌃C → terminal interrupt marker through the aggregator (Phase 1 parity).
        driver.focusedContextProvider = { RawEventFixtures.ctx(app: "Ghostty", bundleId: "com.mitchellh.ghostty") }
        driver.emitKey("c", code: 8, modifiers: [.control])
        let interrupted = try await expectSteps(2)
        XCTAssertEqual(interrupted.steps[1].textBlob, "^C")
    }

    func testToggleHotkeyIsNeverRecordedAsAStep() async throws {
        _ = try await startRecording()

        driver.emitHotkey("⌥Space")
        await waitForState(.idle)

        let session = await engine.currentSnapshot().currentSession
        XCTAssertEqual(session?.steps.count ?? -1, 0, "⌥Space must toggle, never record (R3)")
    }

    func testToggleShortcutDeliveredAsAKeystrokeTogglesFromIdle() async throws {
        // Out-of-process drivers may surface the toggle as a plain keystroke;
        // it must behave exactly like `.hotkeyCombo` in every state.
        driver.emitKey(" ", code: 49, modifiers: [.option])
        await waitForState(.recording)

        let session = await engine.currentSnapshot().currentSession
        XCTAssertEqual(session?.steps.count ?? -1, 0)
    }

    func testSystemCombosAreConsumedAndNotRecorded() async throws {
        _ = try await startRecording()

        driver.emitKey("Tab", code: 48, modifiers: [.command])
        driver.emitKey(" ", code: 49, modifiers: [.command])

        try? await Task.sleep(nanoseconds: 80_000_000)
        let count = await engine.currentSnapshot().stepCount
        XCTAssertEqual(count, 0)
    }

    func testHotkeyFlushesPendingTypingFirst() async throws {
        driver.focusedContextProvider = { RawEventFixtures.ctx(app: "Ghostty", bundleId: "com.mitchellh.ghostty", windowTitle: "~/Code/stepit") }
        _ = try await startRecording()

        for event in RawEventFixtures.typing("git status", at: clickPoint) {
            driver.emit(event)
        }
        driver.emitKey("s", code: 1, modifiers: [.command])

        let session = try await expectSteps(2)
        XCTAssertEqual(session.steps.first?.textBlob, "git status")
        XCTAssertEqual(session.steps.last?.action, .keyPress)
        XCTAssertEqual(session.steps.map(\.index), [1, 2])
    }

    // MARK: - Terminal working directory (E2)

    func testTerminalCommandStepCarriesWorkingDirectory() async throws {
        driver.focusedContextProvider = {
            RawEventFixtures.ctx(app: "Ghostty", bundleId: "com.mitchellh.ghostty", windowTitle: "user@host: ~/Code/stepit")
        }
        driver.terminalInspector = TerminalContextInspector(
            appleScriptRunner: { _ in nil },
            processDirectoryResolver: { _ in nil },
            pidResolver: { _ in nil }
        )
        _ = try await startRecording()

        for event in RawEventFixtures.typing("git status", at: clickPoint) {
            driver.emit(event)
        }
        driver.emitKey("Return", code: 36)

        let session = try await expectSteps(1)
        let step = try XCTUnwrap(session.steps.first)

        XCTAssertEqual(step.workingDirectory, "~/Code/stepit")
        XCTAssertEqual(step.actionDescription, "Run \"git status\" in ~/Code/stepit (Ghostty)")
        XCTAssertEqual(step.action, .writeCode)
        XCTAssertEqual(step.codeLanguage, "bash")
        XCTAssertEqual(driver.terminalRequests.count, 1)
    }

    func testTerminalWithoutResolvablePwdKeepsLegacyDescription() async throws {
        driver.focusedContextProvider = {
            RawEventFixtures.ctx(app: "Terminal", bundleId: "com.apple.Terminal", windowTitle: "shivamjain — -zsh — 80x24")
        }
        driver.terminalInspector = TerminalContextInspector(
            appleScriptRunner: { _ in nil },
            processDirectoryResolver: { _ in nil },
            pidResolver: { _ in nil }
        )
        _ = try await startRecording()

        for event in RawEventFixtures.typing("ls -la", at: clickPoint) {
            driver.emit(event)
        }
        driver.emitKey("Return", code: 36)

        let session = try await expectSteps(1)
        XCTAssertNil(session.steps.first?.workingDirectory)
        XCTAssertEqual(session.steps.first?.actionDescription, "Run \"ls -la\" in Terminal")
    }

    func testDirectTerminalCommandEventsBecomeSteps() async throws {
        driver.focusedContextProvider = { RawEventFixtures.ctx(app: "Ghostty", windowTitle: "") }
        _ = try await startRecording()

        driver.emitTerminalCommand("npm start", workingDir: "~/api")

        let session = try await expectSteps(1)
        let step = try XCTUnwrap(session.steps.first)
        XCTAssertEqual(step.workingDirectory, "~/api")
        XCTAssertEqual(step.actionDescription, "Run \"npm start\" in ~/api (Ghostty)")
        XCTAssertTrue(step.isCode)
    }

    // MARK: - Pre-capture privacy (E3/T6)

    func testSecureFieldTypingNeverLeaksPlaintextAndBlackoutsTheSnapshot() async throws {
        let secureContext = RawEventFixtures.ctx(
            app: "Safari",
            windowTitle: "Sign In",
            role: "AXTextField",
            subrole: "AXSecureTextField",
            isSecure: true,
            bounds: ElementRect(x: 40, y: 40, width: 200, height: 30)
        )
        driver.focusedContextProvider = { secureContext }
        let session = try await startRecording()

        for event in RawEventFixtures.typing("SecretPassword123", at: clickPoint) {
            driver.emit(event)
        }
        driver.emitKey("Return", code: 36)

        let waited = try await expectSteps(1)
        let step = try XCTUnwrap(waited.steps.first)

        XCTAssertEqual(step.textBlob, String(repeating: "•", count: "SecretPassword123".count))
        XCTAssertFalse(step.actionDescription.contains("Secret"))
        XCTAssertNil(step.elementValue)

        // The secure-field region was blacked out before persistence.
        XCTAssertEqual(driver.obscuredRegions.count, 1)
        XCTAssertEqual(driver.obscuredRegions.first?.regions.first, secureContext.boundingBox)

        // Zero plaintext in the persisted session JSON.
        let jsonURL = tempDirectory
            .appendingPathComponent("Sessions")
            .appendingPathComponent(session.id)
            .appendingPathComponent("session.json")
        let json = try String(contentsOf: jsonURL, encoding: .utf8)
        XCTAssertFalse(json.contains("SecretPassword123"))
        XCTAssertTrue(json.contains("••"))
    }

    func testSecureFieldMaskingCanBeTurnedOffBySettings() async throws {
        let secureContext = RawEventFixtures.ctx(
            app: "Safari",
            windowTitle: "Sign In",
            role: "AXSecureTextField",
            isSecure: true,
            bounds: ElementRect(x: 40, y: 40, width: 200, height: 30)
        )
        driver.focusedContextProvider = { secureContext }

        var settings = StepItSettings()
        settings.privacy.maskSecureInputFields = false
        _ = try await startRecording(settings: settings)

        for event in RawEventFixtures.typing("hunter2", at: clickPoint) {
            driver.emit(event)
        }
        driver.emitKey("Return", code: 36)

        try? await Task.sleep(nanoseconds: 120_000_000)
        let count = await engine.currentSnapshot().stepCount
        XCTAssertEqual(count, 0, "With masking disabled, secure keystrokes are dropped entirely")
    }

    // MARK: - OCR redaction (E4/T7)

    func testRedactedClickStepKeepsOriginalForTheReviewToggle() async throws {
        driver.contextProvider = { _ in RawEventFixtures.ctx(app: "Safari", windowTitle: "Console", role: "AXStaticText") }
        driver.redactionProvider = { snapshot, _ in
            RedactionOutcome(
                snapshot: FrameSnapshot(pngData: Data("redacted".utf8), scale: snapshot.scale),
                isRedacted: true
            )
        }
        _ = try await startRecording()

        driver.emitClick(at: clickPoint)

        let session = try await expectSteps(1)
        let step = try XCTUnwrap(session.steps.first)

        XCTAssertEqual(step.isRedacted, true)
        XCTAssertEqual(step.assets.screenshot, "media/step_01.png")
        XCTAssertEqual(step.assets.screenshotOriginal, "media/step_01.original.png")
        XCTAssertEqual(driver.redactionRequests.count, 1)
    }

    func testRedactionRespectsDisabledPrivacySetting() async throws {
        var settings = StepItSettings()
        settings.privacy.enableOfflineOCRRedaction = false

        driver.contextProvider = { _ in RawEventFixtures.ctx(app: "Safari") }
        driver.redactionProvider = { snapshot, _ in
            XCTFail("The redaction facet must not be called when OCR redaction is disabled")
            return RedactionOutcome(snapshot: snapshot, isRedacted: false)
        }
        _ = try await startRecording(settings: settings)

        driver.emitClick(at: clickPoint)

        let session = try await expectSteps(1)
        XCTAssertNil(session.steps.first?.isRedacted)
        XCTAssertTrue(driver.redactionRequests.isEmpty)
    }

    func testSlowRedactionKeepsStepIndicesAndMediaNamesOrdered() async throws {
        driver.contextProvider = { _ in RawEventFixtures.ctx(app: "Safari") }
        // Simulate OCR latency: production must still serialize cleanly.
        driver.redactionProvider = { snapshot, _ in
            try? await Task.sleep(nanoseconds: 80_000_000)
            return RedactionOutcome(snapshot: snapshot, isRedacted: true)
        }
        _ = try await startRecording()

        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        driver.emitClick(at: Point2D(x: 10, y: 10), timestamp: start)
        driver.emitClick(at: Point2D(x: 300, y: 300), timestamp: start.addingTimeInterval(0.3))

        let session = try await expectSteps(2)
        XCTAssertEqual(session.steps.map(\.index), [1, 2])
        XCTAssertEqual(session.steps.map(\.assets.screenshot), ["media/step_01.png", "media/step_02.png"])
        XCTAssertEqual(session.steps.map(\.assets.screenshotOriginal), [
            "media/step_01.original.png",
            "media/step_02.original.png"
        ])
    }

    // MARK: - Drags & app switches (E5/T8)

    func testMouseDragBecomesAStep() async throws {
        driver.contextProvider = { _ in RawEventFixtures.ctx(app: "Finder", bundleId: "com.apple.finder") }
        _ = try await startRecording()

        driver.emitDrag(start: Point2D(x: 10, y: 10), end: Point2D(x: 300, y: 200))

        let session = try await expectSteps(1)
        let step = try XCTUnwrap(session.steps.first)
        XCTAssertEqual(step.action, .mouseDrag)
        XCTAssertEqual(step.actionDescription, "Drag from (10, 10) to (300, 200) in Finder")
        XCTAssertEqual(step.coordinates, ScreenCoordinates(x: 300, y: 200))
        XCTAssertEqual(step.assets.screenshot, "media/step_01.png")
    }

    func testAppSwitchUpdatesContextWithoutStepByDefault() async throws {
        driver.contextProvider = { _ in RawEventFixtures.ctx(app: "Finder") }
        _ = try await startRecording()

        driver.emitAppSwitch(bundleId: "com.tinyspeck.slackmacgap", appName: "Slack")
        driver.emitClick(at: clickPoint)

        let session = try await expectSteps(1)
        // One step: the click (no app switch step by default).
        XCTAssertEqual(session.steps.map(\.action), [.click])
    }

    func testAppSwitchStepsWhenEnabled() async throws {
        driver.contextProvider = { _ in RawEventFixtures.ctx(app: "Finder") }
        driver.focusedContextProvider = { RawEventFixtures.ctx(app: "Finder") }

        var settings = StepItSettings()
        settings.capture.recordAppSwitches = true
        _ = try await startRecording(settings: settings)

        driver.emitAppSwitch(bundleId: "com.tinyspeck.slackmacgap", appName: "Slack")
        driver.emitAppSwitch(bundleId: "com.microsoft.VSCode", appName: "Visual Studio Code")

        let session = try await expectSteps(2)
        XCTAssertEqual(session.steps.map(\.action), [.appSwitch, .appSwitch])
        XCTAssertEqual(session.steps.map(\.actionDescription), ["Switch to Slack", "Switch to Visual Studio Code"])
    }

    func testUnknownContextFallsBackToLastAppSwitch() async throws {
        // No AX provider → clicks resolve to .unknown; the app-switch context fills in.
        _ = try await startRecording()

        driver.emitAppSwitch(bundleId: "com.apple.Safari", appName: "Safari")
        driver.emitClick(at: clickPoint)

        let session = try await expectSteps(1)
        XCTAssertEqual(session.steps.first?.appName, "Safari")
    }

    // MARK: - Settings wiring (T9)

    func testRecordingStartPushesHotkeyPolicyToTheDriver() async throws {
        var settings = StepItSettings()
        settings.hotkeyCapture.captureNavigationKeys = false
        settings.hotkeyCapture.ignoredCombos = ["⌘⇧K"]
        settings.hotkeys.toggleRecording = "⌥ Space"
        _ = try await startRecording(settings: settings)

        XCTAssertEqual(driver.appliedHotkeySettings.last?.settings.captureNavigationKeys, false)
        XCTAssertEqual(driver.appliedHotkeySettings.last?.settings.ignoredCombos, ["⌘⇧K"])
        XCTAssertEqual(driver.appliedHotkeySettings.last?.toggleCombo, "⌥ Space")
    }

    func testApplySettingsUpdatesDriverAndEngineImmediately() async throws {
        _ = try await startRecording()

        var updated = StepItSettings()
        updated.hotkeyCapture.captureModifierShortcuts = false
        updated.privacy.enableOfflineOCRRedaction = false
        await engine.applySettings(updated)

        XCTAssertEqual(driver.appliedHotkeySettings.last?.settings.captureModifierShortcuts, false)

        // ⌘S is now dropped by the engine's recognizer too.
        driver.emitKey("s", code: 1, modifiers: [.command])
        try? await Task.sleep(nanoseconds: 80_000_000)
        let count = await engine.currentSnapshot().stepCount
        XCTAssertEqual(count, 0)

        // ⌃C keeps working as the terminal interrupt regardless of the gate.
        driver.emitKey("c", code: 8, modifiers: [.control])
        let interrupted = try await expectSteps(1)
        XCTAssertEqual(interrupted.steps.first?.textBlob, "^C")
    }

    // MARK: - Backwards compatibility (DoD #7)

    func testPhase1SessionJSONLoadsAndExportsWithoutNewFields() throws {
        let legacyJSON = """
        {
          "id": "sess_legacy",
          "startedAt": "2026-01-10T10:00:00Z",
          "endedAt": "2026-01-10T10:05:00Z",
          "title": "Legacy Workflow",
          "theme": "developer-dark",
          "mediaMode": "hybrid",
          "summary": null,
          "synthesizedMarkdown": null,
          "exports": {},
          "steps": [
            {
              "id": "legacy-step-1",
              "index": 1,
              "timestamp": "2026-01-10T10:00:05Z",
              "action": "write_code",
              "appName": "Ghostty",
              "windowTitle": "zsh",
              "elementRole": "AXTerminal",
              "actionDescription": "Run \\"git status\\" in Ghostty",
              "isCode": true,
              "codeLanguage": "bash",
              "assets": { "screenshot": "media/step_01.png" },
              "textBlob": "git status"
            }
          ]
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(StepSession.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(session.steps.count, 1)
        XCTAssertNil(session.steps[0].workingDirectory)
        XCTAssertNil(session.steps[0].hotkeyCombo)
        XCTAssertNil(session.steps[0].isRedacted)
        XCTAssertNil(session.steps[0].assets.screenshotOriginal)

        // Exports still render.
        let markdown = MarkdownExporter.shared.exportMarkdown(session: session)
        XCTAssertTrue(markdown.contains("Legacy Workflow"))

        let html = WebDocGenerator.shared.generateHTML(session: session)
        XCTAssertTrue(html.contains("Legacy Workflow"))
    }

    func testLegacySettingsJSONWithoutPhase2KeysDecodesWithDefaults() throws {
        let legacyJSON = """
        {
          "capture": {
            "mediaMode": "hybrid",
            "gifFps": 15,
            "clipDurationPreClickSec": 0.5,
            "clipDurationPostClickSec": 1.5,
            "highlightClicks": true,
            "highlightColorHex": "#EF4444",
            "highlightRadius": 28.0
          },
          "publishing": {
            "defaultTheme": "modern-minimal",
            "authorName": "",
            "companyName": "StepIt Docs",
            "enableInteractiveChecklists": true,
            "pdfPaperSize": "A4",
            "includeTimestamp": true
          },
          "gateway": {
            "provider": "openrouter",
            "baseURL": "https://openrouter.ai/api/v1",
            "apiKey": "",
            "model": "anthropic/claude-3.5-sonnet",
            "visionEnabled": true,
            "temperature": 0.2
          },
          "hotkeys": { "toggleRecording": "⌥ Space" }
        }
        """

        let settings = try JSONDecoder().decode(StepItSettings.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(settings.capture.mediaMode, .hybrid)
        XCTAssertFalse(settings.capture.recordAppSwitches, "Phase 2 default: app switches are opt-in")
        XCTAssertTrue(settings.privacy.maskSecureInputFields)
        XCTAssertTrue(settings.privacy.enableOfflineOCRRedaction)
        XCTAssertTrue(settings.hotkeyCapture.captureModifierShortcuts)
        XCTAssertTrue(settings.hotkeyCapture.captureNavigationKeys)
        XCTAssertTrue(settings.hotkeyCapture.ignoredCombos.isEmpty)
        XCTAssertEqual(settings.gestures.shakeAction, .pauseResume)
    }
}
