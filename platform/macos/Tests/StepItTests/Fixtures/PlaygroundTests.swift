import XCTest
import StepItStorage
import StepItCaptureAPI
import StepItMacCapture
import StepItPublishing
import StepItAIGateway
import StepItPermissions
import Foundation
import StepItIR
import StepItPipeline
import StepItEngine
import CoreGraphics
import AppKit
import WebKit

import StepItFixtures

// MARK: - Table Test Data Structures

/// Test vector representing a Playground Web Page to validate HTML integrity and DOM elements
struct PlaygroundPageVector {
    let filename: String
    let expectedBadge: String
    let expectedTitleSnippet: String
    let expectedControlIds: [String]
    let expectedSemanticTags: [String]
}

/// Test vector representing a live WebKit rendering target on a Playground page
struct PlaygroundLiveRenderVector {
    let pageIndex: Int
    let filename: String
    let targetElementId: String
    let expectedRole: String
    let expectedElementTitle: String
    let action: ActionType
    let stepTitle: String
    let stepNotes: String
}

/// Test vector for Playground DOM interaction and state mutation
struct PlaygroundDOMInteractionVector {
    let filename: String
    let setupAction: (PlaygroundPageRenderer, WKWebView) async throws -> Void
    let assertion: (PlaygroundPageRenderer, WKWebView) async throws -> Void
}

/// Test vector for Publishing & Theme matrix
struct ThemeExportVector {
    let theme: ThemeName
    let mediaMode: MediaMode
    let expectedThemeClass: String
}

// MARK: - Playground Test Suite (Exclusively Playground Pages)

final class PlaygroundTests: XCTestCase {
    
    // MARK: - Table Test 1: All 10 Playground Pages Integrity
    
    let pageVectors: [PlaygroundPageVector] = [
        PlaygroundPageVector(
            filename: "page1_onboarding.html",
            expectedBadge: "Workflow 01",
            expectedTitleSnippet: "Auth & User Onboarding",
            expectedControlIds: ["input-fullname", "input-email", "input-password", "select-role", "range-team-size", "toggle-2fa", "btn-submit-onboarding"],
            expectedSemanticTags: ["<form", "<input", "<select", "<button"]
        ),
        PlaygroundPageVector(
            filename: "page2_checkout.html",
            expectedBadge: "Workflow 02",
            expectedTitleSnippet: "E-Commerce Checkout",
            expectedControlIds: ["btn-qty-minus-1", "btn-qty-plus-1", "btn-complete-order", "btn-pay-apple"],
            expectedSemanticTags: ["<button", "<input"]
        ),
        PlaygroundPageVector(
            filename: "page3_analytics.html",
            expectedBadge: "Workflow 03",
            expectedTitleSnippet: "Analytics Dashboard",
            expectedControlIds: ["select-timeframe", "btn-refresh-data", "btn-export-csv", "metric-users"],
            expectedSemanticTags: ["<select", "<button"]
        ),
        PlaygroundPageVector(
            filename: "page4_cloud.html",
            expectedBadge: "Workflow 04",
            expectedTitleSnippet: "Cloud Server",
            expectedControlIds: ["select-datacenter", "btn-provision-server", "input-ssh-key"],
            expectedSemanticTags: ["<select", "<button", "<textarea"]
        ),
        PlaygroundPageVector(
            filename: "page5_media.html",
            expectedBadge: "Workflow 05",
            expectedTitleSnippet: "Media Studio",
            expectedControlIds: ["slider-master-volume", "slider-pan", "btn-codec-aac", "btn-render-audio"],
            expectedSemanticTags: ["<button", "<input"]
        ),
        PlaygroundPageVector(
            filename: "page6_apigateway.html",
            expectedBadge: "Workflow 06",
            expectedTitleSnippet: "API Gateway",
            expectedControlIds: ["input-endpoint-url", "input-api-key", "textarea-json-payload", "btn-send-request"],
            expectedSemanticTags: ["<select", "<textarea", "<button"]
        ),
        PlaygroundPageVector(
            filename: "page7_support.html",
            expectedBadge: "Workflow 07",
            expectedTitleSnippet: "Customer Support",
            expectedControlIds: ["textarea-ticket-body", "slider-impact", "select-assignee", "btn-submit-ticket"],
            expectedSemanticTags: ["<select", "<textarea", "<button"]
        ),
        PlaygroundPageVector(
            filename: "page8_survey.html",
            expectedBadge: "Workflow 08",
            expectedTitleSnippet: "Product Experience",
            expectedControlIds: ["btn-next-stage-1", "star-container"],
            expectedSemanticTags: ["<button", "<span", "<main"]
        ),
        PlaygroundPageVector(
            filename: "page9_datagrid.html",
            expectedBadge: "Workflow 09",
            expectedTitleSnippet: "Enterprise Data Grid",
            expectedControlIds: ["input-search-table", "select-status-filter", "btn-batch-export", "btn-batch-delete", "check-all-rows"],
            expectedSemanticTags: ["<table", "<input", "<button"]
        ),
        PlaygroundPageVector(
            filename: "page10_diagnostics.html",
            expectedBadge: "Workflow 10",
            expectedTitleSnippet: "System Diagnostics",
            expectedControlIds: ["btn-restart-eventtap", "btn-clear-buffer", "btn-ping-gateway", "btn-kill-all", "btn-clear-logs", "btn-inject-log", "log-terminal"],
            expectedSemanticTags: ["<button", "<pre", "<input"]
        )
    ]
    
