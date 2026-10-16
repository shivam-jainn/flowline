import Foundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AVFoundation

public struct CapturedFrame: @unchecked Sendable {
    public let image: CGImage
    public let timestamp: Date
    
    public init(image: CGImage, timestamp: Date = Date()) {
        self.image = image
        self.timestamp = timestamp
    }
}

/// Rolling frame ring-buffer + micro-clip encoders (GIF via ImageIO, MP4 via
/// AVAssetWriter).
///
/// Phase 1: owned by `MacCaptureDriver` for the recording pipeline. The
/// `shared` accessor is a **sanctioned exception** (phase1-plan.md D6):
/// non-pipeline call sites (`PlaygroundPageRenderer`, tests) use only the pure
/// encoders (`createGIF`, `createMP4`), never the buffering path.
public final class MicroClipRecorder: @unchecked Sendable {
    public static let shared = MicroClipRecorder()
    
    private let queue = DispatchQueue(label: "com.stepit.microclip", qos: .userInitiated)
    private var rollingBuffer: [CapturedFrame] = []
    private var isBuffering = false
    private var bufferTimer: DispatchSourceTimer?
    
    public var fps: Int = 12
    public var maxBufferSeconds: Double = 1.5
    
    public init() {}
    
    // MARK: - Rolling Buffer Control
    
    public func startBuffering() {
        queue.async { [weak self] in
            guard let self = self, !self.isBuffering else { return }
            self.isBuffering = true
            self.rollingBuffer.removeAll()
            
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            let interval = 1.0 / Double(self.fps)
            timer.schedule(deadline: .now(), repeating: interval)
            timer.setEventHandler { [weak self] in
                self?.captureCurrentFrame()
            }
            self.bufferTimer = timer
            timer.resume()
        }
    }
    
