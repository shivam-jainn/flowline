import Foundation
import StepItIR

/// Documentation output configuration (R/M1-07: moved from StepItCore).
/// Owned by the publishing target; consumed by the web/PDF exporters.
public struct PublishingSettings: Codable, Sendable, Equatable {
    public var defaultTheme: ThemeName
    public var authorName: String
    public var companyName: String
    public var enableInteractiveChecklists: Bool
    public var pdfPaperSize: String
    public var includeTimestamp: Bool

    public init(
        defaultTheme: ThemeName = .modernMinimal,
        authorName: String = "",
        companyName: String = "StepIt Docs",
        enableInteractiveChecklists: Bool = true,
        pdfPaperSize: String = "A4",
        includeTimestamp: Bool = true
    ) {
        self.defaultTheme = defaultTheme
        self.authorName = authorName
        self.companyName = companyName
        self.enableInteractiveChecklists = enableInteractiveChecklists
        self.pdfPaperSize = pdfPaperSize
        self.includeTimestamp = includeTimestamp
    }
}
