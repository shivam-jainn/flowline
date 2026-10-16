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
}

public struct MediaAssets: Codable, Sendable, Equatable {
    public var screenshot: String?
    public var gif: String?
    public var webm: String?
    
    public init(screenshot: String? = nil, gif: String? = nil, webm: String? = nil) {
        self.screenshot = screenshot
        self.gif = gif
        self.webm = webm
    }
}

public enum ActionType: String, Codable, Sendable {
    case click = "click"
    case rightClick = "right_click"
    case doubleClick = "double_click"
    case keyPress = "key_press"
    case appSwitch = "app_switch"
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
    public var assets: MediaAssets
    
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
        assets: MediaAssets = MediaAssets()
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
        self.actionDescription = actionDescription.isEmpty ? Self.synthesizeDefaultDescription(
            action: action,
            elementTitle: elementTitle,
            elementRole: elementRole,
            appName: appName,
            windowTitle: windowTitle
        ) : actionDescription
        self.userNotes = userNotes
        self.assets = assets
    }
    
    public static func synthesizeDefaultDescription(
        action: ActionType,
        elementTitle: String?,
        elementRole: String?,
        appName: String,
        windowTitle: String
    ) -> String {
        let actionWord: String
        switch action {
        case .click: actionWord = "Click"
        case .rightClick: actionWord = "Right-click"
        case .doubleClick: actionWord = "Double-click"
        case .keyPress: actionWord = "Press"
        case .appSwitch: actionWord = "Switch to"
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
