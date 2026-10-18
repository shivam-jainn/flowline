import XCTest
import Foundation
import FlowlineIR
import FlowlinePublishing
import FlowlineTemplates

/// R/M1-11: guide-preview quirks. The Reader's right-hand text pane renders
/// the same steps 7 ways (one `GuideTemplate` per `FlowlineGuideMode`); this
/// pins the one visible quirk per mode documented in
/// `shared/goldens/guide-preview.sample.md` and `templates/<mode>/preview.md`
/// against the real `TemplateRenderer`, so a template regression shows up
/// here. Real `MarkdownExporter` output is asserted for the overlapping
/// runbook/reference quirks.
final class PhaseR11GuidePreviewTests: XCTestCase {
    /// Mirrors `shared/goldens/session.sample.json` (3 steps).
    private func makeGoldenSession() -> StepSession {
        let step1 = Step(
            id: "step-0001",
            index: 1,
            timestamp: Date(timeIntervalSince1970: 1_770_000_000),
            action: .click,
            appName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            windowTitle: "Docs — Safari",
            elementRole: "AXButton",
            elementTitle: "Save",
            coordinates: ScreenCoordinates(x: 100, y: 200),
            actionDescription: "Click \"Save\" in Docs — Safari",
            assets: MediaAssets()
        )
        let step2 = Step(
            id: "step-0002",
            index: 2,
            timestamp: Date(timeIntervalSince1970: 1_770_000_001),
            action: .writeCode,
            appName: "Terminal",
            windowTitle: "zsh",
            actionDescription: "Run \"git status\" in Terminal",
            textBlob: "git status",
            isCode: true,
            assets: MediaAssets(),
            workingDirectory: "~/Code/flowline"
        )
        let step3 = Step(
            id: "step-0003",
            index: 3,
            timestamp: Date(timeIntervalSince1970: 1_770_000_002),
            action: .keyPress,
            appName: "Safari",
            windowTitle: "Docs — Safari",
            actionDescription: "Press ⌘S",
            assets: MediaAssets(),
            hotkeyCombo: "⌘S"
        )
        return StepSession(
            id: "sess_00000001",
            startedAt: Date(timeIntervalSince1970: 1_770_000_000),
            title: "Golden Session",
            theme: .modernMinimal,
            mediaMode: .hybrid,
            steps: [step1, step2, step3]
        )
    }

    private func template(_ id: String) throws -> GuideTemplate {
        try XCTUnwrap(GuideTemplate.make(id: id), "missing built-in template: \(id)")
    }

    private func guide(_ id: String, session: StepSession) throws -> String {
        TemplateRenderer.renderGuide(session: session, template: try template(id))
    }

    func testRegistryHoldsAllSevenModes() {
        XCTAssertEqual(TemplateRegistry.withDefaults().allIDs,
                       ["checklist", "presentation", "reference", "runbook", "sop", "standard", "tutorial"])
    }

    func testEachModeHasItsQuirk() throws {
        let session = makeGoldenSession()
        // Standard: plain titles, no markers.
        let standard = try guide("standard", session: session)
        XCTAssertTrue(standard.contains("Step 1: Click \"Save\" in Docs — Safari"))
        XCTAssertFalse(standard.contains("- [ ]"))
        // Checklist: tick boxes on every step.
        let checklist = try guide("checklist", session: session)
        XCTAssertEqual(checklist.components(separatedBy: "- [ ]").count - 1, 3)
        XCTAssertTrue(checklist.contains("- [ ] Step 2: Run \"git status\" in Terminal"))
        // SOP: numbered steps, no `Step N:` prefix.
        let sop = try guide("sop", session: session)
        XCTAssertTrue(sop.contains("1. Click \"Save\" in Docs — Safari"))
        XCTAssertFalse(sop.contains("Step 1:"))
        // Tutorial: app/window context line per step.
        let tutorial = try guide("tutorial", session: session)
        XCTAssertTrue(tutorial.contains("(Safari · Docs — Safari)"))
        XCTAssertTrue(tutorial.contains("(Terminal · zsh)"))
        // Runbook: fenced command + Keys line.
        let runbook = try guide("runbook", session: session)
        XCTAssertTrue(runbook.contains("```bash\ngit status\n```"))
        XCTAssertTrue(runbook.contains("Keys: ⌘S"))
        // Presentation: uppercased titles (POSIX locale).
        let presentation = try guide("presentation", session: session)
        XCTAssertTrue(presentation.contains("STEP 1: CLICK \"SAVE\" IN DOCS — SAFARI"))
        // Reference: compact target lines.
        let reference = try guide("reference", session: session)
        XCTAssertTrue(reference.contains("Click → Save · Safari"))
        XCTAssertTrue(reference.contains("Write → zsh · Terminal"))
        XCTAssertTrue(reference.contains("⌘S → Docs — Safari · Safari"))
    }

    func testUnknownTemplateFallsBackToStandard() throws {
        let session = makeGoldenSession()
        let fallback = GuideTemplate(id: "nope", label: "Nope", copy: "", theme: "", synthesisStyle: "")
        let out = TemplateRenderer.renderStep(step: session.steps[0], index: 1, template: fallback)
        XCTAssertEqual(out, "Step 1: Click \"Save\" in Docs — Safari")
    }

    func testRealExporterCarriesRunbookAndReferenceQuirks() {
        let session = makeGoldenSession()
        let md = MarkdownExporter.shared.exportMarkdown(session: session)
        // Runbook quirk: commands render as fenced code.
        XCTAssertTrue(md.contains("```bash\ngit status\n```"))
        // Reference quirk: target element + shortcut survive the projection.
        XCTAssertTrue(md.contains("(`Save`)"))
        XCTAssertTrue(md.contains("`⌘S`"))
        // Deterministic: same bytes on every run.
        XCTAssertEqual(md, MarkdownExporter.shared.exportMarkdown(session: session))
    }
}