    public func stopBuffering() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.isBuffering = false
            self.bufferTimer?.cancel()
            self.bufferTimer = nil
            self.rollingBuffer.removeAll()
        }
    }
    
    private func captureCurrentFrame() {
        guard let screen = NSScreen.main else { return }
        // Capture at standard or half resolution for micro-GIF efficiency
        guard let cgImage = CGWindowListCreateImage(
            screen.frame,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.nominalResolution]
        ) else { return }
        
        let now = Date()
        rollingBuffer.append(CapturedFrame(image: cgImage, timestamp: now))
        
        // Trim buffer to max buffer length
        let maxFrames = Int(maxBufferSeconds * Double(fps))
        if rollingBuffer.count > maxFrames {
            rollingBuffer.removeFirst(rollingBuffer.count - maxFrames)
        }
    }
    
    // MARK: - Micro-Clip Generation
    
    /// Collects pre-click frames from the rolling buffer, records post-click frames for postDuration, and compiles an animated GIF and MP4
    public func recordClip(
        around clickPoint: CGPoint,
        postDuration: Double = 1.2,
        completion: @escaping (Data?, Data?) -> Void
    ) {
        queue.async { [weak self] in
            guard let self = self else {
                completion(nil, nil)
                return
            }
            
            // Snapshot current rolling buffer frames as pre-click
            let preFrames = self.rollingBuffer
            let clickTimestamp = Date()
            
            var postFrames: [CapturedFrame] = []
            let postFrameCount = Int(postDuration * Double(self.fps))
            let frameInterval = 1.0 / Double(self.fps)
            
            // Collect post-click frames synchronously on background queue
            for _ in 0..<postFrameCount {
                Thread.sleep(forTimeInterval: frameInterval)
                if let screen = NSScreen.main,
                   let cgImage = CGWindowListCreateImage(
                    screen.frame,
                    .optionOnScreenOnly,
                    kCGNullWindowID,
                    [.nominalResolution]
                   ) {
                    postFrames.append(CapturedFrame(image: cgImage, timestamp: Date()))
                }
            }
            
            let allFrames = preFrames + postFrames
            if allFrames.isEmpty {
                completion(nil, nil)
                return
            }
            
            // Render ripple animation at click point for frames starting at clickTimestamp
            let processedFrames = self.overlayClickRipples(
                frames: allFrames,
                clickPoint: clickPoint,
                clickTime: clickTimestamp
            )
            
            // Encode GIF
            let gifData = self.createGIF(from: processedFrames, fps: self.fps)
            
            // Encode MP4/Video
            let videoData = self.createMP4(from: processedFrames, fps: self.fps)
            
            completion(gifData, videoData)
        }
    }
    
    // MARK: - Ripple Rendering
    
    private func overlayClickRipples(
        frames: [CapturedFrame],
        clickPoint: CGPoint,
        clickTime: Date
    ) -> [CGImage] {
        guard let screen = NSScreen.main else {
            return frames.map { $0.image }
        }
        
        var resultImages: [CGImage] = []
        let screenRect = screen.frame
        
        var rippleStep = 0
        var hasClicked = false
        
        for frame in frames {
            if frame.timestamp >= clickTime {
                hasClicked = true
            }
            
            if hasClicked && rippleStep < 8 {
                let rippleImage = drawRippleFrame(
                    image: frame.image,
                    clickPoint: clickPoint,
                    screenRect: screenRect,
                    step: rippleStep
                )
                resultImages.append(rippleImage)
                rippleStep += 1
            } else {
                resultImages.append(frame.image)
            }
        }
        
        return resultImages
    }
    
    private func drawRippleFrame(
        image: CGImage,
        clickPoint: CGPoint,
        screenRect: CGRect,
        step: Int
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
        ) else { return image }
        
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        let scaleX = CGFloat(width) / max(screenRect.width, 1)
        let scaleY = CGFloat(height) / max(screenRect.height, 1)
        let imgX = (clickPoint.x - screenRect.origin.x) * scaleX
        let imgY = (clickPoint.y - screenRect.origin.y) * scaleY
        
        let baseRadius: CGFloat = 16.0 * ((scaleX + scaleY) / 2.0)
        let expansion = CGFloat(step) * 5.0
        let radius = baseRadius + expansion
        let alpha = max(0.0, 0.8 - (Double(step) * 0.1))
        
        context.saveGState()
        context.setStrokeColor(NSColor(srgbRed: 0.94, green: 0.27, blue: 0.27, alpha: CGFloat(alpha)).cgColor)
        context.setLineWidth(3.0 * ((scaleX + scaleY) / 2.0))
        context.strokeEllipse(in: CGRect(
            x: imgX - radius,
            y: imgY - radius,
            width: radius * 2.0,
            height: radius * 2.0
        ))
        context.restoreGState()
        
        return context.makeImage() ?? image
    }
    
    // MARK: - Native GIF Encoder (ImageIO)
    
    public func createGIF(from images: [CGImage], fps: Int) -> Data? {
        guard !images.isEmpty else { return nil }
        
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.gif.identifier as CFString,
            images.count,
            nil
        ) else {
            return nil
        }
        
        let frameDelay = 1.0 / Double(fps)
        let fileProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0 // Infinite loop
            ]
        ]
        
        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameDelay,
                kCGImagePropertyGIFUnclampedDelayTime: frameDelay
            ]
        ]
        
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
        
        for image in images {
            CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
        }
        
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        
        return data as Data
    }
    
    // MARK: - Fast-Forward Typing Timelapse GIF
    
    /// Compiles typing frames into an accelerated (fast-forward) animated GIF
    public func createFastForwardTypingGIF(from images: [CGImage], speedFactor: Double = 3.0) -> Data? {
        guard !images.isEmpty else { return nil }
        
        // Sample frames to compress idle pauses
        var sampled: [CGImage] = []
        let strideStep = max(1, Int(speedFactor / 1.5))
        for i in stride(from: 0, to: images.count, by: strideStep) {
            sampled.append(images[i])
        }
        if let last = images.last, !sampled.isEmpty {
            sampled.append(last)
        }
        
        let targetFps = min(24, max(12, Int(10.0 * speedFactor)))
        return createGIF(from: sampled, fps: targetFps)
    }
    
    // MARK: - Native Video Encoder (AVAssetWriter)
    
    public func createMP4(from images: [CGImage], fps: Int) -> Data? {
        guard let first = images.first else { return nil }
        
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("stepit_clip_\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        // Ensure even width and height for H.264
        let width = (first.width / 2) * 2
        let height = (first.height / 2) * 2
        
        do {
            let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mp4)
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
            
            let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            writerInput.expectsMediaDataInRealTime = false
            
            let sourcePixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
            
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: writerInput,
                sourcePixelBufferAttributes: sourcePixelBufferAttributes
            )
            
            if writer.canAdd(writerInput) {
                writer.add(writerInput)
            } else {
                return nil
            }
            
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)
            
            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            
            for (index, image) in images.enumerated() {
                while !writerInput.isReadyForMoreMediaData {
                    Thread.sleep(forTimeInterval: 0.01)
                }
                
                guard let pixelBuffer = pixelBuffer(from: image, width: width, height: height) else { continue }
                let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(index))
                adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
            }
            
            writerInput.markAsFinished()
            
            let semaphore = DispatchSemaphore(value: 0)
            writer.finishWriting {
                semaphore.signal()
            }
            semaphore.wait()
            
            return try? Data(contentsOf: tempURL)
        } catch {
            return nil
        }
    }
    
    private func pixelBuffer(from image: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            attrs as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
        
        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
