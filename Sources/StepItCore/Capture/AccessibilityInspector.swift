import Foundation
import AppKit
import ApplicationServices

public struct ElementInspectionResult: Sendable {
    public var appName: String
    public var bundleIdentifier: String?
    public var windowTitle: String
    public var role: String?
    public var subrole: String?
    public var title: String?
    public var value: String?
    public var roleDescription: String?
    public var elementBounds: ElementRect?
    public var windowBounds: ElementRect?
    
    public init(
        appName: String = "",
        bundleIdentifier: String? = nil,
        windowTitle: String = "",
        role: String? = nil,
        subrole: String? = nil,
        title: String? = nil,
        value: String? = nil,
        roleDescription: String? = nil,
        elementBounds: ElementRect? = nil,
        windowBounds: ElementRect? = nil
    ) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.role = role
        self.subrole = subrole
        self.title = title
        self.value = value
        self.roleDescription = roleDescription
        self.elementBounds = elementBounds
        self.windowBounds = windowBounds
    }
}

public final class AccessibilityInspector: @unchecked Sendable {
    public static let shared = AccessibilityInspector()
    
    public init() {}
    
    public func inspectElement(at screenPoint: CGPoint) -> ElementInspectionResult {
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        var appName = frontmostApp?.localizedName ?? "Unknown App"
        var bundleId = frontmostApp?.bundleIdentifier
        var windowTitle = ""
        var role: String?
        var subrole: String?
        var title: String?
        var value: String?
        var roleDescription: String?
        var elementBounds: ElementRect?
        var windowBounds: ElementRect?
        
        let systemWide = AXUIElementCreateSystemWide()
        var elementRef: AXUIElement?
        
        let axError = AXUIElementCopyElementAtPosition(systemWide, Float(screenPoint.x), Float(screenPoint.y), &elementRef)
        
        if axError == .success, let element = elementRef {
            role = copyStringAttribute(element: element, attribute: kAXRoleAttribute as CFString)
            subrole = copyStringAttribute(element: element, attribute: kAXSubroleAttribute as CFString)
            title = copyStringAttribute(element: element, attribute: kAXTitleAttribute as CFString)
            if title == nil || title?.isEmpty == true {
                title = copyStringAttribute(element: element, attribute: kAXDescriptionAttribute as CFString)
            }
            value = copyStringAttribute(element: element, attribute: kAXValueAttribute as CFString)
            roleDescription = copyStringAttribute(element: element, attribute: kAXRoleDescriptionAttribute as CFString)
            
            // Element Bounds
            elementBounds = copyRect(element: element)
            
            // Check containing window
            var windowRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &windowRef) == .success,
               let winElement = windowRef {
                let win = winElement as! AXUIElement
                if let winTitle = copyStringAttribute(element: win, attribute: kAXTitleAttribute as CFString), !winTitle.isEmpty {
                    windowTitle = winTitle
                }
                windowBounds = copyRect(element: win)
            }
            
            // Check PID to get exact target application if different from frontmost
            var pid: pid_t = 0
            if AXUIElementGetPid(element, &pid) == .success, pid > 0 {
                if let targetApp = NSRunningApplication(processIdentifier: pid) {
                    appName = targetApp.localizedName ?? appName
                    bundleId = targetApp.bundleIdentifier ?? bundleId
                }
            }
        }
        
        return ElementInspectionResult(
            appName: appName,
            bundleIdentifier: bundleId,
            windowTitle: windowTitle,
            role: role,
            subrole: subrole,
            title: title,
            value: value,
            roleDescription: roleDescription,
            elementBounds: elementBounds,
            windowBounds: windowBounds
        )
    }
    
    private func copyStringAttribute(element: AXUIElement, attribute: CFString) -> String? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        if result == .success, let value = valueRef {
            if CFGetTypeID(value) == CFStringGetTypeID() {
                return (value as! String)
            }
        }
        return nil
    }
    
    private func copyRect(element: AXUIElement) -> ElementRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        
        var point = CGPoint.zero
        var size = CGSize.zero
        
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
           let posRef = posRef,
           CFGetTypeID(posRef) == AXValueGetTypeID() {
            let posVal = posRef as! AXValue
            AXValueGetValue(posVal, .cgPoint, &point)
        }
        
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let sizeRef = sizeRef,
           CFGetTypeID(sizeRef) == AXValueGetTypeID() {
            let sizeVal = sizeRef as! AXValue
            AXValueGetValue(sizeVal, .cgSize, &size)
        }
        
        if size.width > 0 && size.height > 0 {
            return ElementRect(x: Double(point.x), y: Double(point.y), width: Double(size.width), height: Double(size.height))
        }
        return nil
    }
}
