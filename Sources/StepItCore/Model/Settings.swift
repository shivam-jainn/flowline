import Foundation
import StepItIR
import StepItPipeline

public typealias RedactionBlurStyle = StepItPipeline.RedactionBlurStyle
public typealias PrivacySettings = StepItPipeline.PrivacySettings
public typealias GestureAction = StepItIR.GestureAction

public struct CaptureSettings: Codable, Sendable, Equatable {
    public var mediaMode: MediaMode
    public var gifFps: Int
    public var clipDurationPreClickSec: Double
    public var clipDurationPostClickSec: Double
    public var highlightClicks: Bool
    public var highlightColorHex: String
    public var highlightRadius: Double
    /// Phase 2: emit discrete `.appSwitch` steps when the frontmost app changes
    /// during a recording (opt-in; context tracking is always updated).
    public var recordAppSwitches: Bool
    
    public init(
        mediaMode: MediaMode = .hybrid,
        gifFps: Int = 15,
        clipDurationPreClickSec: Double = 0.5,
        clipDurationPostClickSec: Double = 1.5,
        highlightClicks: Bool = true,
        highlightColorHex: String = "#EF4444",
        highlightRadius: Double = 28.0,
        recordAppSwitches: Bool = false
    ) {
        self.mediaMode = mediaMode
        self.gifFps = gifFps
        self.clipDurationPreClickSec = clipDurationPreClickSec
        self.clipDurationPostClickSec = clipDurationPostClickSec
        self.highlightClicks = highlightClicks
        self.highlightColorHex = highlightColorHex
        self.highlightRadius = highlightRadius
        self.recordAppSwitches = recordAppSwitches
    }

    // Lenient decoding so Settings.json written before Phase 2 (without
    // `recordAppSwitches`) still loads instead of resetting user settings.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.mediaMode = try container.decodeIfPresent(MediaMode.self, forKey: .mediaMode) ?? .hybrid
        self.gifFps = try container.decodeIfPresent(Int.self, forKey: .gifFps) ?? 15
        self.clipDurationPreClickSec = try container.decodeIfPresent(Double.self, forKey: .clipDurationPreClickSec) ?? 0.5
        self.clipDurationPostClickSec = try container.decodeIfPresent(Double.self, forKey: .clipDurationPostClickSec) ?? 1.5
        self.highlightClicks = try container.decodeIfPresent(Bool.self, forKey: .highlightClicks) ?? true
        self.highlightColorHex = try container.decodeIfPresent(String.self, forKey: .highlightColorHex) ?? "#EF4444"
        self.highlightRadius = try container.decodeIfPresent(Double.self, forKey: .highlightRadius) ?? 28.0
        self.recordAppSwitches = try container.decodeIfPresent(Bool.self, forKey: .recordAppSwitches) ?? false
    }
}

public struct PublishingSettings: Codable, Sendable, Equatable {
    public var defaultTheme: ThemeName
    public var authorName: String
    public var companyName: String
    public var enableInteractiveChecklists: Bool
    public var pdfPaperSize: String
    public var includeTimestamp: Bool
    
    public init(
        defaultTheme: ThemeName = .modernMinimal,
        authorName: String = "",
        companyName: String = "StepIt Docs",
        enableInteractiveChecklists: Bool = true,
        pdfPaperSize: String = "A4",
        includeTimestamp: Bool = true
    ) {
        self.defaultTheme = defaultTheme
        self.authorName = authorName
        self.companyName = companyName
        self.enableInteractiveChecklists = enableInteractiveChecklists
        self.pdfPaperSize = pdfPaperSize
        self.includeTimestamp = includeTimestamp
    }
}

public enum GatewayProviderType: String, Codable, CaseIterable, Sendable {
    case openRouter = "openrouter"
    case customOpenAI = "custom_openai"
    case ollama = "ollama"
    case lmStudio = "lm_studio"
    case cli = "cli"
    
    public var displayName: String {
        switch self {
        case .openRouter: return "OpenRouter (Cloud Gateway)"
        case .customOpenAI: return "OpenAI / Portkey / LiteLLM"
        case .ollama: return "Ollama (Local Offline)"
        case .lmStudio: return "LM Studio (Local Offline)"
        case .cli: return "Local CLI Pipeline"
        }
    }
    
    public var defaultBaseURL: String {
        switch self {
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .customOpenAI: return "https://api.openai.com/v1"
        case .ollama: return "http://localhost:11434/v1"
        case .lmStudio: return "http://localhost:1234/v1"
        case .cli: return ""
        }
    }
    
    public var defaultModel: String {
        switch self {
        case .openRouter: return "anthropic/claude-3.5-sonnet"
        case .customOpenAI: return "gpt-4o"
        case .ollama: return "llama3.2-vision"
        case .lmStudio: return "meta-llama-3.2-11b-vision-instruct"
        case .cli: return "ollama run llama3.2-vision"
        }
    }
}

public struct GatewaySettings: Codable, Sendable, Equatable {
    public var provider: GatewayProviderType
    public var baseURL: String
    public var apiKey: String
    public var model: String
    public var visionEnabled: Bool
    public var temperature: Double
    
    public init(
        provider: GatewayProviderType = .openRouter,
        baseURL: String = "https://openrouter.ai/api/v1",
        apiKey: String = "",
        model: String = "anthropic/claude-3.5-sonnet",
        visionEnabled: Bool = true,
        temperature: Double = 0.2
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.visionEnabled = visionEnabled
        self.temperature = temperature
    }
}

public struct HotkeySettings: Codable, Sendable, Equatable {
    public var toggleRecording: String
    
    public init(toggleRecording: String = "⌥ Space") {
        self.toggleRecording = toggleRecording
    }
}

