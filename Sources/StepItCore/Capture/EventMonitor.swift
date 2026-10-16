import Foundation
import AppKit

public final class EventMonitor: @unchecked Sendable {
    public static let shared = EventMonitor()
    
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalKeyMonitor: Any?
    
    public var onMouseClick: ((ActionType, CGPoint) -> Void)?
    public var onToggleShortcut: (() -> Void)?
    
    private(set) public var isMonitoring = false
    
    public init() {}
    
    public func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        // Global mouse monitor for clicks outside StepIt windows
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            self?.handleMouseEvent(event)
        }
        
        // Global key monitor for shortcuts (Option + Space)
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown]
        ) { [weak self] event in
            self?.handleKeyEvent(event)
        }
    }
    
    public func stop() {
        guard isMonitoring else { return }
        isMonitoring = false
        
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
    }
    
    private func handleMouseEvent(_ event: NSEvent) {
        // AppKit coordinates: origin is at bottom-left of primary screen
        // NSEvent.mouseLocation gives global screen coordinate in Cocoa points
        let mouseLocation = NSEvent.mouseLocation
        
        let action: ActionType
        if event.type == .rightMouseDown {
            action = .rightClick
        } else if event.clickCount >= 2 {
            action = .doubleClick
        } else {
            action = .click
        }
        
        onMouseClick?(action, mouseLocation)
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        // Option + Space check:
        // keyCode 49 is Space in US ANSI keyboard
        if event.keyCode == 49 && event.modifierFlags.contains(.option) {
            onToggleShortcut?()
            return
        }
        
        // Feed printable typing keystrokes into TextTypingAggregator
        if let chars = event.characters, !chars.isEmpty && !event.modifierFlags.contains(.command) {
            // Ignore raw function/arrow keys (Unicode private use area)
            if let first = chars.unicodeScalars.first, first.value >= 32 && first.value != 127 {
                let mouseLocation = NSEvent.mouseLocation
                TextTypingAggregator.shared.appendKeystroke(chars, at: mouseLocation)
            }
        }
    }
}
