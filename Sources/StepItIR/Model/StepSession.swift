import Foundation

public enum MediaMode: String, Codable, CaseIterable, Sendable {
    case hybrid = "hybrid"
    case staticOnly = "static"
    case animatedOnly = "animated"
    
    public var displayName: String {
        switch self {
        case .hybrid: return "Hybrid (Screenshots + GIFs)"
        case .staticOnly: return "Static Screenshots Only"
        case .animatedOnly: return "Animated GIFs Only"
        }
    }
}

public enum ThemeName: String, Codable, CaseIterable, Sendable {
    case modernMinimal = "modern-minimal"
    case developerDark = "developer-dark"
    case enterpriseSop = "enterprise-sop"
    
    public var displayName: String {
        switch self {
        case .modernMinimal: return "Modern Minimalist"
        case .developerDark: return "Developer Dark"
        case .enterpriseSop: return "Enterprise SOP"
        }
    }
}

public struct ScreenCoordinates: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct ElementRect: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Geometric center in the same (screen-point) coordinate space.
    public var center: Point2D {
        Point2D(x: x + width / 2, y: y + height / 2)
    }
}

public struct MediaAssets: Codable, Sendable, Equatable {
    public var screenshot: String?
    public var gif: String?
    public var webm: String?
    public var zoomCrop: String?
    /// Phase 2: the pre-redaction screenshot kept alongside the blurred export
    /// so the Review Window can toggle redaction off/on non-destructively.
    public var screenshotOriginal: String?
    
    public init(screenshot: String? = nil, gif: String? = nil, webm: String? = nil, zoomCrop: String? = nil, screenshotOriginal: String? = nil) {
        self.screenshot = screenshot
        self.gif = gif
        self.webm = webm
        self.zoomCrop = zoomCrop
        self.screenshotOriginal = screenshotOriginal
    }
}

public enum ActionType: String, Codable, Sendable {
    case click = "click"
    case rightClick = "right_click"
    case doubleClick = "double_click"
    case keyPress = "key_press"
    case typing = "typing"
    case writeCode = "write_code"
    case appSwitch = "app_switch"
    case mouseDrag = "mouse_drag"
    case manual = "manual"
}

