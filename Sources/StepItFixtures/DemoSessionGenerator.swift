import Foundation
import StepItIR
import AppKit
import CoreGraphics
import StepItCore

public struct DemoSessionGenerator {
    @MainActor
    public static func generateDemoSession() async throws -> StepSession {
        let sessionId = "sess_showcase_report"
        let mediaDir = SessionStore.shared.mediaDirectory(for: sessionId)
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        
        var steps: [Step] = []
        
        // --- Step 1: CLI Terminal Initializer ---
        print("  💻 [Step 1/6] Recording CLI Terminal: Environment Setup & Toolchain Init...")
        let cliCmd1 = "brew install stepit-cli && stepit init --preset developer-dark"
        let step1 = Step(
            id: UUID().uuidString,
            index: 1,
            action: .typing,
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            windowTitle: "zsh — 80×24",
            elementRole: "AXTextField",
            elementTitle: "Terminal Command Input",
            actionDescription: "Initialize StepIt CLI toolchain and configure developer-dark preset",
            userNotes: "Run Homebrew installation to link stepit binaries and set up default environment.",
            textBlob: cliCmd1,
            isCode: true,
            codeLanguage: "bash",
            assets: MediaAssets()
        )
        steps.append(step1)
        
        // --- Step 2: Playground Page 1 (Auth & Onboarding) with Clean 2.4x Zoom Crop ---
        print("  🌐 [Step 2/6] Rendering live WebKit capture + 2.4x Zoom for Page 1: Auth & Onboarding...")
        let step2Capture = try await PlaygroundPageRenderer.shared.renderStepCapture(
            filename: "page1_onboarding.html",
            targetElementId: "btn-submit-onboarding",
            stepIndex: 2
        )
        
        let step2Png = ScreenRecorder.shared.imageToPNGData(step2Capture.screenshot)!
        let step2Rel = try SessionStore.shared.saveMedia(data: step2Png, sessionID: sessionId, filename: "step_02.png")
        
        let step2ZoomPng = ScreenRecorder.shared.imageToPNGData(step2Capture.zoomCrop)!
        let step2ZoomRel = try SessionStore.shared.saveMedia(data: step2ZoomPng, sessionID: sessionId, filename: "step_02_zoom.png")
        
        let step2GifRel = try SessionStore.shared.saveMedia(data: step2Capture.gifData, sessionID: sessionId, filename: "step_02.gif")
        
        let step2 = Step(
            id: UUID().uuidString,
            index: 2,
            action: .click,
            appName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            windowTitle: "Page 1: Auth & User Onboarding — StepIt Playground",
            elementRole: "AXButton",
            elementTitle: "Create Account →",
            coordinates: ScreenCoordinates(x: Double(step2Capture.targetPoint.x), y: Double(step2Capture.targetPoint.y)),
            actionDescription: "Register Enterprise Team Lead in Onboarding Portal",
            userNotes: "Fill in account credentials. Password indicator evaluates to 'Very Strong'. Use the 2.4x Zoom toggle or click the image to inspect the live button bounding rect.",
            assets: MediaAssets(screenshot: step2Rel, gif: step2GifRel, zoomCrop: step2ZoomRel)
        )
        steps.append(step2)
        
        // --- Step 3: Playground Page 2 (E-Commerce Checkout) with Stepper Stepping ---
        print("  🌐 [Step 3/6] Rendering live WebKit capture + 2.4x Zoom for Page 2: Checkout...")
        let step3Capture = try await PlaygroundPageRenderer.shared.renderStepCapture(
            filename: "page2_checkout.html",
            targetElementId: "btn-qty-plus-1",
            stepIndex: 3
        )
        
        let step3Png = ScreenRecorder.shared.imageToPNGData(step3Capture.screenshot)!
        let step3Rel = try SessionStore.shared.saveMedia(data: step3Png, sessionID: sessionId, filename: "step_03.png")
        
        let step3ZoomPng = ScreenRecorder.shared.imageToPNGData(step3Capture.zoomCrop)!
        let step3ZoomRel = try SessionStore.shared.saveMedia(data: step3ZoomPng, sessionID: sessionId, filename: "step_03_zoom.png")
        
        let step3GifRel = try SessionStore.shared.saveMedia(data: step3Capture.gifData, sessionID: sessionId, filename: "step_03.gif")
        
        let step3 = Step(
            id: UUID().uuidString,
            index: 3,
            action: .click,
            appName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            windowTitle: "Page 2: E-Commerce Checkout — StepIt Playground",
            elementRole: "AXButton",
            elementTitle: "+ (Add Quantity)",
            coordinates: ScreenCoordinates(x: Double(step3Capture.targetPoint.x), y: Double(step3Capture.targetPoint.y)),
            actionDescription: "Increase Item Quantity in Shopping Cart Stepper",
            userNotes: "Click '+' stepper button to double order quantity for Mechanical Keyboards. Focused 2.4x zoom crop isolates the stepper control.",
            assets: MediaAssets(screenshot: step3Rel, gif: step3GifRel, zoomCrop: step3ZoomRel)
        )
        steps.append(step3)
        
        // --- Step 4: CLI Terminal: REST Ingress Webhook Dispatch ---
        print("  💻 [Step 4/6] Recording CLI Terminal: cURL Ingress Transaction Dispatch...")
        let cliCmd2 = "curl -X POST https://api.gateway.stepit.internal/v1/workflows/dispatch -H \"Authorization: Bearer sk-stepit_live_9a8b7c6d5e\" -H \"Content-Type: application/json\" -d '{\"workflow\":\"audit_pipeline\",\"priority\":\"high\",\"notifications\":[\"slack\",\"email\"]}'"
        let step4 = Step(
            id: UUID().uuidString,
            index: 4,
            action: .typing,
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            windowTitle: "zsh — 90×30",
            elementRole: "AXTextField",
            elementTitle: "REST Ingress Command",
            actionDescription: "Dispatch authenticated pipeline webhook transaction via cURL",
            userNotes: "1-click copyable terminal command block. Executes pipeline dispatch to remote ingress cluster.",
            textBlob: cliCmd2,
            isCode: true,
            codeLanguage: "bash",
            assets: MediaAssets()
        )
        steps.append(step4)
        
        // --- Step 5: Playground Page 6 (Developer API Gateway) with Live Request Button ---
        print("  🌐 [Step 5/6] Rendering live WebKit capture + 2.4x Zoom for Page 6: API Gateway...")
        let step5Capture = try await PlaygroundPageRenderer.shared.renderStepCapture(
            filename: "page6_apigateway.html",
            targetElementId: "btn-send-request",
            stepIndex: 5
        )
        
        let step5Png = ScreenRecorder.shared.imageToPNGData(step5Capture.screenshot)!
        let step5Rel = try SessionStore.shared.saveMedia(data: step5Png, sessionID: sessionId, filename: "step_05.png")
        
        let step5ZoomPng = ScreenRecorder.shared.imageToPNGData(step5Capture.zoomCrop)!
        let step5ZoomRel = try SessionStore.shared.saveMedia(data: step5ZoomPng, sessionID: sessionId, filename: "step_05_zoom.png")
        
        let step5GifRel = try SessionStore.shared.saveMedia(data: step5Capture.gifData, sessionID: sessionId, filename: "step_05.gif")
        
        let step5 = Step(
            id: UUID().uuidString,
            index: 5,
            action: .click,
            appName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            windowTitle: "Page 6: Developer API Gateway — StepIt Playground",
            elementRole: "AXButton",
            elementTitle: "⚡️ Send API Request",
            coordinates: ScreenCoordinates(x: Double(step5Capture.targetPoint.x), y: Double(step5Capture.targetPoint.y)),
            actionDescription: "Dispatch Test Transaction in API Gateway Tester",
            userNotes: "Simulate live API request routing. Click the image to toggle smooth in-place zoom directly at the Send button.",
            assets: MediaAssets(screenshot: step5Rel, gif: step5GifRel, zoomCrop: step5ZoomRel)
        )
        steps.append(step5)
        
        // --- Step 6: Playground Page 9 (Enterprise Data Grid) with Batch Export ---
        print("  🌐 [Step 6/6] Rendering live WebKit capture + 2.4x Zoom for Page 9: Data Grid...")
        let step6Capture = try await PlaygroundPageRenderer.shared.renderStepCapture(
            filename: "page9_datagrid.html",
            targetElementId: "btn-batch-export",
            stepIndex: 6
        )
        
        let step6Png = ScreenRecorder.shared.imageToPNGData(step6Capture.screenshot)!
        let step6Rel = try SessionStore.shared.saveMedia(data: step6Png, sessionID: sessionId, filename: "step_06.png")
        
        let step6ZoomPng = ScreenRecorder.shared.imageToPNGData(step6Capture.zoomCrop)!
        let step6ZoomRel = try SessionStore.shared.saveMedia(data: step6ZoomPng, sessionID: sessionId, filename: "step_06_zoom.png")
        
        let step6GifRel = try SessionStore.shared.saveMedia(data: step6Capture.gifData, sessionID: sessionId, filename: "step_06.gif")
        
        let step6 = Step(
            id: UUID().uuidString,
            index: 6,
            action: .click,
            appName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            windowTitle: "Page 9: Enterprise Data Grid — StepIt Playground",
            elementRole: "AXButton",
            elementTitle: "Export Selected",
            coordinates: ScreenCoordinates(x: Double(step6Capture.targetPoint.x), y: Double(step6Capture.targetPoint.y)),
            actionDescription: "Batch Export Filtered Records from Enterprise Data Grid",
            userNotes: "Filtered by Status: 'Active'. Export manifest downloads table data. Use the Lightbox button to inspect full Retina resolution.",
            assets: MediaAssets(screenshot: step6Rel, gif: step6GifRel, zoomCrop: step6ZoomRel)
        )
        steps.append(step6)
        
        let synthesizedDoc = """
# ⚡️ Full-Stack Enterprise SOP & Verification Report

> Comprehensive end-to-end workflow documentation showcasing live WebKit DOM inspection, clean 2.4x focus zoom crops, interactive in-place image zoom, fullscreen inspection lightbox, and 1-click copyable terminal command blocks.

---

### Prerequisites
- macOS Sonoma or later
- Homebrew & Terminal / iTerm2
- StepIt Desktop HUD & WebKit Rendering Engine

---

### Step 1: Initialize StepIt CLI Toolchain
Run the standard Homebrew package installation to configure local binaries and initialize the developer-dark publishing configuration:

```bash
\(cliCmd1)
```

---

### Step 2: Register Enterprise Team Lead Account
Open the onboarding portal in Safari. Fill in corporate credentials, confirm password complexity bar reflects *Very Strong*, and click **Create Account**.

![Register Account](\(step2Rel))

---

### Step 3: Increase Item Quantity in Shopping Cart
In the checkout workflow, locate the mechanical keyboard cart line and click the `+` stepper button to double order quantity.

![Increase Cart Quantity](\(step3Rel))

---

### Step 4: Dispatch Authenticated Ingress Webhook
Trigger the pipeline deployment transaction directly from Terminal using standard `cURL`:

```bash
\(cliCmd2)
```

---

### Step 5: Dispatch Test Transaction in API Gateway Tester
Open the developer API Gateway interface in Safari, verify request payload and bearer tokens, and click **⚡️ Send API Request**.

![API Gateway Request](\(step5Rel))

---

### Step 6: Batch Export Filtered Records from Data Grid
Filter tenant accounts in the enterprise data grid, select checked rows, and click **Export Selected** to download the audit manifest.

![Data Grid Batch Export](\(step6Rel))

---

_Generated effortlessly with [StepIt macOS](https://github.com/stepit/stepit) featuring Live WebKit DOM Capture, Clean 2.4x Zoom, and Copyable Terminal Blobs._
"""
        
        return StepSession(
            id: sessionId,
            startedAt: Date().addingTimeInterval(-240),
            endedAt: Date(),
            title: "Full-Stack Enterprise SOP & Verification Report",
            summary: "Comprehensive showcase featuring live WebKit playground captures, 2.4x focus zoom crops, in-place click-to-zoom, fullscreen lightbox, and 1-click copyable terminal command blocks.",
            theme: .developerDark,
            mediaMode: .hybrid,
            steps: steps,
            synthesizedMarkdown: synthesizedDoc
        )
    }
}
