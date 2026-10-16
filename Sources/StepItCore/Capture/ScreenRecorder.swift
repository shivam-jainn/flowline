import Foundation
import AppKit
import CoreGraphics
import UniformTypeIdentifiers

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
        
        // Capture screen image
        guard let rawImage = CGWindowListCreateImage(
            targetRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
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
}
