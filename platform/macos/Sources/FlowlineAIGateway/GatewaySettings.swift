import Foundation

/// AI gateway configuration (R/M1-07: moved from FlowlineCore).
/// Owned by the AI gateway target; consumed by `AIGatewayClient` and the
/// multimodal payload builder.
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

    /// Local providers run on this Mac — no API key needed.
    public var isLocal: Bool {
        provider == .ollama || provider == .lmStudio || provider == .cli
    }

    /// Cloud providers require an API key before synthesis can run.
    public var needsAPIKey: Bool {
        provider == .openRouter || provider == .customOpenAI
    }

    /// Whether the AI panel is allowed to send: cloud needs a non-empty
    /// key, local providers (`ollama` / `lmStudio` / `cli`) need no key.
    /// Drives the sidebar `canRun` gate and setup card.
    public var canRun: Bool {
        !needsAPIKey
            || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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
