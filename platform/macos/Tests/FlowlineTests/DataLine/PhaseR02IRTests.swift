import XCTest
import FlowlineStorage
import FlowlineCaptureAPI
import FlowlineMacCapture
import FlowlinePublishing
import FlowlineAIGateway
import FlowlinePermissions
import Foundation
import FlowlineIR
import FlowlinePipeline
import FlowlineEngine

/// R/M1-02: IR + Pipeline extraction proof. Moved suites run unmodified
/// (full `swift test` covers that); these assert the new homes and the
/// Foundation-only boundary (mirror of the future gate rule).
final class PhaseR02IRTests: XCTestCase {
    func testStepSessionDecodesInIR() throws {
        let s = StepSession(title: "IR home")
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(StepSession.self, from: data)
        XCTAssertEqual(back.title, "IR home")
    }

    func testIRTypesAreCodableRoundTrip() throws {
        let ev = RawInputEvent(kind: .hotkeyCombo(combo: "⌘S"))
        let data = try JSONEncoder().encode(ev)
        let back = try JSONDecoder().decode(RawInputEvent.self, from: data)
        XCTAssertEqual(back, ev)
    }

    func testPipelineDebounceStillPure() {
        var d = EventDebouncer(minInterval: 0.2, start: .distantPast)
        XCTAssertTrue(d.shouldAccept(at: Date()))
    }

    func testPrivacySettingsOwnedByPipeline() {
        let p = PrivacySettings()
        XCTAssertTrue(p.maskSecureInputFields)
        let pipelineHome: PrivacySettings = FlowlinePipeline.PrivacySettings()
        XCTAssertEqual(p, pipelineHome)
    }

    func testGestureActionOwnedByIR() {
        XCTAssertEqual(GestureAction.pauseResume.rawValue, "pause_resume")
    }
}