    func testPlaygroundPagesIntegrity() throws {
        let dir = try XCTUnwrap(
            FixtureLocator.playgroundWebDirectory(),
            "shared/fixtures/playground-web should be discoverable from the repository root"
        )
        
        for vector in pageVectors {
            let pageURL = dir.appendingPathComponent(vector.filename)
            XCTAssertTrue(FileManager.default.fileExists(atPath: pageURL.path), "Page \(vector.filename) must exist")
            
            let htmlContent = try String(contentsOf: pageURL, encoding: .utf8)
            XCTAssertTrue(htmlContent.contains(vector.expectedBadge), "Page \(vector.filename) must contain badge \(vector.expectedBadge)")
            XCTAssertTrue(htmlContent.contains(vector.expectedTitleSnippet), "Page \(vector.filename) must contain '\(vector.expectedTitleSnippet)'")
            XCTAssertTrue(htmlContent.contains("styles.css"), "Page \(vector.filename) must link to styles.css")
            
            for controlId in vector.expectedControlIds {
                XCTAssertTrue(htmlContent.contains(controlId), "Page \(vector.filename) must contain control element ID '\(controlId)'")
            }
            
            for tag in vector.expectedSemanticTags {
                XCTAssertTrue(htmlContent.contains(tag), "Page \(vector.filename) must contain semantic tag '\(tag)'")
            }
        }
    }
    
    // MARK: - Table Test 2: Live WebKit Rendering & DOM Coordinates Across ALL 10 Pages
    
