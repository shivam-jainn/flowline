import Foundation
import FlowlineIR
import FlowlineStorage
import WebKit
import PDFKit

public final class PDFGenerator: NSObject, WKNavigationDelegate, @unchecked Sendable {
    public static let shared = PDFGenerator()

    private let store: any SessionStoreProtocol

    private var activeWebView: WKWebView?
    private var navigationContinuation: CheckedContinuation<Void, Error>?

    public init(store: any SessionStoreProtocol = SessionStore()) {
        self.store = store
        super.init()
    }
    
    @MainActor
    public func generatePDF(
        session: StepSession,
        settings: PublishingSettings = PublishingSettings()
    ) async throws -> URL {
        let sessionDir = store.sessionDirectory(for: session.id)
        let exportsDir = store.exportsDirectory(for: session.id)
        try? FileManager.default.createDirectory(at: exportsDir, withIntermediateDirectories: true)
        
        let pdfURL = exportsDir.appendingPathComponent("guide.pdf")
        let tempHTMLURL = sessionDir.appendingPathComponent("temp_print.html")
        
        // Generate HTML with relative media paths ("media/step_01.png")
        let html = WebDocGenerator.shared.generateHTML(
            session: session,
            settings: settings,
            assetBaseURL: ""
        )
        try html.write(to: tempHTMLURL, atomically: true, encoding: .utf8)
        
        let webConfig = WKWebViewConfiguration()
        webConfig.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        
        let initialWidth: CGFloat = settings.pdfPaperSize.uppercased() == "A4" ? 794 : 816
        let initialHeight: CGFloat = 1123
        
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: initialWidth, height: initialHeight), configuration: webConfig)
        self.activeWebView = webView
        webView.navigationDelegate = self
        
        // Attach to offscreen window to ensure WebKit WebContent process renders in headless mode
        let offscreenWindow = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: initialWidth, height: initialHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        offscreenWindow.contentView = webView
        
        // Load via loadFileURL granting full WebKit WebContent read access to sessionDir (and media/)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.navigationContinuation = continuation
            webView.loadFileURL(tempHTMLURL, allowingReadAccessTo: sessionDir)
        }
        
        // Enable PDF export styling (hides interactive web buttons, shows print header & static screenshots)
        _ = try? await webView.evaluateJavaScript("document.body.classList.add('pdf-export-mode')")
        
        // Allow WebKit render tree and images to fully lay out
        try await Task.sleep(nanoseconds: 350_000_000)
        
        // Compute full document scroll height to prevent cutting off multi-step workflows
        let measuredHeight: CGFloat
        if let scrollH = try? await webView.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight, 1100)") as? NSNumber {
            measuredHeight = CGFloat(scrollH.doubleValue)
        } else {
            measuredHeight = initialHeight
        }
        
        let fullHeight = max(measuredHeight + 40, initialHeight)
        webView.frame = CGRect(x: 0, y: 0, width: initialWidth, height: fullHeight)
        offscreenWindow.setContentSize(CGSize(width: initialWidth, height: fullHeight))
        
        // Allow relayout after frame update
        try await Task.sleep(nanoseconds: 150_000_000)
        
        // PDF configuration spanning the full workflow height
        let pdfConfig = WKPDFConfiguration()
        pdfConfig.rect = CGRect(x: 0, y: 0, width: initialWidth, height: fullHeight)
        
        let pdfData: Data = try await withCheckedThrowingContinuation { continuation in
            webView.createPDF(configuration: pdfConfig) { result in
                continuation.resume(with: result)
            }
        }
        try pdfData.write(to: pdfURL, options: [.atomic])
        
        // Clean up temporary print file
        try? FileManager.default.removeItem(at: tempHTMLURL)
        
        // Update session export paths
        var updatedSession = session
        updatedSession.exports.pdf = "exports/guide.pdf"
        try? store.saveSession(updatedSession)
        
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
