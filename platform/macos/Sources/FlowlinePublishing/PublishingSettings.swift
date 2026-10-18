import Foundation
import FlowlineIR

/// Documentation output configuration (R/M1-07: moved from FlowlineCore).
/// Owned by the publishing target; consumed by the web/PDF exporters.
public struct PublishingSettings: Codable, Sendable, Equatable {
    public var defaultTheme: ThemeName
    public var authorName: String
    public var companyName: String
    public var enableInteractiveChecklists: Bool
    public var pdfPaperSize: String
    public var includeTimestamp: Bool
    /// Selectable keystroke + mouse visual styles (web/PDF + native stage).
    public var keycapStyle: KeycapStyle
    public var mouseStyle: MouseStyle

    public init(
        defaultTheme: ThemeName = .modernMinimal,
        authorName: String = "",
        companyName: String = "Flowline Docs",
        enableInteractiveChecklists: Bool = true,
        pdfPaperSize: String = "A4",
        includeTimestamp: Bool = true,
        keycapStyle: KeycapStyle = .mac3D,
        mouseStyle: MouseStyle = .mac3D
    ) {
        self.defaultTheme = defaultTheme
        self.authorName = authorName
        self.companyName = companyName
        self.enableInteractiveChecklists = enableInteractiveChecklists
        self.pdfPaperSize = pdfPaperSize
        self.includeTimestamp = includeTimestamp
        self.keycapStyle = keycapStyle
        self.mouseStyle = mouseStyle
    }

    private enum Keys: String, CodingKey {
        case defaultTheme, authorName, companyName
        case enableInteractiveChecklists, pdfPaperSize, includeTimestamp
        case keycapStyle, mouseStyle
    }

    /// Tolerant decode: pre-style payloads lack the new keys.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        defaultTheme = try c.decodeIfPresent(ThemeName.self, forKey: .defaultTheme) ?? .modernMinimal
        authorName = try c.decodeIfPresent(String.self, forKey: .authorName) ?? ""
        companyName = try c.decodeIfPresent(String.self, forKey: .companyName) ?? "Flowline Docs"
        enableInteractiveChecklists = try c.decodeIfPresent(Bool.self, forKey: .enableInteractiveChecklists) ?? true
        pdfPaperSize = try c.decodeIfPresent(String.self, forKey: .pdfPaperSize) ?? "A4"
        includeTimestamp = try c.decodeIfPresent(Bool.self, forKey: .includeTimestamp) ?? true
        keycapStyle = try c.decodeIfPresent(KeycapStyle.self, forKey: .keycapStyle) ?? .mac3D
        mouseStyle = try c.decodeIfPresent(MouseStyle.self, forKey: .mouseStyle) ?? .mac3D
    }
}
