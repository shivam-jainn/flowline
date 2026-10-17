import AppKit
import StepItIR
import SwiftUI
import StepItCore

public final class FloatingHUDWindowController: @unchecked Sendable {
    public static let shared = FloatingHUDWindowController()
    
    private var window: NSPanel?
    public var onStopRequested: (() -> Void)?
    
    public init() {}
    
    @MainActor
    public func show() {
        if window == nil {
            createWindow()
        }
        
        positionWindow()
        window?.orderFrontRegardless()
    }
    
    @MainActor
    public func hide() {
        window?.orderOut(nil)
    }
    
    @MainActor
    private func createWindow() {
        let hudView = FloatingHUDView { [weak self] in
            self?.onStopRequested?()
        }
        
        let hostingView = NSHostingView(rootView: hudView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 330, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.contentView = hostingView
        
        self.window = panel
    }
    
    @MainActor
    private func positionWindow() {
        guard let window = window, let screen = NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        let windowWidth: CGFloat = 330
        let windowHeight: CGFloat = 48
        
        let x = screenRect.origin.x + (screenRect.width - windowWidth) / 2.0
        let y = screenRect.origin.y + screenRect.height - windowHeight - 24
        
        window.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
    }
}
