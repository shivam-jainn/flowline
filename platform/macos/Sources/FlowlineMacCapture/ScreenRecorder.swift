import Foundation
import FlowlineIR
import FlowlinePipeline
import AppKit
import CoreGraphics
import UniformTypeIdentifiers

/// macOS screen capture + click-highlight rendering.
///
/// Phase 1: owned by `MacCaptureDriver` for the recording pipeline. The
/// `shared` accessor is a **sanctioned exception** (phase1-plan.md D6):
/// non-pipeline call sites (`DemoSessionGenerator`, `AutomatedWorkflowRecorder`,
/// `PlaygroundPageRenderer`, tests) use only the pure encoders
/// (`imageToPNGData`), never the capture path.
public final class ScreenRecorder: @unchecked Sendable {
    public static let shared = ScreenRecorder()
    
    public init() {}
    
    /// Captures the full screen containing the point, or main display.
    public func captureScreen(
        highlightAt clickPoint: CGPoint? = nil,
        stepIndex: Int? = nil,
        highlightColor: NSColor = NSColor(srgbRed: 0.94, green: 0.27, blue: 0.27, alpha: 1.0), // #EF4444
        highlightRadius: CGFloat = 28.0
    ) -> (image: CGImage, pngData: Data)? {
        // Find which screen contains the clickPoint
        var targetRect = CGRect.null
        if let point = clickPoint {
            // Note: AppKit coordinates have (0,0) at bottom-left, CG has (0,0) at top-left.
            for screen in NSScreen.screens {
                if screen.frame.contains(point) {
                    // For CGWindowListCreateImage, coordinates are in screen coordinate space
                    targetRect = screen.frame
                    break
                }
            }
        }
        
        // Synchronous exclusion: build the on-screen window list WITHOUT our
        // own windows and capture only those via FromArray. orderOut+grab
        // races WindowServer (the compositor hasn't hidden the pill yet when
        // the grab runs), so hiding alone still photobombs. FromArray never
        // includes the pill in the first place.
        let captureRect = targetRect == .null
            ? (NSScreen.screens.first { $0.frame.contains(clickPoint ?? .zero) }?.frame
                ?? NSScreen.main?.frame
                ?? CGRect(x: 0, y: 0, width: 2000, height: 1200))
            : targetRect
        guard let rawImage = Self.createScreenImageExcludingFlowlineWindows(
            rect: captureRect,
            options: .bestResolution
        ) else {
            return nil
        }
        
        let finalImage: CGImage
        if let point = clickPoint {
            finalImage = drawHighlight(
                on: rawImage,
                at: point,
                stepIndex: stepIndex,
                screenRect: targetRect == .null ? (NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: rawImage.width, height: rawImage.height)) : targetRect,
                color: highlightColor,
                radius: highlightRadius
            )
        } else {
            finalImage = rawImage
        }
        
        guard let pngData = imageToPNGData(finalImage) else {
            return nil
        }
        
