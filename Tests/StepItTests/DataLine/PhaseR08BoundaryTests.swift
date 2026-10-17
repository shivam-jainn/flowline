import XCTest
import Foundation
import StepItIR
import StepItPipeline
import StepItEngine
import StepItStorage
import StepItCaptureAPI
import StepItPublishing
import StepItAIGateway
import StepItFixtures

/// R/M1-08: module boundary proof (mirrors the extended arch gate at runtime).
final class PhaseR08BoundaryTests: XCTestCase {
    func testRegistriesResolveEndToEnd() {
        let drivers = DriverRegistry()
        drivers.register(
            manifest: PluginManifest(id: "mock", version: "1.0.0"),
            factory: { MockCaptureDriver() })
        drivers.register(
            manifest: PluginManifest(id: "noop", version: "1.0.0"),
            factory: { MockCaptureDriver() })
        XCTAssertEqual(drivers.registeredIDs, ["mock", "noop"])
        XCTAssertNotNil(drivers.resolve(id: "mock"))
        XCTAssertNotNil(drivers.resolve(id: "noop"))

        let exporters = ExporterRegistry()
        final class StubExporter: SessionExporter {
            let exporterID = "stub"
            func export(session: Any, to directory: URL) throws -> ExportArtifact {
                ExportArtifact(relativePath: "stub.md", mimeType: "text/markdown")
            }
        }
        exporters.register(
            manifest: PluginManifest(id: "stub", version: "1.0.0"),
            factory: { StubExporter() })
        XCTAssertNotNil(exporters.resolve(id: "stub"))

        let providers = ProviderRegistry()
        final class StubProvider: GatewayProvider {
            let providerID = "stub"
            func complete(request: GatewayRequest) async throws -> GatewayResponse {
                GatewayResponse(text: "ok")
            }
        }
        providers.register(
            manifest: PluginManifest(id: "stub", version: "1.0.0"),
            factory: { StubProvider() })
        XCTAssertNotNil(providers.resolve(id: "stub"))
    }

    func testNoSharedAtModuleCallSites() throws {
        // Mirror of the gate's singleton rule: the five named singletons must
        // not be *used* outside the composition root. Scans module + surface
        // sources (tests exempt, defining shims exempt).
        let thisFile = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // PhaseR08BoundaryTests.swift
            .deletingLastPathComponent() // DataLine
            .deletingLastPathComponent() // StepItTests
            .deletingLastPathComponent() // Tests → <repo root>
        let sources = thisFile.appendingPathComponent("Sources", isDirectory: true)
        let names = ["SessionStore", "ScreenRecorder", "MicroClipRecorder",
                     "PublishingCoordinator", "AIGatewayClient"]
        let allowedDirs = ["StepIt/App", "main.swift"]
        var violations: [String] = []
        let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let path = url.path
            if path.contains("Sources/StepIt/App/") || path.hasSuffix("Sources/StepIt/main.swift") { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            for line in text.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") { continue }
                for name in names where line.contains("\(name).shared") {
                    // The `static let shared` declaration itself is allowed.
                    if line.contains("static let shared") { continue }
                    violations.append("\(url.lastPathComponent): \(trimmed)")
                }
            }
        }
        XCTAssertTrue(violations.isEmpty, "named .shared outside composition root: \(violations)")
    }

    func testSettingsSplitByModule() {
        // Each settings type lives next to its owning module.
        XCTAssertTrue(CaptureSettings().highlightClicks)
        XCTAssertTrue(GestureSettings().shakeToPauseEnabled)
        XCTAssertEqual(HotkeySettings().toggleRecording, "⌥ Space")
        XCTAssertTrue(PrivacySettings().maskSecureInputFields)
        XCTAssertTrue(HotkeyCaptureSettings().captureModifierShortcuts)
        XCTAssertEqual(GatewaySettings().provider, .openRouter)
        XCTAssertEqual(PublishingSettings().companyName, "StepIt Docs")
        XCTAssertFalse(StepItSettings().capture.recordAppSwitches)
    }
}