public struct Step: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var index: Int
    public var timestamp: Date
    public var action: ActionType
    public var appName: String
    public var bundleIdentifier: String?
    public var windowTitle: String
    public var elementRole: String?
    public var elementTitle: String?
    public var elementValue: String?
    public var coordinates: ScreenCoordinates?
    public var windowBounds: ElementRect?
    public var elementBounds: ElementRect?
    public var actionDescription: String
    public var userNotes: String?
    public var textBlob: String?
    public var isCode: Bool
    public var codeLanguage: String?
    public var assets: MediaAssets
    // MARK: - Phase 2 additions (optional → backward compatible with Phase 1 JSON)
    /// Terminal working directory (`pwd`) when known, e.g. `"~/Code/stepit"`.
    public var workingDirectory: String?
    /// Rendered hotkey combo for `.keyPress` steps, e.g. `"⌘S"`, `"⌘⇧P"`.
    public var hotkeyCombo: String?
    /// `true` when OCR redaction blurred sensitive regions in this step's media.
    public var isRedacted: Bool?
    
    public init(
        id: String = UUID().uuidString,
        index: Int,
        timestamp: Date = Date(),
        action: ActionType = .click,
        appName: String = "",
        bundleIdentifier: String? = nil,
        windowTitle: String = "",
        elementRole: String? = nil,
        elementTitle: String? = nil,
        elementValue: String? = nil,
        coordinates: ScreenCoordinates? = nil,
        windowBounds: ElementRect? = nil,
        elementBounds: ElementRect? = nil,
        actionDescription: String = "",
        userNotes: String? = nil,
        textBlob: String? = nil,
        isCode: Bool = false,
        codeLanguage: String? = nil,
        assets: MediaAssets = MediaAssets(),
        workingDirectory: String? = nil,
        hotkeyCombo: String? = nil,
        isRedacted: Bool? = nil
    ) {
        self.id = id
        self.index = index
        self.timestamp = timestamp
        self.action = action
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.elementRole = elementRole
        self.elementTitle = elementTitle
        self.elementValue = elementValue
        self.coordinates = coordinates
        self.windowBounds = windowBounds
        self.elementBounds = elementBounds
        self.userNotes = userNotes
        self.textBlob = textBlob
        self.isCode = isCode
        self.codeLanguage = codeLanguage
        self.assets = assets
        self.workingDirectory = workingDirectory
        self.hotkeyCombo = hotkeyCombo
        self.isRedacted = isRedacted
        self.actionDescription = actionDescription.isEmpty ? Self.synthesizeDefaultDescription(
            action: action,
            elementTitle: elementTitle,
            elementRole: elementRole,
            appName: appName,
            windowTitle: windowTitle,
            textBlob: textBlob,
            isCode: isCode
        ) : actionDescription
    }
    
    public static func synthesizeDefaultDescription(
        action: ActionType,
        elementTitle: String?,
        elementRole: String?,
        appName: String,
        windowTitle: String,
        textBlob: String? = nil,
        isCode: Bool = false
    ) -> String {
        if action == .typing || action == .writeCode {
            let targetApp = appName.isEmpty ? "editor" : appName
            let isTerminalApp = targetApp.lowercased().contains("terminal") || targetApp.lowercased().contains("iterm") || targetApp.lowercased().contains("warp") || targetApp.lowercased().contains("ghostty") || targetApp.lowercased().contains("kitty") || targetApp.lowercased().contains("alacritty")
            
            if let blob = textBlob, !blob.isEmpty {
                let clean = blob.trimmingCharacters(in: .whitespacesAndNewlines)
                let preview = clean.prefix(40)
                if isTerminalApp || isCode && (clean.hasPrefix("npm ") || clean.hasPrefix("git ") || clean.hasPrefix("swift ") || clean.hasPrefix("cd ") || clean.hasPrefix("cat ") || clean.hasPrefix("ls") || clean.hasPrefix("curl") || clean.hasPrefix("docker")) {
                    return "Run \"\(preview)\(clean.count > 40 ? "..." : "")\" in \(targetApp)"
                } else if isCode {
                    return "Write code in \(targetApp)"
                } else {
                    return "Type \"\(preview)\(clean.count > 40 ? "..." : "")\" in \(targetApp)"
                }
            } else if isTerminalApp {
                return "Execute command in \(targetApp)"
            } else if isCode {
                return "Write code in \(targetApp)"
            } else {
                return "Type text in \(targetApp)"
            }
        }
        
        // Notification Center interactions
        if appName.contains("UserNotificationCenter") || appName.contains("Notification") {
            if let title = elementTitle, !title.trimmingCharacters(in: .whitespaces).isEmpty {
                return "Click notification \"\(title)\""
            }
            return "Click system notification"
        }
        
        let actionWord: String
        switch action {
        case .click: actionWord = "Click"
        case .rightClick: actionWord = "Right-click"
        case .doubleClick: actionWord = "Double-click"
        case .keyPress: actionWord = "Press"
        case .typing: actionWord = "Type in"
        case .writeCode: actionWord = "Write code in"
        case .appSwitch: actionWord = "Switch to"
        case .mouseDrag: actionWord = "Drag in"
        case .manual: actionWord = "Perform step in"
        }
        
        var targetDesc = ""
        if let title = elementTitle, !title.trimmingCharacters(in: .whitespaces).isEmpty {
            targetDesc = "\"\(title)\""
        } else if let role = elementRole {
            targetDesc = role.replacingOccurrences(of: "AX", with: "").lowercased()
        }
        
        var context = ""
        if !windowTitle.isEmpty {
            context = " in \(windowTitle)"
        } else if !appName.isEmpty {
            context = " in \(appName)"
        }
        
        if targetDesc.isEmpty {
            return "\(actionWord)\(context)"
        } else {
            return "\(actionWord) \(targetDesc)\(context)"
        }
    }
}

public struct ExportPaths: Codable, Sendable, Equatable {
    public var pdf: String?
    public var web: String?
    public var markdown: String?
    
    public init(pdf: String? = nil, web: String? = nil, markdown: String? = nil) {
        self.pdf = pdf
        self.web = web
        self.markdown = markdown
    }
}

public struct StepSession: Identifiable, Codable, Sendable {
    public var id: String
    public var startedAt: Date
    public var endedAt: Date?
    public var title: String
    public var summary: String?
    public var theme: ThemeName
    public var mediaMode: MediaMode
    public var steps: [Step]
    public var exports: ExportPaths
    public var synthesizedMarkdown: String?
    
    public init(
        id: String = "sess_\(UUID().uuidString.prefix(8).lowercased())",
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        title: String = "Workflow Recording",
        summary: String? = nil,
        theme: ThemeName = .modernMinimal,
        mediaMode: MediaMode = .hybrid,
        steps: [Step] = [],
        exports: ExportPaths = ExportPaths(),
        synthesizedMarkdown: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.title = title
        self.summary = summary
        self.theme = theme
        self.mediaMode = mediaMode
        self.steps = steps
        self.exports = exports
        self.synthesizedMarkdown = synthesizedMarkdown
    }
}
