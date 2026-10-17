import AppKit
import StepItStorage
import StepItMacCapture
import StepItCaptureAPI
import StepItPublishing
import StepItAIGateway
import StepItPipeline
import StepItEngine
import StepItIR
import SwiftUI
import StepItCore

public final class ReviewWindowController: @unchecked Sendable {
    public static let shared = ReviewWindowController()
    
    private var window: NSWindow?
    
    public init() {}
    
    @MainActor
    public func show(for session: StepSession) {
        if window == nil {
            let reviewView = ReviewWindow(session: session)
            let hostingView = NSHostingView(rootView: reviewView)
            
            let win = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 1050, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            
            win.center()
            win.title = "StepIt — Review & Publish"
            win.titleVisibility = .visible
            win.minSize = NSSize(width: 960, height: 600)
            win.contentView = hostingView
            win.isReleasedWhenClosed = false
            
            self.window = win
        } else {
            let reviewView = ReviewWindow(session: session)
            window?.contentView = NSHostingView(rootView: reviewView)
        }
        
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
