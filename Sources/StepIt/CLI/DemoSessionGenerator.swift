import Foundation
import AppKit
import CoreGraphics
import StepItCore

public struct DemoSessionGenerator {
    public static func generateDemoSession() -> StepSession {
        let sessionId = "sess_github_ssh"
        let mediaDir = SessionStore.shared.mediaDirectory(for: sessionId)
        try? FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        
        // Create 3 demo steps
        var steps: [Step] = []
        
        // Step 1: System Settings / Terminal
        let step1Image = createMockScreenshot(
            title: "Terminal — Generate SSH Key",
            subtitle: "ssh-keygen -t ed25519 -C 'shivam@example.com'",
            highlightPoint: CGPoint(x: 240, y: 380),
            stepIndex: 1
        )
        let step1Png = ScreenRecorder.shared.imageToPNGData(step1Image)!
        let step1Rel = try? SessionStore.shared.saveMedia(data: step1Png, sessionID: sessionId, filename: "step_01.png")
        
        // Step 1 Animated GIF
        let step1GifData = createMockAnimatedGIF(baseImage: step1Image, clickPoint: CGPoint(x: 240, y: 380))
        let step1GifRel = try? SessionStore.shared.saveMedia(data: step1GifData, sessionID: sessionId, filename: "step_01.gif")
        
        let step1 = Step(
            id: UUID().uuidString,
            index: 1,
            action: .click,
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            windowTitle: "Terminal — zsh — 80×24",
            elementRole: "AXTextField",
            elementTitle: "ssh-keygen -t ed25519",
            coordinates: ScreenCoordinates(x: 240, y: 380),
            actionDescription: "Generate a new Ed25519 SSH key in Terminal",
            userNotes: "Press Enter to accept default file location (~/.ssh/id_ed25519).",
            assets: MediaAssets(screenshot: step1Rel, gif: step1GifRel)
        )
        steps.append(step1)
        
        // Step 2: Safari / GitHub Navigation
        let step2Image = createMockScreenshot(
            title: "GitHub — Account Settings",
            subtitle: "Click 'SSH and GPG keys' in left sidebar",
            highlightPoint: CGPoint(x: 180, y: 290),
            stepIndex: 2
        )
        let step2Png = ScreenRecorder.shared.imageToPNGData(step2Image)!
        let step2Rel = try? SessionStore.shared.saveMedia(data: step2Png, sessionID: sessionId, filename: "step_02.png")
        
        let step2GifData = createMockAnimatedGIF(baseImage: step2Image, clickPoint: CGPoint(x: 180, y: 290))
        let step2GifRel = try? SessionStore.shared.saveMedia(data: step2GifData, sessionID: sessionId, filename: "step_02.gif")
        
        let step2 = Step(
            id: UUID().uuidString,
            index: 2,
            action: .click,
            appName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            windowTitle: "GitHub — Personal Settings",
            elementRole: "AXLink",
            elementTitle: "SSH and GPG keys",
            coordinates: ScreenCoordinates(x: 180, y: 290),
            actionDescription: "Navigate to 'SSH and GPG keys' in GitHub Settings",
            userNotes: "Ensure you are logged in to your primary GitHub account.",
            assets: MediaAssets(screenshot: step2Rel, gif: step2GifRel)
        )
        steps.append(step2)
        
        // Step 3: Click "New SSH key" button
        let step3Image = createMockScreenshot(
            title: "GitHub — SSH Keys List",
            subtitle: "Click green 'New SSH key' button",
            highlightPoint: CGPoint(x: 680, y: 190),
            stepIndex: 3
        )
        let step3Png = ScreenRecorder.shared.imageToPNGData(step3Image)!
        let step3Rel = try? SessionStore.shared.saveMedia(data: step3Png, sessionID: sessionId, filename: "step_03.png")
        
        let step3GifData = createMockAnimatedGIF(baseImage: step3Image, clickPoint: CGPoint(x: 680, y: 190))
        let step3GifRel = try? SessionStore.shared.saveMedia(data: step3GifData, sessionID: sessionId, filename: "step_03.gif")
        
        let step3 = Step(
            id: UUID().uuidString,
            index: 3,
            action: .click,
            appName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            windowTitle: "GitHub — SSH and GPG keys",
            elementRole: "AXButton",
            elementTitle: "New SSH key",
            coordinates: ScreenCoordinates(x: 680, y: 190),
            actionDescription: "Click 'New SSH key' to register your public key",
            userNotes: "Title it descriptively (e.g., 'MacBook Pro Workstation').",
            assets: MediaAssets(screenshot: step3Rel, gif: step3GifRel)
        )
        steps.append(step3)
        
        let synthesizedDoc = """
# ⚡️ Configuring GitHub SSH Keys on macOS

> Complete step-by-step Standard Operating Procedure (SOP) for creating and associating hardware-backed or Ed25519 SSH keys with your GitHub account.

---

### Prerequisites
- macOS Sonoma or later
- Terminal or iTerm2
- Active GitHub account

---

### Step 1: Generate a new Ed25519 SSH key
Open your terminal and run the standard key generation utility:
```bash
ssh-keygen -t ed25519 -C "your_email@example.com"
```
When prompted for a file to save the key, press Enter to accept the default location (`~/.ssh/id_ed25519`).

![Generate SSH Key](\(step1Rel ?? "media/step_01.png"))

---

### Step 2: Navigate to GitHub Settings
Open your browser, navigate to your GitHub Profile avatar in the top right, select **Settings**, and click **SSH and GPG keys** in the sidebar.

![Navigate to SSH Settings](\(step2Rel ?? "media/step_02.png"))

---

### Step 3: Register Public Key
Click the green **New SSH key** button, paste the contents of `~/.ssh/id_ed25519.pub`, select `Authentication Key`, and save.

![New SSH Key](\(step3Rel ?? "media/step_03.png"))

---

_Generated effortlessly with [StepIt](https://github.com/stepit/stepit) for macOS._
"""
        
        return StepSession(
            id: sessionId,
            startedAt: Date().addingTimeInterval(-180),
            endedAt: Date(),
            title: "Configuring GitHub SSH Keys on macOS",
            summary: "Executive walkthrough for generating secure Ed25519 keys, adding them to macOS Keychain, and registering them on GitHub.",
            theme: .modernMinimal,
            mediaMode: .hybrid,
            steps: steps,
            synthesizedMarkdown: synthesizedDoc
        )
    }
    
