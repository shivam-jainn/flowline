import Foundation
import FlowlineIR
import FlowlineStorage

/// Multi-format publishing orchestration (R/M1-07: store-injected, narrow
/// settings).
///
/// - The session store arrives via constructor injection (defaulting to a
///   fresh `SessionStore`, never the `shared` singleton), so surfaces and
///   tests can supply isolated stores.
/// - Export entry points take the narrow `PublishingSettings` they actually
///   read — never the full `FlowlineSettings` aggregate.
public final class PublishingCoordinator: @unchecked Sendable {
    public static let shared = PublishingCoordinator()

    private let store: any SessionStoreProtocol
    private let fileManager = FileManager.default
    private let urlOpener: any URLOpener

    public init(
        store: any SessionStoreProtocol = SessionStore(),
        urlOpener: any URLOpener = DefaultURLOpener()
    ) {
        self.store = store
        self.urlOpener = urlOpener
    }

    @discardableResult
    public func exportWeb(session: StepSession, publishing: PublishingSettings) throws -> URL {
        let webDir = store.webExportDirectory(for: session.id)
        let webMediaDir = webDir.appendingPathComponent("media", isDirectory: true)

        try? fileManager.createDirectory(at: webMediaDir, withIntermediateDirectories: true)

        // Copy all media files into exports/web/media
        let sourceMediaDir = store.mediaDirectory(for: session.id)
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
            settings: publishing,
            assetBaseURL: ""
        )

        let indexHTMLURL = webDir.appendingPathComponent("index.html")
        try html.write(to: indexHTMLURL, atomically: true, encoding: .utf8)

        var updated = session
        updated.exports.web = "exports/web/index.html"
        try? store.saveSession(updated)

        return indexHTMLURL
    }

    @discardableResult
    public func exportMarkdown(session: StepSession) throws -> URL {
        let exportsDir = store.exportsDirectory(for: session.id)
        try? fileManager.createDirectory(at: exportsDir, withIntermediateDirectories: true)

        let md = MarkdownExporter.shared.exportMarkdown(session: session, relativeAssetPrefix: "../")
        let readmeURL = exportsDir.appendingPathComponent("README.md")
        try md.write(to: readmeURL, atomically: true, encoding: .utf8)

        var updated = session
        updated.exports.markdown = "exports/README.md"
        try? store.saveSession(updated)

        return readmeURL
    }

    @discardableResult
    @MainActor
    public func exportPDF(session: StepSession, publishing: PublishingSettings) async throws -> URL {
        return try await PDFGenerator(store: store).generatePDF(session: session, settings: publishing)
    }

    @MainActor
    public func exportAll(session: StepSession, publishing: PublishingSettings) async throws -> (webURL: URL, pdfURL: URL?, markdownURL: URL) {
        let webURL = try exportWeb(session: session, publishing: publishing)
        let mdURL = try exportMarkdown(session: session)
        let pdfURL = try? await exportPDF(session: session, publishing: publishing)
        return (webURL, pdfURL, mdURL)
    }

    public func openInBrowser(url: URL) {
        urlOpener.open(url)
    }

    public func revealInFinder(url: URL) {
        urlOpener.revealInFinder(url)
    }
}
