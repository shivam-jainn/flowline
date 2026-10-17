import Foundation
import StepItIR
import StepItPipeline
import StepItCaptureAPI
import StepItAIGateway
import StepItPublishing

/// Full application settings aggregate (R/M1-07: moved from StepItCore).
///
/// Lives in the engine target — the lowest module every consumer (surfaces,
/// engine, tests) can already import — so the graph stays acyclic:
/// `StepItEngine → {StepItCaptureAPI, StepItAIGateway, StepItPublishing}`,
/// none of which depend back on the engine. (Placing the aggregate in the
/// app target would make it invisible to `StepItTests`, which cannot import
/// the executable target.)
///
/// Persistence is owned by the composition layer (`SettingsFileStore` in the
/// app target); the engine only ever consumes the narrow `EngineSettings`
/// projection (see `EngineSettings.swift`).
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
