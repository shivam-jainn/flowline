import XCTest
import StepItPipeline
import StepItEngine
import StepItStorage
import StepItCaptureAPI
import StepItMacCapture
import StepItAIGateway
import StepItPermissions
import Foundation
import StepItIR
import StepItPublishing

/// R/M1-06: Publishing extraction proof. Markdown/WebDoc output is byte-stable
/// across the move + WebDoc split, and the three extracted targets stay
/// AppKit-free (no `import AppKit`, no `NSWorkspace`/`NSImage` code usage).
final class PhaseR06PublishTests: XCTestCase {
    private func makeFixtureSession() -> StepSession {
        let step1 = Step(
            index: 1,
            timestamp: Date(timeIntervalSince1970: 1_769_000_000),
            action: .click,
            appName: "Safari",
            windowTitle: "Example",
            elementRole: "AXButton",
            elementTitle: "Sign in",
            coordinates: ScreenCoordinates(x: 100, y: 200),
            actionDescription: "Click the Sign in button",
            assets: MediaAssets(screenshot: "media/step_01.png")
        )
        let step2 = Step(
            index: 2,
            timestamp: Date(timeIntervalSince1970: 1_769_000_060),
            action: .keyPress,
            appName: "Safari",
            windowTitle: "Example",
            actionDescription: "Press Save shortcut",
            textBlob: "echo hi",
            isCode: true,
            codeLanguage: "bash",
            assets: MediaAssets(gif: "media/step_02.gif"),
            hotkeyCombo: "⌘S"
        )
        return StepSession(
            id: "sess_r06fixture",
            startedAt: Date(timeIntervalSince1970: 1_769_000_000),
            title: "R06 Publish Fixture",
            summary: "Covers publish paths.",
            theme: .modernMinimal,
            mediaMode: .hybrid,
            steps: [step1, step2]
        )
    }

    func testMarkdownExporterGoldenMarkers() throws {
        let session = makeFixtureSession()
        // Encode once: fixture itself must be stable and Codable.
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(StepSession.self, from: data)
        XCTAssertEqual(decoded.steps.count, 2)

        let md = MarkdownExporter.shared.exportMarkdown(session: session, relativeAssetPrefix: "../")
        XCTAssertTrue(md.contains("# R06 Publish Fixture"))
        XCTAssertTrue(md.contains("> Covers publish paths."))
        XCTAssertTrue(md.contains("## Table of Contents"))
        XCTAssertTrue(md.contains("## Workflow Steps"))
        XCTAssertTrue(md.contains("### Step 1: Click the Sign in button"))
        XCTAssertTrue(md.contains("### Step 2: Press Save shortcut"))
        XCTAssertTrue(md.contains("`⌘S`"))
        XCTAssertTrue(md.contains("![Click the Sign in button](../media/step_01.png)"))
        XCTAssertTrue(md.contains("![Press Save shortcut](../media/step_02.gif)"))
        XCTAssertTrue(md.contains("step·it"))

        // Deterministic: same bytes on every run.
        let again = MarkdownExporter.shared.exportMarkdown(session: session, relativeAssetPrefix: "../")
        XCTAssertEqual(md, again)
    }

    func testWebDocGeneratorGoldenMarkers() {
        let session = makeFixtureSession()
        let html = WebDocGenerator.shared.generateHTML(
            session: session,
            settings: PublishingSettings(),
            assetBaseURL: "media"
        )
        XCTAssertTrue(html.contains("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("data-theme=\"modern-minimal\""))
        XCTAssertTrue(html.contains("R06 Publish Fixture"))
        XCTAssertTrue(html.contains("id=\"step-card-1\""))
        XCTAssertTrue(html.contains("id=\"step-card-2\""))
        XCTAssertTrue(html.contains("0 of 2 completed"))
        XCTAssertTrue(html.contains("STEP 01"))
        XCTAssertTrue(html.contains("media/step_01.png"))
        XCTAssertTrue(html.contains("media/step_02.gif"))

        // Deterministic: same bytes on every run.
        let again = WebDocGenerator.shared.generateHTML(
            session: session,
            settings: PublishingSettings(),
            assetBaseURL: "media"
        )
        XCTAssertEqual(html, again)
    }

    func testExtractedTargetsHaveNoAppKit() throws {
        let thisFile = URL(fileURLWithPath: #file)
        let repoRoot = thisFile
            .deletingLastPathComponent() // PhaseR06PublishTests.swift
            .deletingLastPathComponent() // DataLine
            .deletingLastPathComponent() // StepItTests
            .deletingLastPathComponent() // Tests → <repo root>
        for target in ["StepItPublishing", "StepItAIGateway", "StepItPermissions"] {
            let dir = repoRoot.appendingPathComponent("Sources/\(target)", isDirectory: true)
            let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "swift" }
            XCTAssertFalse(files.isEmpty, "expected swift files in \(target)")
            for file in files {
                let text = try String(contentsOf: file, encoding: .utf8)
                for rawLine in text.components(separatedBy: "\n") {
                    let line = rawLine.trimmingCharacters(in: .whitespaces)
                    if line.hasPrefix("//") { continue } // doc comments may name removed APIs
                    XCTAssertFalse(line.contains("import AppKit"), "\(file.lastPathComponent): \(line)")
                    XCTAssertFalse(line.contains("NSWorkspace"), "\(file.lastPathComponent): \(line)")
                    XCTAssertFalse(line.contains("NSImage"), "\(file.lastPathComponent): \(line)")
                }
            }
        }
    }
}
