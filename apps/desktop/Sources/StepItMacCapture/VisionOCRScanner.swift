import Foundation
import StepItIR
import StepItPipeline
import StepItCaptureAPI
import Vision
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// On-device Apple Vision text recognition used by the redaction pipeline.
///
/// Performance rules (mitigation R1/R5):
/// - runs on a dedicated serial queue (`com.stepit.visionocr`), never the
///   engine actor's thread or the main thread;
/// - down-samples frames wider/taller than `maximumDimension` before scanning;
/// - reuses one `VNRecognizeTextRequest` across scans (the queue serializes it)
///   and releases pixel buffers as soon as observations are collected.
public final class VisionOCRScanner: OCRScanning, @unchecked Sendable {

    public struct Configuration: Sendable {
        /// Frames whose largest dimension exceeds this are down-sampled (R5).
        public var maximumDimension: Int
        public var recognitionLevel: VNRequestTextRecognitionLevel
        public var usesLanguageCorrection: Bool

        public init(
            maximumDimension: Int = 2560,
            recognitionLevel: VNRequestTextRecognitionLevel = .accurate,
            usesLanguageCorrection: Bool = false
        ) {
            self.maximumDimension = maximumDimension
            self.recognitionLevel = recognitionLevel
            self.usesLanguageCorrection = usesLanguageCorrection
        }
    }

    public var configuration: Configuration

    private let queue = DispatchQueue(label: "com.stepit.visionocr", qos: .utility)
    private var reusableRequest: VNRecognizeTextRequest?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public func scanText(in pngData: Data) async -> [OCRTextItem] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: scanSynchronously(pngData: pngData))
            }
        }
    }

    // MARK: - Synchronous core (serial queue)

    private func scanSynchronously(pngData: Data) -> [OCRTextItem] {
        guard let image = Self.decode(pngData: pngData, maximumDimension: configuration.maximumDimension) else {
            return []
        }

        let request = reusableRequest ?? makeRequest()
        reusableRequest = request

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let observations = request.results else { return [] }
        var items: [OCRTextItem] = []
        items.reserveCapacity(observations.count)
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first, !candidate.string.isEmpty else { continue }
            let box = observation.boundingBox
            items.append(OCRTextItem(
                text: candidate.string,
                boundingBox: ElementRect(
                    x: Double(box.origin.x),
                    y: Double(box.origin.y),
                    width: Double(box.width),
                    height: Double(box.height)
                )
            ))
        }
        return items
    }

    private func makeRequest() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = configuration.recognitionLevel
        request.usesLanguageCorrection = configuration.usesLanguageCorrection
        return request
    }

    /// Decodes and (when needed) down-samples PNG data to a `CGImage`.
    static func decode(pngData: Data, maximumDimension: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil) else { return nil }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? Int) ?? 0
        let largest = max(width, height)

        if maximumDimension > 0, largest > maximumDimension {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumDimension
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
