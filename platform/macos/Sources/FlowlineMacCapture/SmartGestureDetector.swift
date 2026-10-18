import Foundation
import FlowlineIR
import FlowlinePipeline
import FlowlineCaptureAPI
import AppKit

public struct GestureEventNotice: Sendable {
    public let action: GestureAction
    public let gestureName: String
    public let timestamp: Date
    public let location: CGPoint
    
    public init(action: GestureAction, gestureName: String, timestamp: Date = Date(), location: CGPoint = .zero) {
        self.action = action
        self.gestureName = gestureName
        self.timestamp = timestamp
        self.location = location
    }
}

public final class SmartGestureDetector: @unchecked Sendable {
    
    public var settings: GestureSettings = GestureSettings()
    public var onGestureDetected: ((GestureEventNotice) -> Void)?
    
    // Internal tracking state
    private struct MouseSample {
        let point: CGPoint
        let timestamp: Date
    }
    
    private var moveHistory: [MouseSample] = []
    private var lastShakeTriggerTime: Date = .distantPast
    private var lastCornerTriggerTime: Date = .distantPast
    private var lastCornerCandidate: String?
    private var cornerDwellTimer: DispatchSourceTimer?
    
    private var lastRightClickTime: Date = .distantPast
    private var lastRightClickPoint: CGPoint = .zero
    
    private var longPressTimer: DispatchSourceTimer?
    private var longPressStartPoint: CGPoint = .zero
    private var isLongPressActive = false
    
    private let queue = DispatchQueue(label: "com.flowline.smartgestures", qos: .userInteractive)
    
    public init(settings: GestureSettings = GestureSettings()) {
        self.settings = settings
    }
    
    // MARK: - Event Ingestion
    
    /// Call on mouse movement or dragging
    public func handleMouseMoved(to point: CGPoint) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let now = Date()
            
            // Check long-press cancellation if moved significantly
            if self.isLongPressActive {
                let dist = hypot(point.x - self.longPressStartPoint.x, point.y - self.longPressStartPoint.y)
                if dist > 12.0 {
                    self.cancelLongPress()
                }
            }
            
            // 1. Process Mouse Shake
            if self.settings.shakeToPauseEnabled && self.settings.shakeAction != .none {
                self.evaluateMouseShake(point: point, now: now)
            }
            
