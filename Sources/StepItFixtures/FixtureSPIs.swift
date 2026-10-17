import CoreGraphics
import Foundation

/// Service-provider interfaces for fixture generation (R/M1-07).
///
/// Fixture builders take these by constructor injection so the composition
/// root (and tests) can supply doubles; live defaults keep the one-liner
/// static conveniences working without singletons.

/// Renders a playground page into an annotated screenshot + zoom crop + GIF.
/// Conformed to by `PlaygroundPageRenderer` (see below); behavior unchanged.
public protocol PlaygroundCaptureRenderer: AnyObject, Sendable {
    @MainActor
    func renderStepCapture(
        filename: String,
        targetElementId: String,
        stepIndex: Int
    ) async throws -> (screenshot: CGImage, zoomCrop: CGImage, gifData: Data, targetPoint: CGPoint)
}

/// Pure pixel encoding: `CGImage` → PNG bytes.
/// Backed by `ScreenRecorder.imageToPNGData` in live wiring.
public typealias PNGEncoder = @Sendable (CGImage) -> Data?

extension PlaygroundPageRenderer: PlaygroundCaptureRenderer {
    // Forwards to the canonical 5-parameter renderer with the default canvas
    // size (extra defaulted parameters do not satisfy a protocol witness).
    @MainActor
    public func renderStepCapture(
        filename: String,
        targetElementId: String,
        stepIndex: Int
    ) async throws -> (screenshot: CGImage, zoomCrop: CGImage, gifData: Data, targetPoint: CGPoint) {
        try await renderStepCapture(
            filename: filename,
            targetElementId: targetElementId,
            stepIndex: stepIndex,
            width: 1200,
            height: 800
        )
    }
}
