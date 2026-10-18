import Foundation
import FlowlineStorage
import FlowlineMacCapture
import FlowlineCaptureAPI
import FlowlinePublishing
import FlowlineAIGateway
import FlowlinePipeline
import FlowlineEngine
import FlowlineIR
import AppKit
import CoreGraphics

public final class AutomatedWorkflowRecorder: @unchecked Sendable {
    private let store: any SessionStoreProtocol
    private let renderer: any PlaygroundCaptureRenderer
    private let pngEncoder: PNGEncoder
    private let publisher: PublishingCoordinator
    private let publishing: PublishingSettings

    public init(
        store: any SessionStoreProtocol = SessionStore(),
        renderer: any PlaygroundCaptureRenderer = PlaygroundPageRenderer(),
        pngEncoder: @escaping PNGEncoder = { ScreenRecorder().imageToPNGData($0) },
        publisher: PublishingCoordinator = PublishingCoordinator(),
        publishing: PublishingSettings = PublishingSettings()
    ) {
        self.store = store
        self.renderer = renderer
        self.pngEncoder = pngEncoder
        self.publisher = publisher
        self.publishing = publishing
    }

    @MainActor
    public func recordPlaygroundWorkflow(openInBrowserAfter: Bool = true) async throws -> StepSession {
        print("[Flowline] [Automate] Initializing Automated Workflow Recording across all 10 Playground Pages...")

        let sessionId = "sess_playground_tour_\(Int(Date().timeIntervalSince1970))"
        let sessionDir = store.sessionDirectory(for: sessionId)
        let mediaDir = store.mediaDirectory(for: sessionId)
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        
        // Comprehensive 10-step enterprise workflow mapping 1:1 to the 10 live HTML pages:
        let scenarioSteps: [(
            title: String,
            page: String,
            elementId: String,
            appName: String,
            windowTitle: String,
            role: String,
            elementTitle: String,
            notes: String,
            action: ActionType
        )] = [
            (
                title: "Register Enterprise Team Lead Account",
                page: "page1_onboarding.html",
                elementId: "btn-submit-onboarding",
                appName: "Safari",
                windowTitle: "Page 1: Auth & User Onboarding — Flowline Playground",
                role: "AXButton",
                elementTitle: "Create Account →",
                notes: "Input user credentials and verify password strength bar reflects 'Very Strong'.",
                action: .click
            ),
            (
                title: "Increase Item Quantity in Shopping Cart",
                page: "page2_checkout.html",
                elementId: "btn-qty-plus-1",
                appName: "Safari",
                windowTitle: "Page 2: E-Commerce Checkout — Flowline Playground",
                role: "AXButton",
                elementTitle: "+ (Add Quantity)",
                notes: "Click '+' stepper button to double order quantity for Mechanical Keyboards.",
                action: .click
            ),
            (
                title: "Export Core Metrics to Audit CSV",
                page: "page3_analytics.html",
                elementId: "btn-export-csv",
                appName: "Safari",
                windowTitle: "Page 3: Analytics Dashboard — Flowline Playground",
                role: "AXButton",
                elementTitle: "Export CSV",
                notes: "Generate hourly aggregated usage statistics report.",
                action: .click
            ),
            (
                title: "Confirm Cloud Cluster Deployment",
                page: "page4_cloud.html",
                elementId: "btn-provision-server",
                appName: "Safari",
                windowTitle: "Page 4: Cloud Server Provisioning — Flowline Playground",
                role: "AXButton",
                elementTitle: "Provision Cloud Instance",
                notes: "Submit deployment transaction to initialize regional data center VMs.",
                action: .click
            ),
            (
                title: "Render High-Fidelity Audio Master",
                page: "page5_media.html",
                elementId: "btn-render-audio",
                appName: "Safari",
                windowTitle: "Page 5: Audio & Media Studio — Flowline Playground",
                role: "AXButton",
                elementTitle: "Render Master Audio",
                notes: "Apply audio master equalizers and export AAC 320kbps waveform.",
                action: .click
            ),
            (
                title: "Dispatch API Gateway Request",
                page: "page6_apigateway.html",
                elementId: "btn-send-request",
                appName: "Safari",
                windowTitle: "Page 6: Developer API Gateway — Flowline Playground",
                role: "AXButton",
                elementTitle: "Send API Request",
                notes: "Dispatch test POST transaction to simulate gateway endpoint routing.",
                action: .click
            ),
            (
                title: "Submit High-Priority Support Ticket",
                page: "page7_support.html",
                elementId: "btn-submit-ticket",
                appName: "Safari",
                windowTitle: "Page 7: Customer Support Portal — Flowline Playground",
                role: "AXButton",
                elementTitle: "Submit Support Ticket →",
                notes: "Dispatch priority incident to on-call engineering rotations.",
                action: .click
            ),
            (
                title: "Advance Product Feedback Survey Stage",
                page: "page8_survey.html",
                elementId: "btn-next-stage-1",
                appName: "Safari",
                windowTitle: "Page 8: Product Experience Survey — Flowline Playground",
                role: "AXButton",
                elementTitle: "Next Question →",
                notes: "Rate customer NPS satisfaction and progress to multi-choice criteria.",
                action: .click
            ),
            (
                title: "Batch Export Filtered Records in Data Grid",
                page: "page9_datagrid.html",
                elementId: "btn-batch-export",
                appName: "Safari",
                windowTitle: "Page 9: Enterprise Data Grid — Flowline Playground",
                role: "AXButton",
                elementTitle: "Export Selected",
                notes: "Perform bulk CSV export on checked data grid rows.",
                action: .click
            ),
            (
                title: "Restart Global EventTap Background Daemon",
                page: "page10_diagnostics.html",
                elementId: "btn-restart-eventtap",
                appName: "Safari",
                windowTitle: "Page 10: System Diagnostics & Health — Flowline Playground",
                role: "AXButton",
                elementTitle: "Restart",
                notes: "Flush event buffer cache and restart macOS CGEventTap capture listener.",
                action: .click
            )
        ]
        
        var recordedSteps: [Step] = []
        
        for (index, item) in scenarioSteps.enumerated() {
            let stepNum = index + 1
            print("  [CAPTURE] Recording Step \(stepNum)/\(scenarioSteps.count): \(item.title) on [\(item.page)] -> #\(item.elementId)...")
            
            // Render genuine live WebKit snapshot with coordinates resolved from live DOM
            let capture = try await renderer.renderStepCapture(
                filename: item.page,
                targetElementId: item.elementId,
                stepIndex: stepNum
            )
            
            guard let pngData = pngEncoder(capture.screenshot) else {
                throw NSError(
                    domain: "AutomatedWorkflowRecorder",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG for step \(stepNum)"]
                )
            }
            
            let pngName = String(format: "step_%02d.png", stepNum)
            let screenshotRel = try store.saveMedia(data: pngData, sessionID: sessionId, filename: pngName)
            
            let zoomPngData = pngEncoder(capture.zoomCrop)!
            let zoomPngName = String(format: "step_%02d_zoom.png", stepNum)
            let zoomRel = try store.saveMedia(data: zoomPngData, sessionID: sessionId, filename: zoomPngName)
            
            let gifName = String(format: "step_%02d.gif", stepNum)
            let gifRel = try store.saveMedia(data: capture.gifData, sessionID: sessionId, filename: gifName)
            
            let step = Step(
                id: UUID().uuidString,
                index: stepNum,
                timestamp: Date().addingTimeInterval(Double(index * 12)),
                action: item.action,
                appName: item.appName,
                bundleIdentifier: "com.apple.Safari",
                windowTitle: item.windowTitle,
                elementRole: item.role,
                elementTitle: item.elementTitle,
                coordinates: ScreenCoordinates(x: Double(capture.targetPoint.x), y: Double(capture.targetPoint.y)),
                actionDescription: item.title,
                userNotes: item.notes,
                assets: MediaAssets(screenshot: screenshotRel, gif: gifRel, zoomCrop: zoomRel)
            )
            
            recordedSteps.append(step)
        }
        
        let synthesizedDoc = """
# Full-Stack 10-Page Playground Verification Guide

> Automated multi-stage enterprise walkthrough across all 10 playground pages, rendered live via WebKit with dynamic DOM coordinate resolution.

---

### Executive Overview
This guide demonstrates Flowline's automatic UI inspection, coordinate capture, and animated visual synthesis across 10 real-world web components.

---

### Step 1: Register Enterprise Team Lead Account
Open the onboarding portal in Safari, fill in user credentials, and submit the registration form.

![Register Account](\(recordedSteps[0].assets.gif ?? "media/step_01.gif"))

---

### Step 2: Increase Item Quantity in Shopping Cart
In the e-commerce checkout page, locate the developer mechanical keyboard item and click the stepper button to adjust quantity.

![Increase Item Quantity](\(recordedSteps[1].assets.gif ?? "media/step_02.gif"))

---

### Step 3: Export Core Metrics to Audit CSV
On the analytics dashboard, review active user traffic and click **Export CSV** to download the audit manifest.

![Export Analytics CSV](\(recordedSteps[2].assets.gif ?? "media/step_03.gif"))

---

### Step 4: Confirm Cloud Cluster Deployment
Provision regional data center infrastructure by selecting data center specs and clicking **Provision Cloud Instance**.

![Cloud Deployment](\(recordedSteps[3].assets.gif ?? "media/step_04.gif"))

---

### Step 5: Render High-Fidelity Audio Master
In the media studio, configure equalizer curves, select AAC codec, and dispatch audio master rendering.

![Render Audio Master](\(recordedSteps[4].assets.gif ?? "media/step_05.gif"))

---

### Step 6: Dispatch API Gateway Request
In the developer API Gateway tester, inspect REST parameters and click **Send API Request** to test gateway routing.

![API Gateway Request](\(recordedSteps[5].assets.gif ?? "media/step_06.gif"))

---

### Step 7: Submit High-Priority Support Ticket
In the support portal, assign ticket impact, select engineering assignee, and dispatch the ticket.

![Submit Support Ticket](\(recordedSteps[6].assets.gif ?? "media/step_07.gif"))

---

### Step 8: Advance Product Feedback Survey Stage
On the product experience survey, rate NPS score and advance to the qualitative feedback stage.

![Survey Feedback](\(recordedSteps[7].assets.gif ?? "media/step_08.gif"))

---

### Step 9: Batch Export Filtered Records in Data Grid
Filter tenant accounts in the enterprise data table, check candidate rows, and click **Export Selected** to download the batch audit report.

![Batch Export Data Grid](\(recordedSteps[8].assets.gif ?? "media/step_09.gif"))

---

### Step 10: Restart Global EventTap Background Daemon
On the system diagnostics page, monitor buffer usage and restart the background CGEventTap daemon.

![Restart Service](\(recordedSteps[9].assets.gif ?? "media/step_10.gif"))

---

_Generated automatically via [Flowline macOS](https://github.com/flowline/flowline) using live WebKit DOM inspection._
"""
        
        let session = StepSession(
            id: sessionId,
            startedAt: Date().addingTimeInterval(-180),
            endedAt: Date(),
            title: "Automated 10-Page Playground Verification Guide",
            summary: "Comprehensive 10-page recording capturing live DOM controls, steppers, range sliders, analytics charts, and diagnostic services.",
            theme: .developerDark,
            mediaMode: .hybrid,
            steps: recordedSteps,
            synthesizedMarkdown: synthesizedDoc
        )
        
        try store.saveSession(session)
        print("  [OK] Saved session metadata to: \(sessionDir.path)")
        
        print("  [Web] Compiling Interactive Web Documentation with dark theme & stepper...")
        let webURL = try publisher.exportWeb(session: session, publishing: publishing)
        
        print("  [PDF] Rendering Print-Ready PDF with WebKit paged media...")
        let pdfURL = try? await publisher.exportPDF(session: session, publishing: publishing)
        
        print("  [Markdown] Exporting GitHub-flavored Markdown README...")
        let mdURL = try publisher.exportMarkdown(session: session)
        
        print("\n[DONE] [Automate] 10-Page Workflow Tour & Multi-Format Publishing Complete!")
        print("  Web: \(webURL.path)")
        if let pdf = pdfURL {
            print("  PDF:      \(pdf.path)")
        }
        print("  Markdown:       \(mdURL.path)")
        
        if openInBrowserAfter {
            print("  [OPEN] Launching interactive documentation in default browser...")
            publisher.openInBrowser(url: webURL)
        }
        
        return session
    }
}
