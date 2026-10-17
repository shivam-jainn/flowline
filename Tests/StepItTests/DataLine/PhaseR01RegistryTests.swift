import XCTest
import StepItIR
import StepItPipeline
import StepItCaptureAPI
import StepItPublishing
import StepItAIGateway

final class StubDriver: NSObject {}
final class StubExporter: NSObject {}
final class StubProvider: NSObject {}

final class PhaseR01RegistryTests: XCTestCase {
    func testManifestValidation() {
        let m = PluginManifest(id: "mock", version: "1.0", capabilities: ["clips"], minimumHostVersion: "r-m1")
        XCTAssertTrue(m.validateHost(version: "r-m1"))
        XCTAssertTrue(m.supports("clips"))
        XCTAssertFalse(m.supports("nope"))
        let future = PluginManifest(id: "x", version: "2.0", minimumHostVersion: "r-m99")
        XCTAssertNil(DriverRegistry().resolve(id: "missing"))
        XCTAssertFalse(future.validateHost(version: "r-m1"))
    }

    func testDriverRegistry() {
        let r = DriverRegistry()
        r.register(manifest: PluginManifest(id: "mock", version: "1.0"), factory: { StubDriver() })
        r.register(manifest: PluginManifest(id: "noop", version: "1.0"), factory: { StubDriver() })
        XCTAssertEqual(r.registeredIDs, ["mock", "noop"])
        XCTAssertNotNil(r.resolve(id: "mock"))
        XCTAssertNil(r.resolve(id: "windows"))
    }

    func testExporterRegistry() {
        let r = ExporterRegistry()
        r.register(manifest: PluginManifest(id: "markdown", version: "1.0"), factory: { StubExporter() })
        XCTAssertEqual(r.registeredIDs, ["markdown"])
        XCTAssertNotNil(r.resolve(id: "markdown"))
    }

    func testProviderRegistry() {
        let r = ProviderRegistry()
        r.register(manifest: PluginManifest(id: "stub", version: "1.0"), factory: { StubProvider() })
        XCTAssertNotNil(r.resolve(id: "stub"))
        XCTAssertNil(r.resolve(id: "openai"))
    }

    func testVersionMismatchFailsFast() {
        let r = ProviderRegistry()
        r.register(manifest: PluginManifest(id: "future", version: "9.9", minimumHostVersion: "r-m99"), factory: { StubProvider() })
        XCTAssertNil(r.resolve(id: "future", hostVersion: "r-m1"))
    }
}
