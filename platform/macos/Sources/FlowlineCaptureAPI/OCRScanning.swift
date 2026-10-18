import Foundation
import FlowlineIR

/// OCR seam (Phase 2, T7): extracts text + normalized regions from a captured
/// PNG. The engine/`PrivacyRedactionEngine` only sees `OCRTextItem`s, so
/// headless tests inject deterministic fixtures instead of running Vision.
public protocol OCRScanning: Sendable {
    /// Runs offline text recognition over `pngData`. Never throws — an
    /// unreadable frame simply yields no regions.
    func scanText(in pngData: Data) async -> [OCRTextItem]
}