    let allTenPageVectors: [PlaygroundLiveRenderVector] = [
        PlaygroundLiveRenderVector(
            pageIndex: 1,
            filename: "page1_onboarding.html",
            targetElementId: "btn-submit-onboarding",
            expectedRole: "AXButton",
            expectedElementTitle: "Create Account →",
            action: .click,
            stepTitle: "Register Enterprise Team Lead Account",
            stepNotes: "Input user credentials and verify password strength bar reflects 'Very Strong'."
        ),
        PlaygroundLiveRenderVector(
            pageIndex: 2,
            filename: "page2_checkout.html",
            targetElementId: "btn-qty-plus-1",
            expectedRole: "AXButton",
            expectedElementTitle: "+ (Add Quantity)",
            action: .click,
            stepTitle: "Increase Item Quantity in Shopping Cart",
            stepNotes: "Click '+' stepper button to double order quantity for Mechanical Keyboards."
        ),
        PlaygroundLiveRenderVector(
            pageIndex: 3,
            filename: "page3_analytics.html",
            targetElementId: "btn-export-csv",
            expectedRole: "AXButton",
            expectedElementTitle: "Export CSV",
            action: .click,
            stepTitle: "Export Core Metrics to Audit CSV",
            stepNotes: "Generate hourly aggregated usage statistics report."
        ),
        PlaygroundLiveRenderVector(
            pageIndex: 4,
            filename: "page4_cloud.html",
            targetElementId: "btn-provision-server",
            expectedRole: "AXButton",
            expectedElementTitle: "🚀 Provision Cloud Instance",
            action: .click,
            stepTitle: "Confirm Cloud Cluster Deployment",
            stepNotes: "Submit deployment transaction to initialize regional data center VMs."
        ),
        PlaygroundLiveRenderVector(
            pageIndex: 5,
            filename: "page5_media.html",
            targetElementId: "btn-render-audio",
            expectedRole: "AXButton",
            expectedElementTitle: "🎚️ Render Master Audio",
            action: .click,
            stepTitle: "Render High-Fidelity Audio Master",
            stepNotes: "Apply audio master equalizers and export AAC 320kbps waveform."
        ),
        PlaygroundLiveRenderVector(
            pageIndex: 6,
            filename: "page6_apigateway.html",
            targetElementId: "btn-send-request",
            expectedRole: "AXButton",
            expectedElementTitle: "⚡️ Send API Request",
            action: .click,
            stepTitle: "Dispatch API Gateway Request",
            stepNotes: "Dispatch test POST transaction to simulate gateway endpoint routing."
        ),
        PlaygroundLiveRenderVector(
            pageIndex: 7,
            filename: "page7_support.html",
            targetElementId: "btn-submit-ticket",
            expectedRole: "AXButton",
            expectedElementTitle: "Submit Support Ticket →",
            action: .click,
            stepTitle: "Submit High-Priority Support Ticket",
            stepNotes: "Dispatch priority incident to on-call engineering rotations."
        ),
        PlaygroundLiveRenderVector(
            pageIndex: 8,
            filename: "page8_survey.html",
            targetElementId: "btn-next-stage-1",
            expectedRole: "AXButton",
            expectedElementTitle: "Next Question →",
            action: .click,
            stepTitle: "Advance Product Feedback Survey Stage",
            stepNotes: "Rate customer NPS satisfaction and progress to multi-choice criteria."
        ),
        PlaygroundLiveRenderVector(
            pageIndex: 9,
            filename: "page9_datagrid.html",
            targetElementId: "btn-batch-export",
            expectedRole: "AXButton",
            expectedElementTitle: "Export Selected",
            action: .click,
            stepTitle: "Batch Export Filtered Records in Data Grid",
            stepNotes: "Perform bulk CSV export on checked data grid rows."
        ),
        PlaygroundLiveRenderVector(
            pageIndex: 10,
            filename: "page10_diagnostics.html",
            targetElementId: "btn-restart-eventtap",
            expectedRole: "AXButton",
            expectedElementTitle: "Restart",
            action: .click,
            stepTitle: "Restart Global EventTap Background Daemon",
            stepNotes: "Flush event buffer cache and restart macOS CGEventTap capture listener."
        )
    ]
    
    @MainActor
    func testPlaygroundWebKitRenderingAllTenPages() async throws {
        for vector in allTenPageVectors {
            let (cgImage, webView) = try await PlaygroundPageRenderer.shared.renderPage(
                filename: vector.filename,
                width: 1200,
                height: 800
            )
            
            XCTAssertGreaterThan(cgImage.width, 0, "Page \(vector.filename) snapshot width should be > 0")
            XCTAssertGreaterThan(cgImage.height, 0, "Page \(vector.filename) snapshot height should be > 0")
            
            let centerPoint = await PlaygroundPageRenderer.shared.getElementCenter(in: webView, elementId: vector.targetElementId)
            XCTAssertNotNil(centerPoint, "Live DOM should resolve center point for element '#\(vector.targetElementId)' in \(vector.filename)")
            
            if let pt = centerPoint {
                XCTAssertGreaterThan(pt.x, 0, "X coordinate of '#\(vector.targetElementId)' should be > 0")
                XCTAssertLessThan(pt.x, 1200, "X coordinate of '#\(vector.targetElementId)' should be within 1200px viewport")
                XCTAssertGreaterThan(pt.y, 0, "Y coordinate of '#\(vector.targetElementId)' should be > 0")
                XCTAssertLessThan(pt.y, 2500, "Y coordinate of '#\(vector.targetElementId)' should be within rendered document bounds")
            }
        }
    }
    
