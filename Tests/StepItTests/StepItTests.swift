import XCTest
import CoreGraphics
import AppKit
@testable import StepItCore

final class StepItTests: XCTestCase {
    var tempDirectory: URL!
    var sessionStore: SessionStore!
    
    override func setUp() {
        super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("StepItTest_\(UUID().uuidString)")
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
        XCTAssertTrue(md.contains("# ⚡️ PR Merge Procedure"))
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
    
    func testPlaygroundPagesIntegrity() {
        let currentDir = FileManager.default.currentDirectoryPath
        let webDir = URL(fileURLWithPath: currentDir).appendingPathComponent("Playground/web")
        
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
        let aggregator = TextTypingAggregator()
        
        // Test VS Code detection
        XCTAssertTrue(aggregator.isCodeEnvironment(appName: "Visual Studio Code", bundleId: "com.microsoft.VSCode", windowTitle: "main.py"))
        XCTAssertTrue(aggregator.isCodeEnvironment(appName: "Terminal", bundleId: "com.apple.Terminal", windowTitle: "zsh"))
        XCTAssertTrue(aggregator.isCodeEnvironment(appName: "Cursor", bundleId: "com.todesktop.230313mzl4w4u92", windowTitle: "Server.swift"))
        XCTAssertFalse(aggregator.isCodeEnvironment(appName: "Finder", bundleId: "com.apple.finder", windowTitle: "Documents"))
        
        // Test language detection
        XCTAssertEqual(aggregator.detectLanguage(appName: "Visual Studio Code", windowTitle: "workflow.py", text: "def foo(): pass"), "python")
        XCTAssertEqual(aggregator.detectLanguage(appName: "Xcode", windowTitle: "App.swift", text: "import SwiftUI"), "swift")
        XCTAssertEqual(aggregator.detectLanguage(appName: "Terminal", windowTitle: "bash", text: "npm install"), "bash")
        XCTAssertEqual(aggregator.detectLanguage(appName: "Cursor", windowTitle: "index.ts", text: "const x = 1;"), "typescript")
    }
    
    func testFastForwardTypingAndCodeBlobExport() {
        let codeSnippet = """
        import SwiftUI

        struct StepView: View {
            var body: some View {
                Text("StepIt Fast-Forward")
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
        XCTAssertTrue(html.contains("Copy to Clipboard"))
        XCTAssertTrue(html.contains("StepIt Fast-Forward"))
        XCTAssertTrue(html.contains("swift"))
        
        // Verify Markdown exporter includes fenced code block
        let md = MarkdownExporter.shared.exportMarkdown(session: session)
        XCTAssertTrue(md.contains("```swift"))
        XCTAssertTrue(md.contains("struct StepView: View"))
        XCTAssertTrue(md.contains("```"))
    }
    
    func testGestureSettingsEncodingAndDefaults() throws {
        var settings = StepItSettings()
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
        let decoded = try decoder.decode(StepItSettings.self, from: data)
        
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
        
        // Simulate middle-click (buttonNumber 2)
        detector.handleMouseDown(type: .otherMouseDown, buttonNumber: 2, at: CGPoint(x: 200, y: 300))
        
        waitForExpectations(timeout: 1.0)
        
        XCTAssertNotNil(detectedNotice)
        XCTAssertEqual(detectedNotice?.action, .addCheckpoint)
        XCTAssertTrue(detectedNotice?.gestureName.contains("Middle-Click") ?? false)
    }
}


