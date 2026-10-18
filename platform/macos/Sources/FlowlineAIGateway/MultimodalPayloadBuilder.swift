import Foundation
import FlowlineIR
import FlowlineStorage
import CoreGraphics
import ImageIO

public struct MultimodalContentPart: Codable, Sendable {
    public var type: String
    public var text: String?
    public var image_url: ImageURLPayload?
    
    public init(text: String) {
        self.type = "text"
        self.text = text
        self.image_url = nil
    }
    
    public init(imageURL: String) {
        self.type = "image_url"
        self.text = nil
        self.image_url = ImageURLPayload(url: imageURL)
    }
}

public struct ImageURLPayload: Codable, Sendable {
    public var url: String
    
    public init(url: String) {
        self.url = url
    }
}

public struct ChatMessagePayload: Codable, Sendable {
    public var role: String
    public var content: [MultimodalContentPart]
    
    public init(role: String, content: [MultimodalContentPart]) {
        self.role = role
        self.content = content
    }
    
    public init(role: String, text: String) {
        self.role = role
        self.content = [MultimodalContentPart(text: text)]
    }
}

public struct ChatCompletionRequest: Codable, Sendable {
    public var model: String
    public var messages: [ChatMessagePayload]
    public var temperature: Double
    public var stream: Bool
    
    public init(model: String, messages: [ChatMessagePayload], temperature: Double = 0.2, stream: Bool = true) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.stream = stream
    }
}

public final class MultimodalPayloadBuilder: @unchecked Sendable {
    public static let shared = MultimodalPayloadBuilder()

    private let store: any SessionStoreProtocol

    public init(store: any SessionStoreProtocol = SessionStore()) {
        self.store = store
    }
    
    public func buildRequest(
        session: StepSession,
        settings: GatewaySettings,
        style: DocumentationStyle,
        customInstructions: String? = nil,
        maxImageWidth: CGFloat = 1200
    ) -> ChatCompletionRequest {
        let systemPrompt = PromptTemplates.systemPrompt(for: style)
        let textPrompt = PromptTemplates.userPrompt(for: session, style: style, customInstructions: customInstructions)
        
        var userContentParts: [MultimodalContentPart] = [
            MultimodalContentPart(text: textPrompt)
        ]
        
        // If vision is enabled, read and downsample step screenshots into base64 data URLs
        if settings.visionEnabled {
            for step in session.steps {
                guard let relPath = step.assets.screenshot else { continue }
                let fileURL = store.resolveMediaPath(sessionID: session.id, relativePath: relPath)
                if let imageData = try? Data(contentsOf: fileURL),
                   let base64String = encodeAndDownsampleImage(data: imageData, maxWidth: maxImageWidth) {
                    let caption = "Screenshot for Step \(step.index) (\(step.actionDescription)):"
                    userContentParts.append(MultimodalContentPart(text: caption))
                    userContentParts.append(MultimodalContentPart(imageURL: "data:image/png;base64,\(base64String)"))
                }
            }
        }
        
        let messages = [
            ChatMessagePayload(role: "system", text: systemPrompt),
            ChatMessagePayload(role: "user", content: userContentParts)
        ]
        
        return ChatCompletionRequest(
            model: settings.model,
            messages: messages,
            temperature: settings.temperature,
            stream: true
        )
    }
    
    private func encodeAndDownsampleImage(data: Data, maxWidth: CGFloat) -> String? {
        // AppKit-free downsample (R/M1-06): decode via ImageIO, thumbnail to
        // the same target size as before (width capped at maxWidth, aspect
        // preserved, never upscaled), then re-encode as PNG. Fallbacks return
        // the original bytes, exactly as the previous bitmap path did.
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let pixelHeight = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              pixelWidth > 0, pixelHeight > 0 else {
            return nil
        }
        
        var targetWidth = pixelWidth
        var targetHeight = pixelHeight
        if targetWidth > Double(maxWidth) {
            let scale = Double(maxWidth) / targetWidth
            targetWidth = Double(maxWidth)
            targetHeight = targetHeight * scale
        }
        
        let thumbnail: CGImage?
        if targetWidth == pixelWidth && targetHeight == pixelHeight {
            thumbnail = CGImageSourceCreateImageAtIndex(source, 0, nil)
        } else {
            let maxPixelSize = Int(max(targetWidth, targetHeight).rounded())
            let options: CFDictionary = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ] as CFDictionary
            thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options)
        }
        
        guard let image = thumbnail else {
            return data.base64EncodedString()
        }
        
        guard let mutableData = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(mutableData, "public.png" as CFString, 1, nil) else {
            return data.base64EncodedString()
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return data.base64EncodedString()
        }
        return (mutableData as Data).base64EncodedString()
    }
}
