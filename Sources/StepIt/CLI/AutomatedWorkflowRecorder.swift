import Foundation
import AppKit
import CoreGraphics
import StepItCore

public final class AutomatedWorkflowRecorder: @unchecked Sendable {
    public static let shared = AutomatedWorkflowRecorder()
    
    public init() {}
    
    @MainActor
    public func recordPlaygroundWorkflow(openInBrowserAfter: Bool = true) async throws -> StepSession {
        print("⚡️ [StepIt Automate] Initializing Automated Workflow Recording across Playground...")
        
        let sessionId = "sess_playground_tour_\(Int(Date().timeIntervalSince1970))"
        let sessionDir = SessionStore.shared.sessionDirectory(for: sessionId)
        let mediaDir = SessionStore.shared.mediaDirectory(for: sessionId)
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        
        // Define 6 comprehensive steps simulating real user interactions across pages, VS Code, and Terminal:
        let scenarioSteps: [(
            title: String,
            page: String,
            appName: String,
            windowTitle: String,
            role: String,
            elementTitle: String,
            coords: CGPoint,
            notes: String,
            action: ActionType,
            textBlob: String?,
            isCode: Bool,
            language: String?
        )] = [
            (
                title: "Register Enterprise Team Lead Account",
                page: "page1_onboarding.html",
                appName: "Safari",
                windowTitle: "Page 1: Auth & User Onboarding — StepIt Playground",
                role: "AXButton",
                elementTitle: "Create Account →",
                coords: CGPoint(x: 340, y: 520),
                notes: "Input user credentials and verify password strength bar reflects 'Very Strong'.",
                action: .click,
                textBlob: nil,
                isCode: false,
                language: nil
            ),
            (
                title: "Adjust Team Seat Allocation Slider",
                page: "page1_onboarding.html",
                appName: "Safari",
                windowTitle: "Page 1: Auth & User Onboarding — StepIt Playground",
                role: "AXSlider",
                elementTitle: "Team Size Capacity: 48 members",
                coords: CGPoint(x: 480, y: 390),
                notes: "Drag slider thumb rightward to increase workspace seat limit.",
                action: .click,
                textBlob: nil,
                isCode: false,
                language: nil
            ),
            (
                title: "Increase Item Quantity in Shopping Cart",
                page: "page2_checkout.html",
                appName: "Safari",
                windowTitle: "Page 2: E-Commerce Checkout — StepIt Playground",
                role: "AXButton",
                elementTitle: "+ (Add Quantity)",
                coords: CGPoint(x: 520, y: 280),
                notes: "Click '+' stepper button to double order quantity for Mechanical Keyboards.",
                action: .click,
                textBlob: nil,
                isCode: false,
                language: nil
            ),
            (
                title: "Write Backend Fast-Forward Ingestion API in VS Code",
                page: "Visual Studio Code",
                appName: "Visual Studio Code",
                windowTitle: "workflow_router.py — stepit-core — Visual Studio Code",
                role: "AXCodeEditor",
                elementTitle: "workflow_router.py",
                coords: CGPoint(x: 550, y: 320),
                notes: "Fast-forward captured typing in VS Code editor. 1-click copyable to clipboard.",
                action: .writeCode,
                textBlob: """
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title="StepIt Fast-Forward Capture API")

class WorkflowStep(BaseModel):
    index: int
    action: str
    text_blob: str | None = None
    coords: dict[str, float]

@app.post("/v1/record/step")
async def record_workflow_step(step: WorkflowStep):
    print(f"Captured {step.action} step #{step.index}")
    return {"status": "persisted", "step_id": f"stp_{step.index}"}
""",
                isCode: true,
                language: "python"
            ),
            (
                title: "Run Database Migration & Automated Test Suite in Terminal",
                page: "Terminal",
                appName: "Terminal",
                windowTitle: "Terminal — zsh — 90×30",
                role: "AXTextField",
                elementTitle: "pytest tests/ -v && swift run stepit export",
                coords: CGPoint(x: 420, y: 240),
                notes: "Execute automated tests and export publishing bundle.",
                action: .typing,
                textBlob: "pytest tests/test_capture.py -v && swift run stepit export sess_playground",
                isCode: true,
                language: "bash"
            ),
            (
                title: "Confirm Cloud Cluster Deployment",
                page: "page4_cloud.html",
                appName: "Safari",
                windowTitle: "Page 4: Cloud Server Provisioning — StepIt Playground",
                role: "AXButton",
                elementTitle: "🚀 Provision Cloud Instance",
                coords: CGPoint(x: 720, y: 620),
                notes: "Submit deployment transaction to initialize regional data center VMs.",
                action: .click,
                textBlob: nil,
                isCode: false,
                language: nil
            )
        ]
        
        var recordedSteps: [Step] = []
        
        for (index, item) in scenarioSteps.enumerated() {
            let stepNum = index + 1
            print("  📸 Recording Step \(stepNum)/\(scenarioSteps.count): \(item.title)...")
            
            // 1. Generate realistic Retina snapshot with concentric glowing highlight ring and numbered badge
            let snapshotImage = generateMockPageCapture(
                pageName: item.page,
                title: item.title,
                targetRole: item.role,
                targetTitle: item.elementTitle,
                highlightPoint: item.coords,
                stepIndex: stepNum
            )
            
            let pngData = ScreenRecorder.shared.imageToPNGData(snapshotImage)!
            let pngName = String(format: "step_%02d.png", stepNum)
            let screenshotRel = try SessionStore.shared.saveMedia(data: pngData, sessionID: sessionId, filename: pngName)
            
            // 2. Generate animated looping GIF snippet (fast-forward if typing/code)
            let gifData = item.action == .typing || item.action == .writeCode
                ? generateMockFastForwardTypingGIF(baseImage: snapshotImage, clickPoint: item.coords)
                : generateMockAnimatedGIF(baseImage: snapshotImage, clickPoint: item.coords)
            let gifName = String(format: "step_%02d.gif", stepNum)
            let gifRel = try SessionStore.shared.saveMedia(data: gifData, sessionID: sessionId, filename: gifName)
            
            let step = Step(
                id: UUID().uuidString,
                index: stepNum,
                timestamp: Date().addingTimeInterval(Double(index * 12)),
                action: item.action,
                appName: item.appName,
                bundleIdentifier: item.appName == "Visual Studio Code" ? "com.microsoft.VSCode" : (item.appName == "Terminal" ? "com.apple.Terminal" : "com.apple.Safari"),
                windowTitle: item.windowTitle,
                elementRole: item.role,
                elementTitle: item.elementTitle,
                coordinates: ScreenCoordinates(x: Double(item.coords.x), y: Double(item.coords.y)),
                actionDescription: item.title,
                userNotes: item.notes,
                textBlob: item.textBlob,
                isCode: item.isCode,
                codeLanguage: item.language,
                assets: MediaAssets(screenshot: screenshotRel, gif: gifRel)
            )
            
            recordedSteps.append(step)
        }
        
        let synthesizedDoc = """
# ⚡️ Full-Stack Playground Workflow & Verification Guide

> Automated multi-stage enterprise walkthrough across Authentication, E-Commerce, and Cloud Provisioning.

---

### Executive Overview
This guide demonstrates StepIt's automatic UI inspection, coordinate capture, and animated visual synthesis across real-world modern components.

---

### Step 1: Register Enterprise Team Lead Account
Fill in your name, email, and password. Confirm password complexity evaluates to *Very Strong*. Select the **Engineering Lead / Architect** role from the dropdown.

![Register Account](\(recordedSteps[0].assets.gif ?? "media/step_01.gif"))

---

### Step 2: Adjust Team Seat Allocation Slider
Drag the team capacity range slider rightward to expand the workspace seat limit to 48 active engineers.

![Seat Allocation Slider](\(recordedSteps[1].assets.gif ?? "media/step_02.gif"))

---

### Step 3: Increase Item Quantity in Shopping Cart
In the e-commerce cart summary, locate the **Developer Mechanical Keyboard** item and click the `+` stepper button to double the quantity.

![Increase Item Quantity](\(recordedSteps[2].assets.gif ?? "media/step_03.gif"))

---

### Step 4: Write Backend Fast-Forward Ingestion API in VS Code
Open `workflow_router.py` in Visual Studio Code. Implement the FastAPI endpoint with Pydantic request validation. Typing activity is automatically captured, accelerated into a fast-forward micro-clip, and made available as a 1-click copyable code block.

```python
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title="StepIt Fast-Forward Capture API")

class WorkflowStep(BaseModel):
    index: int
    action: str
    text_blob: str | None = None
    coords: dict[str, float]

@app.post("/v1/record/step")
async def record_workflow_step(step: WorkflowStep):
    print(f"Captured {step.action} step #{step.index}")
    return {"status": "persisted", "step_id": f"stp_{step.index}"}
```

![VS Code Fast-Forward Capture](\(recordedSteps[3].assets.gif ?? "media/step_04.gif"))

---

### Step 5: Run Database Migration & Automated Test Suite in Terminal
Switch to Terminal to execute migrations and trigger the automated test suite. Keystrokes are captured and aggregated into a copyable terminal command block.

```bash
pytest tests/test_capture.py -v && swift run stepit export sess_playground
```

![Terminal Fast-Forward Typing](\(recordedSteps[4].assets.gif ?? "media/step_05.gif"))

---

### Step 6: Confirm Cloud Cluster Deployment
Navigate to the Cloud Provisioning console. Review the monthly cost estimation and click **🚀 Provision Cloud Instance** to dispatch the infrastructure provisioning pipeline.

![Confirm Deployment](\(recordedSteps[5].assets.gif ?? "media/step_06.gif"))

---

_Generated automatically via [StepIt macOS](https://github.com/stepit/stepit)._
"""

        
        let session = StepSession(
            id: sessionId,
            startedAt: Date().addingTimeInterval(-120),
            endedAt: Date(),
            title: "Automated 10-Page Playground Verification Guide",
            summary: "Comprehensive multi-page recording capturing forms, range sliders, steppers, radio groups, and button dispatches.",
            theme: .developerDark,
            mediaMode: .hybrid,
            steps: recordedSteps,
            synthesizedMarkdown: synthesizedDoc
        )
        
        try SessionStore.shared.saveSession(session)
        print("  💾 Saved session metadata to: \(sessionDir.path)")
        
        let settings = SessionStore.shared.loadSettings()
        print("  🌐 Compiling Interactive Web Documentation with dark theme & stepper...")
        let webURL = try PublishingCoordinator.shared.exportWeb(session: session, settings: settings)
        
        print("  📄 Rendering Print-Ready PDF with WebKit paged media...")
        let pdfURL = try? await PublishingCoordinator.shared.exportPDF(session: session, settings: settings)
        
        print("  📝 Exporting GitHub-flavored Markdown README...")
        let mdURL = try PublishingCoordinator.shared.exportMarkdown(session: session)
        
        print("\n🎉 [StepIt Automate] Workflow Recording & Multi-Format Publishing Complete!")
        print("  🌐 Interactive Web Site: \(webURL.path)")
        if let pdf = pdfURL {
            print("  📄 Print-Ready PDF:      \(pdf.path)")
        }
        print("  📝 Markdown Guide:       \(mdURL.path)")
        
        if openInBrowserAfter {
            print("  🚀 Launching interactive documentation in default browser...")
            PublishingCoordinator.shared.openInBrowser(url: webURL)
        }
        
        return session
    }
    
