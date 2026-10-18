import Foundation
import FlowlineIR

/// Post-capture redaction planner (Phase 2, T7).
///
/// Pure core step of the OCR redaction pipeline: takes the text regions the
/// driver's `VisionOCRScanner` extracted (or a mock produced) and decides which
/// normalized rectangles the driver's `BlurCompositor` must blur. Foundation-only
/// so the decisions are fully unit-testable (`PrivacyRedactionTests`).
public struct PrivacyRedactionEngine: Sendable {

    public struct Plan: Sendable, Equatable {
        /// Normalized (`0…1`, Vision bottom-left origin) regions to blur.
        public var regions: [ElementRect]
        /// Every sensitive token that triggered a region.
        public var matches: [SensitiveDataMatch]
        /// Convenience: at least one region needs redaction.
        public var isRedacted: Bool { !regions.isEmpty }

        public init(regions: [ElementRect], matches: [SensitiveDataMatch]) {
            self.regions = regions
            self.matches = matches
        }
    }

    public let settings: PrivacySettings
    private let detector: SensitiveDataDetector

    public init(settings: PrivacySettings = PrivacySettings()) {
        self.settings = settings
        self.detector = SensitiveDataDetector(privacy: settings)
    }

    public init(settings: PrivacySettings, detector: SensitiveDataDetector) {
        self.settings = settings
        self.detector = detector
    }

    /// Empty when OCR redaction is disabled in settings.
    public func plan(for items: [OCRTextItem]) -> Plan {
        guard settings.enableOfflineOCRRedaction else {
            return Plan(regions: [], matches: [])
        }

        var regions: [ElementRect] = []
        var matches: [SensitiveDataMatch] = []

        for item in items {
            let itemMatches = detector.matches(in: item.text)
            guard !itemMatches.isEmpty else { continue }
            matches.append(contentsOf: itemMatches)
            // OCR granularity is a text line: the whole observation box is
            // blurred, which guarantees partial-line secrets are covered.
            regions.append(Self.padded(item.boundingBox))
        }

        return Plan(regions: regions, matches: matches)
    }

    /// Small padding so glyphs are fully covered by the blur rectangle.
    static func padded(_ rect: ElementRect, ratio: Double = 0.08) -> ElementRect {
        let padX = rect.width * ratio
        let padY = rect.height * ratio
        return ElementRect(
            x: max(0, rect.x - padX),
            y: max(0, rect.y - padY),
            width: min(1 - max(0, rect.x - padX), rect.width + padX * 2),
            height: min(1 - max(0, rect.y - padY), rect.height + padY * 2)
        )
    }
}