    // MARK: - Table Test 3: Real Visual Step Captures, 2.4x Zoom Crops, and Ripple GIFs Across All 10 Pages
    
    @MainActor
    func testPlaygroundStepCapturesWithZoomAndRippleAllPages() async throws {
        for vector in allTenPageVectors {
            let (annotated, zoomCrop, gifData, targetPoint) = try await PlaygroundPageRenderer.shared.renderStepCapture(
                filename: vector.filename,
                targetElementId: vector.targetElementId,
                stepIndex: vector.pageIndex
            )
            
            // 1. Annotated Full Snapshot
            XCTAssertGreaterThan(annotated.width, 0)
            XCTAssertGreaterThan(annotated.height, 0)
            
            // 2. High-Res 2.4x Zoom Crop
            XCTAssertGreaterThan(zoomCrop.width, 0, "Zoom crop for \(vector.filename) should have non-zero width")
            XCTAssertGreaterThan(zoomCrop.height, 0, "Zoom crop for \(vector.filename) should have non-zero height")
            XCTAssertLessThanOrEqual(zoomCrop.width, annotated.width, "Zoom crop should be cropped from annotated image")
            
            // 3. Multi-Frame Ripple GIF
            XCTAssertFalse(gifData.isEmpty, "Generated GIF data for \(vector.filename) must not be empty")
            let header = String(data: gifData.prefix(6), encoding: .ascii)
            XCTAssertTrue(header == "GIF89a" || header == "GIF87a", "Data should be valid GIF format (was \(header ?? "nil"))")
            
            // 4. Coordinates
            XCTAssertGreaterThan(targetPoint.x, 0)
            XCTAssertGreaterThan(targetPoint.y, 0)
        }
    }
    
    // MARK: - Table Test 4: Live DOM Interactions and State Mutations
    