    private static func createMockScreenshot(
        title: String,
        subtitle: String,
        highlightPoint: CGPoint,
        stepIndex: Int
    ) -> CGImage {
        let width = 1000
        let height = 625
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!
        
        // Window background: modern dark slate
        ctx.setFillColor(NSColor(srgbRed: 0.08, green: 0.11, blue: 0.17, alpha: 1.0).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        // Top window titlebar
        ctx.setFillColor(NSColor(srgbRed: 0.12, green: 0.16, blue: 0.24, alpha: 1.0).cgColor)
        ctx.fill(CGRect(x: 0, y: height - 42, width: width, height: 42))
        
        // macOS traffic lights
        let redLight = CGRect(x: 18, y: height - 26, width: 12, height: 12)
        let yellowLight = CGRect(x: 38, y: height - 26, width: 12, height: 12)
        let greenLight = CGRect(x: 58, y: height - 26, width: 12, height: 12)
        
        ctx.setFillColor(NSColor(srgbRed: 0.94, green: 0.36, blue: 0.35, alpha: 1.0).cgColor)
        ctx.fillEllipse(in: redLight)
        ctx.setFillColor(NSColor(srgbRed: 0.98, green: 0.74, blue: 0.23, alpha: 1.0).cgColor)
        ctx.fillEllipse(in: yellowLight)
        ctx.setFillColor(NSColor(srgbRed: 0.16, green: 0.78, blue: 0.36, alpha: 1.0).cgColor)
        ctx.fillEllipse(in: greenLight)
        
        // Inner card container
        let cardRect = CGRect(x: 40, y: 50, width: width - 80, height: height - 120)
        ctx.setFillColor(NSColor(srgbRed: 0.14, green: 0.18, blue: 0.27, alpha: 1.0).cgColor)
        ctx.fill(cardRect)
        
        // Draw decorative lines / UI mock blocks
        ctx.setFillColor(NSColor(srgbRed: 0.22, green: 0.28, blue: 0.40, alpha: 0.8).cgColor)
        ctx.fill(CGRect(x: 70, y: height - 160, width: 340, height: 32))
        ctx.fill(CGRect(x: 70, y: height - 220, width: 620, height: 24))
        ctx.fill(CGRect(x: 70, y: height - 260, width: 500, height: 24))
        ctx.fill(CGRect(x: 70, y: height - 300, width: 420, height: 24))
        
        // Draw Mock Target Button at highlight point
        let btnRect = CGRect(x: highlightPoint.x - 70, y: highlightPoint.y - 18, width: 140, height: 36)
        ctx.setFillColor(NSColor(srgbRed: 0.15, green: 0.65, blue: 0.45, alpha: 1.0).cgColor)
        ctx.fill(btnRect)
        
        // Draw StepIt Highlight Marker (Glow + Ring + Dot + Numbered Badge)
        let radius: CGFloat = 32.0
        // Soft Glow
        ctx.setFillColor(NSColor(srgbRed: 0.94, green: 0.27, blue: 0.27, alpha: 0.35).cgColor)
        ctx.fillEllipse(in: CGRect(x: highlightPoint.x - radius * 1.5, y: highlightPoint.y - radius * 1.5, width: radius * 3.0, height: radius * 3.0))
        // Ring
        ctx.setStrokeColor(NSColor(srgbRed: 0.94, green: 0.27, blue: 0.27, alpha: 1.0).cgColor)
        ctx.setLineWidth(3.5)
        ctx.strokeEllipse(in: CGRect(x: highlightPoint.x - radius, y: highlightPoint.y - radius, width: radius * 2.0, height: radius * 2.0))
        // Dot
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: highlightPoint.x - 4, y: highlightPoint.y - 4, width: 8, height: 8))
        // Badge
        let badgeCenter = CGPoint(x: highlightPoint.x + radius * 0.75, y: highlightPoint.y + radius * 0.75)
        ctx.setFillColor(NSColor(srgbRed: 0.94, green: 0.27, blue: 0.27, alpha: 1.0).cgColor)
        ctx.fillEllipse(in: CGRect(x: badgeCenter.x - 14, y: badgeCenter.y - 14, width: 28, height: 28))
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2.0)
        ctx.strokeEllipse(in: CGRect(x: badgeCenter.x - 14, y: badgeCenter.y - 14, width: 28, height: 28))
        
        return ctx.makeImage()!
    }
    
    private static func createMockAnimatedGIF(baseImage: CGImage, clickPoint: CGPoint) -> Data {
        var frames: [CGImage] = []
        let width = baseImage.width
        let height = baseImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        // Generate 6 frames with expanding ripple
        for i in 0..<6 {
            let ctx = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )!
            
            ctx.draw(baseImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            
            let rippleRadius = 24.0 + CGFloat(i * 10)
            let alpha = max(0.0, 0.9 - Double(i) * 0.15)
            
            ctx.setStrokeColor(NSColor(srgbRed: 0.94, green: 0.27, blue: 0.27, alpha: CGFloat(alpha)).cgColor)
            ctx.setLineWidth(3.0)
            ctx.strokeEllipse(in: CGRect(x: clickPoint.x - rippleRadius, y: clickPoint.y - rippleRadius, width: rippleRadius * 2.0, height: rippleRadius * 2.0))
            
            if let frame = ctx.makeImage() {
                frames.append(frame)
            }
        }
        
        return MicroClipRecorder.shared.createGIF(from: frames, fps: 8) ?? Data()
    }
}
