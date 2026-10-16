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
        
        // Global mouse monitor for clicks & gestures outside StepIt windows
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [
                .leftMouseDown, .rightMouseDown, .otherMouseDown,
                .leftMouseUp, .rightMouseUp,
                .mouseMoved, .leftMouseDragged, .rightMouseDragged
            ]
        ) { [weak self] event in
            self?.handleMouseEvent(event)
        }
        
        // Global key monitor for shortcuts (Option + Space) & text input
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown]
        ) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // Local monitor so keystrokes / clicks within StepIt / Playground are also captured
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { [weak self] event in
            if event.type == .keyDown {
                self?.handleKeyEvent(event)
            } else {
                self?.handleMouseEvent(event)
            }
            return event
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
        
        switch event.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            SmartGestureDetector.shared.handleMouseMoved(to: mouseLocation)
            
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            SmartGestureDetector.shared.handleMouseUp()
            
        case .otherMouseDown:
            SmartGestureDetector.shared.handleMouseDown(type: event.type, buttonNumber: event.buttonNumber, at: mouseLocation)
            
        case .leftMouseDown, .rightMouseDown:
            SmartGestureDetector.shared.handleMouseDown(type: event.type, buttonNumber: event.buttonNumber, at: mouseLocation)
            
            let action: ActionType
            if event.type == .rightMouseDown {
                action = .rightClick
            } else if event.clickCount >= 2 {
                action = .doubleClick
            } else {
                action = .click
            }
            
            onMouseClick?(action, mouseLocation)
            
        default:
            break
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        // Option + Space check:
        // keyCode 49 is Space in US ANSI keyboard
        if event.keyCode == 49 && event.modifierFlags.contains(.option) {
            onToggleShortcut?()
            return
        }
        
        let mouseLocation = NSEvent.mouseLocation
        
        // Return / Enter key (keyCode 36 on ANSI, 76 on Keypad): finalize command / line immediately
        if event.keyCode == 36 || event.keyCode == 76 {
            TextTypingAggregator.shared.handleReturnKey(at: mouseLocation)
            return
        }
        
        // Delete / Backspace key (keyCode 51)
        if event.keyCode == 51 {
            TextTypingAggregator.shared.handleBackspace(at: mouseLocation)
            return
        }
        
        // Tab key (keyCode 48)
        if event.keyCode == 48 {
            TextTypingAggregator.shared.appendKeystroke("\t", at: mouseLocation)
            return
        }
        
        // Control + C (Terminal Interrupt SIGINT)
        if event.modifierFlags.contains(.control) && (event.keyCode == 8 || event.charactersIgnoringModifiers?.lowercased() == "c") {
            TextTypingAggregator.shared.handleControlC(at: mouseLocation)
            return
        }
        
        // Feed printable typing keystrokes into TextTypingAggregator
        if let chars = event.characters, !chars.isEmpty && !event.modifierFlags.contains(.command) {
            // Check for printable characters
            if let first = chars.unicodeScalars.first, first.value >= 32 && first.value != 127 {
                TextTypingAggregator.shared.appendKeystroke(chars, at: mouseLocation)
            }
        }
    }
}
