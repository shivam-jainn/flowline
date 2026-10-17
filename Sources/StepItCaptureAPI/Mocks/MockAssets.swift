import Foundation
import StepItIR
import StepItPipeline

/// Deterministic byte-valid assets for headless tests.
///
/// `MockCaptureDriver` hands these back so `SessionStore.saveMedia` and the
/// exporters run against real image bytes without a physical screen.
public enum MockAssets {
    /// A real 1×1 red PNG (70 bytes).
    public static let onePixelPNG: Data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP4z8DwHwAFAAH/VscvDQAAAABJRU5ErkJggg==")!

    /// A GIF container stub with the GIF89a magic bytes; enough for
    /// `saveMedia` round-trips that only check file identity.
    public static let gifStub: Data = Data("GIF89a".utf8)

    /// An MP4 container stub with an `ftyp` box header.
    public static let mp4Stub: Data = Data([0x00, 0x00, 0x00, 0x18] + Array("ftypmp42".utf8))
}
