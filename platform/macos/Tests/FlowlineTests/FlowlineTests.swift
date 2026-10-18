import XCTest
import FlowlineStorage
import FlowlineCaptureAPI
import FlowlineMacCapture
import FlowlinePublishing
import FlowlineAIGateway
import FlowlinePermissions
import FlowlineIR
import FlowlinePipeline
import FlowlineEngine
import CoreGraphics
import AppKit

import FlowlineFixtures

final class FlowlineTests: XCTestCase {
    var tempDirectory: URL!
    var sessionStore: SessionStore!
    
    override func setUp() {
        super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("FlowlineTest_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        sessionStore = SessionStore(customBaseDirectory: tempDirectory)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }
    
    func testStepDescriptionSynthesis() {
        let desc1 = Step.synthesizeDefaultDescription(
            action: .click,
            elementTitle: "Submit Order",
            elementRole: "AXButton",
            appName: "CheckoutApp",
            windowTitle: "Cart Summary"
        )
        XCTAssertEqual(desc1, "Click \"Submit Order\" in Cart Summary")
        
        let desc2 = Step.synthesizeDefaultDescription(
            action: .rightClick,
            elementTitle: nil,
            elementRole: "AXMenuItem",
            appName: "Finder",
            windowTitle: ""
        )
        XCTAssertEqual(desc2, "Right-click menuitem in Finder")
    }
    
    func testSessionEncodingAndPersistence() throws {
        let step = Step(
            index: 1,
            action: .click,
            appName: "System Settings",
            windowTitle: "Privacy & Security",
            elementRole: "AXButton",
            elementTitle: "Advanced...",
            coordinates: ScreenCoordinates(x: 420, y: 310),
            actionDescription: "Click \"Advanced...\" in Privacy & Security"
        )
        
        let session = StepSession(
            id: "sess_unit_test",
            title: "Test Workflow",
            theme: .developerDark,
            mediaMode: .hybrid,
            steps: [step]
        )
        
        try sessionStore.saveSession(session)
        
        let loaded = try sessionStore.loadSession(id: "sess_unit_test")
        XCTAssertEqual(loaded.id, "sess_unit_test")
        XCTAssertEqual(loaded.title, "Test Workflow")
        XCTAssertEqual(loaded.theme, .developerDark)
        XCTAssertEqual(loaded.steps.count, 1)
        XCTAssertEqual(loaded.steps.first?.elementTitle, "Advanced...")
        XCTAssertEqual(loaded.steps.first?.coordinates?.x, 420)
    }
    
    func testWebDocGeneratorHTML() {
        let step = Step(
            index: 1,
            action: .click,
            appName: "Terminal",
            windowTitle: "zsh",
            elementRole: "AXTextField",
            elementTitle: "git status",
            actionDescription: "Check git status in Terminal",
            userNotes: "Run this before pushing.",
            assets: MediaAssets(screenshot: "media/step_01.png", gif: "media/step_01.gif")
        )
        
        let session = StepSession(
            id: "sess_web_test",
            title: "Git Workflow Guide",
            theme: .modernMinimal,
            mediaMode: .hybrid,
            steps: [step]
        )
        
        let html = WebDocGenerator.shared.generateHTML(session: session)
        
        XCTAssertTrue(html.contains("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("Git Workflow Guide"))
        XCTAssertTrue(html.contains("Check git status in Terminal"))
        XCTAssertTrue(html.contains("media/step_01.png"))
        XCTAssertTrue(html.contains("media/step_01.gif"))
        XCTAssertTrue(html.contains("Checklist Mode"))
        XCTAssertTrue(html.contains("@media print"))
    }
    
    func testMarkdownExporter() {
        let step = Step(
            index: 1,
            action: .click,
            appName: "Safari",
            windowTitle: "GitHub",
            elementRole: "AXButton",
            elementTitle: "Merge pull request",
            actionDescription: "Merge PR on GitHub",
            assets: MediaAssets(screenshot: "media/step_01.png")
        )
        
        let session = StepSession(
            id: "sess_md_test",
            title: "PR Merge Procedure",
            steps: [step]
        )
        
        let md = MarkdownExporter.shared.exportMarkdown(session: session, relativeAssetPrefix: "")
        XCTAssertTrue(md.contains("# PR Merge Procedure"))
        XCTAssertTrue(md.contains("### Step 1: Merge PR on GitHub"))
        XCTAssertTrue(md.contains("![Merge PR on GitHub](media/step_01.png)"))
    }
    
    func testMultimodalPayloadBuilder() {
        let step = Step(
            index: 1,
            action: .click,
            appName: "Finder",
            actionDescription: "Open folder"
        )
        let session = StepSession(
            id: "sess_payload",
            title: "Open Folder",
            steps: [step]
        )
        
        let settings = GatewaySettings(
            provider: .openRouter,
            baseURL: "https://openrouter.ai/api/v1",
            apiKey: "test_key",
            model: "anthropic/claude-3.5-sonnet",
            visionEnabled: false
        )
        
        let request = MultimodalPayloadBuilder.shared.buildRequest(
            session: session,
            settings: settings,
            style: .sopGuide
        )
        
        XCTAssertEqual(request.model, "anthropic/claude-3.5-sonnet")
        XCTAssertEqual(request.messages.count, 2)
        XCTAssertEqual(request.messages[0].role, "system")
        XCTAssertEqual(request.messages[1].role, "user")
    }
    
    func testGIFCreation() {
        let width = 64
        let height = 64
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        var frames: [CGImage] = []
        for i in 0..<3 {
            let ctx = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )!
            ctx.setFillColor(NSColor(srgbRed: CGFloat(i) * 0.3, green: 0.5, blue: 0.8, alpha: 1.0).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            frames.append(ctx.makeImage()!)
        }
        
        let gifData = MicroClipRecorder.shared.createGIF(from: frames, fps: 10)
        XCTAssertNotNil(gifData)
        XCTAssertTrue((gifData?.count ?? 0) > 100)
    }
    
    func testPlaygroundPagesIntegrity() throws {
        let webDir = try XCTUnwrap(
            FixtureLocator.playgroundWebDirectory(),
            "shared/fixtures/playground-web should be discoverable from the repository root"
        )
        
        let expectedPages = [
            "index.html",
            "page1_onboarding.html",
            "page2_checkout.html",
            "page3_analytics.html",
            "page4_cloud.html",
            "page5_media.html",
            "page6_apigateway.html",
            "page7_support.html",
            "page8_survey.html",
            "page9_datagrid.html",
            "page10_diagnostics.html"
        ]
        
        for page in expectedPages {
            let fileURL = webDir.appendingPathComponent(page)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "Missing page: \(page)")
            
            if let content = try? String(contentsOf: fileURL) {
                XCTAssertTrue(content.contains("<button"), "Page \(page) should contain buttons")
                XCTAssertTrue(content.contains("styles.css"), "Page \(page) should link styles.css")
            }
        }
    }
    
    func testTextTypingAggregationAndLanguageDetection() {
        let classifier = KeystrokeClassifier()
        
        // Test VS Code detection
        XCTAssertTrue(classifier.isCodeEnvironment(appName: "Visual Studio Code", bundleId: "com.microsoft.VSCode", windowTitle: "main.py"))
        XCTAssertTrue(classifier.isCodeEnvironment(appName: "Terminal", bundleId: "com.apple.Terminal", windowTitle: "zsh"))
        XCTAssertTrue(classifier.isCodeEnvironment(appName: "Cursor", bundleId: "com.todesktop.230313mzl4w4u92", windowTitle: "Server.swift"))
        XCTAssertFalse(classifier.isCodeEnvironment(appName: "Finder", bundleId: "com.apple.finder", windowTitle: "Documents"))
        
        // Test language detection
        XCTAssertEqual(classifier.detectLanguage(appName: "Visual Studio Code", windowTitle: "workflow.py", text: "def foo(): pass"), "python")
        XCTAssertEqual(classifier.detectLanguage(appName: "Xcode", windowTitle: "App.swift", text: "import SwiftUI"), "swift")
        XCTAssertEqual(classifier.detectLanguage(appName: "Terminal", windowTitle: "bash", text: "npm install"), "bash")
        XCTAssertEqual(classifier.detectLanguage(appName: "Cursor", windowTitle: "index.ts", text: "const x = 1;"), "typescript")
    }
    
    func testFastForwardTypingAndCodeBlobExport() {
        let codeSnippet = """
        import SwiftUI

        struct StepView: View {
            var body: some View {
                Text("Flowline Fast-Forward")
            }
        }
        """
        
        let step = Step(
            index: 1,
            action: .writeCode,
            appName: "Visual Studio Code",
            windowTitle: "StepView.swift",
            elementRole: "AXCodeEditor",
            actionDescription: "Write Swift UI component in VS Code",
            textBlob: codeSnippet,
            isCode: true,
            codeLanguage: "swift",
            assets: MediaAssets(screenshot: "media/step_01.png", gif: "media/step_01.gif")
        )
        
        let session = StepSession(
            id: "sess_fastforward_test",
            title: "Code Capture Session",
            steps: [step]
        )
        
        // Verify Web HTML output includes code blob container and copy button
        let html = WebDocGenerator.shared.generateHTML(session: session)
        XCTAssertTrue(html.contains("code-blob-container"))
        XCTAssertTrue(html.contains("copy-code-btn"))
        XCTAssertTrue(html.contains("copyText"))
        XCTAssertTrue(html.contains("Copy"))
        XCTAssertTrue(html.contains("Flowline Fast-Forward"))
        XCTAssertTrue(html.contains("swift"))
        
        // Verify Markdown exporter includes fenced code block
        let md = MarkdownExporter.shared.exportMarkdown(session: session)
        XCTAssertTrue(md.contains("```swift"))
        XCTAssertTrue(md.contains("struct StepView: View"))
        XCTAssertTrue(md.contains("```"))
    }
    
    func testGestureSettingsEncodingAndDefaults() throws {
        var settings = FlowlineSettings()
        XCTAssertTrue(settings.gestures.shakeToPauseEnabled)
        XCTAssertEqual(settings.gestures.shakeSensitivity, .medium)
        XCTAssertEqual(settings.gestures.shakeAction, .pauseResume)
        XCTAssertTrue(settings.gestures.hotCorners.enabled)
        XCTAssertEqual(settings.gestures.hotCorners.topRight, .pauseResume)
        XCTAssertEqual(settings.gestures.hotCorners.bottomRight, .stopAndReview)
        XCTAssertEqual(settings.gestures.middleClickAction, .addCheckpoint)
        XCTAssertEqual(settings.gestures.doubleRightClickAction, .discardLastStep)
        
        // Mutate and test encoding
        settings.gestures.shakeSensitivity = .high
        settings.gestures.hotCorners.topLeft = .captureSnapshot
        settings.gestures.longPressDurationSec = 1.2
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(settings)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FlowlineSettings.self, from: data)
        
        XCTAssertEqual(decoded.gestures.shakeSensitivity, .high)
        XCTAssertEqual(decoded.gestures.hotCorners.topLeft, .captureSnapshot)
        XCTAssertEqual(decoded.gestures.longPressDurationSec, 1.2)
    }
    
    func testSmartGestureDetectorDispatch() {
        var gestureSettings = GestureSettings()
        gestureSettings.middleClickAction = .addCheckpoint
        gestureSettings.doubleRightClickAction = .discardLastStep
        
        let detector = SmartGestureDetector(settings: gestureSettings)
        
        var detectedNotice: GestureEventNotice?
        let expectation = self.expectation(description: "Middle-click gesture detected")
        
        detector.onGestureDetected = { notice in
            detectedNotice = notice
            expectation.fulfill()
        }
        
        // Simulate middle-click
        detector.handleMouseDown(button: .middle, at: CGPoint(x: 200, y: 300))
        
        waitForExpectations(timeout: 1.0)
        
        XCTAssertNotNil(detectedNotice)
        XCTAssertEqual(detectedNotice?.action, .addCheckpoint)
        XCTAssertTrue(detectedNotice?.gestureName.contains("Middle-Click") ?? false)
    }
    
    func testReturnKeyImmediatelyFinalizesCommand() async {
        let aggregator = TypingBatchAggregator(
            configuration: .init(debounceInterval: 1.0),
            contextProvider: {
                RawElementContext(
                    appName: "Terminal",
                    bundleIdentifier: "com.apple.Terminal",
                    windowTitle: "zsh"
                )
            }
        )
        let box = TypingResultBox()
        let exp = expectation(description: "Return key immediately commits command")
        
        aggregator.onBatchCompleted = { result in
            box.append(result)
            exp.fulfill()
        }
        
        for character in "git status" {
            await aggregator.append(char: String(character), at: Point2D(x: 100, y: 100))
        }
        
        // Return key pressed
        await aggregator.handleReturn(at: Point2D(x: 100, y: 100))
        
        await fulfillment(of: [exp], timeout: 1.0)
        
        XCTAssertNotNil(box.last)
        XCTAssertEqual(box.last?.textBlob, "git status")
        XCTAssertEqual(box.last?.classification, .terminal)
        XCTAssertFalse(aggregator.hasPendingText)
    }
    
    func testBackspaceAndControlCInTypingAggregator() async {
        let aggregator = TypingBatchAggregator(
            configuration: .init(debounceInterval: 1.0),
            contextProvider: {
                RawElementContext(
                    appName: "Terminal",
                    bundleIdentifier: "com.apple.Terminal",
                    windowTitle: "zsh"
                )
            }
        )
        let box = TypingResultBox()
        let exp = expectation(description: "Backspace edits buffer and Ctrl+C commits")
        
        aggregator.onBatchCompleted = { result in
            box.append(result)
            exp.fulfill()
        }
        
        // Type "npm run devv" then backspace
        for character in "npm x" {
            await aggregator.append(char: String(character), at: Point2D(x: 50, y: 50))
        }
        await aggregator.handleBackspace(at: Point2D(x: 50, y: 50))
        await aggregator.handleControlC(at: Point2D(x: 50, y: 50))
        
        await fulfillment(of: [exp], timeout: 1.0)
        
        XCTAssertNotNil(box.last)
        XCTAssertEqual(box.last?.textBlob, "npm  ^C")
    }
    
    func testNotificationDescriptionSynthesis() {
        let desc = Step.synthesizeDefaultDescription(
            action: .click,
            elementTitle: "Claude Code Prototype",
            elementRole: "AXNotificationCenter",
            appName: "UserNotificationCenter",
            windowTitle: ""
        )
        XCTAssertEqual(desc, "Click notification \"Claude Code Prototype\"")
        
        let descWithoutTitle = Step.synthesizeDefaultDescription(
            action: .click,
            elementTitle: nil,
            elementRole: "AXDialog",
            appName: "UserNotificationCenter",
            windowTitle: ""
        )
        XCTAssertEqual(descWithoutTitle, "Click system notification")
    }
    
    func testThreeThemeSelectorAndEnterpriseSOPVariables() {
        let session = StepSession(
            title: "Theme Test Guide",
            theme: .enterpriseSop,
            mediaMode: .hybrid,
            steps: [
                Step(index: 1, action: .click, appName: "Terminal", actionDescription: "Run command")
            ]
        )
        
        let html = WebDocGenerator.shared.generateHTML(session: session)
        
        // Verify 3-theme selector dropdown exists in header
        XCTAssertTrue(html.contains("id=\"theme-selector-btn\""))
        XCTAssertTrue(html.contains("id=\"theme-dropdown-menu\""))
        XCTAssertTrue(html.contains("data-theme-val=\"modern-minimal\""))
        XCTAssertTrue(html.contains("data-theme-val=\"developer-dark\""))
        XCTAssertTrue(html.contains("data-theme-val=\"enterprise-sop\""))
        
        // Verify Enterprise SOP CSS variables
        XCTAssertTrue(html.contains("[data-theme=\"enterprise-sop\"]"))
        XCTAssertTrue(html.contains("--bg: #fafaf8;"))
        XCTAssertTrue(html.contains("--primary: #8b5a2b;"))
    }
}

