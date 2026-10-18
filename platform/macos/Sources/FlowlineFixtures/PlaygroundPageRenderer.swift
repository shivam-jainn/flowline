import Foundation
import FlowlineStorage
import FlowlineMacCapture
import FlowlineCaptureAPI
import FlowlinePublishing
import FlowlineAIGateway
import FlowlinePipeline
import FlowlineEngine
import FlowlineIR
import WebKit
import AppKit
import CoreGraphics

/// Renders the Playground fixture pages (`shared/fixtures/playground-web`) through an
/// offscreen WebKit renderer and overlays Flowline annotations.
public final class PlaygroundPageRenderer: NSObject, WKNavigationDelegate, @unchecked Sendable {
    public static let shared = PlaygroundPageRenderer()
    
    private var activeWebView: WKWebView?
    private var offscreenWindow: NSWindow?
    private var navigationContinuation: CheckedContinuation<Void, Error>?
    
    public override init() {
        super.init()
    }
    
    /// Renders a real Playground HTML page into a Retina CGImage using offscreen WebKit
    @MainActor
    public func renderPage(
        filename: String,
        width: CGFloat = 1200,
        height: CGFloat = 800
    ) async throws -> (cgImage: CGImage, webView: WKWebView) {
        guard let dir = FixtureLocator.playgroundWebDirectory() else {
            throw NSError(
                domain: "PlaygroundPageRenderer",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "shared/fixtures/playground-web was not found. Run from the repository root or set FLOWLINE_FIXTURES_DIR."]
            )
        }
        let fileURL = dir.appendingPathComponent(filename)
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw NSError(
                domain: "PlaygroundPageRenderer",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Playground page not found at \(fileURL.path)"]
            )
        }
        
        let webConfig = WKWebViewConfiguration()
        webConfig.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: height), configuration: webConfig)
        self.activeWebView = webView
        webView.navigationDelegate = self
        
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        self.offscreenWindow = window
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.navigationContinuation = continuation
            webView.loadFileURL(fileURL, allowingReadAccessTo: dir)
        }
        
        // Wait briefly for WebKit font loading, CSS animations, and layout to settle
        try await Task.sleep(nanoseconds: 200_000_000)
        
        let nsImage = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NSImage, Error>) in
            webView.takeSnapshot(with: nil) { image, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let image = image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "PlaygroundPageRenderer",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "WebKit snapshot returned nil for \(filename)"]
                    ))
                }
            }
        }
        
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(
                domain: "PlaygroundPageRenderer",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to extract CGImage from NSImage for \(filename)"]
            )
        }
        
        return (cgImage, webView)
    }
    
    /// Queries the live DOM of the rendered page for the exact bounding center of a control ID
    @MainActor
    public func getElementCenter(in webView: WKWebView, elementId: String) async -> CGPoint? {
        let script = """
        (() => {
            const el = document.getElementById('\(elementId)') || document.querySelector('\(elementId)');
            if (!el) return null;
            const r = el.getBoundingClientRect();
            return { x: r.left + r.width / 2.0, y: r.top + r.height / 2.0 };
        })()
        """
        
        guard let result = try? await webView.evaluateJavaScript(script) as? [String: Any],
              let x = result["x"] as? NSNumber,
              let y = result["y"] as? NSNumber else {
            return nil
        }
        return CGPoint(x: CGFloat(x.doubleValue), y: CGFloat(y.doubleValue))
    }
    
    /// Evaluates custom JavaScript in the live WebKit instance
    @MainActor
    public func evaluateScript(in webView: WKWebView, script: String) async throws -> Any? {
        return try await webView.evaluateJavaScript(script)
    }
    
    /// Dispatches a programmatic click on an element by ID
    @MainActor
    @discardableResult
    public func clickElement(in webView: WKWebView, elementId: String) async throws -> Bool {
        let script = """
        (() => {
            const el = document.getElementById('\(elementId)') || document.querySelector('\(elementId)');
            if (!el) return false;
            el.scrollIntoView({ behavior: 'instant', block: 'center' });
            el.click();
            return true;
        })()
        """
        let res = try await webView.evaluateJavaScript(script) as? NSNumber
        try await Task.sleep(nanoseconds: 60_000_000)
        return res?.boolValue ?? false
    }
    
    /// Sets an input or textarea value and dispatches input/change events
    @MainActor
    @discardableResult
    public func setInputValue(in webView: WKWebView, elementId: String, value: String) async throws -> Bool {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        let script = """
        (() => {
            const el = document.getElementById('\(elementId)') || document.querySelector('\(elementId)');
            if (!el) return false;
            el.value = '\(escaped)';
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
            return true;
        })()
        """
        let res = try await webView.evaluateJavaScript(script) as? NSNumber
        try await Task.sleep(nanoseconds: 60_000_000)
        return res?.boolValue ?? false
    }
    
    /// Extracts textContent of a DOM element by ID
    @MainActor
    public func getElementText(in webView: WKWebView, elementId: String) async -> String? {
        let script = """
        (() => {
            const el = document.getElementById('\(elementId)') || document.querySelector('\(elementId)');
            return el ? el.textContent : null;
        })()
        """
        return try? await webView.evaluateJavaScript(script) as? String
    }
    
    /// Takes a fresh WebKit snapshot of the current web view state
    @MainActor
    public func takeSnapshot(of webView: WKWebView) async throws -> CGImage {
        let nsImage = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NSImage, Error>) in
            webView.takeSnapshot(with: nil) { image, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let image = image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "PlaygroundPageRenderer",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "WebKit snapshot returned nil"]
                    ))
                }
            }
        }
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(
                domain: "PlaygroundPageRenderer",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to extract CGImage from snapshot"]
            )
        }
        return cgImage
    }
    
    /// Renders an end-to-end Playground Step with real WebKit capture, accurate live DOM coordinate overlay, 2.5x high-res zoom crop, and animated ripple GIF
    @MainActor
    public func renderStepCapture(
        filename: String,
        targetElementId: String,
        stepIndex: Int,
        width: CGFloat = 1200,
        height: CGFloat = 800
    ) async throws -> (screenshot: CGImage, zoomCrop: CGImage, gifData: Data, targetPoint: CGPoint) {
        let (rawImage, webView) = try await renderPage(filename: filename, width: width, height: height)
        
        guard let domPoint = await getElementCenter(in: webView, elementId: targetElementId) else {
            throw NSError(
                domain: "PlaygroundPageRenderer",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Target element '#\(targetElementId)' was not found in the live DOM of \(filename)"]
            )
        }
        
        let annotatedImage = overlayStepAnnotation(
            on: rawImage,
            pagePoint: domPoint,
            stepIndex: stepIndex,
            pageWidth: width,
            pageHeight: height
        )
        
        let zoomCrop = createZoomCrop(
            from: annotatedImage,
            pagePoint: domPoint,
            pageWidth: width,
            pageHeight: height,
            zoomFactor: 2.4
        ) ?? annotatedImage
        
        let gifData = generateRippleGIF(
            baseImage: rawImage,
            pagePoint: domPoint,
            pageWidth: width,
            pageHeight: height
        )
        
        return (annotatedImage, zoomCrop, gifData, domPoint)
    }
    
    /// Creates a pixel-perfect 2.4x zoomed crop centered on the target coordinate
    public func createZoomCrop(
        from baseImage: CGImage,
        pagePoint: CGPoint,
        pageWidth: CGFloat,
        pageHeight: CGFloat,
        zoomFactor: CGFloat = 2.4
    ) -> CGImage? {
        let imgWidth = CGFloat(baseImage.width)
        let imgHeight = CGFloat(baseImage.height)
        
        let scaleX = imgWidth / pageWidth
        let scaleY = imgHeight / pageHeight
        let cx = pagePoint.x * scaleX
        let cy = imgHeight - (pagePoint.y * scaleY)
        
        let cropWidth = imgWidth / zoomFactor
        let cropHeight = imgHeight / zoomFactor
        
        let cropX = max(0, min(cx - cropWidth / 2.0, imgWidth - cropWidth))
        let cropY = max(0, min(cy - cropHeight / 2.0, imgHeight - cropHeight))
        
        return baseImage.cropping(to: CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight))
    }
    
    // MARK: - Annotation & GIF Compositing
    
    /// Overlays Flowline's high-visibility red glow, pulse ring, white focal dot, and numbered badge
    public func overlayStepAnnotation(
        on baseImage: CGImage,
        pagePoint: CGPoint,
        stepIndex: Int,
        pageWidth: CGFloat,
        pageHeight: CGFloat
    ) -> CGImage {
        let imgWidth = baseImage.width
        let imgHeight = baseImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        guard let ctx = CGContext(
            data: nil,
            width: imgWidth,
            height: imgHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return baseImage
        }
        
        // Draw the real rendered web page
        ctx.draw(baseImage, in: CGRect(x: 0, y: 0, width: imgWidth, height: imgHeight))
        
        // Scale factors: pagePoint is in WebKit coordinates (0,0 top-left)
        // CGContext has (0,0) at bottom-left
        let scaleX = CGFloat(imgWidth) / pageWidth
        let scaleY = CGFloat(imgHeight) / pageHeight
        
        let cx = pagePoint.x * scaleX
        let cy = CGFloat(imgHeight) - (pagePoint.y * scaleY)
        
        let baseRadius: CGFloat = 32.0 * ((scaleX + scaleY) / 2.0)
        let redColor = NSColor(srgbRed: 0.94, green: 0.27, blue: 0.27, alpha: 1.0)
        
        ctx.saveGState()
        
        // 1. Outer Glow
        ctx.setFillColor(redColor.withAlphaComponent(0.35).cgColor)
        ctx.fillEllipse(in: CGRect(x: cx - baseRadius * 1.5, y: cy - baseRadius * 1.5, width: baseRadius * 3.0, height: baseRadius * 3.0))
        
        // 2. Translucent Inner Fill
        ctx.setFillColor(redColor.withAlphaComponent(0.20).cgColor)
        ctx.fillEllipse(in: CGRect(x: cx - baseRadius, y: cy - baseRadius, width: baseRadius * 2.0, height: baseRadius * 2.0))
        
        // 3. Crisp Stroke Ring
        ctx.setStrokeColor(redColor.cgColor)
        ctx.setLineWidth(3.5 * ((scaleX + scaleY) / 2.0))
        ctx.strokeEllipse(in: CGRect(x: cx - baseRadius, y: cy - baseRadius, width: baseRadius * 2.0, height: baseRadius * 2.0))
        
        // 4. White Center Dot
        ctx.setFillColor(NSColor.white.cgColor)
        let dotR: CGFloat = 5.0 * ((scaleX + scaleY) / 2.0)
        ctx.fillEllipse(in: CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2.0, height: dotR * 2.0))
        
        // 5. Numbered Step Badge
        let badgeRadius: CGFloat = 16.0 * ((scaleX + scaleY) / 2.0)
        let badgeCenter = CGPoint(x: cx + baseRadius * 0.75, y: cy + baseRadius * 0.75)
        
        ctx.setFillColor(redColor.cgColor)
        ctx.fillEllipse(in: CGRect(x: badgeCenter.x - badgeRadius, y: badgeCenter.y - badgeRadius, width: badgeRadius * 2.0, height: badgeRadius * 2.0))
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2.5 * ((scaleX + scaleY) / 2.0))
        ctx.strokeEllipse(in: CGRect(x: badgeCenter.x - badgeRadius, y: badgeCenter.y - badgeRadius, width: badgeRadius * 2.0, height: badgeRadius * 2.0))
        
        ctx.restoreGState()
        return ctx.makeImage() ?? baseImage
    }
    
    /// Generates a 6-frame expanding ripple animated GIF from the real rendered web page
    public func generateRippleGIF(
        baseImage: CGImage,
        pagePoint: CGPoint,
        pageWidth: CGFloat,
        pageHeight: CGFloat
    ) -> Data {
        let imgWidth = baseImage.width
        let imgHeight = baseImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        let scaleX = CGFloat(imgWidth) / pageWidth
        let scaleY = CGFloat(imgHeight) / pageHeight
        let cx = pagePoint.x * scaleX
        let cy = CGFloat(imgHeight) - (pagePoint.y * scaleY)
        let redColor = NSColor(srgbRed: 0.94, green: 0.27, blue: 0.27, alpha: 1.0)
        
        var frames: [CGImage] = []
        
        for i in 0..<6 {
            guard let ctx = CGContext(
                data: nil,
                width: imgWidth,
                height: imgHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { continue }
            
            // Draw real web page
            ctx.draw(baseImage, in: CGRect(x: 0, y: 0, width: imgWidth, height: imgHeight))
            
            let rippleRadius = (20.0 + CGFloat(i * 12)) * ((scaleX + scaleY) / 2.0)
            let alpha = max(0.0, 0.95 - Double(i) * 0.16)
            
            ctx.setStrokeColor(redColor.withAlphaComponent(CGFloat(alpha)).cgColor)
            ctx.setLineWidth(3.5 * ((scaleX + scaleY) / 2.0))
            ctx.strokeEllipse(in: CGRect(x: cx - rippleRadius, y: cy - rippleRadius, width: rippleRadius * 2.0, height: rippleRadius * 2.0))
            
            // Center focal dot
            ctx.setFillColor(NSColor.white.withAlphaComponent(CGFloat(alpha)).cgColor)
            let dotR: CGFloat = 4.0 * ((scaleX + scaleY) / 2.0)
            ctx.fillEllipse(in: CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2.0, height: dotR * 2.0))
            
            if let frame = ctx.makeImage() {
                frames.append(frame)
            }
        }
        
        return MicroClipRecorder().createGIF(from: frames, fps: 8) ?? Data()
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