    @MainActor
    func testPlaygroundDOMInteractionsAndStateMutation() async throws {
        let renderer = PlaygroundPageRenderer.shared
        
        // 1. Page 1: Auth & User Onboarding Form Mutation
        do {
            let (_, webView) = try await renderer.renderPage(filename: "page1_onboarding.html")
            
            try await renderer.setInputValue(in: webView, elementId: "input-fullname", value: "Alex Vance")
            try await renderer.setInputValue(in: webView, elementId: "input-email", value: "alex@stepit.ai")
            
            let clicked = try await renderer.clickElement(in: webView, elementId: "btn-submit-onboarding")
            XCTAssertTrue(clicked, "Should click submit onboarding button")
            
            // Verify toast or confirmation appears
            let toastText = await renderer.getElementText(in: webView, elementId: "action-toast")
            XCTAssertNotNil(toastText)
        }
        
        // 2. Page 2: E-Commerce Stepper Interaction
        do {
            let (_, webView) = try await renderer.renderPage(filename: "page2_checkout.html")
            
            let clickedPlus = try await renderer.clickElement(in: webView, elementId: "btn-qty-plus-1")
            XCTAssertTrue(clickedPlus, "Should click quantity plus stepper")
            
            try await renderer.setInputValue(in: webView, elementId: "input-promo", value: "STEPIT20")
            let clickedApply = try await renderer.clickElement(in: webView, elementId: "btn-apply-promo")
            XCTAssertTrue(clickedApply, "Should click apply promo button")
        }
        
        // 3. Page 9: Data Grid Table Search and Checkbox Selection
        do {
            let (_, webView) = try await renderer.renderPage(filename: "page9_datagrid.html")
            
            try await renderer.setInputValue(in: webView, elementId: "input-search-table", value: "Shivam")
            let clickedCheckAll = try await renderer.clickElement(in: webView, elementId: "check-all-rows")
            XCTAssertTrue(clickedCheckAll, "Should click select all checkbox")
            
            let clickedExport = try await renderer.clickElement(in: webView, elementId: "btn-batch-export")
            XCTAssertTrue(clickedExport, "Should click batch export button")
        }
        
        // 4. Page 10: System Diagnostics Log Injection & Buffer Clear
        do {
            let (_, webView) = try await renderer.renderPage(filename: "page10_diagnostics.html")
            
            let testLog = "TEST_EVENT_TAP_PROBE_SUCCESS"
            try await renderer.setInputValue(in: webView, elementId: "input-log-filter", value: testLog)
            
            let clickedInject = try await renderer.clickElement(in: webView, elementId: "btn-inject-log")
            XCTAssertTrue(clickedInject, "Should click inject log button")
            
            let termText = await renderer.getElementText(in: webView, elementId: "log-terminal")
            XCTAssertTrue(termText?.contains(testLog) == true, "Terminal logs should contain injected message")
            
            let clickedClear = try await renderer.clickElement(in: webView, elementId: "btn-clear-buffer")
            XCTAssertTrue(clickedClear, "Should click clear buffer button")
            
            let toastText = await renderer.getElementText(in: webView, elementId: "action-toast")
            XCTAssertTrue(toastText?.contains("Frame buffer flushed") == true, "Toast should confirm frame buffer flush")
        }
    }
    
    // MARK: - Table Test 5: End-to-End 10-Step Workflow Session (Exclusively Playground Pages)
    
