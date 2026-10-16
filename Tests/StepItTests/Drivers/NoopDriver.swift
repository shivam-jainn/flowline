import Foundation
@testable import StepItCore

/// Compile-only stub that locks the `CaptureDriver` protocol shape: it
/// implements all three facets with empty bodies and no platform hooks.
final class NoopDriver: CaptureDriver {
    let platformIdentifier = "noop"
    let capabilities: CaptureCapabilities = .mockFull
    let eventStream: AsyncStream<RawInputEvent>
    private let continuation: AsyncStream<RawInputEvent>.Continuation

    init() {
        var cont: AsyncStream<RawInputEvent>.Continuation!
        self.eventStream = AsyncStream<RawInputEvent> { cont = $0 }
        self.continuation = cont
    }

    func start() async throws {}
    func pause() async {}
    func resume() async {}

    func stop() async {
        continuation.finish()
    }

    func inspectElement(at point: Point2D) async -> RawElementContext? { nil }
    func inspectFocusedElement() async -> RawElementContext? { nil }

    func startClipBuffering(config: ClipBufferConfig) async {}
    func stopClipBuffering() async {}
    func captureSnapshot(highlightAt point: Point2D?, stepIndex: Int) async -> FrameSnapshot? { nil }
    func captureMicroClip(around point: Point2D, postDuration: TimeInterval) async -> ClipAsset? { nil }
}
