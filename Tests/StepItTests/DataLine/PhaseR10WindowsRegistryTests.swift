import XCTest
import StepItIR
import StepItCaptureAPI
import StepItFFI

/// R/M3-01 (deferred close-out): the `windows` driver resolves alongside
/// mac/mock/noop with the manifest mirroring
/// `stepit_win_capture::plugin::windows_manifest()` 1:1.
final class PhaseR10WindowsRegistryTests: XCTestCase {
    private func windowsManifest() -> PluginManifest {
        PluginManifest(
            id: "windows",
            version: "1.0.0",
            capabilities: ["snapshots", "micro-clips", "accessibility-tree", "secure-field-detection"],
            minimumHostVersion: "r-m1"
        )
    }

    func testWindowsResolvesAlongsideMockAndNoop() {
        let registry = DriverRegistry()
        registry.register(
            manifest: PluginManifest(id: "mock", version: "1.0.0", minimumHostVersion: "r-m1"),
            factory: { MockCaptureDriver() }
        )
        registry.register(
            manifest: PluginManifest(id: "noop", version: "1.0.0", minimumHostVersion: "r-m1"),
            factory: { MockCaptureDriver() }
        )
        registry.register(manifest: windowsManifest(), factory: { MockCaptureDriver() })

        XCTAssertEqual(registry.registeredIDs, ["mock", "noop", "windows"])
        XCTAssertNotNil(registry.resolve(id: "windows"))
        XCTAssertNil(registry.resolve(id: "windows", hostVersion: "r-m0"))
        XCTAssertEqual(
            registry.manifest(id: "windows")?.capabilities,
            ["snapshots", "micro-clips", "accessibility-tree", "secure-field-detection"]
        )
    }

    func testWindowsManifestValidViaFFI() {
        let manifest = """
        {"id":"windows","version":"1.0.0","capabilities":["snapshots","micro-clips",\
        "accessibility-tree","secure-field-detection"],"minimumHostVersion":"r-m1"}
        """
        XCTAssertTrue(manifestValidForHost(manifestJson: manifest, hostVersion: "r-m1"))
        XCTAssertFalse(manifestValidForHost(manifestJson: manifest, hostVersion: "r-m0"))
    }
}