    func testPlaygroundTenPageEndToEndSession() throws {
        var recordedSteps: [Step] = []
        
        for vector in allTenPageVectors {
            let step = Step(
                id: "step_pg_\(vector.pageIndex)",
                index: vector.pageIndex,
                timestamp: Date().addingTimeInterval(Double(vector.pageIndex * 15)),
                action: vector.action,
                appName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                windowTitle: "Page \(vector.pageIndex) — StepIt Playground",
                elementRole: vector.expectedRole,
                elementTitle: vector.expectedElementTitle,
                coordinates: ScreenCoordinates(x: 450.0 + Double(vector.pageIndex * 10), y: 320.0),
                actionDescription: vector.stepTitle,
                userNotes: vector.stepNotes,
                assets: MediaAssets(
                    screenshot: "media/step_\(String(format: "%02d", vector.pageIndex)).png",
                    gif: "media/step_\(String(format: "%02d", vector.pageIndex)).gif",
                    zoomCrop: "media/step_\(String(format: "%02d", vector.pageIndex))_zoom.png"
                )
            )
            
            XCTAssertEqual(step.index, vector.pageIndex)
            XCTAssertEqual(step.action, vector.action)
            XCTAssertEqual(step.appName, "Safari")
            XCTAssertEqual(step.elementRole, vector.expectedRole)
            XCTAssertEqual(step.actionDescription, vector.stepTitle)
            
            let synthesized = Step.synthesizeDefaultDescription(
                action: vector.action,
                elementTitle: vector.expectedElementTitle,
                elementRole: vector.expectedRole,
                appName: "Safari",
                windowTitle: "Page \(vector.pageIndex) — StepIt Playground"
            )
            XCTAssertFalse(synthesized.isEmpty)
            
            recordedSteps.append(step)
        }
        
        XCTAssertEqual(recordedSteps.count, 10, "Workflow must contain all 10 playground steps")
        
        let session = StepSession(
            id: "sess_playground_complete_10_steps",
            title: "Full 10-Page Enterprise Verification Tour",
            theme: .developerDark,
            mediaMode: .hybrid,
            steps: recordedSteps
        )
        
        // 1. Markdown Export Verification
        let md = MarkdownExporter.shared.exportMarkdown(session: session)
        XCTAssertTrue(md.contains("Full 10-Page Enterprise Verification Tour"))
        for vector in allTenPageVectors {
            XCTAssertTrue(md.contains(vector.stepTitle), "Markdown must contain step title '\(vector.stepTitle)'")
            XCTAssertTrue(md.contains("media/step_\(String(format: "%02d", vector.pageIndex)).gif"))
        }
        
        // 2. Interactive WebDoc HTML Verification
        let html = WebDocGenerator.shared.generateHTML(session: session)
        XCTAssertTrue(html.contains("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("Full 10-Page Enterprise Verification Tour"))
        XCTAssertTrue(html.contains("nav-link"), "HTML WebDoc should contain sidebar navigation links")
        XCTAssertTrue(html.contains("data-theme=\"developer-dark\"") || html.contains("developer-dark"), "HTML WebDoc should configure developer-dark theme")
        XCTAssertTrue(html.contains("Checklist Mode"))
        XCTAssertTrue(html.contains("@media print"))
        
        for vector in allTenPageVectors {
            XCTAssertTrue(html.contains(vector.stepTitle), "HTML WebDoc must render step title '\(vector.stepTitle)'")
        }
    }
    
    // MARK: - Table Test 6: Playground Theme & Media Matrix
    
    let themeVectors: [ThemeExportVector] = [
        ThemeExportVector(theme: .developerDark, mediaMode: .hybrid, expectedThemeClass: "theme-developer-dark"),
        ThemeExportVector(theme: .developerDark, mediaMode: .staticOnly, expectedThemeClass: "theme-developer-dark"),
        ThemeExportVector(theme: .modernMinimal, mediaMode: .hybrid, expectedThemeClass: "theme-modern-minimal"),
        ThemeExportVector(theme: .modernMinimal, mediaMode: .animatedOnly, expectedThemeClass: "theme-modern-minimal"),
        ThemeExportVector(theme: .enterpriseSop, mediaMode: .hybrid, expectedThemeClass: "theme-enterprise-sop")
    ]
    
    func testPlaygroundPublishingMatrix() {
        for vector in themeVectors {
            let assets: MediaAssets
            switch vector.mediaMode {
            case .staticOnly:
                assets = MediaAssets(screenshot: "media/step_01.png", gif: nil)
            case .animatedOnly:
                assets = MediaAssets(screenshot: nil, gif: "media/step_01.gif")
            case .hybrid:
                assets = MediaAssets(screenshot: "media/step_01.png", gif: "media/step_01.gif")
            }
            
            let step = Step(
                index: 1,
                action: .click,
                appName: "Safari",
                windowTitle: "Page 1: Auth & User Onboarding — StepIt Playground",
                elementRole: "AXButton",
                elementTitle: "Create Account →",
                coordinates: ScreenCoordinates(x: 340, y: 520),
                actionDescription: "Register Account",
                assets: assets
            )
            
            let session = StepSession(
                id: "sess_pg_matrix_\(vector.theme.rawValue)",
                title: "Playground Guide (\(vector.theme.displayName))",
                theme: vector.theme,
                mediaMode: vector.mediaMode,
                steps: [step]
            )
            
            let html = WebDocGenerator.shared.generateHTML(session: session)
            XCTAssertTrue(html.contains("<!DOCTYPE html>"))
            XCTAssertTrue(html.contains("Playground Guide"))
            XCTAssertTrue(html.contains("Checklist Mode"))
            XCTAssertTrue(html.contains("@media print"))
            
            let md = MarkdownExporter.shared.exportMarkdown(session: session)
            XCTAssertTrue(md.contains("Playground Guide"))
            XCTAssertTrue(md.contains("Register Account"))
            if vector.mediaMode == .staticOnly {
                XCTAssertTrue(md.contains("media/step_01.png"))
            } else {
                XCTAssertTrue(md.contains("media/step_01.gif"))
            }
        }
    }
}
