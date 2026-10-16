import Foundation
import AppKit

public final class PublishingCoordinator: @unchecked Sendable {
    public static let shared = PublishingCoordinator()
    private let fileManager = FileManager.default
    
    public init() {}
    
    @discardableResult
    public func exportWeb(session: StepSession, settings: StepItSettings) throws -> URL {
        let webDir = SessionStore.shared.webExportDirectory(for: session.id)
        let webMediaDir = webDir.appendingPathComponent("media", isDirectory: true)
        
        try? fileManager.createDirectory(at: webMediaDir, withIntermediateDirectories: true)
        
        // Copy all media files into exports/web/media
        let sourceMediaDir = SessionStore.shared.mediaDirectory(for: session.id)
        if let mediaFiles = try? fileManager.contentsOfDirectory(atPath: sourceMediaDir.path) {
            for file in mediaFiles {
                let src = sourceMediaDir.appendingPathComponent(file)
                let dst = webMediaDir.appendingPathComponent(file)
                if fileManager.fileExists(atPath: dst.path) {
                    try? fileManager.removeItem(at: dst)
                }
                try? fileManager.copyItem(at: src, to: dst)
            }
        }
        
        // Generate HTML with relative media paths ("media/step_01.png")
        let html = WebDocGenerator.shared.generateHTML(
            session: session,
            settings: settings.publishing,
            assetBaseURL: ""
        )
        
        let indexHTMLURL = webDir.appendingPathComponent("index.html")
        try html.write(to: indexHTMLURL, atomically: true, encoding: .utf8)
        
        var updated = session
        updated.exports.web = "exports/web/index.html"
        try? SessionStore.shared.saveSession(updated)
        
        return indexHTMLURL
    }
    
    @discardableResult
    public func exportMarkdown(session: StepSession) throws -> URL {
        let exportsDir = SessionStore.shared.exportsDirectory(for: session.id)
        try? fileManager.createDirectory(at: exportsDir, withIntermediateDirectories: true)
        
        let md = MarkdownExporter.shared.exportMarkdown(session: session, relativeAssetPrefix: "../")
        let readmeURL = exportsDir.appendingPathComponent("README.md")
        try md.write(to: readmeURL, atomically: true, encoding: .utf8)
        
        var updated = session
        updated.exports.markdown = "exports/README.md"
        try? SessionStore.shared.saveSession(updated)
        
        return readmeURL
    }
    
    @discardableResult
    @MainActor
    public func exportPDF(session: StepSession, settings: StepItSettings) async throws -> URL {
        return try await PDFGenerator.shared.generatePDF(session: session, settings: settings.publishing)
    }
    
    @MainActor
    public func exportAll(session: StepSession, settings: StepItSettings) async throws -> (webURL: URL, pdfURL: URL?, markdownURL: URL) {
        let webURL = try exportWeb(session: session, settings: settings)
        let mdURL = try exportMarkdown(session: session)
        let pdfURL = try? await exportPDF(session: session, settings: settings)
        return (webURL, pdfURL, mdURL)
    }
    
    public func openInBrowser(url: URL) {
        NSWorkspace.shared.open(url)
    }
    
    public func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