            // 2. Process Hot Corners
            if self.settings.hotCorners.enabled {
                self.evaluateHotCorners(point: point, now: now)
            }
        }
    }
    
    /// Call on mouse down (left, right, or middle)
    public func handleMouseDown(button: MouseButton, at point: CGPoint) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let now = Date()
            
            // Middle-Click
            if button == .middle && self.settings.middleClickAction != .none {
                self.dispatchGesture(self.settings.middleClickAction, name: "Middle-Click", at: point)
                return
            }
            
            // Right-Click handling for Double Right-Click
            if button == .right && self.settings.doubleRightClickAction != .none {
                let interval = now.timeIntervalSince(self.lastRightClickTime)
                let dist = hypot(point.x - self.lastRightClickPoint.x, point.y - self.lastRightClickPoint.y)
                if interval < 0.38 && dist < 22.0 {
                    self.cancelLongPress()
                    self.lastRightClickTime = .distantPast
                    self.dispatchGesture(self.settings.doubleRightClickAction, name: "Double Right-Click", at: point)
                    return
                }
                self.lastRightClickTime = now
                self.lastRightClickPoint = point
            }
            
            // Start Long-Press evaluation
            if self.settings.longPressAction != .none {
                self.startLongPress(at: point)
            }
        }
    }
    
    /// Call on mouse up
    public func handleMouseUp() {
        queue.async { [weak self] in
            self?.cancelLongPress()
        }
    }
    
    // MARK: - Mouse Shake Detection Algorithm
    
    private func evaluateMouseShake(point: CGPoint, now: Date) {
        moveHistory.append(MouseSample(point: point, timestamp: now))
        
        // Retain only samples from the last 0.45 seconds
        let windowSeconds: Double = 0.45
        moveHistory.removeAll { now.timeIntervalSince($0.timestamp) > windowSeconds }
        guard moveHistory.count >= 8 else { return }
        
        // Check cooldown (1.5 seconds)
        guard now.timeIntervalSince(lastShakeTriggerTime) > 1.5 else { return }
        
        // Count horizontal reversals and aggregate velocity
        var reversals = 0
        var lastDirection: Int = 0 // -1: left, 1: right
        var totalDistance: CGFloat = 0
        
        for i in 1..<moveHistory.count {
            let p0 = moveHistory[i - 1].point
            let p1 = moveHistory[i].point
            let dx = p1.x - p0.x
            totalDistance += abs(dx)
            
            let dir = dx > 4.0 ? 1 : (dx < -4.0 ? -1 : 0)
            if dir != 0 {
                if lastDirection != 0 && dir != lastDirection {
                    reversals += 1
                }
                lastDirection = dir
            }
        }
        
        let duration = max(0.08, now.timeIntervalSince(moveHistory.first!.timestamp))
        let velocity = Double(totalDistance) / duration
        let threshold = settings.shakeSensitivity.thresholdVelocity
        
        // Trigger if at least 3 distinct direction reversals with sufficient speed
        if reversals >= 3 && velocity >= threshold {
            lastShakeTriggerTime = now
            moveHistory.removeAll()
            dispatchGesture(
                settings.shakeAction,
                name: "Mouse Shake (\(Int(velocity)) px/s)",
                at: point
            )
        }
    }
    
    // MARK: - Hot Corners Algorithm
    
    private func evaluateHotCorners(point: CGPoint, now: Date) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        let cornerThreshold: CGFloat = 16.0
        
        var currentCorner: (name: String, action: GestureAction)? = nil
        
        let isLeft = point.x <= frame.minX + cornerThreshold
        let isRight = point.x >= frame.maxX - cornerThreshold
        let isTop = point.y >= frame.maxY - cornerThreshold
        let isBottom = point.y <= frame.minY + cornerThreshold
        
        if isTop && isLeft {
            currentCorner = ("Top-Left Corner", settings.hotCorners.topLeft)
        } else if isTop && isRight {
            currentCorner = ("Top-Right Corner", settings.hotCorners.topRight)
        } else if isBottom && isLeft {
            currentCorner = ("Bottom-Left Corner", settings.hotCorners.bottomLeft)
        } else if isBottom && isRight {
            currentCorner = ("Bottom-Right Corner", settings.hotCorners.bottomRight)
        }
        
        guard let corner = currentCorner, corner.action != .none else {
            // Cancel pending dwell if cursor moved away from corner
            if lastCornerCandidate != nil {
                cornerDwellTimer?.cancel()
                cornerDwellTimer = nil
                lastCornerCandidate = nil
            }
            return
        }
        
        // Check cooldown
        guard now.timeIntervalSince(lastCornerTriggerTime) > 2.0 else { return }
        
        if lastCornerCandidate != corner.name {
            lastCornerCandidate = corner.name
            cornerDwellTimer?.cancel()
            
            // Require 200ms dwell in corner to avoid accidental grazing
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 0.20)
            timer.setEventHandler { [weak self] in
                guard let self = self, self.lastCornerCandidate == corner.name else { return }
                self.lastCornerTriggerTime = Date()
                self.lastCornerCandidate = nil
                self.cornerDwellTimer = nil
                self.dispatchGesture(corner.action, name: corner.name, at: point)
            }
            self.cornerDwellTimer = timer
            timer.resume()
        }
    }
    
    // MARK: - Long Press
    
    private func startLongPress(at point: CGPoint) {
        cancelLongPress()
        isLongPressActive = true
        longPressStartPoint = point
        
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + settings.longPressDurationSec)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isLongPressActive else { return }
            self.isLongPressActive = false
            self.longPressTimer = nil
            self.dispatchGesture(self.settings.longPressAction, name: "Long Press (\(String(format: "%.1f", self.settings.longPressDurationSec))s)", at: point)
        }
        longPressTimer = timer
        timer.resume()
    }
    
    private func cancelLongPress() {
        isLongPressActive = false
        longPressTimer?.cancel()
        longPressTimer = nil
    }
    
    // MARK: - Dispatch
    
    private func dispatchGesture(_ action: GestureAction, name: String, at point: CGPoint) {
        guard action != .none else { return }
        let notice = GestureEventNotice(action: action, gestureName: name, timestamp: Date(), location: point)
        
        DispatchQueue.main.async { [weak self] in
            self?.onGestureDetected?(notice)
        }
    }
}