// MARK: - Phase 2: Privacy & Shortcut Capture Configuration

/// Which keyboard chords become discrete documentation steps.
public struct HotkeyCaptureSettings: Codable, Sendable, Equatable {
    /// Record `⌘`/`⌃` chords (`⌘S`, `⌘⇧P`, `⌃A`, …) as `.keyPress` steps.
    public var captureModifierShortcuts: Bool = true
    /// Record navigation keys (Esc, Tab, arrows, F-keys) as `.keyPress` steps.
    public var captureNavigationKeys: Bool = true
    /// Extra chords the recorder must consume and never record (app-registered
    /// shortcuts). System combos like `⌘Tab` / `⌘Space` are always consumed.
    public var ignoredCombos: Set<String> = []

    public init() {}
}

// MARK: - Smart Gestures Configuration

public enum GestureSensitivity: String, Codable, CaseIterable, Sendable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    
    public var title: String {
        switch self {
        case .low: return "Low (Vigorous Motion)"
        case .medium: return "Medium (Balanced)"
        case .high: return "High (Quick Response)"
        }
    }
    
    public var thresholdVelocity: Double {
        switch self {
        case .low: return 850.0
        case .medium: return 550.0
        case .high: return 380.0
        }
    }
}

public struct HotCornerSettings: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var topLeft: GestureAction
    public var topRight: GestureAction
    public var bottomLeft: GestureAction
    public var bottomRight: GestureAction
    
    public init(
        enabled: Bool = true,
        topLeft: GestureAction = .discardLastStep,
        topRight: GestureAction = .pauseResume,
        bottomLeft: GestureAction = .none,
        bottomRight: GestureAction = .stopAndReview
    ) {
        self.enabled = enabled
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
    }
}

public struct GestureSettings: Codable, Sendable, Equatable {
    public var shakeToPauseEnabled: Bool
    public var shakeSensitivity: GestureSensitivity
    public var shakeAction: GestureAction
    
    public var hotCorners: HotCornerSettings
    
    public var middleClickAction: GestureAction
    public var doubleRightClickAction: GestureAction
    public var longPressAction: GestureAction
    public var longPressDurationSec: Double
    
    public init(
        shakeToPauseEnabled: Bool = true,
        shakeSensitivity: GestureSensitivity = .medium,
        shakeAction: GestureAction = .pauseResume,
        hotCorners: HotCornerSettings = HotCornerSettings(),
        middleClickAction: GestureAction = .addCheckpoint,
        doubleRightClickAction: GestureAction = .discardLastStep,
        longPressAction: GestureAction = .captureSnapshot,
        longPressDurationSec: Double = 0.8
    ) {
        self.shakeToPauseEnabled = shakeToPauseEnabled
        self.shakeSensitivity = shakeSensitivity
        self.shakeAction = shakeAction
        self.hotCorners = hotCorners
        self.middleClickAction = middleClickAction
        self.doubleRightClickAction = doubleRightClickAction
        self.longPressAction = longPressAction
        self.longPressDurationSec = longPressDurationSec
    }
}

public struct StepItSettings: Codable, Sendable, Equatable {
    public var capture: CaptureSettings
    public var publishing: PublishingSettings
    public var gateway: GatewaySettings
    public var hotkeys: HotkeySettings
    public var gestures: GestureSettings
    public var privacy: PrivacySettings
    public var hotkeyCapture: HotkeyCaptureSettings
    
    public init(
        capture: CaptureSettings = CaptureSettings(),
        publishing: PublishingSettings = PublishingSettings(),
        gateway: GatewaySettings = GatewaySettings(),
        hotkeys: HotkeySettings = HotkeySettings(),
        gestures: GestureSettings = GestureSettings(),
        privacy: PrivacySettings = PrivacySettings(),
        hotkeyCapture: HotkeyCaptureSettings = HotkeyCaptureSettings()
    ) {
        self.capture = capture
        self.publishing = publishing
        self.gateway = gateway
        self.hotkeys = hotkeys
        self.gestures = gestures
        self.privacy = privacy
        self.hotkeyCapture = hotkeyCapture
    }
    
    // Custom decoder for backwards compatibility when decoding saved JSON without
    // gestures (Phase 1) or privacy/hotkeyCapture (Phase 2).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.capture = try container.decodeIfPresent(CaptureSettings.self, forKey: .capture) ?? CaptureSettings()
        self.publishing = try container.decodeIfPresent(PublishingSettings.self, forKey: .publishing) ?? PublishingSettings()
        self.gateway = try container.decodeIfPresent(GatewaySettings.self, forKey: .gateway) ?? GatewaySettings()
        self.hotkeys = try container.decodeIfPresent(HotkeySettings.self, forKey: .hotkeys) ?? HotkeySettings()
        self.gestures = try container.decodeIfPresent(GestureSettings.self, forKey: .gestures) ?? GestureSettings()
        self.privacy = try container.decodeIfPresent(PrivacySettings.self, forKey: .privacy) ?? PrivacySettings()
        self.hotkeyCapture = try container.decodeIfPresent(HotkeyCaptureSettings.self, forKey: .hotkeyCapture) ?? HotkeyCaptureSettings()
    }

    
    public static var defaultSettings: StepItSettings {
        var s = StepItSettings()
        // Check environment variables for convenient defaults
        if let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !key.isEmpty {
            s.gateway.apiKey = key
            s.gateway.provider = .openRouter
            s.gateway.baseURL = "https://openrouter.ai/api/v1"
        } else if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty {
            s.gateway.apiKey = key
            s.gateway.provider = .customOpenAI
            s.gateway.baseURL = "https://api.openai.com/v1"
        }
        return s
    }
}

public typealias Settings = StepItSettings
