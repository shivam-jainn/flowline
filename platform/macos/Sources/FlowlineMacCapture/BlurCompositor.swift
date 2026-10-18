import Foundation
import FlowlineIR
import FlowlinePipeline
import CoreImage
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// CoreImage compositor that paints redaction regions onto a captured frame
/// (Phase 2, T7 / T6).
///
/// Two treatments:
/// - `.frostedGlass`: `CIGaussianBlur` (clamped source, cropped back to the
///   region so the blur pulls real neighbouring pixels);
/// - `.blackout`: opaque rectangular fill.
///
/// Used for both OCR-detected secrets (normalized Vision boxes) and secure
/// password fields (screen-space element rects mapped by the caller).
public struct BlurCompositor: Sendable {

    public struct Configuration: Sendable {
        public var style: RedactionBlurStyle
        /// Blur radius in screen points (scaled to pixels internally).
        public var radius: Double

        public init(style: RedactionBlurStyle = .frostedGlass, radius: Double = 12.0) {
            self.style = style
            self.radius = radius
        }
    }

    /// Shared context: `CIContext` creation is expensive and the compositor is
    /// stateless.
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    public let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: - Public API

    /// Applies the configured treatment over normalized (`0…1`, Vision
    /// bottom-left origin) regions. Returns `nil` only when the PNG cannot be
    /// decoded or re-encoded (callers fall back to the original data).
    public func apply(to pngData: Data, normalizedRegions: [ElementRect], scale: Double = 1.0) -> Data? {
        guard !normalizedRegions.isEmpty else { return pngData }
        guard let image = CIImage(data: pngData) else { return nil }

        let extent = image.extent
        let pixelRegions = normalizedRegions.compactMap { region -> CGRect? in
            let rect = CGRect(
                x: extent.origin.x + region.x * extent.width,
                y: extent.origin.y + region.y * extent.height,
                width: region.width * extent.width,
                height: region.height * extent.height
            ).intersection(extent)
            return rect.isNull || rect.isEmpty ? nil : rect
        }
        return render(image: image, pixelRegions: pixelRegions, scale: scale)
    }

    /// Applies the configured treatment over absolute pixel rectangles.
    public func apply(to pngData: Data, pixelRegions: [CGRect], scale: Double = 1.0) -> Data? {
        guard !pixelRegions.isEmpty else { return pngData }
        guard let image = CIImage(data: pngData) else { return nil }

        let clipped = pixelRegions
            .map { $0.intersection(image.extent) }
            .filter { !$0.isNull && !$0.isEmpty }
        return render(image: image, pixelRegions: clipped, scale: scale)
    }

    // MARK: - Rendering

    private func render(image: CIImage, pixelRegions: [CGRect], scale: Double) -> Data? {
        guard !pixelRegions.isEmpty else { return nil }

        var output = image
        for rect in pixelRegions {
            let overlay = redactionOverlay(for: image, region: rect, scale: scale)
            output = overlay.composited(over: output)
        }

        guard let cgImage = Self.context.createCGImage(output, from: image.extent) else { return nil }
        return Self.encodePNG(cgImage)
    }

    private func redactionOverlay(for image: CIImage, region: CGRect, scale: Double) -> CIImage {
        switch configuration.style {
        case .frostedGlass:
            let sigma = max(2.0, configuration.radius * max(scale, 1.0))
            guard let blur = CIFilter(name: "CIGaussianBlur", parameters: [
                kCIInputImageKey: image.clampedToExtent(),
                kCIInputRadiusKey: sigma
            ])?.outputImage else {
                return blackoutOverlay(region: region)
            }
            return blur.cropped(to: region)

        case .blackout:
            return blackoutOverlay(region: region)
        }
    }

    private func blackoutOverlay(region: CGRect) -> CIImage {
        CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1.0)).cropped(to: region)
    }

    public static func encodePNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