    // MARK: - Mock Visual Generators
    
    private func generateMockPageCapture(
        pageName: String,
        title: String,
        targetRole: String,
        targetTitle: String,
        highlightPoint: CGPoint,
        stepIndex: Int
    ) -> CGImage {
        let width = 1100
        let height = 700
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!
        
        // Background
        ctx.setFillColor(NSColor(srgbRed: 0.04, green: 0.05, blue: 0.08, alpha: 1.0).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        // Browser Window Header
        ctx.setFillColor(NSColor(srgbRed: 0.08, green: 0.11, blue: 0.18, alpha: 1.0).cgColor)
        ctx.fill(CGRect(x: 0, y: height - 48, width: width, height: 48))
        
        // Traffic lights
        let redLight = CGRect(x: 20, y: height - 30, width: 12, height: 12)
        let yellowLight = CGRect(x: 40, y: height - 30, width: 12, height: 12)
        let greenLight = CGRect(x: 60, y: height - 30, width: 12, height: 12)
        ctx.setFillColor(NSColor(srgbRed: 0.94, green: 0.36, blue: 0.35, alpha: 1.0).cgColor)
        ctx.fillEllipse(in: redLight)
        ctx.setFillColor(NSColor(srgbRed: 0.98, green: 0.74, blue: 0.23, alpha: 1.0).cgColor)
        ctx.fillEllipse(in: yellowLight)
        ctx.setFillColor(NSColor(srgbRed: 0.16, green: 0.78, blue: 0.36, alpha: 1.0).cgColor)
        ctx.fillEllipse(in: greenLight)
        
        // URL Bar
        ctx.setFillColor(NSColor(srgbRed: 0.12, green: 0.16, blue: 0.26, alpha: 1.0).cgColor)
        ctx.fill(CGRect(x: 95, y: height - 36, width: width - 150, height: 24))
        
        // Page Content Containers
        ctx.setFillColor(NSColor(srgbRed: 0.07, green: 0.10, blue: 0.16, alpha: 1.0).cgColor)
        ctx.fill(CGRect(x: 40, y: 40, width: width - 80, height: height - 110))
        
        // Mock Header & Title inside Page
        ctx.setFillColor(NSColor(srgbRed: 0.20, green: 0.26, blue: 0.40, alpha: 0.8).cgColor)
        ctx.fill(CGRect(x: 70, y: height - 120, width: 380, height: 28))
        
        // Mock UI Component Panels or IDE Canvas
        if targetRole == "AXCodeEditor" {
            // Dark IDE Editor Canvas (VS Code Style)
            ctx.setFillColor(NSColor(srgbRed: 0.11, green: 0.12, blue: 0.18, alpha: 1.0).cgColor)
            ctx.fill(CGRect(x: 70, y: 70, width: width - 140, height: height - 210))
            
            // Tab bar
            ctx.setFillColor(NSColor(srgbRed: 0.15, green: 0.17, blue: 0.24, alpha: 1.0).cgColor)
            ctx.fill(CGRect(x: 70, y: height - 170, width: 220, height: 30))
            
            // Simulated syntax-highlighted code lines
            let syntaxColors = [
                NSColor(srgbRed: 0.77, green: 0.44, blue: 0.88, alpha: 0.9), // purple keyword
                NSColor(srgbRed: 0.38, green: 0.65, blue: 0.98, alpha: 0.9), // blue identifier
                NSColor(srgbRed: 0.95, green: 0.77, blue: 0.44, alpha: 0.9), // yellow string
                NSColor(srgbRed: 0.40, green: 0.80, blue: 0.55, alpha: 0.9)  // green comment
            ]
            for i in 0..<8 {
                let color = syntaxColors[i % syntaxColors.count]
                ctx.setFillColor(color.cgColor)
                let yOffset = CGFloat(height - 210 - (i * 24))
                let lineWidth = CGFloat(160 + (i * 35) % 240)
                ctx.fill(CGRect(x: 100.0, y: yOffset, width: lineWidth, height: 10.0))
            }
        } else if targetRole == "AXTextField" {
            // Dark Terminal Console
            ctx.setFillColor(NSColor(srgbRed: 0.05, green: 0.07, blue: 0.10, alpha: 1.0).cgColor)
            ctx.fill(CGRect(x: 70, y: 70, width: width - 140, height: height - 210))
            
            // Terminal prompt & green command bar
            ctx.setFillColor(NSColor(srgbRed: 0.22, green: 0.85, blue: 0.55, alpha: 0.9).cgColor)
            ctx.fill(CGRect(x: 95, y: height - 190, width: 340, height: 12))
        } else {
            ctx.setFillColor(NSColor(srgbRed: 0.10, green: 0.14, blue: 0.22, alpha: 1.0).cgColor)
            ctx.fill(CGRect(x: 70, y: 80, width: (width - 170) / 2, height: height - 230))
            ctx.fill(CGRect(x: 70 + (width - 170) / 2 + 30, y: 80, width: (width - 170) / 2, height: height - 230))
        }
        
        // Target Element Block (Button, Slider, or Radio)
        let elemWidth: CGFloat = targetRole == "AXSlider" ? 220 : 160
        let elemHeight: CGFloat = targetRole == "AXSlider" ? 24 : 38
        let elemRect = CGRect(x: highlightPoint.x - elemWidth / 2, y: highlightPoint.y - elemHeight / 2, width: elemWidth, height: elemHeight)
        
        if targetRole == "AXSlider" {
            // Draw Slider Track
            ctx.setFillColor(NSColor(srgbRed: 0.2, green: 0.25, blue: 0.35, alpha: 1.0).cgColor)
            ctx.fill(CGRect(x: elemRect.origin.x, y: elemRect.origin.y + 8, width: elemWidth, height: 8))
            // Slider Thumb
            ctx.setFillColor(NSColor(srgbRed: 0.38, green: 0.40, blue: 0.95, alpha: 1.0).cgColor)
            ctx.fillEllipse(in: CGRect(x: elemRect.origin.x + elemWidth * 0.6, y: elemRect.origin.y + 2, width: 20, height: 20))
        } else if targetRole != "AXCodeEditor" && targetRole != "AXTextField" {
            // Draw Button
            ctx.setFillColor(NSColor(srgbRed: 0.38, green: 0.40, blue: 0.95, alpha: 1.0).cgColor)
            ctx.fill(elemRect)
        }
        
        // Draw StepIt Highlight Marker (Glow + Concentric Ring + Center Dot + Step Badge)
        let radius: CGFloat = 34.0
        // Soft Glow
        ctx.setFillColor(NSColor(srgbRed: 0.94, green: 0.27, blue: 0.27, alpha: 0.38).cgColor)
        ctx.fillEllipse(in: CGRect(x: highlightPoint.x - radius * 1.5, y: highlightPoint.y - radius * 1.5, width: radius * 3.0, height: radius * 3.0))
        // Ring
        ctx.setStrokeColor(NSColor(srgbRed: 0.94, green: 0.27, blue: 0.27, alpha: 1.0).cgColor)
        ctx.setLineWidth(3.5)
        ctx.strokeEllipse(in: CGRect(x: highlightPoint.x - radius, y: highlightPoint.y - radius, width: radius * 2.0, height: radius * 2.0))
        // Dot
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: highlightPoint.x - 4, y: highlightPoint.y - 4, width: 8, height: 8))
        // Badge
        let badgeCenter = CGPoint(x: highlightPoint.x + radius * 0.75, y: highlightPoint.y + radius * 0.75)
        ctx.setFillColor(NSColor(srgbRed: 0.94, green: 0.27, blue: 0.27, alpha: 1.0).cgColor)
        ctx.fillEllipse(in: CGRect(x: badgeCenter.x - 14, y: badgeCenter.y - 14, width: 28, height: 28))
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2.0)
        ctx.strokeEllipse(in: CGRect(x: badgeCenter.x - 14, y: badgeCenter.y - 14, width: 28, height: 28))
        
        return ctx.makeImage()!
    }
    
    private func generateMockAnimatedGIF(baseImage: CGImage, clickPoint: CGPoint) -> Data {
        var frames: [CGImage] = []
        let width = baseImage.width
        let height = baseImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        // 8 frames simulating cursor approach and click ripple
        for i in 0..<8 {
            let ctx = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )!
            
            ctx.draw(baseImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            
            let rippleRadius = 20.0 + CGFloat(i * 9)
            let alpha = max(0.0, 0.85 - Double(i) * 0.12)
            
            ctx.setStrokeColor(NSColor(srgbRed: 0.94, green: 0.27, blue: 0.27, alpha: CGFloat(alpha)).cgColor)
            ctx.setLineWidth(3.0)
            ctx.strokeEllipse(in: CGRect(x: clickPoint.x - rippleRadius, y: clickPoint.y - rippleRadius, width: rippleRadius * 2.0, height: rippleRadius * 2.0))
            
            if let frame = ctx.makeImage() {
                frames.append(frame)
            }
        }
        
        return MicroClipRecorder.shared.createGIF(from: frames, fps: 10) ?? Data()
    }
    
    private func generateMockFastForwardTypingGIF(baseImage: CGImage, clickPoint: CGPoint) -> Data {
        var frames: [CGImage] = []
        let width = baseImage.width
        let height = baseImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        // 10 frames simulating fast-forwarded typing keystrokes and cursor advance
        for i in 0..<10 {
            guard let ctx = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { continue }
            
            ctx.draw(baseImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            
            // Render typing indicator container
            let boxRect = CGRect(x: clickPoint.x - 10, y: clickPoint.y - 16, width: 340, height: 32)
            ctx.setFillColor(NSColor(srgbRed: 0.08, green: 0.10, blue: 0.16, alpha: 0.92).cgColor)
            ctx.fill(boxRect)
            ctx.setStrokeColor(NSColor(srgbRed: 0.38, green: 0.40, blue: 0.95, alpha: 0.8).cgColor)
            ctx.setLineWidth(1.5)
            ctx.stroke(boxRect)
            
            // Progressively advancing code/text token bar
            let progressWidth = CGFloat(i + 1) * 26.0
            ctx.setFillColor(NSColor(srgbRed: 0.22, green: 0.85, blue: 0.55, alpha: 0.95).cgColor)
            ctx.fill(CGRect(x: clickPoint.x, y: clickPoint.y - 5, width: progressWidth, height: 10))
            
            // Blinking caret
            if i % 2 == 0 {
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fill(CGRect(x: clickPoint.x + progressWidth + 4, y: clickPoint.y - 9, width: 3, height: 18))
            }
            
            // "3.5x Fast-Forward" indicator pill
            let pillRect = CGRect(x: boxRect.maxX - 90, y: boxRect.origin.y + 6, width: 80, height: 20)
            ctx.setFillColor(NSColor(srgbRed: 0.95, green: 0.55, blue: 0.15, alpha: 0.95).cgColor)
            ctx.fill(pillRect)
            
            if let frame = ctx.makeImage() {
                frames.append(frame)
            }
        }
        
        return MicroClipRecorder.shared.createFastForwardTypingGIF(from: frames, speedFactor: 3.5)
            ?? MicroClipRecorder.shared.createGIF(from: frames, fps: 16)
            ?? Data()
    }
}

