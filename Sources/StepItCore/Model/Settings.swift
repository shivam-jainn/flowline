import Foundation

public struct CaptureSettings: Codable, Sendable, Equatable {
    public var mediaMode: MediaMode
    public var gifFps: Int
    public var clipDurationPreClickSec: Double
    public var clipDurationPostClickSec: Double
    public var highlightClicks: Bool
    public var highlightColorHex: String
    public var highlightRadius: Double
    
    public init(
        mediaMode: MediaMode = .hybrid,
        gifFps: Int = 15,
        clipDurationPreClickSec: Double = 0.5,
        clipDurationPostClickSec: Double = 1.5,
        highlightClicks: Bool = true,
        highlightColorHex: String = "#EF4444",
        highlightRadius: Double = 28.0
    ) {
        self.mediaMode = mediaMode
        self.gifFps = gifFps
        self.clipDurationPreClickSec = clipDurationPreClickSec
        self.clipDurationPostClickSec = clipDurationPostClickSec
        self.highlightClicks = highlightClicks
        self.highlightColorHex = highlightColorHex
        self.highlightRadius = highlightRadius
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

public struct StepItSettings: Codable, Sendable, Equatable {
    public var capture: CaptureSettings
    public var publishing: PublishingSettings
    public var gateway: GatewaySettings
    public var hotkeys: HotkeySettings
    
    public init(
        capture: CaptureSettings = CaptureSettings(),
        publishing: PublishingSettings = PublishingSettings(),
        gateway: GatewaySettings = GatewaySettings(),
        hotkeys: HotkeySettings = HotkeySettings()
    ) {
        self.capture = capture
        self.publishing = publishing
        self.gateway = gateway
        self.hotkeys = hotkeys
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
