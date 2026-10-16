import Foundation
import WebKit
import PDFKit

public final class PDFGenerator: NSObject, WKNavigationDelegate, @unchecked Sendable {
    public static let shared = PDFGenerator()
    
    private var activeWebView: WKWebView?
    private var navigationContinuation: CheckedContinuation<Void, Error>?
    
    public override init() {
        super.init()
    }
    
    @MainActor
    public func generatePDF(
        session: StepSession,
        settings: PublishingSettings = PublishingSettings()
    ) async throws -> URL {
        let sessionDir = SessionStore.shared.sessionDirectory(for: session.id)
        let exportsDir = SessionStore.shared.exportsDirectory(for: session.id)
        let pdfURL = exportsDir.appendingPathComponent("guide.pdf")
        
        // Generate HTML with local file paths
        let html = WebDocGenerator.shared.generateHTML(
            session: session,
            settings: settings,
            assetBaseURL: sessionDir.absoluteString
        )
        
        let webConfig = WKWebViewConfiguration()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 1100), configuration: webConfig)
        self.activeWebView = webView
        webView.navigationDelegate = self
        
        // Attach to offscreen window to ensure WebKit WebContent process renders in headless mode
        let offscreenWindow = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 800, height: 1100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        offscreenWindow.contentView = webView
        
        // Load HTML with baseURL allowing local file access
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.navigationContinuation = continuation
            webView.loadHTMLString(html, baseURL: sessionDir)
        }
        
        // Short pause to ensure all local image resources are fully drawn in WebKit render tree
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // PDF configuration
        let pdfConfig = WKPDFConfiguration()
        if settings.pdfPaperSize.uppercased() == "A4" {
            // A4 in points: 595 x 842
            pdfConfig.rect = CGRect(x: 0, y: 0, width: 595, height: 842)
        } else {
            // US Letter in points: 612 x 792
            pdfConfig.rect = CGRect(x: 0, y: 0, width: 612, height: 792)
        }
        
        let pdfData: Data = try await withCheckedThrowingContinuation { continuation in
            webView.createPDF(configuration: pdfConfig) { result in
                continuation.resume(with: result)
            }
        }
        try pdfData.write(to: pdfURL, options: [.atomic])
        
        // Update session export paths
        var updatedSession = session
        updatedSession.exports.pdf = "exports/guide.pdf"
        try? SessionStore.shared.saveSession(updatedSession)
        
        self.activeWebView = nil
        return pdfURL
    }
    
    // MARK: - WKNavigationDelegate
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationContinuation?.resume()
        navigationContinuation = nil
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }
    
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }
}