        return (finalImage, pngData)
    }
    
    /// Overlays a modern glowing ring and step badge at the click location
    private func drawHighlight(
        on image: CGImage,
        at screenPoint: CGPoint,
        stepIndex: Int?,
        screenRect: CGRect,
        color: NSColor,
        radius: CGFloat
    ) -> CGImage {
        let width = image.width
        let height = image.height
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return image
        }
        
        // Draw base image
        let drawRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(image, in: drawRect)
        
        // Calculate coordinate scaling factor (Retina display ratio)
        let scaleX = CGFloat(width) / max(screenRect.width, 1)
        let scaleY = CGFloat(height) / max(screenRect.height, 1)
        
        // Convert screenPoint (origin at bottom-left in Cocoa, or relative to screenRect)
        // In CGContext, (0,0) is bottom-left
        let relativeX = screenPoint.x - screenRect.origin.x
        let relativeY = screenPoint.y - screenRect.origin.y
        
        let imgX = relativeX * scaleX
        let imgY = relativeY * scaleY
        
        let scaledRadius = radius * ((scaleX + scaleY) / 2.0)
        
        context.saveGState()
        
        // 1. Soft Outer Glow
        let glowColor = color.withAlphaComponent(0.35).cgColor
        context.setFillColor(glowColor)
        context.fillEllipse(in: CGRect(
            x: imgX - scaledRadius * 1.5,
            y: imgY - scaledRadius * 1.5,
            width: scaledRadius * 3.0,
            height: scaledRadius * 3.0
        ))
        
        // 2. Translucent Inner Fill
        let innerFill = color.withAlphaComponent(0.20).cgColor
        context.setFillColor(innerFill)
        context.fillEllipse(in: CGRect(
            x: imgX - scaledRadius,
            y: imgY - scaledRadius,
            width: scaledRadius * 2.0,
            height: scaledRadius * 2.0
        ))
        
        // 3. Crisp Stroke Ring
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(3.0 * ((scaleX + scaleY) / 2.0))
        context.strokeEllipse(in: CGRect(
            x: imgX - scaledRadius,
            y: imgY - scaledRadius,
            width: scaledRadius * 2.0,
            height: scaledRadius * 2.0
        ))
        
        // 4. Center Focal Point Dot
        context.setFillColor(NSColor.white.cgColor)
        let dotRadius = 4.0 * ((scaleX + scaleY) / 2.0)
        context.fillEllipse(in: CGRect(
            x: imgX - dotRadius,
            y: imgY - dotRadius,
            width: dotRadius * 2.0,
            height: dotRadius * 2.0
        ))
        
        // 5. Numbered Badge if stepIndex is provided
        if let step = stepIndex {
            let badgeRadius = 14.0 * ((scaleX + scaleY) / 2.0)
            let badgeCenter = CGPoint(x: imgX + scaledRadius * 0.75, y: imgY + scaledRadius * 0.75)
            
            // Badge background
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: CGRect(
                x: badgeCenter.x - badgeRadius,
                y: badgeCenter.y - badgeRadius,
                width: badgeRadius * 2.0,
                height: badgeRadius * 2.0
            ))
            
            // Badge stroke
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(2.0 * ((scaleX + scaleY) / 2.0))
            context.strokeEllipse(in: CGRect(
                x: badgeCenter.x - badgeRadius,
                y: badgeCenter.y - badgeRadius,
                width: badgeRadius * 2.0,
                height: badgeRadius * 2.0
            ))
            
            // Draw text
            let text = "\(step)"
            let font = NSFont.boldSystemFont(ofSize: 14.0 * ((scaleX + scaleY) / 2.0))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white
            ]
            let attrStr = NSAttributedString(string: text, attributes: attrs)
            let textSize = attrStr.size()
            
            let textRect = CGRect(
                x: badgeCenter.x - textSize.width / 2.0,
                y: badgeCenter.y - textSize.height / 2.0,
                width: textSize.width,
                height: textSize.height
            )
            
            // For drawing text in CGContext, AppKit's NSString drawing can be bridged or drawn via CTLine
            let line = CTLineCreateWithAttributedString(attrStr as CFAttributedString)
            context.textPosition = CGPoint(x: textRect.origin.x, y: textRect.origin.y)
            CTLineDraw(line, context)
        }
        
        context.restoreGState()
        
        return context.makeImage() ?? image
    }
    
    public func imageToPNGData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }

    /// Synchronous, race-free screen grab that NEVER includes Flowline-owned
    /// windows. Captures everything BELOW our backmost window in true
    /// front-to-back z-order (wallpaper + other apps included, all Flowline
    /// windows above excluded). Returns nil without Screen Recording
    /// permission instead of a misleading pill-only black frame.
    public static func createScreenImageExcludingFlowlineWindows(
        rect: CGRect,
        options: CGWindowImageOption
    ) -> CGImage? {
        // Without permission the compositor only gives us our own windows —
        // refuse instead of producing a pill-on-black frame.
        if !hasScreenRecordingPermission() { return nil }
        if let belowID = backmostFlowlineWindowIDInZOrder(), belowID != kCGNullWindowID {
            if let img = CGWindowListCreateImage(rect, .optionOnScreenBelowWindow, belowID, [options]) {
                return img
            }
        }
        return CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, [options])
    }

    static func hasScreenRecordingPermission() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }

    /// The backmost Flowline-owned window in true WindowServer front-to-back
    /// order (windowNumbers do NOT reflect z-order, so read the ordered list).
    private static func backmostFlowlineWindowIDInZOrder() -> CGWindowID? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let flowlineNumbers = Set(NSApp.windows.map { $0.windowNumber })
        guard let info = CGWindowListCopyWindowInfo(
            .optionOnScreenOnly, kCGNullWindowID
        ) as? [[String: Any]] else { return nil }
        var lastFlowlineID: CGWindowID?
        for dict in info {
            let isOwn: Bool = {
                if let pid = dict[kCGWindowOwnerPID as String] as? Int, pid == Int(ownPID) { return true }
                if let num = dict[kCGWindowNumber as String] as? Int, flowlineNumbers.contains(num) { return true }
                return false
            }()
            if isOwn, let num = dict[kCGWindowNumber as String] as? Int {
                lastFlowlineID = CGWindowID(num)
            }
        }
        return lastFlowlineID
    }

    /// Every on-screen window ID except Flowline-owned ones (own PID excluded
    /// so the HUD pill / review / settings can never photobomb a recording).
    /// Kept for tests/callers that need the filtered list; the capture path
    /// itself uses BelowWindow (wallpaper-safe) — see above.
    public static func onScreenWindowIDsExcludingFlowlineWindows() -> [CGWindowID] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let flowlineNumbers = Set(NSApp.windows.map { $0.windowNumber })
        guard let info = CGWindowListCopyWindowInfo(
            .optionOnScreenOnly, kCGNullWindowID
        ) as? [[String: Any]] else { return [] }
        var ids: [CGWindowID] = []
        ids.reserveCapacity(info.count)
        for dict in info {
            if let pid = dict[kCGWindowOwnerPID as String] as? Int32, pid == ownPID { continue }
            if let pid = dict[kCGWindowOwnerPID as String] as? Int, pid == Int(ownPID) { continue }
            if let num = dict[kCGWindowNumber as String] as? Int {
                if flowlineNumbers.contains(num) { continue }
                ids.append(CGWindowID(num))
            }
        }
        return ids
    }

    private static func backmostFlowlineWindowID() -> CGWindowID {
        let numbers = NSApp.windows.map { $0.windowNumber }
        guard let minNum = numbers.min() else { return kCGNullWindowID }
        return CGWindowID(minNum)
    }

    @discardableResult
    static func hideFlowlineWindowsForCapture() -> [NSWindow] {
        hideFlowlineWindows()
    }

    static func restoreFlowlineWindowsAfterCapture(_ windows: [NSWindow]) {
        restoreFlowlineWindows(windows)
    }

    /// Order out Flowline-owned windows synchronously; returns the hidden set
    /// for restoration. Must run on main thread; falls back to enumeration
    /// when off-main.
    @discardableResult
    private static func hideFlowlineWindows() -> [NSWindow] {
        let owned = NSApp.windows.filter { $0.sharingType == .none || $0.level == .floating }
        guard !owned.isEmpty else { return [] }
        if Thread.isMainThread {
            owned.forEach { $0.orderOut(nil) }
        } else {
            DispatchQueue.main.sync { owned.forEach { $0.orderOut(nil) } }
        }
        return owned
    }

    private static func restoreFlowlineWindows(_ windows: [NSWindow]) {
        guard !windows.isEmpty else { return }
        if Thread.isMainThread {
            windows.forEach { $0.orderFrontRegardless() }
        } else {
            DispatchQueue.main.sync { windows.forEach { $0.orderFrontRegardless() } }
        }
    }

    /// Full windowList with Flowline-owned IDs removed (callers pass the
    /// remainder to filtered capture paths).
    private static func windowListExcludingFlowlineWindows() -> [CGWindowID] {
        let excluded = Set(NSApp.windows.filter { $0.sharingType == .none }.map { $0.windowNumber })
        guard let info = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return info.compactMap { $0[kCGWindowNumber as String] as? Int }
            .filter { !excluded.contains($0) }
            .map { CGWindowID($0) }
    }
}
